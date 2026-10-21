#!/usr/bin/env bash
# Tests for scripts/tdd-step.sh (v0.24.23 lane A, Full, code review round 1 fixes), part 10 of 10 (the new parts: test-tdd-step-n.sh, -o.sh, -p.sh; spec 01-spec.md, AC4):
#   F5  the exec-bit check keeps its edges (each row kills a mutant that survived the first review):
#       - reg_lines keeps only stage-0 regular entries: a real index entry that is a symlink (120000) or part of a conflict (stages 1 to 3) is not judged, so the step
#         commits as it did before AC4 (the work tree's file, mode 100644) and prints no exec-bit warning
#       - xbit_paths fails closed: a git, awk or sort call of it that exits non-zero after writing its correct output refuses the step on --commit ("cannot compare the
#         staged modes", exit 1, nothing committed, the index file restored); in print mode (no --commit) the step is advisory and, as in v0.24.22, still exits 0 and prints
#         its commands: it prints a note line (no warning) saying the modes could not be compared
# Shared setup: tdd-step-fixture.sh, tdd-step-d-fixture.sh, tdd-step-g-fixture.sh, tdd-step-j-fixture.sh (xprep, x_run) and tdd-step-n-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/tdd-step-fixture.sh"
. "$(dirname "$0")/tdd-step-d-fixture.sh"
. "$(dirname "$0")/tdd-step-g-fixture.sh"
. "$(dirname "$0")/tdd-step-j-fixture.sh"
. "$(dirname "$0")/tdd-step-n-fixture.sh"

# ---------------------------------------------------------------------------------------------------------------
echo "F5 reg_lines: a symlink entry and a conflicted entry of the real index are not judged (the step commits as before)"
# rl_prep KIND -> R, BL, H0, N0, IDXF, BASE: $F is tracked (100644) and the role rewrites it on disk (a regular file, 644). The real index holds another kind of entry for it:
#   symlink  = one 120000 entry (made with git update-index --cacheinfo: no real symlink is needed)
#   conflict = no stage-0 entry, three unmerged stages; stage 3 is 100755 (the last entry a filter-less reg_lines would keep)
# In both, git commit --only commits the work tree's file as a regular 100644 blob; the real mode (120000, 100755) differs from the scratch index and from HEAD, so a reg_lines
# without its stage-0 or its regular-mode filter would call it a staged exec bit and refuse.
rl_prep() {
  local kind="$1" b b1 b2 b3
  R="$(fresh)"; BASE=""
  ( cd "$R" && printf 'module.exports = 1;\n' > "$F" && git add -- "$F" && git commit -q -m "add $F" )
  dirty "$R"
  case "$kind" in
    symlink)
      b="$(printf 'target' | git -C "$R" hash-object -w --stdin)"
      git -C "$R" update-index --cacheinfo "120000,$b,$F" ;;
    conflict)
      b1="$(git -C "$R" rev-parse "HEAD:$F")"; b2="$(printf 'ours\n' | git -C "$R" hash-object -w --stdin)"; b3="$(printf 'theirs\n' | git -C "$R" hash-object -w --stdin)"
      git -C "$R" rm -q --cached -- "$F"
      printf '100644 %s 1\t%s\n100644 %s 2\t%s\n100755 %s 3\t%s\n' "$b1" "$F" "$b2" "$F" "$b3" "$F" | git -C "$R" update-index --index-info ;;
  esac
  BL="$(snap "$R")"
  printf 'module.exports = 4;\n' > "$R/$F"
  H0="$(head_of "$R")"; N0="$(count_of "$R")"; IDXF="$(mk_tmp)/index.copy"
}
# rl_commit LABEL KIND -> 8 assertions: --baseline --commit commits $F as a regular file, exit 0
rl_commit() {
  local label="$1" kind="$2"
  rl_prep "$kind"; x_run --commit
  assert_rc "$label: exit 0 (not refused)" 0
  assert_not_contains "$label: no exec bit refusal" "$(lower "$OUT")" "the exec bit"
  assert_contains "$label: prints RED=" "$OUT" "RED="
  assert_eq "$label: one new commit" "$((N0 + 1))" "$(count_of "$R")"
  assert_eq "$label: the commit holds the path" "$F" "$(committed "$R")"
  assert_eq "$label: the committed mode is 100644 (the work tree's regular file)" "100644" "$(git -C "$R" ls-tree HEAD -- "$F" | cut -d' ' -f1)"
  assert_eq "$label: the committed content is the work tree's" "module.exports = 4;" "$(git -C "$R" show "HEAD:$F")"
  assert_eq "$label: HEAD is the test(red) commit" "test(red): m" "$(subject "$R")"
}
rl_commit "F5 real index entry is a symlink (120000), --baseline --commit" symlink
rl_commit "F5 real index entry is conflicted (stages 1-3, stage 3 is 100755), --baseline --commit" conflict
rl_prep symlink; x_run ""
assert_rc "F5 symlink entry, print mode: exit 0" 0
assert_contains "F5 symlink entry, print mode: prints the commit commands" "$OUT" "not committing (no --commit)"
assert_eq "F5 symlink entry, print mode: no line about the exec bit" "" "$(printf '%s\n' "$OUT" | tr '[:upper:]' '[:lower:]' | grep -F 'exec bit')"
assert_untouched "F5 symlink entry, print mode: nothing committed" "$R" "$H0" "$N0"

# ---------------------------------------------------------------------------------------------------------------
echo "F5 xbit_paths fails closed: a failing git, awk or sort call of it refuses the step on --commit; print mode still exits 0 and prints a note"
# xf_commit LABEL SEEN WANT -> 9 assertions (after x_run --commit with a stub on PATH). SEEN = what the stub counted, WANT = what the run must have reached
xf_commit() {
  local label="$1" seen="$2" want="$3"
  assert_eq "$label: the stub failed the call (the step reached it)" "$want" "$seen"
  assert_rc "$label: exit 1" 1
  assert_contains "$label: says cannot compare the staged modes" "$(lower "$OUT")" "cannot compare the staged modes"
  assert_contains "$label: says nothing committed" "$(lower "$OUT")" "nothing committed"
  assert_not_contains "$label: no RED= line" "$OUT" "RED="
  assert_untouched "$label: nothing committed" "$R" "$H0" "$N0"
  assert_eq "$label: the index file is restored byte for byte" "same" "$(same_idx)"
  assert_eq "$label: no test(red) commit in the log" "" "$(no_red_commit)"
  assert_not_contains "$label: not a refusal for an exec bit" "$(lower "$OUT")" "the exec bit"
}
# xf_print LABEL SEEN WANT -> 8 assertions (after x_run "" with a stub on PATH): print mode is advisory; the commands are printed, exit 0, a note line, no warning
xf_print() {
  local label="$1" seen="$2" want="$3" l
  assert_eq "$label: the stub failed the call (the step reached it)" "$want" "$seen"
  assert_rc "$label: exit 0 (as in v0.24.22)" 0
  assert_contains "$label: prints the commit commands" "$OUT" "not committing (no --commit)"
  assert_untouched "$label: nothing committed" "$R" "$H0" "$N0"
  assert_eq "$label: the index file is restored byte for byte" "same" "$(same_idx)"
  l="$(printf '%s\n' "$OUT" | tr '[:upper:]' '[:lower:]' | grep -F 'cannot compare the staged modes')"
  assert_contains "$label: a line says the staged modes could not be compared" "$l" "cannot compare the staged modes"
  assert_contains "$label: that line is a note" "$l" "note"
  assert_not_contains "$label: that line is not an error or a warning" "$l" "error"
}
# the scenario: a path staged 100644 (nothing to refuse, so a step that ignores the failure would commit)
for K in lsfiles2 lsfiles3 lstree awk sort; do
  xprep false new 644 plain
  case "$K" in
    lsfiles2) D="$(stubdir git "$(t="${XBGIT_STUB//@WHAT@/lsfiles}"; printf '%s' "${t//@FIRE@/2}")")" ; L="git ls-files -s -z of the real index (line 155)" ;;
    lsfiles3) D="$(stubdir git "$(t="${XBGIT_STUB//@WHAT@/lsfiles}"; printf '%s' "${t//@FIRE@/3}")")" ; L="git ls-files -s -z of the scratch index (line 157)" ;;
    lstree)   D="$(stubdir git "$(t="${XBGIT_STUB//@WHAT@/lstree}"; printf '%s' "${t//@FIRE@/1}")")"   ; L="git ls-tree -r -z HEAD (line 159)" ;;
    awk)      D="$(stubdir awk "${AWK_STUB//@FIRE@/1}")"; printf '%s' 'function pth(l)' > "$D/cnt.pat"             ; L="the awk comparison (line 161)" ;;
    sort)     D="$(stubdir sort "$XBSORT_STUB")"                                                                   ; L="the sort of the result (line 168)" ;;
  esac
  PATH="$D:$SAVEP"; x_run --commit; PATH="$SAVEP"
  case "$K" in lsfiles2) W=2 ;; lsfiles3) W=3 ;; sort) W=fired ;; *) W=1 ;; esac
  if [ "$K" = sort ]; then S="$([ -f "$D/cnt" ] && echo fired || echo never)"; else S="$(cat "$D/cnt" 2>/dev/null)"; fi
  xf_commit "F5 --commit, a failing $L" "$S" "$W"
done
for K in lstree awk; do
  xprep false new 644 plain
  case "$K" in
    lstree) D="$(stubdir git "$(t="${XBGIT_STUB//@WHAT@/lstree}"; printf '%s' "${t//@FIRE@/1}")")"; L="git ls-tree -r -z HEAD" ;;
    awk)    D="$(stubdir awk "${AWK_STUB//@FIRE@/1}")"; printf '%s' 'function pth(l)' > "$D/cnt.pat";        L="the awk comparison" ;;
  esac
  PATH="$D:$SAVEP"; x_run ""; PATH="$SAVEP"
  xf_print "F5 print mode, a failing $L" "$(cat "$D/cnt" 2>/dev/null)" 1
done

t_summary
