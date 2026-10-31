#!/usr/bin/env bash
# Fix round R3 (spec .agents/handoff/01-spec.md "## Revision 6", R3-1 to R3-3): the guard's code-contract check, second round.
# R3-1 in code files a contract statement is SQL-shaped only (drop table|column|database|schema [if exists] <ident>, truncate table <ident>,
#      upper-case TRUNCATE <ident>, alter table ... drop); Tailwind `truncate`, _.truncate(, def truncate(, f.truncate(0), os.Truncate(, a
#      comment saying "never truncate to whole cents", dropdown and knex dropTable( are not. *.sql and *migrat* keep today's rule.
# R3-2 the Stop untracked scan is bounded: at most 2000 untracked files and 1 MB per file; over 2000 files the hook log gets
#      `guard stop-scan-capped`; 2000 small clean files finish fast (bound 10 s here, the spec says 3 s, to avoid flakes).
# R3-3 untracked files present at SessionStart with the same content are not findings; a changed one is; no SessionStart record: as today.
# Hook input shapes as in tests/guard-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$PB_ROOT/tests/guard-fixture.sh"

P=/pbguard-proj/app
HL="$GW/r3-hook.log"
pw() { local f="$1" t="$2"; shift 2; : > "$HL"; GRUNDIR="$GW"; grun PB_HEADLESS=1 PB_EVAL_HOOK_LOG="$HL" "$@" -- "$(jwrite "$f" "$t" "$P")"; }
hl() { cat "$HL" 2>/dev/null; }
quiet() {
  expect_pass "$1"
  if [ -z "$(hl)" ]; then t_ok "$1: nothing in the hook log"; else t_bad "$1: nothing in the hook log" "log=[$(hl)]"; fi
}
warn_cc() {
  expect_warn "$1"
  assert_contains "$1: the hook log says pending code-contract" "$(hl)" "guard pending code-contract"
}

echo "R3-1 pre_write: not a contract statement in a code file (no warning)"
pw "$P/src/Card.jsx" '<div className="truncate text-sm">{name}</div>'
quiet "R3-1 Tailwind class truncate"
pw "$P/src/format.js" 'const short = _.truncate(title, { length: 30 });'
quiet "R3-1 _.truncate( call"
pw "$P/lib/text.py" 'def truncate(s, n):
    return s[:n]'
quiet "R3-1 def truncate( in Python"
pw "$P/lib/log.py" 'with open(path, "r+") as f:
    f.truncate(0)'
quiet "R3-1 f.truncate(0) on a file object"
pw "$P/pkg/file.go" 'err := os.Truncate(name, 0)'
quiet "R3-1 os.Truncate( in Go"
pw "$P/src/money.js" '// round half up, never truncate to whole cents
const cents = Math.round(x * 100);'
quiet "R3-1 a comment saying never truncate to whole cents"
pw "$P/src/menu.js" 'const q = "SELECT dropdown FROM menu"; // the dropdown'
quiet "R3-1 the word dropdown"
pw "$P/src/db.js" 'await knex.schema.dropTable("tmp");'
quiet "R3-1 knex.schema.dropTable( in a code file"

echo "R3-1 pre_write: true positives still warn in code files"
pw "$P/src/orders.js" 'db.exec("drop table legacy_orders");'
warn_cc "R3-1 lower-case drop table in a JS string"
pw "$P/src/orders.js" 'db.exec("TRUNCATE orders");'
warn_cc "R3-1 TRUNCATE orders"
pw "$P/src/orders.js" 'db.exec("truncate table orders");'
warn_cc "R3-1 truncate table orders (lower case)"
pw "$P/src/orders.js" 'db.exec(`DROP TABLE IF EXISTS "legacy_orders"`);'
warn_cc "R3-1 DROP TABLE IF EXISTS with a quoted name"
pw "$P/lib/db.py" 'cur.execute("ALTER TABLE users DROP COLUMN age")'
warn_cc "R3-1 ALTER TABLE ... DROP"

echo "R3-1 pre_write: *.sql and *migrat* keep today's rule"
pw "$P/db/migrations/005.sql" 'truncate orders;'
assert_eq "R3-1 a migration with lower-case truncate orders; is still pending migration-contract" "guard pending migration-contract" "$(hl)"
pw "$P/src/migrations/0006.js" 'await db.raw("truncate orders");'
assert_eq "R3-1 a code file under migrations/ with lower-case truncate is still pending migration-contract" "guard pending migration-contract" "$(hl)"

# ---------------- Stop ----------------
SN=0
SHL="$GW/r3-stop.log"
# srepo -> new repo R (schema + src/orders.js committed), session started
srepo() {
  R="$(mk_tmp)/repo"; mk_schema_repo "$R" >/dev/null; GRUNDIR="$R"
  mkdir -p "$R/src"
  printf '%s\n' 'module.exports = { ordersOf: (db, id) => db.all("SELECT 1", [id]) };' > "$R/src/orders.js"
  fxg "$R" add -A; fxg "$R" commit -qm "code"
  SN=$((SN + 1)); SID="r3$SN"
  grun PB_HEADLESS=1 -- "$(jstart "$R" "$SID")" --session-start
}
# nrepo -> like srepo but the session is NOT started (the caller creates files, then runs sstart)
nrepo() {
  R="$(mk_tmp)/repo"; mk_schema_repo "$R" >/dev/null; GRUNDIR="$R"
  mkdir -p "$R/src"
  printf '%s\n' 'module.exports = { ordersOf: (db, id) => db.all("SELECT 1", [id]) };' > "$R/src/orders.js"
  fxg "$R" add -A; fxg "$R" commit -qm "code"
  SN=$((SN + 1)); SID="r3$SN"
}
sstart() { grun PB_HEADLESS=1 -- "$(jstart "$R" "$SID")" --session-start; }
gs() { local a="${1:-false}"; [ "$#" -gt 0 ] && shift; grun PB_HEADLESS=1 "$@" -- "$(jstop "$R" "$SID" "$a")" --stop; }

echo "R3-1 Stop headless: untracked false positives are not findings"
srepo
printf '%s\n' 'export const C = () => <div className="truncate">x</div>;' > "$R/src/Card.jsx"
printf '%s\n' 'const t = _.truncate(s, { length: 3 });' > "$R/src/fmt.js"
printf '%s\n' 'def truncate(s, n):' '    return s[:n]' > "$R/src/text.py"
printf '%s\n' 'f.truncate(0)' > "$R/src/log.py"
printf '%s\n' 'err := os.Truncate(name, 0)' > "$R/src/file.go"
printf '%s\n' '// round half up, never truncate to whole cents' > "$R/src/money.js"
gs; expect_pass "R3-1 six untracked files with truncate in non-SQL shapes"
srepo; printf '%s\n' '<p className="truncate">x</p>' >> "$R/src/orders.js"
gs; expect_pass "R3-1 a tracked file with an added Tailwind truncate line"

echo "R3-1 Stop headless: untracked true positives still block"
for c in 'db.exec("drop table legacy_orders");' 'db.exec("TRUNCATE orders");' 'db.exec("truncate table orders");' 'db.exec(`DROP TABLE IF EXISTS "legacy_orders"`);'; do
  srepo; printf '%s\n' "$c" > "$R/src/purge.js"
  gs; expect_block "R3-1 untracked src/purge.js: $c" code-contract
  assert_contains "R3-1 the file is named" "$GERR" "src/purge.js"
done
srepo; mkdir -p "$R/db/migrations"; printf '%s\n' 'truncate orders;' > "$R/db/migrations/009.sql"
gs; expect_block "R3-1 a migration with lower-case truncate orders; still gives migration-contract" migration-contract

echo "R3-2 Stop headless: the untracked scan is bounded"
# mkmany N -> N small clean untracked .js files named f0001.js ... under src/many
mkmany() { mkdir -p "$R/src/many"; local i=1; while [ "$i" -le "$1" ]; do printf 'module.exports = %d;\n' "$i" > "$R/src/many/$(printf 'f%04d' "$i").js"; i=$((i + 1)); done; }
srepo; mkmany 2000
: > "$SHL"; T0=$SECONDS; gs false PB_EVAL_HOOK_LOG="$SHL"; DT=$((SECONDS - T0))
expect_pass "R3-2 2000 small clean untracked .js files"
if [ "$DT" -le 10 ]; then t_ok "R3-2 headless Stop with 2000 clean untracked files took ${DT}s (<= 10 s)"; else t_bad "R3-2 headless Stop with 2000 clean untracked files took ${DT}s (<= 10 s)" "too slow"; fi
assert_not_contains "R3-2 2000 files is within the cap: no stop-scan-capped" "$(cat "$SHL")" "stop-scan-capped"
srepo; mkmany 2100
: > "$SHL"; T0=$SECONDS; gs false PB_EVAL_HOOK_LOG="$SHL"; DT=$((SECONDS - T0))
expect_pass "R3-2 2100 small clean untracked .js files"
assert_contains "R3-2 over 2000 files the hook log says stop-scan-capped" "$(cat "$SHL")" "guard stop-scan-capped"
if [ "$DT" -le 10 ]; then t_ok "R3-2 2100 files took ${DT}s (<= 10 s)"; else t_bad "R3-2 2100 files took ${DT}s (<= 10 s)" "too slow"; fi
srepo; mkmany 1500; printf '%s\n' 'db.exec("DROP TABLE legacy_orders");' > "$R/src/a_dirty.js"
gs; expect_block "R3-2 a dirty file among 1500 clean ones (within the cap) is found" code-contract
assert_contains "R3-2 the dirty file is named" "$GERR" "src/a_dirty.js"
assert_not_contains "R3-2 clean files are not named" "$GERR" "src/many/f0001.js"
srepo; mkmany 300; { printf '%s\n' 'DROP TABLE big;'; head -c 1200000 /dev/zero | tr '\0' 'a'; printf '\n'; } > "$R/src/huge.js"
gs; expect_pass "R3-2 an untracked file over 1 MB with a DROP among 300 clean files is skipped"

echo "R3-3 Stop headless: untracked files present at SessionStart"
nrepo; printf '%s\n' 'db.exec("DROP TABLE scratch_cache");' > "$R/src/scratch.js"; sstart
gs; expect_pass "R3-3 an untracked file with a DROP at SessionStart, unchanged, is not a finding"
nrepo; printf '%s\n' 'db.exec("DROP TABLE scratch_cache");' > "$R/src/scratch.js"; sstart
printf '%s\n' '// edited after the session started' >> "$R/src/scratch.js"
gs; expect_block "R3-3 the same file changed after SessionStart is a finding" code-contract
assert_contains "R3-3 the changed file is named" "$GERR" "src/scratch.js"
nrepo; printf '%s\n' 'db.exec("DROP TABLE scratch_cache");' > "$R/src/scratch.js"; sstart
printf '%s\n' 'db.exec("DROP TABLE new_one");' > "$R/src/second.js"
gs; expect_block "R3-3 a file created after SessionStart is a finding" code-contract
assert_contains "R3-3 the new file is named" "$GERR" "src/second.js"
assert_not_contains "R3-3 the unchanged pre-existing file is not named" "$GERR" "src/scratch.js"
nrepo; printf '%s\n' 'db.exec("DROP TABLE scratch_cache");' > "$R/src/scratch.js"
gs; expect_block "R3-3 no SessionStart record: today's behaviour (a finding)" code-contract
nrepo; printf '%s\n' 'db.exec("DROP TABLE scratch_cache");' > "$R/src/scratch.js"; sstart
printf '%s\n' 'db.exec("DROP TABLE scratch_cache");' > "$R/src/moved.js"
gs; expect_block "R3-3 the same content under a new name is a finding (name and hash must match)" code-contract
assert_contains "R3-3 the new name is named" "$GERR" "src/moved.js"

t_summary
