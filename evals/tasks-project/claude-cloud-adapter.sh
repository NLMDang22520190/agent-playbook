#!/usr/bin/env bash
# Eval adapter for containers where the stock `claude -p` preset has no write permission (every write is refused, the run
# changes nothing and is graded FAIL). Accepts edits inside the workdir and a short list of shell commands.
#   run-outcome.sh --cmd "bash evals/tasks-project/claude-cloud-adapter.sh" --model M --arm both ...
# The runner passes the model as PB_EVAL_MODEL, and with --arm or --repeat the arm as PB_EVAL_ARM and the arm's Claude Code
# settings file as PB_EVAL_SETTINGS. The with arm needs a playbook installed somewhere other than the HOME of the session that
# runs the eval: install into a scratch home (install.sh install --home DIR --harness claude --yes --copy) and export
# PB_EVAL_WITH_HOME=DIR; the without arm then keeps the real HOME, which must have no playbook.
set -u
# A file named .pb-eval-stop next to this script ends every later run at once (exit 3: the runner marks it ERROR, nothing is spent),
# so a budget watcher can stop a long invocation without killing the runner, which writes its result file only at the end.
[ -e "$(dirname "$0")/.pb-eval-stop" ] && { echo "adapter: stop file present, run skipped" >&2; exit 3; }
home="${HOME:-/root}"
if [ "${PB_EVAL_ARM:-}" = with ]; then
  [ -n "${PB_EVAL_WITH_HOME:-}" ] || { echo "adapter: PB_EVAL_WITH_HOME is not set for the with arm" >&2; exit 2; }
  home="$PB_EVAL_WITH_HOME"
fi
extra=()
# the with arm reads the playbook scripts and conf under its own home; the without arm has nothing there to read
[ "${PB_EVAL_ARM:-}" = with ] && [ -d "$home/.agents" ] && extra=(--add-dir "$home/.agents")
settings=()
[ -n "${PB_EVAL_SETTINGS:-}" ] && settings=(--settings "$PB_EVAL_SETTINGS")
cd "$1" && HOME="$home" claude -p --output-format stream-json --verbose --model "${PB_EVAL_MODEL:-claude-sonnet-5-5}" \
  "${settings[@]+"${settings[@]}"}" \
  --permission-mode acceptEdits "${extra[@]+"${extra[@]}"}" \
  --allowedTools "Bash(node:*)" "Bash(npm:*)" "Bash(git:*)" "Bash(ls:*)" "Bash(cat:*)" "Bash(grep:*)" "Bash(sed:*)" "Bash(head:*)" "Bash(tail:*)" "Bash(wc:*)" "Bash(find:*)" "Bash(mkdir:*)" "Bash(bash:*)" "Skill" "Agent" \
  < "$2"
