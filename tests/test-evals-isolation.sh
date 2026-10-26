#!/usr/bin/env bash
# Tests for the isolation check of the without arm of evals/run-evals.sh (v0.26.0 lane E, spec .agents/handoff/01-spec.md
# slice S4, AC4.1-AC4.2): every graded without run gets the check "without arm: no playbook file read and no playbook Skill
# call", graded from the stream-json transcript. Never calls a real harness: a --cmd fake adapter prints a canned
# transcript per run label (evals-fixture.sh mk_adapter), HOME is a stand-in (evals-arms-fixture.sh mk_home).
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-arms-fixture.sh"

ISO='without arm: no playbook file read and no playbook Skill call'
# iso_state LABEL -> PASS/FAIL/MANUAL of the isolation check line of LABEL ("" when there is none)
iso_state() { e_state "$1" "$ISO"; }

# The adapter prints one transcript per run label. k picks the case; every case ends with a success result line.
# tu NAME INPUT-JSON -> one assistant line with one tool_use block
mk_adapter isot 'tu() { printf "{\"type\":\"assistant\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"tool_use\",\"id\":\"t1\",\"name\":\"%s\",\"input\":%s}]}}\n" "$1" "$2"; }
k="${e##*.}"
case "$e" in *.with.*) k=1 ;; esac
CLEAN_INIT="{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"s1\",\"skills\":[\"other-skill\"],\"slash_commands\":[\"other-cmd\"]}"
case "$k" in
  7) echo "{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"s1\",\"skills\":[\"other-skill\",\"playbook-proof\"],\"slash_commands\":[]}" ;;
  8) echo "{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"s1\",\"skills\":[],\"slash_commands\":[\"other-cmd\",\"playbook-setup\"]}" ;;
  13) echo "plain text output, not stream-json" ;;
  *) echo "$CLEAN_INIT" ;;
esac
case "$k" in
  1) tu Skill "{\"skill\":\"playbook-tdd\"}" ;;
  2) tu Read "{\"file_path\":\"$HOME/.agents/playbook/scripts/proof-run.sh\"}" ;;
  3) tu Bash "{\"command\":\"cat $HOME/.claude/skills/playbook-proof/SKILL.md\"}" ;;
  4) tu Grep "{\"pattern\":\"weight\",\"path\":\"~/.agents/playbook\"}" ;;
  5) tu Read "{\"file_path\":\"$HOME/.claude/CLAUDE.md\"}" ;;
  6) tu Edit "{\"file_path\":\"/opt/elsewhere/skills/playbook-learn/SKILL.md\",\"old_string\":\"a\",\"new_string\":\"b\"}" ;;
  9) tu Read "{\"file_path\":\"$wd/.agents/handoff/01-spec.md\"}"
     tu Read "{\"file_path\":\".agents/handoff/01-spec.md\"}"
     tu Bash "{\"command\":\"cat .agents/playbook.conf\"}"
     tu Glob "{\"pattern\":\".agents/**\"}" ;;
  10) tu Read "{\"file_path\":\"$PLAYBOOK_HOME/.agents/playbook.conf\"}"
      tu Read "{\"file_path\":\"$PB_EVAL_SETTINGS\"}" ;;
  11) tu Agent "{\"description\":\"look around\",\"prompt\":\"read ~/.agents/playbook and $HOME/.claude/skills/playbook-tdd/SKILL.md\"}" ;;
  12) tu Skill "{\"skill\":\"other-skill\"}"
      tu Read "{\"file_path\":\"$HOME/notes/todo.md\"}"
      tu Read "{\"file_path\":\"$HOME/.agents-old/x.md\"}" ;;
  14) tu Read "{\"file_path\":\"/opt/team/.claude/skills/playbook-tdd/roles/tester.md\"}" ;;
esac
if [ "$k" != 13 ]; then
  if [ "$k" = 11 ]; then echo "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"total_cost_usd\":0.01,\"result\":\"I did not open ~/.agents/playbook.\"}"
  else echo "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"total_cost_usd\":0.01,\"result\":\"Done.\"}"; fi
fi
true'

echo "S4 AC4.1/AC4.2 --arm without --repeat 14: one transcript case per run"
go --cmd "bash $A/isot.sh" --arm without --repeat 14 --scenarios E8
# k -> expected result and what the transcript holds
iso_case() { # K EXPECTED WHAT
  local L="E8.without.$1"
  assert_eq "$3 -> the isolation check is $2 ($L)" "$2" "$(iso_state "$L")"
}
iso_case 1 FAIL "AC4.1 a Skill tool_use whose skill is playbook-tdd"
iso_case 2 FAIL "AC4.1 a Read of \$HOME/.agents/playbook/scripts/proof-run.sh"
iso_case 3 FAIL "AC4.1 a Bash command cat \$HOME/.claude/skills/playbook-proof/SKILL.md"
iso_case 4 FAIL "AC4.1 a Grep with path ~/.agents/playbook (literal tilde)"
iso_case 5 FAIL "AC4.1 a Read of \$HOME/.claude/CLAUDE.md"
iso_case 6 FAIL "AC4.1 an Edit of <dir>/playbook-learn/SKILL.md (a playbook skill's SKILL.md outside HOME)"
iso_case 7 FAIL "AC4.1 the system init line lists the skill playbook-proof"
iso_case 8 FAIL "AC4.1 the system init line lists the slash command playbook-setup"
iso_case 9 PASS "AC4.2 reads of the fixture's own .agents/ (absolute, relative, Bash cat, Glob)"
iso_case 10 PASS "AC4.2 reads of the temp PLAYBOOK_HOME and of the runner's settings file"
iso_case 11 PASS "AC4.1 an Agent prompt naming ~/.agents and a playbook SKILL.md (Agent prompt excluded) and a reply text naming ~/.agents"
iso_case 12 PASS "AC4.1 a non-playbook Skill call and reads under HOME outside .agents/ (\$HOME/notes, \$HOME/.agents-old)"
iso_case 13 MANUAL "AC4.1 a log that is not stream-json"
iso_case 14 FAIL "fix4 a Read under another .claude/skills/playbook-tdd/ (not SKILL.md, outside HOME): the .claude/skills/playbook- path"
assert_eq "AC4.1 each without run gets the isolation check once (E8.without.1)" "1" "$(printf '%s\n' "$OUT" | grep '^E8\.without\.1 ' | grep -cF "$ISO")"
assert_eq "AC4.1 each without run gets the isolation check once (E8.without.12)" "1" "$(printf '%s\n' "$OUT" | grep '^E8\.without\.12 ' | grep -cF "$ISO")"
assert_rc "AC4.1 an isolation FAIL is a FAIL: exit 1 (AC2.6)" 1
assert_eq "AC4.1 the other checks still run: E8.without.1 'tests/calc.test.js still exists'" "PASS" "$(e_state E8.without.1 'tests/calc.test.js still exists')"
assert_contains "AC4.1 the md lists the isolation check of a without run" "$(cat "$RES" 2>/dev/null)" "$ISO"

echo "S4 AC4.1 the with arm never gets the isolation check (even with a playbook Skill call in its transcript)"
go --cmd "bash $A/isot.sh" --arm both --scenarios E8
assert_eq "AC4.1 E8.with.1 has no isolation check line" "0" "$(printf '%s\n' "$OUT" | grep '^E8\.with\.1 ' | grep -cF "$ISO")"
assert_eq "AC4.1 E8.without.1 (Skill playbook-tdd) FAILs the isolation check" "FAIL" "$(iso_state E8.without.1)"
assert_eq "AC4.1 E8.with.1 is graded (its other checks run)" "PASS" "$(e_state E8.with.1 'tests/calc.test.js still exists')"

echo "S4 AC4.1 the default mode (no --arm) has no isolation check"
go --cmd "bash $A/isot.sh" --scenarios E8
assert_eq "AC4.1 default mode: no isolation check line" "0" "$(printf '%s\n' "$OUT" | grep -cF "$ISO")"

echo "H5 (v0.28.0) pbh_iso_check reads Windows backslash paths of real transcripts (Run 25b/28 wording, user name anonymised)"
. "$PB_ROOT/evals/lib-harness.sh"
H5D="$(mk_tmp)"
# h5 LABEL EXPECT HOME OK1 TOOL INPUT-JSON: a one-line transcript with one tool_use, checked with the names playbook-tdd playbook-proof
h5() {
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"%s","input":%s}]}}\n' "$5" "$6" > "$H5D/log"
  assert_eq "$1" "$2" "$(pbh_iso_check "$H5D/log" "$3" "$4" "" "" playbook-tdd playbook-proof)"; }
HP='/c/Users/tester'; HW='C:/Users/tester'; WDP='/c/Users/tester/pbeval/r28/E/E4.without.1'
h5 "H5 Read C:\\Users\\tester\\.claude\\skills\\playbook-tdd\\roles\\tester.md (HOME /c/Users/tester): FAIL" FAIL "$HP" "$WDP" Read \
  '{"file_path":"C:\\Users\\tester\\.claude\\skills\\playbook-tdd\\roles\\tester.md"}'
h5 "H5 Read C:\\Users\\tester\\.agents\\playbook\\scripts\\proof-run.sh (HOME /c/Users/tester): FAIL" FAIL "$HP" "$WDP" Read \
  '{"file_path":"C:\\Users\\tester\\.agents\\playbook\\scripts\\proof-run.sh"}'
h5 "H5 Bash cat C:\\Users\\tester\\.agents\\playbook.conf (HOME C:/Users/tester): FAIL" FAIL "$HW" "$WDP" Bash \
  '{"command":"cat C:\\Users\\tester\\.agents\\playbook.conf"}'
h5 "H5 Read with a lower-case drive c:\\Users\\tester\\.agents\\x.md (HOME /c/Users/tester): FAIL" FAIL "$HP" "$WDP" Read \
  '{"file_path":"c:\\Users\\tester\\.agents\\x.md"}'
h5 "H5 Read D:\\team\\playbook-proof\\SKILL.md (a playbook skill name): FAIL" FAIL "$HP" "$WDP" Read \
  '{"file_path":"D:\\team\\playbook-proof\\SKILL.md"}'
h5 "H5 control: the workdir's own .agents in backslash form (Run 28 E4.without.1): PASS" PASS "$HP" "$WDP" Read \
  '{"file_path":"C:\\Users\\tester\\pbeval\\r28\\E\\E4.without.1\\.agents\\handoff\\01-spec.md"}'
h5 "H5 control: the workdir's own .agents in mixed form (Run 28 E4.without.2 style): PASS" PASS "$HP" "$WDP" Read \
  '{"file_path":"C:\\Users\\tester\\pbeval\\r28\\E\\E4.without.1\\.agents/handoff/01-spec.md"}'
h5 "H5 control: a playbook skill under the allowed PLAYBOOK_HOME in backslash form: PASS" PASS "$HP" "/c/Users/tester/AppData/Local/Temp/pbh" Read \
  '{"file_path":"C:\\Users\\tester\\AppData\\Local\\Temp\\pbh\\.claude\\skills\\playbook-tdd\\SKILL.md"}'
h5 "H5 control: C:\\Users\\tester\\.agents-old\\x.md is not .agents: PASS" PASS "$HP" "$WDP" Read \
  '{"file_path":"C:\\Users\\tester\\.agents-old\\x.md"}'

t_summary
