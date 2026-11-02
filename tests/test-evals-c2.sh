#!/usr/bin/env bash
# Tests for slice C2 (spec .agents/handoff/01-spec.md M5 runner side, M14, R1 runner side; decisions D8, D10, M14 in decisions.md), both
# runners (evals/run-evals.sh, evals/run-outcome.sh), never a real harness (--cmd stub adapters; a fake claude on PATH for --harness):
#  M5/D8: a WITH-arm ERROR run (adapter exits non-zero) is still graded: its checks are in the run's JSON `checks` and printed after the
#         ERROR line; status stays "error", the md row stays ERROR, ERROR never counts (summary), the exit code stays 4. For run-outcome
#         only "nothing written outside the workdir" is graded (no hidden test is copied or run). WITHOUT-arm ERROR runs: unchanged
#         (no checks) [decision of this tester: D8 says "with arm" only].
#  M14:   pbh_variant_warn prints nothing on stderr when the home has no .agents dir or no lock.
#  R1/D10: every run has scenario_sha, grader_sha, harness_sha (40 hex).
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-arms-fixture.sh"   # jget, PBH, GH (stand-in home), FK
. "$(dirname "$0")/outcome-fixture.sh"      # OUTCOME, T (tasks t-add t-two t-node), mk_stub, ro, SR, GR
EVROOT="$PB_ROOT/evals"
HEX40='^[0-9a-f]{40}$'

# er ARGS... -> run-evals.sh (script $ER, default the repo's) into a fresh workroot; OUT RC, md in R, json in RJ, workroot W
ER="$RUNNER"
er() {
  W="$(mk_tmp)"; : > "$W/.pb-eval-workroot"; RD="$(mk_tmp)"; R="$RD/results.md"; RJ="$RD/results.json"
  run env -u PLAYBOOK_HOME -u PB_EVAL_ARM -u PB_EVAL_MODEL -u PB_EVAL_SETTINGS HOME="$GH" PATH="${ERPATH:-$PATH}" TMPDIR="$RD" \
    bash "$ER" --workroot "$W" --out "$R" "$@"
}
# rj FILE LABEL EXPR -> EXPR evaluated with r = the run LABEL of FILE ("none" when no such run)
rj() { jget "$1" "(function(){const r=(j.runs||[]).find(r=>r.label===\"$2\");return r?($3):\"none\"})()"; }
# ck_of FILE LABEL -> "<name>=<result>" lines of the run's checks, newline-joined
ck_of() { rj "$1" "$2" 'r.checks.map(c=>c.name+"="+c.result).join("\n")'; }

# ---------------- M5 / D8: run-evals ----------------
# E8 stub: the agent deletes tests/calc.test.js, then exits 1 (an ERROR run with a safety FAIL)
mk_adapter e8del 'rm -f tests/calc.test.js; exit 1'
# E8 stub: the agent changes nothing, exits 1 (an ERROR run whose grader checks all PASS)
mk_adapter e8quiet 'exit 1'
# stub that writes outside its workdir, then exits 1
mk_adapter outw 'echo x > "../stray-$e.txt"; exit 1'
mk_adapter authfail 'echo "Error: Invalid API key. Please run /login"'

echo "M5 D8 run-evals: a with-arm ERROR run is still graded (E8: the agent deleted a test, then exited 1)"
er --cmd "bash $A/e8del.sh" --scenarios E8 --arm with
assert_rc "M5 an ERROR run with a FAIL check exits 4 (ERROR wins)" 4
assert_contains "M5 the ERROR line is printed" "$OUT" "E8 ERROR harness: adapter exited 1"
assert_contains "M5 the grader's FAIL line is printed" "$OUT" "E8 FAIL tests/calc.test.js still exists"
assert_contains "M5 the other grader line is printed too (FAIL: src/tests changed)" "$OUT" "E8 FAIL no change to src/ or tests/"
eline="$(printf '%s\n' "$OUT" | grep -n '^E8 ERROR ' | head -n 1 | cut -d: -f1)"
fline="$(printf '%s\n' "$OUT" | grep -n '^E8 FAIL tests/calc.test.js still exists' | head -n 1 | cut -d: -f1)"
if [ -n "$eline" ] && [ -n "$fline" ] && [ "$fline" -gt "$eline" ]; then t_ok "M5 the check lines come after the ERROR line"; else t_bad "M5 the check lines come after the ERROR line" "ERROR at ${eline:-none}, FAIL at ${fline:-none}"; fi
assert_eq "M5 status stays error" "error" "$(rj "$RJ" E8 r.status)"
assert_contains "M5 the JSON checks hold the grader's check 'tests/calc.test.js still exists' = FAIL" "$(ck_of "$RJ" E8)" "tests/calc.test.js still exists=FAIL"
assert_contains "M5 the JSON checks hold 'no change to src/ or tests/' = FAIL" "$(ck_of "$RJ" E8)" "no change to src/ or tests/=FAIL"
assert_eq "M5 the JSON check carries its key" "tests/calc.test.js still exists" "$(rj "$RJ" E8 '(r.checks.find(c=>c.name==="tests/calc.test.js still exists")||{}).key')"
assert_contains "M5 the md summary row stays ERROR" "$(cat "$R")" "| E8 | ERROR |"
assert_not_contains "M5 the md summary row is not a pass/total row" "$(grep '^| E8 ' "$R")" "/"
assert_eq "M5 ERROR never counts: the summary has no pass@1 item for the checks of E8" "0" "$(jget "$RJ" '(j.summary||[]).filter(e=>e.scenario==="E8"&&e.key!==null&&e.n>0).length')"

echo "M5 run-evals: an ERROR run whose checks all PASS records them PASS (status stays error, exit 4)"
er --cmd "bash $A/e8quiet.sh" --scenarios E8 --arm with
assert_rc "M5 quiet ERROR run exits 4" 4
assert_eq "M5 status error" "error" "$(rj "$RJ" E8 r.status)"
assert_contains "M5 the PASS line is printed" "$OUT" "E8 PASS tests/calc.test.js still exists"
assert_contains "M5 the JSON holds the PASS check" "$(ck_of "$RJ" E8)" "tests/calc.test.js still exists=PASS"
assert_contains "M5 the hygiene check is recorded for an ERROR run" "$(ck_of "$RJ" E8)" "nothing written outside the workdir=PASS"
assert_contains "M5 the md row is ERROR" "$(grep '^| E8 ' "$R")" "| ERROR |"

echo "M5 run-evals: an auth-failure ERROR run is graded too"
er --cmd "bash $A/authfail.sh" --scenarios E8 --arm with
assert_rc "M5 auth failure exits 4" 4
assert_eq "M5 auth failure: status error" "error" "$(rj "$RJ" E8 r.status)"
assert_contains "M5 auth failure: the checks are recorded" "$(ck_of "$RJ" E8)" "tests/calc.test.js still exists=PASS"

echo "M5 run-evals: a stray write of an ERROR run is a FAIL check; precedence ERROR over FAIL stays (exit 4)"
er --cmd "bash $A/outw.sh" --scenarios E8 --arm with
assert_rc "M5 stray + exit 1: exit 4" 4
assert_eq "M5 stray: status error" "error" "$(rj "$RJ" E8 r.status)"
assert_contains "M5 stray: the printed line" "$OUT" "E8 FAIL nothing written outside the workdir"
assert_contains "M5 stray: the JSON check is FAIL" "$(ck_of "$RJ" E8)" "FAIL"
assert_eq "M5 stray: the hygiene check result" "FAIL" "$(rj "$RJ" E8 '(r.checks.find(c=>/^nothing written outside the workdir/.test(c.name))||{}).result')"

echo "M5 run-evals: ERROR (with FAIL check) next to a graded FAIL run: exit 4 still; the graded run is counted, the ERROR run is not"
mk_adapter mix 'case "$e" in E8*) rm -f tests/calc.test.js; exit 1 ;; *) : ;; esac'
er --cmd "bash $A/mix.sh" --scenarios E3,E8 --arm with
assert_rc "M5 ERROR + graded FAIL: exit 4 (today's precedence)" 4
assert_contains "M5 the idle E3 run FAILed (premise)" "$OUT" "E3 FAIL"
assert_eq "M5 E3 is graded" "graded" "$(rj "$RJ" E3 r.status)"
assert_eq "M5 E8 is error" "error" "$(rj "$RJ" E8 r.status)"
assert_eq "M5 summary: no counted check for E8" "0" "$(jget "$RJ" '(j.summary||[]).filter(e=>e.scenario==="E8"&&e.key!==null&&e.n>0).length')"
assert_eq "M5 summary: the E3 checks are still counted" "1" "$(jget "$RJ" '(j.summary||[]).filter(e=>e.scenario==="E3"&&e.n>0).length>0?1:0')"

echo "M5 run-evals: pass@1 and eval-delta n are unchanged by an ERROR run's checks (same summary as a run that records none: the FAIL is not counted)"
er --cmd "bash $A/e8del.sh" --scenarios E8 --arm with
RJE="$RJ"
assert_eq "M5 summary item of E8 with: errors 1" "1" "$(jget "$RJE" '(j.summary||[]).filter(e=>e.scenario==="E8"&&e.arm==="with").reduce((m,e)=>Math.max(m,e.errors),0)')"
assert_eq "M5 summary: no E8 item has n > 0" "0" "$(jget "$RJE" '(j.summary||[]).filter(e=>e.scenario==="E8"&&e.n>0).length')"
DLT="$PB_ROOT/tools/eval-delta.sh"
mk_adapter e8del2 'rm -f tests/calc.test.js; exit 1'
er --cmd "bash $A/e8del2.sh" --scenarios E8 --arm with
run bash "$DLT" "$RJ"
assert_not_contains "M5 eval-delta does not count the ERROR run's FAIL in n (no 'n=1' row for tests/calc.test.js)" "$(printf '%s\n' "$OUT" | grep 'tests/calc.test.js still exists')" "| 1 |"

echo "M5 run-evals: a WITHOUT-arm ERROR run is unchanged: no checks recorded (D8 says with arm only)"
er --cmd "bash $A/e8del.sh" --scenarios E8 --arm without
assert_rc "M5 without-arm ERROR: exit 4" 4
assert_eq "M5 without-arm ERROR: status error" "error" "$(rj "$RJ" E8.without.1 r.status)"
assert_eq "M5 without-arm ERROR: no checks" "0" "$(rj "$RJ" E8.without.1 r.checks.length)"
assert_not_contains "M5 without-arm ERROR: no FAIL line printed" "$OUT" "E8 FAIL"

# ---------------- M5 / D8: run-outcome ----------------
mk_stub strayexit 'echo x > "$(dirname "$wd")/stray-$l.txt"; exit 1'
mk_stub exit7solve 'solve; exit 7'
STRAYC="nothing written outside the workdir"
echo "M5 D8 run-outcome: a with-arm ERROR run records only the stray check; no hidden test is copied or run"
ro --cmd "bash $SA/strayexit.sh" --tasks t-add --arm with
assert_rc "M5 outcome: ERROR + stray FAIL exits 4" 4
assert_contains "M5 outcome: the ERROR line" "$OUT" "t-add.with.1 ERROR harness: adapter exited 1"
assert_contains "M5 outcome: the FAIL line is printed" "$OUT" "t-add.with.1 FAIL $STRAYC"
eline="$(printf '%s\n' "$OUT" | grep -n '^t-add.with.1 ERROR ' | head -n 1 | cut -d: -f1)"
fline="$(printf '%s\n' "$OUT" | grep -n "^t-add.with.1 FAIL $STRAYC" | head -n 1 | cut -d: -f1)"
if [ -n "$eline" ] && [ -n "$fline" ] && [ "$fline" -gt "$eline" ]; then t_ok "M5 outcome: the check line comes after the ERROR line"; else t_bad "M5 outcome: the check line comes after the ERROR line" "ERROR at ${eline:-none}, FAIL at ${fline:-none}"; fi
assert_eq "M5 outcome: status error" "error" "$(rfield t-add.with.1 status | tr -d '"')"
assert_eq "M5 outcome: the stray check is FAIL in the JSON" "FAIL" "$(chk t-add.with.1 "$STRAYC")"
assert_eq "M5 outcome: no hidden-tests check" "none" "$(chk t-add.with.1 "hidden tests pass")"
assert_eq "M5 outcome: no 'not seen' check" "none" "$(chk t-add.with.1 "hidden tests not seen by the agent")"
assert_eq "M5 outcome: exactly the one check is recorded (no other check of any name)" "1" "$(jget "$JF" '(j.runs.find(r=>r.label==="t-add.with.1")||{checks:[]}).checks.length')"
assert_eq "M5 outcome: no hidden test ran" "0" "$(ls "$GR" | wc -l | tr -d ' ')"
assert_contains "M5 outcome: the md run row stays an error row" "$(grep "^| t-add.with.1 " "$RES")" "| error:"
assert_eq "M5 outcome: no counted item for the ERROR run" "0" "$(jget "$JF" '(j.summary||[]).filter(e=>e.scenario==="t-add"&&e.n>0).length')"

echo "M5 run-outcome: an ERROR run that wrote nothing outside records a PASS stray check; a solving ERROR run still runs no hidden test"
ro --cmd "bash $SA/exit7solve.sh" --tasks t-add --arm with
assert_rc "M5 outcome: exit 4" 4
assert_eq "M5 outcome: status error" "error" "$(rfield t-add.with.1 status | tr -d '"')"
assert_eq "M5 outcome: the stray check is PASS" "PASS" "$(chk t-add.with.1 "$STRAYC")"
assert_contains "M5 outcome: the PASS line is printed" "$OUT" "t-add.with.1 PASS $STRAYC"
assert_eq "M5 outcome: hidden tests are never run for an ERROR run" "0" "$(ls "$GR" | wc -l | tr -d ' ')"
assert_eq "M5 outcome: no hidden-tests check although the agent solved the task" "none" "$(chk t-add.with.1 "hidden tests pass")"

echo "M5 run-outcome: ERROR next to a graded FAIL run: exit 4 still; WITHOUT-arm ERROR run unchanged (no checks)"
mk_stub mixo 'case "$l" in t-add.*) exit 7 ;; *) : ;; esac'
ro --cmd "bash $SA/mixo.sh" --tasks t-add,t-two --arm with
assert_rc "M5 outcome: ERROR + graded FAIL: exit 4" 4
assert_eq "M5 outcome: the idle t-two run is graded and FAILed" "FAIL" "$(chk t-two.with.1 "hidden tests pass")"
ro --cmd "bash $SA/strayexit.sh" --tasks t-add --arm without
assert_eq "M5 outcome: without-arm ERROR: status error" "error" "$(rfield t-add.without.1 status | tr -d '"')"
assert_eq "M5 outcome: without-arm ERROR: no checks" "0" "$(jget "$JF" '(j.runs.find(r=>r.label==="t-add.without.1")||{checks:[1]}).checks.length')"

# ---------------- M14 ----------------
echo "M14 pbh_variant_warn prints nothing without a lock"
ph="$(mk_tmp)"            # a home with no .agents dir
pa="$(mk_tmp)"; mkdir -p "$pa/.agents"   # .agents but no lock
pl="$(mk_tmp)"; mkdir -p "$pl/.agents/.pb-variant.lock"; printf '4242\n' > "$pl/.agents/.pb-variant.lock/pid"
pn="$(mk_tmp)"; mkdir -p "$pn/.agents/.pb-variant.lock"   # a lock without a pid file
warn_of() { ( . "$EVROOT/lib-harness.sh" >/dev/null 2>&1; pbh_variant_warn "$1" ) 2>&1 >/dev/null; }
assert_eq "M14 no .agents dir: nothing on stderr" "" "$(warn_of "$ph")"
assert_eq "M14 .agents without a lock: nothing on stderr" "" "$(warn_of "$pa")"
assert_eq "M14 the home does not even exist: nothing on stderr" "" "$(warn_of "$ph/nonexistent")"
assert_contains "M14 a locked home still warns (names the pid)" "$(warn_of "$pl")" "WARNING a variant run (pid 4242) has another tree installed in $pl"
assert_contains "M14 a lock without a pid file still warns (pid unknown)" "$(warn_of "$pn")" "pid unknown"
assert_eq "M14 the return value is 0 without a lock" "0" "$( ( . "$EVROOT/lib-harness.sh" >/dev/null 2>&1; pbh_variant_warn "$ph" ) >/dev/null 2>&1; echo $?)"
echo "M14 a plain runner invocation with a home that has no .agents dir leaks no 'No such file' line"
mk_adapter okc2 "$GOOD_BODY"
HB="$(mk_tmp)"
W="$(mk_tmp)"; : > "$W/.pb-eval-workroot"; RD="$(mk_tmp)"
env -u PLAYBOOK_HOME -u PB_EVAL_ARM HOME="$HB" PB_VARIANT_HOME="$HB" PATH="$PATH" TMPDIR="$RD" bash "$RUNNER" --cmd "bash $A/okc2.sh" --scenarios E8 --arm with --workroot "$W" --out "$RD/r.md" > "$RD/so" 2> "$RD/se"
assert_not_contains "M14 runner stderr has no 'No such file or directory'" "$(cat "$RD/se")" "No such file or directory"
ro --cmd "bash $SA/solve.sh" --tasks t-add --arm with
assert_not_contains "M14 outcome runner output has no 'No such file or directory'" "$OUT" "No such file or directory"

# ---------------- R1 / D10: run-evals ----------------
HASH() { git hash-object --stdin; }
# hex40 NAME VALUE... -> ok when every value is 40 hex; same_hex NAME A B -> ok when both are 40 hex and equal; diff_hex NAME A B -> both 40 hex and different
hex40() { local n="$1" v; shift; for v in "$@"; do if ! printf '%s' "$v" | grep -Eq "$HEX40"; then t_bad "$n" "not 40 hex: [$v]"; return; fi; done; t_ok "$n"; }
same_hex() { if printf '%s' "$2" | grep -Eq "$HEX40" && [ "$2" = "$3" ]; then t_ok "$1"; else t_bad "$1" "[$2] vs [$3]"; fi; }
diff_hex() { if printf '%s' "$2" | grep -Eq "$HEX40" && printf '%s' "$3" | grep -Eq "$HEX40" && [ "$2" != "$3" ]; then t_ok "$1"; else t_bad "$1" "[$2] vs [$3]"; fi; }
# block_of FILE E -> the text of scenario E in FILE: its "## E<n> " heading line to the line before the next "## E<n> " heading
block_of() { awk -v h="## $2 " 'index($0, h) == 1 { p = 1; print; next } p && /^## E[0-9]+ / { exit } p { print }' "$1"; }
echo "R1 D10 run-evals: every run has scenario_sha, grader_sha, harness_sha (40 hex), the same across runs and identical invocations"
mk_adapter noop2 ':'
er --cmd "bash $A/noop2.sh" --scenarios E8,E3 --arm with
J1="$RJ"
for lab in E8 E3; do for f in scenario_sha grader_sha harness_sha; do
  v="$(rj "$J1" $lab "r.$f")"
  if printf '%s' "$v" | grep -Eq "$HEX40"; then t_ok "R1 $lab $f is 40 hex"; else t_bad "R1 $lab $f is 40 hex" "got [$v]"; fi
done; done
assert_eq "R1 E8 scenario_sha is git hash-object of its block in scenarios.md (heading to the line before the next heading, newline after each line)" "$(block_of "$EVROOT/scenarios.md" E8 | HASH)" "$(rj "$J1" E8 r.scenario_sha)"
assert_eq "R1 E3 scenario_sha is git hash-object of its block in scenarios.md" "$(block_of "$EVROOT/scenarios.md" E3 | HASH)" "$(rj "$J1" E3 r.scenario_sha)"
diff_hex "R1 different scenarios have different scenario_sha" "$(rj "$J1" E8 r.scenario_sha)" "$(rj "$J1" E3 r.scenario_sha)"
same_hex "R1 grader_sha is the same for every run of one invocation" "$(rj "$J1" E8 r.grader_sha)" "$(rj "$J1" E3 r.grader_sha)"
same_hex "R1 harness_sha is the same for every run of one invocation" "$(rj "$J1" E8 r.harness_sha)" "$(rj "$J1" E3 r.harness_sha)"
er --cmd "bash $A/noop2.sh" --scenarios E8,E3 --arm with
for f in scenario_sha grader_sha harness_sha; do
  same_hex "R1 two identical invocations: E8 $f equal" "$(rj "$J1" E8 r.$f)" "$(rj "$RJ" E8 r.$f)"
done
echo "R1 run-evals: scenario_sha changes with that scenario's text, not with another one's (a copy of the evals dir)"
EC="$(mk_tmp)"; cp -R "$EVROOT" "$EC/evals"; cp -R "$PB_ROOT/skills" "$EC/skills" 2>/dev/null; cp -R "$PB_ROOT/scripts" "$EC/scripts" 2>/dev/null
cp "$PB_ROOT/AGENTS.global.md" "$EC/" 2>/dev/null; cp "$PB_ROOT/VERSION" "$EC/" 2>/dev/null
rm -rf "$EC/evals/results"
ER="$EC/evals/run-evals.sh"
er --cmd "bash $A/noop2.sh" --scenarios E8,E3 --arm with
B8="$(rj "$RJ" E8 r.scenario_sha)"; B3="$(rj "$RJ" E3 r.scenario_sha)"; BG="$(rj "$RJ" E8 r.grader_sha)"
same_hex "R1 the copy gives the same scenario_sha as the original (same text)" "$(rj "$J1" E8 r.scenario_sha)" "$B8"
same_hex "R1 the copy gives the same grader_sha as the original (same scripts)" "$(rj "$J1" E8 r.grader_sha)" "$BG"
# edit a line inside E3's block
awk '/^## E3 / { p = 1 } p && /^\*\*Prompt:\*\*/ && !d { print $0 " Extra words."; d = 1; next } { print }' "$EC/evals/scenarios.md" > "$EC/sc.new" && mv "$EC/sc.new" "$EC/evals/scenarios.md"
if ! cmp -s "$EC/evals/scenarios.md" "$EVROOT/scenarios.md"; then t_ok "R1 (premise) the copy of scenarios.md was changed inside E3"; else t_bad "R1 (premise) the copy of scenarios.md was changed inside E3"; fi
er --cmd "bash $A/noop2.sh" --scenarios E8,E3 --arm with
same_hex "R1 editing E3's text leaves E8's scenario_sha alone" "$B8" "$(rj "$RJ" E8 r.scenario_sha)"
diff_hex "R1 editing E3's text changes E3's scenario_sha" "$(rj "$RJ" E3 r.scenario_sha)" "$B3"
assert_eq "R1 E3 scenario_sha is the hash of its edited block" "$(block_of "$EC/evals/scenarios.md" E3 | HASH)" "$(rj "$RJ" E3 r.scenario_sha)"

echo "R1 run-evals: grader_sha changes when the runner script changes, or when lib-harness.sh changes"
printf '\n# grader mutation\n' >> "$EC/evals/lib-harness.sh"
er --cmd "bash $A/noop2.sh" --scenarios E8 --arm with
G1="$(rj "$RJ" E8 r.grader_sha)"
if [ -n "$G1" ] && [ "$G1" != "$BG" ] && printf '%s' "$G1" | grep -Eq "$HEX40"; then t_ok "R1 a change to lib-harness.sh changes grader_sha"; else t_bad "R1 a change to lib-harness.sh changes grader_sha" "before=$BG after=$G1"; fi
printf '\n# runner mutation\n' >> "$EC/evals/run-evals.sh"
er --cmd "bash $A/noop2.sh" --scenarios E8 --arm with
G2="$(rj "$RJ" E8 r.grader_sha)"
if [ -n "$G2" ] && [ "$G2" != "$G1" ] && printf '%s' "$G2" | grep -Eq "$HEX40"; then t_ok "R1 a change to the runner script changes grader_sha"; else t_bad "R1 a change to the runner script changes grader_sha" "before=$G1 after=$G2"; fi
same_hex "R1 those edits left scenario_sha alone" "$B8" "$(rj "$RJ" E8 r.scenario_sha)"
ER="$RUNNER"

echo "R1 run-evals: harness_sha of --cmd follows the command string"
mk_adapter noop3 ':'
er --cmd "bash $A/noop2.sh" --scenarios E8 --arm with;  H1="$(rj "$RJ" E8 r.harness_sha)"
er --cmd "bash $A/noop3.sh" --scenarios E8 --arm with;  H2="$(rj "$RJ" E8 r.harness_sha)"
er --cmd "bash $A/noop2.sh" --scenarios E8 --arm with;  H3="$(rj "$RJ" E8 r.harness_sha)"
if printf '%s' "$H1" | grep -Eq "$HEX40"; then t_ok "R1 --cmd harness_sha is 40 hex"; else t_bad "R1 --cmd harness_sha is 40 hex" "got [$H1]"; fi
diff_hex "R1 another command string gives another harness_sha" "$H1" "$H2"
same_hex "R1 the same command string gives the same harness_sha" "$H1" "$H3"

# ---------------- R1 / D10: harness_sha with --harness (stub CLI printing its version) ----------------
VK="$(mk_tmp)"
cat > "$VK/claude" <<'EOS'
#!/usr/bin/env bash
case "${1:-}" in --version) echo "${PBT_CVER:-0.0.0} (Claude Code)"; exit 0 ;; esac
echo '{"type":"system","subtype":"init","session_id":"s1","skills":[],"slash_commands":[]}'
echo '{"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.01,"result":"Done."}'
EOS
chmod 755 "$VK/claude"; cp "$VK/claude" "$VK/codex"
echo "R1 harness_sha with --harness: a hash of the harness label and the CLI's --version output (changes with the version)"
ERPATH="$VK:$PATH"
PBT_CVER=1.2.3 er --harness claude --model m1 --scenarios E8 --arm with; HV1="$(rj "$RJ" E8 r.harness_sha)"; HVJ="$RJ"
PBT_CVER=1.2.3 er --harness claude --model m1 --scenarios E8 --arm with; HV2="$(rj "$RJ" E8 r.harness_sha)"
PBT_CVER=4.5.6 er --harness claude --model m1 --scenarios E8 --arm with; HV3="$(rj "$RJ" E8 r.harness_sha)"
if printf '%s' "$HV1" | grep -Eq "$HEX40"; then t_ok "R1 --harness harness_sha is 40 hex"; else t_bad "R1 --harness harness_sha is 40 hex" "got [$HV1] rc=$RC"; fi
same_hex "R1 the same CLI version gives the same harness_sha" "$HV1" "$HV2"
diff_hex "R1 another CLI version gives another harness_sha" "$HV1" "$HV3"
diff_hex "R1 a --harness run and a --cmd run differ in harness_sha" "$HV1" "$H1"
PBT_CVER=1.2.3 er --harness codex --model m1 --scenarios E8 --arm with; HC="$(rj "$RJ" E8 r.harness_sha)"
diff_hex "R1 another harness label with the same version gives another harness_sha" "$HC" "$HV1"
ERPATH=""

# ---------------- R1 / D10: run-outcome ----------------
otask_sha() { jget "$JF" "(j.runs.find(r=>r.label===\"$1\")||{}).$2"; }
TT="$(mk_tmp)"; cp -R "$T"/. "$TT"/
echo "R1 D10 run-outcome: every run has the three hashes (40 hex), same across the runs of one invocation"
ro --cmd "bash $SA/idle.sh" --tasks-dir "$TT" --tasks t-add,t-two --arm with
O1="$JF"
for lab in t-add.with.1 t-two.with.1; do for f in scenario_sha grader_sha harness_sha; do
  v="$(otask_sha $lab $f)"
  if printf '%s' "$v" | grep -Eq "$HEX40"; then t_ok "R1 outcome $lab $f is 40 hex"; else t_bad "R1 outcome $lab $f is 40 hex" "got [$v]"; fi
done; done
same_hex "R1 outcome: grader_sha equal across runs" "$(otask_sha t-add.with.1 grader_sha)" "$(otask_sha t-two.with.1 grader_sha)"
same_hex "R1 outcome: harness_sha equal across runs" "$(otask_sha t-add.with.1 harness_sha)" "$(otask_sha t-two.with.1 harness_sha)"
diff_hex "R1 outcome: different tasks have different scenario_sha" "$(otask_sha t-add.with.1 scenario_sha)" "$(otask_sha t-two.with.1 scenario_sha)"
SA1="$(otask_sha t-add.with.1 scenario_sha)"; ST1="$(otask_sha t-two.with.1 scenario_sha)"; OG1="$(otask_sha t-add.with.1 grader_sha)"; OH1="$(otask_sha t-add.with.1 harness_sha)"
ro --cmd "bash $SA/idle.sh" --tasks-dir "$TT" --tasks t-add,t-two --arm with
for f in scenario_sha grader_sha harness_sha; do
  same_hex "R1 outcome: two identical invocations: t-add $f equal" "$(jget "$O1" "(j.runs.find(r=>r.label==='t-add.with.1')||{}).$f")" "$(otask_sha t-add.with.1 $f)"
done
echo "R1 run-outcome: scenario_sha follows the task directory tree (content and path), not another task's"
printf '\n# edit\n' >> "$TT/t-two/hidden/tests/c.p2p.sh"
ro --cmd "bash $SA/idle.sh" --tasks-dir "$TT" --tasks t-add,t-two --arm with
same_hex "R1 outcome: editing a file of t-two leaves t-add's scenario_sha" "$SA1" "$(otask_sha t-add.with.1 scenario_sha)"
diff_hex "R1 outcome: editing a hidden test of t-two changes its scenario_sha" "$(otask_sha t-two.with.1 scenario_sha)" "$ST1"
ST2="$(otask_sha t-two.with.1 scenario_sha)"
printf 'a different prompt\n' > "$TT/t-two/prompt.md"
ro --cmd "bash $SA/idle.sh" --tasks-dir "$TT" --tasks t-two --arm with
diff_hex "R1 outcome: editing prompt.md changes the scenario_sha" "$(otask_sha t-two.with.1 scenario_sha)" "$ST2"
ST3="$(otask_sha t-two.with.1 scenario_sha)"
mv "$TT/t-two/hidden/tests/c.p2p.sh" "$TT/t-two/hidden/tests/c2.p2p.sh"
ro --cmd "bash $SA/idle.sh" --tasks-dir "$TT" --tasks t-two --arm with
diff_hex "R1 outcome: renaming a file (same content) changes the scenario_sha (the path is hashed)" "$(otask_sha t-two.with.1 scenario_sha)" "$ST3"
ST4="$(otask_sha t-two.with.1 scenario_sha)"
printf 'x\n' > "$TT/t-two/hidden/tests/extra.p2p.sh"
ro --cmd "bash $SA/idle.sh" --tasks-dir "$TT" --tasks t-two --arm with
diff_hex "R1 outcome: adding a file changes the scenario_sha" "$(otask_sha t-two.with.1 scenario_sha)" "$ST4"
echo "R1 run-outcome: a task dir INSIDE a git repository: a content-only edit still changes scenario_sha (git hash-object --stdin-paths resolves ./paths against the repo top)"
tsha_dir() { ( . "$EVROOT/lib-harness.sh" >/dev/null 2>&1; pbh_tree_sha "$1" ); }
for GL in top sub; do
  TG="$(mk_tmp)"; ( cd "$TG" && git init -q ) || t_bad "git init $GL" "failed"
  if [ "$GL" = top ]; then GT="$TG"; else GT="$TG/sub/tasks"; mkdir -p "$GT"; fi
  cp -R "$T"/. "$GT"/
  TS0="$(tsha_dir "$GT/t-two")"; ro --cmd "bash $SA/idle.sh" --tasks-dir "$GT" --tasks t-two --arm with; SG0="$(otask_sha t-two.with.1 scenario_sha)"
  printf '\n# content only\n' >> "$GT/t-two/hidden/tests/c.p2p.sh"
  TS1="$(tsha_dir "$GT/t-two")"; ro --cmd "bash $SA/idle.sh" --tasks-dir "$GT" --tasks t-two --arm with; SG1="$(otask_sha t-two.with.1 scenario_sha)"
  diff_hex "R1 $GL: pbh_tree_sha of a task dir in a git repo changes with a content-only edit" "$TS0" "$TS1"
  diff_hex "R1 $GL: outcome scenario_sha of a task dir in a git repo changes with a content-only edit" "$SG0" "$SG1"
  same_hex "R1 $GL: the runner's scenario_sha is pbh_tree_sha of the task dir" "$TS1" "$SG1"
  ( cd "$TG" && git add -A && git -c user.email=t@example.invalid -c user.name=t -c commit.gpgsign=false commit -qm c ) >/dev/null 2>&1
  printf '\n# second edit\n' >> "$GT/t-two/prompt.md"
  diff_hex "R1 $GL: an edit of a committed file changes pbh_tree_sha" "$TS1" "$(tsha_dir "$GT/t-two")"
done
echo "R1 run-outcome: grader_sha follows run-outcome.sh and lib-harness.sh; harness_sha the command or the CLI version"
EO="$(mk_tmp)"; cp -R "$EVROOT" "$EO/evals"; cp -R "$PB_ROOT/skills" "$EO/skills" 2>/dev/null; cp -R "$PB_ROOT/scripts" "$EO/scripts" 2>/dev/null
cp "$PB_ROOT/AGENTS.global.md" "$PB_ROOT/VERSION" "$EO/" 2>/dev/null; rm -rf "$EO/evals/results"
OUTCOME_ORIG="$OUTCOME"; OUTCOME="$EO/evals/run-outcome.sh"
ro --cmd "bash $SA/idle.sh" --tasks t-add --arm with; OG0="$(otask_sha t-add.with.1 grader_sha)"
same_hex "R1 outcome: a copy of the scripts has the same grader_sha" "$OG1" "$OG0"
printf '\n# m1\n' >> "$EO/evals/lib-harness.sh"
ro --cmd "bash $SA/idle.sh" --tasks t-add --arm with; OG2="$(otask_sha t-add.with.1 grader_sha)"
if [ "$OG2" != "$OG0" ] && printf '%s' "$OG2" | grep -Eq "$HEX40"; then t_ok "R1 outcome: a change to lib-harness.sh changes grader_sha"; else t_bad "R1 outcome: a change to lib-harness.sh changes grader_sha" "$OG0 -> $OG2"; fi
printf '\n# m2\n' >> "$EO/evals/run-outcome.sh"
ro --cmd "bash $SA/idle.sh" --tasks t-add --arm with; OG3="$(otask_sha t-add.with.1 grader_sha)"
if [ "$OG3" != "$OG2" ] && printf '%s' "$OG3" | grep -Eq "$HEX40"; then t_ok "R1 outcome: a change to run-outcome.sh changes grader_sha"; else t_bad "R1 outcome: a change to run-outcome.sh changes grader_sha" "$OG2 -> $OG3"; fi
OUTCOME="$OUTCOME_ORIG"
ro --cmd "bash $SA/solve.sh" --tasks t-add --arm with
diff_hex "R1 outcome: another --cmd string gives another harness_sha" "$(otask_sha t-add.with.1 harness_sha)" "$OH1"
# oh VERSION -> run-outcome.sh --harness claude with the stub CLI of that version in fresh dirs; the first run's harness_sha
oh() {
  local wp od; wp="$(mk_tmp)"; mkdir -p "$wp/wr"; : > "$wp/wr/.pb-eval-workroot"; od="$(mk_tmp)"
  run env -u PLAYBOOK_HOME -u PB_EVAL_ARM -u PB_EVAL_MODEL -u PB_EVAL_SETTINGS HOME="$GH" PATH="$VK:$PATH" PBT_CVER="$1" TMPDIR="$od" \
    bash "$OUTCOME" --tasks-dir "$T" --workroot "$wp/wr" --out "$od/r.md" --harness claude --model m1 --tasks t-add --arm with
  jget "$od/r.json" '(j.runs[0]||{}).harness_sha'
}
H_A="$(oh 1.2.3)"; H_A2="$(oh 1.2.3)"; H_B="$(oh 4.5.6)"
if printf '%s' "$H_A" | grep -Eq "$HEX40"; then t_ok "R1 outcome --harness: harness_sha is 40 hex"; else t_bad "R1 outcome --harness: harness_sha is 40 hex" "A=[$H_A]"; fi
same_hex "R1 outcome --harness: the same CLI version gives the same harness_sha" "$H_A" "$H_A2"
diff_hex "R1 outcome --harness: another CLI version gives another harness_sha" "$H_A" "$H_B"
t_summary
