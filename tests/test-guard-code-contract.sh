#!/usr/bin/env bash
# Fix round R2 (spec .agents/handoff/01-spec.md "## Revision 5", R2-1 and R2-2; decision D11): the guard's code-contract check.
# The real gate failed because a DROP TABLE legacy_orders in src/orders.js (a code file) got no warning at the Write and no Stop finding.
# R2-1 pre_write: a Write/Edit of any file outside .agents/ and the test dirs (/test/, /tests/, /spec/, /fixture/, /fixtures/), that is not
#      *.sql or *migrat*, whose written text holds a contract statement logs `guard pending code-contract` and warns with the file named.
# R2-2 stop_mode: added lines of changed tracked files and every line of untracked files (same exemptions, plus node_modules/, *migrat*, schema
#      *.sql kept as today) give the finding `code-contract`; headless blocks (exit 2, restore hint for tracked, "remove the new file or move it
#      under .agents/" for untracked), interactive warns; a drop line already at the baseline is not a finding; binary and > 1 MB files skipped.
# Hook input shapes as in tests/guard-fixture.sh (documented Claude Code hook JSON).
. "$(dirname "$0")/lib.sh"
. "$PB_ROOT/tests/guard-fixture.sh"

P=/pbguard-proj/app
# pw FILE TEXT [ENV...] -> headless PreToolUse Write with a hook log in $HL
HL="$GW/cc-hook.log"
pw() { local f="$1" t="$2"; shift 2; : > "$HL"; GRUNDIR="$GW"; grun PB_HEADLESS=1 PB_EVAL_HOOK_LOG="$HL" "$@" -- "$(jwrite "$f" "$t" "$P")"; }
pe() { local f="$1" o="$2" n="$3"; shift 3; : > "$HL"; GRUNDIR="$GW"; grun PB_HEADLESS=1 PB_EVAL_HOOK_LOG="$HL" "$@" -- "$(jedit "$f" "$o" "$n" "$P")"; }
hl() { cat "$HL" 2>/dev/null; }
# warn_cc NAME FILE -> a code-contract WARN: exit 0, PreToolUse JSON naming FILE and the contract statement, nothing on stderr, hook log line
warn_cc() {
  local low; low="$(printf '%s' "$GOUT" | tr 'A-Z' 'a-z')"
  expect_warn "$1"
  assert_contains "$1: the warning names the file" "$GOUT" "$2"
  assert_contains "$1: the warning says contract statement" "$low" "contract statement"
  assert_eq "$1: stderr is empty" "" "$GERR"
  assert_contains "$1: the hook log says pending code-contract" "$(hl)" "guard pending code-contract"
}
# quiet NAME -> PASS and nothing in the hook log
quiet() {
  expect_pass "$1"
  if [ -z "$(hl)" ]; then t_ok "$1: nothing in the hook log"; else t_bad "$1: nothing in the hook log" "log=[$(hl)]"; fi
}

echo "R2-1 pre_write: a contract statement in a code file warns (code-contract)"
pw "$P/src/orders.js" 'db.exec("DROP TABLE legacy_orders");'
warn_cc "R2-1 Write src/orders.js with DROP TABLE" "src/orders.js"
GRUNDIR="$GW"; grun PB_HEADLESS=0 PB_EVAL_HOOK_LOG="$HL" -- "$(jwrite "$P/src/orders.js" 'db.exec("DROP TABLE legacy_orders");' "$P")"
expect_warn "R2-1 interactive Write src/orders.js with DROP TABLE"
pw "$P/scripts/cleanup.js" 'await db.run("truncate orders");'
warn_cc "R2-1 Write scripts/cleanup.js with lower-case truncate" "scripts/cleanup.js"
pw "$P/lib/db.py" 'cur.execute("ALTER TABLE users DROP COLUMN age")'
warn_cc "R2-1 Write lib/db.py with ALTER TABLE ... DROP" "lib/db.py"
pe "$P/src/orders.js" 'cleanup()' 'db.exec("DROP TABLE legacy_orders");'
warn_cc "R2-1 Edit src/orders.js whose new_string drops a table" "src/orders.js"
pw 'C:\proj\src\orders.js' 'db.exec("drop database shop")'
warn_cc "R2-1 Windows backslash path to a code file" 'src'
pw "$P/README.md" 'Run: DROP TABLE legacy_orders; to clean up.'
warn_cc "R2-1 a doc outside .agents/ is covered (D11)" "README.md"
pw "$P/src/.agentsish/x.js" 'db.exec("DROP TABLE t")'
warn_cc "R2-1 a directory merely starting with .agents is not .agents/" ".agentsish"

echo "R2-1 pre_write: exempt paths and non-contract text stay quiet"
pe "$P/tests/setup.js" 'a' 'db.exec("DROP TABLE legacy_orders");'
quiet "R2-1 Edit tests/setup.js with DROP TABLE (test dir exempt, D11)"
for d in test tests spec fixture fixtures; do
  pw "$P/$d/teardown.js" 'db.exec("DROP TABLE legacy_orders");'
  quiet "R2-1 Write $d/teardown.js with DROP TABLE (test dir exempt)"
done
pw "$P/.agents/proposal.md" 'Proposal: DROP TABLE legacy_orders;'
quiet "R2-1 Write .agents/proposal.md with DROP TABLE (exempt)"
pw "$P/.agents/proposals/drop.js" 'db.exec("TRUNCATE orders")'
quiet "R2-1 Write .agents/proposals/drop.js (exempt)"
pw '.agents/proposal.md' 'DROP TABLE legacy_orders;'
quiet "R2-1 relative .agents/proposal.md (exempt)"
pw 'C:\proj\.agents\proposal.md' 'DROP TABLE legacy_orders;'
quiet "R2-1 Windows path with a .agents segment (exempt)"
pw "$P/src/orders.js" 'function ordersOf(db, id) { return db.all("SELECT * FROM orders WHERE customer_id = ?", [id]); }'
quiet "R2-1 a code file without a contract statement"
pw "$P/src/orders.js" 'db.exec("DELETE FROM orders WHERE id = 1")'
quiet "R2-1 a scoped DELETE is not a contract statement"
pe "$P/src/orders.js" 'db.exec("DROP TABLE t")' '// removed'
quiet "R2-1 Edit whose old_string (not new_string) holds the DROP"

echo "R2-1 pre_write: *.sql and *migrat* keep today's kinds"
pw "$P/db/migrations/003_drop.sql" 'DROP TABLE legacy_orders;'
assert_eq "R2-1 migration .sql still logs pending migration-contract" "guard pending migration-contract" "$(hl)"
pw "$P/db/cleanup.sql" 'TRUNCATE orders;'
assert_eq "R2-1 a plain .sql still logs pending sql" "guard pending sql" "$(hl)"
pw "$P/src/migrations/0004.ts" 'await db.raw("ALTER TABLE users DROP COLUMN age");'
assert_eq "R2-1 a code file under migrations/ still logs pending migration-contract" "guard pending migration-contract" "$(hl)"
pw "$P/db/migrations/007_add.sql" 'CREATE TABLE audit (id INTEGER);'
quiet "R2-1 an additive migration stays quiet"

# ---------------- R2-2 Stop ----------------
SN=0
# crepo -> new repo R: schema + src/orders.js + src/legacy.js (an old drop line at the baseline) + tests/teardown.js + docs/notes.md committed; session started
crepo() {
  R="$(mk_tmp)/repo"; mk_schema_repo "$R" >/dev/null; GRUNDIR="$R"
  mkdir -p "$R/src" "$R/tests" "$R/docs"
  printf '%s\n' 'function ordersOf(db, id) { return db.all("SELECT 1", [id]); }' 'module.exports = { ordersOf };' > "$R/src/orders.js"
  printf '%s\n' 'module.exports = function oldCleanup(db) {' '  db.exec("DROP TABLE tmp_cache");' '};' > "$R/src/legacy.js"
  printf '%s\n' 'afterAll(() => db.exec("DROP TABLE fx"));' > "$R/tests/teardown.js"
  printf '%s\n' '# notes' > "$R/docs/notes.md"
  fxg "$R" add -A; fxg "$R" commit -qm "code"
  BASE="$(git -C "$R" rev-parse HEAD)"; B7="$(printf '%s' "$BASE" | cut -c1-7)"
  SN=$((SN + 1)); SID="cc$SN"
  grun PB_HEADLESS=1 -- "$(jstart "$R" "$SID")" --session-start
}
gs() { local a="${1:-false}"; [ "$#" -gt 0 ] && shift; grun PB_HEADLESS=1 "$@" -- "$(jstop "$R" "$SID" "$a")" --stop; }
SHL="$GW/cc-stop.log"

echo "R2-2 Stop headless: a drop line added to a tracked code file blocks"
crepo; printf '%s\n' 'function purge(db) { db.exec("DROP TABLE legacy_orders"); }' >> "$R/src/orders.js"
: > "$SHL"; gs false PB_EVAL_HOOK_LOG="$SHL"
expect_block "R2-2 tracked src/orders.js gets a DROP TABLE line" code-contract
assert_contains "R2-2 the message names the file" "$GERR" "src/orders.js"
assert_contains "R2-2 the message shows the added line" "$GERR" "DROP TABLE legacy_orders"
assert_contains "R2-2 the message gives the restore hint for a tracked file" "$GERR" "(restore: git checkout $B7 -- src/orders.js)"
assert_contains "R2-2 the hook log says stop-block code-contract" "$(cat "$SHL")" "guard stop-block code-contract"
git -C "$R" checkout -q "$BASE" -- src/orders.js
gs true; expect_pass "R2-2 after git checkout <base> -- src/orders.js"

crepo; printf '%s\n' 'db.exec("ALTER TABLE orders DROP COLUMN total_cents");' >> "$R/src/orders.js"; git -C "$R" add src/orders.js
gs; expect_block "R2-2 a staged ALTER TABLE ... DROP line in code" code-contract
crepo; printf '%s\n' 'db.exec("TRUNCATE orders");' >> "$R/src/orders.js"; fxg "$R" commit -qam "wipe orders"
gs; expect_block "R2-2 a drop line committed after the baseline" code-contract
assert_contains "R2-2 the committed case names the file" "$GERR" "src/orders.js"
crepo; printf '%s\n' 'Run DROP TABLE legacy_orders; before the release.' >> "$R/docs/notes.md"
gs; expect_block "R2-2 a doc outside .agents/ with a drop line blocks (D11)" code-contract
assert_contains "R2-2 the doc is named" "$GERR" "docs/notes.md"
crepo; printf '%s\n' '    db.exec("DROP TABLE a_very_long_table_name_'"$(printf 'x%.0s' $(seq 1 200))"'");' >> "$R/src/orders.js"
gs; expect_block "R2-2 a very long drop line blocks" code-contract
LONGL="$(printf '%s\n' "$GERR" | awk 'length($0) > 600 { n++ } END { print n + 0 }')"
assert_eq "R2-2 the quoted line is cut (no 600+ char line in the message)" "0" "$LONGL"

echo "R2-2 Stop headless: an untracked code file blocks, with the untracked hint"
crepo; mkdir -p "$R/scripts"; printf '%s\n' '#!/bin/sh' 'sqlite3 shop.db "TRUNCATE orders;"' > "$R/scripts/cleanup.js"
gs
expect_block "R2-2 untracked scripts/cleanup.js with TRUNCATE" code-contract
assert_contains "R2-2 the message names the file" "$GERR" "scripts/cleanup.js"
assert_contains "R2-2 the untracked hint" "$GERR" "remove the new file or move it under .agents/"
assert_not_contains "R2-2 no git checkout restore hint for an untracked file" "$GERR" "git checkout $B7 -- scripts/cleanup.js"
crepo; printf '%s\n' 'x' > "$R/src/other.js"; printf '%s\n' 'drop table audit;' > "$R/src/zz_new.js"
gs; expect_block "R2-2 only the new file with the lower-case drop is the finding" code-contract
assert_contains "R2-2 the new file is named" "$GERR" "src/zz_new.js"
assert_not_contains "R2-2 the clean new file is not named" "$GERR" "src/other.js"

echo "R2-2 Stop headless: not findings"
crepo; printf '%s\n' '// one more comment' >> "$R/src/legacy.js"
gs; expect_pass "R2-2 a drop line already at the baseline, file changed elsewhere"
crepo; printf '%s\n' 'module.exports = function oldCleanup(db) {' '};' > "$R/src/legacy.js"
gs; expect_pass "R2-2 the baseline drop line was removed"
crepo; gs; expect_pass "R2-2 a drop line at the baseline, nothing changed"
crepo; mkdir -p "$R/.agents"; printf '%s\n' 'DROP TABLE legacy_orders;' > "$R/.agents/proposal.md"
gs; expect_pass "R2-2 untracked .agents/proposal.md with DROP (exempt)"
crepo; mkdir -p "$R/.agents/proposals"; printf '%s\n' 'db.exec("TRUNCATE orders");' > "$R/.agents/proposals/drop.js"
gs; expect_pass "R2-2 untracked .agents/proposals/drop.js (exempt)"
crepo; printf '%s\n' 'afterAll(() => db.exec("DROP TABLE other"));' >> "$R/tests/teardown.js"
gs; expect_pass "R2-2 a tracked test file gets a DROP line (test dir exempt, D11)"
crepo; mkdir -p "$R/spec" "$R/fixtures" "$R/test"
printf '%s\n' 'DROP TABLE a;' > "$R/spec/a.js"; printf '%s\n' 'DROP TABLE b;' > "$R/fixtures/b.js"; printf '%s\n' 'TRUNCATE c;' > "$R/test/c.js"
gs; expect_pass "R2-2 new files under spec/, fixtures/, test/ (exempt)"
crepo; mkdir -p "$R/node_modules/x"; printf '%s\n' 'DROP TABLE a;' > "$R/node_modules/x/i.js"
gs; expect_pass "R2-2 an untracked file under node_modules/ (exempt)"
crepo; printf 'DROP TABLE a;\000binary\n' > "$R/src/blob.dat"
gs; expect_pass "R2-2 a binary file is skipped"
crepo; { printf '%s\n' 'DROP TABLE big;'; head -c 1200000 /dev/zero | tr '\0' 'a'; printf '\n'; } > "$R/src/huge.js"
gs; expect_pass "R2-2 a file over 1 MB is skipped"
crepo; printf '%s\n' 'db.exec("DELETE FROM orders WHERE id = 1"); // not a contract statement' >> "$R/src/orders.js"
gs; expect_pass "R2-2 a scoped DELETE is not a finding"
crepo; printf '%s\n' 'const q = "SELECT dropdown FROM menu"; // drop in a word' >> "$R/src/orders.js"
gs; expect_pass "R2-2 the word drop outside a contract statement is not a finding"

echo "R2-2 Stop headless: the give-up counter is shared with the other kinds"
crepo; printf '%s\n' 'db.exec("DROP TABLE legacy_orders");' >> "$R/src/orders.js"
LOG3="$GW/cc-giveup.log"; : > "$LOG3"
gs false PB_EVAL_HOOK_LOG="$LOG3"; expect_block "R2-2 Stop 1 blocks" code-contract
gs true PB_EVAL_HOOK_LOG="$LOG3"; expect_block "R2-2 Stop 2 blocks" code-contract
gs true PB_EVAL_HOOK_LOG="$LOG3"; expect_block "R2-2 Stop 3 blocks" code-contract
assert_file "R2-2 the per-session counter file exists" "$(gcd "$R")/pb-guard/$SID.stops"
gs true PB_EVAL_HOOK_LOG="$LOG3"
assert_rc "R2-2 Stop 4 exits 0 (gives up)" 0
assert_contains "R2-2 Stop 4 says it gave up and names the finding kind" "$GOUT$GERR" "gave up after 3 Stop blocks"
assert_contains "R2-2 Stop 4 names the file" "$GOUT" "src/orders.js"
assert_contains "R2-2 the hook log has the give-up line" "$(cat "$LOG3")" "guard stop-giveup code-contract"
assert_eq "R2-2 the hook log has 3 stop-block code-contract lines" "3" "$(grep -c '^guard stop-block code-contract$' "$LOG3")"

echo "R2-2 Stop interactive: a warning, never a block"
crepo; printf '%s\n' 'db.exec("DROP TABLE legacy_orders");' >> "$R/src/orders.js"
: > "$SHL"; grun PB_HEADLESS=0 PB_EVAL_HOOK_LOG="$SHL" -- "$(jstop "$R" "$SID")" --stop
if [ "$RC" = 0 ] && has "$GOUTN" '"systemMessage":"agent-playbook guard: ' && has "$GOUT" "src/orders.js" && has "$GOUT" code-contract && ! has "$GOUT" '"decision"'; then
  t_ok "R2-2 interactive: exit 0, systemMessage naming code-contract and the file"
else t_bad "R2-2 interactive: exit 0, systemMessage naming code-contract and the file" "rc=$RC $OUT"; fi
assert_contains "R2-2 the hook log says warn code-contract" "$(cat "$SHL")" "guard warn code-contract"
assert_eq "R2-2 interactive writes no stop counter" "no" "$([ -f "$(gcd "$R")/pb-guard/$SID.stops" ] && echo yes || echo no)"

echo "R2-2 existing migration and schema outputs are unchanged (characterization)"
crepo; mkdir -p "$R/db/migrations"; printf 'DROP TABLE legacy_orders;\n' > "$R/db/migrations/001_drop.sql"
gs; expect_block "R2-2 an untracked migration still gives migration-contract" migration-contract
assert_not_contains "R2-2 a migration is not also a code-contract finding" "$GERR" "code-contract"
crepo; printf '%s\n' '-- the shop database (SQLite)' 'CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER NOT NULL, created_at TEXT NOT NULL, total_cents INTEGER NOT NULL);' > "$R/db/schema.sql"
gs; expect_block "R2-2 a removed table still gives schema-drop" schema-drop
assert_not_contains "R2-2 a schema change is not a code-contract finding" "$GERR" "code-contract"
crepo; printf 'DELETE FROM tmp; DROP TABLE tmp;\n' > "$R/db/scratch.sql"
gs; expect_pass "R2-2 a new non-migration .sql file with a DROP is still not a finding (schema rule, as today)"
crepo; printf '%s\n' 'db.exec("DROP TABLE legacy_orders");' >> "$R/src/orders.js"; mkdir -p "$R/db/migrations"; printf 'DROP TABLE x;\n' > "$R/db/migrations/002.sql"
gs; expect_block "R2-2 a code drop and a migration drop in one session" code-contract
assert_contains "R2-2 both kinds are reported (migration-contract too)" "$GERR" "migration-contract"
assert_contains "R2-2 the message lists the migration file" "$GERR" "db/migrations/002.sql"

t_summary
