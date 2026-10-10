#!/usr/bin/env bash
# Tests for tests/lib.sh skip counting (#4 AC4.1, AC4.2). Each case runs a tiny suite in its own process.
. "$(dirname "$0")/lib.sh"

# suite BODY -> runs a script that sources lib.sh, runs BODY, then t_summary; sets OUT and RC
suite() {
  local f; f="$(mk_tmp)/test-demo.sh"
  printf '. "%s/tests/lib.sh"\n%s\nt_summary\n' "$PB_ROOT" "$1" > "$f"
  run bash "$f"
}

echo "tests/lib.sh t_skip / t_summary"
suite 't_ok one; t_ok two'
assert_rc "AC4.2 no skips, no failures -> exit 0" 0
assert_contains "AC4.2 no skips: summary unchanged" "$OUT" "test-demo.sh: 2 passed, 0 failed"
assert_not_contains "AC4.2 no skips: no 'skipped' word" "$OUT" "skipped"

suite 't_ok one; t_skip 6 "slash is writable"; t_skip 1 "no timeout"'
assert_rc "AC4.2 skips are not failures -> exit 0" 0
assert_contains "AC4.2 summary counts skipped assertions" "$OUT" "test-demo.sh: 1 passed, 0 failed, 7 skipped"
assert_contains "AC4.1 skip line names the reason" "$OUT" "slash is writable"
assert_eq "AC4.1 one '  skip ' line per t_skip call" "2" "$(printf '%s\n' "$OUT" | grep -c '^  skip ')"
assert_contains "AC4.1 skip line shows the count" "$(printf '%s\n' "$OUT" | grep 'slash is writable')" "6"

suite 't_bad broken; t_skip 2 "x"'
assert_rc "AC4.2 a failure with skips still exits 1" 1
assert_contains "AC4.2 failure summary with skips" "$OUT" "test-demo.sh: 0 passed, 1 failed, 2 skipped"

t_summary
