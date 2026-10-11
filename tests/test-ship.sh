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
SHIPDIR="$PB_ROOT/tools"
GITID() { git -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }

W="$(mk_tmp)"
BIN="$W/bin"; mkdir -p "$BIN"

# ---- fake gh ----
cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
# fake gh. Env: FAKE_LOG, FAKE_GH_STATE, FAKE_GH_MERGE_STATE, FAKE_GH_MERGE_COMMIT (sha of the PR's merge commit, empty = none),
# FAKE_GH_FAIL (words: prview merge runlist runwatch relview shardlist shardview shardlog),
# FAKE_SHARD_LOG (none = the job log has no suite timings),
# FAKE_ORIGIN_WORK (clone of origin used to simulate the merge),
# FAKE_SHARD_LIST (empty|null: the main push run lookup finds nothing), FAKE_MAIN_RUN (its id, default 7777),
# FAKE_SHARDS (comma list of "windows shard" job seconds, "running" = no finish time, "none" = no jobs, "bad" = not JSON).
echo "gh $*" >> "$FAKE_LOG"
fails=" ${FAKE_GH_FAIL:-} "
failing() { case "$fails" in *" $1 "*) echo "gh: simulated $1 failure" >&2; return 0 ;; esac; return 1; }
fields=""; expr=""; prev=""; branch=""
for a in "$@"; do
  case "$prev" in --json) fields="$a" ;; --jq|-q) expr="$a" ;; --branch) branch="$a" ;; esac
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
    databaseId) echo "${RUNID:-4242}" ;;
    oid) echo "${FAKE_GH_MERGE_COMMIT:-}" ;;   # no jq: the value of .mergeCommit.oid
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
      mergeCommit)   # gh prints the merge commit as an object {"oid": "..."}; null while the PR is not merged
        if [ -n "${FAKE_GH_MERGE_COMMIT:-}" ]; then out="$out$sep\"$f\":{\"oid\":\"$FAKE_GH_MERGE_COMMIT\"}"; else out="$out$sep\"$f\":null"; fi ;;
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
    # where the clone is when GitHub merges (a detached HEAD makes the real gh fail locally after the merge)
    echo "merge-at $(git rev-parse --abbrev-ref HEAD 2>&1)" >> "$FAKE_LOG"
    # --auto: GitHub only arms the merge for later (when the checks pass); nothing reaches origin's main now
    case " $* " in *" --auto "*) echo "Pull request #$3 will be automatically merged when all requirements are met"; exit 0 ;; esac
    ( cd "$FAKE_ORIGIN_WORK" &&
      git pull -q --ff-only origin main >/dev/null 2>&1
      case "${FAKE_REWRITE_SHIP:-}" in
        exit99) printf 'exit 99\n' > tools/ship.sh ;;
        trunc)  head -c 300 tools/ship.sh > tools/ship.tmp && mv tools/ship.tmp tools/ship.sh ;;
        grow)   { cat tools/ship.sh; printf '\necho "ship.sh from the merge commit"; exit 98\n'; } > tools/ship.tmp && mv tools/ship.tmp tools/ship.sh ;;
      esac
      echo merged > "merged-${3}.txt" && git add -A &&
      git -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false commit -qm "merge PR $3" &&
      git push -q origin HEAD:main >/dev/null 2>&1 ) || exit 1
    echo "merged pull request #$3" ;;
  "run list")
    if [ "$branch" = main ]; then   # the lookup of the push-to-main run (shard report), not of the tag's run
      failing shardlist && exit 1
      case "${FAKE_SHARD_LIST:-}" in
        empty) emit "[]"; exit 0 ;;
        null) echo null; exit 0 ;;
      esac
      RUNID="${FAKE_MAIN_RUN:-7777}"
    else
      failing runlist && exit 1
      case "${FAKE_RUN_LIST:-}" in
        empty) emit "[]"; exit 0 ;;
        null) echo null; exit 0 ;;
      esac
    fi
    if [ -n "$fields" ]; then emit "[$(json_obj)]"; else printf 'in_progress\t\tfake run\tCI-fake\t%s\tpush\t4242\t5s\n' "${FAKE_TAG:-v1.2.3}"; fi ;;
  "run watch")
    failing runwatch && { echo "Run CI-fake (4242) failed" >&2; exit 1; }
    echo "Run CI-fake (4242) completed with 'success'" ;;
  "run view")   # gh run view RUN --json jobs (--jq is ignored: the JSON comes back whole)
    case " $* " in *" --job "*)   # gh run view --job ID --log: what tools/shard-weights.sh reads (v0.22.2 AC3)
      failing shardlog && exit 1
      case "${FAKE_SHARD_LOG:-}" in none) exit 0 ;; esac
      printf '2026-10-11T10:00:00.0000000Z == tests/test-big.sh (120 s)\r\n2026-10-11T10:02:00.0000000Z == tests/test-small.sh (7 s)\r\n'
      exit 0 ;;
    esac
    failing shardview && exit 1
    case "${FAKE_SHARDS:-}" in
      bad) echo "this is not json"; exit 0 ;;
    esac
    iso() { local s=$((36000 + $1)); printf '2026-10-11T%02d:%02d:%02dZ' $((s / 3600)) $((s % 3600 / 60)) $((s % 60)); }
    job() { printf '{"databaseId":%s,"name":"%s","status":"%s","conclusion":"success","startedAt":"%s","completedAt":"%s"}' "$1" "$2" "$3" "$4" "$5"; }
    jobs=""; sep=""; i=0
    if [ "${FAKE_SHARDS:-}" != none ]; then
      # other jobs of the same run: they are not shards and must not count
      jobs="$(job 9001 'test (ubuntu-latest)' completed "$(iso 0)" "$(iso 900)"),$(job 9002 'test (macos-latest)' completed "$(iso 0)" "$(iso 30)"),$(job 9003 'test (windows-latest)' completed "$(iso 0)" "$(iso 5)")"
      sep=","
      for d in $(printf '%s' "${FAKE_SHARDS:-}" | tr ',' ' '); do
        i=$((i + 1))
        case "$d" in
          running) jobs="$jobs$sep$(job $((9100 + i)) "windows shard $i/3" in_progress "$(iso 0)" '0001-01-01T00:00:00Z')" ;;
          *) jobs="$jobs$sep$(job $((9100 + i)) "windows shard $i/3" completed "$(iso 0)" "$(iso "$d")")" ;;
        esac
        sep=","
      done
    fi
    printf '{"jobs":[%s]}\n' "$jobs" ;;
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
# the real install.sh update checks out the release tag: the dev clone is left on a detached HEAD
[ -n "${FAKE_INSTALL_DETACH:-}" ] && git -C "$(dirname "$0")" checkout -q --detach
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

# ---- fake git front: real git, plus a faithful "git pull rewrites the running script in place" ----
# git normally replaces a file by unlinking it and creating a new one, so a bash that already has the old
# tools/ship.sh open keeps reading the old inode and never notices the pull. Other tools (and Windows/macOS
# checkouts, editors, rsync) rewrite the SAME inode. This front end reproduces that: before a "git pull" in the
# fixture repo it hard-links tools/ship.sh, and after the pull it writes the pulled content into that old inode.
# A ship.sh that is read line by line while it runs then sees the new content at its old offset.
REAL_GIT="$(command -v git)"
cat > "$BIN/git" <<EOF
#!/usr/bin/env bash
REAL="$REAL_GIT"
if [ -n "\${FAKE_INPLACE:-}" ] && [ -n "\${FAKE_SHIP_REPO:-}" ] && [ -f tools/ship.sh ] && [ tools/ship.sh -ef "\$FAKE_SHIP_REPO/tools/ship.sh" ]; then
  case " \$* " in
    *" pull "*)
      keep="\$FAKE_SHIP_REPO/../ship.keep"; rm -f "\$keep"
      ln tools/ship.sh "\$keep" 2>/dev/null
      "\$REAL" "\$@"; rc=\$?
      if [ -f "\$keep" ] && ! [ tools/ship.sh -ef "\$keep" ]; then cat tools/ship.sh > "\$keep" 2>/dev/null; fi
      exit \$rc ;;
  esac
fi
exec "\$REAL" "\$@"
EOF
chmod +x "$BIN/git"

# fx -> fresh fixture: $F/origin.git, $F/repo (on branch feat/x, main pushed), $F/work (clone used by the fake merge)
# The first call builds the fixture with git (init, clone, commit, push); every later call copies that
# template with cp -a and only re-points the two clones at the copied origin.
FXN=0; FXTPL=""
fx_build() { # DIR -> the fixture in DIR
  local F="$1"; mkdir -p "$F"
  git init -q --bare "$F/origin.git" 2>/dev/null
  git -C "$F/origin.git" symbolic-ref HEAD refs/heads/main
  git clone -q "$F/origin.git" "$F/repo" 2>/dev/null
  mkdir -p "$F/repo/tools"
  [ -f "$SHIP" ] && cp -p "$SHIP" "$F/repo/tools/ship.sh"
  [ -f "$SHIPDIR/shard-weights.sh" ] && cp -p "$SHIPDIR/shard-weights.sh" "$F/repo/tools/shard-weights.sh"
  mkdir -p "$F/repo/tests"
  printf '# old weights, run 1\ntest-big.sh 50\n' > "$F/repo/tests/shard-weights"
  cp -p "$W/release.stub" "$F/repo/tools/release.sh"
  cp -p "$W/install.stub" "$F/repo/install.sh"
  printf '1.2.3\n' > "$F/repo/VERSION"
  ( cd "$F/repo" && git symbolic-ref HEAD refs/heads/main && git add -A &&
    GITID commit -qm init && git push -q -u origin main 2>/dev/null &&
    git switch -q -c feat/x ) || { echo "fixture setup failed"; exit 3; }
  git clone -q "$F/origin.git" "$F/work" 2>/dev/null
}
fx() {
  FXN=$((FXN + 1)); F="$W/fx$FXN"
  if [ -z "$FXTPL" ]; then
    FXTPL="$W/fxtpl"; fx_build "$FXTPL"
  fi
  mkdir -p "$F"
  cp -a "$FXTPL/." "$F/"
  git -C "$F/repo" remote set-url origin "$F/origin.git"
  git -C "$F/work" remote set-url origin "$F/origin.git"
  : > "$F/log"
  export FAKE_LOG="$F/log" FAKE_ORIGIN_WORK="$F/work" FAKE_GH_STATE=OPEN FAKE_GH_MERGE_STATE=CLEAN FAKE_GH_FAIL=""
  export FAKE_REL_DRY_RC=0 FAKE_REL_REAL_RC=0 FAKE_INSTALL_RC=0 FAKE_PR=12 FAKE_TAG=v1.2.3 FAKE_GH_MERGE_COMMIT= FAKE_SHARD_LIST= FAKE_MAIN_RUN=7777 FAKE_SHARDS= FAKE_SHARD_LOG=
  export FAKE_REWRITE_SHIP="" FAKE_INPLACE=1 FAKE_SHIP_REPO="$F/repo"
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
    /^gh run list .*--branch main / { next }   # the shard report (v0.17.0 AC4.1) is not a step; see shard_calls
    /^gh run list/ { print "runlist"; next }
    /^gh run watch/ { print "runwatch"; next }
    /^gh release view/ { print "relview"; next }
    /^install.sh/ { print "install"; next }
  ' "$FAKE_LOG" | uniq | tr '\n' ' ' | sed 's/ $//'
}
logged() { grep -c -- "$1" "$FAKE_LOG" 2>/dev/null || true; }
FULL="view merge dry release runlist runwatch relview install"          # with the questions: the dry run is kept
FULL_YES="view merge release runlist runwatch relview install"          # --yes: the dry run is skipped (v0.14.0 AC2.1)
MERGED_YES="view release runlist runwatch relview install"              # PR already merged (v0.17.0 AC2.2), --yes: no merge call
MERGED_Q="view dry release runlist runwatch relview install"            # PR already merged, with the questions: the dry run stays

echo "AC6.1 the script exists"
assert_file "AC6.1 tools/ship.sh exists" "$SHIP"

echo "AC6.1 --yes: the whole flow, in order"
fx
sh_run 12 v1.2.3 --yes
assert_rc "AC6.1 --yes full flow exits 0" 0
assert_eq "AC6.1/AC2.1 order with --yes: view, merge, release, CI list, CI watch, release view, install (no dry run)" "$FULL_YES" "$(steps)"
assert_contains "AC6.1 pr view is asked about PR 12" "$(grep '^gh pr view' "$FAKE_LOG" | head -n 1)" "12"
L="$(grep '^gh pr merge' "$FAKE_LOG")"
assert_contains "AC6.1 merges PR 12" "$L" "pr merge 12"
assert_contains "AC6.1 merge uses --merge" "$L" "--merge"
assert_contains "AC6.1 merge deletes the branch" "$L" "--delete-branch"
assert_eq "AC2.1 --yes: no release.sh --dry-run call at all" "0" "$(logged '^release.sh .*--dry-run')"
assert_eq "AC2.1 --yes: release.sh is called exactly once" "1" "$(logged '^release.sh')"
SKIPLINE="$(printf '%s\n' "$OUT" | grep '^== ' | grep -i 'dry' | grep -i 'skip')"
if [ -n "$SKIPLINE" ]; then t_ok "AC2.1 --yes: a '== ' line says the dry run is skipped"; else t_bad "AC2.1 --yes: a '== ' line says the dry run is skipped" "'== ' lines: $(printf '%s\n' "$OUT" | grep '^== ' | tr '\n' '|')"; fi
assert_eq "AC2.1 --yes: exactly one '== ' line talks about the dry run" "1" "$(printf '%s\n' "$OUT" | grep '^== ' | grep -ci 'dry')"
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

echo "AC6.1 refusal: the PR must be OPEN and CLEAN (nothing merged); MERGED has its own rule (v0.17.0 AC2.2 below)"
for combo in "CLOSED CLEAN" "OPEN BLOCKED" "OPEN BEHIND" "OPEN DIRTY" "OPEN UNSTABLE" "OPEN UNKNOWN" "OPEN DRAFT" "OPEN HAS_HOOKS"; do
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
assert_rc "AC2.1 --yes never runs the dry run, so a dry run that would fail with 7 does not matter: exit 0" 0
assert_eq "AC2.1 --yes with a failing dry-run stub: the full flow without dry run" "$FULL_YES" "$(steps)"
fx
export FAKE_REL_REAL_RC=5
sh_run 12 v1.2.3 --yes
assert_rc "AC6.1 real release failing with 5: ship.sh exits 5" 5
assert_eq "AC6.1 failing release: no CI wait, no release view, no install" "view merge release" "$(steps)"

echo "AC6.1 CI and release checks"
fx
export FAKE_GH_FAIL="runwatch"
sh_run 12 v1.2.3 --yes
assert_rc "AC6.1 failed CI run: exit 1" 1
assert_contains "AC6.1 failed CI run: the message names the run" "$OUT" "4242"
assert_eq "AC6.1 failed CI run: no release view, no install" "view merge release runlist runwatch" "$(steps)"
fx
export FAKE_GH_FAIL="relview"
sh_run 12 v1.2.3 --yes
if [ "$RC" -ne 0 ]; then t_ok "AC6.1 missing GitHub release: non-zero exit"; else t_bad "AC6.1 missing GitHub release: non-zero exit" "exit $RC; output: $OUT"; fi
assert_contains "AC6.1 missing release: the message names the tag" "$OUT" "v1.2.3"
assert_eq "AC6.1 missing release: install is not run" "view merge release runlist runwatch relview" "$(steps)"
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
  assert_eq "R1 run list $mode: never calls run watch, release view or install" "view merge release runlist" "$(steps)"
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
assert_eq "R1 gh run list failing: no watch, no release view, no install" "view merge release runlist" "$(steps)"
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
usage_case "--auto alone, without a PR and a tag (v0.17.0)" --auto
usage_case "--auto and --yes but no PR and no tag (v0.17.0)" --yes --auto
usage_case "--auto with a PR but no tag (v0.17.0)" 12 --auto
assert_eq "AC6.1 usage errors: gh, release.sh and install.sh were never called" "" "$(steps)"
assert_eq "AC6.1 usage errors: the log is empty" "0" "$(wc -l < "$FAKE_LOG" | tr -d ' ')"

echo "v0.13.0 AC1.1 ship merges from main, whatever the clone was on"
merge_at() { grep '^merge-at ' "$FAKE_LOG" | head -n 1; }
# lines printed before the merge step
before_merge() { printf '%s\n' "$OUT" | awk '/^== merge PR/ { exit } { print }'; }
fx   # default fixture: the clone is on the branch feat/x
sh_run 12 v1.2.3 --yes
assert_rc "AC1.1 on another branch: exit 0" 0
assert_eq "AC1.1 on another branch: gh pr merge ran while the clone was on main" "merge-at main" "$(merge_at)"
assert_eq "AC1.1 on another branch: the full flow ran" "$FULL_YES" "$(steps)"
if before_merge | grep '^== ' | grep -q 'main'; then t_ok "AC1.1 on another branch: a '== ' line before the merge says it switches to main"
else t_bad "AC1.1 on another branch: a '== ' line before the merge says it switches to main" "output before the merge: $(before_merge)"; fi
fx
( cd "$F/repo" && git checkout -q --detach )
assert_eq "AC1.1 fixture check: the clone starts on a detached HEAD" "HEAD" "$(cd "$F/repo" && git rev-parse --abbrev-ref HEAD)"
sh_run 12 v1.2.3 --yes
assert_rc "AC1.1 detached HEAD: exit 0" 0
assert_eq "AC1.1 detached HEAD: gh pr merge ran while the clone was on main" "merge-at main" "$(merge_at)"
assert_eq "AC1.1 detached HEAD: the full flow ran" "$FULL_YES" "$(steps)"
assert_eq "AC1.1 detached HEAD: the local main got the merge" "$(git -C "$F/origin.git" rev-parse main)" "$(cd "$F/repo" && git rev-parse HEAD)"
if before_merge | grep '^== ' | grep -q 'main'; then t_ok "AC1.1 detached HEAD: a '== ' line before the merge says it switches to main"
else t_bad "AC1.1 detached HEAD: a '== ' line before the merge says it switches to main" "output before the merge: $(before_merge)"; fi
fx
( cd "$F/repo" && git switch -q main )
sh_run 12 v1.2.3 --yes
assert_rc "AC1.1 already on main: exit 0" 0
assert_eq "AC1.1 already on main: gh pr merge ran on main" "merge-at main" "$(merge_at)"
echo "AC1.1 the switch to main fails: refuse before merging"
for start in branch detached; do
  fx
  [ "$start" = detached ] && ( cd "$F/repo" && git checkout -q --detach )
  before="$(cd "$F/repo" && git rev-parse --abbrev-ref HEAD)"
  # main is checked out in a second work tree, so 'git switch main' fails in the clone
  git -C "$F/repo" worktree add -q "$F/wt" main >/dev/null 2>&1
  sh_run 12 v1.2.3 --yes
  assert_rc "AC1.1 ($start) switch to main impossible: exit 1" 1
  assert_eq "AC1.1 ($start) switch impossible: gh pr merge never called" "0" "$(logged '^gh pr merge')"
  assert_eq "AC1.1 ($start) switch impossible: no release, no install" "0" "$(logged '^release.sh\|^install.sh')"
  assert_eq "AC1.1 ($start) switch impossible: origin main is untouched" "0" "$(git -C "$F/origin.git" ls-tree -r --name-only main | grep -c '^merged-')"
  assert_eq "AC1.1 ($start) switch impossible: the clone stays where it was" "$before" "$(cd "$F/repo" && git rev-parse --abbrev-ref HEAD)"
done

echo "v0.13.0 AC1.2 after install.sh update the clone is back on main"
fx
export FAKE_INSTALL_DETACH=1
sh_run 12 v1.2.3 --yes
unset FAKE_INSTALL_DETACH
assert_rc "AC1.2 install leaves a detached HEAD: ship still exits 0" 0
assert_eq "AC1.2 the clone ends on main, not on a detached HEAD" "main" "$(cd "$F/repo" && git rev-parse --abbrev-ref HEAD)"
AFTER_INSTALL="$(printf '%s\n' "$OUT" | awk 'f { print } /^== update the installs/ { f = 1 }')"
assert_contains "AC1.2 the output after the install step names the branch it ends on" "$AFTER_INSTALL" "main"
fx
sh_run 12 v1.2.3 --yes
assert_eq "AC1.2 install leaves the branch alone: still on main" "main" "$(cd "$F/repo" && git rev-parse --abbrev-ref HEAD)"

echo "v0.13.0 AC1.3 invalid PB_SHIP_WAIT_* values exit 2 before anything is called"
for kv in "TRIES=abc" "TRIES=-1" "TRIES=1.5" "SECS=x" "SECS=-2" "SECS=0.5" "TRIES=4x"; do
  fx
  export "PB_SHIP_WAIT_${kv%%=*}=${kv#*=}"
  sh_run 12 v1.2.3 --yes
  unset PB_SHIP_WAIT_TRIES PB_SHIP_WAIT_SECS
  assert_rc "AC1.3 PB_SHIP_WAIT_$kv: exit 2" 2
  assert_eq "AC1.3 PB_SHIP_WAIT_$kv: gh, release.sh and install.sh were never called" "0" "$(wc -l < "$FAKE_LOG" | tr -d ' ')"
  assert_eq "AC1.3 PB_SHIP_WAIT_$kv: origin main is untouched" "0" "$(git -C "$F/origin.git" ls-tree -r --name-only main | grep -c '^merged-')"
done
fx
export PB_SHIP_WAIT_TRIES=3 PB_SHIP_WAIT_SECS=0
sh_run 12 v1.2.3 --yes
unset PB_SHIP_WAIT_TRIES PB_SHIP_WAIT_SECS
assert_rc "AC1.3 valid integers still ship" 0

echo "v0.14.0 AC1.1 ship survives the merge commit rewriting tools/ship.sh while it runs"
# the whole body is a function, called by the last line, so bash has read all of it before `git pull` runs
LASTLINE="$(grep -v '^[[:space:]]*$' "$SHIP" 2>/dev/null | tail -n 1)"
assert_eq "AC1.1 the last line of tools/ship.sh is exactly: main \"\$@\"; exit \$?" 'main "$@"; exit $?' "$LASTLINE"
assert_eq "AC1.1 tools/ship.sh defines main() exactly once" "1" "$(grep -cE '^main *\(\) *\{' "$SHIP" 2>/dev/null)"
assert_eq "AC1.1 main is called exactly once (nothing else calls it)" "1" "$(grep -cE '^main( |$)' "$SHIP" 2>/dev/null | head -n 1)"
for mode in exit99 trunc grow; do
  fx
  export FAKE_REWRITE_SHIP="$mode"
  sh_run 12 v1.2.3 --yes
  export FAKE_REWRITE_SHIP=""
  assert_eq "AC1.1 [$mode] the merge commit really rewrote tools/ship.sh in the fixture (fixture check)" "1" \
    "$([ "$(cd "$F/repo" && git rev-parse HEAD:tools/ship.sh)" != "$(git hash-object "$SHIP")" ] && echo 1 || echo 0)"
  assert_rc "AC1.1 [$mode] ship still exits 0 although tools/ship.sh was replaced mid-run" 0
  assert_eq "AC1.1 [$mode] every step still ran, in order" "$FULL_YES" "$(steps)"
  assert_contains "AC1.1 [$mode] the last message is still printed" "$OUT" "shipped v1.2.3"
  assert_eq "AC1.1 [$mode] the clone still ends on main" "main" "$(cd "$F/repo" && git rev-parse --abbrev-ref HEAD)"
done

# ---- v0.17.0: gh call shapes the tests fix (the implementer must use exactly these) ----
#  PR check:     gh pr view PR --json state,mergeStateStatus,mergeCommit --jq '...'   (gh prints mergeCommit as {"oid": "SHA"}, null until merged)
#  auto-merge:   gh pr merge PR --auto --merge --delete-branch     (exactly this argument order)
#  shard report: gh run list --branch main --event push --commit SHA --limit 1 --json databaseId [--jq ...]
#                gh run view RUN --json jobs                       (no --jq: parse the JSON with node, as tools/shard-weights.sh does)
#                jobs named "windows shard K/N" carry startedAt/completedAt; a job still running has completedAt 0001-01-01T00:00:00Z
AUTO_MERGE_CALL="gh pr merge 12 --auto --merge --delete-branch"
# merged_on_main -> the PR is MERGED and its merge commit ($MC) is a new commit on origin's main, made through the work
# clone: the local clone does not have it until ship fetches
merged_on_main() {
  ( cd "$F/work" && git pull -q --ff-only origin main >/dev/null 2>&1
    echo merged > "merged-${FAKE_PR}.txt" && git add -A && GITID commit -qm "merge PR $FAKE_PR" &&
    git push -q origin HEAD:main >/dev/null 2>&1 ) || { echo "fixture setup failed: merge commit"; exit 3; }
  MC="$(git -C "$F/work" rev-parse HEAD)"
  export FAKE_GH_STATE=MERGED FAKE_GH_MERGE_COMMIT="$MC"
}
# side_commit -> a commit that exists on origin but only on the branch "side", never on main ($MC)
side_commit() {
  ( cd "$F/work" && git switch -q -c side && echo side > side.txt && git add -A && GITID commit -qm side &&
    git push -q origin side >/dev/null 2>&1 ) || { echo "fixture setup failed: side commit"; exit 3; }
  MC="$(git -C "$F/work" rev-parse HEAD)"
}
origin_merges() { git -C "$F/origin.git" ls-tree -r --name-only main | grep -c '^merged-'; }

echo "v0.17.0 AC2.1 --auto: an OPEN PR that is not CLEAN yet gets GitHub auto-merge and ship stops without releasing"
for st in BLOCKED UNSTABLE; do
  fx
  export FAKE_GH_MERGE_STATE="$st"
  sh_run 12 v1.2.3 --yes --auto
  assert_rc "AC2.1 OPEN/$st with --auto: exit 0" 0
  assert_eq "AC2.1 OPEN/$st with --auto: exactly one merge call, '$AUTO_MERGE_CALL'" "$AUTO_MERGE_CALL" "$(grep '^gh pr merge' "$FAKE_LOG")"
  assert_eq "AC2.1 OPEN/$st with --auto: only the PR check and the auto-merge call (no release, CI wait or install)" "view merge" "$(steps)"
  assert_eq "AC2.1 OPEN/$st with --auto: no release.sh and no install.sh call" "0" "$(logged '^release.sh\|^install.sh')"
  assert_eq "AC2.1 OPEN/$st with --auto: no tag was created" "" "$(git -C "$F/repo" tag)"
  assert_eq "AC2.1 OPEN/$st with --auto: nothing was merged into origin's main yet" "0" "$(origin_merges)"
  assert_contains "AC2.1 OPEN/$st with --auto: says auto-merge was enabled" "$OUT" "auto-merge"
  assert_contains "AC2.1 OPEN/$st with --auto: says it will merge when the checks pass" "$OUT" "will merge when the checks pass"
  assert_contains "AC2.1 OPEN/$st with --auto: names the command to run again (PR and tag)" "$OUT" "tools/ship.sh 12 v1.2.3"
  assert_contains "AC2.1 OPEN/$st with --auto: says to run ship again" "$OUT" "again"
  assert_not_contains "AC2.1 OPEN/$st with --auto: does not claim the release is shipped" "$OUT" "shipped v1.2.3"
done
fx
export FAKE_PR=345 FAKE_TAG=v10.20.30 FAKE_GH_MERGE_STATE=BLOCKED
sh_run --auto 345 v10.20.30 --yes   # the option may come first; another PR and tag
assert_rc "AC2.1 --auto before the arguments, PR 345: exit 0" 0
assert_eq "AC2.1 --auto PR 345: the merge call carries PR 345" "gh pr merge 345 --auto --merge --delete-branch" "$(grep '^gh pr merge' "$FAKE_LOG")"
assert_contains "AC2.1 --auto PR 345: the run-again command names PR 345 and v10.20.30" "$OUT" "tools/ship.sh 345 v10.20.30"
fx
export FAKE_GH_MERGE_STATE=BLOCKED
sh_run 12 v1.2.3 --auto --yes
assert_rc "AC2.1 '--auto --yes' (either order): exit 0" 0
assert_eq "AC2.1 '--auto --yes': one auto-merge call" "$AUTO_MERGE_CALL" "$(grep '^gh pr merge' "$FAKE_LOG")"
echo "AC2.1 --auto on a CLEAN PR merges and releases as usual; without --auto a non-CLEAN PR is still refused"
fx
sh_run 12 v1.2.3 --yes --auto
assert_rc "AC2.1 CLEAN PR with --auto: exit 0" 0
assert_eq "AC2.1 CLEAN PR with --auto: the whole flow ran" "$FULL_YES" "$(steps)"
assert_eq "AC2.1 CLEAN PR with --auto: a plain merge call, no --auto in it" "gh pr merge 12 --merge --delete-branch" "$(grep '^gh pr merge' "$FAKE_LOG")"
assert_eq "AC2.1 CLEAN PR with --auto: released from main with the merge pulled" "release.sh v1.2.3 | branch=main merged=yes" "$(grep '^release.sh' "$FAKE_LOG" | grep -v -- '--dry-run')"
for st in BLOCKED UNSTABLE; do
  fx
  export FAKE_GH_MERGE_STATE="$st"
  sh_run 12 v1.2.3 --yes
  assert_rc "AC2.1 OPEN/$st without --auto is still refused: exit 1" 1
  assert_eq "AC2.1 OPEN/$st without --auto: no merge call at all (not even an auto-merge)" "view" "$(steps)"
done
echo "AC2.1 --auto does not make other states acceptable"
fx
export FAKE_GH_STATE=CLOSED FAKE_GH_MERGE_STATE=BLOCKED
sh_run 12 v1.2.3 --yes --auto
assert_rc "AC2.1 CLOSED PR with --auto: exit 1" 1
assert_eq "AC2.1 CLOSED PR with --auto: nothing merged, nothing released" "view" "$(steps)"
fx
export FAKE_GH_MERGE_STATE=BLOCKED FAKE_GH_FAIL="merge"
sh_run 12 v1.2.3 --yes --auto
if [ "$RC" -ne 0 ]; then t_ok "AC2.1 enabling auto-merge fails (gh error): non-zero exit"; else t_bad "AC2.1 enabling auto-merge fails (gh error): non-zero exit" "exit $RC; output: $OUT"; fi
assert_eq "AC2.1 enabling auto-merge fails: no release, no install" "view merge" "$(steps)"
assert_not_contains "AC2.1 enabling auto-merge fails: does not say auto-merge is on" "$OUT" "will merge when the checks pass"

echo "v0.17.0 AC2.2 a PR already MERGED (auto-merge) whose merge commit is on origin/main goes on to the release"
fx
merged_on_main
assert_eq "AC2.2 fixture: the merge commit is not in the local clone yet (ship must fetch to see it on origin/main)" "no" \
  "$(git -C "$F/repo" cat-file -e "$MC^{commit}" 2>/dev/null && echo yes || echo no)"
sh_run 12 v1.2.3 --yes
assert_rc "AC2.2 MERGED, merge commit on origin/main: exit 0" 0
assert_eq "AC2.2 MERGED: no merge call; update main, release, CI, release check, install ran" "$MERGED_YES" "$(steps)"
assert_eq "AC2.2 MERGED: gh pr merge was never called" "0" "$(logged '^gh pr merge')"
assert_eq "AC2.2 MERGED: exactly one '== ' line says the PR is already merged" "1" "$(printf '%s\n' "$OUT" | grep '^== ' | grep -ci 'already merged')"
assert_eq "AC2.2 MERGED: no '== merge PR' step line" "0" "$(printf '%s\n' "$OUT" | grep -c '^== merge PR')"
assert_eq "AC2.2 MERGED: released from main with the merge commit pulled" "release.sh v1.2.3 | branch=main merged=yes" "$(grep '^release.sh' "$FAKE_LOG" | grep -v -- '--dry-run')"
assert_eq "AC2.2 MERGED: the local main is at origin's main" "$(git -C "$F/origin.git" rev-parse main)" "$(cd "$F/repo" && git rev-parse HEAD)"
assert_eq "AC2.2 MERGED: the local main has the merge commit" "yes" "$(git -C "$F/repo" cat-file -e "$MC^{commit}" 2>/dev/null && echo yes || echo no)"
assert_contains "AC2.2 MERGED: the last message is still printed" "$OUT" "shipped v1.2.3"
assert_eq "AC2.2 MERGED: the clone ends on main" "main" "$(cd "$F/repo" && git rev-parse --abbrev-ref HEAD)"
for ms in UNKNOWN BLOCKED DIRTY; do   # gh reports no useful merge state for a merged PR: only state and commit count
  fx
  merged_on_main
  export FAKE_GH_MERGE_STATE="$ms"
  sh_run 12 v1.2.3 --yes
  assert_rc "AC2.2 MERGED with merge state $ms and the commit on origin/main: exit 0" 0
  assert_eq "AC2.2 MERGED/$ms: the merged flow ran" "$MERGED_YES" "$(steps)"
done
fx
merged_on_main
sh_run 12 v1.2.3 --yes --auto
assert_rc "AC2.2 MERGED with --auto: exit 0" 0
assert_eq "AC2.2 MERGED with --auto: still no merge call (not even an auto-merge)" "0" "$(logged '^gh pr merge')"
assert_eq "AC2.2 MERGED with --auto: the merged flow ran" "$MERGED_YES" "$(steps)"
fx
merged_on_main
sh_run 12 v1.2.3
assert_rc "AC2.2 MERGED, closed stdin, no --yes: stops at the tag question: exit 1" 1
assert_eq "AC2.2 MERGED, closed stdin: no merge question, the dry run ran, nothing was tagged" "view dry" "$(steps)"
assert_not_contains "AC2.2 MERGED, closed stdin: the merge question is skipped" "$OUT" "merge PR #12?"
fx
merged_on_main
export FAKE_REL_REAL_RC=5
sh_run 12 v1.2.3 --yes
assert_rc "AC2.2 MERGED: a failing release.sh (5) still stops ship with its status" 5
assert_eq "AC2.2 MERGED with a failing release: nothing after it" "view release" "$(steps)"

echo "AC2.2 refused: MERGED but the merge commit is not on origin/main, or no merge commit; CLOSED"
fx
export FAKE_GH_STATE=MERGED FAKE_GH_MERGE_COMMIT=0123456789abcdef0123456789abcdef01234567
sh_run 12 v1.2.3 --yes
assert_rc "AC2.2 MERGED with a commit unknown to origin: exit 1" 1
assert_eq "AC2.2 MERGED with an unknown commit: nothing merged or released" "view" "$(steps)"
assert_contains "AC2.2 MERGED with an unknown commit: the refusal names origin/main" "$OUT" "origin/main"
assert_eq "AC2.2 MERGED with an unknown commit: gh pr merge never called" "0" "$(logged '^gh pr merge')"
fx
side_commit
export FAKE_GH_STATE=MERGED FAKE_GH_MERGE_COMMIT="$MC"
sh_run 12 v1.2.3 --yes
assert_rc "AC2.2 MERGED with a commit that is on origin but not on main: exit 1" 1
assert_eq "AC2.2 MERGED with a side-branch commit: nothing merged or released" "view" "$(steps)"
assert_contains "AC2.2 MERGED with a side-branch commit: the refusal names origin/main" "$OUT" "origin/main"
fx
export FAKE_GH_STATE=MERGED FAKE_GH_MERGE_STATE=CLEAN FAKE_GH_MERGE_COMMIT=""
sh_run 12 v1.2.3 --yes
assert_rc "AC2.2 MERGED with no merge commit reported: exit 1" 1
assert_eq "AC2.2 MERGED with no merge commit: nothing merged or released" "view" "$(steps)"
fx
merged_on_main
export FAKE_GH_STATE=CLOSED
sh_run 12 v1.2.3 --yes
assert_rc "AC2.2 CLOSED with a commit that is on origin/main: exit 1" 1
assert_eq "AC2.2 CLOSED: nothing merged or released" "view" "$(steps)"

echo "v0.17.0 AC4.1 unbalanced windows shards are reported after the tag's CI passes"
shard_calls() { grep '^gh run list .*--branch main ' "$FAKE_LOG"; }
unb() { printf '%s\n' "$OUT" | grep -c 'shards unbalanced'; }
fx
export FAKE_SHARDS="300,100,200"
sh_run 12 v1.2.3 --yes
assert_rc "AC4.1 shards 300/100/200 s: ship still succeeds (exit 0)" 0
assert_eq "AC4.1 unbalanced: the whole flow ran as before" "$FULL_YES" "$(steps)"
assert_eq "AC4.1 unbalanced: one line names the shortest, the longest and the run id" "1" \
  "$(printf '%s\n' "$OUT" | grep -cF 'shards unbalanced (100 s .. 300 s): run tools/shard-weights.sh 7777')"
assert_eq "AC4.1 unbalanced: only one line talks about it" "1" "$(unb)"
assert_contains "AC4.1 unbalanced: shipped is still printed" "$OUT" "shipped v1.2.3"
TAGSHA="$(cd "$F/repo" && git rev-parse 'v1.2.3^{commit}' 2>/dev/null)"
assert_eq "AC4.1 exactly one lookup of the push-to-main run" "1" "$(shard_calls | wc -l | tr -d ' ')"
assert_contains "AC4.1 the lookup is for branch main" "$(shard_calls)" "--branch main"
assert_contains "AC4.1 the lookup is for event push" "$(shard_calls)" "--event push"
assert_contains "AC4.1 the lookup is for the release commit (the tag's commit)" "$(shard_calls)" "--commit $TAGSHA"
assert_eq "AC4.1 the jobs of that run are read once: gh run view 7777 --json jobs" "1" "$(grep -c '^gh run view 7777 .*--json jobs' "$FAKE_LOG")"
WATCHN="$(grep -n '^gh run watch' "$FAKE_LOG" | head -n 1 | cut -d: -f1)"; VIEWN="$(grep -n '^gh run view' "$FAKE_LOG" | head -n 1 | cut -d: -f1)"
if [ -n "$WATCHN" ] && [ -n "$VIEWN" ] && [ "$VIEWN" -gt "$WATCHN" ]; then t_ok "AC4.1 the shard jobs are read after the CI run was watched"; else t_bad "AC4.1 the shard jobs are read after the CI run was watched" "watch at log line [$WATCHN], run view at [$VIEWN]"; fi
fx
export FAKE_SHARDS="250,100" FAKE_MAIN_RUN=9191
sh_run 12 v1.2.3 --yes
assert_eq "AC4.1 another run id (9191) and two shards: the hint names 9191" "1" "$(printf '%s\n' "$OUT" | grep -cF 'shards unbalanced (100 s .. 250 s): run tools/shard-weights.sh 9191')"
assert_not_contains "AC4.1 the hint names the push-to-main run, not the tag's run (4242)" "$OUT" "shard-weights.sh 4242"
echo "AC4.1 balanced shards print nothing (the other jobs of the run, 900 s and 30 s, are not shards)"
for sh in "100,120,110" "150,100" "100,100,100" "300"; do
  fx
  export FAKE_SHARDS="$sh"
  sh_run 12 v1.2.3 --yes
  assert_rc "AC4.1 shards [$sh]: exit 0" 0
  assert_eq "AC4.1 shards [$sh]: no unbalanced line (longest is not more than 1.5x the shortest)" "0" "$(unb)"
  assert_eq "AC4.1 shards [$sh]: the jobs were looked at (one gh run view)" "1" "$(logged '^gh run view')"
done
fx
export FAKE_SHARDS="151,100"
sh_run 12 v1.2.3 --yes
assert_eq "AC4.1 151 s against 100 s is more than 1.5x: reported" "1" "$(printf '%s\n' "$OUT" | grep -cF 'shards unbalanced (100 s .. 151 s)')"
fx
export FAKE_SHARDS="300,100,running"
sh_run 12 v1.2.3 --yes
assert_eq "AC4.1 a shard without a finish time is ignored, the others are compared (100 s .. 300 s)" "1" "$(printf '%s\n' "$OUT" | grep -cF 'shards unbalanced (100 s .. 300 s)')"
fx
export FAKE_SHARDS="100,running"
sh_run 12 v1.2.3 --yes
assert_rc "AC4.1 one finished shard and one unfinished: exit 0" 0
assert_eq "AC4.1 one finished shard and one unfinished: nothing to compare, no hint" "0" "$(unb)"
echo "AC4.1 missing or broken data prints nothing and never fails the ship"
fx
export FAKE_SHARDS=none
sh_run 12 v1.2.3 --yes
assert_rc "AC4.1 the run has no shard jobs: exit 0" 0
assert_eq "AC4.1 no shard jobs: no hint, the flow ran" "0 $FULL_YES" "$(unb) $(steps)"
fx
export FAKE_SHARDS=bad
sh_run 12 v1.2.3 --yes
assert_rc "AC4.1 gh run view prints something that is not JSON: exit 0" 0
assert_eq "AC4.1 not JSON: no hint, the flow ran" "0 $FULL_YES" "$(unb) $(steps)"
assert_not_contains "AC4.1 not JSON: no parser noise on the terminal" "$OUT" "SyntaxError"
for mode in empty null; do
  fx
  export FAKE_SHARDS="300,100" FAKE_SHARD_LIST="$mode"
  sh_run 12 v1.2.3 --yes
  assert_rc "AC4.1 no push-to-main run found ($mode): exit 0" 0
  assert_eq "AC4.1 no push-to-main run found ($mode): no hint, the flow ran" "0 $FULL_YES" "$(unb) $(steps)"
  assert_eq "AC4.1 no push-to-main run found ($mode): gh run view is not called" "0" "$(logged '^gh run view')"
done
for word in shardlist shardview; do
  fx
  export FAKE_SHARDS="300,100" FAKE_GH_FAIL="$word"
  sh_run 12 v1.2.3 --yes
  assert_rc "AC4.1 gh failing in the shard report ($word): exit 0" 0
  assert_eq "AC4.1 gh failing ($word): no hint, the flow ran" "0 $FULL_YES" "$(unb) $(steps)"
  assert_contains "AC4.1 gh failing ($word): shipped is still printed" "$OUT" "shipped v1.2.3"
done
fx
export FAKE_SHARDS="300,100" FAKE_GH_FAIL="runwatch"
sh_run 12 v1.2.3 --yes
assert_rc "AC4.1 the tag's CI run failed: exit 1 as before" 1
assert_eq "AC4.1 CI failed: no shard report (no hint, no gh run view)" "0 0" "$(unb) $(logged '^gh run view')"

echo "v0.22.2 AC3 ship refreshes the shard weights when the shards are unbalanced"
WN='.agents/handoff/shard-weights.next'
refreshed() { printf '%s\n' "$OUT" | grep -cF 'shard weights refreshed: copy .agents/handoff/shard-weights.next to tests/shard-weights in the next PR'; }
notref() { printf '%s\n' "$OUT" | grep -c 'shard weights not refreshed'; }
subjects() { git -C "$1" log --format=%s main | tr '\n' '|'; }
fx
export FAKE_SHARDS="300,100,200"
W_BEFORE="$(cat "$F/repo/tests/shard-weights")"
assert_no_path "AC3.1 before the run there is no .agents/handoff in the fixture" "$F/repo/.agents/handoff"
sh_run 12 v1.2.3 --yes
assert_rc "AC3.1 unbalanced: ship succeeds (exit 0)" 0
assert_eq "AC3.1 unbalanced: the whole flow ran as before" "$FULL_YES" "$(steps)"
assert_dir "AC3.1 unbalanced: .agents/handoff was created" "$F/repo/.agents/handoff"
assert_file "AC3.1 unbalanced: .agents/handoff/shard-weights.next was written" "$F/repo/$WN"
assert_eq "AC3.1 unbalanced: one 'shard weights refreshed: copy ...' line" "1" "$(refreshed)"
assert_eq "AC3.1 unbalanced: no 'not refreshed' line" "0" "$(notref)"
assert_contains "AC3.1 unbalanced: shipped is still printed" "$OUT" "shipped v1.2.3"
WNTXT="$(cat "$F/repo/$WN" 2>/dev/null)"
assert_contains "AC3.1 the weights file names the main push run (7777)" "$WNTXT" "run 7777"
assert_contains "AC3.1 the weights file has the suite timings from the shard logs (test-big.sh 120)" "$WNTXT" "test-big.sh 120"
assert_contains "AC3.1 the weights file has the other suite (test-small.sh 7)" "$WNTXT" "test-small.sh 7"
assert_contains "AC3.1 the refresh reads the shard jobs of run 7777 (gh run view 7777 --json jobs)" "$(grep '^gh run view' "$FAKE_LOG")" "7777"
assert_contains "AC3.1 the refresh reads a shard job log (gh run view --job)" "$(grep '^gh run view' "$FAKE_LOG")" "--job"
assert_eq "AC3.1 tests/shard-weights is unchanged" "$W_BEFORE" "$(cat "$F/repo/tests/shard-weights")"
assert_eq "AC3.1 git sees no change under tests/" "" "$(git -C "$F/repo" status --porcelain -- tests)"
assert_eq "AC3.1 no commit was made on main (only init and the fake merge)" "merge PR 12|init|" "$(subjects "$F/repo")"
assert_eq "AC3.1 nothing was pushed (origin main has only init and the fake merge)" "merge PR 12|init|" "$(subjects "$F/origin.git")"

fx
export FAKE_SHARDS="300,100,200" FAKE_GH_FAIL="shardlog"
sh_run 12 v1.2.3 --yes
assert_rc "AC3.1 shard-weights.sh fails: ship still exits 0" 0
assert_eq "AC3.1 shard-weights.sh fails: the flow ran" "$FULL_YES" "$(steps)"
assert_eq "AC3.1 shard-weights.sh fails (gh exit 3): 'shard weights not refreshed (shard-weights.sh exit 3)'" "1" \
  "$(printf '%s\n' "$OUT" | grep -cF 'shard weights not refreshed (shard-weights.sh exit 3)')"
assert_eq "AC3.1 shard-weights.sh fails: no 'refreshed: copy' line" "0" "$(refreshed)"
assert_no_path "AC3.1 shard-weights.sh fails: no .next file" "$F/repo/$WN"
assert_contains "AC3.1 shard-weights.sh fails: shipped is still printed" "$OUT" "shipped v1.2.3"
assert_eq "AC3.1 shard-weights.sh fails: tests/shard-weights is unchanged" "$W_BEFORE" "$(cat "$F/repo/tests/shard-weights")"

fx
export FAKE_SHARDS="300,100,200" FAKE_SHARD_LOG=none
sh_run 12 v1.2.3 --yes
assert_rc "AC3.1 no timings in the logs: ship still exits 0" 0
assert_eq "AC3.1 no timings (shard-weights.sh exit 1): 'shard weights not refreshed (shard-weights.sh exit 1)'" "1" \
  "$(printf '%s\n' "$OUT" | grep -cF 'shard weights not refreshed (shard-weights.sh exit 1)')"
assert_eq "AC3.1 no timings: no 'refreshed: copy' line" "0" "$(refreshed)"

echo "v0.22.2 AC3 balanced shards: no refresh"
fx
export FAKE_SHARDS="100,110,120"
sh_run 12 v1.2.3 --yes
assert_rc "AC3.1 balanced: exit 0" 0
assert_eq "AC3.1 balanced: no 'shard weights' line at all" "0" "$(printf '%s\n' "$OUT" | grep -c 'shard weights')"
assert_no_path "AC3.1 balanced: no .agents/handoff" "$F/repo/.agents/handoff"
assert_eq "AC3.1 balanced: the shard logs were not fetched (no gh run view --job)" "0" "$(logged '^gh run view .*--job')"
fx
export FAKE_SHARDS="300,100,200" FAKE_GH_FAIL="shardview"
sh_run 12 v1.2.3 --yes
assert_eq "AC3.1 no shard data (gh failed): no 'shard weights' line" "0" "$(printf '%s\n' "$OUT" | grep -c 'shard weights')"
assert_no_path "AC3.1 no shard data: no .agents/handoff" "$F/repo/.agents/handoff"
unset FAKE_SHARD_LOG

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
  assert_eq "AC2.1 with the questions the dry run stays: exactly 'release.sh v1.2.3 --dry-run', on main with the merge pulled" \
    "release.sh v1.2.3 --dry-run | branch=main merged=yes" "$(grep '^release.sh .*--dry-run' "$FAKE_LOG")"
  assert_eq "AC2.1 with the questions: no '== ' line says the dry run is skipped" "0" "$(printf '%s\n' "$OUT" | grep '^== ' | grep -i 'dry' | grep -ci 'skip')"
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
  export FAKE_REL_DRY_RC=7
  pty_ship y y -- 12 v1.2.3
  assert_rc "AC2.1 with the questions a failing dry run (7) still stops ship.sh with its status" 7
  assert_eq "AC2.1 with the questions a failing dry run: no real release, nothing after" "view merge dry" "$(steps)"
  fx
  pty_ship -- 12 v1.2.3 --yes
  assert_rc "AC6.1 --yes on a terminal: exit 0 without any answer" 0
  assert_eq "AC2.1 --yes on a terminal: no dry run either" "$FULL_YES" "$(steps)"
  assert_not_contains "AC6.1 --yes on a terminal: no question is printed" "$OUT" "[y/N]"
  fx
  export FAKE_GH_STATE=MERGED
  pty_ship y y -- 12 v1.2.3
  assert_rc "AC6.1/AC2.2 a merged PR with no merge commit on origin/main is refused before any question" 1
  assert_not_contains "AC6.1/AC2.2 refusal comes before the first question" "$OUT" "[y/N]"
  fx
  merged_on_main
  pty_ship y -- 12 v1.2.3
  assert_rc "AC2.2 a merged PR on origin/main: the one answer (y) goes to the tag question: exit 0" 0
  assert_eq "AC2.2 a merged PR with the questions: no merge, the dry run stays" "$MERGED_Q" "$(steps)"
  assert_not_contains "AC2.2 a merged PR: the merge question is not asked" "$OUT" "merge PR #12? [y/N]"
  assert_contains "AC2.2 a merged PR: the tag question is asked" "$OUT" "tag and push v1.2.3? [y/N]"
}
PTY_N=38
if [ "$PTY_OK" = 1 ]; then pty_block; else t_skip "$PTY_N" "AC6.1 prompt assertions need python3 with a pty (not available here)"; fi

t_summary
