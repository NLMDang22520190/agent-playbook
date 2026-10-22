#!/usr/bin/env bash
# Tests for scripts/tdd-step.sh (v0.24.24 lane A, review fix round 3, slice R2; decision D4: when a hook takes the judged content out of the work tree the step never claims
# "the work tree is kept" and prints recovery lines that bring back the role content; code review round 2 found that git show <sha> > <path> is not faithful).
# The form of the recovery line is not pinned (D4 allows changing it): each row RUNS the printed recovery lines with sh -e in the test repo and asserts the result equals what the role judged.
#   S1  a symlink the role added (the hook removes it): after recovery a symlink with the same target
#   X1  a new file at 100755 (the hook removes it): after recovery executable, same content
#   X2  an exec-bit-only change of a tracked file (the hook reverts it): after recovery executable, same content
#   P2b a new file in a new directory (the hook removes the directory): recovery works, the file is back with its content
#   C1  core.autocrlf=true, the role wrote a CRLF file (the hook removes it): after recovery the bytes are what the role wrote (cmp)
#   R2-2 a pre-commit hook reverts the judged file and a post-commit hook creates a branch: exit 3, not "the work tree is kept", recovery lines printed and they restore the content
#   In every row the recovery leaves the index unchanged (git ls-files -s, and git diff --cached is empty).
# Shared setup: tdd-step-fixture.sh, tdd-step-d-fixture.sh, tdd-step-g-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/tdd-step-fixture.sh"
. "$(dirname "$0")/tdd-step-d-fixture.sh"
. "$(dirname "$0")/tdd-step-g-fixture.sh"
. "$(dirname "$0")/tdd-step-j-fixture.sh"

# can_link -> 0 when the file system stores a symbolic link that reads back
can_link() { local d; d="$(mk_tmp)"; ln -s target "$d/l" 2>/dev/null && [ -L "$d/l" ] && [ "$(readlink "$d/l")" = target ]; }
# rec_lines -> the recovery lines of OUT: lines indented by exactly two spaces that start with a shell command word (an indented ref line "refs/..." is not one)
rec_lines() { printf '%s\n' "$OUT" | grep -E '^  (git|rm|mkdir|ln|chmod|cat|printf|cp|sh|test|install|touch|mv|command|umask|\[) '; true; }
# recover TAG -> runs the printed recovery lines with sh -e in R; asserts there were some and that they succeed and leave the index alone
recover() {
  local s rc before after; s="$(mk_tmp)/recover.sh"
  rec_lines > "$s"
  assert_eq "$1: recovery lines are printed" "yes" "$([ -s "$s" ] && echo yes || echo no)"
  before="$(git -C "$R" ls-files -s)"
  ( cd "$R" && sh -e "$s" ) >/dev/null 2>&1; rc=$?
  assert_eq "$1: the recovery lines run without an error (sh -e)" "0" "$rc"
  after="$(git -C "$R" ls-files -s)"
  assert_eq "$1: the recovery leaves the index entries unchanged" "$before" "$after"
  assert_eq "$1: the recovery stages nothing (git diff --cached is empty)" "" "$(git -C "$R" diff --cached --name-status)"
}
# basics TAG RC -> the hook ran, the exit code, the work tree is not claimed kept
basics() {
  assert_eq "$1: the hook ran (the case is real)" "yes" "$([ -e "$R/.git/x-ran" ] && echo yes || echo no)"
  assert_rc "$1: exit $2" "$2"
  assert_not_contains "$1: does not say the work tree is kept" "$(lower "$OUT")" "the work tree is kept"
}
# rmhook NAME CACHEDPATH DIR -> a pre-commit hook that unstages CACHEDPATH and removes DIR from the work tree
rmhook() { mkhook "$1" 'touch .git/x-ran' "git rm -q --cached -- $2" "rm -r -- $3"; }
# hookcmd2 PRE POST -> a test command that installs PRE as pre-commit and POST as post-commit and fails (RED)
hookcmd2() { printf '%s' "cp .git/index '$IDXF'; cp '$1' .git/hooks/pre-commit; cp '$2' .git/hooks/post-commit; chmod +x .git/hooks/pre-commit .git/hooks/post-commit; exit 1"; }

if can_exec; then
  T="S1 symlink the role added"
  if can_link; then
    gprep default; ln -s ../src/app.js "$R/tests/lnk"
    run_red --commit sh -c "$(hookcmd "$(rmhook x1 tests/lnk tests/lnk)")"
    basics "$T" 1
    assert_eq "$T: the link is gone (the case is real)" "no" "$([ -L "$R/tests/lnk" ] && echo yes || echo no)"
    recover "$T"
    assert_eq "$T: it is a symlink" "yes" "$([ -L "$R/tests/lnk" ] && echo yes || echo no)"
    assert_eq "$T: with the same target" "../src/app.js" "$(readlink "$R/tests/lnk")"
  else
    t_skip 10 "$T (no symlinks here)"
  fi

  T="X1 new file at 100755"
  gprep default; printf '#!/bin/sh\necho hi\n' > "$R/tests/run.sh"; chmod +x "$R/tests/run.sh"
  run_red --commit sh -c "$(hookcmd "$(rmhook x2 tests/run.sh tests/run.sh)")"
  basics "$T" 1
  assert_eq "$T: the file is gone (the case is real)" "no" "$([ -e "$R/tests/run.sh" ] && echo yes || echo no)"
  recover "$T"
  # compared as git sees the file (autocrlf may give the recovered file CRLF; git hash-object --path normalizes it like git add did): the sha of the role's LF content
  assert_eq "$T: the file is back with its content" "$(printf '#!/bin/sh\necho hi\n' | git -C "$R" hash-object --stdin)" "$(git -C "$R" hash-object --path=tests/run.sh -- "$R/tests/run.sh" 2>/dev/null)"
  assert_eq "$T: it is executable" "yes" "$([ -x "$R/tests/run.sh" ] && echo yes || echo no)"

  if can_exec_f; then
    T="X2 exec-bit-only change reverted by the hook"
    gprep default; chmod +x "$R/tests/app.test.js"
    run_red --commit sh -c "$(hookcmd "$(mkhook x3 'touch .git/x-ran' 'git checkout -q HEAD -- tests/app.test.js')")"
    basics "$T" 1
    assert_eq "$T: the bit is gone (the case is real)" "no" "$([ -x "$R/tests/app.test.js" ] && echo yes || echo no)"
    recover "$T"
    assert_eq "$T: it is executable" "yes" "$([ -x "$R/tests/app.test.js" ] && echo yes || echo no)"
    assert_eq "$T: the content is unchanged" 'test("x", () => {});' "$(cat "$R/tests/app.test.js")"
  else
    t_skip 10 "X2 exec-bit-only change (this file system or git cannot record an exec bit on a .js file: no such change exists here)"
  fi

  T="P2b new file in a new directory the hook removed"
  gprep default; mkdir -p "$R/tests/newdir/deep"; printf 'deep content\n' > "$R/tests/newdir/deep/f.test.js"
  run_red --commit sh -c "$(hookcmd "$(rmhook x4 tests/newdir/deep/f.test.js tests/newdir)")"
  basics "$T" 1
  assert_eq "$T: the directory is gone (the case is real)" "no" "$([ -e "$R/tests/newdir" ] && echo yes || echo no)"
  recover "$T"
  assert_eq "$T: the file is back with its content" "deep content" "$(cat "$R/tests/newdir/deep/f.test.js" 2>/dev/null)"

  T="C1 core.autocrlf=true, a CRLF file the role wrote"
  gprep default 'git config core.autocrlf true'; printf 'a\r\nb\r\n' > "$R/tests/crlf.txt"
  SAVED="$(mk_tmp)/saved.crlf"; cp "$R/tests/crlf.txt" "$SAVED"
  run_red --commit sh -c "$(hookcmd "$(rmhook x5 tests/crlf.txt tests/crlf.txt)")"
  basics "$T" 1
  assert_eq "$T: the file is gone (the case is real)" "no" "$([ -e "$R/tests/crlf.txt" ] && echo yes || echo no)"
  recover "$T"
  assert_eq "$T: the work-tree bytes equal what the role wrote (cmp)" "same" "$(cmp -s "$SAVED" "$R/tests/crlf.txt" && echo same || echo differ)"

  T="R2-2 pre-commit reverts the judged file, post-commit creates a branch"
  gprep default; printf 'edited by the role\n' >> "$R/tests/app.test.js"; WANT="$(cat "$R/tests/app.test.js")"
  WSHA="$(git -C "$R" hash-object --path=tests/app.test.js -- "$R/tests/app.test.js")"
  PRE="$(mkhook x6 'touch .git/x-ran' 'git checkout -q HEAD -- tests/app.test.js')"
  POST="$(mkhook x7 'git show-ref --verify -q refs/heads/extra || git branch extra')"
  run_red --commit sh -c "$(hookcmd2 "$PRE" "$POST")"
  basics "$T" 3
  assert_eq "$T: the branch extra is left behind (the case is real)" "yes" "$(git -C "$R" show-ref --verify -q refs/heads/extra && echo yes || echo no)"
  assert_eq "$T: the edit is gone from the work tree (the case is real)" 'test("x", () => {});' "$(cat "$R/tests/app.test.js")"
  recover "$T"
  # compared as git sees the file (autocrlf may give the recovered file CRLF): the sha git computes is the judged sha
  assert_eq "$T: the role content is back" "$WSHA" "$(git -C "$R" hash-object --path=tests/app.test.js -- "$R/tests/app.test.js")"
else
  t_skip 60 "X D4 recovery cases (the file system cannot make a hook executable)"
fi

t_summary
