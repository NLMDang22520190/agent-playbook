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
case "$MLINE" in *"(Lite: session, one context)"*) t_ok "v24.10 R8 the line says (Lite: session, one context)" ;; *) t_bad "v24.10 R8 the line says (Lite: session, one context)" "[$MLINE]" ;; esac
case "$MLINE" in *"Quick"*) t_bad "v24.10 R8 the Models line does not name Quick" "[$MLINE]" ;; *) t_ok "v24.10 R8 the Models line does not name Quick" ;; esac
LM="$(grep -nF '**Models used:**' "$FINAL" 2>/dev/null | head -n 1 | cut -d: -f1)"
LL="$(grep -nxF '## Learnings proposed' "$FINAL" 2>/dev/null | head -n 1 | cut -d: -f1)"
if [ -n "$LM" ] && [ -n "$LL" ] && [ "$LM" -lt "$LL" ]; then t_ok "R8 the Models used line comes before ## Learnings proposed"; else t_bad "R8 the Models used line comes before ## Learnings proposed" "models line [$LM], learnings heading [$LL]"; fi
LP="$(grep -nF "$LINE" "$FINAL" 2>/dev/null | head -n 1 | cut -d: -f1)"
if [ -n "$LM" ] && [ -n "$LP" ] && [ "$LM" -lt "$LP" ]; then t_ok "R8 the Models used line comes before the Playbook feedback line"; else t_bad "R8 the Models used line comes before the Playbook feedback line" "models line [$LM], feedback line [$LP]"; fi
LC="$(grep -nxF '## Cost' "$FINAL" 2>/dev/null | head -n 1 | cut -d: -f1)"
if [ -n "$LM" ] && [ -n "$LC" ] && [ "$LM" -gt "$LC" ]; then t_ok "R8 the Models used line sits after the Cost section"; else t_bad "R8 the Models used line sits after the Cost section" "models line [$LM], cost heading [$LC]"; fi
assert_eq "R8 regression: the last non-empty line is still the Playbook feedback line" "$LINE" "$(grep -v '^[[:space:]]*$' "$FINAL" 2>/dev/null | tail -n 1)"
assert_eq "R8 regression: nothing non-empty follows the Playbook feedback line" "0" "$(awk -v l="$LINE" '$0 == l { seen = 1; next } seen && NF { n++ } END { print n + 0 }' "$FINAL")"

# ---- v0.24.4 item 5: the Models used line is a fixed report line, like the Playbook feedback line ----
echo "v0.24.4 item 5 SKILL.md Phase 4 tells the report to carry the Models used line verbatim when sub-agents ran"
MLINE_T="$(grep -F '**Models used:**' "$FINAL" 2>/dev/null | head -n 1)"
assert_contains "I5 Phase 4 gives the exact Models used line of the template" "$FULL4" "$MLINE_T"
MITEM="$(printf '%s\n' "$FULL4" | awk -v l="$MLINE_T" '
  function flush() { if (cur != "" && index(cur, l) > 0) print cur; cur = "" }
  /^([0-9]+\.|-) / || NF == 0 { flush() }
  NF { cur = (cur == "" ? $0 : cur " " $0) }
  END { flush() }')"
if printf '%s\n' "$MITEM" | grep -qi 'verbatim'; then t_ok "I5 the Phase 4 item says the Models used line is copied verbatim"; else t_bad "I5 the Phase 4 item says the Models used line is copied verbatim" "[$MITEM]"; fi
if printf '%s\n' "$MITEM" | grep -qiE 'sub-?agents? (ran|were (started|used))|when (any )?sub-?agents'; then t_ok "I5 the Phase 4 item says when: sub-agents ran"; else t_bad "I5 the Phase 4 item says when: sub-agents ran" "[$MITEM]"; fi
if printf '%s\n' "$MITEM" | grep -qE 'Playbook feedback|Learnings proposed'; then t_ok "I5 the Phase 4 item says where the line sits (before the learnings / feedback line)"; else t_bad "I5 the Phase 4 item says where the line sits (before the learnings / feedback line)" "[$MITEM]"; fi
assert_eq "I5 SKILL.md has at most 296 lines" "ok" "$([ "$(wc -l < "$SKILL" | tr -d ' ')" -le 296 ] && echo ok || echo "too long")"


# ---- v0.24.30 lane K (S1): CHARACTERIZATION pins (true today by design; no implementer step) for the weight line ----
echo "v0.24.30 lane K AC6/AC7 characterization pins: the template **Weight:** line and Lite step 5 Weight: Lite"
WCOUNT="$(grep -c '^\*\*Weight:\*\*' "$FINAL" 2>/dev/null)"
assert_eq "v0.24.30 AC6 characterization: exactly one line of the template starts with **Weight:**" "1" "$WCOUNT"
WL="$(grep -n -m1 '^\*\*Weight:\*\*' "$FINAL" 2>/dev/null | cut -d: -f1)"
RC="$(grep -n -m1 '^## Request coverage' "$FINAL" 2>/dev/null | cut -d: -f1)"
if [ -n "$WL" ] && [ -n "$RC" ] && [ "$WL" -lt "$RC" ]; then t_ok "v0.24.30 AC6 characterization: the **Weight:** line comes before ## Request coverage"; else t_bad "v0.24.30 AC6 characterization: the **Weight:** line comes before ## Request coverage" "weight line [$WL], request coverage heading [$RC]"; fi
WTXT="$(grep -m1 '^\*\*Weight:\*\*' "$FINAL" 2>/dev/null)"
for wopt in 'Full' 'Lite (no independent review)' 'Lite (user override; Full criteria: <x>)' 'Exempt' 'reason:'; do
  case "$WTXT" in *"$wopt"*) t_ok "v0.24.30 AC6 characterization: the **Weight:** line lists [$wopt]" ;; *) t_bad "v0.24.30 AC6 characterization: the **Weight:** line lists [$wopt]" "[$WTXT]" ;; esac
done
case "$LITE5" in *'`Weight: Lite`'*) t_ok "v0.24.30 AC7 characterization: Lite step 5 carries the Weight: Lite label" ;; *) t_bad "v0.24.30 AC7 characterization: Lite step 5 carries the Weight: Lite label" "[$LITE5]" ;; esac
case "$LITE5" in "5. Final report with"*) t_ok "v0.24.30 AC7 characterization: Lite step 5 still starts 5. Final report with" ;; *) t_bad "v0.24.30 AC7 characterization: Lite step 5 still starts 5. Final report with" "[$LITE5]" ;; esac
if printf '%s\n' "$LITE5" | tr '\n' ' ' | grep -qiE 'Weight: Lite`?.{0,20}verbatim'; then t_bad "v0.24.30 AC7 characterization: Lite step 5 adds no verbatim after Weight: Lite" "verbatim found within 20 characters"; else t_ok "v0.24.30 AC7 characterization: Lite step 5 adds no verbatim after Weight: Lite"; fi

t_summary
