#!/usr/bin/env bash
# Tests for evals/run-outcome.sh, runner core (v0.27.0 lane O, spec .agents/handoff/01-spec.md slice S1, AC1-AC6): setup into
# <workroot>/<id>.<arm>.<k>, the prompt file, the adapter contract, grading in a runner-private copy with the hidden tests
# copied in after the adapter exits, FAIL_TO_PASS / PASS_TO_PASS, ERROR runs, exit codes and workroot refusals.
# Fixture tasks and stubs: tests/outcome-fixture.sh. Never calls a real harness.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-arms-fixture.sh"
. "$(dirname "$0")/outcome-fixture.sh"

echo "fixture guard: the three fixture tasks pass evals/check-tasks.sh (F2P fail unsolved, all pass after solution.patch)"
run bash "$PB_ROOT/evals/check-tasks.sh" --tasks-dir "$T"
assert_rc "fixture: check-tasks exits 0 on the fixture tasks" 0
for id in t-add t-two t-node; do assert_contains "fixture: $id SELF-CHECK OK" "$OUT" "$id SELF-CHECK OK"; done

echo "S1 AC1-AC3 every task of --tasks-dir (default all), a stub that solves: setup, prompt, adapter contract, grading copy"
ro --cmd "bash $SA/solve.sh"
assert_rc "AC5 every graded run PASS -> exit 0" 0
for id in t-add t-two t-node; do
  L="$id.with.1"
  assert_dir "AC1 label <id>.<arm>.<k> even without --arm/--repeat: $L is the workdir" "$WR/$L"
  assert_eq "AC1/AC3 $L: hidden tests pass = PASS" "PASS" "$(chk "$L" 'hidden tests pass')"
done
L=t-add.with.1
F="$(mk_tmp)/fresh"; bash "$T/t-add/setup.sh" "$F" >/dev/null 2>&1
assert_eq "AC1 the workdir is a fresh repo made by the task's setup.sh (same HEAD as a direct setup run)" \
  "$(git -C "$F" rev-parse HEAD 2>/dev/null)" "$(git -C "$WR/$L" rev-parse HEAD 2>/dev/null)"
assert_eq "AC1 <workroot>/<label>.prompt = prompt.md plus run-evals' non-interactive line" \
  "$(cat "$T/t-add/prompt.md")
$NONINT" "$(cat "$WR/$L.prompt" 2>/dev/null)"
assert_eq "AC1 the adapter gets <workdir> <prompt-file> (physical paths compared)" \
  "$(physdir "$WR/$L") $(physdir "$WR")/$L.prompt" \
  "$(a="$(sed -n 1p "$SR/$L.args" 2>/dev/null)"; p="$(sed -n 2p "$SR/$L.args" 2>/dev/null)"; printf '%s %s/%s' "$(physdir "$a")" "$(physdir "$(dirname "$p")")" "$(basename "$p")")"
LOGT="$(cat "$WR/$L.log" 2>/dev/null)"
assert_contains "AC1 the adapter's stdout goes to <workroot>/<label>.log" "$LOGT" "STUB-OUT-$L"
assert_contains "AC1 the adapter's stderr goes to <workroot>/<label>.log" "$LOGT" "STUB-ERR-$L"
assert_eq "AC8 no hidden destination path exists in the workdir when the adapter starts" "" "$(rec_of "$SR/$L.hidden")"
assert_no_path "AC2 the hidden F2P file is not left in the workdir after grading" "$WR/$L/tests/add.f2p.sh"
assert_no_path "AC2 the hidden P2P file is not left in the workdir after grading" "$WR/$L/tests/mul.p2p.sh"
# where the hidden tests ran: one line per run of tests/add.f2p.sh
GD="$(head -n 1 "$GR/t-add.add.f2p.sh" 2>/dev/null)"
assert_eq "AC2 the hidden F2P test of t-add ran exactly once" "1" "$({ wc -l < "$GR/t-add.add.f2p.sh"; } 2>/dev/null | tr -d ' ')"
assert_eq "AC2 F2P and P2P of t-add ran in the same grading copy" "same" \
  "$(if [ -n "$GD" ] && [ "$GD" = "$(head -n 1 "$GR/t-add.mul.p2p.sh" 2>/dev/null)" ]; then echo same; else echo "F2P in [$GD], P2P in [$(head -n 1 "$GR/t-add.mul.p2p.sh" 2>/dev/null)]"; fi)"
if [ -n "$GD" ] && ! under "$GD" "$(physdir "$WR")" && ! under "$GD" "$WR" && ! under "$GD" "$(cat "$SR/$L.tmp" 2>/dev/null || echo /nonexistent-agent-tmp)"; then
  t_ok "AC2 the grading copy is outside the workroot and outside the agent's TMPDIR"
else t_bad "AC2 the grading copy is outside the workroot and outside the agent's TMPDIR" "graded in [$GD], workroot $WR, agent TMPDIR $(cat "$SR/$L.tmp" 2>/dev/null)"; fi
if [ -n "$GD" ] && [ ! -e "$GD" ]; then t_ok "AC2 the grading copy is deleted after grading"
else t_bad "AC2 the grading copy is deleted after grading" "[$GD] still exists or no hidden test ran"; fi
assert_eq "AC2 the node task's F2P file ran (node --test) in a grading copy" "1" "$({ wc -l < "$GR/t-node.add.f2p.test.js"; } 2>/dev/null | tr -d ' ')"
assert_eq "AC8/AC10 nothing is left in the runner's TMPDIR" "" "$(leftovers "$RT")"
assert_eq "AC8 no canary anywhere under the workroot" "" "$(grep -rl "$CAN:" "$WR" 2>/dev/null)"

echo "S1 AC1 --interactive: the prompt file is prompt.md alone"
ro --cmd "bash $SA/solve.sh" --tasks t-add --interactive
assert_rc "AC1 --interactive run -> exit 0" 0
assert_eq "AC1 --interactive: <label>.prompt = prompt.md" "$(cat "$T/t-add/prompt.md")" "$(cat "$WR/t-add.with.1.prompt" 2>/dev/null)"

echo "S1 AC3 a stub that changes nothing: FAIL with every F2P file named"
ro --cmd "bash $SA/idle.sh" --tasks t-add,t-two,t-node
assert_rc "AC5 any FAIL -> exit 1" 1
assert_eq "AC3 t-add: hidden tests pass = FAIL" "FAIL" "$(chk t-add.with.1 'hidden tests pass')"
assert_eq "AC3 t-add: FAIL_TO_PASS tests/add.f2p.sh = FAIL" "FAIL" "$(chk t-add.with.1 'FAIL_TO_PASS tests/add.f2p.sh')"
assert_eq "AC3 t-add: PASS_TO_PASS tests/mul.p2p.sh = PASS" "PASS" "$(chk t-add.with.1 'PASS_TO_PASS tests/mul.p2p.sh')"
assert_eq "AC3 t-two: both F2P files FAIL" "FAIL FAIL" "$(chk t-two.with.1 'FAIL_TO_PASS tests/a.f2p.sh') $(chk t-two.with.1 'FAIL_TO_PASS tests/b.f2p.sh')"
assert_eq "AC2 t-node (node --test): F2P FAIL, P2P PASS" "FAIL PASS" "$(chk t-node.with.1 'FAIL_TO_PASS tests/add.f2p.test.js') $(chk t-node.with.1 'PASS_TO_PASS tests/mul.p2p.test.js')"
FL="$(printf '%s\n' "$OUT" | grep '^t-two\.with\.1 ' | grep FAIL)"
assert_contains "AC2 the FAIL output of t-two names tests/a.f2p.sh" "$FL" "tests/a.f2p.sh"
assert_contains "AC2 the FAIL output of t-two names tests/b.f2p.sh" "$FL" "tests/b.f2p.sh"

echo "S1 AC3 a stub that fixes F2P but breaks a P2P behaviour: FAIL naming that P2P file"
ro --cmd "bash $SA/breakp2p.sh" --tasks t-add
assert_rc "AC5 a broken P2P -> exit 1" 1
assert_eq "AC3 FAIL_TO_PASS tests/add.f2p.sh = PASS" "PASS" "$(chk t-add.with.1 'FAIL_TO_PASS tests/add.f2p.sh')"
assert_eq "AC3 PASS_TO_PASS tests/mul.p2p.sh = FAIL" "FAIL" "$(chk t-add.with.1 'PASS_TO_PASS tests/mul.p2p.sh')"
assert_eq "AC3 hidden tests pass = FAIL" "FAIL" "$(chk t-add.with.1 'hidden tests pass')"
assert_contains "AC2 the FAIL output names tests/mul.p2p.sh" "$(printf '%s\n' "$OUT" | grep '^t-add\.with\.1 ' | grep FAIL)" "tests/mul.p2p.sh"

echo "S1 AC2 the hidden files overwrite agent files at the same paths (an agent that writes 'exit 0' F2P files)"
ro --cmd "bash $SA/cheat.sh" --tasks t-add,t-two
assert_rc "AC2 cheat stub -> exit 1" 1
assert_eq "AC2 t-add: the agent's tests/add.f2p.sh is replaced by the hidden one (FAIL)" "FAIL" "$(chk t-add.with.1 'FAIL_TO_PASS tests/add.f2p.sh')"
assert_eq "AC2 t-two: the agent's tests/a.f2p.sh is replaced by the hidden one (FAIL)" "FAIL" "$(chk t-two.with.1 'FAIL_TO_PASS tests/a.f2p.sh')"

echo "S1 AC4 an adapter that exits non-zero is ERROR, not graded, no hidden file copied"
ro --cmd "bash $SA/exit7.sh" --tasks t-add
assert_rc "AC5 any ERROR -> exit 4" 4
assert_eq "AC4 an output line '<label> ERROR ...'" "1" "$(printf '%s\n' "$OUT" | grep -c '^t-add\.with\.1 ERROR')"
assert_eq "AC4 JSON status error" '"error"' "$(rfield t-add.with.1 status)"
assert_eq "AC4 the ERROR run has no checks" "0" "$(jget "$JF" '(((j.runs||[]).find(r=>r.label==="t-add.with.1")||{}).checks||[1]).length')"
assert_eq "AC4 no hidden test ran (nothing copied, not graded)" "" "$(leftovers "$GR")"
assert_eq "AC4 no canary under the workroot" "" "$(grep -rl "$CAN:" "$WR" 2>/dev/null)"
assert_eq "AC4/AC10 nothing is left in the runner's TMPDIR" "" "$(leftovers "$RT")"

echo "S1 AC4 an auth marker in the transcript is ERROR even when the adapter exits 0 and solved the task"
ro --cmd "bash $SA/auth.sh" --tasks t-add
assert_rc "AC4 auth marker -> exit 4" 4
assert_eq "AC4 auth marker: JSON status error" '"error"' "$(rfield t-add.with.1 status)"
assert_eq "AC4 auth marker: no hidden test ran" "" "$(leftovers "$GR")"

echo "S1 AC4 an adapter that runs past --timeout is ERROR"
if [ "$HAS_TIMEOUT" = 1 ]; then
  ro --cmd "bash $SA/slow.sh" --tasks t-add --timeout 1
  assert_rc "AC4 timeout -> exit 4" 4
  assert_eq "AC4 timeout: JSON status error" '"error"' "$(rfield t-add.with.1 status)"
else
  t_skip 2 "no working timeout command on this platform"
fi

echo "S1 AC5 usage and environment exit codes"
ro --cmd "bash $SA/solve.sh" --tasks t-add,t-nope
assert_rc "AC5 an unknown task id -> exit 2" 2
assert_no_path "AC5 unknown task id: nothing run" "$WR/t-add.with.1"
ro --cmd "bash $SA/solve.sh" --tasks t-add --repeat 0
assert_rc "AC5/AC11 --repeat 0 (lane E refusal) -> exit 2" 2
ro --cmd "bash $SA/solve.sh" --tasks t-add --arm sideways
assert_rc "AC5/AC11 --arm sideways (lane E refusal) -> exit 2" 2
ro --cmd "bash $SA/solve.sh" --tasks-dir "$TB" --tasks t-bad
assert_rc "AC5 a setup.sh that fails -> exit 3" 3
assert_eq "AC5 setup fails: the adapter did not run" "NO-RECORD" "$(rec_of "$SR/t-bad.with.1.args")"

echo "S1 AC5 a workroot the runner does not own is refused and left as it was"
rm -f "$SR"/*
NW="$(mk_tmp)"; mkdir -p "$NW/t-add.with.1"; printf 'mine\n' > "$NW/t-add.with.1/keep.txt"
run env -u PLAYBOOK_HOME HOME="$GH" bash "$OUTCOME" --tasks-dir "$T" --tasks t-add --cmd "bash $SA/solve.sh" --workroot "$NW" --out "$(mk_tmp)/r.md"
assert_rc "AC5 a workroot without the marker holding <label> -> exit 2" 2
assert_eq "AC5 the foreign <label> dir is untouched" "mine" "$(cat "$NW/t-add.with.1/keep.txt" 2>/dev/null)"
assert_eq "AC5 the adapter did not run" "NO-RECORD" "$(rec_of "$SR/t-add.with.1.args")"

echo "S1 AC6 a workroot inside the playbook repository or inside --tasks-dir is refused, nothing run"
rm -f "$SR"/*
IN_REPO="$PB_ROOT/pbtest-o-wr.$$"
run env -u PLAYBOOK_HOME HOME="$GH" bash "$OUTCOME" --tasks-dir "$T" --tasks t-add --cmd "bash $SA/solve.sh" --workroot "$IN_REPO" --out "$(mk_tmp)/r.md"
assert_rc "AC6 --workroot inside the playbook repo -> exit 2" 2
assert_no_path "AC6 the in-repo workroot is not created" "$IN_REPO"
case "$IN_REPO" in */pbtest-o-wr.*) if [ -d "$IN_REPO" ]; then rm -rf "$IN_REPO"; fi ;; esac   # only if a wrong runner made it
run env -u PLAYBOOK_HOME HOME="$GH" bash "$OUTCOME" --tasks-dir "$T" --tasks t-add --cmd "bash $SA/solve.sh" --workroot "$T/wr" --out "$(mk_tmp)/r.md"
assert_rc "AC6 --workroot inside --tasks-dir -> exit 2" 2
assert_no_path "AC6 the workroot inside the tasks dir is not created" "$T/wr"
assert_eq "AC6 the adapter did not run" "NO-RECORD" "$(rec_of "$SR/t-add.with.1.args")"

t_summary
