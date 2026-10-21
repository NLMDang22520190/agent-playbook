#!/usr/bin/env bash
# Tests for scripts/tdd-step.sh (v0.24.23 lane A, Full), part 6 of 7 (parts: test-tdd-step-g.sh, -h.sh, -i.sh, -k.sh, -l.sh, -m.sh; slice S3 of .agents/handoff/01-spec.md):
#   AC4  --baseline --commit refuses a path whose staged mode git commit --only would not carry (staged +x on a new or tracked path, staged -x on a tracked 100755 path);
#        the table of the spec row by row, each with its core.filemode and its disk mode; print mode (no --commit) warns for the same paths and exits 0
#        (the print-mode rows are in test-tdd-step-m.sh, split off for the local Windows Git Bash time, L-0009)
#   AC5  the header comment of scripts/tdd-step.sh states the nested-repo limit and the disk-only exec bit limit
# Shared setup: tdd-step-fixture.sh, tdd-step-d-fixture.sh, tdd-step-g-fixture.sh and tdd-step-j-fixture.sh. Cases that already pass on v0.24.22 are named "control" or "unchanged".
# Disk mode: "755" = the file is executable on disk when tdd-step runs, "644" = it is not. Rows that need a real exec bit are skipped where the file system has none (can_exec_f).
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/tdd-step-fixture.sh"
. "$(dirname "$0")/tdd-step-d-fixture.sh"
. "$(dirname "$0")/tdd-step-g-fixture.sh"

. "$(dirname "$0")/tdd-step-j-fixture.sh"

# ---------------------------------------------------------------------------------------------------------------
echo "AC4 --baseline --commit: a staged mode that git commit --only would not carry is refused before the commit (the table, row by row)"
# disk 644 rows do not need a real exec bit when core.filemode=false (git ignores the disk bit); every other row does
xrefuse "AC4 row 1 new path, staged +x"             false new  644 plus
if can_exec_f; then
  xrefuse "AC4 row 2 new path, staged +x"           false new  755 plus
fi
xrefuse "AC4 row 3 tracked 100644, staged +x"       false t644 644 plus
if can_exec_f; then
  xrefuse "AC4 row 4 tracked 100755, staged -x" false t755 755 minus
  xrefuse "AC4 row 5 new path, staged +x"           true  new  644 plus
else
  t_skip 9 "AC4 row 2 (the file system has no exec bit)"
  t_skip 9 "AC4 row 4 (the file system has no exec bit)"
  t_skip 9 "AC4 row 5 (the file system has no exec bit)"
fi

echo "AC4 control: rows that commit as today"
if can_exec_f; then
  xcommit "AC4 row 6 control: new path, staged +x, executable on disk" true new 755 plus 100755
  xcommit "AC4 row 7 control: tracked 100755 chmod -x on disk, edited, nothing staged (the user's intent: 100644)" true t755 644 none 100644
  xcommit "AC4 row 8 control: a path staged 100644" true new 644 plain 100644
else
  t_skip 12 "AC4 rows 6 to 8 (the file system has no exec bit)"
fi
xcommit "AC4 row 8 control: a path staged 100644" false new 644 plain 100644
xcommit "AC4 control: an untracked file, disk 644" false new 644 untracked 100644

# ---------------------------------------------------------------------------------------------------------------
echo "AC5 the header comment of scripts/tdd-step.sh states the two limits"
HDR="$(lower "$(awk 'NR == 1 { next } /^#/ { print; next } { exit }' "$STEP")")"
assert_contains "AC5 the header names the nested repository limit" "$HDR" "nested repo"
assert_contains "AC5 the header says the commit in a nested repository is not detected" "$HDR" "not detected"
assert_contains "AC5 the header says the snapshot records it as unhashable" "$HDR" "unhashable"
assert_contains "AC5 the header names the exec bit" "$HDR" "exec bit"
assert_contains "AC5 the header says only a mode staged in the index is checked" "$HDR" "staged in the index"
assert_contains "AC5 the header names core.filemode=false for the disk-only exec bit" "$HDR" "core.filemode=false"

t_summary
