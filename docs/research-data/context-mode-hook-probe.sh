#!/bin/bash
# Probe the Context Mode PreToolUse hook with synthetic payloads. NO API calls, no install.
# UNTESTED by the author: the automatic permission classifier in the research container refused to run it.
# Run it yourself, on your own machine, in a throwaway directory. Needs Node >= 24.15.
# Usage: bash context-mode-hook-probe.sh /path/to/context-mode/plugins/claude-code
set -u
PLUGIN="${1:?path to plugins/claude-code of a context-mode checkout}"
# Git Bash: node needs Windows paths (cygpath -m) inside the payload and env; on Linux/macOS paths stay as they are.
winp() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
PLUGIN="$(winp "$PLUGIN")"
T="$(mktemp -d)"; mkdir -p "$T/home" "$T/proj"
head -c 40000 "$PLUGIN/README.md" > "$T/proj/big.md" 2>/dev/null || head -c 40000 /dev/urandom | base64 > "$T/proj/big.md"
run() {
  printf '%s' "$2" | env -i PATH="$PATH" HOME="$(winp "$T/home")" CLAUDE_PLUGIN_ROOT="$PLUGIN" CLAUDE_PROJECT_DIR="$(winp "$T/proj")" \
    timeout 15 node "$PLUGIN/hook.mjs" --agent claude-code 2>&1 | head -c 600
  echo " [$1]"
}
P="$(winp "$T/proj")"
run "Read full file (expect: blocked or redirected, file > 16 KB)" '{"hook_event_name":"PreToolUse","session_id":"t1","cwd":"'"$P"'","tool_name":"Read","tool_input":{"file_path":"'"$P"'/big.md"}}'
run "Read with limit (expect: allowed)" '{"hook_event_name":"PreToolUse","session_id":"t1","cwd":"'"$P"'","tool_name":"Read","tool_input":{"file_path":"'"$P"'/big.md","limit":50}}'
run "Bash cat (expect: redirected)" '{"hook_event_name":"PreToolUse","session_id":"t1","cwd":"'"$P"'","tool_name":"Bash","tool_input":{"command":"cat '"$P"'/big.md"}}'
run "Bash git status (expect: allowed)" '{"hook_event_name":"PreToolUse","session_id":"t1","cwd":"'"$P"'","tool_name":"Bash","tool_input":{"command":"git status"}}'
run "Bash git checkout of a file (the playbook guard restore case)" '{"hook_event_name":"PreToolUse","session_id":"t1","cwd":"'"$P"'","tool_name":"Bash","tool_input":{"command":"git checkout abc -- db/schema.sql"}}'
echo "Temp dir (delete when done): $T"
