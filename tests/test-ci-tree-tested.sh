#!/usr/bin/env bash
# Tests for tools/ci-tree-tested.sh (v0.22.3 AC6.1): was the tree of a main commit already tested by a green PR run?
#   tools/ci-tree-tested.sh SHA [--repo OWNER/NAME]    prints a run id or nothing; exit 0 either way, 2 usage
# gh api only. A fake `gh` serves the exact API paths of the spec from files; every call is logged, so the bounds
# (at most 5 PRs, at most 10 runs) and the paths are asserted from the log. No network, no real repository.
. "$(dirname "$0")/lib.sh"
TOOL="$PB_ROOT/tools/ci-tree-tested.sh"

W="$(mk_tmp)"; BIN="$W/bin"; DATA="$W/data"; LOG="$W/log"; mkdir -p "$BIN" "$DATA"

# ---- fake gh: `gh api repos/...[?query]` answered from $FAKE_DATA/<path with / as _>[_hs_<head_sha>] ----
# FAKE_FAIL=<text>: a request whose path contains <text> exits 1 (HTTP error); FAKE_BAD=<text>: prints text that is not JSON.
# --jq / -q are applied with jq when jq exists, else ignored (the whole JSON is printed).
cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >> "$FAKE_LOG"
[ "${1:-}" = api ] || { echo "fake gh: only 'gh api' is allowed, got: $*" >&2; exit 1; }
path=""; expr=""; prev=""
for a in "$@"; do
  case "$a" in repos/* | /repos/*) path="${a#/}" ;; esac
  case "$prev" in --jq | -q) expr="$a" ;; esac
  prev="$a"
done
[ -n "$path" ] || { echo "fake gh: no repos/ path in: $*" >&2; exit 1; }
if [ -n "${FAKE_FAIL:-}" ]; then case "$path" in *"$FAKE_FAIL"*) echo "gh: HTTP 500 (simulated)" >&2; exit 1 ;; esac; fi
if [ -n "${FAKE_BAD:-}" ]; then case "$path" in *"$FAKE_BAD"*) echo '{"this is": not json,'; exit 0 ;; esac; fi
key="${path%%\?*}"
f="$(printf '%s' "$key" | tr '/' '_')"
case "$path" in *head_sha=*) hs="${path#*head_sha=}"; hs="${hs%%&*}"; f="${f}_hs_$hs" ;; esac
[ -f "$FAKE_DATA/$f" ] || { echo "gh: HTTP 404 Not Found ($path)" >&2; exit 1; }
if [ -n "$expr" ] && command -v jq >/dev/null 2>&1; then jq -r "$expr" < "$FAKE_DATA/$f"; else cat "$FAKE_DATA/$f"; fi
EOF
chmod +x "$BIN/gh"

R="own/repo"
h40() { printf '%040d' "$1"; }          # 40 digits are a valid hex sha
SHA="$(h40 1)"; PAR="$(h40 2)"; HEAD="$(h40 3)"; TREE="$(h40 4)"
NAMES=("test (ubuntu-latest)" "test (macos-latest)" "test (windows-latest)" "windows shard 1/4" "windows shard 2/4" "windows shard 3/4" "windows shard 4/4")

# put KEYPATH JSON -> the response of `gh api <KEYPATH>` (query string left out; runs also by head sha: use put_runs)
put() { printf '%s\n' "$2" | tr -d '\r' > "$DATA/$(printf '%s' "$1" | tr '/' '_')"; }
put_runs() { put_raw "repos/$R/actions/workflows/test.yml/runs" "$1" "$2"; }
put_raw() { printf '%s\n' "$3" > "$DATA/$(printf '%s' "$1" | tr '/' '_')_hs_$2"; }
pull_json() { # NUMBER HEADSHA [REPO] [BASEREF]  (REPO "null" = a deleted head repository; the PR is closed: it is merged)
  local b="${4:-main}"
  if [ "${3:-}" = null ]; then printf '{"number":%s,"state":"closed","base":{"ref":"%s"},"head":{"sha":"%s","repo":null}}' "$1" "$b" "$2"
  else printf '{"number":%s,"state":"closed","base":{"ref":"%s"},"head":{"sha":"%s","repo":{"full_name":"%s"}}}' "$1" "$b" "$2" "${3:-$R}"; fi
}
run_json() { # ID HEADSHA [CONCLUSION] [LISTED-BASEREF]  (pull_requests[] is empty: GitHub lists only OPEN PRs there)
  local prs='[]'
  [ -n "${4:-}" ] && prs="[{\"number\":7,\"base\":{\"ref\":\"$4\"}}]"
  printf '{"id":%s,"head_sha":"%s","event":"pull_request","status":"completed","conclusion":"%s","pull_requests":%s}' "$1" "$2" "${3:-success}" "$prs"
}
runs_json() { printf '{"total_count":%s,"workflow_runs":[%s]}' "$1" "$2"; }
jobs_json() { # MODE NAME [STEPKIND]: MODE ok (all seven success) | skipped|failure|cancelled NAME | missing NAME
  # | steps NAME STEPKIND: the jobs are all success; NAME's step list is changed (v0.23.0 AC5.3):
  #   docsonly (only a Docs-only checks step), both (full step skipped + Docs-only success), fullskipped (full step skipped, no other),
  #   fullfailed (full step failure), fullmissing (setup steps only), nosteps (no steps field), fullcancelled, fullnotdone
  # Every other suite job has the full step with conclusion success.
  local mode="${1:-ok}" bad="${2:-}" kind="${3:-}" out="" sep="" n c st steps
  for n in "${NAMES[@]}"; do
    c=success
    if [ "$n" = "$bad" ]; then
      case "$mode" in missing) continue ;; steps) ;; *) c="$mode" ;; esac
    fi
    st=completed
    if [ "$n" = "$bad" ] && [ "$mode" = notcompleted ]; then c=success; st=in_progress; fi
    steps="$(steps_json "$n" "$([ "$n" = "$bad" ] && [ "$mode" = steps ] && echo "$kind" || echo full)")"
    out="$out$sep{\"name\":\"$n\",\"status\":\"$st\",\"conclusion\":\"$c\"$steps}"; sep=","
  done
  # jobs that are not required checks never matter (the PR run skips reuse and main-ci)
  out="$out$sep{\"name\":\"reuse\",\"status\":\"completed\",\"conclusion\":\"skipped\"},{\"name\":\"main-ci\",\"status\":\"completed\",\"conclusion\":\"skipped\"}"
  printf '{"total_count":8,"jobs":[%s]}' "$out"
}
# step_one NAME CONCLUSION NUMBER [STATUS]
step_one() { printf '{"name":"%s","status":"%s","conclusion":"%s","number":%s}' "$1" "${4:-completed}" "$2" "$3"; }
# steps_json JOBNAME KIND -> ,"steps":[...] for the six suite jobs (the aggregator has none), "" for others
steps_json() {
  local n="$1" kind="$2" full='Tests and static checks' pre
  case "$n" in "test (windows-latest)") return 0 ;; "windows shard "*) full='Tests and static checks (shard)' ;; esac
  pre="$(step_one 'Set up job' success 1),$(step_one 'Run actions/checkout@v5' success 2)"
  case "$kind" in
    full)        printf ',"steps":[%s,%s]' "$pre" "$(step_one "$full" success 3)" ;;
    docsonly)    printf ',"steps":[%s,%s]' "$pre" "$(step_one 'Docs-only checks' success 3)" ;;
    both)        printf ',"steps":[%s,%s,%s]' "$pre" "$(step_one "$full" skipped 3)" "$(step_one 'Docs-only checks' success 4)" ;;
    fullskipped) printf ',"steps":[%s,%s]' "$pre" "$(step_one "$full" skipped 3)" ;;
    fullfailed)  printf ',"steps":[%s,%s]' "$pre" "$(step_one "$full" failure 3)" ;;
    fullcancelled) printf ',"steps":[%s,%s]' "$pre" "$(step_one "$full" cancelled 3)" ;;
    fullnotdone) printf ',"steps":[%s,%s]' "$pre" "$(step_one "$full" success 3 in_progress)" ;;
    fullmissing) printf ',"steps":[%s]' "$pre" ;;
    nosteps)     return 0 ;;
  esac
}
commit_json() { printf '{"sha":"%s","tree":{"sha":"%s"},"parents":[{"sha":"%s"}]}' "$1" "$2" "$3"; }
compare_json() { printf '{"status":"%s","ahead_by":1,"behind_by":%s}' "$1" "$2"; }

# world -> the happy path: merge commit SHA of a same-repo PR (head HEAD) whose run 111 was green; same tree; parent is an ancestor of HEAD
world() {
  rm -rf "$DATA"; mkdir -p "$DATA"; : > "$LOG"
  put "repos/$R/commits/$SHA/pulls" "[$(pull_json 7 "$HEAD")]"
  put_runs "$HEAD" "$(runs_json 1 "$(run_json 111 "$HEAD")")"
  put "repos/$R/actions/runs/111/jobs" "$(jobs_json ok)"
  put "repos/$R/git/commits/$SHA" "$(commit_json "$SHA" "$TREE" "$PAR")"
  put "repos/$R/git/commits/$HEAD" "$(commit_json "$HEAD" "$TREE" "$PAR")"
  put "repos/$R/compare/$PAR...$HEAD" "$(compare_json ahead 0)"
}
# tool ARGS... -> OUT = stdout only, RC = exit code; the fake gh is first on PATH
tool() {
  OUT="$(PATH="$BIN:$PATH" FAKE_DATA="$DATA" FAKE_LOG="$LOG" bash "$TOOL" "$@" 2>/dev/null)"; RC=$?
}
logged() { grep -cF -- "$1" "$LOG" 2>/dev/null || true; }
nothing() { # NAME -> exit 0 and empty stdout
  assert_rc "AC6.1 $1: exit 0" 0
  assert_eq "AC6.1 $1: prints nothing" "" "$OUT"
}

echo "AC6.1 the tool exists"
assert_file "AC6.1 tools/ci-tree-tested.sh exists" "$TOOL"

echo "AC6.1 happy path"
world
tool "$SHA" --repo "$R"
assert_rc "AC6.1 happy path: exit 0" 0
assert_eq "AC6.1 happy path: prints the run id" "111" "$OUT"
assert_eq "AC6.1 every gh call is 'gh api' (never logs, artifacts, run list or job outputs)" "0" "$(grep -vc '^gh api ' "$LOG" || true)"
assert_eq "AC6.1 step 1: the pulls of the commit are listed" "1" "$(logged "repos/$R/commits/$SHA/pulls")"
RUNSLINE="$(grep -F "repos/$R/actions/workflows/test.yml/runs" "$LOG" | head -n 1)"
assert_contains "AC6.1 step 3: the runs call is for event=pull_request" "$RUNSLINE" "event=pull_request"
assert_contains "AC6.1 step 3: the runs call is for the PR head sha" "$RUNSLINE" "head_sha=$HEAD"
assert_contains "AC6.1 step 3: the runs call asks for status=success" "$RUNSLINE" "status=success"
assert_contains "AC6.1 step 3: the runs call has per_page=10" "$RUNSLINE" "per_page=10"
JOBSLINE="$(grep -F "repos/$R/actions/runs/111/jobs" "$LOG" | head -n 1)"
[ -n "$JOBSLINE" ] && t_ok "AC6.1 step 4: the jobs of run 111 are read" || t_bad "AC6.1 step 4: the jobs of run 111 are read" "$(cat "$LOG")"
assert_contains "AC6.1 step 4: the jobs call has filter=latest" "$JOBSLINE" "filter=latest"
assert_contains "AC6.1 step 4: the jobs call has per_page=100" "$JOBSLINE" "per_page=100"
assert_eq "AC6.1 step 5: the commit of SHA is read" "1" "$(logged "repos/$R/git/commits/$SHA")"
assert_eq "AC6.1 step 5: the commit of the PR head is read" "1" "$(logged "repos/$R/git/commits/$HEAD")"
assert_eq "AC6.1 step 6: the first parent is compared with the PR head (compare/P...H)" "1" "$(logged "repos/$R/compare/$PAR...$HEAD")"

echo "AC6.1 compare: ahead or identical with behind_by 0 pass"
world; put "repos/$R/compare/$PAR...$HEAD" "$(compare_json identical 0)"
tool "$SHA" --repo "$R"
assert_eq "AC6.1 compare identical, behind_by 0: prints the run id" "111" "$OUT"
world; put "repos/$R/compare/$PAR...$HEAD" "$(compare_json ahead 0)"
tool "$SHA" --repo "$R"
assert_eq "AC6.1 compare ahead, behind_by 0: prints the run id" "111" "$OUT"

echo "AC6.1 a fork PR is skipped"
world; put "repos/$R/commits/$SHA/pulls" "[$(pull_json 7 "$HEAD" "fork/repo")]"
tool "$SHA" --repo "$R"
nothing "a fork PR"
assert_eq "AC6.1 a fork PR: its runs are never looked up" "0" "$(logged "head_sha=$HEAD")"
world; put "repos/$R/commits/$SHA/pulls" "[$(pull_json 7 "$(h40 50)" "fork/repo"),$(pull_json 8 "$HEAD")]"
tool "$SHA" --repo "$R"
assert_eq "AC6.1 a fork PR first, a same-repo PR second: the second one is used" "111" "$OUT"
assert_eq "AC6.1 ... and the fork PR's head sha was never queried" "0" "$(logged "head_sha=$(h40 50)")"

echo "AC6.1 a run that is not success"
for c in failure cancelled skipped timed_out neutral; do
  world; put_runs "$HEAD" "$(runs_json 1 "$(run_json 111 "$HEAD" "$c")")"
  tool "$SHA" --repo "$R"
  nothing "a run concluded $c"
done
world; put_runs "$HEAD" "$(runs_json 1 '{"id":111,"head_sha":"'"$HEAD"'","event":"pull_request","status":"in_progress","conclusion":null}')"
tool "$SHA" --repo "$R"
nothing "a run still in progress"
world; put_runs "$HEAD" "$(runs_json 0 "")"
tool "$SHA" --repo "$R"
nothing "no candidate runs"

echo "AC6.1 each of the seven required jobs: skipped, missing or failed -> nothing"
for n in "${NAMES[@]}"; do
  for mode in skipped missing failure cancelled; do
    world; put "repos/$R/actions/runs/111/jobs" "$(jobs_json "$mode" "$n")"
    tool "$SHA" --repo "$R"
    nothing "job [$n] $mode"
  done
done
world; put "repos/$R/actions/runs/111/jobs" '{"total_count":0,"jobs":[]}'
tool "$SHA" --repo "$R"
nothing "a run with no jobs"
world
put "repos/$R/actions/runs/111/jobs" "$(jobs_json ok | sed 's/"windows shard 4\/4"/"windows shard 4\/5"/')"
tool "$SHA" --repo "$R"
nothing "shard 4/4 missing (only a 4/5 shard)"
world
put "repos/$R/actions/runs/111/jobs" "$(jobs_json ok | sed -e 's/"windows shard 1\/4"/"windows shard 1\/3"/' -e 's/"windows shard 2\/4"/"windows shard 2\/3"/' -e 's/"windows shard 3\/4"/"windows shard 3\/3"/' -e 's/{"name":"windows shard 4\/4"[^]]*\]}/{"name":"unrelated","status":"completed","conclusion":"success"}/')"
tool "$SHA" --repo "$R"
nothing "only the old 1/3, 2/3, 3/3 shards (fail-closed)"

echo "AC6.1 the trees must be equal"
world; put "repos/$R/git/commits/$HEAD" "$(commit_json "$HEAD" "$(h40 99)" "$PAR")"
tool "$SHA" --repo "$R"
nothing "tree mismatch"
world; put "repos/$R/git/commits/$SHA" "$(commit_json "$SHA" "$(h40 98)" "$PAR")"
tool "$SHA" --repo "$R"
nothing "tree mismatch (the merge commit differs)"

echo "AC6.1 the first parent must be an ancestor of the PR head"
for pair in "diverged 0" "behind 3" "diverged 2" "ahead 1" "identical 1"; do
  st="${pair% *}"; bb="${pair#* }"
  world; put "repos/$R/compare/$PAR...$HEAD" "$(compare_json "$st" "$bb")"
  tool "$SHA" --repo "$R"
  case "$st/$bb" in
    diverged/0) nothing "compare $st (a rebase merge: the parent is a rebased commit)" ;;
    *) nothing "compare $st with behind_by $bb" ;;
  esac
done
world; put "repos/$R/compare/$PAR...$HEAD" "$(compare_json behind 0)"
tool "$SHA" --repo "$R"
nothing "compare status behind"

echo "AC6.1 a gh error anywhere -> nothing printed, exit 0"
for part in "/commits/$SHA/pulls" "workflows/test.yml/runs" "/runs/111/jobs" "git/commits/$SHA" "git/commits/$HEAD" "compare/"; do
  world
  OUT="$(PATH="$BIN:$PATH" FAKE_DATA="$DATA" FAKE_LOG="$LOG" FAKE_FAIL="$part" bash "$TOOL" "$SHA" --repo "$R" 2>/dev/null)"; RC=$?
  nothing "a gh error on [$part]"
done
echo "AC6.1 malformed JSON anywhere -> nothing printed, exit 0"
for part in "/commits/$SHA/pulls" "workflows/test.yml/runs" "/runs/111/jobs" "git/commits/$SHA" "git/commits/$HEAD" "compare/"; do
  world
  OUT="$(PATH="$BIN:$PATH" FAKE_DATA="$DATA" FAKE_LOG="$LOG" FAKE_BAD="$part" bash "$TOOL" "$SHA" --repo "$R" 2>/dev/null)"; RC=$?
  nothing "malformed JSON from [$part]"
done
echo "AC6.1 JSON of the wrong shape -> nothing"
world; put "repos/$R/commits/$SHA/pulls" '{"message":"Not Found"}'
tool "$SHA" --repo "$R"; nothing "pulls answered with an object"
world; put "repos/$R/commits/$SHA/pulls" '[]'
tool "$SHA" --repo "$R"; nothing "a commit with no pull request (direct push)"
world; put "repos/$R/commits/$SHA/pulls" '[{"number":7}]'
tool "$SHA" --repo "$R"; nothing "a PR without head data"
world; put_runs "$HEAD" '{"workflow_runs":"x"}'
tool "$SHA" --repo "$R"; nothing "workflow_runs of the wrong type"
world; put "repos/$R/actions/runs/111/jobs" '{"jobs":"x"}'
tool "$SHA" --repo "$R"; nothing "jobs of the wrong type"
world; put "repos/$R/git/commits/$HEAD" '{"sha":"x"}'
tool "$SHA" --repo "$R"; nothing "a commit without a tree"
world; put "repos/$R/compare/$PAR...$HEAD" '{}'
tool "$SHA" --repo "$R"; nothing "a compare answer without a status"

echo "AC6.1 several candidate runs: the first passing run wins"
world
put_runs "$HEAD" "$(runs_json 3 "$(run_json 2001 "$HEAD"),$(run_json 2002 "$HEAD"),$(run_json 2003 "$HEAD")")"
put "repos/$R/actions/runs/2001/jobs" "$(jobs_json failure 'windows shard 2/4')"
put "repos/$R/actions/runs/2002/jobs" "$(jobs_json ok)"
put "repos/$R/actions/runs/2003/jobs" "$(jobs_json ok)"
tool "$SHA" --repo "$R"
assert_eq "AC6.1 run 2001 fails a job, 2002 and 2003 pass: prints 2002" "2002" "$OUT"
world
put_runs "$HEAD" "$(runs_json 2 "$(run_json 2001 "$HEAD"),$(run_json 2002 "$HEAD")")"
put "repos/$R/actions/runs/2001/jobs" "$(jobs_json ok)"
put "repos/$R/actions/runs/2002/jobs" "$(jobs_json ok)"
tool "$SHA" --repo "$R"
assert_eq "AC6.1 two passing runs: the first (newest) is printed" "2001" "$OUT"
assert_eq "AC6.1 the output is one run id and nothing else (one line)" "1" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
world
put_runs "$HEAD" "$(runs_json 2 "$(run_json 2001 "$HEAD" failure),$(run_json 2002 "$HEAD")")"
put "repos/$R/actions/runs/2002/jobs" "$(jobs_json ok)"
tool "$SHA" --repo "$R"
assert_eq "AC6.1 a non-success run first, a passing run second: prints the second" "2002" "$OUT"
echo "AC6.1 several PRs: the first PR that passes wins"
world
put "repos/$R/commits/$SHA/pulls" "[$(pull_json 7 "$(h40 11)"),$(pull_json 8 "$HEAD")]"
put_runs "$(h40 11)" "$(runs_json 1 "$(run_json 3001 "$(h40 11)")")"
put "repos/$R/actions/runs/3001/jobs" "$(jobs_json skipped 'test (macos-latest)')"
put "repos/$R/git/commits/$(h40 11)" "$(commit_json "$(h40 11)" "$TREE" "$PAR")"
put "repos/$R/compare/$PAR...$(h40 11)" "$(compare_json ahead 0)"
tool "$SHA" --repo "$R"
assert_eq "AC6.1 PR 7 fails its jobs, PR 8 passes: prints the run of PR 8" "111" "$OUT"

echo "AC6.1 bounds: at most 5 PRs"
bigworld() { # PASSING-INDEX -> seven PRs; only PR number PASSING-INDEX has a fully green run (run id 1000+i)
  local i pulls="" sep="" hi
  world
  for i in 1 2 3 4 5 6 7; do
    hi="$(h40 $((100 + i)))"
    pulls="$pulls$sep$(pull_json "$i" "$hi")"; sep=","
    put_runs "$hi" "$(runs_json 1 "$(run_json $((1000 + i)) "$hi")")"
    if [ "$i" = "$1" ]; then put "repos/$R/actions/runs/$((1000 + i))/jobs" "$(jobs_json ok)"
    else put "repos/$R/actions/runs/$((1000 + i))/jobs" "$(jobs_json failure 'test (ubuntu-latest)')"; fi
    put "repos/$R/git/commits/$hi" "$(commit_json "$hi" "$TREE" "$PAR")"
    put "repos/$R/compare/$PAR...$hi" "$(compare_json ahead 0)"
  done
  put "repos/$R/commits/$SHA/pulls" "[$pulls]"
}
bigworld 5
tool "$SHA" --repo "$R"
assert_eq "AC6.1 the fifth PR is still looked at: its run is printed" "1005" "$OUT"
bigworld 6
tool "$SHA" --repo "$R"
nothing "only the sixth PR passes (beyond the bound of 5)"
assert_eq "AC6.1 the sixth PR's runs were never requested" "0" "$(logged "head_sha=$(h40 106)")"
assert_eq "AC6.1 the seventh PR's runs were never requested" "0" "$(logged "head_sha=$(h40 107)")"
assert_eq "AC6.1 the fifth PR's runs were requested (5 PRs are examined)" "1" "$(logged "head_sha=$(h40 105)")"

echo "AC6.1 bounds: at most 10 runs"
runsworld() { # PASSING-RUN-ID -> twelve candidate runs 2001..2012; only that one is fully green
  local i rl="" sep=""
  world
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    rl="$rl$sep$(run_json $((2000 + i)) "$HEAD")"; sep=","
    if [ "$((2000 + i))" = "$1" ]; then put "repos/$R/actions/runs/$((2000 + i))/jobs" "$(jobs_json ok)"
    else put "repos/$R/actions/runs/$((2000 + i))/jobs" "$(jobs_json skipped 'windows shard 1/4')"; fi
  done
  put_runs "$HEAD" "$(runs_json 12 "$rl")"
}
runsworld 2010
tool "$SHA" --repo "$R"
assert_eq "AC6.1 the tenth run is still looked at: its id is printed" "2010" "$OUT"
runsworld 2011
tool "$SHA" --repo "$R"
nothing "only the eleventh run passes (beyond the bound of 10)"
assert_eq "AC6.1 the jobs of the eleventh run were never requested" "0" "$(logged "runs/2011/jobs")"
assert_eq "AC6.1 the jobs of the twelfth run were never requested" "0" "$(logged "runs/2012/jobs")"
assert_eq "AC6.1 the jobs of the tenth run were requested" "1" "$(logged "runs/2010/jobs")"

echo "AC6.1 D4: the base ref comes from the merged PR of step 1; the run's pull_requests (open PRs only) is not used"
world
tool "$SHA" --repo "$R"
assert_eq "AC6.1 a closed PR with base main whose run has pull_requests [] prints the run id" "111" "$OUT"
world; put "repos/$R/commits/$SHA/pulls" "[$(pull_json 7 "$HEAD" "$R" develop)]"
tool "$SHA" --repo "$R"
nothing "a PR whose base.ref is develop"
assert_eq "AC6.1 a PR based on develop: its runs are never queried" "0" "$(logged "head_sha=$HEAD")"
assert_eq "AC6.1 a PR based on develop: no jobs call either" "0" "$(logged "/jobs")"
world; put "repos/$R/commits/$SHA/pulls" "[$(pull_json 7 "$(h40 70)" "$R" develop),$(pull_json 8 "$HEAD")]"
tool "$SHA" --repo "$R"
assert_eq "AC6.1 a develop PR first, a main PR second: the second is used" "111" "$OUT"
assert_eq "AC6.1 ... and the develop PR's head sha was never queried" "0" "$(logged "head_sha=$(h40 70)")"
world; put_runs "$HEAD" "$(runs_json 1 "$(run_json 111 "$HEAD" success develop)")"
tool "$SHA" --repo "$R"
assert_eq "AC6.1 a run whose pull_requests lists a develop base, but whose PR from step 1 has base main: still reused (the run field is ignored)" "111" "$OUT"
world; put_runs "$HEAD" "$(runs_json 1 '{"id":111,"head_sha":"'"$HEAD"'","event":"pull_request","status":"completed","conclusion":"success"}')"
tool "$SHA" --repo "$R"
assert_eq "AC6.1 a run without a pull_requests field: still reused" "111" "$OUT"
world; put "repos/$R/commits/$SHA/pulls" '[{"number":7,"state":"closed","head":{"sha":"'"$HEAD"'","repo":{"full_name":"'"$R"'"}}}]'
tool "$SHA" --repo "$R"
nothing "a PR without a base ref"

echo "AC6.1 review lows: a deleted head repository"
world; put "repos/$R/commits/$SHA/pulls" "[$(pull_json 7 "$HEAD" null)]"
tool "$SHA" --repo "$R"
nothing "a PR whose head.repo is null"
assert_eq "AC6.1 a PR whose head.repo is null: its runs are never looked up" "0" "$(logged "head_sha=$HEAD")"
world; put "repos/$R/commits/$SHA/pulls" "[$(pull_json 7 "$(h40 60)" null),$(pull_json 8 "$HEAD")]"
tool "$SHA" --repo "$R"
assert_eq "AC6.1 a null-repo PR first, a same-repo PR second: the second is used" "111" "$OUT"

echo "AC6.1 review lows: a job that succeeded but did not complete"
for n in "${NAMES[@]}"; do
  world; put "repos/$R/actions/runs/111/jobs" "$(jobs_json notcompleted "$n")"
  tool "$SHA" --repo "$R"
  nothing "job [$n] conclusion success but status in_progress"
done

echo "AC6.1 review lows: a run row whose head_sha is not the PR head"
world; put_runs "$HEAD" "$(runs_json 1 "$(run_json 111 "$(h40 77)")")"
tool "$SHA" --repo "$R"
nothing "the only run row has another head_sha"
world; put_runs "$HEAD" "$(runs_json 2 "$(run_json 2001 "$(h40 77)"),$(run_json 2002 "$HEAD")")"
put "repos/$R/actions/runs/2001/jobs" "$(jobs_json ok)"
put "repos/$R/actions/runs/2002/jobs" "$(jobs_json ok)"
tool "$SHA" --repo "$R"
assert_eq "AC6.1 a row with another head_sha is ignored, the next row is used" "2002" "$OUT"
assert_eq "AC6.1 the ignored row's jobs were never read" "0" "$(logged "runs/2001/jobs")"

echo "AC5.3 the full test step must have succeeded in each of the six suite jobs"
world
tool "$SHA" --repo "$R"
assert_eq "AC5.3 the fixtures carry steps: a full run is still reused" "111" "$OUT"
assert_contains "AC5.3 the fixture steps are in the jobs JSON (full step of the ubuntu job)" "$(jobs_json ok)" '"name":"Tests and static checks"'
assert_contains "AC5.3 the fixture steps are in the jobs JSON (shard step)" "$(jobs_json ok)" '"name":"Tests and static checks (shard)"'
SUITES=("test (ubuntu-latest)" "test (macos-latest)" "windows shard 1/4" "windows shard 2/4" "windows shard 3/4" "windows shard 4/4")
for n in "${SUITES[@]}"; do
  for kind in docsonly both fullskipped fullfailed fullcancelled fullnotdone fullmissing nosteps; do
    world; put "repos/$R/actions/runs/111/jobs" "$(jobs_json steps "$n" "$kind")"
    tool "$SHA" --repo "$R"
    nothing "job [$n] steps: $kind (a reduced or missing full step is never reused)"
  done
done
echo "AC5.3 a docs-only run: every suite job reduced -> nothing"
world
dj="$(jobs_json ok)"
for n in "${SUITES[@]}"; do
  case "$n" in "windows shard "*) f='Tests and static checks (shard)' ;; *) f='Tests and static checks' ;; esac
  dj="$(printf '%s' "$dj" | sed "s#\"name\":\"$f\",\"status\":\"completed\",\"conclusion\":\"success\"#\"name\":\"Docs-only checks\",\"status\":\"completed\",\"conclusion\":\"success\"#")"
done
assert_contains "AC5.3 the docs-only fixture really has Docs-only steps" "$dj" '"name":"Docs-only checks"'
assert_not_contains "AC5.3 the docs-only fixture has no full step left" "$dj" '"name":"Tests and static checks'
put "repos/$R/actions/runs/111/jobs" "$dj"
tool "$SHA" --repo "$R"
nothing "a docs-only run (all six suite jobs reduced)"
echo "AC5.3 one shard reduced, the rest full -> nothing"
world; put "repos/$R/actions/runs/111/jobs" "$(jobs_json steps 'windows shard 2/4' docsonly)"
tool "$SHA" --repo "$R"
nothing "only shard 2/4 reduced"
echo "AC5.3 the aggregator (test (windows-latest)) needs only a success conclusion"
world
put "repos/$R/actions/runs/111/jobs" "$(jobs_json ok)"
assert_contains "AC5.3 the aggregator fixture has no steps (its object ends right after the conclusion)" "$(jobs_json ok)" '"name":"test (windows-latest)","status":"completed","conclusion":"success"}'
tool "$SHA" --repo "$R"
assert_eq "AC5.3 the aggregator without steps does not block a reuse" "111" "$OUT"
echo "AC5.3 a successful full step in the right job, an older run with a reduced one: the first full run wins"
world
put_runs "$HEAD" "$(runs_json 2 "$(run_json 2001 "$HEAD"),$(run_json 2002 "$HEAD")")"
put "repos/$R/actions/runs/2001/jobs" "$(jobs_json steps 'test (macos-latest)' docsonly)"
put "repos/$R/actions/runs/2002/jobs" "$(jobs_json ok)"
tool "$SHA" --repo "$R"
assert_eq "AC5.3 a docs-only run is skipped, the next full run is printed" "2002" "$OUT"

echo "AC6.1 usage: exit 2"
: > "$LOG"
tool
assert_rc "AC6.1 no arguments: exit 2" 2
assert_eq "AC6.1 no arguments: prints nothing on stdout" "" "$OUT"
tool --repo "$R"
assert_rc "AC6.1 --repo without a SHA: exit 2" 2
tool "$SHA" --repo
assert_rc "AC6.1 --repo without a value: exit 2" 2
tool "$SHA" --bogus
assert_rc "AC6.1 an unknown option: exit 2" 2
tool "$SHA" "$(h40 9)" --repo "$R"
assert_rc "AC6.1 two SHAs: exit 2" 2
tool "not-a-sha!" --repo "$R"
assert_rc "AC6.1 a SHA that is not hexadecimal: exit 2" 2
tool "$SHA" --repo "justaname"
assert_rc "AC6.1 --repo that is not OWNER/NAME: exit 2" 2
tool ""
assert_rc "AC6.1 an empty SHA: exit 2" 2
assert_eq "AC6.1 usage errors make no gh call" "0" "$(wc -l < "$LOG" | tr -d ' ')"
OUT="$(PATH="$BIN:$PATH" FAKE_DATA="$DATA" FAKE_LOG="$LOG" bash "$TOOL" 2>&1 >/dev/null)"
assert_contains "AC6.1 the usage message names the tool" "$OUT" "ci-tree-tested"

echo "AC6.1 the option order does not matter"
world
tool --repo "$R" "$SHA"
assert_eq "AC6.1 --repo before the SHA works" "111" "$OUT"

t_summary
