#!/usr/bin/env bash
# Tests for scripts/tdd-step.sh (v0.24.24 lane A, review fix round 1, slice R1, part 16 (after -u); review 05-review.md F1, F2, F4, F5, F6, F8, decisions D4):
#   A  F1 a pre-commit hook takes the role files out of the work tree (reset --hard, then a checkout of another branch) and fails git commit: the step exits 3 and says the role files
#      are no longer in the work tree, never "the work tree is kept". Default path and --baseline. (Pins the lost decision on the commit-failed path.)
#   B  F2 the report of git commit names a commit with the step subject whose PARENT is not the pre-run HEAD (a git shim on PATH rewrites the report line): it is rejected; with the
#      reflog off C is unknown ("look in git reflog HEAD") and the fake commit is never named; with the reflog on the reflog finds the real C.
#   C  F4 git commit fails with nothing to commit (the role changed nothing): git's own stdout line is shown, the exit code stays 3.
#   D  F5 a tracked DIRECTORY replaced by a nested repository staged as a gitlink (160000 in the index, a tree in HEAD) is refused before the test command like any other nested repository.
#   E  F6 with core.abbrev=4 (short report shas) and the reflogs off, the right full C is still named.
#   F  F8 a failing git update-index --index-info inside the lost check counts as lost (exit 3, fail closed).
# Shared setup: tdd-step-fixture.sh, tdd-step-d-fixture.sh, tdd-step-g-fixture.sh, tdd-step-n-fixture.sh and tdd-step-r-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/tdd-step-fixture.sh"
. "$(dirname "$0")/tdd-step-d-fixture.sh"
. "$(dirname "$0")/tdd-step-g-fixture.sh"
. "$(dirname "$0")/tdd-step-n-fixture.sh"
. "$(dirname "$0")/tdd-step-r-fixture.sh"

# pre-commit hooks. HK_F1 loses the role files and fails git commit
HK_F1="$(mkhook v1 'touch .git/v1-ran' 'git reset -q --hard' 'git checkout -q existing' 'exit 1')"
# GITSHIM_IDXINFO: once the post-commit hook ran (.git/csha exists), git update-index --index-info fails with 9 (the temp index of the lost check cannot be built)
GITSHIM_IDXINFO='#!/bin/sh
sub=""; skip=0
for a in "$@"; do
  if [ "$skip" = 1 ]; then skip=0; continue; fi
  case "$a" in -c) skip=1 ;; -*) ;; *) sub="$a"; break ;; esac
done
if [ -f .git/csha ] && [ "$sub" = update-index ]; then
  case "$*" in *--index-info*) echo "stub: git update-index --index-info failed" >&2; exit 9 ;; esac
fi
exec "@REAL@" "$@"'

# mkn DIR -> a git repository with one commit at DIR (made from DIR, so the outer repository is not touched)
mkn() {
  mkdir -p "$1" && ( cd "$1" && git init -q && git config user.email t@example.invalid && git config user.name tester && git config commit.gpgsign false \
    && printf 'a\n' > a && git add a && git commit -q -m s )
}
# uprep MODE [PRE] [POST] -> R, BL, MARK, IDXC, H0, N0. PRE runs in R before the baseline snapshot (and so is "pre-existing"), POST after the role file tests/n.test.js is written.
uprep() {
  local mode="$1" pre="${2:-:}" post="${3:-:}"
  R="$(fresh)"; BL=""
  [ "$mode" = baseline ] && dirty "$R"
  ( cd "$R" && eval "$pre" ) >/dev/null 2>&1
  [ "$mode" = baseline ] && BL="$(snap "$R")"
  printf 'test("n", () => {});\n' > "$R/tests/n.test.js"
  ( cd "$R" && eval "$post" ) >/dev/null 2>&1
  MARK="$(mk_tmp)/ran"; IDXC="$(mk_tmp)/index.copy"
  cp "$R/.git/index" "$IDXC"; H0="$(head_of "$R")"; N0="$(count_of "$R")"
}
# urun FLAG -> tdd-step red in R; the test command makes a marker file outside the repository and fails (RED)
urun() { run_in "$R" bash "$STEP" red --message "m" $1 ${BL:+--baseline "$BL"} -- sh -c "touch '$MARK'; exit 1"; }

echo "A F1 a pre-commit hook loses the role files and fails git commit: lost, not kept (default path and --baseline)"
if can_exec; then
  for MODE in default baseline; do
    T="A F1 pre-commit hook: git reset --hard, git checkout existing, exit 1 ($MODE)"
    gprep "$MODE"; run_red --commit sh -c "$(hookcmd "$HK_F1")"
    assert_eq "$T: the hook ran (the case is real)" "yes" "$([ -e "$R/.git/v1-ran" ] && echo yes || echo no)"
    assert_eq "$T: the role file is gone from the work tree (the case is real)" "no" "$([ -e "$R/tests/n.test.js" ] && echo yes || echo no)"
    lost_unknown "$T"; a2_end "$T"
    assert_contains "$T: says the role files are no longer in the work tree" "$(lower "$OUT")" "no longer in the work tree"
  done
else
  t_skip 30 "A F1 commit-failed lost cases (the file system cannot make a hook executable)"
fi

echo "B F2 a report naming a commit with the step subject but another parent is rejected"
if can_exec; then
  T="B F2 reflogs off, the report names a commit with the step subject on the parent of the pre-run HEAD"
  gprep default "$ROFF; git commit-tree 'HEAD^{tree}' -p existing -m 'test(red): m' > .git/xsha"; D="$(stubdir git "$GITSHIM_REPORT")"
  X="$(cat "$R/.git/xsha")"
  run_red_p "$D" --commit sh -c "$(hookcmd "$HK_RESET" post-commit)"
  lost_unknown "$T"; a2_end "$T"
  assert_eq "$T: the fake exists with the step subject and a parent that is not the pre-run HEAD (the case is real)" "test(red): m $E0" "$(git -C "$R" log -1 --format='%s %P' "$X" 2>/dev/null)"
  assert_not_contains "$T: the fake commit is never named" "$OUT" "$(s7 "$X")"

  # a MERGE commit (first parent = the pre-run HEAD, second = another commit) with the step subject: report_c accepts only a SINGLE-parent commit (rev-list --parents), not "HEAD^ is the pre-run HEAD"
  T="B F2 reflogs off, the report names a merge commit with the step subject whose first parent is the pre-run HEAD"
  gprep default "$ROFF; git commit-tree 'HEAD^{tree}' -p HEAD -p existing -m 'test(red): m' > .git/xsha"; D="$(stubdir git "$GITSHIM_REPORT")"
  X="$(cat "$R/.git/xsha")"
  run_red_p "$D" --commit sh -c "$(hookcmd "$HK_RESET" post-commit)"
  lost_unknown "$T"; a2_end "$T"
  assert_eq "$T: the fake is a merge with the step subject, the pre-run HEAD first and another commit second (the case is real)" "test(red): m $H0 $E0" "$(git -C "$R" log -1 --format='%s %P' "$X" 2>/dev/null)"
  assert_not_contains "$T: the merge commit is never named" "$OUT" "$(s7 "$X")"

  T="B F2 reflog on, the same report: the reflog finds the real C"
  gprep default "git commit-tree 'HEAD^{tree}' -p existing -m 'test(red): m' > .git/xsha"; D="$(stubdir git "$GITSHIM_REPORT")"
  X="$(cat "$R/.git/xsha")"
  run_red_p "$D" --commit sh -c "$(hookcmd "$HK_RESET" post-commit)"
  a2_lost "$T"; a2_end "$T"
  assert_not_contains "$T: the fake commit is never named" "$OUT" "$(s7 "$X")"
else
  t_skip 42 "B F2 wrong-parent report cases (the file system cannot make a hook executable)"
fi

echo "C F4 git commit fails with nothing to commit: git's own line is shown, exit 3"
if can_exec; then
  # the role changed nothing: git add -A stages nothing and git commit exits 1 with its report on stdout (a pre-commit hook cannot cause this: git decides before the hook runs)
  T="C F4 default path, the role changed nothing (git commit has nothing to commit)"
  gprep default; rm -f "$R/tests/n.test.js"
  run_red --commit sh -c "exit 1"
  assert_eq "$T: the work tree is clean (the case is real)" "" "$(git -C "$R" status --porcelain)"
  assert_rc "$T: exit 3" 3
  case "$(lower "$OUT")" in
    *"nothing to commit"* | *"nothing added to commit"* | *"no changes added to commit"*) t_ok "$T: git's own nothing-to-commit line is in the output" ;;
    *) t_bad "$T: git's own nothing-to-commit line is in the output" "missing in [$OUT]" ;;
  esac
  assert_not_contains "$T: not reported as a committed step" "$OUT" "RED="
  assert_untouched "$T: nothing was committed" "$R" "$H0" "$N0"
else
  t_skip 5 "C F4 nothing-to-commit case (the file system cannot make a hook executable)"
fi

echo "D F5 a tracked directory replaced by a staged nested repository (gitlink) is refused"
VEND_PRE='mkdir -p tests/vend && printf "a\n" > tests/vend/a.txt && git add tests/vend && git commit -q -m vend'
VEND_POST='git rm -rq --cached tests/vend; rm -rf tests/vend; mkn tests/vend; git add tests/vend'
for MODE in default baseline; do
  T="D F5 tests/vend (a tree in HEAD) is now a nested repository staged as a gitlink ($MODE)"
  uprep "$MODE" "$VEND_PRE" "$VEND_POST"
  assert_contains "$T: the index holds mode 160000 for the path (the case is real)" "$(git -C "$R" ls-files -s tests/vend)" "160000"
  assert_contains "$T: HEAD holds a tree at the path (the case is real)" "$(git -C "$R" ls-tree HEAD tests/vend)" "tree"
  urun --commit
  assert_rc "$T: exit 1" 1
  assert_contains "$T: says nested repository" "$(lower "$OUT")" "nested repository"
  assert_no_path "$T: the test command did not run (no marker)" "$MARK"
  assert_eq "$T: HEAD unchanged" "$H0" "$(head_of "$R")"
  assert_eq "$T: commit count unchanged" "$N0" "$(count_of "$R")"
done

echo "E F6 core.abbrev=4: the right full C is still named"
if can_exec; then
  for MODE in default baseline; do
    T="E F6 core.abbrev=4, reflogs off, post-commit hook: git reset --hard HEAD~1 ($MODE)"
    gprep "$MODE" "$ROFF; git config core.abbrev 4"; run_red --commit sh -c "$(hookcmd "$HK_RESET" post-commit)"
    a2_lost "$T"; a2_end "$T"
    C="$(cat "$R/.git/csha" 2>/dev/null)"
    SH="$(git -C "$R" rev-parse --short "$C" 2>/dev/null)"
    assert_contains "$T: the message names the full C" "$OUT" "$C"
    assert_eq "$T: the case is real (a short sha of C is shorter than the 7 digits the report parser needs)" "yes" "$([ "${#SH}" -gt 0 ] && [ "${#SH}" -lt 7 ] && echo yes || echo no)"
    assert_eq "$T: C is the test(red) commit on the pre-run HEAD" "test(red): m $H0" "$(git -C "$R" log -1 --format='%s %P' "$C" 2>/dev/null)"
  done
else
  t_skip 40 "E F6 abbrev cases (the file system cannot make a hook executable)"
fi

echo "F F8 a failing git update-index --index-info inside the lost check is lost (fail closed)"
if can_exec; then
  T="F F8 post-commit hook: mixed reset (nothing is lost), but the lost check cannot build its temp index"
  gprep default; D="$(stubdir git "$GITSHIM_IDXINFO")"
  run_red_p "$D" --commit sh -c "$(hookcmd "$HK_MIXED" post-commit)"
  a2_lost "$T"; a2_end "$T"
  assert_eq "$T: the role file is still on disk (the case is real: it was not lost)" 'test("n", () => {});' "$(cat "$R/tests/n.test.js" 2>/dev/null)"
else
  t_skip 14 "F F8 fail-closed case (the file system cannot make a hook executable)"
fi

t_summary
