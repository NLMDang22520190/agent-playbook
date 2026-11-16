#!/usr/bin/env bash
# AC8 (v0.37 Q5): conf.sh check-harness warns when playbook.conf harness differs from the running harness; install.sh doctor calls it.
. "$(dirname "$0")/lib.sh"
CONF="$PB_ROOT/scripts/conf.sh"
H="$(mk_tmp)"
export PLAYBOOK_HOME="$H"
bash "$CONF" set harness codex --global >/dev/null 2>&1
# ch ENVSPEC... -- ARGS: run check-harness with the harness hints removed, then ENVSPEC added
ch() { local e=(); while [ "$1" != "--" ]; do e+=("$1"); shift; done; shift
  OUT="$(env -u CLAUDECODE -u CODEX_HOME "${e[@]}" bash "$CONF" check-harness "$@" 2>&1 >/dev/null)"; RC=$?; }

echo "AC8 check-harness"
ch CLAUDECODE=1 --
assert_rc "AC8 mismatch exits 0" 0
assert_eq "AC8 mismatch warns (CLAUDECODE=1 vs harness=codex)" "warning: playbook.conf harness=codex but the running harness looks like claude (role-model routing does not read this key; run conf.sh set harness claude --global)" "$OUT"
ch -- --running claude
assert_contains "AC8 --running overrides the environment" "$OUT" "looks like claude"
ch CODEX_HOME=/x --
assert_eq "AC8 match is silent (CODEX_HOME vs harness=codex)" "" "$OUT"
assert_rc "AC8 match exits 0" 0
ch --
assert_eq "AC8 unknown running harness is silent" "" "$OUT"
assert_rc "AC8 unknown exits 0" 0
ch CLAUDECODE=1 CODEX_HOME=/x --
assert_eq "AC8 both hints (ambiguous) is silent" "" "$OUT"
ch CODEX_HOME=/x -- --running claude
assert_contains "AC8 --running beats ambiguous env" "$OUT" "looks like claude"
H2="$(mk_tmp)"
OUT="$(env -u CLAUDECODE -u CODEX_HOME PLAYBOOK_HOME="$H2" CLAUDECODE=1 bash "$CONF" check-harness 2>&1)"; RC=$?
assert_eq "AC8 no harness key is silent" "" "$OUT"
assert_rc "AC8 no harness key exits 0" 0

echo "AC8 doctor integration"
D="$(mk_tmp)"
PLAYBOOK_HOME="$D" bash "$CONF" set harness codex --global >/dev/null 2>&1
export PLAYBOOK_REGISTRY="$(mk_tmp)/registry"
OUT="$(env -u CODEX_HOME CLAUDECODE=1 bash "$PB_ROOT/install.sh" doctor --home "$D" --harness claude 2>&1)"
assert_contains "AC8 doctor prints the harness warning" "$OUT" "playbook.conf harness=codex but the running harness looks like claude"
OUT="$(env -u CODEX_HOME -u CLAUDECODE bash "$PB_ROOT/install.sh" doctor --home "$D" --harness claude 2>&1)"
assert_not_contains "AC8 doctor is silent without a hint" "$OUT" "the running harness looks like"
assert_contains "AC8 playbook-setup points at check-harness" "$(cat "$PB_ROOT/skills/playbook-setup/SKILL.md")" "check-harness"
t_summary
