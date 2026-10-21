#!/usr/bin/env bash
# Tests for scripts/tdd-step.sh (v0.24.22 lane T, Full): the commit gaps left open by v0.24.21, split from test-tdd-step-c.sh so that no suite is the floor of a
# CI shard (a new suite needs a tests/shard-weights line, L-0009). Shared setup: tdd-step-fixture.sh.
#   AC1  the committed entry of every judged path equals the entry that was judged (hook rewrites content, mode, a deletion, a gitlink)
#   AC2  default path (no --baseline): the test command may not write, edit or commit anything; the role gate runs again
#   AC3  print mode (no --commit): the same checks run before the commands are printed
#   AC4  the refusal for a moved HEAD names the unexpected paths (same-tree case) or says that HEAD was moved (also a merge commit on the pre-run HEAD)
#   fix round 1: a judged list over the argument limit, a merge commit by a hook, core.autocrlf stderr, the second gate alone, HEAD moved with an unchanged manifest
# Cases that already pass on v0.24.21 are characterizations (no false positive, unchanged output); they are named "control" or "unchanged".
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/tdd-step-fixture.sh"

# ---------------------------------------------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------------------------------------------
# mkhook NAME LINES... -> path of a hook script (the lines after a #!/bin/sh line)
mkhook() { local f; f="$(mk_tmp)/$1.sh"; shift; { printf '%s\n' '#!/bin/sh'; printf '%s\n' "$@"; } > "$f"; printf '%s\n' "$f"; }
# hookcmd HOOK [NAME] -> a test command that installs HOOK as .git/hooks/NAME (default pre-commit) and fails (RED)
hookcmd() { printf '%s' "cp .git/index '$IDXF'; cp '$1' .git/hooks/${2:-pre-commit} && chmod +x .git/hooks/${2:-pre-commit}; exit 1"; }
# prep MODE -> R (fresh repo, tests/n.test.js untracked), BL (a baseline manifest for MODE baseline, else empty), H0, N0
prep() {
  R="$(fresh)"; BL=""
  if [ "$1" = baseline ]; then dirty "$R"; BL="$(snap "$R")"; fi
  printf 'test("n", () => {});\n' > "$R/tests/n.test.js"
  H0="$(head_of "$R")"; N0="$(count_of "$R")"; IDXF="$(mk_tmp)/index.copy"
}
# run_red FLAG CMD... -> tdd-step red in R (FLAG is --commit or empty; --baseline BL when set)
run_red() { local flag="$1"; shift; run_in "$R" bash "$STEP" red --message "m" $flag ${BL:+--baseline "$BL"} -- "$@"; }
# the index file of R is the same as IDXF, the copy the test command (hookcmd) takes right before tdd-step stages anything
same_idx() { if cmp -s "$IDXF" "$R/.git/index"; then echo same; else echo differ; fi; }
no_red_commit() { git -C "$R" log --format=%s | grep -F "test(red)"; true; }

# hook_refused MODE LABEL HOOK PATHJ [PRE] -> 8 assertions: a pre-commit hook changes what is committed; the commit is undone
hook_refused() {
  local mode="$1" label="$2" hook="$3" pj="$4" pre="${5:-}"
  prep "$mode"
  if [ -n "$pre" ]; then ( cd "$R" && eval "$pre" ); H0="$(head_of "$R")"; fi
  IDXF="$(mk_tmp)/index.copy"; local bs0; bs0="$(bstate "$R")"
  run_red --commit sh -c "$(hookcmd "$hook")"
  assert_rc "$label ($mode): exit 1" 1
  assert_contains "$label ($mode): says nothing committed" "$(lower "$OUT")" "nothing committed"
  if [ -n "$pj" ]; then
    assert_contains "$label ($mode): names the path that differs" "$OUT" "the commit differs from what was judged: $pj"
  else
    assert_contains "$label ($mode): names the dirty baseline path the hook staged" "$OUT" "README.md"
  fi
  assert_untouched "$label ($mode): the commit is undone" "$R" "$H0" "$N0"
  assert_eq "$label ($mode): the index file is restored byte for byte" "same" "$(same_idx)"
  assert_eq "$label ($mode): the baseline paths are untouched" "$bs0" "$(bstate "$R")"
  assert_eq "$label ($mode): no test(red) commit in the log" "" "$(no_red_commit)"
}
# hook_ok MODE LABEL HOOK EXPECTED [PRE] -> 3 assertions: a harmless hook does not refuse the commit
hook_ok() {
  local mode="$1" label="$2" hook="$3" want="$4" pre="${5:-}"
  prep "$mode"
  if [ -n "$pre" ]; then ( cd "$R" && eval "$pre" ); fi
  run_red --commit sh -c "$(hookcmd "$hook")"
  assert_rc "$label ($mode): exit 0" 0
  assert_eq "$label ($mode): one new commit" "$((N0 + 1))" "$(count_of "$R")"
  assert_eq "$label ($mode): the committed paths" "$want" "$(committed "$R")"
}
# refusal_checks LABEL FLAG WANT_SUBJECT WANT_COUNT -> 6 assertions about a refused step (R, OUT, RC from the run)
refusal_checks() {
  local label="$1" flag="$2" subj="$3" cnt="$4"
  assert_rc "$label: exit 1" 1
  assert_contains "$label: says nothing committed" "$(lower "$OUT")" "nothing committed"
  if [ -n "$flag" ]; then
    assert_not_contains "$label: no RED= line" "$OUT" "RED="
  else
    assert_not_contains "$label: the commit commands are not printed" "$OUT" "not committing (no --commit)"
  fi
  assert_eq "$label: HEAD is the commit from before tdd-step (or the test command's own)" "$subj" "$(subject "$R")"
  assert_eq "$label: commit count" "$cnt" "$(count_of "$R")"
  assert_eq "$label: no test(red) commit in the log" "" "$(no_red_commit)"
}
# refuse_case LABEL MODE FLAG TESTCMD -> 6 assertions: the test command changes the work tree, the step is refused
refuse_case() {
  local label="$1" mode="$2" flag="$3" cmd="$4"
  prep "$mode"
  run_red "$flag" sh -c "$cmd"
  refusal_checks "$label ($mode, ${flag:-print})" "$flag" "init" "$N0"
}
# refuse_moved LABEL MODE FLAG TESTCMD -> 6 assertions: the test command commits the role's file itself (subject x)
refuse_moved() {
  local label="$1" mode="$2" flag="$3" cmd="$4"
  prep "$mode"
  run_red "$flag" sh -c "$cmd"
  refusal_checks "$label ($mode, ${flag:-print})" "$flag" "x" "$((N0 + 1))"
}

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

# ---------------------------------------------------------------------------------------------------------------
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
