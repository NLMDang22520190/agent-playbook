#!/usr/bin/env bash
# Tests for the SKILL.md frontmatter checks in evals/run-checks.sh (AC5).
# Each test runs run-checks.sh inside a fresh copy of the repository (tracked + untracked,
# non-ignored files), so mutations never touch the real skills.
. "$(dirname "$0")/lib.sh"
SKILL=skills/playbook-proof/SKILL.md

# mk_copy -> prints a temp dir holding a copy of the working tree
mk_copy() {
  local d; d="$(mk_tmp)"
  ( cd "$PB_ROOT" &&
    git ls-files -co --exclude-standard | while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done |
    tar -cf - -T - ) | ( cd "$d" && tar -xf - )
  printf '%s\n' "$d"
}
# set_line DIR KEY LINE -> replace the first "KEY:" line of the frontmatter of $SKILL with LINE
set_line() {
  awk -v k="$2:" -v l="$3" 'NR<=10 && !done && index($0, k) == 1 { print l; done = 1; next } { print }' \
    "$1/$SKILL" > "$1/$SKILL.new" && mv "$1/$SKILL.new" "$1/$SKILL"
}
# add_line DIR LINE -> insert LINE as the second frontmatter line of $SKILL
add_line() {
  awk -v l="$2" 'NR == 2 { print l } { print }' "$1/$SKILL" > "$1/$SKILL.new" && mv "$1/$SKILL.new" "$1/$SKILL"
}
# checks DIR -> run run-checks.sh in DIR; OUT keeps only non-"ok" lines (FAIL, skip, summary) to keep failures readable
only_problems() { OUT="$(printf '%s\n' "$OUT" | grep -v '^  ok ')"; }
checks() { run bash "$1/evals/run-checks.sh"; only_problems; }
# mk_git_copy -> a copy of the working tree committed into a fresh git repo with LF in the index
mk_git_copy() {
  local d; d="$(mk_copy)"
  ( cd "$d" && git init -q && git config core.autocrlf false && git config user.email t@example.invalid &&
    git config user.name tester && git config commit.gpgsign false && git add -A && git commit -q -m copy ) >/dev/null 2>&1
  printf '%s\n' "$d"
}
to_crlf() { sed 's/$/\r/' "$1" > "$1.crlf" && mv "$1.crlf" "$1"; }

echo "frontmatter checks (AC5)"
C="$(mk_copy)"
checks "$C"
assert_rc "AC5 current skills pass run-checks (exit 0)" 0

C="$(mk_copy)"
set_line "$C" description 'description: Use when stating results. Note: keep it short.'
checks "$C"
assert_rc "AC5 unquoted description containing ': ' fails (exit 1)" 1
assert_contains "AC5 failure names the SKILL.md" "$OUT" "$SKILL"

C="$(mk_copy)"
set_line "$C" description 'description: "Use when stating results. Note: keep it short."'
checks "$C"
assert_rc "AC5 double-quoted description containing ': ' passes" 0

C="$(mk_copy)"
set_line "$C" description "description: 'Use when stating results. Note: keep it short.'"
checks "$C"
assert_rc "AC5 single-quoted description containing ': ' passes" 0

C="$(mk_copy)"
set_line "$C" description 'description: Use when stating results at a 1:2 ratio or more.'
checks "$C"
assert_rc "AC5 unquoted description with ':' not followed by a space passes" 0

if python3 -c 'import yaml' >/dev/null 2>&1; then
  C="$(mk_copy)"
  add_line "$C" 'metadata: [unclosed'
  checks "$C"
  assert_rc "AC5 frontmatter that PyYAML cannot parse fails (exit 1)" 1
  assert_contains "AC5 parse failure names the SKILL.md" "$OUT" "$SKILL"
else
  t_skip 2 "AC5 PyYAML parse test: python3 -c 'import yaml' failed"
fi

# Without PyYAML the parse check is skipped with a printed note, the rest still runs.
C="$(mk_copy)"
add_line "$C" 'metadata: [unclosed'
FAKE="$(mk_tmp)"
printf '#!/bin/sh\nexit 1\n' > "$FAKE/python3"; chmod +x "$FAKE/python3"
OUT="$(PATH="$FAKE:$PATH" bash "$C/evals/run-checks.sh" 2>&1)"; RC=$?; only_problems
assert_rc "AC5 without PyYAML the parse check does not fail the run" 0
SKIPLINE="$(printf '%s\n' "$OUT" | grep -i 'skip' | grep -i 'yaml')"
assert_contains "AC5 without PyYAML a skip note mentioning yaml is printed" "$(printf '%s' "$SKIPLINE" | tr 'A-Z' 'a-z')" "yaml"

# Without PyYAML the explicit unquoted ': ' check alone must still catch the bad description.
C="$(mk_copy)"
set_line "$C" description 'description: Use when stating results. Note: keep it short.'
OUT="$(PATH="$FAKE:$PATH" bash "$C/evals/run-checks.sh" 2>&1)"; RC=$?; only_problems
assert_rc "AC5 without PyYAML an unquoted description containing ': ' still fails (exit 1)" 1
assert_contains "AC5 without PyYAML the failure says unquoted" "$OUT" "unquoted"
assert_contains "AC5 without PyYAML the failure names the SKILL.md" "$OUT" "$SKILL"

echo "CRLF check judges what git stores (Windows checkouts convert to CRLF)"
C="$(mk_git_copy)"
to_crlf "$C/README.md"; to_crlf "$C/.gitattributes"
checks "$C"
assert_not_contains "CRLF only in the working tree of a tracked LF file is not a failure" "$OUT" "CRLF found"
# "* text=auto eol=lf" would normalise CRLF to LF on add, so override it for this file
# (-text) to really store CRLF in the index.
C="$(mk_git_copy)"
printf 'docs/crlf-note.md -text\n' >> "$C/.gitattributes"
printf 'line one\r\nline two\r\n' > "$C/docs/crlf-note.md"
( cd "$C" && git add .gitattributes docs/crlf-note.md && git commit -q -m crlf ) >/dev/null 2>&1
checks "$C"
assert_rc "CRLF stored in the git index fails" 1
assert_contains "the failure names the CRLF file" "$OUT" "docs/crlf-note.md"
C="$(mk_git_copy)"
printf 'untracked\r\n' > "$C/docs/untracked-crlf.md"
checks "$C"
assert_contains "an untracked CRLF file still fails" "$OUT" "docs/untracked-crlf.md"
C="$(mk_copy)"
printf 'no git here\r\n' > "$C/docs/plain-crlf.md"
checks "$C"
assert_contains "outside git, working-tree CRLF still fails" "$OUT" "docs/plain-crlf.md"

# when `cat` fails, the one-pass CR scan must fall back to the per-file check, not report "no CR"
C="$(mk_copy)"
printf 'no git here\r\n' > "$C/docs/catfail-crlf.md"
FB="$(mk_tmp)"; printf '#!/bin/sh\nexit 1\n' > "$FB/cat"; chmod +x "$FB/cat"
run env PATH="$FB:$PATH" bash "$C/evals/run-checks.sh"
assert_contains "CRLF file still reported when cat fails" "$(printf '%s\n' "$OUT" | grep 'CRLF found in:')" "docs/catfail-crlf.md"


echo "#12b quoted name matches its directory"
C="$(mk_copy)"
set_line "$C" name 'name: "playbook-proof"'
checks "$C"
assert_rc "AC12b.2 quoted name passes run-checks" 0
assert_not_contains "AC12b.2 no name-mismatch failure for a quoted name" "$OUT" "name '"

echo "v0.13.0 AC6.1 regex repeat bounds above 255 (BSD/macOS RE_DUP_MAX) are refused"
# The bound is built at run time: a literal one in this file would fail the real run-checks.
# bound_case NAME FILE BODY-LINE EXPECT(fail|pass) -> FILE (under the copy) gets BODY-LINE as its line 3
bound_case() {
  local name="$1" rel="$2" line="$3" expect="$4"
  C="$(mk_copy)"
  mkdir -p "$C/$(dirname "$rel")"
  printf '#!/usr/bin/env bash\n# fixture\n%s\n' "$line" > "$C/$rel"
  checks "$C"
  if [ "$expect" = fail ]; then
    assert_rc "AC6.1 $name: exit 1" 1
    assert_contains "AC6.1 $name: names file:line" "$OUT" "$rel:3"
  else
    assert_rc "AC6.1 $name: exit 0" 0
    assert_not_contains "AC6.1 $name: the file is not named" "$OUT" "$rel"
  fi
}
BIG=$((255 + 45)); EDGE=$((255 + 1)); TOP=255
bound_case "tests/ file, upper bound over the limit" tests/zz-bound.sh "grep -E 'a{0,${BIG}}' f" fail
bound_case "evals/ file, upper bound over the limit" evals/zz-bound.sh "grep -E 'a{0,${BIG}}' f" fail
bound_case "single bound over the limit" tests/zz-bound.sh "grep -E 'a{${BIG}}' f" fail
bound_case "just above the limit 256"  tests/zz-bound.sh "grep -E 'a{0,${EDGE}}' f" fail
bound_case "four-digit bound"          tests/zz-bound.sh "grep -E 'a{0,${TOP}0}' f" fail
bound_case "both numbers high"         tests/zz-bound.sh "grep -E 'a{${BIG},$((BIG + 100))}' f" fail
bound_case "exactly 255 passes"        tests/zz-bound.sh "grep -E 'a{0,${TOP}}' f" pass
bound_case "single {255} passes"       tests/zz-bound.sh "grep -E 'a{${TOP}}' f" pass
bound_case "small bounds pass"         tests/zz-bound.sh "grep -E 'a{1,100}b{3}' f" pass
bound_case "a bash brace list is not a bound" tests/zz-bound.sh "echo {1,2,3} {a,b}" pass

echo "v0.14.0 AC7.1 every shell script is scanned: scripts/, tools/, install.sh; and the {,n} form"
bound_case "scripts/ file, upper bound over the limit" scripts/zz-bound.sh "grep -E 'a{0,${BIG}}' f" fail
bound_case "scripts/ file, single bound over the limit" scripts/zz-bound.sh "grep -E 'a{${BIG}}' f" fail
bound_case "tools/ file, upper bound over the limit" tools/zz-bound.sh "grep -E 'a{0,${BIG}}' f" fail
bound_case "tools/ file, single bound over the limit" tools/zz-bound.sh "grep -E 'a{${BIG}}' f" fail
bound_case "install.sh, upper bound over the limit" install.sh "grep -E 'a{0,${BIG}}' f" fail
bound_case "install.sh, just above the limit 256" install.sh "grep -E 'a{0,${EDGE}}' f" fail
bound_case "{,n} form with n over the limit (tests/)" tests/zz-bound.sh "grep -E 'a{,${BIG}}' f" fail
bound_case "{,n} form with n over the limit (scripts/)" scripts/zz-bound.sh "grep -E 'a{,${BIG}}' f" fail
bound_case "{,n} form with n = 256" tests/zz-bound.sh "grep -E 'a{,${EDGE}}' f" fail
bound_case "{,255} passes" tests/zz-bound.sh "grep -E 'a{,${TOP}}' f" pass
bound_case "{,n} with a small n passes" scripts/zz-bound.sh "grep -E 'a{,10}' f" pass
bound_case "scripts/ file, exactly 255 passes" scripts/zz-bound.sh "grep -E 'a{0,${TOP}}' f" pass
bound_case "tools/ file, small bounds pass" tools/zz-bound.sh "grep -E 'a{1,100}b{3}' f" pass
bound_case "install.sh, exactly 255 passes" install.sh "grep -E 'a{0,${TOP}}' f" pass
bound_case "a bash brace list in scripts/ is not a bound" scripts/zz-bound.sh "echo {1,2,3} {a,b}" pass
# the message tells what is wrong, not only where
C="$(mk_copy)"; printf '#!/usr/bin/env bash\n# fixture\ngrep -E %s f\n' "'a{,${BIG}}'" > "$C/tools/zz-bound.sh"
checks "$C"
assert_contains "AC7.1 the failure mentions the repeat bound" "$(printf '%s' "$OUT" | tr 'A-Z' 'a-z')" "bound"

t_summary
