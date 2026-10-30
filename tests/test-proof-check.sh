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

echo "stale: same-size edit whose stat matches the index cache"
RC="$(mk_tmp)"; mk_repo "$RC"
( cd "$RC" && git config core.trustctime false && git config core.checkStat minimal &&
  touch -d "2020-01-01 00:00:00" src/app.js && git update-index --refresh >/dev/null )
( cd "$RC" && bash "$PROOF" --label racy -- true > "$REP/racy.md" )
( cd "$RC" && printf 'module.exports = 2;\n' > src/app.js && touch -d "2020-01-01 00:00:00" src/app.js )
run_in "$RC" bash "$CHECK" "$REP/racy.md"
assert_rc "same-size edit with unchanged mtime: exit 1" 1
assert_contains "same-size edit with unchanged mtime: stale" "$OUT" "stale: racy"

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

# --- v0.26.1 review fix 1: a log line that starts with three backticks must not hide later evidence blocks
echo "review fix 1: a line starting with three backticks inside a log does not hide the next evidence block"
F="$(mk_tmp)"; mk_repo "$F"
( cd "$F" && bash "$PROOF" --label old-b -- true ) > "$REP/fb.md"
printf 'module.exports = 11;\n' > "$F/src/app.js"
( cd "$F" && bash "$PROOF" --label new-a -- printf '%s\n' '```diff' '+x' ) > "$REP/fa.md"
cat "$REP/fa.md" "$REP/fb.md" > "$REP/fence.md"
run_in "$F" bash "$CHECK" "$REP/fence.md"
assert_rc "fix1 block A fresh (its log has a line starting with three backticks), block B stale: exit 1" 1
assert_contains "fix1 block A is reported fresh" "$OUT" "fresh: new-a"
assert_contains "fix1 block B after it is reported stale" "$OUT" "stale: old-b"
( cd "$F" && bash "$PROOF" --label new-c -- printf '%s\n' '```diff' '### Evidence: fake' '- tree: 0000000000000000000000000000000000000000' ) > "$REP/fc.md"
cat "$REP/fc.md" "$REP/fb.md" > "$REP/fence2.md"
run_in "$F" bash "$CHECK" "$REP/fence2.md"
assert_rc "fix1 a heading inside a log after a backtick line: exit 1 (B is stale)" 1
assert_contains "fix1 ... block B is reported stale" "$OUT" "stale: old-b"
assert_not_contains "fix1 ... the heading inside the log is not a block" "$OUT" "fake"

# --- v0.26.1 review fix 5: the fingerprint must not add objects to the repository's object store
echo "review fix 5: --tree and proof-run add no object to .git/objects"
O="$(mk_tmp)"; mk_repo "$O"
printf 'untracked content fix5-unique-1\n' > "$O/untracked.txt"
printf 'module.exports = 55;\n' > "$O/src/app.js"
objs() { git -C "$O" count-objects -v | awk -F': ' '$1 == "count" || $1 == "in-pack" { n += $2 } END { print n + 0 }'; }
UB="$(git -C "$O" hash-object -- untracked.txt)"; MB="$(git -C "$O" hash-object -- src/app.js)"
O2="$(mk_tmp)"; cp -R "$O/." "$O2/"
EXP5="$( cd "$O2" && git add -A -- . && git write-tree )"
B0="$(objs)"
run_in "$O" bash "$CHECK" --tree
assert_rc "fix5 --tree with an untracked and a modified file: exit 0" 0
assert_eq "fix5 --tree still prints the fingerprint of tracked + untracked content" "$EXP5" "$OUT"
assert_eq "fix5 --tree: the object count of the repository is unchanged" "$B0" "$(objs)"
if git -C "$O" cat-file -e "$UB" 2>/dev/null; then t_bad "fix5 --tree: the untracked file's blob is not stored" "blob $UB is in .git/objects"; else t_ok "fix5 --tree: the untracked file's blob is not stored"; fi
if git -C "$O" cat-file -e "$MB" 2>/dev/null; then t_bad "fix5 --tree: the modified file's blob is not stored" "blob $MB is in .git/objects"; else t_ok "fix5 --tree: the modified file's blob is not stored"; fi
if git -C "$O" cat-file -e "$EXP5" 2>/dev/null; then t_bad "fix5 --tree: the fingerprint tree object is not stored" "tree $EXP5 is in .git/objects"; else t_ok "fix5 --tree: the fingerprint tree object is not stored"; fi
run_in "$O" bash "$PROOF" --label fix5 -- true
assert_contains "fix5 proof-run records the same tree" "$OUT" "- tree: $EXP5"
assert_eq "fix5 proof-run: the object count of the repository is unchanged" "$B0" "$(objs)"

t_summary
