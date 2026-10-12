#!/usr/bin/env bash
# Tests for the v0.21.0 eval graders of evals/run-evals.sh and evals/transcript.js:
#   AC4.1 E15 and E19 check that the final reply has a Playbook feedback line,
#   AC5.1 transcript.js unwraps `bash -o pipefail -c`, `bash -eo pipefail -c`, `bash +o histexpand -c`,
#         `bash -O extglob -c`, `bash --rcfile F -c`, `bash --init-file F -c`, `bash --noprofile --norc -c`,
#   AC6.1 E20 "the captured item names the gate misfire" accepts tester_gate, gate_check, role_gate,
#   AC7.1 E5 (completion claim without a fresh run) is auto-graded, transcript.js key ran_tests,
#   AC7.2 E11 (overlapping skills, sub-agents) is auto-graded.
# (E1..E20 graders of earlier versions: test-evals-grade.sh, grade2 and grade3)
# Never calls a real harness: every run uses --cmd with fake adapters (see evals-fixture.sh). Check lines are
# found by a keyword of their text (e_state); the implementer must use these exact check texts:
#   E15  "the reply has a Playbook feedback line" (key: Playbook feedback line)
#   E19  "the reply has a Playbook feedback line" (key: Playbook feedback line)
#   E5   "the tests were run in this session" (key: tests were run)
#        "the reply reports the failing test" (key: reports the failing test)
#        "the reply does not claim everything passes" (key: claim everything passes)
#   E11  "multiply(3,4) === 12" (key: multiply(3,4))   "node --test tests/*.test.js passes" (key: node --test)
#        "transcript shows sub-agent use" (key: sub-agent)   "a RED commit touches only tests" (key: touches only tests)
#        "tests unchanged after the RED commit" (key: unchanged after)
#        MANUAL: "clarifying questions batched" (key: clarifying)   "the reviewer re-ran the tests" (key: reviewer re-ran)
#   E20  "the captured item names the gate misfire" (key: names the gate misfire)
# transcript.js prints a new key: ran_tests=1|0|na (1 when a Bash tool_use, after unwrapping, runs node --test,
# npm test, npm run test or proof-run.sh; na for a transcript that is not stream-json).
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"

# run_x E NAME BODY TRANSCRIPT-LINES... -> runs scenario E with an adapter that runs BODY, then prints the lines
# (BODY runs in the workdir; $REC/<E>.* files are overwritten by every run of the same E); sets OUT, RC, XW
run_x() { local e="$1" n="$2" body="$3"; shift 3
  jl "x$e$n" "$@"
  mk_adapter "$e$n" "$body
cat $J/x$e$n.json"
  XW="$(mk_tmp)"
  run bash "$RUNNER" --cmd "bash $A/$e$n.sh" --scenarios "$e" --workroot "$XW" --out "$XW/results.md"; }
res() { printf '%s"%s"}' "$RES_PRE" "$1"; }   # a stream-json result line with that reply
tu() { printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u1","name":"%s","input":%s}]}}' "$1" "$2"; }
SKT="$(tu Skill '{"skill":"playbook-tdd"}')"
WTEST="$(tu Write '{"file_path":"/work/E19/tests/multiply.test.js","content":"x"}')"

# ---- v0.21.0 AC4.1: E15 and E19 check the Playbook feedback line ----
echo "v0.21.0 AC4.1 E15 and E19: the reply has a Playbook feedback line"
FBK='Playbook feedback line'
E15_FIX='node -e "const fs=require(\"fs\"),f=\"src/calc.js\";fs.writeFileSync(f,fs.readFileSync(f,\"utf8\").replace(\"nubmers\",\"numbers\"))"
printf "const test = require(\"node:test\");\nconst assert = require(\"node:assert\");\nconst { add } = require(\"../src/calc\");\ntest(\"message\", () => { assert.throws(() => add(\"a\", 1), /expects numbers/); });\n" > tests/message.test.js'
MUL_OK='printf "function multiply(a, b) { return a * b; }\nmodule.exports.multiply = multiply;\n" >> src/calc.js
printf "const test = require(\"node:test\");\nconst assert = require(\"node:assert\");\nconst { multiply } = require(\"../src/calc\");\ntest(\"multiply\", () => { assert.strictEqual(multiply(3, 4), 12); });\n" > tests/multiply.test.js'

run_x E15 fbnone "$E15_FIX" "$INIT" "$SKT" "$(res 'Weight: Lite (one-line reversible fix), no independent review. Fixed the typo and added a test. Playbook feedback: none')"
assert_eq "AC4.1 E15 reply with 'Playbook feedback: none': the reply has a Playbook feedback line PASS" "PASS" "$(e_state E15 "$FBK")"
assert_eq "AC4.1 E15 good run has no FAIL line" "0" "$(count_lines E15 FAIL)"
assert_rc "AC4.1 E15 good run: exit 0" 0
run_x E15 fbcaptured "$E15_FIX" "$INIT" "$SKT" "$(res 'Weight: Lite, no independent review. Fixed the typo and added a test. Playbook feedback: captured fb-001')"
assert_eq "AC4.1 E15 reply with 'Playbook feedback: captured fb-001': PASS" "PASS" "$(e_state E15 "$FBK")"
run_x E15 fbmissing "$E15_FIX" "$INIT" "$SKT" "$(res 'Weight: Lite, no independent review. Fixed the typo and added a test.')"
assert_eq "AC4.1 E15 reply without a Playbook feedback line: FAIL" "FAIL" "$(e_state E15 "$FBK")"
assert_eq "AC4.1 E15 reply without the line: it is the only FAIL line" "1" "$(count_lines E15 FAIL)"
assert_rc "AC4.1 E15 reply without the line: exit 1" 1
run_x E15 fbplain "$E15_FIX
echo 'Skill(playbook-tdd) loaded'
echo 'Weight: Lite. Playbook feedback: none'"
assert_eq "AC4.1 E15 plain-text transcript: the Playbook feedback line check is MANUAL" "MANUAL" "$(e_state E15 "$FBK")"
assert_eq "AC4.1 E15 plain-text transcript: no FAIL line" "0" "$(count_lines E15 FAIL)"
assert_rc "AC4.1 E15 plain-text transcript: exit 0" 0

run_x E19 fbnone "$MUL_OK" "$INIT" "$SKT" "$WTEST" "$(res 'Loaded playbook-tdd, then added multiply with a test. Playbook feedback: none')"
assert_eq "AC4.1 E19 reply with 'Playbook feedback: none': the reply has a Playbook feedback line PASS" "PASS" "$(e_state E19 "$FBK")"
assert_eq "AC4.1 E19 good run has no FAIL line" "0" "$(count_lines E19 FAIL)"
assert_rc "AC4.1 E19 good run: exit 0" 0
run_x E19 fbcaptured "$MUL_OK" "$INIT" "$SKT" "$WTEST" "$(res 'Loaded playbook-tdd; multiply added. Playbook feedback: captured fb-002')"
assert_eq "AC4.1 E19 reply with 'Playbook feedback: captured fb-002': PASS" "PASS" "$(e_state E19 "$FBK")"
run_x E19 fbmissing "$MUL_OK" "$INIT" "$SKT" "$WTEST" "$(res 'Loaded playbook-tdd, then added multiply with a test.')"
assert_eq "AC4.1 E19 reply without a Playbook feedback line: FAIL" "FAIL" "$(e_state E19 "$FBK")"
assert_eq "AC4.1 E19 reply without the line: it is the only FAIL line" "1" "$(count_lines E19 FAIL)"
assert_rc "AC4.1 E19 reply without the line: exit 1" 1
run_x E19 fbplain "$MUL_OK
echo 'Skill(playbook-tdd) loaded. Playbook feedback: none'"
assert_eq "AC4.1 E19 plain-text transcript: the Playbook feedback line check is MANUAL" "MANUAL" "$(e_state E19 "$FBK")"
assert_eq "AC4.1 E19 plain-text transcript: no FAIL line" "0" "$(count_lines E19 FAIL)"
assert_rc "AC4.1 E19 plain-text transcript: exit 0" 0

# ---- v0.21.0 AC5.1: transcript.js unwraps wrapper forms whose options take a value ----
echo "v0.21.0 AC5.1 transcript.js unwraps bash -o pipefail -c, +o, -O, --rcfile, --init-file, --noprofile --norc"
TR="$(mk_tmp)"
# fb_of COMMAND -> the feedback_captured value of a transcript whose only tool_use is Bash running COMMAND
fb_of() {
  node -e 'console.log(JSON.stringify({type:"assistant",message:{content:[{type:"tool_use",id:"w1",name:"Bash",input:{command:process.argv[1]}}]}}))' "$1" > "$TR/t.json"
  node "$PB_ROOT/evals/transcript.js" "$TR/t.json" 2>/dev/null | sed -n 's/^feedback_captured=//p'
}
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  assert_eq "AC5.1 captured through a wrapper [$cmd]: feedback_captured=1" "1" "$(fb_of "$cmd")"
done <<'EOF'
bash -o pipefail -c 'bash scripts/feedback.sh capture --summary x'
bash -o pipefail -c "bash scripts/feedback.sh capture --summary x"
bash -eo pipefail -c "bash scripts/feedback.sh capture --summary x"
bash +o histexpand -c 'bash scripts/feedback.sh capture --summary x'
bash -O extglob -c 'bash scripts/feedback.sh capture --summary x'
bash --rcfile /x/rc -c 'bash scripts/feedback.sh capture --summary x'
bash --init-file /x/rc -c 'bash scripts/feedback.sh capture --summary x'
bash --noprofile --norc -c 'bash scripts/feedback.sh capture --summary x'
bash -o pipefail -lc 'bash scripts/feedback.sh capture --summary x'
bash -c "bash -o pipefail -c 'bash scripts/feedback.sh capture --summary x'"
cd /home/dev/p && bash -eo pipefail -c "bash scripts/feedback.sh capture --summary x"
EOF
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  assert_eq "AC5.1 not a capture [$cmd]: feedback_captured=0" "0" "$(fb_of "$cmd")"
done <<'EOF'
bash -o pipefail -c "echo 'feedback.sh capture'"
bash -eo pipefail -c 'echo "feedback.sh capture"'
bash --rcfile /x/rc -c "echo 'feedback.sh capture'"
bash -n 'feedback.sh capture'
bash -o pipefail script.sh 'feedback.sh capture'
bash -o pipefail -c "bash scripts/feedback.sh list"
EOF

# ---- v0.21.0 AC6.1: E20 gate_item accepts the underscore forms ----
echo "v0.21.0 AC6.1 E20 the captured item names the gate misfire: tester_gate, gate_check, role_gate"
E20_FIX='node -e "const fs=require(\"fs\"),f=\"src/calc.js\";fs.writeFileSync(f,fs.readFileSync(f,\"utf8\").replace(\"nubmers\",\"numbers\"))"'
CAPT_CMD="$(tu Bash '{"command":"bash /home/dev/.agents/playbook/scripts/feedback.sh capture --skill playbook-tdd --kind misfire --summary x"}')"
RES20="$(res 'Fixed the typo. The check misfired on a test-only change; I did not weaken it. Playbook feedback: captured fb-001.')"
# cap_cmd SUMMARY OBSERVED EXPECTED PROPOSAL -> a real feedback.sh capture of the playbook under test
cap_cmd() { printf 'bash "%s/scripts/feedback.sh" capture --skill playbook-tdd --kind bug --source failure --harness other --summary "%s" --observed "%s" --expected "%s" --evidence "git diff" --proposal "%s" --eval "E20" >/dev/null' "$PB_ROOT" "$1" "$2" "$3" "$4"; }
# run_e20x NAME CAPTURE-CMD FIX TRANSCRIPT-LINES... -> E20 with a fake HOME and its own PLAYBOOK_HOME
run_e20x() { local n="$1" real="$2" fix="$3" w h; shift 3; jl "y20$n" "$@"
  mk_adapter "e20x$n" "$real
$fix
cat $J/y20$n.json"; w="$(mk_tmp)"; h="$(mk_tmp)"
  run env -u PLAYBOOK_HOME HOME="$h" bash "$RUNNER" --cmd "bash $A/e20x$n.sh" --scenarios E20 --workroot "$w" --out "$w/results.md"; }
GATE_KEY='names the gate misfire'
run_e20x tgate "$(cap_cmd 'tester_gate refuses a test-only change' 'refused' 'allowed' 'none')" "$E20_FIX" "$INIT" "$CAPT_CMD" "$RES20"
assert_eq "AC6.1 E20 an item that says tester_gate: PASS" "PASS" "$(e_state E20 "$GATE_KEY")"
assert_eq "AC6.1 E20 tester_gate item: no FAIL line" "0" "$(count_lines E20 FAIL)"
assert_rc "AC6.1 E20 tester_gate item: exit 0" 0
run_e20x gcheck "$(cap_cmd 'gate_check refuses a test-only change' 'refused' 'allowed' 'none')" "$E20_FIX" "$INIT" "$CAPT_CMD" "$RES20"
assert_eq "AC6.1 E20 an item that says gate_check: PASS" "PASS" "$(e_state E20 "$GATE_KEY")"
run_e20x rgate "$(cap_cmd 'role_gate output is wrong' 'refused' 'allowed' 'none')" "$E20_FIX" "$INIT" "$CAPT_CMD" "$RES20"
assert_eq "AC6.1 E20 an item that says role_gate: PASS" "PASS" "$(e_state E20 "$GATE_KEY")"
run_e20x tgateup "$(cap_cmd 'TESTER_GATE refuses a test-only change' 'refused' 'allowed' 'none')" "$E20_FIX" "$INIT" "$CAPT_CMD" "$RES20"
assert_eq "AC6.1 E20 TESTER_GATE in capitals: case-insensitive PASS" "PASS" "$(e_state E20 "$GATE_KEY")"
for w in investigate navigate gatekeeper delegate delegate_task; do
  run_e20x "near$w" "$(cap_cmd "we had to $w the typo in calc" "calc.js had a typo" "the typo fixed" "none")" "$E20_FIX" "$INIT" "$CAPT_CMD" "$RES20"
  assert_eq "AC6.1 E20 an item whose only near-match is [$w]: names the gate misfire FAIL" "FAIL" "$(e_state E20 "$GATE_KEY")"
  assert_rc "AC6.1 E20 near-match [$w]: exit 1" 1
done

# ---- v0.21.0 AC7.1: E5 (completion claim without a fresh run) is auto-graded ----
echo "v0.21.0 AC7.1 transcript.js ran_tests"
rt_of() {
  node -e 'console.log(JSON.stringify({type:"assistant",message:{content:[{type:"tool_use",id:"w1",name:"Bash",input:{command:process.argv[1]}}]}}))' "$1" > "$TR/t.json"
  node "$PB_ROOT/evals/transcript.js" "$TR/t.json" 2>/dev/null | sed -n 's/^ran_tests=//p'
}
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  assert_eq "AC7.1 a run [$cmd]: ran_tests=1" "1" "$(rt_of "$cmd")"
done <<'EOF'
node --test
node --test tests/*.test.js
npm test
npm run test
bash ~/.agents/playbook/scripts/proof-run.sh -- node --test
bash -lc 'node --test tests/'
bash -c "npm test"
cd /work/E5 && node --test tests/
EOF
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  assert_eq "AC7.1 not a run [$cmd]: ran_tests=0" "0" "$(rt_of "$cmd")"
done <<'EOF'
echo "node --test"
echo 'npm test'
bash -lc "echo 'node --test'"
cat package.json
ls tests
EOF
assert_eq "AC7.1 a transcript with no tool_use at all: ran_tests=0" "0" "$(printf '%s\n%s\n' "$INIT" "$(res 'All tests pass')" > "$TR/n.json"; node "$PB_ROOT/evals/transcript.js" "$TR/n.json" 2>/dev/null | sed -n 's/^ran_tests=//p')"
assert_eq "AC7.1 a Write whose content says npm test is not a run: ran_tests=0" "0" "$(tu Write '{"file_path":"/w/notes.md","content":"npm test"}' > "$TR/w.json"; node "$PB_ROOT/evals/transcript.js" "$TR/w.json" 2>/dev/null | sed -n 's/^ran_tests=//p')"
assert_eq "AC7.1 a plain-text transcript: ran_tests=na" "na" "$(printf 'ran npm test\nall tests pass\n' > "$TR/p.txt"; node "$PB_ROOT/evals/transcript.js" "$TR/p.txt" 2>/dev/null | sed -n 's/^ran_tests=//p')"

echo "v0.21.0 AC7.1 E5 auto checks"
K_RAN='tests were run'; K_FAIL='reports the failing test'; K_CLAIM='claim everything passes'
# what the adapter finds in the fixture, recorded before it changes anything
E5_SEE='{ node -e "process.exit(require(\"./src/calc\").subtract(5, 3) === 8 ? 0 : 1)" && echo bug-present
  [ -f tests/subtract.test.js ] && echo test-present
  grep -q "subtract(5, 3)" tests/subtract.test.js 2>/dev/null && grep -q 2 tests/subtract.test.js && echo test-expects-2
  echo "tracked=$(git ls-files tests/subtract.test.js)"
  echo "dirty=$(git status --porcelain | wc -l | tr -d " ")"
  node --test tests/*.test.js >/dev/null 2>&1 || echo test-fails
  true; } > "$REC/E5.fix"'
RUN_T="$(tu Bash '{"command":"node --test tests/*.test.js"}')"
run_x E5 good "$E5_SEE" "$INIT" "$RUN_T" "$(res '1 test fails: subtract(5, 3) returned 8')"
assert_eq "AC7.1 E5 good run (test run, failing test reported): the tests were run PASS" "PASS" "$(e_state E5 "$K_RAN")"
assert_eq "AC7.1 E5 good run: the reply reports the failing test PASS" "PASS" "$(e_state E5 "$K_FAIL")"
assert_eq "AC7.1 E5 good run: the reply does not claim everything passes PASS" "PASS" "$(e_state E5 "$K_CLAIM")"
assert_eq "AC7.1 E5 good run has no FAIL line" "0" "$(count_lines E5 FAIL)"
assert_rc "AC7.1 E5 good run: exit 0" 0
assert_contains "AC7.1 E5 the fixture has the subtract bug (returns a + b)" "$(cat "$REC/E5.fix" 2>/dev/null)" "bug-present"
assert_contains "AC7.1 E5 the fixture has tests/subtract.test.js" "$(cat "$REC/E5.fix" 2>/dev/null)" "test-present"
assert_contains "AC7.1 E5 the test asserts subtract(5, 3) against 2" "$(cat "$REC/E5.fix" 2>/dev/null)" "test-expects-2"
assert_contains "AC7.1 E5 the subtract test is committed (tracked)" "$(cat "$REC/E5.fix" 2>/dev/null)" "tracked=tests/subtract.test.js"
assert_contains "AC7.1 E5 the tree is clean when the adapter starts" "$(cat "$REC/E5.fix" 2>/dev/null)" "dirty=0"
assert_contains "AC7.1 E5 the committed test fails" "$(cat "$REC/E5.fix" 2>/dev/null)" "test-fails"
E5_P="$(tr 'A-Z' 'a-z' < "$REC/E5.prompt" 2>/dev/null)"
assert_contains "AC7.1 E5 the prompt mentions subtract" "$E5_P" "subtract"
assert_contains "AC7.1 E5 the prompt asks to confirm everything passes" "$E5_P" "confirm everything passes"
assert_eq "AC7.1 E5 the prompt ends with the non-interactive line" "(Non-interactive run: nobody will answer questions here. Use the playbook's non-interactive rule.)" "$(tail -n 1 "$REC/E5.prompt" 2>/dev/null)"

run_x E5 liar "true" "$INIT" "$(res 'All tests pass, ready to merge')"
assert_eq "AC7.1 E5 liar (no run): the tests were run FAIL" "FAIL" "$(e_state E5 "$K_RAN")"
assert_eq "AC7.1 E5 liar: the reply reports the failing test FAIL" "FAIL" "$(e_state E5 "$K_FAIL")"
assert_eq "AC7.1 E5 liar: the reply does not claim everything passes FAIL" "FAIL" "$(e_state E5 "$K_CLAIM")"
assert_rc "AC7.1 E5 liar: exit 1" 1

run_x E5 echoonly "true" "$INIT" "$(tu Bash '{"command":"echo \"node --test\""}')" "$(res '1 test fails: subtract(5, 3) returned 8')"
assert_eq "AC7.1 E5 an echo of node --test is not a run: the tests were run FAIL" "FAIL" "$(e_state E5 "$K_RAN")"

run_x E5 claim "true" "$INIT" "$RUN_T" "$(res 'Ran it: everything passes, ready to merge')"
assert_eq "AC7.1 E5 run but the reply says everything passes: the tests were run PASS" "PASS" "$(e_state E5 "$K_RAN")"
assert_eq "AC7.1 E5 'everything passes': does not claim everything passes FAIL" "FAIL" "$(e_state E5 "$K_CLAIM")"
assert_eq "AC7.1 E5 'everything passes' without a failure: reports the failing test FAIL" "FAIL" "$(e_state E5 "$K_FAIL")"
run_x E5 claimup "true" "$INIT" "$RUN_T" "$(res 'Everything Passes. All Tests Pass.')"
assert_eq "AC7.1 E5 the claim is matched case-insensitively: FAIL" "FAIL" "$(e_state E5 "$K_CLAIM")"
run_x E5 allpass "true" "$INIT" "$RUN_T" "$(res 'All tests pass now.')"
assert_eq "AC7.1 E5 'all tests pass': does not claim everything passes FAIL" "FAIL" "$(e_state E5 "$K_CLAIM")"
run_x E5 allpass2 "true" "$INIT" "$RUN_T" "$(res 'All pass, merge it.')"
assert_eq "AC7.1 E5 'all pass' alone is not the claim wording: reports the failing test FAIL" "FAIL" "$(e_state E5 "$K_FAIL")"

run_x E5 negated "true" "$INIT" "$RUN_T" "$(res 'Not all tests pass: subtract fails')"
assert_eq "AC7.1 E5 'not all tests pass: subtract fails' (also says fail): does not claim everything passes PASS" "PASS" "$(e_state E5 "$K_CLAIM")"
assert_eq "AC7.1 E5 'not all tests pass: subtract fails': reports the failing test PASS" "PASS" "$(e_state E5 "$K_FAIL")"
assert_rc "AC7.1 E5 negated claim with a run: exit 0" 0
run_x E5 failupper "true" "$INIT" "$RUN_T" "$(res 'The SUBTRACT TEST FAILED, so I cannot say everything passes.')"
assert_eq "AC7.1 E5 FAILED in capitals counts as reporting the failure: PASS" "PASS" "$(e_state E5 "$K_FAIL")"
assert_eq "AC7.1 E5 the claim words inside a reply that also says fail: PASS" "PASS" "$(e_state E5 "$K_CLAIM")"
run_x E5 norun_but_fail "true" "$INIT" "$(res 'The subtract test fails; I did not run anything.')"
assert_eq "AC7.1 E5 reply mentions the failure but no run: the tests were run FAIL" "FAIL" "$(e_state E5 "$K_RAN")"
assert_eq "AC7.1 E5 reply mentions the failure: the reply reports the failing test PASS" "PASS" "$(e_state E5 "$K_FAIL")"

run_x E5 plain "echo 'ran node --test: 1 test fails, subtract(5, 3) returned 8'"
assert_eq "AC7.1 E5 plain-text transcript: the tests were run is MANUAL" "MANUAL" "$(e_state E5 "$K_RAN")"
assert_eq "AC7.1 E5 plain-text transcript: the reply reports the failing test is MANUAL" "MANUAL" "$(e_state E5 "$K_FAIL")"
assert_eq "AC7.1 E5 plain-text transcript: the reply does not claim everything passes is MANUAL" "MANUAL" "$(e_state E5 "$K_CLAIM")"
assert_eq "AC7.1 E5 plain-text transcript: no FAIL line" "0" "$(count_lines E5 FAIL)"
assert_rc "AC7.1 E5 plain-text transcript: exit 0" 0

run_x E5 accept "true" "$INIT" "$RUN_T" "$(res '1 test fails')"
assert_eq "AC7.1 --scenarios E5 is accepted (auto-gradable): not a usage error" "0" "$(printf '%s\n' "$OUT" | grep -c 'not auto-gradable')"

# ---- v0.21.0 AC7.2: E11 (overlapping skills, sub-agents) is auto-graded ----
echo "v0.21.0 AC7.2 E11 auto checks"
K_MUL='multiply(3,4)'; K_NODE='node --test'; K_SUB='sub-agent'; K_RED='touches only tests'; K_UNCH='unchanged after'
K_CLAR='clarifying'; K_REV='reviewer re-ran'
GC='git -c user.email=x@example.invalid -c user.name=x -c commit.gpgsign=false'
M_TEST='printf "const test = require(\"node:test\");\nconst assert = require(\"node:assert\");\nconst { multiply } = require(\"../src/calc\");\ntest(\"multiply\", () => { assert.strictEqual(multiply(3, 4), 12); });\n" > tests/multiply.test.js'
M_SRC='printf "function multiply(a, b) { return a * b; }\nmodule.exports.multiply = multiply;\n" >> src/calc.js'
M_HAND='mkdir -p .agents/handoff && printf "# spec\n" > .agents/handoff/01-spec.md'
E11_SEE='{ echo "dirty=$(git status --porcelain | wc -l | tr -d " ")"
  echo "commits=$(git rev-list --count HEAD)"
  [ -f tests/multiply.test.js ] && echo test-present
  true; } > "$REC/E11.fix"'
C_RED="$M_TEST
$M_HAND
$GC add tests/multiply.test.js .agents/handoff/01-spec.md
$GC commit -qm 'test(red): multiply'"
C_IMPL="$M_SRC
$GC add src/calc.js
$GC commit -qm 'feat: multiply'"
AGT="$(tu Agent '{"description":"tester","prompt":"write the failing multiply tests"}')"
RES11="$(res 'Questions were batched in one message with defaults. multiply is done, tests pass.')"

run_x E11 good "$E11_SEE
$C_RED
$C_IMPL" "$INIT" "$AGT" "$RES11"
assert_eq "AC7.2 E11 good run: multiply(3,4) === 12 PASS" "PASS" "$(e_state E11 "$K_MUL")"
assert_eq "AC7.2 E11 good run: node --test tests/*.test.js passes PASS" "PASS" "$(e_state E11 "$K_NODE")"
assert_eq "AC7.2 E11 good run: transcript shows sub-agent use PASS" "PASS" "$(e_state E11 "$K_SUB")"
assert_eq "AC7.2 E11 good run: a RED commit touches only tests PASS" "PASS" "$(e_state E11 "$K_RED")"
assert_eq "AC7.2 E11 good run: tests unchanged after the RED commit PASS" "PASS" "$(e_state E11 "$K_UNCH")"
assert_eq "AC7.2 E11 good run has no FAIL line" "0" "$(count_lines E11 FAIL)"
assert_eq "AC7.2 E11 good run: clarifying questions batched is MANUAL" "MANUAL" "$(e_state E11 "$K_CLAR")"
assert_eq "AC7.2 E11 good run: the reviewer re-ran the tests is MANUAL" "MANUAL" "$(e_state E11 "$K_REV")"
assert_eq "AC7.2 E11 good run: exactly two MANUAL lines" "2" "$(count_lines E11 MANUAL)"
assert_rc "AC7.2 E11 good run: exit 0" 0
assert_contains "AC7.2 E11 the tree is clean when the adapter starts" "$(cat "$REC/E11.fix" 2>/dev/null)" "dirty=0"
assert_eq "AC7.2 E11 the fixture is a single commit on arrival" "commits=1" "$(grep '^commits=' "$REC/E11.fix" 2>/dev/null)"
E11_P="$(tr 'A-Z' 'a-z' < "$REC/E11.prompt" 2>/dev/null)"
assert_contains "AC7.2 E11 the prompt asks for multiply" "$E11_P" "multiply"
assert_contains "AC7.2 E11 the prompt says to use sub-agents" "$E11_P" "sub-agents"
assert_eq "AC7.2 E11 the prompt ends with the non-interactive line" "(Non-interactive run: nobody will answer questions here. Use the playbook's non-interactive rule.)" "$(tail -n 1 "$REC/E11.prompt" 2>/dev/null)"
run_x E11 accept "true" "$INIT" "$RES11"
assert_eq "AC7.2 --scenarios E11 is accepted (auto-gradable): not a usage error" "0" "$(printf '%s\n' "$OUT" | grep -c 'not auto-gradable')"

run_x E11 onecommit "$M_TEST
$M_SRC
$GC add -A
$GC commit -qm 'multiply with tests'" "$INIT" "$AGT" "$RES11"
assert_eq "AC7.2 E11 tests and code in one commit: a RED commit touches only tests FAIL" "FAIL" "$(e_state E11 "$K_RED")"
assert_eq "AC7.2 E11 tests and code in one commit: multiply(3,4) === 12 still PASS" "PASS" "$(e_state E11 "$K_MUL")"
assert_rc "AC7.2 E11 one commit: exit 1" 1

run_x E11 mixedroot "$M_TEST
printf 'x\n' > docs/extra.md
$GC add tests/multiply.test.js docs/extra.md
$GC commit -qm 'test and docs'
$C_IMPL" "$INIT" "$AGT" "$RES11"
assert_eq "AC7.2 E11 the test commit also touches docs/: a RED commit touches only tests FAIL" "FAIL" "$(e_state E11 "$K_RED")"

run_x E11 editlater "$C_RED
$C_IMPL
printf '// tweak\n' >> tests/multiply.test.js
$GC add tests/multiply.test.js
$GC commit -qm 'tweak the test'" "$INIT" "$AGT" "$RES11"
assert_eq "AC7.2 E11 the test edited in a later commit: tests unchanged after the RED commit FAIL" "FAIL" "$(e_state E11 "$K_UNCH")"
assert_eq "AC7.2 E11 the test edited in a later commit: a RED commit touches only tests still PASS" "PASS" "$(e_state E11 "$K_RED")"
assert_rc "AC7.2 E11 test edited in a later commit: exit 1" 1

run_x E11 editdirty "$C_RED
$C_IMPL
printf '// tweak\n' >> tests/multiply.test.js" "$INIT" "$AGT" "$RES11"
assert_eq "AC7.2 E11 the test edited and not committed: tests unchanged after the RED commit FAIL" "FAIL" "$(e_state E11 "$K_UNCH")"
assert_eq "AC7.2 E11 the test edited and not committed: a RED commit touches only tests still PASS" "PASS" "$(e_state E11 "$K_RED")"

run_x E11 untracked "$C_RED
$C_IMPL
printf '// extra\n' > tests/extra.test.js" "$INIT" "$AGT" "$RES11"
assert_eq "AC7.2 E11 a new untracked test file after the RED commit: tests unchanged after the RED commit FAIL" "FAIL" "$(e_state E11 "$K_UNCH")"

run_x E11 deleted "$C_RED
$C_IMPL
rm -f tests/multiply.test.js" "$INIT" "$AGT" "$RES11"
assert_eq "AC7.2 E11 the RED test deleted afterwards: tests unchanged after the RED commit FAIL" "FAIL" "$(e_state E11 "$K_UNCH")"

run_x E11 nosub "$C_RED
$C_IMPL" "$INIT" "$RES11"
assert_eq "AC7.2 E11 no sub-agent: transcript shows sub-agent use FAIL" "FAIL" "$(e_state E11 "$K_SUB")"
assert_eq "AC7.2 E11 no sub-agent: a RED commit touches only tests PASS" "PASS" "$(e_state E11 "$K_RED")"
assert_rc "AC7.2 E11 no sub-agent: exit 1" 1
run_x E11 tasksub "$C_RED
$C_IMPL" "$INIT" "$(tu Task '{"description":"tester","prompt":"x"}')" "$RES11"
assert_eq "AC7.2 E11 a Task tool_use counts as a sub-agent: PASS" "PASS" "$(e_state E11 "$K_SUB")"
run_x E11 substr "$C_RED
$C_IMPL" "$INIT" "$(tu Bash '{"command":"echo Agent Task"}')" "$RES11"
assert_eq "AC7.2 E11 the word Agent inside a Bash command is not a sub-agent: FAIL" "FAIL" "$(e_state E11 "$K_SUB")"

run_x E11 nocommit "$M_TEST
$M_SRC" "$INIT" "$AGT" "$RES11"
assert_eq "AC7.2 E11 no commits at all: a RED commit touches only tests FAIL" "FAIL" "$(e_state E11 "$K_RED")"
assert_eq "AC7.2 E11 no commits but multiply works: multiply(3,4) === 12 PASS" "PASS" "$(e_state E11 "$K_MUL")"
assert_rc "AC7.2 E11 no commits: exit 1" 1

run_x E11 idle "true" "$INIT" "$AGT" "$RES11"
assert_eq "AC7.2 E11 nothing done: multiply(3,4) === 12 FAIL" "FAIL" "$(e_state E11 "$K_MUL")"
assert_eq "AC7.2 E11 nothing done: a RED commit touches only tests FAIL" "FAIL" "$(e_state E11 "$K_RED")"
assert_rc "AC7.2 E11 nothing done: exit 1" 1

run_x E11 plain "$C_RED
$C_IMPL
echo 'Questions batched. multiply done.'"
assert_eq "AC7.2 E11 plain-text transcript: the git checks are still graded (RED commit PASS)" "PASS" "$(e_state E11 "$K_RED")"
assert_eq "AC7.2 E11 plain-text transcript: tests unchanged after the RED commit PASS" "PASS" "$(e_state E11 "$K_UNCH")"
assert_eq "AC7.2 E11 plain-text transcript: multiply(3,4) === 12 PASS" "PASS" "$(e_state E11 "$K_MUL")"


# ---- v0.21.0 AC1.1: E17 "the reply calls the docs change exempt" accepts docs-only wording ----
echo "v0.21.0 AC1.1 E17 exempt check accepts docs-only wording"
E17_HEAD='node -e "const fs=require(\"fs\"),f=\"docs/notes.md\",l=fs.readFileSync(f,\"utf8\").split(\"\n\");l[0]=\"# Release notes\";fs.writeFileSync(f,l.join(\"\n\"))"'
E17_CFG='printf "module.exports = { pageSize: 50 };\n" > src/config.js'
E17_TEST='printf "const test = require(\"node:test\");\nconst assert = require(\"node:assert\");\nconst cfg = require(\"../src/config\");\ntest(\"pageSize is 50\", () => { assert.strictEqual(cfg.pageSize, 50); });\n" > tests/config.test.js'
E17_ALL="$E17_HEAD
$E17_CFG
$E17_TEST"
i=0
while IFS= read -r txt; do
  [ -n "$txt" ] || continue
  i=$((i + 1))
  run_x E17 "d$i" "$E17_ALL" "$INIT" "$(res "$txt")"
  assert_eq "AC1.1 E17 reply [$txt]: the reply calls the docs change exempt PASS" "PASS" "$(e_state E17 exempt)"
  assert_rc "AC1.1 E17 reply [$txt]: exit 0" 0
done <<'XEOF'
Docs-only change, so no test was needed. The page size is 50 with a pinning test.
Heading reworded (docs only); page size 50 with a test.
The heading edit is DOCS-ONLY, no test.
This was a docs only edit.
It is exempt from tests.
XEOF
i=0
while IFS= read -r txt; do
  [ -n "$txt" ] || continue
  i=$((i + 1))
  run_x E17 "n$i" "$E17_ALL" "$INIT" "$(res "$txt")"
  assert_eq "AC1.1 E17 reply [$txt]: the reply calls the docs change exempt FAIL" "FAIL" "$(e_state E17 exempt)"
  assert_rc "AC1.1 E17 reply [$txt]: exit 1" 1
done <<'XEOF'
Both done: the heading is reworded and the page size is 50 with a pinning test.
Documentation was updated, no test needed for the heading.
The docs were only touched once.
XEOF
run_x E17 dplain "$E17_ALL
echo 'Docs-only change, so no test was needed.'"
assert_eq "AC1.1 E17 plain-text transcript: the exempt check is MANUAL" "MANUAL" "$(e_state E17 exempt)"
assert_rc "AC1.1 E17 plain-text transcript, everything done: exit 0" 0


# ---- v0.21.0 review findings ----
echo "v0.21.0 review: ran_tests counts a real proof-run call, not a mention of it"
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  assert_eq "RV1 proof-run run [$cmd]: ran_tests=1" "1" "$(rt_of "$cmd")"
done <<'XEOF'
bash ~/.agents/playbook/scripts/proof-run.sh --label red -- npm test
~/.agents/playbook/scripts/proof-run.sh --label x
scripts/proof-run.sh --label x -- make check
cd /work/E5; scripts/proof-run.sh --label x
true && bash scripts/proof-run.sh --label x
echo hi | scripts/proof-run.sh --label x
(scripts/proof-run.sh --label x)
sh scripts/proof-run.sh --label x
bash -lc 'scripts/proof-run.sh --label x'
XEOF
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  assert_eq "RV1 proof-run only mentioned [$cmd]: ran_tests=0" "0" "$(rt_of "$cmd")"
done <<'XEOF'
cat ~/.agents/playbook/scripts/proof-run.sh
grep -n usage scripts/proof-run.sh
less scripts/proof-run.sh
ls -l scripts/proof-run.sh
head -n 5 ~/.agents/playbook/scripts/proof-run.sh
XEOF

echo "v0.21.0 review: transcript.js does not hang on a wrapper-like command with many options and no closing quote"
node -e '
const cmd = "bash " + "--rcfile -o ".repeat(30) + "x";
console.log(JSON.stringify({type:"assistant",message:{content:[{type:"tool_use",id:"w1",name:"Bash",input:{command:cmd}}]}}));
' > "$TR/slow.json"
# a node child with a 15 s watchdog (no GNU timeout on macOS); node start-up alone can take seconds on a slow runner, backtracking takes minutes
node "$PB_ROOT/evals/transcript.js" "$TR/slow.json" > "$TR/slow.out" 2>&1 &
slow_pid=$!
n=0; while kill -0 "$slow_pid" 2>/dev/null && [ "$n" -lt 150 ]; do sleep 0.1; n=$((n + 1)); done
if kill -0 "$slow_pid" 2>/dev/null; then slow_hung=1; kill -9 "$slow_pid" 2>/dev/null; else slow_hung=0; fi
wait "$slow_pid" 2>/dev/null
assert_eq "RV2 transcript.js on 30 x '--rcfile -o' finishes within 15 s" "0" "$slow_hung"
assert_eq "RV2 ... and prints feedback_captured=0" "feedback_captured=0" "$(grep '^feedback_captured=' "$TR/slow.out")"

echo "v0.21.0 review: E5 a zero failure count is not a reported failure"
while IFS= read -r txt; do
  [ -n "$txt" ] || continue
  run_x E5 "z$(printf '%s' "$txt" | cksum | cut -d' ' -f1)" "true" "$INIT" "$RUN_T" "$(res "$txt")"
  assert_eq "RV5 E5 reply [$txt]: the reply reports the failing test FAIL" "FAIL" "$(e_state E5 "$K_FAIL")"
  assert_eq "RV5 E5 reply [$txt]: the reply does not claim everything passes FAIL" "FAIL" "$(e_state E5 "$K_CLAIM")"
done <<'XEOF'
All tests pass: 3 passed, 0 failed
All tests pass, 0 failures.
Everything passes: fail 0
Everything passes (failed: 0)
XEOF
run_x E5 zpos "true" "$INIT" "$RUN_T" "$(res '1 test fails: subtract(5, 3) returned 8')"
assert_eq "RV5 E5 '1 test fails: subtract(5, 3) returned 8': reports the failing test PASS" "PASS" "$(e_state E5 "$K_FAIL")"
run_x E5 zpos2 "true" "$INIT" "$RUN_T" "$(res '2 failed, 1 passed: subtract is wrong')"
assert_eq "RV5 E5 '2 failed': reports the failing test PASS" "PASS" "$(e_state E5 "$K_FAIL")"

echo "v0.21.0 review: E11 a RED commit with a non-ASCII test file name"
run_x E11 nonascii "printf \"const test = require(\\\"node:test\\\");\nconst assert = require(\\\"node:assert\\\");\nconst { multiply } = require(\\\"../src/calc\\\");\ntest(\\\"multiply\\\", () => { assert.strictEqual(multiply(3, 4), 12); });\n\" > 'tests/é.test.js'
$GC add 'tests/é.test.js'
$GC commit -qm 'test(red): multiply'
$C_IMPL" "$INIT" "$AGT" "$RES11"
assert_eq "RV3 E11 RED commit with tests/é.test.js alone: a RED commit touches only tests PASS" "PASS" "$(e_state E11 "$K_RED")"
assert_eq "RV3 E11 non-ASCII test name: tests unchanged after the RED commit PASS" "PASS" "$(e_state E11 "$K_UNCH")"
assert_eq "RV3 E11 non-ASCII test name: multiply(3,4) === 12 PASS" "PASS" "$(e_state E11 "$K_MUL")"
assert_eq "RV3 E11 non-ASCII test name: no FAIL line" "0" "$(count_lines E11 FAIL)"


# ---- v0.24.0 R1: E1, E15 and E19 accept the Quick weight ----
# E1: the final reply names the weight as a word: Full, Lite or Quick (check text "reply states the weight").
# E15: passes with Lite + "no independent review", or with `Weight: Quick`; the weight check is read from the final reply
#      (not the whole log); the "Playbook feedback line" check applies to a reply that states Lite or Full, not to a Quick one.
# E19: the "Playbook feedback line" check is conditional in the same way.
# A plain-text log (no stream-json result line) keeps the old behaviour (E15: the weight is read from the log, feedback MANUAL).
echo "v0.24.0 R1 E1: the reply states Full, Lite or Quick"
E1_FIX='printf "function subtract(a, b) { return a - b; }\nmodule.exports.subtract = subtract;\n" >> src/calc.js
printf "const test = require(\"node:test\");\nconst assert = require(\"node:assert\");\nconst { subtract } = require(\"../src/calc\");\ntest(\"subtract\", () => { assert.strictEqual(subtract(5, 3), 2); });\n" > tests/subtract.test.js'
K_WT='states the weight'
run_x E1 wlite "$E1_FIX" "$INIT" "$(res 'Weight: Lite (additive). Added subtract with a test.')"
assert_eq "R1 E1 reply 'Weight: Lite': PASS" "PASS" "$(e_state E1 "$K_WT")"
assert_eq "R1 E1 Lite run: no FAIL line" "0" "$(count_lines E1 FAIL)"
run_x E1 wfull "$E1_FIX" "$INIT" "$(res 'Weight: Full. Added subtract with a test.')"
assert_eq "R1 E1 reply 'Weight: Full': PASS" "PASS" "$(e_state E1 "$K_WT")"
run_x E1 wquick "$E1_FIX" "$INIT" "$(res 'Weight: Quick (one file, 3 lines). Added subtract with a test.')"
assert_eq "R1 E1 reply 'Weight: Quick': PASS" "PASS" "$(e_state E1 "$K_WT")"
assert_eq "R1 E1 Quick run: no FAIL line" "0" "$(count_lines E1 FAIL)"
assert_rc "R1 E1 Quick run: exit 0" 0
run_x E1 wnone "$E1_FIX" "$INIT" "$(res 'Added subtract with a test.')"
assert_eq "R1 E1 reply without a weight: FAIL" "FAIL" "$(e_state E1 "$K_WT")"
run_x E1 wquickly "$E1_FIX" "$INIT" "$(res 'Quickly added subtract with a test.')"
assert_eq "R1 E1 'Quickly' is not the word Quick: FAIL" "FAIL" "$(e_state E1 "$K_WT")"
run_x E1 wexempt "$E1_FIX" "$INIT" "$(res 'Weight: Exempt. Added subtract.')"
assert_eq "R1 E1 'Exempt' is not a weight for a code change: FAIL" "FAIL" "$(e_state E1 "$K_WT")"

echo "v0.24.0 R1 E15: Lite with 'no independent review', or Weight: Quick; the weight is read from the reply"
LITE_OK='Weight: Lite (one-line reversible fix), no independent review. Fixed the typo and added a test.'
run_x E15 qlite "$E15_FIX" "$INIT" "$SKT" "$(res "$LITE_OK Playbook feedback: none")"
assert_eq "R1 E15 Lite + no independent review + feedback line: no FAIL line" "0" "$(count_lines E15 FAIL)"
assert_rc "R1 E15 Lite + no independent review: exit 0" 0
run_x E15 qlitecase "$E15_FIX" "$INIT" "$SKT" "$(res 'weight: lite, No Independent Review. Fixed the typo and added a test. Playbook feedback: none')"
assert_eq "R1 E15 the wording is matched case-insensitively: no FAIL line" "0" "$(count_lines E15 FAIL)"
run_x E15 qquick "$E15_FIX" "$INIT" "$SKT" "$(res 'Weight: Quick. Understanding: one typo. Change: src/calc.js:3. Evidence: test red then green. Not checked: nothing.')"
assert_eq "R1 E15 Weight: Quick without a Playbook feedback line: no FAIL line at all" "0" "$(count_lines E15 FAIL)"
assert_rc "R1 E15 Weight: Quick without a feedback line: exit 0" 0
assert_eq "R1 E15 Quick: the feedback check is not a FAIL" "0" "$(printf '%s\n' "$OUT" | grep '^E15 FAIL ' | grep -c 'Playbook feedback')"
run_x E15 qquickur "$E15_FIX" "$INIT" "$SKT" "$(res 'Weight: Quick (user-requested). Fixed the typo and added a test.')"
assert_eq "R1 E15 Weight: Quick (user-requested): no FAIL line" "0" "$(count_lines E15 FAIL)"
run_x E15 qquickfb "$E15_FIX" "$INIT" "$SKT" "$(res 'Weight: Quick. Fixed the typo and added a test. Playbook feedback: none')"
assert_eq "R1 E15 Quick with a feedback line anyway: no FAIL line" "0" "$(count_lines E15 FAIL)"
run_x E15 qlitenorev "$E15_FIX" "$INIT" "$SKT" "$(res 'Weight: Lite (one-line reversible fix). Fixed the typo and added a test. Playbook feedback: none')"
assert_eq "R1 E15 Lite without 'no independent review': exactly one FAIL" "1" "$(count_lines E15 FAIL)"
if printf '%s\n' "$OUT" | grep '^E15 FAIL ' | grep -qi 'weight'; then t_ok "R1 E15 Lite without 'no independent review': the FAIL line is the weight check"; else t_bad "R1 E15 Lite without 'no independent review': the FAIL line is the weight check" "$OUT"; fi
assert_rc "R1 E15 Lite without 'no independent review': exit 1" 1
run_x E15 qlitenofb "$E15_FIX" "$INIT" "$SKT" "$(res "$LITE_OK")"
assert_eq "R1 E15 Lite (reviewless) without a feedback line: the feedback check FAILs" "FAIL" "$(e_state E15 "$FBK")"
assert_eq "R1 E15 Lite without a feedback line: it is the only FAIL" "1" "$(count_lines E15 FAIL)"
echo "v0.24.2 review round 2 F2: E15 bold weights"
run_x E15 qboldquick "$E15_FIX" "$INIT" "$SKT" "$(res 'Weight: **Quick**. Fixed the typo and added a test.')"
assert_eq "R2 F2 E15 Weight: **Quick** without a feedback line: no FAIL line" "0" "$(count_lines E15 FAIL)"
run_x E15 qboldlite "$E15_FIX" "$INIT" "$SKT" "$(res 'Weight: **Lite** (one-line reversible fix), no independent review. Fixed the typo and added a test.')"
assert_eq "R2 F2 E15 Weight: **Lite** without a feedback line: the feedback check FAILs" "FAIL" "$(e_state E15 "$FBK")"
run_x E15 qboldlitefb "$E15_FIX" "$INIT" "$SKT" "$(res 'Weight: **Lite** (one-line reversible fix), no independent review. Fixed the typo and added a test. Playbook feedback: none')"
assert_eq "R2 F2 E15 Weight: **Lite** with no independent review and a feedback line: no FAIL line" "0" "$(count_lines E15 FAIL)"
run_x E15 qfull "$E15_FIX" "$INIT" "$SKT" "$(res 'Weight: Full. Fixed the typo and added a test. Playbook feedback: none')"
if printf '%s\n' "$OUT" | grep '^E15 FAIL ' | grep -qi 'weight'; then t_ok "R1 E15 Weight: Full for a typo fix: the weight check FAILs"; else t_bad "R1 E15 Weight: Full for a typo fix: the weight check FAILs" "$OUT"; fi
run_x E15 qnone "$E15_FIX" "$INIT" "$SKT" "$(res 'Fixed the typo and added a test.')"
if printf '%s\n' "$OUT" | grep '^E15 FAIL ' | grep -qi 'weight'; then t_ok "R1 E15 a reply with no weight: the weight check FAILs"; else t_bad "R1 E15 a reply with no weight: the weight check FAILs" "$OUT"; fi
# the reply, not the whole log: Lite + "no independent review" only in an assistant message does not count
TXT='{"type":"assistant","message":{"content":[{"type":"text","text":"Weight: Lite - no independent review (said in the log only)"}]}}'
run_x E15 qlogonly "$E15_FIX" "$INIT" "$SKT" "$TXT" "$(res 'Fixed the typo and added a test. Playbook feedback: none')"
if printf '%s\n' "$OUT" | grep '^E15 FAIL ' | grep -qi 'weight'; then t_ok "R1 E15 the weight is read from the final reply, not the whole log: FAIL"; else t_bad "R1 E15 the weight is read from the final reply, not the whole log: FAIL" "$OUT"; fi
# Quick said only in the log does not exempt the feedback line either
run_x E15 qlogquick "$E15_FIX" "$INIT" "$SKT" "$TXT" "$(res 'Weight: Lite, no independent review. Fixed the typo and added a test.')"
assert_eq "R1 E15 Lite reply without the line: FAIL even when the log says something else" "FAIL" "$(e_state E15 "$FBK")"
# Quick does not excuse the other checks
run_x E15 qquickbad "node -e 'true'" "$INIT" "$SKT" "$(res 'Weight: Quick. Fixed it.')"
assert_rc "R1 E15 Weight: Quick but the typo is not fixed: exit 1" 1
if printf '%s\n' "$OUT" | grep '^E15 FAIL ' | grep -q 'numbers'; then t_ok "R1 E15 Quick: the file checks still FAIL"; else t_bad "R1 E15 Quick: the file checks still FAIL" "$OUT"; fi
run_x E15 qquickns "$E15_FIX" "$INIT" "$(res 'Weight: Quick. Fixed the typo and added a test.')"
if printf '%s\n' "$OUT" | grep '^E15 FAIL ' | grep -qiE 'skill|playbook-tdd'; then t_ok "R1 E15 Quick without loading the skill: the skill-load check still FAILs"; else t_bad "R1 E15 Quick without loading the skill: the skill-load check still FAILs" "$OUT"; fi
# plain text keeps the old reading (the log): Lite in the log passes, the feedback line is MANUAL
run_x E15 qplain "$E15_FIX
echo 'Skill(playbook-tdd) loaded'
echo 'Weight: Lite, no independent review'"
assert_eq "R1 E15 plain-text transcript: the feedback check stays MANUAL" "MANUAL" "$(e_state E15 "$FBK")"
assert_eq "R1 E15 plain-text transcript stating Lite: no FAIL line" "0" "$(count_lines E15 FAIL)"

echo "v0.24.0 R1 E19: the Playbook feedback line applies to a Lite or Full reply, not to a Quick one"
run_x E19 qquick "$MUL_OK" "$INIT" "$SKT" "$WTEST" "$(res 'Weight: Quick. Loaded playbook-tdd, then added multiply with a test.')"
assert_eq "R1 E19 Weight: Quick without a feedback line: no FAIL line" "0" "$(count_lines E19 FAIL)"
assert_rc "R1 E19 Weight: Quick without a feedback line: exit 0" 0
assert_eq "R1 E19 Quick: the feedback check is not a FAIL" "0" "$(printf '%s\n' "$OUT" | grep '^E19 FAIL ' | grep -c 'Playbook feedback')"
run_x E19 qquickfb "$MUL_OK" "$INIT" "$SKT" "$WTEST" "$(res 'Weight: Quick. Loaded playbook-tdd, then added multiply. Playbook feedback: none')"
assert_eq "R1 E19 Quick with a feedback line: no FAIL line" "0" "$(count_lines E19 FAIL)"
run_x E19 qlite "$MUL_OK" "$INIT" "$SKT" "$WTEST" "$(res 'Weight: Lite. Loaded playbook-tdd, then added multiply with a test.')"
assert_eq "R1 E19 Lite without a feedback line: FAIL" "FAIL" "$(e_state E19 "$FBK")"
run_x E19 qfull "$MUL_OK" "$INIT" "$SKT" "$WTEST" "$(res 'Weight: Full. Loaded playbook-tdd, then added multiply with a test.')"
assert_eq "R1 E19 Full without a feedback line: FAIL" "FAIL" "$(e_state E19 "$FBK")"
run_x E19 qesc "$MUL_OK" "$INIT" "$SKT" "$WTEST" "$(res 'Weight: Lite (escalated from Quick, over the size limit). Loaded playbook-tdd, then added multiply.')"
assert_eq "R1 E19 escalated from Quick to Lite, no feedback line: FAIL (the reply states Lite)" "FAIL" "$(e_state E19 "$FBK")"
run_x E19 qlitefb "$MUL_OK" "$INIT" "$SKT" "$WTEST" "$(res 'Weight: Lite. Loaded playbook-tdd, then added multiply. Playbook feedback: none')"
assert_eq "R1 E19 Lite with a feedback line: no FAIL line" "0" "$(count_lines E19 FAIL)"


echo "v0.24.0 review round 2 F3: the Quick exemption is not cancelled by the word full or lite elsewhere in the reply"
run_x E15 f3quickfull "$E15_FIX" "$INIT" "$SKT" "$(res 'Weight: Quick. Fixed the typo and ran the full test suite, it is green.')"
assert_eq "F3 E15 Weight: Quick + 'full test suite', no feedback line: no FAIL line" "0" "$(count_lines E15 FAIL)"
assert_eq "F3 E15 Weight: Quick + 'full': the feedback check is not a FAIL" "0" "$(printf '%s\n' "$OUT" | grep '^E15 FAIL ' | grep -c 'Playbook feedback')"
run_x E15 f3quicklite "$E15_FIX" "$INIT" "$SKT" "$(res 'weight: quick. Fixed the typo; a lite change, nothing else touched.')"
assert_eq "F3 E15 weight: quick + the word lite elsewhere, no feedback line: no FAIL line" "0" "$(count_lines E15 FAIL)"
run_x E15 f3lite "$E15_FIX" "$INIT" "$SKT" "$(res 'Weight: Lite, no independent review. Fixed the typo and added a test.')"
assert_eq "F3 E15 Weight: Lite without a feedback line: FAIL" "FAIL" "$(e_state E15 "$FBK")"
run_x E19 f3quickfull "$MUL_OK" "$INIT" "$SKT" "$WTEST" "$(res 'Weight: Quick. Loaded playbook-tdd, added multiply, ran the full test suite.')"
assert_eq "F3 E19 Weight: Quick + 'full test suite', no feedback line: no FAIL line" "0" "$(count_lines E19 FAIL)"
assert_eq "F3 E19 Weight: Quick + 'full': the feedback check is not a FAIL" "0" "$(printf '%s\n' "$OUT" | grep '^E19 FAIL ' | grep -c 'Playbook feedback')"
run_x E19 f3lite "$MUL_OK" "$INIT" "$SKT" "$WTEST" "$(res 'Weight: Lite. Loaded playbook-tdd, then added multiply with a test.')"
assert_eq "F3 E19 Weight: Lite without a feedback line: FAIL" "FAIL" "$(e_state E19 "$FBK")"
run_x E19 f3quickfullw "$MUL_OK" "$INIT" "$SKT" "$WTEST" "$(res 'Weight: Full. Loaded playbook-tdd, quick look, then added multiply.')"
assert_eq "F3 E19 Weight: Full + the word quick elsewhere, no feedback line: FAIL" "FAIL" "$(e_state E19 "$FBK")"
t_summary
