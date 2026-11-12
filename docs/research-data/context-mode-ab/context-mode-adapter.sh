#!/usr/bin/env bash
# Adapter for evals/run-outcome.sh (--cmd "bash <this file>"). Same as evals/tasks-project/claude-cloud-adapter.sh for the
# without arm, plus an optional Context Mode plugin. UNTESTED by the author (the research container refused to run it).
#   PB_CM_PLUGIN  unset or empty: plain claude -p (baseline arm). Set to <context-mode checkout>/plugins/claude-code: loads
#                 that plugin with --plugin-dir (Context Mode arm) and allows its MCP tools.
#   CM_NODE_DIR   optional directory with a Node >= 24.15 `node`, put first on PATH for the Context Mode arm only.
set -u
settings=()
[ -n "${PB_EVAL_SETTINGS:-}" ] && settings=(--settings "$PB_EVAL_SETTINGS")
plugin=()
if [ -n "${PB_CM_PLUGIN:-}" ]; then
  [ -f "$PB_CM_PLUGIN/hook.mjs" ] || { echo "adapter: PB_CM_PLUGIN has no hook.mjs: $PB_CM_PLUGIN" >&2; exit 3; }
  plugin=(--plugin-dir "$PB_CM_PLUGIN")
  [ -n "${CM_NODE_DIR:-}" ] && export PATH="$CM_NODE_DIR:$PATH"
fi
cd "$1" && claude -p --output-format stream-json --verbose --model "${PB_EVAL_MODEL:-claude-sonnet-5-5}" \
  "${settings[@]+"${settings[@]}"}" "${plugin[@]+"${plugin[@]}"}" \
  --permission-mode acceptEdits \
  --allowedTools "Bash(node:*)" "Bash(npm:*)" "Bash(git:*)" "Bash(ls:*)" "Bash(cat:*)" "Bash(grep:*)" "Bash(sed:*)" "Bash(head:*)" "Bash(tail:*)" "Bash(wc:*)" "Bash(find:*)" "Bash(mkdir:*)" "Bash(bash:*)" "mcp__plugin_context-mode_context-mode" \
  < "$2"
