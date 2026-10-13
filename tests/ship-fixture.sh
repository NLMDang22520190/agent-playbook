#!/usr/bin/env bash
# Shared setup of tests/test-ship.sh and tests/test-ship-b.sh (split in v0.24.7 so that neither part is the floor of a CI shard): the GIT_CONFIG override, the fake
# gh and the stub release.sh / install.sh / ci-tree-tested.sh, fx (the fixture repo), sh_run, steps and the helpers of the merge and shard sections.
# Source it after lib.sh. It is not a suite: run-all.sh only starts tests/test-*.sh.
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
    rv="FAKE_SHARDS_$3"; if [ -n "${!rv:-}" ]; then FAKE_SHARDS="${!rv}"; fi   # per-run override (v0.22.3 AC6.3)
    case "${FAKE_SHARDS:-}" in
      bad) echo "this is not json"; exit 0 ;;
    esac
    iso() { local s=$((36000 + $1)); printf '2026-10-11T%02d:%02d:%02dZ' $((s / 3600)) $((s % 3600 / 60)) $((s % 60)); }
    job() { printf '{"databaseId":%s,"name":"%s","status":"%s","conclusion":"%s","startedAt":"%s","completedAt":"%s"}' "$1" "$2" "$3" "${6:-success}" "$4" "$5"; }
    jobs=""; sep=""; i=0
    if [ "${FAKE_SHARDS:-}" != none ]; then
      # other jobs of the same run: they are not shards and must not count
      jobs="$(job 9001 'test (ubuntu-latest)' completed "$(iso 0)" "$(iso 900)"),$(job 9002 'test (macos-latest)' completed "$(iso 0)" "$(iso 30)"),$(job 9003 'test (windows-latest)' completed "$(iso 0)" "$(iso 5)")"
      sep=","
      for d in $(printf '%s' "${FAKE_SHARDS:-}" | tr ',' ' '); do
        i=$((i + 1))
        case "$d" in
          running) jobs="$jobs$sep$(job $((9100 + i)) "windows shard $i/3" in_progress "$(iso 0)" '0001-01-01T00:00:00Z')" ;;
          skip) jobs="$jobs$sep$(job $((9100 + i)) "windows shard $i/3" completed "$(iso 0)" "$(iso 1)" skipped)" ;;
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
# ---- stub tools/ci-tree-tested.sh (v0.22.3 AC6.3): logs its arguments, prints $FAKE_TREE_RUN (nothing when empty), exits $FAKE_TREE_RC ----
cat > "$W/ci.stub" <<'EOF'
#!/usr/bin/env bash
echo "ci-tree-tested.sh $*" >> "$FAKE_LOG"
[ -n "${FAKE_TREE_RUN:-}" ] && echo "$FAKE_TREE_RUN"
exit "${FAKE_TREE_RC:-0}"
EOF
chmod +x "$BIN/gh" "$W/release.stub" "$W/install.stub" "$W/ci.stub"

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
  cp -p "$W/ci.stub" "$F/repo/tools/ci-tree-tested.sh"
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
  export FAKE_REL_DRY_RC=0 FAKE_REL_REAL_RC=0 FAKE_INSTALL_RC=0 FAKE_PR=12 FAKE_TAG=v1.2.3 FAKE_GH_MERGE_COMMIT= FAKE_SHARD_LIST= FAKE_MAIN_RUN=7777 FAKE_SHARDS= FAKE_SHARD_LOG= FAKE_TREE_RUN= FAKE_TREE_RC=0
  unset FAKE_SHARDS_7777 FAKE_SHARDS_5555 FAKE_SHARDS_9191
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
shard_calls() { grep '^gh run list .*--branch main ' "$FAKE_LOG"; }
unb() { printf '%s\n' "$OUT" | grep -c 'shards unbalanced'; }
