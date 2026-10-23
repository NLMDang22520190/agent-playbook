#!/usr/bin/env bash
# Tests for scripts/role-gate.sh task scopes (v0.24.29 lane C, slice S1): `check ROLE --base REF --scope FILE` (AC1-AC5, AC9, AC13 of
# .agents/handoff/01-spec.md; the exact strings E1-E8 and E14 are used verbatim) and the shared matcher of scripts/lib.sh
# (pb_scope_read, pb_scope_classify). A scope file names the paths a task owns (judged as without --scope) and the paths of
# another task (not judged, named); every other changed path is judged as today with a hint. Slice S2 (--baseline, a moving HEAD)
# and S3 (tdd-step, docs) are not here. Shared setup: role-gate-fixture.sh. Platform probes (exec bits, odd names) skip with exact counts.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/role-gate-fixture.sh"
unset PB_ALLOW_MODE_CHANGE
T="$(printf '\t')"

gate() { run env PLAYBOOK_HOME="$IH" bash "$GATE" "$@"; }
dig() { git hash-object -- "$1" 2>/dev/null || printf 'NODIGEST'; }
blk_check() { if [ "$2" != "$3" ]; then t_bad "$1: the declared skip count ($2) matches the assertions run ($3)" ""; fi; }
# stores_name NAME: 0 when the cwd (a fresh repo plus this one file) lists exactly NAME as its only untracked entry, byte for byte
stores_name() {
  local lf; lf="$(mk_tmp)/lsout"
  git ls-files --others -z > "$lf" 2>/dev/null || return 1
  printf '%s\0' "$1" | cmp -s - "$lf"
}
# new_repo: cd into a fresh repo (src/app.js, tests/app.test.js, README.md committed); sets R, BASE (the sha before the role), SF (a scope file outside the repo)
new_repo() { R="$(mk_tmp)"; mk_repo "$R"; cd "$R" || exit 3; BASE="$(git rev-parse HEAD)"; SF="$(mk_tmp)/scope"; }
# sf FILE KIND:PATH...: write a valid scope file (header, then one "kind TAB path" line per argument; the path is everything after the first colon)
sf() { local f="$1" e; shift; { printf '# role-gate scope v1\n'; for e in "$@"; do printf '%s\t%s\n' "${e%%:*}" "${e#*:}"; done; } > "$f"; }
# sc ROLE [ARGS]: check ROLE --base BASE --scope SF
sc() { local r="$1"; shift; gate check "$r" --base "$BASE" --scope "$SF" "$@"; }
# e1 N M K: the E1 summary for the current SF
e1() { printf 'note: scope %s (%s own, %s other entries, digest %s): %s path(s) outside the scope not checked' "$SF" "$1" "$2" "$(dig "$SF")" "$3"; }
e2() { printf "note: another task's path, not checked: %s [%s]" "$1" "$2"; }
e4() { printf 'note: %s is outside the task scope and not in the baseline; if another task changed it, add an "other" entry to the scope file' "$1"; }
# has_line NAME LINE: $OUT has exactly this line; no_line NAME LINE: it has not
has_line() { if printf '%s\n' "$OUT" | grep -Fx -- "$2" >/dev/null 2>&1; then t_ok "$1"; else t_bad "$1" "no line [$2] in: $OUT"; fi; }
no_line() { if printf '%s\n' "$OUT" | grep -Fx -- "$2" >/dev/null 2>&1; then t_bad "$1" "unexpected line [$2] in: $OUT"; else t_ok "$1"; fi; }
# lno LINE: the first line number of exactly this line in $OUT (0 when absent)
lno() { printf '%s\n' "$OUT" | WANT="$1" awk 'BEGIN { want = ENVIRON["WANT"] } $0 == want { print NR; found = 1; exit } END { if (!found) print 0 }'; }
# assert_next NAME LINE NEXT: the line after LINE in $OUT is exactly NEXT
assert_next() {
  local got
  got="$(printf '%s\n' "$OUT" | WA="$2" WB="$3" awk 'BEGIN { a = ENVIRON["WA"]; b = ENVIRON["WB"] } hit { print ($0 == b) ? "yes" : "no: " $0; done = 1; exit } $0 == a { hit = 1 } END { if (!done) print "no such line" }')"
  if [ "$got" = yes ]; then t_ok "$1"; else t_bad "$1" "after [$2] expected [$3]: $got; output: $OUT"; fi
}
# assert_before NAME EARLIER LATER: both lines exist, EARLIER comes first
assert_before() {
  local a b; a="$(lno "$2")"; b="$(lno "$3")"
  if [ "$a" -gt 0 ] && [ "$b" -gt 0 ] && [ "$a" -lt "$b" ]; then t_ok "$1"; else t_bad "$1" "[$2] at line $a, [$3] at line $b; output: $OUT"; fi
}
no_verdict() { # name: no OK and no FAILED line (the gate stopped before judging)
  case "$OUT" in *"OK: role gate"*|*"role gate FAILED"*) t_bad "$1" "a verdict was printed: $OUT" ;; *) t_ok "$1" ;; esac
}
count_lines() { printf '%s\n' "$OUT" | grep -c -- "$1" || true; }

# ================= AC1 own paths are judged as without --scope, E1 once before the per-path notes =================
echo "AC1 own entries (exact path and dir/ prefix) judged as today: code under an own prefix passes for the implementer, E1 printed once"
new_repo
sf "$SF" own:src/ own:tests/app.test.js
printf 'module.exports = 2;\n' > src/app.js; mkdir -p src/deep/er; printf 'n\n' > src/deep/er/new.js
sc implementer
assert_rc "AC1 own code paths only: implementer exit 0" 0
has_line "AC1 the OK line is unchanged (2 files checked)" "OK: role gate passed for implementer (2 file(s) checked, base=$BASE)"
has_line "AC1 E1: scope FILE (N own, M other entries, digest D): K path(s) outside the scope not checked" "$(e1 2 0 0)"
assert_eq "AC1 E1 is printed exactly once" "1" "$(count_lines '^note: scope ')"
assert_not_contains "AC1 no E2 and no E4 when every changed path is own" "$OUT" "outside the task scope and not in the baseline"

echo "AC1 an own exact test path edited by the implementer is a VIOLATION in today's format; E1 comes before it"
new_repo
sf "$SF" own:src/ own:tests/app.test.js
printf 'test("y", () => {});\n' > tests/app.test.js
sc implementer
assert_rc "AC1 own test path edited: implementer exit 1" 1
has_line "AC1 the VIOLATION line is today's format" "VIOLATION (implementer): tests/app.test.js [test]"
has_line "AC1 the FAILED line is today's format" "role gate FAILED for implementer: 1 violation(s), base=$BASE"
no_line "AC1 an own path gets no E4" "$(e4 tests/app.test.js)"
assert_before "AC1 E1 comes before the per-path VIOLATION line" "$(e1 2 0 0)" "VIOLATION (implementer): tests/app.test.js [test]"

echo "AC5 with --scope where every changed path is own: the verdict, exit code and VIOLATION lines equal the run without --scope (only E1 is added)"
for role in tester implementer reviewer infra; do
  new_repo
  mkdir -p ci; printf 'ci\n' > ci/build.sh
  sf "$SF" own:src/ own:tests/ own:ci/ own:README.md
  printf 'module.exports = 2;\n' > src/app.js; printf 'test("y", () => {});\n' > tests/app.test.js; printf '# changed\n' > README.md
  gate check "$role" --base "$BASE"; PLAIN="$RC|$OUT"
  sc "$role"; SCOPED="$RC|$(printf '%s\n' "$OUT" | grep -v '^note: scope ')"
  assert_eq "AC5 $role: same exit code and bytes as the run without --scope, minus E1" "$PLAIN" "$SCOPED"
  has_line "AC5 $role: E1 is the only addition" "$(e1 4 0 0)"
done

echo "AC1 matching is exact: a dir/ prefix is not a name prefix, an exact entry is not a prefix, case counts (all rule 4: judged, with E4)"
new_repo
mkdir -p src2; printf 'a\n' > src2/x.js; printf 'b\n' > src/app.js.bak; printf 'module.exports = 2;\n' > src/app.js
sf "$SF" own:src/app own:SRC/ own:src/app.js.baK own:docs/
sc tester
assert_rc "AC1 no entry matches: the tester is judged on every changed code path: exit 1" 1
for p in src2/x.js src/app.js.bak src/app.js; do
  has_line "AC1 [$p] is judged (VIOLATION for the tester)" "VIOLATION (tester): $p [code]"
  has_line "AC1 [$p] gets E4" "$(e4 "$p")"
done

echo "AC9 entries that never match (glob, //, backslash, no globs): the path stays rule 4 (judged, E4), the file is still accepted"
new_repo
printf 'module.exports = 2;\n' > src/app.js
sf "$SF" 'own:src/*.js' 'own:src//app.js' 'own:src\app.js' own:docs/
sc tester
assert_rc "AC9 a never-matching own entry: the path is judged: tester exit 1 (not exit 3: the file is valid)" 1
has_line "AC9 src/app.js is judged" "VIOLATION (tester): src/app.js [code]"
has_line "AC9 src/app.js gets E4" "$(e4 src/app.js)"
sf "$SF" own:docs/ 'other:src/*.js' 'other:src//app.js' 'other:src\app.js'
sc reviewer
assert_rc "AC9 a never-matching other entry exempts nothing: reviewer exit 1" 1
has_line "AC9 ... src/app.js is judged" "VIOLATION (reviewer): src/app.js [code]"

# ================= AC3 other paths are not judged, named with E2 =================
echo "AC3 an other path (exact, dir/ prefix; work tree, untracked, staged) is not judged; E2 names it; K counts it; own is still judged"
new_repo
mkdir -p tests/foreign; printf 'f\n' > tests/foreign/a.test.js; printf 'o\n' > tests/other.test.js
printf 'module.exports = 2;\n' > src/app.js
printf 's\n' > tests/foreign/staged.test.js; git add tests/foreign/staged.test.js
sf "$SF" own:src/ other:tests/foreign/ other:tests/other.test.js
sc implementer
assert_rc "AC3 other test paths with only own code changed: implementer exit 0" 0
has_line "AC3 E2 for the other prefix (untracked)" "$(e2 tests/foreign/a.test.js test)"
has_line "AC3 E2 for the other prefix (staged)" "$(e2 tests/foreign/staged.test.js test)"
has_line "AC3 E2 for the other exact path" "$(e2 tests/other.test.js test)"
has_line "AC3 E1 counts the other paths (K = 3)" "$(e1 1 2 3)"
has_line "AC3 only the own path is counted as checked" "OK: role gate passed for implementer (1 file(s) checked, base=$BASE)"
assert_eq "AC3 E1 once" "1" "$(count_lines '^note: scope ')"
assert_before "AC3 E1 comes before the E2 notes" "$(e1 1 2 3)" "$(e2 tests/other.test.js test)"
new_repo
printf 'test("z", () => {});\n' > tests/app.test.js
sf "$SF" own:src/ other:tests/app.test.js
sc implementer
assert_rc "AC3 a modified tracked other path (work tree) is exempt too: exit 0" 0
has_line "AC3 ... named with E2" "$(e2 tests/app.test.js test)"

echo "AC3 every role leaves an other path alone, whatever its kind"
for role in tester implementer reviewer infra; do
  new_repo
  mkdir -p ci; printf 'o\n' > src/other.js; printf 'o\n' > tests/other.test.js; printf 'o\n' > ci/other.sh
  sf "$SF" own:docs/ other:src/other.js other:tests/other.test.js other:ci/other.sh
  sc "$role"
  assert_rc "AC3 $role: only other paths changed: exit 0" 0
  has_line "AC3 $role: the code path is named with E2" "$(e2 src/other.js code)"
  has_line "AC3 $role: the test path is named with E2" "$(e2 tests/other.test.js test)"
  has_line "AC3 $role: the infra path is named with E2" "$(e2 ci/other.sh infra)"
  has_line "AC3 $role: 0 files checked" "OK: role gate passed for $role (0 file(s) checked, base=$BASE)"
done

echo "AC3 an other entry that overlaps an own path does not exempt it (own wins), in both directions"
new_repo
printf 'module.exports = 2;\n' > src/app.js; printf 'o\n' > src/other.js
sf "$SF" own:src/app.js other:src/
sc reviewer
assert_rc "AC3 own exact + other prefix: the own path is judged: reviewer exit 1" 1
has_line "AC3 ... src/app.js is a VIOLATION" "VIOLATION (reviewer): src/app.js [code]"
no_line "AC3 ... and it is not named as another task's path" "$(e2 src/app.js code)"
has_line "AC3 ... a sibling under the other prefix is exempt" "$(e2 src/other.js code)"
has_line "AC3 ... FAILED counts one violation" "role gate FAILED for reviewer: 1 violation(s), base=$BASE"
sf "$SF" own:src/ other:src/app.js
sc reviewer
assert_rc "AC3 own prefix + other exact on the same path: judged: exit 1" 1
has_line "AC3 ... src/app.js is a VIOLATION" "VIOLATION (reviewer): src/app.js [code]"
no_line "AC3 ... not named as another task's path" "$(e2 src/app.js code)"
sf "$SF" own:src/app.js other:src/app.js
sc reviewer
assert_rc "AC2 own x + other x is accepted (own wins): the path is judged: exit 1, not 3" 1
has_line "AC2 ... src/app.js is a VIOLATION" "VIOLATION (reviewer): src/app.js [code]"

# ================= AC4 unknown paths are judged as today, with E4 =================
echo "AC4 a rule-4 path (not own, not other): a forbidden kind is a VIOLATION followed by E4, an allowed kind passes with E4"
new_repo
mkdir -p lib; printf 's\n' > tests/stray.test.js; printf 'ok\n' > lib/ok.js
sf "$SF" own:src/ other:docs/
sc implementer
assert_rc "AC4 an unknown test path for the implementer: exit 1" 1
has_line "AC4 the VIOLATION line is today's format" "VIOLATION (implementer): tests/stray.test.js [test]"
assert_next "AC4 E4 comes right after the VIOLATION line" "VIOLATION (implementer): tests/stray.test.js [test]" "$(e4 tests/stray.test.js)"
has_line "AC4 an allowed-kind unknown path is named with E4 too" "$(e4 lib/ok.js)"
no_line "AC4 the allowed-kind path is no violation" "VIOLATION (implementer): lib/ok.js [code]"
assert_eq "AC4 exactly two E4 lines (one per rule-4 path)" "2" "$(count_lines 'is outside the task scope and not in the baseline')"
has_line "AC4 only the forbidden-kind path is a violation: FAILED counts one" "role gate FAILED for implementer: 1 violation(s), base=$BASE"
assert_before "AC4 E1 comes before the rule-4 notes" "$(e1 1 1 0)" "$(e4 lib/ok.js)"
rm -f tests/stray.test.js
sc implementer
assert_rc "AC4 only an allowed-kind unknown path: the implementer passes: exit 0" 0
has_line "AC4 ... it is counted in C (1 file checked)" "OK: role gate passed for implementer (1 file(s) checked, base=$BASE)"
has_line "AC4 ... and E4 is printed even though it passed" "$(e4 lib/ok.js)"
sc reviewer
assert_rc "AC4 the reviewer is judged on the unknown path as today: exit 1" 1
has_line "AC4 ... VIOLATION (reviewer)" "VIOLATION (reviewer): lib/ok.js [code]"
assert_next "AC4 ... E4 right after it" "VIOLATION (reviewer): lib/ok.js [code]" "$(e4 lib/ok.js)"

# ================= AC2 bad scope files, usage errors, the order of the checks =================
echo "AC2 a scope file with an E8 problem exits 3 with the exact message and no verdict (clean tree: the file is validated anyway)"
new_repo
# bad NAME PRINTF-FORMAT REASON: write the file with printf, run the gate, expect exit 3 and error: malformed scope file FILE: REASON
bad() {
  # shellcheck disable=SC2059
  printf "$2" > "$SF"
  sc implementer
  assert_rc "AC2 $1: exit 3" 3
  has_line "AC2 $1: the message is exact" "error: malformed scope file $SF: $3"
  no_verdict "AC2 $1: no verdict is printed"
}
bad "wrong header"            '# role-gate scope v2\nown\tsrc/\n'                          'line 1 is not the header: # role-gate scope v1'
bad "header with a trailing space" '# role-gate scope v1 \nown\tsrc/\n'                  'line 1 is not the header: # role-gate scope v1'
bad "a line 1 that is an entry" 'own\tsrc/\n'                                            'line 1 is not the header: # role-gate scope v1'
bad "empty file"              ''                                                          'empty file, no header'
bad "UTF-8 BOM"               '\xef\xbb\xbf# role-gate scope v1\nown\tsrc/\n'            'line 1: starts with a UTF-8 BOM (save the file as UTF-8 without BOM)'
bad "BOM and CRLF: the BOM first" '\xef\xbb\xbf# role-gate scope v1\r\nown\tsrc/\r\n'  'line 1: starts with a UTF-8 BOM (save the file as UTF-8 without BOM)'
bad "whole-file CRLF"         '# role-gate scope v1\r\nown\tsrc/\r\n'                    'line 1: CR in the line (CRLF line ends? save the file with LF)'
bad "no TAB (spaces)"         '# role-gate scope v1\nown src/\n'                          'line 2: no TAB'
bad "a blank line is no TAB"  '# role-gate scope v1\nown\tsrc/\n\nown\ttests/\n'         'line 3: no TAB'
bad "unknown kind"            '# role-gate scope v1\nmine\tsrc/\n'                        'line 2: unknown kind (want own or other)'
bad "kind is case-sensitive"  '# role-gate scope v1\nOwn\tsrc/\n'                         'line 2: unknown kind (want own or other)'
bad "empty path"              '# role-gate scope v1\nown\t\n'                             'line 2: empty path'
bad "absolute path"           '# role-gate scope v1\nown\t/etc/passwd\n'                  'line 2: absolute path'
for dp in '.' '..' './src/' 'src/../x' 'src/./x' 'src/..' '../x'; do
  bad "a . or .. segment [$dp]" "# role-gate scope v1\nown\tsrc/\nown\t$dp\n"             'line 3: a . or .. segment'
done
bad "CR in a later line"      '# role-gate scope v1\nown\tsrc/\nother\tdocs/\r\n'        'line 3: CR in the line (CRLF line ends? save the file with LF)'
bad "duplicate own entry"     '# role-gate scope v1\nown\tsrc/\nother\tdocs/\nown\tsrc/\n' 'line 4: duplicate entry (also line 2)'
bad "duplicate other entry"   '# role-gate scope v1\nown\tsrc/\nother\tdocs/\nother\tdocs/\n' 'line 4: duplicate entry (also line 3)'
bad "no own entry (other only)" '# role-gate scope v1\nother\tdocs/\n'                    'no own entry'
bad "no own entry (header only)" '# role-gate scope v1\n'                                  'no own entry'
echo "AC2 the reasons are checked in the listed order; the first bad line wins; no own entry comes last"
bad "unknown kind before empty path" '# role-gate scope v1\nmine\t\n'                      'line 2: unknown kind (want own or other)'
bad "no TAB before everything else" '# role-gate scope v1\nown /abs/../x\r\n'            'line 2: no TAB'
bad "empty path before absolute (no)" '# role-gate scope v1\nown\t\nown\t/x\n'            'line 2: empty path'
bad "absolute before a dot segment" '# role-gate scope v1\nown\t/a/../b\n'               'line 2: absolute path'
bad "a dot segment before CR"  '# role-gate scope v1\nown\t./x\r\n'                      'line 2: a . or .. segment'
bad "the first bad line wins (line 2 over line 3)" '# role-gate scope v1\nown src/\nmine\tx\n' 'line 2: no TAB'
bad "a bad line beats no own entry" '# role-gate scope v1\nother\tdocs/\nother x\n'      'line 3: no TAB'
bad "duplicate is found at the second line even after a good one" '# role-gate scope v1\nown\ta\nown\tb\nown\ta\n' 'line 4: duplicate entry (also line 2)'

echo "AC2 a missing or unreadable scope file (E6), a tracked scope file (E7), and E7 before E8"
new_repo
rm -f "$SF"
sc implementer
assert_rc "AC2 E6 a missing file: exit 3" 3
has_line "AC2 E6 the message is exact" "error: scope file not readable: $SF"
no_verdict "AC2 E6 no verdict"
sf "$SF" own:src/; chmod 000 "$SF" 2>/dev/null
if [ "$(id -u)" != 0 ] && ! cat "$SF" >/dev/null 2>&1; then
  sc implementer
  assert_rc "AC2 E6 an unreadable file (chmod 000): exit 3" 3
  has_line "AC2 E6 the message is exact" "error: scope file not readable: $SF"
else t_skip 2 "AC2 E6 unreadable file (running as root, or chmod 000 has no effect here)"; fi
chmod 644 "$SF" 2>/dev/null
TF="$R/pb-scope.txt"
sf "$TF" own:src/; git add pb-scope.txt; git commit -q -m "scope"
BASE="$(git rev-parse HEAD~1)"; SF="$TF"
sc implementer
assert_rc "AC2 E7 a tracked scope file: exit 3" 3
has_line "AC2 E7 the message is exact" "error: the scope file is a tracked file of this repository: $SF"
no_verdict "AC2 E7 no verdict"
printf '# role-gate scope v1\nmine\tsrc/\n' > "$TF"; git add pb-scope.txt; git commit -q -m "scope bad"
sc implementer
assert_rc "AC2 E7 before E8: a tracked and malformed file reports the tracked file: exit 3" 3
has_line "AC2 E7 ... not the malformed reason" "error: the scope file is a tracked file of this repository: $SF"
assert_not_contains "AC2 E7 ... and no malformed message" "$OUT" "malformed scope file"

echo "AC2 usage errors exit 2 (E5, E14) before any git or scope work"
new_repo
sf "$SF" own:src/
gate check implementer --base "$BASE" --scope
assert_rc "AC2 E5 --scope without a value: exit 2" 2
has_line "AC2 E5 the message is exact" "error: --scope needs a file"
gate check implementer --base "$BASE" --scope ""
assert_rc "AC2 E5 --scope with an empty value: exit 2" 2
has_line "AC2 E5 the message is exact" "error: --scope needs a file"
gate check implementer --base "$BASE" --scope "$SF" --scope "$SF"
assert_rc "AC2 E5 --scope given twice: exit 2" 2
has_line "AC2 E5 the message is exact" "error: --scope given twice"
no_verdict "AC2 E5 no verdict"
gate check implementer --scope "$SF"
assert_rc "AC2 E14 --scope without --base: exit 2" 2
has_line "AC2 E14 the message is exact" "error: --scope needs --base REF (the sha recorded before the role)"
no_verdict "AC2 E14 no verdict"
gate check implementer --scope "$SF" --scope "$SF"
assert_rc "AC2 E5 comes before E14: twice without --base: exit 2" 2
has_line "AC2 E5 ... is the one reported" "error: --scope given twice"
rm -f "$SF"
gate check implementer --scope "$SF"
assert_rc "AC2 E14 comes before the scope file checks: a missing file without --base: exit 2, not 3" 2
has_line "AC2 E14 ... is the one reported" "error: --scope needs --base REF (the sha recorded before the role)"
NG="$(mk_tmp)"; sf "$SF" own:src/
run_in "$NG" env PLAYBOOK_HOME="$IH" bash "$GATE" check implementer --scope "$SF"
assert_rc "AC2 E14 comes before the git work tree check: outside a repository: exit 2, not 3" 2
has_line "AC2 E14 ... is the one reported" "error: --scope needs --base REF (the sha recorded before the role)"
gate check implementer --base no-such-ref --scope "$SF.missing"
assert_rc "AC2 the base ref check comes before the scope file checks: exit 3" 3
has_line "AC2 ... base ref not found is reported" "error: base ref not found: no-such-ref"
gate size --scope "$SF"
assert_rc "AC2 regression: size --scope stays an unknown option: exit 2" 2
assert_contains "AC2 regression: size --scope is today's unknown option message" "$OUT" "error: unknown option: --scope"

echo "AC2 a relative scope file is resolved against the caller's directory (as --baseline), changed paths stay top-relative"
new_repo
printf 'module.exports = 2;\n' > src/app.js
RS="$R/.git/pb-scope-rel"; sf "$RS" own:src/
cd "$R/src" || exit 3
gate check implementer --base "$BASE" --scope ../.git/pb-scope-rel
assert_rc "AC2 a relative FILE from a subdirectory: exit 0" 0
assert_contains "AC2 ... E1 carries the file digest and the entry counts" "$OUT" "(1 own, 0 other entries, digest $(dig "$RS")): 0 path(s) outside the scope not checked"
has_line "AC2 ... the changed path was judged" "OK: role gate passed for implementer (1 file(s) checked, base=$BASE)"
cd "$R" || exit 3

# ================= AC9 odd path names =================
echo "AC9 paths with a space, a double quote, a leading dash or a TAB match byte for byte (own: judged, no E4; other: E2)"
odd_case() { # name path
  local name="$1" P="$2" kind
  new_repo
  if mkdir -p -- "$(dirname -- "$P")" 2>/dev/null && printf 'x\n' > "$P" 2>/dev/null && [ -f "$P" ] && stores_name "$P"; then
    kind="$(env PLAYBOOK_HOME="$IH" bash "$GATE" classify "$P")"
    sf "$SF" "own:$P"
    sc reviewer
    assert_rc "AC9 $name as own: the reviewer is judged on it: exit 1" 1
    has_line "AC9 $name as own: the VIOLATION line names the real path" "VIOLATION (reviewer): $P [$kind]"
    no_line "AC9 $name as own: no E4 (it matched byte for byte)" "$(e4 "$P")"
    sf "$SF" own:docs/ "other:$P"
    sc reviewer
    assert_rc "AC9 $name as other: not judged: exit 0" 0
    has_line "AC9 $name as other: E2 names it" "$(e2 "$P" "$kind")"
  else t_skip 5 "AC9 $name (this file system or git cannot store the name unchanged)"; fi
}
odd_case "a space"        'src/a b.js'
odd_case "a double quote" 'src/we"ird.js'
odd_case "a leading dash" '-lead.js'
odd_case "a TAB"          "$(printf 'src/ta\tb.js')"
echo "AC9 a dir/ prefix with a space matches the files under it; a TAB inside an entry is part of the path"
new_repo
mkdir -p "src/my dir"; printf 'x\n' > "src/my dir/f.js"
sf "$SF" "own:src/my dir/"
sc reviewer
assert_rc "AC9 own prefix with a space: judged: exit 1" 1
has_line "AC9 ... VIOLATION" "VIOLATION (reviewer): src/my dir/f.js [code]"
no_line "AC9 ... no E4" "$(e4 'src/my dir/f.js')"

# ================= AC13 the mode check exempts nothing with --scope =================
echo "AC13 a plain exec-bit drop on an other path is reported (today's string), PB_ALLOW_MODE_CHANGE is the escape; an own drop is reported too"
R="$(mk_tmp)"; mk_mode_repo "$R"; cd "$R" || exit 3; BASE="$(git rev-parse HEAD)"; SF="$(mk_tmp)/scope"
git update-index --chmod=-x -- ci/run.sh
if git diff --cached --raw --no-renames HEAD | grep -q '^:100755 100644'; then
  B0=$((T_PASS + T_FAIL))
  sf "$SF" own:src/ other:ci/
  sc implementer
  assert_rc "AC13 a drop on an other path: exit 1" 1
  has_line "AC13 ... today's mode string names it" "VIOLATION (mode): ci/run.sh lost its executable bit (100755 -> 100644)"
  has_line "AC13 ... the path itself is still exempt (E2)" "$(e2 ci/run.sh infra)"
  has_line "AC13 ... exactly one violation" "role gate FAILED for implementer: 1 violation(s), base=$BASE"
  run env PLAYBOOK_HOME="$IH" PB_ALLOW_MODE_CHANGE=ci/run.sh bash "$GATE" check implementer --base "$BASE" --scope "$SF"
  assert_rc "AC13 the same drop with the path in PB_ALLOW_MODE_CHANGE: exit 0" 0
  assert_not_contains "AC13 ... not reported" "$OUT" "VIOLATION (mode)"
  git update-index --chmod=+x -- ci/run.sh; git update-index --chmod=-x -- src/run.sh
  sc implementer
  assert_rc "AC13 a drop on an own path is reported as without --scope: exit 1" 1
  has_line "AC13 ... today's mode string" "VIOLATION (mode): src/run.sh lost its executable bit (100755 -> 100644)"
  git update-index --chmod=+x -- src/run.sh
  blk_check "AC13 plain drop block" 8 $((T_PASS + T_FAIL - B0))
else t_skip 8 "AC13 plain drop (git does not show a staged mode drop here)"; fi

echo "AC13 a rename that drops the bit, from an own path into an other prefix, is reported by the new path"
R="$(mk_tmp)"; mk_mode_repo "$R"; cd "$R" || exit 3; BASE="$(git rev-parse HEAD)"; SF="$(mk_tmp)/scope"
git mv src/run.sh ci/moved.sh; git update-index --chmod=-x -- ci/moved.sh
if git diff --cached --raw --no-renames HEAD | grep -q '^:000000 100644'; then
  sf "$SF" own:src/ other:ci/
  sc implementer
  assert_rc "AC13 a rename drop into an other prefix: exit 1" 1
  has_line "AC13 ... the new path is named with today's string" "VIOLATION (mode): ci/moved.sh lost its executable bit (100755 -> 100644)"
  has_line "AC13 ... the only violation" "role gate FAILED for implementer: 1 violation(s), base=$BASE"
  run env PLAYBOOK_HOME="$IH" PB_ALLOW_MODE_CHANGE=ci/moved.sh bash "$GATE" check implementer --base "$BASE" --scope "$SF"
  assert_rc "AC13 ... with the new path in PB_ALLOW_MODE_CHANGE: exit 0" 0
else t_skip 4 "AC13 rename drop (git does not show the staged rename drop here)"; fi

echo "AC13 'cannot hash' on an other path is reported; the escape silences exactly that path"
R="$(mk_tmp)"; mk_mode_repo "$R"; cd "$R" || exit 3; BASE="$(git rev-parse HEAD)"; SF="$(mk_tmp)/scope"
UNH_OK=0
if [ "$(id -u)" = 0 ]; then UNH_WHY="running as root (chmod 000 does not stop root)"
elif ! fm_true_ok; then UNH_WHY="this file system does not keep executable bits"
else
  git mv ci/run.sh ci/run2.sh; chmod 000 ci/run2.sh 2>/dev/null
  if cat ci/run2.sh >/dev/null 2>&1; then UNH_WHY="chmod 000 has no effect here"; else UNH_OK=1; fi
fi
if [ "$UNH_OK" = 1 ]; then
  sf "$SF" own:src/ other:ci/
  sc implementer
  assert_rc "AC13 an unhashable other path: the gate fails: exit 1" 1
  has_line "AC13 ... cannot hash PATH; the mode check is incomplete" "VIOLATION (mode): cannot hash ci/run2.sh; the mode check is incomplete"
  run env PLAYBOOK_HOME="$IH" PB_ALLOW_MODE_CHANGE=ci/run2.sh bash "$GATE" check implementer --base "$BASE" --scope "$SF"
  assert_not_contains "AC13 ... the escape silences it" "$OUT" "cannot hash"
  chmod 644 ci/run2.sh 2>/dev/null
else t_skip 3 "AC13 cannot hash on an other path ($UNH_WHY)"; fi

echo "AC13 a path with a newline stays a global mode violation with --scope"
new_repo
NLC="src/a
b.js"
if printf 'x\n' > "$NLC" 2>/dev/null && [ -f "$NLC" ] && stores_name "$NLC"; then
  B0=$((T_PASS + T_FAIL))
  git add -A; git commit -qm "newline path"
  git rm -q --cached -- "$NLC"; rm -f -- "$NLC"
  sf "$SF" own:src/ other:docs/
  sc implementer
  assert_rc "AC13 a newline path only in BASE..HEAD, with --scope: exit 1 (fail closed)" 1
  has_line "AC13 ... the mode check reports it is incomplete" "VIOLATION (mode): a path contains a newline or a \\002 byte; the mode check is incomplete"
  blk_check "AC13 newline block" 2 $((T_PASS + T_FAIL - B0))
else rm -f -- "$NLC" 2>/dev/null; t_skip 2 "AC13 newline path (this file system cannot store a newline in a name, or git does not list it back unchanged)"; fi

# ================= S2: --scope with --baseline (rule 3, E3) and a moving HEAD =================
# snap: take a snapshot of the cwd repo into a fresh MF; a snapshot that fails is a failure here, not in every later row
snap() { MF="$(mk_tmp)/m"; gate snapshot --out "$MF"; assert_rc "setup: snapshot exits 0" 0; }
# scb ROLE [ARGS]: check ROLE --base BASE --scope SF --baseline MF
scb() { local r="$1"; shift; sc "$r" --baseline "$MF" "$@"; }
# bln N K: the baseline note of the current MF (N recorded paths, K unchanged)
bln() { printf 'note: baseline %s (%s path(s), digest %s): %s path(s) unchanged, not checked' "$MF" "$1" "$(dig "$MF")" "$2"; }
e3() { printf 'note: outside the task scope, changed since the baseline, not checked: %s [%s]' "$1" "$2"; }
unch() { printf 'note: unchanged since the baseline: %s' "$1"; }
# other_commit PATH...: another task writes and commits the paths (HEAD moves after BASE)
other_commit() { local p; for p in "$@"; do mkdir -p -- "$(dirname -- "$p")"; printf 'other task\n' > "$p"; git add -- "$p"; done; git commit -q -m "other task"; }

echo "AC6 (a) P1: the other task edits its test after the snapshot; with the other entry the implementer passes and E2 names it (rule 2)"
new_repo
printf 'o\n' > src/other.js
snap
printf 'module.exports = 3;\n' > src/mine.js; printf 'test("o", () => {});\n' > tests/other.test.js
sf "$SF" own:src/mine.js other:tests/other.test.js
scb implementer
assert_rc "AC6a P1 with an other entry: implementer exit 0" 0
has_line "AC6a E2 names tests/other.test.js [test]" "$(e2 tests/other.test.js test)"
has_line "AC6a the baseline-recorded src/other.js, unchanged, keeps today's skip note" "$(unch src/other.js)"
has_line "AC6a E1: 1 own, 1 other entry, K = 1 (the unchanged recorded path is not in K)" "$(e1 1 1 1)"
has_line "AC6a the baseline note is today's" "$(bln 1 1)"
has_line "AC6a only src/mine.js was judged" "OK: role gate passed for implementer (1 file(s) checked, base=$BASE)"
assert_not_contains "AC6a no violation" "$OUT" "VIOLATION"
assert_not_contains "AC6a no E3 (rule 2 path, not recorded)" "$OUT" "changed since the baseline, not checked"
assert_before "AC6a the baseline note comes before E1" "$(bln 1 1)" "$(e1 1 1 1)"
assert_before "AC6a E1 comes before the E2 note" "$(e1 1 1 1)" "$(e2 tests/other.test.js test)"
echo "AC6 (a) control: without the other entry the same edit is rule 4: P1's VIOLATION plus E4"
sf "$SF" own:src/mine.js
scb implementer
assert_rc "AC6a control: no other entry: implementer exit 1" 1
has_line "AC6a control: P1's VIOLATION line" "VIOLATION (implementer): tests/other.test.js [test]"
assert_next "AC6a control: E4 right after it" "VIOLATION (implementer): tests/other.test.js [test]" "$(e4 tests/other.test.js)"

echo "AC6 (b) a path dirty at the snapshot and edited further by another task: rule 3, not judged, E3 names it; unchanged recorded paths keep today's skip note"
new_repo
printf 'v1\n' > src/rec.js; printf 'v1\n' > src/still.js
snap
printf 'v2\n' > src/rec.js
sf "$SF" own:docs/
scb reviewer
assert_rc "AC6b a recorded path edited further: the reviewer passes: exit 0" 0
has_line "AC6b E3 names src/rec.js [code]" "$(e3 src/rec.js code)"
has_line "AC6b the unchanged recorded path keeps today's skip note" "$(unch src/still.js)"
has_line "AC6b E1 counts only the changed recorded path (K = 1)" "$(e1 1 0 1)"
has_line "AC6b the baseline note is today's (2 recorded, 1 unchanged)" "$(bln 2 1)"
has_line "AC6b 0 files judged" "OK: role gate passed for reviewer (0 file(s) checked, base=$BASE)"
assert_not_contains "AC6b no E4 for a recorded path" "$OUT" "is outside the task scope and not in the baseline"
assert_not_contains "AC6b no violation" "$OUT" "VIOLATION"
assert_before "AC6b the baseline note comes before E1" "$(bln 2 1)" "$(e1 1 0 1)"
assert_before "AC6b E1 comes before E3" "$(e1 1 0 1)" "$(e3 src/rec.js code)"
echo "AC6 (b) every role leaves a recorded, changed, out-of-scope path alone (tester: a code path too)"
for role in tester implementer reviewer infra; do
  scb "$role"
  assert_rc "AC6b $role: only a recorded, changed path outside the scope: exit 0" 0
  has_line "AC6b $role: E3" "$(e3 src/rec.js code)"
done
echo "AC6 (b) control: without --baseline rule 3 never applies; the same edit is rule 4 (judged, E4)"
gate check reviewer --base "$BASE" --scope "$SF"
assert_rc "AC6b control: no --baseline: reviewer exit 1" 1
has_line "AC6b control: VIOLATION" "VIOLATION (reviewer): src/rec.js [code]"
has_line "AC6b control: E4" "$(e4 src/rec.js)"
echo "AC6 (b) rule 2 comes before rule 3: a path that is other and recorded is named with E2, not E3"
sf "$SF" own:docs/ other:src/rec.js
scb reviewer
assert_rc "AC6b other + recorded + changed: exit 0" 0
has_line "AC6b ... E2" "$(e2 src/rec.js code)"
assert_not_contains "AC6b ... no E3" "$OUT" "changed since the baseline, not checked"
has_line "AC6b ... K = 1" "$(e1 1 1 1)"

echo "AC6 (b) a recorded OWN path stays judged: edited further by the implementer it is today's VIOLATION, with no E3"
new_repo
printf 'test("t2", () => {});\n' > tests/app.test.js; printf 'v1\n' > src/rec.js
snap
printf 'test("t3", () => {});\n' > tests/app.test.js; printf 'v2\n' > src/rec.js
sf "$SF" own:tests/app.test.js own:src/mine.js
scb implementer
assert_rc "AC6b a recorded own test path edited further: implementer exit 1" 1
has_line "AC6b ... today's VIOLATION line" "VIOLATION (implementer): tests/app.test.js [test]"
no_line "AC6b ... not named as an out-of-scope path" "$(e3 tests/app.test.js test)"
no_line "AC6b ... and no E4" "$(e4 tests/app.test.js)"
has_line "AC6b ... the other recorded path is rule 3" "$(e3 src/rec.js code)"
has_line "AC6b ... one violation" "role gate FAILED for implementer: 1 violation(s), base=$BASE"
printf 'test("t2", () => {});\n' > tests/app.test.js
scb implementer
assert_rc "AC6b the own recorded path back to its snapshot state: skipped as today: exit 0" 0
has_line "AC6b ... today's skip note" "$(unch tests/app.test.js)"

echo "AC7 moving HEAD: another task's commit between BASE and HEAD, touching only other paths, is exempt (P3 test path, P4 code path)"
new_repo
other_commit tests/other.test.js
sf "$SF" own:src/mine.js other:tests/other.test.js
sc implementer
assert_rc "AC7 P3 with an other entry: implementer exit 0" 0
has_line "AC7 P3 ... E2" "$(e2 tests/other.test.js test)"
has_line "AC7 P3 ... --base is still the sha before the role" "OK: role gate passed for implementer (0 file(s) checked, base=$BASE)"
has_line "AC7 P3 ... E1 K = 1" "$(e1 1 1 1)"
gate check implementer --base "$BASE"
assert_rc "AC7 P3 regression: without --scope the commit is a violation: exit 1" 1
has_line "AC7 P3 regression: today's VIOLATION line" "VIOLATION (implementer): tests/other.test.js [test]"
new_repo
other_commit src/other.js
sf "$SF" own:docs/ other:src/other.js
sc reviewer
assert_rc "AC7 P4 with an other entry: reviewer exit 0" 0
has_line "AC7 P4 ... E2" "$(e2 src/other.js code)"
gate check reviewer --base "$BASE"
assert_rc "AC7 P4 regression: without --scope the commit is a violation: exit 1" 1
has_line "AC7 P4 regression: today's VIOLATION line" "VIOLATION (reviewer): src/other.js [code]"

echo "AC7 P9/P10: another task commits the recorded dirty files unchanged: rule 3 (E3) with --scope; today's two violations without it"
new_repo
printf 'r\n' > src/rec.js; printf 'r\n' > tests/rec.test.js
snap
git add -A; git commit -q -m "other task commits its recorded work"
sf "$SF" own:docs/
scb reviewer
assert_rc "AC7 P9 with --scope: the reviewer passes: exit 0" 0
has_line "AC7 P9 ... E3 for the code path" "$(e3 src/rec.js code)"
has_line "AC7 P9 ... E3 for the test path" "$(e3 tests/rec.test.js test)"
has_line "AC7 P9 ... K = 2" "$(e1 1 0 2)"
has_line "AC7 P9 ... 0 files judged, base is the sha before the role" "OK: role gate passed for reviewer (0 file(s) checked, base=$BASE)"
gate check reviewer --base "$BASE" --baseline "$MF"
assert_rc "AC7 P9 regression: without --scope: exit 1" 1
has_line "AC7 P9 regression: VIOLATION for the code path" "VIOLATION (reviewer): src/rec.js [code]"
has_line "AC7 P9 regression: VIOLATION for the test path" "VIOLATION (reviewer): tests/rec.test.js [test]"
has_line "AC7 P9 regression: 2 violations" "role gate FAILED for reviewer: 2 violation(s), base=$BASE"
gate check reviewer --baseline "$MF"
assert_rc "AC7 P10 regression: default base HEAD, without --scope: exit 1" 1
has_line "AC7 P10 regression: 2 violations" "role gate FAILED for reviewer: 2 violation(s), base=HEAD"

echo "AC7 a reviewer commit to an own path still fails, whatever another task committed in the same range (P11 stays closed with the fixed base)"
new_repo
other_commit src/other.js
printf 'module.exports = 9;\n' > src/mine.js; git add src/mine.js; git commit -q -m "reviewer commit"
sf "$SF" own:src/mine.js other:src/other.js
sc reviewer
assert_rc "AC7 a reviewer commit of an own path: exit 1" 1
has_line "AC7 ... today's VIOLATION line" "VIOLATION (reviewer): src/mine.js [code]"
has_line "AC7 ... the other task's path is exempt (E2)" "$(e2 src/other.js code)"
has_line "AC7 ... one violation, base is the sha before the role" "role gate FAILED for reviewer: 1 violation(s), base=$BASE"
echo "AC7 an other task's commit that touches an own path is judged; its other path in the same commit is exempt"
new_repo
other_commit tests/app.test.js src/other.js
sf "$SF" own:tests/app.test.js other:src/other.js
sc implementer
assert_rc "AC7 a commit touching an own test path: implementer exit 1" 1
has_line "AC7 ... own path judged (BASE..HEAD is never unchanged)" "VIOLATION (implementer): tests/app.test.js [test]"
has_line "AC7 ... the other path of the same commit is E2" "$(e2 src/other.js code)"
has_line "AC7 ... one violation" "role gate FAILED for implementer: 1 violation(s), base=$BASE"
echo "AC7 an unknown path in another task's commit is rule 4: a forbidden kind is a VIOLATION plus E4, an allowed kind passes with E4"
new_repo
other_commit tests/stray.test.js lib/ok.js
sf "$SF" own:src/mine.js other:docs/
sc implementer
assert_rc "AC7 unknown paths in BASE..HEAD: implementer exit 1" 1
has_line "AC7 ... the forbidden kind is a VIOLATION" "VIOLATION (implementer): tests/stray.test.js [test]"
assert_next "AC7 ... E4 right after it" "VIOLATION (implementer): tests/stray.test.js [test]" "$(e4 tests/stray.test.js)"
has_line "AC7 ... the allowed kind gets E4" "$(e4 lib/ok.js)"
no_line "AC7 ... and is no violation" "VIOLATION (implementer): lib/ok.js [code]"
has_line "AC7 ... one violation" "role gate FAILED for implementer: 1 violation(s), base=$BASE"

echo "AC8 the no-checkpoint-commit flow: tests left uncommitted, HEAD recorded, snapshot taken; own test edited -> VIOLATION; own code only -> pass"
new_repo
RED='test("red", () => {});\n'
printf "$RED" > tests/app.test.js; printf 'v1\n' > src/theirs.js
BASE="$(git rev-parse HEAD)"
snap
HEAD0="$(git rev-parse HEAD)"; SNAPSHOT_STATE="$(git status --porcelain)"
sf "$SF" own:src/mine.js own:tests/app.test.js other:docs/
printf 'test("changed by the implementer", () => {});\n' > tests/app.test.js
sc implementer --baseline "$MF"
assert_rc "AC8 the implementer edits the own test: exit 1" 1
has_line "AC8 ... today's VIOLATION line" "VIOLATION (implementer): tests/app.test.js [test]"
has_line "AC8 ... base is the sha recorded before the role" "role gate FAILED for implementer: 1 violation(s), base=$BASE"
assert_eq "AC8 no checkpoint commit was needed or made: HEAD is the recorded sha" "$BASE" "$(git rev-parse HEAD)"
assert_eq "AC8 nothing was reset or stashed by the gate (stash empty, the foreign file untouched)" "0|v1" "$(git stash list | wc -l | tr -d ' ')|$(cat src/theirs.js)"
printf "$RED" > tests/app.test.js
printf 'module.exports = 4;\n' > src/mine.js
mkdir -p docs; printf 'n\n' > docs/note.md; printf 'v2\n' > src/theirs.js
git add docs/note.md; git commit -q -m "other task commit" -- docs/note.md
sc implementer --baseline "$MF"
assert_rc "AC8 own test back at its snapshot state, own code edited, foreign work around: exit 0" 0
has_line "AC8 ... the own test is skipped as unchanged since the baseline" "$(unch tests/app.test.js)"
has_line "AC8 ... only the own code path was judged (HEAD moved by another task)" "OK: role gate passed for implementer (1 file(s) checked, base=$BASE)"
has_line "AC8 ... the other task's commit is E2" "$(e2 docs/note.md code)"
has_line "AC8 ... the foreign recorded path edited further is E3" "$(e3 src/theirs.js code)"
assert_not_contains "AC8 ... no violation" "$OUT" "VIOLATION"
echo "AC8 the role gate stays read-only for the reviewer in the same flow: own code edit fails it, a foreign edit does not"
new_repo
printf 'v1\n' > src/theirs.js
BASE="$(git rev-parse HEAD)"
snap
sf "$SF" own:src/mine.js other:docs/
printf 'v2\n' > src/theirs.js; mkdir -p docs; printf 'n\n' > docs/x.md
sc reviewer --baseline "$MF"
assert_rc "AC8 reviewer: only foreign and other changes: exit 0" 0
has_line "AC8 reviewer: E3 for the foreign recorded path" "$(e3 src/theirs.js code)"
has_line "AC8 reviewer: E2 for the other path" "$(e2 docs/x.md code)"
printf 'module.exports = 5;\n' > src/mine.js
sc reviewer --baseline "$MF"
assert_rc "AC8 reviewer: an own path written: exit 1" 1
has_line "AC8 reviewer: today's VIOLATION line" "VIOLATION (reviewer): src/mine.js [code]"

echo "AC13 recorded-path variant: an exec-bit drop on a recorded path outside the scope is reported (U6), the escape silences it, a drop already there at the snapshot is not reported"
R="$(mk_tmp)"; mk_mode_repo "$R"; cd "$R" || exit 3; BASE="$(git rev-parse HEAD)"; SF="$(mk_tmp)/scope"
printf 'echo b\n' >> ci/run.sh
snap
git update-index --chmod=-x -- ci/run.sh
if git diff --cached --raw --no-renames HEAD | grep -q '^:100755 100644'; then
  B0=$((T_PASS + T_FAIL))
  sf "$SF" own:src/
  scb implementer
  assert_rc "AC13 recorded path, outside the scope, bit dropped and changed since the snapshot: exit 1" 1
  has_line "AC13 ... today's mode string names it" "VIOLATION (mode): ci/run.sh lost its executable bit (100755 -> 100644)"
  has_line "AC13 ... the path itself is rule 3 (E3)" "$(e3 ci/run.sh infra)"
  has_line "AC13 ... exactly one violation" "role gate FAILED for implementer: 1 violation(s), base=$BASE"
  run env PLAYBOOK_HOME="$IH" PB_ALLOW_MODE_CHANGE=ci/run.sh bash "$GATE" check implementer --base "$BASE" --scope "$SF" --baseline "$MF"
  assert_rc "AC13 ... the path in PB_ALLOW_MODE_CHANGE: exit 0" 0
  assert_not_contains "AC13 ... not reported" "$OUT" "VIOLATION (mode)"
  snap
  scb implementer
  assert_rc "AC13 a drop already present at the snapshot and unchanged since: not reported (today's baseline semantics): exit 0" 0
  assert_not_contains "AC13 ... no mode violation" "$OUT" "VIOLATION (mode)"
  git update-index --chmod=+x -- ci/run.sh
  blk_check "AC13 recorded-path block" 9 $((T_PASS + T_FAIL - B0))
else t_skip 9 "AC13 recorded-path drop (git does not show a staged mode drop here)"; fi

# ================= the shared matcher of scripts/lib.sh =================
echo "D-1a pb_scope_read / pb_scope_classify: one output line per input line (an empty line gives none), own wins over other, byte-exact"
new_repo
sf "$SF" own:src/ own:tests/app.test.js other:src/other.js other:docs/ 'own:src/my dir/' own:-lead.js
CL="$(printf 'src/app.js\n\nREADME.md\nsrc/other.js\ndocs/a/b.md\ntests/app.test.js\ntests/app.test.js2\nsrc\nsrcx/y.js\nsrc/my dir/z\n-lead.js\nSRC/app.js\n' |
  ( env PLAYBOOK_HOME="$IH" bash -c '. "$1/scripts/lib.sh"; cd "$2" && pb_scope_read "$3" && pb_scope_classify' _ "$PB_ROOT" "$R" "$SF" ) 2>&1)"
assert_eq "D-1a classify: own, none (empty), none, own (own prefix beats the other exact entry), other, own, none, none, none, own, own, none" \
  "own|none|none|own|other|own|none|none|none|own|own|none" "$(printf '%s\n' "$CL" | tr '\n' '|' | sed 's/|$//')"
printf '# role-gate scope v1\nother\tdocs/\n' > "$SF"
RE="$(env PLAYBOOK_HOME="$IH" bash -c '. "$1/scripts/lib.sh"; cd "$2" && pb_scope_read "$3"; echo "rc=$?"' _ "$PB_ROOT" "$R" "$SF" 2>&1)"
assert_contains "D-1a pb_scope_read reports a bad file (no own entry) with the E8 message" "$RE" "malformed scope file $SF: no own entry"

# ================= C-fix (review round): prefix anchoring, a big scope file, a symlinked scope file =================
echo "C-fix F1 a dir/ prefix matches at the start only: a path that merely contains the prefix is none (own and other prefixes)"
new_repo
sf "$SF" own:app/ other:docs/ own:tests/app.test.js
CL="$(printf 'x/docs/a.md\nlib/app/z\ndocs/a.md\napp/z\nsrc/docs/x.js\nx/app/y\n' |
  ( env PLAYBOOK_HOME="$IH" bash -c '. "$1/scripts/lib.sh"; cd "$2" && pb_scope_read "$3" && pb_scope_classify' _ "$PB_ROOT" "$R" "$SF" ) 2>&1)"
assert_eq "C-fix F1 classify: none, none, other, own, none, none" "none|none|other|own|none|none" "$(printf '%s\n' "$CL" | tr '\n' '|' | sed 's/|$//')"
new_repo
sf "$SF" own:tests/app.test.js other:docs/
mkdir -p lib/docs; printf 'x\n' > lib/docs/x.js
sc implementer
assert_rc "C-fix F1 a path that contains an other prefix past the first byte is rule 4 (judged, passes for code): exit 0" 0
has_line "C-fix F1 ... named with E4" "$(e4 lib/docs/x.js)"
no_line "C-fix F1 ... and not exempted as another task's path" "$(e2 lib/docs/x.js code)"

echo "C-fix F2 a big scope file (3001 entries, over 300 KB) classifies correctly: the other path is exempt, the own path judged"
new_repo
PAD="$(printf 'p%.0s' $(seq 1 90))"
{ printf '# role-gate scope v1\n'; awk -v pad="$PAD" 'BEGIN { for (i = 1; i <= 3000; i++) printf "other\tgen/%s/d%05d/\n", pad, i }'
  printf 'own\tsrc/\nother\ttests/foreign/\n'; } > "$SF"
SZ="$(wc -c < "$SF" | tr -d ' ')"
if [ "$SZ" -gt 300000 ]; then t_ok "C-fix F2 the scope file is over 300 KB: $SZ"; else t_bad "C-fix F2 the scope file is over 300 KB" "$SZ bytes"; fi
mkdir -p tests/foreign; printf 't\n' > tests/foreign/a.test.js
printf 'module.exports = 3;\n' > src/app.js
sc implementer
assert_rc "C-fix F2 big scope file: the foreign test is not judged: exit 0" 0
has_line "C-fix F2 ... named as another task's path (E2)" "$(e2 tests/foreign/a.test.js test)"

echo "C-fix F2 a classification failure is exit 3 with a message, never a silent all-own verdict"
new_repo
sf "$SF" own:src/ other:tests/foreign/
mkdir -p tests/foreign; printf 't\n' > tests/foreign/a.test.js
run env PLAYBOOK_HOME="$IH" TMPDIR=/nonexistent/pb-none bash "$GATE" check implementer --base "$BASE" --scope "$SF"
assert_rc "C-fix F2 classify cannot run (no temp dir): exit 3" 3
has_line "C-fix F2 ... the message is exact" "error: cannot classify the changed paths"
no_verdict "C-fix F2 ... no verdict"

echo "C-fix F3 a scope file that is a symlink into a tracked file is E7 too"
new_repo
mkdir -p docs; sf docs/scope.txt own:src/; git add docs/scope.txt; git commit -q -m "tracked scope"
SF="$R/.git/pb-scope-link"; ln -s "$R/docs/scope.txt" "$SF" 2>/dev/null
if [ -L "$SF" ]; then
sc implementer
assert_rc "C-fix F3 E7 through a symlink: exit 3" 3
has_line "C-fix F3 E7 the message is exact" "error: the scope file is a tracked file of this repository: $SF"
no_verdict "C-fix F3 E7 no verdict"
else t_skip 3 "C-fix F3 E7 through a symlink (ln -s makes a copy here, no symlink: Git Bash on Windows)"; fi
new_repo
mkdir -p docs; sf docs/scope.txt own:src/; git add docs/scope.txt; git commit -q -m "tracked scope"
mkdir -p "$R/.git/hop"; ln -s "$R/docs/scope.txt" "$R/.git/hop/l2" 2>/dev/null; SF="$R/.git/pb-scope-link2"; ln -s "hop/l2" "$SF" 2>/dev/null
if [ -L "$SF" ] && [ -L "$R/.git/hop/l2" ]; then
sc implementer
assert_rc "C-fix F3 E7 through two links (a relative link first): exit 3" 3
has_line "C-fix F3 E7 ... the message is exact" "error: the scope file is a tracked file of this repository: $SF"
else t_skip 2 "C-fix F3 E7 through two links (ln -s makes a copy here, no symlink: Git Bash on Windows)"; fi
new_repo
sf "$R/.git/pb-real" own:src/; SF="$R/.git/pb-scope-ok"; ln -s "$R/.git/pb-real" "$SF"
sc implementer
assert_rc "C-fix F3 control: a symlink to an untracked file is accepted: exit 0" 0

t_summary
