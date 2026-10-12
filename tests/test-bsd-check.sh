#!/usr/bin/env bash
# Tests for tools/bsd-check.sh (v0.22.2 AC5.1): run suites with one-true-awk first on PATH, the awk macOS ships.
#   tools/bsd-check.sh [SUITE...]
# The tool is copied into a throw-away tree with a stub suite, and a fake `original-awk` (or `nawk`) is put on PATH:
# a script that records the call and then runs the real awk. No real one-true-awk is needed.
. "$(dirname "$0")/lib.sh"
TOOL="$PB_ROOT/tools/bsd-check.sh"

echo "AC5.1 the tool exists"
assert_file "AC5.1 tools/bsd-check.sh exists" "$TOOL"

case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*)   # copied bash/sh in a bare PATH cannot load the msys DLLs; one-true-awk is a Linux/macOS dev tool
    t_skip 20 "AC5.1 bsd-check cases need a bare PATH (not possible on Git Bash)"; t_summary; exit $? ;;
esac
REAL_AWK="$(command -v awk)"
W="$(mk_tmp)"

# mk_tree DIR -> DIR/tools/bsd-check.sh, a stub suite DIR/tests/test-x.sh and a stub DIR/tests/run-all.sh.
# The suite prints which awk it saw first, runs awk once, and exits with $STUB_RC (default 0).
mk_tree() {
  local d="$1"
  mkdir -p "$d/tools" "$d/tests"
  [ -f "$TOOL" ] && cp "$TOOL" "$d/tools/bsd-check.sh"
  cat > "$d/tests/test-x.sh" <<'SUITE'
#!/usr/bin/env bash
echo "suite x ran"
echo "first awk: $(command -v awk)"
awk 'BEGIN { print "awk output" }'
exit "${STUB_RC:-0}"
SUITE
  cat > "$d/tests/run-all.sh" <<'SUITE'
#!/usr/bin/env bash
echo "run-all ran"
echo "first awk: $(command -v awk)"
exit "${STUB_RC:-0}"
SUITE
}
# fake_awk BINDIR NAME LOG -> BINDIR/NAME: records the call in LOG, then execs the real awk
fake_awk() {
  mkdir -p "$1"
  printf '#!/bin/sh\necho "called %s" >> "%s"\nexec "%s" "$@"\n' "$2" "$3" "$REAL_AWK" > "$1/$2"
  chmod +x "$1/$2"
}

# BARE: a PATH dir with only the basic tools the script can need: no awk at all, so no original-awk and no nawk.
# Every case below puts its fake awk dir in front of BARE, so a real original-awk or nawk on this machine never leaks in.
BARE="$W/bare"; mkdir -p "$BARE"
for t in dirname basename mktemp rm ln cat mkdir cp chmod sed grep tr head tail uname env sh bash cut wc sort ls rmdir true false sleep; do
  p="$(command -v "$t" 2>/dev/null)"
  case "$p" in /*) ln -s "$p" "$BARE/$t" 2>/dev/null || cp "$p" "$BARE/$t" 2>/dev/null ;; esac
done
echo "AC5.1 with original-awk on PATH: it is the awk the suite sees"
D="$W/t1"; mk_tree "$D"; fake_awk "$W/b1" original-awk "$W/b1.log"
run env PATH="$W/b1:$BARE" bash "$D/tools/bsd-check.sh" tests/test-x.sh
assert_rc "AC5.1 a passing suite: exit 0" 0
assert_contains "AC5.1 the suite ran" "$OUT" "suite x ran"
assert_contains "AC5.1 the suite's awk output came through the fake original-awk" "$OUT" "awk output"
assert_contains "AC5.1 original-awk was called (the suite's awk is original-awk)" "$(cat "$W/b1.log" 2>/dev/null)" "called original-awk"
assert_contains "AC5.1 the tool prints the awk it used (original-awk)" "$OUT" "original-awk"
case "$OUT" in *"first awk: $W/b1/original-awk"*) t_bad "AC5.1 awk resolves to a link in a temp dir, not to the original path" "first awk: $W/b1/original-awk" ;; *) t_ok "AC5.1 awk resolves to a link in a temp dir, not to the original path" ;; esac

echo "AC5.1 the suite's exit code is passed through"
D="$W/t2"; mk_tree "$D"; fake_awk "$W/b2" original-awk "$W/b2.log"
run env PATH="$W/b2:$BARE" STUB_RC=7 bash "$D/tools/bsd-check.sh" tests/test-x.sh
assert_rc "AC5.1 a suite that exits 7: the tool exits 7" 7
D="$W/t2b"; mk_tree "$D"
run env PATH="$W/b2:$BARE" STUB_RC=1 bash "$D/tools/bsd-check.sh" tests/test-x.sh
assert_rc "AC5.1 a suite that exits 1: the tool exits 1" 1

echo "AC5.1 without a suite it runs tests/run-all.sh"
D="$W/t3"; mk_tree "$D"; fake_awk "$W/b3" original-awk "$W/b3.log"
run env PATH="$W/b3:$BARE" bash "$D/tools/bsd-check.sh"
assert_rc "AC5.1 no arguments: exit 0" 0
assert_contains "AC5.1 no arguments: run-all.sh ran" "$OUT" "run-all ran"
run env PATH="$W/b3:$BARE" STUB_RC=3 bash "$D/tools/bsd-check.sh"
assert_rc "AC5.1 no arguments: run-all's exit code is passed through (3)" 3

echo "AC5.1 nawk is used when there is no original-awk"
D="$W/t4"; mk_tree "$D"; fake_awk "$W/b4" nawk "$W/b4.log"
run env PATH="$W/b4:$BARE" bash "$D/tools/bsd-check.sh" tests/test-x.sh
assert_contains "AC5.1 nawk was called" "$(cat "$W/b4.log" 2>/dev/null)" "called nawk"
assert_contains "AC5.1 the tool prints that it used nawk" "$OUT" "nawk"
D="$W/t4b"; mk_tree "$D"; fake_awk "$W/b4b" nawk "$W/b4b.log"; fake_awk "$W/b4b" original-awk "$W/b4b.log"
run env PATH="$W/b4b:$BARE" bash "$D/tools/bsd-check.sh" tests/test-x.sh
assert_contains "AC5.1 with both, original-awk is preferred" "$(cat "$W/b4b.log" 2>/dev/null)" "called original-awk"
assert_not_contains "AC5.1 with both, nawk is not used" "$(cat "$W/b4b.log" 2>/dev/null)" "called nawk"

echo "AC5.1 with neither original-awk nor nawk: how to install it, exit 2"
D="$W/t5"; mk_tree "$D"
BASH_BIN="$(command -v bash)"
run env PATH="$BARE" "$BASH_BIN" "$D/tools/bsd-check.sh" tests/test-x.sh
assert_rc "AC5.1 neither awk on PATH: exit 2" 2
assert_contains "AC5.1 neither awk on PATH: the message names original-awk" "$OUT" "original-awk"
assert_contains "AC5.1 neither awk on PATH: the message says how to install it (apt install original-awk)" "$OUT" "apt install original-awk"
assert_not_contains "AC5.1 neither awk on PATH: the suite did not run" "$OUT" "suite x ran"


echo "v0.23.1 AC12.1 when ln -s fails, bsd-check copies the awk and the copy is executable"
D="$W/t6"; mk_tree "$D"; fake_awk "$W/b6" original-awk "$W/b6.log"
cat > "$D/tests/test-y.sh" <<'SUITE'
#!/usr/bin/env bash
a="$(command -v awk)"
echo "awk path: $a"
if [ -L "$a" ]; then echo "awk is a symlink: yes"; else echo "awk is a symlink: no"; fi
if [ -x "$a" ]; then echo "awk is executable: yes"; else echo "awk is executable: no"; fi
if [ -f "$a" ]; then echo "awk is a regular file: yes"; else echo "awk is a regular file: no"; fi
if [ "$(cat "$a" 2>/dev/null)" = "$(cat "$SRC_AWK" 2>/dev/null)" ]; then echo "awk has the source content: yes"; else echo "awk has the source content: no"; fi
awk 'BEGIN { print "awk output" }'
SUITE
# a PATH stub: ln always fails (and records that it was asked), in front of the bare tool dir
LNB="$W/lnfail"; mkdir -p "$LNB"
printf '#!/bin/sh\necho "ln called: $*" >> "%s"\nexit 1\n' "$W/ln.log" > "$LNB/ln"
chmod +x "$LNB/ln"
rm -f "$W/ln.log"
run env PATH="$LNB:$W/b6:$BARE" SRC_AWK="$W/b6/original-awk" bash "$D/tools/bsd-check.sh" tests/test-y.sh
assert_rc "AC12.1 with ln failing, bsd-check still works: exit 0" 0
assert_contains "AC12.1 the stub ln was asked to link (so the fallback is what ran)" "$(cat "$W/ln.log" 2>/dev/null)" "ln called"
assert_contains "AC12.1 the tool still prints the awk it used" "$OUT" "original-awk"
assert_contains "AC12.1 the suite sees awk" "$OUT" "awk path: "
assert_contains "AC12.1 the awk the suite sees is not a symlink (a copy)" "$OUT" "awk is a symlink: no"
assert_contains "AC12.1 the copy is a regular file" "$OUT" "awk is a regular file: yes"
assert_contains "AC12.1 the copy is executable" "$OUT" "awk is executable: yes"
assert_contains "AC12.1 the copy has the content of the original awk" "$OUT" "awk has the source content: yes"
assert_contains "AC12.1 the suite's awk output came through the copy" "$OUT" "awk output"
assert_contains "AC12.1 the copied original-awk was the one called" "$(cat "$W/b6.log" 2>/dev/null)" "called original-awk"
run env PATH="$LNB:$W/b6:$BARE" SRC_AWK="$W/b6/original-awk" STUB_RC=5 bash "$D/tools/bsd-check.sh" tests/test-x.sh
assert_rc "AC12.1 with ln failing the suite's exit code (5) is still passed through" 5
# ---- v0.23.0 AC4.2: bash 3.2 is linked as `bash` next to awk, so nested `bash tests/...` calls use it ----
# The fake bash 3.2 is a wrapper that logs and execs the real bash, so no real bash 3.2 is needed.
echo "AC4.2 the suites run under bash 3.2 when it is available"
REAL_BASH="$(command -v bash)"
# fake_bash PATH LOG -> PATH is a wrapper script: logs its arguments, then execs the real bash
fake_bash() {
  local ver="${3:-3.2.57(1)-release}" maj min rest
  maj="${ver%%.*}"; rest="${ver#*.}"; min="${rest%%.*}"
  mkdir -p "$(dirname "$1")"
  # The wrapper logs every call, answers the usual version probes itself with VER (so the tool can tell a 3.2 from a 5.x),
  # and execs the real bash for everything else.
  cat > "$1" <<WRAP
#!/bin/sh
echo "called $1 \$*" >> "$2"
case "\$*" in
  *'VERSINFO[0]'*) echo $maj; exit 0 ;;
  *'VERSINFO[1]'*) echo $min; exit 0 ;;
  *VERSINFO*) echo "$maj $min"; exit 0 ;;
  *BASH_VERSION*) echo "$ver"; exit 0 ;;
  *--version*|*-version*) echo "GNU bash, version $ver (fake)"; exit 0 ;;
esac
exec "$REAL_BASH" "\$@"
WRAP
  chmod +x "$1"
}
# mk_bash_suite DIR -> DIR/tests/test-b.sh prints the bash it sees first and runs a nested bash
mk_bash_suite() {
  cat > "$1/tests/test-b.sh" <<'SUITE'
#!/usr/bin/env bash
echo "suite b ran"
echo "first bash: $(command -v bash)"
bash -c 'echo nested ran'
exit "${STUB_RC:-0}"
SUITE
}
# bc ARGS... -> run the tool with ARGS (env settings) in D with the fake original-awk first on PATH, HOME isolated
D="$W/b1"; mk_tree "$D"; mk_bash_suite "$D"; fake_awk "$W/bb1" original-awk "$W/bb1.log"
FB1="$W/fb1/bash3.2"; fake_bash "$FB1" "$W/fb1.log"
mkdir -p "$W/home1"
run env -i PATH="$W/bb1:$BARE" HOME="$W/home1" TMPDIR="$W" PB_BASH32="$FB1" "$BASH_BIN" "$D/tools/bsd-check.sh" tests/test-b.sh
assert_rc "AC4.2 with PB_BASH32: a passing suite exits 0" 0
assert_contains "AC4.2 the suite ran" "$OUT" "suite b ran"
assert_contains "AC4.2 the nested bash call ran" "$OUT" "nested ran"
assert_contains "AC4.2 the tool prints 'bsd-check: bash is <path>'" "$OUT" "bsd-check: bash is $FB1"
assert_contains "AC4.2 the awk line is still printed" "$OUT" "bsd-check: awk is original-awk"
assert_not_contains "AC4.2 the suite's first bash is not the real one" "$OUT" "first bash: $REAL_BASH"
case "$OUT" in *"first bash: $BARE/bash"*) t_bad "AC4.2 the suite's first bash is not the bash of the plain PATH" "$OUT" ;; *) t_ok "AC4.2 the suite's first bash is not the bash of the plain PATH" ;; esac
assert_contains "AC4.2 the suite's first bash is a link in a temp dir (named bash)" "$OUT" "/bash"
LOG="$(cat "$W/fb1.log" 2>/dev/null)"
NCALLS=$(printf '%s\n' "$LOG" | grep -c '^called ')
if [ "$NCALLS" -ge 2 ]; then t_ok "AC4.2 the fake bash 3.2 was called for the suite and for the nested call (at least 2 calls)"; else t_bad "AC4.2 the fake bash 3.2 was called at least twice" "calls: $NCALLS; log: $LOG"; fi
assert_contains "AC4.2 the suite itself was started through the wrapper" "$LOG" "tests/test-b.sh"
assert_contains "AC4.2 the nested call went through the wrapper" "$LOG" "nested ran"

echo "AC4.2 the suite's exit code is still passed through under bash 3.2"
D="$W/b2"; mk_tree "$D"; mk_bash_suite "$D"; fake_awk "$W/bb2" original-awk "$W/bb2.log"
run env -i PATH="$W/bb2:$BARE" HOME="$W/home1" TMPDIR="$W" PB_BASH32="$FB1" STUB_RC=5 "$BASH_BIN" "$D/tools/bsd-check.sh" tests/test-b.sh
assert_rc "AC4.2 a suite that exits 5 under bash 3.2: the tool exits 5" 5

echo "AC4.2 no arguments: run-all.sh runs under bash 3.2 too"
D="$W/b3"; mk_tree "$D"; fake_awk "$W/bb3" original-awk "$W/bb3.log"; rm -f "$W/fb1.log"
run env -i PATH="$W/bb3:$BARE" HOME="$W/home1" TMPDIR="$W" PB_BASH32="$FB1" "$BASH_BIN" "$D/tools/bsd-check.sh"
assert_rc "AC4.2 run-all under bash 3.2: exit 0" 0
assert_contains "AC4.2 run-all ran" "$OUT" "run-all ran"
assert_contains "AC4.2 run-all was started through the wrapper" "$(cat "$W/fb1.log" 2>/dev/null)" "run-all.sh"

echo "AC4.2 lookup order: PB_BASH32, then ~/.local/bin/bash3.2, then bash3.2 on PATH"
D="$W/b4"; mk_tree "$D"; mk_bash_suite "$D"; fake_awk "$W/bb4" original-awk "$W/bb4.log"
HB="$W/home4"; mkdir -p "$HB/.local/bin"
fake_bash "$HB/.local/bin/bash3.2" "$W/fb4home.log"; fake_bash "$W/fb4/bash3.2" "$W/fb4env.log"; fake_bash "$W/fb4path/bash3.2" "$W/fb4path.log"
run env -i PATH="$W/bb4:$W/fb4path:$BARE" HOME="$HB" TMPDIR="$W" PB_BASH32="$W/fb4/bash3.2" "$BASH_BIN" "$D/tools/bsd-check.sh" tests/test-b.sh
assert_contains "AC4.2 PB_BASH32 is used first (printed)" "$OUT" "bsd-check: bash is $W/fb4/bash3.2"
assert_contains "AC4.2 PB_BASH32 is used first (called)" "$(cat "$W/fb4env.log" 2>/dev/null)" "called"
assert_not_contains "AC4.2 PB_BASH32 first: ~/.local/bin/bash3.2 not called" "$(cat "$W/fb4home.log" 2>/dev/null)" "called"
assert_not_contains "AC4.2 PB_BASH32 first: bash3.2 on PATH not called" "$(cat "$W/fb4path.log" 2>/dev/null)" "called"
rm -f "$W/fb4home.log" "$W/fb4path.log"
run env -i PATH="$W/bb4:$W/fb4path:$BARE" HOME="$HB" TMPDIR="$W" "$BASH_BIN" "$D/tools/bsd-check.sh" tests/test-b.sh
assert_contains "AC4.2 without PB_BASH32, ~/.local/bin/bash3.2 is used (printed)" "$OUT" "bsd-check: bash is $HB/.local/bin/bash3.2"
assert_contains "AC4.2 without PB_BASH32, ~/.local/bin/bash3.2 is used (called)" "$(cat "$W/fb4home.log" 2>/dev/null)" "called"
assert_not_contains "AC4.2 ~/.local/bin first: bash3.2 on PATH not called" "$(cat "$W/fb4path.log" 2>/dev/null)" "called"
mkdir -p "$W/home4b"
run env -i PATH="$W/bb4:$W/fb4path:$BARE" HOME="$W/home4b" TMPDIR="$W" "$BASH_BIN" "$D/tools/bsd-check.sh" tests/test-b.sh
assert_contains "AC4.2 last, bash3.2 on PATH is used (printed)" "$OUT" "bsd-check: bash is $W/fb4path/bash3.2"
assert_contains "AC4.2 last, bash3.2 on PATH is used (called)" "$(cat "$W/fb4path.log" 2>/dev/null)" "called"

echo "AC4.2 without bash 3.2: the get-bash32 hint is printed and the suites still run"
D="$W/b5"; mk_tree "$D"; mk_bash_suite "$D"; fake_awk "$W/bb5" original-awk "$W/bb5.log"
mkdir -p "$W/home5"
run env -i PATH="$W/bb5:$BARE" HOME="$W/home5" TMPDIR="$W" "$BASH_BIN" "$D/tools/bsd-check.sh" tests/test-b.sh
assert_rc "AC4.2 no bash 3.2: the suite's exit code (0) is the tool's" 0
assert_contains "AC4.2 no bash 3.2: the hint names tools/get-bash32.sh" "$OUT" "get-bash32"
assert_contains "AC4.2 no bash 3.2: the suite still ran" "$OUT" "suite b ran"
assert_contains "AC4.2 no bash 3.2: the nested call still ran" "$OUT" "nested ran"
assert_not_contains "AC4.2 no bash 3.2: no 'bash is' line" "$OUT" "bsd-check: bash is"
assert_contains "AC4.2 no bash 3.2: the awk line is still printed" "$OUT" "bsd-check: awk is original-awk"
run env -i PATH="$W/bb5:$BARE" HOME="$W/home5" TMPDIR="$W" STUB_RC=4 "$BASH_BIN" "$D/tools/bsd-check.sh" tests/test-b.sh
assert_rc "AC4.2 no bash 3.2: a failing suite's exit code (4) is passed through" 4


# ---- v0.23.0 review: a bash that is not 3.2 is refused, not accepted silently ----
echo "AC4.2 review: a bash3.2 that reports version 5.x is refused with a message naming the version"
D="$W/b6"; mk_tree "$D"; mk_bash_suite "$D"; fake_awk "$W/bb6" original-awk "$W/bb6.log"
FB5="$W/fb5/bash3.2"; fake_bash "$FB5" "$W/fb5.log" "5.2.15(1)-release"
mkdir -p "$W/home6"
run env -i PATH="$W/bb6:$BARE" HOME="$W/home6" TMPDIR="$W" PB_BASH32="$FB5" "$BASH_BIN" "$D/tools/bsd-check.sh" tests/test-b.sh
assert_contains "AC4.2 review: the message names the version found (5.2)" "$OUT" "5.2"
assert_not_contains "AC4.2 review: no 'bsd-check: bash is' line for it" "$OUT" "bsd-check: bash is $FB5"
assert_not_contains "AC4.2 review: the suite did not run through the 5.x wrapper" "$(cat "$W/fb5.log" 2>/dev/null)" "tests/test-b.sh"
assert_contains "AC4.2 review: the message says it is not bash 3.2 (refused) or points at get-bash32" "$(printf '%s' "$OUT" | tr 'A-Z' 'a-z')" "3.2"
echo "AC4.2 review: a real 3.2 version report is still accepted"
D="$W/b7"; mk_tree "$D"; mk_bash_suite "$D"; fake_awk "$W/bb7" original-awk "$W/bb7.log"
FB32="$W/fb7/bash3.2"; fake_bash "$FB32" "$W/fb7.log" "3.2.57(1)-release"
run env -i PATH="$W/bb7:$BARE" HOME="$W/home6" TMPDIR="$W" PB_BASH32="$FB32" "$BASH_BIN" "$D/tools/bsd-check.sh" tests/test-b.sh
assert_contains "AC4.2 review: a 3.2 report is accepted" "$OUT" "bsd-check: bash is $FB32"


# ---- v0.23.2 AC5.1: a rejected candidate is followed by the next one ----
echo "v0.23.2 AC5.1 a rejected PB_BASH32 is followed by ~/.local/bin/bash3.2"
D="$W/c1"; mk_tree "$D"; mk_bash_suite "$D"; fake_awk "$W/bc1" original-awk "$W/bc1.log"
HC="$W/homec1"; mkdir -p "$HC/.local/bin"
fake_bash "$HC/.local/bin/bash3.2" "$W/c1home.log" "3.2.57(1)-release"
fake_bash "$W/c1env/bash3.2" "$W/c1env.log" "5.2.15(1)-release"
run env -i PATH="$W/bc1:$BARE" HOME="$HC" TMPDIR="$W" PB_BASH32="$W/c1env/bash3.2" "$BASH_BIN" "$D/tools/bsd-check.sh" tests/test-b.sh
assert_contains "AC5.1 next candidate: 'bash is' names ~/.local/bin/bash3.2" "$OUT" "bsd-check: bash is $HC/.local/bin/bash3.2"
assert_contains "AC5.1 next candidate: the rejected PB_BASH32 is named" "$OUT" "$W/c1env/bash3.2"
assert_contains "AC5.1 next candidate: the rejected version (5.2) is named" "$OUT" "5.2"
assert_not_contains "AC5.1 next candidate: no 'no bash 3.2 found' when one is 3.2" "$OUT" "no bash 3.2 found"
assert_not_contains "AC5.1 next candidate: the rejected bash never ran the suite" "$(cat "$W/c1env.log" 2>/dev/null)" "tests/test-b.sh"
assert_contains "AC5.1 next candidate: the 3.2 from HOME ran the suite" "$(cat "$W/c1home.log" 2>/dev/null)" "tests/test-b.sh"
assert_contains "AC5.1 next candidate: the suite still ran" "$OUT" "suite b ran"
assert_rc "AC5.1 next candidate: exit 0" 0

echo "v0.23.2 AC5.1 a rejected ~/.local/bin/bash3.2 is followed by bash3.2 on PATH"
D="$W/c2"; mk_tree "$D"; mk_bash_suite "$D"; fake_awk "$W/bc2" original-awk "$W/bc2.log"
HC2="$W/homec2"; mkdir -p "$HC2/.local/bin"
fake_bash "$HC2/.local/bin/bash3.2" "$W/c2home.log" "4.4.20(1)-release"
fake_bash "$W/c2path/bash3.2" "$W/c2path.log" "3.2.57(1)-release"
run env -i PATH="$W/bc2:$W/c2path:$BARE" HOME="$HC2" TMPDIR="$W" "$BASH_BIN" "$D/tools/bsd-check.sh" tests/test-b.sh
assert_contains "AC5.1 PATH candidate: 'bash is' names bash3.2 on PATH" "$OUT" "bsd-check: bash is $W/c2path/bash3.2"
assert_contains "AC5.1 PATH candidate: the rejected HOME one is named" "$OUT" "$HC2/.local/bin/bash3.2"
assert_contains "AC5.1 PATH candidate: the rejected version (4.4) is named" "$OUT" "4.4"
assert_not_contains "AC5.1 PATH candidate: no 'no bash 3.2 found'" "$OUT" "no bash 3.2 found"

echo "v0.23.2 AC5.1 two rejected candidates, then a 3.2: each one named with its version"
D="$W/c3"; mk_tree "$D"; mk_bash_suite "$D"; fake_awk "$W/bc3" original-awk "$W/bc3.log"
HC3="$W/homec3"; mkdir -p "$HC3/.local/bin"
fake_bash "$W/c3env/bash3.2" "$W/c3env.log" "5.2.15(1)-release"
fake_bash "$HC3/.local/bin/bash3.2" "$W/c3home.log" "4.4.20(1)-release"
fake_bash "$W/c3path/bash3.2" "$W/c3path.log" "3.2.57(1)-release"
run env -i PATH="$W/bc3:$W/c3path:$BARE" HOME="$HC3" TMPDIR="$W" PB_BASH32="$W/c3env/bash3.2" "$BASH_BIN" "$D/tools/bsd-check.sh" tests/test-b.sh
assert_contains "AC5.1 three candidates: the last one (3.2) is used" "$OUT" "bsd-check: bash is $W/c3path/bash3.2"
assert_contains "AC5.1 three candidates: PB_BASH32 is named as rejected" "$OUT" "$W/c3env/bash3.2"
assert_contains "AC5.1 three candidates: the HOME one is named as rejected" "$OUT" "$HC3/.local/bin/bash3.2"
assert_contains "AC5.1 three candidates: version 5.2 is named" "$OUT" "5.2"
assert_contains "AC5.1 three candidates: version 4.4 is named" "$OUT" "4.4"
assert_not_contains "AC5.1 three candidates: no 'no bash 3.2 found'" "$OUT" "no bash 3.2 found"

echo "v0.23.2 AC5.1 'no bash 3.2 found' only when none of the candidates is 3.2"
D="$W/c4"; mk_tree "$D"; mk_bash_suite "$D"; fake_awk "$W/bc4" original-awk "$W/bc4.log"
HC4="$W/homec4"; mkdir -p "$HC4/.local/bin"
fake_bash "$W/c4env/bash3.2" "$W/c4env.log" "5.2.15(1)-release"
fake_bash "$HC4/.local/bin/bash3.2" "$W/c4home.log" "4.4.20(1)-release"
fake_bash "$W/c4path/bash3.2" "$W/c4path.log" "5.0.17(1)-release"
run env -i PATH="$W/bc4:$W/c4path:$BARE" HOME="$HC4" TMPDIR="$W" PB_BASH32="$W/c4env/bash3.2" "$BASH_BIN" "$D/tools/bsd-check.sh" tests/test-b.sh
assert_contains "AC5.1 none is 3.2: 'no bash 3.2 found' is printed" "$OUT" "no bash 3.2 found"
assert_not_contains "AC5.1 none is 3.2: no 'bash is' line" "$OUT" "bsd-check: bash is"
assert_contains "AC5.1 none is 3.2: PB_BASH32 is named with 5.2" "$OUT" "$W/c4env/bash3.2"
assert_contains "AC5.1 none is 3.2: the HOME one is named" "$OUT" "$HC4/.local/bin/bash3.2"
assert_contains "AC5.1 none is 3.2: the PATH one is named" "$OUT" "$W/c4path/bash3.2"
assert_contains "AC5.1 none is 3.2: version 4.4 is named" "$OUT" "4.4"
assert_contains "AC5.1 none is 3.2: version 5.0 is named" "$OUT" "5.0"
assert_contains "AC5.1 none is 3.2: the suite still ran" "$OUT" "suite b ran"
assert_rc "AC5.1 none is 3.2: the suite's exit code (0) is the tool's" 0

echo "v0.23.2 AC5.1 a missing PB_BASH32 file falls through to the next candidate (no rejection message needed)"
D="$W/c5"; mk_tree "$D"; mk_bash_suite "$D"; fake_awk "$W/bc5" original-awk "$W/bc5.log"
HC5="$W/homec5"; mkdir -p "$HC5/.local/bin"
fake_bash "$HC5/.local/bin/bash3.2" "$W/c5home.log" "3.2.57(1)-release"
run env -i PATH="$W/bc5:$BARE" HOME="$HC5" TMPDIR="$W" PB_BASH32="$W/c5none/bash3.2" "$BASH_BIN" "$D/tools/bsd-check.sh" tests/test-b.sh
assert_contains "AC5.1 PB_BASH32 not executable: ~/.local/bin/bash3.2 is used" "$OUT" "bsd-check: bash is $HC5/.local/bin/bash3.2"


echo "v0.23.2 fix LOW-8 a PB_BASH32 that is missing or not executable is named in a note"
D="$W/c6"; mk_tree "$D"; mk_bash_suite "$D"; fake_awk "$W/bc6" original-awk "$W/bc6.log"
HC6="$W/homec6"; mkdir -p "$HC6/.local/bin"
fake_bash "$HC6/.local/bin/bash3.2" "$W/c6home.log" "3.2.57(1)-release"
run env -i PATH="$W/bc6:$BARE" HOME="$HC6" TMPDIR="$W" PB_BASH32="$W/c6none/bash3.2" "$BASH_BIN" "$D/tools/bsd-check.sh" tests/test-b.sh
assert_contains "LOW-8 a missing PB_BASH32 is named in a note" "$OUT" "$W/c6none/bash3.2"
assert_contains "LOW-8 ... the note names the variable" "$OUT" "PB_BASH32"
assert_contains "LOW-8 ... and the next candidate is still used" "$OUT" "bsd-check: bash is $HC6/.local/bin/bash3.2"
mkdir -p "$W/c6ne"; printf '#!/bin/sh\nexit 0\n' > "$W/c6ne/bash3.2"; chmod -x "$W/c6ne/bash3.2"
run env -i PATH="$W/bc6:$BARE" HOME="$HC6" TMPDIR="$W" PB_BASH32="$W/c6ne/bash3.2" "$BASH_BIN" "$D/tools/bsd-check.sh" tests/test-b.sh
assert_contains "LOW-8 a non-executable PB_BASH32 is named in a note" "$OUT" "$W/c6ne/bash3.2"
assert_contains "LOW-8 ... the note names the variable" "$OUT" "PB_BASH32"
run env -i PATH="$W/bc6:$BARE" HOME="$HC6" TMPDIR="$W" "$BASH_BIN" "$D/tools/bsd-check.sh" tests/test-b.sh
assert_not_contains "LOW-8 with PB_BASH32 unset there is no such note" "$OUT" "PB_BASH32"

# ---- v0.23.3 lane A (tester): AC9 (R11) a candidate that hangs, a candidate that is the same file as an earlier one ----
# hang_bash PATH LOG -> PATH is a "bash" that logs its call and then never answers (exec: killing it ends the sleep too)
hang_bash() {
  mkdir -p "$(dirname "$1")"
  printf '#!/bin/sh\necho "called" >> "%s"\nexec sleep 30\n' "$2" > "$1"
  chmod +x "$1"
}
echo "v0.23.3 AC9.1 a candidate whose version probe hangs is rejected after PB_BSD_PROBE_SECS, and the next one is tried"
D="$W/d1"; mk_tree "$D"; mk_bash_suite "$D"; fake_awk "$W/bd1" original-awk "$W/bd1.log"
HD1="$W/homed1"; mkdir -p "$HD1/.local/bin"
fake_bash "$HD1/.local/bin/bash3.2" "$W/d1home.log" "3.2.57(1)-release"
hang_bash "$W/d1hang/bash3.2" "$W/d1hang.log"
T0="$(date +%s)"
run env -i PATH="$W/bd1:$BARE" HOME="$HD1" TMPDIR="$W" PB_BASH32="$W/d1hang/bash3.2" PB_BSD_PROBE_SECS=1 "$BASH_BIN" "$D/tools/bsd-check.sh" tests/test-b.sh
T1="$(date +%s)"
assert_rc "AC9.1 a hanging first candidate, a good second one: exit 0" 0
assert_contains "AC9.1 the hanging candidate is named" "$OUT" "$W/d1hang/bash3.2"
assert_contains "AC9.1 the rejection says: no answer within 1 s" "$OUT" "no answer within 1 s"
assert_contains "AC9.1 the next candidate is used" "$OUT" "bsd-check: bash is $HD1/.local/bin/bash3.2"
assert_not_contains "AC9.1 no 'no bash 3.2 found' when the next one is 3.2" "$OUT" "no bash 3.2 found"
assert_contains "AC9.1 the hanging candidate was asked once" "$(cat "$W/d1hang.log" 2>/dev/null)" "called"
assert_contains "AC9.1 the good candidate ran the suite" "$(cat "$W/d1home.log" 2>/dev/null)" "tests/test-b.sh"
assert_contains "AC9.1 the suite ran" "$OUT" "suite b ran"
assert_eq "AC9.1 the tool did not wait for the 30 s sleep of the hanging candidate (took $((T1 - T0)) s)" "ok" "$([ $((T1 - T0)) -lt 25 ] && echo ok || echo "took $((T1 - T0)) s")"

echo "v0.23.3 AC9.1 the probe limit is 5 s by default"
D="$W/d1b"; mk_tree "$D"; mk_bash_suite "$D"; fake_awk "$W/bd1b" original-awk "$W/bd1b.log"
rm -f "$W/d1hang.log"
run env -i PATH="$W/bd1b:$BARE" HOME="$HD1" TMPDIR="$W" PB_BASH32="$W/d1hang/bash3.2" "$BASH_BIN" "$D/tools/bsd-check.sh" tests/test-b.sh
assert_rc "AC9.1 default limit: a hanging first candidate, a good second one: exit 0" 0
assert_contains "AC9.1 default limit: the rejection says: no answer within 5 s" "$OUT" "no answer within 5 s"
assert_contains "AC9.1 default limit: the next candidate is used" "$OUT" "bsd-check: bash is $HD1/.local/bin/bash3.2"

echo "v0.23.3 AC9.1 every candidate hanging: the hint is printed and the suites still run"
D="$W/d1c"; mk_tree "$D"; mk_bash_suite "$D"; fake_awk "$W/bd1c" original-awk "$W/bd1c.log"
mkdir -p "$W/homed1c"
run env -i PATH="$W/bd1c:$BARE" HOME="$W/homed1c" TMPDIR="$W" PB_BASH32="$W/d1hang/bash3.2" PB_BSD_PROBE_SECS=1 "$BASH_BIN" "$D/tools/bsd-check.sh" tests/test-b.sh
assert_contains "AC9.1 all candidates hung: the hanging one is named with the limit" "$OUT" "no answer within 1 s"
assert_contains "AC9.1 all candidates hung: 'no bash 3.2 found'" "$OUT" "no bash 3.2 found"
assert_contains "AC9.1 all candidates hung: the suite still ran" "$OUT" "suite b ran"
assert_rc "AC9.1 all candidates hung: the suite's exit code (0) is the tool's" 0

echo "v0.23.3 AC9.2 a candidate that is the same file as an earlier one is not probed or named twice"
# a symlink to the earlier candidate, then a hard link to it
for kind in symlink hardlink; do
  D="$W/e_$kind"; mk_tree "$D"; mk_bash_suite "$D"; fake_awk "$W/be_$kind" original-awk "$W/be_$kind.log"
  HE="$W/homee_$kind"; mkdir -p "$HE/.local/bin"
  FA="$W/e_${kind}_a/bash3.2"; fake_bash "$FA" "$W/e_$kind.log" "5.2.15(1)-release"
  fake_bash "$W/e_${kind}_path/bash3.2" "$W/e_${kind}_good.log" "3.2.57(1)-release"
  DUP=""
  case "$kind" in
    symlink) if [ "$SYMLINKS" = 1 ] && ln -s "$FA" "$HE/.local/bin/bash3.2" 2>/dev/null; then DUP="$HE/.local/bin/bash3.2"; fi ;;
    hardlink) if ln "$FA" "$HE/.local/bin/bash3.2" 2>/dev/null && [ "$HE/.local/bin/bash3.2" -ef "$FA" ]; then DUP="$HE/.local/bin/bash3.2"; fi ;;
  esac
  if [ -z "$DUP" ]; then t_skip 6 "AC9.2 $kind (this file system cannot make one)"; continue; fi
  rm -f "$W/e_$kind.log"
  run env -i PATH="$W/be_$kind:$W/e_${kind}_path:$BARE" HOME="$HE" TMPDIR="$W" PB_BASH32="$FA" "$BASH_BIN" "$D/tools/bsd-check.sh" tests/test-b.sh
  assert_eq "AC9.2 $kind: the earlier candidate is named once (one 'reports bash version' line)" "1" "$(printf '%s\n' "$OUT" | grep -c 'reports bash version')"
  assert_contains "AC9.2 $kind: the earlier candidate is named with its version" "$OUT" "$FA"
  assert_eq "AC9.2 $kind: the earlier candidate was probed once" "1" "$(grep -c '^called ' "$W/e_$kind.log" 2>/dev/null)"
  assert_not_contains "AC9.2 $kind: the second spelling of the same file is not named" "$OUT" "$DUP"
  assert_contains "AC9.2 $kind: a later, different 3.2 on PATH is used" "$OUT" "bsd-check: bash is $W/e_${kind}_path/bash3.2"
  assert_rc "AC9.2 $kind: exit 0" 0
done
echo "v0.23.3 AC9.2 the same path from PB_BASH32 and from PATH is probed and named once"
D="$W/e_sp"; mk_tree "$D"; mk_bash_suite "$D"; fake_awk "$W/be_sp" original-awk "$W/be_sp.log"
mkdir -p "$W/homee_sp"
FA="$W/e_sp_a/bash3.2"; fake_bash "$FA" "$W/e_sp.log" "5.2.15(1)-release"
run env -i PATH="$W/be_sp:$W/e_sp_a:$BARE" HOME="$W/homee_sp" TMPDIR="$W" PB_BASH32="$FA" "$BASH_BIN" "$D/tools/bsd-check.sh" tests/test-b.sh
assert_eq "AC9.2 same path: named once (one 'reports bash version' line)" "1" "$(printf '%s\n' "$OUT" | grep -c 'reports bash version')"
assert_eq "AC9.2 same path: probed once" "1" "$(grep -c '^called ' "$W/e_sp.log" 2>/dev/null)"
assert_contains "AC9.2 same path: no 3.2 anywhere, so 'no bash 3.2 found'" "$OUT" "no bash 3.2 found"
t_summary
