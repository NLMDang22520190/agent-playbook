#!/usr/bin/env bash
# Tests for scripts/tdd-step.sh (v0.24.22 lane T, Full), part 3 of 3 (parts 1 and 2: test-tdd-step-d.sh, test-tdd-step-e.sh): the comparison with the v0.24.21 scripts (from suite d, the last section)
# and the first half of suite e (from "AC3 print mode: a passing run..." to AC4), so that d, e and f take about the same time (L-0009). Shared setup: tdd-step-fixture.sh and tdd-step-d-fixture.sh.
# Same AC ids and fix-round names as part 1.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/tdd-step-fixture.sh"
. "$(dirname "$0")/tdd-step-d-fixture.sh"

# ---------------------------------------------------------------------------------------------------------------
echo "AC2/AC3 path normalizer: each run's own path is replaced in every form it can appear (on Windows C:/... from pwd -W and cygpath -m)"
# unit check on any platform: pwd -W and cygpath are stubbed (and unset again below) so that Linux sees the forms Git Bash prints
NR="$(mk_tmp)"; NB="$(basename "$NR")"; NO="$(basename "$(mk_tmp)")"
pwd() { if [ "${1:-}" = "-W" ]; then printf 'D:/work/%s\n' "$(basename "$PWD")"; else builtin pwd "$@"; fi; }
cygpath() { printf 'C:/Users/x/AppData/Local/Temp/%s\n' "$(basename "$2")"; }
LOGP=".agents/handoff/evidence/20260101T000000Z-red.log"
S1="- full log: C:/Users/x/AppData/Local/Temp/$NB/$LOGP"
N1="$(repl_path "$S1" "<R>" "$NR")"
N2="$(repl_path "- full log: D:/work/$NB/$LOGP" "<R>" "$NR")"
N3="$(repl_path "- full log: $NR/$LOGP" "<R>" "$NR")"
N4="$(repl_path "a $NR b C:/Users/x/AppData/Local/Temp/$NB c D:/work/$NB d" "<R>" "$NR")"
SO="- full log: C:/Users/x/AppData/Local/Temp/$NO/$LOGP"
N5="$(repl_path "$SO" "<R>" "$NR")"
N6="$(repl_path "- full log: C:/Users/x/AppData/Local/Temp/$NB/${LOGP%-red.log}-green.log" "<R>" "$NR")"
N7="$(repl_path "$S1 extra" "<R>" "$NR")"
unset -f pwd cygpath
assert_eq "AC2/3 normalizer: the cygpath -m form (C:/...) becomes <R>" "- full log: <R>/$LOGP" "$N1"
assert_eq "AC2/3 normalizer: the pwd -W form becomes <R>" "- full log: <R>/$LOGP" "$N2"
assert_eq "AC2/3 normalizer: the \$PWD form becomes <R>" "- full log: <R>/$LOGP" "$N3"
assert_eq "AC2/3 normalizer: all three forms in one text" "a <R> b <R> c <R> d" "$N4"
assert_contains "AC2/3 normalizer: the old plain replacement left the C:/ form (the Windows failure)" "${S1//$NR/<R>}" "C:/Users/x"
assert_eq "AC2/3 normalizer: the path of another run is not replaced" "$SO" "$N5"
EQ=differ; [ "$N6" = "$N1" ] && EQ=same
assert_eq "AC2/3 normalizer: a different log name stays different" "differ" "$EQ"
EQ=differ; [ "$N7" = "$N1" ] && EQ=same
assert_eq "AC2/3 normalizer: an extra word stays different" "differ" "$EQ"

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
    oa="$(repl_path "$oa" "<R>" "$a")"; ob="$(repl_path "$ob" "<R>" "$b")"
    if [ -n "$ba" ]; then oa="$(repl_path "$oa" "<BL>" "$ba")"; ob="$(repl_path "$ob" "<BL>" "$bb")"; fi
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
    sa="$(cat "$ea")"; sb="$(cat "$eb")"; sa="$(repl_path "$sa" "<R>" "$a")"; sb="$(repl_path "$sb" "<R>" "$b")"
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

t_summary
