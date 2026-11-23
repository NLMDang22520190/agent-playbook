#!/usr/bin/env bash
# C5 tests for tests/timing-fixture.sh best_of_ms N MAXMS CMD...: a wall-clock threshold check that retries the timed command
# (best of N) so one slow run on a loaded CI runner does not fail a suite. Deterministic: the clock is overridden (tf_now_ms),
# no sleeps. Results are in globals (the command runs in the current shell): TF_BEST_MS, TF_ATTEMPTS, TF_CMD_RC.
. "$(dirname "$0")/lib.sh"
. "$PB_ROOT/tests/timing-fixture.sh"

CLOCK=0; RUNS=0; DURS=(); CMDRC=0
tf_now_ms() { echo "$CLOCK"; }
# fake timed command: advances the fake clock by the next duration of DURS, counts the run, exits CMDRC
fakecmd() { CLOCK=$(( CLOCK + ${DURS[$RUNS]:-0} )); RUNS=$((RUNS + 1)); return "$CMDRC"; }
reset() { CLOCK=1000; RUNS=0; CMDRC=0; DURS=("$@"); TF_BEST_MS=""; TF_ATTEMPTS=""; TF_CMD_RC=""; }
bom() { local n="$1" max="$2"; shift 2; OUT="$(mktemp "$PB_TMPBASE/pbtest.XXXXXX")"; T_TMPS="$T_TMPS $OUT"; best_of_ms "$n" "$max" "$@" > "$OUT"; RC=$?; SUM="$(cat "$OUT")"; }

echo "C5 first run over the limit, second under"
reset 7000 300 9999
bom 3 5000 fakecmd
assert_rc "C5 second run under the limit passes (exit 0)" 0
assert_eq "C5 two attempts" "2" "$TF_ATTEMPTS"
assert_eq "C5 best is the smaller run" "300" "$TF_BEST_MS"
assert_eq "C5 the command ran twice, no third run" "2" "$RUNS"
assert_contains "C5 the output names the best ms" "$SUM" "300"
assert_contains "C5 the output names the attempts" "$SUM" "attempts=2"

echo "C5 all three over the limit"
reset 7000 6000 5500
bom 3 5000 fakecmd
assert_rc "C5 all over: exit 1" 1
assert_eq "C5 three attempts" "3" "$TF_ATTEMPTS"
assert_eq "C5 best is the minimum of the three" "5500" "$TF_BEST_MS"
assert_eq "C5 the command ran exactly three times" "3" "$RUNS"

echo "C5 the best is the minimum even when it is not the last"
reset 9000 5200 8000
bom 3 5000 fakecmd
assert_rc "C5 minimum in the middle, all over: exit 1" 1
assert_eq "C5 best is 5200" "5200" "$TF_BEST_MS"

echo "C5 first run under the limit"
reset 100 100 100
bom 3 5000 fakecmd
assert_rc "C5 first under: exit 0" 0
assert_eq "C5 exactly one attempt" "1" "$TF_ATTEMPTS"
assert_eq "C5 no wasted re-run" "1" "$RUNS"
assert_eq "C5 best is the first run" "100" "$TF_BEST_MS"

echo "C5 the limit is strict (< MAXMS)"
reset 5000 4999
bom 3 5000 fakecmd
assert_rc "C5 5000 ms is not under 5000, 4999 is: exit 0" 0
assert_eq "C5 two attempts at the boundary" "2" "$TF_ATTEMPTS"

echo "C5 a failing command is not masked"
reset 100 100 100; CMDRC=7
bom 3 5000 fakecmd
if [ "$RC" != 0 ]; then t_ok "C5 non-zero command exit makes best_of_ms fail even when fast"; else t_bad "C5 non-zero command exit makes best_of_ms fail even when fast" "rc=0"; fi
assert_eq "C5 the command's exit status is reported" "7" "$TF_CMD_RC"
assert_eq "C5 a failing command is not retried until it passes" "1" "$RUNS"
assert_contains "C5 the output reports the command failure" "$SUM" "cmd_rc=7"
reset 100 100 100; CMDRC=1
bom 3 5000 fakecmd
assert_eq "C5 exit 1 of the command is also reported separately" "1" "$TF_CMD_RC"
assert_contains "C5 exit 1 of the command shows cmd_rc=1" "$SUM" "cmd_rc=1"
reset 100 100 100
bom 3 5000 fakecmd
assert_eq "C5 a passing command reports TF_CMD_RC 0" "0" "$TF_CMD_RC"

echo "C5 N=1 behaves like a single timed run"
reset 7000 100
bom 1 5000 fakecmd
assert_rc "C5 N=1 over the limit: exit 1" 1
assert_eq "C5 N=1 runs once" "1" "$RUNS"
assert_eq "C5 N=1 one attempt" "1" "$TF_ATTEMPTS"
assert_eq "C5 N=1 best is that run" "7000" "$TF_BEST_MS"
reset 100
bom 1 5000 fakecmd
assert_rc "C5 N=1 under the limit: exit 0" 0

echo "C5 the default N is 3"
reset 9000 9000 9000 9000
bom "" 5000 fakecmd
assert_eq "C5 empty N means 3 attempts" "3" "$TF_ATTEMPTS"

echo "C5 the command runs in the current shell (its globals survive)"
reset 10
setter() { MARK=set; }
bom 3 5000 setter
assert_eq "C5 a global set by the command is visible afterwards" "set" "${MARK:-}"

t_summary
