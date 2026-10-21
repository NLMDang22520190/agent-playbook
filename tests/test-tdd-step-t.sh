#!/usr/bin/env bash
# Tests for scripts/tdd-step.sh (v0.24.24 lane A, Full, slice S1, part 14 (after -s); spec 01-spec.md AC0, AC2 incl. "AC amendments, round 3"):
#   A  AC2 / N3 a REJECTED report of git commit (a commit whose parent is not the pre-run HEAD, a sha that is no commit, a commit on the pre-run HEAD with another subject; a git
#      shim on PATH rewrites the report line) is not trusted: exit 3 with C unknown ("look in git reflog HEAD"); with the reflog on, the reflog finds C instead.
#   B  AC0 / N1 the lost decision also runs when HEAD is still a single commit on the pre-run HEAD but its entries differ (a hook amended C): lost when the work tree differs from
#      what was judged, not lost when it equals it; and every git error of the comparison is lost (fail closed).
# Shared setup: tdd-step-fixture.sh, tdd-step-d-fixture.sh, tdd-step-g-fixture.sh, tdd-step-n-fixture.sh and tdd-step-r-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/tdd-step-fixture.sh"
. "$(dirname "$0")/tdd-step-d-fixture.sh"
. "$(dirname "$0")/tdd-step-g-fixture.sh"
. "$(dirname "$0")/tdd-step-n-fixture.sh"
. "$(dirname "$0")/tdd-step-r-fixture.sh"

DET="git checkout -q --detach"
XA="$(printf 'a%.0s' $(seq 1 40))"
# not_lost TAG -> a run whose undo was complete and lost nothing: exit 1, nothing committed, the work tree is kept
not_lost() {
  assert_rc "$1: exit 1" 1
  assert_contains "$1: says nothing committed" "$(lower "$OUT")" "nothing committed"
  assert_not_contains "$1: does not say the role files are gone from the work tree" "$(lower "$OUT")" "no longer in the work tree"
  assert_eq "$1: no recovery line git checkout C -- ." "" "$(recovery_line)"
}

echo "A AC2 a rejected report is not trusted (git shim on PATH rewrites the report line)"
if can_exec; then
  # reflogs off, attached, default path: every rejected report ends as "unknown"
  T="A AC2 reflogs off, the report names the pre-run HEAD (its parent is not the pre-run HEAD)"
  gprep default "$ROFF; git rev-parse HEAD > .git/xsha"; D="$(stubdir git "$GITSHIM_REPORT")"
  run_red_p "$D" --commit sh -c "$(hookcmd "$HK_RESET" post-commit)"
  lost_unknown "$T"; a2_end "$T"

  T="A AC2 reflogs off, the report names a sha that is no commit"
  gprep default "$ROFF; printf '%s\n' $XA > .git/xsha"; D="$(stubdir git "$GITSHIM_REPORT")"
  run_red_p "$D" --commit sh -c "$(hookcmd "$HK_RESET" post-commit)"
  lost_unknown "$T"; a2_end "$T"

  T="A AC2 reflogs off, the report names a commit on the pre-run HEAD with another subject"
  gprep default "$ROFF; git commit-tree 'HEAD^{tree}' -p HEAD -m other > .git/xsha"; D="$(stubdir git "$GITSHIM_REPORT")"
  X="$(cat "$R/.git/xsha")"
  run_red_p "$D" --commit sh -c "$(hookcmd "$HK_RESET" post-commit)"
  lost_unknown "$T"; a2_end "$T"
  assert_eq "$T: the other-subject commit exists and is a child of the pre-run HEAD (the case is real)" "other $H0" "$(git -C "$R" log -1 --format='%s %P' "$X" 2>/dev/null)"
  assert_not_contains "$T: the other-subject commit is not named" "$OUT" "$(s7 "$X")"

  # the same shim with the reflog ON: the fallback is the reflog, which finds the right C
  T="A AC2 reflog on, the report names the pre-run HEAD: the reflog finds C"
  gprep default "git rev-parse HEAD > .git/xsha"; D="$(stubdir git "$GITSHIM_REPORT")"
  run_red_p "$D" --commit sh -c "$(hookcmd "$HK_RESET" post-commit)"
  a2_lost "$T"; a2_end "$T"
else
  t_skip 30 "C AC2 rejected-report cases (the file system cannot make a hook executable)"
fi

echo "B AC0 the lost decision on a single commit with differing entries, and fail closed"
if can_exec; then
  T="B AC0 post-commit hook amends C and leaves the changed file in the work tree (HEAD is a single commit on the pre-run HEAD)"
  gprep default; run_red --commit sh -c "$(hookcmd "$HK_AMEND_LOST" post-commit)"
  a2_lost "$T"; a2_end "$T"
  assert_eq "$T: the work tree holds the changed content (the case is real)" "changed" "$(cat "$R/tests/n.test.js" 2>/dev/null)"

  T="B AC0 post-commit hook amends C and puts the judged content back: the commit differs, nothing is lost"
  gprep default; run_red --commit sh -c "$(hookcmd "$HK_AMEND_KEEP" post-commit)"
  not_lost "$T"; a2_end "$T"
  assert_contains "$T: names the path that differs" "$OUT" "the commit differs from what was judged: tests/n.test.js"

  T="B AC0 fail closed: every git call that compares the work tree fails after a mixed reset in a detached run (nothing is lost, but it cannot be told)"
  gprep default "$DET"; D="$(stubdir git "$GITSHIM_DIFF")"
  run_red_p "$D" --commit sh -c "$(hookcmd "$HK_MIXED" post-commit)"
  assert_rc "$T: exit 3" 3
  assert_not_contains "$T: does not say nothing committed" "$(lower "$OUT")" "nothing committed"
  assert_not_contains "$T: does not say the work tree is kept" "$(lower "$OUT")" "the work tree is kept"
else
  t_skip 40 "D AC0 amend and fail-closed cases (the file system cannot make a hook executable)"
fi

t_summary
