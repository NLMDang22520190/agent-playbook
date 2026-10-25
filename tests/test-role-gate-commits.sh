#!/usr/bin/env bash
# Tests for scripts/role-gate.sh `check ROLE --commits A..B` (v0.26.1 lane G, slices S1-S3 of .agents/handoff/01-spec.md):
# S1 AC-C1 (oracle P/T1/I1/T2), AC-C2 role matrix per commit (also commit + revert), AC-C3 work tree/index/untracked not judged,
# AC-C5 verdict lines and the empty range, plus feedback cases fb #3/#4/#7-#13 rebuilt for --commits; S2 AC-C6 argument errors
# and incompatibilities; S3 AC-C4 merges (first parent), AC-C7 per-commit mode check, AC-C8 mode restore note.
# S4 `--paths-from FILE` with --base: AC-P1 filter and outside notes, AC-P2 summary note, AC-P4 file format and errors, AC-P5 mode
# check unchanged; S5 AC-P3 with --baseline and refused with --scope, AC-P6 refused with --commits, AC-D2 header/usage text.
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
git reset -q -- src/staged.js   # isolate the commit: cmt commits the whole index, the staged file must not ride along
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

# ================= S4 (--paths-from with --base) =================
# dig FILE -> git hash-object of FILE (the AC-P2 digest)
dig() { git hash-object -- "$1" 2>/dev/null || printf 'NODIGEST'; }
# pf FILE ENTRY... -> a paths-from list, one entry per line
pf() { local f="$1"; shift; printf '%s\n' "$@" > "$f"; }
# onote PATH KIND -> the AC-P1 per-path note; psum FILE N K -> the AC-P2 summary note
onote() { printf 'note: outside the paths-from list, not checked: %s [%s]' "$1" "$2"; }
psum() { printf 'note: paths-from %s (%s entries, digest %s): %s changed path(s) outside the list not checked' "$1" "$2" "$(dig "$1")" "$3"; }
# has_line NAME LINE: $OUT has exactly this line; no_line NAME LINE: it has not
has_line() { if printf '%s\n' "$OUT" | grep -Fx -- "$2" >/dev/null 2>&1; then t_ok "$1"; else t_bad "$1" "no line [$2] in: $OUT"; fi; }
no_line() { if printf '%s\n' "$OUT" | grep -Fx -- "$2" >/dev/null 2>&1; then t_bad "$1" "unexpected line [$2] in: $OUT"; else t_ok "$1"; fi; }
# first_pnote -> the first paths-from note of $OUT (summary or per-path)
first_pnote() { printf '%s\n' "$OUT" | grep -e '^note: paths-from ' -e '^note: outside the paths-from list' | head -1; }
PERR='error: --paths-from cannot be combined with --scope'
PCERR='error: --paths-from cannot be combined with --commits'

echo "AC-P1/AC-P2 --paths-from with --base: listed paths judged as without it, outside paths named in notes, the summary first"
new_repo
PF="$(mk_tmp)/paths"; pf "$PF" src/ README.md
printf 'module.exports = 2;\n' > src/app.js; mkdir -p src/deep; printf 'd\n' > src/deep/new.js
printf 'test("y", () => {});\n' > tests/app.test.js; printf 'test("n", () => {});\n' > tests/new.test.js
mkdir -p ci; printf 'on: push\n' > ci/run.yml
gchk implementer --base "$P"
assert_rc "AC-P1 control: without --paths-from the test and infra paths are violations: exit 1" 1
gchk implementer --base "$P" --paths-from "$PF"
assert_rc "AC-P1 implementer, only the listed code paths are judged: exit 0" 0
has_line "AC-P1 ... the OK line counts the judged (listed) paths only" "OK: role gate passed for implementer (2 file(s) checked, base=$P)"
has_line "AC-P1 ... an outside modified test path is named with its kind" "$(onote tests/app.test.js test)"
has_line "AC-P1 ... an outside untracked test path is named" "$(onote tests/new.test.js test)"
has_line "AC-P1 ... an outside infra path is named" "$(onote ci/run.yml infra)"
no_line "AC-P1 ... a listed path (dir/ prefix) gets no outside note" "$(onote src/deep/new.js code)"
assert_not_contains "AC-P1 ... no violation" "$OUT" "VIOLATION"
has_line "AC-P2 the summary note: FILE, 2 entries, digest, 3 outside" "$(psum "$PF" 2 3)"
assert_eq "AC-P2 ... the summary is printed once" "1" "$(printf '%s\n' "$OUT" | grep -c '^note: paths-from ')"
assert_eq "AC-P2 ... the summary comes first among the paths-from notes" "$(psum "$PF" 2 3)" "$(first_pnote)"

echo "AC-P1 a listed path is judged as without the option; the default base is HEAD"
new_repo
PF="$(mk_tmp)/paths"; pf "$PF" tests/app.test.js
printf 'module.exports = 2;\n' > src/app.js; printf 'test("y", () => {});\n' > tests/app.test.js
gchk implementer --base "$P" --paths-from "$PF"
assert_rc "AC-P1 implementer, the listed test path changed: exit 1" 1
has_line "AC-P1 ... the VIOLATION line is today's format" "VIOLATION (implementer): tests/app.test.js [test]"
has_line "AC-P1 ... the FAILED line is today's format (base=REF)" "role gate FAILED for implementer: 1 violation(s), base=$P"
has_line "AC-P1 ... the outside code path is named" "$(onote src/app.js code)"
has_line "AC-P2 ... summary: 1 entry, 1 outside" "$(psum "$PF" 1 1)"
gchk tester --paths-from "$PF"
assert_rc "AC-P1 tester with the default base (HEAD): listed test passes, code is outside: exit 0" 0
has_line "AC-P1 ... OK line with base=HEAD" "OK: role gate passed for tester (1 file(s) checked, base=HEAD)"
has_line "AC-P1 ... the code path is named, not judged" "$(onote src/app.js code)"

echo "AC-P4 entries match byte for byte: dir/ is a prefix, an entry without / is one exact path, no globs, empty lines skipped"
new_repo
PF="$(mk_tmp)/paths"; printf 'src\n\nsrc/dee\ntests/*.test.js\n\n' > "$PF"
mkdir -p src/deep; printf 'x\n' > src/deep/a.js; printf 'module.exports = 2;\n' > src/app.js; printf 'test("y", () => {});\n' > tests/app.test.js
gchk reviewer --base "$P" --paths-from "$PF"
assert_rc "AC-P4 reviewer: 'src' (no /), 'src/dee' and a glob match none of the changed paths: exit 0" 0
has_line "AC-P4 ... 0 files checked" "OK: role gate passed for reviewer (0 file(s) checked, base=$P)"
has_line "AC-P4 ... 3 entries (empty lines skipped), 3 outside" "$(psum "$PF" 3 3)"
has_line "AC-P4 ... 'src' is not a prefix of src/app.js" "$(onote src/app.js code)"
has_line "AC-P4 ... 'src/dee' is not a prefix of src/deep/a.js" "$(onote src/deep/a.js code)"
has_line "AC-P4 ... no glob: tests/*.test.js does not match" "$(onote tests/app.test.js test)"
pf "$PF" src/deep/ tests/app.test.js
gchk reviewer --base "$P" --paths-from "$PF"
assert_rc "AC-P4 control: a dir/ prefix and an exact path do match: exit 1" 1
has_line "AC-P4 ... the prefix-matched path is judged" "VIOLATION (reviewer): src/deep/a.js [code]"
has_line "AC-P4 ... the exact path is judged" "VIOLATION (reviewer): tests/app.test.js [test]"
has_line "AC-P4 ... the unlisted path is named" "$(onote src/app.js code)"

echo "AC-P1 a control character in an outside path is shown as ?"
new_repo
PF="$(mk_tmp)/paths"; pf "$PF" src/
SOHB="$(printf "$(printf '\\%s' 001)")"   # the byte is built from pieces at run time (run-checks soh)
CN="docs/a${SOHB}b.md"; mkdir -p docs; printf 'x\n' > "$CN" 2>/dev/null
if [ -f "$CN" ] && [ "$(git ls-files --others -z 2>/dev/null | tr -d '\000')" = "$CN" ]; then
  gchk implementer --base "$P" --paths-from "$PF"
  has_line "AC-P1 ... the \\001 byte is shown as ?" "$(onote 'docs/a?b.md' code)"
  assert_not_contains "AC-P1 ... the raw byte is not printed" "$OUT" "$CN"
else t_skip 2 "AC-P1 control character (this file system cannot store a \\001 name)"; fi

echo "AC-P4 a bad paths-from file: exit 3, no verdict"
new_repo
printf 'module.exports = 2;\n' > src/app.js
PF="$(mk_tmp)/paths"
gchk implementer --base "$P" --paths-from "$PF"
assert_rc "AC-P4 a missing file: exit 3" 3
has_line "AC-P4 ... the message is exact" "error: paths-from file not readable: $PF"
no_verdict "AC-P4 a missing file"
pf "$PF" src/; chmod 000 "$PF" 2>/dev/null
if [ "$(id -u)" != 0 ] && ! cat "$PF" >/dev/null 2>&1; then
  gchk implementer --base "$P" --paths-from "$PF"
  assert_rc "AC-P4 an unreadable file (chmod 000): exit 3" 3
  has_line "AC-P4 ... the message is exact" "error: paths-from file not readable: $PF"
else t_skip 2 "AC-P4 unreadable file (running as root, or chmod 000 has no effect here)"; fi
chmod 644 "$PF" 2>/dev/null
# pbad NAME PRINTF-FORMAT LINE -> exit 3, "error: malformed paths-from file FILE: line LINE: <reason>", no verdict
pbad() {
  printf "$2" > "$PF"
  gchk implementer --base "$P" --paths-from "$PF"
  assert_rc "AC-P4 $1: exit 3" 3
  assert_contains "AC-P4 $1: malformed, line $3" "$OUT" "error: malformed paths-from file $PF: line $3: "
  no_verdict "AC-P4 $1"
}
pbad "a CR (CRLF line end) on line 1" 'src/\r\n' 1
pbad "a CR on line 3 (after an empty line; physical line numbers)" 'src/\n\nREADME.md\r\n' 3
pbad "a UTF-8 BOM" '\xef\xbb\xbfsrc/\n' 1
pbad "a NUL on line 2" 'src/\nsrc/a\0b.js\n' 2
: > "$PF"
gchk implementer --base "$P" --paths-from "$PF"
assert_rc "AC-P4 an empty file: exit 3" 3
has_line "AC-P4 ... the message is exact" "error: paths-from file has no entries: $PF"
no_verdict "AC-P4 an empty file"
printf '\n\n' > "$PF"
gchk implementer --base "$P" --paths-from "$PF"
assert_rc "AC-P4 only empty lines: exit 3" 3
has_line "AC-P4 ... the message is exact" "error: paths-from file has no entries: $PF"
TF="$R/pf-list.txt"; pf "$TF" src/; git add pf-list.txt; git commit -q -m "list"
gchk implementer --base "$P" --paths-from "$TF"
assert_rc "AC-P4 a tracked file of the repository: exit 3" 3
has_line "AC-P4 ... the message is exact" "error: the paths-from file is a tracked file of this repository: $TF"
no_verdict "AC-P4 a tracked file"

echo "AC-P4 a missing value or --paths-from twice: exit 2, no verdict"
pf "$PF" src/
gchk implementer --base "$P" --paths-from
assert_rc "AC-P4 --paths-from with no value: exit 2" 2
has_line "AC-P4 ... the message is exact" "error: --paths-from needs a file"
no_verdict "AC-P4 no value"
gchk implementer --paths-from "" --base "$P"
assert_rc "AC-P4 --paths-from with an empty value: exit 2" 2
has_line "AC-P4 ... the message is exact" "error: --paths-from needs a file"
gchk implementer --paths-from "$PF" --base "$P" --paths-from "$PF"
assert_rc "AC-P4 --paths-from given twice: exit 2" 2
has_line "AC-P4 ... the message is exact" "error: --paths-from given twice"
no_verdict "AC-P4 twice"

echo "AC-P4 a relative FILE resolves against the caller's directory"
new_repo
printf 'src/\n' > .git/pf-rel
printf 'module.exports = 2;\n' > src/app.js; printf 'test("y", () => {});\n' > tests/app.test.js
cd "$R/src" || exit 3
gchk implementer --base "$P" --paths-from ../.git/pf-rel
assert_rc "AC-P4 a relative FILE from a subdirectory: exit 0" 0
has_line "AC-P4 ... the outside path is named top-relative" "$(onote tests/app.test.js test)"
cd "$R" || exit 3

echo "AC-P5 the mode check exempts nothing with --paths-from; .agents/handoff/ paths are never named"
new_mode_repo
PF="$(mk_tmp)/paths"; pf "$PF" src/plain.js
printf 'plain v2\n' > src/plain.js
setx -x src/second.sh
mkdir -p .agents/handoff; printf 'n\n' > .agents/handoff/notes.md
gchk implementer --base "$P" --paths-from "$PF"
assert_rc "AC-P5 a lost exec bit on a path outside the list: exit 1" 1
has_line "AC-P5 ... the mode violation" "VIOLATION (mode): src/second.sh lost its executable bit (100755 -> 100644)"
assert_not_contains "AC-P5 ... .agents/handoff/ is not named" "$OUT" ".agents/handoff"
gchk_allow src/second.sh implementer --base "$P" --paths-from "$PF"
assert_rc "AC-P5 PB_ALLOW_MODE_CHANGE stays the escape: exit 0" 0
has_line "AC-P5 ... the listed path is judged and passes" "OK: role gate passed for implementer (1 file(s) checked, base=$P)"
assert_not_contains "AC-P5 ... no mode line" "$OUT" "(mode)"

# ================= S5 (combinations, usage text) =================
echo "AC-P3 --paths-from with --baseline: the list filters what the baseline left to judge"
new_repo
printf 'test("pre", () => {});\n' > tests/app.test.js; printf 'pre\n' > src/pre.js
MF="$(mk_tmp)/manifest"; gate snapshot --out "$MF"
assert_contains "AC-P3 setup: a baseline manifest was written" "$(cat "$MF" 2>/dev/null)" "# role-gate baseline v1"
printf 'module.exports = 2;\n' > src/app.js; mkdir -p docs; printf 'other\n' > docs/other.md
PF="$(mk_tmp)/paths"; pf "$PF" src/
gchk implementer --baseline "$MF" --paths-from "$PF"
assert_rc "AC-P3 implementer --baseline --paths-from: exit 0" 0
has_line "AC-P3 ... the baseline still skips the pre-dirty test path" "note: unchanged since the baseline: tests/app.test.js"
no_line "AC-P3 ... a baseline-skipped path is not also an outside note" "$(onote tests/app.test.js test)"
has_line "AC-P3 ... the new outside path is named" "$(onote docs/other.md code)"
has_line "AC-P3 ... summary: 1 entry, 1 outside (after the baseline)" "$(psum "$PF" 1 1)"
has_line "AC-P3 ... 1 file checked (src/pre.js is unchanged since the baseline)" "OK: role gate passed for implementer (1 file(s) checked, base=HEAD)"
gchk tester --base "$P" --baseline "$MF" --paths-from "$PF"
assert_rc "AC-P3 tester --base --baseline --paths-from: the listed code path is judged: exit 1" 1
has_line "AC-P3 ... the listed code path is a violation" "VIOLATION (tester): src/app.js [code]"
no_line "AC-P3 ... the baseline-skipped listed path is not judged" "VIOLATION (tester): src/pre.js [code]"
has_line "AC-P3 ... the FAILED line names the base" "role gate FAILED for tester: 1 violation(s), base=$P"

echo "AC-P3 --paths-from with --scope: exit 2, no verdict (either order)"
SF="$(mk_tmp)/scope"; printf '# role-gate scope v1\nown\tsrc/\n' > "$SF"
gchk implementer --base "$P" --scope "$SF" --paths-from "$PF"
assert_rc "AC-P3 --scope then --paths-from: exit 2" 2
has_line "AC-P3 ... the message is exact" "$PERR"
no_verdict "AC-P3 --scope then --paths-from"
gchk implementer --paths-from "$PF" --base "$P" --scope "$SF"
assert_rc "AC-P3 --paths-from then --scope: exit 2" 2
has_line "AC-P3 ... the message is exact" "$PERR"
no_verdict "AC-P3 --paths-from then --scope"

echo "AC-P6 --commits with --paths-from: exit 2, no verdict, nothing judged (either order)"
new_repo
cmt src/app.js 'module.exports = 2;' "tester touches code"; B="$(git rev-parse HEAD)"
PF="$(mk_tmp)/paths"; pf "$PF" tests/
gchk tester --commits "$P..$B" --paths-from "$PF"
assert_rc "AC-P6 --commits then --paths-from: exit 2" 2
has_line "AC-P6 ... the message is exact" "$PCERR"
no_verdict "AC-P6 --commits then --paths-from"
assert_not_contains "AC-P6 ... nothing judged" "$OUT" "VIOLATION"
gchk tester --paths-from "$PF" --commits "$P..$B"
assert_rc "AC-P6 --paths-from then --commits: exit 2" 2
has_line "AC-P6 ... the message is exact" "$PCERR"
no_verdict "AC-P6 --paths-from then --commits"
assert_not_contains "AC-P6 ... no outside note either" "$OUT" "outside the paths-from list"

echo "AC-D2 the header comment and both usage strings list --commits A..B and --paths-from FILE"
HDR="$(grep -m1 '^#   role-gate.sh check ' "$GATE")"
assert_contains "AC-D2 the header usage line of check names --commits A..B" "$HDR" "--commits A..B"
assert_contains "AC-D2 the header usage line of check names --paths-from FILE" "$HDR" "--paths-from FILE"
gate frobnicate
assert_rc "AC-D2 an unknown subcommand: exit 2" 2
assert_contains "AC-D2 ... the usage names --commits A..B" "$OUT" "--commits A..B"
assert_contains "AC-D2 ... the usage names --paths-from FILE" "$OUT" "--paths-from FILE"
gate size --bogus
assert_rc "AC-D2 size with an unknown option: exit 2" 2
assert_contains "AC-D2 ... the usage names --commits A..B" "$OUT" "--commits A..B"
assert_contains "AC-D2 ... the usage names --paths-from FILE" "$OUT" "--paths-from FILE"

echo "review fix 6: --paths-from entries: a leading ./ is normalised; an absolute or .. entry exits 3"
new_repo
printf 'module.exports = 2;\n' > src/app.js; printf 'test("y", () => {});\n' > tests/app.test.js
PF="$(mk_tmp)/paths"; pf "$PF" ./src/app.js tests/app.test.js
gchk tester --base "$P" --paths-from "$PF"
assert_rc "fix6 ./src/app.js names src/app.js: the tester's code edit is judged: exit 1" 1
has_line "fix6 ... the listed code path is a violation" "VIOLATION (tester): src/app.js [code]"
no_line "fix6 ... it is not an outside note" "$(onote src/app.js code)"
pf "$PF" ./src/ tests/app.test.js
gchk tester --base "$P" --paths-from "$PF"
assert_rc "fix6 ./src/ is the prefix src/: exit 1" 1
has_line "fix6 ... the code path under ./src/ is a violation" "VIOLATION (tester): src/app.js [code]"
# pnp NAME ENTRY -> line 2 of the list is ENTRY: exit 3, "malformed paths-from file FILE: line 2: ", no verdict
pnp() {
  printf 'tests/app.test.js\n%s\n' "$2" > "$PF"
  gchk tester --base "$P" --paths-from "$PF"
  assert_rc "fix6 $1: exit 3" 3
  assert_contains "fix6 $1: malformed, line 2" "$OUT" "error: malformed paths-from file $PF: line 2: "
  no_verdict "fix6 $1"
}
pnp "an absolute entry (the repo path)" "$R/src/app.js"
pnp "an entry ../src/app.js" "../src/app.js"
pnp "an entry with a .. segment inside" "src/../src/app.js"
pnp "the entry .." ".."

t_summary
