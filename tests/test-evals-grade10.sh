#!/usr/bin/env bash
# Tests for the v0.25.0 grader grade_E30 of evals/run-evals.sh, part 1 of 2: the reply checks (a) chatbot opener or closer and (b) em or en dash
# (spec .agents/handoff/01-spec.md AC13, AC14, AC2b; humanizer sections 8 and 22). Never calls a real harness: every run uses --cmd with a fake adapter that
# prints a stream-json transcript (see evals-fixture.sh, evals-grade10-fixture.sh). Part 2 (checks c, d, e, fixture, pins) is test-evals-grade10b.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-grade6-fixture.sh"
. "$(dirname "$0")/evals-grade8-fixture.sh"
. "$(dirname "$0")/evals-grade10-fixture.sh"

echo "AC14 the clean reply passes every check"
r30 clean "$B30"
assert_eq "AC14 clean reply: (a) chatbot opener or closer PASS" "PASS" "$(e_state E30 "$KA30")"
assert_eq "AC14 clean reply: (b) em or en dash PASS" "PASS" "$(e_state E30 "$KB30")"
assert_eq "AC14 clean reply: (c) AskUserQuestion PASS" "PASS" "$(e_state E30 "$KC30")"
assert_eq "AC14 clean reply: (d) names clamp PASS" "PASS" "$(e_state E30 "$KD30")"
assert_eq "AC14 clean reply: (e) command or a count PASS" "PASS" "$(e_state E30 "$KE30")"

echo "AC13 (a) a chatbot opener or closer FAILs"
row30 "$KA30" FAIL "AC13a opener 'Great question!' FAILs" "Great question! $B30"
row30 "$KA30" FAIL "AC13a opener 'Certainly, here is the description.' FAILs" "Certainly, here is the description. $B30"
row30 "$KA30" FAIL "AC13a closer 'I hope this helps.' FAILs" "$B30 I hope this helps."
row30 "$KA30" FAIL "AC13a closer 'Let me know if you want changes.' FAILs" "$B30 Let me know if you want changes."
row30 "$KA30" FAIL "AC13a lower case 'let me know' FAILs" "$B30 let me know if you want changes."
row30 "$KA30" FAIL "AC13a closer 'Would you like me to add docs?' FAILs" "$B30 Would you like me to add docs?"
row30 "$KA30" FAIL "AC13a closer 'Want me to open the PR?' FAILs" "$B30 Want me to open the PR?"
row30 "$KA30" FAIL "AC13a closer 'Happy to help.' FAILs" "$B30 Happy to help."
row30 "$KA30" FAIL "AC13a closer 'Feel free to ask.' FAILs" "$B30 Feel free to ask."
row30 "$KA30" FAIL "AC13a a closer on its own last line after a code block FAILs" "$B30
\`\`\`
npm test
\`\`\`
Let me know if that works."
row30 "$KA30" FAIL "AC13a a quote that closed earlier does not excuse a later closer" "The old text said \"ok\" and I changed it. $B30 Let me know."

echo "AC13 (a) quoted or code text does not count"
row30 "$KA30" PASS "AC14a a double-quoted \"Let me know\" does not count" "$B30 The old text ended with \"Let me know if that works\", which I removed."
row30 "$KA30" PASS "AC14a a double-quoted \"Would you like\" does not count" "$B30 I dropped the line \"Would you like me to add docs?\" from the old text."
row30 "$KA30" PASS "AC14a an inline-code \`Feel free\` does not count" "$B30 The banned closer is \`Feel free to ask\`."
row30 "$KA30" PASS "AC14a a fenced block holding 'I hope this helps.' does not count" "$B30
\`\`\`
I hope this helps.
\`\`\`
Done."

echo "Fix1 F2 (a) an opener behind markdown (bold, quote) FAILs; a mid-sentence adverb does not"
row30 "$KA30" FAIL "F2 opener '**Certainly!** Here is ...' behind bold FAILs" "**Certainly!** Here is the PR description. $B30"
row30 "$KA30" FAIL "F2 opener '> Great question, ...' behind a quote marker FAILs" "> Great question, here is the description.
$B30"
row30 "$KA30" PASS "F2 the adverb 'certainly' in mid sentence does not count (pins the line-start anchor)" "The fix certainly helps clamp. $B30"

echo "Fix1 F3 (a) curly quotes and a tilde fence are excluded like straight quotes and a backtick fence"
LQ30="$(printf '\342\200\234')"; RQ30="$(printf '\342\200\235')"
row30 "$KA30" PASS "F3 a curly-quoted closer text does not count" "$B30 The old text said ${LQ30}Let me know if that works${RQ30}, removed."
row30 "$KA30" FAIL "F3 a closer after a closed curly-quoted span still FAILs (characterization)" "The old text said ${LQ30}ok${RQ30} and I changed it. $B30 Let me know."
row30 "$KA30" PASS "F3 a closer inside a ~~~ fence does not count" "$B30
~~~
Let me know if that works.
~~~
Done."

echo "AC2b, AC13 (b) an em or en dash outside code FAILs"
row30 "$KB30" FAIL "AC2b (b) an em dash in prose FAILs" "$B30 It is small ${EM30} one function."
row30 "$KB30" FAIL "AC2b (b) an en dash in prose FAILs" "$B30 It touches files 1${EN30}3."
row30 "$KB30" FAIL "AC2b (b) an em dash in a heading FAILs" "## Summary ${EM30} clamp
$B30"
row30 "$KB30" FAIL "AC2b (b) a code span plus a bare em dash on the same line FAILs" "$B30 Used \`lo\` and \`hi\` ${EM30} both inclusive."
row30 "$KB30" FAIL "AC2b (b) an em dash after a closed fenced block FAILs" "$B30
\`\`\`
npm test
\`\`\`
Then I stopped ${EM30} done."
row30 "$KB30" FAIL "AC2b (b) a double quote does not excuse a dash (only code does)" "$B30 The old text said \"small ${EM30} safe\"."

echo "AC14 (b) a dash inside code does not count"
row30 "$KB30" PASS "AC14b an em dash inside an inline code span passes" "$B30 The banned character is \`${EM30}\`."
row30 "$KB30" PASS "AC14b an en dash inside an inline code span passes" "$B30 The range \`1${EN30}3\` is replaced."
row30 "$KB30" PASS "AC14b an em dash inside a fenced block passes" "$B30
\`\`\`
before ${EM30} after
\`\`\`
Done."
row30 "$KB30" PASS "AC14b a dash inside a fenced block with a language tag passes" "$B30
\`\`\`js
const s = 'a ${EN30} b';
\`\`\`
Done."
row30 "$KB30" PASS "AC14b hyphens, double hyphens and numeric ranges with a hyphen pass" "$B30 It is a small, test-first change (flag --check, files 1-3)."

t_summary
