#!/usr/bin/env bash
# Lane C (v0.26.3) S2, spec A2e, A3-A3e, A4, A1c, A7: the playbook-tdd SKILL.md split into a core plus references/, and
# references/release.md out of the user skill.
#   A2e target pins: for each moved section, the TARGET file holds one key phrase of it (whitespace and markup do not count:
#       the files are read through tests/skill-keep-rows.sh flat). They fail until the text is at its target.
#   A3  SKILL.md core <= 1500 words (caller's locale, as evals/run-checks.sh counts); its budget is the count rounded up to 50
#   A3c the core points to each moved part; A3e the tree saves words; A4 release.md moved; A1c reference budgets; A7 the map
# The existing pins that moved with the text are migrated in their own suites (.agents/handoff/pin-migration.tsv).
. "$(dirname "$0")/lib.sh"
TDD="$PB_ROOT/skills/playbook-tdd"
SK="$TDD/SKILL.md"
REF="$TDD/references"
WB="$PB_ROOT/evals/word-budgets"
ROWS="$PB_ROOT/tests/skill-keep-rows.sh"
DOCS="$PB_ROOT/docs/release-speed.md"
BASE_SHA=ced2206   # the lane merge point (lane W references + v0.26.0 merged); the split itself must add no words after it

# tpin TARGET PHRASE: TARGET (path under the repo) holds PHRASE in its flat text
tpin() {
  local f="$PB_ROOT/$1"
  if [ -f "$f" ] && bash "$ROWS" flat "$f" | grep -qF -- "$2"; then t_ok "A2e $1 holds: $2"
  else t_bad "A2e $1 holds: $2" "$([ -f "$f" ] && echo "phrase not in $1" || echo "no file $1")"; fi
}
# thead TARGET HEADING: TARGET has a line exactly HEADING (the moved section keeps its heading text)
thead() {
  if grep -qxF -- "$2" "$PB_ROOT/$1" 2>/dev/null; then t_ok "A3b $1 keeps the heading: $2"; else t_bad "A3b $1 keeps the heading: $2" "no line exactly [$2]"; fi
}

echo "A2e/A3b Full-only detail -> references/full.md"
F=skills/playbook-tdd/references/full.md
thead "$F" '### Phase 1: Spec (orchestrator)'
thead "$F" '### Phase 2: Loop per slice (vertical slices, never "all tests first")'
thead "$F" '### Phase 3: Review (reviewer, read-only)'
thead "$F" '### Phase 4: Close-out (orchestrator)'
thead "$F" '## Resuming'
tpin "$F" 'set the project key `test_infra_regex`'
tpin "$F" 'The first RED covers the whole corpus, so a rewrite cannot quietly drop a case an earlier round fixed.'
tpin "$F" 'Spec review (Full). Run the spec reviewer (`roles/spec-reviewer.md`) before the first tester'
tpin "$F" 'Only an OK lets the first tester start.'
tpin "$F" 'Context pack. The orchestrator builds a context pack once per slice'
tpin "$F" 'Never let the implementer resolve a dispute itself.'
tpin "$F" 'REFACTOR (optional, implementer). Only on green, with tests untouched'
tpin "$F" 'First-slice checkpoint. When more than one slice repeats a pattern'
tpin "$F" 'Phase 3 code-review rounds are capped at 2 per lane or slice.'
tpin "$F" 'Fresh full run of test, lint and typecheck through `proof-run.sh`, after the last change.'
tpin "$F" 'When a session resumes or a context was lost, read `state.md` first, then the other hand-off files.'

echo "A2e/A3b parallel slices -> references/parallel.md, cost -> references/cost.md"
tpin skills/playbook-tdd/references/parallel.md 'Parallel slices. Slices whose files are disjoint (per the spec'
tpin skills/playbook-tdd/references/parallel.md 'A merge conflict makes those slices serial.'
tpin skills/playbook-tdd/references/parallel.md 'Slices that share a file stay serial from the start.'
tpin skills/playbook-tdd/references/cost.md 'Log each role run: `bash ~/.agents/playbook/scripts/cost.sh add --role <role>'
tpin skills/playbook-tdd/references/cost.md 'with tokens as the harness reports them (`0` if unknown, never a guess)'
tpin skills/playbook-tdd/references/cost.md '`cost.sh calibrate` shows per weight the review majors and rework rounds per task'

echo "A2e/A3b weight overrides -> references/weights.md, wrong -> references/wrong.md, plumbing -> references/harnesses.md"
W=skills/playbook-tdd/references/weights.md
tpin "$W" 'User override (Full to Lite). When the work meets a Full criterion and the user asks for Lite, ask once'
tpin "$W" 'The user says "quick" (or "quick one", "do it quick"): that counts as asking for Lite'
tpin "$W" 'provided the string is not parsed, matched or sent as data'
thead skills/playbook-tdd/references/wrong.md '## When the user says it is wrong'
tpin skills/playbook-tdd/references/wrong.md 'Classify the cause as one of: misread request, missed place (scan), wrong assumption, not verified live, real bug.'
tpin skills/playbook-tdd/references/wrong.md 'propose a regression eval scenario in the item'
H=skills/playbook-tdd/references/harnesses.md
tpin "$H" 'Two more roles route by task type.'
tpin "$H" 'use `bash ~/.agents/playbook/scripts/tdd-step.sh red green`'   # flat text: "|" reads as a space
tpin "$H" 'With a dirty tree, run `role-gate.sh snapshot` before the first role'

echo "A4 references/release.md leaves the user skill"
assert_no_path "A4 skills/playbook-tdd/references/release.md does not exist" "$REF/release.md"
RELN="$(grep -rlE 'release\.md' "$PB_ROOT/skills" 2>/dev/null | sed "s#^$PB_ROOT/##" | tr '\n' ' ')"
assert_eq "A4 no file under skills/ names release.md" "" "$RELN"
assert_file "A4 docs/release-speed.md exists" "$DOCS"
for id in AC3.3 AC3.4 AC3.5; do tpin docs/release-speed.md "($id)"; done
tpin docs/release-speed.md 'Prefer releases of 3-5 items'
tpin docs/release-speed.md 'A slow platform run (for example the Windows Git Bash suites) runs once before the PR'
tpin skills/playbook-tdd/roles/reviewer.md 'A pre-existing security MAJOR is raised to the user in one line (fix now or queue), and never fixed silently.'
if grep -q 'release-speed\.md' "$PB_ROOT/docs/development.md" 2>/dev/null; then t_ok "A4 docs/development.md links docs/release-speed.md"; else t_bad "A4 docs/development.md links docs/release-speed.md" "no release-speed.md in docs/development.md"; fi

echo "A3 the core is at most 1500 words and its budget follows it"
SKW="$(wc -w < "$SK" | tr -d ' ')"
if [ "$SKW" -le 1500 ]; then t_ok "A3 playbook-tdd SKILL.md is at most 1500 words ($SKW)"; else t_bad "A3 playbook-tdd SKILL.md is at most 1500 words" "$SKW words"; fi
budget_of() { awk -v f="$1" '{ sub(/\r$/, "") } $1 == f && $2 ~ /^[0-9]+$/ { print $2; exit }' "$WB" 2>/dev/null; }
SKB="$(budget_of skills/playbook-tdd/SKILL.md)"
if [ -n "$SKB" ] && [ "$SKB" -le 1500 ] && [ "$SKB" -ge "$SKW" ] && [ "$SKB" -lt $((SKW + 50)) ] && [ $((SKB % 50)) -eq 0 ]; then
  t_ok "A3 the SKILL.md budget is its count rounded up to the next 50, at most 1500 ($SKB for $SKW)"
else t_bad "A3 the SKILL.md budget is its count rounded up to the next 50, at most 1500" "budget [$SKB] count $SKW"; fi

echo "A3c the core points to each moved part"
SKFLAT="$(bash "$ROWS" flat "$SK")"
if printf '%s' "$SKFLAT" | grep -qiE 'at Full, read `references/full\.md` before Phase 1'; then t_ok "A3c the core says: at Full, read references/full.md before Phase 1"
else t_bad "A3c the core says: at Full, read references/full.md before Phase 1" "no such sentence in $SK"; fi
for r in parallel cost weights wrong; do
  if grep -q "references/$r\.md" "$SK" 2>/dev/null; then t_ok "A3c the core has a line naming references/$r.md"; else t_bad "A3c the core has a line naming references/$r.md" "not in $SK"; fi
done

echo "A1c every new or receiving reference has its own budget line"
for r in full parallel cost weights wrong harnesses; do
  p="skills/playbook-tdd/references/$r.md"; b="$(budget_of "$p")"
  w="$(wc -w < "$PB_ROOT/$p" 2>/dev/null | tr -d ' ')"
  if [ -n "$b" ] && [ -n "$w" ] && [ "$b" -ge "$w" ] && [ "$b" -le $((w + 10)) ] && [ $((b % 10)) -eq 0 ]; then
    t_ok "A1c $p has a budget line at its size rounded up to the next 10 ($b for $w)"
  else t_bad "A1c $p has a budget line at its size rounded up to the next 10" "budget [$b] words [$w]"; fi
done

echo "A3e the split adds no words: SKILL.md + references/*.md now <= the tree at the lane merge point + 200 for the S3 contradiction fixes (release.md left out on both sides)"
tree_words() { # REF: words of SKILL.md plus references/*.md except release.md, at git REF (or the work tree when REF is empty)
  local f n=0 w
  if [ -z "$1" ]; then
    for f in "$SK" "$REF"/*.md; do case "$f" in */release.md) continue ;; esac; w="$(wc -w < "$f" | tr -d ' ')"; n=$((n + w)); done
  else
    for f in $(git -C "$PB_ROOT" ls-tree --name-only "$1" skills/playbook-tdd/SKILL.md skills/playbook-tdd/references/ 2>/dev/null); do
      case "$f" in */release.md) continue ;; *.md) ;; *) continue ;; esac
      w="$(git -C "$PB_ROOT" show "$1:$f" | wc -w | tr -d ' ')"; n=$((n + w))
    done
  fi
  printf '%s\n' "$n"
}
if git -C "$PB_ROOT" cat-file -e "$BASE_SHA^{commit}" 2>/dev/null; then
  B0="$(tree_words "$BASE_SHA")"; B1="$(tree_words "")"
  if [ "$B1" -le $((B0 + 200)) ]; then t_ok "A3e tree words $B1 <= $B0 + 200 at $BASE_SHA"; else t_bad "A3e tree words at most the merge point + 200" "$B1 words, merge point $B0"; fi
else t_skip 1 "A3e the base commit $BASE_SHA is not in this clone"; fi

echo "A7 characterization: evals/scenario-map still sends a change to a new reference file to the playbook-tdd scenarios"
for r in full parallel cost weights wrong; do
  p="skills/playbook-tdd/references/$r.md"; got=""
  set -f
  while IFS= read -r line; do
    case "$line" in '' | '#'*) continue ;; esac
    set -- $line; g="$1"; shift
    # shellcheck disable=SC2254
    case "$p" in $g) got="$got $*" ;; esac
  done < "$PB_ROOT/evals/scenario-map"
  set +f
  miss=""
  for e in E1 E3 E4 E15 E16 E21 E22 E23 E26; do case " $got " in *" $e "*) ;; *) miss="$miss $e" ;; esac; done
  assert_eq "A7 a change to $p maps to E1 E3 E4 E15 E16 E21 E22 E23 E26" "" "$miss"
done

t_summary
