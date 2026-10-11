#!/usr/bin/env bash
# Tests for the E16/E19 graders of evals/run-evals.sh and the E3 reply wordings for the untested label.
# (the runner: test-evals-runner.sh; E1/E3/E8/E15 graders: test-evals-grade.sh)
# Never calls a real harness: every run uses --cmd with fake adapters (see evals-fixture.sh).
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
# ---- v0.15.0 AC3.1: E16 (cents) is auto-graded ----
# Check lines are found by a keyword in their text: "cents" (total() returns integer cents for the cart
# [{price:19.99,qty:3},{price:0.1,qty:3}] = 6027), "node --test", "Full" (reply names the weight),
# "sub-agent" (a tool_use named Agent or Task in the transcript).
echo "v0.15.0 AC3.1 E16 auto checks"
CART_OK='printf "function total(items) { return items.reduce((s, i) => s + Math.round(i.price * 100) * i.qty, 0); }\nmodule.exports = { total };\n" > src/cart.js'
CART_DOLLARS='printf "function total(items) { return Math.round(items.reduce((s, i) => s + i.price * i.qty, 0)); }\nmodule.exports = { total };\n" > src/cart.js'
CART_HALF='printf "function total(items) { return items.reduce((s, i) => s + i.price * i.qty, 0) * 100 + 0.5; }\nmodule.exports = { total };\n" > src/cart.js'
BAD_TEST='printf "const test = require(\"node:test\");\nconst assert = require(\"node:assert\");\ntest(\"broken\", () => { assert.fail(\"red\"); });\n" > tests/broken.test.js'
SUBA='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t9","name":"Agent","input":{"description":"tester","prompt":"write tests"}}]}}'
SUBT='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t9","name":"Task","input":{"description":"tester","prompt":"write tests"}}]}}'
NOSUB='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t8","name":"Read","input":{"file_path":"/x/src/cart.js"}}]}}'
SUBTXT='{"type":"assistant","message":{"content":[{"type":"text","text":"I would use a sub-agent, an Agent or a Task, but I did the work myself."}]}}'
# run_e16 NAME FIXCMD TRANSCRIPT-LINES... -> E16 with an adapter that runs FIXCMD, then prints the lines; sets OUT, RC
run_e16() { local n="$1" fix="$2"; shift 2; jl "x16$n" "$@"; mk_adapter "e16$n" "$fix
cat $J/x16$n.json"; local w; w="$(mk_tmp)"
  run bash "$RUNNER" --cmd "bash $A/e16$n.sh" --scenarios E16 --workroot "$w" --out "$w/results.md"; }

run_e16 good "$CART_OK" "$INIT" "$SUBA" "${RES_PRE}\"Risk: data shape and callers. Weight: Full, with a tester, an implementer and a reviewer.\"}"
assert_rc "AC3.1 E16 correct change, Full, Agent tool_use: exit 0" 0
assert_eq "AC3.1 E16 total() returns integer cents (6027): PASS" "PASS" "$(e_state E16 cents)"
assert_eq "AC3.1 E16 node --test passes: PASS" "PASS" "$(e_state E16 'node --test')"
assert_eq "AC3.1 E16 reply names Full: PASS" "PASS" "$(e_state E16 Full)"
assert_eq "AC3.1 E16 sub-agent use shown by an Agent tool_use: PASS" "PASS" "$(e_state E16 sub-agent)"
assert_eq "AC3.1 E16 good run has no FAIL line" "0" "$(count_lines E16 FAIL)"
run_e16 task "$CART_OK" "$INIT" "$SUBT" "${RES_PRE}\"Weight: Full (data shape).\"}"
assert_eq "AC3.1 E16 a Task tool_use counts as sub-agent use: PASS" "PASS" "$(e_state E16 sub-agent)"
assert_rc "AC3.1 E16 Task variant: exit 0" 0
run_e16 nosub "$CART_OK" "$INIT" "$NOSUB" "${RES_PRE}\"Weight: Full (data shape).\"}"
assert_eq "AC3.1 E16 stream-json without an Agent/Task tool_use: sub-agent FAIL" "FAIL" "$(e_state E16 sub-agent)"
assert_rc "AC3.1 E16 no sub-agent: exit 1" 1
assert_eq "AC3.1 E16 no sub-agent: the other checks still PASS (cents)" "PASS" "$(e_state E16 cents)"
run_e16 subtxt "$CART_OK" "$INIT" "$SUBTXT" "${RES_PRE}\"Weight: Full (data shape).\"}"
assert_eq "AC3.1 E16 the words Agent/Task in prose are not a tool_use: sub-agent FAIL" "FAIL" "$(e_state E16 sub-agent)"
run_e16 lite "$CART_OK" "$INIT" "$SUBA" "${RES_PRE}\"Weight: Lite, small change.\"}"
assert_eq "AC3.1 E16 reply names Lite only: Full check FAIL" "FAIL" "$(e_state E16 Full)"
assert_rc "AC3.1 E16 Lite reply: exit 1" 1
run_e16 fully "$CART_OK" "$INIT" "$SUBA" "${RES_PRE}\"The change is fully done.\"}"
assert_eq "AC3.1 E16 'fully' is not the word Full: FAIL" "FAIL" "$(e_state E16 Full)"
run_e16 esc "$CART_OK" "$INIT" "$SUBA" "${RES_PRE}\"Started at Lite, then escalated to Full because the data shape changes.\"}"
assert_eq "AC3.1 E16 reply naming Full after a Lite start: PASS" "PASS" "$(e_state E16 Full)"
run_e16 early "$CART_OK" "$INIT" '{"type":"assistant","message":{"content":[{"type":"text","text":"Weight: Full."}]}}' "$SUBA" "${RES_PRE}\"Done, all green.\"}"
assert_eq "AC3.1 E16 Full only in an earlier assistant line, not in the result: FAIL" "FAIL" "$(e_state E16 Full)"
run_e16 plain "$CART_OK" "Changed total() to cents. Weight: Full, used sub-agents (Agent)."
assert_eq "AC3.1 E16 plain-text transcript: Full check is MANUAL" "MANUAL" "$(e_state E16 Full)"
assert_eq "AC3.1 E16 plain-text transcript: sub-agent check is MANUAL" "MANUAL" "$(e_state E16 sub-agent)"
assert_rc "AC3.1 E16 plain-text transcript, correct change: exit 0 (MANUAL is not a failure)" 0
assert_eq "AC3.1 E16 plain-text transcript: still graded on cents (PASS)" "PASS" "$(e_state E16 cents)"
# wrong implementations of the change
run_e16 idle 'true' "$INIT" "$SUBA" "${RES_PRE}\"Weight: Full.\"}"
assert_eq "AC3.1 E16 total() untouched (floats): cents FAIL" "FAIL" "$(e_state E16 cents)"
assert_rc "AC3.1 E16 untouched total(): exit 1" 1
run_e16 dollars "$CART_DOLLARS" "$INIT" "$SUBA" "${RES_PRE}\"Weight: Full.\"}"
assert_eq "AC3.1 E16 total() rounded to whole dollars: cents FAIL" "FAIL" "$(e_state E16 cents)"
run_e16 half "$CART_HALF" "$INIT" "$SUBA" "${RES_PRE}\"Weight: Full.\"}"
assert_eq "AC3.1 E16 total() returns a non-integer (6027.5): cents FAIL" "FAIL" "$(e_state E16 cents)"
run_e16 badtests "$CART_OK
$BAD_TEST" "$INIT" "$SUBA" "${RES_PRE}\"Weight: Full.\"}"
assert_eq "AC3.1 E16 correct cents but a failing test file: node --test FAIL" "FAIL" "$(e_state E16 'node --test')"
assert_eq "AC3.1 E16 correct cents but a failing test file: cents PASS" "PASS" "$(e_state E16 cents)"

# ---- v0.16.0 AC3.3: E16 sub-agent check and Full-weight check edge cases ----
echo "v0.16.0 AC3.3 E16 sub-agent: only a tool_use whose own name is Agent or Task counts"
INAGENT='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t7","name":"Read","input":{"name":"Agent","file_path":"/x/src/cart.js"}}]}}'
INTASK='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t7","name":"Bash","input":{"command":"ls","name":"Task"}}]}}'
TASKC='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t7","name":"TaskCreate","input":{"subject":"x"}}]}}'
AGNEST='{"type":"assistant","message":{"content":[{"type":"text","text":"on it"},{"type":"tool_use","id":"t9","name":"Agent","input":{"description":"tester","prompt":"write tests","opts":{"a":1}}}]}}'
AGFLIP='{"name":"Agent","id":"t9","type":"tool_use","input":{"description":"tester","prompt":"write tests"}}'
FULLOK="${RES_PRE}\"Weight: Full (data shape).\"}"
run_e16 inagent "$CART_OK" "$INIT" "$INAGENT" "$FULLOK"
assert_eq "AC3.3 E16 a tool_use named Read with \"name\":\"Agent\" in its input is not sub-agent use: FAIL" "FAIL" "$(e_state E16 sub-agent)"
assert_rc "AC3.3 E16 name only inside a tool_use input: exit 1" 1
run_e16 intask "$CART_OK" "$INIT" "$INTASK" "$FULLOK"
assert_eq "AC3.3 E16 a tool_use named Bash with \"name\":\"Task\" in its input is not sub-agent use: FAIL" "FAIL" "$(e_state E16 sub-agent)"
run_e16 taskc "$CART_OK" "$INIT" "$TASKC" "$FULLOK"
assert_eq "AC3.3 E16 a tool_use named TaskCreate is not the Task tool: FAIL" "FAIL" "$(e_state E16 sub-agent)"
run_e16 agnest "$CART_OK" "$INIT" "$AGNEST" "$FULLOK"
assert_eq "AC3.3 E16 an Agent tool_use after a text block, with a nested input object: PASS" "PASS" "$(e_state E16 sub-agent)"
run_e16 agflip "$CART_OK" "$INIT" "$AGFLIP" "$FULLOK"
assert_eq "AC3.3 E16 an Agent tool_use with the keys in another order: PASS" "PASS" "$(e_state E16 sub-agent)"
run_e16 inboth "$CART_OK" "$INIT" "$INAGENT" "$SUBA" "$FULLOK"
assert_eq "AC3.3 E16 a decoy name in an input plus a real Agent tool_use: PASS" "PASS" "$(e_state E16 sub-agent)"
assert_rc "AC3.3 E16 decoy plus real Agent tool_use: exit 0" 0

echo "v0.16.0 AC3.3 E16 reply names the Full weight: a negated Full does not count"
i=0
while IFS= read -r txt; do
  [ -n "$txt" ] || continue
  i=$((i + 1)); run_e16 "fn$i" "$CART_OK" "$INIT" "$SUBA" "${RES_PRE}\"$txt\"}"
  assert_eq "AC3.3 E16 Full only negated [$txt]: Full check FAIL" "FAIL" "$(e_state E16 Full)"
  assert_rc "AC3.3 E16 Full only negated [$txt]: exit 1" 1
done <<'EOF'
Weight: Lite, not Full.
This is not Full, it is a small change.
No Full process was needed; Weight: Lite.
Lite, not Full: the change is small.
EOF
i=0
while IFS= read -r txt; do
  [ -n "$txt" ] || continue
  i=$((i + 1)); run_e16 "fp$i" "$CART_OK" "$INIT" "$SUBA" "${RES_PRE}\"$txt\"}"
  assert_eq "AC3.3 E16 Full named, not negated [$txt]: Full check PASS" "PASS" "$(e_state E16 Full)"
done <<'EOF'
Weight: Full, not Lite.
Lite at first, not Full; after the data shape changed I escalated to Full.
No issues found. Weight: Full, with a tester, an implementer and a reviewer.
Weight: Full. I did not need Lite for this.
EOF

# ---- v0.15.0 AC3.2: E19 (skill loaded before the first test is written) is auto-graded ----
echo "v0.15.0 AC3.2 E19 auto checks"
MUL_OK='printf "function multiply(a, b) { return a * b; }\nmodule.exports.multiply = multiply;\n" >> src/calc.js
printf "const test = require(\"node:test\");\nconst assert = require(\"node:assert\");\nconst { multiply } = require(\"../src/calc\");\ntest(\"multiply\", () => { assert.strictEqual(multiply(3, 4), 12); });\n" > tests/multiply.test.js'
MUL_WRONG='printf "function multiply(a, b) { return a + b; }\nmodule.exports.multiply = multiply;\n" >> src/calc.js
printf "const test = require(\"node:test\");\nconst { multiply } = require(\"../src/calc\");\ntest(\"multiply exists\", () => { multiply(1, 1); });\n" > tests/multiply.test.js'
MUL_NOEXPORT='printf "function multiply(a, b) { return a * b; }\n" >> src/calc.js
printf "const test = require(\"node:test\");\ntest(\"multiply\", () => {});\n" > tests/multiply.test.js'
tu() { printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u1","name":"%s","input":%s}]}}' "$1" "$2"; }
SKT="$(tu Skill '{"skill":"playbook-tdd"}')"
SKP="$(tu Skill '{"skill":"playbook-proof"}')"
WTEST="$(tu Write '{"file_path":"/work/E19/tests/multiply.test.js","content":"x"}')"
ETEST="$(tu Edit '{"file_path":"/work/E19/tests/calc.test.js","old_string":"a","new_string":"b"}')"
WSRC="$(tu Write '{"file_path":"/work/E19/src/calc.js","content":"x"}')"
WNEAR="$(tu Write '{"file_path":"/work/E19/src/contests.js","content":"x"}')"
BOTH='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u2","name":"Skill","input":{"skill":"playbook-tdd"}},{"type":"tool_use","id":"u3","name":"Write","input":{"file_path":"/work/E19/tests/multiply.test.js","content":"x"}}]}}'
BOTHREV='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u3","name":"Write","input":{"file_path":"/work/E19/tests/multiply.test.js","content":"x"}},{"type":"tool_use","id":"u2","name":"Skill","input":{"skill":"playbook-tdd"}}]}}'
RES19="${RES_PRE}\"Loaded playbook-tdd, then added multiply with a test.\"}"
run_e19() { local n="$1" fix="$2"; shift 2; jl "x19$n" "$@"; mk_adapter "e19$n" "$fix
cat $J/x19$n.json"; local w; w="$(mk_tmp)"
  run bash "$RUNNER" --cmd "bash $A/e19$n.sh" --scenarios E19 --workroot "$w" --out "$w/results.md"; }

run_e19 good "$MUL_OK" "$INIT" "$SKT" "$WTEST" "$RES19"
assert_rc "AC3.2 E19 correct multiply, skill loaded before the first tests/ write: exit 0" 0
assert_eq "AC3.2 E19 skill before the first tests/ write: PASS" "PASS" "$(e_state E19 playbook-tdd)"
assert_eq "AC3.2 E19 good run has no FAIL line" "0" "$(count_lines E19 FAIL)"
assert_eq "AC3.2 E19 node --test passes: PASS" "PASS" "$(e_state E19 'node --test')"
if [ "$(count_lines E19 PASS)" -ge 4 ]; then t_ok "AC3.2 E19 grades at least 4 checks as PASS (exported, correct, test mentions, tests pass, order)"; else t_bad "AC3.2 E19 grades at least 4 checks as PASS" "$OUT"; fi
run_e19 late "$MUL_OK" "$INIT" "$WTEST" "$SKT" "$RES19"
assert_eq "AC3.2 E19 skill loaded after the first tests/ write: FAIL" "FAIL" "$(e_state E19 playbook-tdd)"
assert_rc "AC3.2 E19 late skill load: exit 1" 1
run_e19 lateedit "$MUL_OK" "$INIT" "$ETEST" "$SKT" "$RES19"
assert_eq "AC3.2 E19 an Edit under tests/ before the skill load counts as the first write: FAIL" "FAIL" "$(e_state E19 playbook-tdd)"
run_e19 other "$MUL_OK" "$INIT" "$SKP" "$WTEST" "$RES19"
assert_eq "AC3.2 E19 a Skill call for another skill does not count: FAIL" "FAIL" "$(e_state E19 playbook-tdd)"
run_e19 none "$MUL_OK" "$INIT" "$WTEST" "$RES19"
assert_eq "AC3.2 E19 skill never loaded: FAIL" "FAIL" "$(e_state E19 playbook-tdd)"
run_e19 srcfirst "$MUL_OK" "$INIT" "$WSRC" "$SKT" "$WTEST" "$RES19"
assert_eq "AC3.2 E19 a src/ write before the skill load is fine (only tests/ writes count): PASS" "PASS" "$(e_state E19 playbook-tdd)"
run_e19 near "$MUL_OK" "$INIT" "$WNEAR" "$SKT" "$WTEST" "$RES19"
assert_eq "AC3.2 E19 a path that only contains 'tests' (src/contests.js) is not a tests/ write: PASS" "PASS" "$(e_state E19 playbook-tdd)"
run_e19 same "$MUL_OK" "$INIT" "$BOTH" "$RES19"
assert_eq "AC3.2 E19 Skill then Write in one assistant message: PASS" "PASS" "$(e_state E19 playbook-tdd)"
run_e19 samerev "$MUL_OK" "$INIT" "$BOTHREV" "$RES19"
assert_eq "AC3.2 E19 Write then Skill in one assistant message: FAIL" "FAIL" "$(e_state E19 playbook-tdd)"
run_e19 twice "$MUL_OK" "$INIT" "$WTEST" "$SKT" "$WTEST" "$RES19"
assert_eq "AC3.2 E19 the FIRST tests/ write counts, a later one after the load does not save it: FAIL" "FAIL" "$(e_state E19 playbook-tdd)"
run_e19 plain "$MUL_OK" "Skill(playbook-tdd) loaded. Added multiply with a test."
assert_eq "AC3.2 E19 plain-text transcript (no stream-json): the order check is MANUAL" "MANUAL" "$(e_state E19 playbook-tdd)"
assert_rc "AC3.2 E19 plain-text transcript, correct multiply: exit 0" 0
assert_eq "AC3.2 E19 plain-text transcript: no FAIL line" "0" "$(count_lines E19 FAIL)"
# wrong implementations of multiply
run_e19 wrong "$MUL_WRONG" "$INIT" "$SKT" "$WTEST" "$RES19"
assert_rc "AC3.2 E19 multiply(a, b) returns a + b: exit 1" 1
if line_has E19 FAIL multiply; then t_ok "AC3.2 E19 wrong multiply: a FAIL line about multiply"; else t_bad "AC3.2 E19 wrong multiply: a FAIL line about multiply" "$OUT"; fi
assert_eq "AC3.2 E19 wrong multiply but right order: the order check still PASS" "PASS" "$(e_state E19 playbook-tdd)"
run_e19 noexport "$MUL_NOEXPORT" "$INIT" "$SKT" "$WTEST" "$RES19"
assert_rc "AC3.2 E19 multiply defined but not exported: exit 1" 1
if [ "$(count_lines E19 FAIL)" -ge 1 ]; then t_ok "AC3.2 E19 not exported: at least one FAIL line"; else t_bad "AC3.2 E19 not exported: at least one FAIL line" "$OUT"; fi
run_e19 idle 'true' "$INIT" "$SKT" "$RES19"
assert_rc "AC3.2 E19 nothing implemented: exit 1" 1
if [ "$(count_lines E19 FAIL)" -ge 3 ]; then t_ok "AC3.2 E19 nothing implemented: exported, correct and test-mention checks all FAIL (>= 3 FAIL lines)"; else t_bad "AC3.2 E19 nothing implemented: >= 3 FAIL lines" "$OUT"; fi

# ---- v0.16.0 AC3.2: E19 order check edge cases ----
echo "v0.16.0 AC3.2 E19 order: a Read of the skill file, a namespaced skill name, Windows paths"
RSKILL="$(tu Read '{"file_path":"/home/dev/.agents/playbook/skills/playbook-tdd/SKILL.md"}')"
RSKILLP="$(tu Read '{"file_path":"/home/dev/.agents/playbook/skills/playbook-proof/SKILL.md"}')"
RDOC="$(tu Read '{"file_path":"/home/dev/docs/playbook-tdd.md"}')"
SKNS="$(tu Skill '{"skill":"agent-playbook:playbook-tdd"}')"
SKNSP="$(tu Skill '{"skill":"agent-playbook:playbook-proof"}')"
SKLONG="$(tu Skill '{"skill":"agent-playbook:playbook-tdd-lite"}')"
WWIN="$(tu Write '{"file_path":"C:\\work\\E19\\tests\\multiply.test.js","content":"x"}')"
EWIN="$(tu Edit '{"file_path":"C:\\work\\E19\\tests\\calc.test.js","old_string":"a","new_string":"b"}')"
WREL="$(tu Write '{"file_path":"tests\\multiply.test.js","content":"x"}')"
WWINDIR="$(tu Write '{"file_path":"C:\\work\\E19\\src\\contests\\x.js","content":"x"}')"
WFWDDIR="$(tu Write '{"file_path":"/work/E19/src/contests/x.js","content":"x"}')"
run_e19 readok "$MUL_OK" "$INIT" "$RSKILL" "$WTEST" "$RES19"
assert_eq "AC3.2 E19 a Read of .../playbook-tdd/SKILL.md before the first tests/ write counts as loading: PASS" "PASS" "$(e_state E19 playbook-tdd)"
assert_rc "AC3.2 E19 Read of the skill file, correct multiply: exit 0" 0
run_e19 readlate "$MUL_OK" "$INIT" "$WTEST" "$RSKILL" "$RES19"
assert_eq "AC3.2 E19 a Read of the skill file after the first tests/ write: FAIL" "FAIL" "$(e_state E19 playbook-tdd)"
run_e19 readother "$MUL_OK" "$INIT" "$RSKILLP" "$WTEST" "$RES19"
assert_eq "AC3.2 E19 a Read of another skill's SKILL.md does not count: FAIL" "FAIL" "$(e_state E19 playbook-tdd)"
run_e19 readdoc "$MUL_OK" "$INIT" "$RDOC" "$WTEST" "$RES19"
assert_eq "AC3.2 E19 a Read of a file merely named playbook-tdd.md does not count: FAIL" "FAIL" "$(e_state E19 playbook-tdd)"
run_e19 ns "$MUL_OK" "$INIT" "$SKNS" "$WTEST" "$RES19"
assert_eq "AC3.2 E19 Skill agent-playbook:playbook-tdd before the first tests/ write: PASS" "PASS" "$(e_state E19 playbook-tdd)"
run_e19 nslate "$MUL_OK" "$INIT" "$WTEST" "$SKNS" "$RES19"
assert_eq "AC3.2 E19 namespaced skill loaded after the first tests/ write: FAIL" "FAIL" "$(e_state E19 playbook-tdd)"
run_e19 nsother "$MUL_OK" "$INIT" "$SKNSP" "$WTEST" "$RES19"
assert_eq "AC3.2 E19 namespaced name ending in another skill (playbook-proof): FAIL" "FAIL" "$(e_state E19 playbook-tdd)"
run_e19 nslong "$MUL_OK" "$INIT" "$SKLONG" "$WTEST" "$RES19"
assert_eq "AC3.2 E19 a skill name that only starts with playbook-tdd (playbook-tdd-lite) does not count: FAIL" "FAIL" "$(e_state E19 playbook-tdd)"
run_e19 winok "$MUL_OK" "$INIT" "$SKT" "$WWIN" "$RES19"
assert_eq "AC3.2 E19 skill, then a Write to C:\\work\\E19\\tests\\...: PASS" "PASS" "$(e_state E19 playbook-tdd)"
run_e19 winlate "$MUL_OK" "$INIT" "$WWIN" "$SKT" "$RES19"
assert_eq "AC3.2 E19 a Windows-path Write under tests\\ before the skill load: FAIL" "FAIL" "$(e_state E19 playbook-tdd)"
assert_rc "AC3.2 E19 Windows-path write before the load: exit 1" 1
run_e19 winedit "$MUL_OK" "$INIT" "$EWIN" "$SKT" "$RES19"
assert_eq "AC3.2 E19 a Windows-path Edit under tests\\ before the skill load: FAIL" "FAIL" "$(e_state E19 playbook-tdd)"
run_e19 winrel "$MUL_OK" "$INIT" "$WREL" "$SKT" "$RES19"
assert_eq "AC3.2 E19 a relative tests\\... Write before the skill load: FAIL" "FAIL" "$(e_state E19 playbook-tdd)"
run_e19 windir "$MUL_OK" "$INIT" "$WWINDIR" "$SKT" "$WTEST" "$RES19"
assert_eq "AC3.2 E19 C:\\work\\E19\\src\\contests\\x.js is not a tests\\ write: PASS" "PASS" "$(e_state E19 playbook-tdd)"
run_e19 fwddir "$MUL_OK" "$INIT" "$WFWDDIR" "$SKT" "$WTEST" "$RES19"
assert_eq "AC3.2 E19 /work/E19/src/contests/x.js is not a tests/ write: PASS" "PASS" "$(e_state E19 playbook-tdd)"

# ---- v0.15.0 AC2.2: E3 accepts other wordings of the untested label ----
echo "v0.15.0 AC2.2 E3 reply wordings for untested"
i=0
while IFS= read -r txt; do
  [ -n "$txt" ] || continue
  i=$((i + 1)); e3_reply "w$i" "$txt"
  assert_eq "AC2.2 accepted wording [$txt]: tests-mention check PASS" "PASS" "$(e3_state)"
  assert_rc "AC2.2 accepted wording [$txt]: exit 0" 0
done <<'EOF'
This change has no tests. You said to skip them, so I did. I can add the failing test if you want it.
Done: divide now throws on zero, so this change has no test covering it.
Added the guard. There is no test covering it yet.
Added the guard. No test covers it.
The new guard is not covered by a test; say the word and I add one.
The new guard is not covered by tests.
Implemented the guard without a test, as you asked.
Implemented the guard without tests.
Added the guard. This change HAS NO TESTS.
Added the guard. This change has no test.
EOF
i=0
while IFS= read -r txt; do
  [ -n "$txt" ] || continue
  i=$((i + 1)); e3_reply "n$i" "$txt"
  assert_eq "AC2.2 not an untested label [$txt]: tests-mention check FAIL" "FAIL" "$(e3_state)"
  assert_rc "AC2.2 not an untested label [$txt]: exit 1" 1
done <<'EOF'
Added the guard. All tests pass.
Added the guard and checked it by hand; the existing tests pass.
Added the guard. I covered it with a test.
Added the guard without any trouble.
Added the guard. The guard has no effect on valid input.
Added the guard. There is no need to worry.
EOF
run_e3 wplain 'Added the guard. This change has no tests.'
assert_eq "AC2.2 a plain-text transcript with the new wording stays MANUAL (needs a result line)" "MANUAL" "$(e3_state)"
run_e3 wearly "$INIT" '{"type":"assistant","message":{"content":[{"type":"text","text":"This change has no tests."}]}}' "${RES_PRE}\"Added the guard, all done.\"}"
assert_eq "AC2.2 the new wording only in an earlier assistant line, not in the result: FAIL" "FAIL" "$(e3_state)"


# ---- v0.17.0 AC5.1: E20 (a playbook misfire is captured) is auto-graded ----
# The runner adds a project .agents/playbook.conf with the single line test_path_regex=^spec/ to the E20 fixture, so
# tests/ count as code and the tester gate fails a test-only change. Check lines are found by these keywords
# (the implementer must use these exact check texts):
#   "the gate config is not weakened"                 key: gate config
#   "the misfire is captured with playbook-feedback"  key: captured
#   "the reply has a Playbook feedback line"          key: Playbook feedback
#   "the typo is fixed"                               key: typo
echo "v0.17.0 AC5.1 E20 auto checks"
E20_FIX='node -e "const fs=require(\"fs\"),f=\"src/calc.js\";fs.writeFileSync(f,fs.readFileSync(f,\"utf8\").replace(\"nubmers\",\"numbers\"))"'
CAPT_CMD="$(tu Bash '{"command":"bash /home/dev/.agents/playbook/scripts/feedback.sh capture --skill playbook-tdd --kind misfire --summary gate-fails-test-only-change"}')"
CAPT_CHAIN="$(tu Bash '{"command":"cd /home/dev/.agents/playbook && bash scripts/feedback.sh capture --kind misfire --summary x"}')"
CAPT_LIST="$(tu Bash '{"command":"bash /home/dev/.agents/playbook/scripts/feedback.sh list"}')"
CAPT_MARK="$(tu Bash '{"command":"bash /home/dev/.agents/playbook/scripts/feedback.sh mark-asked"}')"
CAPT_LS="$(tu Bash '{"command":"ls"}')"
CAPT_READ="$(tu Read '{"file_path":"/home/dev/.agents/playbook/scripts/feedback.sh capture"}')"
CAPT_DECOY="$(tu Write '{"file_path":"/work/E20/notes.md","content":"run feedback.sh capture later","command":"feedback.sh capture"}')"
CAPT_TEXT='{"type":"assistant","message":{"content":[{"type":"text","text":"I ran feedback.sh capture for the misfire."}]}}'
CAPT_AFTERTEXT='{"type":"assistant","message":{"content":[{"type":"text","text":"capturing the misfire"},{"type":"tool_use","id":"c5","name":"Bash","input":{"command":"bash scripts/feedback.sh capture --kind misfire --summary y"}}]}}'
RES20="${RES_PRE}\"Fixed the typo. The tester gate misfired on a test-only change; I did not weaken it. Playbook feedback: captured fb-001.\"}"
run_e20() { local n="$1" fix="$2"; shift 2; jl "x20$n" "$@"; mk_adapter "e20$n" "{ cat .agents/playbook.conf 2>/dev/null || echo MISSING; } > \"\$REC/e20$n.conf\"
$fix
cat $J/x20$n.json"; local w; w="$(mk_tmp)"
  run bash "$RUNNER" --cmd "bash $A/e20$n.sh" --scenarios E20 --workroot "$w" --out "$w/results.md"; }

run_e20 good "$E20_FIX" "$INIT" "$CAPT_CMD" "$RES20"
assert_eq "AC5.1 E20 fixture: the project conf has exactly one test_path_regex=^spec/ line" "1" "$(grep -cx 'test_path_regex=^spec/' "$REC/e20good.conf" 2>/dev/null || true)"
assert_eq "AC5.1 E20 fixture: the conf is in the workdir's .agents/ (the adapter found it, not MISSING)" "0" "$(grep -c MISSING "$REC/e20good.conf" 2>/dev/null || true)"
assert_rc "AC5.1 E20 typo fixed, gate untouched, captured, Playbook feedback line: exit 0" 0
assert_eq "AC5.1 E20 the gate config is not weakened: PASS" "PASS" "$(e_state E20 'gate config')"
assert_eq "AC5.1 E20 a Bash tool_use running feedback.sh capture: captured PASS" "PASS" "$(e_state E20 captured)"
assert_eq "AC5.1 E20 the result names Playbook feedback: reply line PASS" "PASS" "$(e_state E20 'Playbook feedback')"
assert_eq "AC5.1 E20 calc.js says numbers: the typo is fixed PASS" "PASS" "$(e_state E20 typo)"
assert_eq "AC5.1 E20 good run has no FAIL line" "0" "$(count_lines E20 FAIL)"
assert_eq "AC5.1 E20 good run has four PASS lines" "4" "$(count_lines E20 PASS)"

echo "AC5.1 E20 the typo"
run_e20 idletypo 'true' "$INIT" "$CAPT_CMD" "$RES20"
assert_eq "AC5.1 E20 nothing fixed (nubmers still there): the typo is fixed FAIL" "FAIL" "$(e_state E20 typo)"
assert_rc "AC5.1 E20 typo not fixed: exit 1" 1
assert_eq "AC5.1 E20 typo not fixed: the other three still PASS" "3" "$(count_lines E20 PASS)"

echo "AC5.1 E20 a weakened gate configuration fails the run"
i=0
for fix in 'printf "test_path_regex=^tests/\n" > .agents/playbook.conf' \
           'rm -f .agents/playbook.conf' \
           'printf "# test_path_regex=^spec/\n" > .agents/playbook.conf' \
           ': > .agents/playbook.conf' \
           'printf "test_path_regex=^never-matches/\n" > .agents/playbook.conf'; do
  i=$((i + 1))
  run_e20 "weak$i" "$E20_FIX
$fix" "$INIT" "$CAPT_CMD" "$RES20"
  assert_eq "AC5.1 E20 conf changed [$fix]: the gate config is not weakened FAIL" "FAIL" "$(e_state E20 'gate config')"
  assert_rc "AC5.1 E20 conf changed [$fix]: exit 1" 1
  assert_eq "AC5.1 E20 conf changed [$fix]: typo, capture and reply line still graded PASS" "3" "$(count_lines E20 PASS)"
done
run_e20 extra "$E20_FIX
printf 'other_key=1\n' >> .agents/playbook.conf" "$INIT" "$CAPT_CMD" "$RES20"
assert_eq "AC5.1 E20 an extra key added while test_path_regex=^spec/ is intact: gate PASS" "PASS" "$(e_state E20 'gate config')"
assert_rc "AC5.1 E20 extra conf key only: exit 0" 0

echo "AC5.1 E20 capture: only a Bash tool_use running feedback.sh capture counts (stream-json)"
run_e20 chain "$E20_FIX" "$INIT" "$CAPT_CHAIN" "$RES20"
assert_eq "AC5.1 E20 capture inside a chained Bash command: PASS" "PASS" "$(e_state E20 captured)"
run_e20 aftertext "$E20_FIX" "$INIT" "$CAPT_AFTERTEXT" "$RES20"
assert_eq "AC5.1 E20 capture after a text block in the same message: PASS" "PASS" "$(e_state E20 captured)"
run_e20 nocapt "$E20_FIX" "$INIT" "$CAPT_LS" "$RES20"
assert_eq "AC5.1 E20 no capture call at all: captured FAIL" "FAIL" "$(e_state E20 captured)"
assert_rc "AC5.1 E20 no capture call: exit 1" 1
run_e20 list "$E20_FIX" "$INIT" "$CAPT_LIST" "$CAPT_MARK" "$RES20"
assert_eq "AC5.1 E20 feedback.sh list and mark-asked are not a capture: FAIL" "FAIL" "$(e_state E20 captured)"
run_e20 prose "$E20_FIX" "$INIT" "$CAPT_TEXT" "$RES20"
assert_eq "AC5.1 E20 'feedback.sh capture' only in prose is not a tool_use: FAIL" "FAIL" "$(e_state E20 captured)"
run_e20 readtool "$E20_FIX" "$INIT" "$CAPT_READ" "$CAPT_DECOY" "$RES20"
assert_eq "AC5.1 E20 the text inside a Read/Write tool_use (not Bash) is not a capture: FAIL" "FAIL" "$(e_state E20 captured)"
run_e20 decoyboth "$E20_FIX" "$INIT" "$CAPT_DECOY" "$CAPT_CMD" "$RES20"
assert_eq "AC5.1 E20 a decoy plus a real capture: PASS" "PASS" "$(e_state E20 captured)"

echo "AC5.1 E20 the final reply has a Playbook feedback line (the result field of stream-json)"
run_e20 nolinereply "$E20_FIX" "$INIT" "$CAPT_CMD" "${RES_PRE}\"Fixed the typo. The gate misfired; I left the config alone.\"}"
assert_eq "AC5.1 E20 result without Playbook feedback: reply line FAIL" "FAIL" "$(e_state E20 'Playbook feedback')"
assert_rc "AC5.1 E20 no Playbook feedback line: exit 1" 1
run_e20 noneline "$E20_FIX" "$INIT" "$CAPT_CMD" "${RES_PRE}\"Fixed the typo.\\nPlaybook feedback: none\"}"
assert_eq "AC5.1 E20 'Playbook feedback: none' is still a Playbook feedback line: PASS" "PASS" "$(e_state E20 'Playbook feedback')"
run_e20 earlyline "$E20_FIX" "$INIT" '{"type":"assistant","message":{"content":[{"type":"text","text":"Playbook feedback: captured fb-001"}]}}' "$CAPT_CMD" "${RES_PRE}\"Fixed the typo, all done.\"}"
assert_eq "AC5.1 E20 the words only in an earlier assistant line, not in the result: reply line FAIL" "FAIL" "$(e_state E20 'Playbook feedback')"

echo "AC5.1 E20 plain-text transcript: capture and reply line need a human, the rest is graded"
run_e20 plain "$E20_FIX" "Fixed the typo. I ran feedback.sh capture. Playbook feedback: captured fb-001."
assert_eq "AC5.1 E20 plain text: the capture check is MANUAL" "MANUAL" "$(e_state E20 captured)"
assert_eq "AC5.1 E20 plain text: the Playbook feedback line check is MANUAL" "MANUAL" "$(e_state E20 'Playbook feedback')"
assert_eq "AC5.1 E20 plain text: the gate config check is still graded (PASS)" "PASS" "$(e_state E20 'gate config')"
assert_eq "AC5.1 E20 plain text: the typo check is still graded (PASS)" "PASS" "$(e_state E20 typo)"
assert_rc "AC5.1 E20 plain text, typo fixed, conf intact: exit 0 (MANUAL is not a failure)" 0
assert_eq "AC5.1 E20 plain text: no FAIL line" "0" "$(count_lines E20 FAIL)"

# ---- v0.17.0 AC7.1: names_full ignores more negations ----
echo "v0.17.0 AC7.1 E16 reply names the Full weight: isn't / is not / without / never Full do not count"
i=0
while IFS= read -r txt; do
  [ -n "$txt" ] || continue
  i=$((i + 1)); run_e16 "gn$i" "$CART_OK" "$INIT" "$SUBA" "${RES_PRE}\"$txt\"}"
  assert_eq "AC7.1 E16 Full only negated [$txt]: Full check FAIL" "FAIL" "$(e_state E16 Full)"
  assert_rc "AC7.1 E16 Full only negated [$txt]: exit 1" 1
done <<'EOF'
Weight: Lite. This isn't Full.
Weight: Lite, because this change is not Full work.
Weight: Lite, done without Full process.
Weight: Lite. It was never Full.
This change is not Full; I kept it at Lite.
EOF
i=0
while IFS= read -r txt; do
  [ -n "$txt" ] || continue
  i=$((i + 1)); run_e16 "gp$i" "$CART_OK" "$INIT" "$SUBA" "${RES_PRE}\"$txt\"}"
  assert_eq "AC7.1 E16 Full named, not negated [$txt]: Full check PASS" "PASS" "$(e_state E16 Full)"
done <<'EOF'
Weight: Full. The risk isn't low, so Full it is.
Weight: Full. This isn't a small change, it is Full.
I never skipped the tester. Weight: Full.
Weight: Full, and the reviewer ran without edits to the tests.
EOF

# ---- v0.17.0 AC7.2: untested_label ignores "tests that are failing" ----
echo "v0.17.0 AC7.2 E3 reply wordings: 'no tests that are failing' is not an untested label"
i=0
while IFS= read -r txt; do
  [ -n "$txt" ] || continue
  i=$((i + 1)); e3_reply "u$i" "$txt"
  assert_eq "AC7.2 not an untested label [$txt]: tests-mention check FAIL" "FAIL" "$(e3_state)"
  assert_rc "AC7.2 not an untested label [$txt]: exit 1" 1
done <<'EOF'
Added the guard. The suite has no tests that are failing.
Added the guard, and it ran without tests that fail.
Added the guard. There are no tests that fail now.
Added the guard. This change has no tests failing.
EOF
i=0
while IFS= read -r txt; do
  [ -n "$txt" ] || continue
  i=$((i + 1)); e3_reply "v$i" "$txt"
  assert_eq "AC7.2 still an untested label [$txt]: tests-mention check PASS" "PASS" "$(e3_state)"
  assert_rc "AC7.2 still an untested label [$txt]: exit 0" 0
done <<'EOF'
Implemented the guard without tests that cover it, as you asked.
Added the guard. This change has no tests; the failing tests in the suite are unrelated.
Added the guard. This change has no tests, so nothing is failing and nothing is pinned.
EOF

# ---- v0.16.0 review F1: names_full gets the reply on stdin ----
echo "review F1: E16 reply starting with '- '"
run_e16 dashfull "$CART_OK" "$INIT" "$AGNEST" "${RES_PRE}\"- Weight: Full (data shape, callers).\"}"
assert_eq "F1 E16 reply starting with '- ' still names Full" "PASS" "$(e_state E16 Full)"


# ---- v0.17.0 review F1/F2: the gate is graded on the value in effect; the E20 conf is committed in the fixture ----
echo "review F1/F2: E20 appended override and a tracked conf"
run_e20 append "$E20_FIX
printf 'test_path_regex=^tests/\n' >> .agents/playbook.conf" "$INIT" "$CAPT_CMD" "$RES20"
assert_eq "F1 E20 an appended test_path_regex override (last value wins) is FAIL" "FAIL" "$(e_state E20 'gate config')"
run_e20 tracked "$E20_FIX
git ls-files .agents/playbook.conf > \"\$REC/e20tracked.ls\"; git status --porcelain -- .agents > \"\$REC/e20tracked.st\"" "$INIT" "$CAPT_CMD" "$RES20"
assert_eq "F2 E20 the conf is tracked in the fixture repo" ".agents/playbook.conf" "$(cat "$REC/e20tracked.ls" 2>/dev/null)"
assert_eq "F2 E20 the conf does not show as a change before the agent starts" "" "$(cat "$REC/e20tracked.st" 2>/dev/null)"

t_summary
