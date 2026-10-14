#!/usr/bin/env bash
# Shared setup of tests/test-evals-grade4.sh and tests/test-evals-grade4-b.sh (split in v0.24.14 so that neither part is the floor of a CI shard): the run_x / res / tu
# helpers, SKT / WTEST, and the E15 / E19 fixtures (FBK, E15_FIX, MUL_OK). Source it after lib.sh and evals-fixture.sh. It is not a suite: run-all.sh only starts tests/test-*.sh.
# run_x E NAME BODY TRANSCRIPT-LINES... -> runs scenario E with an adapter that runs BODY, then prints the lines
# (BODY runs in the workdir; $REC/<E>.* files are overwritten by every run of the same E); sets OUT, RC, XW
run_x() { local e="$1" n="$2" body="$3"; shift 3
  jl "x$e$n" "$@"
  mk_adapter "$e$n" "$body
cat $J/x$e$n.json"
  XW="$(mk_tmp)"
  run bash "$RUNNER" --cmd "bash $A/$e$n.sh" --scenarios "$e" --workroot "$XW" --out "$XW/results.md"; }
res() { printf '%s"%s"}' "$RES_PRE" "$1"; }   # a stream-json result line with that reply
tu() { printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u1","name":"%s","input":%s}]}}' "$1" "$2"; }
SKT="$(tu Skill '{"skill":"playbook-tdd"}')"
WTEST="$(tu Write '{"file_path":"/work/E19/tests/multiply.test.js","content":"x"}')"
FBK='Playbook feedback line'
E15_FIX='node -e "const fs=require(\"fs\"),f=\"src/calc.js\";fs.writeFileSync(f,fs.readFileSync(f,\"utf8\").replace(\"nubmers\",\"numbers\"))"
printf "const test = require(\"node:test\");\nconst assert = require(\"node:assert\");\nconst { add } = require(\"../src/calc\");\ntest(\"message\", () => { assert.throws(() => add(\"a\", 1), /expects numbers/); });\n" > tests/message.test.js'
MUL_OK='printf "function multiply(a, b) { return a * b; }\nmodule.exports.multiply = multiply;\n" >> src/calc.js
printf "const test = require(\"node:test\");\nconst assert = require(\"node:assert\");\nconst { multiply } = require(\"../src/calc\");\ntest(\"multiply\", () => { assert.strictEqual(multiply(3, 4), 12); });\n" > tests/multiply.test.js'
