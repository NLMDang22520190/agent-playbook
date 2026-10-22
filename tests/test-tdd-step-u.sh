#!/usr/bin/env bash
# Tests for scripts/tdd-step.sh (v0.24.24 lane A, Full, slice S2, part 15 (after -t); spec 01-spec.md AC5, AC6 incl. "AC amendments, round 3", decisions D1 and D1a):
#   A  AC5 an untracked nested repository outside .agents/handoff/ is REFUSED before the test command runs (exit 1, "nested repository", the path, a hint to add it to .git/info/exclude
#      or .gitignore, "nothing committed"; the test command does not run; HEAD and the index are unchanged): at the top of tests/ and inside an untracked directory, on the default
#      path and on --baseline (a repository made before the baseline snapshot too, D1a), commit mode and print mode.
#   B  AC5 / N7 a staged gitlink that HEAD does not have (index mode 160000) is refused the same way.
#   C  AC5 unchanged rows (they pass before and after): a nested repository under .agents/handoff/, a submodule tracked in HEAD, an empty directory, a broken .git file.
# Shared setup: tdd-step-fixture.sh. Cases that already pass on v0.24.23 are named "unchanged".
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/tdd-step-fixture.sh"

# mkn DIR -> a git repository with one commit at DIR (made from DIR, so the outer repository is not touched)
mkn() {
  mkdir -p "$1" && ( cd "$1" && git init -q && git config user.email t@example.invalid && git config user.name tester && git config commit.gpgsign false \
    && printf 'a\n' > a && git add a && git commit -q -m s )
}
# uprep MODE [PRE] -> R, BL, MARK, IDXC, H0, N0. MODE default | baseline. PRE (a snippet run in R after the baseline pre-state is made but before the baseline snapshot, so it is
# "pre-existing") runs before snap; a role file tests/n.test.js is written after it. POST (a snippet) runs after the snapshot and the role file ("made by the role").
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
# urun FLAG -> tdd-step red in R; FLAG is --commit or empty; the test command makes a marker file outside the repository and fails (RED)
urun() { run_in "$R" bash "$STEP" red --message "m" $1 ${BL:+--baseline "$BL"} -- sh -c "touch '$MARK'; exit 1"; }
# urefuse TAG PATH -> the refusal checks
urefuse() {
  local t="$1" p="$2" lo; lo="$(lower "$OUT")"
  assert_rc "$t: exit 1" 1
  assert_contains "$t: says nested repository" "$lo" "nested repository"
  assert_contains "$t: names the path $p" "$lo" "$p"
  assert_contains "$t: hints at .git/info/exclude" "$lo" ".git/info/exclude"
  assert_contains "$t: hints at .gitignore" "$lo" ".gitignore"
  assert_contains "$t: says nothing committed" "$lo" "nothing committed"
  assert_no_path "$t: the test command did not run (no marker)" "$MARK"
  assert_eq "$t: HEAD unchanged" "$H0" "$(head_of "$R")"
  assert_eq "$t: commit count unchanged" "$N0" "$(count_of "$R")"
  assert_eq "$t: the index file is unchanged" "same" "$(if cmp -s "$IDXC" "$R/.git/index"; then echo same; else echo differ; fi)"
  assert_not_contains "$t: no RED= line" "$OUT" "RED="
}
# uok TAG COMMIT -> the step ran: the test command ran, no refusal; COMMIT 1 = a commit was made (RED=), 0 = print mode (HEAD unchanged)
uok() {
  local t="$1" c="$2" lo; lo="$(lower "$OUT")"
  assert_rc "$t: exit 0" 0
  assert_file "$t: the test command ran (marker)" "$MARK"
  assert_not_contains "$t: no nested repository refusal" "$lo" "nested repository"
  if [ "$c" = 1 ]; then
    assert_contains "$t: commits (RED=)" "$OUT" "RED="
    assert_eq "$t: one commit added" "$((N0 + 1))" "$(count_of "$R")"
  else
    assert_eq "$t: HEAD unchanged (print mode)" "$H0" "$(head_of "$R")"
  fi
}

NEWSUB='mkn tests/vendored-lib'
DEEPSUB='mkn tests/newdir/deep/vendored-lib'
GITLINK='mkn tests/vendored-lib; git add tests/vendored-lib'

# ---------------------------------------------------------------------------------------------------------------
# Each run costs about 0.7 s, so the matrix is thinned (no row repeats another's path x mode x kind combination more than needed): the whole suite stays near 10 s.
echo "A AC5 an untracked nested repository is refused before the test command (default path, --baseline pre-existing and made by the role; commit and print mode)"
P1="tests/vendored-lib"; P2="tests/newdir/deep/vendored-lib"
uprep default ":" "$NEWSUB";  urun --commit; urefuse "A AC5 top nested repo, default path, commit mode" "$P1"
uprep default ":" "$NEWSUB";  urun "";       urefuse "A AC5 top nested repo, default path, print mode" "$P1"
uprep default ":" "$DEEPSUB"; urun --commit; urefuse "A AC5 nested repo inside an untracked directory, default path, commit mode" "$P2"
uprep baseline ":" "$NEWSUB"; urun --commit; urefuse "A AC5 top nested repo made by the role, --baseline, commit mode" "$P1"
uprep baseline ":" "$DEEPSUB"; urun "";      urefuse "A AC5 nested repo inside an untracked directory made by the role, --baseline, print mode" "$P2"
uprep baseline "$NEWSUB";     urun --commit; urefuse "A AC5 D1a top nested repo made BEFORE the baseline snapshot, --baseline, commit mode" "$P1"
uprep baseline "$DEEPSUB";    urun "";       urefuse "A AC5 D1a nested repo inside an untracked directory made BEFORE the baseline snapshot, --baseline, print mode" "$P2"

echo "B AC5 a staged gitlink absent from HEAD (index mode 160000) is refused"
uprep default ":" "$GITLINK"
assert_contains "B the case is real: the index holds mode 160000 for the path" "$(git -C "$R" ls-files -s tests/vendored-lib)" "160000"
urun --commit; urefuse "B AC5 staged gitlink, default path, commit mode" "$P1"
uprep baseline "$GITLINK"
urun "";       urefuse "B AC5 staged gitlink made before the baseline snapshot, --baseline, print mode" "$P1"

echo "C AC5 unchanged rows (one repository holding them all): a nested repository under .agents/handoff/, a submodule tracked in HEAD, an empty directory, a broken .git file"
UNCH="mkdir -p .agents/handoff tests/emptydir; mkn .agents/handoff/sub; mkn tests/subm; git add tests/subm; git commit -q -m addsub"
UNCHP="mkdir -p tests/brk; printf 'gitdir: /nonexistent/xx
' > tests/brk/.git"
for mode in default baseline; do
  for fl in --commit ""; do
    m="print"; c=0; [ -n "$fl" ] && { m="commit"; c=1; }
    uprep "$mode" "$UNCH" "$UNCHP"
    assert_contains "C the case is real: HEAD tracks a gitlink for tests/subm ($mode, $m)" "$(git -C "$R" ls-tree HEAD tests/subm)" "160000"
    urun "$fl"; uok "C unchanged ($mode path, $m mode)" "$c"
    [ "$c" = 1 ] && assert_not_contains "C unchanged ($mode path, $m mode): the commit holds nothing of .agents/handoff/" "$(committed "$R")" ".agents/handoff"
  done
done

t_summary
