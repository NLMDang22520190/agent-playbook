#!/usr/bin/env bash
# Static checks for the playbook itself (no model needed). Exit 1 on any problem.
#   evals/run-checks.sh [--only SECTION]
# --only runs one check group (dupmax|sed|gnu|soh|shellcheck|skills|scenarios) and prints only its lines plus the summary;
# a missing or unknown SECTION exits 2. Without --only everything runs; the always-on and files checks only then.
set -u
cd "$(dirname "$0")/.." || exit 3
P=0
ok()  { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; P=$((P + 1)); }
ONLY=""
if [ "$#" -gt 0 ]; then
  [ "$#" -eq 2 ] && [ "$1" = "--only" ] || { echo "usage: evals/run-checks.sh [--only dupmax|sed|gnu|soh|shellcheck|skills|scenarios]" >&2; exit 2; }
  case "$2" in
    dupmax | sed | gnu | soh | shellcheck | skills | scenarios) ONLY="$2" ;;
    *) echo "run-checks: unknown section '$2' (want dupmax|sed|gnu|soh|shellcheck|skills|scenarios)" >&2; exit 2 ;;
  esac
fi
# want NAME: this group runs (always without --only)
want() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }

# AWKSTRIP: awk code shared by the gnu and soh checks. strip(s) returns the code part of a line and leaves the comment text
# (from its #) in CMT. A # starts a comment only at the start of a line or after a blank, and only outside single and double
# quotes (a backslash escapes the next character outside single quotes). Quote state is per line.
AWKSTRIP='
function strip(s,   i, n, c, q, bs, pc) {
  CMT = ""
  if (index(s, "#") == 0) return s
  n = length(s); q = ""; bs = 0
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1)
    if (bs) { bs = 0; continue }
    if (q == "") {
      if (c == "\\") bs = 1
      else if (c == "\"" || c == "\047") q = c
      else if (c == "#") {
        pc = (i > 1) ? substr(s, i - 1, 1) : " "
        if (pc == " " || pc == "\t") { CMT = substr(s, i); return substr(s, 1, i - 1) }
      }
    } else if (q == "\"") {
      if (c == "\\") bs = 1
      else if (c == q) q = ""
    } else if (c == q) q = ""
  }
  return s
}
'

SENTENCE='Before making any changes, inspect the relevant context and identify any ambiguities or assumptions that could materially affect the implementation. Ask only the necessary clarification questions. If the requirements are already sufficiently clear, proceed without asking unnecessary questions.'

if want skills; then
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
fi

if [ -z "$ONLY" ]; then
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
fi   # full-run-only groups end here

if want shellcheck; then
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning install.sh scripts/*.sh tools/*.sh evals/*.sh && ok "shellcheck (warning level)" || bad "shellcheck reported warnings"
else
  echo "  skip shellcheck not installed"
fi
fi

if want dupmax; then
# BSD regex (macOS) rejects repeat bounds above RE_DUP_MAX (255): such a pattern never matches there
big="$(grep -nE '\{([0-9]+(,[0-9]*)?|,[0-9]+)\}' tests/*.sh evals/*.sh scripts/*.sh tools/*.sh install.sh 2>/dev/null |
  awk -F: '{ line = $0; sub(/^[^:]*:[^:]*:/, "", line)
             while (match(line, /\{([0-9]+(,[0-9]*)?|,[0-9]+)\}/)) { b = substr(line, RSTART + 1, RLENGTH - 2); line = substr(line, RSTART + RLENGTH)
               n = split(b, a, ","); for (i = 1; i <= n; i++) if (a[i] + 0 > 255) { print $1 ":" $2; break } } }' | sort -u | tr '\n' ' ')"
[ -z "$big" ] && ok "regex repeat bounds <= 255 (BSD RE_DUP_MAX)" || bad "regex repeat bound above 255 (BSD/macOS never matches) at: $big"
fi

if want sed; then
# BSD sed (macOS) reads the word after -i as the backup suffix, so `sed -i 's/a/b/' f` edits nothing there;
# an attached suffix (sed -i.bak) works on both. Comments (from a # at the start or after a blank) are ignored.
gsed="$(awk '{ line = $0; sub(/(^|[[:space:]])#.*$/, "", line)
             if (line ~ /(^|[^[:alnum:]_])sed([[:space:]]+-[[:alnum:]]+)*[[:space:]]+(-[[:alpha:]]*i([[:space:]"'"'"']|$)|--in-place([[:space:]=]|$))/) print FILENAME ":" FNR }' \
  tests/*.sh evals/*.sh scripts/*.sh tools/*.sh install.sh 2>/dev/null | sort -u | tr '\n' ' ')"
si=-i   # spelled through a variable so this file does not trip its own check
[ -z "$gsed" ] && ok "sed $si has a suffix (BSD sed)" || bad "sed $si without an attached suffix (BSD/macOS sed edits nothing; use sed -i.bak or node) at: $gsed"
fi

if want gnu; then
# GNU-only options: macOS (BSD tools) lacks them, so a script using them fails there and passes on Ubuntu.
# The line is cut into words (single-quoted text and double-quoted text are skipped, except a $( ) inside double quotes;
# ( ) ; | & ` { } end a command), and for each
# of grep, readlink, date, stat, xargs, sed and find the rest of that command is looked at: the GNU-only short flags
# (also inside a cluster with digits, after an option argument, or as a trailing flag), the GNU-only long options and their
# prefixes of at least 4 letters (with or without =value), and the find actions -printf / -fprintf.
# Comments are ignored: a # starts one at the start of a line or after a blank when it is not inside single or double quotes.
# A line may opt out with "# gnu-ok: <reason>" (a non-blank reason) in its real trailing comment, that line only.
# The names are spelled in pieces so this file does not trip its own check.
ggnu="$(awk "$AWKSTRIP"'
  function flush() { if (t != "") { TK[++nk] = t; t = "" } }
  function tokenize(s,   i, n, c, sp, m) {
    nk = 0; t = ""; n = length(s); sp = 1; MS[1] = "c"; PD[1] = 0
    for (i = 1; i <= n; i++) {
      c = substr(s, i, 1); m = MS[sp]
      if (m == "d") {   # inside double quotes: hidden, except a command substitution
        if (c == "\\") i++
        else if (c == "\"") { sp--; flush() }
        else if (c == "$" && substr(s, i + 1, 1) == "(") { sp++; MS[sp] = "c"; PD[sp] = 0; i++; flush(); TK[++nk] = ";" }
        continue
      }
      if (c == "\\") { i++; flush() }
      else if (c == "\047") { flush(); i++; while (i <= n && substr(s, i, 1) != "\047") i++ }   # single quotes: hidden
      else if (c == "\"") { flush(); sp++; MS[sp] = "d" }
      else if (c == " " || c == "\t" || c == "<" || c == ">") flush()
      else if (c == ")" && sp > 1 && PD[sp] == 0) { flush(); TK[++nk] = ";"; sp-- }
      else if (index(";|&(){}`", c) > 0) {
        if (c == "(" && sp > 1) PD[sp]++
        if (c == ")" && sp > 1) PD[sp]--
        flush(); TK[++nk] = ";"
      }
      else t = t c
    }
    flush()
  }
  function hit(n) { if (!ex) out = out FILENAME ":" FNR " (" n ") " }
  BEGIN {
    nt = split("grep readlink date stat find xargs sed", tl, " ")
    for (k = 1; k <= nt; k++) isT[tl[k]] = 1
    SL["grep"] = "P"; SL["readlink"] = "f"; SL["date"] = "d"; SL["stat"] = "c"; SL["xargs"] = "r"; SL["sed"] = "r"
    LN["grep"] = "perl-regexp"
    LN["stat"] = "format printf"
    LN["readlink"] = "canonicalize canonicalize-existing canonicalize-missing"
    LN["date"] = "date"
    LN["xargs"] = "no-run-if-empty"
    LN["sed"] = "regexp-extended"
  }
  {
    code = strip($0)
    ex = (CMT ~ /(^|[[:space:]])#[[:space:]]*gnu-ok:[[:space:]]*[^[:space:]]/)
    if (code !~ /grep|readlink|date|stat|find|xargs|sed/) next
    tokenize(code)
    for (i = 1; i <= nk; i++) {
      w = TK[i]; sub(/^.*\//, "", w)
      if (!(w in isT)) continue
      skip = 0
      for (j = i + 1; j <= nk && TK[j] != ";"; j++) {
        t = TK[j]
        if (w == "find") { if (t == "-printf" || t == "-fprintf") hit("find " t); continue }
        if (skip) { skip = 0; continue }
        if (t ~ /^--[[:alnum:]]/) {
          nm = substr(t, 3); e = index(nm, "="); if (e > 0) nm = substr(nm, 1, e - 1)
          if (length(nm) >= 4 && (w in LN)) {
            m = split(LN[w], fulls, " ")
            for (q = 1; q <= m; q++) if (substr(fulls[q], 1, length(nm)) == nm) { hit(w " --" fulls[q]); break }
          }
        } else if (t ~ /^-[[:alnum:]]/) {
          pre = t; sub(/^-/, "", pre); match(pre, /^[[:alnum:]]+/); pre = substr(pre, 1, RLENGTH)
          if (index(pre, SL[w]) > 0) hit(w " -" SL[w])
          if (w == "xargs" && length(pre) + 1 == length(t) && pre ~ /[nILsPdEa]$/) skip = 1
        } else if (w == "xargs") break
      }
    }
  }
  END { print out }' tests/*.sh evals/*.sh scripts/*.sh tools/*.sh install.sh 2>/dev/null | tr -s ' ')"
[ -z "${ggnu// /}" ] && ok "GNU-only options absent (BSD/macOS)" || bad "GNU-only options (BSD/macOS lacks them; use a portable form or node) at: $ggnu"
fi

if want soh; then
# The control byte SOH (octal 1) is bash 3.2's internal CTLESC (macOS ships 3.2): a script that builds it with printf, tr, awk
# or an ANSI-C quote misbehaves there while Ubuntu is fine. Refused in every spelling outside comments (a backslash run of odd
# length ends in a live escape): the octal forms with 3 or 2 digits and the hex form. No gnu-ok exemption; build fixtures from pieces.
gsoh="$(awk "$AWKSTRIP"'
  {
    line = strip($0)
    if (index(line, "\\") == 0) next
    n = length(line)
    for (i = 1; i <= n; i++) {
      if (substr(line, i, 1) != "\\") continue
      j = i; while (substr(line, j + 1, 1) == "\\") j++
      rest = substr(line, j + 1, 4)
      if ((j - i + 1) % 2 == 1 && (rest ~ /^001/ || rest ~ /^x01/ || rest ~ /^01([^0-7]|$)/)) { out = out FILENAME ":" FNR " "; break }
      i = j
    }
  }
  END { print out }' tests/*.sh evals/*.sh scripts/*.sh tools/*.sh install.sh 2>/dev/null | tr -s ' ')"
[ -z "${gsoh// /}" ] && ok "no SOH byte (octal 001) spelled in scripts (bash 3.2)" || bad "SOH byte (octal 001) spelled in a script (bash 3.2 on macOS treats it as CTLESC; use the 034 field separator or build the fixture from pieces) at: $gsoh"
fi

if want scenarios; then
echo "eval scenarios"
n=0
while IFS= read -r _; do
  n=$((n + 1))
done < <(grep -E '^## E[0-9]+' evals/scenarios.md)
for k in 'Prompt:' 'Pass if:' 'Fail if:'; do
  c="$(grep -c "^\*\*$k\*\*" evals/scenarios.md || true)"
  [ "$c" -eq "$n" ] && ok "$n scenarios each have $k" || bad "scenarios: $n headings but $c '$k' lines"
done
fi

[ "$P" -eq 0 ] && echo "run-checks: all ok" || { echo "run-checks: $P problem(s)"; exit 1; }
