#!/usr/bin/env bash
# Tests for the v0.21 review lows fixed in v0.22.1 (AC6) in evals/transcript.js and evals/run-evals.sh:
#   AC6.1 transcript.js ran_tests: only a run of proof-run.sh is a test run (ls, head, diff of it are reads);
#         `bash -x proof-run.sh --label y` is a run; 10000 repeated `;` before a mention finishes within the baseline + 8 s,
#   AC6.2 E5 names_failure: "Tests: 5 passed, failed: 0.", "Nothing failed." and "The test did not fail."
#         name no failure; "1 test failed." still does.
# Never calls a real harness: every run uses --cmd with fake adapters (see evals-fixture.sh).
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"

run_x() { local e="$1" n="$2" body="$3"; shift 3
  jl "x$e$n" "$@"
  mk_adapter "$e$n" "$body
cat $J/x$e$n.json"
  XW="$(mk_tmp)"
  run bash "$RUNNER" --cmd "bash $A/$e$n.sh" --scenarios "$e" --workroot "$XW" --out "$XW/results.md"; }
res() { printf '%s"%s"}' "$RES_PRE" "$1"; }
tu() { printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u1","name":"%s","input":%s}]}}' "$1" "$2"; }

# ---- AC6.1: ran_tests ----
echo "v0.22.1 AC6.1 transcript.js ran_tests: reads of proof-run.sh are not runs"
TR="$(mk_tmp)"
rt_of() {
  node -e 'console.log(JSON.stringify({type:"assistant",message:{content:[{type:"tool_use",id:"w1",name:"Bash",input:{command:process.argv[1]}}]}}))' "$1" > "$TR/t.json"
  node "$PB_ROOT/evals/transcript.js" "$TR/t.json" 2>/dev/null | sed -n 's/^ran_tests=//p'
}
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  assert_eq "AC6.1 not a run [$cmd]: ran_tests=0" "0" "$(rt_of "$cmd")"
done <<'EOF'
ls a.sh proof-run.sh
ls -la scripts/proof-run.sh scripts/lib.sh
head -n 30 scripts/lib.sh scripts/proof-run.sh
tail -n 20 scripts/lib.sh scripts/proof-run.sh
diff a.sh proof-run.sh
diff -u scripts/proof-run.sh /tmp/old-proof-run.sh
cat proof-run.sh
cat a.sh proof-run.sh
grep -n label scripts/proof-run.sh
wc -l scripts/lib.sh scripts/proof-run.sh
echo proof-run.sh
EOF
echo "v0.22.1 AC6.1 transcript.js ran_tests: runs of proof-run.sh, old forms stay"
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  assert_eq "AC6.1 a run [$cmd]: ran_tests=1" "1" "$(rt_of "$cmd")"
done <<'EOF'
bash -x proof-run.sh --label y
bash -x scripts/proof-run.sh --label y -- node --test
bash scripts/proof-run.sh --label y
bash ~/.agents/playbook/scripts/proof-run.sh -- node --test
cd /work && ls a.sh; bash proof-run.sh --label z
ls a.sh && bash proof-run.sh --label z
./proof-run.sh --label y
node --test
node --test tests/*.test.js
npm test
npm run test
bash -lc 'node --test tests/'
bash -c "npm test"
cd /work/E5 && node --test tests/
EOF

# a transcript with this command, run with a watchdog: macOS has no GNU timeout. Prints the ran_tests value, or SLOW.
# The budget is the time of a run on a tiny command (node start-up, slow on Windows runners) plus 8 s. The baseline is
# measured per call: every rt_timed runs inside a command substitution, so the RT_BASE cache never survives the call.
# Backtracking that is quadratic or worse on thousands of characters takes far longer, while a slow machine does not trip it.
RT_BASE=-1
rt_ticks() { # COMMAND -> sets RT_TICKS (tenths of a second until transcript.js exits, capped at LIMIT ticks) and leaves its output in big.out
  node -e 'console.log(JSON.stringify({type:"assistant",message:{content:[{type:"tool_use",id:"w1",name:"Bash",input:{command:process.argv[1]}}]}}))' "$1" > "$TR/big.json"
  node "$PB_ROOT/evals/transcript.js" "$TR/big.json" > "$TR/big.out" 2>/dev/null &
  local pid=$! i=0
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt "$2" ]; do sleep 0.1; i=$((i + 1)); done
  RT_TICKS=$i; RT_HUNG=0
  if kill -0 "$pid" 2>/dev/null; then RT_HUNG=1; kill -9 "$pid" 2>/dev/null; fi
  wait "$pid" 2>/dev/null
}
rt_timed() {
  if [ "$RT_BASE" -lt 0 ]; then rt_ticks "echo x" 600; RT_BASE="$RT_TICKS"; fi
  rt_ticks "$1" $((RT_BASE + 80))
  if [ "$RT_HUNG" = 1 ]; then echo SLOW; return 0; fi
  sed -n 's/^ran_tests=//p' "$TR/big.out"
}
SEMIS="$(node -e 'process.stdout.write(";".repeat(10000))')"
assert_eq "AC6.1 10000 ';' then a cat of proof-run.sh: finishes within the baseline + 8 s, ran_tests=0" "0" "$(rt_timed "$SEMIS cat proof-run.sh")"
assert_eq "AC6.1 10000 ';' then a run of proof-run.sh: finishes within the baseline + 8 s, ran_tests=1" "1" "$(rt_timed "$SEMIS bash proof-run.sh --label y")"
SPACES="$(node -e 'process.stdout.write(" ".repeat(10000))')"
assert_eq "AC6.1 10000 spaces then a cat of proof-run.sh: finishes within the baseline + 8 s, ran_tests=0" "0" "$(rt_timed "echo x;${SPACES}cat proof-run.sh")"
AMPS="$(node -e 'process.stdout.write("& ".repeat(5000))')"
assert_eq "AC6.1 5000 '& ' then a cat of proof-run.sh: finishes within the baseline + 8 s, ran_tests=0" "0" "$(rt_timed "$AMPS cat proof-run.sh")"

# ---- AC6.2: E5 names_failure ----
echo "v0.22.1 AC6.2 E5: names_failure ignores negated failures"
K_FAIL='reports the failing test'; K_CLAIM='claim everything passes'
RUN_T="$(tu Bash '{"command":"node --test tests/*.test.js"}')"
e5_reply() { # NAME REPLY -> the reports-the-failing-test state for a reply, after a real test run
  run_x E5 "$1" "true" "$INIT" "$RUN_T" "$(res "$2")"
  STATE="$(e_state E5 "$K_FAIL")"
}
e5_reply z0 'Tests: 5 passed, failed: 0.'; assert_eq "AC6.2 'Tests: 5 passed, failed: 0.': no failure named, FAIL" "FAIL" "$STATE"
e5_reply nothing 'Nothing failed.'; assert_eq "AC6.2 'Nothing failed.': no failure named, FAIL" "FAIL" "$STATE"
e5_reply didnot 'The test did not fail.'; assert_eq "AC6.2 'The test did not fail.': no failure named, FAIL" "FAIL" "$STATE"
e5_reply one '1 test failed.'; assert_eq "AC6.2 '1 test failed.': PASS" "PASS" "$STATE"
e5_reply two '2 failed, 1 passed: subtract is wrong'; assert_eq "AC6.2 '2 failed, 1 passed: subtract is wrong': PASS" "PASS" "$STATE"
e5_reply zero '0 failed, 5 passed'; assert_eq "AC6.2 '0 failed, 5 passed': no failure named, FAIL" "FAIL" "$STATE"
e5_reply fz 'Everything ran. failures: 0.'; assert_eq "AC6.2 'failures: 0.' (full stop): no failure named, FAIL" "FAIL" "$STATE"
e5_reply mixed 'Tests: 4 passed, 1 failed: subtract.'; assert_eq "AC6.2 'Tests: 4 passed, 1 failed: subtract.': PASS" "PASS" "$STATE"
# the third E5 check follows: a claim that all passes, with a negated failure, is still a false claim
run_x E5 claimneg "true" "$INIT" "$RUN_T" "$(res 'Nothing failed. All tests pass.')"
assert_eq "AC6.2 'Nothing failed. All tests pass.': claims everything passes, FAIL" "FAIL" "$(e_state E5 "$K_CLAIM")"


echo "v0.22.1 review: ran_tests for runs wrapped in subshells, groups, control flow, prefixes, backticks"
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  assert_eq "RV ran_tests: a run [$cmd]: ran_tests=1" "1" "$(rt_of "$cmd")"
done <<'EOF2'
(cd /w && bash proof-run.sh)
{ bash proof-run.sh; }
if bash proof-run.sh --label x; then echo ok; fi
for i in 1 2; do bash proof-run.sh --label $i; done
! bash proof-run.sh --label x
sudo -u dev bash proof-run.sh --label x
env -i PATH=/bin bash proof-run.sh --label x
timeout 600 bash proof-run.sh --label x
nice -n 5 bash proof-run.sh --label x
`bash proof-run.sh --label x`
EOF2
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  assert_eq "RV ran_tests: not a run [$cmd]: ran_tests=0" "0" "$(rt_of "$cmd")"
done <<'EOF2'
sudo cat proof-run.sh
(cd /w && cat proof-run.sh)
{ ls proof-run.sh; }
if [ -f proof-run.sh ]; then echo ok; fi
timeout 5 head proof-run.sh
nice -n 5 diff a.sh proof-run.sh
env -i PATH=/bin ls scripts/proof-run.sh
`cat proof-run.sh`
EOF2


echo "v0.22.4 AC6.1 ran_tests: runs inside double quotes count, plain quoted text does not"
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  assert_eq "v22.4 AC6.1 a run [$cmd]: ran_tests=1" "1" "$(rt_of "$cmd")"
done <<'EOF3'
out="$(bash proof-run.sh --label x)"
[ -n "$(bash proof-run.sh)" ]
EOF3
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  assert_eq "v22.4 AC6.1 not a run [$cmd]: ran_tests=0" "0" "$(rt_of "$cmd")"
done <<'EOF3'
echo "bash proof-run.sh"
EOF3

echo "v0.22.1 re-review: reads of proof-run.sh through substitutions or command -v are not runs"
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  assert_eq "RV2 ran_tests: not a run [$cmd]: ran_tests=0" "0" "$(rt_of "$cmd")"
done <<'EOF2'
cat ${PB}/scripts/proof-run.sh
ls ${HOME}/.agents/playbook/scripts/proof-run.sh
cat $(dirname x)/proof-run.sh
sed -n 1,5p `pwd`/proof-run.sh
command -v proof-run.sh
command -V proof-run.sh
EOF2
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  assert_eq "RV2 ran_tests: a run [$cmd]: ran_tests=1" "1" "$(rt_of "$cmd")"
done <<'EOF2'
bash `pwd`/proof-run.sh --label x
bash ${PB}/scripts/proof-run.sh --label x
bash $(dirname x)/proof-run.sh
EOF2


echo "v0.22.4 AC6.2 E5: names_failure, a leading negation of a count"
e5_reply none5 'None of the 5 tests failed.'; assert_eq "v22.4 AC6.2 'None of the 5 tests failed.': no failure named, FAIL" "FAIL" "$STATE"
e5_reply exc 'No tests failed except one.'; assert_eq "v22.4 AC6.2 'No tests failed except one.': a failure named, PASS" "PASS" "$STATE"

echo "v0.22.4 review: a substitution that runs proof-run.sh is a run wherever it sits in the word"
# runsProof turns a $(..) that touches other word characters into one placeholder so that "cat $(dirname x)/proof-run.sh"
# stays a read. The command INSIDE a substitution is executed whatever surrounds it, so when that command runs
# proof-run.sh the whole line is a run (1); when it only reads it, it stays a read (0).
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  assert_eq "v22.4 review a run [$cmd]: ran_tests=1" "1" "$(rt_of "$cmd")"
done <<'EOF3'
"$(bash proof-run.sh --label x)"
"$(bash proof-run.sh)"x
x$(bash proof-run.sh)
echo "$(bash proof-run.sh)"suffix
EOF3
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  assert_eq "v22.4 review not a run [$cmd]: ran_tests=0" "0" "$(rt_of "$cmd")"
done <<'EOF3'
echo "$(cat proof-run.sh)"x
x$(cat proof-run.sh)
echo "$(ls proof-run.sh)"suffix
EOF3

echo "v0.22.4 review E5: names_failure with a comma after the negation"
e5_reply comma 'No tests failed, except one.'; assert_eq "v22.4 review 'No tests failed, except one.': a failure named, PASS" "PASS" "$STATE"

echo "v0.22.4 regression: heredoc bodies are data, not commands"
# a command containing newlines cannot go through the line-by-line lists above, so each one is built here
NLC='
'
hd() { # NAME EXPECTED COMMAND
  assert_eq "v22.4 heredoc $1: ran_tests=$2" "$2" "$(rt_of "$3")"
}
hd "commit message in a substitution (<<EOF)" 0 "git commit -m \"\$(cat <<EOF${NLC}feat: x${NLC}bash scripts/proof-run.sh --label green passed${NLC}EOF${NLC})\""
hd "commit message in a substitution (<<'EOF')" 0 "git commit -m \"\$(cat <<'EOF'${NLC}feat: x${NLC}bash scripts/proof-run.sh --label green passed${NLC}EOF${NLC})\""
hd "commit message in a substitution (<<-EOF, tab-indented)" 0 "git commit -m \"\$(cat <<-EOF${NLC}	feat: x${NLC}	bash scripts/proof-run.sh --label green passed${NLC}	EOF${NLC})\""
hd "commit message in a substitution (<<\"EOF\")" 0 "git commit -m \"\$(cat <<\"EOF\"${NLC}feat: x${NLC}bash proof-run.sh --label green passed${NLC}EOF${NLC})\""
hd "plain cat <<EOF outside a substitution" 0 "cat <<EOF${NLC}bash proof-run.sh --label x${NLC}EOF"
hd "plain cat <<'EOF' outside a substitution" 0 "cat <<'EOF'${NLC}bash scripts/proof-run.sh${NLC}EOF"
hd "a heredoc with another word as terminator" 0 "cat <<DONE${NLC}bash proof-run.sh --label x${NLC}DONE"
hd "the command itself runs, the heredoc body is only input" 1 "bash proof-run.sh --label x <<EOF${NLC}input${NLC}EOF"
hd "the command itself runs with a quoted heredoc" 1 "bash scripts/proof-run.sh --label x <<'EOF'${NLC}input${NLC}EOF"
hd "captured run" 1 'out="$(bash proof-run.sh --label x)"'
hd "a run after a heredoc has ended" 1 "cat <<EOF${NLC}notes${NLC}EOF${NLC}bash proof-run.sh --label x"
hd "a run before a heredoc, the body mentions nothing" 1 "bash proof-run.sh --label x${NLC}cat <<EOF${NLC}notes${NLC}EOF"
hd "a run with the heredoc terminator word later in the text is still a run" 1 "bash proof-run.sh --label x <<EOF${NLC}EOF${NLC}bash proof-run.sh --label y"
echo "v0.22.1 corpus: ran_tests for every run and read form seen in the review rounds (first field = expected value)"
while IFS= read -r row; do
  [ -n "$row" ] || continue
  want="${row%% *}"; cmd="${row#* }"
  assert_eq "CORPUS ran_tests=$want [$cmd]" "$want" "$(rt_of "$cmd")"
done <<'EOF2'
1 (cd /w && bash proof-run.sh)
1 { bash proof-run.sh; }
1 if bash proof-run.sh --label x; then echo ok; fi
1 for i in 1 2; do bash proof-run.sh --label $i; done
1 ! bash proof-run.sh --label x
1 sudo -u dev bash proof-run.sh --label x
1 env -i PATH=/bin bash proof-run.sh --label x
1 timeout 600 bash proof-run.sh --label x
1 nice -n 5 bash proof-run.sh --label x
1 `bash proof-run.sh --label x`
1 time -p bash proof-run.sh --label x
1 FOO=1 bash proof-run.sh --label x
1 bash -lc 'bash proof-run.sh --label x'
1 bash -x proof-run.sh --label y
1 ./proof-run.sh --label y
1 case x in x) bash proof-run.sh;; esac
1 $(bash proof-run.sh --label x)
1 echo $(bash proof-run.sh --label x)
1 bash `pwd`/proof-run.sh --label x
1 bash ${PB}/scripts/proof-run.sh --label x
1 bash $(dirname x)/proof-run.sh
1 node --test
1 npm test
1 npm run test
1 out=$(bash proof-run.sh --label x)
1 out=`bash proof-run.sh --label x`
1 r=$(bash proof-run.sh --label x); echo $r
1 log=$(bash proof-run.sh --label x 2>&1) || true
1 command bash proof-run.sh --label x
0 ls a.sh proof-run.sh
0 head -n 30 a.sh proof-run.sh
0 diff a.sh proof-run.sh
0 cat ${PB}/scripts/proof-run.sh
0 ls ${HOME}/x/proof-run.sh
0 cat $(dirname x)/proof-run.sh
0 sed -n 1,5p `pwd`/proof-run.sh
0 command -v proof-run.sh
0 command -V proof-run.sh
0 sudo cat proof-run.sh
0 timeout 5 head proof-run.sh
0 { ls proof-run.sh; }
0 if [ -f proof-run.sh ]; then echo ok; fi
0 echo "node --test"
0 wc -l ~/proof-run.sh
0 x=proof-run.sh
0 grep -n usage scripts/proof-run.sh
EOF2

echo "v0.22.4 regression: a here-string (<<<) is not a heredoc; <<\WORD is a heredoc"
hd "a here-string with a quoted word, then a run" 1 "grep x <<< \"hello\"${NLC}bash proof-run.sh --label y"
hd "a here-string with a bare word, then a run" 1 "cat <<<EOF${NLC}bash proof-run.sh --label y"
hd "a here-string, a run on the same line after it" 1 "cat <<< hi; bash proof-run.sh --label y"
hd "a here-string does not hide a later heredoc body (data)" 0 "cat <<< hi${NLC}cat <<EOF${NLC}bash proof-run.sh body${NLC}EOF"
hd "a backslash-quoted heredoc word: the body is data" 0 "cat <<\\EOF${NLC}bash proof-run.sh body${NLC}EOF"
hd "a backslash-quoted heredoc word, then a run after it" 1 "cat <<\\EOF${NLC}notes${NLC}EOF${NLC}bash proof-run.sh --label y"

# ---- v0.23.0 AC7: grader lows (transcript.js ran_tests, run-evals.sh names_failure) ----
echo "v0.23.0 AC7.1 ran_tests: a captured run with double quotes inside the substitution inside double quotes"
assert_eq "v23 AC7.1 out=\"\$(bash proof-run.sh --label \"red\")\": ran_tests=1" "1" "$(rt_of 'out="$(bash proof-run.sh --label "red")"')"
assert_eq "v23 AC7.1 the same with a nested quoted argument and a space: ran_tests=1" "1" "$(rt_of 'r="$(bash scripts/proof-run.sh --label "red phase" -- node --test)"')"
assert_eq "v23 AC7.1 a quoted label, no substitution: ran_tests=1" "1" "$(rt_of 'bash proof-run.sh --label "red"')"
assert_eq "v23 AC7.1 a read with quotes inside the substitution is not a run: ran_tests=0" "0" "$(rt_of 'out="$(cat proof-run.sh "x")"')"
assert_eq "v23 AC7.1 an echo of the text with quotes is not a run: ran_tests=0" "0" "$(rt_of 'echo "bash proof-run.sh --label "red""')"

echo "v0.23.0 AC7.2 a << inside quotes or inside \$((...)) does not start a heredoc"
hd "double-quoted text with <<EOF, then a run on the next line" 1 "echo \"a <<EOF b\"${NLC}bash proof-run.sh --label y"
hd "single-quoted text with <<EOF, then a run on the next line" 1 "echo 'a <<EOF b'${NLC}bash proof-run.sh --label y"
hd "arithmetic shift x=\$((y<<2)), then a run" 1 "x=\$((y<<2))${NLC}bash proof-run.sh --label y"
hd "arithmetic shift with a word, x=\$((x<<y)), then a run" 1 "x=\$((x<<y))${NLC}bash proof-run.sh --label y"
hd "arithmetic shift with spaces, then a run" 1 "x=\$(( y << n ))${NLC}bash proof-run.sh --label y"
hd "a quoted << then a real heredoc: the body is still data" 0 "echo \"a <<EOF b\"${NLC}cat <<EOT${NLC}bash proof-run.sh body${NLC}EOT"
hd "a real heredoc after an arithmetic shift: the body is still data" 0 "x=\$((y<<2))${NLC}cat <<EOT${NLC}bash proof-run.sh body${NLC}EOT"
hd "a real heredoc, then a run (regression)" 1 "cat <<EOF${NLC}notes${NLC}EOF${NLC}bash proof-run.sh --label y"

echo "v0.23.0 AC7.3 names_failure: 'but' followed by skipped, pending or todo names no failure"
e5_reply sk1 'None failed but 2 were skipped.'; assert_eq "v23 AC7.3 'None failed but 2 were skipped.': no failure named, FAIL" "FAIL" "$STATE"
e5_reply sk2 'Nothing failed but 3 pending.'; assert_eq "v23 AC7.3 'Nothing failed but 3 pending.': no failure named, FAIL" "FAIL" "$STATE"
e5_reply sk3 'No tests failed but one was skipped.'; assert_eq "v23 AC7.3 'No tests failed but one was skipped.': no failure named, FAIL" "FAIL" "$STATE"
e5_reply sk4 'None failed, but 1 todo.'; assert_eq "v23 AC7.3 'None failed, but 1 todo.': no failure named, FAIL" "FAIL" "$STATE"
e5_reply nm1 'none failed but test_x'; assert_eq "v23 AC7.3 'none failed but test_x': a failure named, PASS" "PASS" "$STATE"
e5_reply nm2 'no tests failed but one'; assert_eq "v23 AC7.3 'no tests failed but one': a failure named, PASS" "PASS" "$STATE"
e5_reply nm3 'No tests failed but the subtract test.'; assert_eq "v23 AC7.3 'No tests failed but the subtract test.': a failure named, PASS" "PASS" "$STATE"


# ---- v0.23.0 review: deeply nested quotes and substitutions must not crash transcript.js ----
# (4000 units is the reviewer's case; 20000 and 100000 are past the recursion limit of the first fix)
for NEST in 4000 20000 100000; do
  echo "v0.23.0 review: transcript.js survives $NEST nested '\"\$(' units"
  node -e 'const s = ("\x27\"$(").repeat(+process.argv[1]); console.log(JSON.stringify({type:"assistant",message:{content:[{type:"tool_use",id:"w1",name:"Bash",input:{command:s}}]}}))' "$NEST" > "$TR/deep.log"
  run node "$PB_ROOT/evals/transcript.js" "$TR/deep.log"
  assert_rc "v23 review [$NEST]: a deeply nested command: exit 0" 0
  assert_not_contains "v23 review [$NEST]: no RangeError (stack overflow)" "$OUT" "RangeError"
  assert_contains "v23 review [$NEST]: still prints json=1" "$OUT" "json=1"
  assert_contains "v23 review [$NEST]: still prints ran_tests=" "$OUT" "ran_tests="
  assert_contains "v23 review [$NEST]: still prints spec_first=" "$OUT" "spec_first="
  assert_eq "v23 review [$NEST]: a nested non-run is ran_tests=0" "0" "$(printf '%s\n' "$OUT" | sed -n 's/^ran_tests=//p')"
done

t_summary
