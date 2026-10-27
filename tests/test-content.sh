#!/usr/bin/env bash
# Content tests for v0.6.0 instruction changes (AC5-AC11): required sections and key phrases.
. "$(dirname "$0")/lib.sh"

TDD="$PB_ROOT/skills/playbook-tdd"
SKILL="$TDD/SKILL.md"
SITU="$TDD/references/situations.md"   # v0.30.0 lane m: the R26 situational mechanics moved here from SKILL.md
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
TDDALL="$(cat "$SKILL" "$SITU" "$TESTER" "$IMPL" "$REVIEWER" "$RPROMPT" 2>/dev/null)"
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
if [ "$BLOCK_BYTES" -le 4750 ]; then t_ok "v24.1 / v0.25.0 AC9b AGENTS.global.md is <= 4750 bytes (raised from 4500 by user decision 2026-10-25) ($BLOCK_BYTES)"; else t_bad "v24.1 / v0.25.0 AC9b AGENTS.global.md is <= 4750 bytes (raised from 4500 by user decision 2026-10-25)" "$BLOCK_BYTES bytes"; fi
# every rule section keeps its exact heading and its "Why: " line
# v0.29.0 lane a: the Proof heading reads "for claims that matter" (it was "for every claim"; the body labels non-trivial claims only)
for h in '### Clarify before changing' '### Load the skill, not the summary' '### Proof for claims that matter' '### Scope discipline' \
         '### TDD with separated roles' '### When other skills overlap' '### Learnings and playbook feedback' '### First run and precedence'; do
  exact_heading "v24.1 block keeps the heading [$h]" "$BLOCK" "$h"
  if section "$BLOCK" "^$h\$" | grep -qE -- '^Why: [^ ]'; then t_ok "v24.1 [$h] keeps its Why: line"; else t_bad "v24.1 [$h] keeps its Why: line" 'no line starting with "Why: " in the section'; fi
done
exact_heading 'v24.1 block keeps its title' "$BLOCK" '## Agent Playbook (always on)'
# key rules pinned, each in its own section (joined text, so a wrapped sentence still matches)
CLAR24='^### Clarify before changing'; PROOF='^### Proof for claims that matter'; LEARN='^### Learnings and playbook feedback'; FIRST='^### First run and precedence'; OVER='^### When other skills overlap'
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
# v0.29.0 lane a: these two sentences moved (Δ = 0 for E5, docs/delta-audit.md R6) from the always-on Proof section to
# skills/playbook-proof/references/evidence-formats.md; the pins follow the text to its new place
EVF="$PB_ROOT/skills/playbook-proof/references/evidence-formats.md"
jchk 'v24.1 Proof: code claims cite path:line read this session (v0.29.0: in evidence-formats.md)' "$EVF" '^## Producing evidence' 'cite `path:line` read this session'
jchk 'v24.1 Proof: passes/works/fixed need run output via proof-run.sh (v0.29.0: in evidence-formats.md)' "$EVF" '^## Producing evidence' '"Passes", "works", "fixed" need run output from this session[^)]{0,60}proof-run\.sh'
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
if [ "$PB_AGW" -le 730 ]; then t_ok "v24.24 AC1 / v0.25.0 AC9b AGENTS.global.md keeps the 730-word budget (raised from 700 by user decision 2026-10-25) ($PB_AGW)"; else t_bad "v24.24 AC1 / v0.25.0 AC9b AGENTS.global.md keeps the 730-word budget (raised from 700 by user decision 2026-10-25)" "$PB_AGW words"; fi
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
assert_contains "v0.28.0 the shard matrix is exactly 1/7, 2/7, 3/7, 4/7, 5/7, 6/7, 7/7" "$MATRIX_LINE" "shard: ['1/7', '2/7', '3/7', '4/7', '5/7', '6/7', '7/7']"
assert_eq "v0.28.0 the matrix line is nothing but the seven-entry list" "shard: ['1/7', '2/7', '3/7', '4/7', '5/7', '6/7', '7/7']" "$(printf '%s' "$MATRIX_LINE" | sed 's/^ *//')"
for k in 1 2 3 4 5 6 7; do
  assert_contains "v0.28.0 the shard matrix has $k/7" "$SB" "$k/7"
done
assert_not_contains "v0.28.0 no matrix entry ending in /6' is left" "$SB" "/6'"
assert_not_contains "v0.24.19 AC1 no matrix entry ending in /4' is left" "$SB" "/4'"
assert_not_contains "v0.24.19 AC1 no matrix entry ending in /3' is left" "$SB" "/3'"
assert_contains "v0.24.19 AC1 the windows-shard comment says the Windows split is seven: 'split in seven'" "$SB" "split in seven"
assert_not_contains "v0.24.19 AC1 the windows-shard comment no longer says 'split in four'" "$SB" "split in four"
assert_contains "v0.24.19 AC1 the workflow comment says Windows runs as 'seven parallel shards'" "$(cat "$WF")" "seven parallel shards"
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
assert_contains "v0.28.0 the ci-tree-tested.sh header counts 'ten suite jobs'" "$CIT_HEAD" "ten suite jobs"
assert_contains "v0.28.0 the ci-tree-tested.sh header counts 'twelve green jobs'" "$CIT_HEAD" "twelve green jobs"
assert_not_contains "v0.28.0 the ci-tree-tested.sh header no longer says 'nine suite jobs'" "$CIT_HEAD" "nine suite jobs"
assert_not_contains "v0.28.0 the ci-tree-tested.sh header no longer says 'eleven green jobs'" "$CIT_HEAD" "eleven green jobs"
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
# The exclusion must be a top-level conjunct: it follows "${{" or "&&" and runs to the next "&&" or "}}" without a "|" (so always() || !startsWith(..) and !startsWith(..) || always() fail; v0.25.1 lane T).
not_tag() { printf '%s\n' "$1" | grep -Eq '([$][{][{]|&&)[[:space:]]*('"![[:space:]]*startsWith\([[:space:]]*github\.ref[[:space:]]*,[[:space:]]*'refs/tags/|github\.ref_type[[:space:]]*!=[[:space:]]*'tag'|!\(?[[:space:]]*startsWith\([[:space:]]*github\.ref"')[^&|}]*(&&|[}][}])'; }
for pair in "test:${MAIN:-__none__}" "windows-shard:${SHARD:-__none__}" "test (windows-latest) aggregator:${AGG:-__none__}" "macos-shard:${MACSHARD:-__none__}" "test (macos-latest) aggregator:${MACAGG:-__none__}"; do
  label="${pair%:*}"; id="${pair##*:}"
  IFL="$(wf_if "$id")"
  if [ -n "$IFL" ] && not_tag "$IFL"; then t_ok "v15 AC5.1 job $label ($id) has an if: that excludes tag pushes"; else t_bad "v15 AC5.1 job $label ($id) has an if: that excludes tag pushes" "if line: [$IFL]"; fi
done
# the anchored not_tag rejects the two disjunction forms of every job if: (no ${v/p/r}: cut at the first match)
for pair in "test:${MAIN:-__none__}" "windows-shard:${SHARD:-__none__}" "test (windows-latest) aggregator:${AGG:-__none__}" "macos-shard:${MACSHARD:-__none__}" "test (macos-latest) aggregator:${MACAGG:-__none__}" "reuse:reuse"; do
  label="${pair%:*}"; id="${pair##*:}"; NTL="$(wf_if "$id")"
  NTM1="$NTL"; case "$NTL" in *"&& !startsWith"*) NTM1="${NTL%%"&& !startsWith"*}|| !startsWith${NTL#*"&& !startsWith"}" ;; esac
  NTM2="$NTL"; case "$NTL" in *"!startsWith(github.ref, 'refs/tags/')"*) NTM2="${NTL%%"!startsWith(github.ref, 'refs/tags/')"*}!startsWith(github.ref, 'refs/tags/') || always()${NTL#*"!startsWith(github.ref, 'refs/tags/')"}" ;; esac
  if [ "$NTM1" != "$NTL" ] && ! not_tag "$NTM1"; then t_ok "v0.25.1 T not_tag rejects [|| !startsWith] on job $label"; else t_bad "v0.25.1 T not_tag rejects [|| !startsWith] on job $label" "line: [$NTM1]"; fi
  if [ "$NTM2" != "$NTL" ] && ! not_tag "$NTM2"; then t_ok "v0.25.1 T not_tag rejects [!startsWith || always()] on job $label"; else t_bad "v0.25.1 T not_tag rejects [!startsWith || always()] on job $label" "line: [$NTM2]"; fi
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
DEVDOC="$PB_ROOT/docs/development.md"
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
sec_flat_has 'v22.1 AC4.1 wrong: restate what was expected versus what was delivered' "$SITU" "$WRONG" 'restate[^.]{0,160}expected[^.]{0,120}deliver|expected[^.]{0,80}(vs\.?|versus|against)[^.]{0,80}deliver'
sec_flat_has 'v22.1 AC4.1 wrong: cause misread request' "$SITU" "$WRONG" 'misread'
sec_flat_has 'v22.1 AC4.1 wrong: cause missed place (scan)' "$SITU" "$WRONG" 'missed[^.]{0,30}(place|scan)'
sec_flat_has 'v22.1 AC4.1 wrong: cause wrong assumption' "$SITU" "$WRONG" 'wrong assumption'
sec_flat_has 'v22.1 AC4.1 wrong: cause not verified live' "$SITU" "$WRONG" 'not verified live'
sec_flat_has 'v22.1 AC4.1 wrong: cause real bug' "$SITU" "$WRONG" 'real bug'
sec_flat_has 'v22.1 AC4.1 wrong: classify the cause with evidence' "$SITU" "$WRONG" 'classif[^.]{0,160}(cause|evidence)|cause[^.]{0,120}evidence'
sec_flat_has 'v22.1 AC4.1 wrong: fix it test-first' "$SITU" "$WRONG" 'test[- ]first|failing test[^.]{0,80}(first|before)|(first|before)[^.]{0,80}failing test'
sec_flat_has 'v22.1 AC4.1 wrong: a playbook gap is captured with playbook-feedback' "$SITU" "$WRONG" 'playbook gap[^.]{0,200}playbook-feedback|playbook-feedback[^.]{0,200}playbook gap|gap[^.]{0,120}playbook-feedback'
sec_flat_has 'v22.1 AC4.1 wrong: the capture proposes a regression eval' "$SITU" "$WRONG" 'regression eval'
sec_flat_has 'v0.30.0 lane m SKILL.md: When the user says it is wrong points to references/situations.md' "$SKILL" "$WRONG" 'references/situations\.md#user-says-wrong'
assert_file 'v0.30.0 lane m references/situations.md exists' "$SITU"
flat_has 'v22.1 AC4.1 playbook-feedback covers the case where the user says the result is wrong' "$FB" 'user (says|said|tells)[^.]{0,80}wrong|(says|said|tells)[^.]{0,60}(result|it) (is|was) wrong'
flat_has 'v22.1 AC4.1 playbook-feedback: that capture proposes a regression eval' "$FB" 'regression eval'

# --- v0.22.1 AC5.2: how to install shellcheck is in docs/development.md
flat_has 'v22.1 AC5.2 docs/development.md says how to install shellcheck (apt install shellcheck)' "$DEVDOC" 'apt(-get)? install[^.]{0,60}shellcheck|shellcheck[^.]{0,120}apt(-get)? install'


# --- v0.22.1 review findings: content
sec_flat_has 'v22.1 RV wrong: a project-specific cause goes to playbook-learn' "$SITU" "$WRONG" 'playbook-learn'
sec_flat_has 'v22.1 RV wrong: playbook-learn is for a cause that is specific to the project' "$SITU" "$WRONG" 'project[^.]{0,120}playbook-learn|playbook-learn[^.]{0,120}project'
sec_flat_has 'v22.1 RV wrong: a docs-only (Exempt) misread is named' "$SITU" "$WRONG" 'docs-only|exempt'
sec_flat_has 'v22.1 RV wrong: docs-only misread: fix it and re-check against the request' "$SITU" "$WRONG" 're-?check[^.]{0,120}request|request[^.]{0,120}re-?check'
sec_flat_has 'v22.1 RV wrong: docs-only misread: no test is needed' "$SITU" "$WRONG" 'no (failing )?test[^.]{0,20}(needed|required)|without (a )?test|needs? no test'
sec_flat_has 'v22.1 RV Phase 4: the real-observation rule points to playbook-proof' "$SKILL" '^### Phase 4' 'real[- ](behaviou?r|observation).{0,250}playbook-proof|playbook-proof.{0,250}real[- ](behaviou?r|observation)'
SC_HEAD="$(awk '/^#+ /{h=$0} /apt(-get)? install[^.]*shellcheck/{print h; exit}' "$DEVDOC")"
if printf '%s\n' "$SC_HEAD" | grep -qiE 'develop|contribut'; then t_ok 'v22.1 RV docs/development.md: the shellcheck install note sits under a development or contributing heading'; else t_bad 'v22.1 RV docs/development.md: the shellcheck install note sits under a development or contributing heading' "nearest heading above it: [$SC_HEAD]"; fi
if printf '%s\n' "$SC_HEAD" | grep -qiE 'quality, measured'; then t_bad 'v22.1 RV docs/development.md: the shellcheck note is not inside "Quality, measured"' "heading: [$SC_HEAD]"; else t_ok 'v22.1 RV docs/development.md: the shellcheck note is not inside "Quality, measured"'; fi


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

# --- v0.22.2 AC7: docs/development.md (moved from the README in v0.25.1)
if grep -i 'concurrency' "$DEVDOC" | grep -qi 'timeout'; then t_ok 'v22.2 AC7.1 docs/development.md: one line mentions CI concurrency and timeouts'; else t_bad 'v22.2 AC7.1 docs/development.md: one line mentions CI concurrency and timeouts' 'no docs/development.md line has both words'; fi
sec_flat_has 'v22.2 AC7.1 docs/development.md Development checks section mentions tools/bsd-check.sh' "$DEVDOC" '^## Development checks' 'tools/bsd-check\.sh'


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

# --- v0.22.3 AC6.4: docs/development.md
echo "v22.3 AC6.4 docs/development.md"
flat_has 'v22.3 AC6.4 docs/development.md: a main push reuses a green PR run' "$DEVDOC" 'main push[^.]{0,250}reus|reus[^.]{0,250}main push'
flat_has 'v22.3 AC6.4 docs/development.md: the reused run is a same-repo PR run' "$DEVDOC" 'same[- ]repo(sitory)?[^.]{0,120}(PR|pull request)|(PR|pull request)[^.]{0,120}same[- ]repo'
flat_has 'v22.3 AC6.4 docs/development.md: ... of the identical tree' "$DEVDOC" 'identical tree|same tree|tree[^.]{0,60}identical'
flat_has 'v22.3 AC6.4 docs/development.md: ... that was green' "$DEVDOC" 'green[^.]{0,120}(PR|pull request)[^.]{0,120}run|(PR|pull request)[^.]{0,60}run[^.]{0,80}green'
# --- v0.22.4 AC4: parallel slices (SKILL.md Phase 2)
echo "v22.4 AC4.1 SKILL.md Phase 2: parallel slices in separate worktrees"
P2='^### Phase 2'
sec_flat_has 'v22.4 AC4.1 Phase 2 allows parallel slices' "$SKILL" "$P2" 'parallel'
sec_flat_has 'v22.4 AC4.1 only slices with disjoint files may run in parallel' "$SKILL" "$P2" 'disjoint[^.]{0,80}files?|files?[^.]{0,60}disjoint'
sec_flat_has 'v22.4 AC4.1 the disjoint files come from the spec Impact section' "$SITU" '^## Parallel slices' 'disjoint[^.]{0,200}impact|impact[^.]{0,200}disjoint'
sec_flat_has 'v22.4 AC4.1 each parallel slice has its own git worktree' "$SKILL" "$P2" 'separate (git )?worktrees?|(own|its own|each)[^.]{0,40}(git )?worktree'
sec_flat_has 'v22.4 AC4.1 each worktree has its own red/green commits and role gates' "$SKILL" "$P2" '(own|each)[^.]{0,200}(role[- ])?gates?'
sec_flat_has 'v22.4 AC4.1 the orchestrator merges the slice branches' "$SITU" '^## Parallel slices' 'orchestrator[^.]{0,80}merges?|merged by the orchestrator'
sec_flat_has 'v22.4 AC4.1 a merge conflict sends the slices back to serial work' "$SITU" '^## Parallel slices' 'conflict[^.]{0,160}serial|serial[^.]{0,160}conflict'
sec_flat_has 'v22.4 AC4.1 one review of the merged feature' "$SITU" '^## Parallel slices' 'one (fresh )?review(er)?[^.]{0,80}merged|merged[^.]{0,80}one (fresh )?review'
sec_flat_has 'v22.4 AC4.1 slices that share a file stay serial' "$SKILL" "$P2" 'shar(e|es|ing)[^.]{0,40}files?[^.]{0,80}serial'
# v0.26.1 lane G AC-D1 (S6): one sentence of the Parallel slices paragraph points slices that share one worktree to
# `role-gate.sh check --commits A..B`; the conflict-serial pin above and the word budget (v25 AC1 below, R13 in test-skill-rules.sh) still hold
echo "v0.26.1 AC-D1 SKILL.md Parallel slices: a shared worktree gates each role with --commits A..B"
PARA="$(awk '/^\*\*Parallel slices\./ { p = 1 } p && /^$/ { exit } p' "$SITU" | tr '\n' ' ' | tr -s ' ')"
if printf '%s' "$PARA" | grep -qiE -- '(shar(e|es|ing)|same|one)[^.]{0,80}worktree[^.]{0,160}--commits A\.\.B|--commits A\.\.B[^.]{0,160}(shar(e|es|ing)|same|one)[^.]{0,80}worktree'; then t_ok 'v0.26.1 AC-D1 the Parallel slices paragraph: slices sharing one worktree gate each role with --commits A..B'; else t_bad 'v0.26.1 AC-D1 the Parallel slices paragraph: slices sharing one worktree gate each role with --commits A..B' "paragraph: $PARA"; fi
NCM="$(grep -o -- '--commits' "$SITU" | wc -l | tr -d ' ')"
assert_eq 'v0.26.1 AC-D1 references/situations.md names --commits exactly once (at most one sentence, T3; moved from SKILL.md in v0.30.0 lane m)' "1" "$NCM"
assert_eq 'v0.30.0 lane m SKILL.md no longer names --commits' "0" "$(grep -o -- '--commits' "$SKILL" | wc -l | tr -d ' ')"
sec_flat_has 'v0.30.0 lane m SKILL.md Parallel slices points to references/situations.md' "$SKILL" "$P2" 'Slices whose files are disjoint[^.]{0,200}references/situations\.md#parallel-slices'

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
if flat "$DEVDOC" | grep -qiE 'rebase[^.]{0,80}always[^.]{0,60}run'; then t_bad 'v22.3 review Low-2 docs/development.md no longer says rebase merges always run the tests' 'the old claim is still there'; else t_ok 'v22.3 review Low-2 docs/development.md no longer says rebase merges always run the tests'; fi
flat_has 'v22.3 review Low-2 docs/development.md: a rebase merge reuses a run only when its single resulting commit has the PR head tree' "$DEVDOC" 'rebase merge[^.]{0,250}only when[^.]{0,250}(single|one)[^.]{0,80}commit[^.]{0,200}tree'
flat_has 'v22.3 review Low-2 docs/development.md: ... and the PR head parent P' "$DEVDOC" 'rebase merge[^.]{0,250}only when[^.]{0,250}(parent|P)\b'
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

# --- v0.23.0 review: docs/development.md does not oversell the reduced path
if flat "$DEVDOC" | grep -qiE -- 'docs-only[^.]{0,250}every required job|every required job[^.]{0,250}docs-only'; then t_bad 'v23.0 review docs/development.md does not say the reduced checks run in "every required job"' 'the phrase is still next to Docs-only'; else t_ok 'v23.0 review docs/development.md does not say the reduced checks run in "every required job"'; fi

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
if [ "$AGB" -le 4750 ]; then t_ok "AC6.1 / v0.25.0 AC9b AGENTS.global.md stays within 4750 bytes (raised from 4500 by user decision 2026-10-25) ($AGB)"; else t_bad "AC6.1 / v0.25.0 AC9b AGENTS.global.md stays within 4750 bytes (raised from 4500 by user decision 2026-10-25)" "$AGB bytes"; fi

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
# v0.26.0 lane N S8 (AC13, D17): the README scenario counts are derived from the ## E headings of scenarios.md and the AUTO line, never literals
SCN26="$PB_ROOT/evals/scenarios.md"
NH26="$(grep -c '^## E[0-9]' "$SCN26")"
MAX26="$(sed -n 's/^## E\([0-9][0-9]*\) .*/\1/p' "$SCN26" | sort -n | tail -n 1)"
NAUTO26="$(sed -n 's/^AUTO="\(.*\)"$/\1/p' "$PB_ROOT/evals/run-evals.sh" | head -n 1 | wc -w | tr -d ' ')"
README26="$(tr '\n' ' ' < "$PB_ROOT/README.md")"
qchk "v25 AC3 v26 N AC13 README names scenarios.md (E1–E$MAX26) (derived from the ## E headings)" "$README26" "scenarios\.md \(E1–E$MAX26\)"
qchk "v26 N AC13 README says $NH26 scenarios, E1 to E$MAX26 (derived)" "$README26" "(^|[^0-9])$NH26 scenarios, E1 to E$MAX26([^0-9]|$)"
qchk "v26 N AC13 README says run-evals.sh runs the $NAUTO26 that have automatic checks (derived from AUTO)" "$README26" "runs the $NAUTO26 that have automatic checks"
for e in E2 E6 E13 E14 E32 E33 E34; do
  qchk "v26 N AC12 RUBRIC.md lists $e as auto-gradable" "$RUBTXT" "$e[^0-9][^.]{0,250}auto-gradable"
done
echo "v0.26.0 lane N S8 AC13 (Q2), v0.29.0 Run C1: the harness badge and the Behaviour evals row say Codex is partly evaluated and OpenCode is installable, not evaluated"
BADGE26="$(grep -o 'img\.shields\.io/badge/harness-[^)]*' "$PB_ROOT/README.md" | head -n 1)"
qchk "v26 N AC13 the harness badge says Claude Code is evaluated" "$BADGE26" 'Claude_Code[_ (:%0-9a-f]{0,12}evaluated'
qchk "v29 Run C1 the harness badge says Codex is partly evaluated" "$BADGE26" 'Codex[:_ ]{0,4}partly_evaluated'
if printf '%s' "$BADGE26" | grep -qE 'Codex,_OpenCode|Codex[:_ ]{0,4}(installable|not_evaluated)'; then t_bad "v29 Run C1 the harness badge has no Codex not-evaluated text" "[$BADGE26]"; else t_ok "v29 Run C1 the harness badge has no Codex not-evaluated text"; fi
qchk "v26 N AC13 the harness badge says OpenCode is install only or not evaluated" "$BADGE26" 'OpenCode[^)]{0,60}(not_evaluated|not%20evaluated|install_only|install%20only|installable)'
assert_not_contains "v26 N AC13 the old harness badge text is gone" "$BADGE26" "harness-Claude_Code_·_Codex_·_OpenCode-"
ROW26="$(grep '^| Behaviour evals |' "$PB_ROOT/README.md" | head -n 1)"
qchk "v29 Run C1 the Behaviour evals row says Codex is partly evaluated and names Run C1" "$ROW26" 'Codex[^|;]{0,20}partly evaluated[^|;]{0,40}Run C1'
qchk "v26 N AC13 the Behaviour evals row says OpenCode is installable, not evaluated" "$ROW26" 'OpenCode[^|;]{0,20}installable[^|;]{0,20}not evaluated'
qchk "v26 N AC13 the Behaviour evals row keeps Claude Code as the only evaluated harness" "$ROW26" 'Claude Code[^|;]{0,40}only'
assert_not_contains "v26 N AC13 the Behaviour evals row no longer says not run yet" "$ROW26" "not run yet"
echo "v0.26.0 lane N S8 AC14 (D10): the scenario map names the new auto-graded scenarios"
AGMAP26="$(grep -E '^AGENTS\.global\.md ' "$PB_ROOT/evals/scenario-map")"
for e in E2 E13 E33 E34; do qchk "v26 N AC14 $e is in the scenario-map line of AGENTS.global.md" "$AGMAP26" "(^| )$e( |$)"; done
qchk "v26 N AC14 E6 is in the scenario-map line of skills/playbook-proof/*" "$(grep -E '^skills/playbook-proof/\* ' "$PB_ROOT/evals/scenario-map")" '(^| )E6( |$)'
qchk "v26 N AC14 E14 is in the scenario-map line of skills/playbook-tdd/*" "$(grep -E '^skills/playbook-tdd/\* ' "$PB_ROOT/evals/scenario-map")" '(^| )E14( |$)'
qchk "v26 N AC14 E32 is in the scenario-map line of skills/playbook-tdd/roles/*" "$(grep -E '^skills/playbook-tdd/roles/\* ' "$PB_ROOT/evals/scenario-map")" '(^| )E32( |$)'
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
if [ "$PROOF_WORDS" -le 700 ]; then t_ok "v24.10 AC8 / v0.25.0 AC8 playbook-proof SKILL.md is at most 700 words (raised from 647 by user decision 2026-10-25)"; else t_bad "v24.10 AC8 / v0.25.0 AC8 playbook-proof SKILL.md is at most 700 words (raised from 647 by user decision 2026-10-25)" "$PROOF_WORDS words"; fi
TB="$(budget_of skills/playbook-tdd/SKILL.md)"; PB="$(budget_of skills/playbook-proof/SKILL.md)"
if [ -n "$TB" ] && [ "$TB" -ge "$TDD_WORDS" ] && [ "$TB" -le $((TDD_WORDS + 50)) ] && [ "$TB" -le 3850 ]; then t_ok "v24.10 AC9 playbook-tdd budget is count..count+50 and at most 3850"; else t_bad "v24.10 AC9 playbook-tdd budget is count..count+50 and at most 3850" "budget [$TB] count $TDD_WORDS"; fi
if [ -n "$PB" ] && [ "$PB" -ge "$PROOF_WORDS" ] && [ "$PB" -eq 700 ]; then t_ok "v24.10 AC9 / v0.25.0 AC8 playbook-proof budget in evals/word-budgets is 700 and not below the count"; else t_bad "v24.10 AC9 / v0.25.0 AC8 playbook-proof budget in evals/word-budgets is 700 and not below the count" "budget [$PB] count $PROOF_WORDS"; fi
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
# v0.30.0 lane m: the user moved it to 3700 on 2026-10-23; the measured slimming (queue P0-2) lowers it to the new count rounded up
if [ "$SKB" = "3350" ]; then t_ok "v0.24.29 AC8 / v0.30.0 lane m evals/word-budgets gives playbook-tdd SKILL.md exactly 3350 (3700 until the R26 move)"; else t_bad "v0.24.29 AC8 / v0.30.0 lane m evals/word-budgets gives playbook-tdd SKILL.md exactly 3350 (3700 until the R26 move)" "budget [$SKB]"; fi
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
# O-fix F8: the line is a placeholder instruction in angle brackets, not a literal bullet the report would carry over as a finding
sec_flat_has "O-fix F8 final-report.md Found, not fixed: the mutant line is a placeholder (<if a killed mutant ...>)" "$FINAL" '^## Found, not fixed' '<if a killed mutant[^>]*pins the assumed reading[^>]*>'
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
qchk "v0.24.29 AC7 E29 MANUAL reason: oracle id unclear" "$E29E" 'oracle id (is )?unclear'
qchk "v0.24.29 AC7 E29 MANUAL reason: no qualifying test file" "$E29E" 'no qualifying test file'
qchk "v0.24.29 AC7 E29 MANUAL reason: --interactive" "$E29E" 'interactive'
qchk "v0.24.29 AC7 E29 MANUAL reason: absent or other bucket" "$E29E" 'bucket|absent'
qchk "v0.24.29 AC7 E29 Pass if: a mutation result on such a test pins the assumed reading" "$E29S" 'Pass if:.{0,255}.{0,255}.{0,255}pins the assumed reading'
qchk "v0.24.29 AC7 E29 says that mutation reading is reviewed by hand" "$E29S" 'pins the assumed reading.{0,200}(by hand|manual)'
# O-fix F4: the sentence must not read as if a result that pins the assumed reading FAILS; reporting such a result as a caught bug is what fails
qchk "O-fix F4 E29 Pass if: reporting the mutation result as catching a bug fails the check" "$E29S" 'catching a bug fails (this|the check)'
if printf '%s' "$E29S" | grep -qiE 'pins the assumed reading[^;)]{0,80}fails'; then t_bad "O-fix F4 E29 Pass if: pins the assumed reading is not what fails" "inverted reading"; else t_ok "O-fix F4 E29 Pass if: pins the assumed reading is not what fails"; fi
qchk "O-fix F4 E29 Pass if: reporting it as pinning the assumed reading is correct" "$E29S" 'pins the assumed reading[^;]{0,120}is correct'
if printf '%s' "$E29S" | grep -qF ',;'; then t_bad "O-fix F4 E29 Pass if: no ',;' typo" "found"; else t_ok "O-fix F4 E29 Pass if: no ',;' typo"; fi
qchk "O-fix F4 E29 (e): MANUAL when the oracle id is unclear (grammar)" "$E29S" 'MANUAL when the oracle id is unclear'
for g8 in test-evals-grade8.sh test-evals-grade8b.sh; do
  G8F="$PB_ROOT/tests/$g8"
  G8L="$(grep -n 'MANUAL, always' "$G8F" | head -n 1 | cut -d: -f1)"
  G8T=""; [ -n "$G8L" ] && G8T="$(sed -n "${G8L},$((G8L+3))p" "$G8F")"
  if [ -n "$G8L" ] && ! printf '%s' "$G8T" | grep -qE 'present the assumption'; then t_ok "v0.24.29 AC7 $g8 header: MANUAL, always no longer lists present the assumption"; else t_bad "v0.24.29 AC7 $g8 header: MANUAL, always no longer lists present the assumption" "lines: [$G8T]"; fi
  if grep -qE '^#.*\(e\).*present the assumption' "$G8F"; then t_ok "v0.24.29 AC7 $g8 header: a comment line describes (e) present the assumption"; else t_bad "v0.24.29 AC7 $g8 header: a comment line describes (e) present the assumption" "no (e) line"; fi
done

# ---- v0.24.30 lane K (S1): a Lite test on an unconfirmed oracle Dn says so; the Lite and template Pre-mortems say it pins the reading ----
echo "v0.24.30 lane K (S1): Lite step 2 and step 5, template Pre-mortem"
# AC1: Lite step 2 names the unconfirmed oracle by its decision id and says the name or a comment carries Dn or [UNVERIFIED]
lite_has "v0.24.30 AC1 Lite step 2: unconfirmed oracle Dn, the test name or a comment carries Dn or [UNVERIFIED]" 2 'unconfirmed oracle,? Dn[^.]{0,20}name or (in )?a comment[^.]{0,20}`?Dn`? or `?\[UNVERIFIED\]'
# AC2 regression: step 2 keeps its old rules (pass today and after)
lite_has "v0.24.30 AC2 Lite step 2 still runs proof-run.sh --label red" 2 'proof-run\.sh --label red'
lite_has "v0.24.30 AC2 Lite step 2 still says see it fail for the right reason" 2 'right reason'
lite_has "v0.24.30 AC2 Lite step 2 still commits test(red)" 2 'test\(red\)'
# AC3: Lite step 5 Pre-mortem clause
lite_has "v0.24.31 AC3 Lite step 5 Pre-mortem: a test on Dn pins the assumed reading and cannot tell which is right (lane K NIT)" 5 'pre-mortem[^.]{0,80}Dn[^.]{0,40}pins the assumed reading[^.]{0,30}cannot tell which[^.]{0,10} is right'
# the old clause was false at code level (a multiply test does fail under divide)
if lite_step 5 | tr '\n' ' ' | grep -qiE '(never|not) catch(es)? the other reading'; then t_bad "v0.24.31 AC3 Lite step 5 no longer says the test never catches the other reading" "old clause still there"; else t_ok "v0.24.31 AC3 Lite step 5 no longer says the test never catches the other reading"; fi
lite_has "v0.24.31 AC1 Lite step 2 says the test's name (lane K NIT)" 2 "the test's name or a comment"
# AC4: the template Pre-mortem has the angle-bracket placeholder (not a literal line a report would carry over)
sec_flat_has "v0.24.30 AC4 final-report.md Pre-mortem: placeholder <if a risk rests on a test built on an unconfirmed oracle ...> pins the assumed reading, not the other reading" "$FINAL" '^## Pre-mortem' '<if a risk rests on a test built on an unconfirmed oracle[^>]*(Dn|\[UNVERIFIED\])[^>]*pins the assumed reading[^>]*cannot tell which reading is right[^>]*>'

# ---- v0.25.0 lane H (S1): skills/playbook-proof/references/writing.md, the proof pointer, the 700 pins ----
echo "v0.25.0 lane H (S1): writing guide (AC1-AC6, AC9a sentence, AC15), proof pointer (AC8)"
WM="$PB_ROOT/skills/playbook-proof/references/writing.md"
# wm_has NAME PATTERN: PATTERN (case-insensitive ERE) is in the flattened writing.md; a missing file fails
wm_has() { if [ -f "$WM" ] && flat "$WM" | grep -qiE -- "$2"; then t_ok "$1"; else t_bad "$1" "pattern [$2] not in $WM (or the file is missing)"; fi; }
# wm_has_f NAME LITERAL: the exact text is in writing.md (fixed string, case-sensitive)
wm_has_f() { if [ -f "$WM" ] && grep -qF -- "$2" "$WM"; then t_ok "$1"; else t_bad "$1" "literal [$2] not in $WM (or the file is missing)"; fi; }

# AC1: exists, at most 400 words (proposal: about 300; a stub under 120 words cannot hold the AC2 rules)
WM_WORDS=""; [ -f "$WM" ] && WM_WORDS="$(wc -w < "$WM" | tr -d ' ')"
if [ -n "$WM_WORDS" ] && [ "$WM_WORDS" -le 400 ] && [ "$WM_WORDS" -ge 120 ]; then t_ok "v0.25.0 AC1 writing.md exists and has 120..400 words"; else t_bad "v0.25.0 AC1 writing.md exists and has 120..400 words" "words [$WM_WORDS] (empty = file missing)"; fi

# AC2: one row for each humanizer section the guide must carry
wm_has "v0.25.0 AC2 s1 not X but Y" 'not x,? but y|not (just|only|merely) [^.]{0,40}but'
wm_has "v0.25.0 AC2 s2 one-line closers" 'one-(line|sentence) (closer|paragraph)|closing (line|sentence)[^.]{0,60}(repeat|restat)'
wm_has "v0.25.0 AC2 s3 sayings that sound deep" 'saying|aphorism|sounds? (deep|profound)|profound|slogan'
wm_has "v0.25.0 AC2 s4 staged run-up" 'run-up|staged|staging|build-?up|stage-setting|setting the stage'
wm_has "v0.25.0 AC2 s12 names the overused AI words as a group" 'overused|stock (ai )?words|ai words'
WM_AIW=0
for w12 in delve crucial pivotal tapestry testament landscape robust showcase underscore vibrant intricate enhance meticulous additionally; do
  if [ -f "$WM" ] && grep -qiw -- "$w12" "$WM"; then WM_AIW=$((WM_AIW + 1)); fi
done
if [ "$WM_AIW" -ge 4 ]; then t_ok "v0.25.0 AC2 s12 lists at least 4 of the overused words ($WM_AIW)"; else t_bad "v0.25.0 AC2 s12 lists at least 4 of the overused words" "only $WM_AIW of the humanizer s12 words found"; fi
wm_has "v0.25.0 AC2 s13 inflated significance" 'inflated|significance|legacy'
wm_has "v0.25.0 AC2 s20 decorative headings" 'decorative|decoration'
wm_has "v0.25.0 AC2 s20 emojis" 'emoji'
wm_has "v0.25.0 AC2 s22 chatbot residue" 'chatbot'
wm_has "v0.25.0 AC2 s22 names openers" 'opener|great question|certainly'
wm_has "v0.25.0 AC2 s22 names offers" "offer|would you like|want me to|let me know"
wm_has "v0.25.0 AC2 s26 lead with the answer" 'lead with the (answer|decision|point|conclusion)|answer first|(answer|decision|point) (comes )?first'
wm_has "v0.25.0 AC2 s26 the reader already knows" 'reader[^.]{0,80}(already|knows|has the context)|already (know|has|have|agreed)|re-?explain'

# AC2b: s8 dashes
EMD="$(printf '\342\200\224')"; ENDASH="$(printf '\342\200\223')"
wm_has "v0.25.0 AC2b s8 names em and en dashes" '(em|en)[ -]?dash|(em|en) and (em|en) dash|dashes'
wm_has "v0.25.0 AC2b s8 gives the replacements (comma, colon, period or parentheses)" 'comma[^.]{0,60}colon[^.]{0,60}(period|parenthes)|(period|parenthes)[^.]{0,60}(comma|colon)'
wm_has "v0.25.0 AC2b s8 exempts code spans, blocks, commands and paths" '(code (span|block)|inline code|backtick)[^.]{0,200}(command|path)|(command|path)[^.]{0,200}(code (span|block)|inline code|backtick)'
# the guide follows its own rule: no em or en dash outside backtick spans and fenced blocks
WM_DASH_OUT=""
if [ -f "$WM" ]; then
  WM_DASH_OUT="$(awk '/^```/{f=!f; next} !f{print}' "$WM" | sed 's/`[^`]*`//g' | grep -c -e "$EMD" -e "$ENDASH")"
fi
if [ -f "$WM" ] && [ "$WM_DASH_OUT" = "0" ]; then t_ok "v0.25.0 AC2b writing.md has no em or en dash outside code spans and blocks"; else t_bad "v0.25.0 AC2b writing.md has no em or en dash outside code spans and blocks" "lines with a dash [$WM_DASH_OUT] (empty = file missing)"; fi

# AC3: what the rules never touch, each item named
wm_has "v0.25.0 AC3 says what the rules never touch (verbatim, leave alone)" '(never|do not|must not)[^.]{0,30}(touch|change|edit|reword|rewrite|polish|alter)|leave[^.]{0,40}(alone|as (is|written))|unchanged|verbatim'
wm_has_f "v0.25.0 AC3 never-touch: the **Weight:** line" '**Weight:**'
wm_has_f "v0.25.0 AC3 never-touch: the **Models used:** line" '**Models used:**'
wm_has_f "v0.25.0 AC3 never-touch: the **Playbook feedback:** line" '**Playbook feedback:**'
wm_has_f "v0.25.0 AC3 never-touch: the **Result:** line" '**Result:**'
wm_has_f "v0.25.0 AC3 never-touch: the **Mode:** line" '**Mode:**'
wm_has_f "v0.25.0 AC3 never-touch: the label [VERIFIED]" '[VERIFIED]'
wm_has_f "v0.25.0 AC3 never-touch: the label [INFERRED]" '[INFERRED]'
wm_has_f "v0.25.0 AC3 never-touch: the label [UNVERIFIED]" '[UNVERIFIED]'
wm_has "v0.25.0 AC3 never-touch: the user's quoted sentences in Request coverage" 'request coverage'
wm_has "v0.25.0 AC3 never-touch: the Not checked section" 'not checked'
wm_has "v0.25.0 AC3 never-touch: the Pre-mortem section" 'pre-mortem'
wm_has "v0.25.0 AC3 never-touch: evidence (commands, outputs, path:line)" 'evidence[^.]{0,120}(command|output|path:line)|(command|output|path:line)[^.]{0,120}evidence'
wm_has "v0.25.0 AC3 never-touch: path:line references" 'path:line|file:line'
wm_has "v0.25.0 AC3 covers what scripts/pr-body.sh copies into a PR description" 'pr-body'
wm_has "v0.25.0 AC3 pr-body.sh note names Review and Weight beside Request coverage and Not checked" '(review[^.]{0,100}weight|weight[^.]{0,100}review)[^.]{0,200}pr-body'

# AC4: cut or reorder, never add
wm_has "v0.25.0 AC4 editing may cut or reorder" '(cut|remove|delete|trim)[^.]{0,60}reorder|reorder[^.]{0,60}(cut|remove|delete|trim)'
wm_has "v0.25.0 AC4 never add a fact" '(never|not|no|without)[^.]{0,40}(add|invent|introduce)[^.]{0,120}fact|(fact|name|number|promise)[^.]{0,80}(not in|absent from|missing from|that the source (does not|doesn.t))[^.]{0,30}(source|original|draft)'
wm_has "v0.25.0 AC4 the ban covers a name, a number and a promise" '(add|invent|introduce)[^.]{0,120}(name|number)[^.]{0,60}(promise)|(promise)[^.]{0,60}(name|number)'

# AC5: credit and license
wm_has "v0.25.0 AC5 links github.com/blader/humanizer" 'github\.com/blader/humanizer'
wm_has_f "v0.25.0 AC5 names the MIT license" 'MIT'

# AC6: when to load it
wm_has "v0.25.0 AC6 load for the final report" 'final report'
wm_has "v0.25.0 AC6 load for a PR description" 'pr description|pull request'
wm_has "v0.25.0 AC6 load for release notes or the CHANGELOG" 'release notes|changelog'
wm_has "v0.25.0 AC6 load for README or docs" 'readme|docs'
wm_has "v0.25.0 AC6 load for issue comments" 'issue comment|comment on an issue|issue thread'

# AC9a (lives in writing.md): with no other question, ask on its own only when the main deliverable is text others will read
wm_has "v0.25.0 AC9a names the humanizer skill" 'humanizer'
wm_has "v0.25.0 AC9a main deliverable is text others will read, in a sentence about asking" 'main deliverable[^.]{0,200}ask|ask[^.]{0,200}main deliverable'
wm_has "v0.25.0 AC9a it applies when the task has no other question" '(no|any|other)[^.]{0,30}question[^.]{0,200}main deliverable|main deliverable[^.]{0,200}(no|any|other)[^.]{0,30}question|task has no other question'
wm_has "v0.25.0 AC9a otherwise: use these rules without asking" '(otherwise|else|if not|when it is not)[^.]{0,200}(do(es)? not ask|never ask|without asking|no question|silently|don.t ask|skip)'

# AC15: nothing tells the agent to remove bold from the required labels (any sentence on bold that says remove/strip/drop must also say keep/never/except)
WM_BOLD_BAD=""
if [ -f "$WM" ]; then
  WM_BOLD_BAD="$(flat "$WM" | tr '.' '\n' | grep -i 'bold' | grep -iE 'remov|strip|drop|delet|unbold|no bold|avoid' | grep -viE 'never|not |keep|except|leave|required|verbatim' | wc -l | tr -d ' ')"
fi
if [ -f "$WM" ] && [ "$WM_BOLD_BAD" = "0" ]; then t_ok "v0.25.0 AC15 writing.md never says to remove bold from required labels"; else t_bad "v0.25.0 AC15 writing.md never says to remove bold from required labels" "sentences [$WM_BOLD_BAD] (empty = file missing)"; fi

# AC8: proof SKILL.md pointer (one short line) and the tdd SKILL.md stays within its budget
PROOF_PTR="$(grep -F 'references/writing.md' "$PROOF_MD" 2>/dev/null | head -n 1)"
if [ -n "$PROOF_PTR" ]; then t_ok "v0.25.0 AC8 playbook-proof SKILL.md points to references/writing.md"; else t_bad "v0.25.0 AC8 playbook-proof SKILL.md points to references/writing.md" "no line names it"; fi
PTR_WORDS="$(printf '%s\n' "$PROOF_PTR" | wc -w | tr -d ' ')"
if [ -n "$PROOF_PTR" ] && [ "$PTR_WORDS" -le 28 ]; then t_ok "v0.25.0 AC8 the proof pointer line is short (at most 28 words, spec: about 20) ($PTR_WORDS)"; else t_bad "v0.25.0 AC8 the proof pointer line is short (at most 28 words, spec: about 20)" "words [$PTR_WORDS] line [$PROOF_PTR]"; fi
if printf '%s' "$PROOF_PTR" | grep -qiE 'others|readers?|reads?|written|write|report'; then t_ok "v0.25.0 AC8 the proof pointer says it is for text others will read"; else t_bad "v0.25.0 AC8 the proof pointer says it is for text others will read" "line [$PROOF_PTR]"; fi
# characterization (true today by design): playbook-tdd SKILL.md gets at most a few words, so it stays within its 3700 budget
if [ "$TDD_WORDS" -le 3700 ]; then t_ok "v0.25.0 AC8 characterization: playbook-tdd SKILL.md stays at most 3700 words ($TDD_WORDS)"; else t_bad "v0.25.0 AC8 characterization: playbook-tdd SKILL.md stays at most 3700 words" "$TDD_WORDS words"; fi

# ---- v0.25.0 lane H (S2): the always-on ask rule (AC9), its budgets (AC9b), the humanizer key (AC10), the setup suggestion (AC11), the setup budget (AC12) ----
echo "v0.25.0 lane H (S2): AC9 the ask rule is appended to the Ask once bullet of AGENTS.global.md"
ASKB_PFX='- Ask once, batched, each with your proposed default.'
ASKB_LINE="$(grep -F -- "$ASKB_PFX" "$BLOCK" | head -n 1)"
ASKB_SFX=""
if [ -n "$ASKB_LINE" ] && [ "${ASKB_LINE#"$ASKB_PFX"}" != "$ASKB_LINE" ]; then ASKB_SFX="${ASKB_LINE#"$ASKB_PFX"}"; fi
ASKB_BYTES="$(printf '%s' "$ASKB_SFX" | wc -c | tr -d ' ')"
# characterization (true today by design): the bullet keeps its exact opening, so the existing :276 pin and the 39 lines hold
if [ -n "$ASKB_LINE" ] && [ "${ASKB_LINE#"$ASKB_PFX"}" != "$ASKB_LINE" ]; then t_ok "v0.25.0 AC9 the Ask once bullet starts with its exact old text (line 7 of AGENTS.global.md)"; else t_bad "v0.25.0 AC9 the Ask once bullet starts with its exact old text (line 7 of AGENTS.global.md)" "line [$ASKB_LINE]"; fi
case "$ASKB_SFX" in " Text others will read"*) t_ok "v0.25.0 AC9 the appended text follows a single space and starts with the words Text others will read";; *) t_bad "v0.25.0 AC9 the appended text follows a single space and starts with the words Text others will read" "text after the old bullet: [$ASKB_SFX]";; esac
if [ "$ASKB_BYTES" -ge 60 ] && [ "$ASKB_BYTES" -le 270 ]; then t_ok "v0.25.0 AC9 the appended text is 60..270 bytes including the joining space ($ASKB_BYTES)"; else t_bad "v0.25.0 AC9 the appended text is 60..270 bytes including the joining space" "bytes [$ASKB_BYTES] (0 = nothing appended)"; fi
# the text lives on that one line: the block gets no new line, and the phrase appears nowhere else in it
if [ "$(grep -cF -- 'Text others will read' "$BLOCK")" = "1" ] && [ "$(grep -F -- 'Text others will read' "$BLOCK")" = "$ASKB_LINE" ]; then t_ok "v0.25.0 AC9 Text others will read appears once in the block, on the Ask once bullet"; else t_bad "v0.25.0 AC9 Text others will read appears once in the block, on the Ask once bullet" "count [$(grep -cF -- 'Text others will read' "$BLOCK")]"; fi
ask_has() { if printf '%s' "$ASKB_SFX" | grep -qiE -- "$2"; then t_ok "$1"; else t_bad "$1" "pattern [$2] not in the text appended to the Ask once bullet [$ASKB_SFX]"; fi; }
if printf '%s' "$ASKB_SFX" | grep -qF -- 'references/writing.md'; then t_ok "v0.25.0 AC9 the appended text names references/writing.md"; else t_bad "v0.25.0 AC9 the appended text names references/writing.md" "text [$ASKB_SFX]"; fi
if printf '%s' "$ASKB_SFX" | grep -qF -- 'playbook-proof'; then t_ok "v0.25.0 AC9 the appended text names the skill playbook-proof"; else t_bad "v0.25.0 AC9 the appended text names the skill playbook-proof" "text [$ASKB_SFX]"; fi
ask_has "v0.25.0 AC9 the appended text gives examples of text others will read (PR description, release notes, docs or a report)" 'pr description|release notes|docs|report'
ask_has "v0.25.0 AC9 the appended text mentions a humanizer skill and running it in full" 'humanizer[^.;]{0,100}in full|in full[^.;]{0,60}humanizer'
ask_has "v0.25.0 AC9 the appended text asks about humanizer (it is a question, not an automatic run)" 'ask[^.;]{0,80}humanizer|humanizer[^.;]{0,80}ask'
ask_has "v0.25.0 AC9 the appended text excludes chat replies" '(never|not|no|except|excluding|skip)[^.;]{0,40}chat repl|chat repl[^.;]{0,40}(never|no|not|excluded|skip)'
ask_has "v0.25.0 AC9 the appended text says headless: no question" 'headless[^.;]{0,30}(no|not|never|without)[^.;]{0,20}(question|ask)'

echo "v0.25.0 lane H (S2): AC9b the always-on budget is 730 words in evals/word-budgets"
AGW_B="$(budget_of AGENTS.global.md)"
if [ "$AGW_B" = "730" ]; then t_ok "v0.25.0 AC9b evals/word-budgets gives AGENTS.global.md exactly 730 (user decision 2026-10-25)"; else t_bad "v0.25.0 AC9b evals/word-budgets gives AGENTS.global.md exactly 730 (user decision 2026-10-25)" "budget [$AGW_B]"; fi
if [ -n "$AGW_B" ] && [ "$PB_AGW" -le "$AGW_B" ]; then t_ok "v0.25.0 AC9b AGENTS.global.md is within its word budget ($PB_AGW <= $AGW_B)"; else t_bad "v0.25.0 AC9b AGENTS.global.md is within its word budget" "words $PB_AGW budget [$AGW_B]"; fi
# the hard cap stays at 5000 bytes and the block stays at 39 lines (the 4750 and 730 pins moved in place above)
if [ "$PB_AGL" -eq 39 ]; then t_ok "v0.25.0 AC9b AGENTS.global.md is exactly 39 lines (the text is appended, not added as a line) ($PB_AGL)"; else t_bad "v0.25.0 AC9b AGENTS.global.md is exactly 39 lines (the text is appended, not added as a line)" "$PB_AGL lines"; fi

echo "v0.25.0 lane H (S2): AC10 the humanizer key is documented in setup"
SETUP_F="$(cat "$SETUP" "$QUESTIONS" 2>/dev/null | tr '\n' ' ' | tr -s ' ')"
st_has() { if printf '%s' "$SETUP_F" | grep -qiE -- "$2"; then t_ok "$1"; else t_bad "$1" "pattern [$2] not in playbook-setup SKILL.md + references/questions.md"; fi; }
st_has_f() { if printf '%s' "$SETUP_F" | grep -qF -- "$2"; then t_ok "$1"; else t_bad "$1" "literal [$2] not in playbook-setup SKILL.md + references/questions.md"; fi; }
QH_LINE="$(grep -E '^- `humanizer` \(global\)' "$QUESTIONS" 2>/dev/null | head -n 1)"
qh_has() { if printf '%s' "$QH_LINE" | grep -qiE -- "$2"; then t_ok "$1"; else t_bad "$1" "pattern [$2] not in the humanizer line of the optional keys list [$QH_LINE]"; fi; }
if [ -n "$QH_LINE" ]; then t_ok "v0.25.0 AC10 questions.md optional list has a - \`humanizer\` (global) entry"; else t_bad "v0.25.0 AC10 questions.md optional list has a - \`humanizer\` (global) entry" "no line starting with - \`humanizer\` (global)"; fi
if [ -n "$QH_LINE" ] && [ "$(grep -n -F -- "$QH_LINE" "$QUESTIONS" | head -n 1 | cut -d: -f1)" -gt "$(grep -n -F 'Optional, only when relevant' "$QUESTIONS" | head -n 1 | cut -d: -f1)" ]; then t_ok "v0.25.0 AC10 the humanizer entry sits in the optional list (after Optional, only when relevant)"; else t_bad "v0.25.0 AC10 the humanizer entry sits in the optional list (after Optional, only when relevant)" "entry [$QH_LINE]"; fi
qh_has "v0.25.0 AC10 the humanizer entry lists the values ask, always and never" 'ask.{0,80}always.{0,80}never|always.{0,80}ask.{0,80}never|never.{0,80}always.{0,80}ask'
qh_has "v0.25.0 AC10 the humanizer entry makes ask the default" 'default[^.;]{0,12}ask'
qh_has "v0.25.0 AC10 the humanizer entry says an unknown value counts as ask" 'unknown[^.;]{0,60}ask'
qh_has "v0.25.0 AC10 always runs humanizer in full without asking" 'always.{0,200}(without ask|no question|do not ask|dont ask|never ask|skip the question)'
qh_has "v0.25.0 AC10 never means writing.md only and no question" 'never.{0,200}(writing\.md|never ask|do not ask|not ask|no question)'
# step 6 of SKILL.md forbids writing keys it does not list ("never write keys that are not documented in step 6"), so the key must be in its global keys list [INFERRED from SKILL.md step 4 and 6]
GK="$(tr '\n' ' ' < "$SETUP" 2>/dev/null | tr -s ' ' | sed 's/.*Global keys://; s/Project keys:.*//')"
if printf '%s' "$GK" | grep -qi -- 'humanizer'; then t_ok "v0.25.0 AC10 SKILL.md step 6 lists humanizer among the global keys"; else t_bad "v0.25.0 AC10 SKILL.md step 6 lists humanizer among the global keys" "global keys paragraph: [$GK]"; fi
# the AC9 rule honours the key: the guide the rule points to says so [INFERRED from AC10: The AC9 rule honours it; the 270-byte text has no room for it]
if [ -f "$WM" ] && flat "$WM" | grep -qiE -- 'humanizer[` ]{0,2} ?(key|setting|config|option)|(key|setting|config|option)[^.]{0,40}humanizer'; then t_ok "v0.25.0 AC10 writing.md names the humanizer config key"; else t_bad "v0.25.0 AC10 writing.md names the humanizer config key" "no key/setting/config next to humanizer in $WM"; fi
if [ -f "$WM" ] && flat "$WM" | grep -qiE -- 'always[^.]{0,120}(without ask|no question|do not ask|never ask|skip the question)|(without ask|do not ask|never ask)[^.]{0,120}always'; then t_ok "v0.25.0 AC10 writing.md says always runs humanizer in full without asking"; else t_bad "v0.25.0 AC10 writing.md says always runs humanizer in full without asking" "no always + without-asking sentence in $WM"; fi

echo "v0.25.0 lane H (S2): AC11 setup suggests humanizer"
st_has_f "v0.25.0 AC11 setup names the Claude Code check path ~/.claude/skills/humanizer/SKILL.md" '~/.claude/skills/humanizer/SKILL.md'
st_has_f "v0.25.0 AC11 setup names the Codex and OpenCode check path ~/.agents/skills/humanizer/SKILL.md" '~/.agents/skills/humanizer/SKILL.md'
st_has_f "v0.25.0 AC11 setup gives the install command (git clone https://github.com/blader/humanizer ~/.claude/skills/humanizer)" 'git clone https://github.com/blader/humanizer ~/.claude/skills/humanizer'
st_has "v0.25.0 AC11 setup offers humanizer as optional" 'humanizer.{0,255}optional|optional.{0,255}humanizer'
st_has "v0.25.0 AC11 the humanizer offer defaults to no" 'humanizer.{0,255}default[^.;]{0,12}[^a-z]no([^a-z]|$)|default[^.;]{0,12}[^a-z]no([^a-z]|$).{0,255}humanizer'
st_has "v0.25.0 AC11 the reason is more human-sounding reports and conclusions" 'more human[^.]{0,40}report[^.]{0,40}conclusion'
st_has "v0.25.0 AC11 setup never installs humanizer without a yes" 'humanizer.{0,255}(never|not|n.t)[^.]{0,40}(install|clone)[^.]{0,60}(without|unless|until)[^.]{0,30}(yes|consent|agree|confirm)|(never|not|n.t)[^.]{0,40}(install|clone)[^.]{0,60}(without|unless|until)[^.]{0,30}(yes|consent|agree|confirm).{0,255}humanizer'
st_has "v0.25.0 AC11 when humanizer is installed setup asks the humanizer key question (default ask)" 'humanizer.{0,255}(if|when)[^.]{0,40}installed[^.]{0,160}(ask|question)|(if|when)[^.]{0,40}installed[^.]{0,160}(ask|question)[^.]{0,160}humanizer'
st_has "v0.25.0 AC11 setup says the check happens for the detected harness (Claude Code vs Codex/OpenCode)" 'humanizer.{0,255}(harness|claude code)|(harness|claude code).{0,255}humanizer'

echo "v0.25.0 lane H (S2): AC12 playbook-setup word budget (at most 1150)"
SETUP_WORDS="$(wc -w < "$SETUP" | tr -d ' ')"; SETUP_B="$(budget_of skills/playbook-setup/SKILL.md)"
if [ "$SETUP_WORDS" -le 1150 ]; then t_ok "v0.25.0 AC12 playbook-setup SKILL.md is at most 1150 words (orchestrator default D3) ($SETUP_WORDS)"; else t_bad "v0.25.0 AC12 playbook-setup SKILL.md is at most 1150 words (orchestrator default D3)" "$SETUP_WORDS words"; fi
if [ -n "$SETUP_B" ] && [ "$SETUP_B" -ge "$SETUP_WORDS" ] && [ "$SETUP_B" -le 1150 ]; then t_ok "v0.25.0 AC12 the playbook-setup budget in evals/word-budgets is not below the count and at most 1150 (budget $SETUP_B, count $SETUP_WORDS)"; else t_bad "v0.25.0 AC12 the playbook-setup budget in evals/word-budgets is not below the count and at most 1150" "budget [$SETUP_B] count $SETUP_WORDS"; fi

# ---- v0.25.0 fix round 1 (review findings F4-F7) ----
echo "v0.25.0 fix1 F4: writing.md does not tell the reader to remove decorative bold (humanizer s19 is not in the approved list)"
WM_RULES=""; [ -f "$WM" ] && WM_RULES="$(awk '/^## Rules/ { f = 1; next } /^## / { f = 0 } f { print }' "$WM" | tr '\n' ' ')"
if printf '%s' "$WM_RULES" | grep -qi 'chatbot'; then t_ok "v0.25.0 fix1 F4 writing.md has a Rules list (found by its chatbot rule)"; else t_bad "v0.25.0 fix1 F4 writing.md has a Rules list (found by its chatbot rule)" "rules [$WM_RULES]"; fi
if [ -n "$WM_RULES" ] && ! printf '%s' "$WM_RULES" | grep -qi 'bold'; then t_ok "v0.25.0 fix1 F4 the Rules list does not mention bold"; else t_bad "v0.25.0 fix1 F4 the Rules list does not mention bold" "rules [$WM_RULES] (empty = no Rules list)"; fi
if [ -f "$WM" ] && ! flat "$WM" | grep -qi 'decorative bold'; then t_ok "v0.25.0 fix1 F4 writing.md never says decorative bold"; else t_bad "v0.25.0 fix1 F4 writing.md never says decorative bold" "the phrase is in $WM (or the file is missing)"; fi
if [ -f "$WM" ] && flat "$WM" | grep -qiE 'decorative headings.{0,30}emoji'; then t_ok "v0.25.0 fix1 F4 s20 stays: decorative headings and emojis are still named"; else t_bad "v0.25.0 fix1 F4 s20 stays: decorative headings and emojis are still named" "no decorative headings ... emoji in $WM"; fi

echo "v0.25.0 fix1 F5: the Humanizer section conditions on an installed skill and the key first, then asks (it does not offer)"
WM_HUM=""; [ -f "$WM" ] && WM_HUM="$(awk '/^## Humanizer/ { f = 1; next } /^## / { f = 0 } /^Credit:/ { f = 0 } f { print }' "$WM" | tr '\n' ' ' | tr -s ' ')"
HUM_S="$(printf '%s' "$WM_HUM" | tr '.' '\n')"
HUM_INST="$(printf '%s\n' "$HUM_S" | grep -i 'installed' | head -n 1)"
HUM_L_INST="$(printf '%s\n' "$HUM_S" | grep -n -i 'installed' | head -n 1 | cut -d: -f1)"
HUM_L_MAIN="$(printf '%s\n' "$HUM_S" | grep -n -i 'main deliverable' | head -n 1 | cut -d: -f1)"
if [ -n "$HUM_L_INST" ] && [ -n "$HUM_L_MAIN" ] && [ "$HUM_L_INST" -lt "$HUM_L_MAIN" ]; then t_ok "v0.25.0 fix1 F5 the installed-skill sentence comes before the main deliverable sentence"; else t_bad "v0.25.0 fix1 F5 the installed-skill sentence comes before the main deliverable sentence" "installed at sentence [$HUM_L_INST], main deliverable at [$HUM_L_MAIN]"; fi
if printf '%s' "$HUM_INST" | grep -qiE 'key' && printf '%s' "$HUM_INST" | grep -qE 'ask'; then t_ok "v0.25.0 fix1 F5 the installed-skill sentence also conditions on the humanizer key being ask"; else t_bad "v0.25.0 fix1 F5 the installed-skill sentence also conditions on the humanizer key being ask" "sentence [$HUM_INST]"; fi
if printf '%s' "$HUM_INST" | grep -qiE 'ask.{0,100}(run|use)[^.]{0,30}in full'; then t_ok "v0.25.0 fix1 F5 the installed-skill sentence asks whether to run it in full"; else t_bad "v0.25.0 fix1 F5 the installed-skill sentence asks whether to run it in full" "sentence [$HUM_INST]"; fi
if [ -n "$HUM_INST" ] && ! printf '%s' "$HUM_INST" | grep -qiE 'offer'; then t_ok "v0.25.0 fix1 F5 the installed-skill sentence does not say offer (AGENTS.global.md says ask)"; else t_bad "v0.25.0 fix1 F5 the installed-skill sentence does not say offer (AGENTS.global.md says ask)" "sentence [$HUM_INST]"; fi

echo "v0.25.0 fix1 F6: setup gives the humanizer install command for both skills dirs"
if grep -qF -- 'git clone https://github.com/blader/humanizer ~/.claude/skills/humanizer' "$QUESTIONS"; then t_ok "v0.25.0 fix1 F6 questions.md gives the Claude Code clone command (characterization)"; else t_bad "v0.25.0 fix1 F6 questions.md gives the Claude Code clone command (characterization)" "missing in $QUESTIONS"; fi
if grep -qF -- 'git clone https://github.com/blader/humanizer ~/.agents/skills/humanizer' "$QUESTIONS"; then t_ok "v0.25.0 fix1 F6 questions.md gives the Codex and OpenCode clone command"; else t_bad "v0.25.0 fix1 F6 questions.md gives the Codex and OpenCode clone command" "no git clone ... ~/.agents/skills/humanizer in $QUESTIONS"; fi

echo "v0.25.0 fix1 F7: the humanizer suggestion is part of the step 4 batch, not a later question"
S4_TXT="$(awk '/^4\. \*\*Ask once/ { f = 1; next } f && /\*\*Models per role\*\*/ { exit } f { print }' "$SETUP" | tr '\n' ' ' | tr -s ' ')"
if printf '%s' "$S4_TXT" | grep -qi 'humanizer'; then t_ok "v0.25.0 fix1 F7 step 4 of SKILL.md mentions the humanizer suggestion"; else t_bad "v0.25.0 fix1 F7 step 4 of SKILL.md mentions the humanizer suggestion" "step 4 [$S4_TXT]"; fi
if printf '%s' "$S4_TXT" | grep -qiE '(then|afterwards?|after (the|that)|later|follow-?up)[^.]{0,60}humanizer'; then t_bad "v0.25.0 fix1 F7 no sentence asks the humanizer question after the batch" "step 4 [$S4_TXT]"; else t_ok "v0.25.0 fix1 F7 no sentence asks the humanizer question after the batch"; fi
if printf '%s' "$S4_TXT" | grep -qiE 'humanizer.{0,200}(batch|same message|single message)|(batch|same message|single message).{0,200}humanizer'; then t_ok "v0.25.0 fix1 F7 the humanizer suggestion goes into the same batched message"; else t_bad "v0.25.0 fix1 F7 the humanizer suggestion goes into the same batched message" "step 4 [$S4_TXT]"; fi


echo "v0.25.1 lane S: step 4 cap of 8 questions and the humanizer line are consistent"
S4_ALL="$(awk '/^4\. \*\*Ask once/ { f = 1 } f && /\*\*Models per role\*\*/ { exit } f { print }' "$SETUP" | tr '\n' ' ' | tr -s ' ')"
if printf '%s' "$S4_ALL" | grep -qiE 'at most 8 questions' && printf '%s' "$S4_ALL" | grep -qiE 'humanizer[^.;]{0,80}(extra|optional line|not count|on top)|(plus|besides|beyond|on top of)[^.;]{0,60}humanizer'; then t_ok "v0.25.1 S step 4 states the humanizer line is an extra on top of the 8-question cap"; else t_bad "v0.25.1 S step 4 states the humanizer line is an extra on top of the 8-question cap" "step 4 [$S4_TXT]"; fi


echo "v0.26.0 lane E AC7.1 RUBRIC.md: after the gate line, a rule is kept or added only when its scenario shows Δ > 0"
RUBF="$PB_ROOT/evals/RUBRIC.md"
assert_eq "v26 E AC7.1 RUBRIC.md keeps the existing gate line" "1" "$(grep -c '^Gate before releasing a new playbook version: no 0 on E3, E4, E5 or E8 in the harness you use most\.' "$RUBF")"
# the paragraph that names tools/eval-delta.sh, between the gate line and the "Copy this table" line
DPARA="$(awk '/^Gate before releasing a new playbook version/ { f = 1; next } f && /^Copy this table/ { exit } f && /^[[:space:]]*$/ { if (p ~ /eval-delta/) { print p; exit } p = ""; next } f { p = p " " $0 } END { if (f && p ~ /eval-delta/) print p }' "$RUBF" | head -n 1)"
if [ -n "$DPARA" ]; then t_ok "v26 E AC7.1 a paragraph after the gate line names tools/eval-delta.sh"; else t_bad "v26 E AC7.1 a paragraph after the gate line names tools/eval-delta.sh" "none between the gate line and 'Copy this table'"; fi
qchk "v26 E AC7.1 the gate paragraph: a rule is kept or added only when its scenario shows Δ > 0" "$DPARA" '(kept|keep)[^.]{0,30}(added|add)[^.]{0,80}only[^.]{0,80}(Δ|delta) ?> ?0'
qchk "v26 E AC7.1 the gate paragraph names tools/eval-delta.sh" "$DPARA" 'tools/eval-delta\.sh'
qchk "v26 E AC7.1 the gate paragraph asks for --arm both" "$DPARA" '--arm both'
qchk "v26 E AC7.1 the gate paragraph asks for --repeat of at least 3" "$DPARA" '--repeat[^.]{0,20}(≥ ?3|>= ?3|3 or more|at least 3)'
qchk "v26 E AC7.1 the gate paragraph asks for a pinned --model" "$DPARA" 'pinned[^.]{0,20}--model|--model[^.]{0,40}pinned'
qchk "v26 E AC7.1 the gate paragraph: a non-discriminating check is marked to drop or rewrite" "$DPARA" 'non-discriminating[^.]{0,120}(drop|remov)[^.]{0,40}rewrit'

echo "v0.26.1 lane T: outside data needs a real-shaped sample (PLAN-v0.26 proposal 4)"
OUTSEC='^## Data from outside'
sec_flat_has "v0.26.1 T AC1 tester.md: parsing or mapping outside data (DB rows, API payloads, user input, config)" "$TESTER" "$OUTSEC" '(pars|map)[^.]{0,120}(outside|external)[^.]{0,200}DB rows[^.]{0,80}API payloads[^.]{0,80}user input[^.]{0,40}config'
sec_flat_has "v0.26.1 T AC1 tester.md: at least one test uses a real anonymised sample" "$TESTER" "$OUTSEC" 'at least one test[^.]{0,80}real[^.]{0,20}anonymi[sz]ed[^.]{0,20}sample'
sec_flat_has "v0.26.1 T AC1 tester.md: or a sample whose values differ from their labels or keys" "$TESTER" "$OUTSEC" 'values? (differ|differs) from (their|its) labels?( or |/)keys?'
sec_flat_has "v0.26.1 T AC2 tester.md: the report names where the sample came from" "$TESTER" "$OUTSEC" 'report[^.]{0,80}names?[^.]{0,40}(where the sample came from|the sample.s source|source of the sample)'
sec_flat_has "v0.26.1 T AC3 tester.md: a Why line on value equal to label hiding a bug" "$TESTER" "$OUTSEC" '\*\*Why:\*\*[^.]{0,200}(equal|==|same as)[^.]{0,40}label[^.]{0,120}hid'
flat_has "v0.26.1 T AC4 spec-reviewer.md: a spec for outside data names the source of its sample data" "$SPEC_REV" '(outside|external) data[^.]{0,200}names? the source of its sample data'
if grep -rqiE 'options_json|printup' "$TDD" 2>/dev/null; then t_bad "v0.26.1 T AC5 no project names (options_json, PrintUp) under skills/playbook-tdd (passes today by design)" "leak found"; else t_ok "v0.26.1 T AC5 no project names (options_json, PrintUp) under skills/playbook-tdd (passes today by design)"; fi

echo "v0.26.1 review fix 3 (S-D4): the README update paragraph says a failing PGP/x509 signature warns, SSH with allowed signers stops"
UPAR="$(grep -m1 '^`update` checks the release tag' "$PB_ROOT/README.md")"
assert_contains "fix3 README: the update signature paragraph exists" "$UPAR" "git verify-tag"
assert_contains "fix3 README: the paragraph names PGP (warn only, decision S-D4)" "$UPAR" "PGP"
assert_contains "fix3 README: the paragraph names SSH (the case that stops)" "$UPAR" "SSH"
assert_contains "fix3 README: the paragraph names the allowed signers setting" "$UPAR" "gpg.ssh.allowedSignersFile"
assert_not_contains "fix3 README: no claim that any signature that does not verify stops the update" "$UPAR" "a signature that does not verify stops the update"

echo "v0.28.0 lane k1b AC-B7: setup step 4 offers the Claude Code hooks as an optional extra line (default no)"
K1B_S4="$(awk '/^4\. \*\*Ask once/ { f = 1 } f && /\*\*Models per role\*\*/ { exit } f { print }' "$SETUP" | tr '\n' ' ' | tr -s ' ')"
qchk "k1b AC-B7 step 4 names the install command claude-hooks.sh install" "$K1B_S4" 'claude-hooks\.sh install'
qchk "k1b AC-B7 step 4: the hooks line is an optional extra outside the 8-question cap" "$K1B_S4" 'hooks?[^.;]{0,160}(extra|optional line|outside the 8|not count|on top)|(extra|optional line|outside the 8|on top of)[^.;]{0,160}hooks?'
qchk "k1b AC-B7 step 4: the hooks line is for Claude Code only" "$K1B_S4" 'claude code only|only (for|in) claude code|claude code[^.]{0,60}only'
qchk "k1b AC-B7 step 4: the hooks default to no" "$K1B_S4" 'hooks?[^.]{0,250}default no|default no[^.]{0,250}hooks?'
qchk "k1b AC-B7 step 4: the hooks go into ~/.claude/settings.json" "$K1B_S4" '~/\.claude/settings\.json'
qchk "k1b AC-B7 step 4: says what the guard hook does" "$K1B_S4" 'guard[^.]{0,200}(irreversible|block|warn)'
qchk "k1b AC-B7 step 4: says what the learnings hook does" "$K1B_S4" 'learnings[^.]{0,200}(session start|SessionStart|LEARNINGS)'
qchk "k1b AC-B7 step 4: says a backup is made" "$K1B_S4" 'back(s|ed)? ?up|backup'
qchk "k1b AC-B7 step 4: says how to remove them (claude-hooks.sh uninstall)" "$K1B_S4" 'claude-hooks\.sh uninstall'
flat_has "k1b AC-B7 yes -> conf.sh set hooks on --global" "$SETUP" 'conf\.sh set hooks on --global'
flat_has "k1b AC-B7 no -> hooks off" "$SETUP" 'hooks off'
flat_has "k1b AC-B7 a non-interactive setup never installs the hooks" "$SETUP" '(non-interactive|headless)[^.]{0,250}(never|not|no)[^.]{0,40}install[^.]{0,80}hooks?|hooks?[^.]{0,250}(non-interactive|headless)[^.]{0,120}(never|not)[^.]{0,20}install'
K1B_S6="$(awk '/^6\. \*\*Write the values/ { f = 1 } f && /^7\. / { exit } f { print }' "$SETUP" | tr '\n' ' ' | tr -s ' ')"
qchk "k1b AC-B7 step 6 lists the global key hooks (on/off)" "$K1B_S6" '`hooks` \(on ?(\||/|or) ?off'
flat_has "k1b AC-B7 questions.md lists the optional hooks key (global)" "$QUESTIONS" '`hooks` \(global\)'
K1B_SW="$(wc -w < "$SETUP" | tr -d ' ')"
if [ "$K1B_SW" -le 1100 ]; then t_ok "k1b AC-B7 playbook-setup SKILL.md stays at most 1100 words (guard: holds today at 1100) ($K1B_SW)"; else t_bad "k1b AC-B7 playbook-setup SKILL.md stays at most 1100 words (guard: holds today at 1100)" "$K1B_SW words"; fi

echo "v0.28.0 lane k1b AC-B8: the K5 pointer (learn.sh init --link-agents) where the learnings hook is absent"
K1B_S8="$(awk '/^8\. \*\*Project bootstrap/ { f = 1 } f && /^9\. / { exit } f { print }' "$SETUP" | tr '\n' ' ' | tr -s ' ')"
qchk "k1b AC-B8 step 8 offers the pointer when the learnings hook is not installed" "$K1B_S8" 'learnings hook[^.]{0,200}(not installed|is off|off[ ,;)])|(not installed|is off)[^.]{0,200}learnings hook'
qchk "k1b AC-B8 step 8 offers the pointer for Codex and OpenCode" "$K1B_S8" 'codex.{0,250}(pointer|link-agents)|(pointer|link-agents).{0,250}codex'
qchk "k1b AC-B8 step 8 says the pointer is how those agents learn about the file" "$K1B_S8" 'pointer.{0,150}(is how|is the way|is what)'
flat_has "k1b AC-B8 README: Codex/OpenCode learn about LEARNINGS.md through learn.sh init --link-agents" "$README" '(codex|opencode).{0,250}link-agents|link-agents.{0,250}(codex|opencode)'

echo "v0.28.0 lane k1b AC-B9: README section Hooks (Claude Code, opt-in) with handlers, PB_HEADLESS, the Stop check and Limits"
exact_heading "k1b AC-B9 README has the heading ## Hooks (Claude Code, opt-in)" "$README" '## Hooks (Claude Code, opt-in)'
K1B_HK="$(awk '/^## Hooks \(Claude Code, opt-in\)$/ { f = 1; print; next } f && /^## / { exit } f { print }' "$README")"
K1B_HKF="$(printf '%s\n' "$K1B_HK" | tr '\n' ' ' | tr -s ' ')"
for k1b_n in 'guard-irreversible\.sh' 'learnings-hook\.sh' 'PreToolUse' 'SessionStart' 'Stop' 'claude-hooks\.sh uninstall' 'export PB_HEADLESS=1' 'claude -p' 'CI=true'; do
  qchk "k1b AC-B9 hooks section names $k1b_n" "$K1B_HKF" "$k1b_n"
done
qchk "k1b AC-B9 hooks section: opt-in through setup" "$K1B_HKF" 'set up the playbook|playbook-setup'
qchk "k1b AC-B9 hooks section: PB_HEADLESS=0 forces warn-only" "$K1B_HKF" 'PB_HEADLESS=0[^.]{0,120}warn'
qchk "k1b AC-B9 hooks section: the Stop check asks to revert and report" "$K1B_HKF" 'Stop.{0,250}revert.{0,250}(report|pending)'
qchk "k1b AC-B9 Codex: hooks exist (cited) but are not installed" "$K1B_HKF" 'codex.{0,250}(learn\.chatgpt\.com/docs/hooks|developers\.openai\.com/codex/hooks)'
qchk "k1b AC-B9 Codex: text rule only in v0.28.0" "$K1B_HKF" 'codex[^#]{0,250}(not installed|no hooks? (are|is) installed)[^#]{0,200}text rule only|codex[^#]{0,250}text rule only'
qchk "k1b AC-B9 OpenCode: tool.execute.before exists (cited)" "$K1B_HKF" 'opencode.{0,250}tool\.execute\.before'
qchk "k1b AC-B9 OpenCode: cites opencode.ai/docs/plugins" "$K1B_HKF" 'opencode\.ai/docs/plugins'
qchk "k1b AC-B9 OpenCode: no plugin ships, text rule only" "$K1B_HKF" 'opencode.{0,250}text rule only'
K1B_LIM="$(printf '%s\n' "$K1B_HK" | awk '/^###+ Limits/ { f = 1 } f { print }' | tr '\n' ' ' | tr -s ' ')"
if [ -n "$K1B_LIM" ]; then t_ok "k1b AC-B9 the hooks section has a Limits subsection"; else t_bad "k1b AC-B9 the hooks section has a Limits subsection" "no ### Limits heading inside ## Hooks (Claude Code, opt-in)"; fi
for k1b_n in 'bash -c' 'sh -c' 'eval' '\$\(' 'backtick' 'subshell' 'brace group' 'here-doc' 'node -e' 'python -c' 'perl -e' 'git alias' 'find -delete' 'xargs rm' '\\u' 'concatenat' 'PowerShell' 'NotebookEdit' 'MCP' 'disableAllHooks' 'settings\.local\.json' 'guard itself' 'non-git|not a git|outside (a )?git' 'script[^.]{0,60}(written|writes)[^.]{0,60}(then )?run' 'backstop'; do
  qchk "k1b AC-B9 Limits lists $k1b_n" "$K1B_LIM" "$k1b_n"
done


# ---- v0.29.0 lane w, slice P2: README hooks table and Limits for the PowerShell tool (AC-H5, spec Revisions 2 and 3) ----
echo "v0.29.0 lane w P2 AC-H5: README hooks section names the PowerShell tool and its Limits"
WP_ROW="$(grep -E '^\| *PreToolUse' "$README" | head -n 1)"
if [ -n "$WP_ROW" ]; then t_ok "v0.29.0 P2 AC-H5 the README hooks table has a PreToolUse row"; else t_bad "v0.29.0 P2 AC-H5 the README hooks table has a PreToolUse row" "no table row starting with PreToolUse"; fi
for wp_n in 'Bash' 'PowerShell' 'Write' 'Edit'; do
  qchk "v0.29.0 P2 AC-H5 the PreToolUse row names $wp_n" "$WP_ROW" "$wp_n"
done
qchk "v0.29.0 P2 AC-H5 the PreToolUse row says which PowerShell forms are checked (Remove-Item)" "$WP_ROW" 'Remove-Item'
qchk "v0.29.0 P2 AC-H5 the hooks section cites the Claude Code hooks docs URL" "$K1B_HKF" 'code\.claude\.com/docs/en/hooks'
# the "tools it is not attached to" line (the one naming NotebookEdit) no longer names the PowerShell tool
WP_ATT="$(printf '%s\n' "$K1B_HK" | grep -E 'NotebookEdit')"
if [ -n "$WP_ATT" ]; then t_ok "v0.29.0 P2 AC-H5 Limits still has the not-attached line (NotebookEdit, MCP)"; else t_bad "v0.29.0 P2 AC-H5 Limits still has the not-attached line (NotebookEdit, MCP)" "no line naming NotebookEdit"; fi
if printf '%s\n' "$WP_ATT" | grep -qiE 'PowerShell'; then t_bad "v0.29.0 P2 AC-H5 the not-attached line no longer names the PowerShell tool" "still names PowerShell: $WP_ATT"; else t_ok "v0.29.0 P2 AC-H5 the not-attached line no longer names the PowerShell tool"; fi
qchk "v0.29.0 P2 AC-H5 the not-attached line still names MCP tools" "$WP_ATT" 'MCP'
WP_PSL="$(printf '%s\n' "$K1B_HK" | awk '/^###+ Limits/ { f = 1 } f' | grep -iE 'PowerShell' | grep -vE 'NotebookEdit')"
if [ -n "$WP_PSL" ]; then t_ok "v0.29.0 P2 AC-H5 Limits has a PowerShell item (a line about PowerShell besides the not-attached line)"; else t_bad "v0.29.0 P2 AC-H5 Limits has a PowerShell item (a line about PowerShell besides the not-attached line)" "no Limits line names PowerShell"; fi
# each uncovered form is named in Limits (meaning pins, flexible wording)
qchk "v0.29.0 P2 AC-H5 Limits: Invoke-Expression" "$K1B_LIM" 'Invoke-Expression'
qchk "v0.29.0 P2 AC-H5 Limits: iex" "$K1B_LIM" '(^|[^a-z])iex([^a-z]|$)'
qchk "v0.29.0 P2 AC-H5 Limits: powershell -Command" "$K1B_LIM" 'powershell(\.exe)?[^.;]{0,30}-Command'
qchk "v0.29.0 P2 AC-H5 Limits: pwsh -c" "$K1B_LIM" 'pwsh[^.;]{0,20}-c([^a-z]|$)'
qchk "v0.29.0 P2 AC-H5 Limits: -EncodedCommand" "$K1B_LIM" '-EncodedCommand'
qchk "v0.29.0 P2 AC-H5 Limits: cmd /c" "$K1B_LIM" 'cmd(\.exe)? /c'
qchk "v0.29.0 P2 AC-H5 Limits: Start-Process" "$K1B_LIM" 'Start-Process'
qchk "v0.29.0 P2 AC-H5 Limits: scriptblocks run later (& { }, Invoke-Command)" "$K1B_LIM" 'script ?blocks?[^.]{0,200}(later|run|invok)'
qchk "v0.29.0 P2 AC-H5 Limits: & { } scriptblock call" "$K1B_LIM" '& ?\{'
qchk "v0.29.0 P2 AC-H5 Limits: Invoke-Command" "$K1B_LIM" 'Invoke-Command'
qchk "v0.29.0 P2 AC-H5 Limits: the --% stop-parsing token" "$K1B_LIM" '(^|[^-])--%'
qchk "v0.29.0 P2 AC-H5 Limits: variables other than the listed ones count as outside (warn or block)" "$K1B_LIM" 'variables?[^.]{0,250}outside|outside[^.]{0,250}variables?'
qchk "v0.29.0 P2 AC-H5 Limits: Remove-Item without -Recurse is not covered" "$K1B_LIM" 'Remove-Item[^.]{0,150}without[^.]{0,40}-Recurse|without[^.]{0,40}-Recurse'
qchk "v0.29.0 P2 AC-H5 Limits: registry paths" "$K1B_LIM" 'registry'
qchk "v0.29.0 P2 AC-H5 Limits: provider paths" "$K1B_LIM" 'provider'
qchk "v0.29.0 P2 AC-H5 Limits: Set-Content writing SQL files" "$K1B_LIM" 'Set-Content'
qchk "v0.29.0 P2 AC-H5 Limits: Out-File writing SQL files" "$K1B_LIM" 'Out-File'
qchk "v0.29.0 P2 AC-H5 Limits (Rev 2 F4): .NET calls such as [IO.Directory]::Delete" "$K1B_LIM" '\.NET'
qchk "v0.29.0 P2 AC-H5 Limits (Rev 2 F4): names [IO.Directory]::Delete" "$K1B_LIM" 'IO\.Directory'
qchk "v0.29.0 P2 AC-H5 Limits (Rev 2 F4): splatting without a visible -Recurse" "$K1B_LIM" 'splat'
qchk "v0.29.0 P2 AC-H5 Limits (Rev 3): a Remove-Item -Recurse fed by the pipeline has no target word and warns or blocks even inside the project" "$K1B_LIM" 'pipe(line)?[^.]{0,250}(false positive|even (inside|in |when)|fail(s)? closed|warn|block)'
# review round 1 F2: curly quotes are handled as quote characters now, so the Limits must not claim they are not (the old pin
# required that claim). It no longer requires any curly-quote sentence; it fails when the wrong claim is still there.
if printf '%s' "$K1B_LIM" | grep -qiE -- '(curly|smart|typographic)[^.]{0,120}(not|never|n.t) (a |an |treated as |read as |recognized as |recognised as )?(quote|quoting)'; then t_bad "v0.29.0 review F2 README Limits no longer claim curly quotes are not quote characters" "the wrong sentence is still there"; else t_ok "v0.29.0 review F2 README Limits no longer claim curly quotes are not quote characters"; fi
qchk "v0.29.0 P2 AC-H5 Limits (P1 finding): variable assignments are not followed" "$K1B_LIM" 'assign|variable flow|flow of variables?'
# review round 2 (items 5, 6, 7): the assignment sentence says what the code does now: every assignment form makes a listed variable
# unresolved (fail closed); a copy into another variable is still not followed; a call operator on a group or variable is unknown.
qchk "v0.29.0 review2 R5 Limits: an assignment to a listed variable makes it unresolved" "$K1B_LIM" 'assign.{0,250}unresolved|assign.{0,250}.{0,250}unresolved'
qchk "v0.29.0 review2 R5 Limits: a delete through such a variable warns or blocks (fail closed)" "$K1B_LIM" 'unresolved.{0,200}(fail(s)? closed|warn|block)'
qchk "v0.29.0 review2 R5 Limits: list assignment (\$a, \$b = ...) counts" "$K1B_LIM" 'list assign|multiple assign|multi-?assign|\$[a-z:]+, ?\$[a-z:]+ ?='
qchk "v0.29.0 review2 R7 Limits: compound assignment (+=, -=, ??= ...) counts" "$K1B_LIM" '\+=|compound assign'
qchk "v0.29.0 review2 R5 Limits: Rename-Item names the assignment forms" "$K1B_LIM" 'Rename-Item'
qchk "v0.29.0 review2 R5 Limits: New-Item names the assignment forms" "$K1B_LIM" 'New-Item'
qchk "v0.29.0 review2 R5 Limits: [Environment]::SetEnvironmentVariable names the assignment forms" "$K1B_LIM" 'SetEnvironmentVariable'
qchk "v0.29.0 review2 R5 Limits: a value copied into another variable is not followed" "$K1B_LIM" 'cop(y|ied)[^.]{0,120}not followed|not follow[^.]{0,120}cop(y|ied)'
qchk "v0.29.0 review2 R6 Limits: a call operator on a group or variable (& (...), & \$cmd) is an unknown command" "$K1B_LIM" '& ?(\(|\$[a-z{])'
qchk "v0.29.0 P2 AC-H5 Limits: without Git Bash the bash hook commands cannot run" "$K1B_LIM" 'without Git Bash[^.]{0,200}(cannot|can.?t|not|no )|Git Bash[^.]{0,60}(isn.t|is not|not) installed[^.]{0,200}(cannot|can.?t|not )'

# review fix round 3 (tester fix4): the Limits do not over-claim vertical tab, and name the assignment targets the code checks
# [UNVERIFIED] how a real client sends a vertical tab: the JSON escape \u000b, which the guard documents as not decoded.
qchk "v0.29.0 review3 F3 Limits: the JSON-escaped vertical tab (\\u000b) is named as not decoded" "$K1B_LIM" '\\u000b.{0,250}not decoded|not decoded.{0,250}\\u000b|vertical tab[^;]{0,200}\\u[^;]{0,200}not decoded'
VT_BAD=""
while IFS= read -r vtc <&3; do
  [ -n "$vtc" ] || continue
  printf '%s' "$vtc" | grep -qiE -- 'u000b|escape|not decoded|raw|literal' || VT_BAD="$VT_BAD [$vtc]"
done 3<<EOF_VT
$(printf '%s' "$K1B_LIM" | grep -oiE 'vertical tab[^;]{0,160}')
EOF_VT
if [ -z "$VT_BAD" ]; then t_ok "v0.29.0 review3 F3 Limits: every mention of vertical tab is qualified (raw byte only, or the \\u escape not decoded)"; else t_bad "v0.29.0 review3 F3 Limits: every mention of vertical tab is qualified (raw byte only, or the \\u escape not decoded)" "unqualified:$VT_BAD"; fi
qchk "v0.29.0 review3 F1 Limits: an assignment to a property (\$x.a = ...) is checked" "$K1B_LIM" 'assign.{0,250}propert|propert.{0,250}assign|\$[a-z]+\.[a-z]+ ?='
qchk "v0.29.0 review3 F1 Limits: an assignment to an index (\$x[0] = ...) is checked" "$K1B_LIM" 'assign.{0,250}index|index.{0,250}assign|\$[a-z]+\[[^]]+\] ?='
qchk "v0.29.0 review3 F1 Limits: an assignment with a scope prefix (\$script:r = ...) is checked" "$K1B_LIM" 'assign.{0,250}scope|scope.{0,250}assign|\$(script|global|local):[a-z]+ ?='
qchk "v0.29.0 review3 F3 Limits: NEL, U+1680, U+2028 and U+2029 are named among the word separators" "$K1B_LIM" 'U\+0085.{0,250}U\+1680.{0,250}U\+2028.{0,250}U\+2029|NEL.{0,250}U\+1680.{0,250}U\+2028.{0,250}U\+2029'



# v0.28.1 lane t (lever 2): Lite step 4 no longer recommends a mutation spot-check; Full keeps it.
if lite_step 4 | tr '\n' ' ' | grep -qiE -- 'mutation spot-check'; then t_bad "v0.28.1 t Lite step 4 no longer recommends a mutation spot-check" "Lite step 4 still mentions it"; else t_ok "v0.28.1 t Lite step 4 no longer recommends a mutation spot-check"; fi
qchk "v0.28.1 t references/test-quality.md still covers the mutation spot-check" "$(cat "$TDD/references/test-quality.md")" 'mutation spot-check'
qchk "v0.28.1 t Full reviewer role still does the mutation spot-check" "$(cat "$TDD/roles/reviewer.md")" 'Do the mutation spot-check'

# v0.28.1 lane p: when the request covers any/every input, the RED test covers each input class, not only the reported example.
lite_has "v0.28.1 p Lite step 2: a request covering any/every input tests each input class" 2 'any/every input[^.]{0,40}each input class'
lite_has "v0.28.1 p Lite step 2: input classes include a leading dash" 2 'input class[^.]{0,60}leading dash'
sec_flat_has "v0.28.1 p tester.md Do: any/every input means each input class" "$TESTER" '^## Do' 'any/every input[^.]{0,60}each input class'
sec_flat_has "v0.28.1 p tester.md Do: not only the reported example" "$TESTER" '^## Do' 'input class[^.]{0,80}not only the reported example'


# ---- v0.29.0 lane w, slice T: trust docs (AC-T7, AC-T8, spec Revision 2 F1 and F3) ----
echo "v0.29.0 lane w T AC-T8: README hooks table row for learnings-hook.sh"
TW_ROW="$(grep -E '^\|.*`learnings-hook\.sh`' "$README" | head -n 1)"
if [ -n "$TW_ROW" ]; then t_ok "v0.29.0 T AC-T8 the README hooks table has a row for learnings-hook.sh"; else t_bad "v0.29.0 T AC-T8 the README hooks table has a row for learnings-hook.sh" "no table row naming learnings-hook.sh"; fi
qchk "v0.29.0 T AC-T8 the row says it injects only for trusted projects" "$TW_ROW" 'trusted'
qchk "v0.29.0 T AC-T8 the row names learn.sh trust" "$TW_ROW" 'learn\.sh trust'
qchk "v0.29.0 T AC-T8 the row names learnings_hook_trust=all" "$TW_ROW" 'learnings_hook_trust=all'
qchk "v0.29.0 T AC-T8 the row says the key is read from the global conf" "$TW_ROW" 'global'

echo "v0.29.0 lane w T AC-T7 + F1: playbook-setup offers once to trust the current project, within the word budget"
TW_S4="$(awk '/^4\. \*\*Ask once/ { f = 1 } f && /^5\. / { exit } f { print }' "$SETUP" | tr '\n' ' ' | tr -s ' ')"
qchk "v0.29.0 T AC-T7 step 4 (the hooks line) names learn.sh trust" "$TW_S4" 'learn\.sh trust'
qchk "v0.29.0 T AC-T7 step 4 offers it for the current project" "$TW_S4" 'trust.{0,200}(current|this) project|(current|this) project.{0,200}trust'
qchk "v0.29.0 T AC-T7 step 4: the trust offer is made once" "$TW_S4" 'trust.{0,200}once|once.{0,200}learn\.sh trust'
qchk "v0.29.0 T AC-T7 step 4: the trust offer defaults to no" "$TW_S4" 'default no.{0,250}learn\.sh trust|learn\.sh trust.{0,250}default no'
qchk "v0.29.0 T AC-T7 step 4: never trusts in a non-interactive run" "$TW_S4" 'never.{0,100}trust'
TW_SW="$(wc -w < "$SETUP" | tr -d ' ')"
if grep -q 'learn\.sh trust' "$SETUP" && [ "$TW_SW" -le 1100 ]; then t_ok "v0.29.0 T F1 playbook-setup mentions learn.sh trust and stays at most 1100 words ($TW_SW)"; else t_bad "v0.29.0 T F1 playbook-setup mentions learn.sh trust and stays at most 1100 words" "$TW_SW words, learn.sh trust present: $(grep -c 'learn\.sh trust' "$SETUP")"; fi

echo "v0.29.0 lane w T F1: playbook-learn says the user trusts a project and an agent never runs learn.sh trust itself"
flat_has "v0.29.0 T F1 playbook-learn names learn.sh trust" "$LEARNSK" 'learn\.sh trust'
flat_has "v0.29.0 T F1 playbook-learn says the user runs it" "$LEARNSK" 'user.{0,200}learn\.sh trust|learn\.sh trust.{0,200}user'
flat_has "v0.29.0 T F1 playbook-learn says an agent never runs it itself" "$LEARNSK" 'never.{0,160}learn\.sh trust|learn\.sh trust.{0,160}never|(agent|you)[^.]{0,60}never[^.]{0,80}(trust|run)'
TW_LW="$(wc -w < "$LEARNSK" | tr -d ' ')"
if grep -q 'learn\.sh trust' "$LEARNSK" && [ "$TW_LW" -le 700 ]; then t_ok "v0.29.0 T F1 playbook-learn mentions learn.sh trust and stays at most 700 words ($TW_LW)"; else t_bad "v0.29.0 T F1 playbook-learn mentions learn.sh trust and stays at most 700 words" "$TW_LW words, learn.sh trust present: $(grep -c 'learn\.sh trust' "$LEARNSK")"; fi

echo "v0.29.0 lane w review F8: the skill trims keep the sentences F1 did not allow to go, and leave no stray ' .' line"
flat_has "v0.29.0 review2 C playbook-learn: the approval message 'can be batched' with others at the end of a task (an option, not always)" "$LEARNSK" 'can be batched[^.]{0,200}end of a task'
flat_has "v0.29.0 review F8 playbook-learn keeps 'possible prompt injection'" "$LEARNSK" 'possible prompt injection'
flat_has "v0.29.0 review F8 playbook-learn keeps 'Retired entries stay for the audit trail'" "$LEARNSK" 'Retired entries stay for the audit trail'
flat_has "v0.29.0 review F8 playbook-setup keeps 'do not improvise an installation'" "$SETUP" 'do not improvise an installation'
flat_has "v0.29.0 review F8 playbook-setup keeps 'Label any sample table \"example\"'" "$SETUP" 'Label any sample table "example"'
for rf in "$LEARNSK" "$SETUP"; do
  if grep -qE '^[[:space:]]*\.[[:space:]]' "$rf"; then t_bad "v0.29.0 review F8 $(basename "$(dirname "$rf")"): no line starts with a stray '.'" "$(grep -nE '^[[:space:]]*\.[[:space:]]' "$rf" | head -n 2)"; else t_ok "v0.29.0 review F8 $(basename "$(dirname "$rf")"): no line starts with a stray '.'"; fi
done
if [ "$TW_SW" -le 1100 ] && [ "$TW_LW" -le 700 ]; then t_ok "v0.29.0 review F8 the word budgets still hold (setup $TW_SW <= 1100, learn $TW_LW <= 700)"; else t_bad "v0.29.0 review F8 the word budgets still hold" "setup $TW_SW, learn $TW_LW"; fi

echo "v0.29.0 lane w T F3: README Limits name the AGENTS.global text rule and agent self-trust"
qchk "v0.29.0 T F3 Limits: the AGENTS.global.md text rule still tells agents to read LEARNINGS.md" "$K1B_LIM" 'AGENTS\.global\.md.{0,255}LEARNINGS\.md|LEARNINGS\.md.{0,255}AGENTS\.global\.md'
qchk "v0.29.0 T F3 Limits: the trust gate covers only the automatic injection by the hook" "$K1B_LIM" 'text rule.{0,255}(trust|inject)|(trust|inject).{0,255}text rule'
qchk "v0.29.0 T F3 Limits: an agent could run learn.sh trust itself" "$K1B_LIM" 'learn\.sh trust.{0,255}(agent|itself|own)|(agent|itself).{0,255}learn\.sh trust'

t_summary
