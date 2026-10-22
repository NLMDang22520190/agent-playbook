#!/usr/bin/env bash
# Shared helpers of tests/test-tdd-step-r.sh, -s.sh and -t.sh (v0.24.24 lane A, slice S1: the lost-work decision of tdd-step.sh, spec AC0-AC4):
# recovery_line, d_end, lost_unknown, ROFF, the hooks (HK_MIXED, HK_TOP, HK_AMEND_LOST, HK_AMEND_KEEP) and the git shims (GITSHIM_REPORT, GITSHIM_DIFF).
# Source it after lib.sh, tdd-step-fixture.sh, tdd-step-d-fixture.sh, tdd-step-g-fixture.sh and tdd-step-n-fixture.sh. It is not a suite: run-all.sh only starts tests/test-*.sh.

# recovery_line -> the lines of the message that hold " -- ." (the recovery line git checkout C -- .)
recovery_line() { printf '%s\n' "$OUT" | grep -F -- ' -- .'; true; }
# PRE snippet of gprep: reflogs off (core.logAllRefUpdates=false and no .git/logs), so that find_c cannot read C from the reflog
ROFF='git config core.logAllRefUpdates false && rm -rf .git/logs'
# d_end TAG -> the end state of the undo of a DETACHED run: HEAD detached again at the pre-run HEAD, every branch as before, the index file restored, nothing committed
d_end() {
  assert_eq "$1: HEAD is detached again" "detached" "$(headref)"
  assert_eq "$1: HEAD is at the pre-run HEAD" "$H0" "$(head_of "$R")"
  assert_eq "$1: every branch tip is as before" "$REFS0" "$(refs "$R")"
  assert_eq "$1: the index file is restored byte for byte" "same" "$(same_idx)"
  assert_eq "$1: no test(red) commit reachable from any ref" "" "$(red_any)"
  assert_not_contains "$1: no RED= line" "$OUT" "RED="
}
# end_state TAG DETACHED -> a2_end (attached run) or d_end (detached run)
end_state() { if [ "$2" = detached ]; then d_end "$1"; else a2_end "$1"; fi; }
# lost_unknown TAG -> a lost run whose C cannot be told: exit 3, never "nothing committed" or "the work tree is kept", the recovery text is "look in git reflog HEAD", the parent is named
lost_unknown() {
  assert_rc "$1: exit 3" 3
  assert_not_contains "$1: does not say nothing committed" "$(lower "$OUT")" "nothing committed"
  assert_not_contains "$1: does not say the work tree is kept" "$(lower "$OUT")" "the work tree is kept"
  assert_contains "$1: the recovery text says to look in git reflog HEAD" "$(lower "$OUT")" "git reflog head"
  assert_contains "$1: the message names the parent (the pre-run HEAD)" "$(printf '%s\n' "$OUT" | grep -v '^- git: ')" "$(s7 "$H0")"
}

# post-commit hooks. Each records C (the commit it runs for) in .git/csha first, as HK_EXISTC does.
# a MIXED reset: the commit is gone, the index is the parent's, the files stay on disk
HK_MIXED="$(mkhook s1 'git rev-parse HEAD > .git/csha' 'git reset -q HEAD~1')"
# commits ONCE on top of C (a marker file stops the re-run of the hook by its own commit; N5), the judged files stay unchanged on disk
HK_TOP="$(mkhook s2 '[ -e .git/top-done ] && exit 0' 'touch .git/top-done' 'git rev-parse HEAD > .git/csha' 'git commit -q --allow-empty -m top')"
# amends C once so that its tree differs from the judged one (HEAD stays a single commit on the pre-run HEAD) and leaves the CHANGED file in the work tree
HK_AMEND_LOST="$(mkhook s3 '[ -e .git/am-done ] && exit 0' 'touch .git/am-done' 'git rev-parse HEAD > .git/csha' 'printf "changed\n" > tests/n.test.js' 'git add tests/n.test.js' 'git commit -q --amend --no-edit')"
# the same amend, then the judged content is put back in the work tree: nothing is lost, the commit just differs
HK_AMEND_KEEP="$(mkhook s4 '[ -e .git/am-done ] && exit 0' 'touch .git/am-done' 'git rev-parse HEAD > .git/csha' 'printf "changed\n" > tests/n.test.js' 'git add tests/n.test.js' 'git commit -q --amend --no-edit' 'printf "test(\"n\", () => {});\n" > tests/n.test.js')"

# GITSHIM_REPORT: runs the real git; for git commit it rewrites the sha of the report line "[branch abc1234] subject" to the one in .git/xsha (read in the repo) and keeps the exit code
GITSHIM_REPORT='#!/bin/sh
sub=""; skip=0
for a in "$@"; do
  if [ "$skip" = 1 ]; then skip=0; continue; fi
  case "$a" in -c) skip=1 ;; -*) ;; *) sub="$a"; break ;; esac
done
if [ "$sub" != commit ]; then exec "@REAL@" "$@"; fi
out="$("@REAL@" "$@")"; rc=$?
repl="$(cat .git/xsha 2>/dev/null)"
printf "%s\n" "$out" | sed "s/ [0-9a-f]\{7,\}\] / $repl] /"
exit $rc'
# GITSHIM_DIFF: once the post-commit hook ran (.git/csha exists), every git call that compares the work tree or the index (diff without --name-only, diff-files, diff-index, status) fails with 129
GITSHIM_DIFF='#!/bin/sh
sub=""; skip=0
for a in "$@"; do
  if [ "$skip" = 1 ]; then skip=0; continue; fi
  case "$a" in -c) skip=1 ;; -*) ;; *) sub="$a"; break ;; esac
done
if [ -f .git/csha ]; then
  case "$sub" in
    diff) case "$*" in *--name-only*) ;; *) echo "stub: git $sub failed" >&2; exit 129 ;; esac ;;
    diff-files | diff-index | status) echo "stub: git $sub failed" >&2; exit 129 ;;
  esac
fi
exec "@REAL@" "$@"'
