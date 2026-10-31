#!/usr/bin/env bash
# Fix round R6 (spec .agents/handoff/01-spec.md "## Revision 9", R6-1 to R6-4).
# R6-1 Stop scans every file new since SessionStart or changed since its recorded hash (group A) up to the cap; any group A file left
#      unscanned blocks headless (scan-capped, fail closed). Unchanged recorded files are skipped. No marker needed for that.
# R6-2 SessionStart hashes up to 20000 filtered files (marker only beyond that); 20000 files SessionStart < 5 s.
# R6-3 (mutant Ma) more than 2000 pre-session unchanged files sorting before src/ plus a new src/zz.js with a DROP: code-contract.
# R6-4 the scan-capped count and directory list leave out unchanged skipped files.
# Reviewer E4 / E6: 2100 pre-session .venv, then 2100 new src/gen plus a new src/zz.js with a DROP, blocks (also after a resume).
. "$(dirname "$0")/lib.sh"
. "$PB_ROOT/tests/guard-fixture.sh"

SN=0
SHL="$GW/r6-stop.log"
DROPJS='db.exec("DROP TABLE legacy_orders");'
nrepo() {
  R="$(mk_tmp)/repo"; mk_schema_repo "$R" >/dev/null; GRUNDIR="$R"
  mkdir -p "$R/src"
  printf "%s\n" "module.exports = { ordersOf: (db, id) => db.all(\"SELECT 1\", [id]) };" > "$R/src/orders.js"
  fxg "$R" add -A; fxg "$R" commit -qm "code"
  SN=$((SN + 1)); SID="r6$SN"
}
sstart() { grun PB_HEADLESS=1 -- "$(jstart "$R" "$SID" "${1:-startup}")" --session-start; }
gs() { local a="${1:-false}"; [ "$#" -gt 0 ] && shift; grun PB_HEADLESS=1 "$@" -- "$(jstop "$R" "$SID" "$a")" --stop; }
# mkn DIR EXT N CONTENT -> N files DIR/f00001.EXT ... (5-digit names so the sort order is numeric), one xargs pass
mkn() { mkdir -p "$R/$1"; seq -f "$R/$1/f%05g.$2" 1 "$3" | CONTENT="$4" xargs -n 1000 sh -c "for f; do printf \"%s\n\" \"\$CONTENT\" > \"\$f\"; done" _; }
now_ms() { echo $(( $(date +%s%N) / 1000000 )); }
blocked_either() { # name -> exit 2 with code-contract or scan-capped, never 0
  if [ "$RC" = 2 ] && { has "$GERR" code-contract || has "$GERR" scan-capped; }; then t_ok "$1 (BLOCK code-contract or scan-capped)"; else t_bad "$1 (BLOCK code-contract or scan-capped)" "rc=$RC $OUT"; fi
}

echo "R6-1/E4 reviewer case: 2100 pre-session .venv, then 2100 new src/gen plus a new src/zz.js with a DROP"
nrepo; mkn .venv/lib py 2100 "x = 1"; sstart
mkn src/gen js 2100 "module.exports = 1;"; printf "%s\n" "$DROPJS" > "$R/src/zz.js"
gs false; blocked_either "E4 headless Stop"

echo "R6-1/E6 the same after a resume SessionStart"
nrepo; mkn .venv/lib py 2100 "x = 1"; sstart
mkn src/gen js 2100 "module.exports = 1;"; printf "%s\n" "$DROPJS" > "$R/src/zz.js"
sstart resume
gs false; blocked_either "E6 headless Stop after resume"

echo "R6-4 the scan-capped count leaves out the unchanged pre-session files"
nrepo; mkn .venv/lib py 2100 "x = 1"; sstart
mkn src/gen js 2100 "module.exports = 1;"
gs false PB_EVAL_HOOK_LOG="$SHL"; expect_block "R6-4 2100 new files over the cap after 2100 unchanged pre-session files" scan-capped
assert_contains "R6-4 the count is the 100 unscanned new files" "$GERR" "scan-capped: 100 untracked"
assert_not_contains "R6-4 the directory list does not name .venv" "$GERR" ".venv"
if printf "%s" "$GERR" | grep -qE "src \(100\)"; then t_ok "R6-4 the directory list is src (100)"; else t_bad "R6-4 the directory list is src (100)" "$GERR"; fi

echo "R6-3 (mutant Ma) 2100 pre-session unchanged files before src/ plus a new src/zz.js with a DROP; then no DROP"
nrepo; mkn .venv/lib py 2100 "x = 1"; sstart
: > "$SHL"; gs false PB_EVAL_HOOK_LOG="$SHL"
expect_pass "R6-2 2100 pre-session unchanged files alone (all hashed, all skipped)"
assert_not_contains "R6-2 no stop-scan-capped in the hook log" "$(cat "$SHL")" "scan-capped"
if [ ! -e "$(gcd "$R")/pb-guard/$SID.untracked.capped" ]; then t_ok "R6-2 no over-cap marker for 2100 files"; else t_bad "R6-2 no over-cap marker for 2100 files" "exists"; fi
printf "%s\n" "$DROPJS" > "$R/src/zz.js"
gs false; expect_block "R6-3 2100 unchanged .venv files plus a new src/zz.js with a DROP" code-contract
assert_contains "R6-3 src/zz.js is named" "$GERR" "src/zz.js"
assert_not_contains "R6-3 no scan-capped finding (only one file needed scanning)" "$GERR" "scan-capped"

echo "R6-2 20000 pre-session files: SessionStart under 5 s and 20000 hashes recorded"
nrepo; mkn src/big js 20000 "const a = 1;"
T0=$(now_ms); sstart; DS_MS=$(( $(now_ms) - T0 ))
REC="$(gcd "$R")/pb-guard/$SID.untracked"
if [ "$RC" = 0 ]; then t_ok "R6-2 SessionStart exits 0"; else t_bad "R6-2 SessionStart exits 0" "rc=$RC $OUT"; fi
if [ "$DS_MS" -lt 5000 ]; then t_ok "R6-2 SessionStart with 20000 files took ${DS_MS} ms (< 5000)"; else t_bad "R6-2 SessionStart with 20000 files took ${DS_MS} ms (< 5000)" "too slow"; fi
echo "  (SessionStart ${DS_MS} ms)"
assert_eq "R6-2 the record holds 20000 hash lines" "20000" "$(grep -c -E '^[0-9a-f]{40} .+$' "$REC" 2>/dev/null)"
if [ ! -e "$REC.capped" ]; then t_ok "R6-2 no over-cap marker at exactly 20000 files"; else t_bad "R6-2 no over-cap marker at exactly 20000 files" "exists"; fi
: > "$SHL"; T0=$(now_ms); gs false PB_EVAL_HOOK_LOG="$SHL"; DT_MS=$(( $(now_ms) - T0 ))
expect_pass "R6-2 Stop with 20000 pre-session unchanged files"
assert_not_contains "R6-2 Stop: no scan-capped in the hook log" "$(cat "$SHL")" "scan-capped"
echo "  (Stop ${DT_MS} ms)"
printf "%s\n" "$DROPJS" > "$R/src/big/f12345.js"
gs false; expect_block "R6-1 one of the 20000 hashed files changed to a DROP" code-contract
assert_contains "R6-1 src/big/f12345.js is named" "$GERR" "src/big/f12345.js"

echo "R6-1/R6-2 23000 pre-session files: only the first 20000 are hashed (documented residual beyond the Stop cap)"
nrepo; mkn src/big js 23000 "const a = 1;"
sstart
REC="$(gcd "$R")/pb-guard/$SID.untracked"
assert_eq "R6-2 the record holds 20000 hash lines" "20000" "$(grep -c -E '^[0-9a-f]{40} .+$' "$REC" 2>/dev/null)"
assert_file "R6-2 the over-cap marker exists beyond 20000 files" "$REC.capped"
( cd "$R" && LC_ALL=C git ls-files -o --exclude-standard | LC_ALL=C sort ) > "$GW/all.txt"
sed -n 's/^[0-9a-f]\{40\} //p' "$REC" | LC_ALL=C sort > "$GW/hashed.txt"
LC_ALL=C comm -23 "$GW/all.txt" "$GW/hashed.txt" > "$GW/unhashed.txt"
assert_eq "R6-2 3000 files are unhashed" "3000" "$(wc -l < "$GW/unhashed.txt" | tr -d ' ')"
LAST_U="$(tail -n 1 "$GW/unhashed.txt")"; FIRST_U="$(head -n 1 "$GW/unhashed.txt")"
printf "%s\n" "$DROPJS" > "$R/$LAST_U"
: > "$SHL"; gs false PB_EVAL_HOOK_LOG="$SHL"
if [ "$RC" = 0 ]; then t_ok "R6-1 the last unhashed file (past the Stop cap) modified to a DROP: exit 0 (warn only, documented residual)"; else t_bad "R6-1 the last unhashed file modified to a DROP: exit 0 (warn only, documented residual)" "rc=$RC $OUT"; fi
assert_not_contains "R6-1 residual: no stop-block in the hook log" "$(cat "$SHL")" "stop-block"
if has "$GOUTN" '"systemMessage":"'; then t_ok "R6-1 residual: a systemMessage warning is given"; else t_bad "R6-1 residual: a systemMessage warning is given" "$OUT"; fi
printf "%s\n" "const a = 1;" > "$R/$LAST_U"
printf "%s\n" "$DROPJS" > "$R/$FIRST_U"
gs false; expect_block "R6-1 the first unhashed file (inside the Stop cap) modified to a DROP is scanned" code-contract
assert_contains "R6-1 the first unhashed file is named" "$GERR" "$FIRST_U"


echo "R6-4 marker set (23000 pre-session files): the count and directory list leave out the 20000 hashed unchanged files"
printf "%s\n" "const a = 1;" > "$R/$FIRST_U"
mkn src/gen js 2100 "module.exports = 1;"
gs false PB_EVAL_HOOK_LOG="$SHL"; expect_block "R6-4 marker: 2100 new files over the cap" scan-capped
assert_contains "R6-4 marker: the count is 100 new plus 3000 unhashed pre-session, not the 20000 unchanged hashed" "$GERR" "scan-capped: 3100 untracked"
if printf "%s" "$GERR" | grep -qE "src \(3100\)"; then t_ok "R6-4 marker: the directory list is src (3100)"; else t_bad "R6-4 marker: the directory list is src (3100)" "$GERR"; fi

echo "R6-1/X6 marker set: 23000 pre-session files, then 2100 new src/gen plus a new src/zz.js with a DROP (group A over the cap)"
printf "%s\n" "$DROPJS" > "$R/src/zz.js"
: > "$SHL"; gs false PB_EVAL_HOOK_LOG="$SHL"; blocked_either "X6 headless Stop"
assert_contains "X6 the hook log has a stop-block line" "$(cat "$SHL")" "stop-block"

t_summary
