#!/usr/bin/env bash
# Tests for scripts/tdd-step.sh (v0.24.23 lane A, Full), part 5 of 7 (parts: test-tdd-step-g.sh, -h.sh, -i.sh, -k.sh, -j.sh, -m.sh; slice S2 of .agents/handoff/01-spec.md):
#   AC2  after every commit the branch list is compared; the undo moves only the pre-run branch (compare-and-swap), re-attaches HEAD and restores the index; exit 1 or exit 3 with the full end state
# Split in v0.24.23 for the local Windows Git Bash time: test-tdd-step-i.sh runs the cases in MODE default (and the last control of MODE baseline), test-tdd-step-l.sh the other cases in MODE baseline (a suite over about 450 s would set a shard floor, L-0009).
# Shared setup: tdd-step-fixture.sh, tdd-step-d-fixture.sh and tdd-step-g-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/tdd-step-fixture.sh"
. "$(dirname "$0")/tdd-step-d-fixture.sh"
. "$(dirname "$0")/tdd-step-g-fixture.sh"

# ---------------------------------------------------------------------------------------------------------------
echo "AC2 after every commit the branch list is compared; the undo moves only the pre-run branch (compare-and-swap), re-attaches HEAD and restores the index"
# a2_msg TAG RC -> exit code and the "nothing committed" wording (said on exit 1, never on exit 3)
a2_msg() {
  assert_rc "$1: exit $2" "$2"
  if [ "$2" = 1 ]; then assert_contains "$1: says nothing committed" "$(lower "$OUT")" "nothing committed"
  else assert_not_contains "$1: does not say nothing committed" "$(lower "$OUT")" "nothing committed"; fi
}
# a2_back TAG -> main is back at the pre-run HEAD, HEAD is attached to it, the index file is restored
a2_back() {
  assert_eq "$1: $MAIN is moved back to the pre-run HEAD" "$H0" "$(tip "$MAIN")"
  assert_eq "$1: HEAD is attached to $MAIN" "refs/heads/$MAIN" "$(headref)"
  assert_eq "$1: the index file is restored byte for byte" "same" "$(same_idx)"
}
# a2_left TAG BRANCH -> BRANCH is left as one commit "test(red): m" on the pre-run HEAD; sets C
a2_left() {
  C="$(tip "$2")"
  assert_eq "$1: $2 is left at one commit on the pre-run HEAD" "$H0" "$(git -C "$R" rev-parse "$C^" 2>/dev/null)"
  assert_eq "$1: that commit is the test(red) commit" "test(red): m" "$(git -C "$R" log -1 --format=%s "$C" 2>/dev/null)"
}
if can_exec; then
  for MODE in baseline; do
    # --- exit 1: only main and HEAD had to change
    T="AC2 post-commit hook: git checkout existing ($MODE)"
    gprep "$MODE"; run_red --commit sh -c "$(hookcmd "$HK_EXIST" post-commit)"
    a2_msg "$T" 1; a2_back "$T"
    assert_eq "$T: every branch tip is as before (existing keeps its tip)" "$REFS0" "$(refs "$R")"
    assert_eq "$T: no test(red) commit reachable from any ref" "" "$(red_any)"
    assert_not_contains "$T: no RED= line" "$OUT" "RED="

    T="AC2 post-commit hook: git checkout --detach ($MODE)"
    gprep "$MODE"; run_red --commit sh -c "$(hookcmd "$HK_DETACH" post-commit)"
    a2_msg "$T" 1; a2_back "$T"
    assert_eq "$T: every branch tip is as before" "$REFS0" "$(refs "$R")"
    assert_eq "$T: no test(red) commit reachable from any ref" "" "$(red_any)"

    T="AC2 detached before the run, post-commit hook: git checkout existing ($MODE)"
    gprep "$MODE" "git checkout -q --detach"; run_red --commit sh -c "$(hookcmd "$HK_EXIST" post-commit)"
    a2_msg "$T" 1
    assert_eq "$T: HEAD is detached again" "detached" "$(headref)"
    assert_eq "$T: HEAD is at the pre-run HEAD" "$H0" "$(head_of "$R")"
    assert_eq "$T: every branch tip is as before" "$REFS0" "$(refs "$R")"
    assert_eq "$T: the index file is restored byte for byte" "same" "$(same_idx)"
    assert_eq "$T: no test(red) commit reachable from any ref" "" "$(red_any)"

    # --- exit 3: something else than main and HEAD had to be left alone
    for HN in post-commit pre-commit; do
      T="AC2 $HN hook: git checkout -b newb ($MODE)"
      gprep "$MODE"; run_red --commit sh -c "$(hookcmd "$HK_NEWB" "$HN")"
      a2_msg "$T" 3; a2_back "$T"; a2_left "$T" newb
      assert_eq "$T: the other branches are as before" "$REFS0" "$(refs "$R" | grep -v '^refs/heads/newb ')"
      assert_contains "$T: the message names newb" "$OUT" "newb"
      assert_contains "$T: the message names the commit left on newb" "$OUT" "$(s7 "$C")"
      assert_not_contains "$T: no RED= line" "$OUT" "RED="
    done

    T="AC2 pre-commit hook: git checkout existing, git commit then fails ($MODE)"
    gprep "$MODE"; run_red --commit sh -c "$(hookcmd "$HK_EXIST" pre-commit)"
    a2_msg "$T" 3; a2_back "$T"
    assert_eq "$T: every branch tip is as before (existing keeps its tip)" "$REFS0" "$(refs "$R")"
    assert_contains "$T: the message names existing" "$OUT" "existing"
    assert_contains "$T: the message names HEAD" "$OUT" "HEAD"
    assert_eq "$T: no test(red) commit reachable from any ref" "" "$(red_any)"

    T="AC2 post-commit hook: git branch -f existing HEAD, HEAD stays on $MAIN ($MODE)"
    gprep "$MODE"; run_red --commit sh -c "$(hookcmd "$HK_BRF" post-commit)"
    a2_msg "$T" 3; a2_back "$T"; a2_left "$T" existing
    assert_eq "$T: the other branches are as before" "$(printf '%s\n' "$REFS0" | grep -v '^refs/heads/existing ')" "$(refs "$R" | grep -v '^refs/heads/existing ')"
    assert_contains "$T: the message names existing" "$OUT" "existing"
    assert_contains "$T: the message names its old sha" "$OUT" "$(s7 "$E0")"
    assert_contains "$T: the message names its new sha" "$OUT" "$(s7 "$C")"
    assert_not_contains "$T: no RED= line" "$OUT" "RED="

    T="AC2 post-commit hook: git branch extra (a branch created) ($MODE)"
    gprep "$MODE"; run_red --commit sh -c "$(hookcmd "$HK_BRNEW" post-commit)"
    a2_msg "$T" 3; a2_back "$T"; a2_left "$T" extra
    assert_eq "$T: the other branches are as before" "$REFS0" "$(refs "$R" | grep -v '^refs/heads/extra ')"
    assert_contains "$T: the message names extra" "$OUT" "extra"
    assert_contains "$T: the message names its sha" "$OUT" "$(s7 "$C")"

    T="AC2 post-commit hook: git branch -D existing (a branch deleted) ($MODE)"
    gprep "$MODE"; run_red --commit sh -c "$(hookcmd "$HK_BRDEL" post-commit)"
    a2_msg "$T" 3; a2_back "$T"
    assert_eq "$T: existing stays deleted (tdd-step creates no branch)" "none" "$(tip existing)"
    assert_eq "$T: the other branches are as before" "$(printf '%s\n' "$REFS0" | grep -v '^refs/heads/existing ')" "$(refs "$R")"
    assert_contains "$T: the message names existing" "$OUT" "existing"
    assert_contains "$T: the message names its old sha" "$OUT" "$(s7 "$E0")"

    # --- compare-and-swap and re-attach that cannot run: exit 3, what is left is named
    T="AC2 the compare-and-swap fails (git update-ref refused), a branch was created ($MODE)"
    gprep "$MODE"; D="$(stubdir git "$UPDREF_STUB")"
    run_red_p "$D" --commit sh -c "$(hookcmd "$HK_BRNEW" post-commit)"
    a2_msg "$T" 3
    C="$(tip "$MAIN")"
    assert_eq "$T: $MAIN is left on the commit (no other way to move it back)" "$H0" "$(git -C "$R" rev-parse "$C^" 2>/dev/null)"
    assert_contains "$T: the message names $MAIN" "$OUT" "$MAIN"
    assert_contains "$T: the message names the commit left on $MAIN" "$OUT" "$(s7 "$C")"
    assert_contains "$T: the message names extra" "$OUT" "extra"
    assert_not_contains "$T: no RED= line" "$OUT" "RED="

    T="AC2 HEAD cannot be re-attached (git symbolic-ref write refused) ($MODE)"
    gprep "$MODE"; D="$(stubdir git "$SRWRITE_STUB")"
    run_red_p "$D" --commit sh -c "$(hookcmd "$HK_DETACH" post-commit)"
    a2_msg "$T" 3
    assert_eq "$T: $MAIN was moved back (step a ran)" "$H0" "$(tip "$MAIN")"
    assert_eq "$T: HEAD is still detached" "detached" "$(headref)"
    assert_contains "$T: the message names HEAD" "$OUT" "HEAD"
    assert_not_contains "$T: no RED= line" "$OUT" "RED="

    # --- controls: a hook that does nothing
    T="AC2 control: a post-commit hook that does nothing ($MODE)"
    gprep "$MODE"; run_red --commit sh -c "$(hookcmd "$HK_NOOP" post-commit)"
    a2_msg "$T" 0
    assert_eq "$T: HEAD is attached to $MAIN" "refs/heads/$MAIN" "$(headref)"
    a2_left "$T" "$MAIN"
    assert_eq "$T: the other branches are as before" "$(printf '%s\n' "$REFS0" | grep -v "^refs/heads/$MAIN ")" "$(refs "$R" | grep -v "^refs/heads/$MAIN ")"
    assert_contains "$T: prints RED=" "$OUT" "RED=$C"
  done
else
  t_skip 196 "AC2 hook cases (the file system cannot make a hook executable)"
fi


t_summary
