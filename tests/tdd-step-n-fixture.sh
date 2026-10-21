#!/usr/bin/env bash
# Shared helpers of tests/test-tdd-step-n.sh, -o.sh and -p.sh (v0.24.23 lane A, review fix round 1; three suites so that none takes more than about 10 s on Linux, 350 s weighted for Windows):
# the hooks (HK_DETX, HK_BRFX, HK_ATPREC) and the fault-injection stubs (XBGIT_STUB, XBSORT_STUB).
# Source it after lib.sh, tdd-step-fixture.sh, tdd-step-d-fixture.sh and tdd-step-g-fixture.sh. It is not a suite: run-all.sh only starts tests/test-*.sh.

# pre-commit hooks that change a ref and then fail git commit
HK_DETX="$(mkhook n1 'git checkout -q --detach existing' 'exit 1')"
HK_BRFX="$(mkhook n2 'git branch -f existing HEAD' 'exit 1')"
# post-commit hook: records C, then attaches HEAD to the branch "atpre" (the setup puts it on the pre-run HEAD)
HK_ATPREC="$(mkhook n3 'git rev-parse HEAD > .git/csha' 'git checkout -q atpre')"

# XBGIT_STUB: fault injection in a git call of xbit_paths. @WHAT@ = lsfiles (the FIRE-th "git ls-files -s -z" after the scratch index was read: 1 = the read of the
# scratch index before git commit, 2 = the real index, 3 = the scratch index again) or lstree (the FIRE-th "git ls-tree -r -z HEAD"). The stub runs the real
# git, writes the correct output, then exits 9. It never fires for the role gate (the marker file @CNT@.rt is made by git read-tree, which the gate does not run).
XBGIT_STUB='#!/bin/sh
case "${1:-}" in
  read-tree) : > "@CNT@.rt" ;;
  ls-files)
    if [ "@WHAT@" = lsfiles ] && [ "$*" = "ls-files -s -z" ] && [ -f "@CNT@.rt" ]; then
      n="$(cat "@CNT@" 2>/dev/null || echo 0)"; n=$((n + 1)); echo "$n" > "@CNT@"
      if [ "$n" -eq @FIRE@ ]; then "@REAL@" "$@"; exit 9; fi
    fi ;;
  ls-tree)
    if [ "@WHAT@" = lstree ] && [ "$*" = "ls-tree -r -z HEAD" ]; then
      n="$(cat "@CNT@" 2>/dev/null || echo 0)"; n=$((n + 1)); echo "$n" > "@CNT@"
      if [ "$n" -eq @FIRE@ ]; then "@REAL@" "$@"; exit 9; fi
    fi ;;
esac
exec "@REAL@" "$@"'
# XBSORT_STUB: the sort of xb.raw (the last step of xbit_paths) writes its correct output, then fails
XBSORT_STUB='#!/bin/sh
"@REAL@" "$@"; rc=$?
last=""; for x in "$@"; do last="$x"; done
case "$last" in */xb.raw) : > "@CNT@"; exit 9 ;; esac
exit $rc'

# review fix round 2 (suite test-tdd-step-q.sh): post-commit hooks that take the role file out of the work tree without attaching HEAD to another branch.
# Each records C (the commit it runs for) in .git/csha first, as HK_EXISTC does.
HK_DETE="$(mkhook q1 'git rev-parse HEAD > .git/csha' 'git checkout -q --detach existing')"
HK_RESET="$(mkhook q2 'git rev-parse HEAD > .git/csha' 'git reset -q --hard HEAD~1')"
# the HEAD reflog is emptied after the switch: C can no longer be read from it (only the tip of the pre-run branch still shows it)
HK_EXPIRE="$(mkhook q3 'git rev-parse HEAD > .git/csha' 'git checkout -q existing' 'git reflog expire --expire=now --all')"
# a2_end TAG -> the end state of the undo after a lost-C run: the pre-run branch is back at the pre-run HEAD, HEAD is attached to it, the index file is restored, no other branch moved
a2_end() {
  assert_eq "$1: $MAIN is back at the pre-run HEAD" "$H0" "$(tip "$MAIN")"
  assert_eq "$1: HEAD is attached to $MAIN" "refs/heads/$MAIN" "$(headref)"
  assert_eq "$1: HEAD is at the pre-run HEAD" "$H0" "$(head_of "$R")"
  assert_eq "$1: every branch tip is as before" "$REFS0" "$(refs "$R")"
  assert_eq "$1: the index file is restored byte for byte" "same" "$(same_idx)"
  assert_eq "$1: no test(red) commit reachable from any ref" "" "$(red_any)"
  assert_not_contains "$1: no RED= line" "$OUT" "RED="
}
