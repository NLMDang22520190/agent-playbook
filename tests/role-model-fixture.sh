#!/usr/bin/env bash
# Shared setup of tests/test-role-model.sh and tests/test-role-model-b.sh (split in v0.24.19 so that neither part is the floor of a CI shard): the RM path, the
# isolated PLAYBOOK_HOME (H) and project dir (P), the conf paths G and L, reset and role.
# Source it after lib.sh. It is not a suite: run-all.sh only starts tests/test-*.sh.
RM="$PB_ROOT/scripts/role-model.sh"

# Fresh, isolated world per scenario: own PLAYBOOK_HOME and own project dir (not inside any repo).
H="$(mk_tmp)"; P="$(mk_tmp)"
export PLAYBOOK_HOME="$H"
unset PLAYBOOK_HARNESS
mkdir -p "$H/.agents" "$P/.agents"
G="$H/.agents/playbook.conf"; L="$P/.agents/playbook.conf"

reset() { rm -f "$G" "$L"; unset PLAYBOOK_HARNESS; }
role() { run_in "$P" bash "$RM" "$@"; }   # sets OUT, RC
