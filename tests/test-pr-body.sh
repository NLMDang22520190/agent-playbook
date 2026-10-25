#!/usr/bin/env bash
# Tests for scripts/pr-body.sh (v0.22.3 AC4.1): the PR description from the spec, the final report and the review verdict.
#   pr-body.sh [--handoff DIR]    default DIR = .agents/handoff
# Prints markdown: ## Summary (spec Goal/Understanding first paragraph + the final report's Result line), then
# ## Request coverage, ## Not checked, ## Review copied from 06-final-report.md, and a Weight line.
# Exit: 0 ok, 1 01-spec.md or 06-final-report.md missing (names the file), 2 usage.
# It never adds harness or vendor text. Fixtures are made here; no real handoff is read.
. "$(dirname "$0")/lib.sh"
PRB="$PB_ROOT/scripts/pr-body.sh"

H="$(mk_tmp)"
export PLAYBOOK_HOME="$H"
unset PLAYBOOK_HARNESS

# mkh DIR [understanding-heading] -> a handoff directory with a spec and a final report
mkh() {
  local d="$1" head="${2:-Understanding}"
  mkdir -p "$d"
  cat > "$d/01-spec.md" <<EOS
# 01 - Spec: widget export

## Source
- S1 "Export the widgets as CSV."

## Goal
GOAL-PARA-ONE: let a user export every widget as one CSV file.

GOAL-PARA-TWO: this second paragraph must not reach the summary.

## $head
UNDERSTANDING-PARA-ONE: the export covers all widgets of the signed-in user and nothing else.
It wraps over a second line of the same paragraph.

UNDERSTANDING-PARA-TWO: this second understanding paragraph must not reach the summary.

## Impact
IMPACT-MARKER: src/export.js

## Acceptance criteria
- AC1 AC-SPEC-MARKER
EOS
  cat > "$d/06-final-report.md" <<'EOR'
# 06 - Final report: widget export

**Result:** RESULT-LINE: widgets export as CSV and the tests pass.
**Weight:** Full · reason: REASON-MARKER changes a public file format
**Mode:** native

## Request coverage
One row for each sentence of the raw request.
| Request sentence (verbatim) | Status |
|---|---|
| "COVERAGE-ROW-ONE export widgets" | done: src/export.js:10 |
| "COVERAGE-ROW-TWO as CSV" | done: AC1 |

## AC to tests to evidence
| AC | Tests | Evidence | Confidence |
|---|---|---|---|
| AC1 | AC-TABLE-MARKER | log | high |

## Not checked
- NOTCHECKED-ONE: the export on a 1 GB account was not run.
- NOTCHECKED-TWO: Windows paths.

## Gates (fresh, after the last change)
GATES-MARKER proof block

## Pre-mortem
PREMORTEM-MARKER risk

## Cost
COST-MARKER table

## Review
Verdict: OK (model: reviewer-model). REVIEW-LINE-ONE findings resolved: 2. Open: none.

## Scope
SCOPE-MARKER diff stat

## Assumptions
- ASSUMPTION-MARKER
EOR
}
body() { run_in "${2:-$P}" bash "$PRB" "$@"; }
# sec TEXT HEADING -> the lines after the exact heading line up to the next "## " heading
sec() { printf '%s\n' "$1" | awk -v h="$2" 'f && /^## /{exit} $0 == h {f = 1; next} f {print}'; }
lnum() { printf '%s\n' "$1" | grep -n -m1 -x -- "$2" | cut -d: -f1; }

echo "pr-body.sh: the script exists"
assert_file "AC4.1 scripts/pr-body.sh exists" "$PRB"

echo "pr-body.sh: output from fixture handoff files (--handoff DIR)"
P="$(mk_tmp)"; HD="$(mk_tmp)/h"; mkh "$HD"
SUMB="$(cat "$HD/01-spec.md" "$HD/06-final-report.md" | cksum)"
run_in "$P" bash "$PRB" --handoff "$HD"
assert_rc "AC4.1 exits 0 with both files present" 0
BODY="$OUT"
for h in '## Summary' '## Request coverage' '## Not checked' '## Review'; do
  if printf '%s\n' "$BODY" | grep -qxF -- "$h"; then t_ok "AC4.1 the output has the heading $h"; else t_bad "AC4.1 the output has the heading $h" "$BODY"; fi
done
A="$(lnum "$BODY" '## Summary')"; B="$(lnum "$BODY" '## Request coverage')"; C="$(lnum "$BODY" '## Not checked')"; D="$(lnum "$BODY" '## Review')"
if [ -n "$A" ] && [ -n "$B" ] && [ -n "$C" ] && [ -n "$D" ] && [ "$A" -lt "$B" ] && [ "$B" -lt "$C" ] && [ "$C" -lt "$D" ]; then t_ok "AC4.1 the headings come in the order Summary, Request coverage, Not checked, Review"; else t_bad "AC4.1 the headings come in the order Summary, Request coverage, Not checked, Review" "lines: $A $B $C $D"; fi
S="$(sec "$BODY" '## Summary')"
assert_contains "AC4.1 Summary has the Understanding first paragraph" "$S" "UNDERSTANDING-PARA-ONE"
assert_contains "AC4.1 Summary keeps the wrapped second line of that paragraph" "$S" "second line of the same paragraph"
assert_not_contains "AC4.1 Summary stops after the first paragraph" "$S" "UNDERSTANDING-PARA-TWO"
assert_contains "AC4.1 Summary has the final report's Result line" "$S" "RESULT-LINE: widgets export as CSV and the tests pass."
assert_not_contains "AC4.1 Summary does not carry the Result label markup" "$S" "**Result:**"
assert_not_contains "AC4.1 Summary has no other spec section (Impact)" "$S" "IMPACT-MARKER"
RC_="$(sec "$BODY" '## Request coverage')"
assert_contains "AC4.1 Request coverage copies row one" "$RC_" '| "COVERAGE-ROW-ONE export widgets" | done: src/export.js:10 |'
assert_contains "AC4.1 Request coverage copies row two" "$RC_" '| "COVERAGE-ROW-TWO as CSV" | done: AC1 |'
assert_contains "AC4.1 Request coverage copies the table heading" "$RC_" '| Request sentence (verbatim) | Status |'
assert_not_contains "AC4.1 Request coverage stops at the next report section" "$RC_" "AC-TABLE-MARKER"
NC="$(sec "$BODY" '## Not checked')"
assert_contains "AC4.1 Not checked copies the first item" "$NC" "- NOTCHECKED-ONE: the export on a 1 GB account was not run."
assert_contains "AC4.1 Not checked copies the second item" "$NC" "- NOTCHECKED-TWO: Windows paths."
assert_not_contains "AC4.1 Not checked stops at the next report section" "$NC" "GATES-MARKER"
RV="$(sec "$BODY" '## Review')"
assert_contains "AC4.1 Review copies the verdict line" "$RV" "Verdict: OK (model: reviewer-model). REVIEW-LINE-ONE findings resolved: 2. Open: none."
assert_not_contains "AC4.1 Review stops at the next report section" "$RV" "SCOPE-MARKER"
WL="$(printf '%s\n' "$BODY" | grep -A1 'Weight')"
[ -n "$WL" ] && t_ok "AC4.1 a Weight line is present" || t_bad "AC4.1 a Weight line is present" "$BODY"
assert_contains "AC4.1 the Weight line names the weight (Full)" "$WL" "Full"
assert_contains "AC4.1 the Weight line carries the reason from the report" "$(printf '%s\n' "$BODY" | grep 'REASON-MARKER')" "changes a public file format"
for m in GATES-MARKER PREMORTEM-MARKER COST-MARKER SCOPE-MARKER ASSUMPTION-MARKER AC-TABLE-MARKER AC-SPEC-MARKER GOAL-PARA-TWO; do
  assert_not_contains "AC4.1 report sections that are not copied stay out ($m)" "$BODY" "$m"
done
assert_eq "AC4.1 the handoff files are not modified" "$SUMB" "$(cat "$HD/01-spec.md" "$HD/06-final-report.md" | cksum)"
assert_eq "AC4.1 nothing is written next to the handoff files" "01-spec.md 06-final-report.md" "$(ls "$HD" | tr '\n' ' ' | sed 's/ $//')"

echo "pr-body.sh: the summary takes the Goal paragraph when there is no Understanding"
P="$(mk_tmp)"; HG="$(mk_tmp)/h"; mkh "$HG" "Understanding"
# a spec with only a Goal section
awk '/^## Understanding/ { skip = 1; next } skip && /^## / { skip = 0 } !skip { print }' "$HG/01-spec.md" > "$HG/01-spec.tmp" && mv "$HG/01-spec.tmp" "$HG/01-spec.md"
run_in "$P" bash "$PRB" --handoff "$HG"
assert_rc "AC4.1 a spec with a Goal only: exit 0" 0
S="$(sec "$OUT" '## Summary')"
assert_contains "AC4.1 Summary has the Goal first paragraph" "$S" "GOAL-PARA-ONE: let a user export every widget as one CSV file."
assert_not_contains "AC4.1 Summary has only the first Goal paragraph" "$S" "GOAL-PARA-TWO"
assert_contains "AC4.1 Summary still has the Result line" "$S" "RESULT-LINE"

echo "pr-body.sh: the default handoff directory is .agents/handoff"
P="$(mk_tmp)"; mkh "$P/.agents/handoff"
run_in "$P" bash "$PRB"
assert_rc "AC4.1 no option: reads .agents/handoff of the project: exit 0" 0
assert_contains "AC4.1 default directory: the summary comes from its spec" "$OUT" "UNDERSTANDING-PARA-ONE"
assert_contains "AC4.1 default directory: the Not checked section comes from its report" "$OUT" "NOTCHECKED-ONE"

echo "pr-body.sh: a missing spec or final report exits 1 and names the file"
P="$(mk_tmp)"; HM="$(mk_tmp)/h"; mkh "$HM"; rm -f "$HM/01-spec.md"
run_in "$P" bash "$PRB" --handoff "$HM"
assert_rc "AC4.1 no 01-spec.md: exit 1" 1
assert_contains "AC4.1 no 01-spec.md: the message names 01-spec.md" "$OUT" "01-spec.md"
assert_not_contains "AC4.1 no 01-spec.md: no half-built body (no Summary heading)" "$OUT" "## Summary"
HM="$(mk_tmp)/h"; mkh "$HM"; rm -f "$HM/06-final-report.md"
run_in "$P" bash "$PRB" --handoff "$HM"
assert_rc "AC4.1 no 06-final-report.md: exit 1" 1
assert_contains "AC4.1 no 06-final-report.md: the message names 06-final-report.md" "$OUT" "06-final-report.md"
assert_not_contains "AC4.1 no 06-final-report.md: no half-built body (no Summary heading)" "$OUT" "## Summary"
HM="$(mk_tmp)/empty"; mkdir -p "$HM"
run_in "$P" bash "$PRB" --handoff "$HM"
assert_rc "AC4.1 an empty handoff directory: exit 1" 1
assert_contains "AC4.1 an empty handoff directory: names the spec" "$OUT" "01-spec.md"
run_in "$P" bash "$PRB" --handoff "$P/does-not-exist"
assert_rc "AC4.1 a handoff directory that does not exist: exit 1" 1
P="$(mk_tmp)"
run_in "$P" bash "$PRB"
assert_rc "AC4.1 no option and no .agents/handoff: exit 1" 1
assert_contains "AC4.1 ... and the message names a missing file" "$OUT" "01-spec.md"

echo "pr-body.sh: bad usage exits 2"
P="$(mk_tmp)"; mkh "$P/.agents/handoff"
run_in "$P" bash "$PRB" --bogus
assert_rc "AC4.1 unknown option: exit 2" 2
run_in "$P" bash "$PRB" --handoff
assert_rc "AC4.1 --handoff without a value: exit 2" 2
run_in "$P" bash "$PRB" extra
assert_rc "AC4.1 a stray argument: exit 2" 2
run_in "$P" bash "$PRB" --handoff "$P/.agents/handoff" extra
assert_rc "AC4.1 a stray argument after --handoff DIR: exit 2" 2
run_in "$P" bash "$PRB" --handoff ""
assert_rc "AC4.1 an empty --handoff value: exit 2" 2

echo "pr-body.sh: no harness or vendor text"
P="$(mk_tmp)"; HV="$(mk_tmp)/h"; mkh "$HV"
run_in "$P" bash "$PRB" --handoff "$HV"
LOWER="$(printf '%s\n' "$OUT" | tr '[:upper:]' '[:lower:]')"
assert_not_contains "AC4.1 no 'Claude' in the output" "$LOWER" "claude"
assert_not_contains "AC4.1 no 'Generated with' in the output" "$LOWER" "generated with"
assert_not_contains "AC4.1 no 'Co-Authored' in the output" "$LOWER" "co-authored"
assert_not_contains "AC4.1 no 'Anthropic' in the output" "$LOWER" "anthropic"
# the same with a harness set in the environment: still nothing added
PLAYBOOK_HARNESS=claude-code run_in "$P" bash "$PRB" --handoff "$HV"
LOWER="$(printf '%s\n' "$OUT" | tr '[:upper:]' '[:lower:]')"
assert_not_contains "AC4.1 PLAYBOOK_HARNESS=claude-code adds no 'Claude' text" "$LOWER" "claude"
assert_not_contains "AC4.1 PLAYBOOK_HARNESS=claude-code adds no 'Generated with' text" "$LOWER" "generated with"
# the script itself carries no vendor footer
if [ -f "$PRB" ]; then
  SL="$(tr '[:upper:]' '[:lower:]' < "$PRB")"
  assert_not_contains "AC4.1 the script source has no 'Generated with' footer" "$SL" "generated with"
  assert_not_contains "AC4.1 the script source has no 'Co-Authored' trailer" "$SL" "co-authored"
else
  t_bad "AC4.1 the script source has no 'Generated with' footer" "no such file: $PRB"
  t_bad "AC4.1 the script source has no 'Co-Authored' trailer" "no such file: $PRB"
fi

# --- v0.26.1 lane R: Decisions from decisions.md, Unverified lines of the report, the Phase 4 PR line
echo "pr-body.sh: ## Decisions from decisions.md (template table: decision + how to undo)"
P="$(mk_tmp)"; HD2="$(mk_tmp)/h"; mkh "$HD2"
cat > "$HD2/decisions.md" <<'EOD'
# Decisions: widget export

Defaults chosen without asking because they are reversible. BOILERPLATE-MARKER Review them in one batch at the end.

| ID | Decision (the default taken) | Why this default | Alternatives | How to undo | Where (`path:line`, marker) | Status |
|---|---|---|---|---|---|---|
| D1 | DEC-ONE comma as separator | WHY-ONE-MARKER spreadsheets expect it | semicolon | UNDO-ONE set SEP in src/export.js | `src/export.js:4` `DECISION[D1]` | open |
| D2 | DEC-TWO UTF-8 with BOM | WHY-TWO-MARKER Excel | no BOM | UNDO-TWO drop the BOM write | `src/export.js:9` | confirmed |

Status: `open` (waiting for review) · STATUS-FOOTER-MARKER
EOD
run_in "$P" bash "$PRB" --handoff "$HD2"
assert_rc "v0.26.1 R with decisions.md: exit 0" 0
BODY2="$OUT"
if printf '%s\n' "$BODY2" | grep -qxF -- '## Decisions'; then t_ok "v0.26.1 R the output has the heading ## Decisions"; else t_bad "v0.26.1 R the output has the heading ## Decisions" "$BODY2"; fi
DS="$(sec "$BODY2" '## Decisions')"
assert_contains "v0.26.1 R Decisions has decision D1" "$DS" "DEC-ONE comma as separator"
assert_contains "v0.26.1 R Decisions has decision D2" "$DS" "DEC-TWO UTF-8 with BOM"
assert_contains "v0.26.1 R Decisions has how to undo D1" "$DS" "UNDO-ONE set SEP in src/export.js"
assert_contains "v0.26.1 R Decisions has how to undo D2" "$DS" "UNDO-TWO drop the BOM write"
assert_contains "v0.26.1 R Decisions keeps the ids" "$DS" "D1"
assert_not_contains "v0.26.1 R Decisions leaves out the template boilerplate" "$DS" "BOILERPLATE-MARKER"
assert_not_contains "v0.26.1 R Decisions leaves out the status footer" "$DS" "STATUS-FOOTER-MARKER"
A="$(lnum "$BODY2" '## Summary')"; B="$(lnum "$BODY2" '## Request coverage')"; C="$(lnum "$BODY2" '## Not checked')"; D="$(lnum "$BODY2" '## Review')"; E="$(lnum "$BODY2" '## Decisions')"
if [ -n "$A" ] && [ -n "$E" ] && [ "$A" -lt "$B" ] && [ "$B" -lt "$C" ] && [ "$C" -lt "$D" ] && [ "$D" -lt "$E" ]; then t_ok "v0.26.1 R existing order kept, Decisions after Review"; else t_bad "v0.26.1 R existing order kept, Decisions after Review" "lines: $A $B $C $D $E"; fi
assert_contains "v0.26.1 R the Weight line is still there" "$BODY2" "REASON-MARKER"

echo "pr-body.sh: ## Decisions omitted when decisions.md is missing, empty or has no rows"
P="$(mk_tmp)"; HD3="$(mk_tmp)/h"; mkh "$HD3"
run_in "$P" bash "$PRB" --handoff "$HD3"
assert_not_contains "v0.26.1 R no decisions.md: no Decisions heading" "$OUT" "## Decisions"
: > "$HD3/decisions.md"
run_in "$P" bash "$PRB" --handoff "$HD3"
assert_rc "v0.26.1 R empty decisions.md: exit 0" 0
assert_not_contains "v0.26.1 R empty decisions.md: no Decisions heading" "$OUT" "## Decisions"
printf '\n  \n\n' > "$HD3/decisions.md"
run_in "$P" bash "$PRB" --handoff "$HD3"
assert_not_contains "v0.26.1 R blank-only decisions.md: no Decisions heading" "$OUT" "## Decisions"
printf '# Decisions: x\n\n| ID | Decision (the default taken) | Why this default | Alternatives | How to undo | Where | Status |\n|---|---|---|---|---|---|---|\n' > "$HD3/decisions.md"
run_in "$P" bash "$PRB" --handoff "$HD3"
assert_not_contains "v0.26.1 R decisions.md with a header row only (D-default): no Decisions heading" "$OUT" "## Decisions"

echo "pr-body.sh: free-form decisions.md is copied (D-default)"
P="$(mk_tmp)"; HD4="$(mk_tmp)/h"; mkh "$HD4"
printf '# Decisions\n\n- FREE-DEC-ONE: sort newest first; undo: flip the comparator\n- FREE-DEC-TWO: retry 3 times; undo: set RETRIES=0\n' > "$HD4/decisions.md"
run_in "$P" bash "$PRB" --handoff "$HD4"
DS="$(sec "$OUT" '## Decisions')"
assert_contains "v0.26.1 R free-form decision one copied verbatim" "$DS" "- FREE-DEC-ONE: sort newest first; undo: flip the comparator"
assert_contains "v0.26.1 R free-form decision two copied verbatim" "$DS" "- FREE-DEC-TWO: retry 3 times; undo: set RETRIES=0"
assert_not_contains "v0.26.1 R free-form: the file title is not copied" "$DS" "# Decisions"

echo "pr-body.sh: Not checked copied verbatim, inner blank lines and sub-items kept"
P="$(mk_tmp)"; HD5="$(mk_tmp)/h"; mkh "$HD5"
awk '{ print } /^- NOTCHECKED-TWO/ { print "  - NOTCHECKED-SUB: only Linux ran"; print ""; print "NOTCHECKED-PARA after a blank line." }' "$HD5/06-final-report.md" > "$HD5/r.tmp" && mv "$HD5/r.tmp" "$HD5/06-final-report.md"
run_in "$P" bash "$PRB" --handoff "$HD5"
NC="$(sec "$OUT" '## Not checked')"
EXP="$(printf '%s\n' '- NOTCHECKED-ONE: the export on a 1 GB account was not run.' '- NOTCHECKED-TWO: Windows paths.' '  - NOTCHECKED-SUB: only Linux ran' '' 'NOTCHECKED-PARA after a blank line.')"
assert_eq "v0.26.1 R Not checked is the report section verbatim" "$EXP" "$(printf '%s\n' "$NC" | sed -e '/./,$!d' | awk '{ a[NR] = $0 } END { n = NR; while (n > 0 && a[n] == "") n--; for (i = 1; i <= n; i++) print a[i] }')"

echo "pr-body.sh: ## Unverified lists every report line with [UNVERIFIED]"
P="$(mk_tmp)"; HD6="$(mk_tmp)/h"; mkh "$HD6"
cat >> "$HD6/06-final-report.md" <<'EOU'
- UNV-ASSUME: the CSV reader is Excel 2019 [UNVERIFIED]

## Found, not fixed / [UNVERIFIED]
- UNV-FOUND: large accounts may time out [UNVERIFIED]
| AC2 | UNV-TABLE-ROW | none | low [UNVERIFIED] |
- FOUND-PLAIN: a line without the label
EOU
run_in "$P" bash "$PRB" --handoff "$HD6"
assert_rc "v0.26.1 R report with [UNVERIFIED] lines: exit 0" 0
if printf '%s\n' "$OUT" | grep -qxF -- '## Unverified'; then t_ok "v0.26.1 R the output has the heading ## Unverified"; else t_bad "v0.26.1 R the output has the heading ## Unverified" "$OUT"; fi
US="$(sec "$OUT" '## Unverified')"
assert_contains "v0.26.1 R Unverified lists the Assumptions line" "$US" "UNV-ASSUME: the CSV reader is Excel 2019 [UNVERIFIED]"
assert_contains "v0.26.1 R Unverified lists the Found line" "$US" "UNV-FOUND: large accounts may time out [UNVERIFIED]"
assert_contains "v0.26.1 R Unverified lists the table row" "$US" "| AC2 | UNV-TABLE-ROW | none | low [UNVERIFIED] |"
assert_not_contains "v0.26.1 R Unverified leaves out lines without the label" "$US" "FOUND-PLAIN"
assert_not_contains "v0.26.1 R Unverified leaves out the heading that carries the label (D-default)" "$US" "Found, not fixed"
N_UNV="$(printf '%s\n' "$US" | grep -c 'UNVERIFIED')"
assert_eq "v0.26.1 R Unverified has exactly the three labelled lines" "3" "$N_UNV"
R_="$(lnum "$OUT" '## Review')"; U_="$(lnum "$OUT" '## Unverified')"
if [ -n "$U_" ] && [ -n "$R_" ] && [ "$R_" -lt "$U_" ]; then t_ok "v0.26.1 R Unverified comes after the existing sections"; else t_bad "v0.26.1 R Unverified comes after the existing sections" "lines: $R_ $U_"; fi
run_in "$P" bash "$PRB" --handoff "$HD3"
assert_not_contains "v0.26.1 R no [UNVERIFIED] line in the report: no Unverified heading" "$OUT" "## Unverified"

echo "playbook-tdd Phase 4: the PR description is the pr-body.sh output"
TDD_SK="$PB_ROOT/skills/playbook-tdd/SKILL.md"
P4="$(awk '/^### Phase 4/ { f = 1; next } f && /^##/ { exit } f { print }' "$TDD_SK" | tr '\n' ' ' | tr -s ' ')"
if printf '%s' "$P4" | grep -qiE 'PR[^.]{0,80}description[^.]{0,40}pr-body\.sh[^.]{0,20}output'; then t_ok "v0.26.1 R Phase 4 says the PR description is the pr-body.sh output"; else t_bad "v0.26.1 R Phase 4 says the PR description is the pr-body.sh output" "Phase 4 [$P4]"; fi


t_summary
