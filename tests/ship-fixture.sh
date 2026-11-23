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
# fake gh. T11 (v0.38.0): the PR is read and merged through the REST API (`gh api`); every `gh pr ...` is refused with a GraphQL-style error
# (exit 1), except `gh pr merge ... --auto` (GraphQL has no REST twin), which needs `gh api graphql` to work.
#   gh api repos/O/R/pulls/N                 -> the PR as raw REST JSON (state open|closed, merged, mergeable_state (lower case), merge_commit_sha,
#                                               head.sha, head.ref, head.repo.full_name, base.ref, base.repo.full_name)
#   gh api -X PUT repos/O/R/pulls/N/merge    -> merges: logs "merge-at <branch>", pushes merged-N.txt to origin's main (N from the path)
#   gh api -X DELETE repos/O/R/git/refs/heads/REF, gh api graphql, gh api repos/O/R/actions/runs...; any other gh api path: exit 0, no output
# Every call is also logged with its GH_REPO to "$FAKE_LOG.ghrepo" (one line "GH_REPO=<value> gh <args>"), so that $FAKE_LOG keeps one line per call.
# Env: FAKE_LOG, FAKE_GH_STATE (OPEN|MERGED|CLOSED), FAKE_GH_MERGE_STATE (upper case word; NULL = "mergeable_state": null, MISSING = key absent),
# FAKE_GH_MERGE_COMMIT (sha of merge_commit_sha, empty = null, also for an OPEN PR: GitHub's trial merge), FAKE_GH_HEAD_REPO (default: the repo of the path;
# "null" = head.repo null; any other value = that head repo, a fork), FAKE_GH_HEAD_REF (default feat/x), FAKE_GH_BASE_REF (default main),
# FAKE_GH_FAIL (words: prview (GET pulls) merge (PUT merge, and gh pr merge --auto) merge405 merge409 merge422 (PUT merge, with that HTTP status) delete
# (DELETE ref) runs (actions/runs) graphql runlist runwatch relview shardlist shardview shardlog),
# FAKE_SHARD_LOG (none = the job log has no suite timings),
# FAKE_ORIGIN_WORK (clone of origin used to simulate the merge), FAKE_ORIGIN_GIT (the bare origin: headRefOid is read from it),
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
    # v0.32.0 AC9: the PR head sha is the tip of origin's refs/pull/N/head, else of the head branch feat/x
    headRefOid) git --git-dir="${FAKE_ORIGIN_GIT:-/nonexistent}" rev-parse -q --verify "refs/pull/${FAKE_PR:-12}/head^{commit}" 2>/dev/null ||
                git --git-dir="${FAKE_ORIGIN_GIT:-/nonexistent}" rev-parse -q --verify "refs/heads/feat/x^{commit}" 2>/dev/null || echo "" ;;
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
    case "$1" in '[]'|null) return ;; esac   # no jq: an empty list or null selects nothing, so print nothing
    # no jq: print the value of every .field named in the expression, one per line
    for t in $(printf '%s' "$expr" | grep -oE '\.[A-Za-z_]+' | tr -d .); do val "$t"; done
    return
  fi
  printf '%s\n' "$1"
}
echo "GH_REPO=${GH_REPO:-} gh $*" >> "$FAKE_LOG.ghrepo"
graphql_403() { echo "GraphQL: Resource not accessible by integration (HTTP 403)" >&2; }
# do_merge N: what GitHub does on a merge: the PR's commit reaches origin's main (a detached HEAD makes the real gh fail locally after the merge)
do_merge() {
  echo "merge-at $(git rev-parse --abbrev-ref HEAD 2>&1)" >> "$FAKE_LOG"
  ( cd "$FAKE_ORIGIN_WORK" &&
    git pull -q --ff-only origin main >/dev/null 2>&1
    case "${FAKE_REWRITE_SHIP:-}" in
      exit99) printf 'exit 99\n' > tools/ship.sh ;;
      trunc)  head -c 300 tools/ship.sh > tools/ship.tmp && mv tools/ship.tmp tools/ship.sh ;;
      grow)   { cat tools/ship.sh; printf '\necho "ship.sh from the merge commit"; exit 98\n'; } > tools/ship.tmp && mv tools/ship.tmp tools/ship.sh ;;
    esac
    echo merged > "merged-${1}.txt" && git add -A &&
    git -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false commit -qm "merge PR $1" &&
    git push -q origin HEAD:main >/dev/null 2>&1 ) || return 1
}
pr_json() { # $1 = OWNER/REPO taken from the path -> the REST JSON of the PR
  local st="${FAKE_GH_STATE:-OPEN}" s merged=false ms mc hr h hsha
  case "$st" in OPEN) s=open ;; MERGED) s=closed; merged=true ;; *) s=closed ;; esac
  case "${FAKE_GH_MERGE_STATE:-CLEAN}" in
    NULL) ms='"mergeable_state":null,' ;;
    MISSING) ms="" ;;
    *) ms="\"mergeable_state\":\"$(printf '%s' "${FAKE_GH_MERGE_STATE:-CLEAN}" | tr 'A-Z' 'a-z')\"," ;;
  esac
  if [ -n "${FAKE_GH_MERGE_COMMIT:-}" ]; then mc="\"$FAKE_GH_MERGE_COMMIT\""; else mc=null; fi
  h="${FAKE_GH_HEAD_REPO:-$1}"
  case "$h" in null) hr=null ;; *) hr="{\"full_name\":\"$h\"}" ;; esac
  hsha="$(val headRefOid)"
  printf '{"number":%s,"title":"fake pull request","state":"%s","merged":%s,%s"merge_commit_sha":%s,"head":{"sha":"%s","ref":"%s","repo":%s},"base":{"ref":"%s","repo":{"full_name":"%s"}}}\n' \
    "${FAKE_PR:-12}" "$s" "$merged" "$ms" "$mc" "$hsha" "${FAKE_GH_HEAD_REF:-feat/x}" "$hr" "${FAKE_GH_BASE_REF:-main}" "$1"
}
if [ "$1" = pr ]; then
  case "$2" in
    merge) case " $* " in *" --auto "*) ;; *) graphql_403; exit 1 ;; esac ;;
    *) graphql_403; exit 1 ;;
  esac
fi
if [ "$1" = api ]; then
  shift; method=GET; apath=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -X|--method) method="$2"; shift ;;
      -f|-F|--field|--raw-field|-H|--header|--jq|-q|--template|-t|--input) shift ;;
      -*) ;;
      *) [ -n "$apath" ] || apath="$1" ;;
    esac
    shift
  done
  case "$apath" in
    graphql) failing graphql && exit 1; echo '{"data":{"repository":{"id":"R_kgFake"}}}'; exit 0 ;;
    repos/*/actions/runs*) failing runs && exit 1; echo '{"total_count":0,"workflow_runs":[]}'; exit 0 ;;
    repos/*/pulls/*/merge)
      [ "$method" = PUT ] || exit 0
      n="${apath#*/pulls/}"; n="${n%%/*}"
      failing merge && exit 1
      for c in 405 409 422; do failing "merge$c" && { echo "gh: HTTP $c (simulated merge refusal)" >&2; exit 1; }; done
      do_merge "$n" || exit 1
      printf '{"sha":"%s","merged":true,"message":"Pull Request successfully merged"}\n' "$(git -C "${FAKE_ORIGIN_GIT:-/nonexistent}" rev-parse main 2>/dev/null)"; exit 0 ;;
    repos/*/pulls/*)
      [ "$method" = GET ] || exit 0
      n="${apath##*/pulls/}"
      case "$n" in '' | *[!0123456789]*) exit 0 ;; esac
      failing prview && exit 1
      r="${apath#repos/}"; r="${r%%/pulls/*}"
      pr_json "$r"; exit 0 ;;
    repos/*/git/refs/heads/*)
      [ "$method" = DELETE ] || exit 0
      failing delete && exit 1
      exit 0 ;;
  esac
  exit 0   # any other gh api path (release.sh reads repos/O/R/commits/SHA/check-runs): nothing
fi
case "$1 $2" in
  "pr merge")   # only --auto gets here (checked above): GitHub arms the merge for later; nothing reaches origin's main now
    failing graphql && exit 1
    failing merge && exit 1
    echo "merge-at $(git rev-parse --abbrev-ref HEAD 2>&1)" >> "$FAKE_LOG"
    echo "Pull request #$3 will be automatically merged when all requirements are met"; exit 0 ;;
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
# ---- stub tools/release-gate.sh (v0.32.0 AC9): logs its arguments; exit code $FAKE_GATE_RC (default 0); on a failure prints $FAKE_GATE_MSG ----
cat > "$W/gate.stub" <<'EOF'
#!/usr/bin/env bash
echo "release-gate.sh $*" >> "$FAKE_LOG"
if [ "${FAKE_GATE_RC:-0}" != 0 ]; then
  echo "${FAKE_GATE_MSG:-gate stub: no passing result}"
  echo "${FAKE_GATE_MSG:-gate stub: no passing result}" >&2
fi
exit "${FAKE_GATE_RC:-0}"
EOF
chmod +x "$BIN/gh" "$W/gate.stub" "$W/release.stub" "$W/install.stub" "$W/ci.stub"

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
  cp -p "$W/gate.stub" "$F/repo/tools/release-gate.sh"
  cp -p "$W/install.stub" "$F/repo/install.sh"
  cp -p "$W/ci.stub" "$F/repo/tools/ci-tree-tested.sh"
  printf '1.2.3\n' > "$F/repo/VERSION"
  ( cd "$F/repo" && git symbolic-ref HEAD refs/heads/main && git add -A &&
    GITID commit -qm init && git push -q -u origin main 2>/dev/null &&
    git switch -q -c feat/x &&
    git push -q origin feat/x:refs/heads/feat/x feat/x:refs/pull/12/head 2>/dev/null ) || { echo "fixture setup failed"; exit 3; }
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
  export FAKE_LOG="$F/log" FAKE_ORIGIN_WORK="$F/work" FAKE_ORIGIN_GIT="$F/origin.git" FAKE_GATE_RC=0 FAKE_GATE_MSG="" FAKE_GH_STATE=OPEN FAKE_GH_MERGE_STATE=CLEAN FAKE_GH_FAIL=""
  export PB_GATE_REPO=o/r   # T11: the repo ship talks to; the REST paths in the log are repos/o/r/...
  unset GH_REPO FAKE_GH_HEAD_REPO FAKE_GH_HEAD_REF FAKE_GH_BASE_REF
  : > "$F/log.ghrepo"
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
    # T11: the PR read is `gh api repos/O/R/pulls/N` (GET), the direct merge is `gh api -X PUT repos/O/R/pulls/N/merge`; --auto still uses `gh pr merge`
    /^gh api / && /\/pulls\/[0-9]+\/merge/ && /(-X|--method)[ =]PUT/ { print "merge"; next }
    /^gh api / && /\/pulls\/[0-9]+( |$)/ && !/(-X|--method)[ =](PUT|DELETE|PATCH)/ { print "view"; next }
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
# v0.32.0 AC9 helpers
# merge_call -> the logged gh pr merge call without a --match-head-commit <sha> pair (AC12 asserts that pair in test-ship-d.sh)
# T11: also the direct merge, `gh api -X PUT repos/o/r/pulls/N/merge -f merge_method=merge -f sha=<head>`, printed without its `-f sha=<sha>` pair
merge_call() { grep -E '^gh pr merge|^gh api .*(-X|--method)[ =]PUT .*/pulls/[0-9]+/merge' "$FAKE_LOG" | sed -e 's/ --match-head-commit [0-9a-fA-F]*//' -e 's/ -f sha=[0-9a-fA-F]*//'; }
# T11 helpers: how many merges were attempted (a PUT merge or a gh pr merge), the PUT merge lines, the GET lines of the PR, the ref DELETE lines
merges_logged() { grep -cE '^gh pr merge|^gh api .*(-X|--method)[ =]PUT .*/pulls/[0-9]+/merge' "$FAKE_LOG" 2>/dev/null || true; }
put_lines() { grep -E '^gh api .*(-X|--method)[ =]PUT .*/pulls/[0-9]+/merge' "$FAKE_LOG" || true; }
del_lines() { grep -E '^gh api .*(-X|--method)[ =]DELETE ' "$FAKE_LOG" || true; }
pr_gets() { grep -E '^gh api ' "$FAKE_LOG" | grep -E '/pulls/[0-9]+( |$)' | grep -vE -- '(-X|--method)[ =](PUT|DELETE|PATCH)' || true; }
PUT_CALL="gh api -X PUT repos/o/r/pulls/12/merge -f merge_method=merge"   # merge_call of a direct merge of PR 12 in repo o/r
gate_calls() { grep '^release-gate.sh' "$FAKE_LOG"; }
pr_head() { git -C "$F/origin.git" rev-parse -q --verify "refs/pull/${FAKE_PR:-12}/head" 2>/dev/null || git -C "$F/origin.git" rev-parse refs/heads/feat/x; }
# origin_advance -> origin's main moves on (a commit made through the work clone); the repo's origin/main is NOT refreshed
origin_advance() {
  ( cd "$F/work" && git pull -q --ff-only origin main >/dev/null 2>&1 &&
    echo moved > main-moved.txt && git add -A && GITID commit -qm "main moved" &&
    git push -q origin HEAD:main >/dev/null 2>&1 ) || { echo "fixture setup failed: origin_advance"; exit 3; }
}
# pr_on_new_main -> the PR head (origin refs/pull/N/head) is a commit ON TOP of origin's current main
pr_on_new_main() {
  ( cd "$F/work" && git fetch -q origin && git switch -q -C prb origin/main 2>/dev/null && echo prfile > pr-file.txt && git add -A && GITID commit -qm "pr commit" &&
    git push -q -f origin "HEAD:refs/pull/${FAKE_PR:-12}/head" >/dev/null 2>&1 && git switch -q main ) || { echo "fixture setup failed: pr_on_new_main"; exit 3; }
}
# pr_ahead -> the PR head has one commit of its own on top of the init commit (main did not move)
pr_ahead() {
  ( cd "$F/repo" && echo prfile > pr-file.txt && git add -A && GITID commit -qm "pr commit" &&
    git push -q -f origin "HEAD:refs/pull/${FAKE_PR:-12}/head" feat/x:refs/heads/feat/x >/dev/null 2>&1 ) || { echo "fixture setup failed: pr_ahead"; exit 3; }
}
origin_merges() { git -C "$F/origin.git" ls-tree -r --name-only main | grep -c '^merged-'; }
shard_calls() { grep '^gh run list .*--branch main ' "$FAKE_LOG"; }
unb() { printf '%s\n' "$OUT" | grep -c 'shards unbalanced'; }
