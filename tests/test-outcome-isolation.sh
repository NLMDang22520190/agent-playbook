#!/usr/bin/env bash
# Tests for evals/run-outcome.sh, hidden-test isolation (v0.27.0 lane O, spec .agents/handoff/01-spec.md slice S2, AC7-AC10):
# a snoop stub finds no canary in its workdir, the workroot (earlier repeats and the other arm), the workroot's parent, the
# git history, its TMPDIR, PLAYBOOK_HOME or env; no hidden file is ever under the workroot; a transcript that shows the canary
# makes the run CONTAMINATED; per-run temp PLAYBOOK_HOME and TMPDIR, removed afterwards; the STRAY check.
# Fixture tasks and stubs: tests/outcome-fixture.sh. Never calls a real harness.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-arms-fixture.sh"
. "$(dirname "$0")/outcome-fixture.sh"

echo "S2 AC7/AC8 a snoop stub with --repeat 2 --arm both (4 runs; runs 2-4 snoop after graded runs of the same task)"
ro --cmd "bash $SA/snoop.sh" --tasks t-add --repeat 2 --arm both
assert_rc "AC7 snoop runs that solve the task -> exit 0" 0
for L in t-add.with.1 t-add.without.1 t-add.with.2 t-add.without.2; do
  assert_eq "AC7 $L was graded PASS (the snoop ran inside a real graded run)" "PASS" "$(chk "$L" 'hidden tests pass')"
  assert_eq "AC7 $L: no canary in workdir, workroot, parent, git log --all -p, TMPDIR, PLAYBOOK_HOME or env" "CLEAN" "$(rec_of "$SR/$L.snoop")"
  assert_eq "AC8 $L: no hidden destination path in the workdir at start" "" "$(rec_of "$SR/$L.hidden")"
done
assert_eq "AC7 the snoop listed the earlier runs (the workroot listing names t-add.with.1)" "yes" "$(grep -q 't-add\.with\.1' "$SR/t-add.without.2.dump" 2>/dev/null && echo yes || echo no)"
assert_eq "AC8 after the invocation no canary anywhere under the workroot" "" "$(grep -rl "$CAN:" "$WR" 2>/dev/null)"
assert_eq "AC8/AC10 nothing is left in the runner's TMPDIR (no grading copy, no temp homes or TMPDIRs)" "" "$(leftovers "$RT")"
GONE=yes; NG=0
for f in "$GR"/t-add.*; do
  [ -f "$f" ] || continue
  while IFS= read -r d; do NG=$((NG + 1)); if [ -e "$d" ]; then GONE="no: $d"; fi; done < "$f"
done
assert_eq "AC2 the hidden tests ran once per run and file (4 runs x 2 files)" "8" "$NG"
assert_eq "AC8 every grading copy is gone after the invocation" "yes" "$GONE"

echo "S2 AC9 a transcript that contains the canary makes the run CONTAMINATED"
ro --cmd "bash $SA/canary.sh" --tasks t-add
assert_rc "AC9 CONTAMINATED -> exit 1" 1
assert_eq "AC9/AC11 'hidden tests not seen by the agent' = FAIL" "FAIL" "$(chk t-add.with.1 'hidden tests not seen by the agent')"
assert_eq "AC9/AC11 'hidden tests pass' = FAIL although every F2P/P2P file passed" "FAIL PASS PASS" \
  "$(chk t-add.with.1 'hidden tests pass') $(chk t-add.with.1 'FAIL_TO_PASS tests/add.f2p.sh') $(chk t-add.with.1 'PASS_TO_PASS tests/mul.p2p.sh')"
assert_contains "AC9 the output says CONTAMINATED for the run" "$(printf '%s\n' "$OUT" | grep '^t-add\.with\.1 ')" "CONTAMINATED"
assert_contains "AC9 the md report says CONTAMINATED" "$(cat "$RES" 2>/dev/null)" "CONTAMINATED"
ro --cmd "bash $SA/solve.sh" --tasks t-add
assert_eq "AC9/AC11 a clean run: 'hidden tests not seen by the agent' = PASS" "PASS" "$(chk t-add.with.1 'hidden tests not seen by the agent')"
assert_not_contains "AC9 a clean run is not CONTAMINATED" "$OUT" "CONTAMINATED"

echo "S2 AC10 per run its own temp PLAYBOOK_HOME and TMPDIR, removed after the run"
ro --cmd "bash $SA/solve.sh" --tasks t-add --repeat 2 --arm both
assert_rc "AC10 solve --repeat 2 --arm both -> exit 0" 0
PHS=""; TMS=""
for L in t-add.with.1 t-add.without.1 t-add.with.2 t-add.without.2; do
  PHS="$PHS $(rec_of "$SR/$L.ph")"; TMS="$TMS $(rec_of "$SR/$L.tmp")"
  assert_eq "AC10 $L: HOME stays the real (stand-in) home" "$GH" "$(rec_of "$SR/$L.home")"
done
assert_eq "AC10 four distinct PLAYBOOK_HOME dirs" "4" "$(printf '%s\n' $PHS | grep -v -e UNSET -e NO-RECORD | LC_ALL=C sort -u | grep -c .)"
assert_eq "AC10 four distinct TMPDIRs" "4" "$(printf '%s\n' $TMS | grep -v -e UNSET -e NO-RECORD | LC_ALL=C sort -u | grep -c .)"
BAD=""
for d in $PHS $TMS; do
  if under "$d" "$RT" || under "$d" "$(physdir "$RT")"; then :; else BAD="$BAD [$d not in runner TMPDIR]"; fi
  if [ -e "$d" ]; then BAD="$BAD [$d left]"; fi
done
assert_eq "AC10 the temp homes and TMPDIRs live in the runner's TMPDIR and are removed" "" "$BAD"
assert_eq "AC10 with arm: PLAYBOOK_HOME holds the conf copy without feedback_repo" "test_cmd=make check
language=vi" "$(rec_of "$SR/t-add.with.1.conf")"
assert_eq "AC10/AC13 without arm: PLAYBOOK_HOME is empty" "" "$(rec_of "$SR/t-add.without.1.phfiles")"

echo "S2 AC10 the STRAY rule: a file written next to the workdir is a FAIL check"
ro --cmd "bash $SA/stray.sh" --tasks t-add
assert_rc "AC10 STRAY -> exit 1" 1
assert_eq "AC10 check 'nothing written outside the workdir ...' = FAIL" "FAIL" \
  "$(jget "$JF" '((((j.runs||[]).find(r=>r.label==="t-add.with.1")||{}).checks||[]).filter(c=>String(c.name).indexOf("nothing written outside the workdir")===0).map(c=>c.result).join(","))||"none"')"
assert_eq "AC10 the hidden tests still pass (the FAIL comes from STRAY alone)" "PASS" "$(chk t-add.with.1 'FAIL_TO_PASS tests/add.f2p.sh')"
ro --cmd "bash $SA/solve.sh" --tasks t-add
assert_eq "AC10 a clean run: 'nothing written outside the workdir' = PASS" "PASS" "$(chk t-add.with.1 'nothing written outside the workdir')"

t_summary
