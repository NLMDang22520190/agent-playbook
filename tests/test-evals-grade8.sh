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
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-grade6-fixture.sh"

fail_graded() { printf '%s/%s' "$(count_lines "$1" FAIL)" "$([ "$(count_lines "$1" PASS)" -gt 0 ] && echo graded || echo ungraded)"; }
KA='AskUserQuestion'; KB='direction is logged'; KC='[UNVERIFIED] labels'; KD='chosen without'
KV='never claims'; KT='present the assumption'; KQ='batched question'
NOOP='true'
SP='src/packing.js'
# implementations of toCrates(qty), each written by the fake adapter in the work dir
mkimpl() { printf 'mkdir -p src\nprintf "%s\\n" > src/packing.js' "$1"; }
IM_MUL="$(mkimpl 'module.exports = { toCrates: (q) => q * 0.045 };')"
IM_DIV="$(mkimpl 'module.exports = { toCrates: (q) => q / 0.045 };')"
IM_FNMUL="$(mkimpl 'module.exports = (q) => q * 0.045;')"
IM_FNDIV="$(mkimpl 'module.exports = (q) => q / 0.045;')"
IM_NOFN="$(mkimpl 'module.exports = { other: 1 };')"
IM_THROW="$(mkimpl 'module.exports = { toCrates: () => { throw new Error(\"x\"); } };')"
IM_NAN="$(mkimpl 'module.exports = { toCrates: () => NaN };')"
IM_SEVEN="$(mkimpl 'module.exports = { toCrates: () => 7 };')"
IM_STR="$(mkimpl 'module.exports = { toCrates: () => \"abc\" };')"
IM_NOTFN="$(mkimpl 'module.exports = { toCrates: 5 };')"
# edges of the bucket tolerances (reviewer-backed, round 1): about 0.5% relative on both readings, whatever quantity the probe uses, so the
# fixtures scale with q: multiply q * 0.045 within +-0.5%, divide q / 0.045 within +-0.5%. 1.004 is inside, 1.006 is outside.
IM_M_IN="$(mkimpl 'module.exports = { toCrates: (q) => q * 0.045 * 1.004 };')"
IM_M_OUT="$(mkimpl 'module.exports = { toCrates: (q) => q * 0.045 * 1.006 };')"
IM_M_LOW="$(mkimpl 'module.exports = { toCrates: (q) => q * 0.045 * 0.996 };')"
IM_M_LOWOUT="$(mkimpl 'module.exports = { toCrates: (q) => q * 0.045 * 0.994 };')"
IM_D_IN="$(mkimpl 'module.exports = { toCrates: (q) => q / 0.045 * 1.004 };')"
IM_D_OUT="$(mkimpl 'module.exports = { toCrates: (q) => q / 0.045 * 1.006 };')"
IM_D_LOW="$(mkimpl 'module.exports = { toCrates: (q) => q / 0.045 * 0.996 };')"
IM_D_LOWOUT="$(mkimpl 'module.exports = { toCrates: (q) => q / 0.045 * 0.994 };')"
# results rounded to whole crates: a probe at qty 10 cannot see the direction (ceil(0.45) is 1), a larger quantity can
IM_R_MCEIL="$(mkimpl 'module.exports = q => Math.ceil(q*0.045);')"
IM_R_DFLOOR="$(mkimpl 'module.exports = q => Math.floor(q/0.045);')"
IM_R_DCEIL="$(mkimpl 'module.exports = q => Math.ceil(q/0.045);')"
# a toCrates that ignores SIGTERM and never returns: the probe timeout must still end it (SIGKILL after a grace period)
IM_HANG_LOAD="$(mkimpl 'process.on(\"SIGTERM\", () => {}); while (true) {}')"
IM_HANG_FN="$(mkimpl 'module.exports = { toCrates: () => { process.on(\"SIGTERM\", () => {}); while (true) {} } };')"
# the files an agent leaves in .agents/handoff
HD='mkdir -p .agents/handoff'
fwrite() { printf '%s\nprintf "%s\\n" > .agents/handoff/%s' "$HD" "$2" "$1"; }
DEC_MUL="$(fwrite decisions.md '# Decisions\nD1: the factor 0.045 is applied as multiply, qty * 0.045.')"
DEC_MUL_T="$(fwrite decisions.md '# Decisions\nD1: the factor 0.045 is applied as multiply, qty * 0.045. [UNVERIFIED]')"
DEC_DIV_T="$(fwrite decisions.md '# Decisions\nD1: the factor 0.045 is applied as divide, qty / 0.045. [UNVERIFIED]')"
DEC_ROW_T="$(fwrite decisions.md '# Decisions\n| D1 | factor | multiply | [UNVERIFIED] |')"
DEC_SPLIT="$(fwrite decisions.md '# Decisions\nD1: the factor 0.045 is applied as multiply.\nD2: the lint config is missing [UNVERIFIED]')"
DEC_NOOP="$(fwrite decisions.md '# Decisions\nD1: used 0.045 in the module.')"
DEC_NOKEY="$(fwrite decisions.md '# Decisions\nD1: packing multiplies things.')"
DEC_X="$(fwrite decisions.md '# Decisions\nD1: direction: qty × F.')"
DEC_DIVSIGN="$(fwrite decisions.md '# Decisions\nD1: the factor: qty ÷ factor.')"
DEC_DIRDIV="$(fwrite decisions.md '# Decisions\nD1: direction is divide.')"
SPEC_MUL="$(fwrite 01-spec.md '# Spec\nThe direction of the conversion: multiply.')"
SPEC_MUL_T="$(fwrite 01-spec.md '# Spec\nThe direction of the conversion: multiply [UNVERIFIED].')"
DEC_COMMIT="$DEC_MUL
$GC add -f .agents/handoff/decisions.md
$GC commit -qm 'log the assumption'"
DEC_ROOT='printf "D1: the factor 0.045 is applied as multiply.\n" > decisions.md'
NOTES_MUL='printf "the factor 0.045 is applied as multiply [UNVERIFIED]\n" > NOTES.md'
R_NEUTRAL='Added toCrates in src/packing.js and the tests. All done.'

# e29 NAME BODY REPLY [TRANSCRIPT-LINE...]: one headless E29 run; sets OUT, RC
e29() { local n="$1" body="$2" reply="$3"; shift 3
  if [ $# -gt 0 ]; then run_x E29 "$n" "$body" "$INIT" "$@" "$(res "$reply")"; else run_x E29 "$n" "$body" "$INIT" "$(res "$reply")"; fi; }

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

echo "AC4 E29 probe: a toCrates that ignores SIGTERM and loops is killed; the grader ends within about 20 s and leaves no node process"
run_orig="$(declare -f run)"
run() { OUT="$(timeout -k 5 40 "$@" 2>&1)"; RC=$?; }   # the test itself is bounded: a hang is a FAIL, not a stuck suite
leftover29() { local d p n=0; for d in /proc/[0-9]*; do p="${d#/proc/}"
    case "$(readlink "$d/cwd" 2>/dev/null)" in "$XW"/*|"$XW") if [ "$(cat "$d/comm" 2>/dev/null)" = node ] || ps -o args= -p "$p" 2>/dev/null | grep -q packing; then n=$((n + 1)); kill -9 "$p" 2>/dev/null; fi ;; esac
  done; echo "$n"; }
for pair in "hangload|$IM_HANG_LOAD" "hangfn|$IM_HANG_FN"; do
  T0=$SECONDS
  e29 "${pair%%|*}" "${pair#*|}" "$R_NEUTRAL"
  EL=$((SECONDS - T0))
  if [ "$RC" = 124 ] || [ "$RC" = 137 ]; then t_bad "AC4 E29 [${pair%%|*}]: the grader finishes (outer timeout hit, exit $RC)" "hung for ${EL}s"
  elif [ "$EL" -le 20 ]; then t_ok "AC4 E29 [${pair%%|*}]: the grader finishes within about 20 s"
  else t_bad "AC4 E29 [${pair%%|*}]: the grader finishes within about 20 s" "took ${EL}s"; fi
  assert_eq "AC4 E29 [${pair%%|*}]: no node process of the fixture is left (killed by PID if found)" "0" "$(leftover29)"
  assert_eq "AC4 E29 [${pair%%|*}]: the direction is logged is MANUAL" "MANUAL" "$(e_state E29 "$KB")"
  assert_eq "AC4 E29 [${pair%%|*}]: no FAIL line" "0/graded" "$(fail_graded E29)"
done
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
bcase specmul "$SPEC_MUL" PASS "01-spec.md with direction and multipl"
bcase decx "$DEC_X" PASS "direction and the multiplication sign"
bcase decdivsign "$DEC_DIVSIGN" PASS "factor and the division sign"
bcase decdirdiv "$DEC_DIRDIV" PASS "direction and divid"
bcase deccommit "$DEC_COMMIT" PASS "a decisions.md committed after E29_BASE"
bcase decnoop "$DEC_NOOP" FAIL "a line with 0.045 but no multipl, divid or sign"
bcase decnokey "$DEC_NOKEY" FAIL "a line with multipl but no 0.045, factor or direction"
bcase root "$DEC_ROOT" FAIL "decisions.md at the repository root, not .agents/handoff"
bcase notes "$NOTES_MUL" FAIL "NOTES.md, not one of the two files"
assert_rc "AC4 E29 (b) the last log says nothing about the direction: exit 1" 1

echo "AC4 E29 (c): [UNVERIFIED] on a line about the factor or direction"
# ccase NAME REPLY EXPECT DESC: a multiply implementation, nothing logged, the reply REPLY
ccase() {
  e29 "c$1" "$IM_MUL" "$2"
  assert_eq "AC4 E29 (c) [$4]: [UNVERIFIED] labels $3" "$3" "$(e_state E29 "$KC")"; }
ccase reply 'The factor multiplies [UNVERIFIED] and toCrates(10) is 0.45.' PASS "reply line with factor"
ccase dir 'The direction is multiply [UNVERIFIED].' PASS "reply line with direction"
ccase mul 'toCrates multiplies the quantity [UNVERIFIED].' PASS "reply line with multipl"
ccase div 'toCrates divides the quantity [UNVERIFIED].' PASS "reply line with divid"
ccase num 'I read 0.045 as given [UNVERIFIED].' PASS "reply line with 0.045"
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

t_summary
