#!/usr/bin/env bash
# Tests for scripts/tdd-step.sh (AC3): the middle part of test-tdd-step.sh (split in v0.24.21 so that it is not the floor of a CI shard), from
# "AC4 --baseline without --commit: prints literal-pathspec commands with quoted paths" to "AC4 (fix 4) --baseline: the first gate output passes through". Shared setup: tdd-step-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/tdd-step-fixture.sh"

echo "AC4 --baseline: a deleted role path is committed"
R="$(fresh)"; dirty "$R"; BL="$(snap "$R")"
rm "$R/tests/app.test.js"
BS0="$(bstate "$R")"
run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c 'exit 1'
assert_rc "AC4 deleted role path: exit 0" 0
assert_eq "AC4 deleted role path: the deletion is committed" "tests/app.test.js" "$(committed "$R")"
assert_eq "AC4 deleted role path: gone from HEAD" "" "$(noeol_ls "$R" | grep -x 'tests/app.test.js')"
assert_eq "AC4 deleted role path: baseline paths untouched" "$BS0" "$(bstate "$R")"

echo "AC4 --baseline: both sides of a rename are committed"
R="$(fresh)"; dirty "$R"; BL="$(snap "$R")"
git -C "$R" mv tests/app.test.js tests/renamed.test.js
BS0="$(bstate "$R")"
run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c 'exit 1'
assert_rc "AC4 rename: exit 0" 0
assert_eq "AC4 rename: old and new path are in the commit" "tests/app.test.js
tests/renamed.test.js" "$(committed "$R")"
assert_eq "AC4 rename: HEAD holds the new name" "tests/renamed.test.js" "$(noeol_ls "$R" | grep -x 'tests/renamed.test.js')"
assert_eq "AC4 rename: HEAD no longer holds the old name" "" "$(noeol_ls "$R" | grep -x 'tests/app.test.js')"
assert_eq "AC4 rename: baseline paths untouched" "$BS0" "$(bstate "$R")"

echo "AC4 --baseline: an untracked directory with a baseline file and a role file"
R="$(fresh)"; mkdir -p "$R/pkg"; printf 'pre-existing\n' > "$R/pkg/base.txt"; dirty "$R"; BL="$(snap "$R")"
printf 'test("n", () => {});\n' > "$R/pkg/role.test.js"
run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c 'exit 1'
assert_rc "AC4 untracked dir: exit 0" 0
assert_eq "AC4 untracked dir: only the role file is committed" "pkg/role.test.js" "$(committed "$R")"
assert_contains "AC4 untracked dir: the baseline file stays untracked" "$(git -C "$R" status --porcelain --untracked-files=all)" "?? pkg/base.txt"
assert_eq "AC4 untracked dir: the baseline file is intact" "pre-existing" "$(cat "$R/pkg/base.txt")"

echo "AC4 --baseline: a path with a space"
R="$(fresh)"; dirty "$R"; BL="$(snap "$R")"
printf 'test("n", () => {});\n' > "$R/tests/a b.test.js"
run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c 'exit 1'
assert_rc "AC4 space in a path: exit 0" 0
assert_eq "AC4 space in a path: committed as one path" "tests/a b.test.js" "$(committed "$R")"

echo "AC4 --baseline: a path with a TAB"
TABN="tests/tab"$'\t'"here.test.js"
if can_name "tab"$'\t'"x"; then
  R="$(fresh)"; dirty "$R"; BL="$(snap "$R")"
  printf 'test("n", () => {});\n' > "$R/$TABN"
  BS0="$(bstate "$R")"
  run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c 'exit 1'
  assert_rc "AC4 TAB in a path: exit 0" 0
  assert_eq "AC4 TAB in a path: committed with its exact name" "$TABN" "$(committed "$R")"
  assert_eq "AC4 TAB in a path: baseline paths untouched" "$BS0" "$(bstate "$R")"
else
  t_skip 3 "AC4 TAB in a path (the file system refuses a TAB in a name)"
fi

echo "AC4 --baseline: a control character in a path commits nothing"
CTLB="$(printf '\033')"   # ESC: a control byte other than TAB
CTLN="tests/c${CTLB}d.test.js"
if can_name "c${CTLB}d"; then
  R="$(fresh)"; dirty "$R"; BL="$(snap "$R")"; H0="$(head_of "$R")"; N0="$(count_of "$R")"
  printf 'test("n", () => {});\n' > "$R/tests/ok.test.js"
  printf 'test("n", () => {});\n' > "$R/$CTLN"
  BS0="$(bstate "$R")"
  run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c 'exit 1'
  assert_rc "AC4 control character: exit 1" 1
  assert_contains "AC4 control character: tells the user to commit by hand" "$(lower "$OUT")" "by hand"
  assert_untouched "AC4 control character: nothing committed" "$R" "$H0" "$N0"
  assert_eq "AC4 control character: baseline paths untouched" "$BS0" "$(bstate "$R")"
else
  t_skip 5 "AC4 control character in a path (the file system refuses it)"
fi

echo "AC4 --baseline: a role file named like a pathspec cannot pull in a baseline path"
GLOBN=':(glob)*.txt'
if can_name "$GLOBN"; then
  R="$(fresh)"
  printf 'one\n' > "$R/x.txt"; git -C "$R" add x.txt; git -C "$R" commit -q -m "add x.txt"
  dirty "$R"; printf 'two\n' >> "$R/x.txt"; BL="$(snap "$R")"; BASE="$(head_of "$R")"
  printf 'role\n' > "$R/$GLOBN"
  BS0="$(bstate "$R")"; X0="$(git -C "$R" diff -- x.txt)"
  run_in "$R" bash "$STEP" green --base "$BASE" --message "m" --commit --baseline "$BL" -- true
  assert_rc "AC4 pathspec-like name: exit 0" 0
  assert_eq "AC4 pathspec-like name: only that file is committed" "$GLOBN" "$(committed "$R")"
  assert_eq "AC4 pathspec-like name: the modified baseline x.txt is still an uncommitted edit" "$X0" "$(git -C "$R" diff -- x.txt)"
  assert_eq "AC4 pathspec-like name: other baseline paths untouched" "$BS0" "$(bstate "$R")"
else
  t_skip 4 "AC4 pathspec-like file name (the file system refuses : and *)"
fi

echo "AC4 --baseline: an empty role list commits nothing"
R="$(fresh)"; dirty "$R"; BL="$(snap "$R")"; H0="$(head_of "$R")"; N0="$(count_of "$R")"
BS0="$(bstate "$R")"
run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c 'exit 1'
assert_rc "AC4 empty role list: exit 1" 1
assert_contains "AC4 empty role list: says there is nothing of the role's to commit" "$OUT" "nothing of the role's to commit"
assert_untouched "AC4 empty role list: nothing committed (the staged baseline is not swept in)" "$R" "$H0" "$N0"
assert_eq "AC4 empty role list: baseline paths untouched" "$BS0" "$(bstate "$R")"

echo "AC4 --baseline: the test command must not change what is committed"
R="$(fresh)"; dirty "$R"; BL="$(snap "$R")"; H0="$(head_of "$R")"; N0="$(count_of "$R")"
printf 'test("n", () => {});\n' > "$R/tests/new.test.js"
run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c 'echo tampered >> src/app.js; exit 1'
assert_rc "AC4 the test command edits a baseline file: exit 1" 1
assert_untouched "AC4 the test command edits a baseline file: nothing committed" "$R" "$H0" "$N0"

R="$(fresh)"; dirty "$R"; BL="$(snap "$R")"; H0="$(head_of "$R")"; N0="$(count_of "$R")"
printf 'test("n", () => {});\n' > "$R/tests/new.test.js"
run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c 'echo gen > tests/generated.test.js; exit 1'
assert_rc "AC4 the test command writes a new file: exit 1" 1
assert_untouched "AC4 the test command writes a new file: nothing committed" "$R" "$H0" "$N0"

R="$(fresh)"; dirty "$R"; BL="$(snap "$R")"; N0="$(count_of "$R")"
printf 'test("n", () => {});\n' > "$R/tests/new.test.js"
run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c 'echo z > tests/z.test.js; git add tests/z.test.js; git commit -q -m sneak -- tests/z.test.js; exit 1'
assert_rc "AC4 the test command commits a new file: exit 1" 1
assert_eq "AC4 the test command commits a new file: HEAD moved by that commit only" "$((N0 + 1))" "$(count_of "$R")"
assert_eq "AC4 the test command commits a new file: that commit is the last one" "sneak" "$(subject "$R")"
assert_eq "AC4 the test command commits a new file: tests/new.test.js not committed" "" "$(noeol_ls "$R" | grep -x 'tests/new.test.js')"

echo "AC4 --baseline: .agents/handoff/ is never committed"
R="$(fresh)"; dirty "$R"; BL="$(snap "$R")"
mkdir -p "$R/.agents/handoff"; printf 'ev\n' > "$R/.agents/handoff/evidence.log"; printf 'n\n' > "$R/.agents/handoff/02-tests.md"
printf 'test("n", () => {});\n' > "$R/tests/new.test.js"
run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c 'exit 1'
assert_rc "AC4 handoff present: exit 0" 0
assert_eq "AC4 handoff present: only the test file is committed" "tests/new.test.js" "$(committed "$R")"
assert_eq "AC4 handoff present: no handoff file tracked" "" "$(git -C "$R" ls-files .agents/handoff)"
assert_file "AC4 handoff present: the evidence file is still in the work tree" "$R/.agents/handoff/evidence.log"

echo "AC4 --baseline without --commit: prints literal-pathspec commands with quoted paths"
R="$(fresh)"; dirty "$R"; BL="$(snap "$R")"; H0="$(head_of "$R")"; N0="$(count_of "$R")"
printf 'test("n", () => {});\n' > "$R/tests/a b.test.js"
printf 'test("x", () => { /* edited */ });\n' > "$R/tests/app.test.js"
BS0="$(bstate "$R")"
run_in "$R" bash "$STEP" red --message "m" --baseline "$BL" -- sh -c 'exit 1'
assert_rc "AC4 no --commit: exit 0" 0
assert_untouched "AC4 no --commit: nothing committed" "$R" "$H0" "$N0"
assert_contains "AC4 no --commit: the add step is printed, literal and with --" "$OUT" "GIT_LITERAL_PATHSPECS=1 git add -- "
assert_contains "AC4 no --commit: the commit step is printed, literal" "$OUT" "GIT_LITERAL_PATHSPECS=1 git commit -m "
assert_contains "AC4 no --commit: a path with a space is shell-quoted (printf %q)" "$OUT" 'tests/a\ b.test.js'
assert_contains "AC4 no --commit: the tracked role path is listed" "$OUT" "tests/app.test.js"
assert_not_contains "AC4 no --commit: not the blanket git add -A" "$OUT" "git add -A"
assert_eq "AC4 no --commit: baseline paths untouched" "$BS0" "$(bstate "$R")"
R="$(fresh)"; dirty "$R"; BL="$(snap "$R")"
printf 'test("x", () => { /* edited */ });\n' > "$R/tests/app.test.js"
run_in "$R" bash "$STEP" red --message "m" --baseline "$BL" -- sh -c 'exit 1'
assert_not_contains "AC4 no --commit, only tracked role paths: no git add step" "$OUT" "git add"
assert_contains "AC4 no --commit, only tracked role paths: the literal commit is printed" "$OUT" "GIT_LITERAL_PATHSPECS=1 git commit -m "

echo "AC5 the default path (no --base, no --baseline) is unchanged (characterization, passes before the change)"
R="$(fresh)"
printf 'test("a", () => {});\n' > "$R/tests/new.test.js"
printf 'test("x", () => { /* edited */ });\n' > "$R/tests/app.test.js"
run_in "$R" bash "$STEP" red --message "m" -- sh -c 'exit 1'
assert_contains "AC5 default red prints the blanket commit command" "$OUT" 'git add -A && git commit -m "test(red): m"'
assert_not_contains "AC5 default red does not print literal-pathspec commands" "$OUT" "GIT_LITERAL_PATHSPECS"
run_in "$R" bash "$STEP" red --message "m" --commit -- sh -c 'exit 1'
assert_eq "AC5 default red --commit: git add -A commits every changed file" "tests/app.test.js
tests/new.test.js" "$(committed "$R")"
R="$(fresh)"; BASE="$(head_of "$R")"
printf 'module.exports = 2;\n' > "$R/src/app.js"
run_in "$R" bash "$STEP" green --base "$BASE" --message "m" -- true
assert_contains "AC5 default green prints the blanket commit command" "$OUT" 'git add -A && git commit -m "feat(green): m"'
assert_not_contains "AC5 default green: no note about --base" "$OUT" "no --base"

t_summary
