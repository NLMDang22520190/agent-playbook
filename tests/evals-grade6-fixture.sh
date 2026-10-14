#!/usr/bin/env bash
# Shared setup of tests/test-evals-grade6.sh and tests/test-evals-grade6-b.sh (split in v0.24.7 so that neither part is the floor of a CI shard): the run_x / res / tu
# helpers, the transcript.js models= helpers, and the E23 fixture. Source it after lib.sh and evals-fixture.sh. It is not a suite: run-all.sh only starts tests/test-*.sh.
TR="$(mk_tmp)"
run_x() { local e="$1" n="$2" body="$3"; shift 3
  jl "x$e$n" "$@"
  mk_adapter "$e$n" "$body
cat $J/x$e$n.json"
  XW="$(mk_tmp)"
  run bash "$RUNNER" --cmd "bash $A/$e$n.sh" --scenarios "$e" --workroot "$XW" --out "$XW/results.md"; }
res() { printf '%s"%s"}' "$RES_PRE" "$1"; }
tu() { printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u1","name":"%s","input":%s}]}}' "$1" "$2"; }
TSX="$PB_ROOT/evals/transcript.js"
mo_of() { printf '%s\n' "$@" > "$TR/m.json"; node "$TSX" "$TR/m.json" 2>/dev/null | sed -n 's/^models=//p'; }
mo_lines() { printf '%s\n' "$@" > "$TR/m.json"; node "$TSX" "$TR/m.json" 2>/dev/null | grep -c '^models='; }
AG() { tu Agent "{\"description\":\"d\",\"subagent_type\":\"general-purpose\",\"model\":\"$1\",\"prompt\":\"x\"}"; }
AGN() { tu Agent '{"description":"d","subagent_type":"general-purpose","prompt":"x"}'; }
# v0.24.13: an AskUserQuestion tool call (what E26 must not make in a headless run)
AQ() { tu AskUserQuestion '{"questions":[{"question":"Which one?","header":"h","options":[{"label":"a","description":"d"},{"label":"b","description":"e"}],"multiSelect":false}]}'; }
# v0.24.10: E22 and E23 grade a RED commit (a commit that changes only tests/), so their fake adapters commit the test first, then fix src/
GC='git -c user.email=x@example.invalid -c user.name=x -c commit.gpgsign=false'
E23_SRC='printf "function total(items) { return items.filter((i) => i.qty > 0).reduce((s, i) => s + i.price * i.qty, 0); }\nmodule.exports = { total };\n" > src/cart.js'
E23_TEST='printf "const test = require(\"node:test\");\nconst assert = require(\"node:assert\");\nconst { total } = require(\"../src/cart\");\ntest(\"ignores non-positive qty\", () => { assert.strictEqual(total([{ price: 5, qty: 2 }, { price: 7, qty: 0 }, { price: 9, qty: -1 }]), 10); });\n" > tests/cart-qty.test.js'
E23_RED="$E23_TEST
$GC add tests/cart-qty.test.js
$GC commit -qm 'test(red): cart qty'"
E23_FIX="$E23_RED
$E23_SRC"            # the RED commit (tests only), then the fix
E23_NORED="$E23_TEST
$E23_SRC"          # test and fix both uncommitted: no RED commit
# check keys (e_state): E23 'ignores items', 'node --test', K23A = the override label check, K23B = the weight is Lite check, 'RED commit'
K23A='user override'; K23B='weight is Lite'
