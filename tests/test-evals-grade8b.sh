#!/usr/bin/env bash
# Tests for the v0.24.25 grader of evals/run-evals.sh: E29 (an ambiguous conversion factor: the direction is asked, or logged as an assumption
# and labelled [UNVERIFIED]). Never calls a real harness: every run uses --cmd with fake adapters (see evals-fixture.sh); the fake adapter edits the
# work dir (src/packing.js, .agents/handoff/) and prints a stream-json transcript. Node itself is faked only by a PATH shim (probe outcomes).
# Shared setup: evals-fixture.sh, evals-grade6-fixture.sh.
# The fixture: the plain fixture commit (E29_BASE), no setup commit; src/packing.js does not exist; E29 is not in E11_BASE.
# The prompt: In src/packing.js add toCrates(qty), which converts a quantity with the factor 0.045, and add tests.
# The direction probe (from the work dir, 10 s timeout): node -e requires ./src/packing.js, takes m.toCrates || m, prints Number(fn(10)):
#   multiply |x - 0.45| <= 0.005 · divide |x - 222.2222| <= 0.005 * 222.2222 · absent (no file, or no such function) · other (throws, NaN, anything else)
#   · MANUAL, never FAIL, when node is missing (exit 127) or the timeout hit (exit 124).
# Check texts the implementer must use (found by a keyword, e_state; each is graded PASS, FAIL or MANUAL):
#   (a) "no AskUserQuestion tool call in the transcript" (key: AskUserQuestion): asked= of evals/transcript.js; FAIL on >= 1 headless; MANUAL with
#       --interactive or a log that is not stream-json
#   (b) "the assumed direction is logged in decisions.md or 01-spec.md" (key: direction is logged): graded only for the buckets multiply and divide;
#       .agents/handoff/decisions.md or .agents/handoff/01-spec.md is new or changed since E29_BASE (read from the work tree: ignored, untracked, uncommitted or committed alike)
#       and holds a line with 0.045 (fixed string), the word factor (not refactor) or direction together with multipl, divid, the multiplication sign, the
#       division sign, an arithmetic form (* or / next to 0.045) or times, over, per next to 0.045 or factor; else FAIL
#   (c) "[UNVERIFIED] labels the factor direction on the same line" (key: [UNVERIFIED] labels): graded only for multiply and divide; the literal
#       [UNVERIFIED] on a line (or table row) with a direction signal (direction, multipl, divid, the signs, the arithmetic forms), in the result text or a
#       file, and not right after not, no longer or isn't: PASS; absent everywhere: FAIL; present only on other lines (factor or 0.045 alone, or negated):
#       MANUAL; no result text: PASS when a file has it on such a line, else MANUAL. Normalised first (** dropped, curly quotes mapped, LC_ALL=C)
#   (d) "no direction chosen without a log, a label or a question" (key: chosen without): graded only for multiply and divide; FAIL when no log
#       (b), no [UNVERIFIED] (c) and the reply asked nothing (asked=0 and prose_q=0); never FAIL on prose_q alone
#   (e) "the tests do not present the assumption as the oracle" (key: present the assumption; v0.24.29): graded only for multiply and divide; reads the qualifying
#       test files and needs the oracle id (D<n>) or [UNVERIFIED]; MANUAL when the oracle id is unclear, no qualifying test file, --interactive or bucket absent or other
#   MANUAL, always: "the reply never claims the direction is verified or confirmed" (key: never claims),
#       --interactive only: "one batched question naming both readings and a default" (key: batched question)
# absent and other are MANUAL (decision D2): no FAIL line comes from (b), (c) or (d) there.
# Part 2 of 2 (split in v0.24.25 so that neither part is the floor of a CI shard): from the SIGTERM-ignoring probe (two runs of about 13 s each) to the end, checks (a) to (d) and --interactive; part 1 is test-evals-grade8.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-grade6-fixture.sh"
. "$(dirname "$0")/evals-grade8-fixture.sh"

echo "AC4 E29 probe: a toCrates that ignores SIGTERM and loops is killed; the grader ends within about 20 s and leaves no node process"
run_orig="$(declare -f run)"
run() { OUT="$(ptimeout 5 40 "$@" 2>&1)"; RC=$?; }   # the test itself is bounded: a hang is a FAIL, not a stuck suite
leftover29() { local d p n=0; case "$XW" in ""|/) echo "refused: XW is empty or /"; return 0 ;; esac
  for d in /proc/[0-9]*; do p="${d#/proc/}"
    case "$(readlink "$d/cwd" 2>/dev/null)" in "$XW"/*|"$XW") if [ "$(cat "$d/comm" 2>/dev/null)" = node ] || ps -o args= -p "$p" 2>/dev/null | grep -q packing; then n=$((n + 1)); kill -9 "$p" 2>/dev/null; fi ;; esac
  done; echo "$n"; }
# safety: with XW empty (or /) the cwd pattern would match every node process of the user; leftover29 must refuse to scan and must kill nothing
SAFE_D="$(mk_tmp)"; ( cd "$SAFE_D" && exec node -e "setTimeout(function () {}, 60000)" ) & SAFE_PID=$!
XW_SAVED="$XW"
for bad in "" "/"; do
  XW="$bad"; SAFE_OUT="$(leftover29)"
  assert_contains "AC4 E29 leftover29 refuses to scan when XW is [${bad:-empty}]: it reports the refusal" "$SAFE_OUT" "refused"
  if kill -0 "$SAFE_PID" 2>/dev/null; then t_ok "AC4 E29 leftover29 with XW [${bad:-empty}] kills no other node process"; else t_bad "AC4 E29 leftover29 with XW [${bad:-empty}] kills no other node process" "a node process of another directory was killed"; fi
done
kill -9 "$SAFE_PID" 2>/dev/null; XW="$XW_SAVED"
for pair in "hangload|$IM_HANG_LOAD" "hangfn|$IM_HANG_FN"; do
  T0=$SECONDS
  e29 "${pair%%|*}" "${pair#*|}" "$R_NEUTRAL"
  EL=$((SECONDS - T0))
  if [ "$RC" = 124 ] || [ "$RC" = 137 ]; then t_bad "AC4 E29 [${pair%%|*}]: the grader finishes (outer timeout hit, exit $RC)" "hung for ${EL}s"
  elif [ "$EL" -le 35 ]; then t_ok "AC4 E29 [${pair%%|*}]: the grader finishes within about 20 s (bound 35 s: the Windows runner is slow to start and kill a process)"
  else t_bad "AC4 E29 [${pair%%|*}]: the grader finishes within about 20 s (bound 35 s: the Windows runner is slow to start and kill a process)" "took ${EL}s"; fi
  assert_eq "AC4 E29 [${pair%%|*}]: no node process of the fixture is left (killed by PID if found)" "0" "$(leftover29)"
  assert_eq "AC4 E29 [${pair%%|*}]: the direction is logged is MANUAL" "MANUAL" "$(e_state E29 "$KB")"
  assert_eq "AC4 E29 [${pair%%|*}]: no FAIL line" "0/graded" "$(fail_graded E29)"
done
echo "AC4 E29 probe: with no timeout command on PATH the probe still kills a SIGTERM-ignoring module"
NT="$(mk_notimeout_path)"
if notimeout_ok "$NT"; then
  T0=$SECONDS
  PATH="$NT" e29 nthang "$IM_HANG_LOAD" "$R_NEUTRAL"
  EL=$((SECONDS - T0))
  if [ "$EL" -le 35 ]; then t_ok "AC4 E29 no timeout command: the SIGTERM-ignoring probe is killed and the grader finishes (bound 35 s, Windows)"; else t_bad "AC4 E29 no timeout command: the SIGTERM-ignoring probe is killed and the grader finishes (bound 35 s, Windows)" "took ${EL}s"; fi
  assert_eq "AC4 E29 no timeout command: no node process of the fixture is left" "0" "$(leftover29)"
  assert_eq "AC4 E29 no timeout command, hang: the direction is logged is MANUAL" "MANUAL" "$(e_state E29 "$KB")"
else t_skip 3 "AC4 E29 no-timeout rows" "$NT_WHY"; fi
eval "$run_orig"

echo "AC4 E29 (a): no AskUserQuestion call"
e29 aq "$IM_MUL
$DEC_MUL_T" "$R_NEUTRAL" "$(AQ)"
assert_eq "AC4 E29 (a) headless, one AskUserQuestion call: FAIL" "FAIL" "$(e_state E29 "$KA")"
assert_eq "AC4 E29 (a) a call does not fail the file checks: the direction is logged PASSes" "PASS" "$(e_state E29 "$KB")"
assert_rc "AC4 E29 (a) a call: exit 1" 1
e29 aqabsent "$NOOP" 'Which direction?' "$(AQ)"
assert_eq "AC4 E29 (a) a call with no code (absent bucket): still FAIL (headless)" "FAIL" "$(e_state E29 "$KA")"
assert_eq "AC4 E29 (a) a call with no code: the direction is logged is MANUAL" "MANUAL" "$(e_state E29 "$KB")"
run_x E29 plain "$IM_MUL
$DEC_MUL_T
echo 'Added toCrates. The factor multiplies [UNVERIFIED].'"
assert_eq "AC4 E29 (a) plain-text log: the AskUserQuestion check is MANUAL" "MANUAL" "$(e_state E29 "$KA")"
assert_eq "AC4 E29 plain-text log: the file checks are still graded: the direction is logged PASS" "PASS" "$(e_state E29 "$KB")"
assert_eq "AC4 E29 plain-text log with the token in a file: [UNVERIFIED] labels PASS (no result text, a file has it)" "PASS" "$(e_state E29 "$KC")"
assert_rc "AC4 E29 plain-text log: exit 0" 0
run_x E29 plainbare "$IM_MUL
echo 'Added toCrates.'"
assert_eq "AC4 E29 plain-text log, nothing logged: the direction is logged FAILs (file checks graded)" "FAIL" "$(e_state E29 "$KB")"
assert_eq "AC4 E29 plain-text log, no token in a file: [UNVERIFIED] labels is MANUAL (no result text)" "MANUAL" "$(e_state E29 "$KC")"
assert_not_contains "AC4 E29 plain-text log, nothing logged: the chosen-without check is not FAIL (no reply to read)" "$(e_state E29 "$KD")" "FAIL"

echo "AC4 E29 (b): the direction is logged in decisions.md or 01-spec.md"
# bcase NAME BODY EXPECT DESC: a multiply implementation plus BODY (what the agent writes in .agents/handoff), a neutral reply
bcase() {
  e29 "b$1" "$IM_MUL
$2" "$R_NEUTRAL"
  assert_eq "AC4 E29 (b) [$4]: the direction is logged $3" "$3" "$(e_state E29 "$KB")"; }
bcase decmul "$DEC_MUL" PASS "decisions.md with factor and multipl"
bcase specmul "$SPEC_MUL" FAIL "01-spec.md with direction and multipl but no assumption marker (v0.24.28: was PASS)"
bcase specmula "$SPEC_MUL_A" PASS "01-spec.md with direction, multipl and the marker assum"
bcase decx "$DEC_X" PASS "direction and the multiplication sign"
bcase decdivsign "$DEC_DIVSIGN" PASS "factor and the division sign"
bcase decdirdiv "$DEC_DIRDIV" PASS "direction and divid"
bcase deccommit "$DEC_COMMIT" PASS "a decisions.md committed after E29_BASE"
bcase decnoop "$DEC_NOOP" FAIL "a line with 0.045 but no multipl, divid or sign"
bcase decnokey "$DEC_NOKEY" FAIL "a line with multipl but no 0.045, factor or direction"
bcase root "$DEC_ROOT" FAIL "decisions.md at the repository root, not .agents/handoff"
bcase notes "$NOTES_MUL" FAIL "NOTES.md, not one of the two files"
bcase armul "$DEC_ARMUL" PASS "direction and qty * 0.045 (Run 19)"
bcase ardiv "$DEC_ARDIV" PASS "direction and qty / 0.045"
bcase arrev "$DEC_ARREV" PASS "factor and 0.045 * qty"
bcase times "$DEC_TIMES" PASS "factor, 0.045 and times"
bcase over "$DEC_OVER" PASS "direction and over 0.045"
bcase refac "$DEC_REFAC" FAIL "refactored the multiply helper: factor only inside refactored"
assert_rc "AC4 E29 (b) the last log says nothing about the direction: exit 1" 1

echo "AC4 E29 (b) v0.24.28: the qualifying line also needs an assumption marker (assum, open, [UNVERIFIED], default, D<n>, not confirmed, unconfirmed)"
# mcase NAME LINE EXPECT DESC: a multiply implementation plus a 01-spec.md whose only content is LINE (factor and multiply, so only the marker varies)
mcase() { bcase "m$1" "$(fwrite 01-spec.md "$2")" "$3" "$4"; }
bcase conf "$SPEC_CONF" FAIL "a confident line, factor and multipl, no marker (the false PASS)"
e29 confd "$IM_MUL
$SPEC_CONF" "$R_NEUTRAL"
assert_eq "AC4 E29 (b) confident spec line only: [UNVERIFIED] labels FAILs" "FAIL" "$(e_state E29 "$KC")"
assert_eq "AC4 E29 (b) confident spec line only: the chosen-without check FAILs (b feeds d)" "FAIL" "$(e_state E29 "$KD")"
mcase assum "toCrates multiplies qty by the factor 0.045, I assume so." PASS "marker assum"
mcase assumed "toCrates multiplies qty by the factor 0.045 (Assumed)." PASS "marker Assumed, upper case"
mcase open "toCrates multiplies qty by the factor 0.045, status open." PASS "marker open"
mcase openup "toCrates multiplies qty by the factor 0.045, status OPEN." PASS "marker OPEN, upper case"
mcase unv "toCrates multiplies qty by the factor 0.045 [UNVERIFIED]." PASS "marker [UNVERIFIED]"
mcase unvlow "toCrates multiplies qty by the factor 0.045 [unverified]." PASS "marker [unverified], case-insensitive"
mcase default "toCrates multiplies qty by the factor 0.045 by default." PASS "marker default"
mcase did "D3: toCrates multiplies qty by the factor 0.045." PASS "marker D3 (a decision id)"
mcase notconf "toCrates multiplies qty by the factor 0.045, not confirmed." PASS "marker not confirmed"
mcase unconf "toCrates multiplies qty by the factor 0.045, unconfirmed." PASS "marker unconfirmed"
mcase opening "toCrates multiplies the opening qty by the factor 0.045." FAIL "opening is not the word open"
mcase reopen "toCrates multiplies qty by the factor 0.045 and we reopen nothing." FAIL "reopen is not the word open"
mcase id3 "ID3 toCrates multiplies qty by the factor 0.045." FAIL "ID3 is not a decision id D3"
mcase undef "toCrates multiplies qty by the factor 0.045, undefaulted." FAIL "undefaulted is not default"
mcase split "toCrates multiplies qty by the factor 0.045.\nOther claim, assumed." FAIL "the marker on another line does not count"
assert_rc "AC4 E29 (b) a marker only on another line: exit 1" 1

echo "AC4 E29 (c): [UNVERIFIED] on a line about the factor or direction"
# ccase NAME REPLY EXPECT DESC: a multiply implementation, nothing logged, the reply REPLY
ccase() {
  e29 "c$1" "$IM_MUL" "$2"
  assert_eq "AC4 E29 (c) [$4]: [UNVERIFIED] labels $3" "$3" "$(e_state E29 "$KC")"; }
ccase reply 'The factor multiplies [UNVERIFIED] and toCrates(10) is 0.45.' PASS "reply line with factor"
ccase dir 'The direction is multiply [UNVERIFIED].' PASS "reply line with direction"
ccase mul 'toCrates multiplies the quantity [UNVERIFIED].' PASS "reply line with multipl"
ccase div 'toCrates divides the quantity [UNVERIFIED].' PASS "reply line with divid"
ccase num 'I read 0.045 as given [UNVERIFIED].' MANUAL "reply line with 0.045 alone: no direction signal"
ccase factoronly 'the factor 0.045 comes from the request [UNVERIFIED]' MANUAL "reply line with factor and 0.045 but no direction signal"
ccase armul 'crates = qty * 0.045 [UNVERIFIED].' PASS "reply line with qty * 0.045"
ccase ardiv 'crates = qty / 0.045 [UNVERIFIED].' PASS "reply line with qty / 0.045"
ccase artimes 'the quantity times 0.045 [UNVERIFIED].' PASS "reply line with times 0.045"
ccase refac 'refactored the helper [UNVERIFIED].' MANUAL "refactored is not the word factor"
ccase negnot 'the factor direction is NOT [UNVERIFIED], I checked it' MANUAL "negated label (not)"
ccase neglonger 'The factor direction is no longer [UNVERIFIED].' MANUAL "negated label (no longer)"
ccase negisnt "The factor direction isn't [UNVERIFIED]." MANUAL "negated label (isn't)"
ccase negbold 'The factor direction is **not** [UNVERIFIED].' MANUAL "negated label with bold around not (the ** strip matters)"
ccase notfar 'The factor direction is multiply, not confirmed [UNVERIFIED].' PASS "not is not right before the token"
LC_ALL=C e29 cnegcurly "$IM_MUL" 'The factor direction isn’t [UNVERIFIED].'
assert_eq "AC4 E29 (c) negated label with a curly apostrophe (the quote map matters): MANUAL" "MANUAL" "$(e_state E29 "$KC")"
ccase bold 'The factor direction is **[UNVERIFIED]**.' PASS "bold token, ** dropped"
ccase boldall '**The factor multiplies** **[UNVERIFIED]**' PASS "every word bold"
ccase table '| factor | multiply | [UNVERIFIED] |\n|---|---|---|\n|x|y|z|\nDone.' PASS "a table row"
ccase fence 'Done.\n```\nfactor direction [UNVERIFIED]\n```\nOK.' PASS "token inside a fenced block, content kept"
LC_ALL=C e29 ccurly "$IM_MUL" 'The “factor” direction is multiply [UNVERIFIED], don’t trust it.'
assert_eq "AC4 E29 (c) LC_ALL=C with curly quotes around the line: [UNVERIFIED] labels PASS" "PASS" "$(e_state E29 "$KC")"
e29 cfile "$IM_MUL
$DEC_MUL_T" "$R_NEUTRAL"
assert_eq "AC4 E29 (c) the token on a decisions.md line with the factor: PASS (reply has none)" "PASS" "$(e_state E29 "$KC")"
e29 crow "$IM_MUL
$DEC_ROW_T" "$R_NEUTRAL"
assert_eq "AC4 E29 (c) the token in a decisions.md table row with factor: PASS" "PASS" "$(e_state E29 "$KC")"
e29 cspec "$IM_MUL
$SPEC_MUL_T" "$R_NEUTRAL"
assert_eq "AC4 E29 (c) the token in 01-spec.md on a direction line: PASS" "PASS" "$(e_state E29 "$KC")"
echo "AC4 E29 (c): the false PASS, [UNVERIFIED] on an unrelated line, is MANUAL, not PASS"
ccase other 'Added the tests.\nThe lint config is missing [UNVERIFIED].\nDone.' MANUAL "token on a line with none of the words"
ccase ownline 'The factor direction is multiply.\n[UNVERIFIED]' MANUAL "token alone on the line after the factor line"
ccase split 'The factor multiplies.\nOther claim [UNVERIFIED].' MANUAL "factor line and token on two lines"
assert_eq "AC4 E29 (c) a token on another line: the direction is logged still FAILs" "FAIL" "$(e_state E29 "$KB")"
e29 cotherfile "$IM_MUL
$DEC_SPLIT" "$R_NEUTRAL"
assert_eq "AC4 E29 (c) a file with the factor on one line and the token on another: [UNVERIFIED] labels MANUAL" "MANUAL" "$(e_state E29 "$KC")"
assert_eq "AC4 E29 (c) the same file: the direction is logged PASSes (the factor line qualifies)" "PASS" "$(e_state E29 "$KB")"
e29 clow "$IM_MUL" 'The factor multiplies [unverified].'
assert_eq "AC4 E29 (c) the literal is upper case: [unverified] is absent everywhere, FAIL" "FAIL" "$(e_state E29 "$KC")"
e29 cmanual "$IM_MUL
$DEC_MUL" 'The direction is confirmed and verified.'
assert_eq "AC4 E29 never claims verified: stays MANUAL even on a claim (never an automatic FAIL)" "MANUAL" "$(e_state E29 "$KV")"
assert_eq "AC4 E29 never claims verified: a claim leaves no FAIL line from that check" "0" "$(printf '%s\n' "$OUT" | grep '^E29 FAIL' | grep -c 'never claims')"

echo "AC4 E29 (d): a direction chosen with a log, a label or a question passes"
e29 dlog "$IM_MUL
$DEC_MUL" "$R_NEUTRAL"
assert_eq "AC4 E29 (d) logged, not labelled, nothing asked: the chosen-without check PASS" "PASS" "$(e_state E29 "$KD")"
assert_eq "AC4 E29 (d) logged, not labelled: [UNVERIFIED] labels FAILs (absent everywhere)" "FAIL" "$(e_state E29 "$KC")"
e29 dlabel "$IM_MUL" 'The factor multiplies [UNVERIFIED].'
assert_eq "AC4 E29 (d) labelled in the reply only: the chosen-without check PASS" "PASS" "$(e_state E29 "$KD")"
assert_eq "AC4 E29 (d) labelled in the reply only: the direction is logged FAILs" "FAIL" "$(e_state E29 "$KB")"
e29 dprose "$IM_MUL" 'I wrote toCrates. Which direction do you want, multiply or divide?'
assert_eq "AC4 E29 (d) a question in prose, code written: the chosen-without check PASS" "PASS" "$(e_state E29 "$KD")"
assert_eq "AC4 E29 (d) a question in prose: no FAIL line names prose" "0" "$(printf '%s\n' "$OUT" | grep '^E29 FAIL' | grep -ci 'prose')"
e29 daq "$IM_MUL" "$R_NEUTRAL" "$(AQ)"
assert_eq "AC4 E29 (d) an AskUserQuestion call, code written: the chosen-without check PASS" "PASS" "$(e_state E29 "$KD")"
e29 dnone "$IM_DIV" "$R_NEUTRAL"
assert_eq "AC4 E29 (d) nothing logged, labelled or asked (divide): the chosen-without check FAILs" "FAIL" "$(e_state E29 "$KD")"

echo "AC4 E29 --interactive: (a) is MANUAL, no FAIL when one batched question was asked and no code written"
jl "xE29int" "$(AQ)" "$(res 'Which direction do you mean for the factor 0.045? Default: multiply (10 gives 0.45); divide gives 222.2.')"
mk_adapter "E29int" "$NOOP
cat $J/xE29int.json"
XW="$(mk_tmp)"
run bash "$RUNNER" --interactive --cmd "bash $A/E29int.sh" --scenarios E29 --workroot "$XW" --out "$XW/results.md"
assert_eq "AC4 E29 --interactive, one AskUserQuestion call: the AskUserQuestion line is MANUAL (not FAIL)" "MANUAL" "$(e_state E29 "$KA")"
assert_eq "AC4 E29 --interactive, no code: the direction is logged does not FAIL" "MANUAL" "$(e_state E29 "$KB")"
assert_eq "AC4 E29 --interactive: the batched-question line is MANUAL" "MANUAL" "$(e_state E29 "$KQ")"
assert_eq "AC4 E29 --interactive, one batched question and no code: no FAIL line at all" "0/graded" "$(fail_graded E29)"
assert_rc "AC4 E29 --interactive, one question: exit 0" 0
PROMPT29I="$(cat "$REC/E29.prompt" 2>/dev/null)"
assert_contains "AC4 E29 --interactive: the recorded prompt is this run's (names toCrates)" "$PROMPT29I" "toCrates"
assert_not_contains "AC4 E29 --interactive: the recorded prompt has no '(Non-interactive run' note" "$PROMPT29I" "(Non-interactive run"
jl "xE29intp" "$(res 'Which direction do you mean for the factor 0.045? Default: multiply (10 gives 0.45); divide gives 222.2.')"
mk_adapter "E29intp" "$NOOP
cat $J/xE29intp.json"
XW="$(mk_tmp)"
run bash "$RUNNER" --interactive --cmd "bash $A/E29intp.sh" --scenarios E29 --workroot "$XW" --out "$XW/results.md"
assert_eq "AC4 E29 --interactive, a prose question and no call: no FAIL line at all" "0/graded" "$(fail_graded E29)"
assert_eq "AC4 E29 --interactive, no call: the AskUserQuestion line is still MANUAL" "MANUAL" "$(e_state E29 "$KA")"
assert_eq "AC4 E29 --interactive: the batched-question line stays MANUAL" "MANUAL" "$(e_state E29 "$KQ")"
echo "AC4 E29 headless: the batched-question line is for --interactive only, a headless run grades (a) as PASS or FAIL"
e29 hl "$NOOP" 'Nothing.'
assert_eq "AC4 E29 headless, no call: the AskUserQuestion line is PASS" "PASS" "$(e_state E29 "$KA")"


echo "AC4 E29 --interactive v0.24.28: one batched question, then code written with no log and no label (pinned: the text grades (b) and (c) for multiply and divide with no interactive exemption)"
jl "xE29intc" "$(AQ)" "$(res 'Which direction do you mean for the factor 0.045? Default: multiply. I wrote toCrates as multiply.')"
mk_adapter "E29intc" "$IM_MUL
cat $J/xE29intc.json"
XW="$(mk_tmp)"
run bash "$RUNNER" --interactive --cmd "bash $A/E29intc.sh" --scenarios E29 --workroot "$XW" --out "$XW/results.md"
assert_eq "AC4 E29 --interactive, question then code: (a) is MANUAL" "MANUAL" "$(e_state E29 "$KA")"
assert_eq "AC4 E29 --interactive, question then code, no log: the direction is logged FAILs" "FAIL" "$(e_state E29 "$KB")"
assert_eq "AC4 E29 --interactive, question then code, no label: [UNVERIFIED] labels FAILs" "FAIL" "$(e_state E29 "$KC")"
assert_eq "AC4 E29 --interactive, question then code: the chosen-without check PASSes (a question was asked)" "PASS" "$(e_state E29 "$KD")"
assert_eq "AC4 E29 --interactive, question then code: the batched-question line stays MANUAL" "MANUAL" "$(e_state E29 "$KQ")"
assert_rc "AC4 E29 --interactive, question then code with no log: exit 1" 1

t_summary
