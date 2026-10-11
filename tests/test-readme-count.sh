#!/usr/bin/env bash
# Tests for tools/readme-count.sh (v0.22.0 AC6.1): the README test count, from a run-all log.
#   tools/readme-count.sh LOG           total = sum of passed + skipped over the "N passed, M failed[, K skipped]" lines;
#                                       rewrites the badge `tests-N`, `**N passing**` and `N tests, run in sandboxes` in
#                                       README.md (the parent of the tools directory) and prints "README: N tests (passed + skipped)"
#   tools/readme-count.sh --check LOG   only compares; exit 1 on a mismatch, nothing is written
# Exit: 0 ok, 1 a non-zero failed count in the log, no summary line, or (--check) a mismatch.
# Everything runs in a sandbox copy of the repository layout; the real README.md is never touched.
. "$(dirname "$0")/lib.sh"
TOOL="$PB_ROOT/tools/readme-count.sh"
G() { git -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }

# mkbox -> sets S (sandbox root with tools/readme-count.sh, scripts/lib.sh and a README.md copy of the real one)
mkbox() {
  S="$(mk_tmp)"; mkdir -p "$S/tools" "$S/scripts"
  [ -f "$TOOL" ] && cp "$TOOL" "$S/tools/readme-count.sh"
  cp "$PB_ROOT/scripts/lib.sh" "$S/scripts/"
  cp "$PB_ROOT/README.md" "$S/README.md"
}
sumof() { cksum < "$1"; }

assert_file "AC6.1 tools/readme-count.sh exists" "$TOOL"

echo "rewrite"
mkbox
cp "$S/README.md" "$S/README.orig"
LOG="$S/run.log"
printf '%s\n' 'test-a.sh: 10 passed, 0 failed' 'noise line' 'test-b.sh: 5 passed, 0 failed, 2 skipped' 'ALL GREEN' > "$LOG"
run_in "$S" bash tools/readme-count.sh "$LOG"
assert_rc "AC6.1 a clean log: exit 0" 0
assert_contains "AC6.1 prints the total (10 + 5 + 2 skipped = 17)" "$OUT" "README: 17 tests (passed + skipped)"
assert_contains "AC6.1 the badge is rewritten" "$(cat "$S/README.md")" "badge/tests-17"
assert_contains "AC6.1 the **N passing** place is rewritten" "$(cat "$S/README.md")" "**17 passing**"
assert_contains "AC6.1 the 'N tests, run in sandboxes' place is rewritten" "$(cat "$S/README.md")" "17 tests, run in sandboxes"
assert_eq "AC6.1 all three places say 17 (and no old number is left in them)" "3" "$(grep -oE 'badge/tests-[0-9]+|\*\*[0-9]+ passing\*\*|[0-9]+ tests, run in sandboxes' "$S/README.md" | grep -cE '17')"
assert_eq "AC6.1 exactly three lines of the README changed" "3" "$(diff "$S/README.orig" "$S/README.md" | grep -c '^>')"
assert_eq "AC6.1 the other lines of the README are byte-identical (the version badge, ...)" "$(grep -c 'badge/version-' "$S/README.orig")" "$(grep -c 'badge/version-' "$S/README.md")"
after1="$(sumof "$S/README.md")"
run_in "$S" bash tools/readme-count.sh "$LOG"
assert_rc "AC6.1 running it again (idempotent): exit 0" 0
assert_eq "AC6.1 the second run changes nothing" "$after1" "$(sumof "$S/README.md")"

echo "a log whose last summary line has no newline, and a single suite"
mkbox
printf 'test-a.sh: 5 passed, 0 failed\ntest-b.sh: 3 passed, 0 failed, 2 skipped\nprintf-c.sh: 1 passed, 0 failed' > "$S/run.log"
run_in "$S" bash tools/readme-count.sh "$S/run.log"
assert_rc "AC6.1 unterminated last line: exit 0" 0
assert_contains "AC6.1 5 + 3 + 2 + 1 = 11, last line included" "$OUT" "README: 11 tests (passed + skipped)"
assert_contains "AC6.1 README badge shows 11" "$(cat "$S/README.md")" "badge/tests-11"
mkbox
printf 'one.sh: 0 passed, 0 failed\n' > "$S/run.log"
run_in "$S" bash tools/readme-count.sh "$S/run.log"
assert_rc "AC6.1 a log with 0 passed, 0 failed is still a summary line: exit 0" 0
assert_contains "AC6.1 total 0" "$OUT" "README: 0 tests (passed + skipped)"

echo "a minimal README: only the three places change"
mkbox
cat > "$S/README.md" <<'EOF'
# demo
![version](https://img.shields.io/badge/version-1.2.3-4F5BD5) ![tests](https://img.shields.io/badge/tests-3214-1F9D63) ![x](https://img.shields.io/badge/always--on_block-44%2F60_lines-C98A00)
| Script tests | **3214 passing** (see `bash tests/run-all.sh`) |
├── tests/                  3214 tests, run in sandboxes, never touch the real HOME
Issue 3214 is unrelated, and so is 3214 passing without the stars.
EOF
printf 'a.sh: 4 passed, 0 failed\nb.sh: 6 passed, 0 failed, 1 skipped\n' > "$S/run.log"
run_in "$S" bash tools/readme-count.sh "$S/run.log"
assert_rc "AC6.1 minimal README: exit 0" 0
assert_eq "AC6.1 minimal README: the whole file after the rewrite" '# demo
![version](https://img.shields.io/badge/version-1.2.3-4F5BD5) ![tests](https://img.shields.io/badge/tests-11-1F9D63) ![x](https://img.shields.io/badge/always--on_block-44%2F60_lines-C98A00)
| Script tests | **11 passing** (see `bash tests/run-all.sh`) |
├── tests/                  11 tests, run in sandboxes, never touch the real HOME
Issue 3214 is unrelated, and so is 3214 passing without the stars.' "$(cat "$S/README.md")"

echo "refusals: a failed count, no summary line"
mkbox
before="$(sumof "$S/README.md")"
printf 'test-a.sh: 10 passed, 0 failed\ntest-b.sh: 5 passed, 1 failed, 2 skipped\n' > "$S/run.log"
run_in "$S" bash tools/readme-count.sh "$S/run.log"
assert_rc "AC6.1 a log with a non-zero failed count: exit 1" 1
assert_eq "AC6.1 a failed count leaves the README unchanged" "$before" "$(sumof "$S/README.md")"
assert_not_contains "AC6.1 a failed count does not print the README line" "$OUT" "README: "
printf 'test-a.sh: 10 passed, 3 failed\n' > "$S/run.log"
run_in "$S" bash tools/readme-count.sh "$S/run.log"
assert_rc "AC6.1 failed count on a line without skipped: exit 1" 1
assert_eq "AC6.1 ... README unchanged" "$before" "$(sumof "$S/README.md")"
printf 'test-a.sh: 10 passed, 0 failed\ntest-b.sh: 4 passed, 0 failed\ntest-c.sh: 1 passed, 12 failed\n' > "$S/run.log"
run_in "$S" bash tools/readme-count.sh "$S/run.log"
assert_rc "AC6.1 one bad suite among clean ones (12 failed, not 0 or 1): exit 1" 1
assert_eq "AC6.1 ... README unchanged" "$before" "$(sumof "$S/README.md")"
printf 'running tests\nALL GREEN\n' > "$S/run.log"
run_in "$S" bash tools/readme-count.sh "$S/run.log"
assert_rc "AC6.1 a log without any summary line: exit 1" 1
assert_eq "AC6.1 no summary line leaves the README unchanged" "$before" "$(sumof "$S/README.md")"
: > "$S/run.log"
run_in "$S" bash tools/readme-count.sh "$S/run.log"
assert_rc "AC6.1 an empty log: exit 1" 1
assert_eq "AC6.1 an empty log leaves the README unchanged" "$before" "$(sumof "$S/README.md")"
run_in "$S" bash tools/readme-count.sh --check "$S/run.log"
assert_rc "AC6.1 --check on a log without summary lines: exit 1" 1
printf 'test-a.sh: 10 passed, 1 failed\n' > "$S/run.log"
run_in "$S" bash tools/readme-count.sh --check "$S/run.log"
assert_rc "AC6.1 --check on a log with a failed count: exit 1" 1
run_in "$S" bash tools/readme-count.sh
if [ "$RC" != 0 ]; then t_ok "AC6.1 no arguments is not a success (exit $RC)"; else t_bad "AC6.1 no arguments is not a success" "exit 0; output: $OUT"; fi

echo "--check"
mkbox
printf 'test-a.sh: 10 passed, 0 failed\ntest-b.sh: 5 passed, 0 failed, 2 skipped\n' > "$S/run.log"
run_in "$S" bash tools/readme-count.sh "$S/run.log"      # README now says 17
before="$(sumof "$S/README.md")"
run_in "$S" bash tools/readme-count.sh --check "$S/run.log"
assert_rc "AC6.1 --check when README and log agree (17): exit 0" 0
assert_eq "AC6.1 --check writes nothing on a match" "$before" "$(sumof "$S/README.md")"
run_in "$S" bash tools/readme-count.sh "$S/run.log" --check
assert_rc "AC6.1 --check after the log (flag order is free): exit 0" 0
printf 'test-a.sh: 10 passed, 0 failed\ntest-b.sh: 6 passed, 0 failed, 2 skipped\n' > "$S/run2.log"   # 18
run_in "$S" bash tools/readme-count.sh --check "$S/run2.log"
assert_rc "AC6.1 --check on a mismatch (README 17, log 18): exit 1" 1
assert_contains "AC6.1 the mismatch message names the log total" "$OUT" "18"
assert_contains "AC6.1 the mismatch message names the README number" "$OUT" "17"
assert_eq "AC6.1 --check writes nothing on a mismatch" "$before" "$(sumof "$S/README.md")"
run_in "$S" bash tools/readme-count.sh "$S/run2.log" --check
assert_rc "AC6.1 --check (flag after the log) on a mismatch: exit 1" 1
assert_eq "AC6.1 --check (flag after the log) writes nothing" "$before" "$(sumof "$S/README.md")"
# one place out of date is a mismatch
mkbox
printf 'test-a.sh: 10 passed, 0 failed\ntest-b.sh: 5 passed, 0 failed, 2 skipped\n' > "$S/run.log"
run_in "$S" bash tools/readme-count.sh "$S/run.log"
node -e 'const fs=require("fs"),f=process.argv[1];fs.writeFileSync(f,fs.readFileSync(f,"utf8").replace("**17 passing**","**16 passing**"))' "$S/README.md"
before="$(sumof "$S/README.md")"
run_in "$S" bash tools/readme-count.sh --check "$S/run.log"
assert_rc "AC6.1 --check when only the **N passing** place is stale: exit 1" 1
assert_eq "AC6.1 --check does not repair it" "$before" "$(sumof "$S/README.md")"

echo "the same total as tools/release.sh"
# a release sandbox whose suite prints the same lines; the README is made by readme-count.sh, release.sh --dry-run must accept it
W="$(mk_tmp)"; O="$W/origin.git"; C="$W/clone"
git init -q --bare "$O"; git -C "$O" symbolic-ref HEAD refs/heads/main
mkdir -p "$C/tools" "$C/tests" "$C/scripts"
cp "$PB_ROOT/tools/check-release.sh" "$PB_ROOT/tools/release.sh" "$C/tools/"
[ -f "$TOOL" ] && cp "$TOOL" "$C/tools/readme-count.sh"
cp "$PB_ROOT/scripts/lib.sh" "$C/scripts/"
printf '#!/usr/bin/env bash\necho "test-a.sh: 5 passed, 0 failed"\necho "test-b.sh: 3 passed, 0 failed, 2 skipped"\nprintf "test-c.sh: 1 passed, 0 failed"\nexit 0\n' > "$C/tests/run-all.sh"
printf '1.2.3\n' > "$C/VERSION"
printf '# Changelog\n\n## 1.2.3 - 2026-01-01\n- thing\n' > "$C/CHANGELOG.md"
printf '![tests](https://img.shields.io/badge/tests-1-1F9D63)\n| x | **1 passing** |\n  1 tests, run in sandboxes\n' > "$C/README.md"
bash "$C/tests/run-all.sh" > "$W/suite.log" 2>&1
run_in "$C" bash tools/readme-count.sh "$W/suite.log"
assert_rc "AC6.1 release sandbox: readme-count.sh on the suite log: exit 0" 0
assert_contains "AC6.1 release sandbox: total 11" "$OUT" "README: 11 tests (passed + skipped)"
( cd "$C" && git init -q && git checkout -q -b main && G add -A && G commit -qm init && git remote add origin "$O" && git push -q origin main ) || echo "fixture setup failed"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC6.1 release.sh --dry-run accepts the README that readme-count.sh wrote (same total): exit 0" 0
run_in "$C" bash tools/readme-count.sh --check "$W/suite.log"
assert_rc "AC6.1 and readme-count.sh --check agrees with release.sh: exit 0" 0


echo "only suite summary lines count (assertion lines with N passed, M failed in a test name are ignored)"
ASSERT_OK="  ok   AC6.2 'Tests: 4 passed, 1 failed: subtract.': PASS"
ASSERT_BAD="  FAIL x 'Tests: 3 passed, 2 failed, 7 skipped': y"
mkbox
printf '%s\n' 'test-a.sh: 10 passed, 0 failed' "$ASSERT_OK" 'ALL GREEN' > "$S/run.log"
run_in "$S" bash tools/readme-count.sh "$S/run.log"
assert_rc "RV readme-count: an assertion line naming '4 passed, 1 failed' is not a summary: exit 0" 0
assert_contains "RV readme-count: the total is 10, the assertion line adds nothing" "$OUT" "README: 10 tests (passed + skipped)"
assert_contains "RV readme-count: the badge shows 10" "$(cat "$S/README.md")" "badge/tests-10"
run_in "$S" bash tools/readme-count.sh --check "$S/run.log"
assert_rc "RV readme-count: --check on the same log with README 10: exit 0" 0
mkbox
printf '%s\n' "$ASSERT_OK" "$ASSERT_BAD" 'test-a.sh: 10 passed, 0 failed' 'test-b.sh: 2 passed, 0 failed, 1 skipped' > "$S/run.log"
run_in "$S" bash tools/readme-count.sh "$S/run.log"
assert_rc "RV readme-count: assertion lines before and between the summaries are ignored: exit 0" 0
assert_contains "RV readme-count: 10 + 2 + 1 skipped = 13" "$OUT" "README: 13 tests (passed + skipped)"
mkbox
before="$(sumof "$S/README.md")"
printf '%s\n' "$ASSERT_OK" 'test-a.sh: 10 passed, 0 failed' 'test-b.sh: 3 passed, 1 failed' > "$S/run.log"
run_in "$S" bash tools/readme-count.sh "$S/run.log"
assert_rc "RV readme-count: a real failing summary line still refuses: exit 1" 1
assert_eq "RV readme-count: the README is unchanged after that refusal" "$before" "$(sumof "$S/README.md")"
mkbox
printf '%s\n' "$ASSERT_OK" 'noise' > "$S/run.log"
run_in "$S" bash tools/readme-count.sh "$S/run.log"
assert_rc "RV readme-count: a log with only an assertion line has no summary: exit 1" 1

t_summary
