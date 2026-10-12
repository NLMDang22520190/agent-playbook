#!/usr/bin/env bash
# Tests for v0.23.2 AC17.1: the final report always ENDS with the exact line
#   **Playbook feedback:** <captured fb- ids or none>
# copied verbatim, never paraphrased (real eval E19 on v0.23.1 wrote "No playbook rule misfired.").
# Files read: skills/playbook-tdd/SKILL.md (Lite step 5 and the Full report step = Phase 4) and
# skills/playbook-tdd/templates/final-report.md (the spec says templates/final-report.md; the file lives under the skill).
# Assumption (tester): the Lite section is the text from the line starting "5. Final report with" up to the next
# "### " heading; the Full section is Phase 4 ("### Phase 4" up to the next "## " heading).
. "$(dirname "$0")/lib.sh"
SKILL="$PB_ROOT/skills/playbook-tdd/SKILL.md"
FINAL="$PB_ROOT/skills/playbook-tdd/templates/final-report.md"
LINE='**Playbook feedback:** <captured fb- ids or none>'

assert_file "the playbook-tdd SKILL.md exists" "$SKILL"
assert_file "the final-report template exists" "$FINAL"

LITE5="$(awk '/^5\. Final report with/ { on = 1 } on && /^### / { exit } on { print }' "$SKILL" 2>/dev/null)"
FULL4="$(awk '/^### Phase 4/ { on = 1; next } on && /^## / { exit } on { print }' "$SKILL" 2>/dev/null)"
[ -n "$LITE5" ] && t_ok "fixture: found the Lite step 5 text" || t_bad "fixture: found the Lite step 5 text" "no line starting '5. Final report with'"
[ -n "$FULL4" ] && t_ok "fixture: found the Phase 4 text" || t_bad "fixture: found the Phase 4 text" "no '### Phase 4' section"

section_checks() { # LABEL TEXT
  local label="$1" text="$2"
  assert_contains "AC17.1 $label gives the exact line: $LINE" "$text" "$LINE"
  # the list item (numbered or "- " bullet, continuation lines joined) that holds the exact line
  local item
  item="$(printf '%s\n' "$text" | awk -v l="$LINE" '
    function flush() { if (cur != "" && index(cur, l) > 0) print cur; cur = "" }
    /^([0-9]+\.|-) / || NF == 0 { flush() }
    NF { cur = (cur == "" ? $0 : cur " " $0) }
    END { flush() }')"
  if printf '%s\n' "$item" | grep -iqE 'ends? (with|on)|last line|final line'; then
    t_ok "AC17.1 $label says the report ENDS with the Playbook feedback line"
  else
    t_bad "AC17.1 $label says the report ENDS with the Playbook feedback line" "no 'ends with' / 'last line' wording in the item that holds the line"
  fi
  if printf '%s\n' "$item" | grep -qi 'verbatim'; then t_ok "AC17.1 $label says the line is copied verbatim"; else t_bad "AC17.1 $label says the line is copied verbatim" "no 'verbatim' in the item that holds the line"; fi
  if printf '%s\n' "$item" | grep -iqE 'never paraphras|not paraphras|no paraphras|do not paraphras'; then
    t_ok "AC17.1 $label says the line is never paraphrased"
  else
    t_bad "AC17.1 $label says the line is never paraphrased" "no 'never paraphrase' wording"
  fi
}
section_checks "Lite step 5" "$LITE5"
section_checks "the Full report step (Phase 4)" "$FULL4"

echo "AC17.1 templates/final-report.md ends with the line"
LASTL="$(grep -v '^[[:space:]]*$' "$FINAL" 2>/dev/null | tail -n 1)"
assert_eq "AC17.1 the last non-empty line of the template is exactly the Playbook feedback line" "$LINE" "$LASTL"
assert_eq "AC17.1 the line appears exactly once in the template" "1" "$(grep -cxF "$LINE" "$FINAL" 2>/dev/null)"
# nothing (not even '## Learnings proposed') may follow it
AFTER="$(awk -v l="$LINE" '$0 == l { seen = 1; next } seen && NF { n++ } END { print (seen ? n + 0 : "line missing") }' "$FINAL" 2>/dev/null)"
assert_eq "AC17.1 no non-empty line follows it" "0" "$AFTER"


# ---- v0.24.0 R8 (Lite, content): the final-report template has a Models used line before the learnings ----
echo "v0.24.0 R8 templates/final-report.md: **Models used:** before ## Learnings proposed, the feedback line stays last"
MLINE="$(grep -F '**Models used:**' "$FINAL" 2>/dev/null | head -n 1)"
assert_eq "R8 the template has exactly one **Models used:** line" "1" "$(grep -cF '**Models used:**' "$FINAL" 2>/dev/null)"
case "$MLINE" in *"tester="*"implementer="*"reviewer="*) t_ok "R8 the Models used line lists tester=, implementer= and reviewer=" ;; *) t_bad "R8 the Models used line lists tester=, implementer= and reviewer=" "[$MLINE]" ;; esac
case "$MLINE" in *"(<effort>)"* | *"(effort)"* | *"(<e>)"*) t_ok "R8 the Models used line shows the effort in parentheses" ;; *) t_bad "R8 the Models used line shows the effort in parentheses" "[$MLINE]" ;; esac
case "$MLINE" in *"Lite/Quick"*"session"*"one context"*) t_ok "R8 the line says Lite/Quick: session, one context" ;; *) t_bad "R8 the line says Lite/Quick: session, one context" "[$MLINE]" ;; esac
LM="$(grep -nF '**Models used:**' "$FINAL" 2>/dev/null | head -n 1 | cut -d: -f1)"
LL="$(grep -nxF '## Learnings proposed' "$FINAL" 2>/dev/null | head -n 1 | cut -d: -f1)"
if [ -n "$LM" ] && [ -n "$LL" ] && [ "$LM" -lt "$LL" ]; then t_ok "R8 the Models used line comes before ## Learnings proposed"; else t_bad "R8 the Models used line comes before ## Learnings proposed" "models line [$LM], learnings heading [$LL]"; fi
LP="$(grep -nF "$LINE" "$FINAL" 2>/dev/null | head -n 1 | cut -d: -f1)"
if [ -n "$LM" ] && [ -n "$LP" ] && [ "$LM" -lt "$LP" ]; then t_ok "R8 the Models used line comes before the Playbook feedback line"; else t_bad "R8 the Models used line comes before the Playbook feedback line" "models line [$LM], feedback line [$LP]"; fi
LC="$(grep -nxF '## Cost' "$FINAL" 2>/dev/null | head -n 1 | cut -d: -f1)"
if [ -n "$LM" ] && [ -n "$LC" ] && [ "$LM" -gt "$LC" ]; then t_ok "R8 the Models used line sits after the Cost section"; else t_bad "R8 the Models used line sits after the Cost section" "models line [$LM], cost heading [$LC]"; fi
assert_eq "R8 regression: the last non-empty line is still the Playbook feedback line" "$LINE" "$(grep -v '^[[:space:]]*$' "$FINAL" 2>/dev/null | tail -n 1)"
assert_eq "R8 regression: nothing non-empty follows the Playbook feedback line" "0" "$(awk -v l="$LINE" '$0 == l { seen = 1; next } seen && NF { n++ } END { print n + 0 }' "$FINAL")"

t_summary
