#!/usr/bin/env bash
# Tests for scripts/tdd-step.sh (v0.24.24 lane A, Full, slice S1, part 13 (after -r); spec 01-spec.md AC0, AC3, AC4 incl. "AC amendments, round 3"):
#   A  AC3 a post-commit hook runs a MIXED git reset HEAD~1 after the role added a judged file (untracked again, on disk, unchanged): nothing is lost, exit 1, "nothing committed",
#      the undo is complete. Attached and detached, default path and --baseline.
#   B  AC3 / AC0 the role deleted a tracked file: after reset --hard HEAD~1 the file is back on disk, which is lost (exit 3, the recovery text names the rm); after a mixed reset
#      it is still absent, which is not lost (exit 1).
#   C  AC4 a hook commits ONCE on top of C (HEAD = D, a child of C; marker file) and leaves the judged files unchanged on disk: exit 1, "nothing committed", the branch back at
#      the pre-run HEAD, the index restored. Attached, default path and --baseline.
# Shared setup: tdd-step-fixture.sh, tdd-step-d-fixture.sh, tdd-step-g-fixture.sh, tdd-step-n-fixture.sh and tdd-step-r-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/tdd-step-fixture.sh"
. "$(dirname "$0")/tdd-step-d-fixture.sh"
. "$(dirname "$0")/tdd-step-g-fixture.sh"
. "$(dirname "$0")/tdd-step-n-fixture.sh"
. "$(dirname "$0")/tdd-step-r-fixture.sh"

DET="git checkout -q --detach"
# not_lost TAG -> a run whose undo was complete and lost nothing: exit 1, nothing committed, the work tree is kept
not_lost() {
  assert_rc "$1: exit 1" 1
  assert_contains "$1: says nothing committed" "$(lower "$OUT")" "nothing committed"
  assert_not_contains "$1: does not say the role files are gone from the work tree" "$(lower "$OUT")" "no longer in the work tree"
  assert_eq "$1: no recovery line git checkout C -- ." "" "$(recovery_line)"
}

echo "A AC3 a mixed reset after an added file: not lost (default path and --baseline)"
if can_exec; then
  for MODE in default baseline; do
    for RUNKIND in attached detached; do
      if [ "$RUNKIND" = detached ]; then PRE="$DET"; else PRE=":"; fi
      T="A AC3 $RUNKIND run, post-commit hook: git reset -q HEAD~1 after an added file ($MODE)"
      gprep "$MODE" "$PRE"; run_red --commit sh -c "$(hookcmd "$HK_MIXED" post-commit)"
      not_lost "$T"; end_state "$T" "$RUNKIND"
      assert_eq "$T: the added file is still on disk, unchanged" 'test("n", () => {});' "$(cat "$R/tests/n.test.js" 2>/dev/null)"
      assert_eq "$T: the hook ran and the commit is gone from every ref (the case is real)" "yes" "$([ -s "$R/.git/csha" ] && echo yes || echo no)"
    done
  done
else
  t_skip 90 "A AC3 mixed-reset cases (the file system cannot make a hook executable)"
fi

echo "B AC3 / AC0 a deleted tracked file: lost when it is back on disk, not lost when it is absent"
if can_exec; then
  # the role's only change is the deletion of tests/app.test.js (after the baseline of the baseline mode was taken)
  for MODE in default baseline; do
    for RUNKIND in attached detached; do
      if [ "$RUNKIND" = detached ]; then PRE="$DET"; else PRE=":"; fi
      T="B AC3 $RUNKIND run, role deleted tests/app.test.js, post-commit hook: git reset --hard HEAD~1 ($MODE)"
      gprep "$MODE" "$PRE"; rm -f "$R/tests/n.test.js" "$R/tests/app.test.js"
      run_red --commit sh -c "$(hookcmd "$HK_RESET" post-commit)"
      a2_lost "$T"; end_state "$T" "$RUNKIND"
      assert_eq "$T: the deleted file is back on disk (the case is real)" "yes" "$([ -e "$R/tests/app.test.js" ] && echo yes || echo no)"
      assert_contains "$T: the recovery text names the rm of the brought-back file" "$(printf '%s\n' "$OUT" | grep -F 'rm --')" "tests/app.test.js"
    done
  done
  for RUNKIND in attached detached; do
    if [ "$RUNKIND" = detached ]; then PRE="$DET"; else PRE=":"; fi
    T="B AC0 $RUNKIND run, role deleted tests/app.test.js, post-commit hook: git reset -q HEAD~1 (the file stays absent)"
    gprep default "$PRE"; rm -f "$R/tests/n.test.js" "$R/tests/app.test.js"
    run_red --commit sh -c "$(hookcmd "$HK_MIXED" post-commit)"
    not_lost "$T"; end_state "$T" "$RUNKIND"
    assert_eq "$T: the deleted file is still absent" "no" "$([ -e "$R/tests/app.test.js" ] && echo yes || echo no)"
  done
else
  t_skip 90 "B AC3 deletion cases (the file system cannot make a hook executable)"
fi

echo "C AC4 a hook commits once on top of C and leaves the files unchanged: exit 1"
if can_exec; then
  for MODE in default baseline; do
    T="C AC4 post-commit hook: one commit on top (HEAD = D, a child of C), files unchanged ($MODE)"
    gprep "$MODE"; run_red --commit sh -c "$(hookcmd "$HK_TOP" post-commit)"
    not_lost "$T"; a2_end "$T"
    C="$(cat "$R/.git/csha" 2>/dev/null)"
    assert_contains "$T: the hook committed on top (the case is real: D is a child of C)" "$(git -C "$R" log -g --format='%s %P' HEAD 2>/dev/null)" "top $C"
    assert_eq "$T: the commit count is as before" "$N0" "$(count_of "$R")"
    assert_eq "$T: the role file is on disk, unchanged" 'test("n", () => {});' "$(cat "$R/tests/n.test.js" 2>/dev/null)"
  done
else
  t_skip 20 "C AC4 commit-on-top cases (the file system cannot make a hook executable)"
fi

t_summary
