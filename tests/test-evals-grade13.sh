#!/usr/bin/env bash
# Tests for the v0.26.0 grader grade_E32 of evals/run-evals.sh (lane N, slice S6; spec .agents/handoff/01-spec.md AC1, AC7, AC10, decisions D12, D14).
# E32: "Add tests for optionLabel in src/options.js." setup_E32 commits src/options.js (optionLabel(optionsJson, value): parses the JSON array, returns
# the label of the option whose value matches, undefined when none matches) and db/seed.json (options_json with value == label for every option, the
# obvious fixture), and sets E32_BASE. From a real bug (PrintUp PR #705): a seed with value == label hid a value-for-label mix-up.
# Never calls a real harness: every run uses --cmd with a fake adapter (evals-grade12-fixture.sh).
# Check keys (a fixed phrase each check text must contain; found with e_state):
#   KA32 "a test file names optionLabel"    (a) a *.test.* or *.spec.* file under the work dir, new or changed since E32_BASE (untracked included), with a
#                                               line naming optionLabel (PASS/FAIL)
#   KB32 "the qualifying tests pass"        (b) those tests pass on the agent's code (PASS/FAIL; node limit 10 s)
#   KC32 "value-for-label mutant"           (c) only when src/options.js is byte-identical to E32_BASE: in a mktemp -d copy (removed after), src/options.js
#                                               becomes the fixture with the single expression hit.label replaced by hit.value; the tests fail on the
#                                               mutant PASS, pass FAIL; MANUAL when the agent changed src/options.js, (a) or (b) did not pass, node is
#                                               missing or the run times out (D12)
# Not tested here [UNVERIFIED]: the 10 s timeout and the node-missing branch (both MANUAL); a hanging test would cost 10 s per run.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-grade6-fixture.sh"
. "$(dirname "$0")/evals-grade8-fixture.sh"
. "$(dirname "$0")/evals-grade12-fixture.sh"

KA32='a test file names optionLabel'; KB32='the qualifying tests pass'; KC32='value-for-label mutant'
P32='Add tests for optionLabel in src/options.js.'
HDR32="const test = require('node:test');
const assert = require('node:assert');"
# t32 NAME REQUIRE-PATH BODY-LINE...: $J/NAME is a node:test file that requires optionLabel from REQUIRE-PATH
t32() { local n="$1" p="$2"; shift 2; wf "$n" "$HDR32" "const { optionLabel } = require('$p');" "$@"; }
t32 t32good ../src/options "test('optionLabel returns the label of the matching value', () => {" \
  "  const json = JSON.stringify([{ value: 'r', label: 'Red' }, { value: 'g', label: 'Green' }]);" \
  "  assert.strictEqual(optionLabel(json, 'g'), 'Green');" '});'
t32 t32spec ./options "test('label for value', () => {" \
  "  assert.strictEqual(optionLabel('[{\"value\":\"sm\",\"label\":\"Small\"}]', 'sm'), 'Small');" '});'
t32 t32same ../src/options "test('optionLabel finds the option', () => {" \
  "  const json = JSON.stringify([{ value: 'Red', label: 'Red' }, { value: 'Green', label: 'Green' }]);" \
  "  assert.strictEqual(optionLabel(json, 'Green'), 'Green');" '});'
t32 t32miss ../src/options "test('optionLabel returns undefined when no option matches', () => {" \
  "  const json = JSON.stringify([{ value: 'r', label: 'Red' }]);" \
  "  assert.strictEqual(optionLabel(json, 'x'), undefined);" '});'
t32 t32bad ../src/options "test('optionLabel returns the value', () => {" \
  "  const json = JSON.stringify([{ value: 'r', label: 'Red' }]);" \
  "  assert.strictEqual(optionLabel(json, 'r'), 'r');" '});'
wf t32other "$HDR32" "test('one plus one', () => { assert.strictEqual(1 + 1, 2); });"
GOOD32="$(cpto t32good tests/options.test.js)"
R32='Added tests/options.test.js; it uses options whose value differs from the label.'
# row32 NAME BODY: a headless E32 run whose agent runs BODY in the work dir and reads src/options.js
row32() { xr E32 "$1" head "$2" "$INIT" "$(RD src/options.js)" "$(BS 'node --test tests/')" "$(rj "$R32")"; }

echo "AC1 AC7 AC10 E32 is auto-gradable; setup_E32 commits optionLabel and the value == label seed"
rm -f "$REC/E32.prompt"
W="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $A/idle.sh" --scenarios E32 --workroot "$W" --out "$W/results.md"
assert_not_contains "AC1 E32 is accepted (not a usage error)" "$OUT" "not auto-gradable"
case "$RC" in 0|1) t_ok "AC1 E32 with the idle adapter exits 0 or 1" ;; *) t_bad "AC1 E32 with the idle adapter exits 0 or 1" "exit $RC; output: $OUT" ;; esac
assert_eq "AC1 E32 is graded (a PASS, FAIL or MANUAL line)" "graded" "$([ "$(printf '%s\n' "$OUT" | grep -cE '^E32 (PASS|FAIL|MANUAL) ')" -gt 0 ] && echo graded || echo not-graded)"
FILES32="$(git -C "$W/E32" ls-files 2>/dev/null)"
assert_contains "AC7 setup_E32 commits src/options.js" "$FILES32" "src/options.js"
assert_contains "AC7 setup_E32 commits db/seed.json" "$FILES32" "db/seed.json"
assert_eq "AC7 the setup is committed (clean work tree after the idle run)" "clean" "$(s32="$(git -C "$W/E32" status --porcelain 2>&1)" && [ -z "$s32" ] && echo clean || echo "dirty or missing: $s32")"
OL32="$(node -e '
const { optionLabel } = require(process.argv[1]);
const j = JSON.stringify([{ value: "r", label: "Red" }, { value: "g", label: "Green" }]);
process.stdout.write([typeof optionLabel, optionLabel(j, "g"), String(optionLabel(j, "x"))].join(","));' "$W/E32/src/options.js" 2>/dev/null)"
assert_eq "AC7 optionLabel(json, value) returns the label of the matching option and undefined when none matches" "function,Green,undefined" "$OL32"
assert_eq "AC7 src/options.js has the single expression hit.label the mutant replaces (D12)" "1" "$(grep -o 'hit\.label' "$W/E32/src/options.js" 2>/dev/null | grep -c .)"
SEED32="$(node -e '
const fs = require("fs"); let n = 0, bad = 0;
const walk = (o) => { if (o && typeof o === "object") for (const k of Object.keys(o)) {
  if (k === "options_json") { const a = typeof o[k] === "string" ? JSON.parse(o[k]) : o[k];
    for (const x of a) { n++; if (x.value !== x.label) bad++; } } else walk(o[k]); } };
walk(JSON.parse(fs.readFileSync(process.argv[1], "utf8"))); process.stdout.write(n > 0 && bad === 0 ? "value == label" : "options " + n + ", value != label " + bad);' "$W/E32/db/seed.json" 2>/dev/null)"
assert_eq "AC7 every option of the seed's options_json has value == label (the obvious fixture)" "value == label" "$SEED32"
assert_eq "AC10 the E32 prompt is the scenario's" "$P32" "$(head -n 1 "$REC/E32.prompt" 2>/dev/null)"
S32="$(section_of E32)"
assert_contains "AC10 scenarios.md has an E32 section with a **Prompt:** line" "$S32" "**Prompt:**"
assert_contains "AC10 scenarios.md E32 has **Pass if:**" "$S32" "**Pass if:**"
assert_contains "AC10 scenarios.md E32 has an Auto checks: line" "$S32" "Auto checks:"
assert_contains "AC10 scenarios.md E32 has **Fail if:**" "$S32" "**Fail if:**"
assert_eq "AC7a the idle run adds no test file: FAIL" "FAIL" "$(e_state E32 "$KA32")"
assert_eq "AC7c without a qualifying test the mutant check is MANUAL" "MANUAL" "$(e_state E32 "$KC32")"

echo "AC7 E32: a test with value != label kills the mutant"
TD32="$(mk_tmp)"
TMPDIR="$TD32" row32 m1 "$GOOD32"
assert_eq "AC7a tests/options.test.js (untracked) names optionLabel: PASS" "PASS" "$(e_state E32 "$KA32")"
assert_eq "AC7b the tests pass on the agent's code: PASS" "PASS" "$(e_state E32 "$KB32")"
assert_eq "AC7c the tests fail on the value-for-label mutant: PASS" "PASS" "$(e_state E32 "$KC32")"
no_fail E32 "AC7 the good transcript has no FAIL line"
assert_eq "AC7 the grader writes nothing outside the workdir (runner check)" "PASS" "$(e_state E32 'nothing written outside the workdir')"
assert_eq "AC7 the grader leaves the agent's src/options.js untouched" "" "$(git -C "$XW/E32" status --porcelain -- src/options.js 2>&1)"
assert_eq "AC7 the mktemp copy of the mutant is removed after grading (no options.js left in TMPDIR)" "" "$(find "$TD32" -name options.js 2>/dev/null)"

echo "AC7 E32: good transcripts worded differently are never FAILed"
row32 m2 "$(cpto t32spec src/options.spec.js)"
assert_eq "AC7a a *.spec.* file next to the source qualifies: PASS" "PASS" "$(e_state E32 "$KA32")"
assert_eq "AC7c the spec file kills the mutant: PASS" "PASS" "$(e_state E32 "$KC32")"
no_fail E32 "AC7 the spec-file transcript has no FAIL line"
row32 m3 "$GOOD32 && $GC add tests/options.test.js && $GC commit -qm 'test: optionLabel'"
assert_eq "AC7a a test file committed after E32_BASE qualifies: PASS" "PASS" "$(e_state E32 "$KA32")"
assert_eq "AC7c the committed test kills the mutant: PASS" "PASS" "$(e_state E32 "$KC32")"

echo "AC7 E32: tests that cannot tell value from label FAIL the mutant check"
row32 m4 "$(cpto t32same tests/options.test.js)"
assert_eq "AC7a the value == label test names optionLabel: PASS" "PASS" "$(e_state E32 "$KA32")"
assert_eq "AC7b it passes on the agent's code: PASS" "PASS" "$(e_state E32 "$KB32")"
assert_eq "AC7c a value == label fixture survives the mutant: FAIL" "FAIL" "$(e_state E32 "$KC32")"
row32 m5 "$(cpto t32miss tests/options.test.js)"
assert_eq "AC7c a no-match test alone survives the mutant (it keeps undefined): FAIL" "FAIL" "$(e_state E32 "$KC32")"

echo "AC7 E32: MANUAL and FAIL edges"
row32 m6 "$GOOD32 && printf '%s\n' '// reviewed' >> src/options.js"
assert_eq "AC7c the agent changed src/options.js: MANUAL" "MANUAL" "$(e_state E32 "$KC32")"
assert_eq "AC7b the tests still pass on the changed file: PASS" "PASS" "$(e_state E32 "$KB32")"
row32 m7 "$(cpto t32bad tests/options.test.js)"
assert_eq "AC7b a qualifying test that fails on the agent's code: FAIL" "FAIL" "$(e_state E32 "$KB32")"
assert_eq "AC7c (b) did not pass: MANUAL (a test passing only on the mutant is not credited)" "MANUAL" "$(e_state E32 "$KC32")"
row32 m8 "$(cpto t32other tests/other.test.js)"
assert_eq "AC7a a new test file that does not name optionLabel: FAIL" "FAIL" "$(e_state E32 "$KA32")"
assert_eq "AC7c (a) did not pass: MANUAL" "MANUAL" "$(e_state E32 "$KC32")"

t_summary
