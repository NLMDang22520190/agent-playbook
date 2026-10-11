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

# ---- v0.22.4 AC5: --role and checklist (a fresh repo; the cases above stay as they are) ----
echo "v0.22.4 AC5.1 add --role"
R2="$(mk_tmp)"; mk_repo "$R2"; cd "$R2" || exit 3
bash "$LEARN" init >/dev/null
add() { run bash "$LEARN" add --why w --evidence e --source user "$@"; }
add --title "Tester rule" --rule "Name each test after its AC." --scope "src/**" --role tester
assert_rc "AC5.1 add --role tester ok" 0
add --title "All rule" --rule "Keep commits small."
assert_rc "AC5.1 add without --role ok (default all)" 0
add --title "Reviewer rule" --rule "Run the mutation script on the diff." --role reviewer
assert_rc "AC5.1 add --role reviewer ok" 0
add --title "Impl rule" --rule "Run lint before the tests." --role implementer
assert_rc "AC5.1 add --role implementer ok" 0
add --title "Explicit all" --rule "Write the why in every commit." --role all
assert_rc "AC5.1 add --role all ok" 0
AFTER_SCOPE="$(awk '/^### L-0001 /{f=1} f && /^- Scope: /{getline nxt; print nxt; exit}' "$F")"
assert_eq "AC5.1 '- Role: tester' is written right after '- Scope:'" "- Role: tester" "$AFTER_SCOPE"
add --title "Bad role" --rule "A rule with a bad role." --role janitor
assert_rc "AC5.1 an unknown --role is rejected (exit 2)" 2
add --title "Bad role case" --rule "Another bad role rule." --role Tester
assert_rc "AC5.1 --role is case-sensitive (Tester rejected)" 2
assert_eq "AC5.1 a rejected --role adds nothing" "0" "$(grep -c 'A rule with a bad role\|Another bad role rule' "$F")"
run bash "$LEARN" check
assert_rc "AC5.2 check passes with Role lines" 0

echo "v0.22.4 AC5.1 entries without a Role line count as all"
# a hand-written entry of the old format (no Role line)
printf '\n### L-0006 · 2026-10-09 · Legacy\n- Status: active\n- Rule: Legacy rule without a role.\n- Why: old\n- Evidence: old\n- Source: user\n- Scope: project-wide\n' >> "$F"
run bash "$LEARN" check
assert_rc "AC5.2 a missing Role is fine (check passes)" 0
run bash "$LEARN" checklist implementer
assert_rc "AC5.3 checklist implementer exits 0" 0
assert_eq "AC5.1 a legacy entry without Role is in the implementer checklist" "1" "$(printf '%s\n' "$OUT" | grep -cxF -- '- [ ] Legacy rule without a role. (L-0006, scope: project-wide)')"

echo "v0.22.4 AC5.3 checklist ROLE: the role's entries and all"
TESTER_L='- [ ] Name each test after its AC. (L-0001, scope: src/**)'
ALL_L='- [ ] Keep commits small. (L-0002, scope: project-wide)'
REV_L='- [ ] Run the mutation script on the diff. (L-0003, scope: project-wide)'
IMPL_L='- [ ] Run lint before the tests. (L-0004, scope: project-wide)'
ALL2_L='- [ ] Write the why in every commit. (L-0005, scope: project-wide)'
LEG_L='- [ ] Legacy rule without a role. (L-0006, scope: project-wide)'
n_items() { printf '%s\n' "$OUT" | grep -c '^- \[ \] '; }
inout() { # NAME LINE WANT(1|0)
  local got; got="$(printf '%s\n' "$OUT" | grep -cxF -- "$2")"
  if [ "$got" = "$3" ]; then t_ok "$1"; else t_bad "$1" "line [$2] count $got, want $3; output: $OUT"; fi
}
run bash "$LEARN" checklist tester
assert_rc "AC5.3 checklist tester exits 0" 0
inout "AC5.3 tester: the tester entry, as '- [ ] <rule> (L-000N, scope: <scope>)'" "$TESTER_L" 1
inout "AC5.3 tester: an entry for all (default)" "$ALL_L" 1
inout "AC5.3 tester: an entry with --role all" "$ALL2_L" 1
inout "AC5.3 tester: the legacy entry" "$LEG_L" 1
inout "AC5.3 tester: not the reviewer entry" "$REV_L" 0
inout "AC5.3 tester: not the implementer entry" "$IMPL_L" 0
assert_eq "AC5.3 tester: exactly four checklist items" "4" "$(n_items)"
run bash "$LEARN" checklist reviewer
inout "AC5.3 reviewer: the reviewer entry" "$REV_L" 1
inout "AC5.3 reviewer: an entry for all" "$ALL_L" 1
inout "AC5.3 reviewer: not the tester entry" "$TESTER_L" 0
assert_eq "AC5.3 reviewer: exactly four checklist items (reviewer, all, all, legacy)" "4" "$(n_items)"
run bash "$LEARN" checklist implementer
inout "AC5.3 implementer: the implementer entry" "$IMPL_L" 1
inout "AC5.3 implementer: not the reviewer entry" "$REV_L" 0
assert_eq "AC5.3 implementer: exactly four checklist items" "4" "$(n_items)"
FILE_BEFORE="$(cksum "$F")"
run bash "$LEARN" checklist tester
assert_eq "AC5.3 checklist is read-only (the file is unchanged)" "$FILE_BEFORE" "$(cksum "$F")"

echo "v0.22.4 AC5.1 retire still works with Role lines; retired entries are never listed"
run bash "$LEARN" retire L-0001 --reason "superseded"
assert_rc "AC5.1 retire an entry that has a Role line" 0
assert_contains "AC5.1 retire writes the retired status" "$(cat "$F")" "- Status: retired (superseded"
assert_eq "AC5.1 retire keeps the Role line of the entry" "1" "$(awk '/^### L-0001 /{f=1;next} /^### /{f=0} f && /^- Role: tester$/{n++} END{print n+0}' "$F")"
assert_eq "AC5.1 retire does not touch other entries (L-0003 still active)" "1" "$(awk '/^### L-0003 /{f=1;next} /^### /{f=0} f && /^- Status: active$/{n++} END{print n+0}' "$F")"
run bash "$LEARN" check
assert_rc "AC5.2 check passes after retiring" 0
run bash "$LEARN" checklist tester
inout "AC5.3 a retired tester entry is no longer listed" "$TESTER_L" 0
assert_eq "AC5.3 tester: three items left" "3" "$(n_items)"

echo "v0.22.4 AC5.2 check flags an unknown Role value"
cp "$F" "$F.keep"
sed 's/^- Role: reviewer$/- Role: janitor/' "$F.keep" > "$F"
run bash "$LEARN" check
assert_rc "AC5.2 an unknown Role value fails check (exit 1)" 1
assert_contains "AC5.2 the problem names Role" "$OUT" "Role"
cp "$F.keep" "$F"; rm -f "$F.keep"
run bash "$LEARN" check
assert_rc "AC5.2 the file is valid again after the fix" 0

echo "v0.22.4 AC5.2 the Role line counts toward the line budget"
LINES="$(wc -l < "$F" | tr -d ' ')"
LEARN_MAX_LINES="$LINES" run bash "$LEARN" check
assert_rc "AC5.2 at the budget: check passes" 0
LEARN_MAX_LINES="$((LINES - 1))" run bash "$LEARN" check
assert_rc "AC5.2 one line over the budget: check fails" 1
R3="$(mk_tmp)"; mk_repo "$R3"; ( cd "$R3" && bash "$LEARN" init >/dev/null && bash "$LEARN" add --title a --rule "Rule one." --why w --evidence e --source user >/dev/null )
L_NOROLE="$(cd "$R3" && wc -l < .agents/LEARNINGS.md | tr -d ' ')"
( cd "$R3" && bash "$LEARN" add --title b --rule "Rule two." --why w --evidence e --source user --role tester >/dev/null )
L_ROLE="$(cd "$R3" && wc -l < .agents/LEARNINGS.md | tr -d ' ')"
( cd "$R3" && bash "$LEARN" add --title c --rule "Rule three." --why w --evidence e --source user >/dev/null )
L_THREE="$(cd "$R3" && wc -l < .agents/LEARNINGS.md | tr -d ' ')"
if [ "$((L_ROLE - L_NOROLE))" -ge "$((L_THREE - L_ROLE))" ]; then t_ok "AC5.2 an entry written with --role is not shorter than one without"; else t_bad "AC5.2 an entry written with --role is not shorter than one without" "deltas: role $((L_ROLE - L_NOROLE)), no role $((L_THREE - L_ROLE))"; fi

echo "v0.22.4 AC5.3 checklist: nothing to list, and usage"
R4="$(mk_tmp)"; mk_repo "$R4"; cd "$R4" || exit 3
bash "$LEARN" init >/dev/null
run bash "$LEARN" checklist tester
assert_rc "AC5.3 no entries at all: exit 0" 0
assert_contains "AC5.3 no entries: 'no learnings for tester'" "$OUT" "no learnings for tester"
bash "$LEARN" add --title r --rule "Only for the reviewer." --why w --evidence e --source user --role reviewer >/dev/null
run bash "$LEARN" checklist tester
assert_contains "AC5.3 entries only for other roles: 'no learnings for tester'" "$OUT" "no learnings for tester"
assert_eq "AC5.3 ... and no checklist item" "0" "$(n_items)"
bash "$LEARN" retire L-0001 --reason gone >/dev/null
run bash "$LEARN" checklist reviewer
assert_contains "AC5.3 only a retired entry: 'no learnings for reviewer'" "$OUT" "no learnings for reviewer"
run bash "$LEARN" checklist janitor
assert_rc "AC5.3 an invalid ROLE exits 2" 2
run bash "$LEARN" checklist
assert_rc "AC5.3 a missing ROLE exits 2" 2
run bash "$LEARN" checklist Tester
assert_rc "AC5.3 ROLE is case-sensitive (Tester exits 2)" 2
t_summary
