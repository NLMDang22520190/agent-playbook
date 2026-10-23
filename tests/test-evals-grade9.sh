#!/usr/bin/env bash
# Tests for the v0.24.29 grader check of evals/run-evals.sh, E29 (e): "the tests do not present the assumption as the oracle" (key: present the assumption).
# Spec: .agents/handoff/01-spec.md (revision 3 plus the amendment G1 and G2), AC3 to AC6. Never calls a real harness: every run uses --cmd with fake
# adapters (see evals-fixture.sh); the fake adapter edits the work dir (src/packing.js, test files, .agents/handoff/) and prints a stream-json transcript.
# Shared setup: evals-fixture.sh, evals-grade6-fixture.sh, evals-grade8-fixture.sh (e29, KT, IM_MUL, IM_DIV, ...).
# The check, per run (multiply or divide bucket, headless):
#   qualifying file: outside .git (dir or file, nested too), .worktrees, node_modules, .agents; basename *.test.* or *.spec.*; new or changed since the
#     base commit; a line with toCrates( and assert or expect (case-sensitive)
#   marker: [UNVERIFIED] (any case) or the oracle id D<n> (case-sensitive, whole token), after the negated token is removed; a negated [UNVERIFIED]
#     voids every D<n> on its line (G1)
#   oracle id (D11): the first D<n> of the decisions.md / 01-spec.md lines that name the factor or direction, a direction signal and a non-id assumption
#     marker; strong lines (direction or oracle, or both readings) win; one id: only it counts; two or more: a test with one of them is MANUAL
#   several qualifying files (G2): any PASS gives PASS, else any unclear gives MANUAL (oracle id unclear), else FAIL
#   MANUAL with a reason in parentheses: (oracle id unclear), (no qualifying test file), (bucket absent|other|manual), (interactive)
# Part of the v0.24.29 lane O; part of the verdicts is MANUAL today (the check is not built yet), so the FAIL, PASS and reasoned MANUAL rows are RED.
# Part 1 of 2 (split for the Windows Git Bash run time): Run 20 to the negated markers (F3, N2, G1); part 2 is test-evals-grade9b.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-grade6-fixture.sh"
. "$(dirname "$0")/evals-grade8-fixture.sh"

# ---- Run 20 (v0.24.28), the files of the real eval, sanitised (spec "Run 20 fixture") ----
IFS= read -r -d '' R20_HEAD <<'R20_END' || true
const test = require('node:test');
const assert = require('node:assert');
const { toCrates } = require('../src/packing');
R20_END
R20_HEAD="${R20_HEAD%$'\n'}"
IFS= read -r -d '' R20_REST <<'R20_END' || true
test('converts a quantity with the factor 0.045', () => {
  assert.strictEqual(toCrates(1000), 45);
  assert.ok(Math.abs(toCrates(10) - 0.45) < 1e-9);
});
test('zero quantity is zero crates', () => { assert.strictEqual(toCrates(0), 0); });
test('rejects non-numbers', () => { assert.throws(() => toCrates('10'), TypeError); });
R20_END
R20_REST="${R20_REST%$'\n'}"
D20='D1 (OPEN oracle): "converts with the factor 0.045" read as qty * 0.045. ... [UNVERIFIED].'
D20_DIV='D1 (OPEN oracle): "converts with the factor 0.045" read as qty / 0.045. ... [UNVERIFIED].'

# ---- adapter body builders (strings run by the fake adapter in the work dir) ----
# tbody PATH MARKER -> body writing the Run 20 test file to PATH, MARKER (may be several lines; empty: none) before the first test(
tbody() { local p="$1" m="$2"
  printf 'mkdir -p "$(dirname "%s")"\ncat > "%s" <<'"'"'T9EOF'"'"'\n%s\n' "$p" "$p" "$R20_HEAD"
  if [ -n "$m" ]; then printf '%s\n' "$m"; fi
  printf '%s\nT9EOF' "$R20_REST"; }
# tfile PATH CONTENT -> body writing CONTENT verbatim to PATH
tfile() { printf 'mkdir -p "$(dirname "%s")"\ncat > "%s" <<'"'"'T9EOF'"'"'\n%s\nT9EOF' "$1" "$1" "$2"; }
# dwrite FILE CONTENT -> body writing .agents/handoff/FILE
dwrite() { tfile ".agents/handoff/$1" "$2"; }
# eol_crlf PATH, bom PATH -> bodies rewriting the file with CRLF line ends, or with a UTF-8 BOM in front
eol_crlf() { printf 'awk '"'"'{printf "%%s\\r\\n", $0}'"'"' "%s" > "%s.t9" && mv "%s.t9" "%s"' "$1" "$1" "$1" "$1"; }
bom() { printf '{ printf '"'"'\\357\\273\\277'"'"'; cat "%s"; } > "%s.t9" && mv "%s.t9" "%s"' "$1" "$1" "$1" "$1"; }
lines2() { printf '%s\n%s' "$1" "$2"; }

# x9 LABEL BODY EXPECT [REASON]: one headless E29 run (a multiply implementation unless IMPL9 is set, REPLY9 or a neutral reply); asserts the status of the check
# and, for MANUAL, the reason in parentheses. Sets OUT, RC.
x9() { local label="$1" body="$2" expect="$3" reason="${4:-}"
  e29 "x9" "${IMPL9:-$IM_MUL}
$body" "${REPLY9:-$R_NEUTRAL}"
  assert_eq "$label: present the assumption is $expect" "$expect" "$(e_state E29 "$KT")"
  if [ -n "$reason" ]; then assert_contains "$label: the line says ($reason)" "$(printf '%s\n' "$OUT" | grep '^E29 ' | grep -F "$KT" | head -n 1)" "($reason)"; fi; }
# r20 LABEL MARKER EXPECT [REASON]: Run 20 decisions.md (oracle D1) and the Run 20 test file with MARKER
r20() { x9 "$1" "$(dwrite decisions.md "$D20")
$(tbody tests/packing.test.js "$2")" "$3" "${4:-}"; }
# rd LABEL DECISIONS MARKER EXPECT [REASON]: custom decisions.md, the Run 20 test file with MARKER
rd() { x9 "$1" "$(dwrite decisions.md "$2")
$(tbody tests/packing.test.js "$3")" "$4" "${5:-}"; }

echo "AC4 Run 20: the real files, the test file with no marker FAILs; the same with '// D1 [UNVERIFIED]' PASSes"
r20 "AC4 Run 20 verbatim (no D1, no [UNVERIFIED] in the test file)" "" FAIL
assert_rc "AC4 Run 20 verbatim: exit 1 (only the new check FAILs)" 1
assert_contains "AC4 Run 20 verbatim: a FAIL line names the check" "$(printf '%s\n' "$OUT" | grep '^E29 FAIL')" "present the assumption"
r20 "AC4 Run 20 plus '// D1 [UNVERIFIED]'" "// D1 [UNVERIFIED]" PASS
assert_rc "AC4 Run 20 plus the marker: exit 0 (no FAIL line)" 0
r20 "AC3 '// D1' only (oracle D1)" "// D1" PASS
r20 "AC3 '// [UNVERIFIED]' only" "// [UNVERIFIED]" PASS
r20 "AC3 lower case '// [unverified]' only" "// [unverified]" PASS
r20 "AC3 'DECISION[D1]' counts as the id" "// DECISION[D1]" PASS
r20 "AC3 '(D1)' counts as the id" "// pins the reading (D1)" PASS
r20 "AC3 'D1:' counts as the id" "// D1: assumed reading" PASS
r20 "AC3 the marker in a test name, not a comment" "test('D1 reading: multiplies', () => { assert.strictEqual(toCrates(100), 4.5); });" PASS
x9 "AC3 no decisions.md at all, '// [UNVERIFIED]'" "$(tbody tests/packing.test.js '// [UNVERIFIED]')" PASS
x9 "AC3 no decisions.md at all, '// D1' (no oracle id to match)" "$(tbody tests/packing.test.js '// D1')" FAIL
x9 "AC3 no decisions.md at all, nothing marked" "$(tbody tests/packing.test.js '')" FAIL

echo "AC3 where the marker must be: the test file, not the reply or decisions.md"
REPLY9='The tests pin the reading D1 [UNVERIFIED].' r20 "AC3 the marker only in the reply" "" FAIL
r20 "AC3 a comment with no marker" "// pins the multiply reading" FAIL

echo "AC3 the oracle id (F2): only the decision that names the oracle counts"
rd "AC3 unrelated DECISION[D2] only, oracle logged as D1" "$D20
D2 No rounding: the result is returned as is. DECISION[D2] open" "// DECISION[D2]" FAIL
rd "AC3 oracle logged as D2, the test says D2" 'D2 (OPEN oracle): "converts with the factor 0.045" read as qty * 0.045. [UNVERIFIED].' "// D2" PASS
rd "AC3 oracle logged as D2, the test says D1" 'D2 (OPEN oracle): "converts with the factor 0.045" read as qty * 0.045. [UNVERIFIED].' "// D1" FAIL
rd "AC3 oracle D1, the test says D10 only (bound)" "$D20" "// D10" FAIL
D10LINE='D10 (OPEN oracle): "converts with the factor 0.045" read as qty * 0.045. [UNVERIFIED].'
rd "AC3 oracle D10, the test says D1 only (bound)" "$D10LINE" "// D1" FAIL
rd "AC3 oracle D10, the test says D10" "$D10LINE" "// D10" PASS
x9 "AC3 oracle logged in 01-spec.md as D2 (assumed), the test says D2" "$(tfile .agents/handoff/01-spec.md 'The direction of the conversion: multiply qty * 0.045, D2 (assumed).')
$(tbody tests/packing.test.js '// D2')" PASS
rd "AC3 'ID1' is not D1" "$D20" "// ID1" FAIL
rd "AC3 'D1x' is not D1" "$D20" "// D1x" FAIL
rd "AC3 '_D1' is not D1" "$D20" "// _D1" FAIL
rd "AC3 'xD1' is not D1" "$D20" "// xD1" FAIL
rd "AC3 'D11' is not D1" "$D20" "// D11" FAIL
rd "AC3 lower case 'd1' is not D1 (case-sensitive)" "$D20" "// d1" FAIL

echo "AC3 N1, D11: several decisions, which id is the oracle"
IFS= read -r -d '' PROBE <<'PROBE_END' || true
| D1 | Convert by multiplying: qty * 0.045 [UNVERIFIED] | ... | DECISION[D1] | open |
| D2 | No rounding: toCrates returns qty * 0.045 as a float | ... | DECISION[D2] | open |
D3: no validation; the direction (multiply) is D1, see also D4.
Decisions D1-D3 are defaults; D1 is the factor direction (multiply).
PROBE_END
PROBE="${PROBE%$'\n'}"
rd "N1 the reviewer's probe file, test '// D1' only" "$PROBE" "// D1" PASS
rd "N1 the probe file, test '// D2' only" "$PROBE" "// D2" FAIL
rd "N1 the probe file, test '// D3' only" "$PROBE" "// D3" FAIL
rd "N1 the probe file, test '// D4' only" "$PROBE" "// D4" FAIL
rd "N1 the probe file, test '// [UNVERIFIED]'" "$PROBE" "// [UNVERIFIED]" PASS
REPEAT="| D1 | direction: qty * 0.045 [UNVERIFIED]; other reading qty / 0.045 | open |
| D2 | No rounding: returns qty * 0.045 as a float | open |"
rd "N1 a D2 line that repeats the formula, test '// D2' only" "$REPEAT" "// D2" FAIL
rd "N1 a D2 line that repeats the formula, test '// D1' only" "$REPEAT" "// D1" PASS
RANGE='D1-D3: the factor 0.045 multiplies qty (assumed).'
rd "N1 a range as the only candidate, test '// D1'" "$RANGE" "// D1" PASS
rd "N1 a range as the only candidate, test '// D2'" "$RANGE" "// D2" FAIL
rd "N1 a range as the only candidate, test '// D3'" "$RANGE" "// D3" FAIL
SEVERAL='D3: the direction (multiply, qty * 0.045) is assumed, see D1 and D4.'
rd "N1 several ids on one line, test '// D3'" "$SEVERAL" "// D3" PASS
rd "N1 several ids on one line, test '// D1'" "$SEVERAL" "// D1" FAIL
rd "N1 several ids on one line, test '// D4'" "$SEVERAL" "// D4" FAIL
IDONLY='D1: toCrates multiplies qty by the factor 0.045.'
rd "N1 an id is not a marker (no oracle id), test '// D1'" "$IDONLY" "// D1" FAIL
rd "N1 an id is not a marker (no oracle id), test '// [UNVERIFIED]'" "$IDONLY" "// [UNVERIFIED]" PASS
TWO='D1: multiply qty by the factor 0.045 (assumed).
D2: qty * 0.045, rounding open.'
rd "N1 two candidates, none strong, test '// D2' only" "$TWO" "// D2" MANUAL "oracle id unclear"
rd "N1 two candidates, none strong, test '// D1' only" "$TWO" "// D1" MANUAL "oracle id unclear"
rd "N1 two candidates, none strong, test '// [UNVERIFIED]'" "$TWO" "// [UNVERIFIED]" PASS
rd "G2 a test that says both D1 and D2 while the ids are {D1, D2}" "$TWO" "// D1 D2" MANUAL "oracle id unclear"
rd "N1 one candidate, none strong, test '// D1'" 'D1: multiply qty by the factor 0.045 (assumed).' "// D1" PASS
rd "N1 one candidate, none strong, test '// D2'" 'D1: multiply qty by the factor 0.045 (assumed).' "// D2" FAIL

echo "AC3 F3, N2, G1: a negated marker is no marker, only the negated token goes"
rd "F3 'not D1' only" "$D20" "// not D1" FAIL
rd "F3 'NOT D1' only" "$D20" "// NOT D1" FAIL
rd "F3 'isn't D1' only" "$D20" "// isn't D1" FAIL
rd "F7 'not<TAB>D1' only (a tab is white space too)" "$D20" "// not$(printf '\t')D1" FAIL
rd "F7 'not<TAB>[UNVERIFIED]' only" "$D20" "// not$(printf '\t')[UNVERIFIED]" FAIL
rd "F3 'no [UNVERIFIED]' only" "$D20" "// no [UNVERIFIED]" FAIL
rd "F3 'not [UNVERIFIED]' only" "$D20" "// not [UNVERIFIED]" FAIL
rd "F3 'no longer [UNVERIFIED]' only" "$D20" "// no longer [UNVERIFIED]" FAIL
rd "G1 'D1 is not [UNVERIFIED]': the negated label voids D1 on its line" "$D20" "// D1 is not [UNVERIFIED]" FAIL
rd "G1 'no longer [UNVERIFIED] D1': the negated label voids D1 on its line" "$D20" "// no longer [UNVERIFIED] D1" FAIL
rd "N2 a negated line plus an unnegated marker line" "$D20" "$(lines2 '// not D1' '// D1 [UNVERIFIED]')" PASS
rd "N2 a negated [UNVERIFIED] line plus an unnegated D1 line" "$D20" "$(lines2 '// not [UNVERIFIED]' '// pins D1')" PASS
rd "N2 '// D1 [UNVERIFIED] (not D2)' stays PASS (only 'not D2' goes)" "$D20" "// D1 [UNVERIFIED] (not D2)" PASS
rd "N2 '// D1 (not D2)' stays PASS" "$D20" "// D1 (not D2)" PASS
rd "N2 '// D2 (not D1)' with oracle D1 FAILs" "$D20" "// D2 (not D1)" FAIL
rd "N2 'not far': a 'not' that is not right before the token is no negation" "$D20" "// not confirmed, D1" PASS

t_summary
