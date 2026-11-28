#!/usr/bin/env bash
# Tests for v0.38 Q9 slice S5: skills/playbook-learn/references/review.md and its pointer in SKILL.md
# (docs/v0.38-q9-s5-spec.md, AC1..AC17). The checks are text checks: they prove the written procedure is complete,
# not that a model follows it. PB_REVIEW_MD / PB_SKILL_MD point the suite at other copies (default: the repo files).
. "$(dirname "$0")/lib.sh"
LEARN="$PB_ROOT/scripts/learn.sh"
RV="${PB_REVIEW_MD:-$PB_ROOT/skills/playbook-learn/references/review.md}"
SK="${PB_SKILL_MD:-$PB_ROOT/skills/playbook-learn/SKILL.md}"
SKDIR="$(dirname "$SK")"

# flat FILE -> the file as one line, runs of blanks squeezed (a phrase may be wrapped over lines)
flat() { if [ -f "$1" ]; then tr '\n' ' ' < "$1" | tr -s ' '; fi; }
RF="$(flat "$RV")"
SF="$(flat "$SK")"

# has NAME DATA ERE (case-insensitive), hasF NAME DATA FIXED (case-sensitive), hasnt NAME DATA ERE FILE (needs FILE to exist,
# so a missing review.md cannot pass a negative check by being empty)
has() { if printf '%s\n' "$2" | grep -qiE -e "$3"; then t_ok "$1"; else t_bad "$1" "no match for: $3"; fi; }
hasF() { if printf '%s\n' "$2" | grep -qF -e "$3"; then t_ok "$1"; else t_bad "$1" "missing text: $3"; fi; }
hasnt() {
  if [ ! -f "$4" ]; then t_bad "$1" "file missing: $4"; return; fi
  if printf '%s\n' "$2" | grep -qiE -e "$3"; then t_bad "$1" "unexpected match for: $3"; else t_ok "$1"; fi
}
r() { has "$1" "$RF" "$2"; }
rF() { hasF "$1" "$RF" "$2"; }
rn() { hasnt "$1" "$RF" "$2" "$RV"; }

SQ="'"
BS2='\\'
QQ="${SQ}${BS2}${SQ}${SQ}"   # ERE for the four characters '\''

echo "AC1 review.md exists, size, ASCII, installer untouched"
assert_file "AC1 review.md exists" "$RV"
RW=0; if [ -f "$RV" ]; then RW="$(wc -w < "$RV" | tr -d ' ')"; fi
if [ "$RW" -ge 200 ] && [ "$RW" -le 700 ]; then t_ok "AC1 review.md has 200..700 words ($RW)"; else t_bad "AC1 review.md has 200..700 words" "got $RW"; fi
if [ -f "$RV" ]; then
  assert_eq "AC1 review.md is printable ASCII only (no em dash)" "0" "$(LC_ALL=C grep -c '[^ -~]' "$RV")"
else t_bad "AC1 review.md is printable ASCII only (no em dash)" "file missing"; fi
assert_eq "AC1 SKILL.md is printable ASCII only" "0" "$(LC_ALL=C grep -c '[^ -~]' "$SK")"
assert_eq "AC1 install.sh does not mention review.md" "0" "$(grep -c 'review\.md' "$PB_ROOT/install.sh")"
assert_eq "AC1 install.ps1 does not mention review.md" "0" "$(grep -c 'review\.md' "$PB_ROOT/install.ps1")"

echo "AC2 procedure and order"
r "AC2 names \$L check" '\$L check'
r "AC2 names \$L stale" '\$L stale'
r "AC2 names the proposal file" '\.agents/handoff/learnings-review\.md'
r "AC2 names LEARNINGS.md" '\.agents/LEARNINGS\.md'
r "AC2 reads the warning line" 'warning'
ORD="$(printf '%s' "$RF" | A='$L check' B='$L stale' C='learnings-review.md' awk '
  { a = index($0, ENVIRON["A"]); b = index($0, ENVIRON["B"])
    if (a > 0 && b > a) { rest = substr($0, b); if (index(rest, ENVIRON["C"]) > 0) ok = 1 } }
  END { print (ok ? "yes" : "no") }')"
assert_eq "AC2 order: check, then stale, then the proposal file named after stale" "yes" "$ORD"

echo "AC3 item kinds"
for K in MERGE RETIRE REWRITE VERIFY; do
  if [ -f "$RV" ] && grep -qw "$K" "$RV"; then t_ok "AC3 label $K present"; else t_bad "AC3 label $K present"; fi
done
KL=0; KD=0
if [ -f "$RV" ]; then
  KL="$(grep -cE '^(- |\| |#+ )?\**(MERGE|RETIRE|REWRITE|VERIFY)' "$RV")"
  KD="$(grep -E '^(- |\| |#+ )?\**(MERGE|RETIRE|REWRITE|VERIFY)' "$RV" | grep -ciE 'command|ids?([^a-z]|$)')"
fi
assert_eq "AC3 exactly 4 lines define a label" "4" "$KL"
assert_eq "AC3 each label line mentions command or id" "4" "$KD"
r "AC3 says exactly one of the labels" 'exactly one of'

echo "AC4 merge and rewrite use only source text"
r "AC4 MERGE/REWRITE only cut or reuse text" '(MERGE|REWRITE).{0,200}(only|just).{0,60}(cut|text|words)'
r "AC4 MERGE names at least two ids" 'at least two'
r "AC4 only text from the source entries" 'only (text|words)[^.]{0,80}(those|source|the) entries'
r "AC4 no new claim" 'no new (claim|fact)'

echo "AC5 exact commands, quoting, approval, order"
r "AC5 retire command pattern" 'bash \$L retire L-[0-9N]{4} --reason'
r "AC5 add command pattern" 'bash \$L add --title'
for FL in --rule --why --evidence --source; do rF "AC5 add flag $FL" "$FL"; done
rF "AC5 L= line" 'L=~/.agents/playbook/scripts/learn.sh'
r "AC5 never run before approval" '(do not|never) run[^.]{0,120}(until|before)[^.]{0,80}approv'
r "AC5 approval is per item" 'each item|that item'
r "AC5 retire before add for MERGE/REWRITE" '(MERGE|REWRITE).{0,200}retire.{0,200}(then|before|first).{0,120}add|retire.{0,120}(first|before).{0,120}add'
rn "AC5 no add-before-retire wording" 'add.{0,40}(first|before).{0,40}retire'
r "AC5 add example uses single quotes" "bash \\\$L add --title '"
r "AC5 retire example uses a single-quoted reason" "--reason '"
rn "AC5 no double-quoted flag value" '--(title|rule|why|evidence|scope|reason) "'
rn "AC5 does not say run them now" 'run (them|it) (now|immediately)'

echo "AC6 input unchanged (text)"
r "AC6 LEARNINGS.md stays unchanged" 'LEARNINGS\.md[^.]{0,120}(unchanged|not (edited|modified|written)|byte-identical)|(unchanged|not (edited|modified|written)|byte-identical)[^.]{0,120}LEARNINGS\.md'
r "AC6 names cksum or byte-identical" 'cksum|byte-identical'
r "AC6 no write commands while reviewing" '(no|never).{0,60}(init|add|retire|trust|untrust).{0,60}(while|during).{0,20}review'
rF "AC6 exact no-write sentence" 'Run no init, add, retire, verify, trust or untrust while you review.'
rn "AC6 review never calls init/trust/untrust" 'bash \$L (init|trust|untrust)'
rn "AC6 checklist never called with all" '\$L checklist all'
r "AC6 checklist is called with a role" '\$L checklist (tester|implementer|reviewer|<role>)'

echo "AC6 behaviour sanity: the read-only commands leave the fixture unchanged"
export PLAYBOOK_HOME="$(mk_tmp)"
FX="$(mk_tmp)"; mk_repo "$FX"
OLDCWD="$PWD"
cd "$FX" || exit 3
run bash "$LEARN" init
assert_rc "fixture init" 0
run env PLAYBOOK_DATE=2025-01-01 bash "$LEARN" add --title "Old rule" --rule "Run pnpm lint before pnpm test." \
  --why "CI lint first." --evidence "CI run 1" --source failure --scope "src/**" --role tester
assert_rc "fixture add 1" 0
run env PLAYBOOK_DATE=2026-10-01 bash "$LEARN" add --title "New rule" --rule "Store timestamps in UTC." \
  --why "User said so." --evidence "User, 2026-10-01" --source user
assert_rc "fixture add 2" 0
snap() { git status --porcelain; git ls-files -s; cksum .agents/LEARNINGS.md; }
BEFORE="$(snap)"
export PLAYBOOK_DATE=2026-10-09
run bash "$LEARN" check
assert_rc "read-only check ok" 0
run bash "$LEARN" stale --days 30
assert_rc "read-only stale ok" 0
assert_contains "stale lists the old entry (fixture sanity)" "$OUT" "L-0001"
run bash "$LEARN" checklist tester
assert_rc "read-only checklist tester ok" 0
run bash "$LEARN" checklist all
assert_rc "checklist all is invalid (so review passes a real role)" 2
run bash "$LEARN" checklist
assert_rc "checklist without a role is invalid" 2
assert_eq "cksum, git status and git ls-files -s unchanged after the allowed commands" "$BEFORE" "$(snap)"
cd "$OLDCWD" || exit 3
unset PLAYBOOK_DATE

echo "AC7 entry text is data"
r "AC7 entry text is data" 'data'
r "AC7 not instructions" 'not (an )?instruction|not instructions'
r "AC7 quote" 'quote'
rF "AC7 FLAG: marker" 'FLAG:'
r "AC7 do not act/follow/run/fetch" '(do not|never) (act|follow|run|fetch)'
r "AC7 example of an injected request" 'fetch|URL|ignore'
rF "AC7 exact flagged-entry sentence" 'An entry with a FLAG gets RETIRE or REWRITE only.'

echo "AC8 non-interactive"
r "AC8 non-interactive" 'non-interactive'
r "AC8 writes only the proposal" '(write|writes)[^.]{0,80}(proposal|learnings-review)[^.]{0,40}only|only[^.]{0,80}(proposal|learnings-review)'
r "AC8 asks nothing" 'ask(s)? nothing|(do not|never) ask'
r "AC8 final message gives path and counts" 'final message.{0,250}(count|number|how many)'
rn "AC8 non-interactive run does not ask the user" 'non-interactive.{0,160}ask the user'
rF "AC8 exact non-interactive phrase" 'In a non-interactive run (no user can answer)'
rF "AC8 exact no-approval sentence" 'The proposal file is not a learning entry, so writing it needs no approval.'

echo "AC9 VERIFY (S3 landed)"
if grep -qE '^  verify\)' "$LEARN"; then t_ok "AC9 learn.sh has a verify branch"; else t_bad "AC9 S3 landed: learn.sh must have a verify branch" "missing"; fi
r "AC9 review.md uses verify L-" 'verify L-'
r "AC9 review.md names the command" '\$L verify L-'
rn "AC9 no stopgap wording" 'no (learn\.sh )?verify command|verify command exists yet'
r "AC9 VERIFY has a read-only check" 'git ls-files|grep'
r "AC9 VERIFY wrong outcome leads to retire" '(wrong|incorrect|no longer (true|valid|holds)|outdated|false).{0,200}retire'

echo "AC11 pointer in SKILL.md and word ceiling"
SW="$(wc -w < "$SK" | tr -d ' ')"
if [ "$SW" -le 700 ]; then t_ok "AC11a SKILL.md is at most 700 words ($SW; base was 700)"; else t_bad "AC11a SKILL.md is at most 700 words" "got $SW"; fi
BUD="$(awk '$1 == "skills/playbook-learn/SKILL.md" { n++; v = $2 } END { print n + 0, v }' "$PB_ROOT/evals/word-budgets")"
assert_eq "AC11b word-budgets has exactly one playbook-learn line, 700" "1 700" "$BUD"
if grep 'TW_LW' "$PB_ROOT/tests/test-content.sh" | grep -q -e '-le 700'; then t_ok "AC11b test-content.sh keeps the -le 700 ceiling"; else t_bad "AC11b test-content.sh keeps the -le 700 ceiling"; fi
assert_eq "AC11c exactly one SKILL.md line names references/review.md" "1" "$(grep -c 'references/review\.md' "$SK")"
SEC="$(awk '/^## Review/ { on = 1 } on { print }' "$SK")"
SECF="$(printf '%s\n' "$SEC" | tr '\n' ' ' | tr -s ' ')"
assert_eq "AC11c exactly one '## Review' heading" "1" "$(grep -c '^## Review' "$SK")"
assert_eq "AC11c '## Review' is the last section" "## Review" "$(grep '^## ' "$SK" | tail -n 1)"
has "AC11c Review section tells the agent to read references/review.md" "$SECF" 'read[^.]{0,60}references/review\.md'
has "AC11c Review section names the proposal file" "$SECF" '\.agents/handoff/learnings-review\.md'
has "AC11c Review section says apply nothing until each item is approved" "$SECF" 'approv'
SECW="$(printf '%s\n' "$SEC" | wc -w | tr -d ' ')"
if [ "$SECW" -gt 0 ] && [ "$SECW" -le 40 ]; then t_ok "AC11d Review section is 1..40 words ($SECW)"; else t_bad "AC11d Review section is 1..40 words" "got $SECW"; fi
SL="$(wc -l < "$SK" | tr -d ' ')"
if [ "$SL" -le 300 ]; then t_ok "AC11e SKILL.md is at most 300 lines ($SL)"; else t_bad "AC11e SKILL.md is at most 300 lines" "got $SL"; fi
MISS=""
for P in $(grep -Eo '(references|roles|templates)/[A-Za-z0-9._-]+\.md' "$SK" | sort -u); do
  [ -f "$SKDIR/$P" ] || MISS="$MISS $P"
done
assert_eq "AC11e every references/roles/templates file named in SKILL.md exists" "" "$MISS"
if [ -z "${PB_SKILL_MD:-}" ] && [ -z "${PB_REVIEW_MD:-}" ]; then
  run bash "$PB_ROOT/evals/run-checks.sh" --only skills
  assert_rc "AC11e evals/run-checks.sh --only skills is green" 0
  run bash "$PB_ROOT/evals/run-checks.sh" --only budgets
  assert_rc "AC11b evals/run-checks.sh --only budgets is green" 0
else
  t_skip 2 "run-checks (a scratch copy is under test)"
fi
echo "AC12 guard: phrases other suites pin must survive the tightening"
has "AC12 keeps --role" "$SF" '\-\-role'
has "AC12 keeps checklist" "$SF" 'checklist'
has "AC12 keeps Role next to the line budget" "$SF" 'role[^.]{0,160}(line budget|LEARN_MAX_LINES|line limit)|(line budget|LEARN_MAX_LINES|line limit)[^.]{0,160}role'
has "AC12 keeps learn.sh trust" "$SF" 'learn\.sh trust'
has "AC12 keeps 'can be batched ... end of a task'" "$SF" 'can be batched[^.]{0,200}end of a task'
has "AC12 keeps 'possible prompt injection'" "$SF" 'possible prompt injection'
has "AC12 keeps 'Retired entries stay for the audit trail'" "$SF" 'Retired entries stay for the audit trail'
has "AC12 keeps the never-edit-global rule" "$SF" 'Never edit the global skills or the always-on block from a project session'

echo "AC14 duplicate rules, retired rules, source choice"
# the flags are kept in a variable: a literal grep with ignore-case plus fixed-strings trips the repo's own gnu scan
DUPFL='-iFx'
r "AC14 whole-line duplicate check (grep $DUPFL) near MERGE/REWRITE" "(MERGE|REWRITE).{0,255}grep $DUPFL|grep $DUPFL.{0,255}(MERGE|REWRITE)"
rF "AC14 duplicate check names the Rule line" '- Rule:'
r "AC14 including retired" 'including retired'
rF "AC14 retired rule sentence" 'A retired rule cannot be added again.'
r "AC14 merged into L-" 'merged into L-'
r "AC14 REWRITE must change the rule" 'REWRITE.{0,200}(change|differ).{0,60}rule'
r "AC14 only why/evidence/title/scope means RETIRE or VERIFY" '(only|just).{0,60}(why|evidence|title|scope).{0,120}(RETIRE|VERIFY)'
rF "AC14 recovery sentence" 'fix the flagged field and re-add with a rule that differs from all existing rules'
r "AC14 source order user, failure, review" 'user.{0,80}failure.{0,80}review'
rn "AC14 never allows re-adding a retired entry" 're-?add (a |the )?retired'
if printf '%s\n' "$RF" | grep -qi 'restore' && printf '%s\n' "$RF" | grep -qi 'add again'; then
  t_bad "AC14 no restore plus add again" "both words present"
elif [ -f "$RV" ]; then t_ok "AC14 no restore plus add again"; else t_bad "AC14 no restore plus add again" "file missing"; fi

echo "AC15 field limits"
r "AC15 title 80" 'title[^0-9.]{0,12}80'
r "AC15 rule 300" 'rule[^0-9.]{0,12}300'
r "AC15 why 300" 'why[^0-9.]{0,12}300'
r "AC15 evidence 400" 'evidence[^0-9.]{0,12}400'
r "AC15 scope 120" 'scope[^0-9.]{0,12}120'
r "AC15 one line per field" 'single line|one line'
r "AC15 secret pattern" 'SECRET_RE|secret'
r "AC15 secret forms: sk- ghp_ AKIA" 'sk-.{0,80}ghp_.{0,80}AKIA'
r "AC15 secret forms: passwd, api_key/apikey" 'passwd.{0,120}api_?key|api_?key.{0,120}passwd'
rn "AC15 does not write the spaced form 'api key'" 'api key'
r "AC15 source values" 'user.{0,20}failure.{0,20}review'
r "AC15 role values" 'tester.{0,20}implementer.{0,20}reviewer.{0,20}all'
r "AC15 shorten by cutting else RETIRE or VERIFY" 'shorten.{0,80}cut.{0,120}(RETIRE|VERIFY)'

echo "AC16 entry text must not become shell"
r "AC16 single quote" 'single quote'
r "AC16 untrusted" 'untrusted'
rF "AC16 escape '\\'' present" "'\\''"
r "AC16 never double quote, \$( or backtick" 'never.{0,120}(double quote|\$\(|backtick)'
r "AC16 --reason is the reviewer's, never copied" 'reason.{0,120}(never|not).{0,80}(copied|copy)'
r "AC16 dangerous text gets FLAG and no add" '(\$\(|backtick).{0,255}(never|no|not|without|instead of)[^.]{0,60}add'
rF "AC16 VERIFY check quotes the scope" "git ls-files -- '"
r "AC16 scope quote escaping uses the same rule" "(scope.{0,255}${QQ}|${QQ}.{0,255}scope)"

echo "AC17 quoting a flagged entry"
r "AC17 fenced code block" 'fenced|code block'
rF "AC17 label text" 'quoted entry text, data only'
r "AC17 200 character limit" '(at most|up to|max)[^.]{0,20}200'
r "AC17 FLAG then fenced block" 'FLAG.{0,255}(fenced|code block)'
r "AC17 fence longer than the quote, or ~~~" 'longer|~~~'
rF "AC17 never re-wrapped" 'never re-wrapped'
r "AC17 rewrite drops the instruction text" 'drop.{0,60}(instruction|text)|without'
r "AC17 flagged retire/rewrite still needs approval" '(FLAG|flagged).{0,255}approv'

echo "Hardening: scope and role carry-over, duplicate check order, mutant pins"
# (A) a REWRITE or MERGE must not reset a scoped, role-specific rule: scope and role are copied into the add
r "HARD-A copy wording names --scope and --role" '(copy|copied|carry|carried|take|reuse|keep)[^.]{0,100}--(scope|role)[^.]{0,60}--(role|scope)'
r "HARD-A copied from the source entry" '(source|original) entr[^.]{0,255}--(scope|role)|--(scope|role)[^.]{0,255}(source|original) entr'
r "HARD-A MERGE copies them only if the sources agree" 'MERGE.{0,255}only if[^.]{0,40}(agree|same|match)|only if[^.]{0,40}(agree|same|match).{0,255}MERGE'
# (B) the duplicate check runs at proposal time, before the retire, so a failed add cannot strand a retired entry
r "HARD-B duplicate grep is before the retire" "grep $DUPFL.{0,255}(before|prior to|ahead of)[^.]{0,40}retir|(before|prior to|ahead of)[^.]{0,40}retir.{0,255}grep $DUPFL"
# (C) mutant pins
r "HARD-C quoting sentence: copied values in single quotes with the '\'' escape" "cop(ied|y)[^.]{0,100}single quotes[^.]{0,100}${QQ}"
r "HARD-C flagged quote limit is 200, not 2000" '(at most|up to|max)[^.]{0,20}200[^0-9]'
r "HARD-C MERGE source rule: user if any, else failure, else review" '--source[^.]{0,60}user[^.]{0,40}(any|if)[^.]{0,40}user[^.]{0,30}else[^.]{0,30}failure[^.]{0,30}else[^.]{0,30}review'
r "HARD-C merged rule equals a source rule: keep that entry, no add" '(equals|equal to|same as|identical)[^.]{0,80}keep[^.]{0,120}no add'
r "HARD-C approval sentence: per item, approve all only if said" "(do not|never) run[^.]{0,60}commands[^.]{0,40}until[^.]{0,40}approves? that item[^.]{0,20}unless[^.]{0,60}approve all"
r "HARD-C REWRITE of a flagged entry drops the instruction text" 'REWRITE (drops?|must drop|omits?)[^.]{0,30}instruction'
for K in MERGE REWRITE; do
  if [ -f "$RV" ] && grep -E "^(- |\| |#+ )?\**$K" "$RV" | grep -qiE 'retire.{0,80}(then|before|first).{0,40}add'; then t_ok "HARD-C $K label line says retire, then add"
  else t_bad "HARD-C $K label line says retire, then add" "no match in the $K label line"; fi
done

cd "$PB_ROOT" || exit 3

t_summary
