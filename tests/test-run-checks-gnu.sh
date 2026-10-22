#!/usr/bin/env bash
# Tests of the GNU-only option scanner of evals/run-checks.sh (section gnu): options, the gnu-ok marker, long options, the
# quote-aware comment stripper (split from test-run-checks.sh in v0.23.3). The tokenizer cases are in test-run-checks-gnu9.sh.
# Each test runs run-checks.sh inside a fresh copy of the repository, so mutations never touch the real tree.
# Cases whose findings come only from their own fixture file run in mk_min_copy (run-checks-fixture.sh); the real-tree runs use mk_copy.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/run-checks-fixture.sh"

# ---- v0.22.1 AC5.1: GNU-only options are refused outside comments (BSD/macOS lacks them) ----
# Every construct is spelled through variables, so this file does not trip its own check.
echo "v0.22.1 AC5.1 GNU-only options"
G="grep"; PF="-P"; RL="readlink"; FF="-f"; DT="date"; DD="-d"; ST="stat"; CC="-c"; FD="find"; PR="-printf"; XA="xargs"; XR="-r"; SD2="sed"
# gnu_case NAME FILE BODY-LINE EXPECT(fail|pass) [CONSTRUCT] -> FILE (under the copy) gets BODY-LINE as its line 3
gnu_case() {
  local name="$1" rel="$2" line="$3" expect="$4" construct="${5:-}"
  C="$(mk_min_copy)"
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
# ---- v0.24.24: grep with both ignore-case and fixed-strings aborts in Git for Windows grep 3.0 (core dump, rc 134) ----
echo "v0.24.24 a grep with ignore-case and fixed-strings is refused (Git for Windows grep 3.0 aborts)"
# spelled through variables, so this file does not trip its own check
CK="ignore-case+fixed-strings"; QIF="-qiF"; I1="-i"; F1="-F"; FI="-Fi"; LI="--ignore-case"; LF="--fixed-strings"
gnu_case "ignore-case and fixed-strings in one cluster"        tests/zz-gnu.sh   "$G $QIF x f" fail "$CK"
gnu_case "ignore-case and fixed-strings as separate flags"     scripts/zz-gnu.sh "$G $I1 $F1 x f" fail "$CK"
gnu_case "fixed-strings first in a cluster"                    tools/zz-gnu.sh   "$G $FI x f" fail "$CK"
gnu_case "two flags with others between them"                  tests/zz-gnu.sh   "$G -n $I1 -q $F1 -- x f" fail "$CK"
gnu_case "long ignore-case with short fixed-strings"           evals/zz-gnu.sh   "$G $LI $F1 x f" fail "$CK"
gnu_case "short ignore-case with long fixed-strings"           tests/zz-gnu.sh   "$G $I1 $LF x f" fail "$CK"
gnu_case "after a pipe"                                        scripts/zz-gnu.sh "printf a | $G $QIF x" fail "$CK"
gnu_case "inside a substitution"                               install.sh        "v=\$(printf a | $G $QIF x)" fail "$CK"
gnu_case "flags after the operands"                            tests/zz-gnu.sh   "$G x f $I1 $F1" fail "$CK"
gnu_case "an if condition"                                     tests/zz-gnu.sh   "if printf a | $G $QIF x; then :; fi" fail "$CK"
gnu_case "fixed-strings alone"                                 tests/zz-gnu.sh   "$G $F1 x f >/dev/null" pass
gnu_case "ignore-case alone"                                   tests/zz-gnu.sh   "$G $I1 x f >/dev/null" pass
gnu_case "quiet fixed-strings and ignore-case on two commands" tests/zz-gnu.sh   "$G $I1 x f | $G $F1 y >/dev/null" pass
gnu_case "the two joined by a semicolon are two commands"      tests/zz-gnu.sh   "$G $I1 x f; $G $F1 y f >/dev/null" pass
gnu_case "a whole-line comment"                                scripts/zz-gnu.sh "# $G $QIF x f" pass
gnu_case "flags after the end-of-options marker are operands"  tests/zz-gnu.sh   "$G $F1 -- $I1 f >/dev/null" pass
gnu_case "ignore-case with the extended-regex flag"            tests/zz-gnu.sh   "$G -iE x f >/dev/null" pass
gnu_case "the i of a pattern argument is not a flag"           tests/zz-gnu.sh   "$G $F1 -e -i f >/dev/null" pass
# the repository itself stays clean and says so
C="$(mk_copy)"
run bash "$C/evals/run-checks.sh"
assert_rc "AC5.1 the real tree passes run-checks" 0
assert_contains "AC5.1 the ok line is printed" "$OUT" "  ok   GNU-only options absent (BSD/macOS)"
assert_contains "v0.24.24 the real tree has no grep pairing ignore-case with fixed-strings" "$OUT" "  ok   no grep call pairs ignore-case with fixed-strings"
FULL_RC=$RC; FULL_OUT="$OUT"   # AC6 below asserts on the same run

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
# the same full run as AC5.1 above (same tree, same command): its result is reused, not run a second time
RC=$FULL_RC; OUT="$FULL_OUT"
assert_rc "AC6 the real tree passes a full run-checks with the new rules" 0
assert_contains "AC6 the gnu ok line is printed" "$OUT" "  ok   GNU-only options absent (BSD/macOS)"


t_summary
