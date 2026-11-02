#!/usr/bin/env bash
# Fix round R4 (spec .agents/handoff/01-spec.md "## Revision 7", R4-1 to R4-3): bounded Stop scan, linear SessionStart record, migration baseline.
# R4-1 the 2000-file cap applies AFTER filtering to files that can be findings (is_code or is_mig, regular files); over the cap on that
#      filtered list a headless Stop blocks with kind `scan-capped` (counted in .stops, stop-giveup after 3), interactive Stop warns.
# R4-2 SessionStart record_untracked is linear: 2000 untracked files in under 5 s, one line per file, no blank line.
# R4-3 an untracked migration file with a contract statement, unchanged since SessionStart, is not a finding; changed after it is.
. "$(dirname "$0")/lib.sh"
. "$PB_ROOT/tests/guard-fixture.sh"

SN=0
SHL="$GW/r4-stop.log"
# nrepo -> new repo R (schema + src/orders.js committed), session NOT started; srepo -> same, session started
nrepo() {
  R="$(mk_tmp)/repo"; mk_schema_repo "$R" >/dev/null; GRUNDIR="$R"
  mkdir -p "$R/src"
  printf '%s\n' 'module.exports = { ordersOf: (db, id) => db.all("SELECT 1", [id]) };' > "$R/src/orders.js"
  fxg "$R" add -A; fxg "$R" commit -qm "code"
  SN=$((SN + 1)); SID="r4$SN"
}
sstart() { grun PB_HEADLESS=1 -- "$(jstart "$R" "$SID")" --session-start; }
srepo() { nrepo; sstart; }
gs() { local a="${1:-false}"; [ "$#" -gt 0 ] && shift; grun PB_HEADLESS=1 "$@" -- "$(jstop "$R" "$SID" "$a")" --stop; }
gi() { grun "$@" -- "$(jstop "$R" "$SID" false)" --stop; }
# mkn DIR EXT N CONTENT -> N small files DIR/f0001.EXT ... in one pass
mkn() { mkdir -p "$R/$1"; seq -f "$R/$1/f%04g.$2" 1 "$3" | CONTENT="$4" xargs -n 500 sh -c 'for f; do printf "%s\n" "$CONTENT" > "$f"; done' _; }

echo "R4-1 Stop headless: the cap applies after filtering"
srepo; mkn node_modules/pkg js 2100 'module.exports = 1;'
mkdir -p "$R/scripts"; printf '%s\n' 'db.exec("DROP TABLE legacy_orders");' > "$R/scripts/cleanup.js"
: > "$SHL"; T0=$SECONDS; gs false PB_EVAL_HOOK_LOG="$SHL"; DT=$((SECONDS - T0))
expect_block "R4-1 2100 node_modules files plus scripts/cleanup.js with a DROP" code-contract
assert_contains "R4-1 scripts/cleanup.js is named" "$GERR" "scripts/cleanup.js"
assert_not_contains "R4-1 node_modules is out of the filtered list: no scan-capped block" "$GERR" "scan-capped"
assert_not_contains "R4-1 node_modules is out of the filtered list: no stop-scan-capped log" "$(cat "$SHL")" "stop-scan-capped"
echo "  (took ${DT}s)"

srepo; mkn assets png 2100 'x'
mkdir -p "$R/db/migrations"; printf '%s\n' 'DROP TABLE legacy_orders;' > "$R/db/migrations/002_drop.sql"
gs; expect_block "R4-1 2100 assets/*.png plus an untracked db/migrations/002_drop.sql with a DROP" migration-contract
assert_contains "R4-1 db/migrations/002_drop.sql is named" "$GERR" "db/migrations/002_drop.sql"

echo "R4-1 Stop: 2100 clean code files over the cap"
srepo; mkn src/gen js 2100 'module.exports = 1;'
: > "$SHL"; gi PB_EVAL_HOOK_LOG="$SHL"
if [ "$RC" = 0 ] && has "$GOUTN" '"systemMessage":"' && has "$GOUT" scan; then t_ok "R4-1 interactive: 2100 clean src/gen files only warn (exit 0, systemMessage mentions the scan)"; else t_bad "R4-1 interactive: 2100 clean src/gen files only warn" "rc=$RC $OUT"; fi
assert_contains "R4-1 interactive: the hook log says warn scan-capped" "$(cat "$SHL")" "warn scan-capped"
assert_contains "R4-1 interactive: stop-scan-capped is still logged" "$(cat "$SHL")" "guard stop-scan-capped"
: > "$SHL"; gs false PB_EVAL_HOOK_LOG="$SHL"
expect_block "R4-1 headless: 2100 clean src/gen files fail closed" scan-capped
assert_contains "R4-1 headless: the message says how many files were not scanned (100 over the cap)" "$GERR" "100"
assert_contains "R4-1 headless: the message says to remove, ignore or move them under .agents/" "$GERR" ".agents/"
assert_contains "R4-1 headless: stop-scan-capped is still logged" "$(cat "$SHL")" "guard stop-scan-capped"
assert_contains "R4-1 headless: the hook log says stop-block scan-capped" "$(cat "$SHL")" "stop-block scan-capped"
assert_eq "R4-1 the block is counted in the .stops file" "1" "$(tr -d '\r\n ' < "$(gcd "$R")/pb-guard/$SID.stops" 2>/dev/null)"
gs; expect_block "R4-1 headless: second Stop still blocks" scan-capped
gs; expect_block "R4-1 headless: third Stop still blocks" scan-capped
: > "$SHL"; gs false PB_EVAL_HOOK_LOG="$SHL"
if [ "$RC" = 0 ] && has "$GERR" "gave up after 3"; then t_ok "R4-1 headless: the 4th Stop gives up (exit 0, gave up after 3)"; else t_bad "R4-1 headless: the 4th Stop gives up" "rc=$RC $OUT"; fi
assert_contains "R4-1 the hook log says stop-giveup scan-capped" "$(cat "$SHL")" "stop-giveup scan-capped"
srepo; mkn src/gen js 2000 'module.exports = 1;'
gs; expect_pass "R4-1 exactly 2000 clean code files (at the cap) pass"

echo "R4-2 SessionStart record_untracked is linear"
nrepo; mkn src/many js 1999 'module.exports = 1;'; printf '%s\n' 'const a = 1;' > "$R/src/with space.js"
T0=$SECONDS; sstart; DT=$((SECONDS - T0))
REC="$(gcd "$R")/pb-guard/$SID.untracked"
assert_file "R4-2 the record file exists" "$REC"
if [ "$DT" -le 5 ]; then t_ok "R4-2 SessionStart with 2000 untracked files took ${DT}s (<= 5 s)"; else t_bad "R4-2 SessionStart with 2000 untracked files took ${DT}s (<= 5 s)" "too slow"; fi
assert_eq "R4-2 the record holds exactly one line per file" "2000" "$(wc -l < "$REC" | tr -d ' ')"
assert_eq "R4-2 the record has no blank line" "0" "$(grep -c '^$' "$REC")"
assert_eq "R4-2 every record line is '<40 hex> <non-empty path>' (no empty-path line)" "2000" "$(grep -c -E '^[0-9a-f]{40} .+$' "$REC")"
echo "  (SessionStart took ${DT}s)"
LST="$(mk_tmp)/list"
( cd "$R" && git -c core.quotepath=off ls-files -o --exclude-standard | sort > "$LST" )
EXP="$( cd "$R" && git hash-object --stdin-paths < "$LST" | paste -d' ' - "$LST" | sort | md5sum )"
GOT="$(sort "$REC" | md5sum)"
assert_eq "R4-2 every line is '<hash-object> <path>' for its own file (incl. the name with a space)" "$EXP" "$GOT"
gs; expect_pass "R4-2 Stop after the record: the 2000 recorded clean files pass"

echo "R4-3 untracked migration files and the SessionStart record"
nrepo; mkdir -p "$R/db/migrations"; printf '%s\n' 'DROP TABLE scratch_cache;' > "$R/db/migrations/003_scratch.sql"; sstart
gs; expect_pass "R4-3 an untracked migration with a contract statement, unchanged since SessionStart, is not a finding"
nrepo; mkdir -p "$R/db/migrations"; printf '%s\n' 'DROP TABLE scratch_cache;' > "$R/db/migrations/003_scratch.sql"; sstart
printf '%s\n' '-- edited after the session started' >> "$R/db/migrations/003_scratch.sql"
gs; expect_block "R4-3 the same migration changed after SessionStart is a finding" migration-contract
assert_contains "R4-3 the changed migration is named" "$GERR" "db/migrations/003_scratch.sql"
nrepo; mkdir -p "$R/db/migrations"; printf '%s\n' 'DROP TABLE scratch_cache;' > "$R/db/migrations/003_scratch.sql"; sstart
printf '%s\n' 'TRUNCATE orders;' > "$R/db/migrations/004_new.sql"
gs; expect_block "R4-3 a migration created after SessionStart is a finding" migration-contract
assert_contains "R4-3 the new migration is named" "$GERR" "db/migrations/004_new.sql"
assert_not_contains "R4-3 the unchanged pre-existing migration is not named" "$GERR" "003_scratch.sql"
nrepo; mkdir -p "$R/db/migrations"; printf '%s\n' 'DROP TABLE scratch_cache;' > "$R/db/migrations/003_scratch.sql"
gs; expect_block "R4-3 no SessionStart record: today's behaviour (a finding)" migration-contract

t_summary
