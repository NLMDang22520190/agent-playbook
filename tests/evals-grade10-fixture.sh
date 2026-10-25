#!/usr/bin/env bash
# Shared setup of tests/test-evals-grade10.sh and tests/test-evals-grade10b.sh (v0.25.0, eval E30: a pull request description without chatbot wrappers).
# Source it after lib.sh, evals-fixture.sh and evals-grade6-fixture.sh. It is not a suite: run-all.sh only starts tests/test-*.sh.
# The checks of grade_E30 (spec AC13, slice S3), each graded PASS, FAIL or MANUAL on the final reply (the stream-json result text); the key is a fixed
# phrase of the check text that the implementer must use (found by e_state):
#   (a) KA30 "no chatbot opener or closer in the reply": Great question, Certainly, I hope this helps, Let me know, Would you like, Want me to,
#       Happy to help, Feel free; not counted inside double quotes, inline code or a fenced block
#   (b) KB30 "no em or en dash in the reply outside code": U+2014 and U+2013 are FAILs outside inline code and fenced blocks (a double quote does not excuse)
#   (c) KC30 "no AskUserQuestion tool call in the transcript": asked= of evals/transcript.js; MANUAL when the log is not stream-json
#   (d) KD30 "the reply names clamp"
#   (e) KE30 "a passing-tests claim names a command or a count": "tests pass" / "all tests pass" / the word verified (not the label [VERIFIED], not
#       unverified, not inside quotes or code) needs a test command (npm test, node --test, ...) or a count (12 passed, 3 tests pass) in the reply
# No result text (a log that is not stream-json): (a), (b), (c), (d) and (e) are MANUAL.
KA30='chatbot opener or closer'; KB30='em or en dash'; KC30='AskUserQuestion'; KD30='names clamp'; KE30='command or a count'
# the two dashes as bytes (this file stays ASCII)
EM30="$(printf '\342\200\224')"; EN30="$(printf '\342\200\223')"
# a reply that passes every check; the rows add one thing to it
B30='Added `clamp(x, lo, hi)` to src/calc.js with a test.'
# r30 NAME REPLY [TRANSCRIPT-LINE...]: one headless E30 run whose final reply is REPLY (JSON-escaped by node); sets OUT, RC
r30() { local n="$1" reply="$2" line; shift 2
  line="$(R30TXT="$reply" node -e 'process.stdout.write(JSON.stringify({type:"result",subtype:"success",is_error:false,result:process.env.R30TXT}))')"
  if [ $# -gt 0 ]; then run_x E30 "$n" "$NOOP" "$INIT" "$@" "$line"; else run_x E30 "$n" "$NOOP" "$INIT" "$line"; fi; }
# row30 KEY EXPECT LABEL REPLY: runs E30 with REPLY and asserts the state of the check KEY
N30=0
row30() { N30=$((N30 + 1)); r30 "r$N30" "$4"; assert_eq "$3" "$2" "$(e_state E30 "$1")"; }
