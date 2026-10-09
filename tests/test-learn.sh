#!/usr/bin/env bash
# Tests for scripts/learn.sh (project-local learnings file)
. "$(dirname "$0")/lib.sh"
LEARN="$PB_ROOT/scripts/learn.sh"
export PLAYBOOK_HOME="$(mk_tmp)"
export PLAYBOOK_DATE="2026-10-09"

R="$(mk_tmp)"; mk_repo "$R"; cd "$R" || exit 3
F=".agents/LEARNINGS.md"

echo "init"
run bash "$LEARN" init
assert_rc "init ok" 0
assert_file "LEARNINGS.md created" "$F"
assert_contains ".gitignore ignores handoff" "$(cat .gitignore)" ".agents/handoff/"
run bash "$LEARN" init
assert_rc "init is idempotent" 0
assert_eq "gitignore entry not duplicated" "1" "$(grep -c '^\.agents/handoff/$' .gitignore)"
run bash "$LEARN" init --link-agents
assert_file "AGENTS.md created by --link-agents" "AGENTS.md"
assert_contains "AGENTS.md points to learnings" "$(cat AGENTS.md)" ".agents/LEARNINGS.md"
run bash "$LEARN" init --link-agents
assert_eq "pointer not duplicated" "1" "$(grep -c 'agent-playbook:learnings' AGENTS.md)"

echo "add"
run bash "$LEARN" add --title "Run lint before test" --rule "Always run pnpm lint before pnpm test." \
  --why "CI fails on lint first." --evidence "CI run 123 failed at lint step" --source failure
assert_rc "add ok" 0
assert_contains "first id" "$(cat $F)" "### L-0001 · 2026-10-09 · Run lint before test"
assert_contains "status active" "$(cat $F)" "- Status: active"
run bash "$LEARN" add --title "Use UTC" --rule "Store timestamps in UTC." \
  --why "User correction." --evidence "User said: 'always UTC' in chat" --source user --scope "src/db/**"
assert_contains "second id increments" "$(cat $F)" "### L-0002"
assert_contains "scope recorded" "$(cat $F)" "- Scope: src/db/**"

run bash "$LEARN" add --title "dup" --rule "always run pnpm lint before pnpm test." \
  --why w --evidence e --source user
assert_rc "duplicate rule (case-insensitive) rejected" 4
run bash "$LEARN" add --title "no evidence" --rule "Something new." --why w --source user
assert_rc "missing evidence rejected" 2
run bash "$LEARN" add --title t --rule r --why w --evidence e --source web
assert_rc "invalid source rejected (web content is not a valid source)" 2
run bash "$LEARN" add --title t --rule "Use token sk-abcdef1234567890abcdef" --why w --evidence e --source user
assert_rc "secret-looking content rejected" 2
LONG="$(printf 'x%.0s' $(seq 1 400))"
run bash "$LEARN" add --title t --rule "$LONG" --why w --evidence e --source user
assert_rc "over-long rule rejected" 2

echo "cap"
export LEARN_MAX_ENTRIES=2
run bash "$LEARN" add --title third --rule "A third distinct rule." --why w --evidence e --source user
assert_rc "cap reached: add rejected" 5
assert_contains "message tells how to proceed" "$OUT" "retire"

echo "retire + check"
run bash "$LEARN" retire L-0001 --reason "superseded"
assert_rc "retire ok" 0
assert_contains "retired status written" "$(cat $F)" "- Status: retired"
run bash "$LEARN" add --title third --rule "A third distinct rule." --why w --evidence e --source user
assert_rc "after retire there is room again" 0
unset LEARN_MAX_ENTRIES
run bash "$LEARN" retire L-9999 --reason x
assert_rc "retire unknown id fails" 2
run bash "$LEARN" check
assert_rc "check passes on a valid file" 0
assert_contains "check summarises counts" "$OUT" "active"
printf '### garbage entry\n' >> "$F"
run bash "$LEARN" check
assert_rc "check fails on malformed entry" 1

t_summary
