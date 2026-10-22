#!/usr/bin/env bash
# Tests of the GNU-only scanner's tokenizer (evals/run-checks.sh --only gnu): quote state across lines, heredocs, arithmetic,
# variables named after a checked tool, wrappers (split from test-run-checks.sh in v0.23.3).
# Each test runs run-checks.sh inside a fresh copy of the repository, so mutations never touch the real tree.
# Cases whose findings come only from their own fixture file run in mk_min_copy (run-checks-fixture.sh); the real-tree runs (the AC9 pass and AC1.3) use mk_copy.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/run-checks-fixture.sh"
# the pieces the fixtures are spelled from (the checker would flag this file otherwise)
G="grep"; PF="-P"; FF="-f"; DD="-d"; CC="-c"; FD="find"; PR="-printf"; XA="xargs"; XR="-r"; SD2="sed"
MK='# gnu-ok:'
B='\'; Q="'"

# ---- v0.23.2 AC9: GNU tokenizer gaps (evals/run-checks.sh --only gnu) ----
# Constructs are built from pieces (DL = a dollar sign, DQ = a double quote, BT = a backtick, LB = an open brace, B = one
# backslash, Q = a single quote), so this file does not trip its own check, before or after the checker gets stricter.
echo "v0.23.2 AC9 GNU tokenizer: constructs the per-line scanner missed"
DL='$'; DQ='"'; BT='`'; LB='{'
# gnu9 NAME FILE EXPECT(fail|pass) LINE-NUMBER BODY-LINE... -> FILE (under the copy) gets #! and a comment line, then the
# BODY-LINEs from line 3 on; for fail the output names FILE:LINE-NUMBER, for pass the file is not named
gnu9() {
  local name="$1" rel="$2" expect="$3" ln="$4"; shift 4
  C="$(mk_min_copy)"
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
# F3: a comment that starts right after an operator is a comment; its apostrophe must not open a quote
gnu9 "F3 a comment right after ';' with an apostrophe, then the flag"  tests/zz-gnu.sh fail 4 "true;# it${Q}s" "$G $PF y"
gnu9 "F3 a comment right after ')' with an apostrophe, then the flag"  tests/zz-gnu.sh fail 4 "( true )# it${Q}s" "$G $PF y"
gnu9 "F3 a comment right after '|' with an apostrophe, then the flag"  tests/zz-gnu.sh fail 4 "a|# it${Q}s" "$G $PF y"
gnu9 "F3 a comment right after '&' with an apostrophe, then the flag"  tests/zz-gnu.sh fail 4 "true &# it${Q}s" "$G $PF y"
gnu9 "F3 a comment right after '(' with an apostrophe, then the flag"  tests/zz-gnu.sh fail 4 "(# it${Q}s" "$G $PF y"
gnu9 "F3 a flag inside a comment after ';' is hidden"                  tests/zz-gnu.sh pass 3 "true;# $G $PF y"
gnu9 "F3 control: a # inside a word is not a comment, the flag is code" tests/zz-gnu.sh fail 3 "echo a#b; $G $PF y"
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



# ---- v0.23.3 AC7.1 / R6: (( x << y )) is arithmetic, not a heredoc; a heredoc word may contain a dash ----
# A false heredoc swallows every later line as a "body" that is read as code on its own, so a flag inside a later multi-line
# quoted string is reported. Fixtures are built from the same pieces as above (DL, DQ, LB, Q, G, PF, SD2).
echo "v0.23.3 AC7.1 arithmetic << is not a heredoc, <<END-X is one"
gnu9 "AC7.1 (( x << y )) then a multi-line single-quoted string holding the flag" tests/zz-gnu.sh pass 3 "(( x << y ))" "echo ${Q}a" "$G $PF x" "${Q}"
gnu9 "AC7.1 \$(( x << y )) then a multi-line single-quoted string holding the flag" tests/zz-gnu.sh pass 3 "z=${DL}(( x << y ))" "echo ${Q}a" "$G $PF x" "${Q}"
gnu9 "AC7.1 (( x<<y )) without blanks, then the multi-line string" tests/zz-gnu.sh pass 3 "(( x<<y ))" "echo ${Q}a" "$G $PF x" "${Q}"
gnu9 "AC7.1 (( x << y )) then a multi-line double-quoted string holding the flag" tests/zz-gnu.sh pass 3 "(( x << y ))" "echo ${DQ}a" "$G $PF x" "${DQ}"
gnu9 "AC7.1 <<END-X (a dash in the word), its terminator, then a multi-line single-quoted string holding the flag" tests/zz-gnu.sh pass 3 "cat <<END-X" "text" "END-X" "echo ${Q}a" "$G $PF x" "${Q}"
gnu9 "AC7.1 <<'END-X' (quoted, a dash), its terminator, then a multi-line single-quoted string holding the flag" tests/zz-gnu.sh pass 3 "cat <<${Q}END-X${Q}" "text" "END-X" "echo ${Q}a" "$G $PF x" "${Q}"
gnu9 "AC7.1 <<-END-X (tab-indented), its terminator, then a multi-line single-quoted string holding the flag" tests/zz-gnu.sh pass 3 "cat <<-END-X" "text" "$(printf '\t')END-X" "echo ${Q}a" "$G $PF x" "${Q}"
# controls: the flag as plain code after the arithmetic or after the terminator is still reported
gnu9 "AC7.1 control: the flag on a plain line after (( x << y ))" tests/zz-gnu.sh fail 5 "(( x << y ))" "echo done" "$G $PF x"
gnu9 "AC7.1 control: the flag on a plain line after the terminator END-X" tests/zz-gnu.sh fail 7 "cat <<END-X" "text" "END-X" "echo done" "$G $PF x"
gnu9 "AC7.1 control: a real heredoc <<EOF still ends at EOF, the flag after it is code" tests/zz-gnu.sh fail 7 "cat <<EOF" "text" "EOF" "echo done" "$G $PF x"
gnu9 "AC7.1 control: a here-string is not a heredoc, the flag after it is code" tests/zz-gnu.sh fail 5 "cat <<< hi" "echo done" "$G $PF x"

# ---- v0.23.3 AC7.2 / R1: assignments and wrappers before a variable command word ----
echo "v0.23.3 AC7.2 an assignment or a wrapper before a variable named after a checked tool"
gnu9 "AC7.2 LC_ALL=C then the variable" tests/zz-gnu.sh fail 3 "LC_ALL=C ${DL}GREP $PF x"
gnu9 "AC7.2 two assignments then the variable" tests/zz-gnu.sh fail 3 "LC_ALL=C FOO=1 ${DL}GREP $PF x"
gnu9 "AC7.2 LC_ALL=C then the braced variable" tests/zz-gnu.sh fail 3 "LC_ALL=C ${DL}${LB}GREP} $PF x"
gnu9 "AC7.2 sudo -u u then the variable" tests/zz-gnu.sh fail 3 "sudo -u u ${DL}GREP $PF x"
gnu9 "AC7.2 sudo then the variable" tests/zz-gnu.sh fail 3 "sudo ${DL}GREP $PF x"
gnu9 "AC7.2 env then the variable" tests/zz-gnu.sh fail 3 "env ${DL}GREP $PF x"
gnu9 "AC7.2 env FOO=1 then the variable" tests/zz-gnu.sh fail 3 "env FOO=1 ${DL}GREP $PF x"
gnu9 "AC7.2 env -u V FOO=1 then the variable" tests/zz-gnu.sh fail 3 "env -u V FOO=1 ${DL}GREP $PF x"
gnu9 "AC7.2 time then the variable" tests/zz-gnu.sh fail 3 "time ${DL}SED -r x"
gnu9 "AC7.2 time -p then the variable" tests/zz-gnu.sh fail 3 "time -p ${DL}SED -r x"
gnu9 "AC7.2 nice -n 5 then the variable" tests/zz-gnu.sh fail 3 "nice -n 5 ${DL}GREP $PF x"
gnu9 "AC7.2 command then the variable" tests/zz-gnu.sh fail 3 "command ${DL}GREP $PF x"
gnu9 "AC7.2 exec then the variable" tests/zz-gnu.sh fail 3 "exec ${DL}GREP $PF x"
gnu9 "AC7.2 exec -a NAME then the variable" tests/zz-gnu.sh fail 3 "exec -a n ${DL}GREP $PF x"
gnu9 "AC7.2 a wrapper chain: sudo -u u env FOO=1 nice -n 5 then the variable" tests/zz-gnu.sh fail 3 "sudo -u u env FOO=1 nice -n 5 ${DL}GREP $PF x"
gnu9 "AC7.2 a wrapper after a pipe" tests/zz-gnu.sh fail 3 "cat f | sudo ${DL}GREP $PF x"
gnu9 "AC7.2 an assignment after then" tests/zz-gnu.sh fail 3 "if true; then LC_ALL=C ${DL}GREP $PF x; fi"
gnu9 "AC7.2 a wrapper in a command substitution" tests/zz-gnu.sh fail 3 "y=${DL}(env LC_ALL=C ${DL}GREP $PF x f)"
# the tool written out after a wrapper was flagged before and stays flagged
gnu9 "AC7.2 corpus: sudo grep with the PCRE flag stays flagged" tests/zz-gnu.sh fail 3 "sudo $G $PF x"
gnu9 "AC7.2 corpus: sudo -u u grep with the PCRE flag stays flagged" tests/zz-gnu.sh fail 3 "sudo -u u $G $PF x"
gnu9 "AC7.2 corpus: env grep with the PCRE flag stays flagged" tests/zz-gnu.sh fail 3 "env $G $PF x"
# not flagged: command -v / -V is a lookup, the variable is then an argument, not a command word
gnu9 "AC7.2 control: command -v then the variable is a lookup" tests/zz-gnu.sh pass 3 "command -v ${DL}GREP $PF x"
gnu9 "AC7.2 control: command -V then the variable is a lookup" tests/zz-gnu.sh pass 3 "command -V ${DL}GREP $PF x"
gnu9 "AC7.2 control: the variable after echo is an argument" tests/zz-gnu.sh pass 3 "echo LC_ALL=C ${DL}GREP $PF x"
gnu9 "AC7.2 control: a longer variable name after an assignment is another variable" tests/zz-gnu.sh pass 3 "LC_ALL=C ${DL}GREPPER $PF x"
gnu9 "AC7.2 control: an assignment alone, with no command word" tests/zz-gnu.sh pass 3 "LC_ALL=C"
gnu9 "AC7.2 control: a GNU-ok marker with a reason exempts a wrapped variable" tests/zz-gnu.sh pass 3 "sudo -u u ${DL}GREP $PF x $MK needs PCRE here"

# ---- v0.23.3 review of lane B ----
echo "v0.23.3 review F2 a (( inside quotes is text, not arithmetic"
# F2: a quoted (( made the later << look like arithmetic, so the heredoc was missed and its body (an apostrophe) opened a quote
gnu9 "review F2 echo \"((\" then a heredoc with an apostrophe, then the flag" tests/zz-gnu.sh fail 6 "echo ${DQ}((${DQ}; cat <<EOF" "it${Q}s" "EOF" "$G $PF x f"
gnu9 "review F2 echo '((' then a heredoc with an apostrophe, then the flag"  tests/zz-gnu.sh fail 6 "echo ${Q}((${Q}; cat <<EOF" "it${Q}s" "EOF" "$G $PF x f"
gnu9 "review F2 control: a real (( )) before << is still arithmetic"         tests/zz-gnu.sh pass 3 "(( x << y ))" "echo ${Q}a" "$G $PF x" "${Q}"

echo "v0.23.3 review N3 timeout DURATION before a variable command word"
gnu9 "review N3 timeout 5 then the variable"                     tests/zz-gnu.sh fail 3 "timeout 5 ${DL}GREP $PF x"
gnu9 "review N3 timeout -s KILL 5 then the variable"             tests/zz-gnu.sh fail 3 "timeout -s KILL 5 ${DL}GREP $PF x"
gnu9 "review N3 timeout -k 2 5 then the braced variable"         tests/zz-gnu.sh fail 3 "timeout -k 2 5 ${DL}${LB}GREP} $PF x"
gnu9 "review N3 corpus: timeout 5 then the tool written out"     tests/zz-gnu.sh fail 3 "timeout 5 $G $PF x"
gnu9 "review N3 control: timeout 5 then a clean variable use"    tests/zz-gnu.sh pass 3 "timeout 5 ${DL}GREP -i x f"
gnu9 "review N3 control: the variable as an argument of timeout's command" tests/zz-gnu.sh pass 3 "timeout 5 echo ${DL}GREP $PF"

echo "v0.23.3 round 3 R1 a quoted \$(( x << y )) is arithmetic, the heredoc check skips it"
# R1: with the count of an opening $(( inside double quotes dropped, the << read as a heredoc and the body lines after it
# were scanned as code, so the flag inside the later multi-line single-quoted string was reported
gnu9 "R1 \"\$(( x << y ))\" in double quotes, then a multi-line string holding the flag" tests/zz-gnu.sh pass 3 "echo ${DQ}${DL}(( x << y ))${DQ}" "echo ${Q}a" "$G $PF x" "${Q}"
gnu9 "R1 nested \$(( \$(( x << y )) << z )) in double quotes, then the multi-line string" tests/zz-gnu.sh pass 3 "echo ${DQ}${DL}(( ${DL}(( x << y )) << z ))${DQ}" "echo ${Q}a" "$G $PF x" "${Q}"
gnu9 "R1 control: the flag after the quoted arithmetic on a plain line is still code" tests/zz-gnu.sh fail 4 "echo ${DQ}${DL}(( x << y ))${DQ}" "$G $PF x"

echo "v0.23.3 round 3 R2 known limit: arithmetic state is per line"
# R2: an arithmetic (( )) that spans lines is not tracked (the scan header says so); its second line "y << z ))" starts a false heredoc
# whose body is read as code on its own, so the flag after it is reported. This pins today's behaviour of that known limit: if
# arithmetic ever becomes multi-line aware, this case flips to pass and its expectation is to be changed with the header.
# (the variable is named stat so that line 3 passes the no-tool prefilter and the scan really sees the open ((; a line without a tool word or quote is skipped)
gnu9 "R2 limit: (( stat + then y << z )) is a false heredoc; its body line holding the flag is scanned" tests/zz-gnu.sh fail 6 "(( stat +" "y << z ))" "echo ${Q}a" "$G $PF x" "${Q}"

echo "v0.23.3 round 3 R7 timeout with long options before a variable command word"
gnu9 "R7 timeout --signal KILL 5 then the variable"              tests/zz-gnu.sh fail 3 "timeout --signal KILL 5 ${DL}GREP $PF x"
gnu9 "R7 timeout --kill-after 2 5 then the variable"             tests/zz-gnu.sh fail 3 "timeout --kill-after 2 5 ${DL}GREP $PF x"
gnu9 "R7 timeout --signal=KILL 5 then the variable (attached value)" tests/zz-gnu.sh fail 3 "timeout --signal=KILL 5 ${DL}GREP $PF x"
gnu9 "R7 timeout --foreground 5 then the variable (a long flag with no value)" tests/zz-gnu.sh fail 3 "timeout --foreground 5 ${DL}GREP $PF x"
gnu9 "R7 control: timeout --signal KILL 5 then a clean variable use" tests/zz-gnu.sh pass 3 "timeout --signal KILL 5 ${DL}GREP -i x f"
gnu9 "R7 control: timeout --kill-after 2 5 then echo, the variable is an argument" tests/zz-gnu.sh pass 3 "timeout --kill-after 2 5 echo ${DL}GREP $PF"

echo "v0.23.3 round 3 R3 a \${NAME} word is matched the same on every run, also under one-true-awk"
# R3: match(substr(s, i + 2, 64), ...) gave different answers from run to run under original-awk, so a ${GREP} word was
# sometimes not recognised. The fixture holds twelve such lines (the more lines, the surer a flaky match shows); every run must name all of them.
# tools/bsd-check.sh is the oracle for the whole suite; this case finds the same awk (original-awk, else nawk) and puts it first on PATH.
r3_lines=(); r3_k=0
while [ "$r3_k" -lt 6 ]; do r3_lines+=("sudo ${DL}${LB}GREP} $PF x" "${DL}${LB}GREP} $PF x"); r3_k=$((r3_k + 1)); done
# r3_runs LABEL COUNT [AWKDIR] -> COUNT runs of --only gnu over the twelve-line fixture; each must exit 1 and name lines 3..14
r3_runs() {
  local label="$1" cnt="$2" awd="${3:-}" r=0 oldp="$PATH" ln missing
  C="$(mk_min_copy)"
  printf '%s\n' '#!/usr/bin/env bash' '# fixture' "${r3_lines[@]}" > "$C/tests/zz-gnu.sh"
  while [ "$r" -lt "$cnt" ]; do
    r=$((r + 1))
    if [ -n "$awd" ]; then PATH="$awd:$oldp"; fi
    checks "$C" gnu
    PATH="$oldp"
    missing=""; ln=3
    while [ "$ln" -le 14 ]; do
      case "$OUT" in *"tests/zz-gnu.sh:$ln "*) ;; *) missing="$missing $ln" ;; esac
      ln=$((ln + 1))
    done
    assert_rc "R3 $label run $r: exit 1" 1
    assert_eq "R3 $label run $r: every \${NAME} line is named (missing:)" "" "${missing# }"
  done
}
r3_runs "default awk" 3
R3AWK=""
for r3_c in original-awk nawk; do
  if command -v "$r3_c" >/dev/null 2>&1; then R3AWK="$(command -v "$r3_c")"; break; fi
done
if [ -n "$R3AWK" ]; then
  R3D="$(mk_tmp)"
  { ln -s "$R3AWK" "$R3D/awk" 2>/dev/null && [ -x "$R3D/awk" ]; } || { rm -f "$R3D/awk"; cp "$R3AWK" "$R3D/awk" && chmod +x "$R3D/awk"; }
  r3_runs "one-true-awk" 10 "$R3D"
else
  t_skip 20 "R3 one-true-awk runs need original-awk or nawk (tools/bsd-check.sh is the oracle)"
fi

echo "v0.23.3 review F1 the arithmetic check is linear in the line length"
# F1: for every << the check rescanned the whole line before it, so a long line with many heredoc operators took
# O(length x operators). The same line without << is the baseline; the budget is baseline + 8 s.
# gen_long PREFIX-COUNT WORD COUNT -> one line: PREFIX-COUNT "((a)) " groups, then COUNT copies of WORD (WORD is "x<<A " or "x<A ": both pass the no-tool prefilter, only the first holds a heredoc operator)
gen_long() { awk -v n="$1" -v w="$2" -v m="$3" 'BEGIN { for (i = 0; i < n; i++) s = s "((a)) "; for (i = 0; i < m; i++) s = s w; print s }'; }
# time_long WORD COUNT -> sets LELAPSED (seconds) and RC/OUT of run-checks --only gnu over a file holding that long line, then a line A
time_long() {
  local line; line="$(gen_long 1000 "$1" "$2")"
  C="$(mk_min_copy)"
  printf '%s\n' '#!/usr/bin/env bash' '# fixture' "$line" 'A' > "$C/tests/zz-gnu.sh"
  local t0=$SECONDS
  checks "$C" gnu
  LELAPSED=$((SECONDS - t0))
}
HD="<<"
time_long "x<A " 2800   # R6: a scanned word (the "<" keeps the line past the no-tool prefilter), still no heredoc operator
LBASE=$LELAPSED
assert_rc "review F1 baseline (no heredoc operators): exit 0" 0
time_long "x${HD}A " 2800
assert_rc "review F1 2800 heredoc operators after 1000 closed (( )) groups: exit 0" 0
if [ "$LELAPSED" -le $((LBASE + 8)) ]; then t_ok "review F1 the heredoc line took ${LELAPSED}s, baseline ${LBASE}s (budget baseline + 8 s)"
else t_bad "review F1 the heredoc line took ${LELAPSED}s, baseline ${LBASE}s (budget baseline + 8 s)" "quadratic in the line length"; fi

echo "v0.24.2 AC1.2 the scanner reads one very long line in linear time under one-true-awk (macOS CI was 3-4x slower than Linux)"
# AC1.2: one-true-awk's substr(s, i, 1) costs O(i), so a per-character loop over a long line is quadratic there. The slow case is one
# line of SLOWK x 2000 characters (each 2000-character segment: a double-quoted text, then command substitutions as code); the baseline
# is the same bytes as SLOWK lines of 2000 characters. Budget: slow <= 3 x baseline + 8 s. The spec says 20000 characters; at 20000 the
# quadratic cost is only ~2-3 s on one-true-awk 20231127 (measured: 6 s against 3 s), well inside the budget, so the size is raised until
# the old scanner is over it (60000 characters: ~36 s against a 4 s baseline).
# Both runs must find the same thing: one GNU-only flag at the very end of the data, so a scanner that gets lost in the long quote is caught.
SLOWK=30
g9_seg="$(awk 'BEGIN { s = "x=\""; while (length(s) < 1000) s = s "abc def "; s = s "\"; "; while (length(s) < 1990) s = s "a$(b) "; print s "true;" }')"
g9_one=""; g9_k=0
while [ "$g9_k" -lt "$SLOWK" ]; do g9_one="$g9_one$g9_seg "; g9_k=$((g9_k + 1)); done
g9_lines=(); g9_k=1
while [ "$g9_k" -lt "$SLOWK" ]; do g9_lines+=("$g9_seg"); g9_k=$((g9_k + 1)); done
g9_lines+=("$g9_seg $G $PF x")
# g9_time LABEL AWKDIR LINE... -> TSEC (seconds), TRC, TOUT of --only gnu over tests/zz-gnu.sh holding the LINEs (AWKDIR empty: default awk)
g9_time() {
  local label="$1" awd="$2" oldp="$PATH" t0; shift 2
  C="$(mk_min_copy)"
  printf '%s\n' '#!/usr/bin/env bash' '# fixture' "$@" > "$C/tests/zz-gnu.sh"
  if [ -n "$awd" ]; then PATH="$awd:$oldp"; fi
  t0=$SECONDS
  checks "$C" gnu
  TSEC=$((SECONDS - t0))
  PATH="$oldp"
  TRC=$RC; TOUT="$OUT"
}
G9AWK=""
for g9_c in original-awk nawk; do
  if command -v "$g9_c" >/dev/null 2>&1; then G9AWK="$(command -v "$g9_c")"; break; fi
done
if [ -n "$G9AWK" ]; then
  G9D="$(mk_tmp)"
  { ln -s "$G9AWK" "$G9D/awk" 2>/dev/null && [ -x "$G9D/awk" ]; } || { rm -f "$G9D/awk"; cp "$G9AWK" "$G9D/awk" && chmod +x "$G9D/awk"; }
  g9_time "default one line" "" "$g9_one$G $PF x"
  G9DEF_RC=$TRC; G9DEF_OUT="$TOUT"
  g9_time "slow" "$G9D" "$g9_one$G $PF x"
  G9A_T=$TSEC; G9A_RC=$TRC; G9A_OUT="$TOUT"
  g9_time "baseline" "$G9D" "${g9_lines[@]}"
  G9B_T=$TSEC; G9B_RC=$TRC; G9B_OUT="$TOUT"
  assert_eq "AC1.2 slow case (one $((SLOWK * 2000))-character line): exit 1" "1" "$G9A_RC"
  assert_contains "AC1.2 slow case: the flag at the end of the line is named (tests/zz-gnu.sh:3)" "$G9A_OUT" "tests/zz-gnu.sh:3"
  assert_eq "AC1.2 slow case: one finding" "1" "$(printf '%s\n' "$G9A_OUT" | grep -c 'tests/zz-gnu.sh:')"
  assert_eq "AC1.2 baseline ($SLOWK lines of 2000): exit 1" "1" "$G9B_RC"
  assert_contains "AC1.2 baseline: the flag on the last line is named (tests/zz-gnu.sh:$((SLOWK + 2)))" "$G9B_OUT" "tests/zz-gnu.sh:$((SLOWK + 2))"
  assert_eq "AC1.2 baseline: one finding" "1" "$(printf '%s\n' "$G9B_OUT" | grep -c 'tests/zz-gnu.sh:')"
  assert_eq "AC1.2 the slow line gives the same exit and findings under one-true-awk and the default awk" "$G9DEF_RC|$G9DEF_OUT" "$G9A_RC|$G9A_OUT"
  if [ "$G9A_T" -le $((3 * G9B_T + 8)) ]; then t_ok "AC1.2 the long line took ${G9A_T}s, baseline ${G9B_T}s (budget 3 x baseline + 8 s)"
  else t_bad "AC1.2 the long line took ${G9A_T}s, baseline ${G9B_T}s (budget 3 x baseline + 8 s)" "quadratic in the line length under one-true-awk"; fi
else
  t_skip 9 "AC1.2 the long-line watchdog needs original-awk or nawk (tools/bsd-check.sh is the oracle)"
fi

echo "v0.24.2 AC1.3 the GNU findings over the whole tree equal those of the v0.24.0 scanner"
# The scanner is rewritten for speed; its answers must not change. The base copy is evals/run-checks.sh at 4517824 (v0.24.0 merged).
G9BASE_SHA=4517824
G9BASEF="$(mk_tmp)/run-checks.base.sh"
if command -v git >/dev/null 2>&1 && git -C "$PB_ROOT" show "$G9BASE_SHA:evals/run-checks.sh" > "$G9BASEF" 2>/dev/null && [ -s "$G9BASEF" ]; then
  C="$(mk_copy)"
  cp "$G9BASEF" "$C/evals/run-checks-base.sh"
  run bash "$C/evals/run-checks-base.sh" --only gnu
  G9BASE_RC=$RC; G9BASE_OUT="$OUT"
  run bash "$C/evals/run-checks.sh" --only gnu
  G9NEW_RC=$RC; G9NEW_OUT="$OUT"
  assert_eq "AC1.3 the new scanner exits as the base scanner over every *.sh of the tree" "$G9BASE_RC" "$G9NEW_RC"
  # v0.24.24 added one check to the gnu group after the base (ok "no grep call pairs ignore-case with fixed-strings").
  # Drop exactly that one line, by whole-line match, from the new output; every other line must stay identical.
  G9NEWLINE="  ok   no grep call pairs ignore-case with fixed-strings"
  assert_contains "AC1.3 the new gnu group prints its added ignore-case/fixed-strings ok line" "$G9NEW_OUT" "$G9NEWLINE"
  G9NEW_SAME="$(printf '%s\n' "$G9NEW_OUT" | grep -vxF -e "$G9NEWLINE")"
  assert_eq "AC1.3 the new scanner prints the same lines as the base scanner over every *.sh of the tree (minus the one added ok line)" "$G9BASE_OUT" "$G9NEW_SAME"
  assert_contains "AC1.3 sanity: the base run scanned (it printed the GNU summary lines)" "$G9BASE_OUT" "ok"
else
  t_skip 3 "AC1.3 the base scanner is not available (git, or $G9BASE_SHA, missing)"
fi

echo "v0.24.4 AC6 the gnu check fails closed: a missing file in the scanned list is a FAIL, never an ok"
# install.sh is named in the scanned list; when it is missing awk aborts on it, and the section used to print ok and exit 0.
C="$(mk_min_copy)"
rm -f "$C/install.sh"
run bash "$C/evals/run-checks.sh" --only gnu
G6M_RC=$RC; G6M_OUT="$OUT"
assert_eq "AC6 install.sh missing: exit 1" "1" "$G6M_RC"
assert_contains "AC6 install.sh missing: a FAIL line" "$G6M_OUT" "FAIL"
assert_contains "AC6 install.sh missing: the missing file is named" "$G6M_OUT" "install.sh"
assert_not_contains "AC6 install.sh missing: no ok line for the GNU check" "$G6M_OUT" "ok   GNU-only options absent"
C="$(mk_min_copy)"
run bash "$C/evals/run-checks.sh" --only gnu
assert_eq "AC6 regression: all scanned files present: exit 0" "0" "$RC"
assert_contains "AC6 regression: all scanned files present: the ok line stays" "$OUT" "ok   GNU-only options absent"
C="$(mk_min_copy)"
rm -f "$C/tools/stub.sh"
run bash "$C/evals/run-checks.sh" --only gnu
assert_eq "AC6 regression: an empty glob (tools/*.sh) still FAILs" "1" "$RC"
assert_contains "AC6 regression: an empty glob is still named" "$OUT" "no files match tools/*.sh"

t_summary
