#!/usr/bin/env bash
# Step 1 of the evaluation of Context Mode: the FIXED token overhead the plugin adds to every call (its tool definitions and the text its
# hooks inject), measured by a tiny prompt with and without the plugin. UNTESTED by the author: the research container refuses to load
# the plugin, so run it on your own machine (Git Bash or WSL on Windows). Costs a few cents (about 6 tiny runs).
#
#   CM_PLUGIN=/path/to/context-mode/plugins/claude-code [CM_NODE_DIR=/path/to/node24/bin] [MODEL=claude-sonnet-5-5] [N=3] \
#     bash docs/research-data/plugin-overhead.sh
#
# The prompt size of the first call (input + cache read + cache write) does not depend on the cache state, so the difference between the
# arms is the overhead O in tokens. Arms alternate (base, plugin, base, plugin ...). Every run starts in a fresh empty directory. Your own
# other plugins, MCP servers and settings are identical in both arms, so only the plugin differs. A SessionStart hook text (for example
# "Call ...ctx_resume...") is part of O for the first call, but it stays in the history for every later call as well.
set -u
: "${CM_PLUGIN:?set CM_PLUGIN to <context-mode checkout>/plugins/claude-code}"
[ -f "$CM_PLUGIN/hook.mjs" ] || { echo "no hook.mjs in CM_PLUGIN" >&2; exit 2; }
command -v claude >/dev/null || { echo "claude CLI not on PATH" >&2; exit 2; }
command -v node >/dev/null || { echo "node not on PATH" >&2; exit 2; }
MODEL="${MODEL:-claude-sonnet-5-5}"; N="${N:-3}"
OUT="$(mktemp -d)"
run() { # $1 = base|plugin  $2 = index
  local d; d="$(mktemp -d)"
  if [ "$1" = plugin ]; then
    ( cd "$d" && PATH="${CM_NODE_DIR:+$CM_NODE_DIR:}$PATH" claude -p "Reply with the single word ok." --model "$MODEL" --max-budget-usd 0.3 --output-format json --plugin-dir "$CM_PLUGIN" > "$OUT/$1-$2.json" 2> "$OUT/$1-$2.err" )
  else
    ( cd "$d" && claude -p "Reply with the single word ok." --model "$MODEL" --max-budget-usd 0.3 --output-format json > "$OUT/$1-$2.json" 2> "$OUT/$1-$2.err" )
  fi
  echo "$1 $2 exit $?" >&2
}
i=1
while [ "$i" -le "$N" ]; do run base "$i"; run plugin "$i"; i=$((i+1)); done
node -e '
const fs = require("fs"), dir = process.argv[1];
const get = (arm) => fs.readdirSync(dir).filter((f) => f.startsWith(arm + "-") && f.endsWith(".json")).map((f) => {
  try { const d = JSON.parse(fs.readFileSync(dir + "/" + f, "utf8")), u = d.usage || {};
    return { side: (u.input_tokens || 0) + (u.cache_read_input_tokens || 0) + (u.cache_creation_input_tokens || 0), cost: d.total_cost_usd, turns: d.num_turns }; } catch (e) { return null; } }).filter(Boolean);
const mean = (a) => a.reduce((s, x) => s + x, 0) / (a.length || 1);
const b = get("base"), p = get("plugin");
console.log("# Fixed overhead of the plugin (tiny prompt, first call prompt size)\n");
console.log("| Arm | Runs | Prompt tokens per run | Mean | Cost USD per run |");
console.log("|---|---|---|---|---|");
for (const [n, a] of [["no plugin", b], ["plugin", p]]) console.log("| " + n + " | " + a.length + " | " + a.map((x) => x.side).join(", ") + " | " + Math.round(mean(a.map((x) => x.side))) + " | " + a.map((x) => (x.cost || 0).toFixed(3)).join(", ") + " |");
if (b.length && p.length) console.log("\n**Overhead O = " + Math.round(mean(p.map((x) => x.side)) - mean(b.map((x) => x.side))) + " tokens per call** (plugin minus no plugin). Put this O into net-savings-sim.js (the grid rows 3000, 6000, 10000, 15000 bracket it) and read the break-even line.");
console.log("\nLimits: tiny prompt, one model, runs per arm: " + b.length + " and " + p.length + "; the prompt size can vary slightly between runs (see the list), so compare the lists, not only the means.");
' "$OUT"
echo "Raw JSON in $OUT (delete when done). Paste the table back to the researcher." >&2
