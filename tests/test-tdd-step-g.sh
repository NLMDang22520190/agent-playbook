#!/usr/bin/env bash
# Tests for scripts/tdd-step.sh (v0.24.23 lane A, Full), part 1 of 7 (parts: test-tdd-step-h.sh, -i.sh, -k.sh, -l.sh, -j.sh, -m.sh; slice S1 + S2 of .agents/handoff/01-spec.md; the exec-bit rows AC4/AC5 are in test-tdd-step-j.sh).
# Split in v0.24.23 for the local Windows Git Bash time (one tdd-step run costs about 20 s there; a suite over about 450 s would set a shard floor, L-0009): this part keeps AC3 (a) and (b); test-tdd-step-k.sh holds the rest of the old part 1.
#   AC3  characterization (they pass on v0.24.22, the mutant kills are their proof): a merge commit with an unchanged tree is refused; every pipe_ok call refuses when its pipeline stage fails
# Shared setup: tdd-step-fixture.sh, tdd-step-d-fixture.sh and tdd-step-g-fixture.sh. Cases that already pass on v0.24.22 are named "control" or "unchanged".
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/tdd-step-fixture.sh"
. "$(dirname "$0")/tdd-step-d-fixture.sh"
. "$(dirname "$0")/tdd-step-g-fixture.sh"

# ---------------------------------------------------------------------------------------------------------------
echo "AC3 (a) a post-commit hook replaces HEAD by a merge commit with the judged tree (first parent = the pre-run HEAD, second = the judged commit): refused"
if can_exec; then
  for MODE in default baseline; do
    prep "$MODE"
    run_red --commit sh -c "$(hookcmd "$HK_MERGE2" post-commit)"
    assert_contains "AC3a merge, same tree ($MODE): the run reached git commit (the post-commit hook ran)" "$(ls "$R/.git")" "mg2-done"
    assert_rc "AC3a merge, same tree ($MODE): exit 1" 1
    assert_contains "AC3a merge, same tree ($MODE): says nothing committed" "$(lower "$OUT")" "nothing committed"
    assert_eq "AC3a merge, same tree ($MODE): HEAD is the HEAD from before tdd-step" "$H0" "$(head_of "$R")"
    assert_eq "AC3a merge, same tree ($MODE): commit count unchanged" "$N0" "$(count_of "$R")"
    assert_eq "AC3a merge, same tree ($MODE): the index file is restored byte for byte" "same" "$(same_idx)"
    assert_eq "AC3a merge, same tree ($MODE): no test(red) commit in the log" "" "$(no_red_commit)"
    assert_not_contains "AC3a merge, same tree ($MODE): no RED= line" "$OUT" "RED="
  done
else
  t_skip 16 "AC3a merge commit with an unchanged tree (the file system cannot make a hook executable)"
fi

# ---------------------------------------------------------------------------------------------------------------
echo "AC3 (b) a pipeline stage that fails after writing its correct output makes the step refuse, one case per pipe_ok call (PATH stubs of awk and sort)"
# fault_case LABEL MODE KIND FIRE -> 8 assertions. KIND awk: the FIRE-th awk call whose program holds the filter_judged text fails (1 = before git commit, 2 = in check_commit);
# KIND sort: the sort of "expected" and "got" fails. The stub runs the real tool, writes the correct output, then exits non-zero.
fault_case() {
  local label="$1" mode="$2" kind="$3" fire="$4" d seen
  prep "$mode"
  if [ "$kind" = awk ]; then
    d="$(stubdir awk "${AWK_STUB//@FIRE@/$fire}")"; printf '%s' 'p = substr($0, index($0, "\t") + 1)' > "$d/cnt.pat"
  else
    d="$(stubdir sort "$SORT_STUB")"
  fi
  run_red_p "$d" --commit sh -c "cp .git/index '$IDXF'; exit 1"
  if [ "$kind" = awk ]; then seen="$(cat "$d/cnt" 2>/dev/null)"; else seen="$([ -f "$d/cnt" ] && echo fired || echo never)"; fi
  if [ "$kind" = awk ]; then assert_eq "$label ($mode): the stub failed awk call number $fire (the step reached it)" "$fire" "$seen"
  else assert_eq "$label ($mode): the stub failed the sort of expected and got" "fired" "$seen"; fi
  assert_rc "$label ($mode): exit 1" 1
  assert_contains "$label ($mode): says nothing committed" "$(lower "$OUT")" "nothing committed"
  assert_not_contains "$label ($mode): no RED= line" "$OUT" "RED="
  assert_untouched "$label ($mode): nothing committed" "$R" "$H0" "$N0"
  assert_eq "$label ($mode): no test(red) commit in the log" "" "$(no_red_commit)"
  assert_eq "$label ($mode): the index file is restored byte for byte" "same" "$(same_idx)"
}
for MODE in default baseline; do
  fault_case "AC3b pipe_ok after the judged entries are read (before git commit; :280 default, :270 --baseline)" "$MODE" awk 1
  fault_case "AC3b pipe_ok after the committed entries are read (check_commit, :159)" "$MODE" awk 2
  fault_case "AC3b pipe_ok after sort expected got (check_commit, :160)" "$MODE" sort 0
  # control: the stub never fires (the third call does not exist), so the step commits; both filter_judged calls were reached
  prep "$MODE"
  D="$(stubdir awk "${AWK_STUB//@FIRE@/99}")"; printf '%s' 'p = substr($0, index($0, "\t") + 1)' > "$D/cnt.pat"
  run_red_p "$D" --commit sh -c "exit 1"
  assert_rc "AC3b control: a stub that never fires does not refuse ($MODE): exit 0" 0
  assert_eq "AC3b control ($MODE): one new commit" "$((N0 + 1))" "$(count_of "$R")"
  assert_eq "AC3b control ($MODE): filter_judged ran twice (before git commit and in check_commit)" "2" "$(cat "$D/cnt" 2>/dev/null)"
done

t_summary
