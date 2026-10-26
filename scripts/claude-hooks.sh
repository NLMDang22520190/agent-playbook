#!/usr/bin/env bash
# Opt-in Claude Code hooks of agent-playbook (v0.28.0): adds the guard and learnings handlers to
# <home>/.claude/settings.json, removes them again, or reports their state. Bash 3.2.
#
# Usage: claude-hooks.sh install|uninstall|status [--home DIR] [--dry-run]
#   install    merge the four handlers (other keys and hooks are kept; a backup goes to
#              <home>/.agents/playbook-backups first; a second run changes nothing)
#   uninstall  remove only handlers whose command contains "# agent-playbook:"
#   status     one line per handler: installed | not installed | broken (script missing)
# --home defaults to the playbook home (PLAYBOOK_HOME, else the user's home).
# DECISION[D12]: install/uninstall merge the JSON with node; without node they exit 3, write nothing and print the
# JSON to add or remove by hand. status uses grep and awk only.
# DECISION[D20]: handlers PreToolUse Bash|Write|Edit (guard), SessionStart (guard --session-start, learnings),
# Stop (guard --stop, timeout 30). DECISION[D22]: no onFailure field (fail-open).
set -u
. "$(dirname "$0")/lib.sh"

usage() { sed -n '4,10p' "$0" | sed 's/^# \{0,1\}//'; }

CMD="${1:-}"
[ $# -gt 0 ] && shift
HDIR=""; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --home) [ $# -ge 2 ] || pb_die "--home needs a directory" 2; HDIR="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) pb_die "unknown option: $1" 2 ;;
  esac
done
[ -n "$HDIR" ] || HDIR="$(pb_home)"
SETTINGS="$HDIR/.claude/settings.json"
BACKUPS="$HDIR/.agents/playbook-backups"
NAMES="guard guard-start guard-stop learnings"

# hook_dir -> <P>, the scripts dir inside the handler commands.
# DECISION[D30] [UNVERIFIED]: `bash "<P>/..."` with <P> in cygpath -m form (C:/...) when cygpath exists, which both
# Git Bash and PowerShell accept as an argument to bash; the plain POSIX path otherwise.
hook_dir() {
  local p="$HDIR/.agents/playbook/scripts"
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$p"; else printf '%s' "$p"; fi
}

jstr() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

# hooks_json -> the settings fragment with the four handlers of the interface contract
hooks_json() {
  local p g s l t
  p="$(hook_dir)"
  g="$(jstr "bash \"$p/guard-irreversible.sh\" # agent-playbook:guard")"
  s="$(jstr "bash \"$p/guard-irreversible.sh\" --session-start # agent-playbook:guard-start")"
  l="$(jstr "bash \"$p/learnings-hook.sh\" # agent-playbook:learnings")"
  t="$(jstr "bash \"$p/guard-irreversible.sh\" --stop # agent-playbook:guard-stop")"
  cat <<EOF
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash|Write|Edit", "hooks": [ { "type": "command", "command": "$g", "timeout": 10 } ] }
    ],
    "SessionStart": [
      { "hooks": [
        { "type": "command", "command": "$s", "timeout": 10 },
        { "type": "command", "command": "$l", "timeout": 10 }
      ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "$t", "timeout": 30 } ] }
    ]
  }
}
EOF
}

# The merge. argv: settings file, backups dir. env: PB_MODE install|uninstall, PB_DRY 0|1, PB_WANT (hooks_json).
# Writes a temp file next to the real file (a symlink is followed, so the link stays) and renames it over the file.
MERGE_JS='
const fs = require("fs"), path = require("path");
const file = process.argv[1], backups = process.argv[2];
const mode = process.env.PB_MODE, dry = process.env.PB_DRY === "1", MARK = "# agent-playbook:";
const fail = (m) => { console.error("error: " + m + "; nothing written"); process.exit(1); };
let real = file, old = null, j = {};
try {
  if (fs.lstatSync(file).isSymbolicLink()) {
    try { real = fs.realpathSync(file); } catch (e) { real = path.resolve(path.dirname(file), fs.readlinkSync(file)); }
  }
} catch (e) { /* no file yet */ }
if (fs.existsSync(real)) {
  old = fs.readFileSync(real, "utf8");
  try { j = JSON.parse(old); } catch (e) { fail(file + " is not valid JSON (" + e.message + ")"); }
  if (!j || typeof j !== "object" || Array.isArray(j)) fail(file + " does not hold a JSON object");
}
const isObj = (v) => v && typeof v === "object" && !Array.isArray(v);
if (j.hooks !== undefined && !isObj(j.hooks)) fail(file + ": \"hooks\" is not an object");
const before = JSON.stringify(j);
const tail = (c) => { const i = typeof c === "string" ? c.lastIndexOf(MARK) : -1; return i < 0 ? null : c.slice(i); };
let count = 0;
if (mode === "install") {
  const want = JSON.parse(process.env.PB_WANT).hooks;
  if (!j.hooks) j.hooks = {};
  for (const ev of Object.keys(want)) {
    if (j.hooks[ev] === undefined) j.hooks[ev] = [];
    if (!Array.isArray(j.hooks[ev])) fail(file + ": hooks." + ev + " is not an array");
    for (const g of want[ev]) {
      const missing = [];
      for (const h of g.hooks) {
        let found = null;
        for (const eg of j.hooks[ev]) for (const x of (eg && Array.isArray(eg.hooks) ? eg.hooks : [])) {
          if (!found && x && tail(x.command) === tail(h.command)) found = x;
        }
        if (found) { found.type = h.type; found.command = h.command; found.timeout = h.timeout; } else missing.push(h);
        count++;
      }
      if (missing.length) { const ng = {}; if (g.matcher !== undefined) ng.matcher = g.matcher; ng.hooks = missing; j.hooks[ev].push(ng); }
    }
  }
} else if (isObj(j.hooks)) {
  const hadEvents = Object.keys(j.hooks).length;
  for (const ev of Object.keys(j.hooks)) {
    const arr = j.hooks[ev];
    if (!Array.isArray(arr)) continue;
    const keep = [];
    for (const g of arr) {
      if (!g || !Array.isArray(g.hooks)) { keep.push(g); continue; }
      const n = g.hooks.length;
      g.hooks = g.hooks.filter((x) => !(x && typeof x.command === "string" && x.command.indexOf(MARK) >= 0));
      count += n - g.hooks.length;
      if (g.hooks.length || n === 0) keep.push(g);
    }
    if (keep.length || arr.length === 0) j.hooks[ev] = keep; else delete j.hooks[ev];
  }
  if (hadEvents && Object.keys(j.hooks).length === 0) delete j.hooks;
}
if ((old !== null || mode === "uninstall") && JSON.stringify(j) === before) {
  console.log(mode === "install" ? "unchanged: " + file + " already has the agent-playbook hooks" : "nothing to remove: no agent-playbook hooks in " + file);
  process.exit(0);
}
const text = JSON.stringify(j, null, 2) + "\n";
if (dry) { console.log("would write " + real + ":"); process.stdout.write(text); process.exit(0); }
let bak = "";
if (old !== null) {
  fs.mkdirSync(backups, { recursive: true });
  const stamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\.[0-9]+Z$/, "Z");
  for (let i = 0; ; i++) {
    bak = path.join(backups, "settings.json." + stamp + (i ? "." + i : ""));
    try { fs.copyFileSync(real, bak, fs.constants.COPYFILE_EXCL); break; } catch (e) { if (e.code !== "EEXIST") fail("cannot back up " + real + " (" + e.message + ")"); }
  }
}
const dir = path.dirname(real), tmp = path.join(dir, "." + path.basename(real) + ".pbtmp." + process.pid);
try {
  fs.mkdirSync(dir, { recursive: true });
  const opts = old !== null ? { mode: fs.statSync(real).mode & 0o777 } : {};
  fs.writeFileSync(tmp, text, opts);
  fs.renameSync(tmp, real);
} catch (e) {
  try { fs.unlinkSync(tmp); } catch (_) { /* not created */ }
  fail("cannot write " + real + " (" + e.message + ")");
}
console.log((mode === "install" ? "installed " + count + " agent-playbook handlers into " : "removed " + count + " agent-playbook handler(s) from ") + file + (bak ? " (backup: " + bak + ")" : ""));
'

have_node() { command -v node >/dev/null 2>&1; }

cmd_install() {
  if ! have_node; then
    printf 'node not found: cannot merge %s safely. Nothing was written.\n' "$SETTINGS" >&2
    printf 'Add these entries by hand (keep your other keys and hooks; back the file up first), then run: claude-hooks.sh status\n' >&2
    hooks_json
    exit 3
  fi
  PB_MODE=install PB_DRY="$DRY" PB_WANT="$(hooks_json)" node -e "$MERGE_JS" -- "$SETTINGS" "$BACKUPS"
}

cmd_uninstall() {
  if [ ! -f "$SETTINGS" ] || ! grep -qF '# agent-playbook:' "$SETTINGS"; then
    printf 'nothing to remove: no agent-playbook hooks in %s\n' "$SETTINGS"
    return 0
  fi
  if ! have_node; then
    printf 'node not found: cannot edit %s safely. Nothing was written.\n' "$SETTINGS" >&2
    printf 'Remove by hand every hook handler whose command contains "# agent-playbook:" (these):\n' >&2
    hooks_json
    exit 3
  fi
  PB_MODE=uninstall PB_DRY="$DRY" node -e "$MERGE_JS" -- "$SETTINGS" "$BACKUPS"
}

cmd_status() {
  local found="" n st nm p tab
  tab="$(printf '\t')"
  if [ -f "$SETTINGS" ]; then
    # one "name<TAB>script path" line per handler command `bash \"<path>\" ... # agent-playbook:<name>`
    found="$(LC_ALL=C grep -oE 'bash \\"[^"\\]*\\"[^"]*# agent-playbook:[a-z-]+' "$SETTINGS" |
      awk '{ n = $0; sub(/.*# agent-playbook:/, "", n); p = $0; sub(/^bash \\"/, "", p); sub(/\\".*/, "", p); print n "\t" p }')"
  fi
  for n in $NAMES; do
    st="not installed"
    while IFS="$tab" read -r nm p; do
      [ "$nm" = "$n" ] || continue
      if [ -f "$p" ]; then st="installed"; break; fi
      st="broken (script missing)"
    done <<EOF
$found
EOF
    printf '%s: %s\n' "$n" "$st"
  done
  if [ -f "$SETTINGS" ] && LC_ALL=C grep -qE '"disableAllHooks"[[:space:]]*:[[:space:]]*true' "$SETTINGS"; then
    printf 'hooks: disabled (disableAllHooks)\n'
  fi
}

case "$CMD" in
  install) cmd_install ;;
  uninstall) cmd_uninstall ;;
  status) cmd_status ;;
  -h|--help|help|"") usage ;;
  *) usage >&2; exit 2 ;;
esac
