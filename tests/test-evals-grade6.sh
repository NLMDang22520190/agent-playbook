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
# The budget is the time of a run on a tiny command (node start-up, slow on Windows runners) plus 8 s: backtracking
# that is quadratic or worse on thousands of characters takes far longer, while a slow machine does not trip it.
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

t_summary
