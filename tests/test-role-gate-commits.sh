#!/usr/bin/env bash
# Tests for scripts/role-gate.sh `check ROLE --commits A..B` (v0.26.1 lane G, slices S1-S3 of .agents/handoff/01-spec.md):
# S1 AC-C1 (oracle P/T1/I1/T2), AC-C2 role matrix per commit (also commit + revert), AC-C3 work tree/index/untracked not judged,
# AC-C5 verdict lines and the empty range, plus feedback cases fb #3/#4/#7-#13 rebuilt for --commits; S2 AC-C6 argument errors
# and incompatibilities; S3 AC-C4 merges (first parent), AC-C7 per-commit mode check, AC-C8 mode restore note.
# Every commit sets modes in the index (git update-index --chmod), so no block depends on chmod working on this file system.
# Shared setup: role-gate-fixture.sh (gchk = check with a global conf whose test_infra_regex is ^ci/).
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/role-gate-fixture.sh"
unset PB_ALLOW_MODE_CHANGE

gate() { run env PLAYBOOK_HOME="$IH" bash "$GATE" "$@"; }
new_repo() { R="$(mk_tmp)"; mk_repo "$R"; cd "$R" || exit 3; P="$(git rev-parse HEAD)"; }
new_mode_repo() { R="$(mk_tmp)"; mk_mode_repo "$R"; cd "$R" || exit 3; P="$(git rev-parse HEAD)"; }
# cmt PATH TEXT MSG -> write PATH (parent dirs made), stage it, commit
cmt() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; git add -- "$1"; git commit -q -m "$3"; }
# setx +x|-x PATH -> the mode in the index (and in the work tree where chmod works, so a later `git add` keeps it)
setx() { chmod "$1" "$2" 2>/dev/null; git update-index --chmod="$1" -- "$2"; }
# first_note -> the first note: line of $OUT that is not a conf note
first_note() { notes_of | grep -v -e '^note: test_path_regex from the ' -e '^note: test_infra_regex from the ' | head -1; }
# cnote RANGE N -> the AC-C3 note, RANGE as given
cnote() { printf 'note: --commits %s: %s commit(s) judged (first parent); the work tree, the index and untracked files are not checked' "$1" "$2"; }
# no_verdict NAME -> neither verdict line was printed
no_verdict() { assert_not_contains "$1: no verdict" "$OUT" "role gate"; }
CERR='error: --commits needs a range A..B (two dots, both ends given)'
XERR='error: --commits cannot be combined with --base, --baseline or --scope'

# ================= S1 =================
echo "AC-C1 oracle: P, T1 (test), I1 (code), T2 (test) on one branch; each role passes on its own range"
new_repo
cmt tests/a.test.js 'test("a", () => {});' T1; T1="$(git rev-parse HEAD)"
cmt src/a.js 'module.exports = "a";' I1; I1="$(git rev-parse HEAD)"
cmt tests/b.test.js 'test("b", () => {});' T2; T2="$(git rev-parse HEAD)"
gchk tester --commits "$P..$T1"
assert_rc "AC-C1 tester --commits P..T1 (HEAD is T2): exit 0" 0
assert_contains "AC-C1 ... OK line, 1 file checked, commits=P..T1" "$OUT" "OK: role gate passed for tester (1 file(s) checked, commits=$P..$T1)"
gchk implementer --commits "$T1..$I1"
assert_rc "AC-C1 implementer --commits T1..I1: exit 0" 0
assert_contains "AC-C1 ... OK line, 1 file checked, commits=T1..I1" "$OUT" "OK: role gate passed for implementer (1 file(s) checked, commits=$T1..$I1)"
gchk tester --commits "$I1..$T2"
assert_rc "AC-C1 tester --commits I1..T2: exit 0" 0
assert_contains "AC-C1 ... OK line, 1 file checked, commits=I1..T2" "$OUT" "OK: role gate passed for tester (1 file(s) checked, commits=$I1..$T2)"
gchk tester --commits "$P..$T2"
assert_rc "AC-C1 tester --commits P..T2 (holds I1): exit 1" 1
assert_contains "AC-C1 ... I1's code path is named" "$OUT" "VIOLATION (tester): src/a.js [code]"
assert_contains "AC-C5 FAILED line names commits=P..T2" "$OUT" "role gate FAILED for tester: 1 violation(s), commits=$P..$T2"
gchk tester --commits "HEAD~3..HEAD~2"
assert_rc "AC-C1 a symbolic range HEAD~3..HEAD~2 (= P..T1): exit 0" 0
assert_contains "AC-C5 D11 the OK line names the range as given" "$OUT" "OK: role gate passed for tester (1 file(s) checked, commits=HEAD~3..HEAD~2)"
assert_eq "AC-C3 the first note after the conf notes, range as given" "$(cnote 'HEAD~3..HEAD~2' 1)" "$(first_note)"

echo "AC-C2 a forbidden path in any commit of the range fails, also when a later commit reverts it (per-commit union, D2)"
new_repo
cmt src/app.js 'module.exports = 2;' "code edit"; cmt src/app.js 'module.exports = 1;' "revert"
assert_eq "AC-C2 setup: the range has no net change" "" "$(git diff --name-only "$P" HEAD)"
gchk tester --commits "$P..HEAD"
assert_rc "AC-C2 tester range: code commit then revert: exit 1" 1
assert_contains "AC-C2 ... the code path is named" "$OUT" "VIOLATION (tester): src/app.js [code]"
new_repo
cmt tests/app.test.js 'test("y", () => {});' "test edit"; cmt tests/app.test.js 'test("x", () => {});' "revert"
cmt ci/run.yml 'on: push' "infra"
gchk implementer --commits "$P..HEAD"
assert_rc "AC-C2 implementer range: test commit + revert and an infra commit: exit 1" 1
assert_contains "AC-C2 ... the test path is named" "$OUT" "VIOLATION (implementer): tests/app.test.js [test]"
assert_contains "AC-C2 ... the infra path is named" "$OUT" "VIOLATION (implementer): ci/run.yml [infra]"
new_repo
cmt ci/run.yml 'on: push' "infra"; CI1="$(git rev-parse HEAD)"
cmt tests/app.test.js 'test("y", () => {});' "test"; cmt src/app.js 'module.exports = 2;' "code"
gchk infra --commits "$P..$CI1"
assert_rc "AC-C2 infra range with only an infra commit: exit 0" 0
gchk infra --commits "$P..HEAD"
assert_rc "AC-C2 infra range with a test and a code commit: exit 1" 1
assert_contains "AC-C2 ... the test path is named" "$OUT" "VIOLATION (infra): tests/app.test.js [test]"
assert_contains "AC-C2 ... the code path is named" "$OUT" "VIOLATION (infra): src/app.js [code]"
gchk reviewer --commits "$P..$CI1"
assert_rc "AC-C2 reviewer range holding any commit: exit 1" 1
assert_contains "AC-C2 ... the path is named" "$OUT" "VIOLATION (reviewer): ci/run.yml [infra]"

echo "AC-C3 uncommitted, staged and untracked changes are not judged; fb #11/#12 rebuilt"
new_repo
cmt tests/c.test.js 'test("c", () => {});' "tester"; B="$(git rev-parse HEAD)"
printf 'module.exports = 9;\n' > src/app.js
printf 'staged\n' > src/staged.js; git add src/staged.js
printf 'untracked\n' > src/untracked.js
printf 'test("dirty", () => {});\n' > tests/app.test.js
gchk tester --commits "$P..$B"
assert_rc "AC-C3 tester range with one test commit, dirty code in work tree/index/untracked: exit 0" 0
assert_contains "AC-C3 ... only the committed path is checked" "$OUT" "OK: role gate passed for tester (1 file(s) checked, commits=$P..$B)"
assert_eq "AC-C3 the first note after the conf notes" "$(cnote "$P..$B" 1)" "$(first_note)"
assert_not_contains "AC-C3 ... the untracked file is not named" "$OUT" "src/untracked.js"
assert_not_contains "AC-C3 ... the staged file is not named" "$OUT" "src/staged.js"
cmt src/added.js 'module.exports = "added";' "tester adds a production file"
gchk tester --commits "$P..HEAD"
assert_rc "AC-C3 fb #11/#12 a tester commit adding a production file: exit 1" 1
assert_contains "AC-C3 ... the committed production file is named" "$OUT" "VIOLATION (tester): src/added.js [code]"
assert_contains "AC-C3 ... one violation only (dirty work not counted)" "$OUT" "role gate FAILED for tester: 1 violation(s), commits=$P..HEAD"

echo "AC-C3 fb #9 rebuilt: the implementer range holds only src/ commits while another task's test is modified in the work tree"
new_repo
cmt src/b.js 'module.exports = "b";' "impl"
printf 'test("other task", () => {});\n' > tests/app.test.js
gchk implementer --commits "$P..HEAD"
assert_rc "AC-C3 fb #9 implementer: exit 0 (work tree not judged)" 0
assert_contains "AC-C3 fb #9 ... 1 file checked" "$OUT" "OK: role gate passed for implementer (1 file(s) checked, commits=$P..HEAD)"

echo "AC-C5 empty range; fb #3/#4/#7/#8/#13 and fb #10 rebuilt for the reviewer"
new_repo
printf 'module.exports = 5;\n' > src/app.js; printf 'x\n' > src/new.js; printf 'test("t", () => {});\n' > tests/app.test.js; git add tests/app.test.js
gchk reviewer --commits "$P..$P"
assert_rc "AC-C5 fb #3 reviewer, empty range on a dirty repo: exit 0" 0
assert_contains "AC-C5 ... 0 files checked, commits=P..P" "$OUT" "OK: role gate passed for reviewer (0 file(s) checked, commits=$P..$P)"
assert_eq "AC-C5 ... 0 commit(s) judged" "$(cnote "$P..$P" 0)" "$(first_note)"
git commit -q -m "concurrent task commit"
gchk reviewer --commits "$P..$P"
assert_rc "AC-C5 fb #10 a concurrent task committed after the range (HEAD moved): exit 0" 0
assert_contains "AC-C5 fb #10 ... 0 files checked" "$OUT" "OK: role gate passed for reviewer (0 file(s) checked, commits=$P..$P)"
gchk reviewer --commits "$P..HEAD"
assert_rc "AC-C5 a reviewer commit in the range: exit 1" 1
assert_contains "AC-C5 ... the committed path is named" "$OUT" "VIOLATION (reviewer): tests/app.test.js [test]"

echo "D12 the range need not end at HEAD nor be an ancestor of HEAD; no --base ancestor note"
new_repo; MAINBR="$(git symbolic-ref --short HEAD)"
git checkout -q -b side; cmt tests/s.test.js 'test("s", () => {});' "side test"; SB="$(git rev-parse HEAD)"
git checkout -q "$MAINBR"; cmt src/m.js 'module.exports = "m";' "main code"
gchk tester --commits "$P..$SB"
assert_rc "D12 tester range on a branch that is not checked out: exit 0" 0
assert_contains "D12 ... 1 file checked" "$OUT" "OK: role gate passed for tester (1 file(s) checked, commits=$P..$SB)"
assert_not_contains "D12 ... no 'not an ancestor of HEAD' note" "$OUT" "is not an ancestor of HEAD"

# ================= S2 =================
echo "AC-C6 malformed ranges: exit 2, no verdict"
new_repo
cmt tests/a.test.js 'test("a", () => {});' T1; B="$(git rev-parse HEAD)"
for v in "$P...$B" "$P" "..$B" "$P.." ".."; do
  gchk tester --commits "$v"
  assert_rc "AC-C6 --commits '$v': exit 2" 2
  assert_contains "AC-C6 --commits '$v': the range error" "$OUT" "$CERR"
  no_verdict "AC-C6 --commits '$v'"
done

echo "AC-C6 --commits twice, and with --base, --baseline or --scope (either order): exit 2, no verdict"
gchk tester --commits "$P..$B" --commits "$P..$B"
assert_rc "AC-C6 --commits given twice: exit 2" 2
assert_contains "AC-C6 ... the message" "$OUT" "error: --commits given twice"
no_verdict "AC-C6 --commits twice"
gchk tester --commits "$P..$B" --base "$P"
assert_rc "AC-C6 --commits then --base: exit 2" 2
assert_contains "AC-C6 ... the message" "$OUT" "$XERR"
gchk tester --base "$P" --commits "$P..$B"
assert_rc "AC-C6 --base then --commits: exit 2" 2
assert_contains "AC-C6 ... the message" "$OUT" "$XERR"
no_verdict "AC-C6 --base with --commits"
MF="$(mk_tmp)/manifest"; gate snapshot --out "$MF"
assert_contains "AC-C6 setup: a baseline manifest was written" "$(cat "$MF" 2>/dev/null)" "# role-gate baseline v1"
gchk tester --commits "$P..$B" --baseline "$MF"
assert_rc "AC-C6 --commits with --baseline: exit 2" 2
assert_contains "AC-C6 ... the message" "$OUT" "$XERR"
SF="$(mk_tmp)/scope"; printf '# role-gate scope v1\nown\ttests/\n' > "$SF"
gchk tester --commits "$P..$B" --scope "$SF"
assert_rc "AC-C6 --commits with --scope (no --base): exit 2" 2
assert_contains "AC-C6 ... the combination message, not the --scope needs --base one" "$OUT" "$XERR"
gchk tester --scope "$SF" --base "$P" --commits "$P..$B"
assert_rc "AC-C6 --scope --base then --commits: exit 2" 2
assert_contains "AC-C6 ... the message" "$OUT" "$XERR"
no_verdict "AC-C6 --scope with --commits"

echo "AC-C6 range ends that are not commits, and A off the first-parent history of B: exit 3, no verdict"
gchk tester --commits "nosuchref..$B"
assert_rc "AC-C6 unknown start: exit 3" 3
assert_contains "AC-C6 ... names the end" "$OUT" "error: commit range end not found: nosuchref"
no_verdict "AC-C6 unknown start"
gchk tester --commits "$P..nosuchref"
assert_rc "AC-C6 unknown end: exit 3" 3
assert_contains "AC-C6 ... names the end" "$OUT" "error: commit range end not found: nosuchref"
BLOB="$(git rev-parse HEAD:README.md)"
gchk tester --commits "$P..$BLOB"
assert_rc "AC-C6 an end that is a blob, not a commit: exit 3" 3
assert_contains "AC-C6 ... names the end" "$OUT" "error: commit range end not found: $BLOB"
gchk tester --commits "$B..$P"
assert_rc "AC-C6 reversed range (A is a descendant of B): exit 3" 3
assert_contains "AC-C6 ... first-parent message (A and B as given)" "$OUT" "error: --commits $B..$P: $B is not on the first-parent history of $P"
no_verdict "AC-C6 reversed range"
MAINBR="$(git symbolic-ref --short HEAD)"
git checkout -q -b side; cmt tests/s.test.js 'test("s", () => {});' "side"; S1="$(git rev-parse HEAD)"
git checkout -q "$MAINBR"; cmt tests/m.test.js 'test("m", () => {});' "main"
git merge -q --no-ff --no-edit -m "merge side" side; M="$(git rev-parse HEAD)"
assert_eq "AC-C6 setup: S1 is an ancestor of M (through the second parent)" "0" "$(git merge-base --is-ancestor "$S1" "$M"; echo $?)"
gchk tester --commits "$S1..$M"
assert_rc "AC-C6 A only on the second-parent side of a merge in B: exit 3" 3
assert_contains "AC-C6 ... first-parent message" "$OUT" "error: --commits $S1..$M: $S1 is not on the first-parent history of $M"
no_verdict "AC-C6 A on the second-parent side"

# ================= S3 =================
echo "AC-C4 a merge on the first-parent chain is judged against its first parent; side-branch commits are not walked"
new_repo; MAINBR="$(git symbolic-ref --short HEAD)"
git checkout -q -b side
cmt src/tmp.js 'module.exports = "tmp";' "side adds code"
git rm -q src/tmp.js; git commit -q -m "side removes it"
cmt tests/side.test.js 'test("side", () => {});' "side test"
git checkout -q "$MAINBR"
cmt tests/main.test.js 'test("main", () => {});' "main test"; T1="$(git rev-parse HEAD)"
git merge -q --no-ff --no-edit -m "merge side" side; M="$(git rev-parse HEAD)"
assert_eq "AC-C4 setup: two commits on the first-parent chain P..M" "2" "$(git rev-list --first-parent --count "$P..$M")"
gchk tester --commits "$P..$M"
assert_rc "AC-C4 tester: the side branch added and removed code, the merge brings only a test: exit 0" 0
assert_not_contains "AC-C4 ... the side-branch-only code path is not judged" "$OUT" "src/tmp.js"
assert_contains "AC-C4 ... merge note with the full sha" "$OUT" "note: merge commit $M in $P..$M: judged against its first parent"
assert_eq "AC-C4 ... 2 commit(s) judged (first parent only)" "$(cnote "$P..$M" 2)" "$(first_note)"
assert_contains "AC-C4 ... 2 files checked (main test + what the merge brings)" "$OUT" "OK: role gate passed for tester (2 file(s) checked, commits=$P..$M)"
gchk implementer --commits "$T1..$M"
assert_rc "AC-C4 implementer range holding only the merge: the test it brings is judged, exit 1" 1
assert_contains "AC-C4 ... the brought-in test path is named" "$OUT" "VIOLATION (implementer): tests/side.test.js [test]"
git checkout -q side; cmt src/side.js 'module.exports = "side";' "side code"
git checkout -q "$MAINBR"; git merge -q --no-ff --no-edit -m "merge side again" side; M2="$(git rev-parse HEAD)"
gchk tester --commits "$M..$M2"
assert_rc "AC-C4 tester range whose merge brings a code path: exit 1" 1
assert_contains "AC-C4 ... the code path is named" "$OUT" "VIOLATION (tester): src/side.js [code]"
assert_contains "AC-C4 ... merge note" "$OUT" "note: merge commit $M2 in $M..$M2: judged against its first parent"

echo "AC-C7 a commit in the range that drops the executable bit is a mode violation for every role"
new_mode_repo
setx -x src/run.sh; git commit -q -m "drop"; setx +x src/run.sh; git commit -q -m "restore"
assert_eq "AC-C7 setup: no net change over the range" "" "$(git diff --raw "$P" HEAD)"
gchk implementer --commits "$P..HEAD"
assert_rc "AC-C7 implementer: a drop then a restore in a later commit: exit 1" 1
assert_contains "AC-C7 ... the mode violation names the path" "$OUT" "VIOLATION (mode): src/run.sh lost its executable bit (100755 -> 100644)"
gchk_allow src/run.sh implementer --commits "$P..HEAD"
assert_rc "AC-C7 PB_ALLOW_MODE_CHANGE with the exact path: exit 0" 0
assert_not_contains "AC-C7 ... no mode line" "$OUT" "(mode)"
gchk_allow src/second.sh implementer --commits "$P..HEAD"
assert_rc "AC-C7 another path in PB_ALLOW_MODE_CHANGE does not exempt it: exit 1" 1
new_mode_repo
git mv src/second.sh src/moved.sh; setx -x src/moved.sh; git commit -q -m "rename and drop"
gchk implementer --commits "$P..HEAD"
assert_rc "AC-C7 a rename with the same blob that drops the bit: exit 1" 1
assert_contains "AC-C7 ... the new path is named" "$OUT" "VIOLATION (mode): src/moved.sh lost its executable bit (100755 -> 100644)"
new_mode_repo
setx -x tests/run.sh; git commit -q -m "tester drops a test script bit"
gchk tester --commits "$P..HEAD"
assert_rc "AC-C7 tester (path allowed by role) dropping a bit: exit 1" 1
assert_contains "AC-C7 ... tester mode violation" "$OUT" "VIOLATION (mode): tests/run.sh lost its executable bit (100755 -> 100644)"
setx -x ci/run.sh; git commit -q -m "infra drops a bit"
gchk infra --commits "HEAD~1..HEAD"
assert_rc "AC-C7 infra (path allowed by role) dropping a bit: exit 1" 1
assert_contains "AC-C7 ... infra mode violation" "$OUT" "VIOLATION (mode): ci/run.sh lost its executable bit (100755 -> 100644)"
gchk reviewer --commits "$P..HEAD"
assert_contains "AC-C7 ... reviewer mode violation" "$OUT" "VIOLATION (mode): tests/run.sh lost its executable bit (100755 -> 100644)"
new_mode_repo
cmt src/plain.js 'plain v2' "implementer edit"; B="$(git rev-parse HEAD)"
setx -x src/second.sh
assert_contains "AC-C7 setup: the index carries an uncommitted drop" "$(git diff --cached --raw "$B")" ":100755 100644"
gchk implementer --commits "$P..$B"
assert_rc "AC-C7 a drop only in the index (and work tree): not judged, exit 0" 0
assert_not_contains "AC-C7 ... no mode line" "$OUT" "(mode)"

echo "AC-C8 implementer: a mode-restore-only commit of a test path is a note; a content change in any commit is a violation"
new_mode_repo
setx -x tests/run.sh; git commit -q -m RED; RED="$(git rev-parse HEAD)"
setx +x tests/run.sh; git commit -q -m "restore the bit"
gchk implementer --commits "$RED..HEAD"
assert_rc "AC-C8 a test path whose only change in the range is a mode restore: exit 0" 0
assert_contains "AC-C8 ... the restore note" "$OUT" "note: tests/run.sh mode restore only (100644 -> 100755, content unchanged)"
assert_not_contains "AC-C8 ... no violation" "$OUT" "VIOLATION"
printf '#!/bin/sh\necho weak\n' > tests/run.sh; git add tests/run.sh; setx +x tests/run.sh; git commit -q -m "weaken"
git show "$RED:tests/run.sh" > tests/run.sh; git add tests/run.sh; setx +x tests/run.sh; git commit -q -m "unweaken"
assert_contains "AC-C8 setup: the net change over the range is a mode restore only" "$(git diff --raw --no-renames "$RED" HEAD)" ":100644 100755 "
gchk implementer --commits "$RED..HEAD"
assert_rc "AC-C8 a content change in a commit of the range (later reverted): exit 1" 1
assert_contains "AC-C8 ... the test path is judged by role" "$OUT" "VIOLATION (implementer): tests/run.sh [test]"
assert_not_contains "AC-C8 ... no restore note" "$OUT" "note: tests/run.sh mode restore only"

t_summary
