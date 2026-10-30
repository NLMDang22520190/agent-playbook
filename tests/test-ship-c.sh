#!/usr/bin/env bash
# Tests for tools/ship.sh (v0.11.0 AC6.1): the second half of test-ship.sh (split in v0.24.19 so that it is not the floor of a CI shard), from "v0.17.0 AC2.1 --auto: an OPEN PR that is not
# CLEAN yet gets GitHub auto-merge and ship stops without releasing" to the end (--auto, a PR already MERGED, the shard report on balanced and unbalanced runs; the rest of the shard report is in test-ship-b.sh).
# Everything is stubbed as in test-ship.sh; shared setup: ship-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/ship-fixture.sh"

# ---- v0.17.0: gh call shapes the tests fix (the implementer must use exactly these) ----
#  PR check:     gh pr view PR --json state,mergeStateStatus,mergeCommit --jq '...'   (gh prints mergeCommit as {"oid": "SHA"}, null until merged)
#  auto-merge:   gh pr merge PR --auto --merge --delete-branch     (exactly this argument order)
#  shard report: gh run list --branch main --event push --commit SHA --limit 1 --json databaseId [--jq ...]
#                gh run view RUN --json jobs                       (no --jq: parse the JSON with node, as tools/shard-weights.sh does)
#                jobs named "windows shard K/N" carry startedAt/completedAt; a job still running has completedAt 0001-01-01T00:00:00Z

echo "v0.17.0 AC2.1 --auto: an OPEN PR that is not CLEAN yet gets GitHub auto-merge and ship stops without releasing"
for st in BLOCKED UNSTABLE; do
  fx
  export FAKE_GH_MERGE_STATE="$st"
  sh_run 12 v1.2.3 --yes --auto
  assert_rc "AC2.1 OPEN/$st with --auto: exit 0" 0
  assert_eq "AC2.1 OPEN/$st with --auto: exactly one merge call, '$AUTO_MERGE_CALL'" "$AUTO_MERGE_CALL" "$(merge_call)"
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
assert_eq "AC2.1 --auto PR 345: the merge call carries PR 345" "gh pr merge 345 --auto --merge --delete-branch" "$(merge_call)"
assert_contains "AC2.1 --auto PR 345: the run-again command names PR 345 and v10.20.30" "$OUT" "tools/ship.sh 345 v10.20.30"
fx
export FAKE_GH_MERGE_STATE=BLOCKED
sh_run 12 v1.2.3 --auto --yes
assert_rc "AC2.1 '--auto --yes' (either order): exit 0" 0
assert_eq "AC2.1 '--auto --yes': one auto-merge call" "$AUTO_MERGE_CALL" "$(merge_call)"
echo "AC2.1 --auto on a CLEAN PR merges and releases as usual; without --auto a non-CLEAN PR is still refused"
fx
sh_run 12 v1.2.3 --yes --auto
assert_rc "AC2.1 CLEAN PR with --auto: exit 0" 0
assert_eq "AC2.1 CLEAN PR with --auto: the whole flow ran" "$FULL_YES" "$(steps)"
assert_eq "AC2.1 CLEAN PR with --auto: a plain merge call, no --auto in it" "gh pr merge 12 --merge --delete-branch" "$(merge_call)"
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
assert_eq "AC4.1/AC3.1 unbalanced: the jobs of that run are read twice, ship's own read and shard-weights.sh's: gh run view 7777 --json jobs" "2" "$(grep -c '^gh run view 7777 .*--json jobs' "$FAKE_LOG")"
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
  assert_eq "AC4.1/AC3.1 shards [$sh]: balanced, the jobs of the run are read exactly once (no refresh read)" "1" "$(grep -c '^gh run view 7777 .*--json jobs' "$FAKE_LOG")"
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
t_summary
