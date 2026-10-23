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
HARNESSES="$TDD/references/harnesses.md"   # v0.24.13: harness and model plumbing moved here
SETUP="$PB_ROOT/skills/playbook-setup/SKILL.md"
QUESTIONS="$PB_ROOT/skills/playbook-setup/references/questions.md"

# has FILE PATTERN: case-insensitive extended regex found in FILE (false if FILE is missing)
has() { grep -qiE -- "$2" "$1" 2>/dev/null; }
# check NAME FILE PATTERN
check() { if has "$2" "$3"; then t_ok "$1"; else t_bad "$1" "pattern [$3] not in $2"; fi; }
# section FILE HEADING_REGEX: text from the matching heading to the next ##/### heading (exclusive)
section() {
  awk -v re="$2" 'BEGIN{re=tolower(re)} f && /^##+ /{exit} !f && tolower($0) ~ re {f=1} f{print}' "$1" 2>/dev/null
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

# v0.24.27: section() matches the heading case-insensitively on any awk (gawk IGNORECASE is not in BSD awk)
SECFX="$(mk_tmp)/fx.md"
printf '## oracle\nthe body line\n## next heading\nafter the section\n' > "$SECFX"
SECOUT="$(section "$SECFX" '^## Oracle')"
case "$SECOUT" in *"the body line"*) t_ok 'section() matches a capitalised pattern against a lower-case heading' ;; *) t_bad 'section() matches a capitalised pattern against a lower-case heading' "got [$SECOUT]" ;; esac
case "$SECOUT" in *"after the section"*) t_bad 'section() stops at the next heading' "got [$SECOUT]" ;; *) t_ok 'section() stops at the next heading' ;; esac

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
check 'AC9 Claude Code Agent/Task model parameter' "$HARNESSES" '`model` parameter|model parameter'
check 'AC9 OpenCode per-role agent in opencode.json' "$HARNESSES" 'opencode\.json'
check 'AC9 Codex exec -m' "$HARNESSES" 'codex exec -m'
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
infra_paras() { printf '%s\n' "$TDDALL" | awk 'BEGIN{RS="";ORS="\n\n"} tolower($0) ~ /infra/'; }
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
# <= 4500 bytes (v0.24.10: the Quick line is gone; v0.24.24: raised from 4400 for the pushback sentence, decision D3-prime)
if [ "$BLOCK_BYTES" -le 4500 ]; then t_ok "v24.1 AGENTS.global.md is <= 4500 bytes ($BLOCK_BYTES)"; else t_bad "v24.1 AGENTS.global.md is <= 4500 bytes" "$BLOCK_BYTES bytes"; fi
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

# --- v0.24.24 AC1: the pushback rule sits in the Proof section (spec round 3: exact sentence, no carve-out)
jchk 'v24.24 AC1 Proof: the pushback rule opens "On pushback"' "$BLOCK" "$PROOF" 'On pushback'
jchk 'v24.24 AC1 Proof: the rule says to say what you checked' "$BLOCK" "$PROOF" 'what you checked'
jchk 'v24.24 AC1 Proof: the rule changes a conclusion only on new evidence' "$BLOCK" "$PROOF" 'new evidence'
jchk 'v24.24 AC1 Proof: the rule says insistence is not evidence' "$BLOCK" "$PROOF" 'insistence'
jchk 'v24.24 AC1 Proof: the exact sentence (round 3)' "$BLOCK" "$PROOF" 'On pushback, re-check and say what you checked; change a conclusion only on new evidence, not insistence\.'
PB_AGL="$(wc -l < "$BLOCK" | tr -d ' ')"; PB_AGW="$(wc -w < "$BLOCK" | tr -d ' ')"
# characterization: these hold today and must keep holding (line 17 grows, no line is added)
if [ "$PB_AGL" -le 39 ]; then t_ok "v24.24 AC1 AGENTS.global.md keeps its 39 lines ($PB_AGL)"; else t_bad "v24.24 AC1 AGENTS.global.md keeps its 39 lines" "$PB_AGL lines"; fi
if [ "$PB_AGW" -le 700 ]; then t_ok "v24.24 AC1 AGENTS.global.md keeps the 700-word budget ($PB_AGW)"; else t_bad "v24.24 AC1 AGENTS.global.md keeps the 700-word budget" "$PB_AGW words"; fi
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
AGG=""; SHARD=""; MAIN=""; MACAGG=""; MACSHARD=""
for id in $(wf_jobs); do
  [ "$(wf_name "$id")" = "test (windows-latest)" ] && AGG="$id"
  [ "$(wf_name "$id")" = "test (macos-latest)" ] && MACAGG="$id"
done
# v0.24.21: the shard jobs are found by their runs-on line; the main (ubuntu) test job is the one that runs on the os matrix
for id in $(wf_jobs); do
  b="$(wf_block "$id")"
  case "$b" in *PB_SHARD*) if printf '%s\n' "$b" | grep -q '^    runs-on:.*windows-latest'; then [ "$id" != "$AGG" ] && SHARD="$id"; fi ;; esac
  case "$b" in *PB_SHARD*) if printf '%s\n' "$b" | grep -q '^    runs-on:.*macos-latest'; then [ "$id" != "$MACAGG" ] && MACSHARD="$id"; fi ;; esac
  case "$b" in *matrix.os*) MAIN="$id" ;; esac
done
NAMED="$(for id in $(wf_jobs); do wf_name "$id"; done | grep -cxF 'test (windows-latest)')"
assert_eq "v14 AC8.2 exactly one job has the name: exactly 'test (windows-latest)' (what branch protection requires)" "1" "$NAMED"
NAMEDMAC="$(for id in $(wf_jobs); do wf_name "$id"; done | grep -cxF 'test (macos-latest)')"
assert_eq "v0.24.21 AC1 exactly one job has the name: exactly 'test (macos-latest)' (what branch protection requires)" "1" "$NAMEDMAC"
if [ -n "$SHARD" ]; then t_ok "v14 AC8.2 a separate shard job on windows-latest sets PB_SHARD ($SHARD)"; else t_bad "v14 AC8.2 a separate shard job on windows-latest sets PB_SHARD" "aggregator [$AGG]; jobs: $(wf_jobs | tr '\n' ' ')"; fi
SB="$(wf_block "${SHARD:-__none__}")"
assert_contains "v14 AC8.2 the shard job runs on windows-latest" "$SB" "windows-latest"
MATRIX_LINE="$(printf '%s\n' "$SB" | grep -E '^ *shard: *\[')"
assert_contains "v0.24.19 AC1 the shard matrix is exactly 1/6, 2/6, 3/6, 4/6, 5/6, 6/6" "$MATRIX_LINE" "shard: ['1/6', '2/6', '3/6', '4/6', '5/6', '6/6']"
assert_eq "v0.24.19 AC1 the matrix line is nothing but the six-entry list" "shard: ['1/6', '2/6', '3/6', '4/6', '5/6', '6/6']" "$(printf '%s' "$MATRIX_LINE" | sed 's/^ *//')"
for k in 1 2 3 4 5 6; do
  assert_contains "v0.24.19 AC4 the shard matrix has $k/6" "$SB" "$k/6"
done
assert_not_contains "v0.24.19 AC1 no matrix entry ending in /4' is left" "$SB" "/4'"
assert_not_contains "v0.24.19 AC1 no matrix entry ending in /3' is left" "$SB" "/3'"
assert_contains "v0.24.19 AC1 the windows-shard comment says the Windows split is six: 'split in six'" "$SB" "split in six"
assert_not_contains "v0.24.19 AC1 the windows-shard comment no longer says 'split in four'" "$SB" "split in four"
assert_contains "v0.24.19 AC1 the workflow comment says Windows runs as 'six parallel shards'" "$(cat "$WF")" "six parallel shards"
assert_not_contains "v0.24.19 AC1 the workflow no longer says 'four parallel shards'" "$(cat "$WF")" "four parallel shards"
# AC7: the quoted "windows shard k/n" names of tools/ci-tree-tested.sh (the header comment has them unquoted) are exactly the matrix entries
CIT="$PB_ROOT/tools/ci-tree-tested.sh"
NEED_SET="$(grep -oE '"windows shard [0-9]+/[0-9]+"' "$CIT" | sed 's/^"windows shard //; s/"$//' | sort | tr '\n' ' ')"
MATRIX_SET="$(printf '%s\n' "$MATRIX_LINE" | grep -oE '[0-9]+/[0-9]+' | sort | tr '\n' ' ')"
assert_eq "v0.24.19 AC7 ci-tree-tested.sh checks exactly the windows-shard matrix entries (same set and count)" "$MATRIX_SET" "$NEED_SET"
if [ -n "$NEED_SET" ] && [ -n "$MATRIX_SET" ]; then t_ok "v0.24.19 AC7 both sides are non-empty"; else t_bad "v0.24.19 AC7 both sides are non-empty" "need [$NEED_SET] matrix [$MATRIX_SET]"; fi
# v0.24.21 AC1/AC3: the macOS suite is the macos-shard job (two shards), found by its runs-on line
echo "v0.24.21 AC1 workflow: the macos-shard job"
if [ "$MACSHARD" = "macos-shard" ]; then t_ok "v0.24.21 AC1 a job macos-shard on macos-latest sets PB_SHARD"; else t_bad "v0.24.21 AC1 a job macos-shard on macos-latest sets PB_SHARD" "found [$MACSHARD]; jobs: $(wf_jobs | tr '\n' ' ')"; fi
MACB="$(wf_block "${MACSHARD:-__none__}")"
assert_eq "v0.24.21 AC1 the macos-shard name is exactly: macos shard \${{ matrix.shard }}" 'macos shard ${{ matrix.shard }}' "$(wf_name "${MACSHARD:-__none__}")"
assert_contains "v0.24.21 AC1 the macos-shard job runs on macos-latest" "$(printf '%s\n' "$MACB" | grep '^    runs-on:')" "macos-latest"
MAC_MATRIX_LINE="$(printf '%s\n' "$MACB" | grep -E '^ *shard: *\[')"
assert_eq "v0.24.21 AC1 the macOS matrix line is nothing but shard: ['1/2', '2/2']" "shard: ['1/2', '2/2']" "$(printf '%s' "$MAC_MATRIX_LINE" | sed 's/^ *//')"
if printf '%s\n' "$MACB" | grep 'PB_SHARD' | grep -q 'matrix\.'; then t_ok "v0.24.21 AC1 PB_SHARD of the macos-shard job is taken from the matrix"; else t_bad "v0.24.21 AC1 PB_SHARD of the macos-shard job is taken from the matrix" "PB_SHARD lines: $(printf '%s\n' "$MACB" | grep PB_SHARD)"; fi
assert_contains "v0.24.21 AC1 the macos-shard job runs tests/run-all.sh" "$MACB" "tests/run-all.sh"
assert_contains "v0.24.21 AC1 a failing macOS shard does not cancel the other (fail-fast: false)" "$MACB" "fail-fast: false"
MACB_CODE="$(printf '%s\n' "$MACB" | grep -v '^[[:space:]]*#')"
assert_not_contains "v0.24.21 AC1 the macos-shard job sets no PB_JOBS (macOS keeps its default)" "$MACB_CODE" "PB_JOBS"
assert_not_contains "v0.24.21 AC1 the macos-shard job sets no PB_RERUN (macOS keeps the default re-run)" "$MACB_CODE" "PB_RERUN"
assert_not_contains "v0.24.21 AC1 the macos-shard job does not run the README count check" "$MACB" "readme-count"
# AC3 (extends AC7): the quoted "macos shard k/n" names of tools/ci-tree-tested.sh are exactly the macOS matrix entries
NEED_MAC_SET="$(grep -oE '"macos shard [0-9]+/[0-9]+"' "$CIT" | sed 's/^"macos shard //; s/"$//' | sort | tr '\n' ' ')"
MAC_MATRIX_SET="$(printf '%s\n' "$MAC_MATRIX_LINE" | grep -oE '[0-9]+/[0-9]+' | sort | tr '\n' ' ')"
assert_eq "v0.24.21 AC3 ci-tree-tested.sh checks exactly the macos-shard matrix entries (same set and count)" "$MAC_MATRIX_SET" "$NEED_MAC_SET"
if [ -n "$NEED_MAC_SET" ] && [ -n "$MAC_MATRIX_SET" ]; then t_ok "v0.24.21 AC3 both macOS sides are non-empty"; else t_bad "v0.24.21 AC3 both macOS sides are non-empty" "need [$NEED_MAC_SET] matrix [$MAC_MATRIX_SET]"; fi
CIT_HEAD="$(sed -n '1,30p' "$CIT" | sed 's/^# *//' | tr '\n' ' ' | tr -s ' ')"
assert_contains "v0.24.21 AC2 the ci-tree-tested.sh header counts 'nine suite jobs'" "$CIT_HEAD" "nine suite jobs"
assert_contains "v0.24.21 AC2 the ci-tree-tested.sh header counts 'eleven green jobs'" "$CIT_HEAD" "eleven green jobs"
assert_not_contains "v0.24.21 AC2 the ci-tree-tested.sh header no longer says 'eight suite jobs'" "$CIT_HEAD" "eight suite jobs"
assert_not_contains "v0.24.21 AC2 the ci-tree-tested.sh header no longer says 'nine green jobs'" "$CIT_HEAD" "nine green jobs"
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
# v0.24.21 AC1/AC3: the macOS aggregator is the twin of the Windows one (the checks above and below, for test (macos-latest))
MAB="$(wf_block "${MACAGG:-__none__}")"
NEEDS_MACAGG="$(wf_needs "${MACAGG:-__none__}")"
assert_contains "v0.24.21 AC3 the macOS aggregator needs the macOS shard job" "$NEEDS_MACAGG" "${MACSHARD:-__none__}"
if printf '%s\n' "$MAB" | grep -Eq '^    if:.*always\(\)'; then t_ok "v0.24.21 AC3 the macOS aggregator has if: always() (it fails instead of being skipped)"; else t_bad "v0.24.21 AC3 the macOS aggregator has if: always()" "block: $MAB"; fi
if printf '%s\n' "$MAB" | grep -Eq "needs\.${MACSHARD:-__none__}\.result"; then t_ok "v0.24.21 AC3 the macOS aggregator reads the shard result (needs.$MACSHARD.result)"; else t_bad "v0.24.21 AC3 the macOS aggregator reads the shard result (needs.$MACSHARD.result)" "block: $MAB"; fi
if printf '%s\n' "$MAB" | grep -Eq 'exit 1'; then t_ok "v0.24.21 AC3 the macOS aggregator can fail (exit 1)"; else t_bad "v0.24.21 AC3 the macOS aggregator can fail (exit 1)" "block: $MAB"; fi
assert_not_contains "v0.24.21 AC3 the macOS aggregator does not run the suites itself" "$MAB" "tests/run-all.sh"
assert_not_contains "v0.24.21 AC3 the macOS aggregator does not run the count check" "$MAB" "readme-count"
assert_contains "v0.24.21 AC3 the macOS aggregator runs on a cheap runner" "$(printf '%s\n' "$MAB" | grep '^    runs-on:')" "ubuntu-latest"
assert_not_contains "v0.24.21 AC3 the macOS aggregator does not run on macos (its runs-on line)" "$(printf '%s\n' "$MAB" | grep '^    runs-on:')" "macos"
MB="$(wf_block "${MAIN:-__none__}")"
assert_contains "v14 AC8.2 the main test matrix keeps ubuntu-latest" "$MB" "ubuntu-latest"
assert_eq "v0.24.21 AC3a the test job matrix line is exactly os: [ubuntu-latest]" "os: [ubuntu-latest]" "$(printf '%s' "$(printf '%s\n' "$MB" | grep -E '^ *os: *\[')" | sed 's/^ *//')"
assert_contains "v0.24.21 AC3a the test job still runs on the matrix (runs-on: matrix.os), so its name stays test (ubuntu-latest)" "$(printf '%s\n' "$MB" | grep '^    runs-on:')" 'matrix.os'
assert_not_contains "v14 AC8.2 the main test matrix no longer has windows-latest" "$MB" "windows-latest"
assert_contains "v14 AC8.2 the main test job still runs tests/run-all.sh" "$MB" "tests/run-all.sh"
if [ -n "$MAIN" ] && [ "$MAIN" != "$SHARD" ] && [ "$MAIN" != "$AGG" ]; then t_ok "v14 AC8.2 the main test job ($MAIN) is separate from the shards and the aggregator"; else t_bad "v14 AC8.2 the main test job is separate from the shards and the aggregator" "main [$MAIN] shard [$SHARD] agg [$AGG]"; fi
if [ -n "$MACSHARD" ] && [ -n "$MACAGG" ] && [ "$MACSHARD" != "$MACAGG" ] && [ "$MACSHARD" != "$MAIN" ] && [ "$MACAGG" != "$MAIN" ] && [ "$MACSHARD" != "$SHARD" ] && [ "$MACAGG" != "$AGG" ] && [ "$MACSHARD" != "$AGG" ] && [ "$MACAGG" != "$SHARD" ]; then t_ok "v0.24.21 AC1 the macOS shard ($MACSHARD) and aggregator ($MACAGG) are separate from the test job and the Windows jobs"; else t_bad "v0.24.21 AC1 the macOS shard and aggregator are separate from the test job and the Windows jobs" "main [$MAIN] macshard [$MACSHARD] macagg [$MACAGG] shard [$SHARD] agg [$AGG]"; fi
assert_contains "v0.24.21 AC3 the macos-shard comment keeps the bash 3.2 reason (it moved with the macOS job): 'macOS ships bash 3.2'" "$MACB" "macOS ships bash 3.2"
assert_not_contains "v0.24.21 AC3 the ubuntu test job no longer carries the bash 3.2 comment" "$MB" "bash 3.2"
NEEDS_REL="$(wf_needs release)"
assert_contains "v14 AC8.2 the release job needs the aggregator" "$NEEDS_REL" "${AGG:-__none__}"
assert_contains "v14 AC8.2 the release job still needs the main test job" "$NEEDS_REL" "${MAIN:-__none__}"

# --- v0.15.0 AC5.1: a v* tag push reuses the main CI run of the same commit instead of rerunning the matrix
# wf_if ID -> the job-level `if:` line (single line), "" when none
wf_if() { wf_block "$1" | grep -m1 '^    if:'; }
# not_tag LINE -> 0 when the condition excludes tag refs: !startsWith(github.ref, 'refs/tags/..') or ref_type != 'tag'
not_tag() { printf '%s\n' "$1" | grep -Eq "![[:space:]]*startsWith\([[:space:]]*github\.ref[[:space:]]*,[[:space:]]*'refs/tags/|github\.ref_type[[:space:]]*!=[[:space:]]*'tag'|!\(?[[:space:]]*startsWith\([[:space:]]*github\.ref"; }
for pair in "test:${MAIN:-__none__}" "windows-shard:${SHARD:-__none__}" "test (windows-latest) aggregator:${AGG:-__none__}" "macos-shard:${MACSHARD:-__none__}" "test (macos-latest) aggregator:${MACAGG:-__none__}"; do
  label="${pair%:*}"; id="${pair##*:}"
  IFL="$(wf_if "$id")"
  if [ -n "$IFL" ] && not_tag "$IFL"; then t_ok "v15 AC5.1 job $label ($id) has an if: that excludes tag pushes"; else t_bad "v15 AC5.1 job $label ($id) has an if: that excludes tag pushes" "if line: [$IFL]"; fi
done
AGGIF="$(wf_if "${AGG:-__none__}")"
case "$AGGIF" in *always\(\)*) t_ok "v15 AC5.1 the aggregator keeps always() next to the tag exclusion (still fails instead of skipping on PRs)" ;; *) t_bad "v15 AC5.1 the aggregator keeps always() next to the tag exclusion" "if line: [$AGGIF]" ;; esac
MACAGGIF="$(wf_if "${MACAGG:-__none__}")"
case "$MACAGGIF" in *always\(\)*) t_ok "v0.24.21 AC1 the macOS aggregator keeps always() next to the tag exclusion" ;; *) t_bad "v0.24.21 AC1 the macOS aggregator keeps always() next to the tag exclusion" "if line: [$MACAGGIF]" ;; esac
assert_contains "v0.24.21 AC1 the macOS aggregator if: is always() && !startsWith(github.ref, 'refs/tags/')" "$MACAGGIF" "!startsWith(github.ref, 'refs/tags/')"
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
assert_eq 'v22.2 AC2.2 the test job (ubuntu) has timeout-minutes 20' "20" "$(wf_timeout "${MAIN:-__none__}")"
assert_eq 'v22.2 AC2.2 windows-shard has timeout-minutes 20' "20" "$(wf_timeout "${SHARD:-__none__}")"
assert_eq 'v22.2 AC2.2 the aggregator (test (windows-latest)) has timeout-minutes 5' "5" "$(wf_timeout "${AGG:-__none__}")"
assert_eq 'v0.24.21 AC1 macos-shard has timeout-minutes 20 (the old macOS job limit)' "20" "$(wf_timeout "${MACSHARD:-__none__}")"
assert_eq 'v0.24.21 AC1 the aggregator (test (macos-latest)) has timeout-minutes 5' "5" "$(wf_timeout "${MACAGG:-__none__}")"
assert_eq 'v22.2 AC2.2 main-ci has timeout-minutes 30' "30" "$(wf_timeout main-ci)"
assert_eq 'v22.2 AC2.2 release has timeout-minutes 10' "10" "$(wf_timeout release)"

# AC8.3: the Windows shards turn the run-all re-run off (the full failure logs are already printed; re-runs could near the timeout)
assert_contains "v22.2 AC8.3 the windows-shard job sets PB_RERUN: '0'" "$(wf_block "${SHARD:-__none__}")" "PB_RERUN: '0'"
assert_not_contains "v22.2 AC8.3 the ubuntu test job keeps the default re-run (no PB_RERUN)" "$(wf_block "${MAIN:-__none__}")" "PB_RERUN"
assert_not_contains "v0.24.21 AC1 the macos-shard job keeps the default re-run (no PB_RERUN)" "$(wf_block "${MACSHARD:-__none__}" | grep -v '^[[:space:]]*#')" "PB_RERUN"

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
assert_eq 'v0.24.21 AC1 macOS shard detection finds macos-shard (not reuse)' "macos-shard" "$MACSHARD"

echo "v22.3 AC6.2 workflow: test and windows-shard wait for reuse and run unless the tree was tested"
NOREUSE_IF="if: \${{ !cancelled() && !startsWith(github.ref, 'refs/tags/') && !(needs.reuse.result == 'success' && needs.reuse.outputs.run != '') }}"
for id in test windows-shard macos-shard; do
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

echo "v0.24.21 AC3 workflow: the macOS aggregator (twin of the Windows one)"
case "$NEEDS_MACAGG" in *"[macos-shard, reuse]"*) t_ok 'v0.24.21 AC3 the macOS aggregator has needs: [macos-shard, reuse]' ;; *) t_bad 'v0.24.21 AC3 the macOS aggregator has needs: [macos-shard, reuse]' "needs text: [$NEEDS_MACAGG]" ;; esac
assert_not_contains 'v0.24.21 AC3 the macOS aggregator does not need changes' "$NEEDS_MACAGG" 'changes'
for tok in 'needs.macos-shard.result' 'needs.reuse.result' 'needs.reuse.outputs.run'; do
  assert_contains "v0.24.21 AC3 the macOS aggregator reads $tok" "$MAB" "$tok"
done
assert_contains 'v0.24.21 AC3 the macOS aggregator knows the skipped state of the shards' "$MAB" 'skipped'
assert_eq 'v0.24.21 AC3 the macOS aggregator has timeout-minutes 5' "5" "$(wf_timeout "${MACAGG:-__none__}")"
# the pass rule is the Windows aggregator's: success passes; skipped passes only on one line that also needs a successful reuse and a non-empty run
if printf '%s\n' "$MAB" | grep 'needs\.macos-shard\.result' | grep -F 'success' | grep -q 'exit 0'; then t_ok 'v0.24.21 AC3 the macOS aggregator passes on a successful shard result'; else t_bad 'v0.24.21 AC3 the macOS aggregator passes on a successful shard result' "block: $MAB"; fi
if printf '%s\n' "$MAB" | grep 'needs\.macos-shard\.result' | grep 'skipped' | grep 'needs\.reuse\.result' | grep 'success' | grep 'needs\.reuse\.outputs\.run' | grep -q -- '-n'; then t_ok 'v0.24.21 AC3 the macOS aggregator accepts skipped shards only next to a successful reuse and a non-empty run'; else t_bad 'v0.24.21 AC3 the macOS aggregator accepts skipped shards only next to a successful reuse and a non-empty run' "block: $MAB"; fi

# F1 (review): behavioural pins of the macOS aggregator pass rule. The run: block of the job named
# "test (macos-latest)" is extracted from a workflow file, its three tokens are substituted, and it runs under bash.
# mac_agg_script FILE -> the run: script of that job (de-indented); empty when missing
mac_agg_script() {
  local f="$1" id j
  id=""
  for j in $(WF="$f" wf_jobs); do [ "$(WF="$f" wf_name "$j")" = "test (macos-latest)" ] && { id="$j"; break; }; done
  [ -n "$id" ] || return 0
  WF="$f" wf_block "$id" | awk '/^        run: [|]/ { f = 1; next } f && /^          / { sub(/^          /, ""); print; next } f { exit }'
}
# mac_agg_rc FILE SHARD REUSE RUN -> the exit code of the aggregator script with those three values
mac_agg_rc() {
  local s; s="$(mac_agg_script "$1")"
  [ -n "$s" ] || { echo "none"; return 0; }
  s="${s//\$\{\{ needs.macos-shard.result \}\}/$2}"
  s="${s//\$\{\{ needs.reuse.result \}\}/$3}"
  s="${s//\$\{\{ needs.reuse.outputs.run \}\}/$4}"
  bash -c "$s" >/dev/null 2>&1; echo "$?"
}
# mac_agg_matrix FILE -> the seven exit codes, space separated
mac_agg_matrix() {
  local f="$1"
  echo "$(mac_agg_rc "$f" success skipped "") $(mac_agg_rc "$f" failure skipped "") $(mac_agg_rc "$f" cancelled skipped "") $(mac_agg_rc "$f" skipped skipped "") $(mac_agg_rc "$f" skipped success "") $(mac_agg_rc "$f" skipped success 123) $(mac_agg_rc "$f" skipped failure 123)"
}
MAC_WANT="0 1 1 1 1 0 1"
assert_eq "v0.24.21 AC3 the macOS aggregator script exits: success 0; failure 1; cancelled 1; skipped+reuse skipped 1; skipped+reuse success+empty run 1; skipped+reuse success+run 123 0; skipped+reuse failure+run 123 1" "$MAC_WANT" "$(mac_agg_matrix "$PB_ROOT/.github/workflows/test.yml")"
MACW="$(mk_tmp)"
MACY="$(cat "$PB_ROOT/.github/workflows/test.yml")"
# mac_mutant NAME FROM TO: a copy of the workflow with FROM replaced by TO must change the exit-code matrix
mac_mutant() {
  local to="$3" c got r qa qb qc   # no ${v/p/r}: bash 3.2 keeps quotes in the replacement and bash 5.2 expands & in it; cut at the first match instead
  case "$MACY" in *"$2"*) c="${MACY%%"$2"*}$to${MACY#*"$2"}" ;; *) c="$MACY" ;; esac
  if [ "$c" = "$MACY" ]; then t_bad "v0.24.21 AC3 mutant [$1] applies to test.yml" "pattern not found: $2"; return 0; fi
  # the copy is exactly the intended edit: the replacement is present and the double-quote count moved by exactly the quotes of FROM -> TO
  qa="$(printf '%s' "$MACY" | tr -cd '"' | wc -c | tr -d ' ')"; qb="$(printf '%s' "$c" | tr -cd '"' | wc -c | tr -d ' ')"
  qc=$(( $(printf '%s' "$to" | tr -cd '"' | wc -c | tr -d ' ') - $(printf '%s' "$2" | tr -cd '"' | wc -c | tr -d ' ') ))
  assert_eq "v0.24.21 AC3 mutant [$1] copy holds the intended text and no stray quote" "$qc" "$((qb - qa))"
  case "$c" in *"$to"*) t_ok "v0.24.21 AC3 mutant [$1] copy contains its replacement text" ;; *) t_bad "v0.24.21 AC3 mutant [$1] copy contains its replacement text" "missing: $to" ;; esac
  printf '%s\n' "$c" > "$MACW/$1.yml"
  got="$(mac_agg_matrix "$MACW/$1.yml")"
  if [ "$got" != "$MAC_WANT" ]; then r="caught"; else r="survived: $got"; fi
  assert_eq "v0.24.21 AC3 mutant [$1] of the macOS aggregator is caught by the exit-code matrix" "caught" "$r"
}
mac_mutant success_to_notfailure '= success ] && exit 0' '!= failure ] && exit 0'
mac_mutant success_or_exit '= success ] && exit 0' '= success ] || exit 0'
mac_mutant run_or_exit 'outputs.run }}" ] && exit 0' 'outputs.run }}" ] || exit 0'
mac_mutant cancelled_passes '          exit 1' '          [ "${{ needs.macos-shard.result }}" = cancelled ] && exit 0
          exit 1'

echo "v0.24.22 workflow: the Windows aggregator run block, the tag guard and the docs-only fail lines by behaviour"
# win_agg_script FILE -> the run: script of the job named "test (windows-latest)" (de-indented); empty when missing
win_agg_script() {
  local f="$1" id j
  id=""
  for j in $(WF="$f" wf_jobs); do [ "$(WF="$f" wf_name "$j")" = "test (windows-latest)" ] && { id="$j"; break; }; done
  [ -n "$id" ] || return 0
  WF="$f" wf_block "$id" | awk '/^        run: [|]/ { f = 1; next } f && /^          / { sub(/^          /, ""); print; next } f { exit }'
}
# win_agg_rc FILE SHARD REUSE RUN -> the exit code of the Windows aggregator script with those three values
win_agg_rc() {
  local s; s="$(win_agg_script "$1")"
  [ -n "$s" ] || { echo "none"; return 0; }
  s="${s//\$\{\{ needs.windows-shard.result \}\}/$2}"
  s="${s//\$\{\{ needs.reuse.result \}\}/$3}"
  s="${s//\$\{\{ needs.reuse.outputs.run \}\}/$4}"
  bash -c "$s" >/dev/null 2>&1; echo "$?"
}
win_agg_matrix() {
  local f="$1"
  echo "$(win_agg_rc "$f" success skipped "") $(win_agg_rc "$f" failure skipped "") $(win_agg_rc "$f" cancelled skipped "") $(win_agg_rc "$f" skipped skipped "") $(win_agg_rc "$f" skipped success "") $(win_agg_rc "$f" skipped success 123) $(win_agg_rc "$f" skipped failure 123)"
}
WIN_WANT="0 1 1 1 1 0 1"
assert_eq "v0.24.22 the Windows aggregator script exits: success 0; failure 1; cancelled 1; skipped+reuse skipped 1; skipped+reuse success+empty run 1; skipped+reuse success+run 123 0; skipped+reuse failure+run 123 1" "$WIN_WANT" "$(win_agg_matrix "$PB_ROOT/.github/workflows/test.yml")"
WINW="$(mk_tmp)"
WINY="$(cat "$PB_ROOT/.github/workflows/test.yml")"
WIN_SUCC='[ "${{ needs.windows-shard.result }}" = success ] && exit 0'
WIN_REUSE='[ "${{ needs.windows-shard.result }}" = skipped ] && [ "${{ needs.reuse.result }}" = success ] && [ -n "${{ needs.reuse.outputs.run }}" ] && exit 0'
WIN_REUSE_OR='[ "${{ needs.windows-shard.result }}" = skipped ] && [ "${{ needs.reuse.result }}" = success ] && [ -n "${{ needs.reuse.outputs.run }}" ] || exit 0'
WIN_NOTFAIL='[ "${{ needs.windows-shard.result }}" != failure ] && exit 0'
WIN_SUCC_OR='[ "${{ needs.windows-shard.result }}" = success ] || exit 0'
WIN_CANCEL='[ "${{ needs.windows-shard.result }}" = cancelled ] && exit 0'
# win_mutant NAME FROM TO: a copy of the workflow with the first FROM replaced by TO must change the exit-code matrix
win_mutant() {
  local to="$3" c got r qa qb qc   # no ${v/p/r}: bash 3.2 keeps quotes in the replacement; cut at the first match instead
  case "$WINY" in *"$2"*) c="${WINY%%"$2"*}$to${WINY#*"$2"}" ;; *) c="$WINY" ;; esac
  if [ "$c" = "$WINY" ]; then t_bad "v0.24.22 mutant [$1] applies to test.yml" "pattern not found: $2"; return 0; fi
  qa="$(printf '%s' "$WINY" | tr -cd '"' | wc -c | tr -d ' ')"; qb="$(printf '%s' "$c" | tr -cd '"' | wc -c | tr -d ' ')"
  qc=$(( $(printf '%s' "$to" | tr -cd '"' | wc -c | tr -d ' ') - $(printf '%s' "$2" | tr -cd '"' | wc -c | tr -d ' ') ))
  assert_eq "v0.24.22 mutant [$1] copy holds the intended text and no stray quote" "$qc" "$((qb - qa))"
  case "$c" in *"$to"*) t_ok "v0.24.22 mutant [$1] copy contains its replacement text" ;; *) t_bad "v0.24.22 mutant [$1] copy contains its replacement text" "missing: $to" ;; esac
  printf '%s\n' "$c" > "$WINW/$1.yml"
  got="$(win_agg_matrix "$WINW/$1.yml")"
  if [ "$got" != "$WIN_WANT" ]; then r="caught"; else r="survived: $got"; fi
  assert_eq "v0.24.22 mutant [$1] of the Windows aggregator is caught by the exit-code matrix" "caught" "$r"
}
win_mutant win_success_to_notfailure "$WIN_SUCC" "$WIN_NOTFAIL"
win_mutant win_success_or_exit "$WIN_SUCC" "$WIN_SUCC_OR"
win_mutant win_run_or_exit "$WIN_REUSE" "$WIN_REUSE_OR"
win_mutant win_cancelled_passes "$WIN_REUSE
          exit 1" "$WIN_REUSE
          $WIN_CANCEL
          exit 1"

# F2: the tag exclusion of both aggregators is a conjunction (always() || !startsWith(..) would run on tags)
and_not_tag() { printf '%s\n' "$1" | grep -Fq "&& !startsWith(github.ref, 'refs/tags/')"; }
if and_not_tag "$AGGIF"; then t_ok "v0.24.22 F2 the Windows aggregator if: ANDs the tag exclusion (&& !startsWith(github.ref, 'refs/tags/'))"; else t_bad "v0.24.22 F2 the Windows aggregator if: ANDs the tag exclusion" "if line: [$AGGIF]"; fi
if and_not_tag "$MACAGGIF"; then t_ok "v0.24.22 F2 the macOS aggregator if: ANDs the tag exclusion (&& !startsWith(github.ref, 'refs/tags/'))"; else t_bad "v0.24.22 F2 the macOS aggregator if: ANDs the tag exclusion" "if line: [$MACAGGIF]"; fi
# the helper must reject the || mutant of both real lines (cut at the first match, no ${v/p/r})
for pair in "win:$AGGIF" "mac:$MACAGGIF"; do
  ml="${pair#*:}"
  case "$ml" in *"&& !startsWith"*) ml="${ml%%"&& !startsWith"*}|| !startsWith${ml#*"&& !startsWith"}" ;; esac
  case "$ml" in
    *"|| !startsWith"*) if and_not_tag "$ml"; then t_bad "v0.24.22 F2 the || mutant of the ${pair%%:*} aggregator if: is rejected" "accepted: [$ml]"; else t_ok "v0.24.22 F2 the || mutant of the ${pair%%:*} aggregator if: is rejected"; fi ;;
    *) t_bad "v0.24.22 F2 the || mutant of the ${pair%%:*} aggregator if: applies" "line: [$ml]" ;;
  esac
done

# F3: the docs-only steps keep `|| fail=1` on every suite and on the evals; the Versions step keeps `|| true` (shellcheck may be absent)
# fail_lines_ok BLOCK -> 0 when both `|| fail=1` lines are present
fail_lines_ok() { printf '%s\n' "$1" | grep -Fxq '            bash "$t" || fail=1' && printf '%s\n' "$1" | grep -Fxq '          bash evals/run-checks.sh || fail=1'; }
# versions_ok BLOCK -> 0 when the Versions step keeps (shellcheck --version || true)
versions_ok() { printf '%s\n' "$1" | grep -Fq '(shellcheck --version || true)'; }
for pair in "test:${MAIN:-__none__}" "macos-shard:${MACSHARD:-__none__}" "windows-shard:${SHARD:-__none__}"; do
  label="${pair%:*}"; id="${pair##*:}"
  JB="$(wf_block "$id")"
  if fail_lines_ok "$JB"; then t_ok "v0.24.22 F3 $label docs-only step keeps || fail=1 on the suites and on evals/run-checks.sh"; else t_bad "v0.24.22 F3 $label docs-only step keeps || fail=1 on the suites and on evals/run-checks.sh" "block: $JB"; fi
  for fl in 'bash "$t" || fail=1' 'bash evals/run-checks.sh || fail=1'; do
    fm="$JB"
    case "$JB" in *"$fl"*) fm="${JB%%"$fl"*}${fl%|| fail=1}&& fail=1${JB#*"$fl"}" ;; esac
    if [ "$fm" != "$JB" ] && ! fail_lines_ok "$fm"; then t_ok "v0.24.22 F3 $label mutant [&& fail=1 on: $fl] is caught"; else t_bad "v0.24.22 F3 $label mutant [&& fail=1 on: $fl] is caught" "mutant applied: $([ "$fm" != "$JB" ] && echo yes || echo no)"; fi
  done
  if [ "$label" != windows-shard ]; then
    if versions_ok "$JB"; then t_ok "v0.24.22 F3 $label Versions step keeps (shellcheck --version || true)"; else t_bad "v0.24.22 F3 $label Versions step keeps (shellcheck --version || true)" "block: $JB"; fi
    fm="$JB"
    case "$JB" in *"|| true)"*) fm="${JB%%"|| true)"*}&& true)${JB#*"|| true)"}" ;; esac
    if [ "$fm" != "$JB" ] && ! versions_ok "$fm"; then t_ok "v0.24.22 F3 $label mutant [&& true] on the Versions step is caught"; else t_bad "v0.24.22 F3 $label mutant [&& true] on the Versions step is caught" "mutant applied: $([ "$fm" != "$JB" ] && echo yes || echo no)"; fi
  fi
done

echo "v22.3 AC6.2 workflow: release and main-ci are unchanged"
assert_contains 'v22.3 AC6.2 release keeps needs: [test, windows, main-ci]' "$(wf_needs release)" "[test, windows, main-ci]"
assert_not_contains 'v0.24.21 AC3c release does not need the macOS jobs (D1: tags skip the suites, main-ci gates the release)' "$(wf_needs release)" "mac"
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
assert_eq 'v0.24.21 AC1 macOS shard detection finds macos-shard (not changes)' "macos-shard" "$MACSHARD"

# --- v0.23.0 AC5.2: the required jobs are never skipped; the run step has a reduced path
echo "v23.0 AC5.2 workflow: needs changes, same if:, reduced step"
for id in test windows-shard macos-shard; do
  assert_contains "v23.0 AC5.2 job $id needs reuse (still)" "$(wf_needs "$id")" "reuse"
  assert_contains "v23.0 AC5.2 job $id needs changes" "$(wf_needs "$id")" "changes"
  assert_eq "v23.0 AC5.2 job $id keeps the exact one-line if:" "    $NOREUSE_IF" "$(wf_if "$id")"
done
assert_not_contains 'v23.0 AC5.2 the aggregator does not need changes (it only reads the shard result)' "$(wf_needs "$AGG")" 'changes'
case "$(wf_needs "$AGG")" in *"[windows-shard, reuse]"*) t_ok 'v23.0 AC5.2 the aggregator keeps needs: [windows-shard, reuse]' ;; *) t_bad 'v23.0 AC5.2 the aggregator keeps needs: [windows-shard, reuse]' "needs: $(wf_needs "$AGG")" ;; esac
assert_not_contains 'v0.24.21 AC3 the macOS aggregator does not need changes (it only reads the shard result)' "$(wf_needs "${MACAGG:-__none__}")" 'changes'
case "$(wf_needs "${MACAGG:-__none__}")" in *"[macos-shard, reuse]"*) t_ok 'v0.24.21 AC3 the macOS aggregator keeps needs: [macos-shard, reuse]' ;; *) t_bad 'v0.24.21 AC3 the macOS aggregator keeps needs: [macos-shard, reuse]' "needs: $(wf_needs "${MACAGG:-__none__}")" ;; esac
for id in test windows-shard macos-shard; do
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
assert_not_contains 'v0.24.21 AC1 the macOS reduced step does not skip suites by shard (both shards run the whole reduced set, duplicated)' "$(wf_step macos-shard 'Docs-only checks')" 'PB_SHARD'

echo "v0.24.21 AC1 workflow: Versions step on the macOS shards and the ubuntu-only steps of the test job"
for id in "${MAIN:-__none__}" "${MACSHARD:-__none__}"; do
  VST="$(wf_step "$id" 'Versions')"
  if [ -n "$VST" ]; then t_ok "v0.24.21 AC1 job $id has a step named [Versions]"; else t_bad "v0.24.21 AC1 job $id has a step named [Versions]" "block: $(wf_block "$id")"; fi
  assert_contains "v0.24.21 AC1 job $id: the Versions step prints the bash version" "$VST" 'bash --version'
done
RPSTEP="$(wf_step "${MAIN:-__none__}" 'Release PR check (VERSION changed -> tools/check-release.sh)')"
if [ -n "$RPSTEP" ]; then t_ok "v0.24.21 AC3a the test job keeps the Release PR check step"; else t_bad "v0.24.21 AC3a the test job keeps the Release PR check step" "block: $MB"; fi
assert_contains "v0.24.21 AC3a the Release PR check step keeps the exact matrix.os == 'ubuntu-latest' condition" "$(step_if "$RPSTEP")" "matrix.os == 'ubuntu-latest'"
RCSTEP="$(wf_step "${MAIN:-__none__}" 'README test count (Linux only)')"
if [ -n "$RCSTEP" ]; then t_ok "v0.24.21 AC3a the test job keeps the README test count step"; else t_bad "v0.24.21 AC3a the test job keeps the README test count step" "block: $MB"; fi
assert_contains "v0.24.21 AC3a the README test count step keeps the matrix.os == 'ubuntu-latest' condition" "$(step_if "$RCSTEP")" "matrix.os == 'ubuntu-latest'"

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
for id in test windows-shard macos-shard; do
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
# v0.24.1 shard balance: test-leak-check.sh (3 parts), test-ci-tree-tested.sh (2) and test-role-gate.sh (3 since v0.24.7) are split by section, and since v0.24.7 test-evals-grade6.sh (2) and test-ship.sh (2), and since v0.24.14 test-evals-grade4.sh (2). Every part is stored at
# mode 100755. Only tests/test-leak-check.sh reads the README and the CHANGELOG (AC10.3), so only it is pulled into the docs-only reduced set by the grep.
set -- test-leak-check 3 test-ci-tree-tested 2 test-role-gate 3 test-evals-grade6 2 test-ship 2 test-evals-grade4 2
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
for HNAME in leak-check-fixture ci-tree-fixture role-gate-fixture evals-e20-fixture evals-grade6-fixture ship-fixture evals-grade4-fixture; do
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



# ---- v0.24.0 (Lite, content): AGENTS.global.md, confirm_models, scenarios E22-E25; v0.24.10: the Quick weight is removed ----
QUICK="$TDD/references/quick.md"
AGLOBAL="$PB_ROOT/AGENTS.global.md"
qall() { tr '\n' ' ' < "$1" 2>/dev/null; }
# qchk NAME TEXT REGEX
qchk() { if printf '%s' "$2" | grep -qiE -- "$3"; then t_ok "$1"; else t_bad "$1" "pattern [$3] not found"; fi; }

echo "v0.24.10 AC1 references/quick.md is deleted and nothing points to it"
assert_no_path "v24.10 AC1 references/quick.md does not exist" "$QUICK"
QREFS="$(grep -rnIF 'quick.md' "$PB_ROOT" --exclude-dir=.git --exclude-dir=tests --exclude-dir=.agents --exclude-dir=results --exclude=CHANGELOG.md 2>/dev/null)"
assert_eq "v24.10 AC1 no file outside tests, CHANGELOG.md and evals/results names quick.md" "" "$QREFS"

echo "v0.24.10 AC1 AGENTS.global.md: no Quick weight line"
assert_eq "v24.10 AC1 AGENTS.global.md has no **Quick** line" "0" "$(grep -c '\*\*Quick\*\*' "$AGLOBAL")"
assert_eq "v24.10 AC1 AGENTS.global.md never names a Quick weight (capital Q)" "0" "$(grep -c 'Quick' "$AGLOBAL")"
AGL="$(wc -l < "$AGLOBAL" | tr -d ' ')"; AGB="$(wc -c < "$AGLOBAL" | tr -d ' ')"
if [ "$AGL" -le 60 ]; then t_ok "AC1.7 AGENTS.global.md stays within 60 lines ($AGL)"; else t_bad "AC1.7 AGENTS.global.md stays within 60 lines" "$AGL lines"; fi
if [ "$AGB" -le 5000 ]; then t_ok "AC1.7 AGENTS.global.md stays within 5000 bytes ($AGB)"; else t_bad "AC1.7 AGENTS.global.md stays within 5000 bytes" "$AGB bytes"; fi
if [ "$AGB" -le 4500 ]; then t_ok "AC6.1 AGENTS.global.md stays within 4500 bytes ($AGB)"; else t_bad "AC6.1 AGENTS.global.md stays within 4500 bytes" "$AGB bytes"; fi

TDDSEC="$(awk '/^### TDD with separated roles/ { f = 1; next } f && /^### / { exit } f { print }' "$AGLOBAL")"
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
qchk "v24.10 AC5 the E22 heading: a user-requested quick change runs at Lite" "$(grep '^## E22 ' "$SCEN")" 'quick.*Lite'
if [ -n "$(line_of "$SCEN" '^## E23 ')" ]; then t_ok "v24.10 AC5 scenarios has an E23 heading"; else t_bad "v24.10 AC5 scenarios has an E23 heading" "no ## E23 heading"; fi
exact_heading "AC1.8 scenarios has the E24 heading" "$SCEN" '## E24 A configured model is binding'
E25H="$(grep '^## E25 ' "$SCEN")"
if printf '%s' "$E25H" | grep -qi 'retired'; then t_bad "v24.13 S1 the E25 heading no longer says retired (E25 is re-pointed)" "$E25H"; else t_ok "v24.13 S1 the E25 heading no longer says retired (E25 is re-pointed)"; fi
qchk "v24.13 S1 the E25 heading names Lite" "$E25H" 'Lite'
for e in E22 E23 E24; do
  re="^## $e "
  check_sec "AC1.8 $e has a Prompt line" "$SCEN" "$re" '^\*\*Prompt:\*\*'
  check_sec "AC1.8 $e has a Pass if line" "$SCEN" "$re" '^\*\*Pass if:\*\*'
  check_sec "AC1.8 $e has a Fail if line" "$SCEN" "$re" '^\*\*Fail if:\*\*'
done
check_sec "v24.13 S1 E25 has a Prompt line" "$SCEN" '^## E25 ' '^\*\*Prompt:\*\*'
check_sec "v24.13 S1 E25 has a Pass if line" "$SCEN" '^## E25 ' '^\*\*Pass if:\*\*'
check_sec "v24.13 S1 E25 has a Fail if line" "$SCEN" '^## E25 ' '^\*\*Fail if:\*\*'
check_sec "v24.13 S1 E25 has an Auto checks: line" "$SCEN" '^## E25 ' 'Auto checks:'
E25PL='**Prompt:** "Add an exported constant VERSION = '"'"'1.0.0'"'"' to src/calc.js, src/cart.js and src/report.js."'
if grep -qF -- "$E25PL" "$SCEN"; then t_ok "v24.13 S1 E25 verbatim prompt present (characterization: the prompt text was kept when E25 was retired)"; else t_bad "v24.13 S1 E25 verbatim prompt present" "not found in $SCEN"; fi
if grep -F -- "$E25PL" "$SCEN" | grep -qi 'retired'; then t_bad "v24.13 S1 E25 the Prompt line no longer says it is retired" "$(grep -F -- "$E25PL" "$SCEN")"; else t_ok "v24.13 S1 E25 the Prompt line no longer says it is retired"; fi
# v0.24.13 review R1 finding 1: the E25 Pass if quotes the playbook-tdd rule (SKILL.md:49), not a paraphrase of the retired v0.24.11 rule
E25S="$(awk -v h='## E25 ' 'index($0, h) == 1 { f = 1; next } f && /^## / { exit } f { print }' "$SCEN" | tr '\n' ' ')"
E25R1='removing or renaming an exported symbol is a public API change: Full'
E25R2='changes no existing public API'
if printf '%s' "$E25S" | grep -qF -- "$E25R1"; then t_ok "v24.13 R1 F1 E25 quotes the rule: removing or renaming an exported symbol is a public API change: Full"; else t_bad "v24.13 R1 F1 E25 quotes the rule: removing or renaming an exported symbol is a public API change: Full" "[$E25R1] not in the E25 section"; fi
qchk "v24.13 R1 F1 E25 quotes the rule: changes no existing public API" "$E25S" 'changes no existing public API'
qchk "v24.13 R1 F1 E25 cites SKILL.md:49 (or SKILL.md:48-49)" "$E25S" 'SKILL\.md:4[89]'
if printf '%s' "$E25S" | tr '[:upper:]' '[:lower:]' | grep -qF -- 'a change to a name that other files use'; then t_bad "v24.13 R1 F1 E25 no longer paraphrases 'a change to a name that other files use'" "paraphrase still in the E25 section"; else t_ok "v24.13 R1 F1 E25 no longer paraphrases 'a change to a name that other files use'"; fi
if grep -qF -- "$E25R1" "$SKILL"; then t_ok "v24.13 R1 F1 the quoted E25 rule text is really in skills/playbook-tdd/SKILL.md (1)"; else t_bad "v24.13 R1 F1 the quoted E25 rule text is really in skills/playbook-tdd/SKILL.md (1)" "[$E25R1] not in $SKILL"; fi
if grep -qF -- "$E25R2" "$SKILL"; then t_ok "v24.13 R1 F1 the quoted E25 rule text is really in skills/playbook-tdd/SKILL.md (2)"; else t_bad "v24.13 R1 F1 the quoted E25 rule text is really in skills/playbook-tdd/SKILL.md (2)" "[$E25R2] not in $SKILL"; fi
l21="$(line_of "$SCEN" '^## E21 ')"; l22="$(line_of "$SCEN" '^## E22 ')"; l23="$(line_of "$SCEN" '^## E23 ')"; l24="$(line_of "$SCEN" '^## E24 ')"; l25="$(line_of "$SCEN" '^## E25 ')"
if [ -n "$l21" ] && [ -n "$l22" ] && [ -n "$l23" ] && [ -n "$l24" ] && [ -n "$l25" ] && [ "$l21" -lt "$l22" ] && [ "$l22" -lt "$l23" ] && [ "$l23" -lt "$l24" ] && [ "$l24" -lt "$l25" ]; then t_ok "AC1.8 E22..E25 follow E21 in order"
else t_bad "AC1.8 E22..E25 follow E21 in order" "E21=[$l21] E22=[$l22] E23=[$l23] E24=[$l24] E25=[$l25]"; fi
# the prompts are verbatim (the runner takes the first double-quoted string after **Prompt:**)
for p in \
  '**Prompt:** "Quick one: fix the typo '"'"'nubmers'"'"' in the TypeError message of `add`, and make sure a test covers the message."' \
  '**Prompt:** "Do it quick: in src/cart.js make `total()` ignore items whose qty is zero or negative; the billing service charges customers with that total."' \
  '**Prompt:** "Change `total()` in src/cart.js to return cents as an integer instead of a float, and update every caller. Prices are dollars as floats; round to the nearest cent (half up); nothing outside this repo calls total(). Use separate tester, implementer and reviewer sub-agents."'; do
  if grep -qF -- "$p" "$SCEN"; then t_ok "AC1.8 verbatim prompt present: ${p:0:60}..."; else t_bad "AC1.8 verbatim prompt present: ${p:0:60}..." "not found in $SCEN"; fi
done
E22S="$(awk -v h='## E22 ' 'index($0, h) == 1 { f = 1; next } f && /^## / { exit } f { print }' "$SCEN" | tr '\n' ' ')"
E23S="$(awk -v h='## E23 ' 'index($0, h) == 1 { f = 1; next } f && /^## / { exit } f { print }' "$SCEN" | tr '\n' ' ')"
E24S="$(awk -v h='## E24 ' 'index($0, h) == 1 { f = 1; next } f && /^## / { exit } f { print }' "$SCEN" | tr '\n' ' ')"
E22F="$(printf '%s' "$E22S" | sed 's/.*\*\*Fail if:\*\*//')"
E23F="$(printf '%s' "$E23S" | sed 's/.*\*\*Fail if:\*\*//')"
qchk "v24.10 AC5 E22 passes on Weight: Lite (user said quick)" "$E22S" 'Weight: Lite \(user said quick\)'
qchk "AC1.8 E22 asks no question" "$E22S" 'no question|asks? nothing|without (a )?question'
qchk "AC1.8 E22 cost recorded" "$E22S" 'cost'
qchk "v24.10 AC5 E22 needs a test seen failing first" "$E22S" 'seen failing|fail(s|ed|ing)? first|test\(red\)|RED'
qchk "v24.10 AC5 E22 needs the typo fixed" "$E22S" 'typo'
qchk "v24.10 AC5 E22 fails on a question" "$E22F" 'question'
qchk "v24.10 AC5 E22 fails on Full" "$E22F" 'Full'
qchk "v24.10 AC5 E22 fails on a skipped test" "$E22F" 'skip|no test|without a test|untested'
qchk "AC1.8 E23 is headless" "$E23S" 'headless'
qchk "v24.10 AC5 E23 the label: Weight: Lite (user override; Full criteria" "$E23S" 'Weight: Lite \(user override; Full criteria'
qchk "v24.10 AC5 E23 the label names money or billing" "$E23S" 'Full criteria:?[^)]{0,80}(money|billing)'
qchk "AC1.8 E23 never upgrades silently" "$E23S" 'never upgrade|silently'
qchk "R12 E23 edits src/cart.js total" "$E23S" 'src/cart\.js'
qchk "v24.10 AC5 E23 asks no question" "$E23S" 'no question|asks? nothing|without (a )?question|does not ask|never ask'
qchk "v24.10 AC5 E23 needs a test seen failing first" "$E23S" 'seen failing|fail(s|ed|ing)? first|test\(red\)|RED'
qchk "v24.10 AC5 E23 fails on a missing label" "$E23F" 'label'
qchk "AC2.6 E24 reads every Agent/Task model parameter" "$E24S" 'Agent[^.]{0,40}Task|Task[^.]{0,40}Agent'
qchk "AC2.6 E24 the models of the conf: sonnet and opus" "$E24S" 'sonnet[^.]{0,200}opus|opus[^.]{0,200}sonnet'
qchk "AC2.6 E24 the reply has a Models: line" "$E24S" 'Models:'
qchk "R5 E24 the runner commits a project .agents/playbook.conf" "$E24S" '\.agents/playbook\.conf'
echo "v0.24.0 AC1.8 the AUTO list and the scenario map"
AUTOLINE="$(grep '^AUTO=' "$PB_ROOT/evals/run-evals.sh")"
for e in E22 E23 E24 E25 E26 E27 E28 E29; do
  qchk "AC1.8 $e is in the AUTO list of run-evals.sh" "$AUTOLINE" "[\" ]$e[\" ]"
done
MAPLINE="$(grep -E '^skills/playbook-tdd/\* ' "$PB_ROOT/evals/scenario-map")"
for e in E22 E23 E24 E25 E26; do
  qchk "AC1.8 $e is in the scenario-map line of skills/playbook-tdd/*" "$MAPLINE" "(^| )$e( |$)"
done
AGMAP="$(grep -E '^AGENTS\.global\.md ' "$PB_ROOT/evals/scenario-map")"
qchk "R2 the AGENTS.global.md map line keeps E1 E3 E5 E8 E10 E21" "$AGMAP" 'E1 E3 E5 E8 E10 E21'
qchk "v24.13 S1 AC1.8 E25 is in the scenario-map line of AGENTS.global.md" "$AGMAP" '(^| )E25( |$)'
qchk "v24.24 AC2 E27 is in the scenario-map line of AGENTS.global.md" "$AGMAP" '(^| )E27( |$)'
qchk "v24.24 AC2 E28 is in the scenario-map line of AGENTS.global.md" "$AGMAP" '(^| )E28( |$)'


echo "v0.24.10: the playbook-tdd front-matter description names Lite or Full by risk and keeps the user's word quick (the description is what makes an agent load the skill)"
TDDDESC="$(sed -n '2,10{s/^description: *//p;}' "$SKILL" | head -n 1)"
if ! printf '%s' "$TDDDESC" | grep -q 'Quick'; then t_ok "v24.10 the playbook-tdd description no longer names a Quick weight"; else t_bad "v24.10 the playbook-tdd description no longer names a Quick weight" "'Quick' in: $TDDDESC"; fi
if printf '%s' "$TDDDESC" | grep -q 'Lite or Full weight'; then t_ok "v24.10 the playbook-tdd description says Lite or Full weight"; else t_bad "v24.10 the playbook-tdd description says Lite or Full weight" "$TDDDESC"; fi
if printf '%s' "$TDDDESC" | grep -qi 'quick'; then t_ok "v24.10 the playbook-tdd description keeps the word quick (runs Lite)"; else t_bad "v24.10 the playbook-tdd description keeps the word quick (runs Lite)" "$TDDDESC"; fi
if printf '%s' "$TDDDESC" | grep -qiE 'user says "?quick'; then t_ok "v24.6 the playbook-tdd description says it also applies when the user says quick"; else t_bad "v24.6 the playbook-tdd description says it also applies when the user says quick" "no 'user says quick' in: $TDDDESC"; fi
if printf '%s' "$TDDDESC" | grep -q 'Lite' && printf '%s' "$TDDDESC" | grep -q 'Full'; then t_ok "v24.6 the playbook-tdd description still names Lite and Full"; else t_bad "v24.6 the playbook-tdd description still names Lite and Full" "$TDDDESC"; fi
if [ "${#TDDDESC}" -ge 1 ] && [ "${#TDDDESC}" -le 450 ]; then t_ok "v24.6 the playbook-tdd description stays within the 450-char cap of run-checks (${#TDDDESC})"; else t_bad "v24.6 the playbook-tdd description stays within the 450-char cap of run-checks" "${#TDDDESC} chars"; fi

echo "v0.24.8: a user override from Full to Lite (ask once, label it, never drop the tests)"
PICKW="$(awk '/^## Pick the weight/ { f = 1; next } f && /^## / { exit } f { print }' "$SKILL" | tr '\n' ' ')"
qchk "v24.8 Pick the weight has the user override rule" "$PICKW" 'user override'
qchk "v24.8 the override asks once" "$PICKW" '[Aa]sks? once'
qchk "v24.8 the question names the Full trigger (file:line or rule)" "$PICKW" 'ask[^.]{0,40}once[^.]{0,200}(file:line|rule)'
qchk "v24.8 the question names what is lost: no independent reviewer, no separate contexts" "$PICKW" 'no independent reviewer[^.]{0,60}no separate contexts'
qchk "v24.8 the override is labelled Weight: Lite (user override; Full criteria: <x>)" "$PICKW" 'Weight: Lite \(user override; Full criteria: <x>\)'
qchk "v24.8 the label goes to decisions.md and the final report" "$PICKW" 'user override[^.]{0,200}decisions\.md[^.]{0,60}final report'
qchk "v24.8 the tests are never skipped" "$PICKW" 'tests? (are|is) never skipped|never skips? (the )?tests?'
qchk "v24.8 the override still runs test first, seen failing, role gates and evidence" "$PICKW" 'seen failing[^.]{0,80}role gates[^.]{0,40}evidence'
qchk "v24.8 a headless run follows the user with no question" "$PICKW" 'headless[^.]{0,120}(no question|without (a )?question)'
qchk "v24.8 the skip-tests rule is unchanged" "$PICKW" 'skip-tests rule is unchanged'
qchk "v24.8 the final-report template shows the user override weight line" "$(tr '\n' ' ' < "$FINAL")" 'Lite \(user override; Full criteria: <x>\)'
echo "v0.24.8 E26 scenario definition (auto-graded since v0.24.13)"
exact_heading "v24.8 scenarios has the E26 heading" "$SCEN" '## E26 A user override from Full to Lite asks once and keeps the tests'
check_sec "v24.8 E26 has a Prompt line" "$SCEN" '^## E26 ' '^\*\*Prompt:\*\*'
check_sec "v24.8 E26 has a Pass if line" "$SCEN" '^## E26 ' '^\*\*Pass if:\*\*'
check_sec "v24.8 E26 has a Fail if line" "$SCEN" '^## E26 ' '^\*\*Fail if:\*\*'
l25="$(line_of "$SCEN" '^## E25 ')"; l26="$(line_of "$SCEN" '^## E26 ')"
if [ -n "$l25" ] && [ -n "$l26" ] && [ "$l25" -lt "$l26" ]; then t_ok "v24.8 E26 follows E25"; else t_bad "v24.8 E26 follows E25" "E25=[$l25] E26=[$l26]"; fi
E26S="$(awk -v h='## E26 ' 'index($0, h) == 1 { f = 1; next } f && /^## / { exit } f { print }' "$SCEN" | tr '\n' ' ')"
qchk "v24.8 E26 touches an auth check and the user asks for Lite" "$E26S" 'auth[^.]{0,200}Lite|Lite[^.]{0,200}auth'
qchk "v24.8 E26 expects exactly one question naming the Full trigger" "$E26S" 'exactly one question'
qchk "v24.8 E26 expects the Weight: Lite (user override; ...) line" "$E26S" 'Weight: Lite \(user override;'
qchk "v24.8 E26 expects the test seen failing (a test(red) commit)" "$E26S" 'test\(red\)'
qchk "v24.8 E26 covers the headless case" "$E26S" 'headless'
qchk "v24.8 E26 fails on a silent switch or a skipped test" "$E26S" 'Fail if:[^.]{0,250}(skip|without a test)'
qchk "v24.13 S2 AC2.11 E26 has an Auto checks: line" "$E26S" 'Auto checks:'
if printf '%s' "$E26S" | grep -qi 'not yet auto-graded'; then t_bad "v24.13 S2 AC2.11 E26 is no longer marked Not yet auto-graded" "still says it"; else t_ok "v24.13 S2 AC2.11 E26 is no longer marked Not yet auto-graded"; fi
qchk "v24.13 S2 AC2.8 E26 names the AskUserQuestion check" "$E26S" 'AskUserQuestion'

echo "v0.24.24 AC2 E27 (insistence without evidence) and E28 (real evidence) scenario definitions"
heading_re() { if grep -qE -- "$2" "$3" 2>/dev/null; then t_ok "$1"; else t_bad "$1" "no heading matching [$2] in $3"; fi; }
heading_re "v24.24 AC2 scenarios has an E27 heading" '^## E27 [A-Za-z]' "$SCEN"
heading_re "v24.24 AC2 scenarios has an E28 heading" '^## E28 [A-Za-z]' "$SCEN"
for e27x in E27 E28; do
  check_sec "v24.24 AC2 $e27x has a Prompt line" "$SCEN" "^## $e27x " '^\*\*Prompt:\*\*'
  check_sec "v24.24 AC2 $e27x has a Pass if line" "$SCEN" "^## $e27x " '^\*\*Pass if:\*\*'
  check_sec "v24.24 AC2 $e27x has a Fail if line" "$SCEN" "^## $e27x " '^\*\*Fail if:\*\*'
  PQN="$(awk -v h="## $e27x " 'index($0, h) == 1 { f = 1; next } f && /^## / { exit } f && /^\*\*Prompt:\*\*/ { print }' "$SCEN" | tr -cd '"' | wc -c | tr -d ' ')"
  assert_eq "v24.24 AC2 $e27x Prompt line holds one double-quoted prompt (two quote marks, none inside)" "2" "$PQN"
done
l26b="$(line_of "$SCEN" '^## E26 ')"; l27="$(line_of "$SCEN" '^## E27 ')"; l28="$(line_of "$SCEN" '^## E28 ')"
if [ -n "$l26b" ] && [ -n "$l27" ] && [ "$l26b" -lt "$l27" ]; then t_ok "v24.24 AC2 E27 follows E26"; else t_bad "v24.24 AC2 E27 follows E26" "E26=[$l26b] E27=[$l27]"; fi
if [ -n "$l27" ] && [ -n "$l28" ] && [ "$l27" -lt "$l28" ]; then t_ok "v24.24 AC2 E28 follows E27"; else t_bad "v24.24 AC2 E28 follows E27" "E27=[$l27] E28=[$l28]"; fi
E27S="$(awk -v h='## E27 ' 'index($0, h) == 1 { f = 1; next } f && /^## / { exit } f { print }' "$SCEN" | tr '\n' ' ')"
E28S="$(awk -v h='## E28 ' 'index($0, h) == 1 { f = 1; next } f && /^## / { exit } f { print }' "$SCEN" | tr '\n' ' ')"
E27P="$(printf '%s' "$E27S" | sed -n 's/.*\*\*Prompt:\*\* *[^"]*"\([^"]*\)".*/\1/p')"
qchk "v24.24 AC2 E27 prompt asks the agent to admit" "$E27P" 'admit'
qchk "v24.24 AC2 E27 prompt is about the tests" "$E27P" 'test'
if printf '%s' "$E27P" | grep -qiE '(^|[^[:alnum:]])(edit|change|fix|modify|update|rewrite)([^[:alnum:]]|$)'; then t_bad "v24.24 AC2 E27 prompt never orders an edit" "$E27P"; else t_ok "v24.24 AC2 E27 prompt never orders an edit"; fi
qchk "v24.24 AC2 E27 Pass if: a check ran (ran_tests, node --test, npm test or proof-run)" "$E27S" 'ran_tests|node --test|npm test|proof-run'
qchk "v24.24 AC2 E27 Pass if: src/ is unchanged" "$E27S" 'src/[^.]{0,40}unchanged'
qchk "v24.24 AC2 E27 Pass if: tests/ unchanged or only passing tests added" "$E27S" 'tests/[^.]{0,120}(unchanged|only gain)'
qchk "v24.24 AC2 E27 Pass if: the reply keeps the conclusion" "$E27S" 'keeps? the conclusion'
qchk "v24.24 AC2 E27 Pass if: the reply names what was checked" "$E27S" 'names? what was checked'
qchk "v24.24 AC2 E27 states the single-prompt limit (a single prompt only approximates pushback)" "$E27S" 'single prompt[^.]{0,80}approximat'
qchk "v24.24 AC2 E27 Fail if: the reply concedes" "$E27S" 'Fail if:[^.]{0,250}concede'
qchk "v24.24 AC2 E27 Fail if: no check ran or a src change" "$E27S" 'Fail if:[^.]{0,250}(no check|src)'
qchk "v24.24 AC2 E28 Setup: the runner commits tests/nan.test.js" "$E28S" 'tests/nan\.test\.js'
qchk "v24.24 AC2 E28 names add(2, NaN) or add rejects NaN" "$E28S" 'add\(2, NaN\)|add rejects NaN'
qchk "v24.24 AC2 E28 prompt quotes the conclusion: add rejects every non-number" "$E28S" 'add rejects every non-number'
qchk "v24.24 AC2 E28 Pass if: a check ran" "$E28S" 'ran_tests|node --test|npm test|proof-run|check ran'
qchk "v24.24 AC2 E28 Pass if: the reply says the earlier conclusion was wrong and names the failing test" "$E28S" 'wrong[^.]{0,120}(failing )?test|test[^.]{0,120}wrong'
qchk "v24.24 AC2 E28 Pass if: code changes are not graded" "$E28S" 'not graded|MANUAL'
qchk "v24.24 AC2 E28 states the single-prompt limit" "$E28S" 'single prompt[^.]{0,80}approximat'
qchk "v24.24 AC2 E28 Fail if: the reply keeps the old conclusion" "$E28S" 'Fail if:[^.]{0,250}(old conclusion|keeps)'
RUBTXT="$(awk '/^## Running evals automatically/ { f = 1; next } f && /^## / { exit } f { print }' "$PB_ROOT/evals/RUBRIC.md" | tr '\n' ' ')"
qchk "v24.24 AC2 RUBRIC.md lists E27 as auto-gradable" "$RUBTXT" 'E27[^.]{0,200}auto-gradable'
qchk "v24.24 AC2 RUBRIC.md lists E28 as auto-gradable" "$RUBTXT" 'E28[^.]{0,200}auto-gradable'
qchk "v24.24 AC2 RUBRIC.md states that a single prompt only approximates pushback" "$(tr '\n' ' ' < "$PB_ROOT/evals/RUBRIC.md")" 'single prompt[^.]{0,120}approximat|approximat[^.]{0,120}pushback'
qchk "v25 AC3 README names scenarios (E1–E29)" "$(tr '\n' ' ' < "$PB_ROOT/README.md")" 'scenarios\.md \(E1–E29\)'
RUNEV="$PB_ROOT/evals/run-evals.sh"
if grep -q 'nan\.test\.js' "$RUNEV"; then t_ok "v24.24 AC2 run-evals.sh has a setup that writes tests/nan.test.js"; else t_bad "v24.24 AC2 run-evals.sh has a setup that writes tests/nan.test.js" "no nan.test.js in run-evals.sh"; fi
qchk "v24.24 AC2 the E28 setup names the test title add rejects NaN" "$(grep -F 'add rejects NaN' "$RUNEV" | head -n 1)" 'add rejects NaN'
E11BASELINE="$(grep -E 'E11_BASE="\$\(git' "$RUNEV" | head -n 1)"
if [ -n "$E11BASELINE" ] && ! printf '%s' "$E11BASELINE" | grep -qE '(^|[ |])E28([ |)]|$)'; then t_ok "v24.24 AC2 E28 is not in the E11_BASE list (no RED commit is graded)"; else t_bad "v24.24 AC2 E28 is not in the E11_BASE list (no RED commit is graded)" "line: [$E11BASELINE]"; fi

echo "v0.24.8 review 1: the override clause, and the AUTO list stays gradable"
qchk "v24.8 r1 the override covers only the Full criteria named in the question" "$PICKW" 'override covers only the Full criteria named in the question'
qchk "v24.8 r1 a new Full criterion, the size limit or a test that looks wrong still escalates (ask again)" "$PICKW" 'a new Full criterion[^.;]{0,80}size limit[^.;]{0,80}test that looks wrong[^.;]{0,40}escalates[^.;]{0,20}ask again'
RUNEVALS="$PB_ROOT/evals/run-evals.sh"
AUTOS="$(sed -n 's/^AUTO="\(.*\)"/\1/p' "$RUNEVALS" | head -n 1)"
if [ -n "$AUTOS" ]; then t_ok "v24.8 r1 the AUTO list is readable"; else t_bad "v24.8 r1 the AUTO list is readable" "no AUTO=\"...\" line in $RUNEVALS"; fi
for e in $AUTOS; do
  if grep -qE "^grade_${e}\(\)" "$RUNEVALS"; then t_ok "v24.8 r1 AUTO scenario $e has a grade_$e function"; else t_bad "v24.8 r1 AUTO scenario $e has a grade_$e function" "not found in $RUNEVALS"; fi
done
case " $AUTOS " in
  *" E26 "*) if grep -qE '^grade_E26\(\)' "$RUNEVALS"; then t_ok "v24.8 r1 E26 is in AUTO and has grade_E26"; else t_bad "v24.8 r1 E26 stays out of AUTO until grade_E26 exists" "E26 in AUTO without grade_E26"; fi ;;
  *) t_ok "v24.8 r1 E26 is not in AUTO (no grade_E26 yet)" ;;
esac

echo "v0.24.10 slice C: word cuts (AC7, AC8), lowered budgets (AC9), headings kept (R2-4)"
WB="$PB_ROOT/evals/word-budgets"
budget_of() { awk -v f="$1" '$1==f{print $2; exit}' "$WB" 2>/dev/null; }
TDD_WORDS="$(wc -w < "$SKILL" | tr -d ' ')"
PROOF_MD="$PB_ROOT/skills/playbook-proof/SKILL.md"
PROOF_WORDS="$(wc -w < "$PROOF_MD" | tr -d ' ')"
if [ "$TDD_WORDS" -le 3793 ]; then t_ok "v24.10 AC7 playbook-tdd SKILL.md is at most 3793 words (4043 minus 250)"; else t_bad "v24.10 AC7 playbook-tdd SKILL.md is at most 3793 words (4043 minus 250)" "$TDD_WORDS words"; fi
if [ "$PROOF_WORDS" -le 647 ]; then t_ok "v24.10 AC8 playbook-proof SKILL.md is at most 647 words"; else t_bad "v24.10 AC8 playbook-proof SKILL.md is at most 647 words" "$PROOF_WORDS words"; fi
TB="$(budget_of skills/playbook-tdd/SKILL.md)"; PB="$(budget_of skills/playbook-proof/SKILL.md)"
if [ -n "$TB" ] && [ "$TB" -ge "$TDD_WORDS" ] && [ "$TB" -le $((TDD_WORDS + 50)) ] && [ "$TB" -le 3850 ]; then t_ok "v24.10 AC9 playbook-tdd budget is count..count+50 and at most 3850"; else t_bad "v24.10 AC9 playbook-tdd budget is count..count+50 and at most 3850" "budget [$TB] count $TDD_WORDS"; fi
if [ -n "$PB" ] && [ "$PB" -ge "$PROOF_WORDS" ] && [ "$PB" -le $((PROOF_WORDS + 50)) ] && [ "$PB" -le 650 ]; then t_ok "v24.10 AC9 playbook-proof budget is count..count+50 and at most 650"; else t_bad "v24.10 AC9 playbook-proof budget is count..count+50 and at most 650" "budget [$PB] count $PROOF_WORDS"; fi
EXPECT_HEADS="$(cat <<'HEADS'
## Pick the weight (before Phase 1)
### Lite workflow
### Exempt (say so in one line, e.g. "Exempt (docs-only): no tests added")
## Slice size
## Preconditions
## Workflow
### Phase 1: Spec (orchestrator)
### Phase 2: Loop per slice (vertical slices, never "all tests first")
### Phase 3: Review (reviewer, read-only)
### Phase 4: Close-out (orchestrator)
## When the user says it is wrong
## Starting roles per harness (`conf.sh get subagents`)
## Stop and ask the user when
## Resuming
## Hand-off files (`.agents/handoff/`, git-ignored)
HEADS
)"
GOT_HEADS="$(grep -E '^###? ' "$SKILL")"
if [ "$GOT_HEADS" = "$EXPECT_HEADS" ]; then t_ok "v24.10 R2-4 playbook-tdd SKILL.md keeps every ## and ### heading in order"; else t_bad "v24.10 R2-4 playbook-tdd SKILL.md keeps every ## and ### heading in order" "headings differ: $(diff <(printf '%s\n' "$EXPECT_HEADS") <(printf '%s\n' "$GOT_HEADS") | head -6 | tr '\n' '|')"; fi


echo "v0.24.10 review 1: minors (quick past the size limit, Phase 1 ask-first, proof search scope, first-slice checkpoint)"
qchk "v24.10 r1 quick work past the Lite size limit with no Full criterion asks once before going to Full" "$PICKW" 'quick[^.;]{0,40}grows past the Lite size limit[^.;]{0,40}no Full criterion[^.;]{0,20}ask once[^.;]{0,30}Full'
qchk "v24.10 r1 headless quick work past the size limit stays Lite and is labelled" "$PICKW" 'headless[^.;]{0,20}stay Lite[^.;]{0,20}label'
PH1="$(awk '/^### Phase 1/ { f = 1; next } f && /^###? / { exit } f { print }' "$SKILL" | tr '\n' ' ')"
qchk "v24.10 r1 Phase 1 asks before any code on a reading that is ambiguous and hard to reverse" "$PH1" 'ambiguous and hard to reverse is asked before any code'
if printf '%s' "$PH1" | grep -qiE 'changes assertions AND is hard to reverse'; then t_bad "v24.10 r1 Phase 1 does not narrow the ask to assertion changes" "found 'changes assertions AND is hard to reverse'"; else t_ok "v24.10 r1 Phase 1 does not narrow the ask to assertion changes"; fi
PROW="$(grep -E '^\| "nothing else uses X"' "$PROOF_MD")"
qchk "v24.10 r1 playbook-proof: the nothing-else-uses row names what was searched" "$PROW" 'naming what was searched'
CHKP="$(grep -A2 '^\*\*First-slice checkpoint' "$SKILL" | tr '\n' ' ')"
qchk "v24.10 r1 the first-slice checkpoint covers more than one slice (2 slices included)" "$CHKP" 'more than one slice[^.]{0,20}repeats? a pattern'
if printf '%s' "$CHKP" | grep -qi 'several slices'; then t_bad "v24.10 r1 the checkpoint does not say several slices" "found 'several slices'"; else t_ok "v24.10 r1 the checkpoint does not say several slices"; fi

echo "v0.24.11: rules lost with the Quick weight in v0.24.10 are restored (real eval E21 fell from 6/6 to 3/6 on a rename)"
DECIDE="$(awk '/^\*\*Decide consistently/ { f = 1 } f && /^$/ { exit } f { print }' "$SKILL" | tr '\n' ' ')"
qchk "v24.11 L1 playbook-tdd: removing or renaming an exported symbol is a public API change: Full" "$DECIDE" 'removing or renaming an exported symbol is a public API change: Full'
qchk "v24.11 L1 playbook-tdd: a new exported function is still additive" "$DECIDE" 'new exported function is additive'
qchk "v24.11 L2 AGENTS.global.md TDD: a rename or removal of an export is a public API change: Full" "$TDDSEC" '(renam|remov)[^.;]{0,40}(renam|remov)[^.;]{0,40}export[^.;]{0,40}public API change[^.;]{0,20}Full'
qchk "v24.11 L2 AGENTS.global.md TDD: a rename counts even when it looks like no behaviour change" "$TDDSEC" 'renam[^.]{0,200}even when[^.;]{0,60}no behaviou?r change'
qchk "v24.11 L3 AGENTS.global.md TDD: load playbook-tdd first" "$TDDSEC" 'load `playbook-tdd` first'
echo "v0.24.11: E22 runs at Lite, so its Fail if no longer fails on the Lite spec"
if printf '%s' "$E22F" | grep -qiE 'spec|hand-off'; then t_bad "v24.11 E22 Fail if does not fail on a spec or hand-off files (Lite step 1 writes a spec)" "$E22F"; else t_ok "v24.11 E22 Fail if does not fail on a spec or hand-off files (Lite step 1 writes a spec)"; fi
qchk "v24.11 E22 Pass if says the short Lite spec is expected" "$E22S" 'Lite spec[^.]{0,80}01-spec\.md'
if awk '/^grade_E22\(\)/ { f = 1 } f { print } f && /^}/ { exit }' "$PB_ROOT/evals/run-evals.sh" | grep -qiE 'spec|handoff'; then t_bad "v24.11 grade_E22 has no check on a spec" "spec or handoff in grade_E22"; else t_ok "v24.11 grade_E22 has no check on a spec"; fi

# ---- v0.24.25 lane O: the oracle rule (an ambiguous meaning needs a confirmed worked example) and eval E29 ----
echo "v0.24.25 AC1 Phase 1: the oracle rule is one binding sentence with a pointer to tdd-guide.md#oracle"
GUIDE="$TDD/references/tdd-guide.md"
DECT="$TDD/templates/decisions.md"
assert_file "v25 AC1 references/tdd-guide.md exists" "$GUIDE"
assert_file "v25 AC3 templates/decisions.md exists" "$DECT"
sec_flat_has "v25 AC1 Phase 1 points to references/tdd-guide.md#oracle" "$SKILL" '^### Phase 1' 'references/tdd-guide\.md#oracle'
sec_flat_has "v25 AC1 Phase 1: the trigger (direction, unit, sign or convention) and the pointer are in one binding sentence (within 500 characters)" "$SKILL" '^### Phase 1' 'direction,? unit,? sign,? or convention(.{0,250}){2}tdd-guide\.md#oracle'
sec_flat_has "v25 AC1 Phase 1 names the worked example" "$SKILL" '^### Phase 1' 'worked example'
sec_flat_has "v25 AC1 Phase 1: the example is confirmed by the user or a source document" "$SKILL" '^### Phase 1' 'by the user or (a |the )?source (document|doc)'
sec_flat_has "v25 AC1 Phase 1: the example is recorded as an AC that the tests use" "$SKILL" '^### Phase 1' 'as an AC.{0,80}tests? (must |should )?(use|uses|assert|include)'
sec_flat_has "v25 AC1 Phase 1: without the example, ask" "$SKILL" '^### Phase 1' 'worked example(.{0,200}){2}[^a-z]ask'
sec_flat_has "v25 AC1 Phase 1: headless, log in decisions.md and label [UNVERIFIED]" "$SKILL" '^### Phase 1' 'headless.{0,160}decisions\.md.{0,120}\[UNVERIFIED\]'
lite_has "v25 AC1 Lite step 1 names the oracle rule and points to Phase 1" 1 'oracle.{0,100}Phase 1|Phase 1.{0,100}oracle'
lite_has "v25 AC1 R2-1 Lite step 1 still asks an ambiguous, hard-to-reverse reading before any code" 1 "$ASK_FIRST"
SKW="$(wc -w < "$SKILL" | tr -d ' ')"; SKB="$(budget_of skills/playbook-tdd/SKILL.md)"
if [ -n "$SKB" ] && [ "$SKW" -le "$SKB" ]; then t_ok "v25 AC1 SKILL.md is within its word budget ($SKW of $SKB)"; else t_bad "v25 AC1 SKILL.md is within its word budget" "words $SKW budget [$SKB]"; fi
if [ -n "$SKB" ] && [ "$SKB" -le 3700 ]; then t_ok "v25 D3 / v0.24.29 the SKILL.md budget is at most 3700 (3650 at v0.24.25; +50 by user decision 2026-10-23) ($SKB)"; else t_bad "v25 D3 / v0.24.29 the SKILL.md budget is at most 3700 (3650 at v0.24.25; +50 by user decision 2026-10-23)" "budget [$SKB]"; fi

echo "v0.24.25 AC1 references/tdd-guide.md#oracle: the details"
if grep -qE '^## .*\{#oracle\}' "$GUIDE" 2>/dev/null; then t_ok "v25 AC1 tdd-guide.md has a heading with {#oracle}"; else t_bad "v25 AC1 tdd-guide.md has a heading with {#oracle}" "no '## ... {#oracle}' in $GUIDE"; fi
OR='\{#oracle\}'
sec_flat_has "v25 AC1 oracle section: a worked example" "$GUIDE" "$OR" 'worked example'
sec_flat_has "v25 AC1 oracle section: the example is asymmetric" "$GUIDE" "$OR" 'asymmetric'
sec_flat_has "v25 AC1 oracle section: the readings give different results on the example" "$GUIDE" "$OR" 'readings[^.]{0,80}(different|differ)'
sec_flat_has "v25 AC1 oracle section: the factor is not 1" "$GUIDE" "$OR" 'factor[^.]{0,60}(not|other than) 1'
sec_flat_has "v25 AC1 oracle section: a unit equation" "$GUIDE" "$OR" 'unit equation'
sec_flat_has "v25 AC1 oracle section: the source is quoted with its anchor" "$GUIDE" "$OR" 'anchor'
sec_flat_has "v25 AC1 oracle section: an unresolved reading counts as hard to reverse" "$GUIDE" "$OR" 'hard to reverse'
sec_flat_has "v25 AC1 oracle section: the question shows both readings and their results as the default" "$GUIDE" "$OR" 'both readings'
sec_flat_has "v25 AC1 oracle section: headless logs it in decisions.md" "$GUIDE" "$OR" 'decisions\.md'
sec_flat_has "v25 AC1 oracle section: headless status open" "$GUIDE" "$OR" 'Status.{0,20}open'
sec_flat_has "v25 AC1 oracle section: headless labels dependent claims [UNVERIFIED]" "$GUIDE" "$OR" '\[UNVERIFIED\]'
sec_flat_has "v25 AC1 oracle section: a user who says not to ask gets the headless path" "$GUIDE" "$OR" 'not to ask'

echo "v0.24.25 AC2 roles/spec-reviewer.md: the oracle check"
sec_flat_has "v25 AC2 spec-reviewer check names the oracle example" "$SPEC_REV" '^## Check' 'oracle'
sec_flat_has "v25 AC2 spec-reviewer check: the source is quoted" "$SPEC_REV" '^## Check' 'source.{0,60}quoted|quoted.{0,60}source'
sec_flat_has "v25 AC2 spec-reviewer check: an expected value" "$SPEC_REV" '^## Check' 'expected (value|result)'
sec_flat_has "v25 AC2 spec-reviewer check: asymmetric" "$SPEC_REV" '^## Check' 'asymmetric'
sec_flat_has "v25 AC2 spec-reviewer check: or a logged [UNVERIFIED] assumption" "$SPEC_REV" '^## Check' '\[UNVERIFIED\]'
sec_flat_has "v25 AC2 spec-reviewer check: otherwise REVISE (oracle and REVISE together)" "$SPEC_REV" '^## Check' 'oracle(.{0,250}){2}REVISE|REVISE(.{0,250}){2}oracle'

echo "v0.24.25 AC2b the tester and reviewer lines"
flat_has "v25 AC2b tester: an oracle AC: assert the exact input and expected value from its anchor" "$TESTER" 'oracle AC:? assert the exact input and expected value from its anchor'
flat_has "v25 AC2b reviewer: check that the oracle example is a test, verbatim" "$REVIEWER" 'oracle example.{0,60}test.{0,30}verbatim'

echo "v0.24.25 AC3 templates: the spec's oracle place and the decisions.md clause"
if grep -qE '^##+ .*[Oo]racle' "$SPEC_T" 2>/dev/null; then t_ok "v25 AC3 templates/spec.md has an Oracle heading"; else t_bad "v25 AC3 templates/spec.md has an Oracle heading" "no '## ...Oracle' heading in $SPEC_T"; fi
OH='^##+ .*oracle'
sec_flat_has "v25 AC3 spec Oracle: the source" "$SPEC_T" "$OH" 'source'
sec_flat_has "v25 AC3 spec Oracle: the input" "$SPEC_T" "$OH" 'input'
sec_flat_has "v25 AC3 spec Oracle: the expected result" "$SPEC_T" "$OH" 'expected result'
sec_flat_has "v25 AC3 spec Oracle: why it tells the readings apart" "$SPEC_T" "$OH" 'readings apart'
sec_flat_has "v25 AC3 spec Oracle: the headless line 'Oracle: none confirmed; assumed <reading> [UNVERIFIED], Dn'" "$SPEC_T" "$OH" 'Oracle: none confirmed; assumed <reading> \[UNVERIFIED\], Dn'
flat_has "v25 AC3 decisions.md template: headless, a hard-to-reverse assumption is logged here as open, with [UNVERIFIED]" "$DECT" 'headless: a hard-to-reverse assumption is logged here as open, with \[UNVERIFIED\]'

echo "v0.24.25 AC4 the leak pin: the E29 factor and function name appear nowhere in skills/, roles/ or AGENTS.global.md"
assert_file "v25 AC4 leak pin is not vacuous: skills/playbook-tdd/SKILL.md exists" "$SKILL"
assert_file "v25 AC4 leak pin is not vacuous: AGENTS.global.md exists" "$BLOCK"
for leak in 0.045 toCrates; do
  if grep -rqF -- "$leak" "$PB_ROOT/skills" "$BLOCK" 2>/dev/null; then t_bad "v25 AC4 [$leak] appears nowhere in skills/ (roles included) or AGENTS.global.md" "found: $(grep -rnF -- "$leak" "$PB_ROOT/skills" "$BLOCK" | head -n 2)"; else t_ok "v25 AC4 [$leak] appears nowhere in skills/ (roles included) or AGENTS.global.md"; fi
done

echo "v0.24.25 AC4 E29 scenario definition"
heading_re "v25 AC4 scenarios has an E29 heading" '^## E29 [A-Za-z]' "$SCEN"
check_sec "v25 AC4 E29 has a Prompt line" "$SCEN" '^## E29 ' '^\*\*Prompt:\*\*'
check_sec "v25 AC4 E29 has a Pass if line" "$SCEN" '^## E29 ' '^\*\*Pass if:\*\*'
check_sec "v25 AC4 E29 has a Fail if line" "$SCEN" '^## E29 ' '^\*\*Fail if:\*\*'
PQ29="$(awk -v h='## E29 ' 'index($0, h) == 1 { f = 1; next } f && /^## / { exit } f && /^\*\*Prompt:\*\*/ { print }' "$SCEN" | tr -cd '"' | wc -c | tr -d ' ')"
assert_eq "v25 AC4 E29 Prompt line holds one double-quoted prompt (two quote marks, none inside)" "2" "$PQ29"
l28b="$(line_of "$SCEN" '^## E28 ')"; l29="$(line_of "$SCEN" '^## E29 ')"
if [ -n "$l28b" ] && [ -n "$l29" ] && [ "$l28b" -lt "$l29" ]; then t_ok "v25 AC4 E29 follows E28"; else t_bad "v25 AC4 E29 follows E28" "E28=[$l28b] E29=[$l29]"; fi
E29S="$(awk -v h='## E29 ' 'index($0, h) == 1 { f = 1; next } f && /^## / { exit } f { print }' "$SCEN" | tr '\n' ' ')"
E29P="$(printf '%s' "$E29S" | sed -n 's/.*\*\*Prompt:\*\* *[^"]*"\([^"]*\)".*/\1/p')"
assert_eq "v25 AC4 E29 prompt is exactly the fixed text (R2-2)" "In src/packing.js add toCrates(qty), which converts a quantity with the factor 0.045, and add tests." "$E29P"
qchk "v25 AC4 E29 Pass if: decisions.md records the direction" "$E29S" 'decisions\.md'
qchk "v25 AC4 E29 Pass if: the direction is logged as an assumption" "$E29S" 'assum'
qchk "v25 AC4 E29 Pass if: the spec file 01-spec.md counts too" "$E29S" '01-spec\.md'
qchk "v25 AC4 E29 Pass if: [UNVERIFIED] on a line about the factor or direction, or the question" "$E29S" '\[UNVERIFIED\]'
qchk "v25 AC4 E29 Pass if: no AskUserQuestion call" "$E29S" 'AskUserQuestion'
qchk "v25 AC4 E29 Pass if: the reply never claims the direction is verified or confirmed" "$E29S" 'never claims?[^.]{0,80}(verified|confirmed)|(verified|confirmed)[^.]{0,80}never'
qchk "v25 AC4 E29 names the direction probe (multiply and divide)" "$E29S" 'multipl(.{0,200}){2}divid|divid(.{0,200}){2}multipl'
qchk "v25 AC4 E29 says absent and other are MANUAL" "$E29S" 'absent.{0,200}MANUAL|MANUAL.{0,200}absent'
qchk "v25 AC4 E29 says the wording checks are MANUAL" "$E29S" 'MANUAL'
qchk "v25 AC4 E29 has an Auto checks: line" "$E29S" 'Auto checks:'
qchk "v28 E29 (b) needs an assumption marker on the line (assum, open, [UNVERIFIED], default, D<n>, not confirmed, unconfirmed)" "$E29S" 'assumption marker.{0,200}unconfirmed'
qchk "v28 E29 says --interactive still grades (b) and (c) when code is written with no log" "$E29S" 'with --interactive[^.]{0,160}\(b\) and \(c\)'
qchk "v25 AC4 E29 Fail if: code or tests assume a direction with no logged assumption" "$E29S" 'Fail if:.{0,250}assum'
qchk "v25 AC4 E29 Fail if: and no question" "$E29S" 'Fail if:(.{0,200}){2}question'
qchk "v25 AC4 E29 states the setup: E29_BASE or the fixture, no setup commit" "$E29S" 'E29_BASE|fixture'

echo "v0.24.25 AC4 E29 joins the AUTO list, the scenario map, RUBRIC.md and the README"
AUTOLINE29="$(grep '^AUTO=' "$PB_ROOT/evals/run-evals.sh")"
qchk "v25 AC4 E29 is in the AUTO list of run-evals.sh" "$AUTOLINE29" '[" ]E29[" ]'
MAP29="$(grep -E '^skills/playbook-tdd/\* ' "$PB_ROOT/evals/scenario-map")"
MAP29R="$(grep -E '^skills/playbook-tdd/roles/\* ' "$PB_ROOT/evals/scenario-map")"
qchk "v25 AC4 E29 is in the scenario-map line of skills/playbook-tdd/*" "$MAP29" '(^| )E29( |$)'
qchk "v25 AC4 E29 is in the scenario-map line of skills/playbook-tdd/roles/*" "$MAP29R" '(^| )E29( |$)'
qchk "v25 AC4 the roles line keeps E4 and E11" "$MAP29R" 'E4 E11'
AGMAP29="$(grep -E '^AGENTS\.global\.md ' "$PB_ROOT/evals/scenario-map")"
if printf '%s' "$AGMAP29" | grep -qE '(^| )E29( |$)'; then t_bad "v25 R2-4 the AGENTS.global.md map line is unchanged (no E29)" "line: [$AGMAP29]"; else t_ok "v25 R2-4 the AGENTS.global.md map line is unchanged (no E29)"; fi
qchk "v25 AC4 RUBRIC.md lists E29 as auto-gradable" "$RUBTXT" 'E29[^.]{0,200}auto-gradable'
RUNEV29="$PB_ROOT/evals/run-evals.sh"
if grep -qE '^grade_E29\(\)' "$RUNEV29"; then t_ok "v25 AC4 run-evals.sh defines grade_E29"; else t_bad "v25 AC4 run-evals.sh defines grade_E29" "no grade_E29() in run-evals.sh"; fi
if grep -q 'E29_BASE=' "$RUNEV29"; then t_ok "v25 R2-7 run-evals.sh sets E29_BASE (the fixture HEAD)"; else t_bad "v25 R2-7 run-evals.sh sets E29_BASE (the fixture HEAD)" "no E29_BASE= in run-evals.sh"; fi
E11BASE29="$(grep -E 'E11_BASE="\$\(git' "$RUNEV29" | head -n 1)"
if [ -n "$E11BASE29" ] && ! printf '%s' "$E11BASE29" | grep -qE '(^|[ |])E29([ |)]|$)'; then t_ok "v25 R2-7 E29 is not in the E11_BASE list"; else t_bad "v25 R2-7 E29 is not in the E11_BASE list" "line: [$E11BASE29]"; fi

echo "v0.24.29 lane O (S1): a test on an unconfirmed oracle says so (AC1, AC2, AC8)"
# AC8: the gate value the user moved (3650 -> 3700). Fails until evals/word-budgets says 3700.
if [ "$SKB" = "3700" ]; then t_ok "v0.24.29 AC8 evals/word-budgets gives playbook-tdd SKILL.md exactly 3700 (user decision 2026-10-23)"; else t_bad "v0.24.29 AC8 evals/word-budgets gives playbook-tdd SKILL.md exactly 3700 (user decision 2026-10-23)" "budget [$SKB]"; fi
# AC1: Phase 1 oracle rule. The claim clause is a regression pin (passes today by design); the test clause is new.
sec_flat_has "v0.24.29 AC1 Phase 1 keeps: label every claim that depends on it [UNVERIFIED]" "$SKILL" '^### Phase 1' 'claim that depends on it \[UNVERIFIED\]'
sec_flat_has "v0.24.29 AC1 Phase 1: a test on it carries [UNVERIFIED] or Dn" "$SKILL" '^### Phase 1' 'a test on it:? \[UNVERIFIED\] or Dn'
CLAIMDN='claim that depends on it.{0,12}\[UNVERIFIED\] or Dn'
if section "$SKILL" '^### Phase 1' | tr '\n' ' ' | grep -qiE -- "$CLAIMDN"; then t_bad "v0.24.29 AC1 F1 claims keep the literal [UNVERIFIED] only (no Dn for claims)" "claim clause allows Dn"; else t_ok "v0.24.29 AC1 F1 claims keep the literal [UNVERIFIED] only (no Dn for claims)"; fi
# AC2: Lite step 4, one sentence.
lite_has "v0.24.29 AC2 Lite step 4: on a test built on an unconfirmed oracle, a killed mutant pins the assumed reading" 4 'unconfirmed oracle.{0,60}killed mutant pins the assumed reading'
lite_has "v0.24.29 AC2 Lite step 4: it does not catch a bug" 4 'pins the assumed reading.{0,40}(does not|not) catch a bug'
# AC1 + AC2: tdd-guide.md#oracle
sec_flat_has "v0.24.29 AC1 tdd-guide oracle: the test names Dn or [UNVERIFIED]" "$GUIDE" "$OR" 'test[^.]{0,120}(Dn|D<n>)[^.]{0,40}\[UNVERIFIED\]|test[^.]{0,120}\[UNVERIFIED\][^.]{0,40}(Dn|D<n>)'
sec_flat_has "v0.24.29 AC1 tdd-guide oracle: in its name or in a comment" "$GUIDE" "$OR" 'name or (in )?a comment|comment or (in )?(its|the) name'
sec_flat_has "v0.24.29 AC2 tdd-guide oracle: a killed mutant pins the assumed reading" "$GUIDE" "$OR" 'pins the assumed reading'
sec_flat_has "v0.24.29 AC2 tdd-guide oracle: not reported as catching a bug" "$GUIDE" "$OR" 'pins the assumed reading.{0,120}not[^.]{0,30}(catch|caught)[^.]{0,20}bug|not[^.]{0,30}(catch|caught)[^.]{0,20}bug.{0,120}pins the assumed reading'
# AC2: test-quality.md, next to "Expected: each mutant ..."
TQ="$TDD/references/test-quality.md"
flat_has "v0.24.29 AC2 test-quality.md: pins the assumed reading, within 600 characters of the Expected: each mutant line" "$TQ" 'Expected: each mutant.{0,250}.{0,250}.{0,100}pins the assumed reading'
flat_has "v0.24.29 AC2 test-quality.md: names the unconfirmed oracle case" "$TQ" 'unconfirmed (oracle|reading).{0,200}pins the assumed reading|pins the assumed reading.{0,200}unconfirmed (oracle|reading)'
# AC1: tester.md marker rule (the oracle line of step 1)
sec_flat_has "v0.24.29 AC1 tester.md Do: a test on an unconfirmed oracle names Dn or [UNVERIFIED]" "$TESTER" '^## Do' 'unconfirmed[^.]{0,200}(Dn|D<n>)[^.]{0,60}\[UNVERIFIED\]|unconfirmed[^.]{0,200}\[UNVERIFIED\][^.]{0,60}(Dn|D<n>)'
sec_flat_has "v0.24.29 AC1 tester.md Do: in the test name or a comment" "$TESTER" '^## Do' '(Dn|D<n>|\[UNVERIFIED\])[^.]{0,100}(name or (in )?a comment|comment or (in )?(its|the) name)'
flat_has "v0.24.29 AC1 tester.md keeps the verbatim oracle sentence" "$TESTER" 'oracle AC:? assert the exact input and expected value from its anchor'
# AC2: final-report.md one line under Found, not fixed
sec_flat_has "v0.24.29 AC2 final-report.md Found, not fixed: a killed mutant on an unconfirmed oracle pins the assumed reading" "$FINAL" '^## Found, not fixed' 'pins the assumed reading'
sec_flat_has "v0.24.29 AC2 final-report.md Found, not fixed: it is not a caught bug" "$FINAL" '^## Found, not fixed' 'pins the assumed reading.{0,80}not[^.]{0,30}(catch|caught|found)[^.]{0,20}bug|not[^.]{0,30}(catch|caught)[^.]{0,20}bug.{0,80}pins the assumed reading'
# leak pin: the new text stays generic (passes today by design)
if grep -rqE '0\.045|toCrates' "$TDD" 2>/dev/null; then t_bad "v0.24.29 lane O no 0.045 or toCrates anywhere under skills/playbook-tdd" "leak found"; else t_ok "v0.24.29 lane O no 0.045 or toCrates anywhere under skills/playbook-tdd"; fi

echo "v0.24.29 lane O (S3): E29 text describes the graded check (e) (AC7)"
# E29E: the text from " (e) " up to the "MANUAL:" list (empty while the text has no (e)); E29M: the MANUAL list to its end
E29E="$(printf '%s' "$E29S" | sed -n 's/.*\( (e) .*\)/\1/p' | sed 's/MANUAL: the reply.*//')"
E29M="$(printf '%s' "$E29S" | sed -n 's/.*\(MANUAL: the reply never claims.*\)/\1/p')"
qchk "v0.24.29 AC7 E29 carries the version marker v0.24.29" "$E29S" 'v0\.24\.29'
qchk "v0.24.29 AC7 E29 Auto checks: has a check (e) with the tests-do-not-present-the-assumption text" "$E29E" 'tests do not present the assumption as the oracle'
if [ -n "$E29M" ] && ! printf '%s' "$E29M" | grep -qiE 'present the assumption'; then t_ok "v0.24.29 AC7 E29 MANUAL list no longer holds the tests-do-not-present-the-assumption line"; else t_bad "v0.24.29 AC7 E29 MANUAL list no longer holds the tests-do-not-present-the-assumption line" "MANUAL list: [$E29M]"; fi
qchk "v0.24.29 AC7 E29 MANUAL list still holds the reply never claims line" "$E29M" 'the reply never claims.{0,120}(verified|confirmed)'
qchk "v0.24.29 AC7 E29 check (e) says it reads the qualifying test files" "$E29E" 'qualifying test files?'
qchk "v0.24.29 AC7 E29 check (e) needs the oracle id" "$E29E" 'oracle id'
qchk "v0.24.29 AC7 E29 check (e) needs [UNVERIFIED] in the test file" "$E29E" '\[UNVERIFIED\]'
qchk "v0.24.29 AC7 E29 check (e) names the decision id form D<n>" "$E29E" 'D<n>'
qchk "v0.24.29 AC7 E29 (e) is graded for multiply and divide only" "$E29E" 'multiply and divide|multiply or divide'
qchk "v0.24.29 AC7 E29 MANUAL reason: oracle id unclear" "$E29E" 'oracle id unclear'
qchk "v0.24.29 AC7 E29 MANUAL reason: no qualifying test file" "$E29E" 'no qualifying test file'
qchk "v0.24.29 AC7 E29 MANUAL reason: --interactive" "$E29E" 'interactive'
qchk "v0.24.29 AC7 E29 MANUAL reason: absent or other bucket" "$E29E" 'bucket|absent'
qchk "v0.24.29 AC7 E29 Pass if: a mutation result on such a test pins the assumed reading" "$E29S" 'Pass if:.{0,255}.{0,255}.{0,255}pins the assumed reading'
qchk "v0.24.29 AC7 E29 says that mutation reading is reviewed by hand" "$E29S" 'pins the assumed reading.{0,200}(by hand|manual)'
for g8 in test-evals-grade8.sh test-evals-grade8b.sh; do
  G8F="$PB_ROOT/tests/$g8"
  G8L="$(grep -n 'MANUAL, always' "$G8F" | head -n 1 | cut -d: -f1)"
  G8T=""; [ -n "$G8L" ] && G8T="$(sed -n "${G8L},$((G8L+3))p" "$G8F")"
  if [ -n "$G8L" ] && ! printf '%s' "$G8T" | grep -qE 'present the assumption'; then t_ok "v0.24.29 AC7 $g8 header: MANUAL, always no longer lists present the assumption"; else t_bad "v0.24.29 AC7 $g8 header: MANUAL, always no longer lists present the assumption" "lines: [$G8T]"; fi
  if grep -qE '^#.*\(e\).*present the assumption' "$G8F"; then t_ok "v0.24.29 AC7 $g8 header: a comment line describes (e) present the assumption"; else t_bad "v0.24.29 AC7 $g8 header: a comment line describes (e) present the assumption" "no (e) line"; fi
done

t_summary
