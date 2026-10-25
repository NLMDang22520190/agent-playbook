#!/usr/bin/env bash
# Tests for the v0.24.0 to v0.24.4 weight grading of evals/run-evals.sh and evals/transcript.js (E1, E15, E19: the reply names Full or Lite, never Quick; the Playbook
# feedback line is always needed; the weight is read however the reply writes it): the second half of test-evals-grade4.sh (split in v0.24.14 so that it is not the
# floor of a CI shard), from "v0.24.0 R1" to the end. Never calls a real harness: every run uses --cmd with fake adapters (see evals-fixture.sh).
# Shared setup: evals-fixture.sh, evals-grade4-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-grade4-fixture.sh"

# ---- v0.24.0 R1 (v0.24.10: the Quick weight is removed): E1 names Full or Lite; E15 passes on Lite with no independent review; E19 and E15 always need the feedback line ----
# E1: the final reply names the weight as a word: Full or Lite (check text "reply states the weight"). A stated Quick weight FAILs.
# E15: passes with Lite + "no independent review"; `Weight: Quick` no longer passes; the weight is read from the final reply (not the whole log).
# E15 and E19: the "Playbook feedback line" check applies to every reply, whatever weight it states (feedback_line_unless_quick is gone).
# stated_weight still parses a Quick statement (it returns quick), so that the graders can FAIL on it.
# A plain-text log (no stream-json result line) keeps the old behaviour (E15: the weight is read from the log, feedback MANUAL).
W15K='states the weight'
echo "v0.24.10 E1: the reply names Full or Lite, never Quick"
E1_FIX='printf "function subtract(a, b) { return a - b; }\nmodule.exports.subtract = subtract;\n" >> src/calc.js
printf "const test = require(\"node:test\");\nconst assert = require(\"node:assert\");\nconst { subtract } = require(\"../src/calc\");\ntest(\"subtract\", () => { assert.strictEqual(subtract(5, 3), 2); });\n" > tests/subtract.test.js'
K_WT='states the weight'
run_x E1 wlite "$E1_FIX" "$INIT" "$(res 'Weight: Lite (additive). Added subtract with a test.')"
assert_eq "R1 E1 reply 'Weight: Lite': PASS" "PASS" "$(e_state E1 "$K_WT")"
assert_eq "R1 E1 Lite run: no FAIL line" "0" "$(count_lines E1 FAIL)"
run_x E1 wfull "$E1_FIX" "$INIT" "$(res 'Weight: Full. Added subtract with a test.')"
assert_eq "R1 E1 reply 'Weight: Full': PASS" "PASS" "$(e_state E1 "$K_WT")"
run_x E1 wquick "$E1_FIX" "$INIT" "$(res 'Weight: Quick (one file, 3 lines). Added subtract with a test.')"
assert_eq "v24.10 E1 reply 'Weight: Quick': FAIL" "FAIL" "$(e_state E1 "$K_WT")"
assert_eq "v24.10 E1 Quick run: exactly one FAIL line (the weight)" "1" "$(count_lines E1 FAIL)"
assert_rc "v24.10 E1 Quick run: exit 1" 1
run_x E1 wboldquick "$E1_FIX" "$INIT" "$(res 'Weight: **Quick**. Added subtract with a test.')"
assert_eq "v24.10 E1 reply 'Weight: **Quick**': FAIL" "FAIL" "$(e_state E1 "$K_WT")"
run_x E1 wquickword "$E1_FIX" "$INIT" "$(res 'Quick job: added subtract with a test.')"
assert_eq "v24.10 E1 the word Quick without a Weight statement does not name a weight: FAIL" "FAIL" "$(e_state E1 "$K_WT")"
run_x E1 wuserquick "$E1_FIX" "$INIT" "$(res 'Weight: Lite (user said quick). Added subtract with a test.')"
assert_eq "v24.10 E1 'Weight: Lite (user said quick)': PASS" "PASS" "$(e_state E1 "$K_WT")"
run_x E1 wnone "$E1_FIX" "$INIT" "$(res 'Added subtract with a test.')"
assert_eq "R1 E1 reply without a weight: FAIL" "FAIL" "$(e_state E1 "$K_WT")"
run_x E1 wquickly "$E1_FIX" "$INIT" "$(res 'Quickly added subtract with a test.')"
assert_eq "R1 E1 'Quickly' is not the word Quick: FAIL" "FAIL" "$(e_state E1 "$K_WT")"
run_x E1 wexempt "$E1_FIX" "$INIT" "$(res 'Weight: Exempt. Added subtract.')"
assert_eq "R1 E1 'Exempt' is not a weight for a code change: FAIL" "FAIL" "$(e_state E1 "$K_WT")"
# v0.24.31: the weight counts only in the label form (Weight: Lite, **Weight:** Lite, Weight: **Lite**); prose such as "at the light weight" or "the Lite workflow" FAILs.
# Pinned on Run 22: run 2 wrote "at the light weight" (FAIL), run 1 wrote "**Weight: Lite (no independent review)**" (PASS).
run_x E1 l1run2 "$E1_FIX" "$INIT" "$(res 'I loaded the playbook-tdd skill. I used it at the light weight (one context, no independent review), because a new exported function is an addition.')"
assert_eq "v31 E1 Run 22 run 2 paraphrase 'at the light weight': FAIL" "FAIL" "$(e_state E1 "$K_WT")"
assert_eq "v31 E1 Run 22 run 2 paraphrase: the weight is the only FAIL line" "1" "$(count_lines E1 FAIL)"
run_x E1 l1run1 "$E1_FIX" "$INIT" "$(res 'I loaded the playbook-tdd skill. **Weight: Lite (no independent review)**: calc.js is used by billing, but this only adds a new function.')"
assert_eq "v31 E1 Run 22 run 1 '**Weight: Lite (no independent review)**': PASS" "PASS" "$(e_state E1 "$K_WT")"
run_x E1 l1boldlabel "$E1_FIX" "$INIT" "$(res '**Weight:** Lite. Added subtract with a test.')"
assert_eq "v31 E1 '**Weight:** Lite': PASS" "PASS" "$(e_state E1 "$K_WT")"
run_x E1 l1boldval "$E1_FIX" "$INIT" "$(res 'Weight: **Full**. Added subtract with a test.')"
assert_eq "v31 E1 'Weight: **Full**': PASS" "PASS" "$(e_state E1 "$K_WT")"
run_x E1 l1workflow "$E1_FIX" "$INIT" "$(res 'I ran the Lite workflow and added subtract with a test.')"
assert_eq "v31 E1 'the Lite workflow' without the label: FAIL" "FAIL" "$(e_state E1 "$K_WT")"
run_x E1 l1liteweight "$E1_FIX" "$INIT" "$(res 'Lite weight, added subtract with a test.')"
assert_eq "v31 E1 'Lite weight' without the label: FAIL" "FAIL" "$(e_state E1 "$K_WT")"
run_x E1 l1fullweight "$E1_FIX" "$INIT" "$(res 'This needed Full weight, so I added subtract with a test.')"
assert_eq "v31 E1 'Full weight' without the label: FAIL" "FAIL" "$(e_state E1 "$K_WT")"
run_x E1 l1word "$E1_FIX" "$INIT" "$(res 'Lite. Added subtract with a test.')"
assert_eq "v31 E1 a bare word Lite: FAIL" "FAIL" "$(e_state E1 "$K_WT")"

echo "v0.24.10 E15: Lite with 'no independent review'; Weight: Quick no longer passes; the feedback line is always needed"
LITE_OK='Weight: Lite (one-line reversible fix), no independent review. Fixed the typo and added a test.'
run_x E15 qlite "$E15_FIX" "$INIT" "$SKT" "$(res "$LITE_OK Playbook feedback: none")"
assert_eq "R1 E15 Lite + no independent review + feedback line: no FAIL line" "0" "$(count_lines E15 FAIL)"
assert_rc "R1 E15 Lite + no independent review: exit 0" 0
run_x E15 qlitecase "$E15_FIX" "$INIT" "$SKT" "$(res 'weight: lite, No Independent Review. Fixed the typo and added a test. Playbook feedback: none')"
assert_eq "R1 E15 the wording is matched case-insensitively: no FAIL line" "0" "$(count_lines E15 FAIL)"
run_x E15 qquick "$E15_FIX" "$INIT" "$SKT" "$(res 'Weight: Quick. Understanding: one typo. Change: src/calc.js:3. Evidence: test red then green. Not checked: nothing.')"
assert_eq "v24.10 E15 Weight: Quick: the weight check FAILs" "FAIL" "$(e_state E15 "$W15K")"
assert_rc "v24.10 E15 Weight: Quick: exit 1" 1
assert_eq "v24.10 E15 Weight: Quick without a feedback line: the feedback check FAILs too (no Quick exemption)" "FAIL" "$(e_state E15 "$FBK")"
assert_eq "v24.10 E15 Weight: Quick without a feedback line: two FAIL lines" "2" "$(count_lines E15 FAIL)"
run_x E15 qquickur "$E15_FIX" "$INIT" "$SKT" "$(res 'Weight: Quick (user-requested). Fixed the typo and added a test.')"
assert_eq "v24.10 E15 Weight: Quick (user-requested): the weight check FAILs" "FAIL" "$(e_state E15 "$W15K")"
run_x E15 qquickfb "$E15_FIX" "$INIT" "$SKT" "$(res 'Weight: Quick. Fixed the typo and added a test. Playbook feedback: none')"
assert_eq "v24.10 E15 Weight: Quick with a feedback line: the weight check still FAILs" "FAIL" "$(e_state E15 "$W15K")"
assert_eq "v24.10 E15 Weight: Quick with a feedback line: the weight check is the only FAIL" "1" "$(count_lines E15 FAIL)"
run_x E15 qlitequick "$E15_FIX" "$INIT" "$SKT" "$(res 'Weight: Lite (user said quick), no independent review. Fixed the typo and added a test. Playbook feedback: none')"
assert_eq "v24.10 E15 Weight: Lite (user said quick) with no independent review: the weight check PASSes" "PASS" "$(e_state E15 "$W15K")"
assert_eq "v24.10 E15 Weight: Lite (user said quick) with no independent review and a feedback line: no FAIL line" "0" "$(count_lines E15 FAIL)"
run_x E15 qlitenorev "$E15_FIX" "$INIT" "$SKT" "$(res 'Weight: Lite (one-line reversible fix). Fixed the typo and added a test. Playbook feedback: none')"
assert_eq "R1 E15 Lite without 'no independent review': exactly one FAIL" "1" "$(count_lines E15 FAIL)"
if printf '%s\n' "$OUT" | grep '^E15 FAIL ' | grep -qi 'weight'; then t_ok "R1 E15 Lite without 'no independent review': the FAIL line is the weight check"; else t_bad "R1 E15 Lite without 'no independent review': the FAIL line is the weight check" "$OUT"; fi
assert_rc "R1 E15 Lite without 'no independent review': exit 1" 1
run_x E15 qlitenofb "$E15_FIX" "$INIT" "$SKT" "$(res "$LITE_OK")"
assert_eq "R1 E15 Lite (reviewless) without a feedback line: the feedback check FAILs" "FAIL" "$(e_state E15 "$FBK")"
assert_eq "R1 E15 Lite without a feedback line: it is the only FAIL" "1" "$(count_lines E15 FAIL)"
echo "v0.24.2 review round 2 F2: E15 bold weights"
run_x E15 qboldquick "$E15_FIX" "$INIT" "$SKT" "$(res 'Weight: **Quick**. Fixed the typo and added a test.')"
assert_eq "v24.10 E15 Weight: **Quick**: the weight check FAILs" "FAIL" "$(e_state E15 "$W15K")"
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
# a Quick reply does not excuse the other checks (v0.24.0: Quick does not excuse the other checks; still true)
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

echo "v0.24.10 E19: the Playbook feedback line applies to every reply, a Quick-labelled one too"
run_x E19 qquick "$MUL_OK" "$INIT" "$SKT" "$WTEST" "$(res 'Weight: Quick. Loaded playbook-tdd, then added multiply with a test.')"
assert_eq "v24.10 E19 Weight: Quick without a feedback line: the feedback check FAILs" "FAIL" "$(e_state E19 "$FBK")"
assert_rc "v24.10 E19 Weight: Quick without a feedback line: exit 1" 1
run_x E19 qquickfb "$MUL_OK" "$INIT" "$SKT" "$WTEST" "$(res 'Weight: Quick. Loaded playbook-tdd, then added multiply. Playbook feedback: none')"
assert_eq "v24.10 E19 Quick with a feedback line: no FAIL line" "0" "$(count_lines E19 FAIL)"
run_x E19 qlitequick "$MUL_OK" "$INIT" "$SKT" "$WTEST" "$(res 'Weight: Lite (user said quick). Loaded playbook-tdd, then added multiply with a test.')"
assert_eq "v24.10 E19 Weight: Lite (user said quick) without a feedback line: FAIL" "FAIL" "$(e_state E19 "$FBK")"
run_x E19 qlite "$MUL_OK" "$INIT" "$SKT" "$WTEST" "$(res 'Weight: Lite. Loaded playbook-tdd, then added multiply with a test.')"
assert_eq "R1 E19 Lite without a feedback line: FAIL" "FAIL" "$(e_state E19 "$FBK")"
run_x E19 qfull "$MUL_OK" "$INIT" "$SKT" "$WTEST" "$(res 'Weight: Full. Loaded playbook-tdd, then added multiply with a test.')"
assert_eq "R1 E19 Full without a feedback line: FAIL" "FAIL" "$(e_state E19 "$FBK")"
run_x E19 qesc "$MUL_OK" "$INIT" "$SKT" "$WTEST" "$(res 'Weight: Lite (escalated from Quick, over the size limit). Loaded playbook-tdd, then added multiply.')"
assert_eq "R1 E19 escalated from Quick to Lite, no feedback line: FAIL (the reply states Lite)" "FAIL" "$(e_state E19 "$FBK")"
run_x E19 qlitefb "$MUL_OK" "$INIT" "$SKT" "$WTEST" "$(res 'Weight: Lite. Loaded playbook-tdd, then added multiply. Playbook feedback: none')"
assert_eq "R1 E19 Lite with a feedback line: no FAIL line" "0" "$(count_lines E19 FAIL)"


echo "v0.24.10 (was v0.24.0 review round 2 F3): a Quick label gives no exemption from the feedback line, whatever else the reply says"
run_x E15 f3quickfull "$E15_FIX" "$INIT" "$SKT" "$(res 'Weight: Quick. Fixed the typo and ran the full test suite, it is green.')"
assert_eq "F3 E15 Weight: Quick + 'full test suite', no feedback line: the feedback check FAILs" "FAIL" "$(e_state E15 "$FBK")"
run_x E15 f3quicklite "$E15_FIX" "$INIT" "$SKT" "$(res 'weight: quick. Fixed the typo; a lite change, nothing else touched.')"
assert_eq "F3 E15 weight: quick + the word lite elsewhere, no feedback line: the feedback check FAILs" "FAIL" "$(e_state E15 "$FBK")"
assert_eq "F3 E15 weight: quick + the word lite elsewhere: the weight check FAILs (the label says quick)" "FAIL" "$(e_state E15 "$W15K")"
run_x E15 f3lite "$E15_FIX" "$INIT" "$SKT" "$(res 'Weight: Lite, no independent review. Fixed the typo and added a test.')"
assert_eq "F3 E15 Weight: Lite without a feedback line: FAIL" "FAIL" "$(e_state E15 "$FBK")"
run_x E19 f3quickfull "$MUL_OK" "$INIT" "$SKT" "$WTEST" "$(res 'Weight: Quick. Loaded playbook-tdd, added multiply, ran the full test suite.')"
assert_eq "F3 E19 Weight: Quick + 'full test suite', no feedback line: the feedback check FAILs" "FAIL" "$(e_state E19 "$FBK")"
run_x E19 f3lite "$MUL_OK" "$INIT" "$SKT" "$WTEST" "$(res 'Weight: Lite. Loaded playbook-tdd, then added multiply with a test.')"
assert_eq "F3 E19 Weight: Lite without a feedback line: FAIL" "FAIL" "$(e_state E19 "$FBK")"
run_x E19 f3quickfullw "$MUL_OK" "$INIT" "$SKT" "$WTEST" "$(res 'Weight: Full. Loaded playbook-tdd, quick look, then added multiply.')"
assert_eq "F3 E19 Weight: Full + the word quick elsewhere, no feedback line: FAIL" "FAIL" "$(e_state E19 "$FBK")"

# ---- v0.24.4 item 5: the graders read the weight however the reply writes it ----
echo "v0.24.4 item 5 E15/E19: the weight is read from 'at X weight', 'X weight' and bold forms"
run_x E15 w5atbquick "$E15_FIX" "$INIT" "$SKT" "$(res 'Fixed the typo and added a test, at **Quick** weight.')"
assert_eq "I5 E15 'at **Quick** weight': the weight check FAILs (v0.24.10)" "FAIL" "$(e_state E15 "$W15K")"
assert_eq "I5 E15 'at **Quick** weight', no feedback line: both checks FAIL (v0.24.10)" "2" "$(count_lines E15 FAIL)"
run_x E15 w5quicksubj "$E15_FIX" "$INIT" "$SKT" "$(res 'Quick weight: fixed the typo and added a test.')"
assert_eq "I5 E15 'Quick weight' as the subject: the weight check FAILs (v0.24.10)" "FAIL" "$(e_state E15 "$W15K")"
run_x E15 w5boldcolon "$E15_FIX" "$INIT" "$SKT" "$(res '**Weight:** Quick. Fixed the typo and added a test.')"
assert_eq "I5 E15 '**Weight:** Quick': the weight check FAILs (v0.24.10)" "FAIL" "$(e_state E15 "$W15K")"
run_x E15 w5atlite "$E15_FIX" "$INIT" "$SKT" "$(res 'Done at **Lite** weight, no independent review. Fixed the typo and added a test.')"
assert_eq "I5 E15 'at **Lite** weight' + no independent review: the weight check PASSes" "PASS" "$(e_state E15 "$W15K")"
assert_eq "I5 E15 'at **Lite** weight' without a feedback line: the feedback check FAILs" "FAIL" "$(e_state E15 "$FBK")"
run_x E15 w5full "$E15_FIX" "$INIT" "$SKT" "$(res 'Done at FULL weight. Fixed the typo and added a test. Playbook feedback: none')"
assert_eq "I5 E15 'at FULL weight' is neither Lite nor Quick: the weight check FAILs" "FAIL" "$(e_state E15 "$W15K")"
run_x E19 w5atbquick "$MUL_OK" "$INIT" "$SKT" "$WTEST" "$(res 'Loaded playbook-tdd, added multiply with a test at **Quick** weight.')"
assert_eq "I5 E19 'at **Quick** weight', no feedback line: the feedback check FAILs (v0.24.10)" "FAIL" "$(e_state E19 "$FBK")"
run_x E19 w5quicksubj "$MUL_OK" "$INIT" "$SKT" "$WTEST" "$(res 'Quick weight. Loaded playbook-tdd, added multiply with a test.')"
assert_eq "I5 E19 'Quick weight' as the subject, no feedback line: the feedback check FAILs (v0.24.10)" "FAIL" "$(e_state E19 "$FBK")"
run_x E19 w5atlite "$MUL_OK" "$INIT" "$SKT" "$WTEST" "$(res 'Loaded playbook-tdd, added multiply with a test at **Lite** weight.')"
assert_eq "I5 E19 'at **Lite** weight' without a feedback line: FAIL" "FAIL" "$(e_state E19 "$FBK")"
run_x E19 w5firstwins "$MUL_OK" "$INIT" "$SKT" "$WTEST" "$(res 'Loaded playbook-tdd, added multiply at Lite weight. A Quick weight would have been too small.')"
assert_eq "I5 E19 the first weight statement wins (Lite before Quick): FAIL without the feedback line" "FAIL" "$(e_state E19 "$FBK")"
echo "v0.24.10 (was v0.24.4 review F2) E15/E19: 'Normally this needs Full weight, but you chose Quick. Weight: Quick' states Quick, which fails E15 and still needs the E19 feedback line"
run_x E15 f2normally "$E15_FIX" "$INIT" "$SKT" "$(res 'Normally this needs Full weight, but you chose Quick. Weight: Quick. Fixed the typo and added a test.')"
assert_eq "F2 E15 the label wins over the prose, and it says Quick: the weight check FAILs" "FAIL" "$(e_state E15 "$W15K")"
run_x E19 f2normally "$MUL_OK" "$INIT" "$SKT" "$WTEST" "$(res 'Normally this needs Full weight, but you chose Quick. Weight: Quick. Loaded playbook-tdd, added multiply with a test.')"
assert_eq "F2 E19 the label says Quick, no feedback line: the feedback check FAILs" "FAIL" "$(e_state E19 "$FBK")"
run_x E15 f2notfull "$E15_FIX" "$INIT" "$SKT" "$(res 'This is not Full weight; Weight: Lite, no independent review. Fixed the typo and added a test.')"
assert_eq "F2 E15 'not Full weight; Weight: Lite' with no independent review: the weight check PASSes" "PASS" "$(e_state E15 "$W15K")"

t_summary
