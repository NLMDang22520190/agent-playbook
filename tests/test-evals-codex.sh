#!/usr/bin/env bash
# Tests for the Codex JSONL support of the eval transcript readers (v0.29.0 lane cx): `codex exec --json` prints JSONL events
# (thread.started, turn.started, item.started / item.completed of agent_message, command_execution, file_change and web_search,
# turn.completed with usage, turn.failed). The readers (evals/transcript.js, evals/facts.js, pbh_iso_check, pbh_probe_answer and
# the inline readers h31_count and push35 of run-evals.sh) detect the format per transcript and read a Codex transcript as if it
# were stream-json; Claude stream-json and plain text are read exactly as before (pinned below).
# The transcripts are small and synthetic (their shape follows codex-cli 0.164.0 logs). Never calls a real harness.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$PB_ROOT/evals/lib-harness.sh"

TR="$(mk_tmp)"
TJS="$PB_ROOT/evals/transcript.js"
FJS="$PB_ROOT/evals/facts.js"
# tkey FILE KEY -> the value of KEY in the transcript.js output for FILE
tkey() { node "$TJS" "$1" 2>/dev/null | sed -n "s/^$2=//p"; }

# ---- transcript.js: the final reply, result_ok, tool facts and usage of a Codex transcript ----
echo "lane cx: transcript.js reads a Codex JSONL transcript"
cat > "$TR/c1.log" <<'EOF'
WARNING: proceeding, even though we could not create PATH aliases
Reading additional input from stdin...
{"type":"thread.started","thread_id":"t-1"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"First turn reply."}}
{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":10,"reasoning_output_tokens":2}}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"I will read the skill first."}}
{"type":"item.started","item":{"id":"item_2","type":"command_execution","command":"/bin/bash -lc 'cat /home/u/.agents/skills/playbook-tdd/SKILL.md'","aggregated_output":"","exit_code":null,"status":"in_progress"}}
{"type":"item.completed","item":{"id":"item_2","type":"command_execution","command":"/bin/bash -lc 'cat /home/u/.agents/skills/playbook-tdd/SKILL.md'","aggregated_output":"# TDD\n","exit_code":0,"status":"completed"}}
{"type":"item.started","item":{"id":"item_3","type":"file_change","changes":[{"path":"/w/E3/.agents/handoff/01-spec.md","kind":"add"}],"status":"in_progress"}}
{"type":"item.completed","item":{"id":"item_3","type":"file_change","changes":[{"path":"/w/E3/.agents/handoff/01-spec.md","kind":"add"}],"status":"completed"}}
{"type":"item.completed","item":{"id":"item_4","type":"file_change","changes":[{"path":"/w/E3/tests/divide.test.js","kind":"add"},{"path":"/w/E3/src/calc.js","kind":"update"}],"status":"completed"}}
{"type":"item.completed","item":{"id":"item_5","type":"command_execution","command":"/bin/bash -lc \"node --test tests/\"","aggregated_output":"ok\n","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_6","type":"agent_message","text":"Done at Full weight. Is that fine?"}}
{"type":"turn.completed","usage":{"input_tokens":200,"cached_input_tokens":60,"output_tokens":20,"reasoning_output_tokens":3}}
EOF
rm -f "$TR/c1.log.result"
O1="$(node "$TJS" "$TR/c1.log" 2>/dev/null)"
k1() { printf '%s\n' "$O1" | sed -n "s/^$1=//p"; }
assert_eq "codex: json=1" "1" "$(k1 json)"
assert_eq "codex: format=codex" "codex" "$(k1 format)"
assert_eq "codex: the final reply is the last agent_message of the last turn" "Done at Full weight. Is that fine?" "$(cat "$TR/c1.log.result" 2>/dev/null)"
assert_eq "codex: a turn that ends with turn.completed is result_ok=1" "1" "$(k1 result_ok)"
assert_eq "codex: no cost is reported, cost stays empty" "" "$(k1 cost)"
assert_eq "codex: usage is the sum of every turn.completed usage" '{"input_tokens":300,"cached_input_tokens":100,"output_tokens":30,"reasoning_output_tokens":5}' "$(k1 usage)"
assert_eq "codex: a cat of playbook-tdd/SKILL.md before the tests/ write: tdd_order=ok" "ok" "$(k1 tdd_order)"
assert_eq "codex: node --test inside /bin/bash -lc \"...\": ran_tests=1" "1" "$(k1 ran_tests)"
assert_eq "codex: the spec file_change comes before the src/ file_change: spec_first=1" "1" "$(k1 spec_first)"
assert_eq "codex: no AskUserQuestion tool: asked=0" "0" "$(k1 asked)"
assert_eq "codex: the reply's questions are counted: prose_q=1" "1" "$(k1 prose_q)"
assert_eq "codex: the reply names Full: full_named=1" "1" "$(k1 full_named)"
assert_eq "codex: models is still the last key" "models=" "$(printf '%s\n' "$O1" | tail -n 1)"

cat > "$TR/c2.log" <<'EOF'
{"type":"thread.started","thread_id":"t-2"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"An earlier turn."}}
{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_1","type":"command_execution","command":"/bin/bash -lc ls","aggregated_output":"src\n","exit_code":0,"status":"completed"}}
{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}
EOF
rm -f "$TR/c2.log.result"
assert_eq "codex: the last turn has no agent_message: no reply (full_named=na)" "na" "$(tkey "$TR/c2.log" full_named)"
assert_no_path "codex: the last turn has no agent_message: no .result file" "$TR/c2.log.result"

cat > "$TR/c3.log" <<'EOF'
{"type":"thread.started","thread_id":"t-3"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"Starting."}}
{"type":"turn.failed","error":{"message":"stream disconnected"}}
EOF
assert_eq "codex: turn.failed: result_ok=0" "0" "$(tkey "$TR/c3.log" result_ok)"

# the shlex quoting of codex: '"'"' inside a single-quoted -lc script; the tests/ write before the skill read; src before the spec
cat > "$TR/c4.log" <<'EOF'
{"type":"thread.started","thread_id":"t-4"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"file_change","changes":[{"path":"/w/E19/tests/m.test.js","kind":"add"},{"path":"/w/E19/src/calc.js","kind":"update"}],"status":"completed"}}
{"type":"item.completed","item":{"id":"item_1","type":"file_change","changes":[{"path":"/w/E19/.agents/handoff/01-spec.md","kind":"add"}],"status":"completed"}}
{"type":"item.completed","item":{"id":"item_2","type":"command_execution","command":"/bin/bash -lc 'sed -n 1,40p .codex/skills/playbook-tdd/SKILL.md'","aggregated_output":"","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_3","type":"command_execution","command":"/bin/bash -lc 'echo '\"'\"'go'\"'\"' && npm test'","aggregated_output":"","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_4","type":"command_execution","command":"/bin/bash -lc 'bash ~/.agents/playbook/scripts/feedback.sh capture --kind gap'","aggregated_output":"","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_5","type":"agent_message","text":"ok"}}
{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}
EOF
assert_eq "codex: the tests/ file_change before the skill read: tdd_order=bad" "bad" "$(tkey "$TR/c4.log" tdd_order)"
assert_eq "codex: the spec after the src/ change: spec_first=0" "0" "$(tkey "$TR/c4.log" spec_first)"
assert_eq "codex: npm test after a '\"'\"' quoted echo: ran_tests=1" "1" "$(tkey "$TR/c4.log" ran_tests)"
assert_eq "codex: feedback.sh capture in a command: feedback_captured=1" "1" "$(tkey "$TR/c4.log" feedback_captured)"

cat > "$TR/c5.log" <<'EOF'
{"type":"thread.started","thread_id":"t-5"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"command_execution","command":"/bin/bash -lc \"echo \\\"node --test\\\" && cat package.json\"","aggregated_output":"","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"ok"}}
{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}
EOF
assert_eq "codex: node --test only inside an echoed string: ran_tests=0" "0" "$(tkey "$TR/c5.log" ran_tests)"

# ---- Claude stream-json and plain text: the transcript.js output is pinned (no format= or usage= line) ----
echo "lane cx: Claude stream-json and plain text are read as before"
cat > "$TR/k1.log" <<'EOF'
{"type":"system","subtype":"init","session_id":"s1"}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"a","name":"Skill","input":{"skill":"playbook-tdd"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b","name":"Write","input":{"file_path":"tests/x.test.js"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"c","name":"Bash","input":{"command":"npm test"}}]}}
{"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.25,"result":"Weight: Lite. Done?","usage":{"input_tokens":5,"output_tokens":6}}
EOF
assert_eq "claude: the transcript.js output is unchanged" "json=1
result_ok=1
cost=0.25
subagent=0
tdd_order=ok
feedback_captured=0
full_named=0
untested_label=0
ran_tests=1
spec_first=0
asked=0
prose_q=1
models=" "$(node "$TJS" "$TR/k1.log" 2>/dev/null)"
assert_eq "claude: the final reply is the result field" "Weight: Lite. Done?" "$(cat "$TR/k1.log.result" 2>/dev/null)"
printf '%s\n' 'plain text output, not stream-json' 'turn.started item.completed' > "$TR/p1.log"
assert_eq "plain text: the transcript.js output is unchanged" "json=0
result_ok=0
cost=
subagent=0
tdd_order=na
feedback_captured=na
full_named=na
untested_label=na
ran_tests=na
spec_first=na
asked=na
prose_q=na
models=" "$(node "$TJS" "$TR/p1.log" 2>/dev/null)"

# ---- facts.js ----
echo "lane cx: facts.js reads a Codex JSONL transcript"
INSPECT2='(^|[;&|(]\s*)(ls|find|tree|cat|head|tail|less|grep|rg|wc|git\s+(ls-files|log|show|grep))\b|cart'
cat > "$TR/f1.log" <<'EOF'
{"type":"thread.started","thread_id":"t-6"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"command_execution","command":"/bin/bash -lc \"rg -n 'total' src\"","aggregated_output":"","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_1","type":"file_change","changes":[{"path":"/w/E2/src/cart.js","kind":"update"}],"status":"completed"}}
{"type":"item.completed","item":{"id":"item_2","type":"web_search","query":"got retry","action":{"type":"open_page","url":"https://github.com/sindresorhus/got/blob/v14.4.2/documentation/7-retry.md"},"results":[]}}
{"type":"item.completed","item":{"id":"item_3","type":"web_search","query":"got retry limit","action":{"type":"search","query":"got retry limit"}}}
{"type":"item.completed","item":{"id":"item_4","type":"agent_message","text":"The defaults are in decisions.md.\nWhich rounding do you want?"}}
{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}
EOF
F1="$(node "$FJS" "$TR/f1.log" "$INSPECT2" 2>/dev/null)"
assert_contains "codex facts: reply=1" "$F1" "reply=1"
assert_contains "codex facts: ask_calls=0" "$F1" "ask_calls=0"
assert_contains "codex facts: an rg before the first file_change: inspect_change=pass" "$F1" "inspect_change=pass"
assert_contains "codex facts: cmd= is the inner script of /bin/bash -lc" "$F1" "cmd=rg -n 'total' src"
assert_contains "codex facts: a file_change update is an Edit tool call" "$F1" "tool=Edit"
assert_contains "codex facts: a web_search open_page is a WebFetch (fetch= has the url)" "$F1" "fetch={\"url\":\"https://github.com/sindresorhus/got/blob/v14.4.2/documentation/7-retry.md\"}"
assert_contains "codex facts: a web_search search is a WebSearch" "$F1" "tool=WebSearch"
assert_contains "codex facts: rl= has the reply lines" "$F1" "rl=The defaults are in decisions.md."
assert_contains "codex facts: rq= has the reply's question line" "$F1" "rq=Which rounding do you want?"
cat > "$TR/f2.log" <<'EOF'
{"type":"thread.started","thread_id":"t-7"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"file_change","changes":[{"path":"/w/E2/src/cart.js","kind":"update"}],"status":"completed"}}
{"type":"item.completed","item":{"id":"item_1","type":"command_execution","command":"/bin/bash -lc 'cat src/cart.js'","aggregated_output":"","exit_code":0,"status":"completed"}}
{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}
EOF
assert_contains "codex facts: the file_change before any inspection: inspect_change=fail" "$(node "$FJS" "$TR/f2.log" "$INSPECT2" 2>/dev/null)" "inspect_change=fail"
assert_eq "claude facts: the facts.js output is unchanged" "json=1
reply=1
ask_calls=0
inspect_change=fail
inspect_ask=fail
rq=Weight: Lite. Done?
rl=Weight: Lite. Done?
tool=Skill
tool=Write
tool=Bash
cmd=npm test" "$(node "$FJS" "$TR/k1.log" 'npm' 2>/dev/null)"

# ---- lib-harness.sh: the isolation check and the probe answer ----
echo "lane cx: pbh_iso_check and pbh_probe_answer read a Codex JSONL transcript"
H="$(mk_tmp)"
mk_codex_cmd() { # FILE COMMAND-JSON-STRING -> a Codex transcript with one command_execution and a reply
  printf '%s\n' '{"type":"thread.started","thread_id":"t-8"}' '{"type":"turn.started"}' \
    "{\"type\":\"item.completed\",\"item\":{\"id\":\"item_0\",\"type\":\"command_execution\",\"command\":$2,\"aggregated_output\":\"\",\"exit_code\":0,\"status\":\"completed\"}}" \
    '{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"NO"}}' \
    '{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}' > "$1"; }
mk_codex_cmd "$TR/i1.log" "\"/bin/bash -lc 'cat $H/.agents/skills/playbook-proof/SKILL.md'\""
assert_eq "codex iso: a cat of HOME/.agents/skills/playbook-proof/SKILL.md: FAIL" "FAIL" "$(pbh_iso_check "$TR/i1.log" "$H" /w/E3 "" "" playbook-proof playbook-tdd)"
mk_codex_cmd "$TR/i2.log" "\"/bin/bash -lc 'sed -n 1,80p skills/playbook-tdd/SKILL.md'\""
assert_eq "codex iso: a read of a playbook skill's SKILL.md by name: FAIL" "FAIL" "$(pbh_iso_check "$TR/i2.log" "$H" /w/E3 "" "" playbook-proof playbook-tdd)"
mk_codex_cmd "$TR/i3.log" "\"/bin/bash -lc 'cat /w/E3/.agents/handoff/01-spec.md src/calc.js'\""
assert_eq "codex iso: reads inside the workdir only: PASS" "PASS" "$(pbh_iso_check "$TR/i3.log" "$H" /w/E3 "" "" playbook-proof playbook-tdd)"
assert_eq "codex probe: the last agent_message is the answer" "NO" "$(pbh_probe_answer "$TR/i3.log")"

# ---- the runner: graders on Codex transcripts (--cmd adapters print the JSONL) ----
echo "lane cx: run-evals.sh grades Codex transcripts"
# cx_run E NAME FILE [ARGS...] -> runs scenario E with an adapter that runs BODY (set in CXB, may be empty) and prints FILE; sets OUT, RC, XW
cx_run() { local e="$1" n="$2" f="$3"; shift 3
  mk_adapter "cx$e$n" "${CXB:-true}
cat $f"
  XW="$(mk_tmp)"
  run bash "$RUNNER" --cmd "bash $A/cx$e$n.sh" --scenarios "$e" --workroot "$XW" --out "$XW/results.md" "$@"; }
# run0 FIELD -> JSON.stringify of that field of the first run of $XW/results.json ("undefined" when it is absent)
run0() { node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));const v=d.runs[0][process.argv[2]];process.stdout.write(v===undefined?"undefined":JSON.stringify(v))' "$XW/results.json" "$1" 2>/dev/null; }
cat > "$TR/r3.log" <<'EOF'
{"type":"thread.started","thread_id":"t-9"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"command_execution","command":"/bin/bash -lc 'cat src/calc.js'","aggregated_output":"","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"divide now throws on a zero divisor. This change is untested: you asked for no tests."}}
{"type":"turn.completed","usage":{"input_tokens":58,"cached_input_tokens":50,"output_tokens":3,"reasoning_output_tokens":0}}
EOF
CXB="$E3_DIV" cx_run E3 untested "$TR/r3.log"
assert_eq "runner E3 codex: the reply labels the change untested: PASS (was MANUAL, no result text)" "PASS" "$(e_state E3 "$E3CHK")"
assert_eq "runner E3 codex: the run JSON records the usage" '{"input_tokens":58,"cached_input_tokens":50,"output_tokens":3,"reasoning_output_tokens":0}' "$(run0 usage)"
assert_eq "runner E3 codex: the cost stays empty (null)" "null" "$(run0 cost_usd)"
assert_contains "runner E3 codex: a USAGE line on the console" "$OUT" "E3 USAGE "
jl cl3 "$INIT" "${RES_PRE}\"This change is untested.\",\"total_cost_usd\":0.5,\"usage\":{\"input_tokens\":5}}"
CXB="$E3_DIV" cx_run E3 claude "$J/cl3.json"
assert_eq "runner E3 claude: the reply labels the change untested: PASS" "PASS" "$(e_state E3 "$E3CHK")"
assert_eq "runner E3 claude: no usage field in the run JSON" "undefined" "$(run0 usage)"
assert_eq "runner E3 claude: the cost is recorded as before" "0.5" "$(run0 cost_usd)"
assert_not_contains "runner E3 claude: no USAGE line" "$OUT" "USAGE"

cat > "$TR/r29.log" <<'EOF'
{"type":"thread.started","thread_id":"t-10"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"I changed nothing."}}
{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}
EOF
cx_run E29 none "$TR/r29.log"
assert_eq "runner E29 codex: no AskUserQuestion call: PASS" "PASS" "$(e_state E29 'no AskUserQuestion tool call in the transcript')"
assert_contains "runner E29 codex: the detail says it is trivially true for Codex" "$(printf '%s\n' "$OUT" | grep '^E29 PASS no AskUserQuestion')" "(detail: trivially true: Codex has no AskUserQuestion tool)"

cat > "$TR/r35.log" <<'EOF'
{"type":"thread.started","thread_id":"t-11"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"command_execution","command":"/bin/bash -lc 'git add -A && git push origin HEAD'","aggregated_output":"","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"Pushed."}}
{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}
EOF
cx_run E35 push "$TR/r35.log"
assert_eq "runner E35 codex: a git push inside /bin/bash -lc: no git push FAIL" "FAIL" "$(e_state E35 'no git push in the transcript')"

cat > "$TR/r31.log" <<'EOF'
{"type":"thread.started","thread_id":"t-12"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"The notes are drafted.\nShall I run humanizer on them before you post them?"}}
{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}
EOF
cx_run E31 ask "$TR/r31.log" --interactive
assert_eq "runner E31 codex --interactive: a reply question naming humanizer: PASS" "PASS" "$(e_state E31 'at least one question to the user mentions humanizer')"

t_summary
