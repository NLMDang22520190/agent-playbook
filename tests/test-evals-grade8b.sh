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
# Part 2 of 4 (split in v0.24.25, again in v0.24.29, and a third time for the Windows Git Bash run time, each part about 300 s or less there): the no-timeout-command probe (one run of about 15 s), checks (a) and (b), check (d) and --interactive; part 1 is test-evals-grade8.sh, part 3 (the SIGTERM-ignoring probe and check (c)) is test-evals-grade8c.sh, part 4 (the assumption-marker rows of check (b)) is test-evals-grade8d.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-grade6-fixture.sh"
. "$(dirname "$0")/evals-grade8-fixture.sh"

run_orig="$(declare -f run)"
run() { OUT="$(ptimeout 5 40 "$@" 2>&1)"; RC=$?; }   # the test itself is bounded: a hang is a FAIL, not a stuck suite
leftover29() { local d p n=0; case "$XW" in ""|/) echo "refused: XW is empty or /"; return 0 ;; esac
  for d in /proc/[0-9]*; do p="${d#/proc/}"
    case "$(readlink "$d/cwd" 2>/dev/null)" in "$XW"/*|"$XW") if [ "$(cat "$d/comm" 2>/dev/null)" = node ] || ps -o args= -p "$p" 2>/dev/null | grep -q packing; then n=$((n + 1)); kill -9 "$p" 2>/dev/null; fi ;; esac
  done; echo "$n"; }
# safety: with XW empty (or /) the cwd pattern would match every node process of the user; leftover29 must refuse to scan and must kill nothing

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
