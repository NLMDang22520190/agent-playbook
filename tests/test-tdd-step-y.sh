#!/usr/bin/env bash
# Tests for scripts/tdd-step.sh (v0.24.25, leftovers of the v0.24.24 lane A review rounds 2-3: message and recovery-line details; no exit code or commit model change):
#   A  a judged gitlink (160000): the recovery line is git -C PATH checkout SHA, not a no-op sh -c line (default path and --baseline)
#   B  the recovery lines say they work from the repository top level, before the lines (the sh -c lines and the git checkout C -- . line)
#   C  the sh -c recovery line refuses when PATH is a directory (not a symlink to one): nothing is deleted; a symlink to a directory is still replaced
#   D  C unknown: the rm -- lines of judged deletions that came back are printed too
#   E  the header of tdd-step.sh no longer says "is therefore never reached"
#   F  git commit gets no -c core.abbrev=40: a hook does not see it in GIT_CONFIG_PARAMETERS (default path and --baseline); the abbrev=4 row stays in test-tdd-step-v.sh
# Shared setup: tdd-step-fixture.sh, tdd-step-d-fixture.sh, tdd-step-g-fixture.sh, tdd-step-n-fixture.sh and tdd-step-r-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/tdd-step-fixture.sh"
. "$(dirname "$0")/tdd-step-d-fixture.sh"
. "$(dirname "$0")/tdd-step-g-fixture.sh"
. "$(dirname "$0")/tdd-step-n-fixture.sh"
. "$(dirname "$0")/tdd-step-r-fixture.sh"

HK_REVERT="$(mkhook y1 'touch .git/y-ran' 'git checkout -q HEAD -- tests/app.test.js')"
# a pre-commit hook that moves the nested repository tests/sub one commit back and stages that gitlink
HK_SUB="$(mkhook y2 'touch .git/y-ran' 'git -C tests/sub checkout -q --detach HEAD~1' 'git update-index --cacheinfo "160000,$(git -C tests/sub rev-parse HEAD),tests/sub"')"
# a pre-commit hook that records the config the commit passes to hooks
HK_GCP="$(mkhook y3 'touch .git/y-ran' 'printf "%s" "${GIT_CONFIG_PARAMETERS-}" > .git/gcp')"

# SUBPRE -> a snippet (gprep PRE): tests/sub is a nested repository with two commits, tracked in HEAD as a gitlink at the first
SUBPRE='mkdir -p tests/sub && ( cd tests/sub && git init -q && git config user.email t@example.invalid && git config user.name tester && git config commit.gpgsign false && printf a > a && git add a && git commit -q -m s1 ) && git add tests/sub 2>/dev/null && git commit -q -m sub && git -C tests/sub commit -q --allow-empty -m s2'
# can_link as in test-tdd-step-x.sh
can_link() { local d; d="$(mk_tmp)"; ln -s target "$d/l" 2>/dev/null && [ -L "$d/l" ] && [ "$(readlink "$d/l")" = target ]; }
rec_sh() { printf '%s\n' "$OUT" | grep -E '^  sh -c ' | grep -F -- " $1" | head -n 1; }
# run_line LINE -> runs the recovery line with sh -e in R, sets RLRC
run_line() { local s; s="$(mk_tmp)/rl.sh"; printf '%s\n' "$1" > "$s"; ( cd "$R" && sh -e "$s" ) >"$s.out" 2>&1; RLRC=$?; RLOUT="$(cat "$s.out")"; }

echo "A a judged gitlink: git -C PATH checkout SHA"
if can_exec; then
  for MODE in default baseline; do
    T="A gitlink ($MODE)"
    gprep "$MODE" "$SUBPRE"; S2="$(git -C "$R/tests/sub" rev-parse HEAD)"; S1="$(git -C "$R/tests/sub" rev-parse HEAD~1)"
    run_red --commit sh -c "$(hookcmd "$HK_SUB")"
    assert_eq "$T: the hook ran (the case is real)" "yes" "$([ -e "$R/.git/y-ran" ] && echo yes || echo no)"
    assert_eq "$T: the nested repository is at the first commit (the case is real)" "$S1" "$(git -C "$R/tests/sub" rev-parse HEAD)"
    assert_rc "$T: exit 1" 1
    assert_contains "$T: a line git -C tests/sub checkout SHA" "$OUT" "  git -C tests/sub checkout $S2"
    assert_eq "$T: no sh -c line for the gitlink (checkout-index skips gitlinks)" "" "$(rec_sh tests/sub)"
    run_line "$(printf '%s\n' "$OUT" | grep -F '  git -C tests/sub checkout ' | head -n 1)"
    assert_eq "$T: the line runs without an error" "0" "$RLRC"
    assert_eq "$T: the nested repository is back at the judged commit" "$S2" "$(git -C "$R/tests/sub" rev-parse HEAD)"
  done
else
  t_skip 12 "A gitlink (the file system cannot make a hook executable)"
fi

echo "B the lines say they run from the top level"
if can_exec; then
  T="B sh -c lines"
  gprep default; printf 'edited by the role\n' >> "$R/tests/app.test.js"
  run_red --commit sh -c "$(hookcmd "$HK_REVERT")"
  assert_rc "$T: exit 1" 1
  LN_TOP="$(printf '%s\n' "$OUT" | grep -n -i 'top level' | head -n 1 | cut -d: -f1)"; LN_REC="$(printf '%s\n' "$OUT" | grep -n '^  sh -c ' | head -n 1 | cut -d: -f1)"
  assert_eq "$T: a recovery line is printed (the case is real)" "yes" "$([ -n "$LN_REC" ] && echo yes || echo no)"
  assert_eq "$T: a top level line is printed" "yes" "$([ -n "$LN_TOP" ] && echo yes || echo no)"
  assert_eq "$T: it comes before the first recovery line" "yes" "$([ -n "$LN_TOP" ] && [ -n "$LN_REC" ] && [ "$LN_TOP" -lt "$LN_REC" ] && echo yes || echo no)"

  T="B git checkout C -- . line"
  gprep default; run_red --commit sh -c "$(hookcmd "$HK_EXISTC" post-commit)"
  a2_lost "$T"
  LN_TOP="$(printf '%s\n' "$OUT" | grep -n -i 'top level' | head -n 1 | cut -d: -f1)"; LN_REC="$(printf '%s\n' "$OUT" | grep -n -F -- ' -- .' | head -n 1 | cut -d: -f1)"
  assert_eq "$T: a top level line comes before the line" "yes" "$([ -n "$LN_TOP" ] && [ -n "$LN_REC" ] && [ "$LN_TOP" -lt "$LN_REC" ] && echo yes || echo no)"
else
  t_skip 8 "B top level (the file system cannot make a hook executable)"
fi

echo "C the sh -c line refuses a directory at PATH"
if can_exec; then
  T="C directory at the judged path"
  gprep default; printf 'edited by the role\n' >> "$R/tests/app.test.js"
  run_red --commit sh -c "$(hookcmd "$HK_REVERT")"
  L="$(rec_sh tests/app.test.js)"
  assert_eq "$T: the recovery line is printed (the case is real)" "yes" "$([ -n "$L" ] && echo yes || echo no)"
  rm -f "$R/tests/app.test.js"; mkdir "$R/tests/app.test.js"; printf 'keep\n' > "$R/tests/app.test.js/keep.txt"
  run_line "$L"
  assert_eq "$T: the line fails" "yes" "$([ "$RLRC" -ne 0 ] && echo yes || echo no)"
  assert_eq "$T: the directory and its file are still there" "keep" "$(cat "$R/tests/app.test.js/keep.txt" 2>/dev/null)"
  assert_contains "$T: it says why (directory)" "$(lower "$RLOUT")" "directory"

  if can_link; then
    T="C symlink to a directory at the judged path"
    rm -rf "$R/tests/app.test.js"; mkdir -p "$R/tests/d2"; printf 'other\n' > "$R/tests/d2/o.txt"; ln -s d2 "$R/tests/app.test.js"
    run_line "$L"
    assert_eq "$T: the line runs without an error" "0" "$RLRC"
    assert_eq "$T: the path is a regular file again, not a link" "file" "$([ -f "$R/tests/app.test.js" ] && [ ! -L "$R/tests/app.test.js" ] && echo file || echo other)"
    assert_eq "$T: the directory the link pointed at is untouched" "other" "$(cat "$R/tests/d2/o.txt" 2>/dev/null)"
  else
    t_skip 3 "C symlink (no symlinks here)"
  fi
else
  t_skip 7 "C directory (the file system cannot make a hook executable)"
fi

echo "D C unknown: the rm -- lines are printed too"
if can_exec; then
  T="D reflogs off, the report names a wrong commit, post-commit git reset --hard HEAD~1, the role deleted tests/app.test.js"
  gprep default "$ROFF; git commit-tree 'HEAD^{tree}' -p existing -m 'test(red): m' > .git/xsha"; rm -f "$R/tests/app.test.js"
  DS="$(stubdir git "$GITSHIM_REPORT")"
  run_red_p "$DS" --commit sh -c "$(hookcmd "$HK_RESET" post-commit)"
  lost_unknown "$T"
  assert_eq "$T: the deleted file is back on disk (the case is real)" "yes" "$([ -e "$R/tests/app.test.js" ] && echo yes || echo no)"
  assert_contains "$T: a line rm -- tests/app.test.js" "$OUT" "rm -- tests/app.test.js"
else
  t_skip 5 "D unknown C (the file system cannot make a hook executable)"
fi

echo "E the header wording"
assert_eq "E the header does not say never reached" "0" "$(grep -c 'never reached' "$STEP")"

echo "F no core.abbrev=40 for hooks"
if can_exec; then
  for MODE in default baseline; do
    T="F pre-commit hook records GIT_CONFIG_PARAMETERS ($MODE)"
    gprep "$MODE"; run_red --commit sh -c "$(hookcmd "$HK_GCP")"
    assert_eq "$T: the hook ran (the case is real)" "yes" "$([ -e "$R/.git/y-ran" ] && echo yes || echo no)"
    assert_rc "$T: exit 0 (RED committed)" 0
    assert_not_contains "$T: no abbrev in the hook's config" "$(cat "$R/.git/gcp" 2>/dev/null)" "abbrev"
  done
else
  t_skip 6 "F hook config (the file system cannot make a hook executable)"
fi

t_summary
