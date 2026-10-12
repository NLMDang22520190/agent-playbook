#!/usr/bin/env bash
# Content tests for two wording rules of skills/playbook-tdd/SKILL.md (v0.23.0 AC15), from a real v0.22.4 eval run:
#   AC15.1 "Pick the weight": a change limited to a string literal or message text, with no control flow and no data
#          shape, is Lite even in a sensitive module; the sensitivity is stated as a risk line
#   AC15.2 non-interactive run: when a sub-agent fails, is interrupted or times out, the orchestrator never stops to ask;
#          it continues at Lite in its own context and reports that
# Kept apart from tests/test-content.sh. Each check looks only in the section where the rule belongs, on the section
# text joined into one line (so a sentence wrapped over several lines still matches).
. "$(dirname "$0")/lib.sh"
SKILL="$PB_ROOT/skills/playbook-tdd/SKILL.md"

# flat FILE HEADING_REGEX [LEVEL] -> the text from the matching heading to the next heading of level <= LEVEL (default:
# any ##/### heading), on one line
flat() {
  awk -v re="$2" -v lvl="${3:-3}" '
    f && /^#+ / { n = match($0, /[^#]/) - 1; if (n <= lvl) exit }
    !f && /^#+ / && $0 ~ re { f = 1 }
    f { print }' "$1" 2>/dev/null | tr '\n' ' '
}
# chk NAME TEXT REGEX
chk() { if printf '%s' "$2" | grep -qiE -- "$3"; then t_ok "$1"; else t_bad "$1" "pattern [$3] not found in the section"; fi; }

WEIGHT="$(flat "$SKILL" '^## Pick the weight' 3)"
if [ -n "$WEIGHT" ]; then t_ok "the Pick the weight section exists"; else t_bad "the Pick the weight section exists" "no heading matched in $SKILL"; fi

echo "AC15.1 a string-literal or message-text change is Lite, even in a sensitive module"
chk "AC15.1 names a string literal or message text change" "$WEIGHT" 'string literal|message text|comment text'
chk "AC15.1 limits it to no control flow" "$WEIGHT" '(string literal|message text|comment text).{0,250}(no|without|not (touch|chang)[a-z]*) (any )?control[- ]flow|control[- ]flow.{0,120}(string literal|message text|comment text)'
chk "AC15.1 limits it to no data shape" "$WEIGHT" '(string literal|message text|comment text).{0,250}(no|without|not (touch|chang)[a-z]*) (any )?data[- ]shape|data[- ]shape.{0,120}(string literal|message text|comment text)'
chk "AC15.1 says such a change is Lite" "$WEIGHT" '(string literal|message text|comment text).{0,250}Lite|Lite.{0,200}(string literal|message text|comment text)'
chk "AC15.1 says Lite holds even in a sensitive module" "$WEIGHT" '(string literal|message text|comment text).{0,250}(even|also|still)[^.]{0,80}(sensitive|critical)|(sensitive|critical)[^.]{0,120}(string literal|message text|comment text)[^.]{0,120}Lite'
chk "AC15.1 the sensitivity is stated as a risk line" "$WEIGHT" '(sensitiv|critical)[^.]{0,200}risk line|risk line[^.]{0,200}(sensitiv|critical)'
# the existing rules stay: critical code that changes behaviour is still Full
chk "AC15.1 regression: altering or removing existing behaviour of critical code is still Full" "$WEIGHT" 'alters or removes existing behaviour of critical code'
chk "AC15.1 regression: a purely additive change in critical code is still Lite" "$WEIGHT" 'purely additive change inside critical code'

echo "AC15.2 non-interactive run: a failed, interrupted or timed-out sub-agent never stops the orchestrator"
# the rule may sit with the roles-per-harness text, the stop-and-ask list, or the workflow: check the first section that has it
RULE_SECS=""
for h in '^## Starting roles per harness' '^## Stop and ask the user when' '^## Workflow'; do
  RULE_SECS="$RULE_SECS $(flat "$SKILL" "$h" 2)"
done
chk "AC15.2 names the non-interactive run with a failing, interrupted or timed-out sub-agent" "$RULE_SECS" 'non-interactive.{0,250}sub-?agent.{0,200}(fail|interrupt|time[ -]?out)|sub-?agent.{0,120}(fail|interrupt|time[ -]?out).{0,250}non-interactive'
chk "AC15.2 covers all three: fails, interrupted, times out" "$RULE_SECS" 'sub-?agent[^.]{0,60}(fails?|failed)[^.]{0,60}(is |was |gets )?interrupted[^.]{0,60}time[sd]? ?out'
chk "AC15.2 the orchestrator never stops to ask" "$RULE_SECS" 'non-interactive.{0,250}(never|does not|do not|not) (stop|ask|wait|pause|block)|(never|does not|do not|not) (stop|ask|wait|pause|block)[^.]{0,80}(sub-?agent|non-interactive)'
chk "AC15.2 it continues at Lite in its own context" "$RULE_SECS" 'continu[a-z]*[^.]{0,120}Lite[^.]{0,120}(own|its) context|Lite[^.]{0,80}(in|within) (its|the orchestrator.s) own context'
chk "AC15.2 it reports that (the fallback)" "$RULE_SECS" 'non-interactive.{0,250}(fail|interrupt|time[ -]?out).{0,250}Lite.{0,250}(report|log)'
# the interactive rule keeps asking
chk "AC15.2 regression: an open dispute after 2 rounds still stops to ask" "$(flat "$SKILL" '^## Stop and ask the user when' 2)" 'dispute is still open after 2 rounds'


# ---- v0.23.0 review: the Lite exception is about user-visible message or comment text that is not parsed, matched or sent as data ----
echo "AC15.1 review: the exception is worded by what the text is used for, not by 'string literal' alone"
chk "AC15.1 review: names user-visible message or comment text" "$WEIGHT" 'user-visible[^.]{0,60}(message|comment)|(message|comment)[^.]{0,40}text[^.]{0,60}user-visible'
chk "AC15.1 review: only provided the string is not parsed, matched or sent as data" "$WEIGHT" '(provided|only if|as long as|unless|when)[^.]{0,120}(not|never|no)[^.]{0,60}(parsed|matched|sent)[^.]{0,60}(parsed|matched|sent)?[^.]{0,60}(as )?data'
chk "AC15.1 review: all three uses are named (parsed, matched, sent)" "$WEIGHT" 'parsed[^.]{0,40}matched[^.]{0,40}sent|sent[^.]{0,40}parsed[^.]{0,40}matched|matched[^.]{0,40}parsed[^.]{0,40}sent'
chk "AC15.1 review: the rule is still Lite" "$WEIGHT" 'user-visible[^.]{0,250}Lite|Lite[^.]{0,200}user-visible'
if printf '%s' "$WEIGHT" | grep -qi 'string literal'; then
  chk "AC15.1 review: where 'string literal' appears, user-visible or parsed/matched/sent qualifies it nearby" "$WEIGHT" 'string literal.{0,250}(user-visible|parsed|matched|sent as data)|(user-visible|parsed|matched|sent as data).{0,250}string literal'
else
  t_ok "AC15.1 review: 'string literal' is not used as the rule"
fi
if printf '%s' "$WEIGHT" | grep -qiE 'limited to a string literal|only a string literal|just a string literal'; then
  t_bad "AC15.1 review: 'string literal' alone is not the rule" "the section still says the change is limited to a string literal"
else
  t_ok "AC15.1 review: 'string literal' alone is not the rule"
fi

t_summary
