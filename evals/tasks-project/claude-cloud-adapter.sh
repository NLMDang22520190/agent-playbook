#!/usr/bin/env bash
# Eval adapter for the cloud container: the stock preset runs `claude -p` with no permission flag, so every write is refused there.
# Writes inside the workdir are accepted; shell commands are limited to the ones a small node task needs.
cd "$1" && claude -p --output-format stream-json --verbose --model "${PB_EVAL_MODEL:-claude-sonnet-5-5}" \
  --permission-mode acceptEdits \
  --allowedTools "Bash(node:*)" "Bash(npm:*)" "Bash(git:*)" "Bash(ls:*)" "Bash(cat:*)" "Bash(grep:*)" "Bash(sed:*)" "Bash(head:*)" "Bash(tail:*)" "Bash(wc:*)" "Bash(find:*)" "Bash(mkdir:*)" \
  < "$2"
