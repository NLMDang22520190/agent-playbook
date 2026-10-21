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



# ---- v0.24.0 (Lite, content): binding models, release rules in SKILL.md; v0.24.10: the Quick weight is removed ----
RELEASE="$PB_ROOT/skills/playbook-tdd/references/release.md"
QUICKMD="$PB_ROOT/skills/playbook-tdd/references/quick.md"
REVIEWER="$PB_ROOT/skills/playbook-tdd/roles/reviewer.md"

echo "v0.24.10 AC1 SKILL.md: no Quick row in Pick the weight, and the Models line says Lite only"
assert_eq "v24.10 AC1 the Pick the weight table has no Quick row" "0" "$(grep -cE '^\| \*\*Quick\*\*' "$SKILL")"
assert_eq "v24.10 AC1 SKILL.md has no /Quick (the Models line says Lite only)" "0" "$(grep -c '/Quick' "$SKILL")"
SKILL_ONE="$(tr '\n' ' ' < "$SKILL")"
chk "v24.10 AC1 the Models line says (Lite: session, one context)" "$SKILL_ONE" '\(Lite: session, one context\)'

echo "v0.24.10 AC2 SKILL.md: the user's word quick runs Lite with its own label; a Full criterion goes through the override"
chk "v24.10 AC2 the label Weight: Lite (user said quick)" "$WEIGHT" 'Weight: Lite \(user said quick\)'
chk "v24.10 AC2 the word quick counts as the user asking for Lite" "$WEIGHT" 'quick[^.]{0,200}(counts? as|means|maps? to|treated as)[^.]{0,80}Lite|"quick"[^.]{0,160}(run|runs|use|uses)[^.]{0,40}Lite'
chk "v24.10 AC2 a Full criterion with quick goes through the user override" "$WEIGHT" 'quick.{0,250}Full criteri(on|a)[^.]{0,120}(user[- ]override|override (rule|label))'
if [ "$(wc -l < "$SKILL" | tr -d ' ')" -le 296 ]; then t_ok "v24.2 AC6.2 SKILL.md stays within 296 lines"; else t_bad "v24.2 AC6.2 SKILL.md stays within 296 lines" "$(wc -l < "$SKILL") lines"; fi
LROW="$(grep -E '^\| \*\*Lite\*\*' "$SKILL" 2>/dev/null | head -n 1)"
chk "AC1.1 regression: the Lite row keeps its 3 file limit" "$LROW" '≤ 3 production files'
chk "AC1.1 regression: the Lite row keeps its 100 line limit" "$LROW" '≤ 100 changed lines'
l_lite="$(grep -n '^| \*\*Lite\*\*' "$SKILL" 2>/dev/null | head -n 1 | cut -d: -f1)"
l_full="$(grep -n '^| \*\*Full\*\*' "$SKILL" 2>/dev/null | head -n 1 | cut -d: -f1)"
l_exempt="$(grep -n '^| \*\*Exempt\*\*' "$SKILL" 2>/dev/null | head -n 1 | cut -d: -f1)"
if [ -n "$l_full" ] && [ -n "$l_lite" ] && [ -n "$l_exempt" ] && [ "$l_full" -lt "$l_lite" ] && [ "$l_lite" -lt "$l_exempt" ] && [ "$((l_lite - l_full))" -eq 1 ]; then t_ok "v24.10 AC1 the weight table is Full, Lite, Exempt in order, Lite right after Full"
else t_bad "v24.10 AC1 the weight table is Full, Lite, Exempt in order, Lite right after Full" "full=[$l_full] lite=[$l_lite] exempt=[$l_exempt]"; fi
assert_eq "v24.10 AC1 the weight section no longer says Quick escalates to Lite" "0" "$(printf '%s' "$WEIGHT" | grep -ci 'Quick escalates')"
chk "AC1.1 the Pick the weight section still says Full when unsure" "$WEIGHT" 'When unsure,? choose Full|choose Full'

echo "v0.24.0 AC3 SKILL.md points to references/release.md and stays within its line budget (v0.24.10: references/quick.md is gone)"
assert_eq "v24.10 AC1 SKILL.md no longer points to references/quick.md" "0" "$(grep -c 'references/quick\.md' "$SKILL")"
if grep -q 'references/release\.md' "$SKILL"; then t_ok "AC3 SKILL.md points to references/release.md"; else t_bad "AC3 SKILL.md points to references/release.md" "not found"; fi
NREL="$(grep -c 'release\.md' "$SKILL")"
if [ "$NREL" -ge 1 ] && [ "$NREL" -le 4 ]; then t_ok "AC3 SKILL.md has at most 4 lines pointing to release.md ($NREL)"; else t_bad "AC3 SKILL.md has 1-4 lines pointing to release.md" "$NREL lines"; fi
assert_no_path "v24.10 AC1 references/quick.md is deleted" "$QUICKMD"
assert_file "references/release.md exists" "$RELEASE"
NL="$(wc -l < "$SKILL" | tr -d ' ')"
if [ "$NL" -le 296 ]; then t_ok "R9 SKILL.md has at most 296 lines ($NL)"; else t_bad "R9 SKILL.md has at most 296 lines" "$NL lines"; fi
MAXLEN="$(awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }' "$SKILL")"
if [ "$MAXLEN" -le 540 ]; then t_ok "R9 no line of SKILL.md is longer than the current longest (540 chars): no long joined lines to dodge the cap ($MAXLEN)"; else t_bad "R9 no joined long lines" "longest line $MAXLEN chars"; fi

echo "v0.24.0 AC2.5/R7/R9 SKILL.md: a configured model is binding, the plan line, ask once, headless, effort"
ROLES="$(flat "$SKILL" '^## Starting roles per harness' 2)"
# v0.24.13: the harness and model plumbing (spawn mechanics, effort passing) moved to references/harnesses.md
HARNMD="$PB_ROOT/skills/playbook-tdd/references/harnesses.md"
HARN="$(tr '\n' ' ' < "$HARNMD" 2>/dev/null)"
if [ -n "$ROLES" ]; then t_ok "the Starting roles per harness section exists"; else t_bad "the Starting roles per harness section exists" "not found"; fi
chk "AC2.5 a configured model is binding" "$ROLES" 'configured model[^.]{0,60}binding|binding[^.]{0,60}(configured )?model'
chk "AC2.5 the agent never upgrades or downgrades it on its own judgement" "$ROLES" 'never (upgrade|downgrade)[^.]{0,80}(own|its) (judg|decision)|never upgrades? or downgrades?'
chk "AC2.5 'hard' or 'Full' is not a reason to change the model" "$ROLES" '(hard|Full)[^.]{0,80}not a reason|not a reason[^.]{0,80}(hard|Full)'
chk "AC2.5 it prints the role-model.sh plan line before starting roles" "$ROLES" 'role-model\.sh plan|`plan` line|plan line'
chk "AC2.5 it asks the user ONCE" "$ROLES" 'ask(s)? the user once|ask once|once, with'
chk "AC2.5 the reason and the cost difference go in the question" "$ROLES" 'reason[^.]{0,60}cost|cost[^.]{0,60}reason'
chk "AC2.5 ask when it wants a different model" "$ROLES" 'wants? a different model'
chk "AC2.5 ask when a role resolves to session on a Full task" "$ROLES" 'resolves? to session[^.]{0,60}Full|Full[^.]{0,60}resolves? to session'
chk "AC2.5 ask when confirm_models=always" "$ROLES" 'confirm_models=always|confirm_models is always'
chk "AC2.5 never ask when confirm_models=never" "$ROLES" 'confirm_models=never[^.]{0,80}never ask|never ask[^.]{0,80}confirm_models=never|(never|not) asks?[^.]{0,60}confirm_models=never'
chk "AC2.5 headless: use the conf, never upgrade" "$ROLES" 'headless[^.]{0,120}(use the conf|conf)[^.]{0,80}never upgrade|headless[^.]{0,160}never upgrade'
chk "R7 the effort is passed where the harness supports it" "$HARN" 'effort[^.]{0,160}(Agent|codex exec|OpenCode)|(Agent|codex exec|OpenCode)[^.]{0,160}effort'
chk "R7 the Claude Code Agent effort parameter" "$HARN" 'Agent[^.]{0,60}`?effort`? parameter|`effort` parameter'
chk "R7 codex exec -c model_reasoning_effort" "$HARN" 'model_reasoning_effort'
chk "R7 otherwise the effort is only printed" "$HARN" '(else|otherwise)[^.]{0,60}print[^.]{0,40}(only|it)|print(ed)? (it )?only'
chk "R7 an unknown confirm_models value is treated as on-change" "$ROLES" 'unknown[^.]{0,80}on-change|on-change[^.]{0,80}unknown'
chk "AC2.5 on-change is the default" "$ROLES" 'on-change[^.]{0,60}default|default[^.]{0,60}on-change'
chk "AC2.5 regression: the resolve-each-role-model rule stays" "$ROLES" 'role-model\.sh <role> --harness <h>'

echo "v0.24.0 AC3.1-AC3.5 (R10, R11) references/release.md holds the release speed rules"
REL="$(tr '\n' ' ' < "$RELEASE" 2>/dev/null)"
if [ -n "$REL" ]; then t_ok "release.md is readable"; else t_bad "release.md is readable" "missing or empty"; fi
chk "AC3.1 review rounds are capped at 2" "$REL" '(capped at|cap of|at most|max(imum)?( of)?) (2|two)[^.]{0,60}(review )?rounds?|(review )?rounds? (are |is )?capped at (2|two)'
chk "AC3.1 per lane or slice" "$REL" 'per lane or slice|per lane or per slice'
chk "AC3.1/R10 round 3 or later: only a MAJOR introduced by this change is fixed" "$REL" '(round 3|3rd round|third round)[^.]{0,200}MAJOR[^.]{0,80}introduced|MAJOR[^.]{0,80}introduced[^.]{0,200}(round 3|3rd round|third round)'
chk "R10 that MAJOR gets one more round" "$REL" 'one more round'
chk "AC3.1 every other finding goes to Found, not fixed" "$REL" 'Found, not fixed'
chk "R10 the cap is for Phase 3 code-review rounds" "$REL" 'Phase 3'
chk "R10 spec-review and dispute limits are unchanged" "$REL" 'spec-review[^.]{0,80}dispute[^.]{0,60}unchanged|dispute[^.]{0,80}spec-review[^.]{0,60}unchanged|(spec review|spec-review) and dispute limits are unchanged'
chk "AC3.2 the reviewer marks findings introduced or pre-existing" "$REL" 'introduced[^.]{0,60}pre-existing|pre-existing[^.]{0,60}introduced'
chk "AC3.2 pre-existing means also present at the base sha" "$REL" 'pre-existing[^.]{0,160}base sha|base sha[^.]{0,160}pre-existing'
chk "AC3.2 pre-existing findings go to the queue" "$REL" 'pre-existing[^.]{0,120}(queue|Found, not fixed)'
chk "AC3.2 a pre-existing security MAJOR is raised to the user in one line" "$REL" 'pre-existing[^.]{0,60}security[^.]{0,60}MAJOR[^.]{0,200}(one line|one-line)'
chk "AC3.2 fix now or queue, not fixed silently" "$REL" 'fix now or queue|fix now[^.]{0,20}queue'
chk "AC3.3 the weight is chosen per item or slice, not per release" "$REL" 'per item or (per )?slice[^.]{0,80}not per release|not per release'
chk "AC3.3 one release may hold Full and Lite items" "$REL" 'Full and Lite items|Full and Lite'
chk "AC3.3/R11 Full for security and core logic" "$REL" 'Full for[^.;]{0,40}security[^.;]{0,40}core logic'
chk "AC3.3/R11 Lite for docs, wording, nits, test refactors" "$REL" 'Lite for[^.]{0,30}docs[^.]{0,30}wording[^.]{0,30}nits[^.]{0,30}test refactors'
chk "AC3.4 slow platform runs happen once before the PR" "$REL" 'slow platform[^.]{0,160}once[^.]{0,60}before the PR|once before the PR'
chk "AC3.4 the example: Windows Git Bash suites" "$REL" 'Windows Git Bash'
chk "AC3.4 not every fix round" "$REL" 'not every fix round|rather than every fix round'
chk "AC3.4 CI is the cross-platform gate" "$REL" 'CI is the cross-platform gate'
chk "AC3.5 prefer releases of 3-5 items" "$REL" 'prefer releases of 3[-–]5 items|releases of 3[-–]5 items'

echo "v0.24.0 AC3.2/R11 roles/reviewer.md: introduced / pre-existing, checked against the base sha"
RV="$(tr '\n' ' ' < "$REVIEWER" 2>/dev/null)"
chk "R11 reviewer.md marks a finding introduced" "$RV" 'introduced'
chk "R11 reviewer.md marks a finding pre-existing" "$RV" 'pre-existing'
chk "R11 reviewer.md checks the base sha for a pre-existing finding" "$RV" 'pre-existing[^.]{0,200}(base sha|BASE_SHA)|(base sha|BASE_SHA)[^.]{0,200}pre-existing'
chk "R11 reviewer.md: the marking is for every finding" "$RV" 'each finding[^.]{0,100}(introduced|pre-existing)|every finding[^.]{0,100}(introduced|pre-existing)|(introduced|pre-existing)[^.]{0,100}each finding'
chk "AC3.2 reviewer.md: regression, no evidence no finding stays" "$RV" 'No evidence, no finding'


echo "v0.24.0 review round 2 F4: the effort command carries --harness"
chk "F4 the effort command is role-model.sh <role> --harness <h> --effort" "$HARN" 'role-model\.sh <role> --harness <h> --effort'

echo "v0.24.2 AC2.1 SKILL.md resolves the reviewer model with role-model.sh, not the generic conf key"
SKTEXT="$(tr '\n' ' ' < "$SKILL" 2>/dev/null)"
chk "AC2.1 'Prefer a different model' is followed (or preceded) by role-model.sh reviewer --harness <h>" "$SKTEXT" 'Prefer a different model.{0,200}role-model\.sh reviewer --harness <h>|role-model\.sh reviewer --harness <h>.{0,200}Prefer a different model'
if printf '%s' "$SKTEXT" | grep -qF 'conf.sh get model_reviewer'; then
  t_bad "AC2.1 SKILL.md no longer says conf.sh get model_reviewer" "the generic key is still named in $SKILL"
else
  t_ok "AC2.1 SKILL.md no longer says conf.sh get model_reviewer"
fi

echo "v0.24.13 lane R: the harness and model plumbing moves to references/harnesses.md; the binding rules stay in SKILL.md"
assert_file "R13 references/harnesses.md exists" "$HARNMD"
POINTER='How to start roles in each harness (native, manual, none), pass the model and effort, and cache the prompt prefix: `references/harnesses.md`.'
if grep -qxF -- "$POINTER" "$SKILL"; then t_ok "R13 SKILL.md has the pointer line to references/harnesses.md"; else t_bad "R13 SKILL.md has the pointer line to references/harnesses.md" "no line exactly [$POINTER]"; fi
chk "R13 the pointer sits in the Starting roles section" "$ROLES" 'references/harnesses\.md'
chk "R13 harnesses.md: native spawns a sub-agent per role with a fresh context" "$HARN" '\*\*native\*\*[^.]{0,80}sub-agent per role[^.]{0,40}fresh context'
chk "R13 harnesses.md: native passes the role file and input paths, not the conversation" "$HARN" 'full text of the role file[^.]{0,80}not your conversation'
chk "R13 harnesses.md: Claude Code Agent/Task tool with the model parameter" "$HARN" 'Agent`/`Task` tool[^.]{0,40}`model` parameter'
chk "R13 harnesses.md: OpenCode per-role agent in opencode.json" "$HARN" 'per-role agent in `opencode\.json`'
chk "R13 harnesses.md: Codex manual mode with codex exec -m" "$HARN" 'codex exec -m <model>'
chk "R13 harnesses.md: manual runs each role as a separate headless process" "$HARN" '\*\*manual\*\*[^.]{0,80}separate headless process'
chk "R13 harnesses.md: manual examples claude -p, codex exec, opencode run" "$HARN" 'claude -p[^.]{0,40}codex exec[^.]{0,40}opencode run'
chk "R13 harnesses.md: none (degraded) and its report line" "$HARN" '\*\*none\*\* \(degraded\).{0,250}degraded mode: roles shared one context'
chk "R13 harnesses.md: the fixed prompt prefix can be cached" "$HARN" 'fixed prefix can be cached'
chk "R13 harnesses.md: the honest limit on shared blind spots" "$HARN" 'same model in fresh contexts still shares blind spots'
for p in 'opencode.json' 'codex exec -m' 'model_reasoning_effort' 'claude -p' 'shares blind spots' 'Agent`/`Task` tool' 'never your earlier reasoning'; do
  if grep -qF -- "$p" "$SKILL"; then t_bad "R13 moved, not copied: SKILL.md no longer says [$p]" "still in $SKILL"; else t_ok "R13 moved, not copied: SKILL.md no longer says [$p]"; fi
done
chk "R13 stays in SKILL.md: the mechanical model routing" "$ROLES" 'Mechanical work[^.]{0,80}uses the `mechanical` model'
chk "R13 stays in SKILL.md: reviewer_light for tests, docs or skill text" "$ROLES" '`reviewer_light` for a review of a diff that only touches tests, docs or skill text'
chk "R13 stays in SKILL.md: build role prompts from templates/role-prompt.md" "$ROLES" 'Build every sub-agent prompt from `templates/role-prompt\.md`'
echo "v0.24.13 review round 1: the binding none-mode rule and the native isolation clause stay in SKILL.md (the mechanics stay moved)"
chk "R13 stays in SKILL.md: native roles get the role file and input paths, never your conversation" "$ROLES" 'Native roles[^.]{0,80}full role file[^.]{0,80}input paths[^.]{0,40}never your conversation'
chk "R13 stays in SKILL.md: none mode plays the roles one after another" "$ROLES" '`none` mode[^.]{0,40}play[s]? the roles one after another'
chk "R13 stays in SKILL.md: none mode commits between roles and re-reads only the hand-off files" "$ROLES" '`none` mode[^.]{0,120}commit between roles[^.]{0,80}re-read only the hand-off files'
chk "R13 stays in SKILL.md: none mode still runs the gates" "$ROLES" '`none` mode[^.]{0,200}still run the gates'
chk "R13 stays in SKILL.md: none mode reports the degraded line" "$ROLES" '`none` mode[^.]{0,250}degraded mode: roles shared one context'
# the "except in `none` mode (see below)" of the opening paragraph must have a target below it
SEEBELOW="$(awk 'f { print } index($0, "except in `none` mode (see below)") { f = 1 }' "$SKILL" 2>/dev/null | tr '\n' ' ')"
if grep -qF 'except in `none` mode (see below)' "$SKILL"; then t_ok "R13 SKILL.md still has the 'except in none mode (see below)' pointer"; else t_bad "R13 SKILL.md still has the 'except in none mode (see below)' pointer" "line not found in $SKILL"; fi
chk "R13 the 'see below' target: none mode is defined below the pointer" "$SEEBELOW" 'In `none` mode[^.]{0,40}play[s]? the roles one after another'
# the Why line of the section reads on its own: no orphan prompt-prefix reason (the prefix caching moved to harnesses.md)
WHY="$(printf '%s' "$ROLES" | grep -oE '\*\*Why:\*\*.*' )"
if [ -n "$WHY" ]; then t_ok "R13 the Starting roles section has a Why line"; else t_bad "R13 the Starting roles section has a Why line" "no **Why:** in the section"; fi
if printf '%s' "$WHY" | grep -qiE 'prompt prefix|cheaper to reuse'; then t_bad "R13 the Why line no longer gives the moved prompt-prefix reason" "$WHY"; else t_ok "R13 the Why line no longer gives the moved prompt-prefix reason"; fi
echo "AC9 (v0.24.17) Preconditions: a dirty start uses role-gate.sh snapshot and --baseline, and not tdd-step.sh"
PRE="$(flat "$SKILL" '^## Preconditions' 3)"
if [ -n "$PRE" ]; then t_ok "AC9 the Preconditions section exists"; else t_bad "AC9 the Preconditions section exists" "no heading matched in $SKILL"; fi
chk "AC9 the clean-tree bullet still mentions a clean tree" "$PRE" 'clean tree'
chk "AC9 names the snapshot command: role-gate.sh snapshot" "$PRE" 'role-gate\.sh`? snapshot'
chk "AC9 says to run the snapshot before the first role" "$PRE" 'snapshot[^.]{0,80}before the first role|before the first role[^.]{0,80}snapshot'
chk "AC9 names the --baseline option" "$PRE" '\-\-baseline'
chk "AC9 says --baseline goes to every gate" "$PRE" '(every|each) gate|gates?[^.]{0,40}\-\-baseline|\-\-baseline[^.]{0,60}(every|each|all) (role )?gate'
chk "AC9 ties it to a dirty tree" "$PRE" 'dirty|pre-existing|already (changed|modified)'
# v0.24.21: tdd-step.sh learns --baseline, so the dirty-tree clause changes from "do not use tdd-step.sh" to "pass --baseline to it too"
chk "v0.24.21 AC1 (was AC9 v0.24.17) says to pass --baseline to tdd-step.sh as well" "$PRE" '(pass|give)[^.]{0,30}--baseline[^.]{0,40}tdd-step\.sh|tdd-step\.sh[^.]{0,40}--baseline'
if printf '%s' "$PRE" | grep -qiE -- "(do not|don.t|never) use[^.]{0,30}tdd-step\.sh"; then t_bad "v0.24.21 AC1 the old 'do not use tdd-step.sh' clause is gone" "still in the Preconditions section"; else t_ok "v0.24.21 AC1 the old 'do not use tdd-step.sh' clause is gone"; fi
chk "AC9 says to commit only the role's paths by hand" "$PRE" 'commit only[^.]{0,60}(path|file)[^.]{0,40}(by hand|manual)|by hand[^.]{0,60}(path|file)'
chk "v0.24.20 the orchestrator checks the baseline digest matches the one snapshot printed" "$PRE" 'digest[^.]{0,30}match|match[^.]{0,30}digest'
echo "v0.24.21 AC1: every role's gate gets the sha recorded before the role"
chk "v0.24.21 AC1 SKILL.md tells to record git rev-parse HEAD" "$SKILL_ONE" 'git rev-parse HEAD'
chk "v0.24.21 AC1 the rule sits next to the generic gate line (Mechanical enforcement)" "$SKILL_ONE" 'Mechanical enforcement.{0,250}rev-parse HEAD|rev-parse HEAD.{0,250}Mechanical enforcement'
chk "v0.24.21 AC1 the rule: record before each role, pass it as --base to that role's gate" "$SKILL_ONE" 'before (each|every|any) role.{0,200}--base|rev-parse HEAD.{0,250}--base'
chk "v0.24.21 AC1 the rule covers every role" "$SKILL_ONE" '(every|each|all) (role|pass)[^.]{0,200}rev-parse HEAD|rev-parse HEAD[^.]{0,250}(every|each|all) (role|pass)|(every|each) role.{0,200}--base'
chk "v0.24.21 r2 the rule near Mechanical enforcement says every pass as well as each role" "$SKILL_ONE" 'Mechanical enforcement.{0,250}(every|each) pass'
echo "v0.24.22 the tdd-step line names --base and --baseline; shared checkouts"
chk "v0.24.22 the tdd-step.sh red|green line names --base and --baseline" "$SKILL_ONE" 'tdd-step\.sh`? red\|green.{0,250}--base[^l].{0,150}--baseline'
HARN="$(tr '\n' ' ' < "$PB_ROOT/skills/playbook-tdd/references/harnesses.md")"
chk "v0.24.22 harnesses.md: concurrent tasks each get their own git worktree add" "$HARN" 'git worktree add.{0,250}(never|not)[^.]{0,60}(share|same)|(never|not)[^.]{0,60}(share|same)[^.]{0,200}git worktree add'
chk "v0.24.22 harnesses.md: pre-existing changes use role-gate.sh snapshot and --baseline" "$HARN" 'role-gate\.sh snapshot.{0,250}--baseline|--baseline.{0,250}role-gate\.sh snapshot'
chk "v0.24.22 harnesses.md: says why no path-scope for out-of-scope changes" "$HARN" '(outside|out-of)[- ]?(its )?scope.{0,200}(unseen|not seen|unnoticed)|(unseen|not seen|unnoticed).{0,200}(outside|out-of)[- ]?(its )?scope'
NGOOD="$(printf '%s' "$SKILL_ONE" | grep -oE 'check (tester|reviewer) --base' | wc -l | tr -d ' ')"
NALL="$(printf '%s' "$SKILL_ONE" | grep -oE 'check (tester|reviewer)' | wc -l | tr -d ' ')"
assert_eq "v0.24.21 AC1 every 'check tester|reviewer' in SKILL.md shows --base" "$NALL" "$NGOOD"
if [ "$NGOOD" -ge 4 ]; then t_ok "v0.24.21 AC1 at least 4 tester/reviewer gate calls show --base (infra tester, RED, spec review, final review): $NGOOD"; else t_bad "v0.24.21 AC1 at least 4 tester/reviewer gate calls show --base (infra tester, RED, spec review, final review)" "only $NGOOD"; fi
chk "v0.24.21 AC1 the tester gate call shows --base" "$SKILL_ONE" 'role-gate\.sh`? check tester --base'
chk "v0.24.21 AC1 the reviewer gate call shows --base" "$SKILL_ONE" 'role-gate\.sh`? check reviewer --base'
# fix round 1: the reviewer/tester gates read --base <sha before the role> (the role files' wording), not a bare <sha>
NSHA="$(printf '%s' "$SKILL_ONE" | grep -oE 'check (tester|reviewer) --base <sha before the role>' | wc -l | tr -d ' ')"
assert_eq "v0.24.21 AC1 (fix 6) every 'check tester|reviewer' in SKILL.md reads --base <sha before the role>" "$NALL" "$NSHA"

echo "v0.24.21 AC2: role files, README and the beginners doc show the gates with --base"
TESTERMD="$PB_ROOT/skills/playbook-tdd/roles/tester.md"
SPECREVMD="$PB_ROOT/skills/playbook-tdd/roles/spec-reviewer.md"
chk "v0.24.21 AC2 roles/tester.md: the tester gate is shown with --base" "$(tr '\n' ' ' < "$TESTERMD")" 'role-gate\.sh`? check tester --base'
chk "v0.24.21 AC2 roles/spec-reviewer.md: the reviewer gate is shown with --base" "$(tr '\n' ' ' < "$SPECREVMD")" 'role-gate\.sh`? check reviewer --base'
for f in README.md docs/tdd-for-beginners.md; do
  case "$f" in README.md) pat='role-gate check (tester|reviewer)' ;; *) pat='gate (tester|reviewer)' ;; esac
  NA="$(grep -cE -- "$pat" "$PB_ROOT/$f")"
  NB="$(grep -E -- "$pat" "$PB_ROOT/$f" | grep -c -- '--base')"
  if [ "$NA" -ge 2 ]; then t_ok "v0.24.21 AC2 $f has the tester and reviewer gate lines: $NA"; else t_bad "v0.24.21 AC2 $f has the tester and reviewer gate lines" "found $NA"; fi
  assert_eq "v0.24.21 AC2 $f: every tester/reviewer gate line shows --base" "$NA" "$NB"
done

TW="$(wc -w < "$SKILL" | tr -d ' ')"
if [ "$TW" -le 3577 ]; then t_ok "R13 SKILL.md is at most 3577 words (3792 at v0.24.12; the none-mode rule restored): $TW"; else t_bad "R13 SKILL.md is at most 3577 words (3792 at v0.24.12; the none-mode rule restored)" "$TW words"; fi
TB="$(awk '$1=="skills/playbook-tdd/SKILL.md"{print $2; exit}' "$PB_ROOT/evals/word-budgets" 2>/dev/null)"
WANT=$(( (TW + 49) / 50 * 50 ))
assert_eq "R13 the playbook-tdd budget is the new count rounded up to the next 50" "$WANT" "$TB"
t_summary
