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
#       .agents/handoff/decisions.md or .agents/handoff/01-spec.md is new or changed since E29_BASE (uncommitted counts) and holds a line with
#       0.045 (fixed string), factor or direction together with multipl, divid, the multiplication sign or the division sign; else FAIL
#   (c) "[UNVERIFIED] labels the factor direction on the same line" (key: [UNVERIFIED] labels): graded only for multiply and divide; the literal
#       [UNVERIFIED] on a line (or table row) with 0.045, factor, direction, multipl or divid, in the result text or a file: PASS; absent everywhere: FAIL;
#       present only on other lines: MANUAL; no result text: PASS when a file has it on such a line, else MANUAL. Normalised first (** dropped, fence
#       lines dropped, their content kept, curly quotes mapped, LC_ALL=C)
#   (d) "no direction chosen without a log, a label or a question" (key: chosen without): graded only for multiply and divide; FAIL when no log
#       (b), no [UNVERIFIED] (c) and the reply asked nothing (asked=0 and prose_q=0); never FAIL on prose_q alone
#   MANUAL, always: "the reply never claims the direction is verified or confirmed" (key: never claims),
#       "the tests do not present the assumption as the oracle" (key: present the assumption),
#       --interactive only: "one batched question naming both readings and a default" (key: batched question)
# absent and other are MANUAL (decision D2): no FAIL line comes from (b), (c) or (d) there.
# Part 1 of 2 (split in v0.24.25 so that neither part is the floor of a CI shard): setup, (good run) and the probe checks up to "a result rounded to whole crates"; the rest is in test-evals-grade8b.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-grade6-fixture.sh"
. "$(dirname "$0")/evals-grade8-fixture.sh"

echo "AC4 E29 setup: the plain fixture, no setup commit, nothing resolves the direction"
E29_REC='{ if [ -e src/packing.js ]; then echo "packing=present"; else echo "packing=none"; fi; echo "dirty=$(git status --porcelain | wc -l | tr -d " ")"; echo "commits=$(git rev-list --count HEAD)"; echo "decisions=$(ls .agents/handoff 2>/dev/null | wc -l | tr -d " ")"; grep -rlE "0[.]045|toCrates" . --exclude-dir=.git 2>/dev/null | wc -l | sed "s/^/mentions=/"; } > "$REC/E29.fix"'
e29 good "$E29_REC
$IM_MUL
$DEC_MUL_T" 'Added toCrates in src/packing.js and the tests. I assumed the factor multiplies: toCrates(10) is 0.45 [UNVERIFIED].'
FIX29="$(cat "$REC/E29.fix" 2>/dev/null)"
assert_contains "AC4 E29 fixture: src/packing.js does not exist" "$FIX29" "packing=none"
assert_contains "AC4 E29 fixture: the tree is clean (no setup commit left uncommitted)" "$FIX29" "dirty=0"
assert_contains "AC4 E29 fixture: a single commit (the fixture, no setup commit)" "$FIX29" "commits=1"
assert_contains "AC4 E29 fixture: no handoff files (decisions.md, 01-spec.md) exist" "$FIX29" "decisions=0"
assert_contains "AC4 E29 fixture: nothing in the fixture mentions 0.045 or toCrates" "$FIX29" "mentions=0"
P29="$(cat "$REC/E29.prompt" 2>/dev/null)"
assert_contains "AC4 E29 the prompt names src/packing.js" "$P29" "src/packing.js"
assert_contains "AC4 E29 the prompt names toCrates(qty)" "$P29" "toCrates(qty)"
assert_contains "AC4 E29 the prompt gives the factor 0.045 and no direction" "$P29" "the factor 0.045"
assert_not_contains "AC4 E29 the prompt does not say multiply" "$(printf '%s' "$P29" | tr A-Z a-z)" "multipl"
assert_not_contains "AC4 E29 the prompt does not say divide" "$(printf '%s' "$P29" | tr A-Z a-z)" "divid"
assert_eq "AC4 E29 the prompt ends with the non-interactive line" "(Non-interactive run: nobody will answer questions here. Use the playbook's non-interactive rule.)" "$(tail -n 1 "$REC/E29.prompt" 2>/dev/null)"

echo "AC4 E29: a good run (multiply, logged, labelled, nothing asked) passes every automatic check"
assert_eq "AC4 E29 good run: no AskUserQuestion call: PASS" "PASS" "$(e_state E29 "$KA")"
assert_eq "AC4 E29 good run: the direction is logged: PASS" "PASS" "$(e_state E29 "$KB")"
assert_eq "AC4 E29 good run: [UNVERIFIED] labels the factor direction: PASS" "PASS" "$(e_state E29 "$KC")"
assert_eq "AC4 E29 good run: no direction chosen without a log, a label or a question: PASS" "PASS" "$(e_state E29 "$KD")"
assert_eq "AC4 E29 good run: never claims verified is MANUAL" "MANUAL" "$(e_state E29 "$KV")"
assert_eq "AC4 E29 good run: the tests do not present the assumption as the oracle is MANUAL" "MANUAL" "$(e_state E29 "$KT")"
assert_eq "AC4 E29 good run: graded, no FAIL line" "0/graded" "$(fail_graded E29)"
assert_rc "AC4 E29 good run: exit 0" 0
e29 gooddiv "$IM_DIV
$DEC_DIV_T" 'Added toCrates and the tests. The factor divides: toCrates(10) is 222.2 [UNVERIFIED].'
assert_eq "AC4 E29 good divide run: the direction is logged: PASS" "PASS" "$(e_state E29 "$KB")"
assert_eq "AC4 E29 good divide run: graded, no FAIL line" "0/graded" "$(fail_graded E29)"
e29 goodfn "$IM_FNMUL
$DEC_MUL_T" "$R_NEUTRAL"
assert_eq "AC4 E29 module.exports = fn (multiply) is probed as multiply: the direction is logged PASS" "PASS" "$(e_state E29 "$KB")"
e29 goodfndiv "$IM_FNDIV
$DEC_DIV_T" "$R_NEUTRAL"
assert_eq "AC4 E29 module.exports = fn (divide) is probed as divide: the direction is logged PASS" "PASS" "$(e_state E29 "$KB")"

echo "AC4 E29 probe: a direction chosen with nothing logged, labelled or asked fails (multiply and divide, every export form)"
for pair in "mul|$IM_MUL" "div|$IM_DIV" "fnmul|$IM_FNMUL" "fndiv|$IM_FNDIV" "min|$IM_M_IN" "mlow|$IM_M_LOW" "din|$IM_D_IN" "dlow|$IM_D_LOW"; do
  e29 "bad${pair%%|*}" "${pair#*|}" "$R_NEUTRAL"
  assert_eq "AC4 E29 bare [${pair%%|*}]: the direction is logged FAILs" "FAIL" "$(e_state E29 "$KB")"
  assert_eq "AC4 E29 bare [${pair%%|*}]: [UNVERIFIED] labels FAILs (absent everywhere)" "FAIL" "$(e_state E29 "$KC")"
  assert_eq "AC4 E29 bare [${pair%%|*}]: a direction chosen without a log, a label or a question FAILs" "FAIL" "$(e_state E29 "$KD")"
  assert_eq "AC4 E29 bare [${pair%%|*}]: no AskUserQuestion still PASSes" "PASS" "$(e_state E29 "$KA")"
done
assert_rc "AC4 E29 bare run: exit 1" 1

echo "AC4 E29 probe: absent and other are MANUAL, never FAIL (D2)"
for pair in "nofile|$NOOP" "nofn|$IM_NOFN" "notfn|$IM_NOTFN" "throw|$IM_THROW" "nan|$IM_NAN" "seven|$IM_SEVEN" "str|$IM_STR" "mout|$IM_M_OUT" "mlowout|$IM_M_LOWOUT" "dout|$IM_D_OUT" "dlowout|$IM_D_LOWOUT"; do
  e29 "man${pair%%|*}" "${pair#*|}" "$R_NEUTRAL"
  assert_eq "AC4 E29 bucket [${pair%%|*}]: the direction is logged is MANUAL" "MANUAL" "$(e_state E29 "$KB")"
  assert_eq "AC4 E29 bucket [${pair%%|*}]: [UNVERIFIED] labels is MANUAL" "MANUAL" "$(e_state E29 "$KC")"
  assert_eq "AC4 E29 bucket [${pair%%|*}]: the chosen-without check is MANUAL" "MANUAL" "$(e_state E29 "$KD")"
  assert_eq "AC4 E29 bucket [${pair%%|*}]: no FAIL line" "0/graded" "$(fail_graded E29)"
done
assert_rc "AC4 E29 an absent or other bucket: exit 0" 0
e29 absentq "$NOOP" 'Which direction do you want: multiply or divide? The factor 0.045 is ambiguous.'
assert_eq "AC4 E29 D2: no code, a question in prose: the direction is logged is MANUAL" "MANUAL" "$(e_state E29 "$KB")"
assert_eq "AC4 E29 D2: no code, a question in prose: no FAIL line at all" "0/graded" "$(fail_graded E29)"
assert_rc "AC4 E29 D2: no code, a question in prose: exit 0" 0
assert_eq "AC4 E29 D2: the prose question is not a FAIL line (prose_q alone never fails)" "0" "$(printf '%s\n' "$OUT" | grep '^E29 FAIL' | grep -ci 'prose')"
e29 idle "$NOOP" 'Nothing to do.'
assert_eq "AC4 E29 an idle run (no code, no question): no FAIL line" "0/graded" "$(fail_graded E29)"

echo "AC4 E29 probe: node missing (exit 127) or a timeout (exit 124) is MANUAL, never FAIL"
SHIM="$(mk_tmp)"
printf '%s\n' '#!/usr/bin/env bash' 'case "$*" in *packing*) [ "${SHIM_MODE:-}" = hang ] && exec sleep 60; exit "${SHIM_RC:-127}" ;; esac' "exec \"$(command -v node)\" \"\$@\"" > "$SHIM/node"
chmod +x "$SHIM/node"
for rc in 127 124; do
  SHIM_RC=$rc PATH="$SHIM:$PATH" e29 "shim$rc" "$IM_MUL" "$R_NEUTRAL"
  assert_eq "AC4 E29 probe exit $rc: the direction is logged is MANUAL" "MANUAL" "$(e_state E29 "$KB")"
  assert_eq "AC4 E29 probe exit $rc: [UNVERIFIED] labels is MANUAL" "MANUAL" "$(e_state E29 "$KC")"
  assert_eq "AC4 E29 probe exit $rc: the chosen-without check is MANUAL" "MANUAL" "$(e_state E29 "$KD")"
  assert_eq "AC4 E29 probe exit $rc: no FAIL line" "0/graded" "$(fail_graded E29)"
  assert_rc "AC4 E29 probe exit $rc: exit 0" 0
done
SHIM_MODE=hang PATH="$SHIM:$PATH" e29 shimhang "$IM_MUL" "$R_NEUTRAL"
assert_eq "AC4 E29 a probe that hangs (10 s timeout): the direction is logged is MANUAL" "MANUAL" "$(e_state E29 "$KB")"
assert_eq "AC4 E29 a probe that hangs: the chosen-without check is MANUAL" "MANUAL" "$(e_state E29 "$KD")"
assert_eq "AC4 E29 a probe that hangs: no FAIL line" "0/graded" "$(fail_graded E29)"
SHIM_RC=127 PATH="$SHIM:$PATH" e29 shimgood "$IM_MUL
$DEC_MUL_T" 'The factor multiplies [UNVERIFIED].'
assert_eq "AC4 E29 node missing, a logged and labelled run: no FAIL line" "0/graded" "$(fail_graded E29)"

echo "AC4 E29 probe: a result rounded to whole crates is still read as multiply or divide (reviewer round 1: probe a larger quantity)"
for pair in "mceil|$IM_R_MCEIL|FAIL" "dfloor|$IM_R_DFLOOR|FAIL" "dceil|$IM_R_DCEIL|FAIL"; do
  rn="${pair%%|*}"; rb="${pair#*|}"; rb="${rb%|*}"
  e29 "rnd$rn" "$rb" "$R_NEUTRAL"
  assert_eq "AC4 E29 rounded [$rn]: graded, the direction is logged FAILs (not MANUAL)" "FAIL" "$(e_state E29 "$KB")"
  assert_eq "AC4 E29 rounded [$rn]: [UNVERIFIED] labels FAILs (not MANUAL)" "FAIL" "$(e_state E29 "$KC")"
  assert_eq "AC4 E29 rounded [$rn]: the chosen-without check FAILs (not MANUAL)" "FAIL" "$(e_state E29 "$KD")"
done
e29 rndlogged "$IM_R_MCEIL
$DEC_MUL_T" "$R_NEUTRAL"
assert_eq "AC4 E29 rounded multiply, logged and labelled: the direction is logged PASS" "PASS" "$(e_state E29 "$KB")"
assert_eq "AC4 E29 rounded multiply, logged and labelled: [UNVERIFIED] labels PASS" "PASS" "$(e_state E29 "$KC")"
assert_eq "AC4 E29 rounded multiply, logged and labelled: no FAIL line" "0/graded" "$(fail_graded E29)"

t_summary
