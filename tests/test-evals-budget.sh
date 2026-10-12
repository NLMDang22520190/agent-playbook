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

echo "AC5.1 --max-cost 1.3 with costs 0.6 + 0.6 + 0.6 (v0.23.2 AC13: was cap 1.0; with the estimate rule 0.6 + 0.6 >= 1.0 would skip E3)"
go --cmd "bash $A/c06.sh" --scenarios E1,E3,E8 --max-cost 1.3
RC_BUD="$RC"
if ran E1 && ran E3; then t_ok "AC5.1 the first two scenarios run (E1, E3)"; else t_bad "AC5.1 the first two scenarios run (E1, E3)" "$(ls "$REC")"; fi
if ran E8; then t_bad "AC5.1 the third scenario (E8) is not run" "adapter ran for E8"; else t_ok "AC5.1 the third scenario (E8) is not run"; fi
assert_eq "AC5.1 E1 has its COST line (0.6)" "1" "$(printf '%s\n' "$OUT" | grep -Ec '^E1 COST 0?\.60*$')"
assert_eq "AC5.1 E3 has its COST line (0.6)" "1" "$(printf '%s\n' "$OUT" | grep -Ec '^E3 COST 0?\.60*$')"
assert_eq "AC5.1 exactly one SKIPPED line" "1" "$(printf '%s\n' "$OUT" | grep -c ' SKIPPED ')"
if printf '%s\n' "$OUT" | grep -E '^E8 SKIPPED ' | grep -Eq 'budget: spent 1\.20* \+ estimate 0?\.60* >= cap 1\.30*($|[^0-9.])'; then t_ok "AC13.1 the line 'E8 SKIPPED ... budget: spent 1.2 + estimate 0.6 >= cap 1.3'"; else t_bad "AC13.1 the line 'E8 SKIPPED ... budget: spent 1.2 + estimate 0.6 >= cap 1.3'" "$(printf '%s\n' "$OUT" | grep -E 'SKIPPED|budget')"; fi
assert_eq "AC5.1 E8 has no PASS/FAIL/MANUAL grader lines" "0" "$(printf '%s\n' "$OUT" | grep -Ec '^E8 (PASS|FAIL|MANUAL) ')"
assert_file "AC5.1 the results file was written" "$WR/results.md"
assert_eq "AC5.1 the summary row of E8 is '| E8 | SKIPPED | - | - |'" "| E8 | SKIPPED | - | - |" "$(row_of "$WR/results.md" E8)"
assert_eq "AC5.1 E1 summary row is a normal row (cost 0.6)" "0.6" "$(cost_cell "$WR/results.md" E1 | sed 's/^0*\./0./; s/0*$//')"
assert_not_contains "AC5.1 E1 is not marked SKIPPED in the results" "$(row_of "$WR/results.md" E1)" "SKIPPED"
assert_not_contains "AC5.1 E3 is not marked SKIPPED in the results" "$(row_of "$WR/results.md" E3)" "SKIPPED"
case "$RC_BUD" in 0|1) t_ok "AC5.1 skipping does not make the exit 2 or 4" ;; *) t_bad "AC5.1 skipping does not make the exit 2 or 4" "exit $RC_BUD" ;; esac
assert_eq "AC5.1 skipping does not change the exit code (same as the baseline run)" "$BASE_RC" "$RC_BUD"

echo "AC5.1 the sum of spent + estimate reaches USD exactly (v0.23.2 AC13: was cap 1.2; now 1.8 = 1.2 spent + 0.6 estimate)"
go --cmd "bash $A/c06.sh" --scenarios E1,E3,E8 --max-cost 1.8
if ran E1 && ran E3 && ! ran E8; then t_ok "AC13.1 spent + estimate == cap (1.2 + 0.6 vs 1.8) counts as reached: the third scenario is skipped"; else t_bad "AC13.1 spent + estimate == cap counts as reached" "ran: $(ls "$REC" | tr '\n' ' ')"; fi
assert_eq "AC13.1 ... with the SKIPPED line for E8" "1" "$(printf '%s\n' "$OUT" | grep -c '^E8 SKIPPED ')"

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
go --cmd "bash $A/mix.sh" --scenarios E1,E3,E8 --max-cost 1.3   # v0.23.2 AC13: was 1.0; E8 now needs spent 0.6 + estimate 0.6 < cap
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
# v0.23.2 AC13: 0.6 spent + 0.6 estimate >= 0.75, so E3 is skipped by the estimate rule; the line names cap 0.75 (not 75)
if ran E1 && ! ran E3; then t_ok "AC11.2 --max-cost .75 is a budget of 0.75: 0.6 + estimate 0.6 reaches it, E3 is skipped"; else t_bad "AC11.2 --max-cost .75 is a budget of 0.75" "ran: $(ls "$REC" | tr '\n' ' ')"; fi
if printf '%s\n' "$OUT" | grep -E '^E3 SKIPPED ' | grep -Eq 'cap 0?\.750*($|[^0-9.])'; then t_ok "AC11.2 the skip line says cap 0.75"; else t_bad "AC11.2 the skip line says cap 0.75" "$(printf '%s\n' "$OUT" | grep SKIPPED)"; fi
for v in . 0. 5. 1.; do
  go --cmd "bash $A/c06.sh" --scenarios E1 --max-cost "$v"
  assert_rc "AC11.2 --max-cost [$v] exits 2" 2
  if ran E1; then t_bad "AC11.2 --max-cost [$v] runs no scenario" "adapter ran"; else t_ok "AC11.2 --max-cost [$v] runs no scenario"; fi
done

echo "v0.23.2 AC13 --max-cost stops before a scenario that would pass the cap (estimate = the largest cost seen so far)"
# mk_pc NAME COST_E1 COST_E3 COST_OTHER -> an adapter whose reported cost depends on the scenario (E1 has "subtract" in
# its prompt, E3 has "divide", every other scenario is "other"); an empty cost means the transcript reports none
mk_pc() {
  mk_adapter "$1" "$GOOD_BODY
case \"\$P\" in
  *subtract*) CST='$2' ;;
  *divide*) CST='$3' ;;
  *) CST='$4' ;;
esac
echo '$INIT'
if [ -n \"\$CST\" ]; then
  echo '{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"total_cost_usd\":'\"\$CST\"',\"result\":\"Weight: Lite.\"}'
else
  echo '{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"result\":\"Weight: Lite.\"}'
fi"
}
# skipline E KEY-REGEX -> 0 when "<E> SKIPPED ..." has a part matching KEY-REGEX
skipline() { printf '%s\n' "$OUT" | grep -E "^$1 SKIPPED " | grep -Eq "$2"; }

# AC13.1 + AC13.2 first example: 1.0, then 2.5 under cap 3
mk_pc pc1 1.0 2.5 1.0
go --cmd "bash $A/pc1.sh" --scenarios E1,E3,E8 --max-cost 3
if ran E1; then t_ok "AC13.1 cap 3: E1 (cost 1.0) runs"; else t_bad "AC13.1 cap 3: E1 (cost 1.0) runs" "ran: $(ls "$REC" | tr '\n' ' ')"; fi
if ran E3; then t_ok "AC13.1 cap 3: E3 runs (spent 1.0 + estimate 1.0 < 3)"; else t_bad "AC13.1 cap 3: E3 runs (spent 1.0 + estimate 1.0 < 3)" "$(printf '%s\n' "$OUT" | grep -E 'SKIPPED|E3')"; fi
if ran E8; then t_bad "AC13.2 cap 3: E8 is not run (spent 3.5 >= 3)" "adapter ran for E8"; else t_ok "AC13.2 cap 3: E8 is not run (spent 3.5 >= 3)"; fi
assert_eq "AC13.2 cap 3: exactly one SKIPPED line (E8)" "1" "$(printf '%s\n' "$OUT" | grep -c ' SKIPPED ')"
if skipline E8 '(spent 3\.50* of 3|budget: spent 3\.50* \+ estimate)'; then t_ok "AC13.2 the E8 skip line names the spent figure 3.5"; else t_bad "AC13.2 the E8 skip line names the spent figure 3.5" "$(printf '%s\n' "$OUT" | grep SKIPPED)"; fi

# AC13.1 second example: 1.2 and 1.2 under cap 2.0 -> the second scenario is skipped before it runs
mk_pc pc2 1.2 1.2 1.2
go --cmd "bash $A/pc2.sh" --scenarios E1,E3 --max-cost 2.0
if ran E1; then t_ok "AC13.1 cap 2.0: E1 (the first scenario) always runs"; else t_bad "AC13.1 cap 2.0: E1 (the first scenario) always runs" "ran: $(ls "$REC" | tr '\n' ' ')"; fi
if ran E3; then t_bad "AC13.1 cap 2.0: E3 is not run (spent 1.2 + estimate 1.2 >= 2.0)" "adapter ran for E3"; else t_ok "AC13.1 cap 2.0: E3 is not run (spent 1.2 + estimate 1.2 >= 2.0)"; fi
if skipline E3 'budget: spent 1\.20* \+ estimate 1\.20* >= cap 2(\.0*)?($|[^0-9.])'; then t_ok "AC13.1 the line 'E3 SKIPPED ... budget: spent 1.2 + estimate 1.2 >= cap 2'"; else t_bad "AC13.1 the line 'E3 SKIPPED ... budget: spent 1.2 + estimate 1.2 >= cap 2'" "$(printf '%s\n' "$OUT" | grep -E 'SKIPPED|budget')"; fi
assert_eq "AC13.1 the summary row of E3 is '| E3 | SKIPPED | - | - |'" "| E3 | SKIPPED | - | - |" "$(row_of "$WR/results.md" E3)"
assert_not_contains "AC13.1 E1 is a normal row" "$(row_of "$WR/results.md" E1)" "SKIPPED"
case "$RC" in 0|1) t_ok "AC13.1 the estimate skip does not change the exit code class (0 or 1)" ;; *) t_bad "AC13.1 the estimate skip does not change the exit code class (0 or 1)" "exit $RC" ;; esac
SKIP_RC="$RC"
go --cmd "bash $A/pc2.sh" --scenarios E1
assert_eq "AC13.1 the exit code with a skip equals that of E1 run alone" "$RC" "$SKIP_RC"

# the estimate is the LARGEST single cost, not the last or the average: 2.0 then 0.2, cap 4.1
mk_pc pc3 2.0 0.2 0.3
go --cmd "bash $A/pc3.sh" --scenarios E1,E3,E8 --max-cost 4.1
if ran E1 && ran E3; then t_ok "AC13.1 largest estimate: E1 (2.0) and E3 (2.0 + 2.0 < 4.1) run"; else t_bad "AC13.1 largest estimate: E1 and E3 run" "ran: $(ls "$REC" | tr '\n' ' ')"; fi
if ran E8; then t_bad "AC13.1 largest estimate: E8 is skipped (spent 2.2 + largest 2.0 >= 4.1; the last cost 0.2 would let it run)" "adapter ran for E8"; else t_ok "AC13.1 largest estimate: E8 is skipped (spent 2.2 + largest 2.0 >= 4.1)"; fi
if skipline E8 'estimate 20*(\.0*)? >= cap 4\.10*($|[^0-9.])'; then t_ok "AC13.1 the E8 line names estimate 2 (the largest seen)"; else t_bad "AC13.1 the E8 line names estimate 2 (the largest seen)" "$(printf '%s\n' "$OUT" | grep SKIPPED)"; fi

# a scenario with no reported cost does not change the estimate (nor the spent sum)
mk_pc pc4 "" 1.0 0.5
go --cmd "bash $A/pc4.sh" --scenarios E1,E3,E8 --max-cost 2.5
assert_eq "AC13.2 unknown cost first, then 1.0, then 0.5 under cap 2.5: all three run" "3" "$(for e in E1 E3 E8; do ran $e && echo x; done | wc -l | tr -d ' ')"
assert_eq "AC13.2 ... nothing is SKIPPED" "0" "$(printf '%s\n' "$OUT" | grep -c SKIPPED)"
mk_pc pc6 1.0 "" 0.5
go --cmd "bash $A/pc6.sh" --scenarios E1,E3,E8 --max-cost 2.2
if ran E1 && ran E3 && ran E8; then t_ok "AC13.2 1.0, unknown, then E8 under cap 2.2: the unknown scenario added nothing (spent 1.0 + estimate 1.0 < 2.2): all run"; else t_bad "AC13.2 the unknown scenario adds nothing to spent or estimate" "ran: $(ls "$REC" | tr '\n' ' ')"; fi

# the first scenario is never skipped by the estimate (there is none yet)
go --cmd "bash $A/c15.sh" --scenarios E1 --max-cost 0.1
if ran E1; then t_ok "AC13.3 with no earlier cost the first scenario runs even when it will pass a tiny cap"; else t_bad "AC13.3 the first scenario runs" "not run"; fi

echo "v0.23.2 AC13.3 usage text: the cap is a guard, the first scenario can pass it"
go --cmd "bash $A/c06.sh" --scenarios E1 --help
HLP="$OUT"
assert_contains "AC13.3 --help mentions --max-cost" "$HLP" "--max-cost"
assert_contains "AC13.3 --help says the cap is a guard" "$HLP" "guard"
if printf '%s\n' "$HLP" | grep -iE 'first scenario' | grep -qi 'pass'; then t_ok "AC13.3 --help says the first scenario can pass the cap"; else t_bad "AC13.3 --help says the first scenario can pass the cap" "$HLP"; fi
HDR2="$(sed -n '1,30p' "$RUNNER")"
assert_contains "AC13.3 the header comment says the cap is a guard" "$HDR2" "guard"
assert_contains "AC13.3 the header comment names the estimate" "$HDR2" "estimate"
# v0.23.2 lane C review LOW-1: --help prints the whole header comment, including the --clean-env description
assert_contains "LOW-1 --help includes the --clean-env description" "$HLP" "drop every CLAUDE"
assert_contains "LOW-1 --help includes the --clean-env detail (ANTHROPIC_BASE_URL)" "$HLP" "ANTHROPIC_BASE_URL"
assert_contains "LOW-1 --help still includes the guard text" "$HLP" "guard"
assert_contains "LOW-1 --help still includes the estimate text" "$HLP" "estimate"

echo "v0.23.2 lane C review LOW-3: an ERROR scenario that reported a cost still counts it"
# mk_errcost NAME COST_E1 COST_E3: E1 succeeds with COST_E1; E3 reports COST_E3 (empty = none) and then exits 9 (ERROR)
mk_errcost() {
  mk_adapter "$1" "$GOOD_BODY
echo '$INIT'
case \"\$P\" in
  *divide*)
    if [ -n '$3' ]; then echo '{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"total_cost_usd\":$3,\"result\":\"Weight: Lite.\"}'; fi
    exit 9 ;;
esac
echo '{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"total_cost_usd\":$2,\"result\":\"Weight: Lite.\"}'"
}
mk_errcost ec1 0.6 0.6
go --cmd "bash $A/ec1.sh" --scenarios E1,E3,E8 --max-cost 1.5
assert_eq "LOW-3 E3 is an ERROR line" "1" "$(printf '%s\n' "$OUT" | grep -c '^E3 ERROR ')"
if ran E8; then t_bad "LOW-3 E8 is skipped (spent 1.2 incl. the ERROR scenario + estimate 0.6 >= 1.5)" "adapter ran for E8"; else t_ok "LOW-3 E8 is skipped (spent 1.2 incl. the ERROR scenario + estimate 0.6 >= 1.5)"; fi
if skipline E8 'budget: spent 1\.20* \+ estimate 0?\.60* >= cap 1\.50*($|[^0-9.])'; then t_ok "LOW-3 the E8 skip line says spent 1.2 + estimate 0.6"; else t_bad "LOW-3 the E8 skip line says spent 1.2 + estimate 0.6" "$(printf '%s\n' "$OUT" | grep -E 'SKIPPED|E3')"; fi
assert_rc "LOW-3 the exit code stays 4 (harness error)" 4
# an ERROR scenario with no reported cost changes nothing
mk_errcost ec2 0.6 ""
go --cmd "bash $A/ec2.sh" --scenarios E1,E3,E8 --max-cost 1.5
assert_eq "LOW-3 no-cost ERROR: E3 is an ERROR line" "1" "$(printf '%s\n' "$OUT" | grep -c '^E3 ERROR ')"
if ran E8; then t_ok "LOW-3 no-cost ERROR adds nothing: E8 runs (spent 0.6 + estimate 0.6 < 1.5)"; else t_bad "LOW-3 no-cost ERROR adds nothing: E8 runs" "$(printf '%s\n' "$OUT" | grep -E 'SKIPPED|E3')"; fi
assert_eq "LOW-3 no-cost ERROR: nothing is SKIPPED" "0" "$(printf '%s\n' "$OUT" | grep -c SKIPPED)"

echo "AC5.1 usage text"
go --cmd "bash $A/c06.sh" --scenarios E1 --bogus
assert_rc "AC5.1 unknown option still exits 2" 2
HDR="$(sed -n '1,20p' "$RUNNER")"
assert_contains "AC5.1 the header comment of run-evals.sh documents --max-cost" "$HDR" "--max-cost"

t_summary
