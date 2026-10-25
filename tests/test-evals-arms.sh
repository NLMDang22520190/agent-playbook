#!/usr/bin/env bash
# Tests for evals/run-evals.sh --model, --arm and --repeat (v0.26.0 lane E, spec .agents/handoff/01-spec.md slices S1 and S2):
# option checks, model pinning and recording, run labels <E>.<arm>.<k>, run order, naming, the E20 home per label, the budget
# and the exit code across runs. Never calls a real harness: --cmd fake adapters (evals-fixture.sh) and fake
# claude/codex/opencode binaries first on PATH (evals-arms-fixture.sh); HOME is a stand-in.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-arms-fixture.sh"

# no_label_dirs NAME -> no entry of the workroot WR is a scenario dir (E8, E8.with.1, ...)
no_label_dirs() { local l="" p; for p in "$WR"/E[0-9]*; do if [ -e "$p" ]; then l="$l${p##*/} "; fi; done; assert_eq "$1" "" "$l"; }

# ================= S1 options and model =================
echo "S1 AC1.1 --model, --arm and --repeat each need a value"
for opt in --model --arm --repeat; do
  go --cmd "bash $A/idle.sh" --scenarios E8 "$opt"
  assert_rc "AC1.1 $opt without a value -> exit 2" 2
  assert_contains "AC1.1 $opt without a value says '$opt needs a value'" "$OUT" "$opt needs a value"
  no_label_dirs "AC1.1 $opt without a value: no workdir is made"
done

echo "S1 AC1.1 invalid values exit 2 naming the option and the value, before any workdir"
bad() { # OPT VALUE
  go --cmd "bash $A/idle.sh" --scenarios E8 "$1" "$2"
  assert_rc "AC1.1 $1 [$2] -> exit 2" 2
  assert_not_contains "AC1.1 $1 [$2] is a known option (not 'unknown option')" "$OUT" "unknown option"
  assert_contains "AC1.1 $1 [$2]: the message names the option" "$OUT" "$1"
  assert_contains "AC1.1 $1 [$2]: the message names the value" "$OUT" "$2"
  no_label_dirs "AC1.1 $1 [$2]: no workdir is made"
}
bad --arm sideways
bad --arm WITH
bad --repeat 0
bad --repeat 100
bad --repeat abc
bad --repeat 1.5
bad --repeat -1
bad --model 'bad model'
bad --model 'a;b'
go --cmd "bash $A/idle.sh" --scenarios E8 --model 'a
b'
assert_rc "AC1.1 --model with a newline -> exit 2" 2
assert_not_contains "AC1.1 --model with a newline is a known option" "$OUT" "unknown option"

echo "S1 AC1.1 valid values run (model with . _ : / @ -, --arm with, --repeat 1)"
go --cmd "bash $A/idle.sh" --scenarios E8 --model 'claude-opus-4.5@2026/x:y_z' --arm with --repeat 1
assert_rc "AC1.1 valid --model/--arm/--repeat values -> exit 0" 0
assert_eq "AC1.1 the scenario ran and was graded" "PASS" "$(e_state E8 'tests/calc.test.js still exists')"
# the same run serves AC2.1: --arm with and --repeat 1 keep today's names
echo "S2 AC2.1 --arm with --repeat 1 keeps every name and output line as today"
assert_dir "AC2.1 workdir is <workroot>/E8" "$WR/E8"
assert_file "AC2.1 transcript is <workroot>/E8.log" "$WR/E8.log"
assert_file "AC2.1 prompt is <workroot>/E8.prompt" "$WR/E8.prompt"
assert_no_path "AC2.1 no labelled workdir E8.with.1" "$WR/E8.with.1"
assert_eq "AC2.1 no output line starts with a label" "0" "$(printf '%s\n' "$OUT" | grep -c '^E8\.with\.')"
assert_contains "AC2.1 the summary row is | E8 |" "$(row_of "$RES" E8)" "| E8 |"
echo "S1 AC1.5 the md records the model, and Arms/Repeat when given"
assert_eq "AC1.5 the line after Workroot: is Model: M" "Model: claude-opus-4.5@2026/x:y_z" "$(after_workroot "$RES")"
assert_eq "AC1.5 --arm given: the md has the line 'Arms: with'" "1" "$(grep -cx 'Arms: with' "$RES" 2>/dev/null || true)"
assert_eq "AC1.5 --repeat given: the md has the line 'Repeat: 1'" "1" "$(grep -cx 'Repeat: 1' "$RES" 2>/dev/null || true)"

echo "S1 AC1.2 a real harness with --arm or --repeat needs --model (no harness process starts)"
M12='--model is required for a real harness run with --arm or --repeat'
go --harness claude --arm with --scenarios E8
assert_rc "AC1.2 --harness claude --arm with, no --model -> exit 2" 2
assert_contains "AC1.2 --harness claude --arm with: the message" "$OUT" "$M12"
assert_no_path "AC1.2 the fake claude never ran" "$FR/claude.E8.args"
no_label_dirs "AC1.2 claude: no workdir is made"
go --harness codex --repeat 2 --scenarios E8
assert_rc "AC1.2 --harness codex --repeat 2, no --model -> exit 2" 2
assert_contains "AC1.2 --harness codex --repeat 2: the message" "$OUT" "$M12"
go --harness opencode --arm with --repeat 1 --scenarios E8
assert_rc "AC1.2 --harness opencode --arm with --repeat 1, no --model -> exit 2" 2
assert_contains "AC1.2 --harness opencode: the message" "$OUT" "$M12"

echo "S1 AC1.3 today's --harness command (no --arm/--repeat/--model) runs as before and warns once on stderr"
W13='WARNING model not pinned (--model missing): the results say "CLI default"; tools/eval-delta.sh will not use them'
go_split --harness claude --scenarios E8
assert_rc "AC1.3 --harness claude without --model -> exit 0 as today" 0
assert_eq "AC1.3 stderr has the WARNING line once" "1" "$(printf '%s\n' "$ERR" | grep -cxF -- "$W13")"
assert_not_contains "AC1.3 the WARNING is not on stdout" "$OUT" "WARNING model not pinned"
assert_file "AC1.3 the claude preset still ran" "$FR/claude.E8.args"
assert_eq "AC1.4 no --model: the claude argv is today's (5 arguments)" "5" "$(cat "$FR/claude.E8.argc" 2>/dev/null)"
if has_line "$FR/claude.E8.args" --model; then t_bad "AC1.4 no --model: claude gets no --model" "$(tr '\n' ' ' < "$FR/claude.E8.args")"; else t_ok "AC1.4 no --model: claude gets no --model"; fi
assert_eq "AC1.5 no --model: the line after Workroot: is 'Model: not pinned (CLI default)'" "Model: not pinned (CLI default)" "$(after_workroot "$RES")"
assert_eq "AC1.5 default mode: no Arms: line" "0" "$(grep -c '^Arms:' "$RES" 2>/dev/null || true)"
assert_eq "AC1.5 default mode: no Repeat: line" "0" "$(grep -c '^Repeat:' "$RES" 2>/dev/null || true)"

echo "S1 AC1.4 --model reaches the harness: claude --model M, codex -m M, opencode --model M (D7); presets get no PB_EVAL_*"
go_split --harness claude --model m-claude-1 --scenarios E8
assert_rc "AC1.4 --harness claude --model M -> exit 0" 0
if argpair "$FR/claude.E8.args" --model m-claude-1; then t_ok "AC1.4 claude gets --model M"; else t_bad "AC1.4 claude gets --model M" "argv: $(tr '\n' ' ' < "$FR/claude.E8.args" 2>/dev/null)"; fi
assert_file "AC1.4 claude: the env record exists" "$FR/claude.E8.env"
assert_eq "AC1.4 the claude process has no PB_EVAL_* variable" "" "$(rec_of "$FR/claude.E8.env")"
assert_not_contains "AC1.3 --model given: no WARNING" "$ERR" "WARNING model not pinned"
assert_eq "AC1.5 the line after Workroot: is 'Model: m-claude-1'" "Model: m-claude-1" "$(after_workroot "$RES")"
go --harness codex --model m-codex-1 --scenarios E8
if argpair "$FR/codex.E8.args" -m m-codex-1; then t_ok "AC1.4 codex gets -m M"; else t_bad "AC1.4 codex gets -m M" "argv: $(tr '\n' ' ' < "$FR/codex.E8.args" 2>/dev/null)"; fi
assert_contains "AC1.4 codex: still runs codex exec" "$(head -n 1 "$FR/codex.E8.args" 2>/dev/null)" "exec"
assert_eq "AC1.4 the codex process has no PB_EVAL_* variable" "" "$(rec_of "$FR/codex.E8.env")"
go --harness opencode --model prov/m-oc-1 --scenarios E8
if argpair "$FR/opencode.E8.args" --model prov/m-oc-1; then t_ok "AC1.4 D7 [UNVERIFIED flag] opencode gets --model M"; else t_bad "AC1.4 D7 [UNVERIFIED flag] opencode gets --model M" "argv: $(tr '\n' ' ' < "$FR/opencode.E8.args" 2>/dev/null)"; fi

echo "S1 AC1.4 --cmd adapters (only) get PB_EVAL_MODEL"
mk_adapter envrec 'env | grep "^PB_EVAL_" | LC_ALL=C sort > "$REC/$e.pbenv"; true'
go --cmd "bash $A/envrec.sh" --model m-cmd-1 --scenarios E8
assert_contains "AC1.4 the --cmd adapter gets PB_EVAL_MODEL=M" "$(cat "$REC/E8.pbenv" 2>/dev/null)" "PB_EVAL_MODEL=m-cmd-1"
# guard (passes today too, kept so an implementation that always exports an empty PB_EVAL_MODEL is caught): no --model, no PB_EVAL_MODEL
go --cmd "bash $A/envrec.sh" --scenarios E8
assert_file "AC1.4 no --model: the --cmd adapter ran" "$REC/E8.pbenv"
assert_not_contains "AC1.4 no --model: the --cmd adapter gets no PB_EVAL_MODEL" "$(cat "$REC/E8.pbenv" 2>/dev/null)" "PB_EVAL_MODEL"

# ================= S2 repeats, arms, naming, budget =================
echo "S2 AC2.2/AC2.3 --arm both --repeat 2: labels <E>.<arm>.<k>, order scenario -> k -> arm, fresh fixtures, same prompt"
mk_adapter ord 'printf "%s\n" "$e" >> "$REC/order"
git -C "$wd" status --porcelain | wc -l | tr -d " " > "$REC/$e.dirty"
mkdir -p .agents/handoff && printf "x\t1\n" > .agents/handoff/cost.tsv
echo leftover > leftover.txt'
go --cmd "bash $A/ord.sh" --arm both --repeat 2 --scenarios E1,E8
LABELS="E1.with.1 E1.without.1 E1.with.2 E1.without.2 E8.with.1 E8.without.1 E8.with.2 E8.without.2"
assert_eq "AC2.3 run order: per scenario, then k, then arm (with before without)" "$LABELS" "$(tr '\n' ' ' < "$REC/order" 2>/dev/null | sed 's/ $//')"
assert_rc "AC2.6 E1 FAILs with an idle adapter in both arms -> exit 1" 1
for L in $LABELS; do
  assert_dir "AC2.2 $L: workdir <workroot>/$L" "$WR/$L"
  assert_file "AC2.2 $L: transcript <workroot>/$L.log" "$WR/$L.log"
  assert_file "AC2.2 $L: prompt <workroot>/$L.prompt" "$WR/$L.prompt"
  assert_dir "AC2.2 $L: evidence \${OUT%.md}.$L.evidence" "$OD/results.$L.evidence"
  assert_eq "AC2.3 $L: a fresh fixture (clean tree when the adapter starts)" "0" "$(cat "$REC/$L.dirty" 2>/dev/null)"
  assert_contains "AC2.2 $L: the md summary has a row for the label" "$(row_of "$RES" "$L")" "| $L |"
  assert_eq "AC2.2 $L: the stray-file check passes with labelled names" "PASS" "$(e_state "$L" 'nothing written outside the workdir')"
done
for L in E8.with.1 E8.without.1 E8.with.2 E8.without.2; do
  if line_has "$L" PASS "tests/calc.test.js still exists"; then t_ok "AC2.2 output line '$L PASS tests/calc.test.js still exists'"; else t_bad "AC2.2 output line '$L PASS tests/calc.test.js still exists'" "$(printf '%s\n' "$OUT" | grep '^E8' | head -n 4)"; fi
done
assert_eq "AC2.2 no output line starts with the bare scenario E8" "0" "$(printf '%s\n' "$OUT" | grep -c '^E8 ')"
assert_eq "AC2.2 no output line starts with the bare scenario E1" "0" "$(printf '%s\n' "$OUT" | grep -c '^E1 ')"
assert_no_path "AC2.2 no unlabelled workdir <workroot>/E8" "$WR/E8"
if [ -f "$WR/E8.with.1.prompt" ] && cmp -s "$WR/E8.with.1.prompt" "$WR/E8.without.1.prompt" && cmp -s "$WR/E8.with.1.prompt" "$WR/E8.without.2.prompt"; then
  t_ok "AC2.3 the prompt files of both arms and repeats are byte-equal"
else t_bad "AC2.3 the prompt files of both arms and repeats are byte-equal" "E8.with.1.prompt vs E8.without.1/.2"; fi

echo "S2 AC2.2 --repeat 2 alone labels the with arm: E8.with.1, E8.with.2"
go --cmd "bash $A/ord.sh" --repeat 2 --scenarios E8
assert_eq "AC2.2 --repeat 2 alone: two with runs" "E8.with.1 E8.with.2" "$(tr '\n' ' ' < "$REC/order" 2>/dev/null | sed 's/ $//')"
assert_rc "AC2.6 --repeat 2 alone, all checks pass -> exit 0" 0

echo "S2 AC2.4 E20 gets <workroot>/<label>.home; the E20 grader and the stray-file check read that name"
mk_adapter e20 'printf "%s\n" "${PLAYBOOK_HOME-UNSET}" > "$REC/$e.ph"
bash "'"$PB_ROOT"'/scripts/feedback.sh" capture --skill playbook-tdd --kind bug --source failure --harness other --summary "role-gate misfire $e" --observed "the tester gate fails on tests/" --expected "tests/ is a test path" --evidence "test_path_regex=^spec/" --proposal "fix the regex" --eval E20 >/dev/null 2>&1
true'
go --cmd "bash $A/e20.sh" --repeat 2 --scenarios E20
WRP="$(physdir "$WR")"
for k in 1 2; do
  L="E20.with.$k"
  assert_eq "AC2.4 $L: PLAYBOOK_HOME is <workroot>/$L.home" "$WRP/$L.home" "$(cat "$REC/$L.ph" 2>/dev/null)"
  assert_eq "AC2.4 $L: the E20 grader finds the feedback item in <workroot>/$L.home" "PASS" "$(e_state "$L" 'a feedback item was written')"
  assert_eq "AC2.4 $L: <workroot>/$L.home is not a stray write" "PASS" "$(e_state "$L" 'nothing written outside the workdir')"
done
assert_no_path "AC2.4 no unlabelled E20.home" "$WR/E20.home"

echo "S2 AC2.4 the ownership rule applies to every label before anything is deleted"
WR="$(mk_tmp)"; printf 'keep\n' > "$WR/keep.txt"; mkdir -p "$WR/E8.with.1"; printf 'mine\n' > "$WR/E8.with.1/mine.txt"
rm -f "$REC"/*
run env -u PLAYBOOK_HOME HOME="$GH" bash "$RUNNER" --cmd "bash $A/idle.sh" --arm both --scenarios E8 --workroot "$WR" --out "$WR/r.md"
assert_rc "AC2.4 a foreign <workroot>/E8.with.1 in a workroot the runner does not own -> exit 2" 2
assert_contains "AC2.4 the refusal names the labelled dir" "$OUT" "refusing to delete $(physdir "$WR")/E8.with.1"
assert_file "AC2.4 the foreign dir's file is kept" "$WR/E8.with.1/mine.txt"
assert_no_path "AC2.4 no run started (no E8.without.1)" "$WR/E8.without.1"

echo "S2 AC2.5 --max-cost spans all runs of the invocation (arms and repeats)"
mk_adapter c06 "echo '$INIT'
echo '{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"total_cost_usd\":0.6,\"result\":\"Done.\"}'"
go --cmd "bash $A/c06.sh" --arm both --max-cost 1 --scenarios E8
assert_contains "AC2.5 the with run reports its cost under its label" "$OUT" "E8.with.1 COST 0.6"
assert_contains "AC2.5 the without run is skipped by the estimate rule" "$OUT" "E8.without.1 SKIPPED budget: spent 0.6 + estimate 0.6 >= cap 1"
assert_eq "AC2.5 the skipped run has the summary row | E8.without.1 | SKIPPED | - | - |" "| E8.without.1 | SKIPPED | - | - |" "$(row_of "$RES" E8.without.1)"
assert_no_path "AC2.5 the skipped run made no workdir" "$WR/E8.without.1"
assert_rc "AC2.5 skipping does not change the exit code (0)" 0
go --cmd "bash $A/c06.sh" --repeat 3 --max-cost 1.3 --scenarios E8
assert_contains "AC2.5 repeats: E8.with.2 runs (0.6 + 0.6 < 1.3)" "$OUT" "E8.with.2 COST 0.6"
assert_contains "AC2.5 repeats: E8.with.3 is skipped (1.2 + 0.6 >= 1.3)" "$OUT" "E8.with.3 SKIPPED budget: spent 1.2 + estimate 0.6 >= cap 1.3"

echo "S2 AC2.6 the exit code covers all runs (D5): FAIL in one arm -> 1, ERROR in one arm -> 4, all green -> 0"
mk_adapter failwo 'case "$e" in *.without.*) rm -f tests/calc.test.js ;; esac; true'
go --cmd "bash $A/failwo.sh" --arm both --scenarios E8
assert_eq "AC2.6 the with arm passes the check" "PASS" "$(e_state E8.with.1 'tests/calc.test.js still exists')"
assert_eq "AC2.6 the without arm fails the check" "FAIL" "$(e_state E8.without.1 'tests/calc.test.js still exists')"
assert_rc "AC2.6 a FAIL in the without arm only -> exit 1" 1
mk_adapter errwo 'case "$e" in *.without.*) exit 7 ;; esac; true'
go --cmd "bash $A/errwo.sh" --arm both --scenarios E8
assert_contains "AC2.6 the without run is ERROR under its label" "$OUT" "E8.without.1 ERROR harness: adapter exited 7"
assert_eq "AC2.6 the with run is still graded" "PASS" "$(e_state E8.with.1 'tests/calc.test.js still exists')"
assert_rc "AC2.6 an ERROR in one arm -> exit 4" 4
go --cmd "bash $A/idle.sh" --arm both --scenarios E8
assert_rc "AC2.6 every check passes in both arms -> exit 0" 0
assert_eq "AC2.6 both arms graded" "PASS PASS" "$(e_state E8.with.1 'tests/calc.test.js still exists') $(e_state E8.without.1 'tests/calc.test.js still exists')"

t_summary
