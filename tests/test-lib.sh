#!/usr/bin/env bash
# Tests for tests/lib.sh skip counting (#4 AC4.1, AC4.2). Each case runs a tiny suite in its own process.
. "$(dirname "$0")/lib.sh"

# suite BODY -> runs a script that sources lib.sh, runs BODY, then t_summary; sets OUT and RC
suite() {
  local f; f="$(mk_tmp)/test-demo.sh"
  printf 'PB_LIB_ALLOW_ANYWHERE=1\n. "%s/tests/lib.sh"\n%s\nt_summary\n' "$PB_ROOT" "$1" > "$f"
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
  # shellcheck source=/dev/null
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


# ---- v0.23.3 lane A review round 3 MINOR-3: the comment above pb_lost_exec_paths states the real cost bound ----
echo "v0.23.3 lane A review round 3 MINOR-3 scripts/lib.sh: the comment on pb_lost_exec_paths says where the process bound holds"
LIBCMT="$(awk '/^#/ { buf = buf $0 "\n"; next } /^pb_lost_exec_paths\(\)/ { printf "%s", buf; exit } { buf = "" }' "$SLIB" | tr 'A-Z' 'a-z')"
if [ -n "$LIBCMT" ]; then t_ok "R3 m3 the comment block above pb_lost_exec_paths was found"; else t_bad "R3 m3 the comment block above pb_lost_exec_paths was found" "no # block right above 'pb_lost_exec_paths() {' in scripts/lib.sh"; fi
if printf '%s\n' "$LIBCMT" | grep -Eq '(10|ten)[- ]process'; then t_ok "R3 m3 the comment names the 10-process bound"; else t_bad "R3 m3 the comment names the 10-process bound" "no '10 process' / '10-process' in the comment"; fi
if printf '%s\n' "$LIBCMT" | grep -Fq 'unreadable'; then t_ok "R3 m3 the comment says the bound holds for unreadable files (the word 'unreadable')"; else t_bad "R3 m3 the comment says the bound holds for unreadable files (the word 'unreadable')" "no 'unreadable' in the comment"; fi
if printf '%s\n' "$LIBCMT" | grep -Fq 'clean filter'; then t_ok "R3 m3 the comment names a failing clean filter"; else t_bad "R3 m3 the comment names a failing clean filter" "no 'clean filter' in the comment"; fi
if printf '%s\n' "$LIBCMT" | grep -Eq 'bisect'; then t_ok "R3 m3 the comment says a readable file that fails bisects"; else t_bad "R3 m3 the comment says a readable file that fails bisects" "no word bisect in the comment"; fi
# ---- v0.24.22: a suite run from outside tests/ refuses to start (v0.24.21: a copy under .agents/handoff sourced the real lib.sh,
#      PB_ROOT pointed into the real repo and the helpers committed there) ----
echo "v0.24.22 tests/lib.sh refuses a suite that does not live in PB_ROOT/tests"
GD="$(mk_tmp)"; mkdir -p "$GD/repo/tests" "$GD/repo/.agents/handoff" "$GD/tmpbase" "$GD/other"
cp "$PB_ROOT/tests/lib.sh" "$GD/repo/tests/lib.sh"
printf '. "$(dirname "$0")/lib.sh"\ntouch "$PB_ROOT/WROTE"\nt_ok in_place\nt_summary\n' > "$GD/repo/tests/test-x.sh"
printf '. "%s/tests/lib.sh"\ntouch "$PB_ROOT/WROTE"\nt_ok stray\nt_summary\n' "$GD/repo" > "$GD/repo/.agents/handoff/test-x.sh"
printf '. "%s/tests/lib.sh"\ntouch "%s/WROTE"\nt_ok stray\nt_summary\n' "$PB_ROOT" "$GD/other" > "$GD/other/test-x.sh"
run env -u PB_LIB_ALLOW_ANYWHERE TMPDIR="$GD/tmpbase" bash "$GD/repo/.agents/handoff/test-x.sh"
assert_rc "v24.22 a copy under the repo (.agents/handoff) exits 2" 2
assert_contains "v24.22 ... and says why" "$OUT" "refusing to run"
assert_not_contains "v24.22 ... no suite output" "$OUT" "passed"
assert_no_path "v24.22 ... nothing written into the repo" "$GD/repo/WROTE"
assert_eq "v24.22 ... no temp file made before the refusal" "" "$(ls -A "$GD/tmpbase")"
run env -u PB_LIB_ALLOW_ANYWHERE TMPDIR="$GD/tmpbase" bash "$GD/other/test-x.sh"
assert_rc "v24.22 a copy in a temp dir that sources the real lib.sh exits 2" 2
assert_contains "v24.22 ... and says why" "$OUT" "refusing to run"
assert_no_path "v24.22 ... nothing written" "$GD/other/WROTE"
assert_no_path "v24.22 ... nothing written into the real repo" "$PB_ROOT/WROTE"
run env -u PB_LIB_ALLOW_ANYWHERE TMPDIR="$GD/tmpbase" bash "$GD/repo/tests/test-x.sh"
assert_rc "v24.22 the canonical run (suite in PB_ROOT/tests) works" 0
assert_contains "v24.22 ... and runs the helpers" "$OUT" "test-x.sh: 1 passed, 0 failed"
assert_file "v24.22 ... and the suite body ran" "$GD/repo/WROTE"
t_summary
