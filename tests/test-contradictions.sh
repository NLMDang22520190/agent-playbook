#!/usr/bin/env bash
# Lane C (v0.26.3) S3, spec A5: each contradiction of scales.md section 7 (C1-C12, C6 dropped) is resolved to ONE rule,
# and that rule is pinned in every file that states it. Pins read joined text (a rule wrapped over lines still matches) and
# use key phrases of the new rule, not exact sentences, except where the spec gives the exact string (C4, C9, C12).
# Earlier pins on the old wording are edited in their own suites (.agents/handoff/pin-migration.tsv, disposition E).
. "$(dirname "$0")/lib.sh"
BLOCK="$PB_ROOT/AGENTS.global.md"
TDD="$PB_ROOT/skills/playbook-tdd"
SK="$TDD/SKILL.md"
PROOF="$PB_ROOT/skills/playbook-proof/SKILL.md"
TQ="$TDD/references/test-quality.md"
RP="$TDD/templates/role-prompt.md"
FULL="$TDD/references/full.md"
FB="$PB_ROOT/skills/playbook-feedback/SKILL.md"
README="$PB_ROOT/README.md"
RUBRIC="$PB_ROOT/evals/RUBRIC.md"
SCEN="$PB_ROOT/evals/scenarios.md"

# sec FILE HEADING_ERE -> the section from the first heading matching HEADING_ERE up to the next heading of the same or a
# higher level, joined into one line (newlines become spaces, runs of spaces squeezed)
sec() {
  awk -v re="$2" '
    /^#+ / { lv = index($0, " ") - 1; if (f && lv <= flv) exit; if (!f && $0 ~ re) { f = 1; flv = lv } }
    f { print }' "$1" 2>/dev/null | tr '\n' ' ' | tr -s ' '
}
# joined FILE -> the whole file on one line
joined() { tr '\n' ' ' < "$1" 2>/dev/null | tr -s ' '; }
# has NAME TEXT ERE / hasnt NAME TEXT ERE (case-sensitive ERE on TEXT)
has() { if printf '%s' "$2" | grep -qE -- "$3"; then t_ok "$1"; else t_bad "$1" "pattern [$3] not found"; fi; }
hasi() { if printf '%s' "$2" | grep -qiE -- "$3"; then t_ok "$1"; else t_bad "$1" "pattern [$3] not found (any case)"; fi; }
hasnt() { if printf '%s' "$2" | grep -qE -- "$3"; then t_bad "$1" "pattern [$3] still found"; else t_ok "$1"; fi; }

SCOPE_J="$(sec "$BLOCK" '^### Scope discipline')"
TDD_J="$(sec "$BLOCK" '^### TDD with separated roles')"
CLAR_J="$(sec "$BLOCK" '^### Clarify before changing')"
WEIGHT_J="$(sec "$SK" '^## Pick the weight')"
STOP_J="$(sec "$SK" '^## Stop and ask the user when')"

echo "C1 skip/quarantine: one rule - a skip, a quarantine included, needs the user's explicit OK"
has "C1 block: never weaken, skip or delete a test or gate to make it pass without the user's explicit OK" "$SCOPE_J" \
  "Never weaken, skip or delete a test or gate to make it pass without the user.s explicit OK"
has "C1 block: quarantining a flaky test is a skip" "$SCOPE_J" '[Qq]uarantin(e|ing)[^.]{0,30}flaky test is a skip'
FLAKY_J="$(sec "$TQ" '^## Flaky tests')"
has "C1 test-quality.md Flaky tests: a quarantine needs the user's explicit OK" "$FLAKY_J" "[Qq]uarantin[^.]{0,120}user.s explicit OK|user.s explicit OK[^.]{0,120}[Qq]uarantin"
has "C1 test-quality.md Flaky tests: a quarantine names an issue link" "$FLAKY_J" '[Qq]uarantin[^.]{0,200}issue link'
has "C1 test-quality.md Flaky tests: a quarantine adds a line under Not checked" "$FLAKY_J" '[Qq]uarantin[^.]{0,250}Not checked'
hasnt "C1 test-quality.md no longer says to quarantine with only an issue link" "$FLAKY_J" 'Quarantine it with an issue link, and fix'
# characterization: the proof DoD already allows it with the user's approval (unchanged by C1)
has "C1 characterization: the proof definition of done keeps (or the user approved it explicitly)" "$(joined "$PROOF")" \
  'weakened, skipped or deleted \(or the user approved it explicitly\)'

echo "C2 proof scope: the heading says claims that matter, in the block and the proof skill"
if grep -qxF '### Proof for claims that matter' "$BLOCK" 2>/dev/null; then t_ok "C2 block heading is exactly ### Proof for claims that matter"
else t_bad "C2 block heading is exactly ### Proof for claims that matter" "no such line in AGENTS.global.md"; fi
if grep -qxF '# Proof for claims that matter' "$PROOF" 2>/dev/null; then t_ok "C2 playbook-proof title is exactly # Proof for claims that matter"
else t_bad "C2 playbook-proof title is exactly # Proof for claims that matter" "no such line in playbook-proof SKILL.md"; fi
for f in "$BLOCK" "$PROOF"; do
  if grep -q 'Proof for every claim' "$f" 2>/dev/null; then t_bad "C2 $(basename "$(dirname "$f")")/$(basename "$f") no longer says Proof for every claim" "still there"
  else t_ok "C2 $(basename "$(dirname "$f")")/$(basename "$f") no longer says Proof for every claim"; fi
done

echo "C3 ask once vs many stops: one opening batch, the AC-list OK after Phase 1, a closed list of mid-task stops, one closing message"
has "C3 block: other stops are only the ones playbook-tdd lists" "$CLAR_J" 'Other stops: only those `playbook-tdd` lists'
has "C3 block: the summary still ends with assumptions and logged defaults" "$CLAR_J" '[Ee]nd the summary with assumptions and logged defaults'
hasi "C3 core Stop and ask: start questions go in one opening batch" "$STOP_J" 'start[^.]{0,80}one opening batch|one opening batch[^.]{0,80}start'
hasi "C3 core Stop and ask: the opening batch holds hard-to-reverse ambiguities" "$STOP_J" 'opening batch[^.]{0,200}ambiguit'
hasi "C3 core Stop and ask: the opening batch holds commit permission" "$STOP_J" 'opening batch[^.]{0,250}commit'
hasi "C3 core Stop and ask: the opening batch holds a model change" "$STOP_J" 'opening batch[^.]{0,250}model'
hasi "C3 core Stop and ask: the AC-list OK is asked at the end of Phase 1, after the spec exists" "$STOP_J" 'AC[- ]list[^.]{0,120}end of Phase 1[^.]{0,80}after the spec'
hasi "C3 core Stop and ask: the AC-list OK is only for an ambiguous request" "$STOP_J" 'AC[- ]list[^.]{0,80}ambiguous'
hasi "C3 core Stop and ask: mid-task stops are only the listed ones" "$STOP_J" 'mid-task stops are only'
hasi "C3 mid-task stop: a dispute or spec review still open after 2 rounds" "$STOP_J" 'dispute or spec review[^.;]{0,40}open after 2 rounds'
hasi "C3 mid-task stop: the first-slice checkpoint" "$STOP_J" 'first-slice checkpoint'
hasi "C3 mid-task stop: a new Full criterion after an override" "$STOP_J" 'new Full criterion[^.;]{0,30}override'
hasi "C3 mid-task stop: quick work past the size limit" "$STOP_J" 'quick[^.;]{0,30}size limit'
hasi "C3 mid-task stop: a test that seems to need weakening" "$STOP_J" 'weaken'
hasi "C3 mid-task stop: baseline failures that make RED/GREEN unreadable" "$STOP_J" 'baseline[^.;]{0,60}unreadable'
# review 263c finding 2 (orchestrator decision 2): the closed list also names the two scope stops it lost
hasi "C3 mid-task stop: adding a dependency" "$STOP_J" 'mid-task stops are only[^.]{0,500}(add|adding|new)[^.;]{0,20}dependenc'
hasi "C3 mid-task stop: touching code outside the request" "$STOP_J" 'mid-task stops are only[^.]{0,500}(code outside the request|unrelated code)'
hasi "C3 core Stop and ask: end-of-task questions go in one closing message" "$STOP_J" 'end-of-task questions[^.]{0,120}one closing message'
for q in learn feedback humanizer; do
  hasi "C3 the closing message names the $q question" "$STOP_J" "end-of-task questions[^.]{0,100}$q"
done

echo "C4 who looks at UI: README says one real look, an agent screenshot or browser read counts"
has "C4 README rule row: a UI change needs one real look at the screen (an agent screenshot or browser read counts)" "$(cat "$README")" \
  '\| A UI change needs one real look at the screen \(an agent screenshot or browser read counts\)\.? \|'
hasnt "C4 README no longer says a UI change needs someone to look at the screen" "$(cat "$README")" 'needs someone to look at the screen'

echo "C5 RUBRIC E1-E17: every scenario of evals/scenarios.md has a row in evals/RUBRIC.md (D10)"
IDS="$(grep -oE '^## E[0-9]+ ' "$SCEN" | sed 's/^## //; s/ $//')"
NIDS="$(printf '%s\n' "$IDS" | grep -c .)"
if [ "$NIDS" -ge 30 ]; then t_ok "C5 the scenario list is not empty ($NIDS ids)"; else t_bad "C5 the scenario list is not empty" "$NIDS ids"; fi
MISSING=""
for e in $IDS; do grep -qE "^\| $e " "$RUBRIC" 2>/dev/null || MISSING="$MISSING $e"; done
assert_eq "C5 no scenario id is missing from the RUBRIC.md table" "" "$MISSING"

echo "C7 feedback example: the --eval example carries no scenario number"
FBT="$(cat "$FB")"
has "C7 the example reads --eval \"new: implementer edits a snapshot file\"" "$FBT" '--eval "new: implementer edits a snapshot file"'
hasnt "C7 no --eval \"new: E<n> ...\" example in playbook-feedback SKILL.md" "$FBT" '--eval "new: E[0-9]'

echo "C8 role independence: the context pack is facts only, the same sentence in role-prompt.md 2b and references/full.md"
RP_J="$(sec "$RP" '^## 2b\. Context pack')"
# the paragraph of references/full.md that defines the context pack (blank-line separated)
FULL_J="$(awk 'BEGIN { RS = "" } /Context pack/' "$FULL" 2>/dev/null | tr '\n' ' ' | tr -s ' ')"
C8RE='[Ff]acts only: paths with line ranges, verbatim excerpts, commands; no diagnosis, proposed fix or opinion'
has "C8 role-prompt.md 2b: facts only, no diagnosis, proposed fix or opinion" "$RP_J" "$C8RE"
has "C8 references/full.md context pack paragraph: facts only, no diagnosis, proposed fix or opinion" "$FULL_J" "$C8RE"

echo "C9 Lite summary: the block points to the skill for the Lite steps"
has "C9 block: **Lite** (one context; its steps are in the skill)" "$TDD_J" '\*\*Lite\*\* \(one context; its steps are in the skill\)'
hasnt "C9 block no longer lists the Lite steps (test seen failing, role gate, evidence)" "$(cat "$BLOCK")" 'test seen failing, role gate, evidence'

echo "C10 when unsure: unsure means a Full criterion may apply and cannot be confirmed; the weight line names it"
has "C10 block: when unsure (name the criterion)" "$TDD_J" 'when unsure \(name the criterion\)'
hasi "C10 core: unsure = a Full criterion may apply but the repo cannot confirm it" "$WEIGHT_J" 'unsure[^.]{0,80}Full criterion may apply[^.]{0,80}(cannot|can.t) confirm'
hasi "C10 core: the weight line names that criterion and why it is unconfirmed" "$WEIGHT_J" 'weight line names (that|the) criterion[^.]{0,60}unconfirmed'
hasi "C10 core: unsure still chooses Full" "$WEIGHT_J" 'unsure[^.]{0,200}choose Full'

echo "C12 rename rule: Full when the export has a caller outside its file or module or is published; 0 hits = Lite with a risk line"
SK_J="$(joined "$SK")"
has "C12 core keeps the exact string quoted by E25" "$SK_J" 'removing or renaming an exported symbol is a public API change: Full'
has "C12 core: the next sentence starts This applies when" "$SK_J" 'removing or renaming an exported symbol is a public API change: Full\. This applies when'
has "C12 core: the condition is a caller outside its own file or module" "$SK_J" 'This applies when[^.]{0,80}caller outside its (own )?file or module'
has "C12 core: or the package is published" "$SK_J" 'This applies when[^.]{0,160}published'
has "C12 core: an Impact scan with no outside caller (command and 0 hits) is Lite with a risk line" "$SK_J" 'Impact scan[^.]{0,80}(none|0 hits)[^.]{0,80}Lite with a risk line'
has "C12 block: the rename rule names the outside use" "$TDD_J" '(rename|removal)[^.]{0,40}export[^.]{0,40}(used outside|caller outside|outside its)[^.]{0,60}public API change: Full'
# review 263c finding 6: the block keeps the "or published" condition of the core rule
has "C12 block: the rename rule also covers a published export" "$TDD_J" '(rename|removal)[^.]{0,40}export[^.]{0,120}published'

t_summary
