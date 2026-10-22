#!/usr/bin/env bash
# Tests for scripts/tdd-step.sh (v0.24.24 lane A, review fix round 1, slice R1, part 17 (after -v); review 05-review.md F3, decision D4 "Keep exit 1, print blob shas"):
#   A  D4 a pre-commit hook takes a judged change out of the work tree AND out of the commit: it reverts the role's edit of a tracked file (git checkout HEAD -- f), it removes the role's
#      new file (git rm --cached, rm), or it brings back a file the role deleted. The work tree then equals the commit C, so the step stays exit 1 (the undo is complete), but it must NOT
#      say "the work tree is kept": the role's work is not there. Each judged path that differs is printed with the blob sha of the role's content and the recovery line
#      a sh -c recovery line (any form; each row runs it; the blob is in the object store: git add wrote it); a judged deletion that was brought back gets rm -- <path>. Default path and --baseline.
#      The formatter-hook rows of tests/test-tdd-step-d.sh and -e.sh stay as they are (there the work tree holds what C holds and the message may stay).
# Shared setup: tdd-step-fixture.sh, tdd-step-d-fixture.sh, tdd-step-g-fixture.sh, tdd-step-n-fixture.sh and tdd-step-r-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/tdd-step-fixture.sh"
. "$(dirname "$0")/tdd-step-d-fixture.sh"
. "$(dirname "$0")/tdd-step-g-fixture.sh"
. "$(dirname "$0")/tdd-step-n-fixture.sh"
. "$(dirname "$0")/tdd-step-r-fixture.sh"

# pre-commit hooks (each marks that it ran)
HK_REVERT="$(mkhook w1 'touch .git/w-ran' 'git checkout -q HEAD -- tests/app.test.js')"
HK_RMNEW="$(mkhook w2 'touch .git/w-ran' 'git rm -q --cached tests/n.test.js' 'rm -f tests/n.test.js')"

# kept_not_claimed TAG -> the step is exit 1 as before, the commit is undone, and the message does not claim the work tree is kept
kept_not_claimed() {
  assert_eq "$1: the hook ran (the case is real)" "yes" "$([ -e "$R/.git/w-ran" ] && echo yes || echo no)"
  assert_rc "$1: exit 1" 1
  assert_not_contains "$1: does not say the work tree is kept" "$(lower "$OUT")" "the work tree is kept"
  assert_untouched "$1: the commit is undone" "$R" "$H0" "$N0"
  assert_eq "$1: the index file is restored byte for byte" "same" "$(same_idx)"
  assert_eq "$1: no test(red) commit in the log" "" "$(no_red_commit)"
}
# rec_line PATH -> the printed recovery line for PATH: two-space indent, sh -c SCRIPT sh MODE SHA PATH (the form is not pinned: the rows below run it)
rec_line() { printf '%s\n' "$OUT" | grep -E '^  sh -c ' | grep -F -- " $1" | head -n 1; }
# blob_line TAG PATH WANT -> the recovery line for PATH is printed; its sha (second word from the end) names a blob that holds the role's content WANT;
# running the line with sh -e in R brings WANT back into the work tree and leaves the index entries and the staged diff unchanged
blob_line() {
  local l sha before after rc s sb sa
  l="$(rec_line "$2")"
  sha="$(printf '%s\n' "$l" | awk '{print $(NF-1)}')"
  assert_contains "$1: a recovery line sh -c ... sh MODE SHA $2" "$l" "  sh -c "
  assert_eq "$1: that sha is a blob" "blob" "$(git -C "$R" cat-file -t "$sha" 2>/dev/null)"
  assert_eq "$1: that blob holds the role's content of $2" "$3" "$(git -C "$R" cat-file -p "$sha" 2>/dev/null)"
  s="$(mk_tmp)/recover.sh"; printf '%s\n' "$l" > "$s"
  before="$(git -C "$R" ls-files -s)"; sb="$(git -C "$R" diff --cached --name-status)"
  ( cd "$R" && sh -e "$s" ) >/dev/null 2>&1; rc=$?
  after="$(git -C "$R" ls-files -s)"; sa="$(git -C "$R" diff --cached --name-status)"
  assert_eq "$1: the recovery line runs without an error (sh -e)" "0" "$rc"
  assert_eq "$1: after the recovery $2 holds the role's content" "$3" "$(cat "$R/$2" 2>/dev/null)"
  assert_eq "$1: the recovery leaves the index entries unchanged" "$before" "$after"
  assert_eq "$1: the recovery stages nothing (git diff --cached is as before: the baseline fixture stages a file of its own)" "$sb" "$sa"
}

echo "A D4 a hook takes the role's work out of the work tree and the commit: exit 1, not kept, blob sha and recovery line"
if can_exec; then
  for MODE in default baseline; do
    T="A D4 pre-commit hook: git checkout HEAD -- tests/app.test.js reverts the role's edit ($MODE)"
    gprep "$MODE"; printf 'edited by the role\n' >> "$R/tests/app.test.js"; WANT="$(cat "$R/tests/app.test.js")"
    run_red --commit sh -c "$(hookcmd "$HK_REVERT")"
    kept_not_claimed "$T"
    assert_eq "$T: the edit is gone from the work tree (the case is real)" 'test("x", () => {});' "$(cat "$R/tests/app.test.js")"
    assert_contains "$T: names the path" "$OUT" "tests/app.test.js"
    blob_line "$T" tests/app.test.js "$WANT"

    T="A D4 pre-commit hook: git rm --cached and rm remove the role's new file ($MODE)"
    gprep "$MODE"; printf 'edited by the role\n' >> "$R/tests/app.test.js"; WANT='test("n", () => {});'
    run_red --commit sh -c "$(hookcmd "$HK_RMNEW")"
    kept_not_claimed "$T"
    assert_eq "$T: the new file is gone from the work tree (the case is real)" "no" "$([ -e "$R/tests/n.test.js" ] && echo yes || echo no)"
    blob_line "$T" tests/n.test.js "$WANT"

    T="A D4 pre-commit hook brings back the file the role deleted ($MODE)"
    gprep "$MODE"; rm -f "$R/tests/app.test.js"
    run_red --commit sh -c "$(hookcmd "$HK_REVERT")"
    kept_not_claimed "$T"
    assert_eq "$T: the deleted file is back on disk (the case is real)" "yes" "$([ -e "$R/tests/app.test.js" ] && echo yes || echo no)"
    assert_contains "$T: the recovery line is rm -- <path>" "$(printf '%s\n' "$OUT" | grep -F 'rm --')" "rm -- tests/app.test.js"
    assert_eq "$T: no sh -c recovery line for the deleted path (it has no blob)" "" "$(rec_line tests/app.test.js)"
  done
else
  t_skip 70 "A D4 cases (the file system cannot make a hook executable)"
fi

t_summary
