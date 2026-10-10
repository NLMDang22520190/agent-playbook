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

t_summary
