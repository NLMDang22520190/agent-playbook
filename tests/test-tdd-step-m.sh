#!/usr/bin/env bash
# Tests for scripts/tdd-step.sh (v0.24.23 lane A, Full), part 7 of 7 (parts: test-tdd-step-g.sh, -h.sh, -i.sh, -k.sh, -l.sh, -j.sh; slice S3 of .agents/handoff/01-spec.md), split off test-tdd-step-j.sh for the local Windows Git Bash time (L-0009):
#   AC4  print mode (no --commit) warns for the same paths as the refusal table of test-tdd-step-j.sh and exits 0
# Shared setup: tdd-step-fixture.sh, tdd-step-d-fixture.sh, tdd-step-g-fixture.sh and tdd-step-j-fixture.sh. Rows that need a real exec bit are skipped where the file system has none (can_exec_f).
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/tdd-step-fixture.sh"
. "$(dirname "$0")/tdd-step-d-fixture.sh"
. "$(dirname "$0")/tdd-step-g-fixture.sh"
. "$(dirname "$0")/tdd-step-j-fixture.sh"

# ---------------------------------------------------------------------------------------------------------------
echo "AC4 print mode (--baseline without --commit): a warning for each such path, exit 0, nothing committed"
xprint "AC4 print row 1 new path, staged +x"        false new  644 plus yes
xprint "AC4 print row 3 tracked 100644, staged +x"  false t644 644 plus yes
xprint "AC4 print control: a path staged 100644"    false new  644 plain no
xprint "AC4 print control: an untracked file"       false new  644 untracked no
if can_exec_f; then
  xprint "AC4 print row 4 tracked 100755, staged -x" false t755 755 minus yes
  xprint "AC4 print row 5 new path, staged +x"      true  new  644 plus yes
  xprint "AC4 print control: new path, staged +x, executable on disk (row 6)" true new 755 plus no
  xprint "AC4 print control: an untracked file, disk 755 (no index entry, no warning)" true new 755 untracked no
else
  t_skip 20 "AC4 print rows that need an exec bit (the file system has none)"
fi

t_summary
