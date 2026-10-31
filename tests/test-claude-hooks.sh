#!/usr/bin/env bash
# Tests for scripts/claude-hooks.sh (v0.28.0 lane k1b, AC-B1 to AC-B4): opt-in merge of the agent-playbook guard and
# learnings hooks into <home>/.claude/settings.json. Every run uses a stand-in home from mk_tmp (HOME is pointed at
# one too), never the real ~/.claude. The hook scripts belong to other lanes: these tests use stub scripts and only the
# handler strings of the interface contract (.agents/handoff/01-spec.md).
. "$(dirname "$0")/lib.sh"
unset PLAYBOOK_HOME
HOME="$(cd "$(mk_tmp)" && pwd -P)"; export HOME
CHS="$PB_ROOT/scripts/claude-hooks.sh"
CH() { bash "$CHS" "$@"; }

ALL4="guard guard-start guard-stop learnings"
ALL5="guard guard-ps guard-start guard-stop learnings"
has_re() { # name text ERE (one line matches)
  if printf '%s\n' "$2" | grep -qE -- "$3"; then t_ok "$1"; else t_bad "$1" "no line matching [$3] in [$2]"; fi
}
HAVE_NODE=0
if command -v node >/dev/null 2>&1 && node -e '' >/dev/null 2>&1; then HAVE_NODE=1; fi
[ "$HAVE_NODE" = 1 ] || echo "note: node not found: install/uninstall merge tests are skipped (the merge needs node, D12)"

# node helpers (written to a temp dir; used only when node exists)
JS="$(mk_tmp)"
cat > "$JS/summ.js" <<'EOF'
// one line per handler: Event|matcher (ALL when omitted, "" or "*")|type|command|timeout|onFailure
const fs = require("fs");
const j = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const h = j.hooks || {};
for (const ev of Object.keys(h)) for (const g of h[ev]) {
  const m = (g.matcher === undefined || g.matcher === "" || g.matcher === "*") ? "ALL" : g.matcher;
  for (const x of (g.hooks || [])) console.log([ev, m, x.type, x.command, x.timeout, x.onFailure === undefined ? "-" : x.onFailure].join("|"));
}
EOF
cat > "$JS/jget.js" <<'EOF'
// jget FILE EXPR [ARG]: JSON.stringify of EXPR evaluated with j = the parsed file, a = ARG ("undefined" when undefined)
const fs = require("fs");
const j = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const v = new Function("j", "a", "return (" + process.argv[3] + ")")(j, process.argv[4]);
console.log(v === undefined ? "undefined" : JSON.stringify(v));
EOF
summ() { node "$JS/summ.js" "$1" 2>&1; }
jget() { node "$JS/jget.js" "$@" 2>&1; }
has_line() { # name text line
  if printf '%s\n' "$2" | grep -qxF -- "$3"; then t_ok "$1"; else t_bad "$1" "no line [$3] in [$2]"; fi
}
ck() { cksum < "$1" 2>/dev/null; }
nbak() { ls "$1/.agents/playbook-backups" 2>/dev/null | grep -c '^settings\.json\.' ; }

# mk_home -> a resolved stand-in home with stub hook scripts at <home>/.agents/playbook/scripts
mk_home() {
  local h; h="$(cd "$(mk_tmp)" && pwd -P)"
  mkdir -p "$h/.agents/playbook/scripts"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$h/.agents/playbook/scripts/guard-irreversible.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$h/.agents/playbook/scripts/learnings-hook.sh"
  printf '%s\n' "$h"
}
# pdir HOME -> <P> of the interface contract: cygpath -m form when cygpath exists (D30), else the POSIX path
pdir() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1/.agents/playbook/scripts"; else printf '%s' "$1/.agents/playbook/scripts"; fi; }
# expected summary lines for <P>
exp_lines() {
  EG="PreToolUse|Bash|Write|Edit|command|bash \"$1/guard-irreversible.sh\" # agent-playbook:guard|10|-"
  EP="PreToolUse|PowerShell|command|bash \"$1/guard-irreversible.sh\" # agent-playbook:guard-ps|10|-"
  ES1="SessionStart|ALL|command|bash \"$1/guard-irreversible.sh\" --session-start # agent-playbook:guard-start|10|-"
  ES2="SessionStart|ALL|command|bash \"$1/learnings-hook.sh\" # agent-playbook:learnings|10|-"
  EST="Stop|ALL|command|bash \"$1/guard-irreversible.sh\" --stop # agent-playbook:guard-stop|30|-"
}

# hcmd NAME P -> the contract handler command, JSON-escaped (for hand-written fixtures)
hcmd() {
  case "$1" in
    guard) printf 'bash \\"%s/guard-irreversible.sh\\" # agent-playbook:guard' "$2" ;;
    guard-ps) printf 'bash \\"%s/guard-irreversible.sh\\" # agent-playbook:guard-ps' "$2" ;;
    guard-start) printf 'bash \\"%s/guard-irreversible.sh\\" --session-start # agent-playbook:guard-start' "$2" ;;
    guard-stop) printf 'bash \\"%s/guard-irreversible.sh\\" --stop # agent-playbook:guard-stop' "$2" ;;
    learnings) printf 'bash \\"%s/learnings-hook.sh\\" # agent-playbook:learnings' "$2" ;;
  esac
}
# mk_settings FILE P "NAMES" [true|false] -> a settings file with a foreign PreToolUse hook, our handlers NAMES
# (guard guard-ps guard-start guard-stop learnings; ALL5 below is the v0.29 set, ALL4 the v0.28 set) and
# optionally "disableAllHooks"
mk_settings() {
  local f="$1" p="$2" names="$3" dis="${4:-}" n pre="" ss="" st=""
  for n in $names; do
    case "$n" in
      guard) pre="$pre, {\"matcher\": \"Bash|Write|Edit\", \"hooks\": [{\"type\": \"command\", \"command\": \"$(hcmd guard "$p")\", \"timeout\": 10}]}" ;;
      guard-ps) pre="$pre, {\"matcher\": \"PowerShell\", \"hooks\": [{\"type\": \"command\", \"command\": \"$(hcmd guard-ps "$p")\", \"timeout\": 10}]}" ;;
      guard-start|learnings) [ -n "$ss" ] && ss="$ss, "; ss="$ss{\"type\": \"command\", \"command\": \"$(hcmd "$n" "$p")\", \"timeout\": 10}" ;;
      guard-stop) st="{\"hooks\": [{\"type\": \"command\", \"command\": \"$(hcmd guard-stop "$p")\", \"timeout\": 30}]}" ;;
    esac
  done
  mkdir -p "$(dirname "$f")"
  {
    printf '{\n'
    [ -n "$dis" ] && printf '  "disableAllHooks": %s,\n' "$dis"
    printf '  "hooks": {\n    "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "/usr/local/bin/audit-bash.sh"}]}%s]' "$pre"
    [ -n "$ss" ] && printf ',\n    "SessionStart": [{"hooks": [%s]}]' "$ss"
    [ -n "$st" ] && printf ',\n    "Stop": [%s]' "$st"
    printf '\n  }\n}\n'
  } > "$f"
}
# A foreign settings file (made-up values that differ from their keys; the SessionStart hook is the user hook of
# docs/update-lifecycle.md:60, which contains "agent-playbook" but not our "# agent-playbook:" marker)
foreign_settings() {
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<'EOF'
{
  "model": "opus",
  "permissions": { "allow": ["Bash(ls:*)", "Read"] },
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "bash ~/agent-playbook/install.sh update --check" } ] }
    ],
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "/usr/local/bin/audit-bash.sh", "timeout": 5 } ] }
    ]
  },
  "statusLine": { "type": "command", "command": "echo hi" }
}
EOF
}
FSS='[{"hooks":[{"type":"command","command":"bash ~/agent-playbook/install.sh update --check"}]}]'
FPRE='[{"matcher":"Bash","hooks":[{"type":"command","command":"/usr/local/bin/audit-bash.sh","timeout":5}]}]'

# A PATH without node (AC-B4, AC-B3 "grep only"): wrappers for the usual tools. NONODE=1 when it works here (L-0004).
BASHX="$(command -v bash)"
NB="$(mk_tmp)"
for t in awk basename cat chmod cmp comm cp cut cygpath date diff dirname env expr find git grep head id ln ls mkdir mktemp mv od readlink realpath rm rmdir sed sh sort stat tail tee touch tr uname uniq wc xargs; do
  p="$(command -v "$t" 2>/dev/null)" || continue
  case "$p" in /*) ;; *) continue ;; esac
  printf '#!%s\nexec "%s" "$@"\n' "$BASHX" "$p" > "$NB/$t"; chmod +x "$NB/$t" 2>/dev/null
done
printf '#!%s\nexec "%s" "$@"\n' "$BASHX" "$BASHX" > "$NB/bash"; chmod +x "$NB/bash" 2>/dev/null
NONODE=0
if env PATH="$NB" "$BASHX" -c 'command -v node >/dev/null 2>&1 && exit 1; for t in cat grep sed awk mktemp mv cp mkdir rm date; do command -v "$t" >/dev/null 2>&1 || exit 1; done; printf x | grep -q x' >/dev/null 2>&1; then NONODE=1; fi
[ "$NONODE" = 1 ] || echo "note: cannot build a PATH without node here: the no-node tests are skipped"
CHN() { env PATH="$NB" "$BASHX" "$CHS" "$@"; }

echo "AC-B1/AC-H1 install into a home without settings.json creates it with the five contract handlers (v0.29: guard-ps added)"
if [ "$HAVE_NODE" = 1 ]; then
  H="$(mk_home)"; P="$(pdir "$H")"; exp_lines "$P"; F="$H/.claude/settings.json"
  run CH install --home "$H"
  assert_rc "AC-B1 install on a fresh home exits 0" 0
  assert_file "AC-B1 settings.json is created" "$F"
  S="$(summ "$F")"
  has_line "AC-B1 PreToolUse Bash|Write|Edit runs the guard (timeout 10, no onFailure, D22)" "$S" "$EG"
  has_line "AC-B1 SessionStart (all sources) runs the guard --session-start (timeout 10)" "$S" "$ES1"
  has_line "AC-B1 SessionStart (all sources) runs the learnings hook (timeout 10)" "$S" "$ES2"
  has_line "AC-B1 Stop (all) runs the guard --stop (timeout 30)" "$S" "$EST"
  has_line "AC-H1 PreToolUse PowerShell runs the guard as guard-ps (timeout 10, no onFailure)" "$S" "$EP"
  assert_eq "AC-H1 exactly one PreToolUse group has the matcher PowerShell" "1" "$(jget "$F" 'j.hooks.PreToolUse.filter(g => g.matcher === "PowerShell").length')"
  assert_eq "AC-B1/AC-H1 exactly five agent-playbook handlers (was four in v0.28)" "5" "$(printf '%s\n' "$S" | grep -c '# agent-playbook:')"
else t_skip 9 "AC-B1 fresh install (no node)"; fi

echo "AC-B1 install keeps every foreign key and hook, appends ours, backs up first and replaces the file by rename"
if [ "$HAVE_NODE" = 1 ]; then
  H="$(mk_home)"; P="$(pdir "$H")"; exp_lines "$P"; F="$H/.claude/settings.json"; HB="$H"
  foreign_settings "$F"; cp "$F" "$JS/orig.json"
  INO0="$(ls -i "$F" | awk '{ print $1 }')"
  run CH install --home "$H"
  assert_rc "AC-B1 install over a foreign settings file exits 0" 0
  assert_eq "AC-B1 model kept" '"opus"' "$(jget "$F" 'j.model')"
  assert_eq "AC-B1 permissions kept" '{"allow":["Bash(ls:*)","Read"]}' "$(jget "$F" 'j.permissions')"
  assert_eq "AC-B1 statusLine kept" '{"type":"command","command":"echo hi"}' "$(jget "$F" 'j.statusLine')"
  assert_eq "AC-B1 top-level key order kept" '"model,permissions,hooks,statusLine"' "$(jget "$F" 'Object.keys(j).join(",")')"
  assert_eq "AC-B1 event order kept, new event appended" '"SessionStart,PreToolUse,Stop"' "$(jget "$F" 'Object.keys(j.hooks).join(",")')"
  assert_eq "AC-B1 the foreign SessionStart group stays first and unchanged" "${FSS#?}" "$(jget "$F" 'j.hooks.SessionStart[0]')]"
  assert_eq "AC-B1 the foreign PreToolUse group stays first and unchanged" "${FPRE#?}" "$(jget "$F" 'j.hooks.PreToolUse[0]')]"
  S="$(summ "$F")"
  has_line "AC-B1 merged: guard handler present" "$S" "$EG"
  has_line "AC-B1 merged: guard-start handler present" "$S" "$ES1"
  has_line "AC-B1 merged: learnings handler present" "$S" "$ES2"
  has_line "AC-B1 merged: guard-stop handler present" "$S" "$EST"
  has_line "AC-H1 merged: guard-ps handler present (matcher PowerShell, timeout 10)" "$S" "$EP"
  BK="$(ls "$H/.agents/playbook-backups" 2>/dev/null | grep '^settings\.json\.' | head -n 1)"
  if printf '%s\n' "$BK" | grep -qE '^settings\.json\.[0-9]{8}T[0-9]{6}Z'; then t_ok "AC-B1 backup named settings.json.<UTC stamp> in ~/.agents/playbook-backups"; else t_bad "AC-B1 backup named settings.json.<UTC stamp> in ~/.agents/playbook-backups" "found [$(ls "$H/.agents/playbook-backups" 2>/dev/null | tr '\n' ' ')]"; fi
  if [ -n "$BK" ] && cmp -s "$JS/orig.json" "$H/.agents/playbook-backups/$BK"; then t_ok "AC-B1 the backup holds the old bytes"; else t_bad "AC-B1 the backup holds the old bytes" "backup [$BK]"; fi
  INO1="$(ls -i "$F" | awk '{ print $1 }')"
  if [ -n "$INO1" ] && [ "$INO0" != "$INO1" ]; then t_ok "AC-B1 settings.json is replaced by a rename (new inode), not rewritten in place"; else t_bad "AC-B1 settings.json is replaced by a rename (new inode), not rewritten in place" "inode $INO0 -> $INO1"; fi
  assert_eq "AC-B1 no temp file left next to settings.json" "settings.json" "$(ls -A "$H/.claude" | tr '\n' ' ' | sed 's/ $//')"
else t_skip 17 "AC-B1 merge over foreign settings (no node)"; fi

echo "AC-B1 a second install is a no-op"
if [ "$HAVE_NODE" = 1 ]; then
  F="$HB/.claude/settings.json"; S1="$(ck "$F")"; N1="$(nbak "$HB")"
  run CH install --home "$HB"
  assert_rc "AC-B1 second install exits 0" 0
  assert_contains "AC-B1 second install says unchanged" "$OUT" "unchanged"
  assert_eq "AC-B1 second install leaves settings.json byte-identical" "$S1" "$(ck "$F")"
  assert_eq "AC-B1 second install makes no backup" "$N1" "$(nbak "$HB")"
else t_skip 4 "AC-B1 idempotence (no node)"; fi

echo "AC-H1 install over a v0.28 settings file (the four old handlers) adds only guard-ps"
if [ "$HAVE_NODE" = 1 ]; then
  H="$(mk_home)"; P="$(pdir "$H")"; exp_lines "$P"; F="$H/.claude/settings.json"
  mk_settings "$F" "$P" "$ALL4"
  S4="$(summ "$F")"
  PRE0="$(jget "$F" 'j.hooks.PreToolUse')"; SS0="$(jget "$F" 'j.hooks.SessionStart')"; ST0="$(jget "$F" 'j.hooks.Stop')"
  run CH install --home "$H"
  assert_rc "AC-H1 install over four v0.28 handlers exits 0" 0
  S5="$(summ "$F")"
  has_line "AC-H1 v0.28 settings: guard-ps is added" "$S5" "$EP"
  assert_eq "AC-H1 v0.28 settings: the four old handlers keep their commands, matchers and timeouts byte for byte" "$S4" "$(printf '%s\n' "$S5" | grep -vF '# agent-playbook:guard-ps')"
  assert_eq "AC-H1 v0.28 settings: PreToolUse gets exactly one new group (foreign, guard, guard-ps)" "3" "$(jget "$F" 'j.hooks.PreToolUse.length')"
  assert_eq "AC-H1 v0.28 settings: the old PreToolUse groups are untouched" "$PRE0" "$(jget "$F" 'j.hooks.PreToolUse.slice(0, 2)')"
  assert_eq "AC-H1 v0.28 settings: SessionStart untouched" "$SS0" "$(jget "$F" 'j.hooks.SessionStart')"
  assert_eq "AC-H1 v0.28 settings: Stop untouched" "$ST0" "$(jget "$F" 'j.hooks.Stop')"
  assert_eq "AC-H1 v0.28 settings: five agent-playbook handlers now" "5" "$(printf '%s\n' "$S5" | grep -c '# agent-playbook:')"
  S1="$(ck "$F")"
  run CH install --home "$H"
  assert_rc "AC-H1 second install after the upgrade exits 0" 0
  assert_contains "AC-H1 second install after the upgrade says unchanged" "$OUT" "unchanged"
  assert_eq "AC-H1 second install after the upgrade leaves settings.json byte-identical" "$S1" "$(ck "$F")"
else t_skip 11 "AC-H1 install over v0.28 settings (no node)"; fi

echo "AC-B1 invalid JSON: exit 1, nothing written"
if [ "$HAVE_NODE" = 1 ]; then
  H="$(mk_home)"; F="$H/.claude/settings.json"; mkdir -p "$H/.claude"
  printf '{"hooks": {"PreToolUse": [\n' > "$F"; S0="$(ck "$F")"
  run CH install --home "$H"
  assert_rc "AC-B1 invalid settings.json -> exit 1" 1
  assert_eq "AC-B1 invalid settings.json is left byte-identical" "$S0" "$(ck "$F")"
  assert_eq "AC-B1 invalid settings.json: no backup" "0" "$(nbak "$H")"
  assert_eq "AC-B1 invalid settings.json: no temp file left" "settings.json" "$(ls -A "$H/.claude" | tr '\n' ' ' | sed 's/ $//')"
else t_skip 4 "AC-B1 invalid JSON (no node)"; fi

echo "AC-B1 a symlinked settings.json stays a link; its target is written"
if [ "$HAVE_NODE" = 1 ] && [ "$SYMLINKS" = 1 ]; then
  H="$(mk_home)"; mkdir -p "$H/.claude" "$H/dotfiles"
  printf '{ "model": "sonnet" }\n' > "$H/dotfiles/claude-settings.json"
  ln -s ../dotfiles/claude-settings.json "$H/.claude/settings.json"
  run CH install --home "$H"
  assert_rc "AC-B1 install through a symlink exits 0" 0
  if [ -L "$H/.claude/settings.json" ]; then t_ok "AC-B1 settings.json is still a symlink"; else t_bad "AC-B1 settings.json is still a symlink" "replaced by a regular file"; fi
  assert_eq "AC-B1 the link still points at the same target" "../dotfiles/claude-settings.json" "$(readlink "$H/.claude/settings.json")"
  assert_contains "AC-B1 the link target holds our handlers" "$(cat "$H/dotfiles/claude-settings.json")" "# agent-playbook:guard-stop"
  assert_eq "AC-B1 the link target keeps its own keys" '"sonnet"' "$(jget "$H/dotfiles/claude-settings.json" 'j.model')"
else t_skip 5 "AC-B1 symlinked settings.json (no node or no symlinks)"; fi

echo "AC-B1 a marker entry with another path is replaced in place"
if [ "$HAVE_NODE" = 1 ]; then
  H="$(mk_home)"; P="$(pdir "$H")"; F="$H/.claude/settings.json"; mkdir -p "$H/.claude"
  cat > "$F" <<'EOF'
{"hooks": {"PreToolUse": [
  {"matcher": "Bash|Write|Edit", "hooks": [{"type": "command", "command": "bash \"/old/place/scripts/guard-irreversible.sh\" # agent-playbook:guard", "timeout": 10}]},
  {"matcher": "Bash", "hooks": [{"type": "command", "command": "/usr/local/bin/audit-bash.sh"}]}
]}}
EOF
  run CH install --home "$H"
  assert_rc "AC-B1 install over an old marker entry exits 0" 0
  assert_eq "AC-B1 no duplicate guard: exactly one handler ends with the guard tail (guard-ps is a different tail)" "1" "$(jget "$F" 'j.hooks.PreToolUse.reduce((n, g) => n + g.hooks.filter(h => h.command.endsWith("# agent-playbook:guard")).length, 0)')"
  assert_eq "AC-H1 over an old guard plus a foreign group PreToolUse has three groups (guard, foreign, PowerShell)" "3" "$(jget "$F" 'j.hooks.PreToolUse.length')"
  assert_eq "AC-H1 the third PreToolUse group is the PowerShell guard-ps one" "true" "$(jget "$F" 'j.hooks.PreToolUse[2].matcher==="PowerShell" && j.hooks.PreToolUse[2].hooks.length===1 && j.hooks.PreToolUse[2].hooks[0].command.endsWith("# agent-playbook:guard-ps")')"
  assert_eq "AC-B1 the old guard entry (first group) now has the new path" "true" "$(jget "$F" 'j.hooks.PreToolUse[0].hooks[0].command===a' "bash \"$P/guard-irreversible.sh\" # agent-playbook:guard")"
  assert_eq "AC-B1 the foreign group stays second" '"/usr/local/bin/audit-bash.sh"' "$(jget "$F" 'j.hooks.PreToolUse[1].hooks[0].command')"
  assert_eq "AC-B1 the old path is gone" "0" "$(grep -c '/old/place' "$F")"
else t_skip 7 "AC-B1 marker replaced in place (no node)"; fi

echo "AC-B1 --dry-run writes nothing"
if [ "$HAVE_NODE" = 1 ]; then
  H="$(mk_home)"
  run CH install --home "$H" --dry-run
  assert_rc "AC-B1 install --dry-run exits 0" 0
  assert_no_path "AC-B1 install --dry-run creates no settings.json" "$H/.claude/settings.json"
  assert_contains "AC-H1 install --dry-run shows the guard-ps handler" "$OUT" "# agent-playbook:guard-ps"
  has_re "AC-H1 install --dry-run shows the PowerShell matcher" "$OUT" '"matcher": "PowerShell"'
else t_skip 4 "AC-B1 dry run (no node)"; fi

echo "AC-B1 the default home is \$HOME"
if [ "$HAVE_NODE" = 1 ]; then
  HD="$(mk_home)"; P="$(pdir "$HD")"; exp_lines "$P"
  run env -u PLAYBOOK_HOME HOME="$HD" bash "$CHS" install
  assert_rc "AC-B1 install without --home exits 0" 0
  has_line "AC-B1 without --home the handlers go to \$HOME/.claude/settings.json with \$HOME's scripts path" "$(summ "$HD/.claude/settings.json")" "$EG"
else t_skip 2 "AC-B1 default home (no node)"; fi

echo "AC-B1 D30 [UNVERIFIED]: with cygpath on PATH the script path is written in cygpath -m form"
if [ "$HAVE_NODE" = 1 ]; then
  FB="$(mk_tmp)"
  printf '#!%s\n# fake cygpath: -m/-w P -> C:/fake P; anything else -> P\ncase "$1" in -m|-w) printf "C:/fake%%s\\n" "$2" ;; *) printf "%%s\\n" "$2" ;; esac\n' "$BASHX" > "$FB/cygpath"
  chmod +x "$FB/cygpath" 2>/dev/null
  H="$(mk_home)"
  run env PATH="$FB:$PATH" bash "$CHS" install --home "$H"
  assert_rc "AC-B1 D30 install with cygpath on PATH exits 0" 0
  has_line "AC-B1 D30 the guard command is bash \"C:/...\" (cygpath -m form)" "$(summ "$H/.claude/settings.json")" "PreToolUse|Bash|Write|Edit|command|bash \"C:/fake$H/.agents/playbook/scripts/guard-irreversible.sh\" # agent-playbook:guard|10|-"
else t_skip 2 "AC-B1 D30 cygpath form (no node)"; fi

echo "AC-B2 uninstall removes only our handlers"
if [ "$HAVE_NODE" = 1 ]; then
  F="$HB/.claude/settings.json"; N1="$(nbak "$HB")"
  run CH uninstall --home "$HB"
  assert_rc "AC-B2 uninstall exits 0" 0
  assert_eq "AC-B2 no agent-playbook handler left" "0" "$(grep -c '# agent-playbook:' "$F")"
  assert_eq "AC-B2 the foreign SessionStart hook (install.sh update --check) stays" "$FSS" "$(jget "$F" 'j.hooks.SessionStart')"
  assert_eq "AC-B2 the foreign PreToolUse hook stays" "$FPRE" "$(jget "$F" 'j.hooks.PreToolUse')"
  assert_eq "AC-B2 the Stop array our removal emptied is dropped" "true" "$(jget "$F" 'j.hooks.Stop===undefined')"
  assert_eq "AC-B2 model kept" '"opus"' "$(jget "$F" 'j.model')"
  assert_eq "AC-B2 statusLine kept" '{"type":"command","command":"echo hi"}' "$(jget "$F" 'j.statusLine')"
  assert_eq "AC-B2 uninstall backs up first" "$((N1 + 1))" "$(nbak "$HB")"
else t_skip 8 "AC-B2 uninstall with foreign hooks (no node)"; fi

echo "AC-B2 uninstall drops a group or the hooks key only when our removal emptied it"
if [ "$HAVE_NODE" = 1 ]; then
  H="$(mk_home)"; F="$H/.claude/settings.json"
  CH install --home "$H" >/dev/null 2>&1
  run CH uninstall --home "$H"
  assert_rc "AC-B2 uninstall after a fresh install exits 0" 0
  assert_eq "AC-B2 the hooks key our removal emptied is dropped" "true" "$(jget "$F" 'j.hooks===undefined')"
  H="$(mk_home)"; F="$H/.claude/settings.json"; mkdir -p "$H/.claude"
  printf '{"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "echo started"}, {"type": "command", "command": "%s", "timeout": 10}]}]}}\n' "$(hcmd learnings /x/scripts)" > "$F"
  run CH uninstall --home "$H"
  assert_rc "AC-B2 uninstall on a mixed group exits 0" 0
  assert_eq "AC-B2 a group holding a foreign handler keeps it" '[{"hooks":[{"type":"command","command":"echo started"}]}]' "$(jget "$F" 'j.hooks.SessionStart')"
else t_skip 4 "AC-B2 emptied groups (no node)"; fi

echo "AC-H2 uninstall removes guard-ps and keeps a foreign hook in a PowerShell group"
if [ "$HAVE_NODE" = 1 ]; then
  H="$(mk_home)"; P="$(pdir "$H")"; F="$H/.claude/settings.json"; mkdir -p "$H/.claude"
  printf '{"hooks": {"PreToolUse": [{"matcher": "PowerShell", "hooks": [{"type": "command", "command": "C:/tools/audit-ps.cmd"}, {"type": "command", "command": "%s", "timeout": 10}]}, {"matcher": "Bash|Write|Edit", "hooks": [{"type": "command", "command": "%s", "timeout": 10}]}]}}\n' "$(hcmd guard-ps "$P")" "$(hcmd guard "$P")" > "$F"
  run CH uninstall --home "$H"
  assert_rc "AC-H2 uninstall with guard-ps in a shared PowerShell group exits 0" 0
  assert_eq "AC-H2 no agent-playbook handler left (guard-ps removed too)" "0" "$(grep -c '# agent-playbook:' "$F")"
  assert_eq "AC-H2 the foreign hook in the PowerShell group stays, the emptied Bash group goes" '[{"matcher":"PowerShell","hooks":[{"type":"command","command":"C:/tools/audit-ps.cmd"}]}]' "$(jget "$F" 'j.hooks.PreToolUse')"
  H="$(mk_home)"; P="$(pdir "$H")"; F="$H/.claude/settings.json"; mk_settings "$F" "$P" "$ALL5"
  run CH uninstall --home "$H"
  assert_rc "AC-H2 uninstall of a five-handler file exits 0" 0
  assert_eq "AC-H2 the guard-ps group is gone, only the foreign Bash group is left" '[{"matcher":"Bash","hooks":[{"type":"command","command":"/usr/local/bin/audit-bash.sh"}]}]' "$(jget "$F" 'j.hooks.PreToolUse')"
else t_skip 5 "AC-H2 uninstall guard-ps (no node)"; fi

echo "AC-B2 uninstall writes nothing when none of ours exist"
if [ "$HAVE_NODE" = 1 ]; then
  H="$(mk_home)"
  run CH uninstall --home "$H"
  assert_rc "AC-B2 uninstall without settings.json exits 0" 0
  assert_no_path "AC-B2 uninstall creates no settings.json" "$H/.claude/settings.json"
  assert_eq "AC-B2 uninstall without settings.json makes no backup" "0" "$(nbak "$H")"
  H="$(mk_home)"; F="$H/.claude/settings.json"; foreign_settings "$F"; S0="$(ck "$F")"
  run CH uninstall --home "$H"
  assert_rc "AC-B2 uninstall on foreign-only settings exits 0" 0
  assert_eq "AC-B2 foreign-only settings.json is left byte-identical" "$S0" "$(ck "$F")"
  assert_eq "AC-B2 foreign-only settings.json: no backup" "0" "$(nbak "$H")"
else t_skip 6 "AC-B2 nothing to remove (no node)"; fi

echo "AC-B4 without node install/uninstall exit 3, write nothing and print the JSON"
if [ "$NONODE" = 1 ]; then
  H="$(mk_home)"; P="$(pdir "$H")"
  run CHN install --home "$H"
  assert_rc "AC-B4 install without node exits 3" 3
  assert_no_path "AC-B4 install without node creates no settings.json" "$H/.claude/settings.json"
  assert_eq "AC-B4 install without node makes no backup" "0" "$(nbak "$H")"
  assert_contains "AC-B4 the printed JSON has the hooks key" "$OUT" '"hooks"'
  assert_contains "AC-B4 the printed JSON has the PreToolUse event" "$OUT" '"PreToolUse"'
  assert_contains "AC-B4 the printed JSON has the Stop handler marker" "$OUT" "# agent-playbook:guard-stop"
  assert_contains "AC-B4 the printed JSON names this home's guard script" "$OUT" "$P/guard-irreversible.sh"
  has_re "AC-H3 the printed JSON has a group with the PowerShell matcher" "$OUT" '"matcher"[[:space:]]*:[[:space:]]*"PowerShell"'
  assert_contains "AC-H3 the printed JSON has the guard-ps handler marker" "$OUT" "# agent-playbook:guard-ps"
  H="$(mk_home)"; F="$H/.claude/settings.json"; foreign_settings "$F"; S0="$(ck "$F")"
  run CHN install --home "$H"
  assert_rc "AC-B4 install without node over existing settings exits 3" 3
  assert_eq "AC-B4 install without node leaves settings.json byte-identical" "$S0" "$(ck "$F")"
  H="$(mk_home)"; P="$(pdir "$H")"; F="$H/.claude/settings.json"; mk_settings "$F" "$P" "$ALL5"; S0="$(ck "$F")"
  run CHN uninstall --home "$H"
  assert_rc "AC-B4 uninstall without node exits 3" 3
  assert_eq "AC-B4 uninstall without node leaves settings.json byte-identical" "$S0" "$(ck "$F")"
  assert_contains "AC-B4 uninstall without node prints what to remove" "$OUT" "# agent-playbook:guard"
  assert_contains "AC-H3 uninstall without node also lists the guard-ps handler" "$OUT" "# agent-playbook:guard-ps"
else t_skip 15 "AC-B4 no node (cannot build a node-free PATH)"; fi

# status runs grep only: run it without node when that PATH works here, else with the normal PATH (same assertions)
CHS_RUN() { if [ "$NONODE" = 1 ]; then CHN "$@"; else CH "$@"; fi; }
st_of() { printf '%s\n' "$OUT" | awk -v n="$1" '{ w = $1; sub(/:$/, "", w); if (w == n) { sub(/^[ \t]*[^ \t]+[ \t]+/, ""); print; exit } }'; }
assert_state() { # test-name HANDLER expected-state (prefix of the text after "HANDLER:")
  local s; s="$(st_of "$2")"
  case "$s" in "$3"*) t_ok "$1" ;; *) t_bad "$1" "status line of $2 is [$s], want [$3...]; output: $OUT" ;; esac
}

echo "AC-B3/AC-H3 status: one line per handler, five in v0.29 (grep only, no node)"
H="$(mk_home)"; P="$(pdir "$H")"; mk_settings "$H/.claude/settings.json" "$P" "$ALL5"
run CHS_RUN status --home "$H"
assert_state "AC-B3 all installed: guard installed" guard "installed"
assert_state "AC-H3 all installed: guard-ps installed" guard-ps "installed"
assert_eq "AC-H3 status prints the five handler lines in order guard, guard-ps, guard-start, guard-stop, learnings" "guard guard-ps guard-start guard-stop learnings " "$(printf '%s\n' "$OUT" | awk '{ w = $1; sub(/:$/, "", w); if (w == "guard" || w == "guard-ps" || w == "guard-start" || w == "guard-stop" || w == "learnings") printf "%s ", w }')"
assert_state "AC-B3 all installed: guard-start installed" guard-start "installed"
assert_state "AC-B3 all installed: guard-stop installed" guard-stop "installed"
assert_state "AC-B3 all installed: learnings installed" learnings "installed"
assert_not_contains "AC-B3 no disableAllHooks key: not reported disabled" "$OUT" "disabled (disableAllHooks)"

H="$(mk_home)"
run CHS_RUN status --home "$H"
assert_state "AC-B3 no settings.json: guard not installed" guard "not installed"
assert_state "AC-H3 no settings.json: guard-ps not installed" guard-ps "not installed"
assert_state "AC-B3 no settings.json: guard-start not installed" guard-start "not installed"
assert_state "AC-B3 no settings.json: guard-stop not installed" guard-stop "not installed"
assert_state "AC-B3 no settings.json: learnings not installed" learnings "not installed"

H="$(mk_home)"; P="$(pdir "$H")"; mk_settings "$H/.claude/settings.json" "$P" "learnings"
run CHS_RUN status --home "$H"
assert_state "AC-B3 partial: learnings installed" learnings "installed"
assert_state "AC-B3 partial: guard not installed" guard "not installed"
assert_state "AC-H3 partial: guard-ps not installed" guard-ps "not installed"
assert_state "AC-B3 partial: guard-stop not installed" guard-stop "not installed"

H="$(mk_home)"; P="$(pdir "$H")"; mk_settings "$H/.claude/settings.json" "$P" "$ALL4"
run CHS_RUN status --home "$H"
assert_state "AC-H3 v0.28 settings (four handlers): guard still installed" guard "installed"
assert_state "AC-H3 v0.28 settings (four handlers): guard-ps not installed" guard-ps "not installed"
assert_state "AC-H3 v0.28 settings (four handlers): guard-start installed" guard-start "installed"
assert_state "AC-H3 v0.28 settings (four handlers): guard-stop installed" guard-stop "installed"
assert_state "AC-H3 v0.28 settings (four handlers): learnings installed" learnings "installed"

H="$(mk_home)"; P="$(pdir "$H")"; mk_settings "$H/.claude/settings.json" "$P" "guard-ps"
run CHS_RUN status --home "$H"
assert_state "AC-H3 only guard-ps present: guard-ps installed" guard-ps "installed"
assert_state "AC-H3 only guard-ps present: guard is not confused with it" guard "not installed"
assert_state "AC-H3 only guard-ps present: guard-start not installed" guard-start "not installed"

H="$(mk_home)"; P="$(pdir "$H")"; mk_settings "$H/.claude/settings.json" "$P" "$ALL5"
rm -f "$H/.agents/playbook/scripts/guard-irreversible.sh"
run CHS_RUN status --home "$H"
assert_state "AC-B3 guard script missing: guard broken (script missing)" guard "broken (script missing)"
assert_state "AC-H3 guard script missing: guard-ps broken (script missing)" guard-ps "broken (script missing)"
assert_state "AC-B3 guard script missing: guard-start broken (script missing)" guard-start "broken (script missing)"
assert_state "AC-B3 guard script missing: guard-stop broken (script missing)" guard-stop "broken (script missing)"
assert_state "AC-B3 learnings script present: learnings installed" learnings "installed"

H="$(mk_home)"; P="$(pdir "$H")"; mk_settings "$H/.claude/settings.json" "$P" "$ALL5" true
run CHS_RUN status --home "$H"
assert_contains "AC-B3 disableAllHooks true is reported" "$OUT" "disabled (disableAllHooks)"
assert_state "AC-B3 disableAllHooks true: guard still reported installed" guard "installed"
H="$(mk_home)"; P="$(pdir "$H")"; mk_settings "$H/.claude/settings.json" "$P" "$ALL5" false
run CHS_RUN status --home "$H"
assert_not_contains "AC-B3 disableAllHooks false is not reported disabled (guard: passes before the feature too)" "$OUT" "disabled (disableAllHooks)"
assert_state "AC-B3 disableAllHooks false: guard installed" guard "installed"


echo "R1-5 from WSL into a Windows home: with WSL_DISTRO_NAME set and the scripts dir under /mnt/<d>/, the handler commands use <D>:/rest"
# Seam (no change of the interface, nothing is written under /mnt): `install --home H --dry-run` prints the settings it would write, handler
# commands included, and creates nothing. H = /mnt/c/<unlikely dir>/home does not exist; the test checks that it still does not.
# The distro name is only a flag: the script must not need a working wsl.exe, wslpath or cygpath (cygpath present: the cases are skipped).
if [ "$HAVE_NODE" = 1 ] && ! command -v cygpath >/dev/null 2>&1; then
  wcmd() { printf 'bash \\"%s/%s\\"' "$1" "$2"; }   # the JSON-escaped start of a handler command
  dry() { # dry HOME [WSL_DISTRO_NAME|-]: the dry-run install output; "-" = WSL_DISTRO_NAME unset
    if [ "${2:--}" = "-" ]; then run env -u WSL_DISTRO_NAME bash "$CHS" install --home "$1" --dry-run
    else run env WSL_DISTRO_NAME="$2" bash "$CHS" install --home "$1" --dry-run; fi
  }
  NX=/mnt/c/pbr1-dryrun-nonexistent
  dry "$NX/home" Ubuntu-24.04
  assert_rc "R1-5 dry-run install for a /mnt/c home exits 0" 0
  for f in guard-irreversible.sh learnings-hook.sh; do
    assert_contains "R1-5 WSL, /mnt/c home: the command uses C:/ and forward slashes ($f)" "$OUT" "$(wcmd "C:/pbr1-dryrun-nonexistent/home/.agents/playbook/scripts" "$f")"
  done
  assert_not_contains "R1-5 WSL, /mnt/c home: no /mnt/c path is left in a command" "$OUT" '\"/mnt/c/'
  assert_eq "R1-5 the dry run created nothing under /mnt/c" "absent" "$([ -e "$NX" ] && echo present || echo absent)"
  # every handler (five) carries the mapped dir
  assert_eq "R1-5 WSL, /mnt/c home: all five handler commands use the C:/ form" "5" "$(printf '%s\n' "$OUT" | grep -c 'bash \\"C:/pbr1-dryrun-nonexistent/home/.agents/playbook/scripts/')"
  dry /mnt/d/pbr1-dryrun-nonexistent/home Ubuntu-24.04
  assert_contains "R1-5 WSL, /mnt/d home: the drive letter is upper case (D:/)" "$OUT" "$(wcmd "D:/pbr1-dryrun-nonexistent/home/.agents/playbook/scripts" guard-irreversible.sh)"
  dry "/mnt/c/pbr1 dryrun nonexistent/Some User/home" Ubuntu-24.04
  assert_contains "R1-5 WSL: a path with spaces keeps them (C:/pbr1 dryrun nonexistent/Some User/...)" "$OUT" "$(wcmd "C:/pbr1 dryrun nonexistent/Some User/home/.agents/playbook/scripts" guard-irreversible.sh)"
  # unchanged cases
  dry "$NX/home" -
  assert_contains "R1-5 no WSL_DISTRO_NAME: the /mnt/c path is unchanged" "$OUT" "$(wcmd "$NX/home/.agents/playbook/scripts" guard-irreversible.sh)"
  assert_not_contains "R1-5 no WSL_DISTRO_NAME: no C:/ form" "$OUT" 'bash \"C:/'
  dry /mnt/wsl/pbr1-dryrun-nonexistent/home Ubuntu-24.04
  assert_contains "R1-5 WSL, /mnt/wsl (not a single drive letter): unchanged" "$OUT" "$(wcmd "/mnt/wsl/pbr1-dryrun-nonexistent/home/.agents/playbook/scripts" guard-irreversible.sh)"
  dry /home/pbr1-dryrun-nonexistent/home Ubuntu-24.04
  assert_contains "R1-5 WSL, a home inside the distro: unchanged" "$OUT" "$(wcmd "/home/pbr1-dryrun-nonexistent/home/.agents/playbook/scripts" guard-irreversible.sh)"
  dry /mnt/cc/pbr1-dryrun-nonexistent/home Ubuntu-24.04
  assert_contains "R1-5 WSL, /mnt/cc (two letters is not a drive): unchanged" "$OUT" "$(wcmd "/mnt/cc/pbr1-dryrun-nonexistent/home/.agents/playbook/scripts" guard-irreversible.sh)"
  H="$(mk_home)"; run env WSL_DISTRO_NAME=Ubuntu-24.04 bash "$CHS" install --home "$H" --dry-run
  assert_contains "R1-5 WSL, a stand-in home in the Linux tmp dir: unchanged" "$OUT" "$(wcmd "$H/.agents/playbook/scripts" guard-irreversible.sh)"
else
  echo "note: R1-5 mapping tests skipped (node missing, or cygpath exists: D30 form applies there)"
fi

echo "R1-5 status accepts either form: the <D>:/rest handlers are found under /mnt/<d>/ when WSL_DISTRO_NAME is set"
# Read-only: /mnt/c/Windows/win.ini is only tested for existence (never written); skipped when this host has no such file.
if [ -f /mnt/c/Windows/win.ini ]; then
  mkdir_set() { # mkdir_set HOME GUARD-PATH STOP-PATH
    mkdir -p "$1/.claude"
    printf '{"hooks":{"PreToolUse":[{"matcher":"Bash|Write|Edit","hooks":[{"type":"command","command":"bash \\"%s\\" # agent-playbook:guard","timeout":10}]}],"Stop":[{"hooks":[{"type":"command","command":"bash \\"%s\\" --stop # agent-playbook:guard-stop","timeout":30}]}]}}\n' "$2" "$3" > "$1/.claude/settings.json"
  }
  H="$(mk_home)"; mkdir_set "$H" "C:/Windows/win.ini" "C:/Windows/pbr1-missing-script.sh"
  run env WSL_DISTRO_NAME=Ubuntu-24.04 bash "$CHS" status --home "$H"
  assert_state "R1-5 status, C:/ form, script exists under /mnt/c: guard installed" guard "installed"
  assert_state "R1-5 status, C:/ form, script missing: guard-stop broken (script missing)" guard-stop "broken (script missing)"
  H="$(mk_home)"; mkdir_set "$H" "/mnt/c/Windows/win.ini" "/mnt/c/Windows/pbr1-missing-script.sh"
  run env WSL_DISTRO_NAME=Ubuntu-24.04 bash "$CHS" status --home "$H"
  assert_state "R1-5 status, the old /mnt/c form still works: guard installed" guard "installed"
  assert_state "R1-5 status, the old /mnt/c form: guard-stop broken (script missing)" guard-stop "broken (script missing)"
else
  t_skip 4 "R1-5 status tests (/mnt/c/Windows/win.ini is not readable here)"
fi

t_summary
