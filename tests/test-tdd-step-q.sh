#!/usr/bin/env bash
# Tests for scripts/tdd-step.sh (v0.24.23 lane A, Full, code review round 2 fixes), part 11 (after -n, -o and -p; spec 01-spec.md, decision D3):
#   A  a hook that takes the role file out of the work tree WITHOUT attaching HEAD to another branch is exit 3 as well (C named, C's parent named, a recovery line
#      git checkout C -- ., never "nothing committed" or "the work tree is kept"): a post-commit hook that runs git checkout --detach existing in an attached run
#      (HEAD ends detached at another commit), and one that runs git reset --hard HEAD~1 (HEAD stays on the pre-run branch at the pre-run HEAD). The rule: C is lost
#      whenever HEAD is not at C after the hooks. The "--detach" row with HEAD detached AT C stays exit 1 (test-tdd-step-i.sh).
#   B  the message of the branch switch names the switch as the reason; C is still named when the HEAD reflog holds no entry for it; a hook that attaches HEAD to a new
#      branch at C (HEAD is at C) says nothing about lost role files and prints no recovery line.
# Shared setup: tdd-step-fixture.sh, tdd-step-d-fixture.sh, tdd-step-g-fixture.sh and tdd-step-n-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/tdd-step-fixture.sh"
. "$(dirname "$0")/tdd-step-d-fixture.sh"
. "$(dirname "$0")/tdd-step-g-fixture.sh"
. "$(dirname "$0")/tdd-step-n-fixture.sh"

# recovery_line -> the lines of the message that hold " -- ." (the recovery line git checkout C -- .)
recovery_line() { printf '%s\n' "$OUT" | grep -F -- ' -- .'; true; }

echo "A B hooks that lose the role file: exit 3 naming C (default path and --baseline)"
if can_exec; then
  for MODE in default baseline; do
    T="A post-commit hook: git checkout --detach existing in an attached run ($MODE)"
    gprep "$MODE"; run_red --commit sh -c "$(hookcmd "$HK_DETE" post-commit)"
    a2_lost "$T"; a2_end "$T"

    T="A post-commit hook: git reset --hard HEAD~1, HEAD stays on $MAIN at the pre-run HEAD ($MODE)"
    gprep "$MODE"; run_red --commit sh -c "$(hookcmd "$HK_RESET" post-commit)"
    a2_lost "$T"; a2_end "$T"

    # B (N8): the branch switch is named as the reason, ahead of "HEAD was moved"
    T="B post-commit hook: git checkout existing, the reason names the branch switch ($MODE)"
    gprep "$MODE"; run_red --commit sh -c "$(hookcmd "$HK_EXISTC" post-commit)"
    a2_lost "$T"; a2_end "$T"
    assert_contains "$T: the reason says a git hook switched HEAD" "$(lower "$OUT")" "a git hook switched head to refs/heads/existing"
    assert_contains "$T: the reason says where HEAD was" "$(lower "$OUT")" "(it was on refs/heads/$MAIN)"

    # B (N7): the HEAD reflog is empty, C is still named (from the tip of the pre-run branch)
    T="B post-commit hook: git checkout existing and git reflog expire, C is not in the reflog ($MODE)"
    gprep "$MODE"; run_red --commit sh -c "$(hookcmd "$HK_EXPIRE" post-commit)"
    a2_lost "$T"; a2_end "$T"
    assert_eq "$T: the HEAD reflog holds no entry for C (the case is real)" "" "$(git -C "$R" log -g --format=%H HEAD 2>/dev/null | grep -F "$(cat "$R/.git/csha")")"
    assert_not_contains "$T: C is not reported as unknown" "$(lower "$OUT")" "could not be found"

    # B (N4): HEAD is at C on a new branch: the files are in the work tree, nothing is lost
    for HN in post-commit pre-commit; do
      T="B $HN hook: git checkout -b newb, HEAD is at C, no lost files ($MODE)"
      gprep "$MODE"; run_red --commit sh -c "$(hookcmd "$HK_NEWB" "$HN")"
      assert_rc "$T: exit 3" 3
      assert_not_contains "$T: does not say the role files are gone from the work tree" "$(lower "$OUT")" "no longer in the work tree"
      assert_eq "$T: no recovery line git checkout C -- ." "" "$(recovery_line)"
      assert_not_contains "$T: does not say the commit could not be found" "$(lower "$OUT")" "could not be found"
      assert_eq "$T: the role file is in the work tree" 'test("n", () => {});' "$(cat "$R/tests/n.test.js" 2>/dev/null)"
    done
  done
else
  t_skip 140 "A B lost-C cases (the file system cannot make a hook executable)"
fi

t_summary
