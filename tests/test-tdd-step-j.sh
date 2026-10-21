#!/usr/bin/env bash
# Tests for scripts/tdd-step.sh (v0.24.23 lane A, Full), part 4 (parts 1 to 3: test-tdd-step-g.sh, -h.sh, -i.sh; slice S3 of .agents/handoff/01-spec.md):
#   AC4  --baseline --commit refuses a path whose staged mode git commit --only would not carry (staged +x on a new or tracked path, staged -x on a tracked 100755 path);
#        the table of the spec row by row, each with its core.filemode and its disk mode; print mode (no --commit) warns for the same paths and exits 0
#   AC5  the header comment of scripts/tdd-step.sh states the nested-repo limit and the disk-only exec bit limit
# Shared setup: tdd-step-fixture.sh, tdd-step-d-fixture.sh and tdd-step-g-fixture.sh. Cases that already pass on v0.24.22 are named "control" or "unchanged".
# Disk mode: "755" = the file is executable on disk when tdd-step runs, "644" = it is not. Rows that need a real exec bit are skipped where the file system has none (can_exec).
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/tdd-step-fixture.sh"
. "$(dirname "$0")/tdd-step-d-fixture.sh"
. "$(dirname "$0")/tdd-step-g-fixture.sh"

F="tests/x.test.js"
# The role gate refuses a tracked file that loses its exec bit relative to --base (VIOLATION (mode)). The rows with a tracked 100755 file (t755) therefore pass
# --base HEAD~1, the commit before the one that added the file: for the gate the file is new and 100644. The other rows pass no --base.
# xprep FM HEADKIND DISK STAGE -> R (a dirty repo with a baseline BL) and the role's change to $F:
#   FM = the core.filemode setting (true or false)
#   HEADKIND = new (not in HEAD), t644 (tracked 100644) or t755 (tracked 100755 in HEAD)
#   DISK = 644 or 755, the disk mode of $F when tdd-step runs
#   STAGE = plus (git add --chmod=+x), minus (git add --chmod=-x), plain (git add), none (nothing staged; a tracked file is edited), untracked (a new file, never added)
xprep() {
  local fm="$1" hk="$2" disk="$3" stage="$4"
  R="$(fresh)"; ( cd "$R" && git config core.filemode "$fm" )
  case "$hk" in
    t644) ( cd "$R" && printf 'module.exports = 1;\n' > "$F" && git add -- "$F" && git commit -q -m "add $F" ) ;;
    t755) ( cd "$R" && printf 'module.exports = 1;\n' > "$F" && chmod +x "$F" && git add --chmod=+x -- "$F" && git commit -q -m "add $F" ) ;;
  esac
  dirty "$R"; BL="$(snap "$R")"
  if [ "$hk" = new ]; then printf 'module.exports = 2;\n' > "$R/$F"; else printf 'module.exports = 3;\n' >> "$R/$F"; fi
  if [ "$disk" = 755 ]; then chmod +x "$R/$F"; else chmod -x "$R/$F"; fi
  case "$stage" in
    plus)  ( cd "$R" && git add --chmod=+x -- "$F" ) ;;
    minus) ( cd "$R" && git add --chmod=-x -- "$F" ) ;;
    plain) ( cd "$R" && git add -- "$F" ) ;;
  esac
  H0="$(head_of "$R")"; N0="$(count_of "$R")"; IDXF="$(mk_tmp)/index.copy"
  BASE=""; if [ "$hk" = t755 ]; then BASE="$(git -C "$R" rev-parse HEAD~1)"; fi
}
# x_run FLAG -> tdd-step red in R; the test command copies the index file first (as hookcmd does), so same_idx compares with the state right before tdd-step stages anything
x_run() { run_in "$R" bash "$STEP" red --message "m" $1 --baseline "$BL" ${BASE:+--base "$BASE"} -- sh -c "cp .git/index '$IDXF'; exit 1"; }
# x_disk LABEL DISK -> the stated disk mode really holds (only where the file system has exec bits)
x_disk() {
  if [ "$2" = 755 ]; then
    if [ -x "$R/$F" ]; then t_ok "$1: the disk mode is 755"; else t_bad "$1: the disk mode is 755" "not executable"; fi
  else
    if [ ! -x "$R/$F" ]; then t_ok "$1: the disk mode is 644"; else t_bad "$1: the disk mode is 644" "executable"; fi
  fi
}
# xrefuse NAME FM HEADKIND DISK STAGE -> refused: exit 1, the message names the path, "the exec bit", "nothing committed" (and core.filemode=false only when set), nothing changed
xrefuse() {
  local name="$1" fm="$2" hk="$3" disk="$4" stage="$5" label l
  label="$name (core.filemode=$fm, disk $disk)"
  xprep "$fm" "$hk" "$disk" "$stage"; x_disk "$label" "$disk"
  x_run --commit
  l="$(printf '%s\n' "$OUT" | grep -i -F 'the exec bit')"
  assert_rc "$label: exit 1" 1
  assert_contains "$label: a line says the exec bit and names the path" "$l" "$F"
  assert_contains "$label: says nothing committed" "$(lower "$OUT")" "nothing committed"
  if [ "$fm" = false ]; then
    assert_contains "$label: names core.filemode=false" "$OUT" "core.filemode=false"
  else
    assert_not_contains "$label: does not mention core.filemode" "$OUT" "core.filemode"
  fi
  assert_untouched "$label: nothing committed" "$R" "$H0" "$N0"
  assert_eq "$label: the index file is byte for byte as before" "same" "$(same_idx)"
  assert_eq "$label: no test(red) commit in the log" "" "$(no_red_commit)"
  assert_not_contains "$label: no RED= line" "$OUT" "RED="
}
# xcommit NAME FM HEADKIND DISK STAGE WANT_MODE -> committed as today: exit 0, one new commit, the committed mode of the path
xcommit() {
  local name="$1" fm="$2" hk="$3" disk="$4" stage="$5" want="$6" label
  label="$name (core.filemode=$fm, disk $disk)"
  xprep "$fm" "$hk" "$disk" "$stage"; x_disk "$label" "$disk"
  x_run --commit
  assert_rc "$label: exit 0" 0
  assert_eq "$label: one new commit" "$((N0 + 1))" "$(count_of "$R")"
  assert_eq "$label: the committed mode is $want" "$want" "$(git -C "$R" ls-tree HEAD -- "$F" | cut -d' ' -f1)"
  assert_contains "$label: prints RED=" "$OUT" "RED="
}
# xprint NAME FM HEADKIND DISK STAGE WARN -> print mode (no --commit): exit 0, the commands are printed, nothing committed, and a warning line
# naming the path and the exec bit (WARN=yes) or none (WARN=no)
xprint() {
  local name="$1" fm="$2" hk="$3" disk="$4" stage="$5" warn="$6" label l
  label="$name (core.filemode=$fm, disk $disk, print mode)"
  xprep "$fm" "$hk" "$disk" "$stage"; x_disk "$label" "$disk"
  x_run ""
  assert_rc "$label: exit 0" 0
  assert_contains "$label: prints the commit commands" "$OUT" "not committing (no --commit)"
  assert_untouched "$label: nothing committed" "$R" "$H0" "$N0"
  assert_eq "$label: the index file is byte for byte as before" "same" "$(same_idx)"
  l="$(printf '%s\n' "$OUT" | grep -i -F 'exec bit')"
  if [ "$warn" = yes ]; then
    assert_contains "$label: a warning line names the path" "$l" "$F"
    assert_contains "$label: the line is a warning" "$(lower "$l")" "warn"
  else
    assert_eq "$label: no warning about the exec bit" "" "$l"
  fi
}

# ---------------------------------------------------------------------------------------------------------------
echo "AC4 --baseline --commit: a staged mode that git commit --only would not carry is refused before the commit (the table, row by row)"
# disk 644 rows do not need a real exec bit when core.filemode=false (git ignores the disk bit); every other row does
xrefuse "AC4 row 1 new path, staged +x"             false new  644 plus
if can_exec; then
  xrefuse "AC4 row 2 new path, staged +x"           false new  755 plus
fi
xrefuse "AC4 row 3 tracked 100644, staged +x"       false t644 644 plus
if can_exec; then
  xrefuse "AC4 row 4 tracked 100755, staged -x" false t755 755 minus
  xrefuse "AC4 row 5 new path, staged +x"           true  new  644 plus
else
  t_skip 9 "AC4 row 2 (the file system has no exec bit)"
  t_skip 9 "AC4 row 4 (the file system has no exec bit)"
  t_skip 9 "AC4 row 5 (the file system has no exec bit)"
fi

echo "AC4 control: rows that commit as today"
if can_exec; then
  xcommit "AC4 row 6 control: new path, staged +x, executable on disk" true new 755 plus 100755
  xcommit "AC4 row 7 control: tracked 100755 chmod -x on disk, edited, nothing staged (the user's intent: 100644)" true t755 644 none 100644
  xcommit "AC4 row 8 control: a path staged 100644" true new 644 plain 100644
else
  t_skip 12 "AC4 rows 6 to 8 (the file system has no exec bit)"
fi
xcommit "AC4 row 8 control: a path staged 100644" false new 644 plain 100644
xcommit "AC4 control: an untracked file, disk 644" false new 644 untracked 100644

echo "AC4 print mode (--baseline without --commit): a warning for each such path, exit 0, nothing committed"
xprint "AC4 print row 1 new path, staged +x"        false new  644 plus yes
xprint "AC4 print row 3 tracked 100644, staged +x"  false t644 644 plus yes
xprint "AC4 print control: a path staged 100644"    false new  644 plain no
xprint "AC4 print control: an untracked file"       false new  644 untracked no
if can_exec; then
  xprint "AC4 print row 4 tracked 100755, staged -x" false t755 755 minus yes
  xprint "AC4 print row 5 new path, staged +x"      true  new  644 plus yes
  xprint "AC4 print control: new path, staged +x, executable on disk (row 6)" true new 755 plus no
  xprint "AC4 print control: an untracked file, disk 755 (no index entry, no warning)" true new 755 untracked no
else
  t_skip 20 "AC4 print rows that need an exec bit (the file system has none)"
fi

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
