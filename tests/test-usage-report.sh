#!/usr/bin/env bash
# Tests for tools/usage-report.js (token report from a Claude Code transcript)
. "$(dirname "$0")/lib.sh"
UR="$PB_ROOT/tools/usage-report.js"

if ! command -v node >/dev/null 2>&1; then
  t_skip 1 "node is not installed"
  t_summary
  exit 0
fi

# asst ID MODEL TIME CACHE_WRITE CACHE_READ OUTPUT [CONTENT_JSON]  -> one assistant line
asst() {
  printf '{"type":"assistant","timestamp":"%s","message":{"id":"%s","model":"%s","usage":{"input_tokens":2,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":%s},"content":%s}}\n' \
    "$3" "$1" "$2" "$4" "$5" "$6" "${7:-[]}"
}
agent_use() { printf '[{"type":"tool_use","id":"%s","name":"Agent","input":{"description":"%s","prompt":"%s"}}]' "$1" "$2" "$3"; }
J() { printf '%s' "$OUT" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const o=JSON.parse(s);console.log(eval(process.argv[1]))})' "$1"; }

D="$(mk_tmp)"
S="$D/sess"; mkdir -p "$D/sess/subagents"

# main thread: two calls 1 min apart, one of them repeated per content block (same id), then a call 3 h later that writes a lot
{
  asst m1 claude-opus-5-5 2026-01-01T10:00:00.000Z 1000 5000 10 "$(agent_use toolu_T 'Tester: slice A' 'Read and follow skills/playbook-tdd/roles/tester.md')"
  asst m1 claude-opus-5-5 2026-01-01T10:00:00.500Z 1000 5000 40
  asst m2 claude-opus-5-5 2026-01-01T10:01:00.000Z 200 6000 20
  asst m3 claude-opus-5-5 2026-01-01T13:01:00.000Z 500000 0 30
  asst sx '<synthetic>' 2026-01-01T13:02:00.000Z 0 0 0
} > "$D/sess.jsonl"

# sub-agent 1: role from the role file in the Agent prompt (the description says nothing useful)
printf '{"toolUseId":"toolu_T","description":"Tester: slice A"}' > "$S/subagents/agent-a1.meta.json"
{ printf '{"type":"user","message":{"role":"user","content":"go"}}\n'
  asst s1 claude-sonnet-5-5 2026-01-01T10:00:30.000Z 3000 10000 100
  asst s2 claude-sonnet-5-5 2026-01-01T10:00:40.000Z 100 13000 50
} > "$S/subagents/agent-a1.jsonl"

# sub-agent 2: no Agent registry entry, role from the description; sub-agent 3: Haiku mechanical; sub-agent 4: no role word
printf '{"toolUseId":"toolu_none","description":"Reviewer lane B"}' > "$S/subagents/agent-a2.meta.json"
asst s3 claude-opus-5-5 2026-01-01T10:02:00.000Z 400 8000 5 > "$S/subagents/agent-a2.jsonl"
printf '{"toolUseId":"toolu_none2","description":"Mechanical: split suite"}' > "$S/subagents/agent-a3.meta.json"
asst s4 claude-haiku-5-5 2026-01-01T10:03:00.000Z 50 900 1 > "$S/subagents/agent-a3.jsonl"
printf '{"toolUseId":"toolu_none3","description":"Look around"}' > "$S/subagents/agent-a4.meta.json"
asst s5 claude-sonnet-5-5 2026-01-01T10:04:00.000Z 10 20 1 > "$S/subagents/agent-a4.jsonl"

echo "usage-report.js"

run node "$UR" --json "$D/sess.jsonl"
assert_rc "json run exits 0" 0
# 3 main calls (m1 counted once, synthetic skipped) + 5 sub-agent calls
assert_eq "one call per message id, synthetic skipped" "8" "$(J 'o.total.calls')"
assert_eq "cache write sums the largest value per id" "504760" "$(J 'o.total.cache_write')"
assert_eq "output takes the largest value per id" "247" "$(J 'o.total.output')"
assert_eq "orchestrator row counts the main thread" "3" "$(J 'o.by_role.find(r=>r.role=="orchestrator").calls')"
assert_eq "role comes from the role file in the Agent prompt" "2" "$(J 'o.by_role.find(r=>r.role=="tester").calls')"
assert_eq "tester cache write" "3100" "$(J 'o.by_role.find(r=>r.role=="tester").cache_write')"
assert_eq "role comes from the description when no prompt names one" "1" "$(J 'o.by_role.find(r=>r.role=="reviewer").calls')"
assert_eq "a Mechanical description is the mechanical role" "1" "$(J 'o.by_role.find(r=>r.role=="mechanical").calls')"
assert_eq "no role word means other" "1" "$(J 'o.by_role.find(r=>r.role=="other").calls')"
assert_eq "by_model lists haiku" "1" "$(J 'o.by_model.find(m=>m.model=="claude-haiku-5-5").calls')"
assert_eq "a 3 h gap splits the main thread in two segments" "2" "$(J 'o.segments.length')"
assert_eq "one cold restart" "1" "$(J 'o.cold_restarts.count')"
assert_eq "the cold restart wrote 500000 tokens" "500000" "$(J 'o.cold_restarts.cache_write')"
assert_eq "the cold restart idle time is 180 min" "180" "$(J 'o.cold_restarts.calls[0].idle_minutes')"

run node "$UR" "$D/sess.jsonl"
assert_rc "markdown run exits 0" 0
assert_contains "markdown has the role table" "$OUT" "## By role"
assert_contains "markdown has the segments table" "$OUT" "## Main-thread segments (split on idle gaps over 60 min)"
assert_contains "markdown names the cold restart share" "$OUT" "1 restarts wrote 0.50M cache tokens, 99% of all cache write."

run node "$UR" --gap 300 --json "$D/sess.jsonl"
assert_eq "--gap 300 keeps one segment" "1" "$(J 'o.segments.length')"
assert_eq "--gap 300 has no cold restart" "0" "$(J 'o.cold_restarts.count')"
run node "$UR" --big 600000 --json "$D/sess.jsonl"
assert_eq "--big above the write has no cold restart" "0" "$(J 'o.cold_restarts.count')"

# prices
printf '{"claude-opus-5-5":{"input":10,"cache_write":20,"cache_read":1,"output":50}}' > "$D/prices.json"
run node "$UR" --json --prices "$D/prices.json" "$D/sess.jsonl"
assert_rc "priced run exits 0" 0
# opus: input 2*4=8, write 1000+200+500000+400=501600, read 5000+6000+0+8000=19000, out 40+20+30+5=95
assert_eq "USD from the price file (opus only)" "10.0558" "$(J 'o.usd.toFixed(4)')"
assert_contains "models without a price are named" "$OUT" '"models_without_price":["claude-sonnet-5-5","claude-haiku-5-5"]'
run node "$UR" --prices "$D/prices.json" "$D/sess.jsonl"
assert_contains "markdown says which models have no price" "$OUT" "no price for claude-sonnet-5-5, claude-haiku-5-5 (counted as 0)"

# no sub-agent folder
{ asst only claude-opus-5-5 2026-01-01T10:00:00.000Z 10 20 5; } > "$D/solo.jsonl"
run node "$UR" "$D/solo.jsonl"
assert_rc "a transcript without sub-agents exits 0" 0
assert_contains "it says only the orchestrator is counted" "$OUT" "only the orchestrator is counted"

# errors
run node "$UR"
assert_rc "no argument is a usage error" 2
run node "$UR" --nope "$D/sess.jsonl"
assert_rc "an unknown option is a usage error" 2
run node "$UR" --gap 0 "$D/sess.jsonl"
assert_rc "--gap 0 is a usage error" 2
run node "$UR" --latest "$D/sess.jsonl"
assert_rc "--latest with a file is a usage error" 2
run node "$UR" --prices "$D/missing.json" "$D/sess.jsonl"
assert_rc "an unreadable price file is a usage error" 2
run node "$UR" "$D/missing.jsonl"
assert_rc "a missing transcript exits 3" 3
printf '{"type":"user","message":{"role":"user","content":"hi"}}\n' > "$D/nousage.jsonl"
run node "$UR" "$D/nousage.jsonl"
assert_rc "a transcript with no usage exits 3" 3

# a torn last line does not stop the report
{ asst t1 claude-opus-5-5 2026-01-01T10:00:00.000Z 10 20 5; printf '{"type":"assis'; } > "$D/torn.jsonl"
run node "$UR" --json "$D/torn.jsonl"
assert_rc "a torn last line is ignored" 0
assert_eq "the complete line still counts" "1" "$(J 'o.total.calls')"

t_summary
