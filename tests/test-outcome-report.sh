#!/usr/bin/env bash
# Tests for evals/run-outcome.sh, flags, metrics and output (v0.27.0 lane O, spec .agents/handoff/01-spec.md slice S3,
# AC11-AC17): lane E's --model/--arm/--repeat/--max-cost, the pb-evals/1 JSON written by pbh_results_json (checks per run,
# pbh_stats summary, ERROR runs out of the denominators), the Oracle pass@1 / pass^K values, the markdown arm line and table,
# cost and time mean ± sd, and tools/eval-delta.sh reading the file. Reuses lane E's fake claude/codex/opencode ($FK) and
# stand-in HOME ($GH). Fixture tasks and stubs: tests/outcome-fixture.sh. Never calls a real harness.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-arms-fixture.sh"
. "$(dirname "$0")/outcome-fixture.sh"
HP='hidden tests pass'
near() { jget "$1" "(function(){const v=($2);return (typeof v===\"number\" && Math.abs(v-($3))<1e-6) ? \"ok\" : \"got \"+JSON.stringify(v)})()"; }
SI() { printf '((j.summary||[]).find(e => e.scenario==="%s" && e.arm==="%s" && e.key==="%s")||{})' "$1" "$2" "$3"; }
SC() { printf '((j.summary||[]).find(e => e.scenario==="%s" && e.arm==="%s" && ("cost_mean" in e))||{})' "$1" "$2"; }
mdsq() { { tr -s ' ' < "$RES"; } 2>/dev/null; }

echo "S3 Oracle AC11: --repeat 3, arm with; t-add PASS, PASS, FAIL; t-two PASS, PASS, PASS"
ro --cmd "bash $SA/oracle.sh" --tasks t-add,t-two --repeat 3
assert_rc "AC5 a FAIL among the runs -> exit 1" 1
assert_eq "AC11 runs t-add.with.3 FAIL, the others PASS" "PASS PASS FAIL PASS PASS PASS" \
  "$(for L in t-add.with.1 t-add.with.2 t-add.with.3 t-two.with.1 t-two.with.2 t-two.with.3; do printf '%s ' "$(chk "$L" "$HP")"; done | sed 's/ $//')"
assert_eq "Oracle t-add/with/'$HP': n 3, passes 2, pass_all false, complete true, errors 0" "3 2 false true 0" "$(sitem t-add with "$HP" n passes pass_all complete errors)"
assert_eq "Oracle t-add/with/'$HP': pass_at_1 = 2/3" "ok" "$(near "$JF" "$(SI t-add with "$HP").pass_at_1" '2/3')"
assert_eq "Oracle t-two/with/'$HP': n 3, passes 3, pass_at_1 1, pass_all true, complete true" "3 3 1 true true" "$(sitem t-two with "$HP" n passes pass_at_1 pass_all complete)"
assert_contains "Oracle md arm line" "$(cat "$RES" 2>/dev/null)" 'with: pass@1 0.83 (5/6 runs), pass^3 0.50 (1 of 2 complete tasks)'

echo "S3 AC12 ERROR runs are out of n, counted in errors, and their task leaves the pass^K share"
ro --cmd "bash $SA/errk2.sh" --tasks t-add,t-two --repeat 2
assert_rc "AC5 any ERROR -> exit 4" 4
assert_eq "AC12 t-add.with.2 is status error" '"error"' "$(rfield t-add.with.2 status)"
assert_eq "AC12 t-add/with/'$HP': n 1, passes 1, errors 1, complete false" "1 1 1 false" "$(sitem t-add with "$HP" n passes errors complete)"
assert_eq "AC12 t-two/with/'$HP': n 2, errors 0, complete true" "2 0 true" "$(sitem t-two with "$HP" n errors complete)"
assert_contains "AC12 md arm line: 3 graded runs, the incomplete task left out of pass^2" "$(cat "$RES" 2>/dev/null)" 'with: pass@1 1.00 (3/3 runs), pass^2 1.00 (1 of 1 complete tasks)'

echo "S3 AC11/AC17 checks and fields of a graded run (--cmd, --arm both, --model)"
ro --cmd "bash $SA/solve.sh" --tasks t-add --arm both --model m-out-1
assert_rc "AC5 solve, both arms -> exit 0" 0
for L in t-add.with.1 t-add.without.1; do
  assert_eq "AC11 $L: the checks hidden tests pass, FAIL_TO_PASS, PASS_TO_PASS, not seen = PASS" "PASS PASS PASS PASS" \
    "$(chk "$L" "$HP") $(chk "$L" 'FAIL_TO_PASS tests/add.f2p.sh') $(chk "$L" 'PASS_TO_PASS tests/mul.p2p.sh') $(chk "$L" 'hidden tests not seen by the agent')"
done
assert_eq "AC11/AC13 lane E's isolation check: in the without run only" "none yes" \
  "$(chk t-add.with.1 "$ISO") $(jget "$JF" "(((j.runs||[]).find(r=>r.label===\"t-add.without.1\")||{}).checks||[]).some(c=>c.name===\"$ISO\")?\"yes\":\"no\"")"
assert_eq "AC11 every check key equals its name (no run-specific group)" "true" \
  "$(jget "$JF" '(j.runs||[]).length===2 && (j.runs||[]).every(r=>(r.checks||[]).length>0 && (r.checks||[]).every(c=>c.key===c.name))')"
assert_eq "AC17 the line after 'results: <md>' is 'json: \${OUT%.md}.json'" "json: $JF" "$(printf '%s\n' "$OUT" | awk -v r="results: $RES" 'f { print; exit } $0 == r { f = 1 }')"
assert_eq "AC17 schema pb-evals/1, model m-out-1, arms [with,without], repeat 1" 'pb-evals/1 m-out-1 ["with","without"] 1' \
  "$(jget "$JF" 'j.schema+" "+j.model+" "+JSON.stringify(j.arms)+" "+j.repeat')"
assert_eq "AC17 scenario = the task id, status graded" '"t-add" "graded"' "$(rfield t-add.with.1 scenario) $(rfield t-add.with.1 status)"
assert_eq "AC17 fixture_tree = the tree of the setup repo (before the adapter), same in both arms" \
  "$(git -C "$FS/t-add" rev-parse 'HEAD^{tree}' 2>/dev/null)" "$(jget "$JF" '[...new Set((j.runs||[]).map(r=>r.fixture_tree))].join(" ")')"
assert_eq "AC17 prompt_sha = git hash-object of the .prompt file" "$(git hash-object "$WR/t-add.with.1.prompt" 2>/dev/null)" "$(jget "$JF" '[...new Set((j.runs||[]).map(r=>r.prompt_sha))].join(" ")')"
NOTES="$(jget "$JF" '(((j.runs||[])[0]||{}).notes||[]).join("|")')"
for n in language=bash source=oss:fixture expected_weight=Lite; do assert_contains "AC17 notes carry $n" "$NOTES" "$n"; done
assert_eq "AC17 the md task table header" "1" "$(mdsq | grep -cxF '| Task | Arm | pass@1 | pass^K | n | Cost mean ± sd | Time mean ± sd |')"
assert_eq "AC17 the md table has a row per (task, arm)" "1 1" "$(mdsq | grep -c '^| t-add | with |') $(mdsq | grep -c '^| t-add | without |')"
assert_contains "AC14 md: Model: m-out-1" "$(cat "$RES" 2>/dev/null)" "Model: m-out-1"
run bash "$PB_ROOT/tools/eval-delta.sh" "$JF"
assert_rc "AC17 tools/eval-delta.sh accepts the JSON of a pinned with+without run (exit 0)" 0
assert_eq "AC17 eval-delta row for '$HP'" "1" "$(printf '%s\n' "$OUT" | tr -s ' ' | grep -cxF "| t-add | $HP | 1.00 (1) | 1.00 (1) | 0.00 | non-discriminating |")"

echo "S3 AC13 --cmd adapters get PB_EVAL_ARM, PB_EVAL_MODEL and, in without, PB_EVAL_SETTINGS"
assert_contains "AC13 with run: PB_EVAL_ARM=with" "$(rec_of "$SR/t-add.with.1.env")" "PB_EVAL_ARM=with"
assert_contains "AC13 with run: PB_EVAL_MODEL=m-out-1" "$(rec_of "$SR/t-add.with.1.env")" "PB_EVAL_MODEL=m-out-1"
assert_contains "AC13 without run: PB_EVAL_ARM=without" "$(rec_of "$SR/t-add.without.1.env")" "PB_EVAL_ARM=without"
assert_contains "AC13 without run: the PB_EVAL_SETTINGS file excludes the user CLAUDE.md" "$(rec_of "$SR/t-add.without.1.settings")" "claudeMdExcludes"
assert_contains "AC13 without run: the settings set autoMemoryEnabled false" "$(rec_of "$SR/t-add.without.1.settings")" '"autoMemoryEnabled": false'

echo "S3 AC13/AC1 --harness claude (lane E's fake on PATH): preset, --model and --settings from pbh_*"
ro --harness claude --model m-out-2 --tasks t-add --arm both
assert_rc "AC13 the fake claude changes nothing -> FAIL -> exit 1" 1
assert_eq "AC1 the claude preset runs claude -p with stream-json" "yes" "$(has_line "$FR/claude.t-add.with.1.args" -p && argpair "$FR/claude.t-add.with.1.args" --output-format stream-json && echo yes || echo no)"
assert_eq "AC14 claude gets --model m-out-2 in both arms" "yes yes" \
  "$(argpair "$FR/claude.t-add.with.1.args" --model m-out-2 && echo yes || echo no) $(argpair "$FR/claude.t-add.without.1.args" --model m-out-2 && echo yes || echo no)"
assert_contains "AC13 the without run gets --settings with claudeMdExcludes" "$(rec_of "$FR/claude.t-add.without.1.settings")" "claudeMdExcludes"
assert_contains "AC13 the with run gets --settings with autoMemoryEnabled false" "$(rec_of "$FR/claude.t-add.with.1.settings")" '"autoMemoryEnabled": false'
assert_eq "AC13 claude gets no PB_EVAL_* variable" "" "$(rec_of "$FR/claude.t-add.without.1.env")"
assert_eq "AC13 the without run (clean stream-json) passes lane E's isolation check" "PASS" "$(chk t-add.without.1 "$ISO")"
assert_eq "AC11 the fake's runs are graded FAIL" "FAIL FAIL" "$(chk t-add.with.1 "$HP") $(chk t-add.without.1 "$HP")"

echo "S3 AC13 refusals: codex/opencode cannot run the without arm; a playbook block above the workroot"
for h in codex opencode; do
  ro --harness "$h" --model m-out-2 --tasks t-add --arm without
  assert_rc "AC13 --harness $h --arm without -> exit 2" 2
  assert_no_path "AC13 --harness $h --arm without: nothing run" "$WR/t-add.without.1"
done
P="$(mk_tmp)"; printf '%s\n' '# project notes' "$PB_BLOCK_BEGIN" 'rule' > "$P/CLAUDE.md"
rm -f "$SR"/*
run env -u PLAYBOOK_HOME HOME="$GH" PATH="$FK:$PATH" bash "$OUTCOME" --tasks-dir "$T" --tasks t-add --cmd "bash $SA/solve.sh" --arm without --workroot "$P/a/wr" --out "$(mk_tmp)/r.md"
assert_rc "AC13 a playbook block in an ancestor CLAUDE.md -> exit 2" 2
assert_eq "AC13 ancestor marker: the adapter did not run" "NO-RECORD" "$(rec_of "$SR/t-add.without.1.args")"

echo "S3 AC13 lane E's isolation check FAILs on a without run: exit 1, the md flags that task's arm invalid"
ro --cmd "bash $SA/skill.sh" --tasks t-add --arm both --model m-out-1
assert_rc "AC13 isolation FAIL -> exit 1" 1
assert_eq "AC13 the without run FAILs the isolation check, hidden tests still PASS" "FAIL PASS" "$(chk t-add.without.1 "$ISO") $(chk t-add.without.1 "$HP")"
assert_eq "AC13 the md flags t-add's without arm result as invalid" "1" "$(grep -i 'invalid' "$RES" 2>/dev/null | grep -F 't-add' | grep -c 'without')"

echo "S3 AC14 --model"
ro --harness claude --tasks t-add --arm both
assert_rc "AC14 --harness with --arm and no --model -> exit 2" 2
assert_no_path "AC14 no --model: nothing run" "$WR/t-add.with.1"
ro --cmd "bash $SA/solve.sh" --tasks t-add
assert_eq "AC14 --cmd without --model: JSON model null" "null" "$(jget "$JF" 'JSON.stringify(j.model)')"
assert_contains "AC14 --cmd without --model: md 'Model: not pinned (CLI default)'" "$(cat "$RES" 2>/dev/null)" "Model: not pinned (CLI default)"

echo "S3 AC15 cost per run from the transcript, whole seconds, mean ± sd, Total cost"
ro --cmd "bash $SA/cost.sh" --tasks t-add --repeat 2
assert_rc "AC15 cost stub -> exit 0" 0
assert_eq "AC15 cost_usd per run" "0.2 0.4" "$(jget "$JF" '(j.runs||[]).map(r=>r.cost_usd).join(" ")')"
assert_eq "AC15 seconds are whole numbers" "true" "$(jget "$JF" '(j.runs||[]).length===2 && (j.runs||[]).every(r=>Number.isInteger(r.seconds) && r.seconds>=0)')"
assert_eq "AC15 cost_mean 0.3, cost_sd sqrt(0.02)" "ok ok" "$(near "$JF" "$(SC t-add with).cost_mean" 0.3) $(near "$JF" "$(SC t-add with).cost_sd" 'Math.sqrt(0.02)')"
assert_eq "AC15 seconds_mean is a number" "number" "$(jget "$JF" "typeof $(SC t-add with).seconds_mean")"
ROW="$(mdsq | grep '^| t-add | with |' | head -n 1)"
assert_contains "AC15 the md row shows the cost mean ± sd" "$ROW" "0.3 ± 0.1414"
assert_contains "AC15 the md has run-evals' Total cost line" "$(grep '^Total cost' "$RES" 2>/dev/null)" "0.60"
ro --cmd "bash $SA/solve.sh" --tasks t-add
assert_eq "AC15 no cost in the transcript -> cost_usd null" "null" "$(rfield t-add.with.1 cost_usd)"

echo "S3 AC16 --max-cost skips runs; a skipped run does not change the exit code"
ro --cmd "bash $SA/cost06.sh" --tasks t-add,t-two --max-cost 1
assert_rc "AC16 a skipped run, the graded one PASS -> exit 0" 0
assert_eq "AC16 the output has '<label> SKIPPED ...' for the second task" "1" "$(printf '%s\n' "$OUT" | grep -c '^t-two\.with\.1 SKIPPED')"
assert_eq "AC16 JSON: t-two.with.1 status skipped, t-add.with.1 graded" '"skipped" "graded"' "$(rfield t-two.with.1 status) $(rfield t-add.with.1 status)"
assert_eq "AC16/AC12 t-two: skipped 1, never in n" "1" "$(jget "$JF" '((j.summary||[]).find(e=>e.scenario==="t-two"&&e.arm==="with")||{}).skipped')"
assert_eq "AC16 max_cost 1" "1" "$(jget "$JF" 'j.max_cost')"

t_summary
