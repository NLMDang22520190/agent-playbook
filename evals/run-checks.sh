#!/usr/bin/env bash
# Static checks for the playbook itself (no model needed). Exit 1 on any problem.
set -u
cd "$(dirname "$0")/.." || exit 3
P=0
ok()  { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; P=$((P + 1)); }

SENTENCE='Before making any changes, inspect the relevant context and identify any ambiguities or assumptions that could materially affect the implementation. Ask only the necessary clarification questions. If the requirements are already sufficiently clear, proceed without asking unnecessary questions.'

echo "skills"
desc_total=0
for d in skills/*/; do
  s="${d%/}"; n="$(basename "$s")"; f="$s/SKILL.md"
  [ -f "$f" ] || { bad "$s has no SKILL.md"; continue; }
  [ "$(head -n 1 "$f")" = "---" ] || bad "$f: frontmatter must start on line 1"
  name="$(sed -n '2,10{s/^name: *//p;}' "$f" | head -n 1)"
  desc="$(sed -n '2,10{s/^description: *//p;}' "$f" | head -n 1)"
  [ "$name" = "$n" ] && ok "$n: name matches directory" || bad "$f: name '$name' != dir '$n'"
  printf '%s' "$name" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$' || bad "$f: name violates ^[a-z0-9]+(-[a-z0-9]+)*$"
  len=${#desc}
  if [ "$len" -ge 1 ] && [ "$len" -le 450 ]; then ok "$n: description $len chars (<=450)"; else bad "$f: description length $len (want 1..450, spec max 1024)"; fi
  desc_total=$((desc_total + len))
  lines="$(wc -l < "$f" | tr -d ' ')"
  [ "$lines" -le 300 ] && ok "$n: SKILL.md $lines lines (<=300)" || bad "$f: $lines lines (>300, move detail to references/)"
  for ref in $(cat "$s"/SKILL.md "$s"/roles/*.md 2>/dev/null | grep -Eo '(references|roles|templates)/[A-Za-z0-9._-]+\.md' | sort -u); do
    [ -f "$s/$ref" ] || bad "$n: referenced file missing: $ref"
  done
done
[ "$desc_total" -le 2000 ] && ok "all descriptions together: $desc_total chars (<=2000, keeps the skill list cheap)" || bad "descriptions total $desc_total chars (>2000)"

echo "always-on block"
g=AGENTS.global.md
grep -qF "$SENTENCE" "$g" && ok "contains the verbatim clarify sentence" || bad "$g lost the verbatim clarify sentence"
l="$(wc -l < "$g" | tr -d ' ')"; b="$(wc -c < "$g" | tr -d ' ')"
[ "$l" -le 60 ] && [ "$b" -le 5000 ] && ok "$g size ok ($l lines, $b bytes)" || bad "$g too big ($l lines, $b bytes; want <=60 / <=5000)"
grep -Eq '^<!-- (BEGIN|END) agent-playbook' "$g" && bad "$g must not contain the managed markers" || ok "no managed markers inside the block source"
for skill in playbook-tdd playbook-proof playbook-learn playbook-setup playbook-feedback; do
  grep -q "$skill" "$g" && ok "block mentions $skill" || bad "$g does not mention $skill"
done
grep -q '^### When other skills overlap' "$g" && ok "block has the precedence section" || bad "$g lacks '### When other skills overlap'"
for s in subagent-driven-development test-driven-development brainstorming; do
  grep -q "$s" "$g" && ok "precedence names $s" || bad "precedence section does not name $s"
done
grep -q '^## E11 ' evals/scenarios.md && ok "eval E11 (overlapping skills) exists" || bad "evals/scenarios.md lacks E11"
[ -f .github/workflows/test.yml ] && ok "CI workflow present" || bad "missing .github/workflows/test.yml"
[ -f .github/ISSUE_TEMPLATE/playbook-feedback.md ] && ok "feedback issue template present" || bad "missing .github/ISSUE_TEMPLATE/playbook-feedback.md"

echo "v0.3 rules"
# 1. reversibility-based clarify rule + decision ledger
grep -qi 'reversib' "$g" && ok "block has the reversibility rule" || bad "$g lacks the reversibility rule"
grep -q 'decisions.md' "$g" && ok "block names the decision ledger" || bad "$g does not name .agents/handoff/decisions.md"
[ -f skills/playbook-tdd/templates/decisions.md ] && ok "decision ledger template exists" || bad "missing skills/playbook-tdd/templates/decisions.md"
grep -q 'templates/decisions.md' skills/playbook-tdd/SKILL.md && ok "playbook-tdd uses the ledger" || bad "playbook-tdd does not reference templates/decisions.md"
# 2. every always-on section and every skill carries its why
secs="$(grep -c '^### ' "$g")"; whys="$(grep -c '^Why: ' "$g")"
[ "$secs" -eq "$whys" ] && ok "each of $secs always-on sections has a Why: line" || bad "$g: $secs sections but $whys 'Why: ' lines"
for f in skills/*/SKILL.md; do
  grep -q '\*\*Why:\*\*' "$f" && ok "$(basename "$(dirname "$f")"): states its why" || bad "$f has no **Why:** line"
done
# 3. AC verbatim with source anchors
grep -q 'Source anchor' skills/playbook-tdd/templates/spec.md && ok "spec template has source anchors" || bad "spec.md lacks a 'Source anchor' column"
grep -qi 'verbatim' skills/playbook-tdd/templates/spec.md && ok "spec template asks for verbatim AC" || bad "spec.md does not ask for verbatim wording"
# 4. behavioural check for UI changes
grep -q '^## If the change touches UI' skills/playbook-tdd/roles/reviewer.md && ok "reviewer has the UI section" || bad "reviewer.md lacks '## If the change touches UI'"
grep -qi 'mobile' skills/playbook-tdd/roles/reviewer.md && ok "UI check starts at mobile width" || bad "reviewer.md does not mention mobile width"
for e in E13 E14; do grep -q "^## $e " evals/scenarios.md && ok "eval $e exists" || bad "evals/scenarios.md lacks $e"; done

echo "files"
crlf="$(grep -rIl $'\r' --exclude-dir=.git . 2>/dev/null || true)"
[ -z "$crlf" ] && ok "no CRLF line endings" || bad "CRLF found in: $crlf"
for f in install.sh scripts/*.sh tests/*.sh evals/*.sh tools/*.sh; do
  bash -n "$f" 2>/dev/null && ok "syntax: $f" || bad "bash -n failed: $f"
  [ "$(head -c 2 "$f")" = "#!" ] || bad "$f: missing shebang"
done
for f in install.sh scripts/conf.sh scripts/role-gate.sh scripts/proof-run.sh scripts/learn.sh scripts/feedback.sh; do
  [ -x "$f" ] && ok "executable: $f" || bad "not executable: $f (chmod +x)"
done
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning install.sh scripts/*.sh && ok "shellcheck (warning level)" || bad "shellcheck reported warnings"
else
  echo "  skip shellcheck not installed"
fi

echo "eval scenarios"
n=0
while IFS= read -r h; do
  n=$((n + 1))
done < <(grep -E '^## E[0-9]+' evals/scenarios.md)
for k in 'Prompt:' 'Pass if:' 'Fail if:'; do
  c="$(grep -c "^\*\*$k\*\*" evals/scenarios.md || true)"
  [ "$c" -eq "$n" ] && ok "$n scenarios each have $k" || bad "scenarios: $n headings but $c '$k' lines"
done

[ "$P" -eq 0 ] && echo "run-checks: all ok" || { echo "run-checks: $P problem(s)"; exit 1; }
