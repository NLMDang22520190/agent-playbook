#!/usr/bin/env bash
# Fix round R5 (spec .agents/handoff/01-spec.md "## Revision 8", R5-1 to R5-4).
# R5-1 files already untracked at SessionStart never cause a scan-capped block (warning only, no .stops count); R4-1 stays without the marker.
# R5-2 the scan-capped message never says remove/delete; names the top dirs with counts; .gitignore and .agents/.
# R5-3 per-file filter is one awk pass: 30000 node_modules files plus 100 src files, Stop < 5 s, SessionStart < 3 s.
# R5-4 the SessionStart record excludes node_modules/, .agents/ and test-dir files.
. "$(dirname "$0")/lib.sh"
. "$PB_ROOT/tests/guard-fixture.sh"

SN=0
SHL="$GW/r5-stop.log"
nrepo() {
  R="$(mk_tmp)/repo"; mk_schema_repo "$R" >/dev/null; GRUNDIR="$R"
  mkdir -p "$R/src"
  printf "%s\n" "module.exports = { ordersOf: (db, id) => db.all(\"SELECT 1\", [id]) };" > "$R/src/orders.js"
  fxg "$R" add -A; fxg "$R" commit -qm "code"
  SN=$((SN + 1)); SID="r5$SN"
}
sstart() { grun PB_HEADLESS=1 -- "$(jstart "$R" "$SID")" --session-start; }
gs() { local a="${1:-false}"; [ "$#" -gt 0 ] && shift; grun PB_HEADLESS=1 "$@" -- "$(jstop "$R" "$SID" "$a")" --stop; }
mkn() { mkdir -p "$R/$1"; seq -f "$R/$1/f%04g.$2" 1 "$3" | CONTENT="$4" xargs -n 500 sh -c "for f; do printf \"%s\n\" \"\$CONTENT\" > \"\$f\"; done" _; }
now_ms() { echo $(( $(date +%s%N) / 1000000 )); }

echo "R5-1 pre-session untracked files over the cap only warn"
nrepo; mkn .venv/lib py 2100 "x = 1"; sstart
: > "$SHL"; gs false PB_EVAL_HOOK_LOG="$SHL"
if [ "$RC" = 0 ]; then t_ok "R5-1 pre-session 2100 .venv/lib/*.py: headless Stop exits 0"; else t_bad "R5-1 pre-session 2100 .venv/lib/*.py: headless Stop exits 0" "rc=$RC $OUT"; fi
assert_contains "R5-1 stop-scan-capped is logged" "$(cat "$SHL")" "guard stop-scan-capped"
if has "$GOUTN" "\"systemMessage\":\"" && has "$GOUT$GERR" scan; then t_ok "R5-1 a systemMessage warning mentions the scan"; else t_bad "R5-1 a systemMessage warning mentions the scan" "$OUT"; fi
assert_not_contains "R5-1 no stop-block line in the hook log" "$(cat "$SHL")" "stop-block"
if [ ! -e "$(gcd "$R")/pb-guard/$SID.stops" ]; then t_ok "R5-1 no .stops file (not counted)"; else t_bad "R5-1 no .stops file (not counted)" "exists: $(cat "$(gcd "$R")/pb-guard/$SID.stops")"; fi

nrepo; sstart; mkn .venv/lib py 2100 "x = 1"
gs false; expect_block "R5-1 the same 2100 files created AFTER SessionStart (no marker) still fail closed" scan-capped

nrepo; mkn .venv/lib py 2100 "x = 1"; sstart
printf "%s\n" "db.exec(\"DROP TABLE legacy_orders\");" > "$R/src/x.js"
gs false; expect_block "R5-1 pre-session over-cap set plus a new src/x.js with a DROP still blocks" code-contract
assert_contains "R5-1 src/x.js is named" "$GERR" "src/x.js"

echo "R5-2 scan-capped message"
nrepo; sstart; mkn src/gen js 2100 "module.exports = 1;"
gs false; expect_block "R5-2 headless scan-capped block" scan-capped
if printf "%s" "$GERR" | grep -qiE "remove|delete"; then t_bad "R5-2 the message has no remove/delete" "$GERR"; else t_ok "R5-2 the message has no remove/delete"; fi
if printf "%s" "$GERR" | grep "^- scan-capped" | grep -qiE "remove|delete"; then t_bad "R5-2 the scan-capped item line has no remove/delete" "$GERR"; else t_ok "R5-2 the scan-capped item line has no remove/delete"; fi
if printf "%s" "$GERR" | grep -qE "src[^0-9]{0,30}[0-9]+"; then t_ok "R5-2 the top-level dir name appears with a number"; else t_bad "R5-2 the top-level dir name appears with a number" "$GERR"; fi
assert_contains "R5-2 mentions .gitignore" "$GERR" ".gitignore"
assert_contains "R5-2 mentions .agents/" "$GERR" ".agents/"

echo "R5-3 30000 node_modules files plus 100 src files are fast"
nrepo; mkn node_modules/pkg js 30000 "module.exports = 1;"; mkn src/many js 100 "const a = 1;"
T0=$(now_ms); sstart; DS_MS=$(( $(now_ms) - T0 ))
T0=$(now_ms); gs false; DT_MS=$(( $(now_ms) - T0 ))
if [ "$RC" = 0 ]; then t_ok "R5-3 headless Stop exits 0"; else t_bad "R5-3 headless Stop exits 0" "rc=$RC $OUT"; fi
if [ "$DT_MS" -lt 5000 ]; then t_ok "R5-3 headless Stop took ${DT_MS} ms (< 5000)"; else t_bad "R5-3 headless Stop took ${DT_MS} ms (< 5000)" "too slow"; fi
if [ "$DS_MS" -lt 3000 ]; then t_ok "R5-3 SessionStart took ${DS_MS} ms (< 3000)"; else t_bad "R5-3 SessionStart took ${DS_MS} ms (< 3000)" "too slow"; fi
echo "  (Stop ${DT_MS} ms, SessionStart ${DS_MS} ms)"

echo "R5-4 the SessionStart record exclusions"
nrepo; mkn node_modules/pkg js 3 "module.exports = 1;"; mkn .agents/gen js 3 "const a = 1;"; mkn tests js 3 "const t = 1;"; mkn src/keep js 3 "const k = 1;"
sstart
REC="$(gcd "$R")/pb-guard/$SID.untracked"
assert_file "R5-4 the record file exists" "$REC"
assert_contains "R5-4 control: src/keep is recorded" "$(cat "$REC" 2>/dev/null)" " src/keep/"
assert_eq "R5-4 no line for node_modules/" "0" "$(grep -c " node_modules/" "$REC" 2>/dev/null)"
assert_eq "R5-4 no line for .agents/" "0" "$(grep -c " \.agents/" "$REC" 2>/dev/null)"
assert_eq "R5-4 no line for a tests/ file" "0" "$(grep -c " tests/" "$REC" 2>/dev/null)"

t_summary
