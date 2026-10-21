#!/usr/bin/env bash
# Tests for scripts/tdd-step.sh (v0.24.22 lane T, Full), part 1 of 2 (the rest: test-tdd-step-e.sh): the commit gaps left open by v0.24.21, split from test-tdd-step-c.sh so that no suite is the floor of a
# CI shard (a new suite needs a tests/shard-weights line, L-0009). Shared setup: tdd-step-fixture.sh.
#   AC1  the committed entry of every judged path equals the entry that was judged (hook rewrites content, mode, a deletion, a gitlink)
#   AC2  default path (no --baseline): the test command may not write, edit or commit anything; the role gate runs again
#   AC3  print mode (no --commit): the same checks run before the commands are printed
#   AC4  the refusal for a moved HEAD names the unexpected paths (same-tree case) or says that HEAD was moved (also a merge commit on the pre-run HEAD)
#   fix round 1: a judged list over the argument limit, a merge commit by a hook, core.autocrlf stderr, the second gate alone, HEAD moved with an unchanged manifest
# Cases that already pass on v0.24.21 are characterizations (no false positive, unchanged output); they are named "control" or "unchanged".
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/tdd-step-fixture.sh"
. "$(dirname "$0")/tdd-step-d-fixture.sh"

# ---------------------------------------------------------------------------------------------------------------
echo "AC1 a pre-commit hook cannot change what is committed for a judged path (both commit paths)"
# 9 refused runs x 8 assertions, 5 control runs x 3 assertions
HK_CONTENT="$(mkhook content "printf 'changed by the hook\\n' > tests/n.test.js" 'git add tests/n.test.js')"
HK_MODE="$(mkhook mode 'git update-index --chmod=+x tests/n.test.js')"
HK_RESTORE="$(mkhook restore 'git show HEAD:tests/app.test.js > tests/app.test.js' 'git add tests/app.test.js')"
HK_GITLINK="$(mkhook gitlink 'git update-index --add --cacheinfo 160000,$(git rev-parse HEAD),tests/n.test.js')"
HK_READD="$(mkhook readd 'git add -- tests/n.test.js')"
HK_ADDU="$(mkhook addu 'git add -u')"
HK_NOOP="$(mkhook noop 'true')"
if can_exec; then
  for MODE in default baseline; do
    hook_refused "$MODE" "AC1 a hook rewrites the content of a judged file" "$HK_CONTENT" "tests/n.test.js"
    hook_refused "$MODE" "AC1 a hook changes only the mode of a judged file" "$HK_MODE" "tests/n.test.js"
    hook_refused "$MODE" "AC1 a hook re-adds a judged deletion" "$HK_RESTORE" "tests/app.test.js" "rm tests/app.test.js"
    hook_refused "$MODE" "AC1 a hook replaces a judged file by a gitlink" "$HK_GITLINK" "tests/n.test.js"
  done
  # on --baseline git add -u in the hook stages the dirty baseline paths (README.md, src/app.js) into the commit: refused (as in v0.24.21: an unjudged path)
  hook_refused baseline "AC1 control: git add -u stages the dirty baseline paths" "$HK_ADDU" ""
  for MODE in default baseline; do
    hook_ok "$MODE" "AC1 control: a hook re-adds a judged path with unchanged content" "$HK_READD" "tests/n.test.js"
    hook_ok "$MODE" "AC1 control: a no-op hook" "$HK_NOOP" "tests/n.test.js"
  done
  hook_ok default "AC1 control: git add -u in the hook (default path)" "$HK_ADDU" "tests/app.test.js"$'\n'"tests/n.test.js" "printf 'more\\n' >> tests/app.test.js"
else
  t_skip 87 "AC1 hook cases (the file system cannot make a hook executable)"
fi

echo "AC1 --baseline with core.filemode=false: a script staged +x is committed 100644 and is not refused (a known separate gap, queued)"
R="$(fresh)"; ( cd "$R" && git config core.filemode false ); dirty "$R"; BL="$(snap "$R")"; N0="$(count_of "$R")"
printf '#!/bin/sh\nexit 1\n' > "$R/tests/run.test.sh"
( cd "$R" && git add tests/run.test.sh && git update-index --chmod=+x tests/run.test.sh )
run_in "$R" bash "$STEP" red --message "m" --commit --baseline "$BL" -- sh -c 'exit 1'
assert_rc "AC1 filemode=false --baseline: exit 0 (not refused)" 0
assert_eq "AC1 filemode=false --baseline: one new commit" "$((N0 + 1))" "$(count_of "$R")"
assert_eq "AC1 filemode=false --baseline: the script is committed as 100644 (the +x drop is the known gap)" "100644" "$(git -C "$R" ls-tree HEAD -- tests/run.test.sh | cut -d' ' -f1)"

# ---------------------------------------------------------------------------------------------------------------
echo "AC2 default path: the test command may not write, edit or commit anything that is not ignored"
for FLAG in --commit ""; do
  refuse_case "AC2 the test command writes an untracked file" default "$FLAG" "printf 'x\\n' > tests/extra.test.js; exit 1"
  refuse_case "AC2 the test command edits a tracked file" default "$FLAG" "echo more >> tests/app.test.js; exit 1"
  refuse_case "AC2 the test command writes tests/__snapshots__x.snap" default "$FLAG" "echo s > tests/__snapshots__x.snap; exit 1"
  refuse_moved "AC2 the test command commits the role's file" default "$FLAG" "git add tests/n.test.js && git commit -q -m x -- tests/n.test.js; exit 1"
done

echo "AC2 default path green --commit: the test command writes src/gen.js, nothing is committed (not even the implementer's file)"
R="$(fresh)"; BASE="$(head_of "$R")"; N0="$(count_of "$R")"
printf 'module.exports = 3;\n' > "$R/src/impl.js"
run_in "$R" bash "$STEP" green --base "$BASE" --message "m" --commit -- sh -c "mkdir -p src; echo gen > src/gen.js"
assert_rc "AC2 green, the test command writes src/gen.js: exit 1" 1
assert_contains "AC2 green, the test command writes src/gen.js: says nothing committed" "$(lower "$OUT")" "nothing committed"
assert_untouched "AC2 green, the test command writes src/gen.js: nothing committed" "$R" "$BASE" "$N0"
assert_eq "AC2 green, the test command writes src/gen.js: src/gen.js is in no commit" "" "$(noeol_ls "$R" | grep -x 'src/gen.js')"
assert_file "AC2 green, the test command writes src/gen.js: the role's file stays in the work tree" "$R/src/impl.js"

echo "AC2 control: a file the test command writes into an ignored directory is outside the snapshot"
R="$(fresh)"; N0="$(count_of "$R")"
printf 'out/\n' >> "$R/.git/info/exclude"
printf 'test("n", () => {});\n' > "$R/tests/n.test.js"
run_in "$R" bash "$STEP" red --message "m" --commit -- sh -c "mkdir -p out; echo o > out/o.txt; exit 1"
assert_rc "AC2 control: an ignored file written by the test command: exit 0" 0
assert_eq "AC2 control: one new commit" "$((N0 + 1))" "$(count_of "$R")"
assert_eq "AC2 control: only the role's file is committed" "tests/n.test.js" "$(committed "$R")"

# ---------------------------------------------------------------------------------------------------------------
echo "AC2/AC3 a normal RED or GREEN run prints and commits exactly what v0.24.21 did (old scripts from git archive f1d6bce)"
OLDD="$(mk_tmp)"
if git -C "$PB_ROOT" cat-file -e f1d6bce 2>/dev/null && git -C "$PB_ROOT" archive f1d6bce scripts 2>/dev/null | tar -x -C "$OLDD" 2>/dev/null && [ -f "$OLDD/scripts/tdd-step.sh" ]; then
  # same_as_old LABEL KIND MODE FLAG -> 4 assertions. KIND red|green, MODE default|baseline; fixed commit dates make equal runs give equal shas
  norm() { printf '%s' "$1" | sed -E "s/[0-9]{8}T[0-9]{6}Z/<ts>/g; s/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z/<time>/g"; }
  same_as_old() {
    local label="$1" kind="$2" mode="$3" flag="$4" a b ba bb oa ob ra rb
    export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"
    a="$(fresh)"; b="$(fresh)"; ba=""; bb=""
    if [ "$mode" = baseline ]; then dirty "$a"; dirty "$b"; ba="$(snap "$a")"; bb="$(snap "$b")"; fi
    local base; base="$(head_of "$a")"
    if [ "$kind" = red ]; then
      printf 'test("n", () => {});\n' > "$a/tests/n.test.js"; printf 'test("n", () => {});\n' > "$b/tests/n.test.js"
    else
      printf 'module.exports = 3;\n' > "$a/src/impl.js"; printf 'module.exports = 3;\n' > "$b/src/impl.js"
    fi
    local tc="exit 1"; [ "$kind" = red ] || tc="exit 0"
    if [ "$kind" = red ]; then
      run_in "$a" bash "$OLDD/scripts/tdd-step.sh" red --message "m" $flag ${ba:+--baseline "$ba"} -- sh -c "$tc"
    else
      run_in "$a" bash "$OLDD/scripts/tdd-step.sh" green --base "$base" --message "m" $flag ${ba:+--baseline "$ba"} -- sh -c "$tc"
    fi
    oa="$OUT"; ra="$RC"
    if [ "$kind" = red ]; then
      run_in "$b" bash "$STEP" red --message "m" $flag ${bb:+--baseline "$bb"} -- sh -c "$tc"
    else
      run_in "$b" bash "$STEP" green --base "$base" --message "m" $flag ${bb:+--baseline "$bb"} -- sh -c "$tc"
    fi
    ob="$OUT"; rb="$RC"
    unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE
    oa="${oa//$a/<R>}"; ob="${ob//$b/<R>}"
    if [ -n "$ba" ]; then oa="${oa//$ba/<BL>}"; ob="${ob//$bb/<BL>}"; fi
    assert_eq "$label: the old script passes (exit 0)" "0" "$ra"
    assert_eq "$label: same exit code" "$ra" "$rb"
    assert_eq "$label: byte-identical output" "$(norm "$oa")" "$(norm "$ob")"
    assert_eq "$label: same commit (sha)" "$(head_of "$a")" "$(head_of "$b")"
  }
  same_as_old "AC2 unchanged RED --commit (default path)" red default --commit
  same_as_old "AC2 unchanged GREEN --commit (default path)" green default --commit
  same_as_old "AC2 unchanged RED --commit (--baseline)" red baseline --commit
  same_as_old "AC3 unchanged RED, print mode (default path)" red default ""
  same_as_old "AC3 unchanged RED, print mode (--baseline)" red baseline ""
  # crlf_same_as_old LABEL KIND -> 5 assertions: with core.autocrlf=true and a tracked file edited with LF, stderr is the old script's byte for byte
  crlf_same_as_old() {
    local label="$1" kind="$2" a b r base ea eb ra rb sa sb
    export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"
    a="$(fresh)"; b="$(fresh)"
    for r in "$a" "$b"; do
      ( cd "$r" && git config core.autocrlf true )
      if [ "$kind" = red ]; then printf 'test("e", () => {});\n' >> "$r/tests/app.test.js"; else printf 'module.exports = 2;\n' > "$r/src/app.js"; fi
      # settle the fixture: every mtime clearly in the past, then refresh the index, so that no entry is racy (git re-reads a racy entry and warns again)
      ( cd "$r" && find . -path ./.git -prune -o -type f -exec touch -t 202001010000 {} + && { git update-index --refresh >/dev/null 2>&1 || true; } )
    done
    base="$(head_of "$a")"; ea="$(mk_tmp)/err"; eb="$(mk_tmp)/err"
    if [ "$kind" = red ]; then
      ( cd "$a" && bash "$OLDD/scripts/tdd-step.sh" red --message "m" --commit -- sh -c "exit 1" 2> "$ea" >/dev/null ); ra=$?
      ( cd "$b" && bash "$STEP" red --message "m" --commit -- sh -c "exit 1" 2> "$eb" >/dev/null ); rb=$?
    else
      ( cd "$a" && bash "$OLDD/scripts/tdd-step.sh" green --base "$base" --message "m" --commit -- sh -c "exit 0" 2> "$ea" >/dev/null ); ra=$?
      ( cd "$b" && bash "$STEP" green --base "$base" --message "m" --commit -- sh -c "exit 0" 2> "$eb" >/dev/null ); rb=$?
    fi
    unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE
    sa="$(cat "$ea")"; sb="$(cat "$eb")"; sa="${sa//$a/<R>}"; sb="${sb//$b/<R>}"
    assert_eq "$label: the old script passes (exit 0)" "0" "$ra"
    assert_contains "$label: the old script warns about the line endings (the fixture works)" "$sa" "LF will be replaced by CRLF"
    assert_eq "$label: same exit code" "$ra" "$rb"
    # byte for byte, as before: the fixture is settled (no racy index entry), so the number of repeated warnings is the same in every run of one script (4 lines, 6 of 6 probes);
    # an unsettled fixture made the OLD script itself print 4 or 6 lines, which made this assertion flaky (about 1 run in 3)
    assert_eq "$label: byte-identical stderr" "$(norm "$sa")" "$(norm "$sb")"
    assert_eq "$label: same commit (sha)" "$(head_of "$a")" "$(head_of "$b")"
  }
  crlf_same_as_old "AC2 core.autocrlf=true: RED --commit (default path)" red
  crlf_same_as_old "AC2 core.autocrlf=true: GREEN --commit (default path)" green
else
  t_skip 30 "AC2/AC3 comparison with the v0.24.21 scripts (commit f1d6bce is not in this clone)"
fi

t_summary
