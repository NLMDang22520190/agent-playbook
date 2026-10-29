#!/usr/bin/env bash
# Tests for tools/ship.sh v0.32.0 AC9 and AC9': before EVERY merge ship starts (the direct merge and arming --auto) it fetches the PR head and
# refuses unless origin/main is an ancestor of the head (PR up to date) and `tools/release-gate.sh --check <head sha>` exits 0. An already MERGED PR is not checked by ship.
# Interface (spec Revision 3): head sha = `gh pr view N --json headRefOid`; fetch refs/pull/N/head, else the head branch (headRefName); gate called from main's checkout.
# The fixture (ship-fixture.sh) has a gate stub with a controllable exit code (FAKE_GATE_RC, FAKE_GATE_MSG) that logs its arguments, and an origin with refs/pull/12/head and feat/x.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/ship-fixture.sh"

# line number of the first log line matching $1 (empty when none)
first_line() { grep -n -- "$1" "$FAKE_LOG" | head -n 1 | cut -d: -f1; }
before() { # name A B -> the first log line matching A comes before the first matching B
  local a b; a="$(first_line "$2")"; b="$(first_line "$3")"
  if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then t_ok "$1"; else t_bad "$1" "line of '$2' = [$a], line of '$3' = [$b]"; fi
}

echo "AC9 direct merge: the gate passes and the PR is up to date -> merged, gate called with --check <PR head sha> before the merge"
fx
HEAD1="$(pr_head)"
sh_run 12 v1.2.3 --yes
assert_rc "AC9 gate ok + up to date: exit 0" 0
assert_eq "AC9 gate ok + up to date: the whole flow ran" "$FULL_YES" "$(steps)"
assert_eq "AC9 gate ok: the gate stub was called exactly once, with '--check <PR head sha>'" "release-gate.sh --check $HEAD1" "$(gate_calls)"
before "AC9 the gate runs before gh pr merge" '^release-gate.sh' '^gh pr merge'
assert_eq "AC9 gate ok: the merge reached origin" "1" "$(origin_merges)"
assert_contains "AC9 gate ok: shipped is printed" "$OUT" "shipped v1.2.3"

echo "AC9 the sha is the PR head (a PR with a commit of its own), not main's"
fx
pr_ahead
HEAD2="$(pr_head)"
MAIN2="$(git -C "$F/origin.git" rev-parse main)"
assert_eq "AC9 setup: the PR head differs from main" "1" "$([ "$HEAD2" != "$MAIN2" ] && echo 1 || echo 0)"
sh_run 12 v1.2.3 --yes
assert_rc "AC9 PR ahead of main: exit 0" 0
assert_eq "AC9 PR ahead of main: --check names the PR head sha" "release-gate.sh --check $HEAD2" "$(gate_calls)"

echo "AC9 the PR is up to date when it contains origin's current main, even if main moved after the PR was opened"
fx
origin_advance
pr_on_new_main
HEAD3="$(pr_head)"
sh_run 12 v1.2.3 --yes
assert_rc "AC9 PR on top of the moved main: exit 0" 0
assert_eq "AC9 PR on top of the moved main: the gate was called with its head" "release-gate.sh --check $HEAD3" "$(gate_calls)"
assert_eq "AC9 PR on top of the moved main: the whole flow ran" "$FULL_YES" "$(steps)"

echo "AC9 head found through the head branch when refs/pull/N/head is missing (PR 345 has no pull ref in origin)"
fx
export FAKE_PR=345 FAKE_TAG=v10.20.30
HEAD4="$(pr_head)"
assert_eq "AC9 setup: origin has no refs/pull/345/head" "" "$(git -C "$F/origin.git" for-each-ref refs/pull/345)"
sh_run 345 v10.20.30 --yes
assert_rc "AC9 head branch fallback: exit 0" 0
assert_eq "AC9 head branch fallback: --check names the head branch's sha" "release-gate.sh --check $HEAD4" "$(gate_calls)"

echo "AC9 direct merge: the gate fails -> refused, nothing merged"
for rc in 1 2; do
  fx
  export FAKE_GATE_RC="$rc" FAKE_GATE_MSG="no gate result for this commit (fake reason)"
  HEADF="$(pr_head)"
  sh_run 12 v1.2.3 --yes
  assert_rc "AC9 gate exit $rc: ship exits 1" 1
  assert_contains "AC9 gate exit $rc: 'ship refused: release gate: <reason>'" "$OUT" "ship refused: release gate: no gate result for this commit (fake reason)"
  assert_eq "AC9 gate exit $rc: gh pr merge was never called" "0" "$(logged '^gh pr merge')"
  assert_eq "AC9 gate exit $rc: only the PR check ran (no release, CI wait or install)" "view" "$(steps)"
  assert_eq "AC9 gate exit $rc: nothing reached origin's main" "0" "$(origin_merges)"
  assert_eq "AC9 gate exit $rc: no tag" "" "$(git -C "$F/repo" tag)"
  assert_eq "AC9 gate exit $rc: the gate was asked about the PR head" "release-gate.sh --check $HEADF" "$(gate_calls)"
  assert_not_contains "AC9 gate exit $rc: not claimed shipped" "$OUT" "shipped v1.2.3"
done

echo "AC9 direct merge: the PR is not up to date with main -> refused, nothing merged (origin's main moved, the clone's origin/main is stale)"
fx
origin_advance
sh_run 12 v1.2.3 --yes
assert_rc "AC9 not up to date: ship exits 1" 1
assert_contains "AC9 not up to date: 'ship refused: PR is not up to date with main'" "$OUT" "ship refused: PR is not up to date with main"
assert_contains "AC9 not up to date: says to update the PR and re-run the gate" "$OUT" "update it and re-run the gate"
assert_eq "AC9 not up to date: gh pr merge was never called" "0" "$(logged '^gh pr merge')"
assert_eq "AC9 not up to date: only the PR check ran" "view" "$(steps)"
assert_eq "AC9 not up to date: main on origin has no merge commit of the PR" "0" "$(origin_merges)"
assert_not_contains "AC9 not up to date: not claimed shipped" "$OUT" "shipped v1.2.3"
fx
origin_advance
sh_run 12 v1.2.3
assert_rc "AC9 not up to date, with questions (no terminal): exit 1" 1
assert_contains "AC9 not up to date, with questions: refused for the stale PR, before the question" "$OUT" "ship refused: PR is not up to date with main"
assert_eq "AC9 not up to date, with questions: gh pr merge was never called" "0" "$(logged '^gh pr merge')"

echo "AC9' --auto: the same refusals happen before auto-merge is armed"
fx
export FAKE_GH_MERGE_STATE=BLOCKED
HEAD5="$(pr_head)"
sh_run 12 v1.2.3 --yes --auto
assert_rc "AC9' --auto, gate ok + up to date: exit 0" 0
assert_eq "AC9' --auto, gate ok: the auto-merge call is made as before" "$AUTO_MERGE_CALL" "$(grep '^gh pr merge' "$FAKE_LOG")"
assert_eq "AC9' --auto, gate ok: the gate was called with '--check <PR head sha>'" "release-gate.sh --check $HEAD5" "$(gate_calls)"
before "AC9' --auto: the gate runs before the auto-merge is armed" '^release-gate.sh' '^gh pr merge'
fx
export FAKE_GH_MERGE_STATE=BLOCKED FAKE_GATE_RC=1 FAKE_GATE_MSG="gate failed (fake reason)"
sh_run 12 v1.2.3 --yes --auto
assert_rc "AC9' --auto, gate fails: exit 1" 1
assert_contains "AC9' --auto, gate fails: 'ship refused: release gate: <reason>'" "$OUT" "ship refused: release gate: gate failed (fake reason)"
assert_eq "AC9' --auto, gate fails: no gh pr merge call at all (auto-merge not armed)" "0" "$(logged '^gh pr merge')"
assert_not_contains "AC9' --auto, gate fails: does not say auto-merge was enabled" "$OUT" "auto-merge enabled"
fx
export FAKE_GH_MERGE_STATE=BLOCKED
origin_advance
sh_run 12 v1.2.3 --yes --auto
assert_rc "AC9' --auto, PR not up to date: exit 1" 1
assert_contains "AC9' --auto, PR not up to date: 'ship refused: PR is not up to date with main'" "$OUT" "ship refused: PR is not up to date with main"
assert_eq "AC9' --auto, PR not up to date: no gh pr merge call at all (auto-merge not armed)" "0" "$(logged '^gh pr merge')"
assert_not_contains "AC9' --auto, PR not up to date: does not say auto-merge was enabled" "$OUT" "auto-merge enabled"

echo "AC9' an already MERGED PR is not checked by ship (release.sh's own check covers the tag)"
fx
merged_on_main
export FAKE_GATE_RC=1 FAKE_GATE_MSG="gate would refuse (fake reason)"
sh_run 12 v1.2.3 --yes
assert_rc "AC9' MERGED PR, failing gate stub: ship still releases, exit 0" 0
assert_eq "AC9' MERGED PR: the gate stub was not called" "0" "$(logged '^release-gate.sh')"
assert_eq "AC9' MERGED PR: the flow is the merged one (no merge call)" "$MERGED_YES" "$(steps)"
assert_not_contains "AC9' MERGED PR: no refusal text" "$OUT" "ship refused"
fx
merged_on_main
origin_advance
sh_run 12 v1.2.3 --yes --auto
assert_eq "AC9' MERGED PR with --auto, main moved on: the gate stub was not called" "0" "$(logged '^release-gate.sh')"
t_summary
