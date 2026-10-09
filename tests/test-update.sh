#!/usr/bin/env bash
# Tests for `install.sh update` against a throw-away origin with two tagged releases.
. "$(dirname "$0")/lib.sh"

W="$(mk_tmp)"
SRC="$W/src"
mkdir -p "$SRC"
if ! (cd "$PB_ROOT" && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
  echo "skip: $PB_ROOT is not a git checkout"; t_summary; exit 0
fi
( cd "$PB_ROOT" && git ls-files -co --exclude-standard ) | while IFS= read -r f; do
  [ -f "$PB_ROOT/$f" ] || continue
  mkdir -p "$SRC/$(dirname "$f")" && cp -p "$PB_ROOT/$f" "$SRC/$f"
done
G() { git -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }
( cd "$SRC" && git init -q && printf '0.1.0\n' > VERSION && G add -A && G commit -qm r1 && G tag -a v0.1.0 -m v0.1.0 &&
  printf '0.2.0\n' > VERSION &&
  { printf '# Changelog\n\n## 0.2.0 - test\n- marker-for-0.2.0\n\n'; sed 1d CHANGELOG.md; } > CHANGELOG.tmp && mv CHANGELOG.tmp CHANGELOG.md &&
  G commit -qam r2 && G tag -a v0.2.0 -m v0.2.0 ) || { echo "fixture setup failed"; exit 3; }
git clone -q --bare "$SRC" "$W/origin.git"
git clone -q "$W/origin.git" "$W/client" 2>/dev/null
C="$W/client"
( cd "$C" && git checkout -q v0.1.0 )
export PLAYBOOK_REGISTRY="$W/registry"
INST() { bash "$C/install.sh" "$@"; }
hdr() { grep -o 'BEGIN agent-playbook v[0-9.]*' "$1" | head -n 1; }

echo "registry"
H="$(mk_tmp)"
run INST install --home "$H" --harness claude --yes
assert_rc "install from v0.1.0 ok" 0
assert_contains "registry records the home" "$(cat "$PLAYBOOK_REGISTRY")" "$H"
assert_contains "registry records the harness" "$(cat "$PLAYBOOK_REGISTRY")" "claude"
assert_eq "installed block is v0.1.0" "BEGIN agent-playbook v0.1.0" "$(hdr "$H/.claude/CLAUDE.md")"
H2="$(mk_tmp)"
run INST install --home "$H2" --harness codex --copy --yes
assert_contains "copy-mode target recorded with its mode" "$(grep "$H2" "$PLAYBOOK_REGISTRY")" "copy"
run INST install --home "$H" --harness codex --yes
TAB="$(printf '\t')"
assert_eq "same home is one registry line" "1" "$(grep -c "^$H$TAB" "$PLAYBOOK_REGISTRY")"
assert_contains "harness lists are merged" "$(grep "^$H$TAB" "$PLAYBOOK_REGISTRY")" "claude,codex"

echo "check"
run INST update --check
assert_rc "check ok" 0
assert_contains "check reports the newer tag" "$OUT" "v0.2.0"
assert_contains "check says an update exists" "$OUT" "UPDATE AVAILABLE"

echo "guards"
run INST update
assert_rc "non-interactive update without --yes -> exit 2" 2
printf 'dirty\n' >> "$C/README.md"
run INST update --yes
assert_rc "dirty working tree -> exit 1" 1
assert_contains "explains why" "$OUT" "uncommitted"
( cd "$C" && git checkout -q -- README.md )

echo "update"
run INST update --yes
assert_rc "update ok" 0
assert_eq "repo now at v0.2.0" "v0.2.0" "$(cd "$C" && git describe --tags --exact-match 2>/dev/null)"
assert_contains "shows the changelog of the new release" "$OUT" "marker-for-0.2.0"
assert_eq "symlink target block upgraded" "BEGIN agent-playbook v0.2.0" "$(hdr "$H/.claude/CLAUDE.md")"
assert_eq "codex block upgraded too" "BEGIN agent-playbook v0.2.0" "$(hdr "$H/.codex/AGENTS.md")"
assert_eq "copy-mode target refreshed" "0.2.0" "$(tr -d '[:space:]' < "$H2/.agents/playbook/VERSION")"
run INST doctor --home "$H2" --harness codex
assert_rc "doctor healthy on the copy target after update" 0
run INST update --check
assert_contains "now up to date" "$OUT" "up to date"

echo "rollback"
run INST update --to v0.1.0 --yes
assert_rc "rollback ok" 0
assert_eq "block back to v0.1.0" "BEGIN agent-playbook v0.1.0" "$(hdr "$H/.claude/CLAUDE.md")"
run INST update --to v9.9.9 --yes
assert_rc "unknown tag -> exit 2" 2

echo "stale targets are pruned"
printf '%s\tclaude\tlink\n' "$W/no-such-home" >> "$PLAYBOOK_REGISTRY"
run INST update --yes
assert_rc "update with a stale entry ok" 0
assert_contains "reports the skip" "$OUT" "skipping"
assert_not_contains "stale entry removed" "$(cat "$PLAYBOOK_REGISTRY")" "no-such-home"

echo "uninstall drops the registry entry"
run INST uninstall --home "$H2" --harness codex --yes
assert_not_contains "registry no longer lists the home" "$(cat "$PLAYBOOK_REGISTRY")" "$H2"

t_summary
