#!/usr/bin/env bash
# Tests for scripts/proof-run.sh (runs a command, emits a verbatim evidence block)
. "$(dirname "$0")/lib.sh"
PROOF="$PB_ROOT/scripts/proof-run.sh"
export PLAYBOOK_HOME="$(mk_tmp)"

R="$(mk_tmp)"; mk_repo "$R"; cd "$R" || exit 3

echo "proof-run.sh"
run bash "$PROOF" --label green -- true
assert_rc "exit code of command is propagated (0)" 0
assert_contains "block heading uses the label" "$OUT" "### Evidence: green"
assert_contains "block shows exit code" "$OUT" "exit: 0"
assert_contains "block shows the command" "$OUT" "true"
assert_contains "block shows the git sha" "$OUT" "git: "

run bash "$PROOF" --label red -- sh -c 'echo failing-output; exit 3'
assert_rc "non-zero exit code is propagated" 3
assert_contains "block shows exit 3" "$OUT" "exit: 3"
assert_contains "block includes command output" "$OUT" "failing-output"

LOG="$(printf '%s\n' "$OUT" | sed -n 's/^- full log: \([^ ]*\) .*/\1/p')"
if [ -n "$LOG" ] && [ -f "$LOG" ]; then t_ok "full log file exists"; else t_bad "full log file exists" "log=[$LOG]"; fi
assert_contains "log lives under .agents/handoff/evidence" "$LOG" ".agents/handoff/evidence"
assert_contains "block records sha256 of the log" "$OUT" "sha256:"

run bash "$PROOF" --label tail --tail 5 -- sh -c 'i=1; while [ $i -le 100 ]; do echo "line-$i"; i=$((i+1)); done'
assert_contains "tail keeps the last line" "$OUT" "line-100"
assert_not_contains "tail drops early lines" "$OUT" "line-1
"

run bash "$PROOF" --label secrets -- sh -c 'echo "API_KEY=abc123secret"; echo "password: hunter2xyz"; echo "Authorization: Bearer abcdef0123456789"'
assert_not_contains "api key value redacted" "$OUT" "abc123secret"
assert_not_contains "password value redacted" "$OUT" "hunter2xyz"
assert_not_contains "bearer token redacted" "$OUT" "abcdef0123456789"
assert_contains "redaction marker present" "$OUT" "[REDACTED]"
RAW="$(printf '%s\n' "$OUT" | sed -n 's/^- full log: \([^ ]*\) .*/\1/p')"
assert_not_contains "secrets also redacted in the stored log" "$(cat "$RAW")" "abc123secret"

run bash "$PROOF" --label missing-cmd -- definitely-not-a-command-xyz
assert_rc "missing command exits 127" 127

run bash "$PROOF" --label nodash true
assert_rc "missing -- separator exits 2" 2

echo "tree fingerprint"
tree_of() { printf '%s\n' "$1" | sed -n 's/^- tree: //p'; }
run bash "$PROOF" --label tree -- true
T1="$(tree_of "$OUT")"
assert_eq "tree line is the HEAD tree in a clean repo (evidence logs left out)" "$(git rev-parse 'HEAD^{tree}')" "$T1"
GN="$(printf '%s\n' "$OUT" | grep -n '^- git: ' | cut -d: -f1)"
TN="$(printf '%s\n' "$OUT" | grep -n '^- tree: ' | cut -d: -f1)"
assert_eq "tree line follows the git line" "$((GN + 1))" "$TN"
printf 'new\n' > untracked.txt
run bash "$PROOF" --label tree2 -- true
T2="$(tree_of "$OUT")"
if [ -n "$T2" ] && [ "$T2" != "$T1" ]; then t_ok "an untracked file changes the tree"; else t_bad "an untracked file changes the tree" "T1=[$T1] T2=[$T2]"; fi
assert_eq "real index untouched: nothing staged" "" "$(git diff --cached --name-only)"
assert_eq "untracked file stays untracked" "?? untracked.txt" "$(git status --porcelain -- untracked.txt)"
run_in "$R/src" bash "$PROOF" --label tree3 -- true
assert_eq "same tree from a subdirectory" "$T2" "$(tree_of "$OUT")"
rm -f untracked.txt
printf 'x\n' > ignored.log; printf '*.log\n' >> .git/info/exclude
run bash "$PROOF" --label tree4 -- true
assert_eq "an ignored file leaves the tree unchanged" "$T1" "$(tree_of "$OUT")"
E="$(mk_tmp)"; ( cd "$E" && git init -q && printf 'a\n' > a.txt )
run_in "$E" bash "$PROOF" --label unborn -- true
case "$(tree_of "$OUT")" in none | '') t_bad "repo without commits still gets a tree hash" "$OUT" ;; *) t_ok "repo without commits still gets a tree hash" ;; esac

N="$(mk_tmp)"; cd "$N" || exit 3
run bash "$PROOF" --label nogit -- true
assert_rc "works outside git" 0
assert_contains "non-git shows git: n/a" "$OUT" "git: n/a"
assert_contains "non-git shows tree: none" "$OUT" "- tree: none"

t_summary
