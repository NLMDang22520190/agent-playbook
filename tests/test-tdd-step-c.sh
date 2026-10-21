#!/usr/bin/env bash
# Tests for scripts/tdd-step.sh (AC3): the last part of test-tdd-step.sh (split in v0.24.21 so that it is not the floor of a CI shard), from
# "AC4 (fix 5) a git hook cannot smuggle an unjudged file into the commit" to the end (the hook and undo sections). Shared setup: tdd-step-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/tdd-step-fixture.sh"

# ---------------------------------------------------------------------------------------------------------------
# v0.24.21 lane G, fix round 1 (review findings)
# ---------------------------------------------------------------------------------------------------------------

echo "AC4 (fix 1) --baseline: the gate runs again after the test command (a corrupted manifest refuses the commit)"
R="$(fresh)"; dirty "$R"; BL="$(snap "$R")"; H0="$(head_of "$R")"; N0="$(count_of "$R")"
printf 'test("n", () => {});\n' > "$R/tests/new.test.js"
run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c "echo garbage > '$BL'; exit 1"
assert_rc "AC4 fix1 the test command corrupts the manifest: exit 1" 1
assert_untouched "AC4 fix1 the test command corrupts the manifest: nothing committed" "$R" "$H0" "$N0"
assert_not_contains "AC4 fix1 the test command corrupts the manifest: no RED= line" "$OUT" "RED="
assert_file "AC4 fix1 the test command corrupts the manifest: the role file stays in the work tree" "$R/tests/new.test.js"
# a clean start: the first gate reports no unchanged paths, so only the post-test gate verdict can refuse
R="$(fresh)"; BL="$(snap "$R")"; H0="$(head_of "$R")"; N0="$(count_of "$R")"
printf 'test("n", () => {});\n' > "$R/tests/new.test.js"
run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c "echo garbage > '$BL'; exit 1"
assert_rc "AC4 fix1 clean start, the test command corrupts the manifest: exit 1" 1
assert_untouched "AC4 fix1 clean start, the test command corrupts the manifest: nothing committed" "$R" "$H0" "$N0"

echo "AC4 (fix 1) --baseline: the unchanged-since-baseline notes must equal before and after the test command"
R="$(fresh)"; printf 'baseline edit\n' >> "$R/tests/app.test.js"; BL="$(snap "$R")"; H0="$(head_of "$R")"; N0="$(count_of "$R")"
printf 'test("n", () => {});\n' > "$R/tests/n.test.js"
run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c "grep -vF tests/app.test.js '$BL' > '$BL.new'; mv '$BL.new' '$BL'; exit 1"
assert_rc "AC4 fix1 the test command drops a manifest line: exit 1" 1
assert_contains "AC4 fix1 the test command drops a manifest line: says nothing committed" "$(lower "$OUT")" "nothing committed"
assert_untouched "AC4 fix1 the test command drops a manifest line: nothing committed" "$R" "$H0" "$N0"
assert_eq "AC4 fix1 the test command drops a manifest line: the baseline test file is not committed" "" "$(noeol_ls "$R" | grep -x 'tests/n.test.js')"
assert_contains "AC4 fix1 the test command drops a manifest line: the baseline edit is still in the work tree" "$(git -C "$R" status --porcelain)" " M tests/app.test.js"

echo "AC4 (fix 2) --baseline --commit: a newline in a role path is refused like other control characters"
if can_nl; then
  R="$(fresh)"; dirty "$R"; BL="$(snap "$R")"; H0="$(head_of "$R")"; N0="$(count_of "$R")"
  printf 'test("n", () => {});\n' > "$R/tests/ok.test.js"
  printf 'test("n", () => {});\n' > "$R/tests/nl"$'\n'"x.test.js"
  BS0="$(bstate "$R")"
  run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c 'exit 1'
  assert_rc "AC4 fix2 newline in a path: exit 1" 1
  assert_contains "AC4 fix2 newline in a path: tells the user to commit by hand" "$(lower "$OUT")" "by hand"
  assert_untouched "AC4 fix2 newline in a path: nothing committed" "$R" "$H0" "$N0"
  assert_eq "AC4 fix2 newline in a path: baseline paths untouched" "$BS0" "$(bstate "$R")"
else
  t_skip 5 "AC4 fix2 newline in a path (the file system refuses a newline in a name)"
fi

echo "AC4 (fix 3) --baseline with an empty value is a usage error"
R="$(fresh)"; H0="$(head_of "$R")"; N0="$(count_of "$R")"
printf 'test("n", () => {});\n' > "$R/tests/new.test.js"
run_in "$R" bash "$STEP" red --message "m" --baseline "" -- sh -c 'exit 1'
assert_rc "AC4 fix3 red --baseline \"\" -> exit 2" 2
run_in "$R" bash "$STEP" red --message "m" --commit --baseline "" -- sh -c 'exit 1'
assert_rc "AC4 fix3 red --commit --baseline \"\" -> exit 2" 2
assert_untouched "AC4 fix3 --baseline \"\": nothing committed" "$R" "$H0" "$N0"

echo "AC4 (fix 4) --baseline: the first gate's output passes through"
R="$(fresh)"; dirty "$R"; BL="$(snap "$R")"
printf 'test("n", () => {});\n' > "$R/tests/new.test.js"
run_in "$R" bash "$STEP" red --message "m" --baseline "$BL" -- sh -c 'exit 1'
assert_contains "AC4 fix4 red --baseline: the baseline note line (2 paths, digest) is printed" "$OUT" "note: baseline $BL (2 path(s), digest "
assert_contains "AC4 fix4 red --baseline: the unchanged note for src/app.js is printed" "$OUT" "note: unchanged since the baseline: src/app.js"
assert_contains "AC4 fix4 red --baseline: the unchanged note for README.md is printed" "$OUT" "note: unchanged since the baseline: README.md"
run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c 'exit 1'
assert_contains "AC4 fix4 red --baseline --commit: the baseline note line is printed" "$OUT" "note: baseline $BL (2 path(s), digest "
assert_contains "AC4 fix4 red --baseline --commit: the unchanged note is printed" "$OUT" "note: unchanged since the baseline: src/app.js"
R="$(fresh)"; dirty "$R"; BL="$(snap "$R")"; BASE="$(head_of "$R")"
printf 'module.exports = 3;\n' > "$R/src/impl.js"
run_in "$R" bash "$STEP" green --base "$BASE" --message "m" --baseline "$BL" -- true
assert_contains "AC4 fix4 green --baseline: the baseline note line is printed" "$OUT" "note: baseline $BL (2 path(s), digest "
assert_contains "AC4 fix4 green --baseline: the unchanged note is printed" "$OUT" "note: unchanged since the baseline: README.md"

echo "AC4 (fix 5) a git hook cannot smuggle an unjudged file into the commit"
# idxq REPO -> the whole index plus the status lines, minus the untracked file the test hooks create (src/evil.js)
idxq() { git -C "$1" ls-files -s; git -C "$1" status --porcelain | grep -v -x "?? src/evil.js"; true; }
# evil_untracked REPO -> the status of src/evil.js (the hook-written file stays in the work tree, untracked)
evil_untracked() { git -C "$1" status --porcelain -- src/evil.js; }
HS="$(mk_tmp)/hook-evil.sh"
printf '%s\n' '#!/bin/sh' 'mkdir -p src' 'echo evil > src/evil.js' 'git add src/evil.js' > "$HS"
HT="$(mk_tmp)/hook-true.sh"
printf '%s\n' '#!/bin/sh' 'true' > "$HT"
INSTALL_EVIL="cp '$HS' .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit; exit 1"
INSTALL_TRUE="cp '$HT' .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit; exit 1"
if can_exec; then
  R="$(fresh)"; H0="$(head_of "$R")"; N0="$(count_of "$R")"
  printf 'test("n", () => {});\n' > "$R/tests/new.test.js"
  IDX0="$(idxq "$R")"
  run_in "$R" bash "$STEP" red --message "m" --commit -- sh -c "$INSTALL_EVIL"
  assert_rc "AC4 fix5 default path, hook adds src/evil.js: exit 1" 1
  assert_contains "AC4 fix5 default path: the message names the unexpected committed path" "$OUT" "src/evil.js"
  assert_untouched "AC4 fix5 default path: the commit is undone (HEAD unchanged)" "$R" "$H0" "$N0"
  assert_eq "AC4 r3 fix5 default path: the index (every entry) and the status lines equal the pre-run ones after the undo" "$IDX0" "$(idxq "$R")"
  assert_eq "AC4 r3 fix5 default path: src/evil.js is untracked (the hook-written file stays in the work tree)" "?? src/evil.js" "$(evil_untracked "$R")"
  assert_eq "AC4 fix5 default path: src/evil.js is in no commit" "" "$(noeol_ls "$R" | grep -x 'src/evil.js')"
  assert_eq "AC4 fix5 default path: the role's work tree content is kept" 'test("n", () => {});' "$(cat "$R/tests/new.test.js")"

  R="$(fresh)"; dirty "$R"; BL="$(snap "$R")"; H0="$(head_of "$R")"; N0="$(count_of "$R")"
  printf 'test("n", () => {});\n' > "$R/tests/new.test.js"
  IDX0="$(idxq "$R")"
  run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c "$INSTALL_EVIL"
  assert_rc "AC4 fix5 --baseline, hook adds src/evil.js: exit 1" 1
  assert_contains "AC4 fix5 --baseline: the message names the unexpected committed path" "$OUT" "src/evil.js"
  assert_untouched "AC4 fix5 --baseline: the commit is undone (HEAD unchanged)" "$R" "$H0" "$N0"
  assert_eq "AC4 r3 fix5 --baseline: the index (every entry) and the status lines equal the pre-run ones after the undo" "$IDX0" "$(idxq "$R")"
  assert_eq "AC4 r3 fix5 --baseline: src/evil.js is untracked (the hook-written file stays in the work tree)" "?? src/evil.js" "$(evil_untracked "$R")"
  assert_eq "AC4 fix5 --baseline: src/evil.js is in no commit" "" "$(noeol_ls "$R" | grep -x 'src/evil.js')"
  assert_eq "AC4 fix5 --baseline: the role's work tree content is kept" 'test("n", () => {});' "$(cat "$R/tests/new.test.js")"
  assert_eq "AC4 fix5 --baseline: the baseline work tree file is kept" "module.exports = 9;" "$(cat "$R/src/app.js")"

  R="$(fresh)"; N0="$(count_of "$R")"
  printf 'test("n", () => {});\n' > "$R/tests/new.test.js"
  run_in "$R" bash "$STEP" red --message "m" --commit -- sh -c "$INSTALL_TRUE"
  assert_rc "AC4 fix5 control, a harmless hook (default path): exit 0" 0
  assert_eq "AC4 fix5 control (default path): one new commit" "$((N0 + 1))" "$(count_of "$R")"
  assert_contains "AC4 fix5 control (default path): the test file is committed" "$(committed "$R")" "tests/new.test.js"

  R="$(fresh)"; dirty "$R"; BL="$(snap "$R")"; N0="$(count_of "$R")"
  printf 'test("n", () => {});\n' > "$R/tests/new.test.js"
  run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c "$INSTALL_TRUE"
  assert_rc "AC4 fix5 control, a harmless hook (--baseline): exit 0" 0
  assert_eq "AC4 fix5 control (--baseline): one new commit" "$((N0 + 1))" "$(count_of "$R")"
  assert_eq "AC4 fix5 control (--baseline): only the role's file is committed" "tests/new.test.js" "$(committed "$R")"
else
  t_skip 21 "AC4 fix5 git hooks (the file system cannot make a hook executable)"
fi


echo "AC4 (fix r2) the undo restores the index exactly; a hook that makes a second commit is fully undone"
# idx REPO -> the whole index (mode, blob, stage, path), plus the porcelain status
idx() { git -C "$1" ls-files -s; git -C "$1" status --porcelain; }
HADD="$(mk_tmp)/hook-addreadme.sh"
printf "%s\n" "#!/bin/sh" "git add README.md" > "$HADD"
HPC="$(mk_tmp)/hook-postcommit.sh"
printf "%s\n" "#!/bin/sh" "[ -e .git/pc-done ] && exit 0" "touch .git/pc-done" "mkdir -p src" "echo evil > src/evil.js" "git add src/evil.js" "git commit -q -m evil-second" > "$HPC"
INSTALL_ADD="cp \"$HADD\" .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit; exit 1"
INSTALL_PC="cp \"$HPC\" .git/hooks/post-commit && chmod +x .git/hooks/post-commit; exit 1"
if can_exec; then
  R="$(fresh)"; dirty "$R"; BL="$(snap "$R")"
  printf "test(\"n\", () => {});\n" > "$R/tests/n.test.js"
  H0="$(head_of "$R")"; N0="$(count_of "$R")"; IDX0="$(idx "$R")"; BS0="$(bstate "$R")"
  run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c "$INSTALL_ADD"
  assert_rc "AC4 r2 --baseline, a pre-commit hook stages README.md: exit 1" 1
  assert_untouched "AC4 r2 --baseline, hook stages README.md: the commit is undone" "$R" "$H0" "$N0"
  assert_eq "AC4 r2 --baseline, hook stages README.md: the whole index equals the pre-run index" "$IDX0" "$(idx "$R")"
  assert_contains "AC4 r2 --baseline, hook stages README.md: README.md is staged and edited again (MM)" "$(git -C "$R" status --porcelain)" "MM README.md"
  assert_eq "AC4 r2 --baseline, hook stages README.md: baseline paths untouched (staged blob, diffs, content)" "$BS0" "$(bstate "$R")"
  assert_eq "AC4 r2 --baseline, hook stages README.md: the role file is kept" "test(\"n\", () => {});" "$(cat "$R/tests/n.test.js")"

  R="$(fresh)"
  printf "test(\"n\", () => {});\n" > "$R/tests/new.test.js"
  H0="$(head_of "$R")"; N0="$(count_of "$R")"; IDX0="$(idxq "$R")"
  run_in "$R" bash "$STEP" red --message "m" --commit -- sh -c "cp \"$HS\" .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit; exit 1"
  assert_rc "AC4 r2 default path, a hook adds an extra file: exit 1" 1
  assert_untouched "AC4 r2 default path, extra file: the commit is undone" "$R" "$H0" "$N0"
  assert_eq "AC4 r3 default path, extra file: the whole index and the status lines equal the pre-run ones" "$IDX0" "$(idxq "$R")"
  assert_eq "AC4 r3 default path, extra file: src/evil.js is untracked" "?? src/evil.js" "$(evil_untracked "$R")"
  assert_eq "AC4 r2 default path, extra file: the role file is kept" "test(\"n\", () => {});" "$(cat "$R/tests/new.test.js")"

  for MODE in default baseline; do
    R="$(fresh)"; BL=""
    # default path: a clean tree (a dirty one fails the tester gate before any commit); --baseline: pre-existing changes recorded in the baseline
    [ "$MODE" = default ] || { dirty "$R"; BL="$(snap "$R")"; }
    printf "test(\"n\", () => {});\n" > "$R/tests/n.test.js"
    H0="$(head_of "$R")"; N0="$(count_of "$R")"; IDX0="$(idxq "$R")"
    if [ "$MODE" = default ]; then
      run_in "$R" bash "$STEP" red --message "m" --commit -- sh -c "$INSTALL_PC"
    else
      run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c "$INSTALL_PC"
    fi
    assert_rc "AC4 r2 $MODE, a post-commit hook makes a second commit: exit 1" 1
    assert_eq "AC4 r2 $MODE, post-commit second commit: HEAD is the HEAD from before tdd-step" "$H0" "$(head_of "$R")"
    assert_eq "AC4 r2 $MODE, post-commit second commit: commit count is the pre-run count" "$N0" "$(count_of "$R")"
    assert_eq "AC4 r2 $MODE, post-commit second commit: no test(red) commit is left in the log" "" "$(git -C "$R" log --format=%s | grep -F "test(red)")"
    assert_eq "AC4 r2 $MODE, post-commit second commit: no evil-second commit is left in the log" "" "$(git -C "$R" log --format=%s | grep -F "evil-second")"
    assert_contains "AC4 r3 $MODE, post-commit second commit: the run reached git commit (the post-commit hook ran)" "$(ls "$R/.git")" "pc-done"
    assert_eq "AC4 r3 $MODE, post-commit second commit: the index (every entry) and the status lines equal the pre-run ones" "$IDX0" "$(idxq "$R")"
    assert_eq "AC4 r3 $MODE, post-commit second commit: src/evil.js is untracked" "?? src/evil.js" "$(evil_untracked "$R")"
    assert_eq "AC4 r2 $MODE, post-commit second commit: the role content is kept" "test(\"n\", () => {});" "$(cat "$R/tests/n.test.js")"
  done
else
  t_skip 26 "AC4 r2 hook cases (the file system cannot make a hook executable)"
fi

echo "AC4 (fix r3) a hook that puts a same-tree commit on top is caught by the parent check, not by the path check"
# pre-commit adds src/evil.js to the commit; post-commit stacks an empty-diff commit (same tree) on top, so the top commit lists no path
HPT="$(mk_tmp)/hook-pre-evil.sh"
printf "%s\n" "#!/bin/sh" "mkdir -p src" "echo evil > src/evil.js" "git add src/evil.js" > "$HPT"
HST="$(mk_tmp)/hook-sametree.sh"
printf "%s\n" "#!/bin/sh" "touch .git/st-done" "t=\$(git rev-parse HEAD^{tree})" "c=\$(git commit-tree \"\$t\" -p HEAD -m sametree)" "git update-ref HEAD \"\$c\"" > "$HST"
INSTALL_ST="cp \"$HPT\" .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit && cp \"$HST\" .git/hooks/post-commit && chmod +x .git/hooks/post-commit; exit 1"
if can_exec; then
  for MODE in default baseline; do
    R="$(fresh)"; BL=""
    [ "$MODE" = default ] || { dirty "$R"; BL="$(snap "$R")"; }
    printf "test(\"n\", () => {});\n" > "$R/tests/n.test.js"
    H0="$(head_of "$R")"
    if [ "$MODE" = default ]; then
      run_in "$R" bash "$STEP" red --message "m" --commit -- sh -c "$INSTALL_ST"
    else
      run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c "$INSTALL_ST"
    fi
    assert_rc "AC4 r3 $MODE, same-tree commit on top (empty diff): exit 1" 1
    assert_contains "AC4 r3 $MODE, same-tree commit on top: the run reached git commit (the post-commit hook ran)" "$(ls "$R/.git")" "st-done"
    assert_eq "AC4 r3 $MODE, same-tree commit on top: HEAD is the HEAD from before tdd-step" "$H0" "$(head_of "$R")"
    assert_eq "AC4 r3 $MODE, same-tree commit on top: src/evil.js is not in HEAD tree" "" "$(noeol_ls "$R" | grep -x "src/evil.js")"
    assert_eq "AC4 r3 $MODE, same-tree commit on top: no test(red) commit is left in the log" "" "$(git -C "$R" log --format=%s | grep -F "test(red)")"
    assert_eq "AC4 r3 $MODE, same-tree commit on top: no sametree commit is left in the log" "" "$(git -C "$R" log --format=%s | grep -F "sametree")"
  done
else
  t_skip 12 "AC4 r3 same-tree hook cases (the file system cannot make a hook executable)"
fi


t_summary
