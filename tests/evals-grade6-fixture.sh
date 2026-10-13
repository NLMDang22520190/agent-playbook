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
E23_FIX='printf "function total(items) { return items.filter((i) => i.qty > 0).reduce((s, i) => s + i.price * i.qty, 0); }\nmodule.exports = { total };\n" > src/cart.js'
K23A='Full stop'; K23B='keeps the Quick'
