#!/usr/bin/env bash
# Tests for the install.sh side of the opt-in Claude Code hooks (v0.28.0 lane k1b, AC-B5, AC-B6): doctor reports the
# hooks, uninstall removes ours (also the way install.ps1 calls it), install never adds or removes them. Everything runs
# against throw-away --home sandboxes and a stand-in HOME; the real home directory is never touched. The hook scripts
# belong to other lanes: the settings fixtures point at stub scripts in a temp dir.
. "$(dirname "$0")/lib.sh"
unset PLAYBOOK_HOME
HOME="$(cd "$(mk_tmp)" && pwd -P)"; export HOME
INST() { bash "$PB_ROOT/install.sh" "$@" $MODEFLAG; }   # MODEFLAG=--copy where symlinks are unavailable
[ "$SYMLINKS" = 1 ] || echo "note: symlinks unavailable here (Windows?): install tests run in --copy mode"
export PLAYBOOK_REGISTRY="$(mk_tmp)/registry"   # never write the real repo's .install-targets

HAVE_NODE=0
if command -v node >/dev/null 2>&1 && node -e '' >/dev/null 2>&1; then HAVE_NODE=1; fi
[ "$HAVE_NODE" = 1 ] || echo "note: node not found: the uninstall-removes-hooks tests are skipped (the merge needs node, D12)"
ck() { cksum < "$1" 2>/dev/null; }
has_line() { # name text line
  if printf '%s\n' "$2" | grep -qxF -- "$3"; then t_ok "$1"; else t_bad "$1" "no line [$3] in [$2]"; fi
}
has_re() { # name text ERE (one line matches)
  if printf '%s\n' "$2" | grep -qE -- "$3"; then t_ok "$1"; else t_bad "$1" "no line matching [$3] in [$2]"; fi
}
mk_home() { cd "$(mk_tmp)" && pwd -P; }
# stub hook scripts in a dir outside the install (the real ones come from lane k1a)
mk_stubs() { # DIR NAMES
  local n; for n in $2; do printf '#!/usr/bin/env bash\nexit 0\n' > "$1/$n"; done
}
pform() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

# hcmd NAME P -> the contract handler command, JSON-escaped
hcmd() {
  case "$1" in
    guard) printf 'bash \\"%s/guard-irreversible.sh\\" # agent-playbook:guard' "$2" ;;
    guard-ps) printf 'bash \\"%s/guard-irreversible.sh\\" # agent-playbook:guard-ps' "$2" ;;
    guard-start) printf 'bash \\"%s/guard-irreversible.sh\\" --session-start # agent-playbook:guard-start' "$2" ;;
    guard-stop) printf 'bash \\"%s/guard-irreversible.sh\\" --stop # agent-playbook:guard-stop' "$2" ;;
    learnings) printf 'bash \\"%s/learnings-hook.sh\\" # agent-playbook:learnings' "$2" ;;
  esac
}
# mk_settings FILE P "NAMES" [true|false] -> a settings file with a foreign PreToolUse hook, our handlers NAMES and
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
ALL4="guard guard-start guard-stop learnings"            # the v0.28 set
ALL5="guard guard-ps guard-start guard-stop learnings"   # the v0.29 set (guard-ps: the PowerShell tool)
NOT_INSTALLED='INFO  hooks: not installed (opt-in: say "set up the playbook")'

SD="$(cd "$(mk_tmp)" && pwd -P)"; mk_stubs "$SD" "guard-irreversible.sh learnings-hook.sh"; PS="$(pform "$SD")"

echo "AC-B5 install.sh install never adds hooks"
H="$(mk_home)"
run INST install --home "$H" --harness claude --yes
assert_rc "install (claude) exits 0" 0
assert_no_path "AC-B5 install.sh install creates no ~/.claude/settings.json (characterization: true before k1b too)" "$H/.claude/settings.json"

echo "AC-B6 doctor reports the hooks (claude)"
run INST doctor --home "$H" --harness claude
assert_rc "AC-B6 doctor on a healthy install without hooks exits 0" 0
has_line "AC-B6 doctor without hooks: INFO not installed (opt-in)" "$OUT" "$NOT_INSTALLED"
assert_contains "AC-B6 doctor without hooks: still healthy" "$OUT" "doctor: healthy"

mk_settings "$H/.claude/settings.json" "$PS" ""
run INST doctor --home "$H" --harness claude
assert_rc "AC-B6 doctor with only foreign hooks exits 0" 0
has_line "AC-B6 doctor with only foreign hooks: INFO not installed" "$OUT" "$NOT_INSTALLED"

mk_settings "$H/.claude/settings.json" "$PS" "$ALL5"
run INST doctor --home "$H" --harness claude
assert_rc "AC-B6 doctor with all five handlers exits 0" 0
has_line "AC-B6/AC-H4 doctor with all five handlers: OK guard, learnings installed" "$OUT" "OK    hooks: guard, learnings installed"

mk_settings "$H/.claude/settings.json" "$PS" "$ALL4"
run INST doctor --home "$H" --harness claude
assert_rc "AC-H4 doctor with the four v0.28 handlers (no guard-ps) exits 0" 0
assert_not_contains "AC-H4 four v0.28 handlers: not the OK line (the PowerShell tool is unguarded)" "$OUT" "OK    hooks:"
has_re "AC-H4 four v0.28 handlers: INFO partly installed" "$OUT" '^INFO  hooks: partly installed '
assert_contains "AC-H4 four v0.28 handlers: names the missing PowerShell handler guard-ps" "$OUT" "guard-ps"
has_re "AC-H4 four v0.28 handlers: says the fix, claude-hooks.sh install" "$OUT" 'claude-hooks\.sh install'

S0="$(ck "$H/.claude/settings.json")"
run INST install --home "$H" --harness claude --yes
assert_rc "re-install (claude) with hooks present exits 0" 0
assert_eq "AC-B5 install.sh install leaves the hooks alone (settings.json byte-identical)" "$S0" "$(ck "$H/.claude/settings.json")"

mk_settings "$H/.claude/settings.json" "$PS" "learnings"
run INST doctor --home "$H" --harness claude
assert_rc "AC-B6 doctor with one handler exits 0" 0
has_re "AC-B6 doctor with one handler: INFO partly installed (<names>)" "$OUT" '^INFO  hooks: partly installed \(.+\)$'

mk_settings "$H/.claude/settings.json" "$PS" "$ALL5" true
run INST doctor --home "$H" --harness claude
assert_rc "AC-B6 doctor with disableAllHooks exits 0" 0
has_line "AC-B6 doctor with disableAllHooks: INFO installed but disabled" "$OUT" "INFO  hooks: installed but disabled (disableAllHooks)"

SM="$(cd "$(mk_tmp)" && pwd -P)"; mk_stubs "$SM" "learnings-hook.sh"
mk_settings "$H/.claude/settings.json" "$(pform "$SM")" "$ALL5"
run INST doctor --home "$H" --harness claude
assert_rc "AC-B6 doctor when our guard handler points at a missing script exits 1" 1
has_re "AC-B6 doctor names the hooks problem on a PROBLEM line" "$OUT" '^PROBLEM: .*hook'

H2="$(mk_home)"
INST install --home "$H2" --harness codex --yes >/dev/null 2>&1
mk_settings "$H2/.claude/settings.json" "$PS" "$ALL5"
run INST doctor --home "$H2" --harness codex
assert_not_contains "AC-B6 doctor for codex only has no hooks line (characterization)" "$OUT" "hooks:"

echo "AC-B5 install.sh uninstall removes our hooks and keeps foreign ones"
if [ "$HAVE_NODE" = 1 ]; then
  H="$(mk_home)"
  INST install --home "$H" --harness claude --yes >/dev/null 2>&1
  mk_settings "$H/.claude/settings.json" "$PS" "$ALL5"
  run INST uninstall --home "$H" --harness claude --yes
  assert_rc "AC-B5 uninstall (claude) exits 0" 0
  assert_eq "AC-B5 uninstall removed every agent-playbook handler" "0" "$(grep -c '# agent-playbook:' "$H/.claude/settings.json" 2>/dev/null)"
  assert_contains "AC-B5 uninstall kept the foreign hook" "$(cat "$H/.claude/settings.json" 2>/dev/null)" "/usr/local/bin/audit-bash.sh"
  assert_no_path "AC-B5 uninstall still removed ~/.agents/playbook" "$H/.agents/playbook"

  # install.ps1 runs: bash install.sh <command> --home <USERPROFILE> --copy [--harness H] [--yes] (install.ps1:25-36)
  H="$(mk_home)"
  bash "$PB_ROOT/install.sh" install --home "$H" --copy --harness claude --yes >/dev/null 2>&1
  mk_settings "$H/.claude/settings.json" "$PS" "$ALL5"
  run bash "$PB_ROOT/install.sh" uninstall --home "$H" --copy --harness claude --yes
  assert_rc "AC-B5 uninstall the install.ps1 way (--home --copy) exits 0" 0
  assert_eq "AC-B5 install.ps1 way: every agent-playbook handler removed" "0" "$(grep -c '# agent-playbook:' "$H/.claude/settings.json" 2>/dev/null)"
  assert_contains "AC-B5 install.ps1 way: foreign hook kept" "$(cat "$H/.claude/settings.json" 2>/dev/null)" "/usr/local/bin/audit-bash.sh"
else t_skip 7 "AC-B5 uninstall removes hooks (no node)"; fi

echo "AC-B5 uninstall on a home without settings.json creates none"
H="$(mk_home)"
INST install --home "$H" --harness claude --yes >/dev/null 2>&1
run INST uninstall --home "$H" --harness claude --yes
assert_rc "uninstall (claude) without settings.json exits 0" 0
assert_no_path "AC-B5 uninstall creates no settings.json (characterization: true before k1b too)" "$H/.claude/settings.json"
assert_eq "AC-B5 uninstall makes no backup of a settings.json that does not exist" "" "$(ls "$H/.agents/playbook-backups" 2>/dev/null | grep '^settings\.json' )"

echo "AC-B5 uninstall without node: WARN with the manual step, still finishes"
BASHX="$(command -v bash)"
NB="$(mk_tmp)"
for t in awk basename cat chmod cmp comm cp cut cygpath date diff dirname env expr find git grep head id ln ls mkdir mktemp mv od readlink realpath rm rmdir sed sh sort stat tail tee touch tr uname uniq wc xargs; do
  p="$(command -v "$t" 2>/dev/null)" || continue
  case "$p" in /*) ;; *) continue ;; esac
  printf '#!%s\nexec "%s" "$@"\n' "$BASHX" "$p" > "$NB/$t"; chmod +x "$NB/$t" 2>/dev/null
done
printf '#!%s\nexec "%s" "$@"\n' "$BASHX" "$BASHX" > "$NB/bash"; chmod +x "$NB/bash" 2>/dev/null
# probe: the node-free PATH must lack node and run a plain uninstall to the end (control without hooks)
NONODE=0
HC="$(mk_home)"
INST install --home "$HC" --harness claude --yes >/dev/null 2>&1
if ! env PATH="$NB" "$BASHX" -c 'command -v node' >/dev/null 2>&1 &&
   env PATH="$NB" "$BASHX" "$PB_ROOT/install.sh" uninstall --home "$HC" --harness claude --yes $MODEFLAG >/dev/null 2>&1 &&
   [ ! -e "$HC/.agents/playbook" ]; then NONODE=1; fi
if [ "$NONODE" = 1 ]; then
  H="$(mk_home)"
  INST install --home "$H" --harness claude --yes >/dev/null 2>&1
  mk_settings "$H/.claude/settings.json" "$PS" "$ALL5"; S0="$(ck "$H/.claude/settings.json")"
  run env PATH="$NB" "$BASHX" "$PB_ROOT/install.sh" uninstall --home "$H" --harness claude --yes $MODEFLAG
  assert_rc "AC-B5 uninstall without node still exits 0" 0
  has_re "AC-B5 uninstall without node prints a WARN about the hooks" "$OUT" '^WARN: .*hook'
  assert_eq "AC-B5 uninstall without node leaves settings.json byte-identical" "$S0" "$(ck "$H/.claude/settings.json")"
  assert_no_path "AC-B5 uninstall without node still removes ~/.agents/playbook" "$H/.agents/playbook"
else t_skip 4 "AC-B5 uninstall without node (cannot build a node-free PATH that runs install.sh here)"; fi

t_summary
