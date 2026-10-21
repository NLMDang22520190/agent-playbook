#!/usr/bin/env bash
# Tests for scripts/tdd-step.sh (v0.24.23 lane A, Full), part 1 of 3 (parts 2 and 3: test-tdd-step-h.sh, test-tdd-step-i.sh; slice S1 + S2 of .agents/handoff/01-spec.md; the exec-bit rows AC4/AC5 come in a later slice).
#   AC3  characterization (they pass on v0.24.22, the mutant kills are their proof): a merge commit with an unchanged tree is refused; every pipe_ok call refuses when its pipeline stage fails
#   AC1  linked worktree, unborn branch, and a branch that cannot be read (git symbolic-ref -q HEAD fails: exit 3)
#   AC2  unchanged: a no-op hook (or none) gives byte-identical output
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

# the branch of a run in a linked worktree is that worktree's own
echo "AC1 linked worktree: the branch is the worktree's own"
wt_setup() {
  gprep default; WT="$(mk_tmp)/wt"
  ( cd "$R" && git worktree add -q -b wtb "$WT" ) || t_bad "worktree add failed"
  printf 'test("n", () => {});\n' > "$WT/tests/n.test.js"
  W0="$(git -C "$WT" rev-parse HEAD)"; WN="$(git -C "$WT" rev-list --count HEAD)"
}
wt_setup
run_in "$WT" bash "$STEP" red --message "m" --commit -- sh -c "git checkout -q -b other2; exit 1"
assert_rc "AC1 worktree: the test command switches the worktree's branch: exit 1" 1
assert_contains "AC1 worktree: says nothing committed" "$(lower "$OUT")" "nothing committed"
assert_eq "AC1 worktree: no commit on any branch" "$WN" "$(git -C "$WT" rev-list --all --count)"
assert_eq "AC1 worktree: wtb is where it was" "$W0" "$(git -C "$WT" rev-parse refs/heads/wtb)"
wt_setup
run_in "$WT" bash "$STEP" red --message "m" --commit -- sh -c "git -C '$R' checkout -q existing; exit 1"
assert_rc "AC1 worktree control: the primary worktree switches its own branch: not the worktree's branch, exit 0" 0
assert_eq "AC1 worktree control: the commit is on wtb" "test(red): m" "$(git -C "$WT" log -1 --format=%s refs/heads/wtb)"
assert_eq "AC1 worktree control: its parent is the worktree's HEAD from before" "$W0" "$(git -C "$WT" rev-parse refs/heads/wtb^)"
assert_eq "AC1 worktree control: $MAIN did not move" "$H0" "$(tip "$MAIN")"
assert_eq "AC1 worktree control: the primary worktree is on the branch its test command chose" "refs/heads/existing" "$(git -C "$R" symbolic-ref HEAD)"

# an unborn branch stops before the test command (role-gate: base ref not found)
echo "AC1 unchanged: an unborn branch stops before the test command"
U="$(mk_tmp)"; ( cd "$U" && git init -q && git config user.email t@example.invalid && git config user.name tester ); UM="$(mk_tmp)/ran"
run_in "$U" bash "$STEP" red --message "m" --commit -- sh -c "touch '$UM'; exit 1"
assert_rc "AC1 unborn: exit 1" 1
assert_contains "AC1 unborn: base ref not found" "$OUT" "base ref not found"
assert_no_path "AC1 unborn: the test command did not run" "$UM"

# the branch cannot be read: git symbolic-ref -q HEAD exits with neither 0 nor 1
echo "AC1 git symbolic-ref -q HEAD fails with an exit code other than 0 and 1: exit 3, nothing committed"
# sr_case LABEL MODE FROM RC -> 6 assertions (FROM = the number of the first symbolic-ref read that fails)
sr_case() {
  local label="$1" mode="$2" from="$3" rc="$4" d t
  gprep "$mode"
  t="${SRREAD_STUB//@FROM@/$from}"; t="${t//@RC@/$rc}"; d="$(stubdir git "$t")"
  run_red_p "$d" --commit sh -c "exit 1"
  assert_rc "$label ($mode): exit 3" 3
  assert_contains "$label ($mode): says it cannot read the branch" "$(lower "$OUT")" "cannot read the branch"
  assert_not_contains "$label ($mode): no RED= line" "$OUT" "RED="
  assert_untouched "$label ($mode): nothing committed" "$R" "$H0" "$N0"
  assert_eq "$label ($mode): no commit on any branch" "$N0" "$(allcount)"
  assert_eq "$label ($mode): the work tree is kept" 'test("n", () => {});' "$(cat "$R/tests/n.test.js")"
}
sr_case "AC1 the read before the test command fails (exit 128)" default 1 128
sr_case "AC1 the read after the test command fails (exit 128)" default 2 128
sr_case "AC1 the read after the test command fails (exit 2)" default 2 2
sr_case "AC1 the read after the test command fails (exit 128)" baseline 2 128

# ---------------------------------------------------------------------------------------------------------------
echo "AC2 unchanged: a no-op hook (or none) gives byte-identical output, exit code and commit (the v0.24.22 behaviour)"
if can_exec; then
  norm() { printf '%s' "$1" | sed -E "s/[0-9]{8}T[0-9]{6}Z/<ts>/g; s/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z/<time>/g"; }
  dropw() { printf '%s\n' "$1" | sed -E "/^warning: in the working copy of '[^']*', LF will be replaced by CRLF the next time Git touches it$/d"; }
  # noop_same LABEL MODE FLAG -> 3 assertions: repo a has no hook, repo b a post-commit hook that does nothing; fixed dates make equal runs give equal shas
  noop_same() {
    local label="$1" mode="$2" flag="$3" a b ba bb oa ob ra rb
    export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"
    a="$(fresh)"; b="$(fresh)"; ba=""; bb=""
    if [ "$mode" = baseline ]; then dirty "$a"; dirty "$b"; ba="$(snap "$a")"; bb="$(snap "$b")"; fi
    printf 'test("n", () => {});\n' > "$a/tests/n.test.js"; printf 'test("n", () => {});\n' > "$b/tests/n.test.js"
    cp "$HK_NOOP" "$b/.git/hooks/post-commit" && chmod +x "$b/.git/hooks/post-commit"
    run_in "$a" bash "$STEP" red --message "m" $flag ${ba:+--baseline "$ba"} -- sh -c "exit 1"; oa="$OUT"; ra="$RC"
    run_in "$b" bash "$STEP" red --message "m" $flag ${bb:+--baseline "$bb"} -- sh -c "exit 1"; ob="$OUT"; rb="$RC"
    unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE
    oa="$(repl_path "$oa" "<R>" "$a")"; ob="$(repl_path "$ob" "<R>" "$b")"
    if [ -n "$ba" ]; then oa="$(repl_path "$oa" "<BL>" "$ba")"; ob="$(repl_path "$ob" "<BL>" "$bb")"; fi
    assert_eq "$label: same exit code (0)" "0 $ra" "0 $rb"
    assert_eq "$label: byte-identical output" "$(norm "$(dropw "$oa")")" "$(norm "$(dropw "$ob")")"
    assert_eq "$label: same commit (sha)" "$(head_of "$a")" "$(head_of "$b")"
  }
  for MODE in default baseline; do
    noop_same "AC2 unchanged: no-op hook, RED --commit ($MODE)" "$MODE" --commit
  done
  noop_same "AC2 unchanged: no-op hook, RED print mode (default)" default ""
else
  t_skip 9 "AC2 unchanged output with a no-op hook (the file system cannot make a hook executable)"
fi


t_summary
