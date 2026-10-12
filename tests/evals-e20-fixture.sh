#!/usr/bin/env bash
# Shared setup of tests/test-evals-grade2-e20.sh and its split part (test-evals-grade2-e20-capture.sh; split in v0.24.1 so that neither part is
# the floor of a CI shard): tu, the E20 fixture command, the transcript lines, run_e20 and count_old. Source it after lib.sh and evals-fixture.sh.
# It is not a suite: run-all.sh only starts tests/test-*.sh.
# tu TOOL INPUT-JSON -> an assistant line with one tool_use (the same helper as in test-evals-grade2.sh)
tu() { printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u1","name":"%s","input":%s}]}}' "$1" "$2"; }
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
