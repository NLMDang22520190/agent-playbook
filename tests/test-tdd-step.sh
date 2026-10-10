#!/usr/bin/env bash
# Tests for scripts/tdd-step.sh (AC3): RED/GREEN steps that drive role-gate.sh and proof-run.sh.
. "$(dirname "$0")/lib.sh"
STEP="$PB_ROOT/scripts/tdd-step.sh"
export PLAYBOOK_HOME="$(mk_tmp)"

head_of()  { git -C "$1" rev-parse HEAD; }
count_of() { git -C "$1" rev-list --count HEAD; }
subject()  { git -C "$1" log -1 --format=%s; }
fresh()    { local d; d="$(mk_tmp)"; mk_repo "$d"; printf '%s\n' "$d"; }
lower()    { printf '%s' "$1" | tr 'A-Z' 'a-z'; }
# assert_untouched NAME REPO HEAD COUNT -> nothing was committed
assert_untouched() {
  assert_eq "$1: HEAD unchanged" "$3" "$(head_of "$2")"
  assert_eq "$1: commit count unchanged" "$4" "$(count_of "$2")"
}

echo "red: passing"
R="$(fresh)"; H0="$(head_of "$R")"; N0="$(count_of "$R")"
printf 'test("new", () => { throw new Error("x"); });\n' > "$R/tests/new.test.js"
run_in "$R" bash "$STEP" red --message "add new" -- sh -c 'echo boom; exit 1'
assert_rc "AC3 red: gate ok + failing cmd -> exit 0" 0
assert_contains "AC3 red: evidence block is printed" "$OUT" "boom"
assert_untouched "AC3 red without --commit" "$R" "$H0" "$N0"
assert_contains "AC3 red without --commit: prints a commit command" "$OUT" "git commit"
assert_contains "AC3 red without --commit: command carries the subject" "$OUT" "test(red): add new"
assert_file "AC3 red: test file left in the work tree" "$R/tests/new.test.js"

echo "red: --commit"
R="$(fresh)"; H0="$(head_of "$R")"; N0="$(count_of "$R")"
printf 'test("new", () => {});\n' > "$R/tests/new.test.js"
run_in "$R" bash "$STEP" red --message "add new" --commit -- sh -c 'exit 1'
assert_rc "AC3 red --commit -> exit 0" 0
assert_eq "AC3 red --commit: exactly one new commit" "$((N0 + 1))" "$(count_of "$R")"
assert_eq "AC3 red --commit: subject" "test(red): add new" "$(subject "$R")"
assert_eq "AC3 red --commit: parent is the old HEAD" "$H0" "$(git -C "$R" rev-parse HEAD~1)"
assert_contains "AC3 red --commit: new test file is in the commit" "$(git -C "$R" show --name-only --format= HEAD)" "tests/new.test.js"
assert_eq "AC3 red --commit: work tree is clean afterwards" "" "$(git -C "$R" status --porcelain)"
SHA="$(printf '%s\n' "$OUT" | sed -n 's/.*RED=\([0-9a-f][0-9a-f]*\).*/\1/p' | tail -n 1)"
HEADNOW="$(head_of "$R")"
if [ -n "$SHA" ] && [ "${#SHA}" -ge 7 ] && [ "${HEADNOW#"$SHA"}" != "$HEADNOW" ]; then
  t_ok "AC3 red --commit: prints RED=<sha> of the new commit"
else
  t_bad "AC3 red --commit: prints RED=<sha> of the new commit" "RED=[$SHA] head=[$HEADNOW]"
fi

echo "red: refused"
R="$(fresh)"; H0="$(head_of "$R")"; N0="$(count_of "$R")"
printf 'test("new", () => {});\n' > "$R/tests/new.test.js"
run_in "$R" bash "$STEP" red --message "add new" --commit -- true
assert_rc "AC3 red refused when the test cmd passes -> exit 1" 1
assert_contains "AC3 red refused: says it did not fail" "$(lower "$OUT")" "did not fail"
assert_untouched "AC3 red refused (cmd passes) even with --commit" "$R" "$H0" "$N0"
assert_not_contains "AC3 red refused: no RED= line" "$OUT" "RED="

R="$(fresh)"; H0="$(head_of "$R")"; N0="$(count_of "$R")"
printf 'module.exports = 2;\n' > "$R/src/app.js"
run_in "$R" bash "$STEP" red --message "sneaky" --commit -- sh -c 'exit 1'
assert_rc "AC3 red refused when the tester gate fails (production file changed) -> exit 1" 1
assert_contains "AC3 red gate failure names the violation" "$OUT" "src/app.js"
assert_untouched "AC3 red refused (gate) even with --commit" "$R" "$H0" "$N0"
assert_eq "AC3 red refused (gate): production change left alone" "module.exports = 2;" "$(cat "$R/src/app.js")"

echo "green: passing"
R="$(fresh)"; BASE="$(head_of "$R")"; N0="$(count_of "$R")"
printf 'module.exports = 2;\n' > "$R/src/app.js"
run_in "$R" bash "$STEP" green --base "$BASE" --message "make it pass" -- sh -c 'echo fine; exit 0'
assert_rc "AC3 green: gate ok + passing cmd -> exit 0" 0
assert_contains "AC3 green: evidence block is printed" "$OUT" "fine"
assert_untouched "AC3 green without --commit" "$R" "$BASE" "$N0"
assert_contains "AC3 green without --commit: prints a commit command" "$OUT" "git commit"
assert_contains "AC3 green without --commit: command carries the subject" "$OUT" "feat(green): make it pass"

R="$(fresh)"; BASE="$(head_of "$R")"; N0="$(count_of "$R")"
printf 'module.exports = 2;\n' > "$R/src/app.js"
run_in "$R" bash "$STEP" green --base "$BASE" --message "make it pass" --commit -- true
assert_rc "AC3 green --commit -> exit 0" 0
assert_eq "AC3 green --commit: exactly one new commit" "$((N0 + 1))" "$(count_of "$R")"
assert_eq "AC3 green --commit: subject" "feat(green): make it pass" "$(subject "$R")"
assert_contains "AC3 green --commit: production change is in the commit" "$(git -C "$R" show --name-only --format= HEAD)" "src/app.js"
assert_eq "AC3 green --commit: work tree is clean afterwards" "" "$(git -C "$R" status --porcelain)"

echo "green: refused"
R="$(fresh)"; BASE="$(head_of "$R")"; N0="$(count_of "$R")"
printf 'module.exports = 2;\n' > "$R/src/app.js"
run_in "$R" bash "$STEP" green --base "$BASE" --message "m" --commit -- sh -c 'exit 1'
assert_rc "AC3 green refused when the cmd fails -> exit 1" 1
assert_untouched "AC3 green refused (cmd fails) even with --commit" "$R" "$BASE" "$N0"

R="$(fresh)"; BASE="$(head_of "$R")"; N0="$(count_of "$R")"
printf 'module.exports = 2;\n' > "$R/src/app.js"
printf 'test("x", () => { /* weakened */ });\n' > "$R/tests/app.test.js"
run_in "$R" bash "$STEP" green --base "$BASE" --message "m" --commit -- true
assert_rc "AC3 green refused when a test file changed since --base -> exit 1" 1
assert_contains "AC3 green gate failure names the test file" "$OUT" "tests/app.test.js"
assert_untouched "AC3 green refused (test changed) even with --commit" "$R" "$BASE" "$N0"

echo "usage"
R="$(fresh)"; H0="$(head_of "$R")"
run_in "$R" bash "$STEP" red -- true
assert_rc "AC3 red without --message -> exit 2" 2
run_in "$R" bash "$STEP" red --message m
assert_rc "AC3 red without -- -> exit 2" 2
run_in "$R" bash "$STEP" red --message m --
assert_rc "AC3 red with -- but no command -> exit 2" 2
run_in "$R" bash "$STEP" frobnicate --message m -- true
assert_rc "AC3 unknown subcommand -> exit 2" 2
run_in "$R" bash "$STEP"
assert_rc "AC3 no subcommand -> exit 2" 2
run_in "$R" bash "$STEP" green --message m -- true
assert_rc "AC3 green without --base -> exit 2" 2
run_in "$R" bash "$STEP" green --base HEAD -- true
assert_rc "AC3 green without --message -> exit 2" 2
run_in "$R" bash "$STEP" green --base HEAD --message m
assert_rc "AC3 green without -- -> exit 2" 2
assert_eq "AC3 usage errors commit nothing" "$H0" "$(head_of "$R")"

echo "environment"
D="$(mk_tmp)"
run_in "$D" bash "$STEP" red --message m -- sh -c 'exit 1'
assert_rc "AC3 red outside a git repo -> exit 3" 3
run_in "$D" bash "$STEP" green --base HEAD --message m -- true
assert_rc "AC3 green outside a git repo -> exit 3" 3

t_summary
