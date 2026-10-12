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


# ---- v0.23.0 AC4.2: bash 3.2 is linked as `bash` next to awk, so nested `bash tests/...` calls use it ----
# The fake bash 3.2 is a wrapper that logs and execs the real bash, so no real bash 3.2 is needed.
echo "AC4.2 the suites run under bash 3.2 when it is available"
REAL_BASH="$(command -v bash)"
# fake_bash PATH LOG -> PATH is a wrapper script: logs its arguments, then execs the real bash
fake_bash() {
  mkdir -p "$(dirname "$1")"
  printf '#!/bin/sh\necho "called %s $*" >> "%s"\nexec "%s" "$@"\n' "$1" "$2" "$REAL_BASH" > "$1"
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

t_summary
