#!/usr/bin/env bash
# Lane k1a (v0.28.0) scripts/guard-irreversible.sh: A-S8 eval switches, hook log, speed, bash 3.2 (AC-A15, AC-A16) and
# A-S10 home through pb_home + the run-checks sections (AC-A18).
. "$(dirname "$0")/lib.sh"
. "$PB_ROOT/tests/guard-fixture.sh"

PUSH="$(jbash 'git push --force origin main')"

echo "A-S8 AC-A15 PB_EVAL_HOOKS: without --eval the guard stands aside"
grun PB_HEADLESS=1 PB_EVAL_HOOKS=1 -- "$PUSH"
expect_pass "AC-A15 PB_EVAL_HOOKS=1, no --eval: a force push is not judged"
grun PB_HEADLESS=1 PB_EVAL_HOOKS=1 -- "$PUSH" --eval
expect_block "AC-A15 PB_EVAL_HOOKS=1 with --eval: judged as usual" git-push-force
grun PB_HEADLESS=1 -- "$PUSH" --eval
expect_block "AC-A15 --eval without PB_EVAL_HOOKS: judged as usual" git-push-force
R="$(mk_tmp)/repo"; mk_schema_repo "$R" >/dev/null; GRUNDIR="$R"
grun PB_HEADLESS=1 PB_EVAL_HOOKS=1 -- "$(jstart "$R" ev1)" --session-start
expect_pass "AC-A15 PB_EVAL_HOOKS=1, --session-start without --eval: no output"
if [ "$RC" = 0 ] && [ ! -e "$(gcd "$R")/pb-guard/ev1" ]; then t_ok "AC-A15 PB_EVAL_HOOKS=1, --session-start without --eval: exit 0, no state file"; else t_bad "AC-A15 PB_EVAL_HOOKS=1, --session-start without --eval: exit 0, no state file" "rc=$RC"; fi
grun PB_HEADLESS=1 PB_EVAL_HOOKS=1 -- "$(jstart "$R" ev2)" --eval --session-start
assert_file "AC-A15 --eval --session-start (eval flag before the mode flag) records the baseline" "$(gcd "$R")/pb-guard/ev2"
printf '%s\n' '-- the shop database (SQLite)' > "$R/db/schema.sql"
grun PB_HEADLESS=1 PB_EVAL_HOOKS=1 -- "$(jstop "$R" ev2)" --stop
expect_pass "AC-A15 PB_EVAL_HOOKS=1, --stop without --eval on a violating tree: no-op"
grun PB_HEADLESS=1 PB_EVAL_HOOKS=1 -- "$(jstop "$R" ev2)" --eval --stop
expect_block "AC-A15 PB_EVAL_HOOKS=1, --eval --stop on a violating tree" schema-drop

echo "A-S8 AC-A15 PB_EVAL_HOOK_LOG: one line per non-PASS decision"
GRUNDIR="$GW"
L="$GW/hook.log"
grun PB_HEADLESS=1 PB_EVAL_HOOK_LOG="$L" -- "$PUSH"
assert_contains "AC-A15 a BLOCK logs guard block <kind>" "$(cat "$L" 2>/dev/null)" "guard block git-push-force"
grun PB_HEADLESS=0 PB_EVAL_HOOK_LOG="$L" -- "$(jbash 'rm -rf /opt/pbguard-data')"
assert_contains "AC-A15 a WARN logs guard warn <kind>" "$(cat "$L" 2>/dev/null)" "guard warn rm-outside"
assert_contains "AC-A15 the log appends (the earlier line stays)" "$(cat "$L" 2>/dev/null)" "guard block git-push-force"
grun PB_HEADLESS=1 PB_EVAL_HOOK_LOG="$L" -- "$(jwrite /pbguard-proj/app/db/migrations/9_drop.sql 'DROP TABLE t;')"
assert_contains "AC-A15 a PENDING logs guard pending <kind>" "$(cat "$L" 2>/dev/null)" "guard pending "
L2="$GW/hook-pass.log"
grun PB_HEADLESS=1 PB_EVAL_HOOK_LOG="$L2" -- "$(jbash 'ls -la')"
expect_pass "AC-A15 a PASS with a hook log set"
if [ "$RC" = 0 ] && [ -z "$(cat "$L2" 2>/dev/null)" ]; then t_ok "AC-A15 a PASS logs nothing"; else t_bad "AC-A15 a PASS logs nothing" "rc=$RC log=[$(cat "$L2" 2>/dev/null)]"; fi
grun PB_HEADLESS=1 PB_EVAL_HOOK_LOG="$GW/hook-off.log" PB_EVAL_HOOKS=1 -- "$PUSH"
if [ "$RC" = 0 ] && [ ! -e "$GW/hook-off.log" ]; then t_ok "AC-A15 PB_EVAL_HOOKS without --eval: exit 0, logs nothing"; else t_bad "AC-A15 PB_EVAL_HOOKS without --eval: exit 0, logs nothing" "rc=$RC"; fi

echo "A-S8 AC-A16 speed and process count"
if [ "$(uname -s)" = Linux ]; then
  NOM="$(jbash 'ls -la src && npm test')"
  t0="$(date +%s)"
  i=0; bad=0; while [ "$i" -lt 50 ]; do grun PB_HEADLESS=1 -- "$NOM"; [ "$RC" = 0 ] || bad=$((bad + 1)); i=$((i + 1)); done
  t1="$(date +%s)"
  expect_pass "AC-A16 the no-match command is PASS"
  if [ "$bad" = 0 ] && [ $((t1 - t0)) -lt 10 ]; then t_ok "AC-A16 50 no-match PreToolUse runs take < 10 s ($((t1 - t0)) s)"; else t_bad "AC-A16 50 no-match PreToolUse runs take < 10 s" "$((t1 - t0)) s"; fi
  R="$(mk_tmp)/repo"; mk_schema_repo "$R" >/dev/null; GRUNDIR="$R"
  grun PB_HEADLESS=1 -- "$(jstart "$R" sp1)" --session-start
  t0="$(date +%s)"
  i=0; bad=0; while [ "$i" -lt 5 ]; do grun PB_HEADLESS=1 -- "$(jstop "$R" sp1)" --stop; [ "$RC" = 0 ] || bad=$((bad + 1)); i=$((i + 1)); done
  t1="$(date +%s)"
  expect_pass "AC-A16 --stop on a clean tree is PASS"
  if [ "$bad" = 0 ] && [ $((t1 - t0)) -lt 10 ]; then t_ok "AC-A16 --stop on a clean tree < 2 s each (5 runs: $((t1 - t0)) s)"; else t_bad "AC-A16 --stop on a clean tree < 2 s each" "5 runs took $((t1 - t0)) s"; fi
  GRUNDIR="$GW"
else
  t_skip 4 "AC-A16 timing is pinned on Linux CI only"
fi
# process count: every external tool the guard could start is a shim on PATH that logs its name, then runs the real one
SH="$(mk_tmp)"; SL="$SH/calls.log"; : > "$SL"
for t in git awk sed grep tr cat head tail cut sort uniq wc dirname basename date mktemp cygpath env expr readlink realpath printf ls id uname; do
  p="$(command -v "$t" 2>/dev/null)" || continue
  case "$p" in /*) ;; *) continue ;; esac
  printf '#!/bin/sh\necho %s >> "%s"\nexec "%s" "$@"\n' "$t" "$SL" "$p" > "$SH/$t"
  chmod +x "$SH/$t" 2>/dev/null
done
if [ -x "$SH/git" ] && [ -x "$SH/awk" ]; then
  GRUNDIR="$(mk_tmp)"; mk_repo "$GRUNDIR" >/dev/null
  : > "$SL"
  grun PB_HEADLESS=1 PATH="$SH:$PATH" -- "$(jbash 'ls -la src && npm test' "$GRUNDIR")"
  expect_pass "AC-A16 shimmed PATH: the no-match command is PASS"
  N="$(grep -c . "$SL" | tr -d ' ')"
  if [ "$RC" = 0 ] && [ "$N" -le 2 ]; then t_ok "AC-A16 the no-match path starts at most 2 external processes ($N)"; else t_bad "AC-A16 the no-match path starts at most 2 external processes" "$N: $(tr '\n' ' ' < "$SL")"; fi
  assert_eq "AC-A16 the no-match path exits 0 and never runs git" "0 0" "$RC $(grep -c '^git$' "$SL" | tr -d ' ')"
  : > "$SL"
  grun PB_HEADLESS=1 PATH="$SH:$PATH" -- "$(jbash 'git log --oneline -3' "$GRUNDIR")"
  assert_eq "AC-A16 a git command that is not a discard candidate exits 0 and never runs git" "0 0" "$RC $(grep -c '^git$' "$SL" | tr -d ' ')"
  GRUNDIR="$GW"
else
  t_skip 4 "AC-A16 cannot build PATH shims here (chmod probe failed)"
fi

echo "A-S8 AC-A16 bash 3.2"
B32="$HOME/.local/bin/bash3.2"; [ -x "$B32" ] || B32="$(command -v bash3.2 2>/dev/null)"
if [ -n "$B32" ] && [ -x "$B32" ]; then
  GBASH="$B32"
  grun PB_HEADLESS=1 -- "$PUSH"; expect_block "AC-A16 bash 3.2: force push" git-push-force
  grun PB_HEADLESS=1 -- "$(jbash 'd=$(mktemp -d); rm -rf "$d"')"; expect_pass "AC-A16 bash 3.2: rm of a mktemp dir"
  grun PB_HEADLESS=1 -- "$(jbash "sqlite3 app.db <<'SQL'
DROP TABLE users;
SQL")"; expect_block "AC-A16 bash 3.2: sql here-doc" sql
  R="$(mk_tmp)/repo"; mk_schema_repo "$R" >/dev/null; GRUNDIR="$R"
  grun PB_HEADLESS=1 -- "$(jstart "$R" b32)" --session-start
  assert_file "AC-A16 bash 3.2: --session-start records the baseline" "$(gcd "$R")/pb-guard/b32"
  printf '%s\n' '-- the shop database (SQLite)' > "$R/db/schema.sql"
  grun PB_HEADLESS=1 -- "$(jstop "$R" b32)" --stop; expect_block "AC-A16 bash 3.2: --stop" schema-drop
  GBASH="${GUARD_BASH:-$BASH}"; GRUNDIR="$GW"
else
  t_skip 5 "AC-A16 bash3.2 not installed (tools/get-bash32.sh); run the suites with it where it is"
fi

echo "A-S10 AC-A18 home only through pb_home; run-checks sections"
GS="$(cat "$G" 2>/dev/null)"
assert_contains "AC-A18 the guard uses pb_home" "$GS" "pb_home"
SRC="$(grep -nE '^[[:space:]]*(\.|source)[[:space:]].*lib\.sh' "$G" 2>/dev/null)"
if [ -n "$SRC" ]; then t_ok "AC-A18 the guard sources scripts/lib.sh"; else t_bad "AC-A18 the guard sources scripts/lib.sh" "no '. .../lib.sh' line in $G"; fi
BYP="$(grep -nE '\$HOME|\$\{HOME|~/|USERPROFILE' "$G" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#')"
if [ -f "$G" ] && [ -z "$BYP" ]; then t_ok "AC-A18 no HOME, ~/ or USERPROFILE outside a comment in the guard"; else t_bad "AC-A18 no HOME, ~/ or USERPROFILE outside a comment in the guard" "${BYP:-guard missing}"; fi
# tilde resolves against pb_home (PLAYBOOK_HOME), not the shell HOME (D29)
grun PB_HEADLESS=1 HOME=/pbguard-ha PLAYBOOK_HOME=/pbguard-hb -- "$(jbash 'rm -rf ~/proj/build' /pbguard-hb/proj)"
expect_pass "AC-A18 ~ resolves through pb_home (PLAYBOOK_HOME/proj/build is inside)"
grun PB_HEADLESS=1 HOME=/pbguard-ha PLAYBOOK_HOME=/pbguard-hb -- "$(jbash 'rm -rf ~/proj/build' /pbguard-ha/proj)"
expect_block "AC-A18 ~ does not resolve through the shell HOME when PLAYBOOK_HOME differs" rm-outside
# the run-checks sections over the real tree: they scan scripts/*.sh (the guard) and tests/*.sh (these suites and the fixture with
# the recorded GNU sed commands); they pass before the guard exists, so they pin that neither the fixture nor the guard breaks them
for sec in dupmax sed gnu soh; do
  run bash "$PB_ROOT/evals/run-checks.sh" --only "$sec"
  assert_rc "AC-A18 evals/run-checks.sh --only $sec passes on the tree" 0
done
if command -v shellcheck >/dev/null 2>&1; then
  run shellcheck -S warning "$G"
  assert_rc "AC-A18 shellcheck -S warning on the guard" 0
else
  t_skip 1 "AC-A18 shellcheck not installed"
fi

t_summary
