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
INST() { bash "$C/install.sh" "$@" $MODEFLAG; }   # --copy where symlinks are unavailable
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

# --- update --check reports the relation between HEAD and the newest release (spec S1) ---
# Separate origin so the flows above are untouched. History (B = untagged, Y = newest tag v0.3.0):
#   v0.1.0 -- v0.2.0 -- B -- Y(v0.3.0)
# Local-only commits in the client: two on top of Y (ahead), one on top of v0.2.0 (diverged).
RO="$W/rel-origin.git"
git clone -q --bare "$W/origin.git" "$RO"
git clone -q "$RO" "$W/rel-src" 2>/dev/null
( cd "$W/rel-src" && git checkout -q v0.2.0 &&
  G commit -q --allow-empty -m behind &&
  G commit -q --allow-empty -m r3 && G tag -a v0.3.0 -m v0.3.0 &&
  G push -q origin HEAD:refs/heads/rel v0.3.0 ) || { echo "relation fixture setup failed"; exit 3; }
R="$W/rel-client"
git clone -q "$RO" "$R" 2>/dev/null
( cd "$R" && git fetch -q --tags origin ) || { echo "relation client setup failed"; exit 3; }
RINST() { bash "$R/install.sh" "$@"; }
rco() { ( cd "$R" && git checkout -q "$1" ) || { echo "checkout $1 failed"; exit 3; }; }

echo "check: HEAD on the newest release"
rco v0.3.0
run RINST update --check
assert_rc "AC1 check on newest tag exits 0" 0
assert_contains "AC1 HEAD at newest tag reports up to date" "$OUT" "up to date"
assert_not_contains "AC1 HEAD at newest tag does not offer an update" "$OUT" "UPDATE AVAILABLE"

echo "check: HEAD on an older release"
rco v0.1.0
run RINST update --check
assert_rc "AC2 check on older tag exits 0" 0
assert_contains "AC2 older tag reports UPDATE AVAILABLE" "$OUT" "UPDATE AVAILABLE"
assert_contains "AC2 older tag names the newest tag" "$OUT" "v0.3.0"

echo "check: untagged HEAD ahead of the newest release"
rco v0.3.0
( cd "$R" && G commit -q --allow-empty -m local1 && G commit -q --allow-empty -m local2 ) || { echo "ahead setup failed"; exit 3; }
run RINST update --check
assert_rc "AC3 ahead checkout exits 0" 0
assert_not_contains "AC3 ahead checkout is not told to update" "$OUT" "UPDATE AVAILABLE"
assert_contains "AC3 ahead checkout says ahead of the newest tag" "$OUT" "ahead of v0.3.0"
assert_contains "AC3 ahead checkout states the commit count" "$OUT" "ahead of v0.3.0 by 2 commit"

echo "check: untagged HEAD behind the newest release"
rco "v0.3.0~1"
run RINST update --check
assert_rc "AC4 behind checkout exits 0" 0
assert_contains "AC4 behind checkout reports UPDATE AVAILABLE" "$OUT" "UPDATE AVAILABLE"
assert_contains "AC4 behind checkout names the newest tag" "$OUT" "v0.3.0"

echo "check: untagged HEAD diverged from the newest release"
rco v0.2.0
( cd "$R" && G commit -q --allow-empty -m side ) || { echo "diverged setup failed"; exit 3; }
run RINST update --check
assert_rc "AC5 diverged checkout exits 0" 0
assert_not_contains "AC5 diverged checkout is not told to update" "$OUT" "UPDATE AVAILABLE"
assert_contains "AC5 diverged checkout says diverged from the newest tag" "$OUT" "diverged from v0.3.0"

echo "check: two tags on the HEAD commit"
# v0.3.1 is a lightweight tag on the same commit as the annotated v0.3.0; it is the newest by version.
( cd "$W/rel-src" && G tag v0.3.1 v0.3.0^{} && G push -q origin v0.3.1 &&
  cd "$R" && git fetch -q --tags origin ) || { echo "second tag setup failed"; exit 3; }
rco v0.3.0
run RINST update --check
assert_rc "AC6 two tags on HEAD exits 0" 0
assert_contains "AC6 HEAD carrying the newest tag's commit reports up to date" "$OUT" "up to date"
assert_not_contains "AC6 HEAD carrying the newest tag's commit does not offer an update" "$OUT" "UPDATE AVAILABLE"

t_summary
