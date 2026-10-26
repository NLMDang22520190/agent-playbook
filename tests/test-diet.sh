#!/usr/bin/env bash
# Tests for v0.29.0 lane a ("diet"): the Δ audit of the behaviour rules (docs/delta-audit.md), the RUBRIC markers for
# process-only and Δ=0 scenarios, the README runs pointer and cost line, the always-loaded diet, the PR report parts
# (pr-body.sh in the release flow, Pre-mortem and the feedback line in the hand-off report only) and the wording contradictions.
# Reads repo files only; nothing is written.
. "$(dirname "$0")/lib.sh"
AUDIT="$PB_ROOT/docs/delta-audit.md"
RUB="$PB_ROOT/evals/RUBRIC.md"
SCN="$PB_ROOT/evals/scenarios.md"
README="$PB_ROOT/README.md"
# flat FILE -> the file on one line, runs of spaces squeezed (missing file: empty)
flat() { tr '\n' ' ' < "$1" 2>/dev/null | tr -s ' '; }
# has NAME TEXT ERE -> case-insensitive match
has() { if printf '%s' "$2" | grep -qiE -- "$3"; then t_ok "$1"; else t_bad "$1" "pattern [$3] not found"; fi; }
hasnt() { if printf '%s' "$2" | grep -qiE -- "$3"; then t_bad "$1" "pattern [$3] found"; else t_ok "$1"; fi; }

echo "S1 AC1 docs/delta-audit.md: one row per scenario, a verdict each, runs and lines cited"
assert_file "AC1 docs/delta-audit.md exists" "$AUDIT"
AF="$(flat "$AUDIT")"
has "AC1 the audit names the results file it cites" "$AF" '2026-10-12-claude-code-2\.1\.296\.md'
for v in KEEP PROCESS-ONLY ZERO UNMEASURED; do has "AC1 the audit defines the verdict $v" "$AF" "\*\*$v\*\*: "; done
for e in $(sed -n 's/^## \(E[0-9][0-9]*\) .*/\1/p' "$SCN"); do
  row="$(grep -E "^\| $e[ |]" "$AUDIT" 2>/dev/null | head -n 1)"
  if [ -n "$row" ]; then t_ok "AC1 the audit has a row for $e"; else t_bad "AC1 the audit has a row for $e" "no '| $e ' row"; continue; fi
  if printf '%s' "$row" | grep -qE '\| *(KEEP|PROCESS-ONLY|ZERO|ZERO-1|UNMEASURED)[^|]*\|[^|]*\|? *$'; then t_ok "AC1 the $e row ends with a verdict and an action"; else t_bad "AC1 the $e row ends with a verdict and an action" "[$row]"; fi
done
NRULES="$(grep -cE '^\| R[0-9]+ ' "$AUDIT" 2>/dev/null)"
if [ "${NRULES:-0}" -ge 15 ]; then t_ok "AC1 the audit has at least 15 rule or reference rows R<n> ($NRULES)"; else t_bad "AC1 the audit has at least 15 rule or reference rows R<n>" "${NRULES:-0} rows"; fi
NCITE="$(grep -oE 'Run (2[5-9]|3[0-7])[a-z]?:? ?[^|]{0,40}(line|:)[ ]?[0-9]{3}' "$AUDIT" 2>/dev/null | wc -l | tr -d ' ')"
if [ "${NCITE:-0}" -ge 20 ]; then t_ok "AC1 the audit cites a run and a line at least 20 times ($NCITE)"; else t_bad "AC1 the audit cites a run and a line at least 20 times" "${NCITE:-0} citations"; fi
has "AC1 the audit counts the verdicts" "$AF" 'verdict counts?[^.]{0,40}KEEP[^.]{0,10}[0-9]'
has "AC1 the audit records the Run 27 lesson (lane C)" "$AF" 'Run 27[^.]{0,200}(lane C|slimmed)'

echo "S1 AC2 RUBRIC.md: process-only and Δ=0 scenarios are marked and do not count as Δ evidence"
RF="$(flat "$RUB")"
if grep -qE '^## (Δ|Delta) status' "$RUB"; then t_ok "AC2 RUBRIC.md has a Δ status section"; else t_bad "AC2 RUBRIC.md has a Δ status section" "no '## Δ status' heading"; fi
DS="$(awk '/^## (Δ|Delta) status/ { f = 1; next } f && /^## / { exit } f { print }' "$RUB" | tr '\n' ' ')"
has "AC2 the section marks PROCESS-ONLY scenarios" "$DS" 'PROCESS-ONLY[^.]{0,200}E(1|15|16|19|21)[^0-9]'
has "AC2 the section marks ZERO scenarios" "$DS" 'ZERO[^.]{0,200}E(5|30|41)[^0-9]'
has "AC2 marked scenarios are not Δ evidence" "$DS" 'not (count as )?Δ evidence|no longer count'
has "AC2 the section points to docs/delta-audit.md" "$DS" 'docs/delta-audit\.md'
GATE="$(printf '%s' "$RF" | grep -oE 'Gate for keeping a rule[^#]*' | head -n 1)"
has "AC2 the gate says what happens to ZERO items: reference-only or opt-in" "$GATE" 'ZERO[^.]{0,250}(reference-only|reference only)[^.]{0,120}opt-in|ZERO[^.]{0,250}opt-in[^.]{0,120}reference'
has "AC2 the gate says ZERO items leave always-loaded text" "$GATE" 'ZERO[^.]{0,250}always-loaded'
RUBTXT="$(awk '/^## Running evals automatically/ { f = 1; next } f && /^## / { exit } f { print }' "$RUB" | tr '\n' ' ')"
AUTO="$(sed -n 's/^AUTO="\(.*\)"$/\1/p' "$PB_ROOT/evals/run-evals.sh" | head -n 1)"
for e in $AUTO; do
  case " E1 E3 E8 E15 " in *" $e "*) continue ;; esac
  if printf '%s' "$RUBTXT" | grep -qE -- "(^|[^0-9])$e([^0-9]|$)"; then t_ok "AC2 the auto-gradable list of RUBRIC.md names $e"; else t_bad "AC2 the auto-gradable list of RUBRIC.md names $e" "not in the Running evals automatically section"; fi
done

echo "S1 AC6 README: the runs pointer covers Runs 25-37, one cost line"
RM="$(flat "$README")"
hasnt "AC6 README no longer says Latest, Run 28" "$RM" 'Latest, Run 28'
has "AC6 README points to Runs 25-37 and the audit" "$RM" 'Runs 25[-–]37[^|]{0,250}docs/delta-audit\.md|docs/delta-audit\.md[^|]{0,250}Runs 25[-–]37'
has "AC6 README states the cost of the with arm, about 2-2.5x" "$RM" '2[-–]2\.5 ?(x|times)'
has "AC6 the cost line cites Runs 25, 26 and 29" "$RM" '2[-–]2\.5 ?(x|times)[^|]{0,250}Run 25[^|]{0,80}26[^|]{0,80}29|Runs? 25, 26 and 29[^|]{0,200}2[-–]2\.5'

echo "S2 AC3 the always-loaded diet: ZERO-only text leaves AGENTS.global.md and the playbook-proof SKILL.md, a pointer stays"
BLOCK="$PB_ROOT/AGENTS.global.md"
PSK="$PB_ROOT/skills/playbook-proof/SKILL.md"
EVF="$PB_ROOT/skills/playbook-proof/references/evidence-formats.md"
BF="$(flat "$BLOCK")"; PF="$(flat "$PSK")"; EF="$(flat "$EVF")"
hasnt "AC3 R6 AGENTS.global.md no longer carries the E5 run-output sentence" "$BF" 'need run output from this session'
hasnt "AC3 R6 AGENTS.global.md no longer carries the path:line sentence" "$BF" 'Code claims cite `path:line`'
has "AC3 R6 the always-on Proof section still points to playbook-proof" "$BF" 'Details: `playbook-proof`'
has "AC3 R6 evidence-formats.md carries the moved sentence" "$EF" '"Passes", "works", "fixed" need run output from this session'
if grep -q '^## Producing evidence' "$PSK"; then t_bad "AC3 R27 playbook-proof SKILL.md no longer has the Producing evidence section" "heading still there"; else t_ok "AC3 R27 playbook-proof SKILL.md no longer has the Producing evidence section"; fi
if grep -q '^## Producing evidence' "$EVF"; then t_ok "AC3 R27 evidence-formats.md has the Producing evidence section"; else t_bad "AC3 R27 evidence-formats.md has the Producing evidence section" "no heading"; fi
has "AC3 R27 the moved section keeps the proof-run.sh usage" "$EF" 'P=~/.agents/playbook/scripts/proof-run\.sh[^`]{0,60}--label unit-tests'
has "AC3 R27 the moved section keeps the never-retype rule" "$EF" 'Never retype or summari[sz]e output inside the block'
has "AC3 R27 playbook-proof SKILL.md keeps one pointer line to proof-run.sh and evidence-formats.md" "$PF" 'proof-run\.sh[^.]{0,120}references/evidence-formats\.md|references/evidence-formats\.md[^.]{0,120}proof-run\.sh'
AGW="$(wc -w < "$BLOCK" | tr -d ' ')"; PSW="$(wc -w < "$PSK" | tr -d ' ')"
if [ "$AGW" -lt 718 ]; then t_ok "AC3 AGENTS.global.md has fewer words than at v0.28.2 (718): $AGW"; else t_bad "AC3 AGENTS.global.md has fewer words than at v0.28.2 (718)" "$AGW words"; fi
if [ "$PSW" -lt 675 ]; then t_ok "AC3 playbook-proof SKILL.md has fewer words than at v0.28.2 (675): $PSW"; else t_bad "AC3 playbook-proof SKILL.md has fewer words than at v0.28.2 (675)" "$PSW words"; fi
for keep in '\[VERIFIED\] ran or read this session' 'On pushback, re-check' 'Never weaken, skip or delete a test or gate' 'If the user asks to skip tests, ask once and offer the test' 'A rename or removal of an export is a public API change' 'log it in `\.agents/handoff/decisions\.md`' 'Read `\.agents/LEARNINGS\.md` first'; do
  has "AC3 KEEP text stays in AGENTS.global.md: $keep" "$BF" "$keep"
done

echo "S3 AC4 PR report parts: the release flow builds the PR body with pr-body.sh; Pre-mortem and the feedback line are hand-off only"
DEV="$PB_ROOT/docs/development.md"; REL="$PB_ROOT/skills/playbook-tdd/references/release.md"
TSK="$PB_ROOT/skills/playbook-tdd/SKILL.md"; FIN="$PB_ROOT/skills/playbook-tdd/templates/final-report.md"
DF="$(flat "$DEV")"; RLF="$(flat "$REL")"
has "AC4 development.md: the release PR body is the pr-body.sh output" "$DF" 'release[^.]{0,120}pr-body\.sh|pr-body\.sh[^.]{0,120}release'
has "AC4 development.md: the PR is opened with that body (gh pr create --body-file)" "$DF" 'gh pr create[^.]{0,40}--body-file'
has "AC4 development.md: ship.sh comes after the PR" "$DF" 'pr-body\.sh[^#]{0,400}tools/ship\.sh'
has "AC4 release.md: the release PR description is the pr-body.sh output" "$RLF" 'PR description[^.]{0,80}pr-body\.sh|pr-body\.sh[^.]{0,80}PR description'
has "AC4 release.md: a release of several items has one block per item" "$RLF" 'one block per item'
P4="$(awk '/^### Phase 4/ { f = 1; next } f && /^##/ { exit } f { print }' "$TSK" | tr '\n' ' ' | tr -s ' ')"
has "AC4 Phase 4: the final report is the hand-off report 06-final-report.md" "$P4" 'hand-off report[^.]{0,40}06-final-report\.md|06-final-report\.md[^.]{0,40}hand-off report'
has "AC4 Phase 4: Pre-mortem, Models used and the feedback line belong to the hand-off report only" "$P4" 'Pre-mortem[^.]{0,80}Models used[^.]{0,80}Playbook feedback line[^.]{0,60}this report only'
has "AC4 Phase 4: they are not PR description parts" "$P4" 'not (to|in|part of) the PR description'
L5="$(awk '/^### Lite workflow/ { f = 1; next } f && /^###? / { exit } f { print }' "$TSK" | tr '\n' ' ' | tr -s ' ')"
has "AC4 Lite step 5: the final report is the hand-off report" "$L5" '5\. Final report \(`06-final-report\.md`, the hand-off report\)'
has "AC4 the template says which parts stay in the hand-off report" "$(flat "$FIN")" 'hand-off report[^>]{0,200}Pre-mortem[^>]{0,120}Playbook feedback[^>]{0,200}pr-body\.sh'
echo "S3 AC4 pr-body.sh keeps Weight and Not checked and leaves the Pre-mortem and the feedback line out (characterization)"
H="$(mk_tmp)"
printf '# 01 - Spec\n\n## Understanding\nRename x to y.\n' > "$H/01-spec.md"
sed -e 's/<one sentence>/renamed x/' "$FIN" > "$H/06-final-report.md"
run bash "$PB_ROOT/scripts/pr-body.sh" --handoff "$H"
assert_rc "AC4 pr-body.sh exits 0 on the template report" 0
assert_contains "AC4 pr-body.sh prints ## Weight" "$OUT" "## Weight"
assert_contains "AC4 pr-body.sh prints ## Not checked" "$OUT" "## Not checked"
assert_not_contains "AC4 pr-body.sh leaves the Pre-mortem out" "$OUT" "Pre-mortem"
assert_not_contains "AC4 pr-body.sh leaves the Playbook feedback line out" "$OUT" "Playbook feedback"
TW="$(wc -w < "$TSK" | tr -d ' ')"
if [ "$TW" -le 3700 ] && [ "$TW" -ge 3650 ]; then t_ok "AC3 playbook-tdd SKILL.md stays within its budget and its count+50 pin (3650..3700): $TW"; else t_bad "AC3 playbook-tdd SKILL.md stays within 3650..3700" "$TW words"; fi

t_summary
