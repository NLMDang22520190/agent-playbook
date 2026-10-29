#!/usr/bin/env bash
# Tests for tools/ci-tree-tested.sh (v0.22.3 AC6.1): was the tree of a main commit already tested by a green PR run?
#   tools/ci-tree-tested.sh SHA [--repo OWNER/NAME]    prints a run id or nothing; exit 0 either way, 2 usage
# gh api only. A fake `gh` serves the exact API paths of the spec from files; every call is logged, so the bounds
# (at most 5 PRs, at most 10 runs) and the paths are asserted from the log. No network, no real repository.
# Split in v0.24.1: the bounds (at most 10 runs), the base ref, review lows and the AC5.3 step checks are in test-ci-tree-tested-steps.sh;
# shared setup: ci-tree-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/ci-tree-fixture.sh"

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

echo "AC6.1 each of the thirteen required jobs: skipped, missing or failed -> nothing"
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
put "repos/$R/actions/runs/111/jobs" "$(jobs_json ok | sed 's/"windows shard 8\/8"/"windows shard 8\/9"/')"
tool "$SHA" --repo "$R"
nothing "shard 8/8 missing (only an 8/9 shard)"
world
put "repos/$R/actions/runs/111/jobs" "$(jobs_json ok | sed -e 's/{"name":"windows shard 5\/8"[^]]*\]}/{"name":"unrelated","status":"completed","conclusion":"success"}/' -e 's/{"name":"windows shard 6\/8"[^]]*\]}/{"name":"unrelated 2","status":"completed","conclusion":"success"}/' -e 's/{"name":"windows shard 7\/8"[^]]*\]}/{"name":"unrelated 3","status":"completed","conclusion":"success"}/' -e 's/{"name":"windows shard 8\/8"[^]]*\]}/{"name":"unrelated 4","status":"completed","conclusion":"success"}/' -e 's/"windows shard 1\/8"/"windows shard 1\/4"/' -e 's/"windows shard 2\/8"/"windows shard 2\/4"/' -e 's/"windows shard 3\/8"/"windows shard 3\/4"/' -e 's/"windows shard 4\/8"/"windows shard 4\/4"/')"
assert_not_contains "AC2 the transition fixture has no 5/8, 6/8, 7/8 or 8/8 job left" "$(cat "$DATA/repos_${R//\//_}_actions_runs_111_jobs")" '"windows shard 5/8"'
assert_contains "AC2 the transition fixture carries the old shard names" "$(cat "$DATA/repos_${R//\//_}_actions_runs_111_jobs")" '"windows shard 4/4"'
tool "$SHA" --repo "$R"
nothing "only the old 1/4, 2/4, 3/4, 4/4 shards (the transition: a PR run of the four-shard workflow is never reused)"
echo "v0.28.0 a PR run of the six-shard workflow (windows shard 1/6 .. 6/6, all green, no 7/8 or 8/8) is never reused"
world
put "repos/$R/actions/runs/111/jobs" "$(jobs_json ok | sed -e 's/{"name":"windows shard 7\/8"[^]]*\]}/{"name":"unrelated","status":"completed","conclusion":"success"}/' -e 's/{"name":"windows shard 8\/8"[^]]*\]}/{"name":"unrelated 2","status":"completed","conclusion":"success"}/' -e 's/"windows shard \([1-6]\)\/8"/"windows shard \1\/6"/g')"
SIXJ="$(cat "$DATA/repos_${R//\//_}_actions_runs_111_jobs")"
assert_contains "v0.28.0 the six-shard fixture carries windows shard 1/6" "$SIXJ" '"windows shard 1/6"'
assert_contains "v0.28.0 the six-shard fixture carries windows shard 6/6" "$SIXJ" '"windows shard 6/6"'
assert_not_contains "v0.28.0 the six-shard fixture has no /8 shard left" "$SIXJ" '/8"'
tool "$SHA" --repo "$R"
nothing "only the old 1/6 .. 6/6 shards (a PR run of the six-shard workflow is never reused)"
echo "v0.30.0 a PR run of the seven-shard workflow (windows shard 1/7 .. 7/7, all green, no 8/8) is never reused"
world
put "repos/$R/actions/runs/111/jobs" "$(jobs_json ok | sed -e 's/{"name":"windows shard 8\/8"[^]]*\]}/{"name":"unrelated","status":"completed","conclusion":"success"}/' -e 's/"windows shard \([1-7]\)\/8"/"windows shard \1\/7"/g')"
SEVENJ="$(cat "$DATA/repos_${R//\//_}_actions_runs_111_jobs")"
assert_contains "v0.30.0 the seven-shard fixture carries windows shard 1/7" "$SEVENJ" '"windows shard 1/7"'
assert_contains "v0.30.0 the seven-shard fixture carries windows shard 7/7" "$SEVENJ" '"windows shard 7/7"'
assert_not_contains "v0.30.0 the seven-shard fixture has no /8 shard left" "$SEVENJ" '/8"'
tool "$SHA" --repo "$R"
nothing "only the old 1/7 .. 7/7 shards (a PR run of the seven-shard workflow is never reused)"
echo "AC2 shard 7/8 failed, shard 8/8 skipped or on the docs-only step -> nothing; all eight green -> reused"
world; put "repos/$R/actions/runs/111/jobs" "$(jobs_json failure 'windows shard 7/8')"
tool "$SHA" --repo "$R"
nothing "shard 7/8 failed"
world; put "repos/$R/actions/runs/111/jobs" "$(jobs_json skipped 'windows shard 8/8')"
tool "$SHA" --repo "$R"
nothing "shard 8/8 skipped"
world; put "repos/$R/actions/runs/111/jobs" "$(jobs_json steps 'windows shard 8/8' docsonly)"
tool "$SHA" --repo "$R"
nothing "shard 8/8 ran only the docs-only step"
world
tool "$SHA" --repo "$R"
assert_eq "AC2 all eight shards green: the run is reused" "111" "$OUT"

echo "v0.24.21 AC2 the two macOS shards: failed, skipped or missing -> nothing; the old single macOS job (no shards) is never reused"
world; put "repos/$R/actions/runs/111/jobs" "$(jobs_json failure 'macos shard 2/2')"
tool "$SHA" --repo "$R"
nothing "macOS shard 2/2 failed"
world; put "repos/$R/actions/runs/111/jobs" "$(jobs_json failure 'macos shard 1/2')"
tool "$SHA" --repo "$R"
nothing "macOS shard 1/2 failed"
world; put "repos/$R/actions/runs/111/jobs" "$(jobs_json skipped 'macos shard 2/2')"
tool "$SHA" --repo "$R"
nothing "macOS shard 2/2 skipped"
world; put "repos/$R/actions/runs/111/jobs" "$(jobs_json missing 'macos shard 1/2')"
tool "$SHA" --repo "$R"
nothing "macOS shard 1/2 missing"
world
put "repos/$R/actions/runs/111/jobs" "$(jobs_json ok | sed -e 's/"macos shard 1\/2"/"macos shard 1\/3"/' -e 's/"macos shard 2\/2"/"macos shard 2\/3"/')"
assert_contains "v0.24.21 AC2 the wrong-macOS-shard fixture carries the renamed shards" "$(cat "$DATA/repos_${R//\//_}_actions_runs_111_jobs")" '"macos shard 2/3"'
tool "$SHA" --repo "$R"
nothing "only macOS shards named 1/3 and 2/3 (not the 1/2 and 2/2 the workflow runs)"
OLDMAC_JOBS="$(jobs_json_oldmac)"
assert_not_contains "v0.24.21 AC3b the old-shape fixture has no macOS shard job" "$OLDMAC_JOBS" '"macos shard'
assert_contains "v0.24.21 AC3b the old-shape fixture has the full step in the test (macos-latest) job" "$OLDMAC_JOBS" '{"name":"test (macos-latest)","status":"completed","conclusion":"success","steps":['
assert_contains "v0.24.21 AC3b the old-shape fixture still has the eight Windows shards" "$OLDMAC_JOBS" '"windows shard 8/8"'
world; put "repos/$R/actions/runs/111/jobs" "$OLDMAC_JOBS"
tool "$SHA" --repo "$R"
nothing "a suite-style test (macos-latest) with a full step and no macOS shards (a PR run of the pre-v0.24.21 workflow)"
world
tool "$SHA" --repo "$R"
assert_eq "v0.24.21 AC2 all thirteen jobs green (two macOS shards, aggregators without steps): the run is reused" "111" "$OUT"

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
put "repos/$R/actions/runs/2001/jobs" "$(jobs_json failure 'windows shard 2/8')"
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


t_summary
