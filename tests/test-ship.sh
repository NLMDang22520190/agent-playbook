#!/usr/bin/env bash
# Tests for tools/ship.sh (v0.11.0 AC6.1): one command from an open PR to an installed release.
#   tools/ship.sh PR vX.Y.Z [--yes]
# Everything is stubbed: a fake `gh` first on PATH, stub tools/release.sh and install.sh inside a throw-away
# git repo (bare origin + clone). The stubs append one line per call to $FAKE_LOG, so the order of the steps
# and the arguments are asserted from that log. The fake `gh pr merge` simulates the merge by pushing a commit
# (merged-N.txt) to origin's main, so `git switch main && git pull --ff-only` has something to pull.
# Prompts are answered through a pseudo-terminal (python3 pty); where none is available those assertions are
# skipped with an exact count.
. "$(dirname "$0")/lib.sh"
# no CRLF warnings from git on Windows: the output is compared byte for byte
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.autocrlf GIT_CONFIG_VALUE_0=false
SHIP="$PB_ROOT/tools/ship.sh"
GITID() { git -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }

W="$(mk_tmp)"
BIN="$W/bin"; mkdir -p "$BIN"

# ---- fake gh ----
cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
# fake gh. Env: FAKE_LOG, FAKE_GH_STATE, FAKE_GH_MERGE_STATE, FAKE_GH_FAIL (words: prview merge runlist runwatch relview),
# FAKE_ORIGIN_WORK (clone of origin used to simulate the merge)
echo "gh $*" >> "$FAKE_LOG"
fails=" ${FAKE_GH_FAIL:-} "
failing() { case "$fails" in *" $1 "*) echo "gh: simulated $1 failure" >&2; return 0 ;; esac; return 1; }
fields=""; expr=""; prev=""
for a in "$@"; do
  case "$prev" in --json) fields="$a" ;; --jq|-q) expr="$a" ;; esac
  prev="$a"
done
val() { # field -> value for the PR (kind=pr) or the run (kind=run)
  case "$1" in
    state) echo "${FAKE_GH_STATE:-OPEN}" ;;
    mergeStateStatus) echo "${FAKE_GH_MERGE_STATE:-CLEAN}" ;;
    number) echo "${FAKE_PR:-12}" ;;
    title) echo "fake pull request" ;;
    url) echo "https://example.invalid/pull/12" ;;
    headRefName) echo "feat/x" ;;
    baseRefName) echo "main" ;;
    mergeable) echo "MERGEABLE" ;;
    databaseId) echo "4242" ;;
    status) echo "in_progress" ;;
    conclusion) echo "" ;;
    workflowName|name) echo "CI-fake" ;;
    displayTitle) echo "fake run" ;;
    headBranch) echo "${FAKE_TAG:-v1.2.3}" ;;
    event) echo "push" ;;
    *) echo "" ;;
  esac
}
json_obj() {
  local out="" f v sep=""
  for f in $(printf '%s\n' "$fields" | tr ',' '\n' | sort); do
    v="$(val "$f")"
    case "$f" in
      number|databaseId) out="$out$sep\"$f\":$v" ;;
      url) out="$out$sep\"$f\":\"${v}\"" ;;
      *) out="$out$sep\"$f\":\"$v\"" ;;
    esac
    sep=","
  done
  printf '{%s}' "$out"
}
emit() { # $1 = JSON text; apply --jq/-q when given
  if [ -n "$expr" ]; then
    if command -v jq >/dev/null 2>&1; then printf '%s\n' "$1" | jq -r "$expr"; return; fi
    # no jq: print the value of every .field named in the expression, one per line
    for t in $(printf '%s' "$expr" | grep -oE '\.[A-Za-z_]+' | tr -d .); do val "$t"; done
    return
  fi
  printf '%s\n' "$1"
}
case "$1 $2" in
  "pr view")
    failing prview && exit 1
    if [ -n "$fields" ]; then emit "$(json_obj)"; else printf 'title:\tfake\nstate:\t%s\n' "${FAKE_GH_STATE:-OPEN}"; fi ;;
  "pr merge")
    failing merge && exit 1
    ( cd "$FAKE_ORIGIN_WORK" &&
      git pull -q --ff-only origin main >/dev/null 2>&1
      echo merged > "merged-${3}.txt" && git add -A &&
      git -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false commit -qm "merge PR $3" &&
      git push -q origin HEAD:main >/dev/null 2>&1 ) || exit 1
    echo "merged pull request #$3" ;;
  "run list")
    failing runlist && exit 1
    case "${FAKE_RUN_LIST:-}" in
      empty) emit "[]"; exit 0 ;;
      null) echo null; exit 0 ;;
    esac
    if [ -n "$fields" ]; then emit "[$(json_obj)]"; else printf 'in_progress\t\tfake run\tCI-fake\t%s\tpush\t4242\t5s\n' "${FAKE_TAG:-v1.2.3}"; fi ;;
  "run watch")
    failing runwatch && { echo "Run CI-fake (4242) failed" >&2; exit 1; }
    echo "Run CI-fake (4242) completed with 'success'" ;;
  "release view")
    failing relview && { echo "release not found" >&2; exit 1; }
    echo "title: fake release" ;;
esac
exit 0
EOF

# ---- stub release.sh / install.sh (committed in every fixture repo) ----
cat > "$W/release.stub" <<'EOF'
#!/usr/bin/env bash
cd "$(dirname "$0")/.." || exit 3
m=no; ls merged-*.txt >/dev/null 2>&1 && m=yes
echo "release.sh $* | branch=$(git rev-parse --abbrev-ref HEAD) merged=$m" >> "$FAKE_LOG"
case " $* " in
  *" --dry-run "*) exit "${FAKE_REL_DRY_RC:-0}" ;;
  *) rc="${FAKE_REL_REAL_RC:-0}"; [ "$rc" = 0 ] && git tag "$1" 2>/dev/null; exit "$rc" ;;
esac
EOF
cat > "$W/install.stub" <<'EOF'
#!/usr/bin/env bash
echo "install.sh $*" >> "$FAKE_LOG"
exit "${FAKE_INSTALL_RC:-0}"
EOF
# ---- pseudo-terminal driver: answers each "[y/N]" prompt with the next argument before "--" ----
cat > "$W/ptyrun.py" <<'EOF'
import os, pty, re, select, signal, sys, time
args = sys.argv[1:]
i = args.index("--")
answers, cmd = args[:i], args[i + 1:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(cmd[0], cmd)
out = b""
seen = 0
deadline = time.time() + 90
while True:
    r, _, _ = select.select([fd], [], [], 1)
    if r:
        try:
            d = os.read(fd, 4096)
        except OSError:
            break
        if not d:
            break
        out += d
        n = len(re.findall(rb"\[y/n\]", out, re.I))
        while seen < n:
            a = answers[seen] if seen < len(answers) else ""
            os.write(fd, a.encode() + b"\n")
            seen += 1
    if time.time() > deadline:
        os.kill(pid, signal.SIGKILL)
        break
_, st = os.waitpid(pid, 0)
sys.stdout.buffer.write(out.replace(b"\r\n", b"\n"))
sys.stdout.flush()
sys.exit(os.WEXITSTATUS(st) if os.WIFEXITED(st) else 128 + os.WTERMSIG(st))
EOF
chmod +x "$BIN/gh" "$W/release.stub" "$W/install.stub"

# fx -> fresh fixture: $F/origin.git, $F/repo (on branch feat/x, main pushed), $F/work (clone used by the fake merge)
FXN=0
fx() {
  FXN=$((FXN + 1)); F="$W/fx$FXN"; mkdir -p "$F"
  git init -q --bare "$F/origin.git" 2>/dev/null
  git -C "$F/origin.git" symbolic-ref HEAD refs/heads/main
  git clone -q "$F/origin.git" "$F/repo" 2>/dev/null
  mkdir -p "$F/repo/tools"
  [ -f "$SHIP" ] && cp -p "$SHIP" "$F/repo/tools/ship.sh"
  cp -p "$W/release.stub" "$F/repo/tools/release.sh"
  cp -p "$W/install.stub" "$F/repo/install.sh"
  printf '1.2.3\n' > "$F/repo/VERSION"
  ( cd "$F/repo" && git symbolic-ref HEAD refs/heads/main && git add -A &&
    GITID commit -qm init && git push -q -u origin main 2>/dev/null &&
    git switch -q -c feat/x ) || { echo "fixture setup failed"; exit 3; }
  git clone -q "$F/origin.git" "$F/work" 2>/dev/null
  : > "$F/log"
  export FAKE_LOG="$F/log" FAKE_ORIGIN_WORK="$F/work" FAKE_GH_STATE=OPEN FAKE_GH_MERGE_STATE=CLEAN FAKE_GH_FAIL=""
  export FAKE_REL_DRY_RC=0 FAKE_REL_REAL_RC=0 FAKE_INSTALL_RC=0 FAKE_PR=12 FAKE_TAG=v1.2.3
  export PATH="$BIN:$ORIG_PATH"
}
ORIG_PATH="$PATH"
# sh_run ARGS... -> run tools/ship.sh in the fixture repo with a closed stdin (non-interactive)
sh_run() { run_in "$F/repo" bash tools/ship.sh "$@" </dev/null; }
# steps -> compact sequence of what was called, from the log (consecutive repeats collapsed)
steps() {
  awk '
    /^gh pr view/ { print "view"; next }
    /^gh pr merge/ { print "merge"; next }
    /^release.sh .*--dry-run/ { print "dry"; next }
    /^release.sh/ { print "release"; next }
    /^gh run list/ { print "runlist"; next }
    /^gh run watch/ { print "runwatch"; next }
    /^gh release view/ { print "relview"; next }
    /^install.sh/ { print "install"; next }
  ' "$FAKE_LOG" | uniq | tr '\n' ' ' | sed 's/ $//'
}
logged() { grep -c -- "$1" "$FAKE_LOG" 2>/dev/null || true; }
FULL="view merge dry release runlist runwatch relview install"

echo "AC6.1 the script exists"
assert_file "AC6.1 tools/ship.sh exists" "$SHIP"

echo "AC6.1 --yes: the whole flow, in order"
fx
sh_run 12 v1.2.3 --yes
assert_rc "AC6.1 --yes full flow exits 0" 0
assert_eq "AC6.1 order: view, merge, release dry run, release, CI list, CI watch, release view, install" "$FULL" "$(steps)"
assert_contains "AC6.1 pr view is asked about PR 12" "$(grep '^gh pr view' "$FAKE_LOG" | head -n 1)" "12"
L="$(grep '^gh pr merge' "$FAKE_LOG")"
assert_contains "AC6.1 merges PR 12" "$L" "pr merge 12"
assert_contains "AC6.1 merge uses --merge" "$L" "--merge"
assert_contains "AC6.1 merge deletes the branch" "$L" "--delete-branch"
assert_eq "AC6.1 dry run is exactly 'release.sh v1.2.3 --dry-run', on main with the merge pulled" \
  "release.sh v1.2.3 --dry-run | branch=main merged=yes" "$(grep '^release.sh .*--dry-run' "$FAKE_LOG")"
assert_eq "AC6.1 real release is exactly 'release.sh v1.2.3', on main with the merge pulled" \
  "release.sh v1.2.3 | branch=main merged=yes" "$(grep '^release.sh' "$FAKE_LOG" | grep -v -- '--dry-run')"
assert_contains "AC6.1 CI run is looked up by the tag" "$(grep '^gh run list' "$FAKE_LOG" | head -n 1)" "--branch v1.2.3"
assert_contains "AC6.1 CI run is watched with --exit-status" "$(grep '^gh run watch' "$FAKE_LOG")" "--exit-status"
assert_contains "AC6.1 release view is for the tag" "$(grep '^gh release view' "$FAKE_LOG")" "v1.2.3"
assert_eq "AC6.1 install is exactly './install.sh update --yes'" "install.sh update --yes" "$(grep '^install.sh' "$FAKE_LOG")"
assert_eq "AC6.1 the local checkout ends on main" "main" "$(cd "$F/repo" && git rev-parse --abbrev-ref HEAD)"
assert_eq "AC6.1 the local main was fast-forwarded to origin's main" "$(git -C "$F/origin.git" rev-parse main)" "$(cd "$F/repo" && git rev-parse HEAD)"
NSTEP="$(printf '%s\n' "$OUT" | grep -c '^== ')"
if [ "$NSTEP" -ge 6 ]; then t_ok "AC6.1 prints a '== ' line per step ($NSTEP lines)"; else t_bad "AC6.1 prints a '== ' line per step" "only $NSTEP lines starting with '== ' in: $OUT"; fi
assert_not_contains "AC6.1 --yes asks nothing" "$OUT" "[y/N]"

echo "AC6.1 another PR number and tag are passed through"
fx
export FAKE_PR=345 FAKE_TAG=v10.20.30
sh_run 345 v10.20.30 --yes
assert_rc "AC6.1 PR 345 / v10.20.30 exits 0" 0
assert_contains "AC6.1 merges PR 345" "$(grep '^gh pr merge' "$FAKE_LOG")" "pr merge 345"
assert_eq "AC6.1 releases v10.20.30" "release.sh v10.20.30 | branch=main merged=yes" "$(grep '^release.sh' "$FAKE_LOG" | grep -v -- '--dry-run')"
assert_contains "AC6.1 looks up the CI run of v10.20.30" "$(grep '^gh run list' "$FAKE_LOG" | head -n 1)" "--branch v10.20.30"

echo "AC6.1 refusal: the PR must be OPEN and CLEAN (nothing merged)"
for combo in "MERGED CLEAN" "CLOSED CLEAN" "OPEN BLOCKED" "OPEN BEHIND" "OPEN DIRTY" "OPEN UNSTABLE" "OPEN UNKNOWN" "OPEN DRAFT" "OPEN HAS_HOOKS"; do
  fx
  export FAKE_GH_STATE="${combo% *}" FAKE_GH_MERGE_STATE="${combo#* }"
  sh_run 12 v1.2.3 --yes
  assert_rc "AC6.1 state/merge-state $combo with --yes: exit 1" 1
  assert_eq "AC6.1 $combo: nothing merged, nothing released" "view" "$(steps)"
done
fx
export FAKE_GH_FAIL="prview"
sh_run 12 v1.2.3 --yes
if [ "$RC" -ne 0 ]; then t_ok "AC6.1 gh pr view failing: non-zero exit"; else t_bad "AC6.1 gh pr view failing: non-zero exit" "exit $RC; output: $OUT"; fi
assert_eq "AC6.1 gh pr view failing: nothing merged" "view" "$(steps)"

echo "AC6.1 non-interactive stdin without --yes refuses at the first question"
fx
sh_run 12 v1.2.3
assert_rc "AC6.1 closed stdin, no --yes: exit 1" 1
assert_eq "AC6.1 closed stdin, no --yes: nothing merged" "view" "$(steps)"
assert_eq "AC6.1 closed stdin: origin main is untouched" "0" "$(git -C "$F/origin.git" ls-tree -r --name-only main | grep -c '^merged-')"
fx
OUT="$(cd "$F/repo" && printf 'y\ny\n' | bash tools/ship.sh 12 v1.2.3 2>&1)"; RC=$?
assert_rc "AC6.1 piped 'y' answers without a terminal are not accepted: exit 1" 1
assert_eq "AC6.1 piped answers: nothing merged" "view" "$(steps)"

echo "AC6.1 a failing release.sh stops ship.sh with its status"
fx
export FAKE_REL_DRY_RC=7
sh_run 12 v1.2.3 --yes
assert_rc "AC6.1 dry run failing with 7: ship.sh exits 7" 7
assert_eq "AC6.1 failing dry run: the real release is not run, nor anything after" "view merge dry" "$(steps)"
fx
export FAKE_REL_REAL_RC=5
sh_run 12 v1.2.3 --yes
assert_rc "AC6.1 real release failing with 5: ship.sh exits 5" 5
assert_eq "AC6.1 failing release: no CI wait, no release view, no install" "view merge dry release" "$(steps)"

echo "AC6.1 CI and release checks"
fx
export FAKE_GH_FAIL="runwatch"
sh_run 12 v1.2.3 --yes
assert_rc "AC6.1 failed CI run: exit 1" 1
assert_contains "AC6.1 failed CI run: the message names the run" "$OUT" "4242"
assert_eq "AC6.1 failed CI run: no release view, no install" "view merge dry release runlist runwatch" "$(steps)"
fx
export FAKE_GH_FAIL="relview"
sh_run 12 v1.2.3 --yes
if [ "$RC" -ne 0 ]; then t_ok "AC6.1 missing GitHub release: non-zero exit"; else t_bad "AC6.1 missing GitHub release: non-zero exit" "exit $RC; output: $OUT"; fi
assert_contains "AC6.1 missing release: the message names the tag" "$OUT" "v1.2.3"
assert_eq "AC6.1 missing release: install is not run" "view merge dry release runlist runwatch relview" "$(steps)"
fx
export FAKE_GH_FAIL="merge"
sh_run 12 v1.2.3 --yes
if [ "$RC" -ne 0 ]; then t_ok "AC6.1 gh pr merge failing: non-zero exit"; else t_bad "AC6.1 gh pr merge failing: non-zero exit" "exit $RC; output: $OUT"; fi
assert_eq "AC6.1 gh pr merge failing: release.sh is not run" "view merge" "$(steps)"

echo "review round 1: the CI run is looked up by tag, tag commit and event"
fx
sh_run 12 v1.2.3 --yes
assert_rc "R1 full flow still exits 0 (the stub release.sh tags locally)" 0
RL="$(grep '^gh run list' "$FAKE_LOG" | head -n 1)"
TAGSHA="$(cd "$F/repo" && git rev-parse 'v1.2.3^{commit}' 2>/dev/null)"
assert_eq "R1 fixture: the tag points at the merged main" "$(cd "$F/repo" && git rev-parse HEAD)" "$TAGSHA"
assert_contains "R1 run list has --branch v1.2.3" "$RL" "--branch v1.2.3"
assert_contains "R1 run list has --commit <sha of the tag>" "$RL" "--commit $TAGSHA"
assert_contains "R1 run list has --event push" "$RL" "--event push"

echo "review round 1: no CI run found (empty list, null, gh failure)"
export PB_SHIP_WAIT_TRIES=2 PB_SHIP_WAIT_SECS=0
for mode in empty null; do
  fx
  export FAKE_RUN_LIST="$mode"
  sh_run 12 v1.2.3 --yes
  assert_rc "R1 run list $mode: exit 1" 1
  assert_contains "R1 run list $mode: says no CI run found" "$OUT" "no CI run found"
  assert_contains "R1 run list $mode: names the tag" "$OUT" "v1.2.3"
  assert_eq "R1 run list $mode: never calls run watch, release view or install" "view merge dry release runlist" "$(steps)"
  assert_eq "R1 run list $mode: no 'run watch' call at all" "0" "$(logged '^gh run watch')"
  if [ "$(logged '^gh run list')" -ge 2 ]; then t_ok "R1 run list $mode: retried (PB_SHIP_WAIT_TRIES=2)"; else t_bad "R1 run list $mode: retried (PB_SHIP_WAIT_TRIES=2)" "run list calls: $(logged '^gh run list')"; fi
done
unset FAKE_RUN_LIST
fx
export FAKE_GH_FAIL="runlist"
sh_run 12 v1.2.3 --yes
assert_rc "R1 gh run list failing: exit 1" 1
assert_contains "R1 gh run list failing: the gh error is shown, not hidden" "$OUT" "simulated runlist failure"
assert_contains "R1 gh run list failing: same refusal, no CI run found" "$OUT" "no CI run found"
assert_eq "R1 gh run list failing: no watch, no release view, no install" "view merge dry release runlist" "$(steps)"
unset PB_SHIP_WAIT_TRIES PB_SHIP_WAIT_SECS

echo "review round 1: a dirty work tree is refused before anything changes"
fx
printf 'edit
' >> "$F/repo/VERSION"
sh_run 12 v1.2.3 --yes
assert_rc "R1 modified tracked file: exit 1" 1
assert_contains "R1 modified tracked file: says the tree is not clean" "$OUT" "not clean"
assert_eq "R1 modified tracked file: no gh pr merge, no release" "0" "$(logged '^gh pr merge')"
assert_eq "R1 modified tracked file: nothing after the check" "" "$(steps | sed 's/^view$//')"
fx
printf 'x
' > "$F/repo/untracked-file.txt"
sh_run 12 v1.2.3 --yes
assert_rc "R1 untracked file: exit 1" 1
assert_contains "R1 untracked file: says the tree is not clean" "$OUT" "not clean"
assert_eq "R1 untracked file: no gh pr merge" "0" "$(logged '^gh pr merge')"
assert_eq "R1 untracked file: no release.sh or install.sh call" "0" "$(logged '^release.sh\|^install.sh')"

echo "AC6.1 usage errors exit 2 and touch nothing"
fx
usage_case() { local name="$1"; shift; sh_run "$@"; assert_rc "AC6.1 usage: $name" 2; }
usage_case "no arguments"
usage_case "PR without a tag" 12
usage_case "PR is not a number (abc)" abc v1.2.3
usage_case "PR is not a number (12x)" 12x v1.2.3
usage_case "PR is negative" -5 v1.2.3
usage_case "tag without the v (1.2.3)" 12 1.2.3
usage_case "tag with two parts (v1.2)" 12 v1.2
usage_case "tag with a suffix (v1.2.3-rc1)" 12 v1.2.3-rc1
usage_case "unknown option (--force)" 12 v1.2.3 --force
usage_case "unknown option before the arguments (--bogus)" --bogus 12 v1.2.3
assert_eq "AC6.1 usage errors: gh, release.sh and install.sh were never called" "" "$(steps)"
assert_eq "AC6.1 usage errors: the log is empty" "0" "$(wc -l < "$FAKE_LOG" | tr -d ' ')"

# ---- prompts, through a pseudo-terminal ----
PTY_OK=0
if [ -z "${PB_NO_PTY:-}" ] && command -v python3 >/dev/null 2>&1; then
  OUT="$(python3 "$W/ptyrun.py" -- bash -c '[ -t 0 ] && echo isatty' 2>/dev/null)"
  case "$OUT" in *isatty*) PTY_OK=1 ;; esac
fi
# pty_ship ANSWERS... -- ship args... : answers the "[y/N]" prompts in order
pty_ship() {
  local ans=() a
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do ans+=("$1"); shift; done
  shift
  OUT="$(cd "$F/repo" && python3 "$W/ptyrun.py" "${ans[@]}" -- bash tools/ship.sh "$@" 2>&1)"; RC=$?
}
pty_block() {
  echo "AC6.1 prompts answered on a terminal"
  fx
  pty_ship y y -- 12 v1.2.3
  assert_rc "AC6.1 answers y, y: exit 0" 0
  assert_eq "AC6.1 answers y, y: the full flow ran in order" "$FULL" "$(steps)"
  assert_contains "AC6.1 the first question is 'merge PR #12?'" "$OUT" "merge PR #12? [y/N]"
  assert_contains "AC6.1 the second question is 'tag and push v1.2.3?'" "$OUT" "tag and push v1.2.3? [y/N]"
  fx
  pty_ship yes yes -- 12 v1.2.3
  assert_rc "AC6.1 answers yes, yes: exit 0" 0
  assert_eq "AC6.1 answers yes, yes: the full flow ran" "$FULL" "$(steps)"
  for ans in n "" no maybe N; do
    fx
    pty_ship "$ans" -- 12 v1.2.3
    assert_rc "AC6.1 first answer [$ans]: exit 1" 1
    assert_eq "AC6.1 first answer [$ans]: only the PR check ran, nothing merged" "view" "$(steps)"
    assert_eq "AC6.1 first answer [$ans]: origin main is untouched" "0" "$(git -C "$F/origin.git" ls-tree -r --name-only main | grep -c '^merged-')"
  done
  fx
  pty_ship y n -- 12 v1.2.3
  assert_rc "AC6.1 second answer n: exit 1" 1
  assert_eq "AC6.1 second answer n: merged and dry-ran, but did not tag" "view merge dry" "$(steps)"
  fx
  pty_ship y "" -- 12 v1.2.3
  assert_rc "AC6.1 second answer empty: exit 1" 1
  assert_eq "AC6.1 second answer empty: did not tag" "view merge dry" "$(steps)"
  fx
  pty_ship -- 12 v1.2.3 --yes
  assert_rc "AC6.1 --yes on a terminal: exit 0 without any answer" 0
  assert_not_contains "AC6.1 --yes on a terminal: no question is printed" "$OUT" "[y/N]"
  fx
  export FAKE_GH_STATE=MERGED
  pty_ship y y -- 12 v1.2.3
  assert_rc "AC6.1 a merged PR is refused before any question" 1
  assert_not_contains "AC6.1 refusal comes before the first question" "$OUT" "[y/N]"
}
PTY_N=29
if [ "$PTY_OK" = 1 ]; then pty_block; else t_skip "$PTY_N" "AC6.1 prompt assertions need python3 with a pty (not available here)"; fi

t_summary
