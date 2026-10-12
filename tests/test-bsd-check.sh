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
t_summary
