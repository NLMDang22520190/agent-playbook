#!/usr/bin/env bash
# Tests for tools/ship.sh v0.37 AC10: every step line carries a timestamp and the elapsed seconds, the whole output (stdout and stderr)
# is also written to a log file (default .agents/handoff/ship-<tag>-<YYYYMMDD-HHMMSS>.log in the repo, PB_SHIP_LOG=<file> overrides),
# and a successful ship prints "total time: Ns". Step lines still START with "== ". Spec: docs/v0.37-spec.md AC10.
# Shared setup (fake gh, stubs, fx, sh_run, steps): ship-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/ship-fixture.sh"

TS_RE='^== \[[0-9][0-9]:[0-9][0-9]:[0-9][0-9] \+[0-9]+s\] .'
# step_lines TEXT -> the lines starting with '== '
step_lines() { printf '%s\n' "$1" | grep '^== ' || true; }
# bad_step_lines TEXT -> the '== ' lines that lack the timestamp
bad_step_lines() { step_lines "$1" | grep -Ev "$TS_RE" || true; }

echo "AC10 every step line is '== [HH:MM:SS +Ns] <title>'"
fx
unset PB_SHIP_LOG
sh_run 12 v1.2.3 --yes
assert_rc "AC10 --yes flow exits 0" 0
NSTEP="$(step_lines "$OUT" | grep -c . || true)"
if [ "$NSTEP" -ge 6 ]; then t_ok "AC10 still at least 6 lines start with '== ' ($NSTEP)"; else t_bad "AC10 still at least 6 lines start with '== '" "$NSTEP in: $OUT"; fi
assert_eq "AC10 no '== ' step line lacks the timestamp" "" "$(bad_step_lines "$OUT")"
assert_contains "AC10 the step title is kept after the timestamp" "$(step_lines "$OUT")" "] check PR #12"
assert_contains "AC10 the release step title keeps the tag" "$(step_lines "$OUT")" "] release v1.2.3"
assert_eq "AC10 the flow order is unchanged" "$FULL_YES" "$(steps)"
SECS="$(step_lines "$OUT" | sed -n 's/^== \[[0-9:]* +\([0-9][0-9]*\)s\].*/\1/p' | tr '\n' ' ')"
SORTED="$(printf '%s\n' $SECS | sort -n | tr '\n' ' ')"
assert_eq "AC10 elapsed seconds never go backwards" "$SORTED" "$SECS"
FIRSTSEC="${SECS%% *}"
if [ -n "$FIRSTSEC" ] && [ "$FIRSTSEC" -le 5 ]; then t_ok "AC10 the first step is at most +5s after ship started ($FIRSTSEC)"; else t_bad "AC10 the first step is at most +5s after ship started" "first elapsed = [$FIRSTSEC] in: $OUT"; fi

echo "AC10 the stub steps' own output and the step lines of the dry-run path carry the timestamp too"
fx
unset PB_SHIP_LOG
run_in "$F/repo" bash -c 'printf "y\ny\ny\n" | bash tools/ship.sh 12 v1.2.3' 
# no terminal: ask() refuses, but the steps before it were printed with timestamps
assert_eq "AC10 without --yes: every printed '== ' line has the timestamp" "" "$(bad_step_lines "$OUT")"
if [ "$(step_lines "$OUT" | grep -c . || true)" -ge 1 ]; then t_ok "AC10 without --yes: at least one step line printed"; else t_bad "AC10 without --yes: at least one step line printed" "$OUT"; fi

echo "AC10 default log file: .agents/handoff/ship-<tag>-<YYYYMMDD-HHMMSS>.log in the repo"
fx
unset PB_SHIP_LOG
rm -rf "$F/repo/.agents/handoff"
sh_run 12 v1.2.3 --yes
assert_rc "AC10 default log: exit 0" 0
LOGS="$(ls "$F/repo/.agents/handoff"/ship-v1.2.3-*.log 2>/dev/null || true)"
assert_eq "AC10 default log: exactly one ship-v1.2.3-*.log file" "1" "$(printf '%s\n' "$LOGS" | grep -c . || true)"
LOGBASE="$(basename "$LOGS")"
if printf '%s' "$LOGBASE" | grep -Eq '^ship-v1\.2\.3-[0-9]{8}-[0-9]{6}\.log$'; then t_ok "AC10 default log name is ship-v1.2.3-YYYYMMDD-HHMMSS.log"; else t_bad "AC10 default log name is ship-v1.2.3-YYYYMMDD-HHMMSS.log" "got [$LOGBASE]"; fi
LOGTXT="$(cat "$LOGS" 2>/dev/null || true)"
assert_eq "AC10 the log has the same step lines as the screen output" "$(step_lines "$OUT")" "$(step_lines "$LOGTXT")"
assert_contains "AC10 the log has the final shipped line" "$LOGTXT" "shipped v1.2.3"
assert_contains "AC10 the log has the stubbed release.sh output (stdout of a child step)" "$LOGTXT" "$(printf '%s\n' "$OUT" | grep -v '^==' | head -n 1)"

echo "AC10 another tag names the default log after that tag"
fx
export FAKE_PR=345 FAKE_TAG=v10.20.30
unset PB_SHIP_LOG
sh_run 345 v10.20.30 --yes
assert_rc "AC10 v10.20.30: exit 0" 0
assert_eq "AC10 the log is named after v10.20.30" "1" "$(ls "$F/repo/.agents/handoff"/ship-v10.20.30-*.log 2>/dev/null | grep -c . || true)"

echo "AC10 PB_SHIP_LOG=<file> overrides the path"
fx
rm -rf "$F/repo/.agents/handoff"
CUSTOM="$F/custom dir/my ship.log"
mkdir -p "$F/custom dir"
export PB_SHIP_LOG="$CUSTOM"
sh_run 12 v1.2.3 --yes
unset PB_SHIP_LOG
assert_rc "AC10 PB_SHIP_LOG: exit 0" 0
assert_file "AC10 PB_SHIP_LOG: the log is written to the given file (path with a space)" "$CUSTOM"
assert_eq "AC10 PB_SHIP_LOG: the log has the same step lines as the screen output" "$(step_lines "$OUT")" "$(step_lines "$(cat "$CUSTOM" 2>/dev/null || true)")"
assert_eq "AC10 PB_SHIP_LOG: no default ship-*.log is written as well" "0" "$(ls "$F/repo/.agents/handoff"/ship-*.log 2>/dev/null | grep -c . || true)"

echo "AC10 a successful ship ends with 'total time: Ns'"
fx
export PB_SHIP_LOG="$F/ok.log"
sh_run 12 v1.2.3 --yes
unset PB_SHIP_LOG
assert_rc "AC10 total time: exit 0" 0
TT="$(printf '%s\n' "$OUT" | grep -E '^total time: [0-9]+s$' || true)"
assert_eq "AC10 exactly one 'total time: Ns' line on screen" "1" "$(printf '%s\n' "$TT" | grep -c . || true)"
assert_contains "AC10 'total time: Ns' is in the log" "$(cat "$F/ok.log" 2>/dev/null || true)" "total time: "
assert_contains "AC10 shipped line is still printed" "$OUT" "shipped v1.2.3"
LAST2="$(printf '%s\n' "$OUT" | tail -n 2 | tr '\n' '|')"
case "$LAST2" in
  "shipped v1.2.3|total time: "*s"|"|"total time: "*s"|shipped v1.2.3|") t_ok "AC10 the last two lines are 'shipped vX.Y.Z' and 'total time: Ns' (either order)" ;;
  *) t_bad "AC10 the last two lines are 'shipped vX.Y.Z' and 'total time: Ns' (either order)" "got: $LAST2" ;;
esac

echo "AC10 a refusal (fail()) is logged to the file, with the timestamped steps before it"
fx
export FAKE_GATE_RC=1 FAKE_GATE_MSG="no gate result for this commit (fake reason)"
export PB_SHIP_LOG="$F/refused.log"
sh_run 12 v1.2.3 --yes
unset PB_SHIP_LOG
assert_rc "AC10 refusal: ship exits 1" 1
REFLOG="$(cat "$F/refused.log" 2>/dev/null || true)"
assert_contains "AC10 refusal: the refusal line is in the log" "$REFLOG" "ship refused: release gate: no gate result for this commit (fake reason)"
assert_contains "AC10 refusal: the step lines before it are in the log, timestamped" "$(step_lines "$REFLOG")" "] check PR #12"
assert_eq "AC10 refusal: no untimestamped step line" "" "$(bad_step_lines "$REFLOG")"
assert_not_contains "AC10 refusal: no 'total time' claim in the log" "$REFLOG" "total time:"
assert_not_contains "AC10 refusal: no 'total time' claim on screen" "$OUT" "total time:"

echo "AC10 a usage error writes no log and no timestamped step"
fx
rm -rf "$F/repo/.agents/handoff"
unset PB_SHIP_LOG
sh_run 12
assert_rc "AC10 usage error exits 2" 2
assert_eq "AC10 usage error: no ship log file" "0" "$(ls "$F/repo/.agents/handoff"/ship-*.log 2>/dev/null | grep -c . || true)"

t_summary
