#!/usr/bin/env bash
# Tests for the SKILL.md frontmatter checks in evals/run-checks.sh (AC5).
# Each test runs run-checks.sh inside a fresh copy of the repository (tracked + untracked,
# non-ignored files), so mutations never touch the real skills.
. "$(dirname "$0")/lib.sh"
SKILL=skills/playbook-proof/SKILL.md

# The tree is read once into MASTER (tracked + untracked, non-ignored files); every mk_copy is a plain
# `cp -a` of it, so the file list and the tar pipeline are not repeated for each of the ~50 cases.
MASTER="$(mk_tmp)"
( cd "$PB_ROOT" &&
  git ls-files -co --exclude-standard | while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done |
  tar -cf - -T - ) | ( cd "$MASTER" && tar -xf - )
# mk_copy -> prints a temp dir holding a copy of the working tree
mk_copy() {
  local d; d="$(mk_tmp)"
  cp -a "$MASTER/." "$d/"
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
# checks DIR [SECTION] -> with SECTION only that check group runs (run-checks.sh --only SECTION): a sandbox case for one
# rule does not need the other groups (shellcheck, frontmatter, ...), which dominate the time on Windows
checks() { if [ -n "${2:-}" ]; then run bash "$1/evals/run-checks.sh" --only "$2"; else run bash "$1/evals/run-checks.sh"; fi; only_problems; }
# mk_git_copy -> a copy of the working tree committed into a fresh git repo with LF in the index
# (the repo is built once in GMASTER, with .git, and copied with cp -a)
GMASTER="$(mk_tmp)"
cp -a "$MASTER/." "$GMASTER/"
( cd "$GMASTER" && git init -q && git config core.autocrlf false && git config user.email t@example.invalid &&
  git config user.name tester && git config commit.gpgsign false && git add -A && git commit -q -m copy ) >/dev/null 2>&1
mk_git_copy() {
  local d; d="$(mk_tmp)"
  cp -a "$GMASTER/." "$d/"
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
  checks "$C" dupmax
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
checks "$C" dupmax
assert_contains "AC7.1 the failure mentions the repeat bound" "$(printf '%s' "$OUT" | tr 'A-Z' 'a-z')" "bound"


echo "v0.21.0 AC2.1 GNU-only in-place sed (no attached suffix) is refused; BSD sed needs one"
# The commands are built at run time: a literal one in this file would fail the real run-checks.
SD=sed; FI=-i
# sed_case NAME FILE BODY-LINE EXPECT(fail|pass) -> FILE (under the copy) gets BODY-LINE as its line 3
sed_case() {
  local name="$1" rel="$2" line="$3" expect="$4"
  C="$(mk_copy)"
  mkdir -p "$C/$(dirname "$rel")"
  printf '#!/usr/bin/env bash\n# fixture\n%s\n' "$line" > "$C/$rel"
  checks "$C" sed
  if [ "$expect" = fail ]; then
    assert_rc "AC2.1 $name: exit 1" 1
    assert_contains "AC2.1 $name: names file:line" "$OUT" "$rel:3"
  else
    assert_rc "AC2.1 $name: exit 0" 0
    assert_not_contains "AC2.1 $name: the file is not named" "$OUT" "$rel"
  fi
}
sed_case "double-quoted script, no suffix"        tests/zz-sed.sh "$SD $FI \"s/a/b/\" f" fail
sed_case "single-quoted script, no suffix"        tests/zz-sed.sh "$SD $FI 's/a/b/' f" fail
sed_case "-E before -i"                           tests/zz-sed.sh "$SD -E $FI 's/a/b/' f" fail
sed_case "long form --in-place"                  tests/zz-sed.sh "$SD --in-place 's/a/b/' f" fail
sed_case "combined flags -Ei"                    tests/zz-sed.sh "$SD -E${FI#-} 's/a/b/' f" fail
sed_case "-n before -i"                           tests/zz-sed.sh "$SD -n $FI 's/a/b/p' f" fail
sed_case "mid-line after a semicolon"             tests/zz-sed.sh "x=1; $SD $FI \"s/a/b/\" f" fail
sed_case "script quoted right after -i (double)"  tests/zz-sed.sh "$SD $FI\"s/a/b/\" f" fail
sed_case "script quoted right after -i (single)"  tests/zz-sed.sh "$SD $FI's/a/b/' f" fail
sed_case "in a pipeline"                          tests/zz-sed.sh "cat f | $SD $FI 's/a/b/' g" fail
sed_case "evals/ file"                            evals/zz-sed.sh "$SD $FI \"s/a/b/\" f" fail
sed_case "scripts/ file"                          scripts/zz-sed.sh "$SD $FI \"s/a/b/\" f" fail
sed_case "tools/ file"                            tools/zz-sed.sh "$SD $FI \"s/a/b/\" f" fail
sed_case "install.sh"                             install.sh "$SD $FI \"s/a/b/\" f" fail
sed_case "attached suffix .bak"                   tests/zz-sed.sh "$SD $FI.bak 's/a/b/' f" pass
sed_case "attached suffix .bak, -E before"        tests/zz-sed.sh "$SD -E $FI.bak 's/a/b/' f" pass
sed_case "a comment line mentioning it"           tests/zz-sed.sh "# do not use $SD $FI \"s/...\"" pass
sed_case "a trailing comment mentioning it"       tests/zz-sed.sh "foo   # node, not $SD $FI: BSD" pass
sed_case "sed without -i"                         tests/zz-sed.sh "$SD -n 's/a/b/p' f" pass
sed_case "grep -i is not in-place sed"                tests/zz-sed.sh "grep $FI x f" pass
sed_case "sed -e script, no -i at all"           tests/zz-sed.sh "$SD -e 's/a/b/' f" pass
# the message tells what is wrong, not only where
C="$(mk_copy)"; printf '#!/usr/bin/env bash\n# fixture\n%s\n' "$SD $FI 's/a/b/' f" > "$C/tests/zz-sed.sh"
checks "$C" sed
assert_contains "AC2.1 the failure mentions sed" "$OUT" "$SD"
# the repository itself stays clean and says so
C="$(mk_copy)"
run bash "$C/evals/run-checks.sh"
assert_rc "AC2.1 the real tree passes run-checks" 0
assert_contains "AC2.1 the ok line is printed" "$OUT" "  ok   $SD $FI has a suffix (BSD sed)"

# AC8.2: the default run (no --only) still contains the dupmax group
C="$(mk_copy)"
run bash "$C/evals/run-checks.sh"
assert_rc "AC8.2 the real tree passes a full run-checks" 0
assert_contains "AC8.2 the full run has the dupmax ok line" "$OUT" "  ok   regex repeat bounds <= 255 (BSD RE_DUP_MAX)"


# ---- v0.22.1 AC5.1: GNU-only options are refused outside comments (BSD/macOS lacks them) ----
# Every construct is spelled through variables, so this file does not trip its own check.
echo "v0.22.1 AC5.1 GNU-only options"
G=grep; PF=-P; RL=readlink; FF=-f; DT=date; DD=-d; ST=stat; CC=-c; FD=find; PR=-printf; XA=xargs; XR=-r; SD2=sed
# gnu_case NAME FILE BODY-LINE EXPECT(fail|pass) [CONSTRUCT] -> FILE (under the copy) gets BODY-LINE as its line 3
gnu_case() {
  local name="$1" rel="$2" line="$3" expect="$4" construct="${5:-}"
  C="$(mk_copy)"
  mkdir -p "$C/$(dirname "$rel")"
  printf '#!/usr/bin/env bash\n# fixture\n%s\n' "$line" > "$C/$rel"
  checks "$C" gnu
  if [ "$expect" = fail ]; then
    assert_rc "AC5.1 $name: exit 1" 1
    assert_contains "AC5.1 $name: names file:line" "$OUT" "$rel:3"
    [ -z "$construct" ] || assert_contains "AC5.1 $name: names the construct" "$OUT" "$construct"
  else
    assert_rc "AC5.1 $name: exit 0" 0
    assert_not_contains "AC5.1 $name: the file is not named" "$OUT" "$rel"
  fi
}
# flagged
gnu_case "grep PCRE flag"                        tests/zz-gnu.sh   "$G $PF 'a\\d' f" fail "$G $PF"
gnu_case "grep PCRE flag after a pipe"             scripts/zz-gnu.sh "cat f | $G $PF 'a' >/dev/null" fail "$G $PF"
gnu_case "grep PCRE in a cluster (n first)"               evals/zz-gnu.sh   "$G -n${PF#-} 'a' f" fail "$G"
gnu_case "grep PCRE in a cluster (P last)"      tools/zz-gnu.sh   "$G -rl${PF#-} 'a' ." fail "$G"
gnu_case "grep PCRE in a cluster (P first)"      install.sh        "$G ${PF}i 'a' f" fail "$G"
gnu_case "grep PCRE as a separate flag"      tests/zz-gnu.sh   "$G -n $PF 'a' f" fail "$G"
gnu_case "readlink canonicalise"                      install.sh        "$RL $FF \"\$0\" >/dev/null" fail "$RL $FF"
gnu_case "readlink canonicalise inside a substitution"         tests/zz-gnu.sh   "echo \"\$($RL $FF \"\$0\")\"" fail "$RL $FF"
gnu_case "date string flag"                        scripts/zz-gnu.sh "$DT $DD yesterday >/dev/null" fail "$DT $DD"
gnu_case "date string flag after and-and"                 evals/zz-gnu.sh   "true && $DT $DD '1 day ago' >/dev/null" fail "$DT $DD"
gnu_case "stat format flag"                        evals/zz-gnu.sh   "$ST $CC %Y f >/dev/null" fail "$ST $CC"
gnu_case "stat format flag with an attached format"  tools/zz-gnu.sh   "$ST $CC%Y f >/dev/null" fail "$ST $CC"
gnu_case "find print-format action"                   tools/zz-gnu.sh   "$FD . $PR '%p\\n' >/dev/null" fail "$PR"
gnu_case "find print-format action after other tests"   tests/zz-gnu.sh   "$FD . -type f -name x $PR '%p\\n' >/dev/null" fail "$PR"
gnu_case "xargs no-run-if-empty"                       tests/zz-gnu.sh   "echo a | $XA $XR echo >/dev/null" fail "$XA $XR"
gnu_case "xargs no-run-if-empty as a later flag"        scripts/zz-gnu.sh "echo a | $XA -n1 $XR echo >/dev/null" fail "$XA"
gnu_case "sed extended-regex flag"                         scripts/zz-gnu.sh "echo a | $SD2 -r 's/a/b/' >/dev/null" fail "$SD2 -r"
gnu_case "sed extended-regex flag in a cluster"                install.sh        "echo a | $SD2 -nr 's/a/b/p' >/dev/null" fail "$SD2"
gnu_case "mid-line after a semicolon"       tests/zz-gnu.sh   "x=1; $RL $FF \"\$0\" >/dev/null" fail "$RL $FF"
# not flagged
gnu_case "grep -E"                          tests/zz-gnu.sh   "$G -E 'a|b' f >/dev/null" pass
gnu_case "grep -i -n"                       tests/zz-gnu.sh   "$G -i -n 'a' f >/dev/null" pass
gnu_case "grep -iE"                         tests/zz-gnu.sh   "$G -iE 'a' f >/dev/null" pass
gnu_case "date +%s"                         scripts/zz-gnu.sh "$DT +%s >/dev/null" pass
gnu_case "date -u"                          scripts/zz-gnu.sh "$DT -u +%s >/dev/null" pass
gnu_case "stat with no format flag"                  evals/zz-gnu.sh   "$ST f >/dev/null" pass
gnu_case "stat -f (BSD)"                    evals/zz-gnu.sh   "$ST -f %m f >/dev/null" pass
gnu_case "find -print"                      tools/zz-gnu.sh   "$FD . -print >/dev/null" pass
gnu_case "find -print0"                     tools/zz-gnu.sh   "$FD . -type f -print0 >/dev/null" pass
gnu_case "xargs with no -r"                 tests/zz-gnu.sh   "echo a | $XA echo >/dev/null" pass
gnu_case "xargs -n1"                        tests/zz-gnu.sh   "echo a | $XA -n1 echo >/dev/null" pass
gnu_case "sed -E"                           install.sh        "echo a | $SD2 -E 's/a/b/' >/dev/null" pass
gnu_case "sed -n"                           install.sh        "echo a | $SD2 -n 's/a/b/p' >/dev/null" pass
gnu_case "readlink without the flag"              scripts/zz-gnu.sh "$RL \"\$0\" >/dev/null" pass
gnu_case "a comment line mentioning them"   tests/zz-gnu.sh   "# do not use $G $PF, $RL $FF, $DT $DD, $ST $CC, $XA $XR or $SD2 -r" pass
gnu_case "a trailing comment mentioning it" tests/zz-gnu.sh   "true   # not $G $PF and not $RL $FF" pass
gnu_case "a trailing comment after a tab"   scripts/zz-gnu.sh "true$(printf '\t')# no $DT $DD here" pass
gnu_case "the word in another tool: a prefixed grep" tests/zz-gnu.sh "my$G $PF 'a' f" pass
gnu_case "the word in another tool: a --date option" tests/zz-gnu.sh "foo --$DT $DD x" pass
gnu_case "the word in another tool: a prefixed readlink" scripts/zz-gnu.sh "my$RL $FF x" pass
# the repository itself stays clean and says so
C="$(mk_copy)"
run bash "$C/evals/run-checks.sh"
assert_rc "AC5.1 the real tree passes run-checks" 0
assert_contains "AC5.1 the ok line is printed" "$OUT" "  ok   GNU-only options absent (BSD/macOS)"

# ---- v0.22.1 review: an explicit exemption marker, and no GNU flag hidden in a variable ----
echo "v0.22.1 review: gnu-ok marker"
MK='# gnu-ok:'
gnu_case "marker with a reason exempts the line"            scripts/zz-gnu.sh "$DT $DD yesterday >/dev/null $MK BSD fallback follows" pass
gnu_case "marker with a reason, readlink, in install.sh"    install.sh        "$RL $FF \"\$0\" >/dev/null $MK checked on Linux only" pass
gnu_case "marker with a reason after a pipe and a cluster"  tests/zz-gnu.sh   "cat f | $G -n${PF#-} 'a' >/dev/null $MK PCRE needed here" pass
gnu_case "the same line without the marker is flagged"      scripts/zz-gnu.sh "$DT $DD yesterday >/dev/null" fail "$DT $DD"
gnu_case "marker with no reason is still flagged"           scripts/zz-gnu.sh "$DT $DD yesterday >/dev/null $MK" fail "$DT $DD"
gnu_case "marker followed only by blanks is still flagged"  evals/zz-gnu.sh   "$ST $CC %Y f >/dev/null $MK   " fail "$ST $CC"
gnu_case "marker without the colon is still flagged"        tools/zz-gnu.sh   "$XA $XR echo </dev/null # gnu-ok reason" fail "$XA $XR"
gnu_case "marker text without a leading # is still flagged" tests/zz-gnu.sh   "$RL $FF \"\$0\" >/dev/null gnu-ok: reason" fail "$RL $FF"
gnu_case "a marker on another line does not exempt this one" tests/zz-gnu.sh  "$RL $FF \"\$0\" >/dev/null
true $MK unrelated" fail "$RL $FF"
LIBF="$PB_ROOT/scripts/lib.sh"
ED="$(awk '/^pb_epoch_day\(\)/ { f = 1 } f { print } f && /^}/ { exit }' "$LIBF")"
assert_contains "RV pb_epoch_day has the GNU date call written literally" "$ED" "$DT -u $DD "
GL="$(printf '%s\n' "$ED" | grep -F -- "$DT -u $DD " | head -n 1)"
assert_contains "RV pb_epoch_day: that GNU call carries the gnu-ok marker with a reason" "$GL" "# gnu-ok: "
HID="$(grep -nE '^[[:space:]]*(local +)?[A-Za-z_][A-Za-z0-9_]*=-[A-Za-z]([[:space:]]|$)' "$PB_ROOT"/scripts/*.sh 2>/dev/null)"
assert_eq "RV no line in scripts/*.sh assigns a short flag to a variable to hide it" "" "$HID"

# ---- v0.22.2 AC8.1: run-checks.sh --only SECTION ----
echo "v0.22.2 AC8.1 run-checks.sh --only SECTION runs one check group"
# the fixtures are built from variables, so this file does not trip its own checks
G2=grep; P2=-P; S3=sed; I3=-i; BIG2=$((255 + 45))
# fixture_gnu DIR / fixture_sed DIR / fixture_big DIR -> a flagged line 3 of tests/zz-only.sh
fixture_gnu() { printf '#!/usr/bin/env bash\n# fixture\n%s\n' "$G2 $P2 'a' f >/dev/null" > "$1/tests/zz-only.sh"; }
fixture_sed() { printf '#!/usr/bin/env bash\n# fixture\n%s\n' "$S3 $I3 's/a/b/' f" > "$1/tests/zz-only.sh"; }
fixture_big() { printf '#!/usr/bin/env bash\n# fixture\n%s\n' "grep -E 'a{0,${BIG2}}' f" > "$1/tests/zz-only.sh"; }
only_run() { run bash "$1/evals/run-checks.sh" --only "$2"; }
# other_groups_absent LABEL -> assert that OUT has no line of the other check groups
other_groups_absent() {
  assert_not_contains "$1: no skills line (name matches directory)" "$OUT" "name matches directory"
  assert_not_contains "$1: no eval scenarios line" "$OUT" "scenarios each have"
  assert_not_contains "$1: no always-on block heading" "$OUT" "always-on block"
  assert_not_contains "$1: no syntax line from the files group" "$OUT" "  ok   syntax:"
}

C="$(mk_copy)"; fixture_gnu "$C"
only_run "$C" gnu
assert_rc "AC8.1 --only gnu on a flagged fixture: exit 1" 1
assert_contains "AC8.1 --only gnu on a flagged fixture: names the file:line" "$OUT" "tests/zz-only.sh:3"
assert_contains "AC8.1 --only gnu on a flagged fixture: names the construct" "$OUT" "$G2 $P2"
assert_contains "AC8.1 --only gnu on a flagged fixture: ends with the problem count" "$OUT" "run-checks: 1 problem(s)"
other_groups_absent "AC8.1 --only gnu (flagged)"
assert_not_contains "AC8.1 --only gnu (flagged): no sed line" "$OUT" "has a suffix (BSD sed)"
assert_not_contains "AC8.1 --only gnu (flagged): no dupmax line" "$OUT" "regex repeat bounds"

C="$(mk_copy)"
only_run "$C" gnu
assert_rc "AC8.1 --only gnu on a clean fixture: exit 0" 0
assert_contains "AC8.1 --only gnu on a clean fixture: the gnu ok line" "$OUT" "  ok   GNU-only options absent (BSD/macOS)"
assert_contains "AC8.1 --only gnu on a clean fixture: run-checks: all ok" "$OUT" "run-checks: all ok"
other_groups_absent "AC8.1 --only gnu (clean)"

C="$(mk_copy)"
only_run "$C" bogus
assert_rc "AC8.1 --only bogus: exit 2" 2
assert_not_contains "AC8.1 --only bogus: no check ran (no ok line)" "$OUT" "  ok   "
C="$(mk_copy)"
run bash "$C/evals/run-checks.sh" --only
assert_rc "AC8.1 --only without a section: exit 2" 2

C="$(mk_copy)"; fixture_sed "$C"
only_run "$C" sed
assert_rc "AC8.1 --only sed on a flagged fixture: exit 1" 1
assert_contains "AC8.1 --only sed on a flagged fixture: names the file:line" "$OUT" "tests/zz-only.sh:3"
other_groups_absent "AC8.1 --only sed (flagged)"
assert_not_contains "AC8.1 --only sed (flagged): no gnu line" "$OUT" "GNU-only options"
C="$(mk_copy)"
only_run "$C" sed
assert_rc "AC8.1 --only sed on a clean fixture: exit 0" 0
assert_contains "AC8.1 --only sed on a clean fixture: the sed ok line" "$OUT" "has a suffix (BSD sed)"

C="$(mk_copy)"; fixture_big "$C"
only_run "$C" dupmax
assert_rc "AC8.1 --only dupmax on a flagged fixture: exit 1" 1
assert_contains "AC8.1 --only dupmax on a flagged fixture: names the file:line" "$OUT" "tests/zz-only.sh:3"
other_groups_absent "AC8.1 --only dupmax (flagged)"
assert_not_contains "AC8.1 --only dupmax (flagged): no gnu line" "$OUT" "GNU-only options"
C="$(mk_copy)"
only_run "$C" dupmax
assert_rc "AC8.1 --only dupmax on a clean fixture: exit 0" 0
assert_contains "AC8.1 --only dupmax on a clean fixture: the dupmax ok line" "$OUT" "regex repeat bounds <= 255"

echo "AC8.1 a section runs only its own rule: the other rules' flagged files are not reported"
C="$(mk_copy)"; fixture_gnu "$C"
only_run "$C" sed
assert_rc "AC8.1 --only sed ignores a gnu-flagged file: exit 0" 0
C="$(mk_copy)"; fixture_sed "$C"
only_run "$C" gnu
assert_rc "AC8.1 --only gnu ignores a sed-flagged file: exit 0" 0
C="$(mk_copy)"; fixture_big "$C"
only_run "$C" gnu
assert_rc "AC8.1 --only gnu ignores a repeat-bound-flagged file: exit 0" 0
C="$(mk_copy)"; fixture_gnu "$C"
only_run "$C" dupmax
assert_rc "AC8.1 --only dupmax ignores a gnu-flagged file: exit 0" 0

echo "AC8.1 the other sections: skills, scenarios, shellcheck"
C="$(mk_copy)"
only_run "$C" skills
assert_rc "AC8.1 --only skills on the real tree: exit 0" 0
assert_contains "AC8.1 --only skills: the skills lines are there" "$OUT" "name matches directory"
assert_not_contains "AC8.1 --only skills: no gnu line" "$OUT" "GNU-only options"
assert_not_contains "AC8.1 --only skills: no scenarios line" "$OUT" "scenarios each have"
C="$(mk_copy)"
set_line "$C" description 'description: Use when stating results. Note: keep it short.'
only_run "$C" skills
assert_rc "AC8.1 --only skills on a bad description: exit 1" 1
assert_contains "AC8.1 --only skills on a bad description: names the SKILL.md" "$OUT" "$SKILL"
C="$(mk_copy)"
only_run "$C" scenarios
assert_rc "AC8.1 --only scenarios on the real tree: exit 0" 0
assert_contains "AC8.1 --only scenarios: the scenario lines are there" "$OUT" "scenarios each have Prompt:"
assert_not_contains "AC8.1 --only scenarios: no skills line" "$OUT" "name matches directory"
assert_not_contains "AC8.1 --only scenarios: no gnu line" "$OUT" "GNU-only options"
C="$(mk_copy)"
only_run "$C" shellcheck
assert_rc "AC8.1 --only shellcheck on the real tree: exit 0" 0
assert_contains "AC8.1 --only shellcheck: a shellcheck line (ok or skip)" "$OUT" "shellcheck"
assert_not_contains "AC8.1 --only shellcheck: no gnu line" "$OUT" "GNU-only options"
assert_not_contains "AC8.1 --only shellcheck: no skills line" "$OUT" "name matches directory"

echo "AC8.1 without --only every group runs"
C="$(mk_copy)"; fixture_gnu "$C"
run bash "$C/evals/run-checks.sh"
assert_rc "AC8.1 no --only: a gnu-flagged file fails the full run" 1
for want in "name matches directory" "always-on block" "regex repeat bounds <= 255" "has a suffix (BSD sed)" "GNU-only options (BSD/macOS lacks them" "scenarios each have Prompt:" "syntax:"; do
  assert_contains "AC8.1 no --only: the full output has [$want]" "$OUT" "$want"
done


# ---- v0.23.0 AC4.3: the control byte SOH (octal 1) in scripts is refused in every spelling (bash 3.2 on macOS) ----
# New check group: `evals/run-checks.sh --only soh`. Every construct is built from pieces (B = one backslash, Q = a single
# quote), so this file does not trip its own check. The message names file:line.
echo "v0.23.0 AC4.3 the SOH byte in any spelling (section soh)"
B='\'; Q="'"
# soh_case NAME FILE BODY-LINE EXPECT(fail|pass) -> FILE (under the copy) gets BODY-LINE as its line 3
soh_case() {
  local name="$1" rel="$2" line="$3" expect="$4"
  C="$(mk_copy)"
  mkdir -p "$C/$(dirname "$rel")"
  printf '#!/usr/bin/env bash\n# fixture\n%s\n' "$line" > "$C/$rel"
  checks "$C" soh
  if [ "$expect" = fail ]; then
    assert_rc "AC4.3 $name: exit 1" 1
    assert_contains "AC4.3 $name: names file:line" "$OUT" "$rel:3"
  else
    assert_rc "AC4.3 $name: exit 0" 0
    assert_not_contains "AC4.3 $name: the file is not named" "$OUT" "$rel"
  fi
}
# every spelling is flagged
soh_case "printf with the octal escape"          tests/zz-soh.sh "printf ${Q}${B}001${Q}" fail
soh_case "ANSI-C quote with the octal escape"    tests/zz-soh.sh "x=\$${Q}${B}001${Q}" fail
soh_case "hex escape"                            tests/zz-soh.sh "printf ${Q}${B}x01${Q}" fail
soh_case "ANSI-C quote with the hex escape"      tests/zz-soh.sh "x=\$${Q}${B}x01${Q}" fail
soh_case "short octal escape"                    tests/zz-soh.sh "printf ${Q}${B}01${Q}" fail
soh_case "printf %b with the octal escape"       tests/zz-soh.sh "printf ${Q}%b${Q} ${Q}${B}001${Q}" fail
soh_case "tr with the octal escape"              tests/zz-soh.sh "tr ${Q}${B}001${Q} x" fail
soh_case "awk string with the octal escape"      tests/zz-soh.sh "awk ${Q}BEGIN { printf \"${B}001\" }${Q}" fail
soh_case "three backslashes: the last one escapes" tests/zz-soh.sh "printf ${Q}${B}${B}${B}001${Q}" fail
soh_case "inside double quotes"                  tests/zz-soh.sh "echo \"a${B}001b\"" fail
soh_case "mid-line after a semicolon"            tests/zz-soh.sh "x=1; printf ${Q}${B}001${Q}" fail
soh_case "no gnu-ok exemption"                   tests/zz-soh.sh "printf ${Q}${B}001${Q}   # gnu-ok: legacy fixture" fail
# in every scanned location
soh_case "evals/ file"       evals/zz-soh.sh   "printf ${Q}${B}001${Q}" fail
soh_case "scripts/ file"     scripts/zz-soh.sh "printf ${Q}${B}001${Q}" fail
soh_case "tools/ file"       tools/zz-soh.sh   "printf ${Q}${B}001${Q}" fail
soh_case "install.sh"        install.sh        "printf ${Q}${B}001${Q}" fail
soh_case "hex spelling in scripts/"  scripts/zz-soh.sh "printf ${Q}${B}x01${Q}" fail
soh_case "tr spelling in tools/"     tools/zz-soh.sh   "tr ${Q}${B}001${Q} x" fail
# not flagged
soh_case "a comment line mentioning it"      tests/zz-soh.sh "# uses ${B}001 and printf ${Q}${B}x01${Q} here" pass
soh_case "an indented comment line"          tests/zz-soh.sh "   # ${B}001 is CTLESC" pass
soh_case "a trailing comment mentioning it (as scripts/mutate.sh does)" tests/zz-soh.sh "soh=\"\$(printf ${Q}${B}034${Q})\"   # ASCII field separator: bash 3.2 uses ${B}001 internally" pass
soh_case "an escaped backslash before 01 (as tests/test-evals-grade5.sh does)" tests/zz-soh.sh "x=${Q}handoff${B}${B}01-spec.md${Q}" pass
soh_case "an escaped backslash before 01 in double quotes" tests/zz-soh.sh "echo \"handoff${B}${B}01-spec.md\"" pass
soh_case "an escaped backslash before 001"   tests/zz-soh.sh "printf ${Q}${B}${B}001${Q}" pass
soh_case "the field separator 034"           tests/zz-soh.sh "printf ${Q}${B}034${Q}" pass
soh_case "another escape (newline)" tests/zz-soh.sh "printf ${Q}${B}n${Q}" pass
soh_case "a path with 001 and no backslash"  tests/zz-soh.sh "cat tests/fixture-001.txt" pass

echo "v0.23.0 AC4.3 the real tree passes and says so"
C="$(mk_copy)"
run bash "$C/evals/run-checks.sh" --only soh
assert_rc "AC4.3 --only soh on the real tree: exit 0" 0
assert_contains "AC4.3 --only soh: run-checks: all ok" "$OUT" "run-checks: all ok"
assert_eq "AC4.3 --only soh prints exactly one ok line" "1" "$(printf '%s\n' "$OUT" | grep -c '^  ok   ')"
assert_contains "AC4.3 the ok line names 001" "$(printf '%s\n' "$OUT" | grep '^  ok   ')" "001"
assert_not_contains "AC4.3 --only soh: no gnu line" "$OUT" "GNU-only options"
C="$(mk_copy)"
run bash "$C/evals/run-checks.sh"
assert_rc "AC4.3 the full run on the real tree: exit 0" 0
assert_eq "AC4.3 the full run has the soh ok line (001)" "1" "$(printf '%s\n' "$OUT" | grep '^  ok   ' | grep -c '001')"
C="$(mk_copy)"
printf '#!/usr/bin/env bash\n# fixture\n%s\n' "printf ${Q}${B}001${Q}" > "$C/tests/zz-soh.sh"
run bash "$C/evals/run-checks.sh" --only gnu
assert_rc "AC4.3 --only gnu ignores a soh-flagged file: exit 0" 0
run bash "$C/evals/run-checks.sh" --only sed
assert_rc "AC4.3 --only sed ignores a soh-flagged file: exit 0" 0

# ---- v0.23.0 AC6: more GNU-only constructs, and a quote-aware comment stripper ----
echo "v0.23.0 AC6.1 GNU long options, find -fprintf, flags after arguments, clusters with digits"
# the constructs are spelled through the variables above (G, ST, RL, DT, XA, SD2, FD, PF, XR, MK)
gnu_case "long perl option"                       tests/zz-gnu.sh   "$G --perl 'a' f" fail
gnu_case "long perl-regexp option"                tests/zz-gnu.sh   "$G --perl-regexp 'a' f" fail
gnu_case "stat --form (a prefix of the format option)" tests/zz-gnu.sh "$ST --form %Y f" fail
gnu_case "stat --format=x"                        scripts/zz-gnu.sh "$ST --format=x f" fail
gnu_case "stat --printf"                          evals/zz-gnu.sh   "$ST --printf x f" fail
gnu_case "readlink --canon"                       tools/zz-gnu.sh   "$RL --canon f" fail
gnu_case "date --date=x"                          install.sh        "$DT --date=x" fail
gnu_case "xargs --no-run"                         tests/zz-gnu.sh   "echo a | $XA --no-run echo" fail
gnu_case "sed --regexp (a prefix of the extended option)" tests/zz-gnu.sh "echo a | $SD2 --regexp 's/a/b/'" fail
gnu_case "find -fprintf"                          tests/zz-gnu.sh   "$FD . -fprintf out x" fail
gnu_case "PCRE flag after an option argument (-e x)" tests/zz-gnu.sh "$G -e x $PF f" fail
gnu_case "PCRE flag after an option argument (-A 3)" tests/zz-gnu.sh "$G -A 3 $PF x f" fail
gnu_case "PCRE flag as a trailing flag"           tests/zz-gnu.sh   "$G x f $PF" fail
gnu_case "xargs -0r (cluster with a digit)"       tests/zz-gnu.sh   "echo a | $XA -0${XR#-} echo" fail
gnu_case "long option in scripts/"                scripts/zz-gnu.sh "$G --perl-regexp x f" fail
gnu_case "long option in tools/"                  tools/zz-gnu.sh   "$DT --date=x" fail
gnu_case "long option after a pipe"               evals/zz-gnu.sh   "cat f | $G --perl x" fail
gnu_case "long option with a marker without a reason" tests/zz-gnu.sh "$G --perl x f $MK" fail
# not flagged
gnu_case "grep --regexp=x"                        tests/zz-gnu.sh   "$G --regexp=x f" pass
gnu_case "grep --extended-regexp"                 tests/zz-gnu.sh   "$G --extended-regexp x f" pass
gnu_case "grep --ignore-case"                     tests/zz-gnu.sh   "$G --ignore-case x f" pass
gnu_case "xargs -n1 -0"                           tests/zz-gnu.sh   "echo a | $XA -n1 -0 echo" pass
gnu_case "a long option in a comment"             tests/zz-gnu.sh   "# do not use $G --perl, $ST --format=x or $FD . -fprintf" pass
gnu_case "a trailing flag that is not a GNU one"  tests/zz-gnu.sh   "$G x f -i" pass
gnu_case "a real trailing gnu-ok marker with a reason" tests/zz-gnu.sh "$G $PF x f $MK needs PCRE here" pass
gnu_case "a real trailing gnu-ok marker on a long option" scripts/zz-gnu.sh "$DT --date=x $MK Linux only, checked" pass

echo "v0.23.0 AC6.2 the comment stripper and the gnu-ok marker are quote-aware"
gnu_case "a # inside double quotes is not a comment" tests/zz-gnu.sh "echo \"a # b\"; $G $PF x" fail
gnu_case "a gnu-ok marker inside single quotes does not exempt" tests/zz-gnu.sh "echo 'a $MK x'; $G $PF y" fail
gnu_case "a # inside single quotes is not a comment" tests/zz-gnu.sh "echo 'a # b'; $G $PF x" fail
gnu_case "a gnu-ok marker inside double quotes does not exempt" scripts/zz-gnu.sh "echo \"a $MK x\"; $G $PF y" fail
gnu_case "a quoted # before a real trailing comment: the flag is code" tests/zz-gnu.sh "echo \"a # b\"; $G $PF x # tail" fail
gnu_case "a quoted # then a real marker with a reason exempts" tests/zz-gnu.sh "echo \"a # b\"; $G $PF x $MK needs PCRE" pass
gnu_case "a real comment after a closed quote hides the rest" tests/zz-gnu.sh "echo \"a b\" # $G $PF x" pass
gnu_case "a # inside quotes in a comment-free line without GNU flags" tests/zz-gnu.sh "echo \"a # b\"; $G -i x" pass
C="$(mk_copy)"
run bash "$C/evals/run-checks.sh"
assert_rc "AC6 the real tree passes a full run-checks with the new rules" 0
assert_contains "AC6 the gnu ok line is printed" "$OUT" "  ok   GNU-only options absent (BSD/macOS)"


# ---- v0.23.0 review: four-digit octal, what the soh check documents as not covered, executable bits ----
echo "v0.23.0 review: AC4.3 four digits"
soh_case "printf %b with a four-digit octal escape" tests/zz-soh.sh "printf ${Q}%b${Q} ${Q}${B}0001${Q}" fail
soh_case "four-digit octal escape in a plain printf" tests/zz-soh.sh "printf ${Q}${B}0001${Q}" fail

echo "v0.23.0 review: the soh block documents what it does not cover"
SOHBLK="$(awk '/^if want soh; then/ { f = 1 } f && /^#/ { print } f && /^fi$/ { exit }' "$PB_ROOT/evals/run-checks.sh")"
if [ -n "$SOHBLK" ]; then t_ok "the soh block in evals/run-checks.sh has comment lines"; else t_bad "the soh block in evals/run-checks.sh has comment lines" "no '# ' lines between 'if want soh' and 'fi'"; fi
assert_contains "the soh comment mentions the short escape (backslash 1)" "$SOHBLK" "${B}1"
assert_contains "the soh comment mentions the short hex escape (backslash x1)" "$SOHBLK" "${B}x1"
assert_contains "the soh comment mentions the control escape (backslash cA)" "$SOHBLK" "${B}cA"
assert_contains "the soh comment says these are not covered" "$(printf '%s' "$SOHBLK" | tr 'A-Z' 'a-z')" "not covered"

echo "v0.23.0 review: executable bits (git mode 100755) of every script"
# Guard: every tracked file under scripts/, tools/ and evals/ whose first line is a #! line, plus tests/*.sh and install.sh,
# is stored with mode 100755. A commit that rewrites a script as 100644 breaks `bash x` nowhere but `./x` and the CI wrappers.
if git -C "$PB_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  BADMODE=""
  LSF="$(git -C "$PB_ROOT" ls-files -s -- scripts tools evals tests install.sh)"
  while read -r mode _ _ path; do
    case "$path" in
      scripts/*|tools/*|evals/*) first=""; IFS= read -r first < "$PB_ROOT/$path" 2>/dev/null; case "$first" in "#!"*) ;; *) continue ;; esac ;;
      tests/*.sh|install.sh) ;;
      *) continue ;;
    esac
    [ "$mode" = 100755 ] || BADMODE="$BADMODE $path($mode)"
  done <<EOF
$LSF
EOF
  assert_eq "every script is stored with git mode 100755" "" "$BADMODE"
else
  t_skip 1 "executable-bit guard needs a git checkout"
fi


# ---- v0.23.2 AC6: the exec-bit guard has its own fixture test ----
# Interface chosen for the guard: `evals/run-checks.sh --only modes`. It runs inside the repository that holds the script
# (run-checks.sh already does cd to its own repo root), reads the INDEX modes with `git ls-files -s` (never [ -x ]), and
# prints "FAIL ... <path>" lines plus exit 1 for every tracked script stored with a mode other than 100755: a file under
# scripts/, tools/ or evals/ whose first line is a #! line, or tests/*.sh, or install.sh. Nothing else is read, so the
# fixture repositories below hold only run-checks.sh and a few scripts.
echo "v0.23.2 AC6.1 exec guard: evals/run-checks.sh --only modes on fixture repositories"
G3="git -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false -c core.autocrlf=false"
# mk_modes_repo -> sets MR: a repo with run-checks.sh and one script per guarded place, all stored at 100755
mk_modes_repo() {
  MR="$(mk_tmp)"
  mkdir -p "$MR/evals" "$MR/scripts" "$MR/tools" "$MR/tests"
  cp "$PB_ROOT/evals/run-checks.sh" "$MR/evals/run-checks.sh"
  printf '#!/usr/bin/env bash\necho a\n' > "$MR/scripts/a.sh"
  printf '#!/usr/bin/env bash\necho b\n' > "$MR/tools/b.sh"
  printf '#!/usr/bin/env bash\necho c\n' > "$MR/evals/c.sh"
  printf '#!/usr/bin/env bash\necho t\n' > "$MR/tests/t.sh"
  printf '#!/usr/bin/env bash\necho i\n' > "$MR/install.sh"
  printf 'plain data, no shebang\n' > "$MR/scripts/data.txt"
  ( cd "$MR" && $G3 init -q && $G3 add -A && $G3 update-index --chmod=+x evals/run-checks.sh scripts/a.sh tools/b.sh evals/c.sh tests/t.sh install.sh &&
    $G3 commit -q -m base ) >/dev/null 2>&1
}
# modes_run DIR -> OUT, RC of the guard in that repository
modes_run() { run_in "$1" bash evals/run-checks.sh --only modes; }
# stage_mode DIR MODE PATH -> change the INDEX mode of a path (+x or -x) and commit nothing
stage_mode() { ( cd "$1" && $G3 update-index "--chmod=$2" "$3" ) >/dev/null 2>&1; }

# corpus first: the all-100755 repository passes
mk_modes_repo
modes_run "$MR"
assert_rc "AC6.1 all scripts at 100755: the guard exits 0" 0
assert_not_contains "AC6.1 all scripts at 100755: no FAIL line" "$OUT" "FAIL"
assert_eq "AC6.1 precondition: the fixture really stores run-checks.sh at 100755" "100755" "$(cd "$MR" && git ls-files -s evals/run-checks.sh | cut -d' ' -f1)"

# a 100644 #! script is reported by path
mk_modes_repo; stage_mode "$MR" -x scripts/a.sh
assert_eq "AC6.1 precondition: scripts/a.sh is staged at 100644" "100644" "$(cd "$MR" && git ls-files -s scripts/a.sh | cut -d' ' -f1)"
modes_run "$MR"
assert_rc "AC6.1 a 100644 #! script under scripts/: exit 1" 1
assert_contains "AC6.1 a 100644 #! script under scripts/: the path is reported" "$OUT" "scripts/a.sh"
assert_not_contains "AC6.1 only the offending path is reported (tools/b.sh is fine)" "$OUT" "tools/b.sh"
assert_contains "AC6.1 the output says FAIL" "$OUT" "FAIL"
for p in tools/b.sh evals/c.sh tests/t.sh install.sh; do
  mk_modes_repo; stage_mode "$MR" -x "$p"; modes_run "$MR"
  assert_rc "AC6.1 [$p] at 100644: exit 1" 1
  assert_contains "AC6.1 [$p] at 100644: the path is reported" "$OUT" "$p"
done
mk_modes_repo; stage_mode "$MR" -x scripts/a.sh; stage_mode "$MR" -x tools/b.sh; modes_run "$MR"
assert_rc "AC6.1 two files at 100644: exit 1" 1
assert_contains "AC6.1 two files at 100644: the first path is reported" "$OUT" "scripts/a.sh"
assert_contains "AC6.1 two files at 100644: the second path is reported" "$OUT" "tools/b.sh"

# a new file added at 100644 (committed, not just staged) is reported too
mk_modes_repo
printf '#!/usr/bin/env bash\necho new\n' > "$MR/scripts/new.sh"
( cd "$MR" && $G3 add scripts/new.sh && $G3 update-index --chmod=-x scripts/new.sh && $G3 commit -q -m new ) >/dev/null 2>&1
modes_run "$MR"
assert_rc "AC6.1 a committed new #! script at 100644: exit 1" 1
assert_contains "AC6.1 a committed new #! script at 100644: the path is reported" "$OUT" "scripts/new.sh"

# a file under scripts/ without a #! first line is data, not a script: not reported
mk_modes_repo
( cd "$MR" && $G3 update-index --chmod=-x scripts/data.txt ) >/dev/null 2>&1
modes_run "$MR"
assert_rc "AC6.1 scripts/data.txt (no #!) at 100644 is not a script: exit 0" 0

# the INDEX mode decides, never the work-tree executable bit
mk_modes_repo; stage_mode "$MR" -x scripts/a.sh; chmod +x "$MR/scripts/a.sh"
modes_run "$MR"
assert_rc "AC6.1 index 100644 but the work tree file is chmod +x: still exit 1" 1
assert_contains "AC6.1 index 100644 but the work tree file is chmod +x: the path is reported" "$OUT" "scripts/a.sh"
mk_modes_repo; chmod -x "$MR/scripts/a.sh" "$MR/tools/b.sh"
modes_run "$MR"
assert_rc "AC6.1 index 100755 but the work tree file lost +x (not staged): exit 0 (the index is what is committed)" 0
assert_not_contains "AC6.1 index 100755 but the work tree file lost +x (not staged): no FAIL line" "$OUT" "FAIL"

# the section name is part of the usage text
run bash "$PB_ROOT/evals/run-checks.sh" --only nosuchgroup
assert_rc "AC6.1 an unknown section still exits 2" 2
assert_contains "AC6.1 the usage text lists the modes group" "$OUT" "modes"

# mutant: a guard that accepts 100644. A `git` shim rewrites the mode column of `git ls-files -s` (100644 -> 100755), which is
# exactly what a guard that accepts 100644 would see. The fixture that must FAIL then passes, so the assertions above (exit 1,
# path reported) are able to tell the mutant from the real guard.
REALGIT="$(command -v git)"
SHIM="$(mk_tmp)"
printf '#!/bin/sh\ncase " $* " in\n  *" ls-files "*) "%s" "$@" | sed "s/^100644/100755/" ;;\n  *) exec "%s" "$@" ;;\nesac\n' "$REALGIT" "$REALGIT" > "$SHIM/git"
chmod +x "$SHIM/git"
mk_modes_repo; stage_mode "$MR" -x scripts/a.sh
OUT="$(cd "$MR" && PATH="$SHIM:$PATH" bash evals/run-checks.sh --only modes 2>&1)"; RC=$?
assert_eq "AC6.1 mutant (accepts 100644): the 100644 fixture is NOT reported, so the exit-1 assertion above kills it" "0" "$RC"
assert_not_contains "AC6.1 mutant (accepts 100644): the offending path is not reported, so the path assertion above kills it" "$OUT" "scripts/a.sh"

# the real checkout passes the guard (modes are read from its index; the work tree is not looked at)
if git -C "$PB_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  run bash "$PB_ROOT/evals/run-checks.sh" --only modes
  assert_rc "AC6.1 the real checkout passes evals/run-checks.sh --only modes" 0
else
  t_skip 1 "AC6.1 the real-checkout guard run needs a git checkout"
fi

# ---- v0.23.2 AC9: GNU tokenizer gaps (evals/run-checks.sh --only gnu) ----
# Constructs are built from pieces (DL = a dollar sign, DQ = a double quote, BT = a backtick, LB = an open brace, B = one
# backslash, Q = a single quote), so this file does not trip its own check, before or after the checker gets stricter.
echo "v0.23.2 AC9 GNU tokenizer: constructs the per-line scanner missed"
DL='$'; DQ='"'; BT='`'; LB='{'
# gnu9 NAME FILE EXPECT(fail|pass) LINE-NUMBER BODY-LINE... -> FILE (under the copy) gets #! and a comment line, then the
# BODY-LINEs from line 3 on; for fail the output names FILE:LINE-NUMBER, for pass the file is not named
gnu9() {
  local name="$1" rel="$2" expect="$3" ln="$4"; shift 4
  C="$(mk_copy)"
  mkdir -p "$C/$(dirname "$rel")"
  printf '%s\n' '#!/usr/bin/env bash' '# fixture' "$@" > "$C/$rel"
  checks "$C" gnu
  if [ "$expect" = fail ]; then
    assert_rc "AC9 $name: exit 1" 1
    assert_contains "AC9 $name: names $rel:$ln" "$OUT" "$rel:$ln"
  else
    assert_rc "AC9 $name: exit 0" 0
    assert_not_contains "AC9 $name: the file is not named" "$OUT" "$rel"
  fi
}
# corpus first: forms that hold today and must keep holding
gnu9 "corpus: a flag after a plain line"                         tests/zz-gnu.sh fail 4 "echo hi" "$G $PF x"
gnu9 "corpus: a flag in a one-line double-quoted text is hidden" tests/zz-gnu.sh pass 3 "echo ${DQ}$G $PF x${DQ}"
gnu9 "corpus: a flag in a one-line single-quoted text is hidden" tests/zz-gnu.sh pass 3 "echo ${Q}$G $PF x${Q}"
gnu9 "corpus: a flag in a command substitution inside double quotes" tests/zz-gnu.sh fail 3 "echo ${DQ}${DL}($G $PF x)${DQ}"
gnu9 "corpus: a flag in a full-line comment is hidden"          tests/zz-gnu.sh pass 3 "# $G $PF x"

# AC9.1 flagged
gnu9 "a backtick command inside double quotes"                   tests/zz-gnu.sh fail 3 "x=${DQ}${BT}$G $PF y${BT}${DQ}"
gnu9 "a backtick command inside double quotes, after other text" tests/zz-gnu.sh fail 3 "x=${DQ}a ${BT}$G $PF y${BT} b${DQ}"
gnu9 "after an ANSI-C quoted word with an escaped quote"        tests/zz-gnu.sh fail 3 "x=${DL}${Q}a${B}${Q}b${Q}; $G $PF y"
gnu9 "after an ANSI-C quoted word without an escape"            tests/zz-gnu.sh fail 3 "x=${DL}${Q}ab${Q}; $G $PF y"
gnu9 "find -exec echo {} escaped-semicolon -printf"             tests/zz-gnu.sh fail 3 "$FD . -exec echo {} ${B}; $PR '%p'"
gnu9 "find -exec with a plus terminator and -printf"            tests/zz-gnu.sh fail 3 "$FD . -exec echo {} + $PR '%p'"
gnu9 "xargs -I {} then the GNU no-run-if-empty flag"            tests/zz-gnu.sh fail 3 "echo a | $XA -I {} $XR echo {}"
gnu9 "xargs -I {} on a command with a trailing brace word"      tests/zz-gnu.sh fail 3 "echo a | $XA -I {} $XR echo x{}y"
# AC9.2 quote state carries across lines
gnu9 "a double quote opened on one line closes on the next"      tests/zz-gnu.sh fail 4 "x=${DQ}a" "${DQ}; $G $PF y"
gnu9 "a single quote opened on one line closes on the next"      tests/zz-gnu.sh fail 4 "x=${Q}a" "b${Q}; $G $PF y"
gnu9 "a double quote over three lines, the flag after it closes" tests/zz-gnu.sh fail 5 "x=${DQ}a" "b" "${DQ}; $G $PF y"
gnu9 "a flag inside a multi-line double-quoted string is text"   tests/zz-gnu.sh pass 3 "x=${DQ}a" "$G $PF y" "${DQ}"
gnu9 "a flag inside a multi-line single-quoted string is text"   tests/zz-gnu.sh pass 3 "x=${Q}a" "$G $PF y" "${Q}"
gnu9 "a flag line before a multi-line string is still code"      tests/zz-gnu.sh fail 3 "$G $PF y" "x=${DQ}a" "b${DQ}"
gnu9 "a # inside a multi-line string body is not a comment"      tests/zz-gnu.sh fail 5 "x=${DQ}a" "# it${Q}s" "${DQ}; $G $PF y"
gnu9 "a clean line after a closed multi-line string is clean"    tests/zz-gnu.sh pass 3 "x=${DQ}a" "b${DQ}" "echo done"
# E2: comments and heredoc bodies never change the quote state
gnu9 "E2 a heredoc body with an apostrophe, then the flag"       tests/zz-gnu.sh fail 6 "cat <<EOF" "don${Q}t" "EOF" "$G $PF y"
gnu9 "E2 a heredoc body with a double quote, then the flag"      tests/zz-gnu.sh fail 6 "cat <<EOF" "say ${DQ}hi" "EOF" "$G $PF y"
gnu9 "E2 a comment with an apostrophe, then the flag"            tests/zz-gnu.sh fail 4 "# it${Q}s" "$G $PF y"
gnu9 "E2 a comment with a double quote, then the flag"           tests/zz-gnu.sh fail 4 "# say ${DQ}hi" "$G $PF y"
gnu9 "E2 a trailing comment with an apostrophe, then the flag"   tests/zz-gnu.sh fail 4 "echo a   # it${Q}s" "$G $PF y"
# AC9.3 a command word that is a variable named after a checked tool (any case) is checked like the tool
gnu9 "variable GREP, dollar form"                                tests/zz-gnu.sh fail 3 "${DL}GREP $PF x"
gnu9 "variable GREP, braced form"                                tests/zz-gnu.sh fail 3 "${DL}${LB}GREP} $PF x"
gnu9 "variable GREP in a pipeline"                               tests/zz-gnu.sh fail 3 "cat f | ${DL}GREP $PF x"
gnu9 "variable GREP in a command substitution"                   tests/zz-gnu.sh fail 3 "y=${DL}(${DL}GREP $PF x f)"
gnu9 "variable sed in lower case"                                tests/zz-gnu.sh fail 3 "${DL}$SD2 -r 's/a/b/' f"
gnu9 "variable Grep in mixed case"                               tests/zz-gnu.sh fail 3 "${DL}Grep $PF x"
gnu9 "variable SED"                                              tests/zz-gnu.sh fail 3 "${DL}SED -r 's/a/b/' f"
gnu9 "variable STAT"                                             tests/zz-gnu.sh fail 3 "${DL}STAT $CC %Y f"
gnu9 "variable DATE"                                             tests/zz-gnu.sh fail 3 "${DL}DATE $DD yesterday"
gnu9 "variable XARGS"                                            tests/zz-gnu.sh fail 3 "echo a | ${DL}XARGS $XR echo"
gnu9 "variable FIND"                                             tests/zz-gnu.sh fail 3 "${DL}FIND . $PR '%p'"
gnu9 "variable READLINK"                                         tests/zz-gnu.sh fail 3 "${DL}READLINK $FF x"
gnu9 "variable GREP without a GNU option is clean"               tests/zz-gnu.sh pass 3 "${DL}GREP -i x f"
# decision: only the exact tool names, with or without braces and in any case, count; a longer variable name is a different variable
gnu9 "variable GREPPER is not a tool name"                       tests/zz-gnu.sh pass 3 "${DL}GREPPER $PF x"
gnu9 "variable GREPPER, braced, is not a tool name"              tests/zz-gnu.sh pass 3 "${DL}${LB}GREPPER} $PF x"
gnu9 "a variable named after a tool, used as an argument, is not a command word" tests/zz-gnu.sh pass 3 "echo ${DL}GREP $PF"
gnu9 "a GNU-ok marker with a reason still exempts the variable form" tests/zz-gnu.sh pass 3 "${DL}GREP $PF x $MK needs PCRE here"

# the real tree still passes the stricter scanner, alone and in a full run
C="$(mk_copy)"
run bash "$C/evals/run-checks.sh" --only gnu
assert_rc "AC9 the real tree passes run-checks --only gnu" 0
assert_contains "AC9 the gnu ok line is printed" "$OUT" "  ok   GNU-only options absent (BSD/macOS)"


# ---- v0.23.2 AC16.1: a file glob that matches nothing fails its section (a renamed directory is not a silent pass) ----
# Sections covered: dupmax, sed, gnu, soh (globs tests/*.sh, scripts/*.sh, tools/*.sh), skills (skills/*/), shellcheck (scripts/*.sh,
# tools/*.sh; only where shellcheck is installed) and the full run (the files group loops over the same globs).
# evals/*.sh is not emptied: evals/run-checks.sh itself always matches it. A directory is renamed, never globbed away.
echo "v0.23.2 AC16.1 a glob that matches no file is reported and fails the section"
# glob_case SECTION DIR GLOB -> in a copy whose DIR is renamed, run-checks --only SECTION says "no files match GLOB" and exits 1
glob_case() {
  local sec="$1" dir="$2" glob="$3"
  C="$(mk_copy)"
  mv "$C/$dir" "$C/$dir-renamed"
  run bash "$C/evals/run-checks.sh" --only "$sec"
  assert_rc "AC16.1 [$sec] $dir/ renamed: exit 1" 1
  assert_contains "AC16.1 [$sec] $dir/ renamed: reports no files match $glob" "$OUT" "no files match $glob"
}
# corpus first: the real tree has files for every glob, so each section passes and never says it
C="$(mk_copy)"
for sec in dupmax sed gnu soh; do
  run bash "$C/evals/run-checks.sh" --only "$sec"
  assert_rc "AC16.1 the real tree passes --only $sec" 0
  assert_not_contains "AC16.1 the real tree: --only $sec never says no files match" "$OUT" "no files match"
done
for sec in dupmax sed gnu soh; do
  glob_case "$sec" tools   'tools/*.sh'
  glob_case "$sec" scripts 'scripts/*.sh'
  glob_case "$sec" tests   'tests/*.sh'
done
# only the empty glob is named
C="$(mk_copy)"; mv "$C/tools" "$C/tools-renamed"
run bash "$C/evals/run-checks.sh" --only gnu
assert_not_contains "AC16.1 only the empty glob is named (scripts/*.sh matches, so it is not reported)" "$OUT" "no files match scripts/*.sh"
assert_not_contains "AC16.1 only the empty glob is named (tests/*.sh matches, so it is not reported)" "$OUT" "no files match tests/*.sh"
# a section that does not read the glob does not fail for it
run bash "$C/evals/run-checks.sh" --only scenarios
assert_rc "AC16.1 --only scenarios does not read tools/*.sh: exit 0" 0
# skills
C="$(mk_copy)"; mv "$C/skills" "$C/skills-renamed"
run bash "$C/evals/run-checks.sh" --only skills
assert_rc "AC16.1 [skills] skills/ renamed: exit 1" 1
assert_contains "AC16.1 [skills] skills/ renamed: reports no files match skills/*" "$OUT" "no files match skills/*"
# shellcheck, where it is installed
if command -v shellcheck >/dev/null 2>&1; then
  glob_case shellcheck tools   'tools/*.sh'
  glob_case shellcheck scripts 'scripts/*.sh'
else
  t_skip 4 "AC16.1 [shellcheck] needs shellcheck installed"
fi
# the full run: the files group loops over the same globs
C="$(mk_copy)"; mv "$C/tools" "$C/tools-renamed"
run bash "$C/evals/run-checks.sh"
assert_rc "AC16.1 [full run] tools/ renamed: exit 1" 1
assert_contains "AC16.1 [full run] tools/ renamed: reports no files match tools/*.sh" "$OUT" "no files match tools/*.sh"
C="$(mk_copy)"; mv "$C/scripts" "$C/scripts-renamed"
run bash "$C/evals/run-checks.sh"
assert_rc "AC16.1 [full run] scripts/ renamed: exit 1" 1
assert_contains "AC16.1 [full run] scripts/ renamed: reports no files match scripts/*.sh" "$OUT" "no files match scripts/*.sh"

t_summary
