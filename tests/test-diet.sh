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
has "AC1 the audit defines the four verdicts" "$AF" 'KEEP[^|]{0,400}PROCESS-ONLY[^|]{0,400}ZERO[^|]{0,400}UNMEASURED'
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
has "AC2 the gate says ZERO items leave always-loaded text" "$GATE" 'ZERO[^.]{0,300}always-loaded'
RUBTXT="$(awk '/^## Running evals automatically/ { f = 1; next } f && /^## / { exit } f { print }' "$RUB" | tr '\n' ' ')"
AUTO="$(sed -n 's/^AUTO="\(.*\)"$/\1/p' "$PB_ROOT/evals/run-evals.sh" | head -n 1)"
for e in $AUTO; do
  case " E1 E3 E8 E15 " in *" $e "*) continue ;; esac
  if printf '%s' "$RUBTXT" | grep -qE -- "(^|[^0-9])$e([^0-9]|$)"; then t_ok "AC2 the auto-gradable list of RUBRIC.md names $e"; else t_bad "AC2 the auto-gradable list of RUBRIC.md names $e" "not in the Running evals automatically section"; fi
done

echo "S1 AC6 README: the runs pointer covers Runs 25-37, one cost line"
RM="$(flat "$README")"
hasnt "AC6 README no longer says Latest, Run 28" "$RM" 'Latest, Run 28'
has "AC6 README points to Runs 25-37 and the audit" "$RM" 'Runs 25[-–]37[^|]{0,300}docs/delta-audit\.md|docs/delta-audit\.md[^|]{0,300}Runs 25[-–]37'
has "AC6 README states the cost of the with arm, about 2-2.5x" "$RM" '2[-–]2\.5 ?(x|times)'
has "AC6 the cost line cites Runs 25, 26 and 29" "$RM" '2[-–]2\.5 ?(x|times)[^|]{0,300}Run 25[^|]{0,80}26[^|]{0,80}29|Runs? 25, 26 and 29[^|]{0,200}2[-–]2\.5'

t_summary
