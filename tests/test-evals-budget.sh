#!/usr/bin/env bash
# Tests for evals/run-evals.sh --max-cost USD (v0.22.3 AC5.1): stop running scenarios once the known costs reach USD.
# Never calls a real harness: every run uses --cmd with fake adapters whose transcripts are stream-json lines
# that carry total_cost_usd (see evals-fixture.sh). Exit codes stay as before: 0 green, 1 any FAIL, 4 harness error.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"

# cost_cell RESULTS.md E -> the cell of the "Cost (USD)" column in E's summary row ("" when none)
cost_cell() { awk -F'|' -v e="$2" '
  { c = $2; gsub(/^[ \t]+|[ \t]+$/, "", c) }
  c == e { v = $5; gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit }' "$1" 2>/dev/null; }
# row_of RESULTS.md E -> the summary row of E, whitespace squeezed
row_of() { grep -E "^\| *$2 *\|" "$1" 2>/dev/null | head -n 1 | tr -s ' '; }
ran() { [ -f "$REC/$1.args" ]; }   # did the adapter run for scenario $1?

# an adapter that does the good work of GOOD_BODY, then prints a stream-json transcript with cost $1 (USD) and weight line
mk_cost_adapter() { # NAME COST
  mk_adapter "$1" "$GOOD_BODY
echo '$INIT'
echo '{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"total_cost_usd\":$2,\"result\":\"Done. Weight: Lite (small). Summary: billing calculator.\"}'"
}
mk_cost_adapter c06 0.6
mk_cost_adapter c15 1.5
# a good transcript without a cost (plain text): the cost is unknown
# (GOOD adapter = good.sh from evals-fixture.sh)
# an adapter that fails the work and still reports a cost
mk_adapter cwrong "printf 'function subtract(a, b) { return a + b; }\nmodule.exports.subtract = subtract;\n' >> src/calc.js
echo '$INIT'
echo '{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"total_cost_usd\":0.9,\"result\":\"Weight: Lite. done\"}'"
# an adapter that crashes (harness error)
mk_adapter ccrash 'echo "boom" >&2; exit 9'

go() { # RESULTS-DIR ARGS... -> run the runner into a fresh workroot; sets OUT, RC, WR
  WR="$(mk_tmp)"; : > "$WR/.pb-eval-workroot"; rm -f "$REC"/*
  run bash "$RUNNER" --workroot "$WR" --out "$WR/results.md" "$@"
}

echo "AC5.1 baseline: without --max-cost every scenario runs"
go --cmd "bash $A/c06.sh" --scenarios E1,E3,E8
BASE_RC="$RC"
assert_eq "AC5.1 baseline: three scenarios, three adapter runs" "3" "$(for e in E1 E3 E8; do ran $e && echo x; done | wc -l | tr -d ' ')"
assert_eq "AC5.1 baseline: no SKIPPED line" "0" "$(printf '%s\n' "$OUT" | grep -c SKIPPED)"
case "$BASE_RC" in 0|1) t_ok "AC5.1 baseline: exit is 0 or 1 (never 2 or 4)" ;; *) t_bad "AC5.1 baseline: exit is 0 or 1 (never 2 or 4)" "exit $BASE_RC: $OUT" ;; esac

echo "AC5.1 --max-cost 1.0 with costs 0.6 + 0.6 + 0.6"
go --cmd "bash $A/c06.sh" --scenarios E1,E3,E8 --max-cost 1.0
RC_BUD="$RC"
if ran E1 && ran E3; then t_ok "AC5.1 the first two scenarios run (E1, E3)"; else t_bad "AC5.1 the first two scenarios run (E1, E3)" "$(ls "$REC")"; fi
if ran E8; then t_bad "AC5.1 the third scenario (E8) is not run" "adapter ran for E8"; else t_ok "AC5.1 the third scenario (E8) is not run"; fi
assert_eq "AC5.1 E1 has its COST line (0.6)" "1" "$(printf '%s\n' "$OUT" | grep -Ec '^E1 COST 0?\.60*$')"
assert_eq "AC5.1 E3 has its COST line (0.6)" "1" "$(printf '%s\n' "$OUT" | grep -Ec '^E3 COST 0?\.60*$')"
assert_eq "AC5.1 exactly one SKIPPED line" "1" "$(printf '%s\n' "$OUT" | grep -c ' SKIPPED ')"
if printf '%s\n' "$OUT" | grep -Eq '^E8 SKIPPED budget reached \(spent 1\.20* of 1\.0\)$'; then t_ok "AC5.1 the line 'E8 SKIPPED budget reached (spent 1.2 of 1.0)'"; else t_bad "AC5.1 the line 'E8 SKIPPED budget reached (spent 1.2 of 1.0)'" "$(printf '%s\n' "$OUT" | grep -E 'SKIPPED|budget')"; fi
assert_eq "AC5.1 E8 has no PASS/FAIL/MANUAL grader lines" "0" "$(printf '%s\n' "$OUT" | grep -Ec '^E8 (PASS|FAIL|MANUAL) ')"
assert_file "AC5.1 the results file was written" "$WR/results.md"
assert_eq "AC5.1 the summary row of E8 is '| E8 | SKIPPED | - | - |'" "| E8 | SKIPPED | - | - |" "$(row_of "$WR/results.md" E8)"
assert_eq "AC5.1 E1 summary row is a normal row (cost 0.6)" "0.6" "$(cost_cell "$WR/results.md" E1 | sed 's/^0*\./0./; s/0*$//')"
assert_not_contains "AC5.1 E1 is not marked SKIPPED in the results" "$(row_of "$WR/results.md" E1)" "SKIPPED"
assert_not_contains "AC5.1 E3 is not marked SKIPPED in the results" "$(row_of "$WR/results.md" E3)" "SKIPPED"
case "$RC_BUD" in 0|1) t_ok "AC5.1 skipping does not make the exit 2 or 4" ;; *) t_bad "AC5.1 skipping does not make the exit 2 or 4" "exit $RC_BUD" ;; esac
assert_eq "AC5.1 skipping does not change the exit code (same as the baseline run)" "$BASE_RC" "$RC_BUD"

echo "AC5.1 the sum of known costs reaches USD exactly"
go --cmd "bash $A/c06.sh" --scenarios E1,E3,E8 --max-cost 1.2
if ran E1 && ran E3 && ! ran E8; then t_ok "AC5.1 spent == USD (1.2 of 1.2) counts as reached: the third scenario is skipped"; else t_bad "AC5.1 spent == USD counts as reached" "ran: $(ls "$REC" | tr '\n' ' ')"; fi
assert_eq "AC5.1 ... with the SKIPPED line for E8" "1" "$(printf '%s\n' "$OUT" | grep -c '^E8 SKIPPED budget reached')"

echo "AC5.1 a budget that is not reached runs everything"
go --cmd "bash $A/c06.sh" --scenarios E1,E3,E8 --max-cost 1.9
assert_eq "AC5.1 1.8 spent of 1.9: all three scenarios run" "3" "$(for e in E1 E3 E8; do ran $e && echo x; done | wc -l | tr -d ' ')"
assert_eq "AC5.1 ... and nothing is SKIPPED" "0" "$(printf '%s\n' "$OUT" | grep -c SKIPPED)"
assert_eq "AC5.1 ... and the exit code equals the baseline" "$BASE_RC" "$RC"

echo "AC5.1 the first scenario already exceeds the budget: every later scenario is skipped"
go --cmd "bash $A/c15.sh" --scenarios E1,E3,E8 --max-cost 1.0
if ran E1 && ! ran E3 && ! ran E8; then t_ok "AC5.1 only E1 ran"; else t_bad "AC5.1 only E1 ran" "ran: $(ls "$REC" | tr '\n' ' ')"; fi
assert_eq "AC5.1 one SKIPPED line per skipped scenario (two)" "2" "$(printf '%s\n' "$OUT" | grep -c ' SKIPPED ')"
if printf '%s\n' "$OUT" | grep -Eq '^E3 SKIPPED budget reached \(spent 1\.50* of 1\.0\)$'; then t_ok "AC5.1 E3: spent 1.5 of 1.0"; else t_bad "AC5.1 E3: spent 1.5 of 1.0" "$(printf '%s\n' "$OUT" | grep SKIPPED)"; fi
if printf '%s\n' "$OUT" | grep -Eq '^E8 SKIPPED budget reached \(spent 1\.50* of 1\.0\)$'; then t_ok "AC5.1 E8: spent 1.5 of 1.0"; else t_bad "AC5.1 E8: spent 1.5 of 1.0" "$(printf '%s\n' "$OUT" | grep SKIPPED)"; fi
assert_eq "AC5.1 summary row of E3" "| E3 | SKIPPED | - | - |" "$(row_of "$WR/results.md" E3)"
assert_eq "AC5.1 summary row of E8" "| E8 | SKIPPED | - | - |" "$(row_of "$WR/results.md" E8)"
assert_eq "AC5.1 the order of the scenarios is kept: E1 row first" "E1" "$(grep -E '^\| *E[0-9]+ *\|' "$WR/results.md" | head -n 1 | awk -F'|' '{gsub(/ /, "", $2); print $2}')"
case "$RC" in 0|1) t_ok "AC5.1 exit stays 0 or 1 with skipped scenarios" ;; *) t_bad "AC5.1 exit stays 0 or 1 with skipped scenarios" "exit $RC" ;; esac

echo "AC5.1 unknown costs never trigger the budget"
go --cmd "bash $A/good.sh" --scenarios E1,E3,E8 --max-cost 0.01
assert_eq "AC5.1 plain-text transcripts (cost unknown): all three scenarios run" "3" "$(for e in E1 E3 E8; do ran $e && echo x; done | wc -l | tr -d ' ')"
assert_eq "AC5.1 ... and nothing is SKIPPED" "0" "$(printf '%s\n' "$OUT" | grep -c SKIPPED)"
NOTE_N="$(printf '%s\n' "$OUT" | grep -c 'budget counts known costs only')"
assert_eq "AC5.1 the note is printed once for the run" "1" "$NOTE_N"
if printf '%s\n' "$OUT" | grep -qxF 'note: cost unknown for E1; the budget counts known costs only'; then t_ok "AC5.1 the exact note, naming the first scenario with an unknown cost (E1)"; else t_bad "AC5.1 the exact note, naming E1" "$(printf '%s\n' "$OUT" | grep note)"; fi
assert_eq "AC5.1 every summary row is a normal row" "0" "$(grep -c 'SKIPPED' "$WR/results.md")"
assert_eq "AC5.1 the results show the unknown costs as -" "-" "$(cost_cell "$WR/results.md" E1)"
go --cmd "bash $A/good.sh" --scenarios E1,E3,E8
assert_eq "AC5.1 without --max-cost no note about the budget is printed" "0" "$(printf '%s\n' "$OUT" | grep -c 'budget counts known costs only')"

echo "AC5.1 mixed: an unknown cost adds nothing to the sum"
# E1 unknown, E3 and E8 (separate runs, one adapter each) cannot mix inside one --cmd; use one adapter that picks by prompt
mk_adapter mix "$GOOD_BODY
case \"\$P\" in
  *subtract*) echo '$INIT'; echo '{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"result\":\"Weight: Lite.\"}' ;;
  *) echo '$INIT'; echo '{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"total_cost_usd\":0.6,\"result\":\"Weight: Lite.\"}' ;;
esac"
go --cmd "bash $A/mix.sh" --scenarios E1,E3,E8 --max-cost 1.0
assert_eq "AC5.1 E1 (unknown) + E3 (0.6) + E8 (0.6): all three run, the sum is 1.2 only after E8" "3" "$(for e in E1 E3 E8; do ran $e && echo x; done | wc -l | tr -d ' ')"
assert_eq "AC5.1 ... so nothing is skipped (unknown E1 added 0)" "0" "$(printf '%s\n' "$OUT" | grep -c SKIPPED)"
assert_eq "AC5.1 the note names E1 (the unknown one)" "1" "$(printf '%s\n' "$OUT" | grep -cF 'note: cost unknown for E1; the budget counts known costs only')"
go --cmd "bash $A/mix.sh" --scenarios E1,E3,E8 --max-cost 0.5
if ran E1 && ran E3 && ! ran E8; then t_ok "AC5.1 E1 unknown, E3 0.6 >= 0.5: E8 is skipped, E3 still ran"; else t_bad "AC5.1 E1 unknown, E3 0.6 >= 0.5: E8 is skipped" "ran: $(ls "$REC" | tr '\n' ' ')"; fi
if printf '%s\n' "$OUT" | grep -Eq '^E8 SKIPPED budget reached \(spent 0\.60* of 0\.5\)$'; then t_ok "AC5.1 the spent figure counts known costs only (0.6 of 0.5)"; else t_bad "AC5.1 the spent figure counts known costs only (0.6 of 0.5)" "$(printf '%s\n' "$OUT" | grep -E 'SKIPPED|note')"; fi

echo "AC5.1 the exit code is unchanged by the budget"
go --cmd "bash $A/cwrong.sh" --scenarios E1,E3 --max-cost 0.5
assert_rc "AC5.1 a FAIL in the first scenario and a skip after it: exit 1" 1
assert_eq "AC5.1 ... E3 was skipped" "1" "$(printf '%s\n' "$OUT" | grep -c '^E3 SKIPPED budget reached')"
assert_eq "AC5.1 ... and E1 has its FAIL line" "1" "$(printf '%s\n' "$OUT" | grep '^E1 FAIL ' | head -n 1 | grep -c 'E1 FAIL')"
go --cmd "bash $A/c15.sh" --scenarios E1
ONE_RC="$RC"
go --cmd "bash $A/c15.sh" --scenarios E1,E8 --max-cost 1.0
assert_eq "AC5.1 a skip after a first scenario: the exit code equals that of the same scenario run alone" "$ONE_RC" "$RC"
# harness error: E3 crashes (no cost), E1 costs 1.5, E8 skipped
mk_adapter mixcrash "case \"\$P\" in
  *divide*) echo boom >&2; exit 9 ;;
esac
$GOOD_BODY
echo '$INIT'
echo '{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"total_cost_usd\":1.5,\"result\":\"Weight: Lite.\"}'"
go --cmd "bash $A/mixcrash.sh" --scenarios E3,E1,E8 --max-cost 1.0
assert_rc "AC5.1 a harness error plus a skip: exit 4" 4
assert_eq "AC5.1 ... the crashed scenario is an ERROR line" "1" "$(printf '%s\n' "$OUT" | grep -c '^E3 ERROR ')"
assert_eq "AC5.1 ... E8 was skipped" "1" "$(printf '%s\n' "$OUT" | grep -c '^E8 SKIPPED budget reached')"
go --cmd "bash $A/ccrash.sh" --scenarios E1,E3 --max-cost 5
assert_rc "AC5.1 only crashes under a budget: exit 4" 4
assert_eq "AC5.1 a crash costs nothing, so nothing is skipped" "0" "$(printf '%s\n' "$OUT" | grep -c SKIPPED)"

echo "AC5.1 an invalid USD exits 2 and runs nothing"
for v in 0 0.0 -1 -0.5 abc 1.2.3 "" "1,5" 1e3 " " "\$1" "1 2"; do
  go --cmd "bash $A/c06.sh" --scenarios E1 --max-cost "$v"
  assert_rc "AC5.1 --max-cost [$v] exits 2" 2
  if ran E1; then t_bad "AC5.1 --max-cost [$v] runs no scenario" "adapter ran"; else t_ok "AC5.1 --max-cost [$v] runs no scenario"; fi
done
go --cmd "bash $A/c06.sh" --scenarios E1 --max-cost
assert_rc "AC5.1 --max-cost without a value exits 2" 2
for v in 5 1.0 0.50 2.75 100; do
  go --cmd "bash $A/c06.sh" --scenarios E1 --max-cost "$v"
  case "$RC" in 0|1) t_ok "AC5.1 --max-cost $v is a valid amount (exit 0 or 1)" ;; *) t_bad "AC5.1 --max-cost $v is a valid amount" "exit $RC: $OUT" ;; esac
done

echo "v0.23.1 AC11.2 --max-cost .5 and 0.5 are accepted and the budget works; ., 0. and 5. are rejected"
for v in .5 0.5; do
  go --cmd "bash $A/c06.sh" --scenarios E1,E3,E8 --max-cost "$v"
  case "$RC" in 0|1) t_ok "AC11.2 --max-cost $v is accepted (exit 0 or 1)" ;; *) t_bad "AC11.2 --max-cost $v is accepted (exit 0 or 1)" "exit $RC: $OUT" ;; esac
  if ran E1 && ! ran E3 && ! ran E8; then t_ok "AC11.2 --max-cost $v: the first scenario (0.6) reaches the budget, the others are skipped"; else t_bad "AC11.2 --max-cost $v: the budget works" "ran: $(ls "$REC" | tr '\n' ' ')"; fi
  assert_eq "AC11.2 --max-cost $v: a SKIPPED line for E3" "1" "$(printf '%s\n' "$OUT" | grep -c '^E3 SKIPPED budget reached')"
  assert_eq "AC11.2 --max-cost $v: a SKIPPED line for E8" "1" "$(printf '%s\n' "$OUT" | grep -c '^E8 SKIPPED budget reached')"
done
go --cmd "bash $A/c06.sh" --scenarios E1,E3 --max-cost .75
if ran E1 && ran E3; then t_ok "AC11.2 --max-cost .75 is a budget of 0.75: 0.6 does not reach it, the second scenario runs"; else t_bad "AC11.2 --max-cost .75 is a budget of 0.75" "ran: $(ls "$REC" | tr '\n' ' ')"; fi
for v in . 0. 5. 1.; do
  go --cmd "bash $A/c06.sh" --scenarios E1 --max-cost "$v"
  assert_rc "AC11.2 --max-cost [$v] exits 2" 2
  if ran E1; then t_bad "AC11.2 --max-cost [$v] runs no scenario" "adapter ran"; else t_ok "AC11.2 --max-cost [$v] runs no scenario"; fi
done

echo "AC5.1 usage text"
go --cmd "bash $A/c06.sh" --scenarios E1 --bogus
assert_rc "AC5.1 unknown option still exits 2" 2
HDR="$(sed -n '1,20p' "$RUNNER")"
assert_contains "AC5.1 the header comment of run-evals.sh documents --max-cost" "$HDR" "--max-cost"

t_summary
