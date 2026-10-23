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
# Part 3 of 3 (split from test-evals-grade8b.sh in v0.24.29: the slowest rows, so that no part is the floor of a CI shard): the SIGTERM-ignoring probe (two runs of about 13 s each) and the leftover29 safety rows; part 1 is test-evals-grade8.sh, part 2 is test-evals-grade8b.sh.
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

eval "$run_orig"

t_summary
