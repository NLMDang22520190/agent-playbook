#!/usr/bin/env bash
# Tests for the v0.25.1 grader grade_E31 of evals/run-evals.sh: the humanizer question in an INTERACTIVE run (user decision 2026-10-25: add E31, run it for real later).
# Never calls a real harness: every run uses --cmd with a fake adapter that prints a stream-json transcript (see evals-fixture.sh, evals-grade6-fixture.sh).
# The checks, each graded on the transcript (--interactive only; a headless run asks nothing by the playbook rule, so it is MANUAL there):
#   (a) KA31 "at least one question": a question to the user that mentions humanizer: an AskUserQuestion tool call whose input names humanizer, or a line of the
#       final reply (outside fenced blocks and quotes) with a "?" and the word humanizer; any case
#   (b) KB31 "at most one question": at most one such question (the larger of the tool-call count and the prose count, so a question that is restated is one)
#   MANUAL when the log is not stream-json (no tool data); MANUAL: the release notes follow the writing guide (KC31)
# The fixture: the E30 setup commit (clamp) plus a stub humanizer skill (name humanizer, a one-line description), a project skill in the work dir (committed
# before the clamp commit, so the last commit is the clamp one) and a copy under the scenario playbook home.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-grade6-fixture.sh"
. "$(dirname "$0")/evals-grade8-fixture.sh"
. "$(dirname "$0")/evals-grade10-fixture.sh"

KA31='at least one question'; KB31='at most one question'; KC31='follow the writing guide'
AQH() { tu AskUserQuestion '{"questions":[{"question":"Run the humanizer skill in full on the release notes?","header":"Humanizer","options":[{"label":"Yes","description":"d"},{"label":"No","description":"e"}],"multiSelect":false}]}'; }
AQO() { tu AskUserQuestion '{"questions":[{"question":"Which audience is this for?","header":"Audience","options":[{"label":"Users","description":"d"},{"label":"Devs","description":"e"}],"multiSelect":false}]}'; }
# x31 NAME MODE REPLY [TRANSCRIPT-LINE...]: one E31 run (MODE int = --interactive, head = headless) whose final reply is REPLY; sets OUT, RC
x31() { local n="$1" m="$2" reply="$3" line; shift 3
  line="$(R30TXT="$reply" node -e 'process.stdout.write(JSON.stringify({type:"result",subtype:"success",is_error:false,result:process.env.R30TXT}))')"
  jl "x31$n" "$INIT" "$@" "$line"
  mk_adapter "E31$n" "$NOOP
cat $J/x31$n.json"
  XW="$(mk_tmp)"
  if [ "$m" = int ]; then run bash "$RUNNER" --interactive --cmd "bash $A/E31$n.sh" --scenarios E31 --workroot "$XW" --out "$XW/results.md"
  else run bash "$RUNNER" --cmd "bash $A/E31$n.sh" --scenarios E31 --workroot "$XW" --out "$XW/results.md"; fi; }
N31=0
# row31 KEY EXPECT LABEL REPLY [TRANSCRIPT-LINE...]: an interactive run, asserts the state of the check KEY
row31() { local k="$1" e="$2" l="$3" r="$4"; shift 4; N31=$((N31 + 1)); x31 "r$N31" int "$r" "$@"; assert_eq "$l" "$e" "$(e_state E31 "$k")"; }
RN='Release notes: you can now limit a number to a range with `clamp(x, lo, hi)`.'

echo "E31 (a) and (b): the AskUserQuestion call that mentions humanizer"
row31 "$KA31" PASS "a1 one AskUserQuestion naming humanizer: (a) PASS" "$RN" "$(AQH)"
row31 "$KB31" PASS "b1 one AskUserQuestion naming humanizer: (b) PASS" "$RN" "$(AQH)"
row31 "$KA31" FAIL "a2 no question at all: (a) FAIL" "$RN"
row31 "$KB31" PASS "b2 no question at all: (b) PASS (at most one)" "$RN"
row31 "$KA31" FAIL "a3 a question that does not mention humanizer: (a) FAIL" "$RN" "$(AQO)"
row31 "$KB31" PASS "b3 a question that does not mention humanizer: (b) PASS" "$RN" "$(AQO)"
row31 "$KA31" PASS "a4 an unrelated question plus the humanizer question: (a) PASS" "$RN" "$(AQO)" "$(AQH)"
row31 "$KB31" PASS "b4 an unrelated question plus one humanizer question: (b) PASS" "$RN" "$(AQO)" "$(AQH)"
row31 "$KA31" PASS "a5 two humanizer questions: (a) PASS" "$RN" "$(AQH)" "$(AQH)"
row31 "$KB31" FAIL "b5 two humanizer questions: (b) FAIL (asked more than once)" "$RN" "$(AQH)" "$(AQH)"
row31 "$KA31" PASS "a6 the word in capitals, HUMANIZER, counts" "$RN" "$(tu AskUserQuestion '{"questions":[{"question":"Use HUMANIZER?","header":"h","options":[{"label":"a","description":"d"},{"label":"b","description":"e"}],"multiSelect":false}]}')"
row31 "$KA31" PASS "a7 the name may sit in an option label only" "$RN" "$(tu AskUserQuestion '{"questions":[{"question":"Polish the text?","header":"h","options":[{"label":"Run humanizer","description":"d"},{"label":"Skip","description":"e"}],"multiSelect":false}]}')"
row31 "$KA31" FAIL "a8 other tool calls only: (a) FAIL" "$RN" "$(tu Bash '{"command":"git log -1"}')"

echo "E31 (a) and (b): a question in the final reply (a plain-text question line)"
row31 "$KA31" PASS "a9 a prose question naming humanizer: (a) PASS" "Should I run the humanizer skill on these notes?
$RN"
row31 "$KB31" PASS "b9 one prose question naming humanizer: (b) PASS" "Should I run the humanizer skill on these notes?
$RN"
row31 "$KA31" FAIL "a10 a prose line naming humanizer without a question mark: (a) FAIL" "I did not run the humanizer skill.
$RN"
row31 "$KA31" FAIL "a11 a question mark in a fenced block does not count: (a) FAIL" "$RN
\`\`\`
Should I run the humanizer skill?
\`\`\`"
row31 "$KA31" FAIL "a12 a quoted line does not count: (a) FAIL" "$RN
> Should I run the humanizer skill?"
row31 "$KB31" FAIL "b10 two prose questions naming humanizer: (b) FAIL" "Run the humanizer skill in full?
Or should the humanizer run only on the title?
$RN"
row31 "$KB31" PASS "b11 the tool call restated once in prose is one question: (b) PASS (the larger count, not the sum)" "Run the humanizer skill in full?
$RN" "$(AQH)"

echo "E31 no tool data and headless: MANUAL"
XW="$(mk_tmp)"; mk_adapter E31pl "$NOOP
echo 'plain text, not json'"
run bash "$RUNNER" --interactive --cmd "bash $A/E31pl.sh" --scenarios E31 --workroot "$XW" --out "$XW/results.md"
assert_eq "plain log, interactive: (a) is MANUAL" "MANUAL" "$(e_state E31 "$KA31")"
assert_eq "plain log, interactive: (b) is MANUAL" "MANUAL" "$(e_state E31 "$KB31")"
x31 head head "$RN" "$(AQH)"
assert_eq "headless run with the humanizer question: (a) is MANUAL (the playbook asks nothing headless)" "MANUAL" "$(e_state E31 "$KA31")"
assert_eq "headless run with the humanizer question: (b) is MANUAL" "MANUAL" "$(e_state E31 "$KB31")"
row31 "$KC31" MANUAL "c1 the release-notes writing check is MANUAL" "$RN" "$(AQH)"

echo "E31 the fixture and the prompt"
IFS= read -r -d '' FIX31 <<'EOF_B' || true
git log --format=%s > "$REC/E31.log" 2>&1
git status --porcelain | wc -l | tr -d ' ' > "$REC/E31.clean"
head -4 .claude/skills/humanizer/SKILL.md > "$REC/E31.skill" 2>&1
head -4 "$PLAYBOOK_HOME/.claude/skills/humanizer/SKILL.md" > "$REC/E31.homeskill" 2>&1
node -e 'process.stdout.write(String(require("./src/calc").clamp(5, 0, 3)))' > "$REC/E31.clamp" 2>&1
git ls-files > "$REC/E31.files" 2>&1
EOF_B
rm -f "$REC/E31.log" "$REC/E31.clean" "$REC/E31.skill" "$REC/E31.homeskill" "$REC/E31.clamp" "$REC/E31.files" "$REC/E31.prompt"
jl x31fix "$INIT" "$(res "$RN")"
mk_adapter E31fix "$FIX31
cat $J/x31fix.json"
XW="$(mk_tmp)"
run bash "$RUNNER" --interactive --cmd "bash $A/E31fix.sh" --scenarios E31 --workroot "$XW" --out "$XW/results.md"
assert_eq "fixture: the last commit is the clamp commit" "feat: clamp" "$(head -n 1 "$REC/E31.log" 2>/dev/null)"
assert_eq "fixture: the setup is committed (clean work tree at the start)" "0" "$(cat "$REC/E31.clean" 2>/dev/null)"
assert_eq "fixture: clamp(5,0,3) is 3" "3" "$(cat "$REC/E31.clamp" 2>/dev/null)"
assert_contains "fixture: the project stub skill is tracked" "$(cat "$REC/E31.files" 2>/dev/null)" ".claude/skills/humanizer/SKILL.md"
assert_contains "fixture: the stub skill is named humanizer" "$(cat "$REC/E31.skill" 2>/dev/null)" "name: humanizer"
assert_contains "fixture: the stub description is the one-liner" "$(cat "$REC/E31.skill" 2>/dev/null)" "description: Rewrite AI-sounding text so it reads like the writer"
assert_contains "fixture: the scenario playbook home has the stub skill too" "$(cat "$REC/E31.homeskill" 2>/dev/null)" "name: humanizer"
P31="$(cat "$REC/E31.prompt" 2>/dev/null | tr 'A-Z' 'a-z')"
assert_contains "the prompt asks for the release notes" "$P31" "release notes"
assert_contains "the prompt is about the last commit" "$P31" "last commit"
assert_contains "the prompt says the notes are for users" "$P31" "users"
assert_not_contains "the interactive prompt has no non-interactive line" "$P31" "non-interactive run"
x31 hp head "$RN"
assert_contains "the headless prompt has the non-interactive line" "$(cat "$REC/E31.prompt" 2>/dev/null)" "Non-interactive run"

echo "E31 is auto-gradable: the idle adapter is graded, exit 0 or 1"
W="$(mk_tmp)"
run bash "$RUNNER" --interactive --cmd "bash $A/idle.sh" --scenarios E31 --workroot "$W" --out "$W/results.md"
assert_not_contains "E31 is accepted (not a usage error)" "$OUT" "not auto-gradable"
assert_eq "E31: the idle adapter is graded (a check line for E31)" "graded" "$([ "$(printf '%s\n' "$OUT" | grep -cE '^E31 (PASS|FAIL|MANUAL) ')" -gt 0 ] && echo graded || echo not-graded)"
case "$RC" in 0|1) t_ok "E31: the idle adapter exits 0 or 1" ;; *) t_bad "E31: the idle adapter exits 0 or 1" "exit $RC; output: $OUT" ;; esac

echo "E31 is registered where E30 is"
RUNEV31="$PB_ROOT/evals/run-evals.sh"
AUTOLINE31="$(grep '^AUTO=' "$RUNEV31")"
if printf '%s' "$AUTOLINE31" | grep -qE '[" ]E31[" ]'; then t_ok "E31 is in the AUTO list of run-evals.sh"; else t_bad "E31 is in the AUTO list of run-evals.sh" "line: [$AUTOLINE31]"; fi
if grep -qE '^grade_E31\(\)' "$RUNEV31"; then t_ok "run-evals.sh defines grade_E31"; else t_bad "run-evals.sh defines grade_E31" "no grade_E31() in run-evals.sh"; fi
if grep -q 'E31_BASE=' "$RUNEV31"; then t_ok "run-evals.sh records E31_BASE"; else t_bad "run-evals.sh records E31_BASE" "no E31_BASE= in run-evals.sh"; fi
MAPAG31="$(grep -E '^AGENTS\.global\.md ' "$PB_ROOT/evals/scenario-map")"
MAPPR31="$(grep -E '^skills/playbook-proof/\* ' "$PB_ROOT/evals/scenario-map")"
if printf '%s' "$MAPAG31" | grep -qE '(^| )E31( |$)'; then t_ok "E31 is on the AGENTS.global.md scenario-map line"; else t_bad "E31 is on the AGENTS.global.md scenario-map line" "line: [$MAPAG31]"; fi
if printf '%s' "$MAPPR31" | grep -qE '(^| )E31( |$)'; then t_ok "E31 is on the skills/playbook-proof/* scenario-map line"; else t_bad "E31 is on the skills/playbook-proof/* scenario-map line" "line: [$MAPPR31]"; fi
if printf '%s' "$MAPPR31" | grep -qE '(^| )E30( |$)'; then t_ok "the playbook-proof map line keeps E30"; else t_bad "the playbook-proof map line keeps E30" "line: [$MAPPR31]"; fi
RUBTXT31="$(tr '\n' ' ' < "$PB_ROOT/evals/RUBRIC.md")"
if printf '%s' "$RUBTXT31" | grep -qE 'E31[^.]{0,200}auto-gradable'; then t_ok "RUBRIC.md lists E31 as auto-gradable"; else t_bad "RUBRIC.md lists E31 as auto-gradable" "no E31 before auto-gradable"; fi

echo "E31 the scenarios.md section"
SCEN31="$PB_ROOT/evals/scenarios.md"
E31S="$(awk -v h='## E31 ' 'index($0, h) == 1 { f = 1; next } f && /^## / { exit } f { print }' "$SCEN31" | tr '\n' ' ')"
s31() { if printf '%s' "$E31S" | grep -qiE -- "$2"; then t_ok "$1"; else t_bad "$1" "pattern [$2] not found in the E31 section"; fi; }
if grep -qE '^## E31 [A-Za-z]' "$SCEN31"; then t_ok "scenarios.md has an E31 heading"; else t_bad "scenarios.md has an E31 heading" "no ## E31 heading"; fi
l30="$(grep -n -m1 '^## E30 ' "$SCEN31" | cut -d: -f1)"; l31="$(grep -n -m1 '^## E31 ' "$SCEN31" | cut -d: -f1)"
if [ -n "$l30" ] && [ -n "$l31" ] && [ "$l30" -lt "$l31" ]; then t_ok "E31 follows E30"; else t_bad "E31 follows E30" "E30=[$l30] E31=[$l31]"; fi
s31 "E31 has a Prompt line" '\*\*Prompt:\*\*'
s31 "E31 has a Pass if line" '\*\*Pass if:\*\*'
s31 "E31 has a Fail if line" '\*\*Fail if:\*\*'
s31 "E31 has an Auto checks: line" 'Auto checks:'
s31 "E31 names the humanizer stub skill" 'humanizer'
s31 "E31 names AskUserQuestion" 'AskUserQuestion'
s31 "E31 says it needs --interactive" '\-\-interactive'
s31 "E31 says the writing check is MANUAL" 'MANUAL'
s31 "E31 names E31_BASE" 'E31_BASE'
PQ31="$(awk -v h='## E31 ' 'index($0, h) == 1 { f = 1; next } f && /^## / { exit } f && /^\*\*Prompt:\*\*/ { print }' "$SCEN31" | tr -cd '"' | wc -c | tr -d ' ')"
assert_eq "E31 Prompt line holds one double-quoted prompt (two quote marks, none inside)" "2" "$PQ31"

t_summary
