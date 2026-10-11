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
# v0.18.0 AC3.1: E20 runs against a throw-away playbook home (PLAYBOOK_HOME=<workroot>/E20.home). The adapter really runs
# scripts/feedback.sh capture (REAL_CAPT) unless E20_NOREAL=1, so the new check "a feedback item was written" can pass.
# Every E20 run gets a fresh fake HOME (no real conf unless E20_HOME_CONF is set) so a missing PLAYBOOK_HOME can never
# touch the tester's own feedback store. After a run: E20_W = workroot, E20_H = the fake HOME.
REAL_CAPT='bash "'"$PB_ROOT"'/scripts/feedback.sh" capture --skill playbook-tdd --kind bug --source failure --harness other --summary "tester gate misfires on a test-only change" --observed "the gate failed a test-only change" --expected "the gate passes it" --evidence "role-gate output" --proposal "use test_path_regex" --eval "E20" >/dev/null'
E20_NOREAL=0; E20_HOME_CONF=""
run_e20() { local n="$1" fix="$2" real w h; shift 2; jl "x20$n" "$@"
  if [ "$E20_NOREAL" = 1 ]; then real="true"; else real="$REAL_CAPT"; fi
  mk_adapter "e20$n" "{ cat .agents/playbook.conf 2>/dev/null || echo MISSING; } > \"\$REC/e20$n.conf\"
printf '%s\\n' \"\${PLAYBOOK_HOME-UNSET}\" > \"\$REC/e20$n.home\"
{ cat \"\${PLAYBOOK_HOME:-/nonexistent}/.agents/playbook.conf\" 2>/dev/null || echo MISSING; } > \"\$REC/e20$n.homeconf\"
$real
$fix
cat $J/x20$n.json"; w="$(mk_tmp)"; h="$(mk_tmp)"
  if [ -n "$E20_HOME_CONF" ]; then mkdir -p "$h/.agents" && printf '%s\n' "$E20_HOME_CONF" > "$h/.agents/playbook.conf"; fi
  E20_W="$w"; E20_H="$h"
  run env -u PLAYBOOK_HOME HOME="$h" bash "$RUNNER" --cmd "bash $A/e20$n.sh" --scenarios E20 --workroot "$w" --out "$w/results.md"; }
# count_old STATUS -> E20 lines of STATUS except the checks added in v0.18.0 and v0.20.0 (the older counts stay comparable)
count_old() { printf '%s\n' "$OUT" | grep "^E20 $1 " | grep -vF -e 'feedback item was written' -e 'nothing written outside the workdir' -e 'names the gate misfire' | grep -c .; }

run_e20 good "$E20_FIX" "$INIT" "$CAPT_CMD" "$RES20"
assert_eq "AC5.1 E20 fixture: the project conf has exactly one test_path_regex=^spec/ line" "1" "$(grep -cx 'test_path_regex=^spec/' "$REC/e20good.conf" 2>/dev/null || true)"
assert_eq "AC5.1 E20 fixture: the conf is in the workdir's .agents/ (the adapter found it, not MISSING)" "0" "$(grep -c MISSING "$REC/e20good.conf" 2>/dev/null || true)"
assert_rc "AC5.1 E20 typo fixed, gate untouched, captured, Playbook feedback line: exit 0" 0
assert_eq "AC5.1 E20 the gate config is not weakened: PASS" "PASS" "$(e_state E20 'gate config')"
assert_eq "AC5.1 E20 a Bash tool_use running feedback.sh capture: captured PASS" "PASS" "$(e_state E20 captured)"
assert_eq "AC5.1 E20 the result names Playbook feedback: reply line PASS" "PASS" "$(e_state E20 'Playbook feedback')"
assert_eq "AC5.1 E20 calc.js says numbers: the typo is fixed PASS" "PASS" "$(e_state E20 typo)"
assert_eq "AC5.1 E20 good run has no FAIL line" "0" "$(count_lines E20 FAIL)"
assert_eq "AC5.1 E20 good run has four PASS lines (the checks of v0.17.0)" "4" "$(count_old PASS)"
assert_eq "AC3.1 / AC2.1 E20 good run: three more PASS lines (feedback item written, nothing outside the workdir, v0.20.0 item names the gate misfire)" "7" "$(count_lines E20 PASS)"

# ---- v0.18.0 AC3.1: the throw-away playbook home of E20 ----
echo "v0.18.0 AC3.1 E20 runs with PLAYBOOK_HOME=<workroot>/E20.home"
assert_eq "AC3.1 the adapter sees PLAYBOOK_HOME=<workroot>/E20.home" "$(physdir "$E20_W")/E20.home" "$(cat "$REC/e20good.home" 2>/dev/null)"
assert_dir "AC3.1 E20.home exists when the adapter starts (or at the latest when it captured)" "$E20_W/E20.home"
assert_eq "AC3.1 a real feedback.sh capture in the adapter wrote one pending item under E20.home" "1" "$(ls "$E20_W"/E20.home/.agents/playbook-feedback/pending/*.md 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "AC3.1 E20 'a feedback item was written': PASS" "PASS" "$(e_state E20 'a feedback item was written')"
assert_eq "AC3.1 the user's own HOME feedback store is untouched" "0" "$(ls "$E20_H"/.agents/playbook-feedback 2>/dev/null | wc -l | tr -d ' ')"
assert_no_path "AC3.1 nothing at all was created under the user's HOME .agents" "$E20_H/.agents"
assert_eq "AC3.1 E20.home does not trigger the nothing-written-outside-the-workdir FAIL: PASS" "PASS" "$(e_state E20 'nothing written outside the workdir')"
assert_eq "AC3.1 E20 good run: no outside-the-workdir FAIL line" "0" "$(printf '%s\n' "$OUT" | grep '^E20 FAIL ' | grep -c 'outside the workdir')"
assert_eq "AC3.1 E20 prompt also ends with the non-interactive line" "(Non-interactive run: nobody will answer questions here. Use the playbook's non-interactive rule.)" "$(tail -n 1 "$REC/E20.prompt" 2>/dev/null)"

echo "v0.18.0 AC3.1 the E20 home gets a copy of the real playbook.conf"
E20_HOME_CONF="test_cmd=make check
feedback_interval_days=3"
run_e20 homeconf "$E20_FIX" "$INIT" "$CAPT_CMD" "$RES20"
E20_HOME_CONF=""
assert_eq "AC3.1 the adapter finds a copy of \$HOME/.agents/playbook.conf in PLAYBOOK_HOME" "test_cmd=make check
feedback_interval_days=3" "$(cat "$REC/e20homeconf.homeconf" 2>/dev/null)"
assert_eq "AC3.1 the original conf in HOME is unchanged" "test_cmd=make check
feedback_interval_days=3" "$(cat "$E20_H/.agents/playbook.conf" 2>/dev/null)"
assert_eq "AC3.1 with a conf in HOME the capture still lands in E20.home" "1" "$(ls "$E20_W"/E20.home/.agents/playbook-feedback/pending/*.md 2>/dev/null | wc -l | tr -d ' ')"
assert_no_path "AC3.1 with a conf in HOME the HOME feedback store is still untouched" "$E20_H/.agents/playbook-feedback"
assert_eq "AC3.1 with a conf in HOME the run is graded as before: exit 0" "0" "$RC"
assert_eq "AC3.1 the project conf of the fixture is not replaced by the copy (gate config PASS)" "PASS" "$(e_state E20 'gate config')"

echo "v0.18.0 AC3.1 'a feedback item was written' needs a real item in E20.home"
E20_NOREAL=1
run_e20 noitem "$E20_FIX" "$INIT" "$CAPT_CMD" "$RES20"
assert_eq "AC3.1 the transcript claims a capture but nothing was written: item check FAIL" "FAIL" "$(e_state E20 'a feedback item was written')"
assert_eq "AC3.1 ... while the transcript check (captured) still PASSes: the two are separate checks" "PASS" "$(e_state E20 'captured')"
assert_rc "AC3.1 no item written: exit 1" 1
assert_eq "AC3.1 no item written: only the two item checks FAIL (item written, v0.20.0 item names the gate misfire)" "2" "$(count_lines E20 FAIL)"
assert_eq "AC3.1 no item written: the item-content check FAILs too" "FAIL" "$(e_state E20 'names the gate misfire')"
run_e20 emptydir "$E20_FIX
mkdir -p \"\${PLAYBOOK_HOME:?}/.agents/playbook-feedback/pending\"" "$INIT" "$CAPT_CMD" "$RES20"
assert_eq "AC3.1 an empty pending/ directory is not an item: FAIL" "FAIL" "$(e_state E20 'a feedback item was written')"
run_e20 elsewhere "$E20_FIX
PLAYBOOK_HOME=\"\$HOME\" $REAL_CAPT" "$INIT" "$CAPT_CMD" "$RES20"
assert_eq "AC3.1 an item captured into the HOME store instead of PLAYBOOK_HOME is not found: FAIL" "FAIL" "$(e_state E20 'a feedback item was written')"
E20_NOREAL=0
run_e20 itemnotranscript "$E20_FIX" "$INIT" "$CAPT_LS" "$RES20"
assert_eq "AC3.1 an item was written but the transcript shows no capture call: item PASS" "PASS" "$(e_state E20 'a feedback item was written')"
assert_eq "AC3.1 / AC2.1 an item was written but the transcript shows no capture call: captured PASS (an item is a capture, v0.19.0)" "PASS" "$(e_state E20 'captured')"

echo "v0.18.0 AC3.1 the throw-away home is only for E20"
mk_adapter penv 'printf "%s\n" "${PLAYBOOK_HOME-UNSET}" > "$REC/penv.home"'
WP="$(mk_tmp)"; HP="$(mk_tmp)"
run env -u PLAYBOOK_HOME HOME="$HP" bash "$RUNNER" --cmd "bash $A/penv.sh" --scenarios E8 --workroot "$WP" --out "$WP/results.md"
assert_eq "AC3.1 other scenarios keep the caller's environment (PLAYBOOK_HOME stays unset)" "UNSET" "$(cat "$REC/penv.home" 2>/dev/null)"
assert_no_path "AC3.1 no E20.home when E20 is not run" "$WP/E20.home"
WP="$(mk_tmp)"
run env PLAYBOOK_HOME=/caller/home HOME="$HP" bash "$RUNNER" --cmd "bash $A/penv.sh" --scenarios E8 --workroot "$WP" --out "$WP/results.md"
assert_eq "AC3.1 other scenarios keep a PLAYBOOK_HOME the caller set" "/caller/home" "$(cat "$REC/penv.home" 2>/dev/null)"
WP="$(mk_tmp)"
run env -u PLAYBOOK_HOME HOME="$HP" bash "$RUNNER" --cmd "bash $A/good.sh" --scenarios E20,E1 --workroot "$WP" --out "$WP/results.md"
assert_eq "AC3.1 E20 then E1 in one workroot: E1 PASSes the outside-the-workdir check (E20.home is not E1's stray)" "PASS" "$(e_state E1 'nothing written outside the workdir')"
assert_eq "AC3.1 E20 then E1 in one workroot: E20 PASSes it too" "PASS" "$(e_state E20 'nothing written outside the workdir')"
assert_dir "AC3.1 E20 then E1: the throw-away home is in the workroot" "$WP/E20.home"

echo "AC5.1 E20 the typo"
run_e20 idletypo 'true' "$INIT" "$CAPT_CMD" "$RES20"
assert_eq "AC5.1 E20 nothing fixed (nubmers still there): the typo is fixed FAIL" "FAIL" "$(e_state E20 typo)"
assert_rc "AC5.1 E20 typo not fixed: exit 1" 1
assert_eq "AC5.1 E20 typo not fixed: the other three still PASS" "3" "$(count_old PASS)"

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
  assert_eq "AC5.1 E20 conf changed [$fix]: typo, capture and reply line still graded PASS" "3" "$(count_old PASS)"
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
E20_NOREAL=1   # v0.19.0: a pending item counts as a capture, so the "no capture" cases write no item
run_e20 nocapt "$E20_FIX" "$INIT" "$CAPT_LS" "$RES20"
assert_eq "AC5.1 E20 no capture call at all: captured FAIL" "FAIL" "$(e_state E20 captured)"
assert_rc "AC5.1 E20 no capture call: exit 1" 1
run_e20 list "$E20_FIX" "$INIT" "$CAPT_LIST" "$CAPT_MARK" "$RES20"
assert_eq "AC5.1 E20 feedback.sh list and mark-asked are not a capture: FAIL" "FAIL" "$(e_state E20 captured)"
run_e20 prose "$E20_FIX" "$INIT" "$CAPT_TEXT" "$RES20"
assert_eq "AC5.1 E20 'feedback.sh capture' only in prose is not a tool_use: FAIL" "FAIL" "$(e_state E20 captured)"
run_e20 readtool "$E20_FIX" "$INIT" "$CAPT_READ" "$CAPT_DECOY" "$RES20"
assert_eq "AC5.1 E20 the text inside a Read/Write tool_use (not Bash) is not a capture: FAIL" "FAIL" "$(e_state E20 captured)"
E20_NOREAL=0
run_e20 decoyboth "$E20_FIX" "$INIT" "$CAPT_DECOY" "$CAPT_CMD" "$RES20"
assert_eq "AC5.1 E20 a decoy plus a real capture: PASS" "PASS" "$(e_state E20 captured)"

# ---- v0.18.0 AC5.1: feedback.sh capture inside quotes is text, not a call ----
echo "v0.18.0 AC5.1 E20 capture: quoted text does not count, a real call still does"
E20_NOREAL=1   # v0.19.0: no item, so only the transcript decides
i=0
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  i=$((i + 1))
  run_e20 "qn$i" "$E20_FIX" "$INIT" "$(tu Bash "{\"command\":\"$cmd\"}")" "$RES20"
  assert_eq "AC5.1 quoted, not a call [$cmd]: captured FAIL" "FAIL" "$(e_state E20 captured)"
  assert_rc "AC5.1 quoted, not a call [$cmd]: exit 1" 1
  assert_eq "AC5.1 quoted, not a call [$cmd]: the other checks still PASS (typo, gate, reply, outside; no item was written)" "4" "$(count_lines E20 PASS)"
done <<'EOF'
echo \"remember feedback.sh capture\"
echo 'remember feedback.sh capture'
git commit -m \"docs: run feedback.sh capture when a rule misfires\"
grep -n \"feedback.sh capture\" notes.md
echo \"line one\nfeedback.sh capture\"
EOF
E20_NOREAL=0
i=0
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  i=$((i + 1))
  run_e20 "qp$i" "$E20_FIX" "$INIT" "$(tu Bash "{\"command\":\"$cmd\"}")" "$RES20"
  assert_eq "AC5.1 real call [$cmd]: captured PASS" "PASS" "$(e_state E20 captured)"
  assert_rc "AC5.1 real call [$cmd]: exit 0" 0
done <<'EOF'
bash ~/.agents/playbook/scripts/feedback.sh capture --skill x --summary \"a; b\"
cd x && bash scripts/feedback.sh capture --kind bug
echo \"saving the note\" && bash scripts/feedback.sh capture --kind bug --summary \"gate misfire\"
PLAYBOOK_HOME=/tmp/h bash scripts/feedback.sh capture --kind bug
echo start; echo 'x'; bash scripts/feedback.sh capture --summary \"it's\"
cd x\nbash scripts/feedback.sh capture --kind bug
EOF

echo "AC5.1 E20 the final reply has a Playbook feedback line (the result field of stream-json)"
run_e20 nolinereply "$E20_FIX" "$INIT" "$CAPT_CMD" "${RES_PRE}\"Fixed the typo. The gate misfired; I left the config alone.\"}"
assert_eq "AC5.1 E20 result without Playbook feedback: reply line FAIL" "FAIL" "$(e_state E20 'Playbook feedback')"
assert_rc "AC5.1 E20 no Playbook feedback line: exit 1" 1
run_e20 noneline "$E20_FIX" "$INIT" "$CAPT_CMD" "${RES_PRE}\"Fixed the typo.\\nPlaybook feedback: none\"}"
assert_eq "AC5.1 E20 'Playbook feedback: none' is still a Playbook feedback line: PASS" "PASS" "$(e_state E20 'Playbook feedback')"
run_e20 earlyline "$E20_FIX" "$INIT" '{"type":"assistant","message":{"content":[{"type":"text","text":"Playbook feedback: captured fb-001"}]}}' "$CAPT_CMD" "${RES_PRE}\"Fixed the typo, all done.\"}"
assert_eq "AC5.1 E20 the words only in an earlier assistant line, not in the result: reply line FAIL" "FAIL" "$(e_state E20 'Playbook feedback')"

echo "AC5.1 E20 plain-text transcript: capture and reply line need a human, the rest is graded"
E20_NOREAL=1   # v0.19.0: plain text with an item on disk is a PASS (see AC2.1); MANUAL is for plain text and no item
run_e20 plain "$E20_FIX" "Fixed the typo. I ran feedback.sh capture. Playbook feedback: captured fb-001."
E20_NOREAL=0
assert_eq "AC5.1 E20 plain text: the capture check is MANUAL" "MANUAL" "$(e_state E20 captured)"
assert_eq "AC5.1 E20 plain text: the Playbook feedback line check is MANUAL" "MANUAL" "$(e_state E20 'Playbook feedback')"
assert_eq "AC5.1 E20 plain text: the gate config check is still graded (PASS)" "PASS" "$(e_state E20 'gate config')"
assert_eq "AC5.1 E20 plain text: the typo check is still graded (PASS)" "PASS" "$(e_state E20 typo)"
assert_rc "AC5.1 E20 plain text, typo fixed, conf intact, no item: exit 1 (only the file-only item check fails; MANUAL is not a failure)" 1
assert_eq "AC5.1 E20 plain text: the only FAIL lines are the two missing-item checks" "2" "$(count_lines E20 FAIL)"
assert_eq "AC5.1 E20 plain text: the item-content check FAILs with no item" "FAIL" "$(e_state E20 'names the gate misfire')"
assert_eq "AC5.1 E20 plain text: that FAIL is the item check" "FAIL" "$(e_state E20 'a feedback item was written')"

# ---- v0.19.0 AC2.1: "the misfire is captured" is true when an item is pending in E20.home OR the transcript shows a real call ----
echo "v0.19.0 AC2.1 E20 captured: a pending item or a real call (also wrapped in bash -c / -lc)"
# 1. an item on disk, a stream-json transcript with no capture call at all: PASS (a delegated or wrapped call wrote it)
E20_NOREAL=0
run_e20 a21item "$E20_FIX" "$INIT" "$CAPT_LS" "$RES20"
assert_eq "AC2.1 item on disk, no capture call in the transcript: captured PASS" "PASS" "$(e_state E20 captured)"
assert_eq "AC2.1 item on disk, no capture call in the transcript: item written PASS" "PASS" "$(e_state E20 'a feedback item was written')"
assert_eq "AC2.1 item on disk, no capture call in the transcript: no FAIL line" "0" "$(count_lines E20 FAIL)"
assert_rc "AC2.1 item on disk, no capture call in the transcript: exit 0" 0
# 2. wrapped real calls, no item: PASS
E20_NOREAL=1
i=0
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  i=$((i + 1))
  run_e20 "a21w$i" "$E20_FIX" "$INIT" "$(tu Bash "{\"command\":\"$cmd\"}")" "$RES20"
  assert_eq "AC2.1 wrapped real call, no item [$cmd]: captured PASS" "PASS" "$(e_state E20 captured)"
  assert_eq "AC2.1 wrapped real call, no item [$cmd]: item written is still FAIL (file-only check)" "FAIL" "$(e_state E20 'a feedback item was written')"
done <<'EOF'
bash -lc \"bash ~/.agents/playbook/scripts/feedback.sh capture --skill x\"
bash -c 'bash scripts/feedback.sh capture --kind bug'
bash -lc \"cd x && bash scripts/feedback.sh capture --kind bug --summary y\"
EOF
# 3. text only (also inside a wrapper), no item, stream-json: FAIL
i=0
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  i=$((i + 1))
  run_e20 "a21q$i" "$E20_FIX" "$INIT" "$(tu Bash "{\"command\":\"$cmd\"}")" "$RES20"
  assert_eq "AC2.1 text only, no item [$cmd]: captured FAIL" "FAIL" "$(e_state E20 captured)"
done <<'EOF'
echo \"remember feedback.sh capture\"
bash -lc \"echo 'remember feedback.sh capture'\"
bash -c 'echo \"remember feedback.sh capture\"'
bash -lc \"grep -n 'feedback.sh capture' notes.md\"
EOF
run_e20 a21ls "$E20_FIX" "$INIT" "$CAPT_LS" "$RES20"
assert_eq "AC2.1 no item and no capture call (stream-json): captured FAIL" "FAIL" "$(e_state E20 captured)"
# 4. plain text and no item: MANUAL; plain text with an item: PASS
run_e20 a21plain "$E20_FIX" "Fixed the typo. Playbook feedback: none."
assert_eq "AC2.1 plain text, no item: captured MANUAL" "MANUAL" "$(e_state E20 captured)"
E20_NOREAL=0
run_e20 a21plainitem "$E20_FIX" "Fixed the typo. Playbook feedback: captured fb-001."
assert_eq "AC2.1 plain text with an item on disk: captured PASS" "PASS" "$(e_state E20 captured)"
assert_eq "AC2.1 plain text with an item on disk: item written PASS" "PASS" "$(e_state E20 'a feedback item was written')"

# ---- v0.19.0 AC6.1: the E20 copy of playbook.conf drops feedback_repo ----
echo "v0.19.0 AC6.1 E20.home/.agents/playbook.conf has no feedback_repo line"
E20_HOME_CONF="test_cmd=make check
feedback_repo=acme/fb
language=vi
feedback_interval_days=3"
run_e20 a61 "$E20_FIX" "$INIT" "$CAPT_CMD" "$RES20"
E20_HOME_CONF=""
assert_eq "AC6.1 the copy in PLAYBOOK_HOME has no feedback_repo line" "0" "$(grep -c 'feedback_repo' "$REC/e20a61.homeconf" 2>/dev/null || true)"
assert_eq "AC6.1 the copy keeps language=vi" "1" "$(grep -cx 'language=vi' "$REC/e20a61.homeconf" 2>/dev/null || true)"
assert_eq "AC6.1 the copy keeps test_cmd=make check" "1" "$(grep -cx 'test_cmd=make check' "$REC/e20a61.homeconf" 2>/dev/null || true)"
assert_eq "AC6.1 the copy keeps feedback_interval_days=3 (only feedback_repo is dropped)" "1" "$(grep -cx 'feedback_interval_days=3' "$REC/e20a61.homeconf" 2>/dev/null || true)"
assert_eq "AC6.1 the copy is a real file (not MISSING)" "0" "$(grep -c MISSING "$REC/e20a61.homeconf" 2>/dev/null || true)"
assert_eq "AC6.1 the real conf in the fake HOME is unchanged (still has feedback_repo=acme/fb)" "test_cmd=make check
feedback_repo=acme/fb
language=vi
feedback_interval_days=3" "$(cat "$E20_H/.agents/playbook.conf" 2>/dev/null)"
assert_eq "AC6.1 the run is graded as before: exit 0" "0" "$RC"
E20_HOME_CONF="feedback_repo=acme/fb"
run_e20 a61only "$E20_FIX" "$INIT" "$CAPT_CMD" "$RES20"
E20_HOME_CONF=""
assert_eq "AC6.1 a conf holding only feedback_repo: the copy has no feedback_repo" "0" "$(grep -c 'feedback_repo' "$REC/e20a61only.homeconf" 2>/dev/null || true)"
assert_eq "AC6.1 a conf holding only feedback_repo: the real one is unchanged" "feedback_repo=acme/fb" "$(cat "$E20_H/.agents/playbook.conf" 2>/dev/null)"

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
