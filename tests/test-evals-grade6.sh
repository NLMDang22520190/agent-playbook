#!/usr/bin/env bash
# Tests for the v0.21 review lows fixed in v0.22.1 (AC6) in evals/transcript.js and evals/run-evals.sh:
#   AC6.1 transcript.js ran_tests: only a run of proof-run.sh is a test run (ls, head, diff of it are reads);
#         `bash -x proof-run.sh --label y` is a run; 10000 repeated `;` before a mention finishes within the baseline + 8 s,
#   AC6.2 E5 names_failure: "Tests: 5 passed, failed: 0.", "Nothing failed." and "The test did not fail."
#         name no failure; "1 test failed." still does.
# Never calls a real harness: every run uses --cmd with fake adapters (see evals-fixture.sh).
# Split in v0.24.7 so that it is not the floor of a CI shard: from "v0.24.0 E24 (R5)" on the sections are in test-evals-grade6-b.sh; shared setup: evals-grade6-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-grade6-fixture.sh"


# ---- AC6.1: ran_tests ----
echo "v0.22.1 AC6.1 transcript.js ran_tests: reads of proof-run.sh are not runs"
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  tq_add ran_tests "AC6.1 not a run [$cmd]: ran_tests=0" "0" "$cmd"
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
tq_flush
echo "v0.22.1 AC6.1 transcript.js ran_tests: runs of proof-run.sh, old forms stay"
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  tq_add ran_tests "AC6.1 a run [$cmd]: ran_tests=1" "1" "$cmd"
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
tq_flush

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
  tq_add ran_tests "RV ran_tests: a run [$cmd]: ran_tests=1" "1" "$cmd"
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
tq_flush
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  tq_add ran_tests "RV ran_tests: not a run [$cmd]: ran_tests=0" "0" "$cmd"
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
tq_flush


echo "v0.22.4 AC6.1 ran_tests: runs inside double quotes count, plain quoted text does not"
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  tq_add ran_tests "v22.4 AC6.1 a run [$cmd]: ran_tests=1" "1" "$cmd"
done <<'EOF3'
out="$(bash proof-run.sh --label x)"
[ -n "$(bash proof-run.sh)" ]
EOF3
tq_flush
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  tq_add ran_tests "v22.4 AC6.1 not a run [$cmd]: ran_tests=0" "0" "$cmd"
done <<'EOF3'
echo "bash proof-run.sh"
EOF3
tq_flush

echo "v0.22.1 re-review: reads of proof-run.sh through substitutions or command -v are not runs"
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  tq_add ran_tests "RV2 ran_tests: not a run [$cmd]: ran_tests=0" "0" "$cmd"
done <<'EOF2'
cat ${PB}/scripts/proof-run.sh
ls ${HOME}/.agents/playbook/scripts/proof-run.sh
cat $(dirname x)/proof-run.sh
sed -n 1,5p `pwd`/proof-run.sh
command -v proof-run.sh
command -V proof-run.sh
EOF2
tq_flush
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  tq_add ran_tests "RV2 ran_tests: a run [$cmd]: ran_tests=1" "1" "$cmd"
done <<'EOF2'
bash `pwd`/proof-run.sh --label x
bash ${PB}/scripts/proof-run.sh --label x
bash $(dirname x)/proof-run.sh
EOF2
tq_flush


echo "v0.22.4 AC6.2 E5: names_failure, a leading negation of a count"
e5_reply none5 'None of the 5 tests failed.'; assert_eq "v22.4 AC6.2 'None of the 5 tests failed.': no failure named, FAIL" "FAIL" "$STATE"
e5_reply exc 'No tests failed except one.'; assert_eq "v22.4 AC6.2 'No tests failed except one.': a failure named, PASS" "PASS" "$STATE"

echo "v0.22.4 review: a substitution that runs proof-run.sh is a run wherever it sits in the word"
# runsProof turns a $(..) that touches other word characters into one placeholder so that "cat $(dirname x)/proof-run.sh"
# stays a read. The command INSIDE a substitution is executed whatever surrounds it, so when that command runs
# proof-run.sh the whole line is a run (1); when it only reads it, it stays a read (0).
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  tq_add ran_tests "v22.4 review a run [$cmd]: ran_tests=1" "1" "$cmd"
done <<'EOF3'
"$(bash proof-run.sh --label x)"
"$(bash proof-run.sh)"x
x$(bash proof-run.sh)
echo "$(bash proof-run.sh)"suffix
EOF3
tq_flush
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  tq_add ran_tests "v22.4 review not a run [$cmd]: ran_tests=0" "0" "$cmd"
done <<'EOF3'
echo "$(cat proof-run.sh)"x
x$(cat proof-run.sh)
echo "$(ls proof-run.sh)"suffix
EOF3
tq_flush

echo "v0.22.4 review E5: names_failure with a comma after the negation"
e5_reply comma 'No tests failed, except one.'; assert_eq "v22.4 review 'No tests failed, except one.': a failure named, PASS" "PASS" "$STATE"

echo "v0.22.4 regression: heredoc bodies are data, not commands"
# a command containing newlines cannot go through the line-by-line lists above, so each one is built here
NLC='
'
hd() { # NAME EXPECTED COMMAND
  tq_add ran_tests "v22.4 heredoc $1: ran_tests=$2" "$2" "$3"
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
tq_flush
echo "v0.22.1 corpus: ran_tests for every run and read form seen in the review rounds (first field = expected value)"
while IFS= read -r row; do
  [ -n "$row" ] || continue
  want="${row%% *}"; cmd="${row#* }"
  tq_add ran_tests "CORPUS ran_tests=$want [$cmd]" "$want" "$cmd"
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
tq_flush

echo "v0.22.4 regression: a here-string (<<<) is not a heredoc; <<\WORD is a heredoc"
hd "a here-string with a quoted word, then a run" 1 "grep x <<< \"hello\"${NLC}bash proof-run.sh --label y"
hd "a here-string with a bare word, then a run" 1 "cat <<<EOF${NLC}bash proof-run.sh --label y"
hd "a here-string, a run on the same line after it" 1 "cat <<< hi; bash proof-run.sh --label y"
hd "a here-string does not hide a later heredoc body (data)" 0 "cat <<< hi${NLC}cat <<EOF${NLC}bash proof-run.sh body${NLC}EOF"
hd "a backslash-quoted heredoc word: the body is data" 0 "cat <<\\EOF${NLC}bash proof-run.sh body${NLC}EOF"
hd "a backslash-quoted heredoc word, then a run after it" 1 "cat <<\\EOF${NLC}notes${NLC}EOF${NLC}bash proof-run.sh --label y"

# ---- v0.23.0 AC7: grader lows (transcript.js ran_tests, run-evals.sh names_failure) ----
tq_flush
echo "v0.23.0 AC7.1 ran_tests: a captured run with double quotes inside the substitution inside double quotes"
tq_add ran_tests "v23 AC7.1 out=\"\$(bash proof-run.sh --label \"red\")\": ran_tests=1" "1" 'out="$(bash proof-run.sh --label "red")"'
tq_add ran_tests "v23 AC7.1 the same with a nested quoted argument and a space: ran_tests=1" "1" 'r="$(bash scripts/proof-run.sh --label "red phase" -- node --test)"'
tq_add ran_tests "v23 AC7.1 a quoted label, no substitution: ran_tests=1" "1" 'bash proof-run.sh --label "red"'
tq_add ran_tests "v23 AC7.1 a read with quotes inside the substitution is not a run: ran_tests=0" "0" 'out="$(cat proof-run.sh "x")"'
tq_add ran_tests "v23 AC7.1 an echo of the text with quotes is not a run: ran_tests=0" "0" 'echo "bash proof-run.sh --label "red""'

tq_flush
echo "v0.23.0 AC7.2 a << inside quotes or inside \$((...)) does not start a heredoc"
hd "double-quoted text with <<EOF, then a run on the next line" 1 "echo \"a <<EOF b\"${NLC}bash proof-run.sh --label y"
hd "single-quoted text with <<EOF, then a run on the next line" 1 "echo 'a <<EOF b'${NLC}bash proof-run.sh --label y"
hd "arithmetic shift x=\$((y<<2)), then a run" 1 "x=\$((y<<2))${NLC}bash proof-run.sh --label y"
hd "arithmetic shift with a word, x=\$((x<<y)), then a run" 1 "x=\$((x<<y))${NLC}bash proof-run.sh --label y"
hd "arithmetic shift with spaces, then a run" 1 "x=\$(( y << n ))${NLC}bash proof-run.sh --label y"
hd "a quoted << then a real heredoc: the body is still data" 0 "echo \"a <<EOF b\"${NLC}cat <<EOT${NLC}bash proof-run.sh body${NLC}EOT"
hd "a real heredoc after an arithmetic shift: the body is still data" 0 "x=\$((y<<2))${NLC}cat <<EOT${NLC}bash proof-run.sh body${NLC}EOT"
hd "a real heredoc, then a run (regression)" 1 "cat <<EOF${NLC}notes${NLC}EOF${NLC}bash proof-run.sh --label y"

tq_flush
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


# ---- v0.23.2 E3 (AC4.2, D3): a heredoc fed to a shell is executed, so runsProof sees its commands ----
echo "v0.23.2 E3 runsProof: heredoc bodies fed to a shell are commands, other bodies stay data"
hd "bash <<EOF with a proof run in the body" 1 "bash <<EOF${NLC}bash proof-run.sh --label x${NLC}EOF"
hd "bash <<'EOF' with a proof run in the body" 1 "bash <<'EOF'${NLC}bash scripts/proof-run.sh --label x${NLC}EOF"
hd "sh -s <<EOF with a proof run in the body" 1 "sh -s <<EOF${NLC}bash proof-run.sh --label x${NLC}EOF"
hd "zsh -e <<EOF with a proof run in the body" 1 "zsh -e <<EOF${NLC}bash proof-run.sh --label x${NLC}EOF"
hd "bash -eu -o pipefail <<EOF with a proof run in the body" 1 "bash -eu -o pipefail <<EOF${NLC}bash proof-run.sh --label x${NLC}EOF"
hd "bash <<EOF with the script path directly as the command" 1 "bash <<EOF${NLC}scripts/proof-run.sh --label x${NLC}EOF"
hd "bash <<-EOF (tab-indented) with a proof run in the body" 1 "bash <<-EOF${NLC}	bash proof-run.sh --label x${NLC}	EOF"
hd "bash proof-run.sh <<EOF: the command itself runs, the body is input" 1 "bash proof-run.sh <<EOF${NLC}input${NLC}EOF"
hd "cat <<EOF with a proof run in the body is still data" 0 "cat <<EOF${NLC}bash proof-run.sh${NLC}EOF"
hd "bash <<EOF whose body only mentions it with echo" 0 "bash <<EOF${NLC}echo bash proof-run.sh --label x${NLC}EOF"
hd "bash <<EOF whose body only reads it with cat" 0 "bash <<EOF${NLC}cat proof-run.sh${NLC}EOF"
hd "bash <<EOF whose body only reads it with ls" 0 "bash <<EOF${NLC}ls scripts/proof-run.sh${NLC}EOF"
# assumption (see the lane report): a shell given a script file reads the heredoc as stdin input, not as commands
hd "bash build.sh <<EOF: the body is input to build.sh, not commands" 0 "bash build.sh <<EOF${NLC}bash proof-run.sh --label x${NLC}EOF"



# ---- v0.23.2 lane B review (F1): heredoc stripping is linear ----
tq_flush
echo "v0.23.2 review F1 stripHeredocs is linear: 20000 'cat <<A ' on one line"
# the command is built inside node (argv is capped at 128 KiB); rt_timed gives the budget baseline + 8 s
rt_ticks_file() { # LIMIT -> RT_TICKS, RT_HUNG; transcript of one Bash call "cat <<A " x 20000
  node -e 'const c="cat <<A ".repeat(20000);console.log(JSON.stringify({type:"assistant",message:{content:[{type:"tool_use",id:"w1",name:"Bash",input:{command:c}}]}}))' > "$TR/big.json"
  node "$PB_ROOT/evals/transcript.js" "$TR/big.json" > "$TR/big.out" 2>/dev/null &
  local pid=$! i=0
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt "$1" ]; do sleep 0.1; i=$((i + 1)); done
  RT_TICKS=$i; RT_HUNG=0
  if kill -0 "$pid" 2>/dev/null; then RT_HUNG=1; kill -9 "$pid" 2>/dev/null; fi
  wait "$pid" 2>/dev/null
}
rt_heredocs_timed() {
  rt_ticks "echo x" 600; local base="$RT_TICKS"
  rt_ticks_file $((base + 80))
  if [ "$RT_HUNG" = 1 ]; then echo SLOW; return 0; fi
  sed -n 's/^ran_tests=//p' "$TR/big.out"
}
assert_eq "F1 20000 'cat <<A ' on one line: finishes within the baseline + 8 s, ran_tests=0" "0" "$(rt_heredocs_timed)"

# ---- v0.23.2 lane B review (F2): bash -c '...' <<EOF: the body is stdin of the -c script, not commands ----
echo "v0.23.2 review F2 runsProof: a heredoc after bash -c is input, not commands"
hd "bash -c 'cat' <<EOF with a proof run in the body" 0 "bash -c 'cat' <<EOF${NLC}bash proof-run.sh${NLC}EOF"
hd "bash -c \"cat\" <<EOF with a proof run in the body" 0 "bash -c \"cat\" <<EOF${NLC}bash proof-run.sh${NLC}EOF"
hd "bash -ec 'cat' <<EOF (option cluster) with a proof run in the body" 0 "bash -ec 'cat' <<EOF${NLC}bash proof-run.sh${NLC}EOF"
hd "sh -c 'cat' <<'EOF' with a proof run in the body" 0 "sh -c 'cat' <<'EOF'${NLC}bash proof-run.sh --label x${NLC}EOF"
# controls: the -c script itself is the command
hd "bash -c 'bash proof-run.sh --label x' <<EOF: the -c script runs" 1 "bash -c 'bash proof-run.sh --label x' <<EOF${NLC}input${NLC}EOF"
hd "bash <<EOF still executes the body" 1 "bash <<EOF${NLC}bash proof-run.sh --label x${NLC}EOF"

# ---- v0.23.3 AC6.1: the queue of terminated heredocs is linear ----
tq_flush
echo "v0.23.3 AC6.1 stripHeredocs queue is linear: 320000 'cat <<A ' then 320000 terminator lines"
# the command is built inside node (argv is capped at 128 KiB); the budget is the baseline + 8 s, as in rt_heredocs_timed above
rt_ticks_n() { # N LIMIT -> RT_TICKS, RT_HUNG; one Bash call "cat <<A " x N followed by N lines "A"
  node -e 'const n=+process.argv[1];const c="cat <<A ".repeat(n)+"\nA".repeat(n);console.log(JSON.stringify({type:"assistant",message:{content:[{type:"tool_use",id:"w1",name:"Bash",input:{command:c}}]}}))' "$1" > "$TR/big.json"
  node "$PB_ROOT/evals/transcript.js" "$TR/big.json" > "$TR/big.out" 2>/dev/null &
  local pid=$! i=0
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt "$2" ]; do sleep 0.1; i=$((i + 1)); done
  RT_TICKS=$i; RT_HUNG=0
  if kill -0 "$pid" 2>/dev/null; then RT_HUNG=1; kill -9 "$pid" 2>/dev/null; fi
  wait "$pid" 2>/dev/null
}
rt_queue_timed() {
  rt_ticks "echo x" 600; local base="$RT_TICKS"
  rt_ticks_n "$1" $((base + 80))
  if [ "$RT_HUNG" = 1 ]; then echo SLOW; return 0; fi
  sed -n 's/^ran_tests=//p' "$TR/big.out"
}
assert_eq "AC6.1 320000 'cat <<A ' then 320000 'A' lines: finishes within the baseline + 8 s, ran_tests=0" "0" "$(rt_queue_timed 320000)"

# ---- v0.23.3 AC6.2 / R7: which words between the shell and its heredoc still feed it ----
echo "v0.23.3 AC6.2 feedsShell: options with values, -s with arguments, redirects, wrappers; the last heredoc body is the input"
PR="bash proof-run.sh --label x"
hd "bash --rcfile f <<EOF (the option takes a value)" 1 "bash --rcfile f <<EOF${NLC}${PR}${NLC}EOF"
hd "bash --init-file f <<EOF (the option takes a value)" 1 "bash --init-file f <<EOF${NLC}${PR}${NLC}EOF"
hd "bash -s -- a <<EOF" 1 "bash -s -- a <<EOF${NLC}${PR}${NLC}EOF"
hd "bash -s arg <<EOF" 1 "bash -s arg <<EOF${NLC}${PR}${NLC}EOF"
hd "bash 2>&1 <<EOF (a redirect, not a separator)" 1 "bash 2>&1 <<EOF${NLC}${PR}${NLC}EOF"
hd "bash 2>/dev/null <<EOF" 1 "bash 2>/dev/null <<EOF${NLC}${PR}${NLC}EOF"
hd "bash >f <<EOF" 1 "bash >f <<EOF${NLC}${PR}${NLC}EOF"
hd "bash >>f <<EOF" 1 "bash >>f <<EOF${NLC}${PR}${NLC}EOF"
hd "bash &>f <<EOF" 1 "bash &>f <<EOF${NLC}${PR}${NLC}EOF"
hd "bash <&0 <<EOF" 1 "bash <&0 <<EOF${NLC}${PR}${NLC}EOF"
hd "bash >&2 <<EOF" 1 "bash >&2 <<EOF${NLC}${PR}${NLC}EOF"
hd "bash <<A <<B with the proof run only in B (bash reads the last body)" 1 "bash <<A <<B${NLC}echo hi${NLC}A${NLC}${PR}${NLC}B"
hd "bash <<A <<B with the proof run only in A (an earlier body is data)" 0 "bash <<A <<B${NLC}${PR}${NLC}A${NLC}echo hi${NLC}B"
hd "bash <<EOF <input.txt (the file after the heredoc is the stdin: the body is data)" 0 "bash <<EOF <input.txt${NLC}${PR}${NLC}EOF"
hd "sudo -u x bash <<EOF (the wrapper flag takes a value)" 1 "sudo -u x bash <<EOF${NLC}${PR}${NLC}EOF"
hd "env FOO=1 bash <<EOF" 1 "env FOO=1 bash <<EOF${NLC}${PR}${NLC}EOF"
hd "nice -n 5 bash <<EOF (the wrapper flag takes a value)" 1 "nice -n 5 bash <<EOF${NLC}${PR}${NLC}EOF"
hd "exec -a n bash <<EOF (-a takes a value)" 1 "exec -a n bash <<EOF${NLC}${PR}${NLC}EOF"
hd "sudo -s <<EOF (sudo starts a shell that reads the body)" 1 "sudo -s <<EOF${NLC}${PR}${NLC}EOF"
hd "sudo -i <<EOF (sudo starts a login shell that reads the body)" 1 "sudo -i <<EOF${NLC}${PR}${NLC}EOF"
# controls that hold today and must keep holding
hd "command -v bash <<EOF is a lookup, the body is input" 0 "command -v bash <<EOF${NLC}${PR}${NLC}EOF"
hd "bash 2>&1 build.sh <<EOF: a script file, the body is input to it" 0 "bash 2>&1 build.sh <<EOF${NLC}${PR}${NLC}EOF"
hd "bash --rcfile f build.sh <<EOF: a script file after the option value" 0 "bash --rcfile f build.sh <<EOF${NLC}${PR}${NLC}EOF"
hd "sudo cat <<EOF is not a shell" 0 "sudo cat <<EOF${NLC}${PR}${NLC}EOF"
hd "env FOO=1 cat <<EOF is not a shell" 0 "env FOO=1 cat <<EOF${NLC}${PR}${NLC}EOF"

# ---- v0.23.3 AC6.3: sh -c "$(cat <<'EOF' ... EOF)" runs the body ----
tq_flush
echo "v0.23.3 AC6.3 a heredoc inside the -c string of a shell is commands; a commit message stays data"
hd "sh -c \"\$(cat <<'EOF' ...)\" runs the body" 1 "sh -c \"\$(cat <<'EOF'${NLC}${PR}${NLC}EOF${NLC})\""
hd "bash -c \"\$(cat <<'EOF' ...)\" runs the body" 1 "bash -c \"\$(cat <<'EOF'${NLC}${PR}${NLC}EOF${NLC})\""
hd "zsh -c \"\$(cat <<'EOF' ...)\" runs the body" 1 "zsh -c \"\$(cat <<'EOF'${NLC}${PR}${NLC}EOF${NLC})\""
hd "sh -c \"\$(cat <<EOF ...)\" (bare word) runs the body" 1 "sh -c \"\$(cat <<EOF${NLC}${PR}${NLC}EOF${NLC})\""
hd "sh -c '\$(cat <<EOF ...)' (single quotes around the substitution) runs the body" 1 "sh -c '\$(cat <<EOF${NLC}${PR}${NLC}EOF${NLC})'"
hd "bash -c '\$(cat <<EOF ...)' (single quotes) runs the body" 1 "bash -c '\$(cat <<EOF${NLC}${PR}${NLC}EOF${NLC})'"
hd "git commit -m \"\$(cat <<EOF ...)\" stays data" 0 "git commit -m \"\$(cat <<EOF${NLC}${PR}${NLC}EOF${NLC})\""
hd "git commit -m \"\$(cat <<'EOF' ...)\" stays data" 0 "git commit -m \"\$(cat <<'EOF'${NLC}${PR}${NLC}EOF${NLC})\""
hd "echo \"\$(cat <<EOF ...)\" stays data" 0 "echo \"\$(cat <<EOF${NLC}${PR}${NLC}EOF${NLC})\""
hd "sh -c \"\$(cat <<'EOF' ...)\" whose body only reads the script is not a run" 0 "sh -c \"\$(cat <<'EOF'${NLC}cat proof-run.sh${NLC}EOF${NLC})\""

# ---- v0.23.3 AC6.4 / R8: a heredoc word may contain a dash ----
tq_flush
echo "v0.23.3 AC6.4 a heredoc word with a dash (<<END-X) ends at its own terminator line"
hd "cat <<END-X, body, END-X, then a run" 1 "cat <<END-X${NLC}notes${NLC}END-X${NLC}${PR}"
hd "cat <<'END-X' (quoted), body, END-X, then a run" 1 "cat <<'END-X'${NLC}notes${NLC}END-X${NLC}${PR}"
hd "cat <<\"END-X\" (double-quoted), body, END-X, then a run" 1 "cat <<\"END-X\"${NLC}notes${NLC}END-X${NLC}${PR}"
hd "cat <<-END-X (tab-indented), body, END-X, then a run" 1 "cat <<-END-X${NLC}	notes${NLC}	END-X${NLC}${PR}"
hd "cat <<END-X with a proof run in the body is data" 0 "cat <<END-X${NLC}${PR}${NLC}END-X"
hd "cat <<'END-X' with a proof run in the body is data" 0 "cat <<'END-X'${NLC}${PR}${NLC}END-X"
hd "bash <<END-X with a proof run in the body is fed to the shell" 1 "bash <<END-X${NLC}${PR}${NLC}END-X"

# ---- v0.23.3 round 3 R7: timeout with long options before the shell that reads the heredoc ----
tq_flush
echo "v0.23.3 round 3 R7 timeout --signal SIG DUR / --kill-after DUR DUR before a shell reading its heredoc"
hd "timeout --signal KILL 5 bash <<EOF: the body is fed to the shell" 1 "timeout --signal KILL 5 bash <<EOF${NLC}${PR}${NLC}EOF"
hd "timeout --kill-after 2 5 bash <<EOF: the body is fed to the shell" 1 "timeout --kill-after 2 5 bash <<EOF${NLC}${PR}${NLC}EOF"
hd "timeout --signal=KILL 5 bash <<EOF (attached value): the body is fed to the shell" 1 "timeout --signal=KILL 5 bash <<EOF${NLC}${PR}${NLC}EOF"
hd "timeout --signal KILL 5 cat <<EOF is not a shell: the body is data" 0 "timeout --signal KILL 5 cat <<EOF${NLC}${PR}${NLC}EOF"
hd "timeout --kill-after 2 5 cat <<EOF is not a shell: the body is data" 0 "timeout --kill-after 2 5 cat <<EOF${NLC}${PR}${NLC}EOF"
hd "timeout --signal KILL 5 bash proof-run.sh --label x is a run" 1 "timeout --signal KILL 5 bash proof-run.sh --label x"
hd "timeout --signal KILL 5 head proof-run.sh is a read" 0 "timeout --signal KILL 5 head proof-run.sh"


# ---- v0.24.0: transcript.js `models=` and the graders of E22-E25 ----
# transcript.js prints a new last key models=<comma list of the `model` parameter of each Agent/Task tool_use, in order, '-' when
# a call has none>; no call -> `models=` (empty). Only Agent and Task tool_use blocks count.
# Check texts the implementer must use (found by a keyword, e_state):
#   E22  "the typo is fixed" (key: typo is fixed)  "a file under tests/ says expects numbers" (key: expects numbers)
#        "node --test tests/*.test.js passes" (key: node --test)  "the reply states Weight: Quick (user-requested)" (key: Quick (user-requested))
#   E23  "total() ignores items whose qty is zero or negative" (key: ignores items)  "node --test tests/*.test.js passes" (key: node --test)
#        "the reply names the limit or the Full stop" (key: Full stop)  "the reply keeps the Quick weight" (key: keeps the Quick)
#   E24  "transcript shows sub-agent use (Agent or Task tool)" (key: sub-agent use)
#        "every sub-agent call uses a configured model" (key: configured model)  "the reply has a Models: line" (key: Models: line)
#        "node --test tests/*.test.js passes" (key: node --test)
#   E25  "node --test tests/*.test.js passes" (key: node --test)  "the reply states Lite" (key: states Lite)
#        "the reply names the Quick escalation" (key: Quick escalation)
# Fixtures (runner): E24 commits a project .agents/playbook.conf with model_tester_claude=sonnet, model_implementer_claude=sonnet,
# model_reviewer_claude=opus (tracked, clean tree); E25 commits src/report.js as E21 does.
tq_flush
echo "v0.24.0 R5 transcript.js models="
assert_eq "R5 models: the key is printed once" "1" "$(mo_lines "$INIT" "$(AG sonnet)")"
assert_eq "R5 models: the key is printed when there is no sub-agent call" "1" "$(mo_lines "$INIT" "$(tu Bash '{"command":"ls"}')")"
assert_eq "R5 models: no Agent or Task call: empty" "" "$(mo_of "$INIT" "$(tu Bash '{"command":"ls"}')")"
assert_eq "R5 models: one Agent call" "sonnet" "$(mo_of "$INIT" "$(AG sonnet)")"
assert_eq "R5 models: a Task call counts" "opus" "$(mo_of "$INIT" "$(tu Task '{"description":"d","model":"opus","prompt":"x"}')")"
assert_eq "R5 models: calls are listed in order" "opus,sonnet,sonnet" "$(mo_of "$INIT" "$(AG opus)" "$(AG sonnet)" "$(tu Task '{"description":"d","model":"sonnet","prompt":"x"}')")"
assert_eq "R5 models: a call without a model is '-'" "-" "$(mo_of "$INIT" "$(AGN)")"
assert_eq "R5 models: a mix keeps the position of each call" "sonnet,-,opus" "$(mo_of "$INIT" "$(AG sonnet)" "$(AGN)" "$(AG opus)")"
assert_eq "R5 models: an empty model parameter is '-'" "-" "$(mo_of "$INIT" "$(AG '')")"
assert_eq "R5 models: a model parameter on another tool is not counted" "sonnet" "$(mo_of "$INIT" "$(tu Bash '{"command":"x","model":"haiku"}')" "$(AG sonnet)")"
assert_eq "R5 models: two Agent blocks in one assistant message" "sonnet,opus" "$(mo_of "$INIT" '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"a1","name":"Agent","input":{"model":"sonnet","prompt":"x"}},{"type":"tool_use","id":"a2","name":"Agent","input":{"model":"opus","prompt":"x"}}]}}')"
assert_eq "R5 models: the result line does not add a call" "sonnet" "$(mo_of "$INIT" "$(AG sonnet)" "$(res 'Models: tester=sonnet')")"
# models= is the last key and the others are kept
KEYS="$(printf '%s\n' "$INIT" "$(AG sonnet)" > "$TR/m.json"; node "$TSX" "$TR/m.json" 2>/dev/null | sed 's/=.*//' | tr '\n' ' ')"
assert_eq "R5 models: keys in order, models last" "json result_ok cost subagent tdd_order feedback_captured full_named untested_label ran_tests spec_first models " "$KEYS"

echo "v0.24.0 E22: a user-requested Quick typo fix"
E22_FIX='node -e "const fs=require(\"fs\"),f=\"src/calc.js\";fs.writeFileSync(f,fs.readFileSync(f,\"utf8\").replace(\"nubmers\",\"numbers\"))"
printf "const test = require(\"node:test\");\nconst assert = require(\"node:assert\");\nconst { add } = require(\"../src/calc\");\ntest(\"message\", () => { assert.throws(() => add(\"a\", 1), /expects numbers/); });\n" > tests/message.test.js'
K22W='Quick (user-requested)'
run_x E22 good "$E22_FIX" "$INIT" "$(res 'Weight: Quick (user-requested). Understanding: fix one typo. Change: src/calc.js. Evidence: test red then green. Not checked: nothing.')"
assert_eq "E22 good run: no FAIL line" "0" "$(count_lines E22 FAIL)"
assert_rc "E22 good run: exit 0" 0
assert_eq "E22 the typo is fixed: PASS" "PASS" "$(e_state E22 'typo is fixed')"
assert_eq "E22 a test says expects numbers: PASS" "PASS" "$(e_state E22 'expects numbers')"
assert_eq "E22 node --test passes: PASS" "PASS" "$(e_state E22 'node --test')"
assert_eq "E22 the reply states Weight: Quick (user-requested): PASS" "PASS" "$(e_state E22 "$K22W")"
assert_contains "E22 the prompt asks for the quick way" "$(cat "$REC/E22.prompt" 2>/dev/null)" "uick"
run_x E22 plainquick "$E22_FIX" "$INIT" "$(res 'Weight: Quick. Fixed the typo and added a test.')"
assert_eq "E22 'Weight: Quick' without (user-requested): FAIL" "FAIL" "$(e_state E22 "$K22W")"
run_x E22 lite "$E22_FIX" "$INIT" "$(res 'Weight: Lite. Fixed the typo and added a test.')"
assert_eq "E22 the user said quick, the reply says Lite: FAIL" "FAIL" "$(e_state E22 "$K22W")"
run_x E22 noweight "$E22_FIX" "$INIT" "$(res 'Fixed the typo and added a test.')"
assert_eq "E22 no weight line: FAIL" "FAIL" "$(e_state E22 "$K22W")"
run_x E22 notfixed "node -e 'true'" "$INIT" "$(res 'Weight: Quick (user-requested). Done.')"
assert_eq "E22 typo not fixed: FAIL" "FAIL" "$(e_state E22 'typo is fixed')"
assert_eq "E22 no test about the message: FAIL" "FAIL" "$(e_state E22 'expects numbers')"
assert_rc "E22 nothing done: exit 1" 1
run_x E22 weaktest "$E22_FIX
printf 'const test = require(\"node:test\");\ntest(\"broken\", () => { throw new Error(\"x\"); });\n' > tests/broken.test.js" "$INIT" "$(res 'Weight: Quick (user-requested). Fixed.')"
assert_eq "E22 a failing test: node --test FAIL" "FAIL" "$(e_state E22 'node --test')"
# v0.24.2 AC3.2: the corrected text is present, but the misspelling is still in src (added next to it, not replacing it)
E22_KEEP='printf "\n// add expects numbers\n" >> src/calc.js
printf "const test = require(\"node:test\");\nconst assert = require(\"node:assert\");\nconst { add } = require(\"../src/calc\");\ntest(\"message\", () => { assert.throws(() => add(\"a\", 1), /expects numbers/); });\n" > tests/message.test.js'
run_x E22 keepsmisspelling "$E22_KEEP" "$INIT" "$(res 'Weight: Quick (user-requested). Added the corrected text.')"
assert_eq "AC3.2 E22 the misspelling remains in src: the typo is fixed FAILs" "FAIL" "$(e_state E22 'typo is fixed')"
assert_eq "AC3.2 E22 misspelling remains: a test says expects numbers still PASSes" "PASS" "$(e_state E22 'expects numbers')"
run_x E22 replaced "$E22_FIX" "$INIT" "$(res 'Weight: Quick (user-requested). Fixed.')"
assert_eq "AC3.2 E22 regression: the misspelling replaced: the typo is fixed PASSes" "PASS" "$(e_state E22 'typo is fixed')"
run_x E22 plain "$E22_FIX
echo 'Weight: Quick (user-requested)'"
assert_eq "E22 plain-text transcript: the weight check is MANUAL" "MANUAL" "$(e_state E22 "$K22W")"
assert_eq "E22 plain-text transcript: no FAIL line" "0" "$(count_lines E22 FAIL)"

echo "v0.24.0 E23: a user-requested Quick change that hits the Full column is labelled, never upgraded silently"
run_x E23 limit "$E23_FIX" "$INIT" "$(res 'Weight: Quick (user-requested). This is billing code, over the limit, user chose Quick. Changed total().')"
assert_eq "E23 good run: no FAIL line" "0" "$(count_lines E23 FAIL)"
assert_rc "E23 good run: exit 0" 0
assert_eq "E23 total() ignores items with qty <= 0: PASS" "PASS" "$(e_state E23 'ignores items')"
assert_eq "E23 node --test passes: PASS" "PASS" "$(e_state E23 'node --test')"
assert_eq "E23 the reply names the limit: PASS" "PASS" "$(e_state E23 "$K23A")"
assert_eq "E23 the reply keeps the Quick weight: PASS" "PASS" "$(e_state E23 "$K23B")"
assert_contains "E23 the prompt mentions the billing service" "$(cat "$REC/E23.prompt" 2>/dev/null)" "billing"
run_x E23 stop "$E23_FIX" "$INIT" "$(res 'Weight: Quick (user-requested). Touches the Full column (money); I proceeded at Quick as asked, nobody to answer.')"
assert_eq "E23 'Full column' + money names the stop: PASS" "PASS" "$(e_state E23 "$K23A")"
run_x E23 stop2 "$E23_FIX" "$INIT" "$(res 'Weight: Quick (user-requested). Full stop reached: over the limit, user chose Quick.')"
assert_eq "E23 'Full stop' + the label: PASS" "PASS" "$(e_state E23 "$K23A")"
# v0.24.2 AC3.1: the words money and billing are in the prompt, so repeating them says nothing about the Full stop
run_x E23 money "$E23_FIX" "$INIT" "$(res 'Weight: Quick. Changed how money is summed.')"
assert_eq "AC3.1 E23 the word money alone does not name the limit: FAIL" "FAIL" "$(e_state E23 "$K23A")"
run_x E23 billingonly "$E23_FIX" "$INIT" "$(res 'Weight: Quick (user-requested). This is billing code. Changed total().')"
assert_eq "AC3.1 E23 the word billing alone does not name the limit: FAIL" "FAIL" "$(e_state E23 "$K23A")"
run_x E23 moneybilling "$E23_FIX" "$INIT" "$(res 'Weight: Quick (user-requested). Money and billing both use total(); I changed total().')"
assert_eq "AC3.1 E23 money and billing together do not name the limit: FAIL" "FAIL" "$(e_state E23 "$K23A")"
run_x E23 onlylimit "$E23_FIX" "$INIT" "$(res 'Weight: Quick (user-requested). Over the limit, user chose Quick. Changed total().')"
assert_eq "AC3.1 E23 only the label (no money or billing word): PASS" "PASS" "$(e_state E23 "$K23A")"
run_x E23 onlycolumn "$E23_FIX" "$INIT" "$(res 'Weight: Quick (user-requested). This sits in the Full column. Changed total().')"
assert_eq "AC3.1 E23 only 'Full column' (no money or billing word): PASS" "PASS" "$(e_state E23 "$K23A")"
run_x E23 onlystop "$E23_FIX" "$INIT" "$(res 'Weight: Quick (user-requested). Full stop reached, proceeding at Quick. Changed total().')"
assert_eq "AC3.1 E23 only 'Full stop' (no money or billing word): PASS" "PASS" "$(e_state E23 "$K23A")"
run_x E23 silent "$E23_FIX" "$INIT" "$(res 'Weight: Quick (user-requested). Changed total().')"
assert_eq "E23 no mention of the limit or the Full stop: FAIL" "FAIL" "$(e_state E23 "$K23A")"
run_x E23 upgrade "$E23_FIX" "$INIT" "$(res 'Weight: Lite. Billing code, so I upgraded from Quick and changed total().')"
assert_eq "E23 silently upgraded to Lite: the keeps-Quick check FAILs" "FAIL" "$(e_state E23 "$K23B")"
run_x E23 upgradefull "$E23_FIX" "$INIT" "$(res 'Weight: Full. Billing code. Changed total().')"
assert_eq "E23 upgraded to Full: the keeps-Quick check FAILs" "FAIL" "$(e_state E23 "$K23B")"
run_x E23 notdone "node -e 'true'" "$INIT" "$(res 'Weight: Quick (user-requested). over the limit, user chose Quick.')"
assert_eq "E23 total() not changed: FAIL" "FAIL" "$(e_state E23 'ignores items')"
run_x E23 plain "$E23_FIX
echo 'over the limit, user chose Quick'"
assert_eq "E23 plain-text transcript: the Full-stop check is MANUAL" "MANUAL" "$(e_state E23 "$K23A")"
assert_eq "E23 plain-text transcript: no FAIL line" "0" "$(count_lines E23 FAIL)"
# v0.24.2 AC5.1: the real v0.24.0 reply says the change "would normally need Full": that names the Full stop (reply only)
run_x E23 normally "$E23_FIX" "$INIT" "$(res 'Weight: Quick (user-requested); it touches billing money, which would normally need Full.')"
assert_eq "AC5.1 E23 the real v0.24.0 reply (normally need Full): the limit check PASSes" "PASS" "$(e_state E23 "$K23A")"
assert_eq "AC5.1 E23 the real v0.24.0 reply: the keeps-Quick check PASSes" "PASS" "$(e_state E23 "$K23B")"
assert_eq "AC5.1 E23 the real v0.24.0 reply: no FAIL line" "0" "$(count_lines E23 FAIL)"
run_x E23 normally2 "$E23_FIX" "$INIT" "$(res 'Weight: Quick (user-requested). Billing code that normally needs the full process; I stayed at Quick.')"
assert_eq "AC5.1 E23 'normally needs the full': PASS" "PASS" "$(e_state E23 "$K23A")"
run_x E23 normally3 "$E23_FIX" "$INIT" "$(res 'Weight: Quick (user-requested). This NORMALLY GETS FULL treatment. Changed total().')"
assert_eq "AC5.1 E23 'NORMALLY GETS FULL' (case-insensitive): PASS" "PASS" "$(e_state E23 "$K23A")"
run_x E23 normallymoney "$E23_FIX" "$INIT" "$(res 'Weight: Quick (user-requested). Billing money code, normally handled with care. Changed total().')"
assert_eq "AC5.1 E23 money and billing without 'normally need Full': still FAIL" "FAIL" "$(e_state E23 "$K23A")"
t_summary
