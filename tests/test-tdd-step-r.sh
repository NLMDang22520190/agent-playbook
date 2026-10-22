#!/usr/bin/env bash
# Tests for scripts/tdd-step.sh (v0.24.24 lane A, Full, slice S1, part 12 (after -q); spec 01-spec.md AC0-AC2 incl. "AC amendments, round 3"):
#   A  AC1 a DETACHED run whose post-commit hook runs git reset --hard HEAD~1, or git checkout --detach <other commit>, is exit 3 naming C (not "the work tree is kept"):
#      the lost decision compares the work tree with the judged entries and does not depend on the run being attached. HEAD ends detached at the pre-run HEAD again,
#      the index is restored, the branches are unchanged. Default path and --baseline.
#   B  AC2 with the reflogs off (core.logAllRefUpdates=false, no .git/logs) C still comes from git commit's own report: reset --hard HEAD~1 is exit 3 naming the commit that
#      holds the judged content, attached and detached, default path and --baseline. The report is not printed (a normal run is as before).
# Shared setup: tdd-step-fixture.sh, tdd-step-d-fixture.sh, tdd-step-g-fixture.sh, tdd-step-n-fixture.sh and tdd-step-r-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/tdd-step-fixture.sh"
. "$(dirname "$0")/tdd-step-d-fixture.sh"
. "$(dirname "$0")/tdd-step-g-fixture.sh"
. "$(dirname "$0")/tdd-step-n-fixture.sh"
. "$(dirname "$0")/tdd-step-r-fixture.sh"

DET="git checkout -q --detach"
XA="$(printf 'a%.0s' $(seq 1 40))"

echo "A AC1 detached runs: a hook loses the role file (default path and --baseline)"
if can_exec; then
  for MODE in default baseline; do
    T="A AC1 detached run, post-commit hook: git reset --hard HEAD~1 ($MODE)"
    gprep "$MODE" "$DET"; run_red --commit sh -c "$(hookcmd "$HK_RESET" post-commit)"
    a2_lost "$T"; d_end "$T"
    assert_eq "$T: the role file is gone from the work tree (the case is real)" "no" "$([ -e "$R/tests/n.test.js" ] && echo yes || echo no)"

    T="A AC1 detached run, post-commit hook: git checkout --detach <other commit> ($MODE)"
    gprep "$MODE" "$DET"; run_red --commit sh -c "$(hookcmd "$HK_DETE" post-commit)"
    a2_lost "$T"; d_end "$T"
  done
else
  t_skip 40 "A AC1 lost-C cases (the file system cannot make a hook executable)"
fi

echo "B AC2 reflogs off: C comes from the report of git commit"
if can_exec; then
  for MODE in default baseline; do
    for RUNKIND in attached detached; do
      if [ "$RUNKIND" = detached ]; then PRE="$DET; $ROFF"; else PRE="$ROFF"; fi
      T="B AC2 reflogs off, $RUNKIND, post-commit hook: git reset --hard HEAD~1 ($MODE)"
      gprep "$MODE" "$PRE"; run_red --commit sh -c "$(hookcmd "$HK_RESET" post-commit)"
      a2_lost "$T"; end_state "$T" "$RUNKIND"
      C="$(cat "$R/.git/csha" 2>/dev/null)"
      assert_eq "$T: the reflog case is real (no HEAD reflog entry names C)" "" "$(git -C "$R" log -g --format=%H HEAD 2>/dev/null | grep -F "$C")"
      assert_eq "$T: C is the test(red) commit on the pre-run HEAD" "test(red): m $H0" "$(git -C "$R" log -1 --format='%s %P' "$C" 2>/dev/null)"
      assert_eq "$T: C holds the judged content" 'test("n", () => {});' "$(git -C "$R" show "$C:tests/n.test.js" 2>/dev/null)"
      assert_not_contains "$T: C is not reported as unknown" "$(lower "$OUT")" "could not be found"
      assert_not_contains "$T: the report of git commit is not printed" "$OUT" "] test(red): m"
    done
  done
  # a normal run: the captured report of git commit stays out of the output
  T="B AC2 control: a normal run prints RED= and not the report of git commit"
  gprep default; run_red --commit sh -c "exit 1"
  assert_rc "$T: exit 0" 0
  assert_contains "$T: RED= line" "$OUT" "RED="
  assert_not_contains "$T: the report line of git commit is not printed" "$OUT" "] test(red): m"
  assert_eq "$T: one new commit" "$((N0 + 1))" "$(count_of "$R")"
else
  t_skip 90 "B AC2 reflogs-off cases (the file system cannot make a hook executable)"
fi

t_summary
