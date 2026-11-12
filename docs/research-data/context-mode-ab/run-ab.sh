#!/usr/bin/env bash
# A/B measurement of Context Mode on the project-level outcome tasks: baseline claude -p versus claude -p with the plugin.
# Run it YOURSELF on your own machine (bash: Git Bash or WSL on Windows) from a checkout of the research branch.
# UNTESTED by the author. Both arms are the "without playbook" arm, same model, same tasks, interleaved.
#   CM_PLUGIN=/path/to/context-mode/plugins/claude-code [CM_NODE_DIR=/path/to/node24/bin] \
#   [K=3] [BUDGET=3.5] [MODEL=claude-sonnet-5-5] [OUT_DIR=DIR] bash docs/research-data/context-mode-ab/run-ab.sh
# Spend stops at BUDGET USD of cost_usd as the runner reports it (a notional figure on a subscription). Each runner call is capped by
# --max-cost too, which only blocks starting a LATER run, so the real total can exceed BUDGET by about one run.
# Do not put a real secret in the test repos. The plugin's ctx_execute runs model-written code with your network and environment.
set -u
HERE="$(cd "$(dirname "$0")" && pwd -P)"; REPO="$(cd "$HERE/../../.." && pwd -P)"
: "${CM_PLUGIN:?set CM_PLUGIN to <context-mode checkout>/plugins/claude-code}"
K="${K:-3}"; BUDGET="${BUDGET:-3.5}"; MODEL="${MODEL:-claude-sonnet-5-5}"
# TASKS: comma-separated ids under evals/tasks-project. Default: the two small tasks of the first run. For the large-output run use
# TASKS=project-05-tax-exempt-noisy (npm test prints about 65 KB; docs/tax-history.md 33 KB; data/orders-2025.csv 62 KB).
TASKS="${TASKS:-project-01-order-flow,project-02-tax-exempt}"
OUT_DIR="${OUT_DIR:-$HOME/context-mode-ab-$(date -u +%Y%m%dT%H%M%SZ)}"
[ -f "$REPO/evals/run-outcome.sh" ] || { echo "run from a checkout that has evals/run-outcome.sh (research branch)" >&2; exit 2; }
[ -f "$CM_PLUGIN/hook.mjs" ] || { echo "no hook.mjs in CM_PLUGIN" >&2; exit 2; }
command -v claude >/dev/null || { echo "claude CLI not on PATH" >&2; exit 2; }
NODEBIN="node"; [ -n "${CM_NODE_DIR:-}" ] && NODEBIN="$CM_NODE_DIR/node"
"$NODEBIN" -e 'const [a,b]=process.versions.node.split(".").map(Number);process.exit(a>24||(a===24&&b>=15)?0:1)' \
  || { echo "Context Mode needs Node >= 24.15 (set CM_NODE_DIR)" >&2; exit 2; }
mkdir -p "$OUT_DIR"; WORK="$(mktemp -d)"
CM_STATE_EXISTED=0; [ -e "$HOME/.context-mode" ] && CM_STATE_EXISTED=1
echo "out: $OUT_DIR   workroot: $WORK   K=$K budget=$BUDGET model=$MODEL" >&2
spent() { node -e '
const fs=require("fs"),p=process.argv[1];let s=0;
for(const f of fs.readdirSync(p).filter(x=>x.endsWith(".json"))){try{for(const r of JSON.parse(fs.readFileSync(p+"/"+f)).runs||[])if(typeof r.cost_usd==="number")s+=r.cost_usd}catch(e){}}
console.log(s.toFixed(4))' "$OUT_DIR"; }
run_arm() { # $1 = baseline|cm  $2 = iteration
  local plug=""; [ "$1" = cm ] && plug="$CM_PLUGIN"
  PB_CM_PLUGIN="$plug" CM_NODE_DIR="${CM_NODE_DIR:-}" bash "$REPO/evals/run-outcome.sh" \
    --cmd "bash $HERE/context-mode-adapter.sh" --model "$MODEL" --tasks-dir "$REPO/evals/tasks-project" \
    --tasks "$TASKS" --arm without --repeat 1 --clean-env \
    --max-cost "$(awk -v b="$BUDGET" 'BEGIN{printf "%.2f", b/4}')" --workroot "$WORK" --out "$OUT_DIR/$1-$2.md" \
    > "$OUT_DIR/$1-$2.stdout" 2>&1
  rc=$?; echo "$1 iteration $2 runner exit $rc (1 = some run FAILED a hidden test, 4 = an ERROR run) spent so far $(spent)" >&2
}
i=1
while [ "$i" -le "$K" ]; do
  if [ $((i % 2)) -eq 1 ]; then order="baseline cm"; else order="cm baseline"; fi
  for a in $order; do
    over="$(awk -v s="$(spent)" -v b="$BUDGET" 'BEGIN{print (s>=b)?1:0}')"
    [ "$over" = 1 ] && { echo "budget reached, stopping before $a $i" >&2; break 2; }
    run_arm "$a" "$i"
  done
  i=$((i+1))
done
node "$HERE/summarize.js" "$OUT_DIR" | tee "$OUT_DIR/summary.md"
rm -rf "$WORK"
if [ "$CM_STATE_EXISTED" = 0 ] && [ -e "$HOME/.context-mode" ]; then
  echo "NOTE: the plugin created $HOME/.context-mode (SQLite index of the test runs). Delete it if you do not want to keep it." >&2
fi
echo "Paste $OUT_DIR/summary.md back to the researcher; the per-run transcripts are in $OUT_DIR/*.runs/" >&2
