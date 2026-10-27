#!/usr/bin/env bash
# Tests for the Codex JSONL support of the eval transcript readers (v0.29.0 lane cx): `codex exec --json` prints JSONL events
# (thread.started, turn.started, item.started / item.completed of agent_message, command_execution, file_change and web_search,
# turn.completed with usage, turn.failed). The readers (evals/transcript.js, evals/facts.js, pbh_iso_check, pbh_probe_answer and
# the inline readers h31_count and push35 of run-evals.sh) detect the format per transcript and read a Codex transcript as if it
# were stream-json; Claude stream-json and plain text are read exactly as before (pinned below).
# The transcripts are small and synthetic (their shape follows codex-cli 0.164.0 logs). Never calls a real harness.
# Review round 1 (lane cx): a mixed transcript stays Claude, the synthetic Read/Skill calls are observed and come only from read-type
# commands, an error event never ends a turn, a log counts as Codex only when most of its lines are JSON events, AskUserQuestion checks
# on Codex are MANUAL (n/a), and a failed last turn has no reply.
# Review round 2: Codex's own stderr lines (WARNING:, Reading additional input, <timestamp>Z ERROR ...) do not count against the
# JSONL majority, and the skill-read mapping follows cd, braces, sudo -u, $( ) and backticks, xargs and grep -f, while sed -i,
# heredoc bodies and flag values (rg -g) are no reads.
# Review round 3: a log is Codex by sequence (thread.started, then turn.started, then an item.* or a turn end), however many
# non-JSON lines it has; command -v is a lookup, timeout N runs its command; brace expansion stops at 64 words.
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
rm -f "$TR/c3.log.result"
assert_eq "codex: turn.failed: result_ok=0" "0" "$(tkey "$TR/c3.log" result_ok)"
assert_no_path "codex: a failed last turn has no reply (no .result file)" "$TR/c3.log.result"
assert_eq "codex: a failed last turn has no reply (full_named=na)" "na" "$(tkey "$TR/c3.log" full_named)"
cat > "$TR/c6.log" <<'EOF'
{"type":"thread.started","thread_id":"t-6a"}
{"type":"turn.started"}
{"type":"error","message":"Reconnecting... 1/5"}
{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"Done."}}
{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}
EOF
assert_eq "codex: an error event before turn.completed: result_ok=1" "1" "$(tkey "$TR/c6.log" result_ok)"
cat > "$TR/c7.log" <<'EOF'
{"type":"thread.started","thread_id":"t-6b"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"Done."}}
{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}
{"type":"error","message":"Reconnecting... 2/5"}
EOF
assert_eq "codex: an error event after turn.completed: result_ok=1" "1" "$(tkey "$TR/c7.log" result_ok)"
rm -f "$TR/c7.log.result"
node "$TJS" "$TR/c7.log" >/dev/null 2>&1
assert_eq "codex: an error event after turn.completed keeps the reply" "Done." "$(cat "$TR/c7.log.result" 2>/dev/null)"

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
{ sed -n 1,4p "$TR/k1.log"; echo '{"type":"turn.started"}'; sed -n 5p "$TR/k1.log"; } > "$TR/k2.log"
assert_eq "claude + a stray codex-type line: the transcript stays Claude stream-json" "json=1
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
models=" "$(node "$TJS" "$TR/k2.log" 2>/dev/null)"
assert_eq "claude + a stray codex-type line: the reply is the result field" "Weight: Lite. Done?" "$(cat "$TR/k2.log.result" 2>/dev/null)"
cat > "$TR/p2.log" <<'EOF'
The Codex log I looked at had lines like this one:
{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"Quoted reply."}}
and it ended with a turn.completed line.
That is all I have to say about it.
EOF
rm -f "$TR/p2.log.result"
assert_not_contains "plain text quoting one codex event line: not read as Codex (no format= line)" "$(node "$TJS" "$TR/p2.log" 2>/dev/null)" "format="
assert_no_path "plain text quoting one codex event line: no reply taken from the quoted line" "$TR/p2.log.result"
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

F3="$(node "$FJS" "$TR/c1.log" 2>/dev/null)"
assert_contains "codex facts: a cat of a playbook SKILL.md is a Bash, a Read and a Skill call, in that order" "$F3" "tool=Bash
tool=Read
tool=Skill"
assert_contains "codex facts: the Read call has the SKILL.md path" "$F3" "read=/home/u/.agents/skills/playbook-tdd/SKILL.md"
cat > "$TR/s1.log" <<'EOF'
{"type":"thread.started","thread_id":"t-s1"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"command_execution","command":"/bin/bash -lc 'ls /h/.agents/skills/playbook-tdd/SKILL.md'","aggregated_output":"","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_1","type":"command_execution","command":"/bin/bash -lc 'test -f /h/.agents/skills/playbook-tdd/SKILL.md && echo yes'","aggregated_output":"","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_2","type":"command_execution","command":"/bin/bash -lc \"rg 'skills/playbook-tdd/SKILL.md' src\"","aggregated_output":"","exit_code":1,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_3","type":"command_execution","command":"/bin/bash -lc 'echo skills/playbook-tdd/SKILL.md > notes.txt'","aggregated_output":"","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_4","type":"command_execution","command":"/bin/bash -lc 'cat src/a.js > skills/playbook-tdd/SKILL.md'","aggregated_output":"","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_5","type":"file_change","changes":[{"path":"/w/E19/tests/m.test.js","kind":"add"}],"status":"completed"}}
{"type":"item.completed","item":{"id":"item_6","type":"agent_message","text":"ok"}}
{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}
EOF
S1="$(node "$FJS" "$TR/s1.log" 2>/dev/null)"
assert_not_contains "codex: ls, test -f, an rg pattern, an echo and a redirect target naming SKILL.md are no Skill call" "$S1" "tool=Skill"
assert_not_contains "codex: ... and no Read call" "$S1" "tool=Read"
assert_eq "codex: no read-type command before the tests/ write: tdd_order=bad" "bad" "$(tkey "$TR/s1.log" tdd_order)"
cat > "$TR/s2.log" <<'EOF'
{"type":"thread.started","thread_id":"t-s2"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"command_execution","command":"/bin/bash -lc 'grep -n Weight skills/playbook-proof/SKILL.md'","aggregated_output":"","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_1","type":"command_execution","command":"/bin/bash -lc 'cd /w && head -n 20 x/playbook-learn/SKILL.md | wc -l'","aggregated_output":"","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_2","type":"command_execution","command":"/bin/bash -lc \"awk 'NR<5' skills/playbook-feedback/SKILL.md\"","aggregated_output":"","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_3","type":"agent_message","text":"ok"}}
{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}
EOF
S2="$(node "$FJS" "$TR/s2.log" 2>/dev/null)"
assert_eq "codex: grep with the path as its file, head after cd, awk with the path as its file: three Skill calls" "3" "$(printf '%s\n' "$S2" | grep -c '^tool=Skill$')"
assert_contains "codex: the grep read is a Read of that path" "$S2" "read=skills/playbook-proof/SKILL.md"

# skill reads of single commands (evals/codex-jsonl.js skillReads): sr NAME EXPECTED SCRIPT -> the skills read, comma separated
P="/h/.agents/skills/playbook-tdd/SKILL.md"; Q="/h/.agents/skills/playbook-proof/SKILL.md"
sr() { assert_eq "skill reads: $1" "$2" "$(node -e 'process.stdout.write(require(process.argv[1]).skillReads(process.argv[2]).map(r => r[1]).join(","))' "$PB_ROOT/evals/codex-jsonl.js" "$3" 2>&1)"; }
sr "cat of two paths in two commands" "playbook-tdd,playbook-proof" "cat $P; cat $Q"
sr "head -n 200 PATH (the -n value is skipped)" "playbook-tdd" "head -n 200 $P"
sr "rg -g PATH pattern src: a flag value, no read" "" "rg -g $P Weight src"
sr "grep -f PATH file: the pattern file is read" "playbook-tdd" "grep -f $P src/a.js"
sr "cd DIR && cat SKILL.md: the cd is followed" "playbook-tdd" "cd /h/.agents/skills/playbook-tdd && cat SKILL.md"
sr "brace expansion playbook-{tdd,proof}/SKILL.md" "playbook-tdd,playbook-proof" "cat ~/.agents/skills/playbook-{tdd,proof}/SKILL.md"
sr "sudo -u dev cat PATH" "playbook-tdd" "sudo -u dev cat $P"
sr "echo \"\$(cat PATH)\"" "playbook-tdd" "echo \"\$(cat $P)\""
sr "echo \`cat PATH\`" "playbook-tdd" "echo \`cat $P\`"
sr "echo PATH | xargs cat" "playbook-tdd" "echo $P | xargs cat"
sr "sed in place (-i.bak) on PATH is a write" "" "sed -i.bak 's/a/b/' $P"
sr "a heredoc body that names a cat of PATH is data" "" "cat > notes.sh <<'EOF'
cat $P
EOF"
sr "a heredoc written into PATH is a write" "" "cat <<EOF > $P
hello
EOF"
sr "a command after the heredoc body is still read" "playbook-proof" "cat > n.txt <<EOF
x
EOF
cat $Q"

# a short run with Codex's own stderr noise (rmcp / models ERROR lines, WARNING, Reading additional input) is still Codex
{ echo 'WARNING: proceeding, even though we could not create PATH aliases'
  echo 'Reading additional input from stdin...'
  for t in 05.729174 05.922185 06.310046 06.656755 07.658929 07.673645; do
    echo "2026-10-27T02:11:$t""Z ERROR rmcp::transport::worker: worker quit with fatal: Transport channel closed"
  done
  echo '{"type":"thread.started","thread_id":"t-n"}'
  echo '{"type":"turn.started"}'
  echo '{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"NO"}}'
  echo '{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}'
  echo '{"type":"thread.started","thread_id":"t-n2"}'
} > "$TR/n1.log"
rm -f "$TR/n1.log.result"
assert_eq "codex + stderr noise (5 events, 8 stderr lines): format=codex" "codex" "$(tkey "$TR/n1.log" format)"
assert_eq "codex + stderr noise: the reply is read" "NO" "$(cat "$TR/n1.log.result" 2>/dev/null)"

sr "command -v cat PATH: a lookup, no read" "" "command -v cat $P"
sr "timeout 5 cat PATH: a read" "playbook-tdd" "timeout 5 cat $P"
BR=""; for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22; do BR="$BR{a,b}"; done
assert_eq "braces: a 22-group word stops at 64 words and finishes in under 2 s" "fast" "$(node -e 'const t=Date.now();require(process.argv[1]).skillReads("cat x/"+process.argv[2]+"/playbook-tdd/SKILL.md");process.stdout.write(Date.now()-t<2000?"fast":"slow")' "$PB_ROOT/evals/codex-jsonl.js" "$BR" 2>&1)"

# stderr noise of any shape around a 9-event run: the event sequence decides, not the share of JSON lines
ev9() { cat <<'EOF'
{"type":"thread.started","thread_id":"t"}
{"type":"turn.started"}
{"type":"item.started","item":{"type":"command_execution","command":"ls","status":"in_progress"}}
{"type":"item.completed","item":{"type":"command_execution","command":"ls","exit_code":0}}
{"type":"item.started","item":{"type":"command_execution","command":"cat a","status":"in_progress"}}
{"type":"item.completed","item":{"type":"command_execution","command":"cat a","exit_code":0}}
{"type":"item.completed","item":{"type":"reasoning","text":"x"}}
{"type":"item.completed","item":{"type":"agent_message","text":"done"}}
{"type":"turn.completed","usage":{"input_tokens":1}}
EOF
}
{ ev9 | head -2; for i in 1 2 3 4 5 6 7 8 9 10 11 12; do echo "error: failed to connect to MCP server 'ps': connection refused"; done; ev9 | tail -n +3; } > "$TR/nb.log"
assert_eq "noise B: 12 untimestamped error lines inside a 9-event run: format=codex" "codex" "$(tkey "$TR/nb.log" format)"
{ ev9 | head -2; for i in 1 2 3 4 5 6 7 8 9 10; do printf '\033[2m2026-10-27T02:11:06.310046Z\033[0m \033[31mERROR\033[0m rmcp::transport::worker: closed\n'; done; ev9 | tail -n +3; } > "$TR/nb2.log"
assert_eq "noise B2: 10 ANSI-coloured timestamped ERROR lines: format=codex" "codex" "$(tkey "$TR/nb2.log" format)"
{ ev9 | head -8
  printf '%s\n' "thread 'tokio-runtime-worker' panicked at codex-rs/core/src/client.rs:412:17:" \
    'called `Result::unwrap()` on an `Err` value: Os { code: 32, kind: BrokenPipe }' \
    'note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace' 'stack backtrace:' \
    '   0: rust_begin_unwind' '   1: core::panicking::panic_fmt' '   2: core::result::unwrap_failed' \
    '   3: codex_core::client::stream' '   4: tokio::runtime::task::harness' '   5: std::sys::thread::unix::thread_start'
  ev9 | tail -1; } > "$TR/nc.log"
assert_eq "noise C: a Rust panic with a 6-frame backtrace: format=codex" "codex" "$(tkey "$TR/nc.log" format)"
{ printf '%s\n' 'WARNING: proceeding, even though we could not create PATH aliases:' \
    '  Refusing to create helper binaries under temporary dir "/w/tmp"' '  (codex_home: AbsolutePathBuf("/w/tmp/.codex"))' \
    '  Hint: set CODEX_HOME to a directory outside the temporary dir, or pass' '  --allow-temp-home to keep going. The helper binaries are used for:' \
    '    - apply_patch' '    - the sandbox launcher' '    - the shell snapshot' '  Without them, commands may run more slowly.' \
    '  See the docs for details.'
  ev9; } > "$TR/nd.log"
assert_eq "noise D: a 10-line indented WARNING block: format=codex" "codex" "$(tkey "$TR/nd.log" format)"
printf '%s\n' 'Notes:' '{"type":"thread.started","thread_id":"x"}' '{"type":"turn.started"}' 'Shall I continue?' > "$TR/ne3.log"
assert_not_contains "plain text quoting thread.started and turn.started only: not Codex" "$(node "$TJS" "$TR/ne3.log" 2>/dev/null)" "format="
printf '%s\n' 'Here is the log:' '2026-10-27T02:11:05Z ERROR codex: x' '2026-10-27T02:11:05Z ERROR codex: y' '{"type":"thread.started","thread_id":"x"}' 'Shall I continue?' > "$TR/ne2.log"
assert_not_contains "plain text quoting one event and two timestamped lines: not Codex" "$(node "$TJS" "$TR/ne2.log" 2>/dev/null)" "format="

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
mk_codex_cmd "$TR/i4.log" "\"/bin/bash -lc 'ls $H/.agents/skills/playbook-tdd/SKILL.md'\""
assert_eq "codex iso: an ls of HOME/.agents/skills/... (no read) still FAILs: the check stays strict" "FAIL" "$(pbh_iso_check "$TR/i4.log" "$H" /w/E3 "" "" playbook-proof playbook-tdd)"
printf '%s\n' '{"type":"thread.started","thread_id":"t-p"}' '{"type":"turn.started"}' \
  '{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"NO"}}' \
  '{"type":"turn.failed","error":{"message":"stream disconnected"}}' > "$TR/i5.log"
assert_eq "codex probe: a failed last turn has no answer: UNKNOWN" "UNKNOWN" "$(pbh_probe_answer "$TR/i5.log")"

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
assert_eq "runner E29 codex: no AskUserQuestion call: MANUAL (n/a, not an inflated PASS)" "MANUAL" "$(e_state E29 'no AskUserQuestion tool call in the transcript')"
assert_contains "runner E29 codex: the detail says n/a for Codex" "$(printf '%s\n' "$OUT" | grep '^E29 MANUAL no AskUserQuestion')" "(detail: n/a: Codex has no AskUserQuestion tool)"
assert_contains "runner E29 codex: the JSON key of the check is unchanged" "$(cat "$XW/results.json" 2>/dev/null)" '"key": "no AskUserQuestion tool call in the transcript"'
cx_run E2 none "$TR/r29.log"
assert_eq "runner E2 codex headless: no AskUserQuestion call: MANUAL" "MANUAL" "$(e_state E2 'headless: no AskUserQuestion call in the transcript')"
assert_contains "runner E2 codex: the detail says n/a for Codex" "$(printf '%s\n' "$OUT" | grep '^E2 MANUAL headless: no AskUserQuestion')" "(detail: n/a: Codex has no AskUserQuestion tool)"
cx_run E26 none "$TR/r29.log"
assert_eq "runner E26 codex: no AskUserQuestion call: MANUAL" "MANUAL" "$(e_state E26 'no AskUserQuestion tool call in the transcript')"
assert_contains "runner E26 codex: the detail says n/a for Codex" "$(printf '%s\n' "$OUT" | grep '^E26 MANUAL no AskUserQuestion')" "(detail: n/a: Codex has no AskUserQuestion tool)"

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
