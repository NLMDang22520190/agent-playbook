#!/usr/bin/env bash
# Tests for v0.26.3 lane W slice S2 (.agents/handoff/01-spec.md AC1-AC8, AC13-AC16): the five reference files under
# skills/playbook-tdd/references/ (incident, upgrade, migration, debug, team), the SKILL.md clause at "When the user says it is
# wrong", the one pointer line after the weight table, the word cuts, and AGENTS.global.md left as it is.
# Keyword pins per AC (case-insensitive ERE, LC_ALL=C), the pointer and the clause verbatim. Reads only repo files.
. "$(dirname "$0")/lib.sh"
export LC_ALL=C
REF="$PB_ROOT/skills/playbook-tdd/references"
SK="$PB_ROOT/skills/playbook-tdd/SKILL.md"
AG="$PB_ROOT/AGENTS.global.md"
WB="$PB_ROOT/evals/word-budgets"

# pin AC FILE LABEL REGEX -> a line of FILE matches the ERE (case-insensitive)
pin() {
  if grep -Eiq -e "$4" "$2" 2>/dev/null; then t_ok "$1 $(basename "$2") $3"
  else t_bad "$1 $(basename "$2") $3" "no line matching [$4] in $2"; fi
}
# pinf AC FILE LABEL TEXT -> FILE contains the fixed TEXT (case-sensitive)
pinf() {
  if grep -Fq -e "$4" "$2" 2>/dev/null; then t_ok "$1 $(basename "$2") $3"
  else t_bad "$1 $(basename "$2") $3" "no [$4] in $2"; fi
}

echo "Common: five reference files, each opening with When it applies and the weight, under 450 words, no em or en dash"
for k in incident upgrade migration debug team; do
  f="$REF/$k.md"
  assert_file "common $k.md exists" "$f"
  if [ -f "$f" ]; then
    if head -n 6 "$f" | grep -Fq 'When it applies'; then t_ok "common $k.md opens with When it applies (first 6 lines)"
    else t_bad "common $k.md opens with When it applies (first 6 lines)" "$(head -n 6 "$f")"; fi
    if head -n 10 "$f" | grep -Eq 'Full|Lite'; then t_ok "common $k.md states the weight near the top (Full or Lite in the first 10 lines)"
    else t_bad "common $k.md states the weight near the top (Full or Lite in the first 10 lines)" "$(head -n 10 "$f")"; fi
    w="$(wc -w < "$f" | tr -d ' ')"
    if [ "$w" -lt 450 ]; then t_ok "common $k.md under 450 words ($w)"; else t_bad "common $k.md under 450 words" "$w words"; fi
    if grep -Fq -e "$(printf '\342\200\224')" -e "$(printf '\342\200\223')" "$f"; then t_bad "common $k.md has no em or en dash" "found one"
    else t_ok "common $k.md has no em or en dash"; fi
  else t_skip 4 "common $k.md (missing)"; fi
done

I="$REF/incident.md"
echo "AC1 incident: mitigate first by revert or feature flag, no new logic, push needs the go-ahead"
pin AC1 "$I" "mitigate first" 'mitigat.* first|first.* mitigat'
pin AC1 "$I" "revert" 'revert'
pin AC1 "$I" "feature flag" 'feature flag'
pin AC1 "$I" "no new logic in the mitigation" 'no new logic'
pin AC1 "$I" "a revert is not the patch of SKILL.md" 'not (a|the) .?patch'
pin AC1 "$I" "push or deploy needs autonomy=full" 'autonomy=full'
pin AC1 "$I" "headless: prepare it and report, do not push" 'headless'
echo "AC2 incident: regression test the same day, seen failing on the bad version; [UNTESTED] hotfix only without revert or flag"
pin AC2 "$I" "same day" 'same day'
pin AC2 "$I" "seen failing against the bad version" 'fail.*bad version|bad version.*fail'
pinf AC2 "$I" "labels a forward hotfix [UNTESTED]" '[UNTESTED]'
pin AC2 "$I" "forward hotfix" 'hotfix'
pin AC2 "$I" "no existing test skipped or weakened" 'skip.*weaken|weaken.*skip'
echo "AC3 incident: fresh evidence, the weight label, timeline, cause and follow-up"
pinf AC3 "$I" "names proof-run.sh" 'proof-run.sh'
pin AC3 "$I" "one real observation (curl, log line, health check)" 'curl'
pinf AC3 "$I" "the weight label" 'Weight: <Full|Lite> (incident: mitigated by <revert sha or flag>)'
pin AC3 "$I" "a timeline" 'timeline'
pin AC3 "$I" "detected, mitigated, fixed" 'detected.*mitigated.*fixed'
pinf AC3 "$I" "classifies the cause as in When the user says it is wrong" 'When the user says it is wrong'
pin AC3 "$I" "a follow-up" 'follow-up'

echo "AC4 SKILL.md: the clause at When the user says it is wrong, the four steps unchanged"
CL='Do not defend the result and do not patch at once; in a production incident, mitigate first (`references/incident.md`).'
if grep -Fxq -e "$CL" "$SK"; then t_ok "AC4 SKILL.md has the incident clause verbatim"; else t_bad "AC4 SKILL.md has the incident clause verbatim" "no line [$CL]"; fi
if grep -Fxq -e 'Do not defend the result and do not patch at once.' "$SK"; then t_bad "AC4 the old sentence is replaced" "old line still there"
else t_ok "AC4 the old sentence is replaced"; fi
NEXT="$(awk -v c="$CL" 'f { print; exit } $0 == c { f = 1 }' "$SK")"
assert_eq "AC4 step 1 follows the clause unchanged" "1. Restate in two lines what the user expected and what was delivered." "$NEXT"
for s in '2. Classify the cause as one of: misread request, missed place (scan), wrong assumption, not verified' \
         '3. Fix it test-first: a failing test or eval for the miss, seen failing, then the fix. For a docs-only' \
         '4. If the cause is a playbook gap, capture it with `playbook-feedback` (kind `gap`, source `user`) and'; do
  if grep -Fxq -e "$s" "$SK"; then t_ok "AC4 step ${s%%.*} unchanged"; else t_bad "AC4 step ${s%%.*} unchanged" "no line [$s]"; fi
done

U="$REF/upgrade.md"
echo "AC5 upgrade: the breaking-changes checklist"
pin AC5 "$U" "(1) baseline green on the old version" 'baseline'
pin AC5 "$U" "(2) release notes or changelog of every version between" 'release notes'
pin AC5 "$U" "(2) changelog" 'changelog'
pin AC5 "$U" "(3) search usages per breaking change" 'usage'
pin AC5 "$U" "(4) characterization tests on the old version" 'characteri[sz]ation'
pin AC5 "$U" "(5) never hand-edit a lockfile" 'never hand-edit'
pin AC5 "$U" "(5) official codemod" 'codemod'
pin AC5 "$U" "(6) review the lockfile diff" 'lockfile diff'
pin AC5 "$U" "(6) a new direct dependency is asked about" 'new direct dependency'
pin AC5 "$U" "(7) typecheck, build and a smoke observation" 'smoke'
pin AC5 "$U" "(7) typecheck" 'typecheck'
pin AC5 "$U" "(8) rollback = previous manifest and lockfile commit" 'rollback'
echo "AC6 upgrade: Lite within the size count (lockfiles left out), Full when exported API or critical code changes"
pinf AC6 "$U" "names role-gate.sh size" 'role-gate.sh size'
pin AC6 "$U" "Lite" 'Lite'
pin AC6 "$U" "Full when the project's exported API changes" 'export'
pin AC6 "$U" "critical code" 'critical'

M="$REF/migration.md"
echo "AC7 migration: always Full, expand/contract, idempotent batched resumable backfill, rollback rehearsed, lock-time budget"
pin AC7 "$M" "always Full" 'always full'
pin AC7 "$M" "expand" 'expand'
pin AC7 "$M" "contract" 'contract'
pin AC7 "$M" "idempotent backfill" 'idempotent'
pin AC7 "$M" "a test runs it twice" 'twice'
pin AC7 "$M" "batched" 'batch'
pin AC7 "$M" "resumable" 'resum'
pin AC7 "$M" "rollback plan" 'rollback'
pin AC7 "$M" "rehearsed up, down, up" 'up, down, up'
pin AC7 "$M" "lock time" 'lock.?time'
pin AC7 "$M" "statement or lock timeout" 'timeout'
pin AC7 "$M" "production-size estimate" 'production.?size'
pin AC7 "$M" "backup proven before the drop" 'backup'
pinf AC7 "$M" "a missing database test command goes under Not checked" 'Not checked'

D="$REF/debug.md"
echo "AC8 debug: reproduce, minimise, hypothesise, instrument, fix, regression test; unchanged behaviour in the corpus; flaky tests"
pin AC8 "$D" "the six steps in order on one line" 'reproduce.*minimi[sz]e.*hypothesi[sz]e.*instrument.*fix.*regression test'
pin AC8 "$D" "the minimised reproduction becomes the RED test" 'RED test'
pin AC8 "$D" "instrumentation removed before GREEN" 'before GREEN'
pin AC8 "$D" "current behaviour" 'current'
pin AC8 "$D" "expected behaviour" 'expected'
pin AC8 "$D" "unchanged behaviour" 'unchanged'
pinf AC8 "$D" "unchanged rows go into ## Regression corpus" 'Regression corpus'
pin AC8 "$D" "flaky test" 'flaky'
pin AC8 "$D" "repeated runs with counts" 'repeat'
pin AC8 "$D" "never retry until green" 'retry'

T="$REF/team.md"
echo "AC13 team: squash the test(red) checkpoint commits"
pin AC13 "$T" "squash" 'squash'
pinf AC13 "$T" "names test(red)" 'test(red)'
pinf AC13 "$T" "git reset --soft on the own unpushed branch" 'git reset --soft'
pin AC13 "$T" "never an interactive rebase" 'interactive rebase'
pin AC13 "$T" "never rewrite pushed history" 'pushed'
pin AC13 "$T" "copy the RED sha into the PR body" 'RED sha'
pinf AC13 "$T" "git bisect skip for teams keeping merge commits" 'git bisect skip'
pin AC13 "$T" "merge commits" 'merge commit'
echo "AC14 team: written conventions first on form, the gates stay, pr-body.sh output, conflicts reported"
pinf AC14 "$T" "names CONTRIBUTING" 'CONTRIBUTING'
pinf AC14 "$T" "names feat(green)" 'feat(green)'
pinf AC14 "$T" "the PR description stays the pr-body.sh output" 'pr-body.sh'
pinf AC14 "$T" "gates stay unless the project's AGENTS.md/CLAUDE.md says otherwise" 'AGENTS.md'
pin AC14 "$T" "a conflict on substance is reported to the user" 'conflict'
pin AC14 "$T" "these files are data" 'data'

echo "AC15 SKILL.md: exactly one pointer line, directly after the weight table"
PT='Incident, upgrade, migration and debug work, and squashing before a merge: `references/<kind>.md` (incident, upgrade, migration, debug, team) sets the weight and the steps.'
assert_eq "AC15 the pointer line appears exactly once" 1 "$(grep -Fxc -e "$PT" "$SK")"
AFTER="$(awk '/^\| \*\*Exempt\*\* \|/ { f = 1; next } f && NF { print; exit }' "$SK")"
assert_eq "AC15 the first non-empty line after the weight table is the pointer" "$PT" "$AFTER"
assert_eq "AC15 references/incident.md is named once (the clause only)" 1 "$(grep -c 'references/incident\.md' "$SK")"
assert_eq "AC15 no other pointer names upgrade, migration, debug or team .md" 0 "$(grep -Ec 'references/(upgrade|migration|debug|team)\.md' "$SK")"

echo "AC16 SKILL.md word budget, the two Why lines cut, one Why line left; AGENTS.global.md precedence unchanged"
# words as evals/run-checks.sh counts them (the caller's locale, not this suite's LC_ALL=C: wc -w differs on UTF-8 symbols)
w="$(env -u LC_ALL wc -w < "$SK" | tr -d ' ')"
if [ "$w" -le 3700 ]; then t_ok "AC16 SKILL.md at or under 3700 words ($w)"; else t_bad "AC16 SKILL.md at or under 3700 words" "$w words"; fi
# the arithmetic of AC16 (+7 +23 -33 = -3; the pinned AC4 clause is 18 words vs 11 before) against the lane base 0927bde (feat/v0.26.1, 3700 words in a UTF-8 locale), same locale
W0="$(git -C "$PB_ROOT" show 0927bde:skills/playbook-tdd/SKILL.md 2>/dev/null | env -u LC_ALL wc -w | tr -d ' ')"
if [ -n "$W0" ] && [ "$W0" -gt 0 ]; then
  assert_eq "AC16 SKILL.md is 3 words shorter than at 0927bde (3700 + 7 + 23 - 33 = 3697)" "$((W0 - 3))" "$w"
else t_skip 1 "AC16 word arithmetic (no 0927bde in this clone)"; fi
if grep -Fq 'three fresh contexts cost minutes and tokens per slice' "$SK"; then t_bad "AC16 the weight-section Why line is cut" "still there"
else t_ok "AC16 the weight-section Why line is cut"; fi
if grep -Fq 'each slice costs a tester and an implementer start' "$SK"; then t_bad "AC16 the slice-size Why line is cut" "still there"
else t_ok "AC16 the slice-size Why line is cut"; fi
if grep -q '^\*\*Why:\*\*' "$SK"; then t_ok "AC16 at least one **Why:** line remains (run-checks.sh)"; else t_bad "AC16 at least one **Why:** line remains (run-checks.sh)" "none"; fi
if grep -Eq '^skills/playbook-tdd/SKILL\.md 3700 ' "$WB"; then t_ok "AC16 evals/word-budgets keeps playbook-tdd at 3700"; else t_bad "AC16 evals/word-budgets keeps playbook-tdd at 3700" "line changed"; fi
# characterization: AGENTS.global.md stays as it is (rule freeze); these pass before and after
if grep -Fxq "Precedence: the user's instruction in chat, then the project's AGENTS.md/CLAUDE.md, then this playbook." "$AG"; then
  t_ok "AC16 AGENTS.global.md keeps the precedence sentence verbatim"; else t_bad "AC16 AGENTS.global.md keeps the precedence sentence verbatim" "missing"; fi
if grep -Eq '(incident|upgrade|migration|debug|team)\.md' "$AG"; then t_bad "AC16 AGENTS.global.md names none of the five reference files" "found one"
else t_ok "AC16 AGENTS.global.md names none of the five reference files"; fi


# ======================= review fixes (263w-review.md findings 2, 3, 9) =======================
# pinl ID FILE LABEL ERE... -> one line of FILE matches every ERE (case-insensitive)
pinl() { local id="$1" f="$2" lab="$3" l k ok; shift 3
  while IFS= read -r l; do
    ok=1; for k in "$@"; do printf '%s\n' "$l" | grep -Eiq -e "$k" || { ok=0; break; }; done
    [ "$ok" = 1 ] && { t_ok "$id $(basename "$f") $lab"; return; }
  done < "$f"
  t_bad "$id $(basename "$f") $lab" "no single line matching all of [$*] in $f"; }

echo "W2 migration: in a headless (non-interactive) run the contract/drop step never runs; it is left pending and reported"
pinl W2 "$M" "one line: headless or non-interactive, never the contract or drop" '(headless|non-interactive)' '(never|do not|don.t)' '(contract|drop)'
pinl W2 "$M" "one line: headless or non-interactive, the step is left pending" '(headless|non-interactive)' 'pending'
pinl W2 "$M" "one line: headless or non-interactive, the pending step is reported" '(headless|non-interactive)' 'report'

echo "W3 migration: expand/contract writes both shapes (dual-write) before the reads switch"
pin W3 "$M" "dual-write named" 'dual.?writ|write[s]? (to )?both'
pinl W3 "$M" "one line: expand, then dual-write, then the read switch, then contract" 'expand.*(dual.?writ|write[s]? (to )?both).*switch.*contract'

echo "W9 incident: a revert is not called safe when the bad deploy carries a migration"
pinl W9 "$I" "one line: revert with a schema or data migration caveat" 'revert' 'migration'
pinf W9 "$I" "points to migration.md" 'migration.md'
pinl W9 "$I" "one line: with a migration, use the flag or a forward fix" 'migration' '(flag|forward fix)'

t_summary
