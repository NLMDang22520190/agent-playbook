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
have_yaml=0
if python3 -c 'import yaml' >/dev/null 2>&1; then have_yaml=1; else echo "  skip yaml frontmatter parse: python3 with PyYAML not available"; fi
for d in skills/*/; do
  s="${d%/}"; n="$(basename "$s")"; f="$s/SKILL.md"
  [ -f "$f" ] || { bad "$s has no SKILL.md"; continue; }
  [ "$(head -n 1 "$f")" = "---" ] || bad "$f: frontmatter must start on line 1"
  unquote() { sed -E "s/^\"(.*)\"[[:space:]]*$/\\1/; s/^'(.*)'[[:space:]]*$/\\1/"; }
  name_raw="$(sed -n '2,10{s/^name: *//p;}' "$f" | head -n 1)"
  desc_raw="$(sed -n '2,10{s/^description: *//p;}' "$f" | head -n 1)"
  name="$(printf '%s\n' "$name_raw" | unquote)"; desc="$(printf '%s\n' "$desc_raw" | unquote)"   # quotes are YAML syntax, not content
  [ "$name" = "$n" ] && ok "$n: name matches directory" || bad "$f: name '$name' != dir '$n'"
  printf '%s' "$name" | grep -Eq '^[[:lower:][:digit:]]+(-[[:lower:][:digit:]]+)*$' || bad "$f: name violates ^[a-z0-9]+(-[a-z0-9]+)*$"
  # An unquoted value containing ': ' is not valid YAML (some harnesses then drop the skill).
  for kv in "name:$name_raw" "description:$desc_raw"; do   # the quoting check needs the raw value
    k="${kv%%:*}"; v="${kv#*:}"
    case "$v" in \"*|\'*) ;; *': '*) bad "$f: unquoted $k contains ': ' (quote the value)" ;; esac
  done
  if [ "$have_yaml" -eq 1 ]; then
    if awk 'NR == 1 { next } /^---$/ { exit } { print }' "$f" |
      python3 -c 'import sys, yaml; yaml.safe_load(sys.stdin)' >/dev/null 2>&1; then
      ok "$n: frontmatter parses as YAML"
    else
      bad "$f: frontmatter does not parse as YAML (PyYAML)"
    fi
  fi
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

echo "v0.4 weights"
T=skills/playbook-tdd/SKILL.md
# 1. Full / Lite chosen by risk, with escalation
grep -q '\*\*Full\*\*' "$g" && grep -q '\*\*Lite\*\*' "$g" && ok "block names the Full and Lite weights" || bad "$g lacks **Full** / **Lite**"
grep -q '^## Pick the weight' "$T" && ok "playbook-tdd has 'Pick the weight'" || bad "$T lacks '## Pick the weight'"
grep -qi 'escalate to Full' "$T" && ok "Lite escalates to Full" || bad "$T does not say when to escalate to Full"
grep -q '^### Lite workflow' "$T" && ok "playbook-tdd describes the Lite workflow" || bad "$T lacks '### Lite workflow'"
grep -q 'Weight:' skills/playbook-tdd/templates/final-report.md && ok "final report records the weight" || bad "final-report.md lacks 'Weight:'"
grep -q 'Weight:' skills/playbook-tdd/templates/spec.md && ok "spec records the weight" || bad "spec.md lacks 'Weight:'"
# 2. one review per feature
grep -q 'One reviewer per feature' "$T" && ok "review is batched per feature" || bad "$T lacks 'One reviewer per feature'"
# 5. exemptions spelled out
grep -q '^### Exempt' "$T" && ok "playbook-tdd spells out the exemptions" || bad "$T lacks '### Exempt'"
for w in docs-only config-only spike; do grep -qi "$w" "$T" && ok "exemption covers $w" || bad "$T exemptions do not cover $w"; done
grep -qi 'not exempt' "$T" && ok "exemptions say what is NOT exempt" || bad "$T does not say what is not exempt"
for e in E15 E16 E17; do grep -q "^## $e " evals/scenarios.md && ok "eval $e exists" || bad "evals/scenarios.md lacks $e"; done

echo "files"
# CRLF: judge what git stores. On Windows, core.autocrlf converts tracked LF files to CRLF in the
# working tree; that is not a repo problem. Untracked files, and copies outside git, are read as they are.
# CR is detected with tr, not grep: MSYS grep (Git Bash) handles a CR pattern in text mode and either
# matches nothing or everything. Binary files are skipped (grep -I with an empty pattern is reliable).
has_cr() { [ -n "$(tr -cd '\r' < "$1" | head -c 1)" ]; }
# cr_files: one pass over all files first (the usual case has no CR at all); only then per file,
# which costs three processes each and is slow on Git Bash.
cr_files() {
  local f list=()
  while IFS= read -r f; do [ -f "$f" ] && list+=("$f"); done
  [ "${#list[@]}" -gt 0 ] || return 0
  # if cat fails (e.g. argument list too long), emit a CR so the per-file check below runs
  [ -n "$( { cat -- "${list[@]}" || printf '\r'; } 2>/dev/null | tr -cd '\r' | head -c 1)" ] || return 0
  for f in "${list[@]}"; do grep -Iq '' "$f" && has_cr "$f" && printf '%s\n' "$f"; done
}
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  crlf="$( { git ls-files --eol | awk '$1 ~ /^i\/(crlf|mixed)$/ { print $NF }'
            git ls-files -o --exclude-standard | cr_files; } | sort -u | tr '\n' ' ')"
else
  crlf="$(find . -path ./.git -prune -o -type f -print | sed 's#^\./##' | cr_files | tr '\n' ' ')"
fi
[ -z "${crlf// /}" ] && ok "no CRLF line endings" || bad "CRLF found in: $crlf"
for f in install.sh scripts/*.sh tests/*.sh evals/*.sh tools/*.sh; do
  bash -n "$f" 2>/dev/null && ok "syntax: $f" || bad "bash -n failed: $f"
  sb=""; IFS= read -r -n 2 sb < "$f"   # builtin read: no head process per file
  [ "$sb" = "#!" ] || bad "$f: missing shebang"
done
for f in install.sh scripts/conf.sh scripts/role-gate.sh scripts/proof-run.sh scripts/learn.sh scripts/feedback.sh; do
  [ -x "$f" ] && ok "executable: $f" || bad "not executable: $f (chmod +x)"
done
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning install.sh scripts/*.sh tools/*.sh evals/*.sh && ok "shellcheck (warning level)" || bad "shellcheck reported warnings"
else
  echo "  skip shellcheck not installed"
fi

# BSD regex (macOS) rejects repeat bounds above RE_DUP_MAX (255): such a pattern never matches there
big="$(grep -nE '\{[0-9]+(,[0-9]*)?\}' tests/*.sh evals/*.sh 2>/dev/null |
  awk -F: '{ line = $0; sub(/^[^:]*:[^:]*:/, "", line)
             while (match(line, /\{[0-9]+(,[0-9]*)?\}/)) { b = substr(line, RSTART + 1, RLENGTH - 2); line = substr(line, RSTART + RLENGTH)
               n = split(b, a, ","); for (i = 1; i <= n; i++) if (a[i] + 0 > 255) { print $1 ":" $2; break } } }' | sort -u | tr '\n' ' ')"
[ -z "$big" ] && ok "regex repeat bounds <= 255 (BSD RE_DUP_MAX)" || bad "regex repeat bound above 255 (BSD/macOS never matches) at: $big"

echo "eval scenarios"
n=0
while IFS= read -r _; do
  n=$((n + 1))
done < <(grep -E '^## E[0-9]+' evals/scenarios.md)
for k in 'Prompt:' 'Pass if:' 'Fail if:'; do
  c="$(grep -c "^\*\*$k\*\*" evals/scenarios.md || true)"
  [ "$c" -eq "$n" ] && ok "$n scenarios each have $k" || bad "scenarios: $n headings but $c '$k' lines"
done

[ "$P" -eq 0 ] && echo "run-checks: all ok" || { echo "run-checks: $P problem(s)"; exit 1; }
