#!/usr/bin/env bash
# Shared helpers of tests/test-tdd-step-j.sh and -m.sh (v0.24.23 lane A, slice S3, AC4): F, xprep, x_run, x_disk, xrefuse, xcommit, xprint (the exec-bit rows).
# Source it after lib.sh, tdd-step-fixture.sh, tdd-step-d-fixture.sh and tdd-step-g-fixture.sh. It is not a suite: run-all.sh only starts tests/test-*.sh.
# Disk mode: "755" = the file is executable on disk when tdd-step runs, "644" = it is not.
F="tests/x.test.js"
# can_exec_f -> 0 when a .js file really gets an exec bit here: chmod sticks ([ -x ]) and git (core.filemode=true) stages it 100755. can_exec probes a .sh file, which is no
# proof: NTFS under msys (Git Bash, the windows-latest runner) keeps the bit only for names it knows (.sh, .exe), so "chmod +x tests/x.test.js" does not stick there.
can_exec_f() {
  local d; d="$(mk_tmp)"
  git -C "$d" init -q 2>/dev/null || return 1
  printf 'x\n' > "$d/p.test.js"; chmod +x "$d/p.test.js" 2>/dev/null
  [ -x "$d/p.test.js" ] || return 1
  git -C "$d" -c core.filemode=true add p.test.js 2>/dev/null || return 1
  [ "$(git -C "$d" -c core.filemode=true ls-files -s -- p.test.js | cut -d' ' -f1)" = 100755 ]
}
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
  l="$(printf '%s\n' "$OUT" | tr '[:upper:]' '[:lower:]' | grep -F 'the exec bit')"
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
  l="$(printf '%s\n' "$OUT" | tr '[:upper:]' '[:lower:]' | grep -F 'exec bit')"
  if [ "$warn" = yes ]; then
    assert_contains "$label: a warning line names the path" "$l" "$F"
    assert_contains "$label: the line is a warning" "$(lower "$l")" "warn"
  else
    assert_eq "$label: no warning about the exec bit" "" "$l"
  fi
}
