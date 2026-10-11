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
if [ "$BLOCK_BYTES" -le 4700 ]; then t_ok "v13 AC5.1 AGENTS.global.md is <= 4700 bytes ($BLOCK_BYTES)"; else t_bad "v13 AC5.1 AGENTS.global.md is <= 4700 bytes" "$BLOCK_BYTES bytes"; fi

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
assert_contains "v14 AC8.2 the shard matrix has 1/3" "$SB" "1/3"
assert_contains "v14 AC8.2 the shard matrix has 2/3" "$SB" "2/3"
assert_contains "v14 AC8.2 the shard matrix has 3/3" "$SB" "3/3"
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
t_summary
