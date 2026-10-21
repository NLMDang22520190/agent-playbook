#!/usr/bin/env bash
# Tests for scripts/tdd-step.sh (v0.24.22 lane T, Full), part 2 of 3 (parts 1 and 3: test-tdd-step-d.sh, test-tdd-step-f.sh): the fix-round-1 cases of the old suite d (split so that no suite is the floor of a CI shard, L-0009):
# a judged list over the argument limit, a merge commit by a post-commit hook, the second gate alone and HEAD moved with an unchanged manifest. Shared setup: tdd-step-fixture.sh and tdd-step-d-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/tdd-step-fixture.sh"
. "$(dirname "$0")/tdd-step-d-fixture.sh"

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
