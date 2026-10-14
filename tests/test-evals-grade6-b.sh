#!/usr/bin/env bash
# Tests for the v0.24.0 to v0.24.4 grading of evals/run-evals.sh and evals/transcript.js: the second half of test-evals-grade6.sh (split in v0.24.7 so that it is not
# the floor of a CI shard), from "v0.24.0 E24 (R5)" to the end. Never calls a real harness: every run uses --cmd with fake adapters (see evals-fixture.sh).
# Shared setup: evals-fixture.sh, evals-grade6-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-grade6-fixture.sh"

echo "v0.24.0 E24 (R5): every sub-agent call of a Full task uses a configured model"
E24_REC='{ echo "tracked=$(git ls-files .agents/playbook.conf)"; echo "dirty=$(git status --porcelain | wc -l | tr -d " ")"; cat .agents/playbook.conf; } > "$REC/E24.fix"'
K24A='sub-agent use'; K24B='configured model'; K24C='Models: line'
MODELS_REPLY='Models: tester=sonnet, implementer=sonnet, reviewer=opus - from conf. Weight: Full.'
run_x E24 good "$E24_REC" "$INIT" "$(AG sonnet)" "$(AG sonnet)" "$(AG opus)" "$(res "$MODELS_REPLY")"
assert_eq "E24 good run: no FAIL line" "0" "$(count_lines E24 FAIL)"
assert_eq "E24 sub-agent use: PASS" "PASS" "$(e_state E24 "$K24A")"
assert_eq "E24 configured model: PASS" "PASS" "$(e_state E24 "$K24B")"
assert_eq "E24 Models: line: PASS" "PASS" "$(e_state E24 "$K24C")"
FIX24="$(cat "$REC/E24.fix" 2>/dev/null)"
assert_contains "E24 fixture: the project conf is tracked" "$FIX24" "tracked=.agents/playbook.conf"
assert_contains "E24 fixture: the tree is clean after the conf commit" "$FIX24" "dirty=0"
assert_contains "E24 fixture: model_tester_claude=sonnet" "$FIX24" "model_tester_claude=sonnet"
assert_contains "E24 fixture: model_implementer_claude=sonnet" "$FIX24" "model_implementer_claude=sonnet"
assert_contains "E24 fixture: model_reviewer_claude=opus" "$FIX24" "model_reviewer_claude=opus"
assert_contains "E24 the prompt is a Full task (sub-agents / the cart)" "$(cat "$REC/E24.prompt" 2>/dev/null)" "total()"
run_x E24 explore "$E24_REC" "$INIT" "$(tu Agent '{"description":"d","subagent_type":"Explore","model":"opus","prompt":"x"}')" "$(AG sonnet)" "$(res "$MODELS_REPLY")"
assert_eq "E24 an Explore sub-agent with an allowed model: no FAIL line" "0" "$(count_lines E24 FAIL)"
run_x E24 task "$E24_REC" "$INIT" "$(tu Task '{"description":"d","model":"sonnet","prompt":"x"}')" "$(res "$MODELS_REPLY")"
assert_eq "E24 a Task call with an allowed model: sub-agent use PASS" "PASS" "$(e_state E24 "$K24A")"
assert_eq "E24 a Task call with an allowed model: configured model PASS" "PASS" "$(e_state E24 "$K24B")"
run_x E24 nocall "$E24_REC" "$INIT" "$(tu Bash '{"command":"ls"}')" "$(res "$MODELS_REPLY")"
assert_eq "E24 no Agent or Task call: sub-agent use FAIL" "FAIL" "$(e_state E24 "$K24A")"
assert_rc "E24 no Agent or Task call: exit 1" 1
run_x E24 nomodel "$E24_REC" "$INIT" "$(AG sonnet)" "$(AGN)" "$(res "$MODELS_REPLY")"
assert_eq "E24 one call without a model: configured model FAIL" "FAIL" "$(e_state E24 "$K24B")"
assert_eq "E24 one call without a model: sub-agent use still PASS" "PASS" "$(e_state E24 "$K24A")"
run_x E24 haiku "$E24_REC" "$INIT" "$(AG sonnet)" "$(AG haiku)" "$(res "$MODELS_REPLY")"
assert_eq "E24 one call with a model outside {sonnet, opus}: configured model FAIL" "FAIL" "$(e_state E24 "$K24B")"
run_x E24 upgrade "$E24_REC" "$INIT" "$(AG opus)" "$(AG opus)" "$(AG opus)" "$(res "$MODELS_REPLY")"
assert_eq "E24 only opus: both sonnet and opus are in the allowed set, so PASS" "PASS" "$(e_state E24 "$K24B")"
run_x E24 nomodelsline "$E24_REC" "$INIT" "$(AG sonnet)" "$(AG opus)" "$(res 'Done. Weight: Full, three roles, tests pass.')"
assert_eq "E24 no Models: line in the reply: FAIL" "FAIL" "$(e_state E24 "$K24C")"
assert_eq "E24 no Models: line: the other two checks PASS" "2" "$(printf '%s\n' "$OUT" | grep '^E24 PASS ' | grep -cE 'sub-agent use|configured model')"
run_x E24 inline "$E24_REC" "$INIT" "$(AG sonnet)" "$(AG opus)" "$(res 'Done. Plan was Models: tester=sonnet, implementer=sonnet, reviewer=opus. Tests pass.')"
assert_eq "E24 'Models: tester=' in the middle of the reply: PASS" "PASS" "$(e_state E24 "$K24C")"
run_x E24 lineinbody "$E24_REC" "$INIT" "$(AG sonnet)" "$(AG opus)" "$(res 'Result: done.\nModels: tester=sonnet, implementer=sonnet, reviewer=opus - from conf\nWeight: Full')"
assert_eq "E24 a 'Models: ' line of its own: PASS" "PASS" "$(e_state E24 "$K24C")"
run_x E24 plain "$E24_REC
echo 'Models: tester=sonnet'"
assert_eq "E24 plain-text transcript: the sub-agent check is not a FAIL" "0" "$(printf '%s\n' "$OUT" | grep '^E24 FAIL ' | grep -c 'sub-agent use')"
assert_eq "E24 plain-text transcript: the Models: line check is MANUAL" "MANUAL" "$(e_state E24 "$K24C")"

echo "v0.24.10 (was v0.24.2 review round 2 F2) E23: bold weights; a stated Quick or Full fails the weight is Lite check"
run_x E23 boldquick "$E23_FIX" "$INIT" "$(res 'Weight: **Quick** (user-requested). Over the limit, user chose Quick. Changed total().')"
assert_eq "R2 F2 E23 Weight: **Quick**: the weight is Lite check FAILs" "FAIL" "$(e_state E23 "$K23B")"
run_x E23 boldlite "$E23_FIX" "$INIT" "$(res 'Weight: **Lite**. Billing code, so no Full. Changed total().')"
assert_eq "R2 F2 E23 Weight: **Lite**: the weight is Lite check PASSes" "PASS" "$(e_state E23 "$K23B")"
run_x E23 boldfull "$E23_FIX" "$INIT" "$(res 'Weight: **Full**. Billing code. Changed total().')"
assert_eq "R2 F2 E23 Weight: **Full** is an upgrade: the weight is Lite check FAILs" "FAIL" "$(e_state E23 "$K23B")"

echo "v0.24.0 review round 2 F1 (v0.24.10: E25 retired): E24 FAILs on a missing stream-json result only when the log is stream-json"
ERRRES='{"type":"result","subtype":"error_max_turns","is_error":true,"result":"x"}'
run_x E24 f1plain "$E24_REC
echo 'Models: tester=sonnet'"
assert_eq "F1 E24 plain-text transcript: no FAIL line names the stream-json result" "0" "$(printf '%s\n' "$OUT" | grep '^E24 FAIL ' | grep -c 'stream-json result')"
assert_eq "F1 E24 plain-text transcript: the stream-json check is MANUAL (needs --harness claude)" "MANUAL" "$(e_state E24 'needs --harness claude')"
run_x E24 f1err "$E24_REC" "$INIT" "$(AG sonnet)" "$ERRRES"
assert_eq "F1 E24 stream-json run with an error result: the stream-json check FAILs" "1" "$(printf '%s\n' "$OUT" | grep '^E24 FAIL ' | grep -c 'stream-json result')"
run_x E24 f1ok "$E24_REC" "$INIT" "$(AG sonnet)" "$(res "$MODELS_REPLY")"
assert_eq "F1 E24 good stream-json run: no FAIL line names the stream-json result" "0" "$(printf '%s\n' "$OUT" | grep '^E24 FAIL ' | grep -c 'stream-json result')"

echo "v0.24.0 review round 2 F2: models= lists only general-purpose (or untyped) Agent/Task calls"
AGX() { tu Agent "{\"description\":\"d\",\"subagent_type\":\"$1\",\"prompt\":\"x\"}"; }
assert_eq "F2 models: an Explore call without a model is not listed" "sonnet" "$(mo_of "$INIT" "$(AGX Explore)" "$(AG sonnet)")"
assert_eq "F2 models: an Explore call with a model is not listed either" "sonnet" "$(mo_of "$INIT" "$(tu Agent '{"description":"d","subagent_type":"Explore","model":"opus","prompt":"x"}')" "$(AG sonnet)")"
assert_eq "F2 models: Explore alone gives an empty list" "" "$(mo_of "$INIT" "$(AGX Explore)")"
assert_eq "F2 models: a general-purpose call without a model is still '-'" "-" "$(mo_of "$INIT" "$(AGN)")"
assert_eq "F2 models: a call without subagent_type and without model is '-'" "-" "$(mo_of "$INIT" "$(tu Agent '{"description":"d","prompt":"x"}')")"
assert_eq "F2 models: a Task call without subagent_type is listed" "opus" "$(mo_of "$INIT" "$(tu Task '{"description":"d","model":"opus","prompt":"x"}')")"
assert_eq "F2 models: the general-purpose position order is kept around a helper" "sonnet,-,opus" "$(mo_of "$INIT" "$(AG sonnet)" "$(AGX Explore)" "$(AGN)" "$(AG opus)")"
run_x E24 f2helper "$E24_REC" "$INIT" "$(AGX Explore)" "$(AG sonnet)" "$(res "$MODELS_REPLY")"
assert_eq "F2 E24 Explore without a model + a sonnet call: configured model PASS" "PASS" "$(e_state E24 "$K24B")"
assert_eq "F2 E24 Explore without a model + a sonnet call: no FAIL line" "0" "$(count_lines E24 FAIL)"
run_x E24 f2gp "$E24_REC" "$INIT" "$(AGN)" "$(res "$MODELS_REPLY")"
assert_eq "F2 E24 general-purpose without a model: configured model FAIL" "FAIL" "$(e_state E24 "$K24B")"
run_x E24 f2onlyexp "$E24_REC" "$INIT" "$(AGX Explore)" "$(res "$MODELS_REPLY")"
assert_eq "F2 E24 only a helper call: no listed model, configured model FAIL" "FAIL" "$(e_state E24 "$K24B")"
assert_contains "F2 the transcript.js header documents the helper rule" "$(sed -n 1,12p "$TSX" | tr '\n' ' ')" "Explore"
assert_contains "F2 the E24 scenario text documents the helper rule" "$(grep -A12 '^## E24' "$PB_ROOT/evals/scenarios.md" | tr '\n' ' ')" "Explore"

echo "v0.24.13 AUTO list: E22-E25 are auto-gradable (E25 is re-pointed), and the default scenarios stay E1,E3,E8,E15"
for e in E22 E23 E24; do
  W="$(mk_tmp)"
  run bash "$RUNNER" --cmd "bash $A/idle.sh" --scenarios "$e" --workroot "$W" --out "$W/results.md"
  assert_not_contains "AUTO $e is accepted (not a usage error)" "$OUT" "not auto-gradable"
  assert_contains "AUTO $e: the idle adapter is graded (a line for $e)" "$OUT" "$e "
  case "$e" in
    E24) # review round 2 F1: a plain-text idle run is MANUAL for the stream-json checks (needs --harness claude), never a FAIL
      assert_eq "AUTO $e: the idle plain-text adapter is graded without a FAIL (exit 0, not 2)" "0" "$RC" ;;
    *) assert_eq "AUTO $e: the idle adapter fails a check (exit 1, not 2)" "1" "$RC" ;;
  esac
done
W="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $A/idle.sh" --scenarios E25 --workroot "$W" --out "$W/results.md"
assert_not_contains "AC1.1 E25 is accepted (not a usage error)" "$OUT" "not auto-gradable"
assert_eq "AC1.1 E25: the idle adapter is graded (a check line for E25)" "graded" "$([ "$(printf '%s\n' "$OUT" | grep -cE '^E25 (PASS|FAIL|MANUAL) ')" -gt 0 ] && echo graded || echo not-graded)"
assert_rc "AC1.1 E25: the idle adapter fails a check (exit 1, not 2)" 1


echo "v0.24.10 (was v0.24.4 item 5) E23: the weight is read from 'at X weight' and 'X weight' too; Quick and Full FAIL, Lite passes"
run_x E23 atbquick "$E23_FIX" "$INIT" "$(res 'Done at **Quick** weight (user said quick). Changed total().')"
assert_eq "I5 E23 'at **Quick** weight': the weight is Lite check FAILs" "FAIL" "$(e_state E23 "$K23B")"
run_x E23 atlite "$E23_FIX" "$INIT" "$(res 'Billing code, so I worked at Lite weight. Changed total().')"
assert_eq "I5 E23 'at Lite weight': the weight is Lite check PASSes" "PASS" "$(e_state E23 "$K23B")"
run_x E23 atboldfull "$E23_FIX" "$INIT" "$(res 'Done at **Full** weight. Changed total().')"
assert_eq "I5 E23 'at **Full** weight' is an upgrade: FAIL" "FAIL" "$(e_state E23 "$K23B")"
run_x E23 fullsubj "$E23_FIX" "$INIT" "$(res 'FULL weight. Changed total().')"
assert_eq "I5 E23 'FULL weight' as the subject is an upgrade: FAIL" "FAIL" "$(e_state E23 "$K23B")"
run_x E23 firstquick "$E23_FIX" "$INIT" "$(res 'Quick weight (user said quick); Lite weight was not used. Changed total().')"
assert_eq "I5 E23 the first statement wins (Quick before Lite): FAIL" "FAIL" "$(e_state E23 "$K23B")"
run_x E23 firstlite "$E23_FIX" "$INIT" "$(res 'Lite weight (user said quick); Full weight was not used. Changed total().')"
assert_eq "I5 E23 the first statement wins (Lite before Full): PASS" "PASS" "$(e_state E23 "$K23B")"

echo "v0.24.4 item 5 E24: the Models line may be the template form or name each role with its model"
run_x E24 usedform "$E24_REC" "$INIT" "$(AG sonnet)" "$(AG opus)" "$(res 'Done at Full weight.\n\n**Models used:** tester=sonnet (high), implementer=sonnet (high), reviewer=opus (high)\n\n**Playbook feedback:** none')"
assert_eq "I5 E24 the template line '**Models used:**': PASS" "PASS" "$(e_state E24 "$K24C")"
run_x E24 usedbare "$E24_REC" "$INIT" "$(AG sonnet)" "$(AG opus)" "$(res 'Done at Full weight. **Models used:** sonnet and opus.')"
assert_eq "I5 E24 'Models used:' in the middle of a line: PASS" "PASS" "$(e_state E24 "$K24C")"
run_x E24 roleeq "$E24_REC" "$INIT" "$(AG sonnet)" "$(AG opus)" "$(res 'Done at Full weight.\nRoles: tester=sonnet, implementer=sonnet, reviewer=opus.')"
assert_eq "I5 E24 a line with tester=, implementer=, reviewer=: PASS" "PASS" "$(e_state E24 "$K24C")"
run_x E24 rolefor "$E24_REC" "$INIT" "$(AG sonnet)" "$(AG opus)" "$(res 'Done at Full weight. I used sonnet for tester, sonnet for implementer and opus for reviewer.')"
assert_eq "I5 E24 'sonnet for tester, sonnet for implementer, opus for reviewer': PASS" "PASS" "$(e_state E24 "$K24C")"
# the real v0.24.3 reply (ev243-evidence/E24.log): the models are named in prose, the implementer only in 'tester and implementer'
E24_REAL='I used the playbook-tdd skill at Full weight. Separate sub-agents each started fresh: a spec reviewer, a tester, an implementer and a reviewer, with the configured models (sonnet for tester and implementer, opus for the reviewers).'
run_x E24 realprose "$E24_REC" "$INIT" "$(AG sonnet)" "$(AG opus)" "$(res "$E24_REAL")"
assert_eq "I5 E24 the real prose-only reply: the Models line check still FAILs" "FAIL" "$(e_state E24 "$K24C")"
run_x E24 prosenomodel "$E24_REC" "$INIT" "$(AG sonnet)" "$(AG opus)" "$(res 'Done at Full weight with the configured models: a tester, an implementer and a reviewer.')"
assert_eq "I5 E24 roles named without their models: FAIL" "FAIL" "$(e_state E24 "$K24C")"
run_x E24 twoofthree "$E24_REC" "$INIT" "$(AG sonnet)" "$(AG opus)" "$(res 'Done. tester=sonnet and reviewer=opus.')"
assert_eq "I5 E24 only two of the three roles with a model: FAIL" "FAIL" "$(e_state E24 "$K24C")"

echo "v0.24.4 review F2 stated_weight: an explicit Weight: label wins over prose; negated prose is skipped"
eval "$(sed -n '/^stated_weight() {/,/^}/p' "$PB_ROOT/evals/run-evals.sh")"
sw() { assert_eq "F2 stated_weight [$1]" "$2" "$(stated_weight "$1")"; }
sw 'Normally this needs Full weight, but you chose Quick. Weight: Quick' quick
sw 'Normally this needs Full weight, but you chose Quick. **Weight:** Quick' quick
sw 'Normally this needs Full weight, but you chose Quick. Weight: **Quick**' quick
sw 'This is not Full weight; Weight: Lite' lite
sw 'Full weight would be too much here. Weight: Lite' lite
sw 'This is not Full weight. Lite weight used.' lite
sw 'You would need Full weight; Quick weight used.' quick
sw 'Not Full weight, Quick weight.' quick
sw 'Quick weight dropped; Lite weight used' quick
sw 'Done at Lite weight.' lite
sw 'Weight: Full' full
sw 'Weight: Quick, size --quick said escalate to Lite weight but I did not.' quick
sw 'Nothing about it.' ''
run_x E23 normallylabel "$E23_FIX" "$INIT" "$(res 'Normally this needs Full weight, but you chose Quick. Weight: Quick. Changed total().')"
assert_eq "F2 E23 'Normally this needs Full weight ... Weight: Quick' states Quick: the weight is Lite check FAILs (v0.24.10)" "FAIL" "$(e_state E23 "$K23B")"
run_x E23 labelfull "$E23_FIX" "$INIT" "$(res 'Over the limit, user chose Quick, but I escalated. Weight: Full. Changed total().')"
assert_eq "F2 E23 an explicit 'Weight: Full' is still an upgrade: FAIL" "FAIL" "$(e_state E23 "$K23B")"

echo "v0.24.4 review round 2 N1: an affirmative needs/would still counts as the stated weight"
sw 'This change needs Full weight: it touches auth.' full
sw 'I would use Full weight here since it touches money.' full
sw 'It needs Lite weight because it is small and reversible.' lite
sw 'Normally this needs Full weight, but Quick weight fits.' quick
sw 'This does not need Full weight; Quick weight.' quick
sw 'This would normally get Full weight; Quick weight here.' quick
run_x E23 needsfull "$E23_FIX" "$INIT" "$(res 'Over the limit; this needs Full weight. Changed total().')"
assert_eq "N1 E23 a reply without a Weight: label that says 'this needs Full weight' FAILs" "FAIL" "$(e_state E23 "$K23B")"

# v0.24.13: fail_graded E -> "<FAIL lines>/graded": a run with no FAIL line counts only when the scenario was graded (some PASS line), so a refused scenario cannot pass it
fail_graded() { printf '%s/%s' "$(count_lines "$1" FAIL)" "$([ "$(count_lines "$1" PASS)" -gt 0 ] && echo graded || echo ungraded)"; }
# ---- v0.24.13 S1: E25 is re-pointed (an additive export in three files still runs at Lite) ----
# Check texts the implementer must use (found by a keyword, e_state):
#   E25  "each file exports VERSION (src/calc.js, src/cart.js, src/report.js)" (key: exports VERSION)
#        "node --test tests/*.test.js passes" (key: node --test)
#        "the reply's weight is Lite (a stated Quick or Full fails)" (key: weight is Lite)
#        "a RED commit touches only tests" (key: RED commit)
#        MANUAL "no Full jump without a Full-column reason" (key: Full-column reason)
#        and the generic "nothing written outside the workdir" (key: outside the workdir)
# Fixture: the runner commits src/report.js (as for E21) before the agent starts.
echo "v0.24.13 S1 E25: VERSION exported from three files, stated weight Lite, a RED commit first"
E25_TEST='printf "const test = require(\"node:test\");\nconst assert = require(\"node:assert\");\ntest(\"VERSION\", () => { for (const f of [\"calc\", \"cart\", \"report\"]) assert.strictEqual(require(\"../src/\" + f).VERSION, \"1.0.0\"); });\n" > tests/version.test.js'
E25_RED="$E25_TEST
$GC add tests/version.test.js
$GC commit -qm 'test(red): VERSION'"
E25_SRC='for f in calc cart report; do printf "\nmodule.exports.VERSION = \"1.0.0\";\n" >> src/$f.js; done'
E25_FIX="$E25_RED
$E25_SRC"
E25_NORED="$E25_TEST
$E25_SRC"
E25_REC='echo "tracked=$(git ls-files src/report.js)" > "$REC/E25.fix"'
K25X='exports VERSION'; K25W='weight is Lite'; K25R='RED commit'; K25M='Full-column reason'
E25_OK='Weight: Lite. Added VERSION to the three files. Tests pass.'
run_x E25 good "$E25_REC
$E25_FIX" "$INIT" "$(res "$E25_OK")"
assert_rc "AC1.2 E25 good run: exit 0" 0
assert_eq "AC1.2 E25 good run: each file exports VERSION: PASS" "PASS" "$(e_state E25 "$K25X")"
assert_eq "AC1.3 E25 good run: node --test passes: PASS" "PASS" "$(e_state E25 'node --test')"
assert_eq "AC1.4 E25 good run: the reply's weight is Lite: PASS" "PASS" "$(e_state E25 "$K25W")"
assert_eq "AC1.5 E25 good run: a RED commit touches only tests: PASS" "PASS" "$(e_state E25 "$K25R")"
assert_eq "AC1.6 E25 good run: nothing written outside the workdir: PASS" "PASS" "$(e_state E25 'outside the workdir')"
assert_eq "AC1.7 E25 records the MANUAL line about a Full jump without a Full-column reason" "MANUAL" "$(e_state E25 "$K25M")"
assert_eq "AC1.2 E25 good run: graded, no FAIL line" "0/graded" "$(fail_graded E25)"
assert_contains "AC1.2 E25 fixture: the runner commits src/report.js" "$(cat "$REC/E25.fix" 2>/dev/null)" "tracked=src/report.js"
E25P="$(cat "$REC/E25.prompt" 2>/dev/null)"
assert_contains "AC1.9 E25 the prompt asks for VERSION" "$E25P" "VERSION"
assert_contains "AC1.9 E25 the prompt names src/report.js" "$E25P" "src/report.js"
if [ -n "$E25P" ] && ! printf '%s' "$E25P" | grep -qi quick; then t_ok "AC1.9 E25 the prompt does not say quick (the user never asks for it)"; else t_bad "AC1.9 E25 the prompt does not say quick (the user never asks for it)" "prompt: [$E25P]"; fi
run_x E25 noreport "$E25_RED
for f in calc cart; do printf '\nmodule.exports.VERSION = \"1.0.0\";\n' >> src/\$f.js; done" "$INIT" "$(res "$E25_OK")"
assert_eq "AC1.2 E25 src/report.js without VERSION: the exports check FAILs" "FAIL" "$(e_state E25 "$K25X")"
assert_rc "AC1.2 E25 one file without VERSION: exit 1" 1
assert_eq "AC1.2 E25 one file without VERSION: the weight check still PASSes" "PASS" "$(e_state E25 "$K25W")"
run_x E25 wrongval "$E25_RED
for f in calc report; do printf '\nmodule.exports.VERSION = \"1.0.0\";\n' >> src/\$f.js; done
printf '\nmodule.exports.VERSION = \"2.0.0\";\n' >> src/cart.js" "$INIT" "$(res "$E25_OK")"
assert_eq "AC1.2 E25 a VERSION that is not 1.0.0 in src/cart.js: the exports check FAILs" "FAIL" "$(e_state E25 "$K25X")"
run_x E25 full "$E25_FIX" "$INIT" "$(res 'Weight: Full. Added VERSION to the three files.')"
assert_eq "AC1.4 E25 'Weight: Full' (a jump to Full): the weight is Lite check FAILs" "FAIL" "$(e_state E25 "$K25W")"
assert_eq "AC1.4 E25 'Weight: Full': the exports check still PASSes" "PASS" "$(e_state E25 "$K25X")"
assert_rc "AC1.4 E25 a stated Full: exit 1" 1
run_x E25 quick "$E25_FIX" "$INIT" "$(res 'Weight: Quick. Added VERSION to the three files.')"
assert_eq "AC1.4 E25 'Weight: Quick': the weight is Lite check FAILs" "FAIL" "$(e_state E25 "$K25W")"
run_x E25 noweight "$E25_FIX" "$INIT" "$(res 'Added VERSION to the three files. Tests pass.')"
assert_eq "AC1.4 E25 no weight statement: the weight is Lite check FAILs" "FAIL" "$(e_state E25 "$K25W")"
run_x E25 nored "$E25_NORED" "$INIT" "$(res "$E25_OK")"
assert_eq "AC1.5 E25 test and change never committed (no RED commit): a RED commit touches only tests FAILs" "FAIL" "$(e_state E25 "$K25R")"
assert_eq "AC1.5 E25 no RED commit: the exports check still PASSes" "PASS" "$(e_state E25 "$K25X")"
run_x E25 plain "$E25_FIX
echo 'Weight: Lite'"
assert_eq "AC1.4 E25 plain-text transcript: the weight check is MANUAL" "MANUAL" "$(e_state E25 "$K25W")"
assert_eq "AC1.5 E25 plain-text transcript: the RED commit is still graded (PASS)" "PASS" "$(e_state E25 "$K25R")"
assert_eq "AC1.2 E25 plain-text transcript: the exports check PASSes" "PASS" "$(e_state E25 "$K25X")"
assert_eq "AC1.4 E25 plain-text transcript: graded, no FAIL line" "0/graded" "$(fail_graded E25)"

t_summary
