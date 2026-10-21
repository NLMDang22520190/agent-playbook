#!/usr/bin/env bash
# Tests for scripts/tdd-step.sh (v0.24.23 lane A, Full, code review round 1 fixes), part 8 of 10 (the new parts: test-tdd-step-n.sh, -o.sh, -p.sh; the earlier ones are test-tdd-step-g.sh to -m.sh; spec 01-spec.md, decisions D3):
#   F3  detached run, a pre-commit hook runs git checkout --detach existing and git commit fails: exit 3, HEAD is detached at the pre-run HEAD again and is named
#   F4  a pre-commit hook runs git branch -f existing HEAD and git commit fails: exit 3, existing is named "was X, now Y", the index file is restored
#   F7  a test command that checks out a branch at a different commit is refused with a message that says "branch"
#   F5  the re-attach guard (a failed compare-and-swap and a switched HEAD: HEAD is not re-attached) and the detached undo condition (a detached run whose hook attaches
#       HEAD to a branch at the pre-run HEAD: HEAD is detached at the pre-run HEAD again)
#   F9  the header of scripts/tdd-step.sh says that another worktree that commits while the step runs makes it exit 3
# (F1 and F6 are rows of test-tdd-step-i.sh and -l.sh, F2 is test-tdd-step-o.sh, the other F5 rows are test-tdd-step-p.sh.)
# Shared setup: tdd-step-fixture.sh, tdd-step-d-fixture.sh, tdd-step-g-fixture.sh and tdd-step-n-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/tdd-step-fixture.sh"
. "$(dirname "$0")/tdd-step-d-fixture.sh"
. "$(dirname "$0")/tdd-step-g-fixture.sh"
. "$(dirname "$0")/tdd-step-n-fixture.sh"

# a2_msg TAG RC -> exit code and the "nothing committed" wording (said on exit 1, never on exit 3)
a2_msg() {
  assert_rc "$1: exit $2" "$2"
  if [ "$2" = 1 ]; then assert_contains "$1: says nothing committed" "$(lower "$OUT")" "nothing committed"
  else assert_not_contains "$1: does not say nothing committed" "$(lower "$OUT")" "nothing committed"; fi
}
# the message lines that say HEAD, without the role gate's "base=HEAD"
head_lines() { printf '%s\n' "$OUT" | grep -v 'base=HEAD'; }

# ---------------------------------------------------------------------------------------------------------------
echo "F3 F4 F5 hooks: the end state and the message of the undo (default path and --baseline)"
if can_exec; then
  for MODE in default baseline; do
    # F3: HEAD was detached at the pre-run HEAD and a pre-commit hook detached it at another commit before failing git commit
    T="F3 detached before the run, pre-commit hook: git checkout --detach existing, git commit then fails ($MODE)"
    gprep "$MODE" "git checkout -q --detach"; run_red --commit sh -c "$(hookcmd "$HK_DETX" pre-commit)"
    a2_msg "$T" 3
    assert_eq "$T: HEAD is detached" "detached" "$(headref)"
    assert_eq "$T: HEAD is at the pre-run HEAD again (not left on existing)" "$H0" "$(head_of "$R")"
    assert_eq "$T: every branch tip is as before" "$REFS0" "$(refs "$R")"
    assert_eq "$T: the index file is restored byte for byte" "same" "$(same_idx)"
    assert_contains "$T: the message names HEAD" "$(head_lines)" "HEAD"
    assert_eq "$T: no test(red) commit reachable from any ref" "" "$(red_any)"
    assert_not_contains "$T: no RED= line" "$OUT" "RED="

    # F4: the branch the step runs on is unchanged, but a pre-commit hook moved another branch and git commit failed
    T="F4 pre-commit hook: git branch -f existing HEAD, git commit then fails ($MODE)"
    gprep "$MODE"; run_red --commit sh -c "$(hookcmd "$HK_BRFX" pre-commit)"
    a2_msg "$T" 3
    assert_eq "$T: HEAD is attached to $MAIN" "refs/heads/$MAIN" "$(headref)"
    assert_eq "$T: $MAIN is at the pre-run HEAD" "$H0" "$(tip "$MAIN")"
    assert_eq "$T: existing is left where the hook put it (the undo moves no other branch)" "$H0" "$(tip existing)"
    assert_contains "$T: the message names existing" "$OUT" "refs/heads/existing"
    wasnow "$T" refs/heads/existing "$E0" "$H0"
    assert_eq "$T: the index file is restored byte for byte" "same" "$(same_idx)"
    assert_eq "$T: no test(red) commit reachable from any ref" "" "$(red_any)"
    assert_not_contains "$T: no RED= line" "$OUT" "RED="
  done

  # F5: the re-attach guard. R (main) cannot be moved back (git update-ref refused), so HEAD must stay where the hook put it
  T="F5 re-attach guard: the compare-and-swap fails and a post-commit hook switched HEAD to existing (default)"
  gprep default; D="$(stubdir git "$UPDREF_STUB")"
  run_red_p "$D" --commit sh -c "$(hookcmd "$HK_EXISTC" post-commit)"
  a2_msg "$T" 3
  C="$(tip "$MAIN")"
  assert_eq "$T: $MAIN is left on the commit (it could not be moved back)" "$H0" "$(git -C "$R" rev-parse "$C^" 2>/dev/null)"
  assert_eq "$T: HEAD is NOT re-attached to $MAIN (it stays on existing)" "refs/heads/existing" "$(headref)"
  assert_eq "$T: existing keeps its tip" "$E0" "$(tip existing)"
  assert_contains "$T: the message names $MAIN" "$OUT" "$MAIN"
  assert_contains "$T: the message names the commit left on $MAIN" "$OUT" "$(s7 "$C")"
  assert_not_contains "$T: no RED= line" "$OUT" "RED="

  T="F5 re-attach guard: the compare-and-swap fails and a post-commit hook detached HEAD (default)"
  gprep default; D="$(stubdir git "$UPDREF_STUB")"
  run_red_p "$D" --commit sh -c "$(hookcmd "$HK_DETACH" post-commit)"
  a2_msg "$T" 3
  C="$(tip "$MAIN")"
  assert_eq "$T: $MAIN is left on the commit (it could not be moved back)" "$H0" "$(git -C "$R" rev-parse "$C^" 2>/dev/null)"
  assert_eq "$T: HEAD is NOT re-attached to $MAIN (it stays detached)" "detached" "$(headref)"
  assert_eq "$T: HEAD is at the commit left behind" "$C" "$(head_of "$R")"
  assert_contains "$T: the message names the commit left on $MAIN" "$OUT" "$(s7 "$C")"
  assert_not_contains "$T: no RED= line" "$OUT" "RED="

  # F5: the detached undo condition. A detached run whose post-commit hook attaches HEAD to a branch that is AT the pre-run HEAD: the sha is right, the branch is wrong
  for MODE in default baseline; do
    T="F5 detached before the run, a post-commit hook attaches HEAD to a branch at the pre-run HEAD ($MODE)"
    gprep "$MODE" "git checkout -q --detach && git branch atpre"; run_red --commit sh -c "$(hookcmd "$HK_ATPREC" post-commit)"
    a2_lost "$T"
    assert_eq "$T: HEAD is detached again" "detached" "$(headref)"
    assert_eq "$T: HEAD is at the pre-run HEAD" "$H0" "$(head_of "$R")"
    assert_eq "$T: every branch tip is as before (atpre and $MAIN are not moved)" "$REFS0" "$(refs "$R")"
    assert_eq "$T: the index file is restored byte for byte" "same" "$(same_idx)"
    assert_eq "$T: no test(red) commit reachable from any ref" "" "$(red_any)"
    assert_not_contains "$T: no RED= line" "$OUT" "RED="
  done
else
  t_skip 81 "F3 F4 F5 hook cases (the file system cannot make a hook executable)"
fi

# ---------------------------------------------------------------------------------------------------------------
echo "F7 a test command that checks out a branch at a different commit is refused, and the message says branch"
# sha_case LABEL MODE PRE CMD -> 7 assertions. CMD changes HEAD to another branch whose commit differs from the pre-run HEAD
sha_case() {
  local label="$1" mode="$2" pre="$3" cmd="$4" errl tag
  gprep "$mode" "$pre"
  run_red --commit sh -c "$cmd; exit 1"
  tag="$label ($mode)"
  errl="$(printf '%s\n' "$OUT" | tr '[:upper:]' '[:lower:]' | grep 'nothing committed')"
  assert_rc "$tag: exit 1" 1
  assert_contains "$tag: a message says nothing committed" "$errl" "nothing committed"
  assert_contains "$tag: that message says branch" "$errl" "branch"
  assert_eq "$tag: no commit on any branch" "$N0" "$(allcount)"
  assert_eq "$tag: no test(red) commit reachable from any ref" "" "$(red_any)"
  assert_not_contains "$tag: no RED= line" "$OUT" "RED="
  assert_eq "$tag: the work tree is kept" 'test("n", () => {});' "$(cat "$R/tests/n.test.js")"
}
sha_case "F7 git checkout existing (a branch at an older commit)" default ":" "git checkout -q existing"
sha_case "F7 git checkout --detach existing (to a detached HEAD at an older commit)" default ":" "git checkout -q --detach existing"
sha_case "F7 git checkout existing (a branch at an older commit)" baseline ":" "git checkout -q existing"

# ---------------------------------------------------------------------------------------------------------------
echo "F9 the header says that another worktree that commits while the step runs makes it exit 3"
HDR="$(awk 'NR == 1 { next } /^#/ { print; next } { exit }' "$STEP" | tr '[:upper:]' '[:lower:]' | tr '\n' ' ' | sed 's/#//g' | tr -s ' ')"
assert_contains "F9 the header names another worktree" "$HDR" "another worktree"
if printf '%s' "$HDR" | grep -E 'another worktree.{0,200}exit 3|exit 3.{0,200}another worktree' >/dev/null; then t_ok "F9 the header says exit 3 close to another worktree"
else t_bad "F9 the header says exit 3 close to another worktree" "no 'exit 3' within 200 characters of 'another worktree'"; fi
if printf '%s' "$HDR" | grep -E 'another worktree.{0,200}commit|commit.{0,200}another worktree' >/dev/null; then t_ok "F9 the header says the other worktree commits"
else t_bad "F9 the header says the other worktree commits" "no 'commit' within 200 characters of 'another worktree'"; fi

t_summary
