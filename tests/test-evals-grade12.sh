#!/usr/bin/env bash
# Tests for the v0.26.0 grader grade_E2 of evals/run-evals.sh (lane N, slice S2; spec .agents/handoff/01-spec.md AC1, AC2, AC3, AC10, decisions D3,
# D8, D9). E2: "Add discounts to the cart." (an ambiguous request). setup_E2 commits nothing: E2_BASE is the fixture HEAD.
# Never calls a real harness: every run uses --cmd with a fake adapter (evals-grade12-fixture.sh).
# Check keys (a fixed phrase each check text must contain; found with e_state):
#   headless (D3):
#     KA2 "headless: no AskUserQuestion"   (a) asked=0 PASS, >0 FAIL, not stream-json MANUAL
#     KB2 "inspected the code before"      (b) a Read/Grep/Glob call or a Bash command naming cart before the first file change (Write/Edit/MultiEdit, or a
#                                              Bash command writing under src/ or tests/); no file change: an inspection anywhere PASS; none FAIL; not
#                                              stream-json MANUAL
#     KC2 "decisions.md names the discount" (c) .agents/handoff/decisions.md new or changed since E2_BASE with a line naming discount, percent, fixed,
#                                              stack or round PASS; no file or no such line FAIL
#     KD2 "reply names the defaults"       (d) the word default or decisions.md in the reply PASS, else MANUAL (never FAIL, D9)
#   interactive (--interactive):
#     KF2 "src/ unchanged"                 (a) src/ unchanged since E2_BASE, untracked included (PASS/FAIL)
#     KB2 "inspected the code before"      (b) as headless (b), with the first AskUserQuestion call as the bound (PASS/FAIL)
#     KG2 "one batch of questions"         (c) at most one AskUserQuestion call and at least one question (a call, or a "?" line of the reply outside code)
#     KH2 "at most 5 questions"            (d) the questions of the call: <= 5 PASS, more FAIL; "?" lines only: <= 5 PASS, more MANUAL (D8, D9)
#     KI2 "each question has a default"    (e) a call: every question has an option label/description or question text matching default or recommend (any
#                                              case) PASS, else FAIL; prose: at least as many default/recommend lines as questions PASS, else MANUAL
#   MANUAL in both modes: KM2 "product guess" (no product guess implemented silently)
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-grade6-fixture.sh"
. "$(dirname "$0")/evals-grade8-fixture.sh"
. "$(dirname "$0")/evals-grade12-fixture.sh"

KA2='headless: no AskUserQuestion'; KB2='inspected the code before'; KC2='decisions.md names the discount'; KD2='reply names the defaults'
KF2='src/ unchanged'; KG2='one batch of questions'; KH2='at most 5 questions'; KI2='each question has a default'; KM2='product guess'
DEC='.agents/handoff/decisions.md'
wf dec2good '# Decisions' '| D1 | Discount type: percentage of the cart total (default) | undo: switch to a fixed amount |'
wf dec2round '- D1 Rounding: round half up to whole cents. Undo: change roundCents.'
wf dec2stack '- D1 Stacking: one code per cart, codes never stack.'
wf dec2none '- D1 Logging: the cart keeps no log. Undo: none.'
wf disc2 'module.exports = { applyDiscount: (t) => t };'

echo "AC1 AC10 E2 is auto-gradable; setup_E2 commits nothing; the prompt is the scenario's"
rm -f "$REC/E2.prompt"
W="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $A/idle.sh" --scenarios E2 --workroot "$W" --out "$W/results.md"
assert_not_contains "AC1 E2 is accepted (not a usage error)" "$OUT" "not auto-gradable"
case "$RC" in 0|1) t_ok "AC1 E2 with the idle adapter exits 0 or 1" ;; *) t_bad "AC1 E2 with the idle adapter exits 0 or 1" "exit $RC; output: $OUT" ;; esac
assert_eq "AC1 E2 is graded (a PASS, FAIL or MANUAL line)" "graded" "$([ "$(printf '%s\n' "$OUT" | grep -cE '^E2 (PASS|FAIL|MANUAL) ')" -gt 0 ] && echo graded || echo not-graded)"
assert_eq "AC2 setup_E2 commits nothing (E2_BASE is the fixture HEAD: one commit)" "1" "$(git -C "$W/E2" rev-list --count HEAD 2>/dev/null)"
assert_eq "AC10 the E2 prompt is the scenario's first double-quoted string" "Add discounts to the cart." "$(head -n 1 "$REC/E2.prompt" 2>/dev/null)"
assert_contains "AC10 scenarios.md E2 has an Auto checks: line" "$(section_of E2)" "Auto checks:"
if grep -qE '^grade_E2\(\)' "$RUNNER"; then t_ok "AC1 run-evals.sh defines grade_E2"; else t_bad "AC1 run-evals.sh defines grade_E2" "no grade_E2() in run-evals.sh"; fi

echo "AC2 E2 headless: a good transcript passes every check"
xr E2 h1 head "$(cpto dec2good "$DEC")" "$INIT" "$(RD src/cart.js)" "$(WR src/cart.js)" \
  "$(rj 'Added percentage discounts to src/cart.js. The defaults I chose are logged in .agents/handoff/decisions.md.')"
assert_eq "AC2a no AskUserQuestion call: PASS" "PASS" "$(e_state E2 "$KA2")"
assert_eq "AC2b Read of src/cart.js before the Write: PASS" "PASS" "$(e_state E2 "$KB2")"
assert_eq "AC2c decisions.md new with a discount line: PASS" "PASS" "$(e_state E2 "$KC2")"
assert_eq "AC2d the reply names decisions.md: PASS" "PASS" "$(e_state E2 "$KD2")"
assert_eq "AC2 the product-guess check stays MANUAL" "MANUAL" "$(e_state E2 "$KM2")"
no_fail E2 "AC2 the good headless transcript has no FAIL line"

echo "AC2 E2 headless: a good transcript worded differently is never FAILed (D9)"
xr E2 h2 head "$(cpto dec2round "$DEC")" "$INIT" "$(BS 'grep -n total src/cart.js')" "$(ED src/cart.js)" \
  "$(rj 'Implemented fixed-amount discounts; I assumed one code per cart, see the ledger.')"
assert_eq "AC2b a Bash grep naming cart before the Edit: PASS" "PASS" "$(e_state E2 "$KB2")"
assert_eq "AC2c a rounding line counts as a discount line: PASS" "PASS" "$(e_state E2 "$KC2")"
assert_eq "AC2d no 'default' and no 'decisions.md' in the reply: MANUAL, not FAIL" "MANUAL" "$(e_state E2 "$KD2")"
no_fail E2 "AC2 D9 the reworded good transcript has no FAIL line"

echo "AC2 E2 headless: a bad transcript FAILs"
xr E2 h3 head "$NOOP" "$INIT" "$(AQ)" "$(WR src/cart.js)" "$(RD src/cart.js)" "$(rj 'Done.')"
assert_eq "AC2a an AskUserQuestion call in a headless run: FAIL" "FAIL" "$(e_state E2 "$KA2")"
assert_eq "AC2b the Write comes before the first Read: FAIL" "FAIL" "$(e_state E2 "$KB2")"
assert_eq "AC2c no decisions.md: FAIL" "FAIL" "$(e_state E2 "$KC2")"
assert_eq "AC2d a reply without defaults is MANUAL, never FAIL" "MANUAL" "$(e_state E2 "$KD2")"

echo "AC2 E2 headless: (b) a Bash write counts as a file change; fix6 a Bash ls before it is an inspection; (c) a ledger without discount words"
xr E2 h4 head "$(cpto dec2none "$DEC") && $(cpto disc2 src/discount.js)" "$INIT" "$(BS 'ls')" "$(BS 'printf x > src/discount.js')" "$(rj 'Done.')"
assert_eq "fix6 AC2b ls (exploration, no cart) then a Bash write under src/: PASS" "PASS" "$(e_state E2 "$KB2")"
assert_eq "AC2c decisions.md without a discount, percent, fixed, stack or round line: FAIL" "FAIL" "$(e_state E2 "$KC2")"

echo "fix6 E2 headless: (b) exploring with find or Glob before the first file change is an inspection; after it, it is not"
xr E2 h8 head "$NOOP" "$INIT" "$(BS 'find . -name "*.js" -not -path "./node_modules/*"')" "$(WR src/cart.js)" "$(rj 'Done.')"
assert_eq "fix6 AC2b a Bash find, then a Write: PASS" "PASS" "$(e_state E2 "$KB2")"
xr E2 h9 head "$NOOP" "$INIT" "$(tu Glob '{"pattern":"src/**/*.js"}')" "$(WR src/cart.js)" "$(rj 'Done.')"
assert_eq "fix6 AC2b a Glob call, then a Write: PASS" "PASS" "$(e_state E2 "$KB2")"
xr E2 h10 head "$NOOP" "$INIT" "$(WR src/cart.js)" "$(BS 'ls src')" "$(rj 'Done.')"
assert_eq "fix6 AC2b a Write, then an ls: FAIL" "FAIL" "$(e_state E2 "$KB2")"

echo "AC2 E2 headless: (b) no file change and an inspection PASS; (c) a committed decisions.md counts"
xr E2 h5 head "$(cpto dec2stack "$DEC") && $GC add $DEC && $GC commit -qm decisions" "$INIT" "$(GRP)" \
  "$(rj 'Logged the stacking default in decisions.md; no code yet.')"
assert_eq "AC2b no file change, a Grep call: PASS" "PASS" "$(e_state E2 "$KB2")"
assert_eq "AC2c decisions.md committed after E2_BASE with a stacking line: PASS" "PASS" "$(e_state E2 "$KC2")"

echo "AC2 E2 headless: (b) no inspection and no change FAILs; not stream-json is MANUAL"
xr E2 h6 head "$NOOP" "$INIT" "$(rj 'Nothing to do.')"
assert_eq "AC2b no tool call at all: FAIL" "FAIL" "$(e_state E2 "$KB2")"
xr E2 h7 head "$(plain 'I added discounts.')"
assert_eq "AC2a not stream-json: MANUAL" "MANUAL" "$(e_state E2 "$KA2")"
assert_eq "AC2b not stream-json: MANUAL" "MANUAL" "$(e_state E2 "$KB2")"

echo "AC3 E2 interactive: a good transcript passes every check"
xr E2 i1 int "$NOOP" "$INIT" "$(RD src/cart.js)" \
  "$(aqj 'Percentage or fixed amount?' 'Percentage (Recommended)' 'Most carts use a percent' \
         'Can discounts stack?' 'No stacking (Recommended)' 'One code per cart' \
         'How to round?' 'Half up to cents (Recommended)' 'Standard rounding')" \
  "$(rj 'I read src/cart.js. Answer the questions above and I will start.')"
assert_eq "AC3a src/ unchanged: PASS" "PASS" "$(e_state E2 "$KF2")"
assert_eq "AC3b Read before the AskUserQuestion call: PASS" "PASS" "$(e_state E2 "$KB2")"
assert_eq "AC3c one AskUserQuestion call: PASS" "PASS" "$(e_state E2 "$KG2")"
assert_eq "AC3d three questions: PASS" "PASS" "$(e_state E2 "$KH2")"
assert_eq "AC3e every question has a (Recommended) option: PASS" "PASS" "$(e_state E2 "$KI2")"
no_fail E2 "AC3 the good interactive transcript has no FAIL line"

echo "AC3 E2 interactive: a bad transcript FAILs"
xr E2 i2 int "$(cpto disc2 src/discount.js)" "$INIT" "$(aqj 'Which discount type?' 'Percentage' 'Share of the total')" "$(RD src/cart.js)" \
  "$(aqj 'Which discount type?' 'Percentage' 'Share of the total')" "$(rj 'Waiting for your answer.')"
assert_eq "AC3a an untracked src/discount.js: FAIL" "FAIL" "$(e_state E2 "$KF2")"
assert_eq "AC3b the first question comes before any inspection: FAIL" "FAIL" "$(e_state E2 "$KB2")"
assert_eq "AC3c two AskUserQuestion calls: FAIL" "FAIL" "$(e_state E2 "$KG2")"
assert_eq "AC3e a question without a default or recommendation: FAIL" "FAIL" "$(e_state E2 "$KI2")"

echo "AC3 E2 interactive: (d) six questions in the call FAIL; (e) a default in the option description counts"
xr E2 i3 int "$NOOP" "$INIT" "$(RD src/cart.js)" \
  "$(aqj 'Q one?' 'A' 'Default: a' 'Q two?' 'B' 'Default: b' 'Q three?' 'C' 'Default: c' 'Q four?' 'D' 'Default: d' 'Q five?' 'E' 'Default: e' 'Q six?' 'F' 'Default: f')" \
  "$(rj 'Waiting for your answers.')"
assert_eq "AC3d six questions in one call: FAIL" "FAIL" "$(e_state E2 "$KH2")"
assert_eq "AC3e every option description says Default: PASS" "PASS" "$(e_state E2 "$KI2")"

echo "AC3 E2 interactive: (e) a default in the question text counts; a good transcript worded differently is never FAILed"
xr E2 i8 int "$NOOP" "$INIT" "$(GRP)" "$(aqj 'Use a percentage discount by default, or a fixed amount?' 'Percentage' 'Share of the total')" \
  "$(rj 'One question above; I will wait.')"
assert_eq "AC3e 'by default' in the question text: PASS" "PASS" "$(e_state E2 "$KI2")"
no_fail E2 "AC3 D9 the reworded interactive transcript has no FAIL line"

echo "AC3 E2 interactive: questions in the reply (prose)"
xr E2 i4 int "$NOOP" "$INIT" "$(RD src/cart.js)" "$(rj 'Before I write code, three questions (each with my default):
1. Percentage or fixed amount? Default: percentage.
2. Can two codes stack? Default: no.
3. Round to cents half up? Default: yes.')"
assert_eq "AC3c three prose questions, no call: one batch PASS" "PASS" "$(e_state E2 "$KG2")"
assert_eq "AC3d three prose questions: PASS" "PASS" "$(e_state E2 "$KH2")"
assert_eq "AC3e three prose questions with three default lines: PASS" "PASS" "$(e_state E2 "$KI2")"
xr E2 i5 int "$NOOP" "$INIT" "$(RD src/cart.js)" "$(rj 'Two questions:
1. Percentage or fixed amount?
2. Can two codes stack?')"
assert_eq "AC3c two prose questions: PASS" "PASS" "$(e_state E2 "$KG2")"
assert_eq "AC3e prose questions without default lines: MANUAL, not FAIL (D9)" "MANUAL" "$(e_state E2 "$KI2")"
xr E2 i6 int "$NOOP" "$INIT" "$(RD src/cart.js)" "$(rj 'Questions:
1. Percentage? Default: yes.
2. Fixed? Default: no.
3. Stack? Default: no.
4. Round? Default: half up.
5. Minimum cart? Default: none.
6. Expiry? Default: none.
7. Per customer? Default: once.')"
assert_eq "AC3d seven prose questions: MANUAL, not FAIL (D8, D9)" "MANUAL" "$(e_state E2 "$KH2")"

echo "AC3 E2 interactive: (c) no question at all FAILs; a ? line inside a fenced block does not count"
xr E2 i7 int "$NOOP" "$INIT" "$(RD src/cart.js)" "$(rj 'I read src/cart.js.
```
Percentage or fixed?
```')"
assert_eq "AC3c no call and only a fenced ? line: FAIL" "FAIL" "$(e_state E2 "$KG2")"

t_summary
