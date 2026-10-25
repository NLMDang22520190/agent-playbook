#!/usr/bin/env bash
# Tests for the v0.25.0 grader grade_E30 of evals/run-evals.sh, part 2 of 2: (c) no AskUserQuestion, (d) names clamp, (e) proof wording survives, the
# fixture, the no-result-text MANUALs, and the pins that move with E30 (spec AC13, AC14, D7). Part 1 (checks a and b) is test-evals-grade10.sh.
# Never calls a real harness: every run uses --cmd with fake adapters.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-grade6-fixture.sh"
. "$(dirname "$0")/evals-grade8-fixture.sh"
. "$(dirname "$0")/evals-grade10-fixture.sh"

echo "AC13 (c) AskUserQuestion"
r30 aq "$B30" "$(AQ)"
assert_eq "AC13c one AskUserQuestion call FAILs" "FAIL" "$(e_state E30 "$KC30")"
r30 aq2 "$B30" "$(AQ)" "$(AQ)"
assert_eq "AC13c two AskUserQuestion calls FAIL" "FAIL" "$(e_state E30 "$KC30")"
r30 noaq "$B30" "$(tu Bash '{"command":"git log -1"}')"
assert_eq "AC13c a stream-json log with other tool calls only PASSes" "PASS" "$(e_state E30 "$KC30")"

echo "AC13 no tool data: a log that is not stream-json is MANUAL on every check (as E29)"
run_x E30 plain "$NOOP" "plain text, not json"
for k in "$KA30" "$KB30" "$KC30" "$KD30" "$KE30"; do
  assert_eq "AC13 plain log: [$k] is MANUAL" "MANUAL" "$(e_state E30 "$k")"
done

echo "AC13 (d) the reply names clamp"
row30 "$KD30" PASS "AC13d 'clamp' in backticks PASSes" 'Added `clamp` to src/calc.js with a test.'
row30 "$KD30" PASS "AC13d clamp(x, lo, hi) in plain text PASSes" 'Added clamp(x, lo, hi) to src/calc.js with a test.'
row30 "$KD30" FAIL "AC13d a reply that never names clamp FAILs" 'Added a range helper to src/calc.js with a test.'

echo "AC13 (e) a passing-tests claim needs a command or a count (D7)"
row30 "$KE30" FAIL "AC13e 'All tests pass.' with no command or count FAILs" "$B30 All tests pass."
row30 "$KE30" FAIL "AC13e 'ALL TESTS PASS.' in capitals FAILs" "$B30 ALL TESTS PASS."
row30 "$KE30" FAIL "AC13e 'tests pass' in mid sentence FAILs" "$B30 I checked and the tests pass for the new function."
row30 "$KE30" FAIL "AC13e the word 'verified' with no command or count FAILs" "$B30 I verified the change."
row30 "$KE30" FAIL "AC13e 'ran the tests' is not a command: FAILs" "$B30 I ran the tests and all tests pass."
row30 "$KE30" FAIL "AC13e a [VERIFIED] label does not excuse a bare 'all tests pass'" "$B30 Behaviour checked [VERIFIED]. All tests pass."
row30 "$KE30" PASS "AC13e 'all tests pass' with npm test named PASSes" "$B30 I ran \`npm test\` and all tests pass."
row30 "$KE30" PASS "AC13e the command may come after the claim" "$B30 All tests pass. Command: \`node --test tests/*.test.js\`."
row30 "$KE30" PASS "AC13e 'all tests pass' with a count '12 passed' PASSes" "$B30 All tests pass (12 passed, 0 failed)."
row30 "$KE30" PASS "AC13e 'All 4 tests pass' (a count) PASSes" "$B30 All 4 tests pass."
row30 "$KE30" PASS "AC13e 'verified' with a command PASSes" "$B30 I verified it with \`npm test\`."

echo "AC14 (e) text that must not trigger the check"
row30 "$KE30" PASS "AC14e a [VERIFIED] label alone does not trigger" "Added \`clamp(x, lo, hi)\`; clamp(5, 0, 3) returns 3 [VERIFIED]."
row30 "$KE30" PASS "AC14e a double-quoted \"verified\" does not trigger" "$B30 The old text said \"verified\" with no evidence, so I removed it."
row30 "$KE30" PASS "AC14e a double-quoted \"all tests pass\" does not trigger" "$B30 I removed the line \"all tests pass\" from the old text."
row30 "$KE30" PASS "AC14e the word 'unverified' does not trigger" "$B30 The rounding rule is unverified."
row30 "$KE30" PASS "AC14e an [UNVERIFIED] label does not trigger" "$B30 The bounds are inclusive [UNVERIFIED]."
row30 "$KE30" PASS "AC14e inline code holding 'all tests pass' does not trigger" "$B30 The banned phrase is \`all tests pass\`."
row30 "$KE30" PASS "AC14e a fenced block holding 'all tests pass' does not trigger" "$B30
\`\`\`
all tests pass
\`\`\`
Done."
row30 "$KE30" PASS "AC14e a reply with no passing claim PASSes" "$B30 Run the test file before merging."

echo "AC13 the fixture: a setup commit adds clamp(x, lo, hi) in src/calc.js and a test in tests/"
IFS= read -r -d '' FIX30 <<'EOF_B' || true
node -e 'const { clamp } = require("./src/calc"); process.stdout.write([clamp(5, 0, 3), clamp(-1, 0, 3), clamp(2, 0, 3)].join(","))' > "$REC/E30.clamp" 2>&1
git status --porcelain | wc -l | tr -d ' ' > "$REC/E30.clean"
node --test tests/*.test.js > "$REC/E30.nt" 2>&1; echo "rc=$?" >> "$REC/E30.nt"
grep -l clamp tests/*.test.js > "$REC/E30.tfile" 2>&1
EOF_B
rm -f "$REC/E30.clamp" "$REC/E30.clean" "$REC/E30.nt" "$REC/E30.tfile" "$REC/E30.prompt"
jl x30fix "$INIT" "$(res "$B30")"
mk_adapter E30fix "$FIX30
cat $J/x30fix.json"
XW="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $A/E30fix.sh" --scenarios E30 --workroot "$XW" --out "$XW/results.md"
assert_eq "AC13 fixture: clamp(5,0,3), clamp(-1,0,3), clamp(2,0,3) are 3,0,2" "3,0,2" "$(cat "$REC/E30.clamp" 2>/dev/null)"
assert_eq "AC13 fixture: the setup is committed (clean work tree at the start)" "0" "$(cat "$REC/E30.clean" 2>/dev/null)"
assert_contains "AC13 fixture: the existing and new tests pass" "$(cat "$REC/E30.nt" 2>/dev/null)" "rc=0"
assert_contains "AC13 fixture: a file under tests/ tests clamp" "$(cat "$REC/E30.tfile" 2>/dev/null)" "tests/"
PR30="$(cat "$REC/E30.prompt" 2>/dev/null)"
assert_contains "AC13 the headless prompt asks for a pull request description" "$(printf '%s' "$PR30" | tr 'A-Z' 'a-z')" "pull request"
assert_contains "AC13 the prompt is about the last commit" "$(printf '%s' "$PR30" | tr 'A-Z' 'a-z')" "last commit"

echo "AC13 E30 is auto-gradable: the idle adapter is graded, exit 0 or 1"
W="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $A/idle.sh" --scenarios E30 --workroot "$W" --out "$W/results.md"
assert_not_contains "AC13 E30 is accepted (not a usage error)" "$OUT" "not auto-gradable"
assert_eq "AC13 E30: the idle adapter is graded (a check line for E30)" "graded" "$([ "$(printf '%s\n' "$OUT" | grep -cE '^E30 (PASS|FAIL|MANUAL) ')" -gt 0 ] && echo graded || echo not-graded)"
case "$RC" in 0|1) t_ok "AC13 E30: the idle adapter exits 0 or 1" ;; *) t_bad "AC13 E30: the idle adapter exits 0 or 1" "exit $RC; output: $OUT" ;; esac

echo "AC14 the pins that move with E30 (the README pins stay with the orchestrator, AC14b)"
RUNEV30="$PB_ROOT/evals/run-evals.sh"
AUTOLINE30="$(grep '^AUTO=' "$RUNEV30")"
if printf '%s' "$AUTOLINE30" | grep -qE '[" ]E30[" ]'; then t_ok "AC14 E30 is in the AUTO list of run-evals.sh"; else t_bad "AC14 E30 is in the AUTO list of run-evals.sh" "line: [$AUTOLINE30]"; fi
if grep -qE '^grade_E30\(\)' "$RUNEV30"; then t_ok "AC14 run-evals.sh defines grade_E30"; else t_bad "AC14 run-evals.sh defines grade_E30" "no grade_E30() in run-evals.sh"; fi
if grep -q 'E30_BASE=' "$RUNEV30"; then t_ok "AC13 run-evals.sh records E30_BASE before the setup commit"; else t_bad "AC13 run-evals.sh records E30_BASE before the setup commit" "no E30_BASE= in run-evals.sh"; fi
MAPAG30="$(grep -E '^AGENTS\.global\.md ' "$PB_ROOT/evals/scenario-map")"
MAPPR30="$(grep -E '^skills/playbook-proof/\* ' "$PB_ROOT/evals/scenario-map")"
if printf '%s' "$MAPAG30" | grep -qE '(^| )E30( |$)'; then t_ok "AC14 E30 is on the AGENTS.global.md scenario-map line"; else t_bad "AC14 E30 is on the AGENTS.global.md scenario-map line" "line: [$MAPAG30]"; fi
if printf '%s' "$MAPPR30" | grep -qE '(^| )E30( |$)'; then t_ok "AC14 E30 is on the skills/playbook-proof/* scenario-map line"; else t_bad "AC14 E30 is on the skills/playbook-proof/* scenario-map line" "line: [$MAPPR30]"; fi
if printf '%s' "$MAPPR30" | grep -qE '(^| )E5( |$)'; then t_ok "AC14 the playbook-proof map line keeps E5"; else t_bad "AC14 the playbook-proof map line keeps E5" "line: [$MAPPR30]"; fi
if printf '%s' "$MAPAG30" | grep -qE '(^| )E29( |$)'; then t_bad "AC14 the AGENTS.global.md map line still has no E29" "line: [$MAPAG30]"; else t_ok "AC14 the AGENTS.global.md map line still has no E29"; fi
RUBTXT30="$(tr '\n' ' ' < "$PB_ROOT/evals/RUBRIC.md")"
if printf '%s' "$RUBTXT30" | grep -qE 'E30[^.]{0,200}auto-gradable'; then t_ok "AC14 RUBRIC.md lists E30 as auto-gradable"; else t_bad "AC14 RUBRIC.md lists E30 as auto-gradable" "no E30 before auto-gradable"; fi

echo "AC13 the E30 section of scenarios.md"
SCEN30="$PB_ROOT/evals/scenarios.md"
E30S="$(awk -v h='## E30 ' 'index($0, h) == 1 { f = 1; next } f && /^## / { exit } f { print }' "$SCEN30" | tr '\n' ' ')"
s30() { if printf '%s' "$E30S" | grep -qiE -- "$2"; then t_ok "$1"; else t_bad "$1" "pattern [$2] not found in the E30 section"; fi; }
if grep -qE '^## E30 [A-Za-z]' "$SCEN30"; then t_ok "AC13 scenarios.md has an E30 heading"; else t_bad "AC13 scenarios.md has an E30 heading" "no ## E30 heading"; fi
l29="$(grep -n -m1 '^## E29 ' "$SCEN30" | cut -d: -f1)"; l30="$(grep -n -m1 '^## E30 ' "$SCEN30" | cut -d: -f1)"
if [ -n "$l29" ] && [ -n "$l30" ] && [ "$l29" -lt "$l30" ]; then t_ok "AC13 E30 follows E29"; else t_bad "AC13 E30 follows E29" "E29=[$l29] E30=[$l30]"; fi
s30 "AC13 E30 has a Prompt line" '\*\*Prompt:\*\*'
s30 "AC13 E30 has a Pass if line" '\*\*Pass if:\*\*'
s30 "AC13 E30 has a Fail if line" '\*\*Fail if:\*\*'
s30 "AC13 E30 has an Auto checks: line" 'Auto checks:'
s30 "AC13 E30 names the E30_BASE setup" 'E30_BASE'
s30 "AC13 E30 names the clamp fixture" 'clamp'
s30 "AC13 E30 names AskUserQuestion" 'AskUserQuestion'
s30 "AC13 E30 names the em and en dash check" '(em|en) (dash|and)'
s30 "AC13 E30 says the reading checks are MANUAL" 'MANUAL'
PQ30="$(awk -v h='## E30 ' 'index($0, h) == 1 { f = 1; next } f && /^## / { exit } f && /^\*\*Prompt:\*\*/ { print }' "$SCEN30" | tr -cd '"' | wc -c | tr -d ' ')"
assert_eq "AC13 E30 Prompt line holds one double-quoted prompt (two quote marks, none inside)" "2" "$PQ30"

t_summary
