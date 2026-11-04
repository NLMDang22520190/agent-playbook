#!/usr/bin/env bash
# Tests for evals/tasks-project/outcome-classes.js (fixed / surfaced / missed from a pb-evals/1 result and the final replies)
. "$(dirname "$0")/lib.sh"
OC="$PB_ROOT/evals/tasks-project/outcome-classes.js"

if ! command -v node >/dev/null 2>&1; then
  t_skip 1 "node is not installed"
  t_summary
  exit 0
fi

D="$(mk_tmp)"
mkdir -p "$D/tasks/t1" "$D/out/result.runs"
printf '{"checks":[{"name":"second place","test":"tests/x.f2p.test.js","pattern":"dailyRevenue|reports\\\\.js"}]}' > "$D/tasks/t1/surface.json"
run_json() { # label arm status result
  printf '{"scenario":"t1","arm":"%s","label":"%s","status":"%s","notes":["tasks_dir=%s/tasks"],"checks":[{"name":"FAIL_TO_PASS tests/x.f2p.test.js","result":"%s"}]}' "$2" "$1" "$3" "$D" "$4"
}
{
  printf '{"schema":"pb-evals/1","runs":['
  run_json t1.with.1 with graded PASS; printf ','
  run_json t1.with.2 with graded FAIL; printf ','
  run_json t1.with.3 with graded FAIL; printf ','
  run_json t1.with.4 with ERROR FAIL; printf ','
  run_json t1.without.1 without graded FAIL
  printf ']}'
} > "$D/out/result.json"
printf 'All done.\n' > "$D/out/result.runs/t1.with.1.log.result"
printf 'Note: `dailyRevenue` still ignores refunds, left for you.\n' > "$D/out/result.runs/t1.with.2.log.result"
printf 'All done, nothing else.\n' > "$D/out/result.runs/t1.with.3.log.result"
printf 'The REPORTS.JS file is unchanged.\n' > "$D/out/result.runs/t1.without.1.log.result"

echo "outcome-classes.js"
run node "$OC" --json "$D/out/result.json"
assert_rc "json run exits 0" 0
J() { printf '%s' "$OUT" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const o=JSON.parse(s);console.log(eval(process.argv[1]))})' "$1"; }
assert_eq "a passing test is FIXED" "FIXED" "$(J 'o.rows.find(r=>r.label=="t1.with.1").cls')"
assert_eq "a failing test whose reply names the thing is SURFACED" "SURFACED" "$(J 'o.rows.find(r=>r.label=="t1.with.2").cls')"
assert_eq "a failing test whose reply does not is MISSED" "MISSED" "$(J 'o.rows.find(r=>r.label=="t1.with.3").cls')"
assert_eq "the match ignores case" "SURFACED" "$(J 'o.rows.find(r=>r.label=="t1.without.1").cls')"
assert_eq "an ERROR run is left out" "4" "$(J 'o.rows.length')"
assert_eq "the summary counts per arm" "1" "$(J 'o.summary["t1|second place|with"].MISSED')"
run node "$OC" "$D/out/result.json"
assert_contains "the table names the arm and the counts" "$OUT" "| t1 | second place | with | 1 | 1 | 1 |"
assert_contains "the surfaced line is printed for a reader" "$OUT" "still ignores refunds"
run node "$OC"
assert_rc "no argument is a usage error" 2
run node "$OC" "$D/missing.json"
assert_rc "an unreadable file exits 3" 3
printf '{"schema":"pb-evals/1","runs":[{"scenario":"nope","arm":"with","label":"n.with.1","status":"graded","notes":[],"checks":[]}]}' > "$D/none.json"
run node "$OC" "$D/none.json"
assert_rc "a result with no surface.json exits 3" 3
t_summary
