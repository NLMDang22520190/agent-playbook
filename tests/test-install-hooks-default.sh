#!/usr/bin/env bash
# Tests for v0.33.0 slice S3 (AC5'/N1/N2/N5/N6): install.sh install installs the Claude Code hooks by default unless --no-hooks,
# PB_HOOKS=off (one run, nothing persisted) or `hooks_optout yes` in <home>/.agents/playbook.conf; --hooks turns them back on;
# a legacy `hooks off` (the old default) does not stop the install and earns one line. Throw-away --home sandboxes and stand-in
# HOME/PLAYBOOK_HOME; the real home is never touched. Real node merge, so the node tests skip without node.
. "$(dirname "$0")/lib.sh"
unset PLAYBOOK_HOME PB_HOOKS
HOME="$(cd "$(mk_tmp)" && pwd -P)"; export HOME
INST() { bash "$PB_ROOT/install.sh" "$@" $MODEFLAG; }
export PLAYBOOK_REGISTRY="$(mk_tmp)/registry"
HAVE_NODE=0
if command -v node >/dev/null 2>&1 && node -e '' >/dev/null 2>&1; then HAVE_NODE=1; fi
[ "$HAVE_NODE" = 1 ] || echo "note: node not found: the merge tests are skipped"
ck() { cksum < "$1" 2>/dev/null; }
mk_home() { cd "$(mk_tmp)" && pwd -P; }
nh() { grep -c '# agent-playbook:' "$1/.claude/settings.json" 2>/dev/null || true; }   # handlers in H settings.json
conf_line() { grep -x "hooks_optout=.*" "$1/.agents/playbook.conf" 2>/dev/null || true; }
has_line() { if printf '%s\n' "$2" | grep -qxF -- "$3"; then t_ok "$1"; else t_bad "$1" "no line [$3] in [$2]"; fi; }
no_line() { if printf '%s\n' "$2" | grep -qF -- "$3"; then t_bad "$1" "unexpected [$3] in [$2]"; else t_ok "$1"; fi; }
LEGACY='hooks: turned on (they were off by the old default; turn off: install.sh install --no-hooks)'
WARN_NI='WARN  hooks: not installed (run install.sh install, or install.sh install --no-hooks to keep them off)'
OFFL='INFO  hooks: off (hooks_optout yes; turn on: install.sh install --hooks)'
OKL='OK    hooks: guard, learnings installed'
HOME_CONF="$HOME/.agents/playbook.conf"
mkdir -p "$HOME/.agents"; printf 'autonomy=full\n' > "$HOME_CONF"; HC0="$(ck "$HOME_CONF")"   # the stand-in HOME conf must never change

if [ "$HAVE_NODE" = 1 ]; then
echo "AC5' default install (claude): the five handlers are installed, no opt-out written, doctor OK"
H="$(mk_home)"
run INST install --home "$H" --harness claude --yes
assert_rc "AC5' default install exits 0" 0
assert_eq "AC5' default install puts the five agent-playbook handlers in <home>/.claude/settings.json" "5" "$(nh "$H")"
assert_contains "AC5' the install output names the hooks step" "$OUT" "hooks"
assert_eq "AC5' a default install writes no hooks_optout" "" "$(conf_line "$H")"
no_line "AC5' N5 a fresh default install prints no legacy line" "$OUT" "turned on"
run INST doctor --home "$H" --harness claude
assert_rc "AC5' doctor after a default install exits 0" 0
has_line "AC5' doctor after a default install: OK guard, learnings installed" "$OUT" "$OKL"
S1="$(ck "$H/.claude/settings.json")"; B1="$(ls "$H/.agents/playbook-backups" 2>/dev/null | grep -c '^settings\.json')"
run INST install --home "$H" --harness claude --yes
assert_rc "AC5' second default install exits 0" 0
assert_eq "AC5' second default install: settings.json byte-identical" "$S1" "$(ck "$H/.claude/settings.json")"
assert_eq "AC5' second default install: no new settings backup" "$B1" "$(ls "$H/.agents/playbook-backups" 2>/dev/null | grep -c '^settings\.json')"

echo "AC5' a foreign settings.json is merged, not replaced, with a backup"
H="$(mk_home)"; mkdir -p "$H/.claude"
printf '{\n  "model": "opus",\n  "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "/usr/local/bin/audit-bash.sh"}]}]}\n}\n' > "$H/.claude/settings.json"
run INST install --home "$H" --harness claude --yes
assert_rc "AC5' install over a foreign settings.json exits 0" 0
assert_eq "AC5' handlers added to the foreign file" "5" "$(nh "$H")"
assert_contains "AC5' foreign hook kept" "$(cat "$H/.claude/settings.json")" "/usr/local/bin/audit-bash.sh"
assert_contains "AC5' foreign key kept" "$(cat "$H/.claude/settings.json")" '"model": "opus"'
assert_eq "AC5' one backup of the old settings.json" "1" "$(ls "$H/.agents/playbook-backups" 2>/dev/null | grep -c '^settings\.json')"

echo "AC5' N2 --no-hooks: nothing installed, hooks_optout yes in H conf only (never HOME conf, never PLAYBOOK_HOME conf)"
H="$(mk_home)"; OTHER="$(mk_home)"
run env PLAYBOOK_HOME="$OTHER" bash "$PB_ROOT/install.sh" install --home "$H" --harness claude --yes --no-hooks $MODEFLAG
assert_rc "AC5' --no-hooks install exits 0" 0
assert_no_path "AC5' --no-hooks: no settings.json" "$H/.claude/settings.json"
assert_eq "AC5' N2 --no-hooks writes hooks_optout=yes in <home>/.agents/playbook.conf" "hooks_optout=yes" "$(conf_line "$H")"
assert_eq "AC5' N2 --no-hooks leaves HOME conf byte-identical" "$HC0" "$(ck "$HOME_CONF")"
assert_no_path "AC5' N2 --no-hooks does not write the conf PLAYBOOK_HOME points at" "$OTHER/.agents/playbook.conf"
run INST doctor --home "$H" --harness claude
assert_rc "AC5' doctor after --no-hooks exits 0" 0
has_line "AC5' doctor after --no-hooks: INFO off" "$OUT" "$OFFL"
run INST install --home "$H" --harness claude --yes
assert_no_path "AC5' a later plain install keeps the opt-out (update keeps the choice): no settings.json" "$H/.claude/settings.json"
assert_eq "AC5' the opt-out stays" "hooks_optout=yes" "$(conf_line "$H")"
run INST install --home "$H" --harness claude --yes --hooks
assert_rc "AC5' --hooks install exits 0" 0
assert_eq "AC5' --hooks installs the five handlers" "5" "$(nh "$H")"
assert_eq "AC5' --hooks sets hooks_optout=no" "hooks_optout=no" "$(conf_line "$H")"
assert_eq "AC5' N2 --hooks leaves HOME conf byte-identical" "$HC0" "$(ck "$HOME_CONF")"
run INST doctor --home "$H" --harness claude
has_line "AC5' doctor after --hooks: OK" "$OUT" "$OKL"

echo "AC5' PB_HOOKS=off: this run installs nothing and persists nothing; the next plain run installs"
H="$(mk_home)"
run env PB_HOOKS=off bash "$PB_ROOT/install.sh" install --home "$H" --harness claude --yes $MODEFLAG
assert_rc "AC5' PB_HOOKS=off install exits 0" 0
assert_no_path "AC5' PB_HOOKS=off: no settings.json" "$H/.claude/settings.json"
assert_eq "AC5' PB_HOOKS=off persists no hooks_optout" "" "$(conf_line "$H")"
run INST install --home "$H" --harness claude --yes
assert_eq "AC5' the run after PB_HOOKS=off installs the handlers" "5" "$(nh "$H")"
H="$(mk_home)"
run env PB_HOOKS=on bash "$PB_ROOT/install.sh" install --home "$H" --harness claude --yes $MODEFLAG
assert_eq "AC5' PB_HOOKS=on (not off) still installs" "5" "$(nh "$H")"

echo "AC5' hand-written conf: hooks_optout yes stops the install, hooks_optout no does not"
H="$(mk_home)"; mkdir -p "$H/.agents"; printf 'hooks_optout=yes\n' > "$H/.agents/playbook.conf"
run INST install --home "$H" --harness claude --yes
assert_rc "AC5' install with hooks_optout=yes exits 0" 0
assert_no_path "AC5' hooks_optout=yes in H conf: no settings.json" "$H/.claude/settings.json"
H="$(mk_home)"; mkdir -p "$H/.agents"; printf 'hooks_optout=no\n' > "$H/.agents/playbook.conf"
run INST install --home "$H" --harness claude --yes
assert_eq "AC5' hooks_optout=no installs" "5" "$(nh "$H")"
H="$(mk_home)"   # an opt-out in the HOME conf does not govern a different --home (N2)
printf 'hooks_optout=yes\n' > "$HOME_CONF"
run INST install --home "$H" --harness claude --yes
assert_eq "AC5' N2 an opt-out in HOME conf does not stop an install into another --home" "5" "$(nh "$H")"
printf 'autonomy=full\n' > "$HOME_CONF"

echo "AC5' D8/N5 legacy hooks=off (the old default) does not stop the install; one line says so"
H="$(mk_home)"; mkdir -p "$H/.agents"; printf 'hooks=off\n' > "$H/.agents/playbook.conf"
run INST install --home "$H" --harness claude --yes
assert_rc "AC5' install with legacy hooks=off exits 0" 0
assert_eq "AC5' D8 legacy hooks=off: the handlers are installed" "5" "$(nh "$H")"
has_line "AC5' N5 the legacy line, exact" "$OUT" "$LEGACY"
run INST install --home "$H" --harness claude --yes
no_line "AC5' N5 the legacy line is not printed again when the handlers were already there" "$OUT" "turned on"
H="$(mk_home)"; mkdir -p "$H/.agents"; printf 'hooks=off\n' > "$H/.agents/playbook.conf"
run env PB_HOOKS=off bash "$PB_ROOT/install.sh" install --home "$H" --harness claude --yes $MODEFLAG
no_line "AC5' N5 no legacy line when this run added no handlers (PB_HOOKS=off)" "$OUT" "turned on"
H="$(mk_home)"; mkdir -p "$H/.agents"; printf 'hooks=off\n' > "$H/.agents/playbook.conf"
run INST install --home "$H" --harness claude --yes --no-hooks
no_line "AC5' N5 no legacy line with --no-hooks" "$OUT" "turned on"
assert_no_path "AC5' legacy conf + --no-hooks: nothing installed" "$H/.claude/settings.json"
assert_eq "AC5' legacy conf + --no-hooks writes hooks_optout=yes" "hooks_optout=yes" "$(conf_line "$H")"

echo "AC5' --dry-run prints the hook step and changes nothing"
H="$(mk_home)"
run INST install --home "$H" --harness claude --dry-run
assert_rc "AC5' dry-run exits 0" 0
assert_contains "AC5' dry-run prints the hook step" "$OUT" "hooks"
assert_no_path "AC5' dry-run: no settings.json" "$H/.claude/settings.json"
assert_no_path "AC5' dry-run: no .agents dir" "$H/.agents"
H="$(mk_home)"
run INST install --home "$H" --harness claude --dry-run --no-hooks
assert_no_path "AC5' dry-run --no-hooks writes no conf" "$H/.agents/playbook.conf"
assert_no_path "AC5' dry-run --no-hooks writes no settings.json" "$H/.claude/settings.json"

echo "AC5' codex-only install has no hooks step and no settings.json"
H="$(mk_home)"
run INST install --home "$H" --harness codex --yes
assert_rc "AC5' codex install exits 0" 0
assert_no_path "AC5' codex install writes no ~/.claude/settings.json" "$H/.claude/settings.json"
else t_skip 60 "AC5' merge tests (no node)"; fi

echo "AC5' without node: WARN, install still exits 0, nothing half-written"
BASHX="$(command -v bash)"; NB="$(mk_tmp)"
for t in awk basename cat chmod cmp comm cp cut cygpath date diff dirname env expr find git grep head id ln ls mkdir mktemp mv od readlink realpath rm rmdir sed sh sort stat tail tee touch tr uname uniq wc xargs; do
  p="$(command -v "$t" 2>/dev/null)" || continue
  case "$p" in /*) ;; *) continue ;; esac
  printf '#!%s\nexec "%s" "$@"\n' "$BASHX" "$p" > "$NB/$t"; chmod +x "$NB/$t" 2>/dev/null
done
printf '#!%s\nexec "%s" "$@"\n' "$BASHX" "$BASHX" > "$NB/bash"; chmod +x "$NB/bash" 2>/dev/null
NONODE=0
HC="$(mk_home)"
if ! env PATH="$NB" "$BASHX" -c 'command -v node' >/dev/null 2>&1 &&
   env PB_HOOKS=off PATH="$NB" "$BASHX" "$PB_ROOT/install.sh" install --home "$HC" --harness claude --yes $MODEFLAG >/dev/null 2>&1; then NONODE=1; fi
if [ "$NONODE" = 1 ]; then
  H="$(mk_home)"
  run env PATH="$NB" "$BASHX" "$PB_ROOT/install.sh" install --home "$H" --harness claude --yes $MODEFLAG
  assert_rc "AC5' install without node exits 0" 0
  if printf '%s\n' "$OUT" | grep -qE '^WARN: .*hooks'; then t_ok "AC5' install without node prints a WARN about the hooks"; else t_bad "AC5' install without node prints a WARN about the hooks" "$OUT"; fi
  assert_no_path "AC5' install without node writes no settings.json" "$H/.claude/settings.json"
  assert_file "AC5' install without node still installs the playbook (stable dir)" "$H/.agents/playbook/VERSION"
  run env PATH="$NB" "$BASHX" "$PB_ROOT/install.sh" doctor --home "$H" --harness claude
  assert_rc "AC5' doctor without hooks and without node exits 0 (never a problem line)" 0
  has_line "AC5' doctor without node: WARN not installed" "$OUT" "$WARN_NI"
else t_skip 6 "AC5' without node (cannot build a node-free PATH here)"; fi

t_summary
