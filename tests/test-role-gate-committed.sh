#!/usr/bin/env bash
# Tests for scripts/role-gate.sh v0.24.20 item 5 (slice S1): `check` also judges committed changes (BASE..HEAD) and the index
# (AC1-AC6, AC8 of .agents/handoff/01-spec.md): a role that commits a change and restores the tree, a staged-only change, the
# mode drop that was committed and restored, the pairing of the BASE..HEAD list on its own, --baseline, and the v0.24.9 mode
# restore note (P7, P8). AC3 compares the normal flows byte for byte with the gate of d35e95d (before this feature).
# Shared setup: role-gate-fixture.sh. Exec-bit blocks probe the file system and skip with exact counts.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/role-gate-fixture.sh"
unset PB_ALLOW_MODE_CHANGE
T="$(printf '\t')"

gate() { run env PLAYBOOK_HOME="$IH" bash "$GATE" "$@"; }
# blk_check NAME DECLARED DELTA: a skipped block declares how many assertions it holds; a drift is a failure here
blk_check() { if [ "$2" != "$3" ]; then t_bad "$1: the declared skip count ($2) matches the assertions run ($3)" ""; fi; }
new_repo() { R="$(mk_tmp)"; mk_repo "$R"; cd "$R" || exit 3; }
new_mode_repo() { R="$(mk_tmp)"; mk_mode_repo "$R"; cd "$R" || exit 3; }
# fs_exec_ok: 0 when this file system keeps executable bits (the cwd is a fresh mode repo); leaves tests/run.sh as it was
fs_exec_ok() {
  git config core.fileMode true
  [ -z "$(git diff --raw 2>/dev/null)" ] || return 1
  chmod -x tests/run.sh 2>/dev/null
  if [ ! -x tests/run.sh ]; then chmod +x tests/run.sh 2>/dev/null; [ -x tests/run.sh ] && [ -z "$(git diff --raw 2>/dev/null)" ]; else return 1; fi
}

echo "AC1 a role commits a change and restores the work tree and index to BASE: judged by role"
new_repo; BASE="$(git rev-parse HEAD)"
printf 'test("y", () => {});\n' > tests/app.test.js; git commit -qam "edit test"
git checkout -q "$BASE" -- tests/app.test.js
assert_eq "AC1 setup: the work tree and index equal BASE again" "" "$(git diff --raw "$BASE"; git diff --cached --raw "$BASE")"
gchk implementer --base "$BASE"
assert_rc "AC1 implementer committed a test change then restored it: exit 1" 1
assert_contains "AC1 ... the test path is named" "$OUT" "VIOLATION (implementer): tests/app.test.js [test]"
gchk tester --base "$BASE"
assert_rc "AC1 tester committed a test change then restored it: allowed, exit 0" 0
assert_contains "AC1 ... the path is counted as checked" "$OUT" "OK: role gate passed for tester (1 file(s) checked"
new_repo; BASE="$(git rev-parse HEAD)"
printf 'module.exports = 2;\n' > src/app.js; git commit -qam "edit code"
git checkout -q "$BASE" -- src/app.js
gchk tester --base "$BASE"
assert_rc "AC1 tester committed a code change then restored it: exit 1" 1
assert_contains "AC1 ... the code path is named" "$OUT" "VIOLATION (tester): src/app.js [code]"
gchk reviewer --base "$BASE"
assert_rc "AC1 reviewer committed a code change then restored it: exit 1" 1
assert_contains "AC1 ... the code path is named" "$OUT" "VIOLATION (reviewer): src/app.js [code]"
gchk implementer --base "$BASE"
assert_rc "AC1 implementer committed a code change then restored it: allowed, exit 0" 0
assert_contains "AC1 ... the path is counted as checked" "$OUT" "OK: role gate passed for implementer (1 file(s) checked"

echo "AC1 a staged change whose work tree was restored (MM), default base"
new_repo
printf 'module.exports = 2;\n' > src/app.js; git add src/app.js; git show HEAD:src/app.js > src/app.js
gchk reviewer
assert_rc "AC1 reviewer, staged-only code change (work tree = HEAD): exit 1" 1
assert_contains "AC1 ... the path is named" "$OUT" "VIOLATION (reviewer): src/app.js [code]"
gchk tester
assert_rc "AC1 tester, staged-only code change: exit 1" 1
assert_contains "AC1 ... the code path is named" "$OUT" "VIOLATION (tester): src/app.js [code]"
new_repo
printf 'test("z", () => {});\n' > tests/app.test.js; git add tests/app.test.js; git show HEAD:tests/app.test.js > tests/app.test.js
gchk implementer
assert_rc "AC1 implementer, staged-only test change: exit 1" 1
assert_contains "AC1 ... the test path is named" "$OUT" "VIOLATION (implementer): tests/app.test.js [test]"

echo "AC5 a path in several lists is counted once in the OK line"
new_repo
for n in a b c d; do printf 'v0 %s\n' "$n" > "src/$n.js"; done
git add -A; git commit -qm "four files"; BASE="$(git rev-parse HEAD)"
printf 'v1\n' >> src/a.js; printf 'v1\n' >> src/b.js; printf 'v1\n' >> src/d.js; git commit -qam "edit a b d"
git checkout -q "$BASE" -- src/b.js
printf 'v1\n' >> src/c.js; git add src/c.js; git show "$BASE:src/c.js" > src/c.js
printf 'v2\n' >> src/d.js
gchk implementer --base "$BASE"
assert_rc "AC5 four code paths over HEAD, index and work tree: implementer exit 0" 0
assert_contains "AC5 each path once: 4 files checked" "$OUT" "OK: role gate passed for implementer (4 file(s) checked, base="
gchk reviewer --base "$BASE"
assert_contains "AC5 the reviewer reports 4 violations, one per path" "$OUT" "role gate FAILED for reviewer: 4 violation(s), base="

echo "AC2 a committed 100755 -> 100644 drop restored in the work tree and index is reported"
new_mode_repo
if ! fs_exec_ok; then t_skip 6 "AC2 committed drop (this file system does not keep executable bits)"
else
  B0=$((T_PASS + T_FAIL))
  BASE="$(git rev-parse HEAD)"
  chmod -x src/run.sh; git update-index --chmod=-x -- src/run.sh; git commit -qm "drop the bit"
  git checkout -q "$BASE" -- src/run.sh
  assert_eq "AC2 setup: the work tree and index equal BASE again" "" "$(git diff --raw "$BASE"; git diff --cached --raw "$BASE")"
  gchk implementer --base "$BASE"
  assert_rc "AC2 a committed drop restored afterwards: exit 1" 1
  assert_contains "AC2 ... the mode violation names the path" "$OUT" "VIOLATION (mode): src/run.sh lost its executable bit (100755 -> 100644)"
  gchk_allow src/run.sh implementer --base "$BASE"
  assert_rc "AC2 PB_ALLOW_MODE_CHANGE with the exact path silences it: exit 0" 0
  assert_not_contains "AC2 ... no mode line" "$OUT" "(mode)"
  gchk_allow src/second.sh implementer --base "$BASE"
  assert_rc "AC2 another path in PB_ALLOW_MODE_CHANGE does not silence it: exit 1" 1
  blk_check "AC2 committed drop block" 6 $((T_PASS + T_FAIL - B0))
fi

echo "AC2 the BASE..HEAD list is paired on its own: a delete in HEAD and an add in the work tree are not a rename"
new_mode_repo; BASE="$(git rev-parse HEAD)"
git rm -q src/run.sh; git commit -qm "delete run.sh"
git checkout -q "$BASE" -- src/run.sh
cp src/run.sh src/copy.sh; chmod -x src/copy.sh 2>/dev/null; git add src/copy.sh; git update-index --chmod=-x -- src/copy.sh
gchk tester --base "$BASE"
assert_rc "AC2 tester: a deleted-and-restored code file plus a new code copy: exit 1" 1
assert_contains "AC2 ... the restored path is judged by role (HEAD deleted it)" "$OUT" "VIOLATION (tester): src/run.sh [code]"
assert_contains "AC2 ... the copy is judged by role" "$OUT" "VIOLATION (tester): src/copy.sh [code]"
gchk implementer --base "$BASE"
assert_not_contains "AC2 no cross-list pairing: the copy did not lose a bit" "$OUT" "lost its executable bit"
assert_contains "AC2 implementer judges both paths: 2 files checked" "$OUT" "OK: role gate passed for implementer (2 file(s) checked"

echo "AC3 normal flows give the same output and exit code as the gate of d35e95d"
OLDD="$(mk_tmp)"; OLDG="$OLDD/scripts/role-gate.sh"
if git -C "$PB_ROOT" cat-file -e d35e95d 2>/dev/null && git -C "$PB_ROOT" archive d35e95d scripts 2>/dev/null | tar -x -C "$OLDD" 2>/dev/null && [ -f "$OLDG" ]; then HAVE_OLD=1; else HAVE_OLD=0; fi
# cmp_old NAME ARGS...: the new gate and the old gate in the cwd, same arguments; output and exit code must be identical
cmp_old() {
  local n="$1" o1 r1; shift
  gchk "$@"; o1="$OUT"; r1="$RC"
  run env PLAYBOOK_HOME="$IH" bash "$OLDG" check "$@"
  assert_eq "AC3 $n: same output" "$OUT" "$o1"
  assert_eq "AC3 $n: same exit code" "$RC" "$r1"
}
new_repo
printf 'test("red", () => { throw 1; });\n' > tests/app.test.js
gchk tester; assert_rc "AC3 tester, uncommitted RED test: exit 0" 0
assert_contains "AC3 ... one file checked" "$OUT" "OK: role gate passed for tester (1 file(s) checked"
git add -A; git commit -qm RED; RED="$(git rev-parse HEAD)"
printf 'module.exports = 2;\n' > src/app.js
gchk implementer --base "$RED"; assert_rc "AC3 implementer, uncommitted GREEN edit: exit 0" 0
if [ "$HAVE_OLD" = 1 ]; then
  B0=$((T_PASS + T_FAIL))
  cmp_old "implementer --base RED before the GREEN commit" implementer --base "$RED"
  git add -A; git commit -qm GREEN; GREEN="$(git rev-parse HEAD)"
  cmp_old "implementer --base RED after the GREEN commit" implementer --base "$RED"
  printf 'module.exports = 3;\n' > src/app.js
  cmp_old "implementer --base RED with a REFACTOR edit on top" implementer --base "$RED"
  cmp_old "reviewer, default base" reviewer
  cmp_old "reviewer --base GREEN" reviewer --base "$GREEN"
  cmp_old "tester, default base" tester
  blk_check "AC3 old-gate comparison block" 12 $((T_PASS + T_FAIL - B0))
else
  git add -A; git commit -qm GREEN; GREEN="$(git rev-parse HEAD)"; printf 'module.exports = 3;\n' > src/app.js
  t_skip 12 "AC3 old-gate comparison (commit d35e95d is not in this repository)"
fi
gchk implementer --base "$RED"
assert_rc "AC3 implementer after GREEN commit and REFACTOR edit: exit 0" 0
assert_contains "AC3 ... one file checked (src/app.js only)" "$OUT" "OK: role gate passed for implementer (1 file(s) checked"
gchk reviewer
assert_rc "AC3 reviewer with the REFACTOR edit uncommitted: exit 1" 1
assert_contains "AC3 ... the edit is named" "$OUT" "VIOLATION (reviewer): src/app.js [code]"

echo "AC3 --base HEAD~1 with an uncommitted revert of a committed test edit is judged"
new_repo
printf 'test("y", () => {});\n' > tests/app.test.js; git commit -qam "edit test"
git show HEAD~1:tests/app.test.js > tests/app.test.js
gchk implementer --base HEAD~1
assert_rc "AC3 an uncommitted revert of a committed test edit, base HEAD~1: exit 1" 1
assert_contains "AC3 ... the test path is named (HEAD still carries the edit)" "$OUT" "VIOLATION (implementer): tests/app.test.js [test]"

echo "AC4 --baseline: a committed-and-restored path is judged even when its states equal the recorded ones"
new_repo
printf 'test("v1", () => {});\n' > tests/app.test.js; git commit -qam "v1"
BASE="$(git rev-parse HEAD~1)"
git show "$BASE:tests/app.test.js" > tests/app.test.js
MF="$(mk_tmp)/m"; gate snapshot --out "$MF"
assert_contains "AC4 setup: the manifest records the path" "$(cat "$MF")" "tests/app.test.js"
gate check implementer --base "$BASE" --baseline "$MF"
assert_rc "AC4 a commit since BASE touched the recorded path: exit 1" 1
assert_contains "AC4 ... the path is judged" "$OUT" "VIOLATION (implementer): tests/app.test.js [test]"
new_repo; BASE="$(git rev-parse HEAD)"
printf 'dirty\n' > src/dirty.js
MF="$(mk_tmp)/m"; gate snapshot --out "$MF"
printf 'test("y", () => {});\n' > tests/app.test.js; git add tests/app.test.js; git commit -qm "role commit"
git checkout -q "$BASE" -- tests/app.test.js
gate check implementer --base "$BASE" --baseline "$MF"
assert_rc "AC4 a role commit after the snapshot, then restored, with a baseline: exit 1" 1
assert_contains "AC4 ... the committed-and-restored test path is judged" "$OUT" "VIOLATION (implementer): tests/app.test.js [test]"

echo "AC8 P7: RED drops the bit; a committed weakened edit at +x, content restored in the work tree and index keeping +x"
new_mode_repo
chmod -x tests/run.sh 2>/dev/null; git update-index --chmod=-x -- tests/run.sh; git commit -qm RED; RED="$(git rev-parse HEAD)"
printf '#!/bin/sh\necho weak\n' > tests/run.sh; git add tests/run.sh; git update-index --chmod=+x -- tests/run.sh; chmod +x tests/run.sh 2>/dev/null; git commit -qm weak
git show "$RED:tests/run.sh" > tests/run.sh; git add tests/run.sh; git update-index --chmod=+x -- tests/run.sh; chmod +x tests/run.sh 2>/dev/null
if ! git diff --raw --no-renames "$RED" | grep -q '^:100644 100755'; then t_skip 3 "AC8 P7 (the work tree does not show a 100644 -> 100755 restore against RED here)"
else
  B0=$((T_PASS + T_FAIL))
  gchk implementer --base "$RED"
  assert_rc "AC8 P7 the committed weakened edit is a violation: exit 1" 1
  assert_contains "AC8 P7 ... the test path is judged by role" "$OUT" "VIOLATION (implementer): tests/run.sh [test]"
  assert_not_contains "AC8 P7 ... no mode restore note for the path" "$OUT" "note: tests/run.sh mode restore only"
  blk_check "AC8 P7 block" 3 $((T_PASS + T_FAIL - B0))
fi

echo "AC8 P8: HEAD = RED, the index holds a weakened edit, the work tree is a mode restore only"
new_mode_repo
if ! fs_exec_ok; then t_skip 3 "AC8 P8 (this file system does not keep executable bits)"
else
  B0=$((T_PASS + T_FAIL))
  chmod -x tests/run.sh; git update-index --chmod=-x -- tests/run.sh; git commit -qm RED
  printf '#!/bin/sh\necho weak\n' > tests/run.sh; git add tests/run.sh
  git show HEAD:tests/run.sh > tests/run.sh; chmod +x tests/run.sh
  gchk implementer
  assert_rc "AC8 P8 a staged weakened edit behind a work-tree mode restore: exit 1" 1
  assert_contains "AC8 P8 ... the test path is judged by role" "$OUT" "VIOLATION (implementer): tests/run.sh [test]"
  assert_not_contains "AC8 P8 ... no mode restore note for the path" "$OUT" "note: tests/run.sh mode restore only"
  blk_check "AC8 P8 block" 3 $((T_PASS + T_FAIL - B0))
fi

echo "AC8 a genuine v0.24.9 mode restore (work tree only, same blob, index and HEAD equal BASE) still prints the note (characterization: passes before the change)"
new_mode_repo
if ! fs_exec_ok; then t_skip 3 "AC8 genuine mode restore (this file system does not keep executable bits)"
else
  B0=$((T_PASS + T_FAIL))
  chmod -x tests/run.sh; git update-index --chmod=-x -- tests/run.sh; git commit -qm RED
  chmod +x tests/run.sh
  gchk implementer
  assert_rc "AC8 genuine restore: exit 0" 0
  assert_contains "AC8 genuine restore: the note is printed" "$OUT" "note: tests/run.sh mode restore only (100644 -> 100755, content unchanged)"
  assert_not_contains "AC8 genuine restore: no violation" "$OUT" "VIOLATION"
  blk_check "AC8 genuine restore block" 3 $((T_PASS + T_FAIL - B0))
fi

echo "v0.24.21 C1 a 100644 -> 100755 restore carried only in HEAD (work tree and index back at 100644) stays a violation (characterization: fail closed, passes before and after)"
new_mode_repo
if ! fs_exec_ok; then t_skip 3 "C1 HEAD-only restore (this file system does not keep executable bits)"
else
  B0=$((T_PASS + T_FAIL))
  chmod -x tests/run.sh; git update-index --chmod=-x -- tests/run.sh; git commit -qm RED; RED="$(git rev-parse HEAD)"
  chmod +x tests/run.sh; git update-index --chmod=+x -- tests/run.sh; git commit -qm "restore in HEAD"
  chmod -x tests/run.sh; git update-index --chmod=-x -- tests/run.sh
  gchk implementer --base "$RED"
  assert_rc "C1 a restore in HEAD only (work tree and index equal RED again): exit 1" 1
  assert_contains "C1 ... the test path is judged by role" "$OUT" "VIOLATION (implementer): tests/run.sh [test]"
  assert_not_contains "C1 ... no mode restore note (the work tree shows no restore)" "$OUT" "note: tests/run.sh mode restore only"
  blk_check "C1 block" 3 $((T_PASS + T_FAIL - B0))
fi

echo "AC5 a committed code path with a newline (gone from index and work tree) fails closed on the BASE..HEAD list"
new_repo; BASE="$(git rev-parse HEAD)"
NLC="src/a
b.js"
nl_stores() { local lf; lf="$(mk_tmp)/lsout"; git ls-files --others -z > "$lf" 2>/dev/null || return 1; printf '%s\0' "$1" | cmp -s - "$lf"; }
if printf 'x\n' > "$NLC" 2>/dev/null && [ -f "$NLC" ] && nl_stores "$NLC"; then
  B0=$((T_PASS + T_FAIL))
  git add -A; git commit -qm "newline path"
  git rm -q --cached -- "$NLC"; rm -f -- "$NLC"
  gchk implementer --base "$BASE"
  assert_rc "AC5 a newline path only in BASE..HEAD: implementer exit 1 (fail closed)" 1
  assert_contains "AC5 ... the mode check reports it is incomplete" "$OUT" "VIOLATION (mode): a path contains a newline or a \\002 byte; the mode check is incomplete"
  blk_check "AC5 newline BASE..HEAD block" 2 $((T_PASS + T_FAIL - B0))
else rm -f -- "$NLC" 2>/dev/null; t_skip 2 "AC5 newline path in BASE..HEAD (this file system cannot store a newline in a name, or git does not list it back unchanged)"; fi

t_summary
