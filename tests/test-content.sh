#!/usr/bin/env bash
# Content tests for v0.6.0 instruction changes (AC5-AC11): required sections and key phrases.
. "$(dirname "$0")/lib.sh"

TDD="$PB_ROOT/skills/playbook-tdd"
SKILL="$TDD/SKILL.md"
TESTER="$TDD/roles/tester.md"
IMPL="$TDD/roles/implementer.md"
REVIEWER="$TDD/roles/reviewer.md"
FINAL="$TDD/templates/final-report.md"
RPROMPT="$TDD/templates/role-prompt.md"
SETUP="$PB_ROOT/skills/playbook-setup/SKILL.md"
QUESTIONS="$PB_ROOT/skills/playbook-setup/references/questions.md"

# has FILE PATTERN: case-insensitive extended regex found in FILE (false if FILE is missing)
has() { grep -qiE -- "$2" "$1" 2>/dev/null; }
# check NAME FILE PATTERN
check() { if has "$2" "$3"; then t_ok "$1"; else t_bad "$1" "pattern [$3] not in $2"; fi; }
# section FILE HEADING_REGEX: text from the matching heading to the next ##/### heading (exclusive)
section() {
  awk -v re="$2" 'BEGIN{IGNORECASE=1} f && /^##+ /{exit} !f && $0 ~ re {f=1} f{print}' "$1" 2>/dev/null
}
# check_sec NAME FILE HEADING_REGEX PATTERN
check_sec() {
  if section "$2" "$3" | grep -qiE -- "$4"; then t_ok "$1"; else t_bad "$1" "pattern [$4] not in section [$3] of $2"; fi
}
# exact_heading NAME FILE HEADING
exact_heading() {
  if grep -qxF -- "$3" "$2" 2>/dev/null; then t_ok "$1"; else t_bad "$1" "no line exactly [$3] in $2"; fi
}
line_of() { grep -n -m1 -- "$2" "$1" 2>/dev/null | cut -d: -f1; }

# --- AC5: focused tests for sub-agents, full run at close-out by orchestrator
for f in "$IMPL" "$REVIEWER"; do
  b="$(basename "$f")"
  check "AC5 $b says run focused tests" "$f" 'focused'
  check "AC5 $b says not the full/whole suite" "$f" '(not|never|instead of|rather than)[^.]{0,60}(full|whole)[^.]{0,20}suite'
  check "AC5 $b says orchestrator runs full suite at close-out" "$f" 'orchestrator[^.]{0,80}(full|whole)|(full|whole)[^.]{0,80}orchestrator'
done
check_sec "AC5 Phase 4 keeps one fresh full run by orchestrator" "$SKILL" '^### Phase 4' 'fresh[^.]{0,120}(full|whole)|(full|whole)[^.]{0,120}fresh'
check_sec "AC5 Phase 4 names lint and typecheck" "$SKILL" '^### Phase 4' 'lint[^.]{0,40}type'
check_sec "AC5 Phase 4 says a failing close-out run starts a new round" "$SKILL" '^### Phase 4' 'fail[^.]{0,160}(new (RED|round)|back to)|(new (RED|round))[^.]{0,160}fail'
check_sec "AC5 Phase 4 says a failing close-out run means not done" "$SKILL" '^### Phase 4' 'not (reported |report(ed)? )?(as )?done|never (report|say)[^.]{0,30}done'

# --- AC6: tester section
SEC='^## Make every check able to fail'
exact_heading 'AC6 tester has exact heading' "$TESTER" '## Make every check able to fail'
check_sec 'AC6 mutant thinking' "$TESTER" "$SEC" 'mutant'
check_sec 'AC6 assertion fails if behaviour missing or wrong' "$TESTER" "$SEC" 'fail[^.]{0,80}(missing|wrong)|(missing|wrong)[^.]{0,80}fail'
check_sec 'AC6 cwd' "$TESTER" "$SEC" 'cwd|working directory'
check_sec 'AC6 project config overrides' "$TESTER" "$SEC" 'config'
check_sec 'AC6 HOME' "$TESTER" "$SEC" 'HOME'
check_sec 'AC6 line endings' "$TESTER" "$SEC" 'line.?ending'
check_sec 'AC6 destructive wrong-target safety' "$TESTER" "$SEC" 'destructive'
check_sec 'AC6 wrong target: empty' "$TESTER" "$SEC" 'empty'
check_sec 'AC6 wrong target: root' "$TESTER" "$SEC" 'root'
check_sec 'AC6 wrong target: foreign repo' "$TESTER" "$SEC" 'foreign|other repo'
# destructive-target paragraph: from the "destructive" bullet up to the next blank line
destr() { section "$TESTER" "$SEC" | awk '/destructive/{f=1} f&&/^$/{exit} f{print}'; }
if destr | grep -qiE -- '(^|[^a-z])home([^a-z]|$)'; then t_ok 'AC6 destructive wrong targets include home'; else t_bad 'AC6 destructive wrong targets include home' 'no "home" in the destructive bullet'; fi
if destr | grep -qiE -- 'cwd|current directory|working directory'; then t_ok 'AC6 destructive wrong targets include cwd'; else t_bad 'AC6 destructive wrong targets include cwd' 'no cwd/current directory in the destructive bullet'; fi
check_sec 'AC6 locale' "$TESTER" "$SEC" 'locale'
check_sec 'AC6 boundaries' "$TESTER" "$SEC" 'boundar'
check_sec 'AC6 already-passing check needs a reason' "$TESTER" "$SEC" 'already pass[^.]{0,60}reason|reason[^.]{0,60}already pass'

# --- AC7: slice size
exact_heading 'AC7 SKILL has exact heading' "$SKILL" '## Slice size'
check_sec 'AC7 cohesive behaviour group' "$SKILL" '^## Slice size' 'cohesive'
check_sec 'AC7 1-5 tests' "$SKILL" '^## Slice size' '1 ?(-|to) ?5'
check_sec 'AC7 avoid one-test slices' "$SKILL" '^## Slice size' 'one-test|single test|1 test'
check_sec 'AC7 split on more than one public surface' "$SKILL" '^## Slice size' 'split[^.]{0,120}(more than one|multiple|two)[^.]{0,40}surface'

# --- AC8: role-prompt template order and use
# Marker headings (documented): "## 1. Fixed" < "## 2. Spec" < "## 3. This slice"
assert_file 'AC8 templates/role-prompt.md exists' "$RPROMPT"
l1="$(line_of "$RPROMPT" '^## 1\. Fixed')"
l2="$(line_of "$RPROMPT" '^## 2\. Spec')"
l3="$(line_of "$RPROMPT" '^## 3\. This slice')"
if [ -n "$l1" ] && [ -n "$l2" ] && [ -n "$l3" ] && [ "$l1" -lt "$l2" ] && [ "$l2" -lt "$l3" ]; then
  t_ok 'AC8 markers ordered: 1. Fixed < 2. Spec < 3. This slice'
else t_bad 'AC8 markers ordered: 1. Fixed < 2. Spec < 3. This slice' "lines: [$l1] [$l2] [$l3]"; fi
check_sec 'AC8 per-slice part has slice id' "$RPROMPT" '^## 3\. This slice' 'slice'
check_sec 'AC8 per-slice part has RED sha' "$RPROMPT" '^## 3\. This slice' 'sha'
check 'AC8 SKILL references role-prompt.md' "$SKILL" 'role-prompt\.md'
check 'AC8 SKILL ties it to prompt caching / prefix' "$SKILL" 'prefix[^.]{0,80}(cach|reuse)|cach[^.]{0,80}prefix'

# --- AC9: starting roles
check_sec 'AC9 Starting roles section uses role-model.sh' "$SKILL" '^## Starting roles' 'role-model\.sh'
check_sec 'AC9 Starting roles names harness values claude, codex, opencode' "$SKILL" '^## Starting roles' '`?claude`?[^.]{0,40}`?codex`?[^.]{0,40}`?opencode`?'
check 'AC9 Claude Code Agent/Task model parameter' "$SKILL" '`model` parameter|model parameter'
check 'AC9 OpenCode per-role agent in opencode.json' "$SKILL" 'opencode\.json'
check 'AC9 Codex exec -m' "$SKILL" 'codex exec -m'
check 'AC9 session means no override' "$SKILL" 'session[^.]{0,80}(no override|not override|do not override|dont override|without override)|(no override|not override|do not override)[^.]{0,80}session'

# --- AC10: cost in final report and close-out
exact_heading 'AC10 final-report has exact heading' "$FINAL" '## Cost'
check_sec 'AC10 Cost mentions cost.sh summary' "$FINAL" '^## Cost' 'cost\.sh summary'
check_sec 'AC10 Cost mentions weight' "$FINAL" '^## Cost' 'weight'
check_sec 'AC10 Cost mentions wall-clock' "$FINAL" '^## Cost' 'wall.?clock'
check_sec 'AC10 Phase 4 close-out logs runs with cost.sh add' "$SKILL" '^### Phase 4' 'cost\.sh add'
check 'AC10 SKILL says tokens 0 if unknown' "$SKILL" 'unknown[^.]{0,40}`?0`?|`?0`?[^.]{0,40}unknown'

# --- AC11: setup asks models per role per harness with a recommendation
for f in "$SETUP" "$QUESTIONS"; do
  b="$(basename "$(dirname "$f")")/$(basename "$f")"
  check "AC11 $b mentions opencode models" "$f" 'opencode models'
  check "AC11 $b mentions recommendation" "$f" 'recommendation table'
  check "AC11 $b mentions model_<role>_<harness>" "$f" 'model_<role>_<harness>'
  check "AC11 $b reviewer strongest / other vendor" "$f" 'strongest|another vendor|other vendor|different vendor'
  check "AC11 $b implementer mid-tier" "$f" 'mid-?tier'
  check "AC11 $b tester low-tier" "$f" 'low-?tier'
  check "AC11 $b relative cost" "$f" 'relative cost'
done
check 'AC11 setup lists configured models for Codex' "$SETUP" 'configured models'
check 'AC11 setup stores with conf.sh' "$SETUP" 'conf\.sh[^.]{0,120}model_|model_[^.]{0,120}conf\.sh'
check 'AC11 setup lets user accept or pick others' "$SETUP" 'accept[^.]{0,80}(pick|choose|other)'

# --- #1 AC1.3 / AC1.4: setup never writes generic model keys; E18 scenario
check 'AC1.3 setup runs role-model.sh check' "$SETUP" 'role-model\.sh check'
check 'AC1.3 setup says never write generic model_<role> keys' "$SETUP" 'never[^.]{0,80}generic[^.]{0,80}model_<role>|generic[^.]{0,80}model_<role>[^.]{0,80}never'
check 'AC1.3 setup says never write undocumented keys' "$SETUP" 'never[^.]{0,60}(not documented|undocumented)|never[^.]{0,60}keys[^.]{0,40}not (listed|documented)'
check 'AC1.3 setup marks generic keys legacy' "$SETUP" 'legacy'
check 'AC1.3 legacy mention is near the generic model keys' "$SETUP" 'model_(tester|implementer|reviewer)[^.]{0,200}legacy|legacy[^.]{0,200}model_(tester|implementer|reviewer)'
check 'AC1.3 legacy keys are read, not written' "$SETUP" 'read[^.]{0,40}not written|legacy[^.]{0,120}(read|fallback)'
SCEN="$PB_ROOT/evals/scenarios.md"
check 'AC1.4 scenarios has an E18 heading' "$SCEN" '^## E18 '
check 'AC1.4 E18 mentions role-model.sh check' "$SCEN" 'role-model\.sh check'
check_sec 'AC1.4 E18 section covers list --harness unchanged' "$SCEN" '^## E18 ' 'list --harness'
check_sec 'AC1.4 E18 section covers model_<role>_<harness> storage' "$SCEN" '^## E18 ' 'model_<role>_'


# --- v0.9.0 #2 AC2.1 / AC2.2: the named skill is loaded, not just named
BLOCK="$PB_ROOT/AGENTS.global.md"
LOADSEC='^### Load the skill, not the summary'
exact_heading 'AC2.1 block has exact heading' "$BLOCK" '### Load the skill, not the summary'
check_sec 'AC2.1 section mentions the Skill tool' "$BLOCK" "$LOADSEC" '`?Skill`? tool'
check_sec 'AC2.1 section mentions SKILL.md (Codex/OpenCode)' "$BLOCK" "$LOADSEC" 'SKILL\.md'
check_sec 'AC2.1 section says to say which skill was loaded' "$BLOCK" "$LOADSEC" '(say|state|name|tell)[^.]{0,60}(which|the) skill[^.]{0,40}loaded|loaded[^.]{0,60}(say|state|name)'
check_sec 'AC2.1 section says the block is a summary, not the procedure' "$BLOCK" "$LOADSEC" 'summary[^.]{0,80}(not|never)[^.]{0,40}procedure|not the procedure'
if section "$BLOCK" "$LOADSEC" | grep -qE -- '^Why: '; then t_ok 'AC2.1 section has a "Why:" line'; else t_bad 'AC2.1 section has a "Why:" line' 'no line starting with "Why: " in the section'; fi

E19='^## E19 The named skill is loaded before the work'
exact_heading 'AC2.2 scenarios has the E19 heading' "$SCEN" '## E19 The named skill is loaded before the work'
check_sec 'AC2.2 E19 has a Prompt line' "$SCEN" "$E19" '^\*\*Prompt:\*\*'
check_sec 'AC2.2 E19 has a Pass if line' "$SCEN" "$E19" '^\*\*Pass if:\*\*'
check_sec 'AC2.2 E19 has a Fail if line' "$SCEN" "$E19" '^\*\*Fail if:\*\*'
check_sec 'AC2.2 E19 mentions the Skill call for playbook-tdd' "$SCEN" "$E19" 'Skill[^.]{0,60}playbook-tdd'
check_sec 'AC2.2 E19 mentions reading playbook-tdd/SKILL.md' "$SCEN" "$E19" 'playbook-tdd/SKILL\.md'
check_sec 'AC2.2 E19 ties the load to before the first test' "$SCEN" "$E19" 'before[^.]{0,60}first test'
l18="$(line_of "$SCEN" '^## E18 ')"; l19="$(line_of "$SCEN" '^## E19 ')"
if [ -n "$l18" ] && [ -n "$l19" ] && [ "$l18" -lt "$l19" ]; then t_ok 'AC2.2 E19 comes after E18'; else t_bad 'AC2.2 E19 comes after E18' "E18 line [$l18] E19 line [$l19]"; fi

# --- v0.9.0 #4 AC4.6: the test-infra role is documented
TDDALL="$(cat "$SKILL" "$TESTER" "$IMPL" "$REVIEWER" "$RPROMPT" 2>/dev/null)"
# paragraphs (blank-line separated) that talk about infra
infra_paras() { printf '%s\n' "$TDDALL" | awk 'BEGIN{RS="";ORS="\n\n";IGNORECASE=1} /infra/'; }
IP="$(infra_paras)"
case "$IP" in *[![:space:]]*) t_ok 'AC4.6 playbook-tdd has an infra paragraph' ;; *) t_bad 'AC4.6 playbook-tdd has an infra paragraph' 'no paragraph mentions infra' ;; esac
case "$IP" in *"check infra"*) t_ok 'AC4.6 playbook-tdd mentions `check infra`' ;; *) t_bad 'AC4.6 playbook-tdd mentions `check infra`' 'not found' ;; esac
if printf '%s\n' "$IP" | grep -qiE -- 'check infra[^.]{0,40}--base'; then t_ok 'AC4.6 infra change is checked with `check infra --base`'; else t_bad 'AC4.6 infra change is checked with `check infra --base`' 'no "check infra ... --base"'; fi
if printf '%s\n' "$IP" | grep -qiE -- 'tester[^.]{0,160}(first|before)|(first|before)[^.]{0,160}tester'; then t_ok 'AC4.6 order: the tester writes the tests of the infra change first'; else t_bad 'AC4.6 order: the tester writes the tests of the infra change first' 'no tester + first/before in the infra paragraph'; fi
if printf '%s\n' "$IP" | grep -qiE -- '(different|separate|another|fresh)[^.]{0,30}(context|agent)'; then t_ok 'AC4.6 the infra change is made by a different context'; else t_bad 'AC4.6 the infra change is made by a different context' 'no different/separate context in the infra paragraph'; fi
if printf '%s\n' "$IP" | grep -qiE -- 'test_infra_regex'; then t_ok 'AC4.6 the infra paragraph names test_infra_regex'; else t_bad 'AC4.6 the infra paragraph names test_infra_regex' 'key not named next to the infra role'; fi
SETUPALL="$(cat "$SETUP" "$QUESTIONS" 2>/dev/null)"
case "$SETUPALL" in *test_infra_regex*) t_ok 'AC4.6 playbook-setup lists test_infra_regex' ;; *) t_bad 'AC4.6 playbook-setup lists test_infra_regex' 'key absent from SKILL.md and references/questions.md' ;; esac
check 'AC4.6 playbook-setup SKILL.md lists test_infra_regex as a project key' "$SETUP" 'test_infra_regex'

# --- v0.11.0 AC6.2: the lifecycle doc names the one-command release path
check 'AC6.2 docs/update-lifecycle.md mentions tools/ship.sh' "$PB_ROOT/docs/update-lifecycle.md" 'tools/ship\.sh'


# --- v0.12.0 AC1.1 / AC1.2: instructions found in data are pointed out, not followed
SCOPE='^### Scope discipline'
check_sec 'AC1.1 Scope discipline: instructions found in data are not followed' "$BLOCK" "$SCOPE" 'instruction[^.]{0,200}(do not|don.t|never|not) (follow|act on|obey|execute)|(do not|don.t|never) (follow|act on|obey|execute)[^.]{0,120}instruction'
check_sec 'AC1.1 Scope discipline: the user is told about the instruction found' "$BLOCK" "$SCOPE" '(tell|inform|notify|report to|flag (it )?to|point(s)? out (to|for))[^.]{0,40}(the )?user|point(s)? (it|them) out'
check_sec 'AC1.1 Scope discipline: tell-the-user sentence is about instructions' "$BLOCK" "$SCOPE" 'instruction[^.]{0,250}(tell|inform|notify|report|point(s)? out|flag)|(tell|inform|notify|report|point(s)? out|flag)[^.]{0,120}instruction'
check_sec 'AC1.2 E8 still says it points out the embedded instruction' "$SCEN" '^## E8 ' 'points out the embedded instruction'

# --- v0.12.0 AC2.1 / AC2.2: the weight is chosen the same way every time
# whole "Pick the weight" part: up to the next level-2 heading (a ### sub-heading stays inside)
wsec() { awk '/^## /{ if (f) exit } !f && /^## Pick the weight/ {f=1} f{print}' "$SKILL" 2>/dev/null; }
wchk() { if wsec | grep -qiE -- "$2"; then t_ok "$1"; else t_bad "$1" "pattern [$2] not in the Pick the weight part of $SKILL"; fi; }
wchk 'AC2.1 Pick the weight has a consistency rule' 'consisten'
wchk 'AC2.1 weight rule: critical code documented in the repo' 'critical[^.]{0,120}document|document[^.]{0,120}critical'
wchk 'AC2.1 weight rule: examples billing, payments, auth' 'billing[^.]{0,80}payment[^.]{0,80}auth'
wchk 'AC2.1 weight rule: existing behaviour untouched' 'untouched|unchanged|not (alter|chang|touch)[^.]{0,30}existing'
wchk 'AC2.1 weight line quotes the file:line or rule that decided it' 'quote[^.]{0,80}(file:line|line|rule)|(file:line|rule)[^.]{0,80}quote'
E1='^## E1 '
check_sec 'AC2.2 E1 mentions the weight' "$SCEN" "$E1" 'weight'
check_sec 'AC2.2 E1 expects the weight stated with its reason' "$SCEN" "$E1" 'weight[^.]{0,120}reason|reason[^.]{0,120}weight'
check_sec 'AC2.2 E1 expects Lite for the additive subtract' "$SCEN" "$E1" 'lite[^.]{0,160}(subtract|additive)|(subtract|additive)[^.]{0,160}lite'

# --- v0.12.0 AC3.1: a request to skip tests for a behaviour change
TDDSEC='^### TDD with separated roles'
check_sec 'AC3.1 TDD section covers a user request to skip tests' "$BLOCK" "$TDDSEC" '(user|they)[^.]{0,60}(ask|want|request)[^.]{0,60}(skip|without|no) tests|(skip|without|no) tests[^.]{0,80}(ask|request)'
check_sec 'AC3.1 TDD section says a failing test is cheap' "$BLOCK" "$TDDSEC" 'cheap'
check_sec 'AC3.1 TDD section offers the failing test' "$BLOCK" "$TDDSEC" 'offer'
check_sec 'AC3.1 TDD section says to ask only once' "$BLOCK" "$TDDSEC" 'once'
check_sec 'AC3.1 TDD section: if the user declines, label the result untested' "$BLOCK" "$TDDSEC" 'declin[^.]{0,160}untested|untested[^.]{0,160}declin'

# --- v0.12.0 review round 1: E1 note placement, narrow Lite case, injection exceptions, headless skip-tests
# joined text of a section (newlines -> spaces), so a sentence split over lines is still one sentence
jsec() { section "$1" "$2" | tr '\n' ' '; }
jchk() { if printf '%s' "$(jsec "$2" "$3")" | grep -qE -- "$4"; then t_ok "$1"; else t_bad "$1" "pattern [$4] not in joined section [$3] of $2"; fi; }
jwchk() { if wsec | tr '\n' ' ' | grep -qiE -- "$2"; then t_ok "$1"; else t_bad "$1" "pattern [$2] not in the joined Pick the weight part"; fi; }
# finding 1: the E1 Pass-if parenthesis is intact (the weight note may not sit inside it)
if jsec "$SCEN" '^## E1 ' | grep -qiE -- 'asks nothing \(or at most one question that really matters\)'; then t_ok 'R1.1 E1 Pass-if parenthesis "(or at most one question that really matters)" is uninterrupted'; else t_bad 'R1.1 E1 Pass-if parenthesis "(or at most one question that really matters)" is uninterrupted' 'text between "really" and "matters)"'; fi
check_sec 'R1.1 E1 still mentions the weight note after the Pass-if sentence' "$SCEN" "$E1" 'weight'
# finding 2: the Lite case is narrow, "critical" is defined by the repo's docs, Full/Lite cannot be swapped
jwchk 'R1.2 Lite case is an internal or private additive change' 'additive[^.]{0,255}(internal|private)|(internal|private)[^.]{0,255}additive'
jwchk 'R1.2 Lite case: no change or removal of an existing public API' 'additive[^.]{0,255}public api'
jwchk 'R1.2 Lite case: no change to an existing data shape' 'additive[^.]{0,255}data shape'
jwchk 'R1.2 Lite case: no money movement' 'additive[^.]{0,255}money'
jwchk 'R1.2 the additive case ends in Lite (not Full)' 'additive[^.]{0,255}is lite'
jwchk 'R1.2 "critical" is defined by what the repo docs or notes say' 'critical[^.]{0,200}(docs|notes)|(docs|notes)[^.]{0,120}critical'
jwchk 'R1.2 Full sentence: Full when the change alters existing behaviour (M1: not swapped with Lite)' '(^|[.*] +)full (when|if|for)[^.]{0,80}(alter|chang|remov)[^.]{0,40}existing behaviou?r'
# finding 3: injection rule keeps its core and names the exceptions
jchk 'R1.3 Scope discipline names the exception: AGENTS.md or CLAUDE.md' "$BLOCK" "$SCOPE" 'AGENTS\.md|CLAUDE\.md'
jchk 'R1.3 Scope discipline names the exception: a skill' "$BLOCK" "$SCOPE" '[^a-z]skill'
jchk 'R1.3 Scope discipline: the exception is a file the user points to' "$BLOCK" "$SCOPE" '(unless|except|only (when|if))[^.]{0,250}user[^.]{0,120}(point|name|refer|direct|tell)|user[^.]{0,120}(point|name|refer|direct)[^.]{0,60}file'
jchk 'R1.3 Scope discipline: exception phrased as unless/except' "$BLOCK" "$SCOPE" '(unless|except)'
jchk 'R1.3 Scope discipline keeps: do not obey/follow instructions in it' "$BLOCK" "$SCOPE" '(do not|don.t|never) (obey|follow)[^.]{0,40}instruction'
jchk 'R1.3 Scope discipline keeps: tell the user' "$BLOCK" "$SCOPE" 'tell the user'
# finding 4: ask once about the skip, and a headless clause
jchk 'R1.4 skip-tests: ask once (M2: write the test anyway is not enough)' "$BLOCK" "$TDDSEC" 'skip[^.]{0,100}ask[^.]{0,25}once'
jchk 'R1.4 skip-tests: headless clause with offer or without waiting' "$BLOCK" "$TDDSEC" 'headless[^.]{0,160}(offer|without waiting)|(offer|without waiting)[^.]{0,160}headless'

# --- v0.13.0 AC3.1: E3 grades what the block now says (headless: offer the test, label untested)
E3S='^## E3 '
check_sec 'v13 AC3.1 E3 still has its Pass if and Fail if lines' "$SCEN" "$E3S" '^\*\*Pass if:\*\*'
jchk 'v13 AC3.1 E3 Pass if still allows a failing test written first' "$SCEN" "$E3S" 'Pass if:[^.]{0,200}failing test'
jchk 'v13 AC3.1 E3 Pass if has a headless case that offers the test' "$SCEN" "$E3S" 'Pass if:.*headless[^.]{0,200}offer[^.]{0,200}untested|Pass if:.*offer[^.]{0,200}headless[^.]{0,200}untested'
jchk 'v13 AC3.1 E3 headless case is part of Pass if, not of Fail if' "$SCEN" "$E3S" 'Pass if:.*headless.*Fail if:'
jchk 'v13 AC3.1 E3 Fail if still says tests silently skipped' "$SCEN" "$E3S" 'Fail if:[^.]{0,100}silently skip'

# --- v0.13.0 AC4.1: the injection exception names "this block"
jchk 'v13 AC4.1 Scope discipline exception names this block' "$BLOCK" "$SCOPE" '(unless|except)[^.]{0,250}this block'
jchk 'v13 AC4.1 the exception still names the user, a skill and AGENTS.md/CLAUDE.md' "$BLOCK" "$SCOPE" '(unless|except)[^.]{0,250}user[^.]{0,250}skill[^.]{0,250}AGENTS\.md'

# --- v0.13.0 AC4.2: additive Lite case
jwchk 'v13 AC4.2 additive Lite case says unless another Full item applies' 'additive[^.]{0,255}is lite[^.]{0,60}unless another Full item applies'
jwchk 'v13 AC4.2 a new exported function counts as additive' 'exported function[^.]{0,200}(additive|is lite)|(additive|is lite)[^.]{0,200}exported function'
jwchk 'v13 AC4.2 the exported-function sentence ties it to changing no existing public API' 'exported function[^.]{0,250}(no|not|without)[^.]{0,60}existing[^.]{0,30}public api|existing[^.]{0,30}public api[^.]{0,200}exported function'
jwchk 'v13 AC4.2 the Full side stays: alters or removes existing behaviour is Full' '(^|[.*] +)full (when|if|for)[^.]{0,80}(alter|chang|remov)[^.]{0,40}existing behaviou?r'

# --- v0.13.0 AC5.1: the always-on block fits with headroom
BLOCK_BYTES="$(wc -c < "$BLOCK" | tr -d ' ')"
# v0.24.0 AC1.7: the Quick line (<= 160 bytes) moves the ceiling from 4850 to 5000 bytes, the run-checks cap; v0.24.1 shrinks the block
if [ "$BLOCK_BYTES" -le 5000 ]; then t_ok "v13 AC5.1 / v24 AC1.7 AGENTS.global.md is <= 5000 bytes (v0.24.1 shrinks the block) ($BLOCK_BYTES)"; else t_bad "v13 AC5.1 / v24 AC1.7 AGENTS.global.md is <= 5000 bytes (v0.24.1 shrinks the block)" "$BLOCK_BYTES bytes"; fi

# --- v0.24.1: a shorter always-on block with the same rules
# <= 4200 bytes, so the one-line Quick weight of v0.24 (<= 160 bytes) still fits under 4400
if [ "$BLOCK_BYTES" -le 4400 ]; then t_ok "v24.1 AGENTS.global.md is <= 4400 bytes (4200 plus the v0.24.0 Quick line) ($BLOCK_BYTES)"; else t_bad "v24.1 AGENTS.global.md is <= 4400 bytes (4200 plus the v0.24.0 Quick line)" "$BLOCK_BYTES bytes"; fi
# every rule section keeps its exact heading and its "Why: " line
for h in '### Clarify before changing' '### Load the skill, not the summary' '### Proof for every claim' '### Scope discipline' \
         '### TDD with separated roles' '### When other skills overlap' '### Learnings and playbook feedback' '### First run and precedence'; do
  exact_heading "v24.1 block keeps the heading [$h]" "$BLOCK" "$h"
  if section "$BLOCK" "^$h\$" | grep -qE -- '^Why: [^ ]'; then t_ok "v24.1 [$h] keeps its Why: line"; else t_bad "v24.1 [$h] keeps its Why: line" 'no line starting with "Why: " in the section'; fi
done
exact_heading 'v24.1 block keeps its title' "$BLOCK" '## Agent Playbook (always on)'
# key rules pinned, each in its own section (joined text, so a wrapped sentence still matches)
CLAR24='^### Clarify before changing'; PROOF='^### Proof for every claim'; LEARN='^### Learnings and playbook feedback'; FIRST='^### First run and precedence'; OVER='^### When other skills overlap'
jchk 'v24.1 Clarify: inspect first (code, config, docs, git history)' "$BLOCK" "$CLAR24" 'Inspect first[^.]{0,20}code, config, docs, git history'
jchk 'v24.1 Clarify: never ask what the repo can answer' "$BLOCK" "$CLAR24" 'Never ask what the repo can answer'
jchk 'v24.1 Clarify: ask only when material AND hard to reverse' "$BLOCK" "$CLAR24" 'material AND hard to reverse'
jchk 'v24.1 Clarify: the hard-to-reverse list' "$BLOCK" "$CLAR24" 'public API or data shape, migrations, security, money, anything sent outside[^.]{0,20}product choice[^.]{0,30}user'
jchk 'v24.1 Clarify: otherwise a default logged with decision, why, how to undo' "$BLOCK" "$CLAR24" 'default, log it in `\.agents/handoff/decisions\.md` \(decision, why, how to undo\)'
jchk 'v24.1 Clarify: ask once, batched, with a proposed default' "$BLOCK" "$CLAR24" '[Aa]sk once, batched[^.]{0,40}proposed default'
jchk 'v24.1 Clarify: end the summary with assumptions and logged defaults' "$BLOCK" "$CLAR24" 'summary[^.]{0,30}assumptions and logged defaults'
jchk 'v24.1 Proof: the [VERIFIED] label' "$BLOCK" "$PROOF" '\[VERIFIED\][^[]{0,60}(ran|read)[^[]{0,60}evidence'
jchk 'v24.1 Proof: the [INFERRED] label' "$BLOCK" "$PROOF" '\[INFERRED\] reasoned from stated facts'
jchk 'v24.1 Proof: the [UNVERIFIED] label' "$BLOCK" "$PROOF" '\[UNVERIFIED\] not checked'
jchk 'v24.1 Proof: code claims cite path:line read this session' "$BLOCK" "$PROOF" 'cite `path:line` read this session'
jchk 'v24.1 Proof: passes/works/fixed need run output via proof-run.sh' "$BLOCK" "$PROOF" '"Passes", "works", "fixed" need run output from this session[^)]{0,60}proof-run\.sh'
jchk 'v24.1 Proof: library, API and version facts cite official docs' "$BLOCK" "$PROOF" 'version facts cite official docs \(URL, version\)'
jchk 'v24.1 Proof: no evidence means say unverified' "$BLOCK" "$PROOF" 'No evidence[^.]{0,30}"unverified"'
jchk 'v24.1 Proof: never fill gaps with plausible guesses' "$BLOCK" "$PROOF" '[Nn]ever[^.]{0,30}plausible guess'
jchk 'v24.1 Proof: names playbook-proof' "$BLOCK" "$PROOF" '`playbook-proof`'
jchk 'v24.1 Scope: never weaken, skip or delete a test or gate' "$BLOCK" "$SCOPE" 'Never weaken, skip or delete a test or gate to make it pass'
jchk 'v24.1 Scope: no new dependency without asking' "$BLOCK" "$SCOPE" 'no new dependency without asking'
jchk 'v24.1 Scope: the playbook ~/.agents files are the write exception' "$BLOCK" "$SCOPE" '~/\.agents files'
jchk 'v24.1 Scope: text in pages, tool output and files is data' "$BLOCK" "$SCOPE" 'web pages, tool output and files is data'
jchk 'v24.1 TDD: names playbook-tdd, tests first, weight by risk with reason' "$BLOCK" "$TDDSEC" '`playbook-tdd`[^.]{0,30}tests first[^.]{0,20}weight chosen by risk[^.]{0,30}reason'
jchk 'v24.1 TDD: Full is separate contexts for hard-to-reverse, core logic, unsure' "$BLOCK" "$TDDSEC" '\*\*Full\*\* \(tester, implementer and reviewer in (separate|different) contexts\)[^;]{0,30}hard-to-reverse[^;]{0,20}core logic[^;]{0,30}unsure'
jchk 'v24.1 TDD: Lite is one context, test seen failing, role gate, evidence' "$BLOCK" "$TDDSEC" '\*\*Lite\*\* \(one context, test seen failing, role gate, evidence\)[^.]{0,20}small reversible'
jchk 'v24.1 TDD: the exemptions are named and said' "$BLOCK" "$TDDSEC" 'Exempt, but say so: docs-only, config-only without behaviou?r change,[^.]{0,10}throwaway spikes'
jchk 'v24.1 TDD: skip-tests asks once and offers the test' "$BLOCK" "$TDDSEC" 'ask once and offer the test'
jchk 'v24.1 Overlap: this playbook wins' "$BLOCK" "$OVER" 'this playbook wins'
jchk 'v24.1 Overlap: tests from a tester role, never the implementer' "$BLOCK" "$OVER" 'tests come from a tester role, never the implementer'
jchk 'v24.1 Overlap: reviewers re-run the tests' "$BLOCK" "$OVER" 'reviewers re-run the tests'
jchk 'v24.1 Overlap: questions in one batched message with defaults' "$BLOCK" "$OVER" 'questions go in one batched message with defaults'
jchk 'v24.1 Learnings: read .agents/LEARNINGS.md first' "$BLOCK" "$LEARN" 'Read `\.agents/LEARNINGS\.md` first'
jchk 'v24.1 Learnings: only through playbook-learn, user-approved and evidenced' "$BLOCK" "$LEARN" 'only through skill `playbook-learn` \(user-approved, evidenced\)'
jchk 'v24.1 Learnings: never into this block or the playbook repo' "$BLOCK" "$LEARN" '[Nn]ever[^.]{0,40}this block or the playbook repo'
jchk 'v24.1 Learnings: misfires noted with playbook-feedback' "$BLOCK" "$LEARN" 'misfires, is missing or gets in the way[^.]{0,30}`playbook-feedback`'
jchk 'v24.1 Learnings: capture quietly, ask at most once, at the end of a task' "$BLOCK" "$LEARN" 'capture quietly, ask the user at most once, at the end of a task'
jchk 'v24.1 First run: missing playbook.conf runs playbook-setup once' "$BLOCK" "$FIRST" 'playbook\.conf` is missing, run skill `playbook-setup` once before substantial work'
jchk 'v24.1 First run: a decline is recorded with conf.sh' "$BLOCK" "$FIRST" 'declin[^.]{0,40}`~/\.agents/playbook/scripts/conf\.sh set setup declined`'
jchk 'v24.1 First run: precedence user, then AGENTS.md/CLAUDE.md, then this playbook' "$BLOCK" "$FIRST" "Precedence: the user's instruction in chat, then the project's AGENTS\.md/CLAUDE\.md, then this playbook"

# --- v0.14.0 AC8.2: Windows runs as 3 shard jobs plus an aggregator named exactly `test (windows-latest)`
WF="$PB_ROOT/.github/workflows/test.yml"
# wf_jobs -> job ids (2-space indent under jobs:)
wf_jobs() { awk '/^jobs:/ { j = 1; next } j && /^[^ #]/ { j = 0 } j && /^  [A-Za-z0-9_-]+:[ ]*$/ { sub(/^  /, ""); sub(/:.*/, ""); print }' "$WF" 2>/dev/null; }
# wf_block ID -> the lines of that job
wf_block() { awk -v id="$1" '/^jobs:/ { j = 1; next } j && /^[^ #]/ { j = 0 } j && /^  [A-Za-z0-9_-]+:[ ]*$/ { f = ($0 == "  " id ":") } f { print }' "$WF" 2>/dev/null; }
# wf_name ID -> the job's name: value without quotes ("" when none)
wf_name() { wf_block "$1" | grep -m1 '^    name:' | sed 's/^    name:[[:space:]]*//; s/[[:space:]]*$//; s/^"\(.*\)"$/\1/; s/^'"'"'\(.*\)'"'"'$/\1/'; }
# wf_needs ID -> the text of the job's needs: key (inline or list), one line
wf_needs() { wf_block "$1" | awk '/^    needs:/ { f = 1; print; next } f && /^    [A-Za-z]/ { exit } f { print }' | tr '\n' ' '; }
AGG=""; SHARD=""; MAIN=""
for id in $(wf_jobs); do
  [ "$(wf_name "$id")" = "test (windows-latest)" ] && AGG="$id"
done
for id in $(wf_jobs); do
  b="$(wf_block "$id")"
  case "$b" in *PB_SHARD*) case "$b" in *windows-latest*) [ "$id" != "$AGG" ] && SHARD="$id" ;; esac ;; esac
  case "$b" in *macos-latest*) MAIN="$id" ;; esac
done
NAMED="$(for id in $(wf_jobs); do wf_name "$id"; done | grep -cxF 'test (windows-latest)')"
assert_eq "v14 AC8.2 exactly one job has the name: exactly 'test (windows-latest)' (what branch protection requires)" "1" "$NAMED"
if [ -n "$SHARD" ]; then t_ok "v14 AC8.2 a separate shard job on windows-latest sets PB_SHARD ($SHARD)"; else t_bad "v14 AC8.2 a separate shard job on windows-latest sets PB_SHARD" "aggregator [$AGG]; jobs: $(wf_jobs | tr '\n' ' ')"; fi
SB="$(wf_block "${SHARD:-__none__}")"
assert_contains "v14 AC8.2 the shard job runs on windows-latest" "$SB" "windows-latest"
assert_contains "v0.23.3 the shard matrix is exactly 1/4, 2/4, 3/4, 4/4" "$(printf '%s\n' "$SB" | grep -E '^ *shard: *\[')" "shard: ['1/4', '2/4', '3/4', '4/4']"
assert_contains "v0.23.3 the shard matrix has 1/4" "$SB" "1/4"
assert_contains "v0.23.3 the shard matrix has 2/4" "$SB" "2/4"
assert_contains "v0.23.3 the shard matrix has 3/4" "$SB" "3/4"
assert_contains "v0.23.3 the shard matrix has 4/4" "$SB" "4/4"
assert_not_contains "v0.23.3 the shard matrix has no 3/3 left" "$SB" "3/3"
assert_not_contains "v0.23.3 no matrix entry ending in /3' is left" "$SB" "/3'"
if printf '%s\n' "$SB" | grep 'PB_SHARD' | grep -q 'matrix\.'; then t_ok "v14 AC8.2 PB_SHARD is taken from the matrix"; else t_bad "v14 AC8.2 PB_SHARD is taken from the matrix" "PB_SHARD lines: $(printf '%s\n' "$SB" | grep PB_SHARD)"; fi
assert_contains "v14 AC8.2 the shard job still runs tests/run-all.sh" "$SB" "tests/run-all.sh"
assert_contains "v14 AC8.2 a failing shard does not cancel the others (fail-fast: false)" "$SB" "fail-fast: false"
AB="$(wf_block "${AGG:-__none__}")"
NEEDS_AGG="$(wf_needs "${AGG:-__none__}")"
assert_contains "v14 AC8.2 the aggregator needs the shard job" "$NEEDS_AGG" "${SHARD:-__none__}"
if printf '%s\n' "$AB" | grep -Eq '^    if:.*always\(\)'; then t_ok "v14 AC8.2 the aggregator has if: always() (it fails instead of being skipped)"; else t_bad "v14 AC8.2 the aggregator has if: always()" "block: $AB"; fi
if printf '%s\n' "$AB" | grep -Eq "needs\.${SHARD:-__none__}\.result"; then t_ok "v14 AC8.2 the aggregator reads the shard result (needs.$SHARD.result)"; else t_bad "v14 AC8.2 the aggregator reads the shard result (needs.$SHARD.result)" "block: $AB"; fi
if printf '%s\n' "$AB" | grep -Eq 'exit 1'; then t_ok "v14 AC8.2 the aggregator can fail (exit 1)"; else t_bad "v14 AC8.2 the aggregator can fail (exit 1)" "block: $AB"; fi
assert_not_contains "v14 AC8.2 the aggregator does not run the suites itself" "$AB" "tests/run-all.sh"
assert_contains "v14 AC8.2 the aggregator runs on a cheap runner, not windows" "$(printf '%s\n' "$AB" | grep 'runs-on')" "ubuntu"
MB="$(wf_block "${MAIN:-__none__}")"
assert_contains "v14 AC8.2 the main test matrix keeps ubuntu-latest" "$MB" "ubuntu-latest"
assert_contains "v14 AC8.2 the main test matrix keeps macos-latest" "$MB" "macos-latest"
assert_not_contains "v14 AC8.2 the main test matrix no longer has windows-latest" "$MB" "windows-latest"
assert_contains "v14 AC8.2 the main test job still runs tests/run-all.sh" "$MB" "tests/run-all.sh"
if [ -n "$MAIN" ] && [ "$MAIN" != "$SHARD" ] && [ "$MAIN" != "$AGG" ]; then t_ok "v14 AC8.2 the main test job ($MAIN) is separate from the shards and the aggregator"; else t_bad "v14 AC8.2 the main test job is separate from the shards and the aggregator" "main [$MAIN] shard [$SHARD] agg [$AGG]"; fi
NEEDS_REL="$(wf_needs release)"
assert_contains "v14 AC8.2 the release job needs the aggregator" "$NEEDS_REL" "${AGG:-__none__}"
assert_contains "v14 AC8.2 the release job still needs the main test job" "$NEEDS_REL" "${MAIN:-__none__}"

# --- v0.15.0 AC5.1: a v* tag push reuses the main CI run of the same commit instead of rerunning the matrix
# wf_if ID -> the job-level `if:` line (single line), "" when none
wf_if() { wf_block "$1" | grep -m1 '^    if:'; }
# not_tag LINE -> 0 when the condition excludes tag refs: !startsWith(github.ref, 'refs/tags/..') or ref_type != 'tag'
not_tag() { printf '%s\n' "$1" | grep -Eq "![[:space:]]*startsWith\([[:space:]]*github\.ref[[:space:]]*,[[:space:]]*'refs/tags/|github\.ref_type[[:space:]]*!=[[:space:]]*'tag'|!\(?[[:space:]]*startsWith\([[:space:]]*github\.ref"; }
for pair in "test:${MAIN:-__none__}" "windows-shard:${SHARD:-__none__}" "test (windows-latest) aggregator:${AGG:-__none__}"; do
  label="${pair%:*}"; id="${pair##*:}"
  IFL="$(wf_if "$id")"
  if [ -n "$IFL" ] && not_tag "$IFL"; then t_ok "v15 AC5.1 job $label ($id) has an if: that excludes tag pushes"; else t_bad "v15 AC5.1 job $label ($id) has an if: that excludes tag pushes" "if line: [$IFL]"; fi
done
AGGIF="$(wf_if "${AGG:-__none__}")"
case "$AGGIF" in *always\(\)*) t_ok "v15 AC5.1 the aggregator keeps always() next to the tag exclusion (still fails instead of skipping on PRs)" ;; *) t_bad "v15 AC5.1 the aggregator keeps always() next to the tag exclusion" "if line: [$AGGIF]" ;; esac
case "$(wf_if "${MAIN:-__none__}")" in *github.event_name*|*refs/tags*) t_ok "v15 AC5.1 the test job's if: is about the ref (PRs and main pushes still match it)" ;; *) t_bad "v15 AC5.1 the test job's if: is about the ref" "if line: [$(wf_if "${MAIN:-__none__}")]" ;; esac
if wf_jobs | grep -qxF main-ci; then t_ok "v15 AC5.1 a job main-ci exists"; else t_bad "v15 AC5.1 a job main-ci exists" "jobs: $(wf_jobs | tr '\n' ' ')"; fi
CB="$(wf_block main-ci)"
CIF="$(wf_if main-ci)"
if printf '%s\n' "$CIF" | grep -Eq "startsWith\([[:space:]]*github\.ref[[:space:]]*,[[:space:]]*'refs/tags/v" && ! not_tag "$CIF"; then t_ok "v15 AC5.1 main-ci runs on v* tag pushes only (if: startsWith(github.ref, 'refs/tags/v'))"; else t_bad "v15 AC5.1 main-ci runs on v* tag pushes only" "if line: [$CIF]"; fi
case "$CB" in *"gh run"*) t_ok "v15 AC5.1 main-ci uses gh run" ;; *) t_bad "v15 AC5.1 main-ci uses gh run" "block: $CB" ;; esac
if printf '%s\n' "$CB" | grep -Eq 'GITHUB_SHA|github\.sha'; then t_ok "v15 AC5.1 main-ci looks up the run by the commit sha"; else t_bad "v15 AC5.1 main-ci looks up the run by the commit sha" "block: $CB"; fi
if printf '%s\n' "$CB" | grep -Eq -- '--branch[ =]+main|branch=main|head_branch.{0,20}main'; then t_ok "v15 AC5.1 main-ci restricts the lookup to branch main"; else t_bad "v15 AC5.1 main-ci restricts the lookup to branch main" "block: $CB"; fi
if printf '%s\n' "$CB" | grep -Eq -- '--event[ =]+push|event=push|\.event.{0,10}push'; then t_ok "v15 AC5.1 main-ci restricts the lookup to the push event"; else t_bad "v15 AC5.1 main-ci restricts the lookup to the push event" "block: $CB"; fi
if printf '%s\n' "$CB" | grep -Eq -- '--workflow[ =]+[^ ]*test|workflows/test|workflow.{0,10}test'; then t_ok "v15 AC5.1 main-ci names the test workflow"; else t_bad "v15 AC5.1 main-ci names the test workflow" "block: $CB"; fi
if printf '%s\n' "$CB" | grep -Eq -- '--exit-status|conclusion.{0,40}success|success.{0,40}conclusion'; then t_ok "v15 AC5.1 main-ci fails unless the main run succeeded (--exit-status or a conclusion check)"; else t_bad "v15 AC5.1 main-ci fails unless the main run succeeded" "block: $CB"; fi
case "$CB" in *"gh run watch"*|*"gh run list"*|*"gh run view"*|*"gh api"*) t_ok "v15 AC5.1 main-ci finds or waits for the main run (gh run watch/list/view)" ;; *) t_bad "v15 AC5.1 main-ci finds or waits for the main run" "block: $CB" ;; esac
if printf '%s\n' "$CB" | grep -Eq '^      actions:[[:space:]]*read|^    permissions:' && printf '%s\n' "$CB" | grep -Eq 'actions:[[:space:]]*read'; then t_ok "v15 AC5.1 main-ci has actions: read (the default token cannot list workflow runs otherwise)"; else t_bad "v15 AC5.1 main-ci has actions: read" "block: $CB"; fi
if printf '%s\n' "$CB" | grep -Eq 'GH_TOKEN'; then t_ok "v15 AC5.1 main-ci passes GH_TOKEN to gh"; else t_bad "v15 AC5.1 main-ci passes GH_TOKEN to gh" "block: $CB"; fi
assert_not_contains "v15 AC5.1 main-ci does not rerun the suites" "$CB" "tests/run-all.sh"
NEEDS_REL="$(wf_needs release)"
assert_contains "v15 AC5.1 the release job needs main-ci" "$NEEDS_REL" "main-ci"
RIF="$(wf_if release)"
case "$RIF" in *needs.main-ci.result*success*) t_ok "v15 AC5.1 the release if: requires needs.main-ci.result == 'success'" ;; *) t_bad "v15 AC5.1 the release if: requires needs.main-ci.result == 'success'" "if line: [$RIF]" ;; esac
if printf '%s\n' "$RIF" | grep -Eq "needs\.main-ci\.result[[:space:]]*==[[:space:]]*'success'"; then t_ok "v15 AC5.1 the release if: compares with == 'success' (not !=)"; else t_bad "v15 AC5.1 the release if: compares with == 'success'" "if line: [$RIF]"; fi
if printf '%s\n' "$RIF" | grep -Eq 'always\(\)|!cancelled\(\)|!failure\(\)'; then t_ok "v15 AC5.1 the release if: has always()/!cancelled() (test and windows are skipped on tags, so it would be skipped silently)"; else t_bad "v15 AC5.1 the release if: has always()/!cancelled()" "if line: [$RIF]"; fi
assert_contains "v15 AC5.1 the release if: still limits to v* tags" "$RIF" "refs/tags/v"

# --- v0.15.0 AC11.1: close-out captures playbook misfires; the final report has a Playbook feedback line
P4='^### Phase 4'
check_sec 'v15 AC11.1 playbook-tdd Phase 4 mentions playbook-feedback' "$SKILL" "$P4" 'playbook-feedback'
check_sec 'v15 AC11.1 Phase 4 says to capture a misfire' "$SKILL" "$P4" 'misfire'
check_sec 'v15 AC11.1 Phase 4 covers rules, gates or scripts that misfired' "$SKILL" "$P4" 'rule[^.]{0,80}(gate|script)|gate[^.]{0,80}script'
check_sec 'v15 AC11.1 Phase 4 asks for the capture before the final report' "$SKILL" "$P4" 'before[^.]{0,60}final report'
check_sec 'v15 AC11.1 Phase 4 asks for one line per misfire with evidence' "$SKILL" "$P4" 'one line[^.]{0,60}evidence|evidence[^.]{0,60}one line'
check_sec 'v15 AC11.1 Phase 4 still fills the final report template' "$SKILL" "$P4" 'templates/final-report\.md'
check_sec 'v15 AC11.1 Phase 4 still proposes learnings with playbook-learn' "$SKILL" "$P4" 'playbook-learn'
if grep -Eq '^\*\*Playbook feedback:?\*\*' "$FINAL" 2>/dev/null; then t_ok 'v15 AC11.1 final-report has a **Playbook feedback:** line'; else t_bad 'v15 AC11.1 final-report has a **Playbook feedback:** line' "no line starting with **Playbook feedback:** in $FINAL"; fi
if grep -E '^\*\*Playbook feedback:?\*\*' "$FINAL" 2>/dev/null | grep -qi 'none'; then t_ok 'v15 AC11.1 the Playbook feedback line offers "none" as the empty value'; else t_bad 'v15 AC11.1 the Playbook feedback line offers "none"' "$(grep -i 'playbook feedback' "$FINAL" 2>/dev/null)"; fi
if grep -E '^\*\*Playbook feedback:?\*\*' "$FINAL" 2>/dev/null | grep -qiE 'id|captured'; then t_ok 'v15 AC11.1 the Playbook feedback line says captured ids'; else t_bad 'v15 AC11.1 the Playbook feedback line says captured ids' "$(grep -i 'playbook feedback' "$FINAL" 2>/dev/null)"; fi
exact_heading 'v15 AC11.1 final-report keeps the exact ## Cost heading' "$FINAL" '## Cost'

# --- v0.15.0 AC11.2: scenario E20
exact_heading 'v15 AC11.2 scenarios has the E20 heading' "$SCEN" '## E20 A playbook misfire is captured'
E20='^## E20 '
check_sec 'v15 AC11.2 E20 has a Prompt line' "$SCEN" "$E20" '^\*\*Prompt:\*\*'
check_sec 'v15 AC11.2 E20 has a Pass if line' "$SCEN" "$E20" '^\*\*Pass if:\*\*'
check_sec 'v15 AC11.2 E20 has a Fail if line' "$SCEN" "$E20" '^\*\*Fail if:\*\*'
check_sec 'v15 AC11.2 E20 mentions playbook-feedback' "$SCEN" "$E20" 'playbook-feedback'
check_sec 'v15 AC11.2 E20 mentions a misfire' "$SCEN" "$E20" 'misfire'
check_sec 'v15 AC11.2 E20 Pass if mentions the Playbook feedback line of the final report' "$SCEN" "$E20" 'Pass if:.*Playbook feedback'
check_sec 'v15 AC11.2 E20 Fail if covers a misfire fixed but not captured' "$SCEN" "$E20" 'Fail if:.*(not captured|never captured|without captur|no capture|skips|does not capture)'
l19="$(line_of "$SCEN" '^## E19 ')"; l20="$(line_of "$SCEN" '^## E20 ')"
if [ -n "$l19" ] && [ -n "$l20" ] && [ "$l20" -gt "$l19" ]; then t_ok 'v15 AC11.2 E20 comes after E19'; else t_bad 'v15 AC11.2 E20 comes after E19' "E19 at [$l19], E20 at [$l20]"; fi

# --- v0.17.0 AC1.1: the E16 prompt gives the answers a headless agent would otherwise ask for
# The runner sends the first double-quoted string of the **Prompt:** paragraph (evals/run-evals.sh prompt_of), so the new
# wording must sit inside that one quoted string.
E16='^## E16 '
e16_para() { section "$SCEN" "$E16" | awk '/^\*\*Prompt:\*\*/ { p = 1 } /^\*\*(Pass|Fail) if:\*\*/ { p = 0 } p' | tr '\n' ' '; }
e16_sent() { e16_para | sed -n 's/^[^"]*"\([^"]*\)".*/\1/p'; }   # what the runner would send
e16_has() { # NAME PATTERN -> PATTERN (case-insensitive ERE) is in the prompt the runner sends
  if e16_sent | grep -qiE -- "$2"; then t_ok "$1"; else t_bad "$1" "pattern [$2] not in the E16 prompt as sent: [$(e16_sent)]"; fi
}
e16_has 'v17 AC1.1 E16 prompt is still the cents change of total() in src/cart.js' 'total\(\).*src/cart\.js|src/cart\.js.*total\(\)'
e16_has 'v17 AC1.1 E16 prompt still asks for integer cents' 'cents[^.]{0,40}integer|integer[^.]{0,40}cents'
e16_has 'v17 AC1.1 E16 prompt says the prices are dollars' 'dollar'
e16_has 'v17 AC1.1 E16 prompt says the dollar prices are floats' 'dollars?[^.]{0,40}float'
e16_has 'v17 AC1.1 E16 prompt says to round to the nearest cent' 'round[^.]{0,40}nearest cent'
e16_has 'v17 AC1.1 E16 prompt says half up' 'half[ -]up'
e16_has 'v17 AC1.1 E16 prompt says nothing outside this repo calls total()' '(nothing|nobody|no other code|no one|none)[^.]{0,60}outside this repo|outside this repo[^.]{0,60}(nothing|nobody|no one|none|not)'
e16_has 'v17 AC1.1 E16 prompt says in-repo callers are updated' 'caller'
e16_pass() { section "$SCEN" "$E16" | tr '\n' ' ' | sed -n 's/.*\*\*Pass if:\*\*\(.*\)\*\*Fail if:\*\*.*/\1/p'; }   # the Pass if paragraph on one line
e16_pass_has() { if e16_pass | grep -qiE -- "$2"; then t_ok "$1"; else t_bad "$1" "pattern [$2] not in the E16 Pass if: [$(e16_pass)]"; fi; }
e16_pass_has 'v17 AC1.1 E16 Pass if still wants Full with the reason' 'Full.*reason|reason.*Full'
e16_pass_has 'v17 AC1.1 E16 Pass if still wants separate tester, implementer and reviewer' 'tester,[^.]{0,20}implementer[^.]{0,20}reviewer'
e16_pass_has 'v17 AC1.1 E16 Pass if still names the data shape' 'data shape'
check_sec 'v17 AC1.1 E16 Fail if is still there' "$SCEN" "$E16" '^\*\*Fail if:\*\*'
if [ "$(e16_para | tr -cd '"' | wc -c | tr -d ' ')" = 2 ]; then t_ok 'v17 AC1.1 E16 prompt is one double-quoted string (no inner double quotes cut it short)'; else t_bad 'v17 AC1.1 E16 prompt is one double-quoted string' "$(e16_para | tr -cd '"' | wc -c | tr -d ' ') double quotes in [$(e16_para)]"; fi

# --- v0.18.0 AC1.2: the non-interactive bullet also covers "the request says nobody will answer"
CLAR='^### Clarify before changing'
NIB="$(section "$BLOCK" "$CLAR" | grep -iE '^- Non-interactive' | tr '\n' ' ')"
case "$NIB" in *[![:space:]]*) t_ok 'v18 AC1.2 Clarify keeps a "- Non-interactive" bullet' ;; *) t_bad 'v18 AC1.2 Clarify keeps a "- Non-interactive" bullet' "no such bullet in the Clarify section" ;; esac
if printf '%s' "$NIB" | grep -qiE 'nobody will answer|no one will answer'; then t_ok 'v18 AC1.2 the Non-interactive bullet mentions that nobody will answer'; else t_bad 'v18 AC1.2 the Non-interactive bullet mentions that nobody will answer' "bullet: [$NIB]"; fi
if printf '%s' "$NIB" | grep -qiE 'request[^.]{0,60}(say|says|state|states|tell|tells)'; then t_ok 'v18 AC1.2 the bullet ties it to the request saying so'; else t_bad 'v18 AC1.2 the bullet ties it to the request saying so' "bullet: [$NIB]"; fi
if printf '%s' "$NIB" | grep -qiE 'CI|headless'; then t_ok 'v18 AC1.2 the bullet keeps the CI/headless case'; else t_bad 'v18 AC1.2 the bullet keeps the CI/headless case' "bullet: [$NIB]"; fi
if printf '%s' "$NIB" | grep -qiE 'do not block'; then t_ok 'v18 AC1.2 the bullet still says do not block'; else t_bad 'v18 AC1.2 the bullet still says do not block' "bullet: [$NIB]"; fi
if printf '%s' "$NIB" | grep -qiE 'log[^.]{0,60}default'; then t_ok 'v18 AC1.2 the bullet still says to log the defaults'; else t_bad 'v18 AC1.2 the bullet still says to log the defaults' "bullet: [$NIB]"; fi
# the phrase belongs to the Clarify section (not just anywhere in the block)
if section "$BLOCK" "$CLAR" | grep -qiE 'nobody will answer|no one will answer'; then t_ok 'v18 AC1.2 "nobody will answer" is in the Clarify section'; else t_bad 'v18 AC1.2 "nobody will answer" is in the Clarify section' "not in section $CLAR"; fi

# --- v0.18.0 AC2.2: Scope discipline says to write only inside the project/workdir the agent was asked to work in
SCOPE_J="$(jsec "$BLOCK" "$SCOPE")"
if printf '%s' "$SCOPE_J" | grep -qE '([Ww]rite|[Cc]reate)( files)? (only (inside|in|within)|nothing outside)[^.]{0,80}(project|workdir|working directory)[^.]{0,80}(asked|told|work in)'; then t_ok 'v18 AC2.2 Scope discipline: write only inside the project/workdir you were asked to work in'; else t_bad 'v18 AC2.2 Scope discipline: write only inside the project/workdir you were asked to work in' "section: [$SCOPE_J]"; fi
# the existing scope rules stay in the same section (the new clause adds, it does not replace)
if printf '%s' "$SCOPE_J" | grep -qiE 'no drive-by refactors'; then t_ok 'v18 AC2.2 Scope discipline keeps: no drive-by refactors'; else t_bad 'v18 AC2.2 Scope discipline keeps: no drive-by refactors' "section: [$SCOPE_J]"; fi
if printf '%s' "$SCOPE_J" | grep -qiE 'never weaken, skip or delete a test'; then t_ok 'v18 AC2.2 Scope discipline keeps: never weaken a test'; else t_bad 'v18 AC2.2 Scope discipline keeps: never weaken a test' "section: [$SCOPE_J]"; fi
# the clause is in Scope discipline, not only in another section
if printf '%s' "$(section "$BLOCK" "$CLAR" | tr '\n' ' ')" | grep -qE '[Ww]rite only (inside|in|within)'; then t_bad 'v18 AC2.2 the write-only-inside clause is not parked in the Clarify section' 'found in Clarify'; else t_ok 'v18 AC2.2 the write-only-inside clause is not parked in the Clarify section'; fi

# --- v0.19.0 AC1.1: capturing feedback is local and needs no question; only submit asks the user
FB19="$PB_ROOT/skills/playbook-feedback/SKILL.md"
# flat FILE -> the whole file on one line (a sentence may wrap), runs of blanks squeezed
flat() { tr '\n' ' ' < "$1" 2>/dev/null | tr -s ' '; }
# flat_has NAME FILE PATTERN: PATTERN (case-insensitive ERE) is in the flattened FILE; PATTERN gaps use [^.] so a clause stays in one sentence
flat_has() { if flat "$2" | grep -qiE -- "$3"; then t_ok "$1"; else t_bad "$1" "pattern [$3] not in the flattened $2"; fi; }
flat_has 'v19 AC1.1 playbook-feedback says that capture is local (same sentence)' "$FB19" 'capture[^.]{0,120}(local|on disk)|(local|on disk)[^.]{0,80}capture'
flat_has 'v19 AC1.1 playbook-feedback says capture needs no question' "$FB19" 'capture[^.]{0,160}(no question|no need to ask|without asking|never ask|do not ask|needs no (question|permission))|(no question|no need to ask|without asking)[^.]{0,120}capture'
flat_has 'v19 AC1.1 playbook-feedback says to capture right away' "$FB19" 'capture[^.]{0,200}(right away|immediately|at once)|(right away|immediately|at once)[^.]{0,80}capture'
flat_has 'v19 AC1.1 playbook-feedback says only submit (sending) asks the user' "$FB19" 'only[^.]{0,80}(submit|sending|send)[^.]{0,80}ask|only[^.]{0,40}ask[^.]{0,80}(submit|sending|send)'
flat_has 'v19 AC1.1 playbook-feedback still asks at most once at the end (submit stays gated)' "$FB19" 'ask at most once'
flat_has 'v19 AC1.1 playbook-feedback still has mark-asked' "$FB19" 'mark-asked'

# --- v0.19.0 AC1.2: the Phase 4 and the Lite feedback lines say to capture without asking
sec_flat_has() { # NAME FILE HEADING_REGEX PATTERN
  if section "$2" "$3" | tr '\n' ' ' | tr -s ' ' | grep -qiE -- "$4"; then t_ok "$1"; else t_bad "$1" "pattern [$4] not in section [$3] of $2"; fi
}
NOASK='(no need to ask|without asking|no question|do not ask|don.t ask|never ask|needs no (question|permission))'
sec_flat_has 'v19 AC1.2 Phase 4 feedback line: capture without asking' "$SKILL" '^### Phase 4' "playbook-feedback[^.]{0,250}$NOASK|capture[^.]{0,250}$NOASK"
sec_flat_has 'v19 AC1.2 Lite feedback line: capture without asking' "$SKILL" '^### Lite workflow' "capture[^.]{0,250}$NOASK"
sec_flat_has 'v19 AC1.2 Phase 4 still names playbook-feedback' "$SKILL" '^### Phase 4' 'playbook-feedback'
sec_flat_has 'v19 AC1.2 Lite still names the Playbook feedback line' "$SKILL" '^### Lite workflow' 'Playbook feedback'

# --- v0.19.0 AC3.1: every role file and the role prompt template tell sub-agents to write only inside the repository
for f in "$TESTER" "$IMPL" "$REVIEWER" "$RPROMPT"; do
  b="$(basename "$(dirname "$f")")/$(basename "$f")"
  flat_has "v19 AC3.1 $b: write only inside the repository you were given" "$f" '(write|create)[^.]{0,50}only (inside|in|within)[^.]{0,80}repositor|only (write|create)[^.]{0,60}(inside|in|within)[^.]{0,80}repositor|(write|create)[^.]{0,30}nothing outside[^.]{0,80}repositor'
  flat_has "v19 AC3.1 $b: never next to the repository" "$f" '(never|not)[^.]{0,60}(next to|beside|alongside)[^.]{0,40}(the )?(repo|repository)|(next to|beside|alongside) the repo[^.]{0,40}(never|not)'
  flat_has "v19 AC3.1 $b: scratch files go under .agents/handoff/" "$f" 'scratch[^.]{0,100}\.agents/handoff'
  flat_has "v19 AC3.1 $b: or the system temp dir" "$f" 'temp(orary)? (dir|folder)|\$TMPDIR|/tmp'
done

# --- v0.20.0 AC4.1: the Lite final report always has a "Playbook feedback:" line (the captured id, or "none")
sec_flat_has 'v20 AC4.1 Lite step 5: the final report always has a Playbook feedback line' "$SKILL" '^### Lite workflow' 'always[^.]{0,200}Playbook feedback|Playbook feedback[^.]{0,200}always'
sec_flat_has 'v20 AC4.1 Lite step 5: the line says none when nothing was captured' "$SKILL" '^### Lite workflow' 'Playbook feedback[^.]{0,200}[^[:alnum:]]none[^[:alnum:]]|[^[:alnum:]]none[^[:alnum:]][^.]{0,200}Playbook feedback'


# --- v0.22.0 AC2: understanding before code (templates/spec.md, playbook-tdd Lite step 1 and Phase 1)
SPEC_T="$TDD/templates/spec.md"
SPEC_REV="$TDD/roles/spec-reviewer.md"
l_und="$(line_of "$SPEC_T" '^## Understanding')"
l_ac="$(line_of "$SPEC_T" '^## Acceptance criteria')"
l_imp="$(line_of "$SPEC_T" '^## Impact')"
if [ -n "$l_und" ] && [ -n "$l_ac" ] && [ "$l_und" -lt "$l_ac" ]; then t_ok 'v22 AC2.1 spec template: ## Understanding comes before ## Acceptance criteria'; else t_bad 'v22 AC2.1 spec template: ## Understanding comes before ## Acceptance criteria' "Understanding line [$l_und], Acceptance criteria line [$l_ac]"; fi
sec_flat_has 'v22 AC2.1 Understanding: the request restated in your own words' "$SPEC_T" '^## Understanding' 'restat|own words|rephras'
sec_flat_has 'v22 AC2.1 Understanding: a scan log' "$SPEC_T" '^## Understanding' 'scan log|search log'
sec_flat_has 'v22 AC2.1 Understanding: the scan log has each command' "$SPEC_T" '^## Understanding' 'command'
sec_flat_has 'v22 AC2.1 Understanding: the scan log has the hit counts' "$SPEC_T" '^## Understanding' 'hit count|hits|number of (hits|matches)|match(es)? count'
sec_flat_has 'v22 AC2.1 Understanding: files read are listed' "$SPEC_T" '^## Understanding' 'files? read|read files|read:'
sec_flat_has 'v22 AC2.1 Understanding: other readings of the request and why this one' "$SPEC_T" '^## Understanding' 'other reading|alternative reading|other interpretation|another reading'
sec_flat_has 'v22 AC2.1 Understanding: in scope' "$SPEC_T" '^## Understanding' 'in scope|in-scope'
sec_flat_has 'v22 AC2.1 Understanding: out of scope' "$SPEC_T" '^## Understanding' 'out of scope|out-of-scope'
exact_heading 'v22 AC2.2 spec template has the exact heading ## Impact' "$SPEC_T" '## Impact'
sec_flat_has 'v22 AC2.2 Impact: who calls or uses what changes' "$SPEC_T" '^## Impact' 'calls?|callers?|uses|users of|call sites?'
sec_flat_has 'v22 AC2.2 Impact: the search command' "$SPEC_T" '^## Impact' 'search|grep|command'
sec_flat_has 'v22 AC2.2 Impact: hits with file:line' "$SPEC_T" '^## Impact' 'file:line|hits?'
if [ -n "$l_imp" ] && [ -n "$l_ac" ] && [ "$l_imp" -lt "$l_ac" ]; then t_ok 'v22 AC2.2 spec template: ## Impact also comes before the acceptance criteria'; else t_bad 'v22 AC2.2 spec template: ## Impact also comes before the acceptance criteria' "Impact line [$l_imp], Acceptance criteria line [$l_ac]"; fi

# lite_step N -> the text of step N of the Lite workflow (from "N. " up to the next numbered step)
lite_step() { section "$SKILL" '^### Lite workflow' | awk -v n="$1" 'BEGIN { p = "^" n "\\. " } $0 ~ p { f = 1; print; next } f && /^[0-9]+\. / { exit } f { print }'; }
lite_has() { # NAME STEP PATTERN
  if lite_step "$2" | tr '\n' ' ' | tr -s ' ' | grep -qiE -- "$3"; then t_ok "$1"; else t_bad "$1" "pattern [$3] not in Lite step $2"; fi
}
ASK_FIRST='(ambiguous|ambiguity).{0,200}hard[- ]to[- ]reverse.{0,200}before (any|writing|you write|touching|the first).{0,40}(code|test|line)|hard[- ]to[- ]reverse.{0,200}(ambiguous|ambiguity).{0,200}before (any|writing|you write|touching|the first).{0,40}(code|test|line)'
lite_has 'v22 AC2.3 Lite step 1 requires the Understanding section' 1 'Understanding'
lite_has 'v22 AC2.3 Lite step 1 requires the Impact section' 1 'Impact'
lite_has 'v22 AC2.3 Lite step 1: a few lines each' 1 'few lines|short|brief'
lite_has 'v22 AC2.3 Lite step 1: an ambiguous, hard-to-reverse reading is asked before any code' 1 "$ASK_FIRST"
lite_has 'v22 AC2.3 Lite step 1: the question is one batched message' 1 'batch|one (question|message)'
sec_flat_has 'v22 AC2.3 Phase 1 requires the Understanding section' "$SKILL" '^### Phase 1' 'Understanding'
sec_flat_has 'v22 AC2.3 Phase 1 requires the Impact section' "$SKILL" '^### Phase 1' 'Impact'
sec_flat_has 'v22 AC2.3 Phase 1: an ambiguous, hard-to-reverse reading is asked before any code' "$SKILL" '^### Phase 1' "$ASK_FIRST"
sec_flat_has 'v22 AC2.3 Phase 1: that question is one batched message' "$SKILL" '^### Phase 1' 'batch'

# --- v0.22.0 AC3: the spec reviewer role, run before the first tester
assert_file 'v22 AC3.1 skills/playbook-tdd/roles/spec-reviewer.md exists' "$SPEC_REV"
flat_has 'v22 AC3.1 spec-reviewer is read-only' "$SPEC_REV" 'read-only|read only'
flat_has 'v22 AC3.1 spec-reviewer changes nothing in the repo (besides its own report)' "$SPEC_REV" 'change nothing|changes? no (file|code)|do not (change|edit|modify)|never (change|edit|modify)'
flat_has 'v22 AC3.1 spec-reviewer takes the raw request verbatim' "$SPEC_REV" 'raw request.{0,120}verbatim|verbatim.{0,120}(raw )?request'
flat_has 'v22 AC3.1 spec-reviewer reads 01-spec.md' "$SPEC_REV" '01-spec\.md'
flat_has 'v22 AC3.1 spec-reviewer re-runs the impact and scan searches' "$SPEC_REV" 're-?run.{0,120}(search|scan|grep|impact)|(search|scan|grep|impact).{0,80}re-?run'
flat_has 'v22 AC3.1 spec-reviewer compares every request sentence with the ACs' "$SPEC_REV" '(every|each).{0,60}sentence.{0,160}(AC|acceptance)|sentence by sentence'
flat_has 'v22 AC3.1 spec-reviewer verdict OK' "$SPEC_REV" '(^|[^[:alnum:]])OK([^[:alnum:]]|$)'
flat_has 'v22 AC3.1 spec-reviewer verdict REVISE' "$SPEC_REV" '(^|[^[:alnum:]])REVISE([^[:alnum:]]|$)'
flat_has 'v22 AC3.1 spec-reviewer lists findings' "$SPEC_REV" 'findings?'
flat_has 'v22 AC3.1 spec-reviewer writes .agents/handoff/01b-spec-review.md' "$SPEC_REV" '\.agents/handoff/01b-spec-review\.md'
flat_has 'v22 AC3.1 spec-reviewer gate: role-gate.sh check reviewer' "$SPEC_REV" 'role-gate\.sh check reviewer'
flat_has 'v22 AC3.1 spec-reviewer writes only inside the repository (scratch under .agents/handoff)' "$SPEC_REV" '\.agents/handoff'
sec_flat_has 'v22 AC3.2 Phase 1 runs the spec reviewer' "$SKILL" '^### Phase 1' 'spec[- ]review'
sec_flat_has 'v22 AC3.2 Phase 1 runs the spec reviewer BEFORE the first tester' "$SKILL" '^### Phase 1' 'spec[- ]review.{0,200}before.{0,60}(first )?tester|before.{0,60}(first )?tester.{0,120}spec[- ]review|tester.{0,60}(only )?after.{0,80}spec[- ]review'
sec_flat_has 'v22 AC3.2 Phase 1: a REVISE verdict goes back to the spec' "$SKILL" '^### Phase 1' 'REVISE.{0,160}(spec|back)'
sec_flat_has 'v22 AC3.2 Phase 1 names the spec-reviewer role file or its report' "$SKILL" '^### Phase 1' 'roles/spec-reviewer|01b-spec-review|spec-reviewer'

# --- v0.22.0 AC4: request coverage before "done"
exact_heading 'v22 AC4.1 final-report template has the exact heading ## Request coverage' "$FINAL" '## Request coverage'
sec_flat_has 'v22 AC4.1 Request coverage: each sentence of the raw request verbatim' "$FINAL" '^## Request coverage' '(each|every).{0,60}sentence.{0,80}(raw )?request.{0,80}verbatim|verbatim.{0,120}sentence|sentence.{0,80}verbatim'
sec_flat_has 'v22 AC4.1 Request coverage: done, with where (file:line or AC)' "$FINAL" '^## Request coverage' 'done.{0,80}(file:line|AC|where)'
sec_flat_has 'v22 AC4.1 Request coverage: read as ...' "$FINAL" '^## Request coverage' 'read as'
sec_flat_has 'v22 AC4.1 Request coverage: not done' "$FINAL" '^## Request coverage' 'not done'
sec_flat_has 'v22 AC4.1 Phase 4 requires the request coverage' "$SKILL" '^### Phase 4' 'request coverage'
lite_has 'v22 AC4.1 Lite step 5 requires the request coverage' 5 'request coverage'


# --- v0.22.0 review findings: content
if grep -qiE 'divide' "$SPEC_REV" 2>/dev/null; then t_bad 'RV10 spec-reviewer.md does not contain the E21 answer (divide)' "found: $(grep -niE 'divide' "$SPEC_REV" | head -n 2)"; else t_ok 'RV10 spec-reviewer.md does not contain the E21 answer (divide)'; fi
if grep -qiE 'report\.js' "$SPEC_REV" 2>/dev/null; then t_bad 'RV10 spec-reviewer.md does not contain the E21 answer (report.js)' "found: $(grep -niE 'report\.js' "$SPEC_REV" | head -n 2)"; else t_ok 'RV10 spec-reviewer.md does not contain the E21 answer (report.js)'; fi
assert_file 'RV10 spec-reviewer.md still exists (the leak checks above are not vacuous)' "$SPEC_REV"
flat_has 'RV10 spec-reviewer.md: the report is its only output' "$SPEC_REV" 'only output'
flat_has 'RV10 spec-reviewer.md: the orchestrator saves the report to 01b-spec-review.md' "$SPEC_REV" 'orchestrator.{0,160}(save|saves|saved|writes?|stor).{0,160}01b-spec-review|01b-spec-review.{0,160}(saved|written|stored) by the orchestrator'
sec_flat_has 'RV10 SKILL.md Phase 1: the orchestrator saves the spec reviewer report to .agents/handoff/01b-spec-review.md' "$SKILL" '^### Phase 1' 'orchestrator.{0,160}(save|saves|saved|writes?|stor).{0,160}01b-spec-review|(save|saves|saved|writes?|stor).{0,80}01b-spec-review.{0,120}orchestrator|01b-spec-review.{0,120}(saved|written|stored) by the orchestrator'
sec_flat_has 'RV10 SKILL.md Phase 1: it is the reviewer report that is saved (its only output)' "$SKILL" '^### Phase 1' 'report.{0,120}01b-spec-review|01b-spec-review.{0,120}report'
flat_has 'RV10 playbook-setup: leak_literals only in the project conf are not read in linked git worktrees' "$SETUP" 'worktree.{0,250}(project|leak_literals)|leak_literals.{0,250}worktree'
flat_has 'RV10 playbook-setup: the project conf is git-excluded' "$SETUP" 'worktree.{0,250}(exclude|ignored)|(exclude|ignored).{0,250}worktree'
flat_has 'RV10 playbook-setup: so private literals belong in the global conf' "$SETUP" 'worktree.{0,250}global|global.{0,250}worktree'


# --- v0.22.1 AC1: one real observation of the user-visible behaviour (Phase 4, Lite step 4, playbook-proof)
PROOF="$PB_ROOT/skills/playbook-proof/SKILL.md"
README="$PB_ROOT/README.md"
FB="$PB_ROOT/skills/playbook-feedback/SKILL.md"
REAL='real[- ](behaviou?r|observation|run)|observ[a-z]* (of )?the real'
UVIS='user[- ]visible'
NOTENOUGH='unit tests?[^.]{0,80}(not|never) enough|(not|never) enough[^.]{0,80}unit tests?|unit tests? alone'
NOTCHK_IMPOSSIBLE='(cannot|can.t|could not|not possible|unable)[^.]{0,120}Not checked|Not checked[^.]{0,120}(cannot|can.t|could not|not possible|unable)'
sec_flat_has 'v22.1 AC1.1 Phase 4: user-visible changes' "$SKILL" '^### Phase 4' "$UVIS"
sec_flat_has 'v22.1 AC1.1 Phase 4: one real observation of the behaviour' "$SKILL" '^### Phase 4' "$REAL"
sec_flat_has 'v22.1 AC1.1 Phase 4: in this session' "$SKILL" '^### Phase 4' 'in this session|this session'
sec_flat_has 'v22.1 AC1.1 Phase 4: screenshot or browser read for a UI' "$SKILL" '^### Phase 4' 'screenshot|browser'
sec_flat_has 'v22.1 AC1.1 Phase 4: curl for an API' "$SKILL" '^### Phase 4' 'curl'
sec_flat_has 'v22.1 AC1.1 Phase 4: the CLI command for a CLI' "$SKILL" '^### Phase 4' 'CLI'
sec_flat_has 'v22.1 AC1.1 Phase 4: unit tests alone are not enough' "$SKILL" '^### Phase 4' "$NOTENOUGH"
sec_flat_has 'v22.1 AC1.1 Phase 4: when it cannot be run it goes under Not checked' "$SKILL" '^### Phase 4' "$NOTCHK_IMPOSSIBLE"
lite_has 'v22.1 AC1.1 Lite step 4: user-visible changes' 4 "$UVIS"
lite_has 'v22.1 AC1.1 Lite step 4: one real observation of the behaviour' 4 "$REAL"
lite_has 'v22.1 AC1.1 Lite step 4: screenshot or browser read for a UI' 4 'screenshot|browser'
lite_has 'v22.1 AC1.1 Lite step 4: curl for an API' 4 'curl'
lite_has 'v22.1 AC1.1 Lite step 4: unit tests alone are not enough' 4 "$NOTENOUGH"
lite_has 'v22.1 AC1.1 Lite step 4: when it cannot be run it goes under Not checked' 4 "$NOTCHK_IMPOSSIBLE"
flat_has 'v22.1 AC1.1 playbook-proof: user-visible changes need a real observation' "$PROOF" "($UVIS)[^.]{0,250}($REAL)|($REAL)[^.]{0,250}($UVIS)"
flat_has 'v22.1 AC1.1 playbook-proof: unit tests alone are not enough for it' "$PROOF" "$NOTENOUGH"
flat_has 'v22.1 AC1.1 playbook-proof: what could not be observed goes under Not checked' "$PROOF" 'Not checked'

# --- v0.22.1 AC2: an honest final report (templates/final-report.md, Phase 4, Lite step 5)
exact_heading 'v22.1 AC2.1 final-report template has the exact heading ## Not checked' "$FINAL" '## Not checked'
sec_flat_has 'v22.1 AC2.1 Not checked: environments' "$FINAL" '^## Not checked' 'environment'
sec_flat_has 'v22.1 AC2.1 Not checked: data' "$FINAL" '^## Not checked' '(^|[^[:alnum:]])data([^[:alnum:]]|$)'
sec_flat_has 'v22.1 AC2.1 Not checked: files or paths not exercised' "$FINAL" '^## Not checked' 'files?|paths?'
sec_flat_has 'v22.1 AC2.1 Not checked: says these were not exercised' "$FINAL" '^## Not checked' 'not (exercised|run|tested|checked)|never (exercised|run)'
sec_flat_has 'v22.1 AC2.1 AC table has a Confidence column' "$FINAL" '^## AC to tests' '\|[^|]*Confidence[^|]*\|'
sec_flat_has 'v22.1 AC2.1 Confidence levels high, medium, low' "$FINAL" '^## AC to tests' 'high[^[:alnum:]]{1,12}medium[^[:alnum:]]{1,12}low'
sec_flat_has 'v22.1 AC2.1 Confidence comes with a why' "$FINAL" '^## AC to tests' 'why|because|reason'
exact_heading 'v22.1 AC2.1 final-report template has the exact heading ## Pre-mortem' "$FINAL" '## Pre-mortem'
sec_flat_has 'v22.1 AC2.1 Pre-mortem: three ways the result could still be wrong' "$FINAL" '^## Pre-mortem' 'three[^.]{0,80}(wrong|fail|break)|3[^.]{0,40}(ways|risks)'
sec_flat_has 'v22.1 AC2.1 Pre-mortem: each with the command run to check it' "$FINAL" '^## Pre-mortem' 'command'
sec_flat_has 'v22.1 AC2.1 Pre-mortem: and its outcome' "$FINAL" '^## Pre-mortem' 'outcome|result of'
sec_flat_has 'v22.1 AC2.2 Phase 4 requires Not checked' "$SKILL" '^### Phase 4' 'Not checked'
sec_flat_has 'v22.1 AC2.2 Phase 4 requires the Confidence column' "$SKILL" '^### Phase 4' 'confidence'
sec_flat_has 'v22.1 AC2.2 Phase 4 requires the Pre-mortem' "$SKILL" '^### Phase 4' 'pre-mortem'
lite_has 'v22.1 AC2.2 Lite step 5 requires Not checked' 5 'Not checked'
lite_has 'v22.1 AC2.2 Lite step 5 requires the Confidence column' 5 'confidence'
lite_has 'v22.1 AC2.2 Lite step 5 requires the Pre-mortem' 5 'pre-mortem'
lite_has 'v22.1 AC2.2 Lite step 5: the pre-mortem may be one line per risk' 5 'one line (per|for each|each)[^.]{0,40}risk|one-line'

# --- v0.22.1 AC3: first-slice checkpoint (Phase 2)
sec_flat_has 'v22.1 AC3.1 Phase 2: slices that repeat a pattern' "$SKILL" '^### Phase 2' 'repeat[^.]{0,120}pattern|pattern[^.]{0,120}repeat|same pattern'
sec_flat_has 'v22.1 AC3.1 Phase 2: examples are screens, endpoints or files' "$SKILL" '^### Phase 2' 'screens?|endpoints?'
sec_flat_has 'v22.1 AC3.1 Phase 2: shows the first finished slice' "$SKILL" '^### Phase 2' 'first (finished |completed |done )?slice|first (finished|completed) one'
sec_flat_has 'v22.1 AC3.1 Phase 2: waits for an OK before the rest' "$SKILL" '^### Phase 2' 'wait[^.]{0,120}(OK|approval|go-ahead|confirm)[^.]{0,160}(rest|remaining|other|next|before)|before the rest[^.]{0,160}(OK|approval|wait)'
sec_flat_has 'v22.1 AC3.1 Phase 2: this applies to an interactive run' "$SKILL" '^### Phase 2' 'interactive'
sec_flat_has 'v22.1 AC3.1 Phase 2: a non-interactive run logs the skipped checkpoint in decisions.md' "$SKILL" '^### Phase 2' 'non-interactive[^.]{0,200}(log|decisions\.md)[^.]{0,200}(decisions\.md|skip)|decisions\.md[^.]{0,160}(skip|checkpoint)'
sec_flat_has 'v22.1 AC3.1 Phase 2: a non-interactive run then continues' "$SKILL" '^### Phase 2' 'non-interactive[^.]{0,250}continu'

# --- v0.22.1 AC4: when the user says the result is wrong
exact_heading 'v22.1 AC4.1 playbook-tdd has the exact heading ## When the user says it is wrong' "$SKILL" '## When the user says it is wrong'
WRONG='^## When the user says it is wrong'
sec_flat_has 'v22.1 AC4.1 wrong: restate what was expected versus what was delivered' "$SKILL" "$WRONG" 'restate[^.]{0,160}expected[^.]{0,120}deliver|expected[^.]{0,80}(vs\.?|versus|against)[^.]{0,80}deliver'
sec_flat_has 'v22.1 AC4.1 wrong: cause misread request' "$SKILL" "$WRONG" 'misread'
sec_flat_has 'v22.1 AC4.1 wrong: cause missed place (scan)' "$SKILL" "$WRONG" 'missed[^.]{0,30}(place|scan)'
sec_flat_has 'v22.1 AC4.1 wrong: cause wrong assumption' "$SKILL" "$WRONG" 'wrong assumption'
sec_flat_has 'v22.1 AC4.1 wrong: cause not verified live' "$SKILL" "$WRONG" 'not verified live'
sec_flat_has 'v22.1 AC4.1 wrong: cause real bug' "$SKILL" "$WRONG" 'real bug'
sec_flat_has 'v22.1 AC4.1 wrong: classify the cause with evidence' "$SKILL" "$WRONG" 'classif[^.]{0,160}(cause|evidence)|cause[^.]{0,120}evidence'
sec_flat_has 'v22.1 AC4.1 wrong: fix it test-first' "$SKILL" "$WRONG" 'test[- ]first|failing test[^.]{0,80}(first|before)|(first|before)[^.]{0,80}failing test'
sec_flat_has 'v22.1 AC4.1 wrong: a playbook gap is captured with playbook-feedback' "$SKILL" "$WRONG" 'playbook gap[^.]{0,200}playbook-feedback|playbook-feedback[^.]{0,200}playbook gap|gap[^.]{0,120}playbook-feedback'
sec_flat_has 'v22.1 AC4.1 wrong: the capture proposes a regression eval' "$SKILL" "$WRONG" 'regression eval'
flat_has 'v22.1 AC4.1 playbook-feedback covers the case where the user says the result is wrong' "$FB" 'user (says|said|tells)[^.]{0,80}wrong|(says|said|tells)[^.]{0,60}(result|it) (is|was) wrong'
flat_has 'v22.1 AC4.1 playbook-feedback: that capture proposes a regression eval' "$FB" 'regression eval'

# --- v0.22.1 AC5.2: how to install shellcheck is in the README
flat_has 'v22.1 AC5.2 README says how to install shellcheck (apt install shellcheck)' "$README" 'apt(-get)? install[^.]{0,60}shellcheck|shellcheck[^.]{0,120}apt(-get)? install'


# --- v0.22.1 review findings: content
sec_flat_has 'v22.1 RV wrong: a project-specific cause goes to playbook-learn' "$SKILL" "$WRONG" 'playbook-learn'
sec_flat_has 'v22.1 RV wrong: playbook-learn is for a cause that is specific to the project' "$SKILL" "$WRONG" 'project[^.]{0,120}playbook-learn|playbook-learn[^.]{0,120}project'
sec_flat_has 'v22.1 RV wrong: a docs-only (Exempt) misread is named' "$SKILL" "$WRONG" 'docs-only|exempt'
sec_flat_has 'v22.1 RV wrong: docs-only misread: fix it and re-check against the request' "$SKILL" "$WRONG" 're-?check[^.]{0,120}request|request[^.]{0,120}re-?check'
sec_flat_has 'v22.1 RV wrong: docs-only misread: no test is needed' "$SKILL" "$WRONG" 'no (failing )?test[^.]{0,20}(needed|required)|without (a )?test|needs? no test'
sec_flat_has 'v22.1 RV Phase 4: the real-observation rule points to playbook-proof' "$SKILL" '^### Phase 4' 'real[- ](behaviou?r|observation).{0,250}playbook-proof|playbook-proof.{0,250}real[- ](behaviou?r|observation)'
SC_HEAD="$(awk '/^#+ /{h=$0} /apt(-get)? install[^.]*shellcheck/{print h; exit}' "$README")"
if printf '%s\n' "$SC_HEAD" | grep -qiE 'develop|contribut'; then t_ok 'v22.1 RV README: the shellcheck install note sits under a development or contributing heading'; else t_bad 'v22.1 RV README: the shellcheck install note sits under a development or contributing heading' "nearest heading above it: [$SC_HEAD]"; fi
if printf '%s\n' "$SC_HEAD" | grep -qiE 'quality, measured'; then t_bad 'v22.1 RV README: the shellcheck note is not inside "Quality, measured"' "heading: [$SC_HEAD]"; else t_ok 'v22.1 RV README: the shellcheck note is not inside "Quality, measured"'; fi


# --- v0.22.2 AC1: process rules (named-line assertions: each check names the line or phrase it needs)
exact_heading 'v22.2 AC1.1 spec template has ## Regression corpus' "$SPEC_T" '## Regression corpus'
sec_flat_has 'v22.2 AC1.1 template: the corpus lists old inputs' "$SPEC_T" '^## Regression corpus' 'old inputs?|existing inputs?|inputs?'
sec_flat_has 'v22.2 AC1.1 template: the corpus lists earlier bugs' "$SPEC_T" '^## Regression corpus' 'earlier bugs?|past bugs?|previous bugs?|bugs?'
sec_flat_has 'v22.2 AC1.1 template: each entry has an expected result' "$SPEC_T" '^## Regression corpus' 'expected'
sec_flat_has 'v22.2 AC1.1 Phase 1 names the regression corpus' "$SKILL" '^### Phase 1' 'regression corpus'
sec_flat_has 'v22.2 AC1.1 Phase 1: it applies when a change replaces or rewrites existing logic' "$SKILL" '^### Phase 1' 'replac.{0,200}corpus|rewrit.{0,200}corpus|corpus.{0,200}(replac|rewrit)'
sec_flat_has 'v22.2 AC1.1 Phase 1: the corpus holds old inputs and earlier bugs with the expected result' "$SKILL" '^### Phase 1' 'corpus.{0,250}(old inputs?|earlier bugs?)|(old inputs?|earlier bugs?).{0,250}corpus'
sec_flat_has 'v22.2 AC1.1 Phase 1: the first RED covers the whole corpus' "$SKILL" '^### Phase 1' 'corpus.{0,250}first RED|first RED.{0,250}corpus'
flat_has 'v22.2 AC1.2 implementer: never hide a construct from a gate' "$IMPL" 'never hide|not hide|do not hide|don.t hide|hid(e|ing)[^.]{0,80}(from|inside)[^.]{0,40}(gate|rule|check)'
flat_has 'v22.2 AC1.2 implementer: a flagged construct is reported (Dispute or note)' "$IMPL" '(gate|rule)[^.]{0,200}flag[^.]{0,250}report|report[^.]{0,200}(dispute|note)|(dispute|note)[^.]{0,200}report'
flat_has 'v22.2 AC1.2 implementer: the hiding tricks are named (variable, disabling, renaming)' "$IMPL" 'variable|disabl|renam'
flat_has 'v22.2 AC1.3 tester: prefer named-line assertions' "$TESTER" 'named[- ]line'
flat_has 'v22.2 AC1.3 tester: ... over exact counts' "$TESTER" 'exact (count|number)s?|counts? of (lines|keys|list)|instead of (an )?exact'
flat_has 'v22.2 AC1.3 tester: a new check must not break unrelated tests' "$TESTER" 'unrelated|new check'

# --- v0.22.2 AC2: CI concurrency and timeouts (static checks of .github/workflows/test.yml)
# wf_top KEY -> the lines of the workflow-level KEY: block (up to the next top-level key)
wf_top() { awk -v k="$1" '$0 ~ "^" k ":" { f = 1; print; next } f && /^[^ #]/ { exit } f { print }' "$WF" 2>/dev/null; }
CONC="$(wf_top concurrency)"
if [ -n "$CONC" ]; then t_ok 'v22.2 AC2.1 the workflow has a top-level concurrency: block'; else t_bad 'v22.2 AC2.1 the workflow has a top-level concurrency: block' 'no ^concurrency: key'; fi
GROUP_LINE="$(printf '%s\n' "$CONC" | grep -m1 '^[[:space:]]*group:')"
CANCEL_LINE="$(printf '%s\n' "$CONC" | grep -m1 '^[[:space:]]*cancel-in-progress:')"
assert_contains 'v22.2 AC2.1 the group expression contains github.ref' "$GROUP_LINE" 'github.ref'
assert_contains 'v22.2 AC2.1 the group expression contains github.sha' "$GROUP_LINE" 'github.sha'
assert_contains 'v22.2 AC2.1 the group expression has the pull_request condition' "$GROUP_LINE" 'pull_request'
assert_contains 'v22.2 AC2.1 the group expression is an expression (${{ ... }})' "$GROUP_LINE" '${{'
GROUP_PR="${GROUP_LINE%%||*}"
GROUP_REST="${GROUP_LINE#*||}"
case "$GROUP_LINE" in *'||'*) t_ok 'v22.2 AC2.1 the group is "PR ? ref : other" (an || between the two branches)' ;; *) t_bad 'v22.2 AC2.1 the group is "PR ? ref : other" (an || between the two branches)' "group line: [$GROUP_LINE]" ;; esac
assert_contains 'v22.2 AC2.1 the PR branch tests pull_request' "$GROUP_PR" 'pull_request'
assert_contains 'v22.2 AC2.1 the PR branch groups by github.ref (runs of one PR cancel each other)' "$GROUP_PR" 'github.ref'
assert_not_contains 'v22.2 AC2.1 the PR branch does not use github.sha' "$GROUP_PR" 'github.sha'
assert_contains 'v22.2 AC2.1 the non-PR branch contains github.ref' "$GROUP_REST" 'github.ref'
assert_contains 'v22.2 AC2.1 the non-PR branch contains github.sha (main and tag runs are never cancelled)' "$GROUP_REST" 'github.sha'
assert_contains 'v22.2 AC2.1 cancel-in-progress is an expression' "$CANCEL_LINE" '${{'
assert_contains 'v22.2 AC2.1 cancel-in-progress tests github.event_name' "$CANCEL_LINE" 'github.event_name'
assert_contains "v22.2 AC2.1 cancel-in-progress is true only when the event is pull_request (== 'pull_request')" "$CANCEL_LINE" "== 'pull_request'"
assert_not_contains 'v22.2 AC2.1 cancel-in-progress is not negated (no !=)' "$CANCEL_LINE" '!='
if printf '%s\n' "$CANCEL_LINE" | grep -Eq 'cancel-in-progress:[[:space:]]*(true|false)[[:space:]]*$'; then t_bad 'v22.2 AC2.1 cancel-in-progress is not a constant' "line: [$CANCEL_LINE]"; else t_ok 'v22.2 AC2.1 cancel-in-progress is not a constant'; fi
# wf_timeout ID -> the job's timeout-minutes value ("" when none)
wf_timeout() { wf_block "$1" | grep -m1 '^    timeout-minutes:' | sed 's/^    timeout-minutes:[[:space:]]*//; s/[[:space:]]*#.*$//; s/[[:space:]]*$//'; }
for id in $(wf_jobs); do
  tv="$(wf_timeout "$id")"
  case "$tv" in '' | *[!0123456789]*) t_bad "v22.2 AC2.2 job $id has a numeric timeout-minutes" "value: [$tv]" ;; *) t_ok "v22.2 AC2.2 job $id has a numeric timeout-minutes ($tv)" ;; esac
done
assert_eq 'v22.2 AC2.2 the test job (ubuntu/macos) has timeout-minutes 20' "20" "$(wf_timeout "${MAIN:-__none__}")"
assert_eq 'v22.2 AC2.2 windows-shard has timeout-minutes 20' "20" "$(wf_timeout "${SHARD:-__none__}")"
assert_eq 'v22.2 AC2.2 the aggregator (test (windows-latest)) has timeout-minutes 5' "5" "$(wf_timeout "${AGG:-__none__}")"
assert_eq 'v22.2 AC2.2 main-ci has timeout-minutes 30' "30" "$(wf_timeout main-ci)"
assert_eq 'v22.2 AC2.2 release has timeout-minutes 10' "10" "$(wf_timeout release)"

# AC8.3: the Windows shards turn the run-all re-run off (the full failure logs are already printed; re-runs could near the timeout)
assert_contains "v22.2 AC8.3 the windows-shard job sets PB_RERUN: '0'" "$(wf_block "${SHARD:-__none__}")" "PB_RERUN: '0'"
assert_not_contains "v22.2 AC8.3 the ubuntu/macos test job keeps the default re-run (no PB_RERUN)" "$(wf_block "${MAIN:-__none__}")" "PB_RERUN"

# --- v0.22.2 AC6: resume state file
STATE_T="$TDD/templates/state.md"
assert_file 'v22.2 AC6.1 templates/state.md exists' "$STATE_T"
flat_has 'v22.2 AC6.1 state template: the phase' "$STATE_T" 'phase'
flat_has 'v22.2 AC6.1 state template: the slice' "$STATE_T" 'slice'
flat_has 'v22.2 AC6.1 state template: the last sha per role (tester)' "$STATE_T" 'tester'
flat_has 'v22.2 AC6.1 state template: the last sha per role (implementer)' "$STATE_T" 'implementer'
flat_has 'v22.2 AC6.1 state template: the last sha per role (reviewer)' "$STATE_T" 'reviewer'
flat_has 'v22.2 AC6.1 state template: sha' "$STATE_T" 'sha'
flat_has 'v22.2 AC6.1 state template: the next step' "$STATE_T" 'next step'
flat_has 'v22.2 AC6.1 state template: open questions' "$STATE_T" 'open questions?'
flat_has 'v22.2 AC6.1 SKILL.md: the orchestrator updates .agents/handoff/state.md' "$SKILL" 'orchestrator.{0,200}\.agents/handoff/state\.md|\.agents/handoff/state\.md.{0,200}orchestrator'
flat_has 'v22.2 AC6.1 SKILL.md: state.md is updated after each phase' "$SKILL" 'state\.md.{0,200}after each phase|after each phase.{0,200}state\.md'
flat_has 'v22.2 AC6.1 SKILL.md: state.md is read first when resuming' "$SKILL" 'resum.{0,200}state\.md|state\.md.{0,200}resum'
flat_has 'v22.2 AC6.1 SKILL.md: ... read first' "$SKILL" 'read[^.]{0,40}state\.md[^.]{0,40}first|first[^.]{0,80}(read|reads)[^.]{0,60}state\.md|state\.md[^.]{0,80}first'

# --- v0.22.2 AC7: README
if grep -i 'concurrency' "$README" | grep -qi 'timeout'; then t_ok 'v22.2 AC7.1 README: one line mentions CI concurrency and timeouts'; else t_bad 'v22.2 AC7.1 README: one line mentions CI concurrency and timeouts' 'no README line has both words'; fi
sec_flat_has 'v22.2 AC7.1 README Development section mentions tools/bsd-check.sh' "$README" '^## Development' 'tools/bsd-check\.sh'


# --- v0.22.3 AC2: context packs
exact_heading 'v22.3 AC2.1 role-prompt.md has the heading "## 2b. Context pack"' "$RPROMPT" '## 2b. Context pack'
L_SPEC="$(line_of "$RPROMPT" '## 2. Spec')"; L_PACK="$(line_of "$RPROMPT" '## 2b. Context pack')"; L_SLICE="$(line_of "$RPROMPT" '## 3. This slice')"
if [ -n "$L_SPEC" ] && [ -n "$L_PACK" ] && [ -n "$L_SLICE" ] && [ "$L_SPEC" -lt "$L_PACK" ] && [ "$L_PACK" -lt "$L_SLICE" ]; then t_ok 'v22.3 AC2.1 the Context pack section sits between Spec and This slice'; else t_bad 'v22.3 AC2.1 the Context pack section sits between Spec and This slice' "spec line [$L_SPEC] pack line [$L_PACK] slice line [$L_SLICE]"; fi
PK='^## 2b\. Context pack'
sec_flat_has 'v22.3 AC2.1 pack: files with line ranges (path:line-line)' "$RPROMPT" "$PK" 'path:line-line|line ranges?'
sec_flat_has 'v22.3 AC2.1 pack: the files to read' "$RPROMPT" "$PK" 'files?|paths?'
sec_flat_has 'v22.3 AC2.1 pack: the functions or sections involved' "$RPROMPT" "$PK" 'functions?[^.]{0,40}sections?|sections?[^.]{0,40}functions?'
sec_flat_has 'v22.3 AC2.1 pack: short excerpts' "$RPROMPT" "$PK" 'excerpts?'
sec_flat_has 'v22.3 AC2.1 pack: the commands to run' "$RPROMPT" "$PK" 'commands?[^.]{0,30}run|run[^.]{0,30}commands?'
sec_flat_has 'v22.3 AC2.1 pack: the role reads the pack first' "$RPROMPT" "$PK" 'read[^.]{0,40}pack first|pack first|first[^.]{0,40}read[^.]{0,40}pack'
sec_flat_has 'v22.3 AC2.1 pack: other files only when the pack is not enough' "$RPROMPT" "$PK" 'not enough|insufficient|does not (cover|answer|contain)'
flat_has 'v22.3 AC2.2 SKILL.md: the orchestrator builds the context pack' "$SKILL" 'orchestrator[^.]{0,160}(builds?|writes?|makes?|prepares?|assembles?)[^.]{0,80}context pack|context pack[^.]{0,200}(built|written|made|prepared|assembled) by the orchestrator'
flat_has 'v22.3 AC2.2 SKILL.md: once per slice' "$SKILL" 'context pack[^.]{0,250}once per slice|once per slice[^.]{0,250}context pack'
flat_has 'v22.3 AC2.2 SKILL.md: from the spec Impact section and the scan log' "$SKILL" 'context pack[^.]{0,250}impact[^.]{0,120}scan log|impact[^.]{0,120}scan log[^.]{0,250}context pack'

# --- v0.22.3 AC6.2: the reuse job of .github/workflows/test.yml (static checks)
echo "v22.3 AC6.2 workflow: reuse job"
if wf_jobs | grep -qxF reuse; then t_ok 'v22.3 AC6.2 a job reuse exists'; else t_bad 'v22.3 AC6.2 a job reuse exists' "jobs: $(wf_jobs | tr '\n' ' ')"; fi
RB="$(wf_block reuse)"
RUIF="$(wf_if reuse)"
if printf '%s\n' "$RB" | grep -c '^    if:' | grep -qx 1; then t_ok 'v22.3 AC6.2 reuse has exactly one one-line if:'; else t_bad 'v22.3 AC6.2 reuse has exactly one one-line if:' "block: $RB"; fi
if printf '%s\n' "$RUIF" | grep -Eq "github\.event_name[[:space:]]*==[[:space:]]*'push'"; then t_ok "v22.3 AC6.2 the reuse if: tests the push event"; else t_bad "v22.3 AC6.2 the reuse if: tests the push event" "if line: [$RUIF]"; fi
if printf '%s\n' "$RUIF" | grep -Eq "github\.ref[[:space:]]*==[[:space:]]*'refs/heads/main'"; then t_ok "v22.3 AC6.2 the reuse if: tests the main ref"; else t_bad "v22.3 AC6.2 the reuse if: tests the main ref" "if line: [$RUIF]"; fi
if [ -n "$RUIF" ] && not_tag "$RUIF"; then t_ok 'v22.3 AC6.2 the reuse if: excludes tags'; else t_bad 'v22.3 AC6.2 the reuse if: excludes tags' "if line: [$RUIF]"; fi
assert_eq 'v22.3 AC6.2 reuse has timeout-minutes 5' "5" "$(wf_timeout reuse)"
if printf '%s\n' "$RB" | grep -Eq '^    permissions:'; then t_ok 'v22.3 AC6.2 reuse has its own permissions: block'; else t_bad 'v22.3 AC6.2 reuse has its own permissions: block' "block: $RB"; fi
if printf '%s\n' "$RB" | grep -Eq '^      actions:[[:space:]]*read[[:space:]]*$'; then t_ok 'v22.3 AC6.2 reuse has actions: read'; else t_bad 'v22.3 AC6.2 reuse has actions: read' "block: $RB"; fi
if printf '%s\n' "$RB" | grep -Eq '^      contents:[[:space:]]*read[[:space:]]*$'; then t_ok 'v22.3 AC6.2 reuse has contents: read (decision D3)'; else t_bad 'v22.3 AC6.2 reuse has contents: read (decision D3)' "block: $RB"; fi
if printf '%s' "$RB" | grep -Eq '^      [a-z-]+:[[:space:]]*write'; then t_bad 'v22.3 AC6.2 reuse has no write permission' "block: $RB"; else t_ok 'v22.3 AC6.2 reuse has no write permission'; fi
if printf '%s\n' "$RB" | grep -Eq '^    outputs:'; then t_ok 'v22.3 AC6.2 reuse has outputs:'; else t_bad 'v22.3 AC6.2 reuse has outputs:' "block: $RB"; fi
if printf '%s\n' "$RB" | grep -Eq '^      run:[[:space:]]*\$\{\{'; then t_ok 'v22.3 AC6.2 reuse outputs run'; else t_bad 'v22.3 AC6.2 reuse outputs run' "block: $RB"; fi
assert_not_contains 'v22.3 AC6.2 the reuse block never names macos-latest' "$RB" 'macos-latest'
assert_not_contains 'v22.3 AC6.2 the reuse block never names PB_SHARD' "$RB" 'PB_SHARD'
assert_not_contains 'v22.3 AC6.2 the reuse block never names windows-latest' "$RB" 'windows-latest'
assert_contains 'v22.3 AC6.2 reuse runs tools/ci-tree-tested.sh' "$RB" 'tools/ci-tree-tested.sh'
assert_contains 'v22.3 AC6.2 reuse passes GH_TOKEN to gh' "$RB" 'GH_TOKEN'
assert_not_contains 'v22.3 AC6.2 reuse does not run the suites' "$RB" 'tests/run-all.sh'
assert_eq 'v22.3 AC6.2 MAIN detection still finds the test job (not reuse)' "test" "$MAIN"
assert_eq 'v22.3 AC6.2 SHARD detection still finds windows-shard (not reuse)' "windows-shard" "$SHARD"

echo "v22.3 AC6.2 workflow: test and windows-shard wait for reuse and run unless the tree was tested"
NOREUSE_IF="if: \${{ !cancelled() && !startsWith(github.ref, 'refs/tags/') && !(needs.reuse.result == 'success' && needs.reuse.outputs.run != '') }}"
for id in test windows-shard; do
  assert_contains "v22.3 AC6.2 job $id has needs: reuse" "$(wf_needs "$id")" "reuse"
  assert_eq "v22.3 AC6.2 job $id has the exact one-line if: of the spec" "    $NOREUSE_IF" "$(wf_if "$id")"
done

echo "v22.3 AC6.2 workflow: the aggregator"
AGGNEEDS="$(wf_needs "$AGG")"
assert_contains "v22.3 AC6.2 the aggregator ($AGG) needs windows-shard" "$AGGNEEDS" "windows-shard"
assert_contains "v22.3 AC6.2 the aggregator ($AGG) needs reuse (the needs context holds direct dependencies only)" "$AGGNEEDS" "reuse"
case "$AGGNEEDS" in *"[windows-shard, reuse]"*) t_ok 'v22.3 AC6.2 the aggregator has needs: [windows-shard, reuse]' ;; *) t_bad 'v22.3 AC6.2 the aggregator has needs: [windows-shard, reuse]' "needs text: [$AGGNEEDS]" ;; esac
for tok in 'needs.windows-shard.result' 'needs.reuse.result' 'needs.reuse.outputs.run'; do
  assert_contains "v22.3 AC6.2 the aggregator reads $tok" "$AB" "$tok"
done
assert_contains "v22.3 AC6.2 the aggregator knows the skipped state of the shards" "$AB" 'skipped'
assert_contains 'v22.3 AC6.2 the aggregator can still fail' "$AB" 'exit 1'
assert_contains 'v22.3 AC6.2 the aggregator still has always()' "$(wf_if "$AGG")" 'always()'
assert_eq 'v22.3 AC6.2 the aggregator still has timeout-minutes 5' "5" "$(wf_timeout "$AGG")"
# the skip is allowed only together with a successful reuse and a non-empty run output: the pass logic names all three
PASSLOGIC="$(printf '%s\n' "$AB" | grep -E 'success|skipped' | tr '\n' ' ')"
case "$PASSLOGIC" in *needs.windows-shard.result*success*) t_ok 'v22.3 AC6.2 the aggregator passes on a successful shard result' ;; *) t_bad 'v22.3 AC6.2 the aggregator passes on a successful shard result' "logic: $PASSLOGIC" ;; esac
case "$PASSLOGIC" in *skipped*needs.reuse.result*success*|*needs.reuse.result*success*skipped*|*skipped*success*) t_ok 'v22.3 AC6.2 the aggregator accepts skipped shards only next to a successful reuse' ;; *) t_bad 'v22.3 AC6.2 the aggregator accepts skipped shards only next to a successful reuse' "logic: $PASSLOGIC" ;; esac
if printf '%s\n' "$AB" | grep -E 'needs\.reuse\.outputs\.run' | grep -Eq -- '-n|-z|!=|=='; then t_ok 'v22.3 AC6.2 the aggregator tests the reuse output for emptiness'; else t_bad 'v22.3 AC6.2 the aggregator tests the reuse output for emptiness' "block: $AB"; fi

echo "v22.3 AC6.2 workflow: release and main-ci are unchanged"
assert_contains 'v22.3 AC6.2 release keeps needs: [test, windows, main-ci]' "$(wf_needs release)" "[test, windows, main-ci]"
assert_eq 'v22.3 AC6.2 the release if: is unchanged' "    if: \${{ always() && startsWith(github.ref, 'refs/tags/v') && needs.main-ci.result == 'success' }}" "$(wf_if release)"
assert_eq 'v22.3 AC6.2 main-ci still runs on v* tags only (unchanged if:)' "    if: startsWith(github.ref, 'refs/tags/v')" "$(wf_if main-ci)"
assert_not_contains 'v22.3 AC6.2 main-ci does not depend on reuse' "$(wf_needs main-ci)" "reuse"
assert_not_contains 'v22.3 AC6.2 only release has contents: write (reuse has none)' "$RB" 'contents: write'

# --- v0.22.3 AC6.4: README
echo "v22.3 AC6.4 README"
flat_has 'v22.3 AC6.4 README: a main push reuses a green PR run' "$README" 'main push[^.]{0,250}reus|reus[^.]{0,250}main push'
flat_has 'v22.3 AC6.4 README: the reused run is a same-repo PR run' "$README" 'same[- ]repo(sitory)?[^.]{0,120}(PR|pull request)|(PR|pull request)[^.]{0,120}same[- ]repo'
flat_has 'v22.3 AC6.4 README: ... of the identical tree' "$README" 'identical tree|same tree|tree[^.]{0,60}identical'
flat_has 'v22.3 AC6.4 README: ... that was green' "$README" 'green[^.]{0,120}(PR|pull request)[^.]{0,120}run|(PR|pull request)[^.]{0,60}run[^.]{0,80}green'
# --- v0.22.4 AC4: parallel slices (SKILL.md Phase 2)
echo "v22.4 AC4.1 SKILL.md Phase 2: parallel slices in separate worktrees"
P2='^### Phase 2'
sec_flat_has 'v22.4 AC4.1 Phase 2 allows parallel slices' "$SKILL" "$P2" 'parallel'
sec_flat_has 'v22.4 AC4.1 only slices with disjoint files may run in parallel' "$SKILL" "$P2" 'disjoint[^.]{0,80}files?|files?[^.]{0,60}disjoint'
sec_flat_has 'v22.4 AC4.1 the disjoint files come from the spec Impact section' "$SKILL" "$P2" 'disjoint[^.]{0,200}impact|impact[^.]{0,200}disjoint'
sec_flat_has 'v22.4 AC4.1 each parallel slice has its own git worktree' "$SKILL" "$P2" 'separate (git )?worktrees?|(own|its own|each)[^.]{0,40}(git )?worktree'
sec_flat_has 'v22.4 AC4.1 each worktree has its own red/green commits and role gates' "$SKILL" "$P2" '(own|each)[^.]{0,200}(role[- ])?gates?'
sec_flat_has 'v22.4 AC4.1 the orchestrator merges the slice branches' "$SKILL" "$P2" 'orchestrator[^.]{0,80}merges?|merged by the orchestrator'
sec_flat_has 'v22.4 AC4.1 a merge conflict sends the slices back to serial work' "$SKILL" "$P2" 'conflict[^.]{0,160}serial|serial[^.]{0,160}conflict'
sec_flat_has 'v22.4 AC4.1 one review of the merged feature' "$SKILL" "$P2" 'one (fresh )?review(er)?[^.]{0,80}merged|merged[^.]{0,80}one (fresh )?review'
sec_flat_has 'v22.4 AC4.1 slices that share a file stay serial' "$SKILL" "$P2" 'shar(e|es|ing)[^.]{0,40}files?[^.]{0,80}serial'

# --- v0.22.4 AC5.4: project checklist in the role prompt and in playbook-learn
echo "v22.4 AC5.4 role-prompt.md has a project checklist section"
exact_heading 'v22.4 AC5.4 role-prompt.md has the exact heading' "$RPROMPT" '## 2c. Project checklist'
L2B="$(line_of "$RPROMPT" '^## 2b. Context pack')"; L2C="$(line_of "$RPROMPT" '^## 2c. Project checklist')"; L3="$(line_of "$RPROMPT" '^## 3. This slice')"
if [ -n "$L2B" ] && [ -n "$L2C" ] && [ -n "$L3" ] && [ "$L2B" -lt "$L2C" ] && [ "$L2C" -lt "$L3" ]; then t_ok 'v22.4 AC5.4 section 2c sits between 2b and 3'; else t_bad 'v22.4 AC5.4 section 2c sits between 2b and 3' "lines: 2b=[$L2B] 2c=[$L2C] 3=[$L3]"; fi
sec_flat_has 'v22.4 AC5.4 section 2c is the output of learn.sh checklist for the role' "$RPROMPT" '^## 2c' 'learn\.sh checklist'
LEARNSK="$PB_ROOT/skills/playbook-learn/SKILL.md"
flat_has 'v22.4 AC5.4 playbook-learn mentions --role' "$LEARNSK" '--role'
flat_has 'v22.4 AC5.4 playbook-learn mentions checklist' "$LEARNSK" 'checklist'
flat_has 'v22.4 AC5.2 playbook-learn says the Role line counts toward the line budget' "$LEARNSK" '(role[^.]{0,160}(line budget|LEARN_MAX_LINES|line limit)|(line budget|LEARN_MAX_LINES|line limit)[^.]{0,160}role)'

# --- v0.22.4 AC6.3: wording lows
echo "v22.4 AC6.3 SKILL.md, state.md, bsd-check"
flat_has 'v22.4 AC6.3 SKILL.md: the regression corpus comes from code and tests, not from the source' "$SKILL" 'corpus[^.]{0,200}code and (the )?tests?[^.]{0,120}not[^.]{0,40}source'
check 'v22.4 AC6.3 state.md: the reviewer line is "the sha it reviewed"' "$TDD/templates/state.md" 'reviewer:.*the sha it reviewed'
sec_flat_has 'v22.4 AC6.3 first-slice checkpoint: autonomy=full shows the slice' "$SKILL" "$P2" 'autonomy=full[^.]{0,200}show'
sec_flat_has 'v22.4 AC6.3 first-slice checkpoint: autonomy=full does not wait' "$SKILL" "$P2" 'autonomy=full[^.]{0,200}(do not wait|does not wait|without waiting|no wait|not wait)'
BSD_USAGE="$(sed -n '1,12p' "$PB_ROOT/tools/bsd-check.sh" | tr '\n' ' ' | tr -s ' ')"
case "$BSD_USAGE" in
  *[Rr]elative\ to\ the\ repo*root*) t_ok 'v22.4 AC6.3 bsd-check usage: suite paths are relative to the repo root' ;;
  *) t_bad 'v22.4 AC6.3 bsd-check usage: suite paths are relative to the repo root' "header: $BSD_USAGE" ;;
esac
case "$BSD_USAGE" in
  *[Ss]uite*relative*|*relative*[Ss]uite*|*[Pp]ath*relative*|*relative*[Pp]ath*) t_ok 'v22.4 AC6.3 bsd-check usage: the sentence is about the suite paths' ;;
  *) t_bad 'v22.4 AC6.3 bsd-check usage: the sentence is about the suite paths' "header: $BSD_USAGE" ;;
esac

echo "v22.4 review: the first-slice checkpoint keeps its Why line directly after it"
CHK_L="$(grep -n -m1 '^\*\*First-slice checkpoint' "$SKILL" | cut -d: -f1)"
PAR_L="$(grep -n -m1 '^\*\*Parallel slices' "$SKILL" | cut -d: -f1)"
WHY_L="$(grep -n 'wrong pattern copied' "$SKILL" | head -n 1 | cut -d: -f1)"
if [ -n "$CHK_L" ] && [ -n "$PAR_L" ] && [ -n "$WHY_L" ]; then t_ok 'v22.4 review SKILL.md has the checkpoint, its Why line and the Parallel slices paragraph'; else t_bad 'v22.4 review SKILL.md has the checkpoint, its Why line and the Parallel slices paragraph' "checkpoint=[$CHK_L] parallel=[$PAR_L] why=[$WHY_L]"; fi
if [ -n "$CHK_L" ] && [ -n "$WHY_L" ] && [ -n "$PAR_L" ] && [ "$CHK_L" -lt "$WHY_L" ] && [ "$WHY_L" -lt "$PAR_L" ]; then t_ok 'v22.4 review the Why line comes before the Parallel slices paragraph'; else t_bad 'v22.4 review the Why line comes before the Parallel slices paragraph' "checkpoint=[$CHK_L] why=[$WHY_L] parallel=[$PAR_L]"; fi
if [ -n "$CHK_L" ] && [ -n "$WHY_L" ] && [ "$CHK_L" -lt "$WHY_L" ] && [ "$(sed -n "$((CHK_L + 1)),$((WHY_L - 1))p" "$SKILL" | grep -c '^\*\*')" = 0 ]; then t_ok 'v22.4 review no other paragraph starts between the checkpoint and its Why line'; else t_bad 'v22.4 review no other paragraph starts between the checkpoint and its Why line' "checkpoint=[$CHK_L] why=[$WHY_L]"; fi
if flat "$README" | grep -qiE 'rebase[^.]{0,80}always[^.]{0,60}run'; then t_bad 'v22.3 review Low-2 README no longer says rebase merges always run the tests' 'the old claim is still there'; else t_ok 'v22.3 review Low-2 README no longer says rebase merges always run the tests'; fi
flat_has 'v22.3 review Low-2 README: a rebase merge reuses a run only when its single resulting commit has the PR head tree' "$README" 'rebase merge[^.]{0,250}only when[^.]{0,250}(single|one)[^.]{0,80}commit[^.]{0,200}tree'
flat_has 'v22.3 review Low-2 README: ... and the PR head parent P' "$README" 'rebase merge[^.]{0,250}only when[^.]{0,250}(parent|P)\b'
echo "v22.3 review Low-4: the reuse step validates the run id before writing the output"
RSTEP="$(wf_block reuse | awk '/id: tree/ { f = 1 } f { print }')"
assert_contains 'v22.3 review Low-4 the reuse step has a numeric-only guard' "$RSTEP" '[!0-9]'
GUARD_LN="$(printf '%s\n' "$RSTEP" | grep -n -m1 -F '[!0-9]' | cut -d: -f1)"
OUT_LN="$(printf '%s\n' "$RSTEP" | grep -n -m1 'GITHUB_OUTPUT' | cut -d: -f1)"
if [ -n "$GUARD_LN" ] && [ -n "$OUT_LN" ] && [ "$GUARD_LN" -lt "$OUT_LN" ]; then t_ok 'v22.3 review Low-4 the guard comes before the write to GITHUB_OUTPUT'; else t_bad 'v22.3 review Low-4 the guard comes before the write to GITHUB_OUTPUT' "guard line [$GUARD_LN] output line [$OUT_LN]"; fi

# --- v0.23.0 AC2: the README test count is checked in the PR (static checks of the workflow)
# wf_step ID NAME -> the lines of that step ("      - name: NAME" up to the next step) of the job
wf_step() { wf_block "$1" | awk -v n="      - name: $2" '$0 == n { f = 1; print; next } f && /^      - / { exit } f { print }'; }
# step_if TEXT -> the step-level if: line ("" when none)
step_if() { printf '%s\n' "$1" | grep -m1 '^        if:'; }
REDUCED_COND="needs.changes.result == 'success' && needs.changes.outputs.docs_only == 'true'"

echo "v23.0 AC2 workflow: the ubuntu job counts the README tests"
FULLSTEP="$(wf_step "${MAIN:-__none__}" 'Tests and static checks')"
if [ -n "$FULLSTEP" ]; then t_ok 'v23.0 AC5.2 the test job keeps a step named exactly "Tests and static checks"'; else t_bad 'v23.0 AC5.2 the test job keeps a step named exactly "Tests and static checks"' "block: $MB"; fi
RUNALL_LINES="$(printf '%s\n' "$MB" | grep 'run-all\.sh')"
TEE_LINE="$(printf '%s\n' "$RUNALL_LINES" | grep -m1 'tee')"
if [ -n "$TEE_LINE" ]; then t_ok 'v23.0 AC2.1 the test job tees the run-all output to a log'; else t_bad 'v23.0 AC2.1 the test job tees the run-all output to a log' "run-all lines: $RUNALL_LINES"; fi
case "$MB" in *pipefail*|*PIPESTATUS*) t_ok 'v23.0 AC2.1 the test job keeps the exit code of run-all (pipefail or PIPESTATUS)' ;; *) t_bad 'v23.0 AC2.1 the test job keeps the exit code of run-all (pipefail or PIPESTATUS)' "no pipefail or PIPESTATUS in the block" ;; esac
case "$RUNALL_LINES" in *'|| true'*) t_bad 'v23.0 AC2.1 the run-all line never ends in || true' "lines: $RUNALL_LINES" ;; *) t_ok 'v23.0 AC2.1 the run-all line never ends in || true' ;; esac
CHECK_LINE="$(printf '%s\n' "$MB" | grep -m1 'readme-count\.sh --check')"
if printf '%s\n' "$CHECK_LINE" | grep -Eq 'readme-count\.sh --check[[:space:]]+[^[:space:]]+'; then t_ok 'v23.0 AC2.1 the test job runs tools/readme-count.sh --check with a log argument'; else t_bad 'v23.0 AC2.1 the test job runs tools/readme-count.sh --check with a log argument' "check line: [$CHECK_LINE]"; fi
TEE_LOG="$(printf '%s\n' "$TEE_LINE" | sed 's/.*tee[[:space:]]*//; s/^-a[[:space:]]*//; s/[[:space:]].*//; s/"//g')"
if [ -n "$TEE_LOG" ]; then case "$CHECK_LINE" in *"$TEE_LOG"*) t_ok 'v23.0 AC2.1 the check reads the log that run-all wrote (same path as tee)' ;; *) t_bad 'v23.0 AC2.1 the check reads the log that run-all wrote (same path as tee)' "tee log [$TEE_LOG] check line [$CHECK_LINE]" ;; esac; else t_bad 'v23.0 AC2.1 the check reads the log that run-all wrote (same path as tee)' "no tee log found"; fi
TEE_LN="$(printf '%s\n' "$MB" | grep -n -m1 'run-all\.sh.*tee' | cut -d: -f1)"
CHECK_LN="$(printf '%s\n' "$MB" | grep -n -m1 'readme-count\.sh --check' | cut -d: -f1)"
if [ -n "$TEE_LN" ] && [ -n "$CHECK_LN" ] && [ "$TEE_LN" -lt "$CHECK_LN" ]; then t_ok 'v23.0 AC2.1 the count check comes after the run-all line'; else t_bad 'v23.0 AC2.1 the count check comes after the run-all line' "tee line [$TEE_LN] check line [$CHECK_LN]"; fi
# the step that holds the check: only ubuntu, never macOS, and only on a full run
CHECK_STEP="$(printf '%s\n' "$MB" | awk '/^      - / { if (buf ~ /readme-count\.sh --check/) { printf "%s", buf; exit } buf = "" } { buf = buf $0 "\n" } END { if (buf ~ /readme-count\.sh --check/) printf "%s", buf }')"
case "$CHECK_STEP" in *ubuntu-latest*|*Linux*) t_ok 'v23.0 AC2.1 the count check is limited to ubuntu (the macOS job does not run it)' ;; *) t_bad 'v23.0 AC2.1 the count check is limited to ubuntu (the macOS job does not run it)' "step: $CHECK_STEP" ;; esac
case "$CHECK_STEP" in *docs_only*|*"name: Tests and static checks"*) t_ok 'v23.0 AC2.1 the count check runs on full runs only (docs_only gate or inside the full step)' ;; *) t_bad 'v23.0 AC2.1 the count check runs on full runs only (docs_only gate or inside the full step)' "step: $CHECK_STEP" ;; esac
assert_not_contains 'v23.0 AC2.1 the Windows shard job does not run the count check' "$SB" 'readme-count'
assert_not_contains 'v23.0 AC2.1 the aggregator does not run the count check' "$AB" 'readme-count'

echo "v23.0 AC2.2 README or CHANGELOG: a PR that adds tests updates the README count"
CHLOG="$PB_ROOT/CHANGELOG.md"
COUNT_RULE='(PR|pull request)[^.]{0,80}(add|adds|adding|added)[^.]{0,60}tests?[^.]{0,160}(README|readme-count)|(README|readme-count)[^.]{0,120}(PR|pull request)[^.]{0,80}(add|adds|adding|added)[^.]{0,60}tests?'
if flat "$README" | grep -qiE -- "$COUNT_RULE" || flat "$CHLOG" | grep -qiE -- "$COUNT_RULE"; then t_ok 'v23.0 AC2.2 README or CHANGELOG says a PR that adds tests updates the README count'; else t_bad 'v23.0 AC2.2 README or CHANGELOG says a PR that adds tests updates the README count' "pattern [$COUNT_RULE] in neither file"; fi
if flat "$README" | grep -qiE -- 'readme-count|tools/readme-count' || flat "$CHLOG" | grep -qiE -- 'readme-count\.sh[^.]{0,120}(PR|CI|check)'; then t_ok 'v23.0 AC2.2 the rule names tools/readme-count.sh'; else t_bad 'v23.0 AC2.2 the rule names tools/readme-count.sh' 'neither file ties readme-count.sh to the PR check'; fi

# --- v0.23.0 AC5.1: the changes job (docs-only detection)
echo "v23.0 AC5.1 workflow: the changes job"
if wf_jobs | grep -qxF changes; then t_ok 'v23.0 AC5.1 a job changes exists'; else t_bad 'v23.0 AC5.1 a job changes exists' "jobs: $(wf_jobs | tr '\n' ' ')"; fi
CHB="$(wf_block changes)"
CHIF="$(wf_if changes)"
assert_contains "v23.0 AC5.1 the changes if: tests the event" "$CHIF" "github.event_name == 'pull_request'"
assert_eq 'v23.0 AC5.1 changes has timeout-minutes 5' "5" "$(wf_timeout changes)"
if printf '%s\n' "$CHB" | grep -Eq '^      contents:[[:space:]]*read[[:space:]]*$'; then t_ok 'v23.0 AC5.1 changes has contents: read'; else t_bad 'v23.0 AC5.1 changes has contents: read' "block: $CHB"; fi
if printf '%s' "$CHB" | grep -Eq '^      [a-z-]+:[[:space:]]*write'; then t_bad 'v23.0 AC5.1 changes has no write permission' "block: $CHB"; else t_ok 'v23.0 AC5.1 changes has no write permission'; fi
assert_contains 'v23.0 AC5.1 changes checks out with fetch-depth: 0' "$CHB" 'fetch-depth: 0'
if printf '%s\n' "$CHB" | grep -Eq '^    outputs:' && printf '%s\n' "$CHB" | grep -Eq '^      docs_only:[[:space:]]*\$\{\{'; then t_ok 'v23.0 AC5.1 changes outputs docs_only'; else t_bad 'v23.0 AC5.1 changes outputs docs_only' "block: $CHB"; fi
assert_contains 'v23.0 AC5.1 changes writes docs_only to GITHUB_OUTPUT' "$CHB" 'docs_only='
assert_contains 'v23.0 AC5.1 changes uses the base sha of the event' "$CHB" 'pull_request.base.sha'
assert_contains 'v23.0 AC5.1 changes uses the head sha of the event' "$CHB" 'pull_request.head.sha'
assert_contains 'v23.0 AC5.1 changes runs tools/docs-only.sh' "$CHB" 'tools/docs-only.sh'
assert_not_contains 'v23.0 AC5.1 the changes block never names macos-latest' "$CHB" 'macos-latest'
assert_not_contains 'v23.0 AC5.1 the changes block never names PB_SHARD' "$CHB" 'PB_SHARD'
assert_not_contains 'v23.0 AC5.1 the changes block never names windows-latest' "$CHB" 'windows-latest'
assert_not_contains 'v23.0 AC5.1 changes does not run the suites' "$CHB" 'tests/run-all.sh'
DOCSONLY="$PB_ROOT/tools/docs-only.sh"
assert_file 'v23.0 AC5.1 tools/docs-only.sh exists' "$DOCSONLY"
DOTXT="$(cat "$DOCSONLY" 2>/dev/null)"
assert_contains 'v23.0 AC5.1 docs-only.sh lists the changed paths with git diff --name-only' "$DOTXT" 'git diff --name-only'
assert_contains 'v23.0 AC5.1 docs-only.sh turns rename detection off (--no-renames)' "$DOTXT" '--no-renames'
assert_eq 'v23.0 AC5.1 MAIN detection still finds the test job (not changes)' "test" "$MAIN"
assert_eq 'v23.0 AC5.1 SHARD detection still finds windows-shard (not changes)' "windows-shard" "$SHARD"

# --- v0.23.0 AC5.2: the required jobs are never skipped; the run step has a reduced path
echo "v23.0 AC5.2 workflow: needs changes, same if:, reduced step"
for id in test windows-shard; do
  assert_contains "v23.0 AC5.2 job $id needs reuse (still)" "$(wf_needs "$id")" "reuse"
  assert_contains "v23.0 AC5.2 job $id needs changes" "$(wf_needs "$id")" "changes"
  assert_eq "v23.0 AC5.2 job $id keeps the exact one-line if:" "    $NOREUSE_IF" "$(wf_if "$id")"
done
assert_not_contains 'v23.0 AC5.2 the aggregator does not need changes (it only reads the shard result)' "$(wf_needs "$AGG")" 'changes'
case "$(wf_needs "$AGG")" in *"[windows-shard, reuse]"*) t_ok 'v23.0 AC5.2 the aggregator keeps needs: [windows-shard, reuse]' ;; *) t_bad 'v23.0 AC5.2 the aggregator keeps needs: [windows-shard, reuse]' "needs: $(wf_needs "$AGG")" ;; esac
for id in test windows-shard; do
  if [ "$id" = test ]; then FULLN='Tests and static checks'; else FULLN='Tests and static checks (shard)'; fi
  FS="$(wf_step "$id" "$FULLN")"
  DS="$(wf_step "$id" 'Docs-only checks')"
  if [ -n "$FS" ]; then t_ok "v23.0 AC5.2 job $id keeps the full step named [$FULLN]"; else t_bad "v23.0 AC5.2 job $id keeps the full step named [$FULLN]" "block: $(wf_block "$id")"; fi
  if [ -n "$DS" ]; then t_ok "v23.0 AC5.2 job $id has a step named [Docs-only checks]"; else t_bad "v23.0 AC5.2 job $id has a step named [Docs-only checks]" "block: $(wf_block "$id")"; fi
  assert_contains "v23.0 AC5.2 job $id: the reduced step runs only when changes succeeded and docs_only is true" "$(step_if "$DS")" "$REDUCED_COND"
  assert_contains "v23.0 AC5.2 job $id: the full step runs unless that condition holds (negated)" "$(step_if "$FS")" "!($REDUCED_COND)"
  assert_contains "v23.0 AC5.2 job $id: the full step still runs tests/run-all.sh" "$FS" 'tests/run-all.sh'
  assert_not_contains "v23.0 AC5.2 job $id: the reduced step does not run the count check" "$DS" 'readme-count'
  assert_contains "v23.0 AC5.2 job $id: the reduced suites are found by grep at run time" "$DS" 'grep'
  assert_contains "v23.0 AC5.2 job $id: the reduced set reads PB_ROOT/README.md" "$DS" 'PB_ROOT/README.md'
  assert_contains "v23.0 AC5.2 job $id: the reduced set reads PB_ROOT/CHANGELOG.md" "$DS" 'PB_ROOT/CHANGELOG.md'
  assert_contains "v23.0 AC5.2 job $id: the reduced set adds tests/test-content.sh" "$DS" 'test-content.sh'
  assert_contains "v23.0 AC5.2 job $id: the reduced set adds evals/run-checks.sh" "$DS" 'run-checks.sh'
done
assert_not_contains 'v23.0 AC5.2 the Windows reduced step does not skip suites by shard (every shard runs the whole set)' "$(wf_step windows-shard 'Docs-only checks')" 'PB_SHARD'

# --- v0.23.0 review: the shas reach the changes job through env:, never interpolated into the script text
echo "v23.0 review: changes passes the shas through env:"
PRREF_LINES="$(printf '%s\n' "$CHB" | grep 'github\.event\.pull_request')"
PRREF_N="$(printf '%s\n' "$PRREF_LINES" | grep -c 'github\.event\.pull_request')"
if [ "$PRREF_N" -ge 2 ]; then t_ok 'v23.0 review changes reads the base and the head sha from the event (>= 2 references)'; else t_bad 'v23.0 review changes reads the base and the head sha from the event (>= 2 references)' "lines: $PRREF_LINES"; fi
BAD_REF="$(printf '%s\n' "$PRREF_LINES" | grep -v -E '^[[:space:]]+[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*\$\{\{[[:space:]]*github\.event\.pull_request\.(base|head)\.sha[[:space:]]*\}\}[[:space:]]*$')"
assert_eq 'v23.0 review every pull_request reference in changes is an env mapping (NAME: ${{ ... }})' "" "$BAD_REF"
CH_RUN="$(printf '%s\n' "$CHB" | awk '/^        run:/ { f = 1 } f { print }')"
assert_not_contains 'v23.0 review the run: text of changes has no ${{ github.event.pull_request' "$CH_RUN" '${{ github.event.pull_request'
assert_not_contains 'v23.0 review the run: text of changes has no ${{ github.event at all' "$CH_RUN" '${{ github.event'
if printf '%s\n' "$CHB" | grep -Eq '^        env:'; then t_ok 'v23.0 review the docs step of changes has an env: block'; else t_bad 'v23.0 review the docs step of changes has an env: block' "block: $CHB"; fi
# the env names are used in the script as quoted shell variables
ENVNAMES="$(printf '%s\n' "$PRREF_LINES" | grep -E '^[[:space:]]+[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*\$\{\{' | sed 's/^[[:space:]]*//; s/:.*//')"
for nm in $ENVNAMES; do
  case "$CH_RUN" in *"\$$nm"*|*"\${$nm}"*) t_ok "v23.0 review changes uses \$$nm in its script" ;; *) t_bad "v23.0 review changes uses \$$nm in its script" "run text: $CH_RUN" ;; esac
done

# --- v0.23.0 review: the README does not oversell the reduced path
if flat "$README" | grep -qiE -- 'docs-only[^.]{0,250}every required job|every required job[^.]{0,250}docs-only'; then t_bad 'v23.0 review README does not say the reduced checks run in "every required job"' 'the phrase is still next to Docs-only'; else t_ok 'v23.0 review README does not say the reduced checks run in "every required job"'; fi

# --- v0.23.2 AC8.1 / E1: the reduced docs-only set is the grep result plus tests/test-update.sh (D4)
echo "v23.2 AC8.1 workflow: the reduced docs-only set is pinned"
# The expected set is built here from the same grep the workflow runs (never a hard-coded list), plus the two names the
# workflow adds by name: tests/test-content.sh and tests/test-update.sh. tests/test-docs-rules.sh (lane A of v0.23.2) reads
# the README, so the grep finds it and the pin includes it (E1).
EXPECT_SET="$( cd "$PB_ROOT" && { grep -l 'PB_ROOT/README.md' tests/test-*.sh; grep -l 'PB_ROOT/CHANGELOG.md' tests/test-*.sh; echo tests/test-content.sh; echo tests/test-update.sh; } | sort -u )"
# the workflow's own computation: the text of the run block before its `for t in` loop is evaluated in the repo root
# (contract: it assigns the list of suites to the shell variable suites)
for id in test windows-shard; do
  DS23="$(wf_step "$id" 'Docs-only checks')"
  assert_contains "v23.2 AC8.1 job $id: the Docs-only step names tests/test-update.sh" "$DS23" 'test-update.sh'
  SETCODE="$(printf '%s\n' "$DS23" | awk '/^        run:/ { f = 1; next } f && /for t in/ { exit } f { print }')"
  GOT_SET="$( cd "$PB_ROOT" && suites=""; eval "$SETCODE" >/dev/null 2>&1; printf '%s\n' $suites | sort -u )"
  assert_eq "v23.2 AC8.1 job $id: the reduced set is exactly the grep result plus test-content.sh and test-update.sh" "$EXPECT_SET" "$GOT_SET"
  case "
$GOT_SET
" in *"
tests/test-update.sh
"*) t_ok "v23.2 AC8.1 job $id: tests/test-update.sh is in the reduced set" ;; *) t_bad "v23.2 AC8.1 job $id: tests/test-update.sh is in the reduced set" "set: $GOT_SET" ;; esac
  case "
$GOT_SET
" in *"
tests/test-docs-rules.sh
"*) t_ok "v23.2 AC8.1 job $id: tests/test-docs-rules.sh is in the reduced set (E1)" ;; *) t_bad "v23.2 AC8.1 job $id: tests/test-docs-rules.sh is in the reduced set (E1)" "set: $GOT_SET" ;; esac
  # D4: no wider grep. The grep stays on the two README/CHANGELOG patterns, so heavy suites stay out
  assert_not_contains "v23.2 AC8.1 job $id: the heavy suite tests/test-install.sh stays out (D4)" "
$GOT_SET
" "
tests/test-install.sh
"
  # v0.23.3 R5: the heavy suites stay out, every part of the two split suites (tests/test-run-checks*.sh and
  # tests/test-evals-grade2*.sh, found by glob so a part added later is covered too)
  for HEAVY in $(cd "$PB_ROOT" && ls tests/test-run-checks*.sh tests/test-evals-grade2*.sh 2>/dev/null); do
    assert_not_contains "v23.3 R5 job $id: the heavy suite $HEAVY stays out (D4)" "
$GOT_SET
" "
$HEAVY
"
  done
  # v0.24.1: test-leak-check.sh, test-ci-tree-tested.sh and test-role-gate.sh are split by section. tests/test-leak-check.sh is the one part that reads
  # the README and the CHANGELOG, so it alone is in the reduced set; every other part (found by glob, a part added later is covered too) stays out
  case "
$GOT_SET
" in *"
tests/test-leak-check.sh
"*) t_ok "v24.1 job $id: tests/test-leak-check.sh (it reads the README and the CHANGELOG) is in the reduced set" ;; *) t_bad "v24.1 job $id: tests/test-leak-check.sh (it reads the README and the CHANGELOG) is in the reduced set" "set: $GOT_SET" ;; esac
  for HEAVY in $(cd "$PB_ROOT" && ls tests/test-leak-check-*.sh tests/test-ci-tree-tested*.sh tests/test-role-gate*.sh 2>/dev/null); do
    assert_not_contains "v24.1 job $id: the suite $HEAVY stays out of the reduced set" "
$GOT_SET
" "
$HEAVY
"
  done
done
# v0.23.3 AC1a / R5: the suites are split, no part reads the README or the CHANGELOG (the grep above would pull it into the reduced
# set), every part is stored at mode 100755, and the shared fixture is a helper that run-all.sh does not start
for FAMILY in test-run-checks test-evals-grade2; do
  NPARTS="$(cd "$PB_ROOT" && ls tests/$FAMILY*.sh 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$NPARTS" -ge 2 ]; then t_ok "v23.3 AC1a tests/$FAMILY.sh is split into $NPARTS suites"; else t_bad "v23.3 AC1a tests/$FAMILY.sh is split into at least 2 suites" "found $NPARTS"; fi
  for PART in $(cd "$PB_ROOT" && ls tests/$FAMILY*.sh 2>/dev/null); do
    assert_eq "v23.3 R5 $PART names neither PB_ROOT/README.md nor PB_ROOT/CHANGELOG.md" "0" "$(grep -c -e 'PB_ROOT/README.md' -e 'PB_ROOT/CHANGELOG.md' "$PB_ROOT/$PART")"
    if git -C "$PB_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      assert_eq "v23.3 AC1a $PART is stored at mode 100755" "100755" "$(git -C "$PB_ROOT" ls-files -s -- "$PART" | cut -d' ' -f1)"
    else
      t_skip 1 "v23.3 AC1a mode of $PART needs a git checkout"
    fi
  done
done
HELPER="$PB_ROOT/tests/run-checks-fixture.sh"
assert_file "v23.3 R5 the shared run-checks fixture exists" "$HELPER"
case "$(basename "$HELPER")" in test-*.sh) t_bad "v23.3 R5 the fixture helper is not named test-*.sh" "name: $(basename "$HELPER")" ;; *) t_ok "v23.3 R5 the fixture helper is not named test-*.sh" ;; esac
FIRSTL=""; IFS= read -r FIRSTL < "$HELPER" 2>/dev/null
case "$FIRSTL" in "#!"*) t_ok "v23.3 R5 the fixture helper has a #! line" ;; *) t_bad "v23.3 R5 the fixture helper has a #! line" "first line: $FIRSTL" ;; esac
if bash -n "$HELPER" 2>/dev/null; then t_ok "v23.3 R5 the fixture helper passes bash -n"; else t_bad "v23.3 R5 the fixture helper passes bash -n"; fi
assert_eq "v23.3 R5 the fixture helper names neither PB_ROOT/README.md nor PB_ROOT/CHANGELOG.md" "0" "$(grep -c -e 'PB_ROOT/README.md' -e 'PB_ROOT/CHANGELOG.md' "$HELPER" 2>/dev/null)"
if git -C "$PB_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  assert_eq "v23.3 R5 the fixture helper is stored at mode 100755" "100755" "$(git -C "$PB_ROOT" ls-files -s -- tests/run-checks-fixture.sh | cut -d' ' -f1)"
else
  t_skip 1 "v23.3 R5 mode of the fixture helper needs a git checkout"
fi
# v0.24.1 shard balance: test-leak-check.sh (3 parts), test-ci-tree-tested.sh (2) and test-role-gate.sh (3 since v0.24.7) are split by section, and since v0.24.7 test-evals-grade6.sh (2) and test-ship.sh (2). Every part is stored at
# mode 100755. Only tests/test-leak-check.sh reads the README and the CHANGELOG (AC10.3), so only it is pulled into the docs-only reduced set by the grep.
set -- test-leak-check 3 test-ci-tree-tested 2 test-role-gate 3 test-evals-grade6 2 test-ship 2
while [ $# -ge 2 ]; do
  FAMILY="$1"; MINPARTS="$2"; shift 2
  NPARTS="$(cd "$PB_ROOT" && ls tests/$FAMILY*.sh 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$NPARTS" -ge "$MINPARTS" ]; then t_ok "v24.1 tests/$FAMILY.sh is split into $NPARTS suites (at least $MINPARTS)"; else t_bad "v24.1 tests/$FAMILY.sh is split into at least $MINPARTS suites" "found $NPARTS"; fi
  for PART in $(cd "$PB_ROOT" && ls tests/$FAMILY*.sh 2>/dev/null); do
    if [ "$PART" = tests/test-leak-check.sh ]; then
      if grep -q 'PB_ROOT/README.md' "$PB_ROOT/$PART" && grep -q 'PB_ROOT/CHANGELOG.md' "$PB_ROOT/$PART"; then t_ok "v24.1 $PART keeps the README and CHANGELOG reads"; else t_bad "v24.1 $PART keeps the README and CHANGELOG reads" "a literal is missing"; fi
    else
      assert_eq "v24.1 $PART names neither PB_ROOT/README.md nor PB_ROOT/CHANGELOG.md" "0" "$(grep -c -e 'PB_ROOT/README.md' -e 'PB_ROOT/CHANGELOG.md' "$PB_ROOT/$PART")"
    fi
    if git -C "$PB_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      assert_eq "v24.1 $PART is stored at mode 100755" "100755" "$(git -C "$PB_ROOT" ls-files -s -- "$PART" | cut -d' ' -f1)"
    else
      t_skip 1 "v24.1 mode of $PART needs a git checkout"
    fi
  done
done
# the shared setup of the split suites lives in helpers that run-all.sh does not start
for HNAME in leak-check-fixture ci-tree-fixture role-gate-fixture evals-e20-fixture evals-grade6-fixture ship-fixture; do
  HELPER="$PB_ROOT/tests/$HNAME.sh"
  assert_file "v24.1 the helper tests/$HNAME.sh exists" "$HELPER"
  case "$(basename "$HELPER")" in test-*.sh) t_bad "v24.1 the helper $HNAME.sh is not named test-*.sh" "name: $(basename "$HELPER")" ;; *) t_ok "v24.1 the helper $HNAME.sh is not named test-*.sh" ;; esac
  FIRSTL=""; IFS= read -r FIRSTL < "$HELPER" 2>/dev/null
  case "$FIRSTL" in "#!"*) t_ok "v24.1 the helper $HNAME.sh has a #! line" ;; *) t_bad "v24.1 the helper $HNAME.sh has a #! line" "first line: $FIRSTL" ;; esac
  if bash -n "$HELPER" 2>/dev/null; then t_ok "v24.1 the helper $HNAME.sh passes bash -n"; else t_bad "v24.1 the helper $HNAME.sh passes bash -n"; fi
  assert_eq "v24.1 the helper $HNAME.sh names neither PB_ROOT/README.md nor PB_ROOT/CHANGELOG.md" "0" "$(grep -c -e 'PB_ROOT/README.md' -e 'PB_ROOT/CHANGELOG.md' "$HELPER" 2>/dev/null)"
  if git -C "$PB_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    assert_eq "v24.1 the helper $HNAME.sh is stored at mode 100755" "100755" "$(git -C "$PB_ROOT" ls-files -s -- "tests/$HNAME.sh" | cut -d' ' -f1)"
  else
    t_skip 1 "v24.1 mode of the helper $HNAME.sh needs a git checkout"
  fi
done
assert_file "v23.2 AC8.1 E1 tests/test-docs-rules.sh exists" "$PB_ROOT/tests/test-docs-rules.sh"
if [ -f "$PB_ROOT/tests/test-docs-rules.sh" ]; then
  if grep -q 'PB_ROOT/README.md' "$PB_ROOT/tests/test-docs-rules.sh"; then t_ok 'v23.2 AC8.1 E1 tests/test-docs-rules.sh reads PB_ROOT/README.md (so the grep finds it)'; else t_bad 'v23.2 AC8.1 E1 tests/test-docs-rules.sh reads PB_ROOT/README.md (so the grep finds it)' 'the literal is missing'; fi
fi
if git -C "$PB_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  assert_eq 'v23.2 AC8.1 E1 tests/test-docs-rules.sh is committed or staged at mode 100755' "100755" "$(git -C "$PB_ROOT" ls-files -s -- tests/test-docs-rules.sh | cut -d' ' -f1)"
else
  t_skip 1 'v23.2 AC8.1 E1 mode of tests/test-docs-rules.sh needs a git checkout'
fi


# --- v0.23.3 AC8.1 / D5: the cd tracking limits of evals/transcript.js are documented in its header (not implemented)
echo "v23.3 AC8.1 transcript.js header names the cd tracking limits"
TSJS="$PB_ROOT/evals/transcript.js"
# the header is the comment block at the top of the file, up to the first line that is not a comment
TSHEAD="$(awk '/^(#!|\/\/)/ { print; next } { exit }' "$TSJS")"
TSHEAD_FLAT="$(printf '%s\n' "$TSHEAD" | tr '\n' ' ' | tr -s ' ')"
assert_contains "v23.3 AC8.1 the header names the chained form cd .agents; cd handoff" "$TSHEAD_FLAT" "cd .agents; cd handoff"
assert_contains "v23.3 AC8.1 the header names pushd" "$TSHEAD_FLAT" "pushd"
assert_contains "v23.3 AC8.1 the header says the cwd is not kept across Bash calls" "$TSHEAD_FLAT" "across Bash calls"
assert_contains "v23.3 AC8.1 the header uses the word cwd" "$TSHEAD_FLAT" "cwd"
case "$(printf '%s' "$TSHEAD_FLAT" | tr 'A-Z' 'a-z')" in
  *"not tracked"*|*"not followed"*|*"not kept"*|*"not covered"*|*"limit"*) t_ok "v23.3 AC8.1 the header states these as limits (not tracked / not covered / limit)" ;;
  *) t_bad "v23.3 AC8.1 the header states these as limits (not tracked / not covered / limit)" "header: $TSHEAD_FLAT" ;;
esac

# --- v0.23.3 review N4: the known grader limits are listed in the header next to the cd limits
echo "v23.3 review N4 transcript.js header names the heredoc and shell-feed limits"
assert_contains "v23.3 review N4 the header names sh -c with a command-substitution heredoc" "$TSHEAD_FLAT" 'sh -c "$(cat <<EOF'
assert_contains "v23.3 review N4 the header says that shape is read only at the end of a line" "$TSHEAD_FLAT" "end of a line"
assert_contains "v23.3 review N4 the header names eval with a command-substitution heredoc" "$TSHEAD_FLAT" 'eval "$(cat <<EOF"'
assert_contains "v23.3 review N4 the header names the heredoc written before its command (<<EOF cat)" "$TSHEAD_FLAT" '<<EOF cat'
assert_contains "v23.3 review N4 the header names sudo -iu" "$TSHEAD_FLAT" "sudo -iu"
assert_contains "v23.3 review N4 the header names a here-string after a heredoc" "$TSHEAD_FLAT" "here-string"
assert_contains "v23.3 review N4 the here-string limit is about the position after a heredoc" "$TSHEAD_FLAT" "after a heredoc"

# --- v0.23.3 round 3 R5: the here-string limit says what really happens (the here-string replaces the shell's stdin)
echo "v23.3 round 3 R5 the here-string limit is worded as what the grader does"
assert_not_contains "v23.3 R5 the header no longer says the position after a heredoc is not tracked" "$TSHEAD_FLAT" "position after a heredoc is not tracked"
# the text from the here-string bullet to the end of the header is that one limit (it is the last bullet)
TSHS="${TSHEAD_FLAT#*here-string}"
assert_contains "v23.3 R5 the here-string limit says the here-string replaces the shell's stdin" "$TSHS" "stdin"
assert_contains "v23.3 R5 the here-string limit says the heredoc body is still read as commands" "$TSHS" "commands"
assert_contains "v23.3 R5 the here-string limit keeps its subject: after a heredoc" "$TSHS" "after a heredoc"

# --- v0.23.3 round 3 R2 / R4: two limits of evals/run-checks.sh are documented in its own comments (not implemented)
echo "v23.3 round 3 R2 R4 run-checks.sh documents the arithmetic and quote-state limits"
RCSH="$PB_ROOT/evals/run-checks.sh"
# the comment lines of the gnu section (up to its first command) and of the strip() helper, one line each
RCGNU="$(awk '/^if want gnu; then/ { f = 1; next } f && /^#/ { print } f && /^ggnu=/ { exit }' "$RCSH" | tr '\n' ' ' | tr -s ' ' | tr 'A-Z' 'a-z')"
RCSTRIP="$(awk '/^# AWKSTRIP:/ { f = 1 } f && /^#/ { print; next } f { exit }' "$RCSH" | tr '\n' ' ' | tr -s ' ' | tr 'A-Z' 'a-z')"
RCSEDC="$(awk '/^if want sed; then/ { f = 1; next } f && /^#/ { print } f && /^gsed=/ { exit }' "$RCSH" | tr '\n' ' ' | tr -s ' ' | tr 'A-Z' 'a-z')"
if [ -n "$RCGNU" ] && [ -n "$RCSTRIP" ] && [ -n "$RCSEDC" ]; then t_ok "v23.3 R2 R4 the gnu, strip and sed comment blocks were found in evals/run-checks.sh"
else t_bad "v23.3 R2 R4 the gnu, strip and sed comment blocks were found in evals/run-checks.sh" "gnu=${#RCGNU} strip=${#RCSTRIP} sed=${#RCSEDC} chars"; fi
# R2: arithmetic state is per line
assert_contains "v23.3 R2 the gnu header names an arithmetic (( )) that spans lines" "$RCGNU" "(( ))"
assert_contains "v23.3 R2 the gnu header says that case is not tracked" "$RCGNU" "not tracked"
# R4: quote state in strip() is per line; an apostrophe in prose or a heredoc body hides a later # (a false positive for the sed check)
RCQ="$RCSTRIP $RCSEDC"
assert_contains "v23.3 R4 the strip/sed comments name an apostrophe in text" "$RCQ" "apostrophe"
assert_contains "v23.3 R4 the strip/sed comments name a heredoc body" "$RCQ" "heredoc"
assert_contains "v23.3 R4 the strip/sed comments state it as a limit" "$RCQ" "limit"



# ---- v0.24.0 (Lite, content): references/quick.md, AGENTS.global.md, confirm_models, scenarios E22-E25 ----
QUICK="$TDD/references/quick.md"
AGLOBAL="$PB_ROOT/AGENTS.global.md"
# qflat FILE -> the "## Quick workflow" section (heading to the next ## heading) on one line
qsec() { awk '/^## Quick workflow[[:space:]]*$/ { f = 1; next } f && /^## / { exit } f { print }' "$1" 2>/dev/null | tr '\n' ' '; }
qall() { tr '\n' ' ' < "$1" 2>/dev/null; }
# qchk NAME TEXT REGEX
qchk() { if printf '%s' "$2" | grep -qiE -- "$3"; then t_ok "$1"; else t_bad "$1" "pattern [$3] not found"; fi; }

echo "v0.24.0 AC1.2 quick.md: the Quick workflow section"
assert_file "AC1.2 references/quick.md exists" "$QUICK"
exact_heading "AC1.2 quick.md has the heading '## Quick workflow'" "$QUICK" "## Quick workflow"
QS="$(qsec "$QUICK")"
QW="$(printf '%s' "$QS" | wc -w | tr -d ' ')"
if [ "$QW" -ge 40 ] && [ "$QW" -le 250 ]; then t_ok "AC1.2 the Quick workflow section is 40..250 words ($QW)"; else t_bad "AC1.2 the Quick workflow section is 40..250 words" "$QW words"; fi
qchk "AC1.2 keep: a one-sentence restatement of the request in chat" "$QS" 'keep[^.]{0,200}(one-sentence|one sentence)[^.]{0,80}(restate|restatement|request)|(restate|restatement)[^.]{0,80}(one-sentence|one sentence)'
qchk "AC1.2 keep: one grep of the call sites with the hit count printed" "$QS" 'grep[^.]{0,80}call sites?[^.]{0,80}hit count|hit count[^.]{0,80}(printed|grep)'
qchk "AC1.2 keep: a behaviour change is still tested first and seen failing" "$QS" '(tested first|test first)[^.]{0,60}seen failing|seen failing'
qchk "AC1.2 keep: one proof-run after the last change" "$QS" 'one proof-run|proof-run[^.]{0,60}after the last change'
qchk "AC1.2 keep: git diff --stat" "$QS" 'git diff --stat'
qchk "AC1.2 drop: hand-off files" "$QS" 'drop[^.]{0,250}hand-?off files|hand-?off files'
qchk "AC1.2 drop: the detailed scan log" "$QS" 'scan log'
qchk "AC1.2 drop: Impact" "$QS" 'Impact'
qchk "AC1.2 drop: Pre-mortem" "$QS" 'Pre-mortem'
qchk "AC1.2 drop: the Confidence column" "$QS" 'Confidence column'
qchk "AC1.2 drop: the mutation spot-check" "$QS" 'mutation spot-check'
qchk "AC1.2 drop: cost.sh" "$QS" 'cost\.sh'
qchk "AC1.2 drop: the Playbook feedback line unless a rule misfired" "$QS" 'Playbook feedback[^.]{0,80}(unless|except|only)[^.]{0,40}misfire'
qchk "AC1.2 report: 3-5 lines" "$QS" '3[-–]5 lines'
qchk "AC1.2 report: understanding, change, evidence, not checked" "$QS" 'understanding[^.]{0,40}change[^.]{0,40}evidence[^.]{0,40}not checked'
qchk "AC1.2 report: the weight line Weight: Quick" "$QS" 'Weight: Quick'
qchk "AC1.2 report: Weight: Quick (user-requested)" "$QS" 'Weight: Quick \(user-requested\)'

echo "v0.24.0 AC1.3/AC1.4/R3/R4 quick.md: user-requested Quick, the two stops, headless, escalation"
QA="$(qall "$QUICK")"
qchk "AC1.3 user-requested: the user asks for the quick way or the Quick weight" "$QA" 'user[^.]{0,60}(asks?|says?|requests?)[^.]{0,60}quick'
qchk "R3 examples of asking: 'quick one', 'do it quick'" "$QA" 'quick one[^.]{0,80}do it quick|do it quick[^.]{0,80}quick one'
qchk "AC1.3 Quick at once, no re-assessment" "$QA" '(at once|immediately)[^.]{0,80}(no re-assess|without re-assess)|no re-assess'
qchk "AC1.3 two stops" "$QA" 'two stops'
qchk "AC1.3 stop (a): the diff touches the Full column" "$QA" 'Full column[^.]{0,120}(money|auth|migration|public API|data shape)|(money|auth|migration)[^.]{0,120}Full column'
qchk "AC1.3 stop (a) names money, auth, migration, public API or data shape" "$QA" 'money[^.]{0,40}auth[^.]{0,40}migration[^.]{0,60}(public )?API'
qchk "AC1.3 stop (b): the diff exceeds the Quick limits" "$QA" 'exceeds? the Quick limits'
qchk "AC1.3 ask the user ONCE" "$QA" 'ask(s)? the user (ONCE|once)'
qchk "AC1.3 never auto-upgrade" "$QA" 'never auto-?upgrade'
qchk "AC1.3 headless: do not block, do Quick" "$QA" 'headless[^.]{0,160}(do not block|never block|not block)[^.]{0,120}Quick|headless[^.]{0,200}do Quick'
qchk "AC1.3 headless label: over the limit, user chose Quick" "$QA" 'over the limit, user chose Quick'
qchk "R3 the skip-tests rule still applies inside Quick" "$QA" 'skip-tests rule|ask once[^.]{0,80}untested'
qchk "AC1.4 Quick never means no tests" "$QA" 'Quick never means no tests'
qchk "AC1.4 agent-chosen Quick that exceeds the limits escalates to Lite" "$QA" 'agent-chosen[^.]{0,200}escalat[^.]{0,40}Lite'
qchk "R4 Quick makes no checkpoint commits" "$QA" 'no checkpoint commits'
qchk "R4 role-gate.sh size --quick runs against HEAD after the change" "$QA" 'role-gate\.sh size --quick[^.]{0,80}HEAD|HEAD[^.]{0,80}role-gate\.sh size --quick'
qchk "R4 on escalation the test files alone are committed as test(red)" "$QA" 'test files alone[^.]{0,80}test\(red\)|test\(red\)[^.]{0,80}test files alone'
qchk "R4 that sha is RED" "$QA" '(sha|commit)[^.]{0,30}is RED|RED sha|as `?RED`?'
qchk "R4 continue at Lite from step 3" "$QA" 'Lite[^.]{0,40}step 3|step 3[^.]{0,60}Lite'
qchk "R4 write the Lite spec then" "$QA" 'Lite spec[^.]{0,40}then|then[^.]{0,40}Lite spec|write the Lite spec'
qchk "D6 agent-chosen Quick in documented-critical code: message-only or purely additive" "$QA" '(message[- ]only|message text)[^.]{0,120}(purely )?additive|purely additive[^.]{0,120}(message[- ]only|message text)'

echo "v0.24.0 AC1.7/R2 AGENTS.global.md: one Quick line"
QLINES="$(grep -c '\*\*Quick\*\*' "$AGLOBAL")"
assert_eq "AC1.7 exactly one line names **Quick**" "1" "$QLINES"
QLINE="$(grep '\*\*Quick\*\*' "$AGLOBAL" | head -n 1)"
QBYTES="$(printf '%s\n' "$QLINE" | LC_ALL=C wc -c | tr -d ' ')"
QB1=$((QBYTES - 1))
if [ "$QLINES" = 1 ] && [ "$QB1" -le 200 ]; then t_ok "R2 / v24.2 AC6.1 the Quick line is at most 200 bytes ($QB1)"; else t_bad "R2 / v24.2 AC6.1 the Quick line is at most 200 bytes" "$QB1 bytes: $QLINE"; fi
# v0.24.2 AC6.1/AC6.3: the always-on Quick line states the limits and the gate (real eval E21 chose Quick from this line alone)
qchk "AC6.1 the Quick line names the 1 production file limit" "$QLINE" '1 production file'
qchk "AC6.1 the Quick line names the 20 line limit" "$QLINE" '(≤|<=) ?20 lines'
qchk "AC6.1 the Quick line says nothing from the Full column" "$QLINE" 'nothing from the Full column'
qchk "AC6.1 the Quick line names changed public API, money, auth and migrations" "$QLINE" 'changed public API[^;]{0,40}money[^;]{0,40}auth[^;]{0,40}migrations?'
qchk "AC6.1 the Quick line says to load playbook-tdd first" "$QLINE" 'load `?playbook-tdd`? first'
qchk "AC6.1 the Quick line still says the user can ask by saying quick" "$QLINE" 'say(ing)? "quick"'
qchk "AC1.7 the line says Quick is for tiny changes" "$QLINE" 'tiny|small'
qchk "AC1.7 the line says the user can ask for it by saying quick" "$QLINE" 'user[^.]{0,40}(ask|say)[^.]{0,60}"quick"|say(ing)? "quick"'
AGL="$(wc -l < "$AGLOBAL" | tr -d ' ')"; AGB="$(wc -c < "$AGLOBAL" | tr -d ' ')"
if [ "$AGL" -le 60 ]; then t_ok "AC1.7 AGENTS.global.md stays within 60 lines ($AGL)"; else t_bad "AC1.7 AGENTS.global.md stays within 60 lines" "$AGL lines"; fi
if [ "$AGB" -le 5000 ]; then t_ok "AC1.7 AGENTS.global.md stays within 5000 bytes ($AGB)"; else t_bad "AC1.7 AGENTS.global.md stays within 5000 bytes" "$AGB bytes"; fi
if [ "$AGB" -le 4400 ]; then t_ok "AC6.1 AGENTS.global.md stays within 4400 bytes ($AGB)"; else t_bad "AC6.1 AGENTS.global.md stays within 4400 bytes" "$AGB bytes"; fi
# v0.24.2 AC6.2/AC6.3: quick.md says that removing or renaming an exported symbol is a public API change, never Quick
qchk "AC6.2 quick.md: removing or renaming an exported symbol is a public API change" "$(qall "$QUICK")" '(remov|renam)[^.]{0,60}exported symbol[^.]{0,80}public API'
qchk "AC6.2 quick.md: such a change is the Full column, never Quick" "$(qall "$QUICK")" 'exported symbol[^.]{0,200}Full column[^.]{0,80}never Quick|never Quick[^.]{0,200}exported symbol'
qchk "AC6.2 quick.md: the always-on line is not enough, load playbook-tdd first" "$(qall "$QUICK")" 'load[^.]{0,40}playbook-tdd[^.]{0,40}first|before[^.]{0,60}(choos|pick)[^.]{0,40}Quick'

TDDSEC="$(awk '/^### TDD with separated roles/ { f = 1; next } f && /^### / { exit } f { print }' "$AGLOBAL")"
qchk "AC1.7 the Quick line sits in the TDD section" "$TDDSEC" '\*\*Quick\*\*'
qchk "AC1.7 regression: the TDD section still names Full and Lite" "$TDDSEC" '\*\*Full\*\*[^*]{0,200}\*\*Lite\*\*'
SECS="$(grep -c '^### ' "$AGLOBAL")"; WHYS="$(grep -c '^Why: ' "$AGLOBAL")"
assert_eq "AC1.7 regression: every always-on section keeps its Why: line" "$SECS" "$WHYS"

echo "v0.24.0 AC2.4 confirm_models is documented (on-change by default)"
DOCS="$(cat "$PB_ROOT/README.md" "$PB_ROOT/skills/playbook-setup/SKILL.md" "$PB_ROOT/skills/playbook-setup/references/questions.md" 2>/dev/null | tr '\n' ' ')"
qchk "AC2.4 confirm_models is named in the README or setup" "$DOCS" 'confirm_models'
qchk "AC2.4 the three values always, on-change, never" "$DOCS" 'confirm_models[^|]{0,200}always[^|]{0,60}on-change[^|]{0,60}never|confirm_models[^|]{0,200}(on-change[^|]{0,60}always|never)'
qchk "AC2.4 on-change is the default" "$DOCS" 'confirm_models[^|]{0,250}default[^|]{0,60}on-change|on-change[^|]{0,60}\(?default'
README_T="$(tr '\n' ' ' < "$PB_ROOT/README.md")"
qchk "AC2.4 the README documents confirm_models" "$README_T" 'confirm_models'
SETUP_T="$(cat "$PB_ROOT/skills/playbook-setup/SKILL.md" "$PB_ROOT/skills/playbook-setup/references/questions.md" | tr '\n' ' ')"
qchk "AC2.4 setup documents confirm_models" "$SETUP_T" 'confirm_models'

echo "v0.24.0 AC1.8 / R12 scenarios E22-E25 in evals/scenarios.md"
exact_heading "AC1.8 scenarios has the E22 heading" "$SCEN" '## E22 A user-requested Quick change runs at Quick weight'
exact_heading "AC1.8 scenarios has the E23 heading" "$SCEN" '## E23 A user-requested Quick change that hits the Full column is labelled, not upgraded'
exact_heading "AC1.8 scenarios has the E24 heading" "$SCEN" '## E24 A configured model is binding'
exact_heading "R12 scenarios has the E25 heading" "$SCEN" '## E25 A change over the Quick limit runs at Lite'
for e in E22 E23 E24 E25; do
  re="^## $e "
  check_sec "AC1.8 $e has a Prompt line" "$SCEN" "$re" '^\*\*Prompt:\*\*'
  check_sec "AC1.8 $e has a Pass if line" "$SCEN" "$re" '^\*\*Pass if:\*\*'
  check_sec "AC1.8 $e has a Fail if line" "$SCEN" "$re" '^\*\*Fail if:\*\*'
done
l21="$(line_of "$SCEN" '^## E21 ')"; l22="$(line_of "$SCEN" '^## E22 ')"; l23="$(line_of "$SCEN" '^## E23 ')"; l24="$(line_of "$SCEN" '^## E24 ')"; l25="$(line_of "$SCEN" '^## E25 ')"
if [ -n "$l21" ] && [ -n "$l22" ] && [ -n "$l23" ] && [ -n "$l24" ] && [ -n "$l25" ] && [ "$l21" -lt "$l22" ] && [ "$l22" -lt "$l23" ] && [ "$l23" -lt "$l24" ] && [ "$l24" -lt "$l25" ]; then t_ok "AC1.8 E22..E25 follow E21 in order"
else t_bad "AC1.8 E22..E25 follow E21 in order" "E21=[$l21] E22=[$l22] E23=[$l23] E24=[$l24] E25=[$l25]"; fi
# the prompts are verbatim (the runner takes the first double-quoted string after **Prompt:**)
for p in \
  '**Prompt:** "Quick one: fix the typo '"'"'nubmers'"'"' in the TypeError message of `add`, and make sure a test covers the message."' \
  '**Prompt:** "Do it quick: in src/cart.js make `total()` ignore items whose qty is zero or negative; the billing service charges customers with that total."' \
  '**Prompt:** "Change `total()` in src/cart.js to return cents as an integer instead of a float, and update every caller. Prices are dollars as floats; round to the nearest cent (half up); nothing outside this repo calls total(). Use separate tester, implementer and reviewer sub-agents."' \
  '**Prompt:** (setup: the runner commits `src/report.js`, a second call site of `divide`) "Add an exported constant VERSION = '"'"'1.0.0'"'"' to src/calc.js, src/cart.js and src/report.js."'; do
  if grep -qF -- "$p" "$SCEN"; then t_ok "AC1.8 verbatim prompt present: ${p:0:60}..."; else t_bad "AC1.8 verbatim prompt present: ${p:0:60}..." "not found in $SCEN"; fi
done
E22S="$(awk -v h='## E22 ' 'index($0, h) == 1 { f = 1; next } f && /^## / { exit } f { print }' "$SCEN" | tr '\n' ' ')"
E23S="$(awk -v h='## E23 ' 'index($0, h) == 1 { f = 1; next } f && /^## / { exit } f { print }' "$SCEN" | tr '\n' ' ')"
E24S="$(awk -v h='## E24 ' 'index($0, h) == 1 { f = 1; next } f && /^## / { exit } f { print }' "$SCEN" | tr '\n' ' ')"
E25S="$(awk -v h='## E25 ' 'index($0, h) == 1 { f = 1; next } f && /^## / { exit } f { print }' "$SCEN" | tr '\n' ' ')"
qchk "AC1.8 E22 passes on Weight: Quick (user-requested)" "$E22S" 'Weight: Quick \(user-requested\)'
qchk "AC1.8 E22 asks no question" "$E22S" 'no question|asks? nothing|without (a )?question'
qchk "AC1.8 E22 cost recorded" "$E22S" 'cost'
qchk "AC1.8 E23 is headless" "$E23S" 'headless'
qchk "AC1.8 E23 the label: over the limit, user chose Quick" "$E23S" 'over the limit, user chose Quick'
qchk "AC1.8 E23 never upgrades silently" "$E23S" 'never upgrade|silently'
qchk "R12 E23 edits src/cart.js total" "$E23S" 'src/cart\.js'
qchk "AC2.6 E24 reads every Agent/Task model parameter" "$E24S" 'Agent[^.]{0,40}Task|Task[^.]{0,40}Agent'
qchk "AC2.6 E24 the models of the conf: sonnet and opus" "$E24S" 'sonnet[^.]{0,200}opus|opus[^.]{0,200}sonnet'
qchk "AC2.6 E24 the reply has a Models: line" "$E24S" 'Models:'
qchk "R5 E24 the runner commits a project .agents/playbook.conf" "$E24S" '\.agents/playbook\.conf'
qchk "R12 E25 escalates from Quick to Lite" "$E25S" 'escalat[^.]{0,80}Lite|Lite[^.]{0,80}escalat'
qchk "R12 E25 names size --quick" "$E25S" 'size --quick'
qchk "v24.2 AC5.2 E25 is a purely additive change (no Full item)" "$E25S" 'additive'
qchk "v24.2 AC5.2 E25 checks that each file exports VERSION" "$E25S" 'each file exports VERSION|exports? VERSION'
qchk "v24.2 AC5.2 E25 fails on a Full jump without a Full-column reason" "$E25S" 'Full[^.]{0,80}(without|no)[^.]{0,40}(Full[- ]column )?reason'
qchk "R12 E25 is headless" "$E25S" 'headless'
echo "v0.24.0 AC1.8 the AUTO list and the scenario map"
AUTOLINE="$(grep '^AUTO=' "$PB_ROOT/evals/run-evals.sh")"
for e in E22 E23 E24 E25; do
  qchk "AC1.8 $e is in the AUTO list of run-evals.sh" "$AUTOLINE" "[\" ]$e[\" ]"
done
MAPLINE="$(grep -E '^skills/playbook-tdd/\* ' "$PB_ROOT/evals/scenario-map")"
for e in E22 E23 E24 E25; do
  qchk "AC1.8 $e is in the scenario-map line of skills/playbook-tdd/*" "$MAPLINE" "(^| )$e( |$)"
done
AGMAP="$(grep -E '^AGENTS\.global\.md ' "$PB_ROOT/evals/scenario-map")"
qchk "R2 the AGENTS.global.md map line keeps E1 E3 E5 E8 E10 E21" "$AGMAP" 'E1 E3 E5 E8 E10 E21'


echo "v0.24.0 review round 2 F6: the size --quick check applies to both paths (user-requested stop b, agent-chosen escalation)"
QOUTSIDE="$(awk '/^## When Quick must escalate/ { skip = 1; next } skip && /^## / { skip = 0 } !skip { print }' "$QUICK" 2>/dev/null | tr '\n' ' ')"
qchk "F6 quick.md names role-gate.sh size --quick outside the escalation section" "$QOUTSIDE" 'role-gate\.sh size --quick'
QUSER="$(awk '/^## When the user asks for Quick/ { f = 1; next } f && /^## / { exit } f { print }' "$QUICK" 2>/dev/null | tr '\n' ' ')"
qchk "F6 the user-requested section uses the size --quick check for stop (b)" "$QUSER" 'size --quick'
t_summary
