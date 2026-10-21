#!/usr/bin/env bash
# Tests for scripts/tdd-step.sh (v0.24.22 lane T, Full), part 2 of 2: the second half of test-tdd-step-d.sh (split so that neither is the floor of a CI shard, L-0009),
# from "AC3 print mode: a passing run..." to the end. Shared setup: tdd-step-fixture.sh and tdd-step-d-fixture.sh. Same AC ids and fix-round names as part 1.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/tdd-step-fixture.sh"
. "$(dirname "$0")/tdd-step-d-fixture.sh"

# ---------------------------------------------------------------------------------------------------------------
echo "AC3 print mode: a passing run prints the commands unchanged and commits nothing"
prep default
run_red "" sh -c 'exit 1'
assert_rc "AC3 print mode, default path, passing: exit 0" 0
assert_contains "AC3 print mode, default path, passing: the command line" "$OUT" 'not committing (no --commit). To commit: git add -A && git commit -m "test(red): m"'
assert_eq "AC3 print mode, default path, passing: nothing committed" "$N0" "$(count_of "$R")"
prep baseline
run_red "" sh -c 'exit 1'
assert_rc "AC3 print mode, --baseline, passing: exit 0" 0
assert_contains "AC3 print mode, --baseline, passing: the header line" "$OUT" "not committing (no --commit). To commit only the role's paths:"
assert_contains "AC3 print mode, --baseline, passing: the add line" "$OUT" "GIT_LITERAL_PATHSPECS=1 git add -- tests/n.test.js"
assert_contains "AC3 print mode, --baseline, passing: the commit line" "$OUT" 'GIT_LITERAL_PATHSPECS=1 git commit -m test\(red\):\ m -- tests/n.test.js'
assert_eq "AC3 print mode, --baseline, passing: nothing committed" "$N0" "$(count_of "$R")"

echo "AC3 print mode, --baseline: the same failures print the refusal instead of the commands"
refuse_case "AC3 the test command writes an untracked file" baseline "" "printf 'x\\n' > tests/extra.test.js; exit 1"
refuse_moved "AC3 the test command commits the role's file" baseline "" "git add tests/n.test.js && git commit -q -m x -- tests/n.test.js; exit 1"
echo "AC3 print mode: the test command writes src/gen.js (review probe P1), the commands are not printed"
refuse_case "AC3 P1 the test command writes src/gen.js" default "" "mkdir -p src; echo gen > src/gen.js; exit 1"
refuse_case "AC3 P1 the test command writes src/gen.js" baseline "" "mkdir -p src; echo gen > src/gen.js; exit 1"
echo "AC2 --baseline --commit control: the test command writes a file (already refused in v0.24.21)"
refuse_case "AC2 control: the test command writes an untracked file" baseline --commit "printf 'x\\n' > tests/extra.test.js; exit 1"

# ---------------------------------------------------------------------------------------------------------------
echo "AC2/AC3 a role path with a newline or a \\002 byte is refused before the test command (all four combinations)"
# precheck LABEL MODE FLAG NAME -> 6 assertions
precheck() {
  local label="$1" mode="$2" flag="$3" name="$4" mark
  prep "$mode"
  printf 'test("w", () => {});\n' > "$R/tests/$name"
  mark="$(mk_tmp)/marker"
  run_red "$flag" sh -c "touch '$mark'; exit 1"
  assert_rc "$label: exit 1" 1
  assert_contains "$label: tells the user to commit by hand" "$(lower "$OUT")" "by hand"
  assert_contains "$label: says nothing committed" "$(lower "$OUT")" "nothing committed"
  assert_no_path "$label: the test command did not run" "$mark"
  assert_untouched "$label: nothing committed" "$R" "$H0" "$N0"
}
C2="$(printf '\002')"
if can_nl; then
  for MODE in default baseline; do
    for FLAG in --commit ""; do
      precheck "AC2/3 newline in a role path ($MODE, ${FLAG:-print})" "$MODE" "$FLAG" "w"$'\n'"x.test.js"
    done
  done
else
  t_skip 24 "AC2/3 newline in a role path (the file system refuses a newline in a name)"
fi
if can_name "ctl${C2}x.test.js"; then
  for MODE in default baseline; do
    for FLAG in --commit ""; do
      precheck "AC2/3 \\002 in a role path ($MODE, ${FLAG:-print})" "$MODE" "$FLAG" "ctl${C2}x.test.js"
    done
  done
else
  t_skip 24 "AC2/3 \\002 in a role path (the file system refuses that name)"
fi

# ---------------------------------------------------------------------------------------------------------------
echo "AC4 the refusal names what was committed (same-tree case) or says HEAD was moved"
HK_PRE="$(mkhook preevil 'mkdir -p src' 'echo evil > src/evil.js' 'git add src/evil.js')"
HK_SAME="$(mkhook sametree 'touch .git/st-done' 't=$(git rev-parse HEAD^{tree})' 'c=$(git commit-tree "$t" -p HEAD -m sametree)' 'git update-ref HEAD "$c"')"
HK_RESET="$(mkhook resetsoft 'touch .git/rs-done' 'git reset -q --soft HEAD^')"
if can_exec; then
  for MODE in default baseline; do
    prep "$MODE"
    run_red --commit sh -c "cp '$HK_PRE' .git/hooks/pre-commit && cp '$HK_SAME' .git/hooks/post-commit && chmod +x .git/hooks/pre-commit .git/hooks/post-commit; exit 1"
    assert_rc "AC4 same-tree commit on top ($MODE): exit 1" 1
    assert_contains "AC4 same-tree commit on top ($MODE): says nothing committed" "$(lower "$OUT")" "nothing committed"
    assert_contains "AC4 same-tree commit on top ($MODE): the message names src/evil.js" "$OUT" "src/evil.js"
    assert_eq "AC4 same-tree commit on top ($MODE): HEAD is the HEAD from before tdd-step" "$H0" "$(head_of "$R")"
  done
  for MODE in default baseline; do
    prep "$MODE"
    run_red --commit sh -c "$(hookcmd "$HK_RESET" post-commit)"
    assert_rc "AC4 post-commit reset --soft HEAD^ ($MODE): exit 1" 1
    assert_contains "AC4 post-commit reset ($MODE): the run reached git commit (the post-commit hook ran)" "$(ls "$R/.git")" "rs-done"
    assert_contains "AC4 post-commit reset ($MODE): says nothing committed" "$(lower "$OUT")" "nothing committed"
    assert_contains "AC4 post-commit reset ($MODE): says HEAD was moved" "$OUT" "HEAD was moved to "
    assert_contains "AC4 post-commit reset ($MODE): names the pre-run commit" "$OUT" "(not one commit on "
    # the refusal only: the --baseline first gate prints "note: unchanged since the baseline: <path>" lines before it
    REFUSAL="$(printf '%s\n' "$OUT" | sed -n '/error: HEAD was moved/,$p')"
    assert_contains "AC4 post-commit reset ($MODE): the refusal text starts at the HEAD was moved line" "$REFUSAL" "error: HEAD was moved"
    assert_not_contains "AC4 post-commit reset ($MODE): names no pre-run path (README.md)" "$REFUSAL" "README.md"
    assert_not_contains "AC4 post-commit reset ($MODE): names no pre-run path (src/app.js)" "$REFUSAL" "src/app.js"
    assert_not_contains "AC4 post-commit reset ($MODE): names no pre-run path (tests/app.test.js)" "$REFUSAL" "tests/app.test.js"
    assert_untouched "AC4 post-commit reset ($MODE): the commit is undone" "$R" "$H0" "$N0"
  done
else
  t_skip 28 "AC4 hook cases (the file system cannot make a hook executable)"
fi

# ---------------------------------------------------------------------------------------------------------------
# the hook of suite d's first section that this section reuses
HK_CONTENT="$(mkhook content "printf 'changed by the hook\\n' > tests/n.test.js" 'git add tests/n.test.js')"
echo "AC1 fix round 1: a judged path list longer than the argument limit does not make the content check fail open"
# mkmany REPO -> 3000 untracked test files with 90-character names (about 300 KB of arguments, over the 128 KB floor of ARG_MAX on Linux)
mkmany() {
  local i n pad; pad="$(printf '%080d' 0)"
  mkdir -p "$1/tests/many"
  for ((i = 0; i < 3000; i++)); do printf -v n 'f%04d' "$i"; printf 'x\n' > "$1/tests/many/${n}_${pad}.test.js"; done
}
# a small stack limit means a small argument limit on Linux (Git Bash on Windows has a small one anyway)
SMALLSTACK='ulimit -s 160 2>/dev/null; exec "$@"'
if can_exec; then
  prep default; mkmany "$R"
  # the precondition: the platform really refuses this many arguments (else no fix is needed and the case cannot fail)
  if ! ( cd "$R" && ulimit -s 160 2>/dev/null; git ls-files -- tests/many/* >/dev/null 2>&1 ); then
    run_in "$R" bash -c "$SMALLSTACK" x bash "$STEP" red --message "m" --commit -- sh -c "$(hookcmd "$HK_CONTENT")"
    assert_rc "AC1 many judged paths (default): a hook rewrites a judged file: exit 1" 1
    assert_contains "AC1 many judged paths (default): says nothing committed" "$(lower "$OUT")" "nothing committed"
    assert_untouched "AC1 many judged paths (default): the commit is undone" "$R" "$H0" "$N0"
    assert_eq "AC1 many judged paths (default): no test(red) commit in the log" "" "$(no_red_commit)"
    assert_eq "AC1 many judged paths (default): the rewritten file is not in any commit" "" "$(git -C "$R" log --all --format=%H -- tests/n.test.js)"
    prep baseline; mkmany "$R"
    run_in "$R" bash -c "$SMALLSTACK" x bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c "$(hookcmd "$HK_CONTENT")"
    RCOK="no ($RC)"; if [ "$RC" = 1 ] || [ "$RC" = 3 ]; then RCOK=yes; fi
    assert_eq "AC1 many judged paths (--baseline): refused (exit 1 or 3), not committed" "yes" "$RCOK"
    assert_untouched "AC1 many judged paths (--baseline): nothing committed" "$R" "$H0" "$N0"
    assert_eq "AC1 many judged paths (--baseline): no test(red) commit in the log" "" "$(no_red_commit)"
    assert_eq "AC1 many judged paths (--baseline): the rewritten file is not in any commit" "" "$(git -C "$R" log --all --format=%H -- tests/n.test.js)"
  else
    t_skip 9 "AC1 many judged paths (this platform does not refuse 3000 long arguments under a small stack limit)"
  fi
else
  t_skip 9 "AC1 many judged paths (the file system cannot make a hook executable)"
fi

# ---------------------------------------------------------------------------------------------------------------
echo "AC4 fix round 1: a post-commit hook replaces HEAD by a merge commit (first parent = the pre-run HEAD) that adds src/evil.js"
HK_MERGE="$(mkhook merge 'touch .git/mg-done' 'pre=$(git rev-parse HEAD^)' 'cur=$(git rev-parse HEAD)' 'blob=$(echo evil | git hash-object -w --stdin)' \
  'GIT_INDEX_FILE=.git/mg.idx git read-tree HEAD' 'GIT_INDEX_FILE=.git/mg.idx git update-index --add --cacheinfo "100644,$blob,src/evil.js"' \
  't=$(GIT_INDEX_FILE=.git/mg.idx git write-tree)' 'c=$(git commit-tree "$t" -p "$pre" -p "$cur" -m merged)' 'git update-ref HEAD "$c"')"
if can_exec; then
  for MODE in default baseline; do
    prep "$MODE"
    run_red --commit sh -c "$(hookcmd "$HK_MERGE" post-commit)"
    assert_contains "AC4 merge commit on the pre-run HEAD ($MODE): the run reached git commit (the post-commit hook ran)" "$(ls "$R/.git")" "mg-done"
    assert_rc "AC4 merge commit on the pre-run HEAD ($MODE): exit 1" 1
    assert_contains "AC4 merge commit on the pre-run HEAD ($MODE): says nothing committed" "$(lower "$OUT")" "nothing committed"
    assert_eq "AC4 merge commit on the pre-run HEAD ($MODE): HEAD is the HEAD from before tdd-step" "$H0" "$(head_of "$R")"
    assert_eq "AC4 merge commit on the pre-run HEAD ($MODE): commit count unchanged" "$N0" "$(count_of "$R")"
    assert_eq "AC4 merge commit on the pre-run HEAD ($MODE): src/evil.js is not in HEAD" "" "$(noeol_ls "$R" | grep -x 'src/evil.js')"
    assert_contains "AC4 merge commit on the pre-run HEAD ($MODE): the refusal names src/evil.js" "$OUT" "src/evil.js"
  done
else
  t_skip 14 "AC4 merge commit by a post-commit hook (the file system cannot make a hook executable)"
fi

# ---------------------------------------------------------------------------------------------------------------
echo "AC2/AC3 fix round 1: the second gate fails alone, or HEAD moves with an unchanged manifest (default path, both commit modes)"
# second_gate_case FLAG -> 6 assertions: the test command changes the global conf test_path_regex (outside the work tree: the snapshot is unchanged) so that the role gate fails
second_gate_case() {
  local flag="$1" conf="$PLAYBOOK_HOME/.agents/playbook.conf"
  prep default
  run_red "$flag" sh -c "mkdir -p \"\$(dirname \"$conf\")\"; printf '%s\n' 'test_path_regex=^never-matches/' > \"$conf\"; exit 1"
  rm -f "$conf"
  refusal_checks "AC2/3 the second gate fails while the snapshot is unchanged (default, ${flag:-print})" "$flag" "init" "$N0"
}
for FLAG in --commit ""; do
  second_gate_case "$FLAG"
  refuse_moved "AC2/3 the test command makes an empty commit (manifest unchanged)" default "$FLAG" "git commit -q --allow-empty -m x; exit 1"
done

t_summary
