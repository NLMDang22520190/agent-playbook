#!/usr/bin/env bash
# Shared setup of tests/test-evals-arms.sh and tests/test-evals-arms-b.sh (v0.26.0 lane E: --model, --arm, --repeat of
# evals/run-evals.sh): fake claude/codex/opencode binaries that record what they got, a stand-in real home, JSON probes.
# Source it after lib.sh and evals-fixture.sh. It is not a suite: run-all.sh only starts tests/test-*.sh.
# Never calls a real harness: every --harness run of these suites puts $FK first on PATH.

FK="$(mk_tmp)"   # fake harness binaries
# PBH: the heading of the always-on block (line 1 of AGENTS.global.md without "## "). A fake whose argv names it is the leak probe of
# run-evals.sh: it records $FR/<binary>.probe.count, .probe.<n>.args, .probe.<n>.settings and a "probe" line in $FR/<binary>.order,
# and its PB_EVAL_* variables in $FR/<binary>.probe.<n>.env (v0.28.0 k1c), and answers the text of $FK/probe.answer (default NO): a stream-json result when --output-format stream-json is in argv, else plain text.
PBH="$(sed -n 's/^## //p' "$PB_ROOT/AGENTS.global.md" | head -n 1)"
FR="$(mk_tmp)"   # what they recorded: $FR/<binary>.<label>.<what>, label = basename of the cwd (the workdir)

# mk_fakes: claude, codex and opencode in $FK. Each records its argv (one per line, plus .argc), its PB_EVAL_* variables,
# PB_HEADLESS (.headless, UNSET when absent; v0.28.0 k1c), PLAYBOOK_HOME, HOME, the regular files under PLAYBOOK_HOME, and the path and a
# copy of the file after --settings; then
# prints a canned stream-json transcript (init line, success result with total_cost_usd 0.01) and exits 0.
mk_fakes() {
  local n
  for n in claude codex opencode; do
    { printf '#!/usr/bin/env bash\nFR=%s\nN=%s\nFKD=%s\nPBH=%s\n' "'$FR'" "$n" "'$FK'" "'$PBH'"
      cat <<'EOF'
probe=0
for a in "$@"; do case "$a" in *"$PBH"*) probe=1 ;; esac; done
if [ "$probe" = 1 ]; then
  pn=$(( $(cat "$FR/$N.probe.count" 2>/dev/null || echo 0) + 1 ))
  printf '%s\n' "$pn" > "$FR/$N.probe.count"
  printf '%s\n' "$@" > "$FR/$N.probe.$pn.args"
  env | grep '^PB_EVAL_' > "$FR/$N.probe.$pn.env"
  printf 'probe\n' >> "$FR/$N.order"
  prev=""
  for a in "$@"; do
    if [ "$prev" = "--settings" ]; then cp "$a" "$FR/$N.probe.$pn.settings" 2>/dev/null; fi
    prev="$a"
  done
  ans="$(cat "$FKD/probe.answer" 2>/dev/null)"; [ -n "$ans" ] || ans=NO
  sj=0; for a in "$@"; do [ "$a" = stream-json ] && sj=1; done
  if [ "$sj" = 1 ]; then
    echo '{"type":"system","subtype":"init","session_id":"p1","skills":[],"slash_commands":[]}'
    printf '{"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.001,"result":"%s"}\n' "$ans"
  else
    printf '%s\n' "$ans"
  fi
  exit 0
fi
l="$(basename "$PWD")"
printf '%s\n' "$l" >> "$FR/$N.order"
printf '%s\n' "$@" > "$FR/$N.$l.args"
printf '%s\n' "$#" > "$FR/$N.$l.argc"
env | grep '^PB_EVAL_' > "$FR/$N.$l.env"
printf '%s\n' "${PB_HEADLESS-UNSET}" > "$FR/$N.$l.headless"
printf '%s\n' "${PLAYBOOK_HOME-UNSET}" > "$FR/$N.$l.ph"
printf '%s\n' "$HOME" > "$FR/$N.$l.hm"
if [ -n "${PLAYBOOK_HOME:-}" ] && [ -d "$PLAYBOOK_HOME" ]; then (cd "$PLAYBOOK_HOME" && find . -type f) > "$FR/$N.$l.phfiles"; fi
prev=""
for a in "$@"; do
  if [ "$prev" = "--settings" ]; then printf '%s\n' "$a" > "$FR/$N.$l.setpath"; cp "$a" "$FR/$N.$l.settings" 2>/dev/null; fi
  prev="$a"
done
echo '{"type":"system","subtype":"init","session_id":"s1","skills":[],"slash_commands":[]}'
echo '{"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.01,"result":"Done."}'
exit 0
EOF
    } > "$FK/$n"
    chmod 755 "$FK/$n"
  done
}
mk_fakes

# mk_home [blockonly] -> a fresh stand-in real home: a conf (with feedback_repo), a credentials file that must never be copied,
# a ~/.claude/CLAUDE.md with the playbook block plus 2 personal lines (blockonly: the block alone), the skills
# playbook-extra (a playbook skill not in the repo) and other-skill (not a playbook skill).
PB_BLOCK_BEGIN='<!-- BEGIN agent-playbook v0.25.1 (managed block: edit the agent-playbook repo and re-run install.sh; do not edit here) -->'
# shellcheck disable=SC2120   # the suites call mk_home blockonly
mk_home() {
  local h; h="$(mk_tmp)"
  mkdir -p "$h/.agents/playbook" "$h/.claude/skills/playbook-extra" "$h/.claude/skills/other-skill"
  printf 'test_cmd=make check\nfeedback_repo=acme/fb\nlanguage=vi\n' > "$h/.agents/playbook.conf"
  printf 'SECRET-TOKEN-XYZ\n' > "$h/.claude/.credentials.json"
  printf -- '---\nname: playbook-extra\n---\n' > "$h/.claude/skills/playbook-extra/SKILL.md"
  printf -- '---\nname: other-skill\n---\n' > "$h/.claude/skills/other-skill/SKILL.md"
  if [ "${1:-}" = blockonly ]; then
    printf '%s\n' "$PB_BLOCK_BEGIN" '## Agent Playbook' 'rule one' '<!-- END agent-playbook -->' > "$h/.claude/CLAUDE.md"
  else
    printf '%s\n' '# my notes' "$PB_BLOCK_BEGIN" '## Agent Playbook' 'rule one' '<!-- END agent-playbook -->' 'my personal rule' > "$h/.claude/CLAUDE.md"
  fi
  printf '%s\n' "$h"
}
home_listing() { (cd "$1" && find . | LC_ALL=C sort); }
GH="$(mk_home)"   # the default stand-in home of go()

# go [ARGS...] -> run the runner with HOME=$GH (no PLAYBOOK_HOME), $FK first on PATH, a fresh runner-owned workroot WR and a
# results file in a separate dir OD; RES = the results file. Sets OUT (stdout+stderr), RC, WR, OD, RES. Clears $REC and $FR.
go() {
  WR="$(mk_tmp)"; : > "$WR/.pb-eval-workroot"; OD="$(mk_tmp)"; RES="$OD/results.md"
  rm -f "$REC"/* "$FR"/*
  run env -u PLAYBOOK_HOME -u PB_EVAL_ARM -u PB_EVAL_MODEL -u PB_EVAL_SETTINGS HOME="$GH" PATH="$FK:$PATH" \
    bash "$RUNNER" --workroot "$WR" --out "$RES" "$@"
}
# go_split ARGS... -> as go, but OUT holds stdout only and ERR stderr only
# shellcheck disable=SC2034   # RC, OUT and ERR are read by the suites
go_split() {
  WR="$(mk_tmp)"; : > "$WR/.pb-eval-workroot"; OD="$(mk_tmp)"; RES="$OD/results.md"
  rm -f "$REC"/* "$FR"/*
  env -u PLAYBOOK_HOME -u PB_EVAL_ARM -u PB_EVAL_MODEL -u PB_EVAL_SETTINGS HOME="$GH" PATH="$FK:$PATH" \
    bash "$RUNNER" --workroot "$WR" --out "$RES" "$@" > "$OD/stdout" 2> "$OD/stderr"
  RC=$?; OUT="$(cat "$OD/stdout")"; ERR="$(cat "$OD/stderr")"
}

# argpair FILE OPT VAL -> 0 when some line of FILE equals OPT and the next line equals VAL (an argv recorded one per line)
argpair() { [ -f "$1" ] && awk -v o="$2" -v v="$3" 'p && $0 == v { f = 1 } { p = ($0 == o) } END { exit !f }' "$1"; }
has_line() { [ -f "$1" ] && grep -qxF -- "$2" "$1"; }   # FILE LINE -> 0 when FILE has the exact line
# jget FILE EXPR -> the JS expression EXPR evaluated with j = the parsed JSON of FILE (strings raw, other values as JSON);
# NOJSON when FILE is missing or not JSON, ERR:... when EXPR throws
jget() {
  node -e 'const fs=require("fs");let j;try{j=JSON.parse(fs.readFileSync(process.argv[1],"utf8"))}catch(e){process.stdout.write("NOJSON");process.exit(0)}
let r;try{r=(new Function("j","return ("+process.argv[2]+")"))(j)}catch(e){r="ERR:"+e.message}
process.stdout.write(typeof r==="string"?r:String(JSON.stringify(r)))' "$1" "$2"
}
# row_of RESULTS.md LABEL -> the summary row of LABEL, whitespace squeezed ("" when none)
row_of() { grep -E "^\| *$2 *\|" "$1" 2>/dev/null | head -n 1 | tr -s ' '; }
# after_workroot RESULTS.md -> the first non-empty line after the "Workroot:" line
after_workroot() { awk 'f && NF { print; exit } /^Workroot: / { f = 1 }' "$1" 2>/dev/null; }
alive() { kill -0 "$1" 2>/dev/null; }
# evnames FILE -> the variable names of an env record (NAME=value lines), sorted (LC_ALL=C), space-separated
evnames() { if [ -f "$1" ]; then sed 's/=.*//' "$1" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'; else echo NO-RECORD; fi; }
rec_of() { if [ -f "$1" ]; then cat "$1"; else echo NO-RECORD; fi; }   # FILE -> its content, NO-RECORD when missing
