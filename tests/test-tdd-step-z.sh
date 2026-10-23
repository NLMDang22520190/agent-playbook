#!/usr/bin/env bash
# Tests for scripts/tdd-step.sh (v0.24.28 lane T, Lite; spec 01-spec.md AC2):
#   A  a normal red --commit run asks git status only for what it needs: the nested repository check reuses the output of the first (pre-check) git status instead of running
#      a second, read-only one. A git shim counts the status calls: 2 on the default path, 3 with --baseline (the snapshot after the test command asks once more).
# Shared setup: tdd-step-fixture.sh, tdd-step-d-fixture.sh and tdd-step-g-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/tdd-step-fixture.sh"
. "$(dirname "$0")/tdd-step-d-fixture.sh"
. "$(dirname "$0")/tdd-step-g-fixture.sh"

# GITSHIM_COUNT_STATUS: one line in @CNT@ per git status call (global options such as -c are skipped), then the real git
GITSHIM_COUNT_STATUS='#!/bin/sh
sub=""; skip=0
for a in "$@"; do
  if [ "$skip" = 1 ]; then skip=0; continue; fi
  case "$a" in -c) skip=1 ;; -*) ;; *) sub="$a"; break ;; esac
done
if [ "$sub" = status ]; then echo x >> "@CNT@"; fi
exec "@REAL@" "$@"'

echo "A a normal red --commit run makes exactly N git status calls (one fewer than before)"
if can_exec; then
  for MODE in default baseline; do
    want=2; [ "$MODE" = baseline ] && want=3
    T="A git status calls ($MODE)"
    gprep "$MODE"; D="$(stubdir git "$GITSHIM_COUNT_STATUS")"
    run_red_p "$D" --commit sh -c 'exit 1'
    assert_rc "$T: exit 0" 0
    assert_contains "$T: commits (RED=)" "$OUT" "RED="
    assert_eq "$T: exactly $want status calls" "$want" "$(wc -l < "$D/cnt" | tr -d ' ')"
  done
else
  t_skip 6 "A git status calls (the file system cannot make a shim executable)"
fi

t_summary
