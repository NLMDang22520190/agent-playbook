#!/usr/bin/env bash
# Tests for scripts/tdd-step.sh (AC3): RED/GREEN steps that drive role-gate.sh and proof-run.sh. Part 1 of 3 (split in v0.24.21 so that it is not the floor of a CI shard):
# from "red: passing" to "AC4 --baseline green: the implementer's paths only"; the rest is in test-tdd-step-b.sh and test-tdd-step-c.sh. Shared setup: tdd-step-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/tdd-step-fixture.sh"

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

echo "--commit never commits .agents/handoff/ (project without a .gitignore entry)"
R="$(fresh)"
assert_eq "AC3 handoff sandbox has no .gitignore" "" "$(ls -A "$R" | grep -x '.gitignore')"
mkdir -p "$R/.agents/handoff"; printf 'evidence\n' > "$R/.agents/handoff/evidence-red.log"
printf 'test("n", () => { throw new Error("x"); });\n' > "$R/tests/new.test.js"
run_in "$R" bash "$STEP" red --message "add new" --commit -- sh -c 'exit 1'
assert_rc "AC3 red --commit with a handoff file present -> exit 0" 0
FILES="$(git -C "$R" show --name-only --format= HEAD)"
assert_contains "AC3 red --commit (handoff present): the test change is committed" "$FILES" "tests/new.test.js"
assert_eq "AC3 red --commit never commits .agents/handoff/" "" "$(printf '%s\n' "$FILES" | grep '^\.agents/handoff/')"
assert_eq "AC3 red --commit: no handoff file is tracked" "" "$(git -C "$R" ls-files .agents/handoff)"
B2="$(head_of "$R")"
printf 'evidence\n' > "$R/.agents/handoff/evidence-green.log"
printf 'module.exports = 2;\n' > "$R/src/app.js"
run_in "$R" bash "$STEP" green --base "$B2" --message "make it pass" --commit -- true
assert_rc "AC3 green --commit with a handoff file present -> exit 0" 0
FILES="$(git -C "$R" show --name-only --format= HEAD)"
assert_contains "AC3 green --commit (handoff present): the production change is committed" "$FILES" "src/app.js"
assert_eq "AC3 green --commit never commits .agents/handoff/" "" "$(printf '%s\n' "$FILES" | grep '^\.agents/handoff/')"
assert_eq "AC3 green --commit: no handoff file is tracked" "" "$(git -C "$R" ls-files .agents/handoff)"

echo "--commit announces the .git/info/exclude edit"
R="$(fresh)"
printf 'test("n", () => { throw new Error("x"); });\n' > "$R/tests/new.test.js"
run_in "$R" bash "$STEP" red --message "add new" --commit -- sh -c 'exit 1'
assert_rc "AC3 red --commit in a repo without the ignore -> exit 0" 0
assert_contains "AC3 red --commit prints a notice naming .git/info/exclude" "$OUT" ".git/info/exclude"

echo "--commit in a project that TRACKS .agents/handoff/ (documented: tracked change stays in the work tree, uncommitted, still modified)"
R="$(fresh)"
mkdir -p "$R/.agents/handoff"; printf 'v1\n' > "$R/.agents/handoff/notes.md"
git -C "$R" add -A && git -C "$R" commit -q -m "track handoff notes"
printf 'v2\n' > "$R/.agents/handoff/notes.md"
printf 'test("n", () => { throw new Error("x"); });\n' > "$R/tests/new.test.js"
run_in "$R" bash "$STEP" red --message "add new" --commit -- sh -c 'exit 1'
assert_rc "AC3 red --commit with a tracked handoff file -> exit 0" 0
FILES="$(git -C "$R" show --name-only --format= HEAD)"
assert_contains "AC3 tracked handoff: the test change is committed" "$FILES" "tests/new.test.js"
assert_eq "AC3 tracked handoff: red step does not commit the tracked handoff change" "" "$(printf '%s\n' "$FILES" | grep '^\.agents/handoff/')"
assert_eq "AC3 tracked handoff: the file content is untouched in the work tree" "v2" "$(cat "$R/.agents/handoff/notes.md")"
assert_contains "AC3 tracked handoff: still listed as modified afterwards" "$(git -C "$R" status --porcelain)" ".agents/handoff/notes.md"
assert_eq "AC3 tracked handoff: still tracked" ".agents/handoff/notes.md" "$(git -C "$R" ls-files .agents/handoff)"

echo "environment"
D="$(mk_tmp)"
run_in "$D" bash "$STEP" red --message m -- sh -c 'exit 1'
assert_rc "AC3 red outside a git repo -> exit 3" 3
run_in "$D" bash "$STEP" green --base HEAD --message m -- true
assert_rc "AC3 green outside a git repo -> exit 3" 3

# ---------------------------------------------------------------------------------------------------------------
# v0.24.21 lane G: tdd-step.sh --base (red) and --baseline (red, green)
# ---------------------------------------------------------------------------------------------------------------

echo "AC3 red --base: the tester's own commit is judged"
R="$(fresh)"; B0="$(head_of "$R")"
printf 'module.exports = 2;\n' > "$R/src/app.js"
git -C "$R" commit -q -am "tester sneaks in a production change"
H1="$(head_of "$R")"; N1="$(count_of "$R")"
printf 'test("new", () => {});\n' > "$R/tests/new.test.js"
run_in "$R" bash "$GATE" check tester --base "$B0"
assert_rc "AC6 probe: the gate with --base <sha before> fails a tester that committed production code" 1
run_in "$R" bash "$STEP" red --message "add new" --commit --base "$B0" -- sh -c 'exit 1'
assert_rc "AC3 red --base <sha before>: tester committed a production change -> exit 1" 1
assert_contains "AC3 red --base: the failure names the production file" "$OUT" "src/app.js"
assert_untouched "AC6 red --base (tester committed production code): nothing committed" "$R" "$H1" "$N1"
assert_not_contains "AC6 red --base refused: no RED= line" "$OUT" "RED="
assert_file "AC6 red --base refused: the new test file is left in the work tree" "$R/tests/new.test.js"
assert_contains "AC6 red --base refused: the new test file is still untracked" "$(git -C "$R" status --porcelain)" "?? tests/new.test.js"

echo "AC3 red --base: a clean tester passes; the note appears only without --base"
R="$(fresh)"; B0="$(head_of "$R")"; N0="$(count_of "$R")"
printf 'test("new", () => {});\n' > "$R/tests/new.test.js"
NOTE='note: no --base: a tester that commits is not judged; pass the sha from before the role'
ERR="$(cd "$R" && bash "$STEP" red --message "add new" --base "$B0" -- sh -c 'exit 1' 2>&1 >/dev/null)"
assert_not_contains "AC3 red --base: no 'no --base' note" "$ERR" "no --base"
run_in "$R" bash "$STEP" red --message "add new" --base "$B0" --commit -- sh -c 'exit 1'
assert_rc "AC3 red --base <HEAD> with a clean tester -> exit 0" 0
assert_eq "AC3 red --base: one test commit" "$((N0 + 1))" "$(count_of "$R")"
R="$(fresh)"
printf 'test("new", () => {});\n' > "$R/tests/new.test.js"
ERR="$(cd "$R" && bash "$STEP" red --message "add new" -- sh -c 'echo boom; exit 1' 2>&1 >/dev/null)"
assert_contains "AC3 red without --base: stderr carries the note" "$ERR" "$NOTE"
SOUT="$(cd "$R" && bash "$STEP" red --message "add new" -- sh -c 'echo boom; exit 1' 2>/dev/null)"
assert_not_contains "AC3 red without --base: the note is on stderr, not stdout" "$SOUT" "no --base"
run_in "$R" bash "$STEP" red --message "add new" -- sh -c 'exit 1'
assert_rc "AC3 red without --base: exit code unchanged (0)" 0

echo "AC4 --baseline: baseline paths keep their state, only the role's paths are committed"
R="$(fresh)"; dirty "$R"; BL="$(snap "$R")"
printf 'test("new", () => { throw new Error("x"); });\n' > "$R/tests/new.test.js"
printf 'test("x", () => { /* edited */ });\n' > "$R/tests/app.test.js"
BS0="$(bstate "$R")"; H0="$(head_of "$R")"; N0="$(count_of "$R")"
run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c 'exit 1'
assert_rc "AC4 red --baseline --commit -> exit 0" 0
assert_eq "AC4 red --baseline --commit: one new commit" "$((N0 + 1))" "$(count_of "$R")"
assert_eq "AC4 red --baseline --commit: subject" "test(red): m" "$(subject "$R")"
assert_eq "AC4 red --baseline --commit: exactly the role's paths are committed" "tests/app.test.js
tests/new.test.js" "$(committed "$R")"
assert_eq "AC4 baseline paths: index and work tree untouched byte for byte" "$BS0" "$(bstate "$R")"
assert_contains "AC4 baseline paths: README.md still staged and edited (MM)" "$(git -C "$R" status --porcelain)" "MM README.md"
assert_contains "AC4 baseline paths: src/app.js still an unstaged edit" "$(git -C "$R" status --porcelain)" " M src/app.js"
run_in "$R" bash "$GATE" check tester --baseline "$BL"
assert_contains "AC4 the next gate with the same manifest reports src/app.js unchanged" "$OUT" "note: unchanged since the baseline: src/app.js"
assert_contains "AC4 the next gate with the same manifest reports README.md unchanged" "$OUT" "note: unchanged since the baseline: README.md"

echo "AC4 --baseline green: the implementer's paths only"
R="$(fresh)"; dirty "$R"; BL="$(snap "$R")"; BASE="$(head_of "$R")"
printf 'module.exports = 3;\n' > "$R/src/impl.js"
BS0="$(bstate "$R")"
run_in "$R" bash "$STEP" green --base "$BASE" --message "impl" --commit --baseline "$BL" -- true
assert_rc "AC4 green --baseline --commit -> exit 0" 0
assert_eq "AC4 green --baseline --commit: subject" "feat(green): impl" "$(subject "$R")"
assert_eq "AC4 green --baseline --commit: only the new production file" "src/impl.js" "$(committed "$R")"
assert_eq "AC4 green baseline paths untouched byte for byte" "$BS0" "$(bstate "$R")"

t_summary
