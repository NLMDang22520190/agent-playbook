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
GATE="$PB_ROOT/scripts/role-gate.sh"
# committed REPO -> the paths of HEAD's commit, one per line (no rename detection: both sides of a rename show up)
committed() { git -C "$1" -c core.quotepath=off diff-tree -r --root --no-commit-id --name-only -z HEAD | tr '\0' '\n'; }
# bstate REPO -> index entries, diffs and contents of the two baseline paths (README.md src/app.js)
bstate() { ( cd "$1" && git ls-files -s -- README.md src/app.js; git diff -- README.md src/app.js; git diff --cached -- README.md src/app.js; cat README.md src/app.js ); }
# dirty REPO -> pre-existing changes: README.md staged then edited again (MM), src/app.js edited (unstaged)
dirty() {
  ( cd "$1" && printf 'staged edit\n' >> README.md && git add README.md && printf 'later edit\n' >> README.md \
    && printf 'module.exports = 9;\n' > src/app.js )
}
# snap REPO -> prints the path of a baseline manifest recorded now (outside the work tree)
snap() { local f; f="$(mk_tmp)/baseline.txt"; ( cd "$1" && bash "$GATE" snapshot --out "$f" >/dev/null 2>&1 ); printf '%s\n' "$f"; }
# can_name NAME -> 0 when the file system accepts a file with that exact name (NTFS refuses TAB, control, : and *)
can_name() { local d; d="$(mk_tmp)"; { : > "$d/$1"; } 2>/dev/null && [ -f "$d/$1" ] && [ "$(ls "$d" | wc -l | tr -d ' ')" = "1" ]; }
noeol_ls() { git -C "$1" -c core.quotepath=off ls-tree -r --name-only -z HEAD | tr '\0' '\n'; }

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

# ---------------------------------------------------------------------------------------------------------------
# v0.24.21 lane G, fix round 1 (review findings)
# ---------------------------------------------------------------------------------------------------------------
# can_nl -> 0 when the file system stores a file name holding a newline (probed by globbing: ls would print two lines)
can_nl() { local d; d="$(mk_tmp)"; { : > "$d/a"$'\n'"b"; } 2>/dev/null || return 1; set -- "$d"/*; [ $# -eq 1 ] && [ -f "$1" ]; }
# can_exec -> 0 when a file made executable here really runs (NTFS mounts refuse the mode)
can_exec() { local d f; d="$(mk_tmp)"; f="$d/h.sh"; printf '#!/bin/sh\nexit 0\n' > "$f"; chmod +x "$f" 2>/dev/null; [ -x "$f" ] && "$f" 2>/dev/null; }

echo "AC4 (fix 1) --baseline: the gate runs again after the test command (a corrupted manifest refuses the commit)"
R="$(fresh)"; dirty "$R"; BL="$(snap "$R")"; H0="$(head_of "$R")"; N0="$(count_of "$R")"
printf 'test("n", () => {});\n' > "$R/tests/new.test.js"
run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c "echo garbage > '$BL'; exit 1"
assert_rc "AC4 fix1 the test command corrupts the manifest: exit 1" 1
assert_untouched "AC4 fix1 the test command corrupts the manifest: nothing committed" "$R" "$H0" "$N0"
assert_not_contains "AC4 fix1 the test command corrupts the manifest: no RED= line" "$OUT" "RED="
assert_file "AC4 fix1 the test command corrupts the manifest: the role file stays in the work tree" "$R/tests/new.test.js"
# a clean start: the first gate reports no unchanged paths, so only the post-test gate verdict can refuse
R="$(fresh)"; BL="$(snap "$R")"; H0="$(head_of "$R")"; N0="$(count_of "$R")"
printf 'test("n", () => {});\n' > "$R/tests/new.test.js"
run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c "echo garbage > '$BL'; exit 1"
assert_rc "AC4 fix1 clean start, the test command corrupts the manifest: exit 1" 1
assert_untouched "AC4 fix1 clean start, the test command corrupts the manifest: nothing committed" "$R" "$H0" "$N0"

echo "AC4 (fix 1) --baseline: the unchanged-since-baseline notes must equal before and after the test command"
R="$(fresh)"; printf 'baseline edit\n' >> "$R/tests/app.test.js"; BL="$(snap "$R")"; H0="$(head_of "$R")"; N0="$(count_of "$R")"
printf 'test("n", () => {});\n' > "$R/tests/n.test.js"
run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c "grep -vF tests/app.test.js '$BL' > '$BL.new'; mv '$BL.new' '$BL'; exit 1"
assert_rc "AC4 fix1 the test command drops a manifest line: exit 1" 1
assert_contains "AC4 fix1 the test command drops a manifest line: says nothing committed" "$(lower "$OUT")" "nothing committed"
assert_untouched "AC4 fix1 the test command drops a manifest line: nothing committed" "$R" "$H0" "$N0"
assert_eq "AC4 fix1 the test command drops a manifest line: the baseline test file is not committed" "" "$(noeol_ls "$R" | grep -x 'tests/n.test.js')"
assert_contains "AC4 fix1 the test command drops a manifest line: the baseline edit is still in the work tree" "$(git -C "$R" status --porcelain)" " M tests/app.test.js"

echo "AC4 (fix 2) --baseline --commit: a newline in a role path is refused like other control characters"
if can_nl; then
  R="$(fresh)"; dirty "$R"; BL="$(snap "$R")"; H0="$(head_of "$R")"; N0="$(count_of "$R")"
  printf 'test("n", () => {});\n' > "$R/tests/ok.test.js"
  printf 'test("n", () => {});\n' > "$R/tests/nl"$'\n'"x.test.js"
  BS0="$(bstate "$R")"
  run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c 'exit 1'
  assert_rc "AC4 fix2 newline in a path: exit 1" 1
  assert_contains "AC4 fix2 newline in a path: tells the user to commit by hand" "$(lower "$OUT")" "by hand"
  assert_untouched "AC4 fix2 newline in a path: nothing committed" "$R" "$H0" "$N0"
  assert_eq "AC4 fix2 newline in a path: baseline paths untouched" "$BS0" "$(bstate "$R")"
else
  t_skip 5 "AC4 fix2 newline in a path (the file system refuses a newline in a name)"
fi

echo "AC4 (fix 3) --baseline with an empty value is a usage error"
R="$(fresh)"; H0="$(head_of "$R")"; N0="$(count_of "$R")"
printf 'test("n", () => {});\n' > "$R/tests/new.test.js"
run_in "$R" bash "$STEP" red --message "m" --baseline "" -- sh -c 'exit 1'
assert_rc "AC4 fix3 red --baseline \"\" -> exit 2" 2
run_in "$R" bash "$STEP" red --message "m" --commit --baseline "" -- sh -c 'exit 1'
assert_rc "AC4 fix3 red --commit --baseline \"\" -> exit 2" 2
assert_untouched "AC4 fix3 --baseline \"\": nothing committed" "$R" "$H0" "$N0"

echo "AC4 (fix 4) --baseline: the first gate's output passes through"
R="$(fresh)"; dirty "$R"; BL="$(snap "$R")"
printf 'test("n", () => {});\n' > "$R/tests/new.test.js"
run_in "$R" bash "$STEP" red --message "m" --baseline "$BL" -- sh -c 'exit 1'
assert_contains "AC4 fix4 red --baseline: the baseline note line (2 paths, digest) is printed" "$OUT" "note: baseline $BL (2 path(s), digest "
assert_contains "AC4 fix4 red --baseline: the unchanged note for src/app.js is printed" "$OUT" "note: unchanged since the baseline: src/app.js"
assert_contains "AC4 fix4 red --baseline: the unchanged note for README.md is printed" "$OUT" "note: unchanged since the baseline: README.md"
run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c 'exit 1'
assert_contains "AC4 fix4 red --baseline --commit: the baseline note line is printed" "$OUT" "note: baseline $BL (2 path(s), digest "
assert_contains "AC4 fix4 red --baseline --commit: the unchanged note is printed" "$OUT" "note: unchanged since the baseline: src/app.js"
R="$(fresh)"; dirty "$R"; BL="$(snap "$R")"; BASE="$(head_of "$R")"
printf 'module.exports = 3;\n' > "$R/src/impl.js"
run_in "$R" bash "$STEP" green --base "$BASE" --message "m" --baseline "$BL" -- true
assert_contains "AC4 fix4 green --baseline: the baseline note line is printed" "$OUT" "note: baseline $BL (2 path(s), digest "
assert_contains "AC4 fix4 green --baseline: the unchanged note is printed" "$OUT" "note: unchanged since the baseline: README.md"

echo "AC4 (fix 5) a git hook cannot smuggle an unjudged file into the commit"
HS="$(mk_tmp)/hook-evil.sh"
printf '%s\n' '#!/bin/sh' 'mkdir -p src' 'echo evil > src/evil.js' 'git add src/evil.js' > "$HS"
HT="$(mk_tmp)/hook-true.sh"
printf '%s\n' '#!/bin/sh' 'true' > "$HT"
INSTALL_EVIL="cp '$HS' .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit; exit 1"
INSTALL_TRUE="cp '$HT' .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit; exit 1"
if can_exec; then
  R="$(fresh)"; H0="$(head_of "$R")"; N0="$(count_of "$R")"
  printf 'test("n", () => {});\n' > "$R/tests/new.test.js"
  IDX0="$(git -C "$R" ls-files -s; git -C "$R" status --porcelain)"
  run_in "$R" bash "$STEP" red --message "m" --commit -- sh -c "$INSTALL_EVIL"
  assert_rc "AC4 fix5 default path, hook adds src/evil.js: exit 1" 1
  assert_contains "AC4 fix5 default path: the message names the unexpected committed path" "$OUT" "src/evil.js"
  assert_untouched "AC4 fix5 default path: the commit is undone (HEAD unchanged)" "$R" "$H0" "$N0"
  assert_eq "AC4 r2 fix5 default path: the index equals the pre-run index after the undo" "$IDX0" "$(git -C "$R" ls-files -s; git -C "$R" status --porcelain)"
  assert_eq "AC4 fix5 default path: src/evil.js is in no commit" "" "$(noeol_ls "$R" | grep -x 'src/evil.js')"
  assert_eq "AC4 fix5 default path: the role's work tree content is kept" 'test("n", () => {});' "$(cat "$R/tests/new.test.js")"

  R="$(fresh)"; dirty "$R"; BL="$(snap "$R")"; H0="$(head_of "$R")"; N0="$(count_of "$R")"
  printf 'test("n", () => {});\n' > "$R/tests/new.test.js"
  IDX0="$(git -C "$R" ls-files -s; git -C "$R" status --porcelain)"
  run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c "$INSTALL_EVIL"
  assert_rc "AC4 fix5 --baseline, hook adds src/evil.js: exit 1" 1
  assert_contains "AC4 fix5 --baseline: the message names the unexpected committed path" "$OUT" "src/evil.js"
  assert_untouched "AC4 fix5 --baseline: the commit is undone (HEAD unchanged)" "$R" "$H0" "$N0"
  assert_eq "AC4 r2 fix5 --baseline: the index equals the pre-run index after the undo" "$IDX0" "$(git -C "$R" ls-files -s; git -C "$R" status --porcelain)"
  assert_eq "AC4 fix5 --baseline: src/evil.js is in no commit" "" "$(noeol_ls "$R" | grep -x 'src/evil.js')"
  assert_eq "AC4 fix5 --baseline: the role's work tree content is kept" 'test("n", () => {});' "$(cat "$R/tests/new.test.js")"
  assert_eq "AC4 fix5 --baseline: the baseline work tree file is kept" "module.exports = 9;" "$(cat "$R/src/app.js")"

  R="$(fresh)"; N0="$(count_of "$R")"
  printf 'test("n", () => {});\n' > "$R/tests/new.test.js"
  run_in "$R" bash "$STEP" red --message "m" --commit -- sh -c "$INSTALL_TRUE"
  assert_rc "AC4 fix5 control, a harmless hook (default path): exit 0" 0
  assert_eq "AC4 fix5 control (default path): one new commit" "$((N0 + 1))" "$(count_of "$R")"
  assert_contains "AC4 fix5 control (default path): the test file is committed" "$(committed "$R")" "tests/new.test.js"

  R="$(fresh)"; dirty "$R"; BL="$(snap "$R")"; N0="$(count_of "$R")"
  printf 'test("n", () => {});\n' > "$R/tests/new.test.js"
  run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c "$INSTALL_TRUE"
  assert_rc "AC4 fix5 control, a harmless hook (--baseline): exit 0" 0
  assert_eq "AC4 fix5 control (--baseline): one new commit" "$((N0 + 1))" "$(count_of "$R")"
  assert_eq "AC4 fix5 control (--baseline): only the role's file is committed" "tests/new.test.js" "$(committed "$R")"
else
  t_skip 21 "AC4 fix5 git hooks (the file system cannot make a hook executable)"
fi


echo "AC4 (fix r2) the undo restores the index exactly; a hook that makes a second commit is fully undone"
# idx REPO -> the whole index (mode, blob, stage, path), plus the porcelain status
idx() { git -C "$1" ls-files -s; git -C "$1" status --porcelain; }
HADD="$(mk_tmp)/hook-addreadme.sh"
printf "%s\n" "#!/bin/sh" "git add README.md" > "$HADD"
HPC="$(mk_tmp)/hook-postcommit.sh"
printf "%s\n" "#!/bin/sh" "[ -e .git/pc-done ] && exit 0" "touch .git/pc-done" "mkdir -p src" "echo evil > src/evil.js" "git add src/evil.js" "git commit -q -m evil-second" > "$HPC"
INSTALL_ADD="cp \"$HADD\" .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit; exit 1"
INSTALL_PC="cp \"$HPC\" .git/hooks/post-commit && chmod +x .git/hooks/post-commit; exit 1"
if can_exec; then
  R="$(fresh)"; dirty "$R"; BL="$(snap "$R")"
  printf "test(\"n\", () => {});\n" > "$R/tests/n.test.js"
  H0="$(head_of "$R")"; N0="$(count_of "$R")"; IDX0="$(idx "$R")"; BS0="$(bstate "$R")"
  run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c "$INSTALL_ADD"
  assert_rc "AC4 r2 --baseline, a pre-commit hook stages README.md: exit 1" 1
  assert_untouched "AC4 r2 --baseline, hook stages README.md: the commit is undone" "$R" "$H0" "$N0"
  assert_eq "AC4 r2 --baseline, hook stages README.md: the whole index equals the pre-run index" "$IDX0" "$(idx "$R")"
  assert_contains "AC4 r2 --baseline, hook stages README.md: README.md is staged and edited again (MM)" "$(git -C "$R" status --porcelain)" "MM README.md"
  assert_eq "AC4 r2 --baseline, hook stages README.md: baseline paths untouched (staged blob, diffs, content)" "$BS0" "$(bstate "$R")"
  assert_eq "AC4 r2 --baseline, hook stages README.md: the role file is kept" "test(\"n\", () => {});" "$(cat "$R/tests/n.test.js")"

  R="$(fresh)"; dirty "$R"
  printf "test(\"n\", () => {});\n" > "$R/tests/new.test.js"
  H0="$(head_of "$R")"; N0="$(count_of "$R")"; IDX0="$(idx "$R")"
  run_in "$R" bash "$STEP" red --message "m" --commit -- sh -c "cp \"$HS\" .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit; exit 1"
  assert_rc "AC4 r2 default path, a hook adds an extra file: exit 1" 1
  assert_untouched "AC4 r2 default path, extra file: the commit is undone" "$R" "$H0" "$N0"
  assert_eq "AC4 r2 default path, extra file: the whole index equals the pre-run index" "$IDX0" "$(idx "$R")"
  assert_eq "AC4 r2 default path, extra file: the role file is kept" "test(\"n\", () => {});" "$(cat "$R/tests/new.test.js")"

  for MODE in default baseline; do
    R="$(fresh)"; dirty "$R"; BL="$(snap "$R")"
    printf "test(\"n\", () => {});\n" > "$R/tests/n.test.js"
    H0="$(head_of "$R")"; N0="$(count_of "$R")"; IDX0="$(idx "$R")"
    if [ "$MODE" = default ]; then
      run_in "$R" bash "$STEP" red --message "m" --commit -- sh -c "$INSTALL_PC"
    else
      run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c "$INSTALL_PC"
    fi
    assert_rc "AC4 r2 $MODE, a post-commit hook makes a second commit: exit 1" 1
    assert_eq "AC4 r2 $MODE, post-commit second commit: HEAD is the HEAD from before tdd-step" "$H0" "$(head_of "$R")"
    assert_eq "AC4 r2 $MODE, post-commit second commit: commit count is the pre-run count" "$N0" "$(count_of "$R")"
    assert_eq "AC4 r2 $MODE, post-commit second commit: no test(red) commit is left in the log" "" "$(git -C "$R" log --format=%s | grep -F "test(red)")"
    assert_eq "AC4 r2 $MODE, post-commit second commit: no evil-second commit is left in the log" "" "$(git -C "$R" log --format=%s | grep -F "evil-second")"
    assert_eq "AC4 r2 $MODE, post-commit second commit: the index equals the pre-run index" "$IDX0" "$(idx "$R")"
    assert_eq "AC4 r2 $MODE, post-commit second commit: the role content is kept" "test(\"n\", () => {});" "$(cat "$R/tests/n.test.js")"
  done
else
  t_skip 26 "AC4 r2 hook cases (the file system cannot make a hook executable)"
fi


t_summary
