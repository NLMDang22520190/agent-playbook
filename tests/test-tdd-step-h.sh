#!/usr/bin/env bash
# Tests for scripts/tdd-step.sh (v0.24.23 lane A, Full), part 2 of 3 (parts 1 and 3: test-tdd-step-g.sh, test-tdd-step-i.sh; slice S2 of .agents/handoff/01-spec.md):
#   AC1  the branch is compared before and after the test command: a changed branch is refused with nothing committed (red and green, default path and --baseline, with and without --commit)
# Shared setup: tdd-step-fixture.sh, tdd-step-d-fixture.sh and tdd-step-g-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/tdd-step-fixture.sh"
. "$(dirname "$0")/tdd-step-d-fixture.sh"
. "$(dirname "$0")/tdd-step-g-fixture.sh"

# ---------------------------------------------------------------------------------------------------------------
echo "AC1 the branch is compared before and after the test command: a changed branch is refused with nothing committed (red and green, default path and --baseline, with and without --commit)"
# branch_case LABEL KIND MODE FLAG PRE CMD -> 7 assertions. KIND red|green. PRE (a snippet, MAIN known) runs in R first, CMD (@MAIN@ = the branch name) is the test command's first part;
# every case changes only the branch, never the sha (the sha check of v0.24.22 would refuse a moved sha by itself).
branch_case() {
  local label="$1" kind="$2" mode="$3" flag="$4" pre="$5" cmd="$6" tag errl
  gprep "$mode"
  MAIN="$(git -C "$R" symbolic-ref --short HEAD)"
  ( cd "$R" && eval "$pre" ); REFS0="$(refs "$R")"
  cmd="${cmd//@MAIN@/$MAIN}"
  tag="$label ($mode, $kind, ${flag:-print})"
  if [ "$kind" = red ]; then
    run_red "$flag" sh -c "$cmd; exit 1"
  else
    rm -f "$R/tests/n.test.js"; printf 'module.exports = 3;\n' > "$R/src/impl.js"
    run_in "$R" bash "$STEP" green --base "$H0" --message "m" $flag ${BL:+--baseline "$BL"} -- sh -c "$cmd; exit 0"
  fi
  errl="$(lower "$(printf '%s\n' "$OUT" | grep -i 'nothing committed')")"
  assert_rc "$tag: exit 1" 1
  assert_contains "$tag: a message says nothing committed" "$errl" "nothing committed"
  assert_contains "$tag: that message says branch" "$errl" "branch"
  assert_eq "$tag: no commit on any branch (commit count over all refs)" "$N0" "$(allcount)"
  assert_eq "$tag: no test(red) or feat(green) commit in any branch" "" "$(git -C "$R" log --all --format=%s | grep -E 'test\(red\)|feat\(green\)'; true)"
  if [ -n "$flag" ]; then assert_not_contains "$tag: no RED= or committed: line" "$OUT" "RED="
  else assert_not_contains "$tag: the commit commands are not printed" "$OUT" "not committing (no --commit)"; fi
  if [ "$kind" = red ]; then assert_eq "$tag: the work tree is kept (the test file is still there)" 'test("n", () => {});' "$(cat "$R/tests/n.test.js")"
  else assert_eq "$tag: the work tree is kept (the implementation is still there)" 'module.exports = 3;' "$(cat "$R/src/impl.js")"; fi
}
for MODE in default baseline; do
  for FLAG in --commit ""; do
    branch_case "AC1 git checkout -b other" red "$MODE" "$FLAG" ":" "git checkout -q -b other"
    branch_case "AC1 git checkout other (an existing branch at the same commit)" red "$MODE" "$FLAG" "git branch other" "git checkout -q other"
    branch_case "AC1 git checkout --detach" red "$MODE" "$FLAG" ":" "git checkout -q --detach"
    branch_case "AC1 detached to a branch at the same commit" red "$MODE" "$FLAG" "git checkout -q --detach" "git checkout -q @MAIN@"
  done
  branch_case "AC1 green: git checkout -b other" green "$MODE" "--commit" ":" "git checkout -q -b other"
done


t_summary
