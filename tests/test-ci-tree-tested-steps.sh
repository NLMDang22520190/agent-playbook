#!/usr/bin/env bash
# Tests for tools/ci-tree-tested.sh, part 2 of 2 (split from test-ci-tree-tested.sh in v0.24.1): the bound of 10 runs, the base ref of the merged PR,
# the review lows, the AC5.3 checks of the test steps, usage and option order. Shared setup: ci-tree-fixture.sh.
# gh api only. A fake `gh` serves the exact API paths from files; every call is logged. No network, no real repository.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/ci-tree-fixture.sh"

echo "AC6.1 bounds: at most 10 runs"
runsworld() { # PASSING-RUN-ID -> twelve candidate runs 2001..2012; only that one is fully green
  local i rl="" sep=""
  world
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    rl="$rl$sep$(run_json $((2000 + i)) "$HEAD")"; sep=","
    if [ "$((2000 + i))" = "$1" ]; then put "repos/$R/actions/runs/$((2000 + i))/jobs" "$(jobs_json ok)"
    else put "repos/$R/actions/runs/$((2000 + i))/jobs" "$(jobs_json skipped 'windows shard 1/6')"; fi
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

echo "AC5.3 the full test step must have succeeded in each of the eight suite jobs"
world
tool "$SHA" --repo "$R"
assert_eq "AC5.3 the fixtures carry steps: a full run is still reused" "111" "$OUT"
assert_contains "AC5.3 the fixture steps are in the jobs JSON (full step of the ubuntu job)" "$(jobs_json ok)" '"name":"Tests and static checks"'
assert_contains "AC5.3 the fixture steps are in the jobs JSON (shard step)" "$(jobs_json ok)" '"name":"Tests and static checks (shard)"'
SUITES=("test (ubuntu-latest)" "test (macos-latest)" "windows shard 1/6" "windows shard 2/6" "windows shard 3/6" "windows shard 4/6" "windows shard 5/6" "windows shard 6/6")
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
nothing "a docs-only run (all eight suite jobs reduced)"
echo "AC5.3 one shard reduced, the rest full -> nothing"
world; put "repos/$R/actions/runs/111/jobs" "$(jobs_json steps 'windows shard 2/6' docsonly)"
tool "$SHA" --repo "$R"
nothing "only shard 2/6 reduced"
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
