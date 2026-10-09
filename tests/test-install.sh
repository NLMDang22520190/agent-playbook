#!/usr/bin/env bash
# Tests for install.sh. Everything runs against throw-away --home sandboxes;
# the real home directory is never touched.
. "$(dirname "$0")/lib.sh"
INST() { bash "$PB_ROOT/install.sh" "$@"; }
SENTENCE='Before making any changes, inspect the relevant context and identify any ambiguities or assumptions that could materially affect the implementation. Ask only the necessary clarification questions. If the requirements are already sufficiently clear, proceed without asking unnecessary questions.'
BEGIN='<!-- BEGIN agent-playbook'
END='<!-- END agent-playbook -->'
count_in() { grep -c -- "$2" "$1" 2>/dev/null || true; }

echo "detection and arguments"
H="$(mk_tmp)"
run INST install --home "$H"
assert_rc "no harness detected and none given -> exit 2" 2
assert_contains "message says to pass --harness" "$OUT" "--harness"
run INST install --home "$H" --harness wizard
assert_rc "unknown harness rejected" 2
run INST frobnicate --home "$H"
assert_rc "unknown command rejected" 2
mkdir -p "$H/.claude"
run INST install --home "$H" --dry-run
assert_rc "auto-detects claude from ~/.claude (dry run)" 0
assert_contains "dry run announces claude" "$OUT" "claude"

echo "dry run changes nothing"
H="$(mk_tmp)"
run INST install --home "$H" --harness all --dry-run
assert_rc "dry-run exits 0" 0
assert_no_path "dry-run created no ~/.agents" "$H/.agents"
assert_no_path "dry-run created no ~/.claude" "$H/.claude"
assert_no_path "dry-run created no ~/.codex" "$H/.codex"

echo "install claude + codex (symlinks)"
H="$(mk_tmp)"
mkdir -p "$H/.claude/skills/other-skill" "$H/.claude"
printf '# my own rules\n' > "$H/.claude/CLAUDE.md"
run INST install --home "$H" --harness claude,codex --yes
assert_rc "install ok" 0
assert_link_to "claude: tdd skill linked" "$H/.claude/skills/playbook-tdd" "$PB_ROOT/skills/playbook-tdd"
assert_link_to "claude: setup skill linked" "$H/.claude/skills/playbook-setup" "$PB_ROOT/skills/playbook-setup"
assert_link_to "codex: tdd skill linked under ~/.agents/skills" "$H/.agents/skills/playbook-tdd" "$PB_ROOT/skills/playbook-tdd"
assert_link_to "stable scripts path" "$H/.agents/playbook/scripts" "$PB_ROOT/scripts"
assert_link_to "stable templates path" "$H/.agents/playbook/templates" "$PB_ROOT/templates"
assert_dir "foreign skill untouched" "$H/.claude/skills/other-skill"
assert_no_path "no opencode-specific skills dir" "$H/.config/opencode/skills"
assert_contains "claude global keeps user text" "$(cat "$H/.claude/CLAUDE.md")" "# my own rules"
assert_contains "claude global has the managed block" "$(cat "$H/.claude/CLAUDE.md")" "$BEGIN"
assert_contains "claude global has the verbatim clarify sentence" "$(cat "$H/.claude/CLAUDE.md")" "$SENTENCE"
assert_contains "codex global has the verbatim clarify sentence" "$(cat "$H/.codex/AGENTS.md")" "$SENTENCE"
assert_eq "exactly one block in claude file" "1" "$(count_in "$H/.claude/CLAUDE.md" "$BEGIN")"
BAK="$(ls "$H/.agents/playbook-backups" 2>/dev/null | head -1)"
if [ -n "$BAK" ]; then t_ok "pre-existing global file was backed up"; else t_bad "pre-existing global file was backed up"; fi
assert_contains "backup holds the original text" "$(cat "$H/.agents/playbook-backups/$BAK" 2>/dev/null)" "# my own rules"

echo "idempotence"
S1="$(cat "$H/.claude/CLAUDE.md" "$H/.codex/AGENTS.md" | cksum)"
run INST install --home "$H" --harness claude,codex --yes
assert_rc "second install ok" 0
S2="$(cat "$H/.claude/CLAUDE.md" "$H/.codex/AGENTS.md" | cksum)"
assert_eq "global files byte-identical after re-install" "$S1" "$S2"
assert_eq "still one block" "1" "$(count_in "$H/.claude/CLAUDE.md" "$BEGIN")"

echo "status and doctor"
run INST status --home "$H" --harness claude,codex
assert_rc "status ok" 0
assert_contains "status reports claude installed" "$OUT" "claude: installed"
assert_contains "status reports codex installed" "$OUT" "codex: installed"
run INST doctor --home "$H" --harness claude,codex
assert_rc "doctor passes on a healthy install" 0
# drift: someone edited inside the managed block
sed -i.bak 's/Scope discipline/Scope DISCIPLINE/' "$H/.claude/CLAUDE.md" 2>/dev/null; rm -f "$H/.claude/CLAUDE.md.bak"
run INST doctor --home "$H" --harness claude
assert_rc "doctor detects drift in the managed block" 1
assert_contains "drift message" "$OUT" "drift"
run INST install --home "$H" --harness claude --yes
run INST doctor --home "$H" --harness claude
assert_rc "re-install repairs drift" 0
rm "$H/.claude/skills/playbook-proof"
run INST doctor --home "$H" --harness claude
assert_rc "doctor detects a missing skill link" 1
run INST install --home "$H" --harness claude --yes
run INST doctor --home "$H" --harness claude
assert_rc "re-install repairs the missing link" 0

echo "codex override warning"
printf 'local override\n' > "$H/.codex/AGENTS.override.md"
run INST install --home "$H" --harness codex --yes
assert_contains "warns that AGENTS.override.md shadows AGENTS.md" "$OUT" "AGENTS.override.md"
run INST doctor --home "$H" --harness codex
assert_rc "doctor fails while the override shadows the block" 1
rm "$H/.codex/AGENTS.override.md"

echo "opencode interplay"
H="$(mk_tmp)"
run INST install --home "$H" --harness claude,opencode --yes
assert_rc "claude+opencode ok" 0
assert_no_path "opencode global file not created when claude file covers it" "$H/.config/opencode/AGENTS.md"
assert_contains "explains the fallback" "$OUT" "falls back"
assert_no_path "no duplicate skills for opencode" "$H/.agents/skills/playbook-tdd"
H="$(mk_tmp)"
run INST install --home "$H" --harness opencode --yes
assert_rc "opencode only ok" 0
assert_link_to "opencode-only uses ~/.agents/skills" "$H/.agents/skills/playbook-tdd" "$PB_ROOT/skills/playbook-tdd"
assert_contains "opencode-only gets its own rules file" "$(cat "$H/.config/opencode/AGENTS.md")" "$SENTENCE"
run INST doctor --home "$H" --harness opencode
assert_rc "doctor ok for opencode only" 0

echo "uninstall"
H="$(mk_tmp)"
mkdir -p "$H/.claude/skills/other-skill"
printf '# keep me\n' > "$H/.claude/CLAUDE.md"
run INST install --home "$H" --harness claude,codex --yes
run INST uninstall --home "$H" --harness claude,codex --yes
assert_rc "uninstall ok" 0
assert_no_path "skill link removed (claude)" "$H/.claude/skills/playbook-tdd"
assert_no_path "skill link removed (codex)" "$H/.agents/skills/playbook-tdd"
assert_no_path "stable path removed" "$H/.agents/playbook"
assert_dir "foreign skill kept" "$H/.claude/skills/other-skill"
assert_contains "user text kept" "$(cat "$H/.claude/CLAUDE.md")" "# keep me"
assert_not_contains "block removed" "$(cat "$H/.claude/CLAUDE.md")" "$BEGIN"
assert_no_path "codex file with only our block is removed" "$H/.codex/AGENTS.md"

echo "refuses to clobber real directories"
H="$(mk_tmp)"
mkdir -p "$H/.claude/skills/playbook-tdd"; printf 'mine\n' > "$H/.claude/skills/playbook-tdd/SKILL.md"
run INST install --home "$H" --harness claude --yes
if [ "$RC" -ne 0 ]; then t_ok "install refuses without --force"; else t_bad "install refuses without --force" "rc=$RC"; fi
assert_eq "user's directory untouched" "mine" "$(cat "$H/.claude/skills/playbook-tdd/SKILL.md")"
run INST install --home "$H" --harness claude --yes --force
assert_rc "--force proceeds" 0
assert_link_to "--force replaced it with a link" "$H/.claude/skills/playbook-tdd" "$PB_ROOT/skills/playbook-tdd"
FOUND="$(grep -rl '^mine$' "$H/.agents/playbook-backups" 2>/dev/null | head -1)"
if [ -n "$FOUND" ]; then t_ok "--force kept the old directory in backups"; else t_bad "--force kept the old directory in backups"; fi

echo "copy mode (Windows without symlink rights)"
H="$(mk_tmp)"
mkdir -p "$H/.claude/skills/other-skill"
run INST install --home "$H" --harness claude --copy --yes
assert_rc "copy install ok" 0
if [ -d "$H/.claude/skills/playbook-tdd" ] && [ ! -L "$H/.claude/skills/playbook-tdd" ]; then t_ok "skill is a real directory"; else t_bad "skill is a real directory"; fi
assert_file "copy carries a managed marker" "$H/.claude/skills/playbook-tdd/.playbook-managed"
assert_file "scripts copied to stable path" "$H/.agents/playbook/scripts/role-gate.sh"
printf 'tampered\n' > "$H/.claude/skills/playbook-tdd/SKILL.md"
run INST doctor --home "$H" --harness claude
assert_rc "doctor detects a drifted copy" 1
run INST install --home "$H" --harness claude --copy --yes
assert_rc "re-install in copy mode ok" 0
assert_contains "copy refreshed from the repo" "$(cat "$H/.claude/skills/playbook-tdd/SKILL.md")" "name: playbook-tdd"
run INST uninstall --home "$H" --harness claude --yes
assert_no_path "managed copy removed" "$H/.claude/skills/playbook-tdd"
assert_dir "foreign skill kept in copy mode" "$H/.claude/skills/other-skill"

t_summary
