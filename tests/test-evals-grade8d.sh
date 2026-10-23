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
# Part 4 of 4 (split from test-evals-grade8b.sh for the Windows Git Bash run time): the assumption-marker rows of check (b) (v0.24.28); part 1 is test-evals-grade8.sh, part 2 is test-evals-grade8b.sh, part 3 is test-evals-grade8c.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-grade6-fixture.sh"
. "$(dirname "$0")/evals-grade8-fixture.sh"

# bcase NAME BODY EXPECT DESC: a multiply implementation plus BODY (what the agent writes in .agents/handoff), a neutral reply
bcase() {
  e29 "b$1" "$IM_MUL
$2" "$R_NEUTRAL"
  assert_eq "AC4 E29 (b) [$4]: the direction is logged $3" "$3" "$(e_state E29 "$KB")"; }

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

t_summary
