#!/usr/bin/env bash
# Lane k1a (v0.28.0) scripts/guard-irreversible.sh --session-start and --stop:
# A-S5 session baseline, Stop schema/migration diff, rename is not a drop (AC-A10, AC-A11, AC-A13), A-S9 Stop give-up counter (AC-A17).
# Review fix round R6, R7: the guard's state dir is outside the project; a commented-out CREATE TABLE counts as removed.
# Hook input: the documented SessionStart and Stop JSON (https://code.claude.com/docs/en/hooks, fetched 2026-10-26).
. "$(dirname "$0")/lib.sh"
. "$PB_ROOT/tests/guard-fixture.sh"

S_HEAD='-- the shop database (SQLite)'
S_ORD='CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER NOT NULL, created_at TEXT NOT NULL, total_cents INTEGER NOT NULL);'
S_LEGC='-- orders of the old shop, read-only since the move to the orders table'
S_LEG='CREATE TABLE legacy_orders (id INTEGER PRIMARY KEY, customer_id INTEGER, created_at TEXT, total_cents INTEGER);'
SN=0
# srepo -> a new schema repo R (orders + legacy_orders committed, BASE = that commit), session SID started there
srepo() {
  R="$(mk_tmp)/repo"; mk_schema_repo "$R" >/dev/null; GRUNDIR="$R"
  BASE="$(git -C "$R" rev-parse HEAD)"; B7="$(printf '%s' "$BASE" | cut -c1-7)"
  SN=$((SN + 1)); SID="sess$SN"
  grun PB_HEADLESS=1 -- "$(jstart "$R" "$SID")" --session-start
}
# schema LINE... -> rewrites db/schema.sql in R
schema() { printf '%s\n' "$@" > "$R/db/schema.sql"; }
# gs [ACTIVE] [ENV...] -> --stop in R for SID, headless unless ENV says otherwise
gs() { local a="${1:-false}"; [ "$#" -gt 0 ] && shift; grun PB_HEADLESS=1 "$@" -- "$(jstop "$R" "$SID" "$a")" --stop; }

echo "A-S5 AC-A10 --session-start records the baseline"
srepo
expect_pass "AC-A10 --session-start prints nothing and exits 0"
STATE="$(gcd "$R")/pb-guard"
assert_eq "AC-A10 the baseline file holds HEAD" "$BASE" "$(cat "$STATE/$SID" 2>/dev/null | tr -d '\r\n')"
if [ -f "$STATE/$SID" ] && [ -z "$(git -C "$R" status --porcelain)" ]; then t_ok "AC-A10 the state file exists and is not visible to git status"; else t_bad "AC-A10 the state file exists and is not visible to git status" "$(git -C "$R" status --porcelain)"; fi
printf 'x\n' > "$R/new.txt"; fxg "$R" add new.txt; fxg "$R" commit -qm later
grun PB_HEADLESS=1 -- "$(jstart "$R" "$SID" resume)" --session-start
assert_eq "AC-A10 resume keeps the first baseline" "$BASE" "$(cat "$STATE/$SID" 2>/dev/null | tr -d '\r\n')"
grun PB_HEADLESS=1 -- "$(jstart "$R" "$SID" compact)" --session-start
assert_eq "AC-A10 compact keeps the first baseline" "$BASE" "$(cat "$STATE/$SID" 2>/dev/null | tr -d '\r\n')"
grun PB_HEADLESS=1 -- "$(jstart "$R" other)" --session-start
assert_eq "AC-A10 another session id gets the current HEAD" "$(git -C "$R" rev-parse HEAD)" "$(cat "$STATE/other" 2>/dev/null | tr -d '\r\n')"
E="$(mk_tmp)/empty"; mkdir -p "$E"; git -C "$E" init -q; GRUNDIR="$E"
grun PB_HEADLESS=1 -- "$(jstart "$E" s0)" --session-start
assert_eq "AC-A10 before the first commit the baseline is none" "none" "$(cat "$(gcd "$E")/pb-guard/s0" 2>/dev/null | tr -d '\r\n')"
N="$(mk_tmp)/plain"; mkdir -p "$N"; GRUNDIR="$N"
grun PB_HEADLESS=1 -- "$(jstart "$N" s0)" --session-start
expect_pass "AC-A10 outside git: exit 0, no output"
if [ "$RC" = 0 ] && [ -z "$(ls -A "$N")" ]; then t_ok "AC-A10 outside git: exit 0, nothing written"; else t_bad "AC-A10 outside git: exit 0, nothing written" "rc=$RC $(ls -A "$N")"; fi
R="$(mk_tmp)/repo"; mk_schema_repo "$R" >/dev/null; GRUNDIR="$R"
grun PB_HEADLESS=1 -- "$(jstart "$R" -)" --session-start
expect_pass "AC-A10 without session_id: exit 0, no output"
if [ "$RC" = 0 ] && [ -z "$(ls -A "$(gcd "$R")/pb-guard" 2>/dev/null)" ]; then t_ok "AC-A10 without session_id: exit 0, no state file"; else t_bad "AC-A10 without session_id: exit 0, no state file" "rc=$RC"; fi
fxg "$R" worktree add -q -b side "$R.wt" 2>/dev/null
if [ -d "$R.wt" ]; then
  GRUNDIR="$R.wt"
  grun PB_HEADLESS=1 -- "$(jstart "$R.wt" swt)" --session-start
  assert_eq "AC-A10 a linked worktree keeps its baseline in the common dir" "$(git -C "$R.wt" rev-parse HEAD)" "$(cat "$(gcd "$R")/pb-guard/swt" 2>/dev/null | tr -d '\r\n')"
  fxg "$R" worktree remove --force "$R.wt" 2>/dev/null
else
  t_skip 1 "AC-A10 git worktree add failed here"
fi

echo "A-S5 AC-A11 --stop: PASS cases"
srepo
gs; expect_pass "AC-A11 clean tree after the session start"
N="$(mk_tmp)/plain"; mkdir -p "$N"; GRUNDIR="$N"
grun PB_HEADLESS=1 -- "$(jstop "$N" sx)" --stop
expect_pass "AC-A11 not a git tree"
srepo; schema "$S_HEAD" "$S_ORD" "$S_LEGC" "$S_LEG" 'CREATE TABLE audit (id INTEGER);'
gs; expect_pass "AC-A11 an added table"
srepo; schema "$S_HEAD" 'CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER NOT NULL, created_at TEXT NOT NULL, total_cents INTEGER NOT NULL, note TEXT);' "$S_LEGC" "$S_LEG"
gs; expect_pass "AC-A11 an added column"
srepo; schema "$S_HEAD" 'CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER NOT NULL, created_at TEXT NOT NULL, amount_cents INTEGER NOT NULL);' "$S_LEGC" "$S_LEG"
gs; expect_pass "AC-A11 a renamed column (the column count did not drop)"
srepo; schema "$S_HEAD" "$S_ORD"; printf '%s\n' "$S_LEGC" "$S_LEG" > "$R/db/legacy.sql"
gs; expect_pass "AC-A11 a table moved to another schema file"
srepo; printf 'DELETE FROM tmp; DROP TABLE tmp;\n' > "$R/db/scratch.sql"
gs; expect_pass "AC-A11 a new non-migration .sql file with a DROP (no table it created at the baseline)"
srepo; mkdir -p "$R/.agents/proposals/migrations"; printf 'DROP TABLE legacy_orders;\n' > "$R/.agents/proposals/migrations/001_drop_legacy_orders.sql"
gs; expect_pass "AC-A11 a contract migration under .agents/ is ignored (the advised place for a pending proposal)"
# test fixtures are not schema files; a migration that held a DROP at the baseline and did not change is old
R="$(mk_tmp)/repo"; mk_schema_repo "$R" >/dev/null; GRUNDIR="$R"
mkdir -p "$R/tests/fixtures" "$R/spec" "$R/db/migrations"
printf '%s\n' 'CREATE TABLE fx_users (id INTEGER);' 'CREATE TABLE fx_carts (id INTEGER);' > "$R/tests/fixtures/schema.sql"
printf '%s\n' 'CREATE TABLE spec_a (id INTEGER);' > "$R/spec/db.sql"
printf 'DROP TABLE old_cache;\n' > "$R/db/migrations/001_drop_cache.sql"
fxg "$R" add -A; fxg "$R" commit -qm "fixtures and an old migration"
SID=fx1; grun PB_HEADLESS=1 -- "$(jstart "$R" fx1)" --session-start
printf '%s\n' 'CREATE TABLE fx_users (id INTEGER);' > "$R/tests/fixtures/schema.sql"
: > "$R/spec/db.sql"
gs; expect_pass "AC-A11 tables removed from tests/fixtures and spec .sql files; an unchanged old DROP migration"
printf 'DROP TABLE orders;\n' >> "$R/db/migrations/001_drop_cache.sql"
gs; expect_block "AC-A11 a line with DROP added to an old migration" migration-contract

echo "A-S5 AC-A11 --stop: BLOCK cases"
srepo; schema "$S_HEAD" "$S_ORD"
gs
expect_block "AC-A11 uncommitted removal of legacy_orders" schema-drop
LOW="$(printf '%s' "$GERR" | tr 'A-Z' 'a-z')"
assert_contains "AC-A11 the message names the file" "$GERR" "db/schema.sql"
assert_contains "AC-A11 the message names the table" "$GERR" "legacy_orders"
assert_contains "AC-A11 the message says how to restore from the baseline" "$GERR" "git checkout $B7"
assert_contains "AC-A11 the message says headless" "$LOW" "headless run"
assert_contains "AC-A11 the message says revert" "$LOW" "revert"
assert_contains "AC-A11 the message says never rewrite history" "$LOW" "never by rewriting history"
assert_contains "AC-A11 the message asks for a pending proposal in the final reply" "$LOW" "pending proposal"
git -C "$R" checkout -q "$BASE" -- db/schema.sql
gs true; expect_pass "AC-A11 after git checkout <base> -- db/schema.sql"
srepo; schema "$S_HEAD" "$S_ORD"; git -C "$R" add db/schema.sql
gs; expect_block "AC-A11 a staged removal" schema-drop
srepo; schema "$S_HEAD" "$S_ORD"; fxg "$R" commit -qam "drop legacy_orders"
gs; expect_block "AC-A11 a removal committed after the baseline" schema-drop
fxg "$R" revert --no-edit HEAD >/dev/null
gs true; expect_pass "AC-A11 after a revert commit"
srepo; mkdir -p "$R/db/migrations"; printf 'DROP TABLE legacy_orders;\n' > "$R/db/migrations/001_drop_legacy_orders.sql"
gs
expect_block "AC-A11 a new untracked migration with DROP TABLE" migration-contract
assert_contains "AC-A11 the migration message names the file" "$GERR" "db/migrations/001_drop_legacy_orders.sql"
srepo; mkdir -p "$R/db/migrations"; printf 'ALTER TABLE orders DROP COLUMN total_cents;\n' > "$R/db/migrations/002.sql"
fxg "$R" add -A; fxg "$R" commit -qm mig
gs; expect_block "AC-A11 a committed migration with ALTER TABLE ... DROP" migration-contract
srepo; schema "$S_HEAD" 'CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER NOT NULL, created_at TEXT NOT NULL);' "$S_LEGC" "$S_LEG"
gs
expect_block "AC-A11 a dropped column" schema-column-drop
assert_contains "AC-A11 the column message names the column" "$GERR" "total_cents"
srepo; git -C "$R" rm -q db/schema.sql
gs
expect_block "AC-A11 the schema file deleted" schema-drop
assert_contains "AC-A11 a deleted schema file: orders is named too" "$GERR" "orders"
srepo; schema "$S_HEAD" "$S_ORD"
grun CI=true -- "$(jstop "$R" "$SID")" --stop
expect_block "AC-A11 CI=true without PB_HEADLESS is headless" schema-drop
gs true; expect_block "AC-A11 stop_hook_active true and still violating: blocks again" schema-drop

echo "A-S5 AC-A11 --stop interactive: systemMessage only"
for envs in PB_HEADLESS=0 none; do
  srepo; schema "$S_HEAD" "$S_ORD"
  if [ "$envs" = none ]; then grun -- "$(jstop "$R" "$SID")" --stop; else grun "$envs" CI=true -- "$(jstop "$R" "$SID")" --stop; fi
  if [ "$RC" = 0 ] && has "$GOUTN" '"systemMessage":"agent-playbook guard: ' && has "$GOUT" legacy_orders && ! has "$GOUT" '"decision"' && ! has "$GOUT" hookSpecificOutput; then
    t_ok "AC-A11 interactive ($envs): exit 0, systemMessage naming legacy_orders, no decision"
  else t_bad "AC-A11 interactive ($envs): exit 0, systemMessage naming legacy_orders, no decision" "rc=$RC $OUT"; fi
done

echo "A-S5 AC-A11 baseline fallbacks without a session file"
SRC="$(mk_tmp)/src"; mk_schema_repo "$SRC" >/dev/null
R="$(mk_tmp)/clone"; git clone -q "$SRC" "$R"; GRUNDIR="$R"
schema "$S_HEAD" "$S_ORD"; fxg "$R" commit -qam "drop legacy_orders"
SID=never-started; gs
expect_block "AC-A11 no session file: merge-base with @{upstream} sees the committed drop" schema-drop
R="$(mk_tmp)/repo"; mk_schema_repo "$R" >/dev/null; GRUNDIR="$R"
schema "$S_HEAD" "$S_ORD"; fxg "$R" commit -qam "drop legacy_orders"
SID=never-started2; gs
expect_pass "AC-A11 no session file, no upstream: HEAD is the baseline (work tree only)"
schema "$S_HEAD"
gs; expect_block "AC-A11 no session file, no upstream: an uncommitted drop vs HEAD" schema-drop

echo "A-S5 AC-A13 a rename is not a drop"
srepo; schema "$S_HEAD" "$S_ORD" "$S_LEGC" 'CREATE TABLE archived_orders (id INTEGER PRIMARY KEY, customer_id INTEGER, created_at TEXT, total_cents INTEGER);'
gs; expect_pass "AC-A13 renamed table with equal columns"
srepo; schema "$S_HEAD" "$S_ORD" 'create table Archived_Orders (ID  INTEGER PRIMARY KEY, Customer_Id integer, created_at   text, total_cents INTEGER);'
gs; expect_pass "AC-A13 renamed table, columns equal after case and whitespace normalisation"
srepo; schema "$S_HEAD" "$S_ORD" 'CREATE TABLE old_orders (id INTEGER PRIMARY KEY, customer_ref TEXT);'
mkdir -p "$R/db/migrations"; printf 'ALTER TABLE legacy_orders RENAME TO old_orders;\n' > "$R/db/migrations/003_rename.sql"
gs; expect_pass "AC-A13 other columns, but a session migration says RENAME TO"
srepo; schema "$S_HEAD" "$S_ORD" 'CREATE TABLE old_orders (id INTEGER PRIMARY KEY, customer_ref TEXT);'
mkdir -p "$R/db/migrations"; printf 'RENAME TABLE legacy_orders TO old_orders;\n' > "$R/db/migrations/003_rename.sql"
gs; expect_pass "AC-A13 other columns, but a session migration says RENAME TABLE ... TO"
srepo; schema "$S_HEAD" "$S_ORD" 'CREATE TABLE old_orders (id INTEGER PRIMARY KEY, customer_ref TEXT);'
gs; expect_block "AC-A13 other columns and no rename migration: a drop" schema-drop
for form in 'CREATE TABLE "legacy_orders" (id INTEGER PRIMARY KEY, customer_id INTEGER, created_at TEXT, total_cents INTEGER);' \
  'CREATE TABLE `legacy_orders` (id INTEGER PRIMARY KEY, customer_id INTEGER, created_at TEXT, total_cents INTEGER);' \
  'CREATE TABLE [Legacy_Orders] (id INTEGER PRIMARY KEY, customer_id INTEGER, created_at TEXT, total_cents INTEGER);' \
  'CREATE TABLE IF NOT EXISTS LEGACY_ORDERS (id INTEGER PRIMARY KEY, customer_id INTEGER, created_at TEXT, total_cents INTEGER);'; do
  srepo; schema "$S_HEAD" "$S_ORD" "$S_LEGC" "$form"
  gs; expect_pass "AC-A13 the same table written as [$form]"
done
srepo; schema "$S_HEAD" "$S_ORD" 'CREATE TABLE archive.legacy_orders (id INTEGER PRIMARY KEY, note TEXT);'
gs; expect_block "AC-A13 schema.table is kept whole: archive.legacy_orders is not legacy_orders" schema-drop

echo "A-S9 AC-A17 the guard gives up after 3 Stop blocks in one session"
srepo; schema "$S_HEAD" "$S_ORD"
LOG="$GW/hooks-$SID.log"
gs false PB_EVAL_HOOK_LOG="$LOG"; expect_block "AC-A17 Stop 1 blocks" schema-drop
gs true PB_EVAL_HOOK_LOG="$LOG"; expect_block "AC-A17 Stop 2 blocks" schema-drop
gs true PB_EVAL_HOOK_LOG="$LOG"; expect_block "AC-A17 Stop 3 blocks" schema-drop
assert_file "AC-A17 the per-session counter file exists" "$(gcd "$R")/pb-guard/$SID.stops"
gs true PB_EVAL_HOOK_LOG="$LOG"
assert_rc "AC-A17 Stop 4 exits 0 (gives up)" 0
assert_contains "AC-A17 Stop 4 systemMessage" "$GOUTN" '"systemMessage":"agent-playbook guard: gave up after 3 Stop blocks; unresolved irreversible changes: '
assert_contains "AC-A17 Stop 4 systemMessage ends with the report request" "$GOUT" 'Report them to the user.'
assert_contains "AC-A17 Stop 4 lists the unresolved change" "$GOUT" "legacy_orders"
assert_contains "AC-A17 Stop 4 prints the same text on stderr" "$GERR" "gave up after 3 Stop blocks"
assert_eq "AC-A17 the hook log has 3 stop-block lines" "3" "$(grep -c '^guard stop-block schema-drop$' "$LOG" 2>/dev/null)"
assert_contains "AC-A17 the hook log has the give-up line" "$(cat "$LOG" 2>/dev/null)" "guard stop-giveup schema-drop"
SID="$SID-new"
gs; expect_block "AC-A17 a new session id starts at 0" schema-drop
srepo; schema "$S_HEAD" "$S_ORD"
for i in 1 2 3; do grun PB_HEADLESS=1 -- "$(jstop "$R" -)" --stop; expect_block "AC-A17 no session_id: Stop $i blocks" schema-drop; done
assert_file "AC-A17 no session_id: the count lives in nosession.stops" "$(gcd "$R")/pb-guard/nosession.stops"
grun PB_HEADLESS=1 -- "$(jstop "$R" -)" --stop
assert_rc "AC-A17 no session_id: Stop 4 gives up" 0
assert_contains "AC-A17 no session_id: Stop 4 says it gave up" "$GOUT" "gave up after 3 Stop blocks"

# ---- v0.28 hook review fix round (review /home/dev/v026/28-hooks-review.md, orchestrator decisions R6, R7) ----
echo "R6 (review F6) the guard's own state dir counts as outside the project (AC-A6, AC-A10)"
srepo
for c in 'rm -rf .git/pb-guard' 'rm -rf ./.git/pb-guard/' 'rm -rf .git/pb-guard/*' "rm -rf $R/.git/pb-guard" \
  'cd .git && rm -rf pb-guard' 'rm -rf .git/./pb-guard' 'rm -rf .git'; do
  grun PB_HEADLESS=1 -- "$(jbash "$c" "$R")"
  expect_block "R6 [$c] in a repo with a session baseline" rm-outside
done
assert_file "R6 the baseline file is still there (nothing ran)" "$(gcd "$R")/pb-guard/$SID"
for c in 'rm -rf build' 'rm -rf .agents/handoff' 'rm -rf db/pb-guard'; do
  grun PB_HEADLESS=1 -- "$(jbash "$c" "$R")"
  expect_pass "R6 [$c] inside the project is still allowed"
done
# characterization (spec AC-A11 fallback order: session file, merge-base with @{upstream}, HEAD): with the state dir gone
# after SessionStart, a committed drop is still caught through the upstream merge-base
SRC="$(mk_tmp)/src"; mk_schema_repo "$SRC" >/dev/null
R="$(mk_tmp)/clone"; git clone -q "$SRC" "$R"; GRUNDIR="$R"; SID=r6-wiped
grun PB_HEADLESS=1 -- "$(jstart "$R" "$SID")" --session-start
schema "$S_HEAD" "$S_ORD"; fxg "$R" commit -qam "drop legacy_orders"
rm -rf "$(gcd "$R")/pb-guard"
gs; expect_block "R6 state dir removed after SessionStart: the upstream merge-base still sees the committed drop" schema-drop

echo "R7 (review F7) a CREATE TABLE inside a comment counts as removed (AC-A11)"
srepo; schema "$S_HEAD" "$S_ORD" "$S_LEGC" "/* $S_LEG */"
gs; expect_block "R7 CREATE TABLE legacy_orders inside /* */ on one line" schema-drop
assert_contains "R7 the message names the commented-out table" "$GERR" "legacy_orders"
srepo; schema "$S_HEAD" "$S_ORD" "$S_LEGC" '/*' "$S_LEG" '*/'
gs; expect_block "R7 CREATE TABLE legacy_orders inside a multi-line /* */" schema-drop
srepo; schema "$S_HEAD" "$S_ORD" "$S_LEGC" '/* dropped:' "$S_LEG" 'end */'
gs; expect_block "R7 a multi-line /* */ with text on the open and close lines" schema-drop
srepo; schema "$S_HEAD" "$S_ORD" "$S_LEGC" "-- $S_LEG"
gs; expect_block "R7 CREATE TABLE legacy_orders after -- (characterization)" schema-drop
srepo; schema "$S_HEAD" "$S_ORD" "/* $S_LEGC */" "$S_LEG"
gs; expect_pass "R7 a closed /* */ comment before the table keeps it"
srepo; schema "$S_HEAD" "$S_ORD" "$S_LEGC" "/* old shop */ $S_LEG"
gs; expect_pass "R7 a closed /* */ comment before CREATE on the same line keeps it"
srepo; schema "$S_HEAD" "$S_ORD" '/*' 'notes' '*/' "$S_LEG"
gs; expect_pass "R7 a closed multi-line comment above the table keeps it"

# ---- v0.28 fix round 2 (re-review /home/dev/v026/28-rereview.md N3) ----
echo "F2-3 (re-review N3) a glob that can match .git or the state dir counts as the state dir (AC-A6, AC-A10)"
srepo
for c in 'rm -rf .git/pb-*' 'rm -rf .git/pb*' 'rm -rf .git/pb-guar?' 'rm -rf .git/*' 'rm -rf .gi*' 'rm -rf .g?t' 'rm -rf ./.gi*' \
  'rm -rf .[g]it' 'rm -rf .[!.]*' "rm -rf $R/.gi*" 'cd .git && rm -rf pb-*'; do
  grun PB_HEADLESS=1 -- "$(jbash "$c" "$R")"
  expect_block "F2-3 N3 [$c] in a repo with a session baseline" rm-outside
done
assert_file "F2-3 N3 the baseline file is still there (nothing ran)" "$(gcd "$R")/pb-guard/$SID"
for c in 'rm -rf build*' 'rm -rf .agents/*' 'rm -rf db/pb-*' 'rm -rf .gitk*' 'rm -rf .gitignore'; do
  grun PB_HEADLESS=1 -- "$(jbash "$c" "$R")"
  expect_pass "F2-3 N3 [$c] cannot match .git: still allowed"
done

t_summary
