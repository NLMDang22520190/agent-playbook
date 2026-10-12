#!/usr/bin/env bash
# Tests for tests/lib.sh skip counting (#4 AC4.1, AC4.2). Each case runs a tiny suite in its own process.
. "$(dirname "$0")/lib.sh"

# suite BODY -> runs a script that sources lib.sh, runs BODY, then t_summary; sets OUT and RC
suite() {
  local f; f="$(mk_tmp)/test-demo.sh"
  printf '. "%s/tests/lib.sh"\n%s\nt_summary\n' "$PB_ROOT" "$1" > "$f"
  run bash "$f"
}

echo "tests/lib.sh t_skip / t_summary"
suite 't_ok one; t_ok two'
assert_rc "AC4.2 no skips, no failures -> exit 0" 0
assert_contains "AC4.2 no skips: summary unchanged" "$OUT" "test-demo.sh: 2 passed, 0 failed"
assert_not_contains "AC4.2 no skips: no 'skipped' word" "$OUT" "skipped"

suite 't_ok one; t_skip 6 "slash is writable"; t_skip 1 "no timeout"'
assert_rc "AC4.2 skips are not failures -> exit 0" 0
assert_contains "AC4.2 summary counts skipped assertions" "$OUT" "test-demo.sh: 1 passed, 0 failed, 7 skipped"
assert_contains "AC4.1 skip line names the reason" "$OUT" "slash is writable"
assert_eq "AC4.1 one '  skip ' line per t_skip call" "2" "$(printf '%s\n' "$OUT" | grep -c '^  skip ')"
assert_contains "AC4.1 skip line shows the count" "$(printf '%s\n' "$OUT" | grep 'slash is writable')" "6"

suite 't_bad broken; t_skip 2 "x"'
assert_rc "AC4.2 a failure with skips still exits 1" 1
assert_contains "AC4.2 failure summary with skips" "$OUT" "test-demo.sh: 0 passed, 1 failed, 2 skipped"


# ---- v0.23.3 lane A (tester): AC3.3 (R3) scripts/lib.sh pb_raw_lines tells an LF inside a path from a git failure ----
echo "v0.23.3 AC3.3 scripts/lib.sh pb_raw_lines: a path with an LF inside a record gets a distinct status"
SLIB="$PB_ROOT/scripts/lib.sh"
RL="$(mk_tmp)"; mk_repo "$RL"
# rawlines DIR GITSHIMDIR -> sets RAWOUT and RAWRC: pb_raw_lines --cached in DIR (a git shim dir in front of PATH when given)
rawlines() {
  RAWOUT="$( cd "$1" && { [ -z "${2:-}" ] || PATH="$2:$PATH"; . "$SLIB"; pb_raw_lines --cached; echo "rc=$?"; } 2>/dev/null )"
  RAWRC="${RAWOUT##*rc=}"; RAWOUT="${RAWOUT%rc=*}"
}
printf 'one\n' > "$RL/src/with space.js"; git -C "$RL" add -- "src/with space.js"
rawlines "$RL"
assert_eq "AC3.3 a plain staged path (with a space): status 0" "0" "$RAWRC"
assert_contains "AC3.3 ... printed as META<TAB>PATH" "$RAWOUT" "$(printf ':000000 100644 ')"
assert_contains "AC3.3 ... the path is whole" "$RAWOUT" "src/with space.js"
FSHIM="$(mk_tmp)/failgit"; mkdir -p "$FSHIM"
printf '#!/bin/sh\necho "shim: git failed" >&2\nexit 128\n' > "$FSHIM/git"; chmod +x "$FSHIM/git"
rawlines "$RL" "$FSHIM"
GITFAIL_RC="$RAWRC"
if [ "$GITFAIL_RC" != 0 ]; then t_ok "AC3.3 a failing git: nonzero status ($GITFAIL_RC)"; else t_bad "AC3.3 a failing git: nonzero status" "status 0"; fi
NLP="$(printf 'src/new\nline.js')"
if printf 'x\n' > "$RL/$NLP" 2>/dev/null && [ -f "$RL/$NLP" ] && git -C "$RL" add -- "$NLP" 2>/dev/null && git -C "$RL" ls-files --error-unmatch -- "$NLP" >/dev/null 2>&1; then
  rawlines "$RL"
  if [ "$RAWRC" != 0 ]; then t_ok "AC3.3 an LF inside a record: nonzero status ($RAWRC)"; else t_bad "AC3.3 an LF inside a record: nonzero status" "status 0, output: $RAWOUT"; fi
  if [ "$RAWRC" != 0 ] && [ "$RAWRC" != "$GITFAIL_RC" ]; then t_ok "AC3.3 ... and a failure status different from a git failure ($RAWRC vs $GITFAIL_RC)"; else t_bad "AC3.3 ... and a failure status different from a git failure" "LF status $RAWRC, git failure status $GITFAIL_RC"; fi
else rm -f "$RL/$NLP" 2>/dev/null; t_skip 2 "AC3.3 newline path (this file system or git refuses the name)"; fi

t_summary
