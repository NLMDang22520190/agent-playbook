#!/usr/bin/env bash
# Tests for scripts/proof-check.sh (compares the tree: fingerprints of evidence blocks with the working tree)
. "$(dirname "$0")/lib.sh"
PROOF="$PB_ROOT/scripts/proof-run.sh"
CHECK="$PB_ROOT/scripts/proof-check.sh"
export PLAYBOOK_HOME="$(mk_tmp)"
REP="$(mk_tmp)"   # reports live outside the repo unless a test says otherwise

R="$(mk_tmp)"; mk_repo "$R"; cd "$R" || exit 3

echo "proof-check.sh usage"
run bash "$CHECK"
assert_rc "no argument exits 2" 2
run bash "$CHECK" "$REP/no-such-report.md"
assert_rc "unreadable report exits 2" 2
run bash "$CHECK" "$REP/a.md" "$REP/b.md"
assert_rc "two arguments exit 2" 2

echo "--tree prints the current fingerprint"
run bash "$CHECK" --tree
assert_rc "--tree exits 0" 0
assert_eq "clean repo: fingerprint is the HEAD tree" "$(git rev-parse 'HEAD^{tree}')" "$OUT"
N="$(mk_tmp)"
run_in "$N" bash "$CHECK" --tree
assert_eq "outside git: --tree prints none" "none" "$OUT"

echo "fresh"
bash "$PROOF" --label unit -- true > "$REP/r1.md"
run bash "$CHECK" "$REP/r1.md"
assert_rc "unchanged tree: exit 0" 0
assert_contains "block reported fresh with its label" "$OUT" "fresh: unit"
run_in "$R/src" bash "$CHECK" "$REP/r1.md"
assert_rc "fresh when run from a subdirectory" 0
awk '{ printf "%s\r\n", $0 }' "$REP/r1.md" > "$REP/crlf.md"
run bash "$CHECK" "$REP/crlf.md"
assert_rc "CRLF report (pasted PR body) still fresh" 0
mkdir -p .agents/handoff
bash "$PROOF" --label inrepo -- true > .agents/handoff/report.md
run bash "$CHECK" .agents/handoff/report.md
assert_rc "a report written under .agents/handoff does not make itself stale" 0
printf '*.log\n' >> .git/info/exclude
printf 'junk\n' > junk.log
run bash "$CHECK" "$REP/r1.md"
assert_rc "an ignored file does not change freshness" 0
printf 'staged\n' > staged.txt
bash "$PROOF" --label pre-stage -- true > "$REP/r2.md"
git add staged.txt
run bash "$CHECK" "$REP/r2.md"
assert_rc "staging a file does not change the fingerprint" 0
git rm -q --cached staged.txt
rm -f staged.txt

echo "stale"
printf 'module.exports = 2;\n' > src/app.js
run bash "$CHECK" "$REP/r1.md"
assert_rc "edited tracked file: exit 1" 1
assert_contains "block reported stale with its label" "$OUT" "stale: unit"
printf 'module.exports = 1;\n' > src/app.js
run bash "$CHECK" "$REP/r1.md"
assert_rc "restoring the content makes the block fresh again" 0
run bash "$CHECK" "$REP/r2.md"
assert_rc "untracked file present at run time and removed since: exit 1" 1
printf 'new\n' > new-file.txt
run bash "$CHECK" "$REP/r1.md"
assert_rc "new untracked file: exit 1" 1
assert_contains "new untracked file: stale" "$OUT" "stale: unit"

echo "missing"
printf '### Evidence: old\n- command: `true`\n- exit: 0\n- git: abc1234\n' > "$REP/old.md"
run bash "$CHECK" "$REP/old.md"
assert_rc "block without a tree line: exit 1" 1
assert_contains "block without a tree line: missing" "$OUT" "missing: old"
printf '### Evidence: outside\n- git: n/a\n- tree: none\n' > "$REP/none.md"
run bash "$CHECK" "$REP/none.md"
assert_rc "tree: none cannot be checked: exit 1" 1
assert_contains "tree: none reported missing" "$OUT" "missing: outside"
printf 'All tests pass.\n' > "$REP/empty.md"
run bash "$CHECK" "$REP/empty.md"
assert_rc "report with no evidence block: exit 1" 1
assert_contains "report with no evidence block: missing" "$OUT" "missing"

echo "several blocks"
bash "$PROOF" --label now -- true > "$REP/now.md"
cat "$REP/now.md" "$REP/r1.md" "$REP/old.md" > "$REP/mix.md"
run bash "$CHECK" "$REP/mix.md"
assert_rc "one stale or missing block fails the report" 1
assert_contains "mixed: fresh block listed" "$OUT" "fresh: now"
assert_contains "mixed: stale block listed" "$OUT" "stale: unit"
assert_contains "mixed: missing block listed" "$OUT" "missing: old"
cat "$REP/now.md" "$REP/now.md" > "$REP/both.md"
run bash "$CHECK" "$REP/both.md"
assert_rc "all blocks fresh: exit 0" 0

echo "outside git"
run_in "$N" bash "$CHECK" "$REP/now.md"
assert_rc "recorded hash, no repo now: exit 1" 1
assert_contains "recorded hash, no repo now: stale" "$OUT" "stale: now"

echo "repo that gitignores .agents/handoff (the usual setup)"
G="$(mk_tmp)"; mk_repo "$G"
( cd "$G" && printf '.agents/handoff/\n' > .gitignore && mkdir -p .agents/handoff &&
  printf 'kept\n' > .agents/handoff/tracked.md && git add .gitignore && git add -f .agents/handoff/tracked.md &&
  git commit -q -m ignore-handoff )
run_in "$G" bash "$CHECK" --tree
assert_rc "ignored handoff dir: --tree exits 0" 0
assert_eq "ignored handoff dir: fingerprint is the HEAD tree minus .agents/handoff" \
  "$( cd "$G" && git rm -q -r --cached .agents/handoff && git write-tree; git reset -q )" "$OUT"
( cd "$G" && bash "$PROOF" --label ign -- true > "$REP/ign.md" )
run_in "$G" bash "$CHECK" "$REP/ign.md"
assert_rc "ignored handoff dir: fresh block exits 0" 0
assert_contains "ignored handoff dir: block reported fresh" "$OUT" "fresh: ign"
printf 'edited\n' > "$G/.agents/handoff/tracked.md"
run_in "$G" bash "$CHECK" "$REP/ign.md"
assert_rc "editing a tracked file under .agents/handoff keeps the block fresh" 0

t_summary
