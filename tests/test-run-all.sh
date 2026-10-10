#!/usr/bin/env bash
# Tests for tests/run-all.sh: job pool (#6 AC6.1-AC6.3). Runs a copy of run-all.sh in a fake tree
# with timed stand-in suites; each suite records when it starts and ends.
. "$(dirname "$0")/lib.sh"

# guarded SECS CMD... -> runs CMD with a time limit; sets OUT (stdout+stderr) and RC (124 when the limit hit).
# Uses `timeout` when it is on PATH, else a bash watchdog; PB_FORCE_WATCHDOG=1 forces the watchdog (so it is
# testable on every OS without touching PATH). The watchdog polls (no background sleeper to leave behind),
# runs CMD in its own process group (set -m) and, on timeout, kills that group, then CMD itself.
# Output goes to a file, never a pipe, so a leftover grandchild cannot keep the caller waiting.
guarded() {
  local secs="$1" f pid t0 had_m=0; shift
  f="$(mktemp "${TMPDIR:-/tmp}/pbguard.XXXXXX")" || exit 3
  T_TMPS="$T_TMPS $f $f.timeout"
  if [ -z "${PB_FORCE_WATCHDOG:-}" ] && command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@" >"$f" 2>&1 </dev/null; RC=$?
  else
    case $- in *m*) had_m=1 ;; esac
    set -m
    "$@" >"$f" 2>&1 </dev/null &
    pid=$!
    [ "$had_m" = 1 ] || set +m
    t0=$SECONDS
    while kill -0 "$pid" 2>/dev/null; do
      if [ $((SECONDS - t0)) -ge "$secs" ]; then
        : > "$f.timeout"
        kill -TERM -- "-$pid" 2>/dev/null
        command -v pkill >/dev/null 2>&1 && pkill -P "$pid" 2>/dev/null
        kill -TERM "$pid" 2>/dev/null
        sleep 0.2
        kill -KILL -- "-$pid" 2>/dev/null
        kill -KILL "$pid" 2>/dev/null
        break
      fi
      sleep 0.1
    done
    wait "$pid" 2>/dev/null; RC=$?
    [ -e "$f.timeout" ] && RC=124
  fi
  OUT="$(cat "$f")"
  [ "$RC" -eq 124 ] && OUT="$OUT
GUARD: killed after ${secs}s"
  return 0
}

# mk_tree DIR [SLOW] [OTHERS] [NAMES] -> DIR/tests/run-all.sh + DIR/evals/run-checks.sh (stub) + suites (default a..e)
# Suite a sleeps SLOW s (default 2); the others sleep OTHERS s (default 0.3). A suite n whose DIE_n is set kills its wrapper (no exit code written). Each writes start/end lines to DIR/log and tracks concurrency.
mk_tree() {
  local d="$1" slow="${2:-2}" oth="${3:-0.3}" names="${4:-a b c d e}" n s
  mkdir -p "$d/tests" "$d/evals" "$d/run"
  cp "$PB_ROOT/tests/run-all.sh" "$d/tests/run-all.sh"
  printf '#!/usr/bin/env bash\necho "run-checks: all ok"\n' > "$d/evals/run-checks.sh"
  for n in $names; do
    s=$oth; [ "$n" = a ] && s=$slow
    cat > "$d/tests/test-$n.sh" <<SUITE
#!/usr/bin/env bash
mkdir "$d/run/$n"
c=0; for x in "$d"/run/*; do [ -e "\$x" ] && c=\$((c + 1)); done
echo "\$c" >> "$d/conc"
echo "start $n" >> "$d/log"
[ -n "\${DIE_$n:-}" ] && kill -9 \$PPID
sleep $s
echo "end $n" >> "$d/log"
rmdir "$d/run/$n"
echo "suite $n out"
exit \${FAIL_$n:-0}
SUITE
  done
}
line_of() { grep -n -x "$2" "$1/log" | head -n 1 | cut -d: -f1; }   # DIR "start c" -> line number

echo "run-all.sh job pool"
D="$(mk_tmp)"; mk_tree "$D" 6
TD="$(mk_tmp)"
guarded 60 env PB_JOBS=2 TMPDIR="$TD" bash "$D/tests/run-all.sh"
assert_rc "AC6.3 all suites pass -> exit 0" 0
assert_contains "AC6.3 ends with ALL GREEN" "$OUT" "ALL GREEN"
sa="$(line_of "$D" "end a")"; sc="$(line_of "$D" "start c")"
if [ -n "$sa" ] && [ -n "$sc" ] && [ "$sc" -lt "$sa" ]; then t_ok "AC6.2 suite c starts while the slow suite a is still running"
else t_bad "AC6.2 suite c starts while the slow suite a is still running" "log: $(tr '\n' ' ' < "$D/log")"; fi
se="$(line_of "$D" "start e")"
if [ -n "$se" ] && [ "$se" -lt "$sa" ]; then t_ok "AC6.2 the last suite e also starts before a ends"
else t_bad "AC6.2 the last suite e also starts before a ends" "log: $(tr '\n' ' ' < "$D/log")"; fi
max="$(sort -n "$D/conc" | tail -n 1)"
if [ -n "$max" ] && [ "$max" -le 2 ]; then t_ok "AC6.1 at most PB_JOBS=2 suites at once (max $max)"
else t_bad "AC6.1 at most PB_JOBS=2 suites at once" "max concurrency $max"; fi
order="$(printf '%s\n' "$OUT" | grep -E '^== tests/test-' | tr '\n' ' ')"
assert_eq "AC6.3 output in suite order" "== tests/test-a.sh == tests/test-b.sh == tests/test-c.sh == tests/test-d.sh == tests/test-e.sh " "$order"
assert_contains "AC6.3 suite output printed" "$OUT" "suite c out"
left="$(ls -A "$TD" 2>/dev/null)"
assert_eq "AC6.3 temp dir removed" "" "$left"

D="$(mk_tmp)"; mk_tree "$D"
guarded 60 env PB_JOBS=2 FAIL_d=1 bash "$D/tests/run-all.sh"
assert_rc "AC6.3 a failing suite -> exit 1" 1
assert_contains "AC6.3 failing run ends with FAILURES" "$OUT" "FAILURES"

D="$(mk_tmp)"; mk_tree "$D"
guarded 60 env PB_JOBS=x bash "$D/tests/run-all.sh"
assert_rc "AC6.3 invalid PB_JOBS still runs (exit 0)" 0
max="$(sort -n "$D/conc" | tail -n 1)"
assert_eq "AC6.3 invalid PB_JOBS falls back to 1 at a time" "1" "$max"

D="$(mk_tmp)"; mk_tree "$D"
guarded 60 env -u PB_JOBS bash "$D/tests/run-all.sh"
max="$(sort -n "$D/conc" | tail -n 1)"
if [ -n "$max" ] && [ "$max" -ge 2 ] && [ "$max" -le 4 ]; then t_ok "AC6.3 default runs several suites at once, at most 4 (max $max)"
else t_bad "AC6.3 default runs several suites at once, at most 4" "max concurrency $max"; fi

# six equal 2.5 s suites: the first four start well within 2.5 s, so a default of 4 gives exactly 4
D="$(mk_tmp)"; mk_tree "$D" 2.5 2.5 "a b c d e f"
guarded 60 env -u PB_JOBS bash "$D/tests/run-all.sh"
max="$(sort -n "$D/conc" | tail -n 1)"
assert_eq "AC6.3 default job count is exactly 4 (not 3, not 5)" "4" "$max"

echo "run-all.sh survives a suite wrapper that dies without an exit code"
D="$(mk_tmp)"; mk_tree "$D"
guarded 30 env PB_JOBS=1 DIE_b=1 bash "$D/tests/run-all.sh"
assert_rc "AC6.3 a suite that dies without an exit code -> run-all finishes and exits 1" 1
assert_contains "AC6.3 dead-suite run ends with FAILURES" "$OUT" "FAILURES"
assert_contains "AC6.3 suites after the dead one still ran" "$(cat "$D/log" 2>/dev/null)" "end e"

echo "AC5.1 the guard turns a never-ending run-all into a FAIL, on the watchdog path (PB_FORCE_WATCHDOG=1)"
# a copy of run-all whose suite a never exits (sleeps 40 s; the guard must cut it at 3 s)
D="$(mk_tmp)"; mk_tree "$D" 40 0.1 "a b"
t0=$SECONDS
PB_FORCE_WATCHDOG=1 guarded 3 "$BASH" "$D/tests/run-all.sh"
el=$((SECONDS - t0))
assert_eq "AC5.1 watchdog path: a hung run-all is reported as RC 124 (a FAIL), not left running" "124" "$RC"
if [ "$el" -lt 15 ]; then t_ok "AC5.1 watchdog path ends the hung run within the limit (${el}s of a 3 s limit, run-all would take 40 s)"; else t_bad "AC5.1 watchdog path ends the hung run within the limit" "took ${el}s"; fi
assert_contains "AC5.1 the guard says it killed the run" "$OUT" "killed after 3s"
# a run-all that finishes in time is not touched by the watchdog
D="$(mk_tmp)"; mk_tree "$D" 0.2 0.1 "a b"
PB_FORCE_WATCHDOG=1 guarded 20 "$BASH" "$D/tests/run-all.sh"
assert_rc "AC5.1 watchdog path: a healthy run-all finishes normally (exit 0)" 0
assert_contains "AC5.1 watchdog path: the healthy run output is kept" "$OUT" "ALL GREEN"
D="$(mk_tmp)"; mk_tree "$D" 0.2 0.1 "a b"
PB_FORCE_WATCHDOG=1 guarded 20 env FAIL_b=1 "$BASH" "$D/tests/run-all.sh"
assert_rc "AC5.1 watchdog path: a failing run-all keeps its own exit code (1, not 124)" 1

echo "AC5.2 the guard leaves no process behind"
PF="$(mk_tmp)"
PB_FORCE_WATCHDOG=1 guarded 2 "$BASH" -c 'sleep 60 & echo $! > "$1/child"; echo $$ > "$1/self"; wait' x "$PF"
assert_rc "AC5.2 the killed command reports RC 124" 124
sleep 0.5
CH="$(cat "$PF/child" 2>/dev/null)"; SF="$(cat "$PF/self" 2>/dev/null)"
if [ -n "$CH" ] && ! kill -0 "$CH" 2>/dev/null; then t_ok "AC5.2 the killed run's child (sleep 60) is gone"; else t_bad "AC5.2 the killed run's child (sleep 60) is gone" "pid [$CH] still alive or not recorded"; fi
if [ -n "$SF" ] && ! kill -0 "$SF" 2>/dev/null; then t_ok "AC5.2 the killed run itself is gone"; else t_bad "AC5.2 the killed run itself is gone" "pid [$SF] still alive or not recorded"; fi
[ -n "$CH" ] && kill -9 "$CH" 2>/dev/null
# a healthy call must not leave a watchdog sleeper either: this shell has no child processes afterwards
PB_FORCE_WATCHDOG=1 guarded 30 "$BASH" -c 'exit 0'
sleep 0.3
if command -v pgrep >/dev/null 2>&1; then
  KIDS="$(pgrep -P $$ -x sleep 2>/dev/null | tr '\n' ' ')"   # sleepers only: the $(...) subshell itself is a child
  if [ -z "${KIDS// /}" ]; then t_ok "AC5.2 no watchdog sleeper is left running after guarded calls"; else t_bad "AC5.2 no watchdog sleeper is left running after guarded calls" "sleep children of the test shell: $KIDS"; fi
else
  t_skip 1 "'pgrep' not on PATH: the no-leftover-sleeper assertion"
fi

t_summary
