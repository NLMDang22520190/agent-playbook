#!/usr/bin/env bash
# Tests for tests/run-all.sh: job pool (#6 AC6.1-AC6.3). Runs a copy of run-all.sh in a fake tree
# with timed stand-in suites; each suite records when it starts and ends.
. "$(dirname "$0")/lib.sh"

# mk_tree DIR -> DIR/tests/run-all.sh + DIR/evals/run-checks.sh (stub) + suites a..e
# Suite a sleeps 2 s; b..e sleep 0.3 s. Each writes start/end lines to DIR/log and tracks concurrency.
mk_tree() {
  local d="$1" n s
  mkdir -p "$d/tests" "$d/evals" "$d/run"
  cp "$PB_ROOT/tests/run-all.sh" "$d/tests/run-all.sh"
  printf '#!/usr/bin/env bash\necho "run-checks: all ok"\n' > "$d/evals/run-checks.sh"
  for n in a b c d e; do
    s=0.3; [ "$n" = a ] && s=2
    cat > "$d/tests/test-$n.sh" <<SUITE
#!/usr/bin/env bash
mkdir "$d/run/$n"
c=0; for x in "$d"/run/*; do [ -e "\$x" ] && c=\$((c + 1)); done
echo "\$c" >> "$d/conc"
echo "start $n" >> "$d/log"
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
D="$(mk_tmp)"; mk_tree "$D"
TD="$(mk_tmp)"
run env PB_JOBS=2 TMPDIR="$TD" bash "$D/tests/run-all.sh"
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
run env PB_JOBS=2 FAIL_d=1 bash "$D/tests/run-all.sh"
assert_rc "AC6.3 a failing suite -> exit 1" 1
assert_contains "AC6.3 failing run ends with FAILURES" "$OUT" "FAILURES"

D="$(mk_tmp)"; mk_tree "$D"
run env PB_JOBS=x bash "$D/tests/run-all.sh"
assert_rc "AC6.3 invalid PB_JOBS still runs (exit 0)" 0
max="$(sort -n "$D/conc" | tail -n 1)"
assert_eq "AC6.3 invalid PB_JOBS falls back to 1 at a time" "1" "$max"

D="$(mk_tmp)"; mk_tree "$D"
run env -u PB_JOBS bash "$D/tests/run-all.sh"
max="$(sort -n "$D/conc" | tail -n 1)"
if [ -n "$max" ] && [ "$max" -ge 2 ] && [ "$max" -le 4 ]; then t_ok "AC6.3 default runs several suites at once, at most 4 (max $max)"
else t_bad "AC6.3 default runs several suites at once, at most 4" "max concurrency $max"; fi

t_summary
