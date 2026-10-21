#!/usr/bin/env bash
# Shared helpers of tests/test-tdd-step-g.sh, -h.sh, -i.sh, -k.sh and -l.sh (v0.24.23 lane A, the branch check and the safe undo; five suites so that none is the floor of a CI shard, L-0009):
# refs, tip, headref, s7, red_any, allcount, gprep, stubdir, run_red_p, the fault-injection stubs (AWK_STUB, SORT_STUB, SRREAD_STUB, SRWRITE_STUB, UPDREF_STUB) and the hooks (HK_*).
# Source it after lib.sh, tdd-step-fixture.sh and tdd-step-d-fixture.sh. It is not a suite: run-all.sh only starts tests/test-*.sh.
SAVEP="$PATH"
# ---------------------------------------------------------------------------------------------------------------
# helpers (all read the globals R, MAIN, H0, N0, E0, REFS0, IDXF that gprep and prep set)
refs()    { git -C "$1" for-each-ref --format='%(refname) %(objectname)' refs/heads; }
tip()     { git -C "$R" rev-parse --verify -q "refs/heads/$1" 2>/dev/null || echo none; }
headref() { git -C "$R" symbolic-ref -q HEAD 2>/dev/null || echo detached; }
s7()      { printf '%s' "${1:0:7}"; }
red_any() { git -C "$R" log --all --format=%s | grep -F 'test(red)'; true; }
allcount() { git -C "$R" rev-list --all --count; }
# gprep MODE [PRE] -> R with a branch "existing" at init and MAIN one empty commit (c2) ahead of it; PRE (a snippet) runs in R first; then as prep (tests/n.test.js untracked, BL, H0, N0, IDXF)
gprep() {
  local mode="$1" pre="${2:-:}"
  R="$(fresh)"; BL=""
  ( cd "$R" && git branch existing && git commit -q --allow-empty -m c2 && eval "$pre" )
  if [ "$mode" = baseline ]; then dirty "$R"; BL="$(snap "$R")"; fi
  printf 'test("n", () => {});\n' > "$R/tests/n.test.js"
  H0="$(head_of "$R")"; N0="$(count_of "$R")"; IDXF="$(mk_tmp)/index.copy"
  MAIN="$(git -C "$R" symbolic-ref --short HEAD 2>/dev/null)"; E0="$(git -C "$R" rev-parse existing)"; REFS0="$(refs "$R")"
}
# stubdir TOOL TEXT -> a dir holding an executable TOOL made from TEXT (@REAL@ = the real tool, resolved now; @CNT@ = a counter file in that dir)
stubdir() {
  local d t real; d="$(mk_tmp)"; real="$(command -v "$1")"; t="${2//@REAL@/$real}"; t="${t//@CNT@/$d/cnt}"
  printf '%s\n' "$t" > "$d/$1"; chmod +x "$d/$1"; printf '%s\n' "$d"
}
# run_red_p STUBDIR FLAG CMD... -> run_red with STUBDIR first on PATH (only the tdd-step run sees it)
run_red_p() { local d="$1"; shift; PATH="$d:$SAVEP"; run_red "$@"; PATH="$SAVEP"; }

# the stubs: fault injection at one call, the real tool otherwise
AWK_STUB='#!/bin/sh
"@REAL@" "$@"; rc=$?
pat="$(cat "@CNT@.pat")"
case "$*" in *"$pat"*)
  n="$(cat "@CNT@" 2>/dev/null || echo 0)"; n=$((n + 1)); echo "$n" > "@CNT@"
  if [ "$n" -eq @FIRE@ ]; then exit 9; fi ;;
esac
exit $rc'
SORT_STUB='#!/bin/sh
"@REAL@" "$@"; rc=$?
a=""; b=""; for x in "$@"; do a="$b"; b="$x"; done
case "$a" in */expected) case "$b" in */got) : > "@CNT@"; exit 9 ;; esac ;; esac
exit $rc'
SRREAD_STUB='#!/bin/sh
case "${1:-}" in symbolic-ref)
  case "$*" in *" refs/"*) ;; *)
    n="$(cat "@CNT@" 2>/dev/null || echo 0)"; n=$((n + 1)); echo "$n" > "@CNT@"
    if [ "$n" -ge @FROM@ ]; then exit @RC@; fi ;;
  esac ;;
esac
exec "@REAL@" "$@"'
SRWRITE_STUB='#!/bin/sh
case "${1:-}" in symbolic-ref) case "$*" in *" refs/"*) echo "stub: symbolic-ref write refused" >&2; exit 1 ;; esac ;; esac
exec "@REAL@" "$@"'
UPDREF_STUB='#!/bin/sh
case "${1:-}" in update-ref) echo "stub: update-ref refused" >&2; exit 1 ;; esac
exec "@REAL@" "$@"'

# the hooks
HK_MERGE2="$(mkhook merge2 'touch .git/mg2-done' 'pre=$(git rev-parse HEAD^)' 'cur=$(git rev-parse HEAD)' 't=$(git rev-parse "HEAD^{tree}")' \
  'c=$(git commit-tree "$t" -p "$pre" -p "$cur" -m merged)' 'git update-ref HEAD "$c"')"
HK_EXIST="$(mkhook h1 'git checkout -q existing')"
# the same, a post-commit hook that first records the commit C it runs for in .git/csha (the end state of a hook that switches to another branch names C)
HK_EXISTC="$(mkhook h1c 'git rev-parse HEAD > .git/csha' 'git checkout -q existing')"
HK_NEWB="$(mkhook h2 'git checkout -q -b newb')"
HK_BRF="$(mkhook h3 'git branch -f existing HEAD')"
HK_BRNEW="$(mkhook h4 'git branch extra')"
HK_BRDEL="$(mkhook h5 'git branch -D existing')"
HK_DETACH="$(mkhook h6 'git checkout -q --detach')"
HK_NOOP="$(mkhook h7 'true')"

# a2_lost TAG -> the message of a hook that switched HEAD to another branch and so took the role's files out of the work tree (review round 1, finding 1, decision D3):
# exit 3, never "nothing committed" or "the work tree is kept", and it names C (the commit the hook ran for, read from .git/csha), C's parent (the pre-run HEAD) and a
# recovery line "git checkout C -- ."
a2_lost() {
  local c l; c="$(cat "$R/.git/csha" 2>/dev/null)"
  assert_eq "$1: the hook ran (it recorded C)" "yes" "$([ -n "$c" ] && echo yes || echo no)"
  assert_rc "$1: exit 3" 3
  assert_not_contains "$1: does not say nothing committed" "$(lower "$OUT")" "nothing committed"
  assert_not_contains "$1: does not say the work tree is kept" "$(lower "$OUT")" "the work tree is kept"
  assert_contains "$1: the message names C" "$OUT" "$(s7 "$c")"
  # the "- git: <sha>+dirty" line of the evidence block shows the pre-run HEAD anyway: it does not count
  assert_contains "$1: the message names the parent of C (the pre-run HEAD)" "$(printf '%s\n' "$OUT" | grep -v '^- git: ')" "$(s7 "$H0")"
  l="$(printf '%s\n' "$OUT" | grep -F -- ' -- .')"
  assert_contains "$1: a recovery line git checkout C -- ." "$l" "git checkout"
  assert_contains "$1: that recovery line names C" "$l" "$(s7 "$c")"
}
# wasnow TAG REF OLD NEW -> a line of the exit-3 message reads exactly "REF: was OLD, now NEW" (old first; "none" = no such branch; the shas in full as the undo read them)
wasnow() {
  local l; l="$(printf '%s\n' "$OUT" | grep -F "$2: was ")"
  assert_contains "$1: a line reads $2: was OLD, now NEW (old first)" "$l" "$2: was $3, now $4"
}
