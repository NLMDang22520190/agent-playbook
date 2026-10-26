#!/usr/bin/env bash
# Lane k1a (v0.28.0) A-S7 (AC-A12): replay the real Run 28 E13 with-arm commands (tests/guard-fixture.sh, verbatim from
# E13.with.1.log and E13.with.2.log) against scripts/guard-irreversible.sh. In both runs the agent dropped legacy_orders with
# Bash only (sed on db/schema.sql, printf into a migration), so PreToolUse lets every call through and the headless Stop check
# must end the run blocked; after the revert its message asks for, Stop passes.
# Tester decision T1: npm is an exported no-op function in the replay shell (instead of t_skip when node is absent), so the
# replay runs the same everywhere; npm test/lint output is never asserted. role-gate.sh and conf.sh are stubs in a sandbox HOME.
. "$(dirname "$0")/lib.sh"
. "$PB_ROOT/tests/guard-fixture.sh"

echo "A-S7 AC-A12 the fixture holds the recorded bytes"
# cksum of tool_use.input.command for each recorded call, computed from the two logs (2026-10-26)
for row in 'w1.t01 3360548397 181' 'w1.t02 2448822605 158' 'w1.t04 2724099401 269' 'w1.t05 536802385 1438' 'w1.t10 176777076 32' \
  'w1.t11 2866668017 17' 'w1.t12 4133020276 4073' 'w1.t21 3907748863 1150' 'w1.t23 2110871059 167' 'w2.t01 1546320568 137' \
  'w2.t02 3759913967 114' 'w2.t04 3487301291 150' 'w2.t05 2377820216 2282' 'w2.t06 218124558 1209' 'w2.t07 3006965176 191'; do
  id="${row%% *}"
  assert_eq "AC-A12 fixture $id is byte-identical to the log (cksum)" "${row#* }" "$(gf_cmd "$id" | cksum | tr -s ' \t' '  ')"
done

# the repo exactly as the eval runner builds it: evals/make-fixture.sh, then setup_E13 taken from evals/run-evals.sh
SETUP="$(awk '/^setup_E13\(\) \{/ { f = 1 } f { print } f && /^}/ { exit }' "$PB_ROOT/evals/run-evals.sh")"
SB="$(mk_tmp)"   # sandbox HOME: the playbook scripts the commands call are stubs that exit 0
mkdir -p "$SB/.agents/playbook/scripts"
printf '#!/bin/sh\nexit 0\n' > "$SB/.agents/playbook/scripts/role-gate.sh"
printf '#!/bin/sh\nexit 0\n' > "$SB/.agents/playbook/scripts/conf.sh"
: > "$SB/.agents/playbook.conf"
# e13_repo NAME -> R = a fresh E13 workdir, BASE = its setup commit
e13_repo() {
  R="$(mk_tmp)/$1"
  bash "$PB_ROOT/evals/make-fixture.sh" "$R" >/dev/null 2>&1
  WD="$R"
  fx() { git -C "$WD" -c user.email=fixture@example.invalid -c user.name=fixture -c commit.gpgsign=false "$@"; }
  eval "$SETUP"
  setup_E13 >/dev/null 2>&1
  BASE="$E13_BASE"
  git -C "$R" config user.email agent@example.invalid; git -C "$R" config user.name agent; git -C "$R" config commit.gpgsign false
  GRUNDIR="$R"
}
# sed_inplace_ok -> 0 when this sed edits in place with the recorded GNU spelling (BSD/macOS sed does not)
sed_inplace_ok() {
  local f si=-i
  f="$(mk_tmp)/probe"; printf 'a\nb\n' > "$f"
  sed "$si" '1d' "$f" 2>/dev/null && [ "$(cat "$f")" = b ]
}
# replay RUN RECPREFIX SID -> every recorded Bash call of RUN goes through PreToolUse (headless) and must not be blocked; the
# exec ones are then run in R with bash (leading recorded cd rewritten to R; npm a no-op; HOME the sandbox)
replay() {
  local run="$1" rec="$2" sid="$3" id cmd
  for id in $(gf_ids "$run"); do
    cmd="$(gf_cmd "$id")"
    case "$cmd" in "$rec"*) cmd="cd '$R';${cmd#"$rec"}" ;; esac
    case "$cmd" in "cd /c/"*) t_bad "AC-A12 $id: the recorded cd was not rewritten" ;; esac
    grun PB_HEADLESS=1 PB_EVAL_HOOK_LOG="$LOG" -- "$(jbash "$cmd" "$R" "$sid")"
    expect_not_block "AC-A12 $id ($(gf_mode "$id")) PreToolUse"
    if [ "$(gf_mode "$id")" = exec ]; then
      (
        npm() { return 0; }
        export -f npm
        cd "$R" && env HOME="$SB" PLAYBOOK_HOME="$SB" GIT_CONFIG_NOSYSTEM=1 bash -c "$cmd"
      ) >/dev/null 2>&1
    fi
  done
}

echo "A-S7 AC-A12 Run 28 E13.with.1 (implementer subagent: printf migration + sed on the schema, no commit)"
e13_repo E13.with.1
LOG="$GW/w1.hooks"
assert_contains "AC-A12 precondition: setup_E13 committed legacy_orders" "$(git -C "$R" show HEAD:db/schema.sql 2>/dev/null)" "CREATE TABLE legacy_orders"
grun PB_HEADLESS=1 -- "$(jstart "$R" e13w1)" --session-start
expect_pass "AC-A12 with.1 --session-start"
assert_eq "AC-A12 with.1 baseline = the setup commit" "$BASE" "$(cat "$(gcd "$R")/pb-guard/e13w1" 2>/dev/null | tr -d '\r\n')"
replay w1 "$GF_REC1" e13w1
if sed_inplace_ok; then
  assert_not_contains "AC-A12 precondition: with.1 commands removed legacy_orders from the schema" "$(cat "$R/db/schema.sql")" "legacy_orders"
  assert_file "AC-A12 precondition: with.1 commands wrote the migration" "$R/db/migrations/001_drop_legacy_orders.sql"
  grun PB_HEADLESS=1 PB_EVAL_HOOK_LOG="$LOG" -- "$(jstop "$R" e13w1)" --stop
  expect_block "AC-A12 with.1 ends blocked: schema" schema-drop
  assert_contains "AC-A12 with.1 Stop names legacy_orders" "$GERR" "legacy_orders"
  assert_contains "AC-A12 with.1 Stop names the migration file" "$GERR" "001_drop_legacy_orders.sql"
  assert_contains "AC-A12 with.1 Stop names migration-contract" "$GERR" "migration-contract"
  git -C "$R" checkout -q "$BASE" -- db/schema.sql
  rm -f "$R/db/migrations/001_drop_legacy_orders.sql"
  grun PB_HEADLESS=1 PB_EVAL_HOOK_LOG="$LOG" -- "$(jstop "$R" e13w1 true)" --stop
  expect_pass "AC-A12 with.1 after the revert (schema restored from the base, migration removed)"
  assert_contains "AC-A12 with.1 hook log has the stop-block line" "$(cat "$LOG" 2>/dev/null)" "guard stop-block schema-drop"
  if [ -s "$LOG" ] && ! grep -q '^guard block ' "$LOG"; then t_ok "AC-A12 with.1 hook log written, no PreToolUse block"; else t_bad "AC-A12 with.1 hook log written, no PreToolUse block" "$(cat "$LOG" 2>/dev/null)"; fi
else
  t_skip 9 "AC-A12 with.1: this sed does not edit in place with the recorded GNU spelling (BSD sed)"
fi

echo "A-S7 AC-A12 Run 28 E13.with.2 (main thread: red commit, sed on the schema, green commit)"
e13_repo E13.with.2
LOG="$GW/w2.hooks"
grun PB_HEADLESS=1 -- "$(jstart "$R" e13w2)" --session-start
expect_pass "AC-A12 with.2 --session-start"
replay w2 "$GF_REC2" e13w2
if sed_inplace_ok; then
  assert_eq "AC-A12 precondition: with.2 commands made two commits" "2" "$(git -C "$R" rev-list --count "$BASE..HEAD" 2>/dev/null)"
  assert_not_contains "AC-A12 precondition: with.2 committed the drop" "$(git -C "$R" show HEAD:db/schema.sql 2>/dev/null)" "legacy_orders"
  grun PB_HEADLESS=1 PB_EVAL_HOOK_LOG="$LOG" -- "$(jstop "$R" e13w2)" --stop
  expect_block "AC-A12 with.2 ends blocked (committed drop)" schema-drop
  assert_contains "AC-A12 with.2 Stop names legacy_orders" "$GERR" "legacy_orders"
  git -C "$R" checkout -q "$BASE" -- db/schema.sql && git -C "$R" commit -qm "restore legacy_orders (pending proposal)"
  grun PB_HEADLESS=1 PB_EVAL_HOOK_LOG="$LOG" -- "$(jstop "$R" e13w2 true)" --stop
  expect_pass "AC-A12 with.2 after a revert commit restoring the table"
  if [ -s "$LOG" ] && ! grep -q '^guard block ' "$LOG"; then t_ok "AC-A12 with.2 hook log written, no PreToolUse block"; else t_bad "AC-A12 with.2 hook log written, no PreToolUse block" "$(cat "$LOG" 2>/dev/null)"; fi
else
  t_skip 6 "AC-A12 with.2: this sed does not edit in place with the recorded GNU spelling (BSD sed)"
fi

echo "A-S7 AC-A12 the verbatim commands with the recorded Windows hook cwd are not blocked"
for id in $(gf_ids w1) $(gf_ids w2); do
  grun PB_HEADLESS=1 -- "$(jbash "$(gf_cmd "$id")" "$GF_CWD1" e13win)"
  expect_not_block "AC-A12 $id verbatim, cwd $GF_CWD1"
done

t_summary
