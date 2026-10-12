#!/usr/bin/env bash
# Tests of the GNU-only scanner's tokenizer (evals/run-checks.sh --only gnu): quote state across lines, heredocs, arithmetic,
# variables named after a checked tool, wrappers (split from test-run-checks.sh in v0.23.3).
# Each test runs run-checks.sh inside a fresh copy of the repository, so mutations never touch the real tree.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/run-checks-fixture.sh"
# the pieces the fixtures are spelled from (the checker would flag this file otherwise)
G=grep; PF=-P; RL=readlink; FF=-f; DT=date; DD=-d; ST=stat; CC=-c; FD=find; PR=-printf; XA=xargs; XR=-r; SD2=sed
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

t_summary
