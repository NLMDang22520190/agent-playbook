#!/usr/bin/env bash
# Lane C (v0.26.3) S1, spec A2-A2d: nothing is lost when playbook-tdd SKILL.md is split into a core plus references/.
#   tests/skill-keep.tsv        the sentence list, generated once from the lane base (header names the sha) with
#                               tests/skill-keep-rows.sh gen; KEEP/DOCS/EDIT/RETIRE rows (format in skill-keep-rows.sh)
#   tests/skill-keep-rules.txt  the curated key rules (ERE, one per line), found in skills/playbook-tdd/**
# CHARACTERIZATION at the base: the keep list and the key rules pass on the unsplit tree by design and must pass after every
# slice. The checker's own cases (A2b self-test, A2d extraction) run on throwaway trees made with mk_tmp.
. "$(dirname "$0")/lib.sh"
ROWS="$PB_ROOT/tests/skill-keep-rows.sh"
TSV="$PB_ROOT/tests/skill-keep.tsv"
RULES="$PB_ROOT/tests/skill-keep-rules.txt"
BASE_SHA=4694b1c

echo "A2 the keep list holds on this tree"
assert_file "A2 tests/skill-keep.tsv exists" "$TSV"
assert_eq "A2 the keep list header names the base it was generated from" "1" "$(grep -c "^# base $BASE_SHA" "$TSV" 2>/dev/null)"
run bash "$ROWS" check "$PB_ROOT" "$TSV"
assert_rc "A2 every KEEP row is found at least its base count, every DOCS row in docs/release-speed.md, every EDIT/RETIRE row has its reason" 0
assert_contains "A2 the check reports its row counts" "$OUT" "rows: KEEP "

echo "A2b the keep list is not vacuous"
nsrc() { awk -F'\t' -v s="$1" '$1 !~ /^#/ && $2 == s { n++ } END { print n + 0 }' "$TSV" 2>/dev/null; }
N_SK="$(nsrc skills/playbook-tdd/SKILL.md)"
N_REL="$(nsrc skills/playbook-tdd/references/release.md)"
if [ "$N_SK" -ge 150 ]; then t_ok "A2b at least 150 rows come from playbook-tdd SKILL.md ($N_SK)"; else t_bad "A2b at least 150 rows come from playbook-tdd SKILL.md" "$N_SK rows"; fi
if [ "$N_REL" -ge 10 ]; then t_ok "A2b at least 10 rows come from references/release.md ($N_REL)"; else t_bad "A2b at least 10 rows come from references/release.md" "$N_REL rows"; fi
for src in skills/playbook-tdd/references/test-quality.md skills/playbook-tdd/templates/role-prompt.md skills/playbook-tdd/roles/reviewer.md \
           skills/playbook-proof/SKILL.md skills/playbook-feedback/SKILL.md AGENTS.global.md; do
  n="$(nsrc "$src")"
  if [ "$n" -ge 5 ]; then t_ok "A2d the keep list covers $src, a file the lane edits ($n rows)"; else t_bad "A2d the keep list covers $src, a file the lane edits" "$n rows"; fi
done

# copy_tree DIR -> DIR holds skills/, AGENTS.global.md and docs/ of the real tree
copy_tree() { mkdir -p "$1"; cp -R "$PB_ROOT/skills" "$1/"; cp "$PB_ROOT/AGENTS.global.md" "$1/"; cp -R "$PB_ROOT/docs" "$1/"; }
# drop_text DIR TEXT -> remove every occurrence of TEXT (fixed string, within a line) from every file of DIR's tree
drop_text() {
  local f
  for f in $(find "$1/skills" -type f -name '*.md') "$1/AGENTS.global.md"; do
    awk -v t="$2" '{ s = $0; o = ""; while ((p = index(s, t)) > 0) { o = o substr(s, 1, p - 1); s = substr(s, p + length(t)) } print o s }' "$f" > "$f.new" && mv "$f.new" "$f"
  done
}

echo "A2b self-test: a lost sentence fails and names its row; a moved and re-wrapped one passes"
GONE='A merge conflict makes those slices serial.'
assert_eq "A2b the self-test sentence is a KEEP row" "1" "$(awk -F'\t' -v t="$GONE" '$1 == "KEEP" && $4 == t { n++ } END { print n + 0 }' "$TSV" 2>/dev/null)"
C="$(mk_tmp)"; copy_tree "$C"
run bash "$ROWS" check "$C" "$TSV"
assert_rc "A2b control: the copied tree passes" 0
drop_text "$C" "$GONE"
run bash "$ROWS" check "$C" "$TSV"
assert_rc "A2b the copy without the sentence fails" 1
assert_contains "A2b the FAIL names the lost sentence" "$OUT" "$GONE"
assert_contains "A2b the FAIL says it is a KEEP row found 0 times" "$OUT" "found 0 time(s)"
mkdir -p "$C/skills/playbook-tdd/references"
printf '# Moved\n\n- A merge conflict\n  makes those **slices**\n  serial. Next sentence here.\n' > "$C/skills/playbook-tdd/references/zz-moved.md"
run bash "$ROWS" check "$C" "$TSV"
assert_rc "A2b the sentence moved into another file, as a re-wrapped list item with markup, passes" 0

echo "A2 the checker on a tiny tree: count at least the base count, DOCS, EDIT, RETIRE"
T="$(mk_tmp)"; mkdir -p "$T/skills/x" "$T/docs"
printf -- '---\nname: x\n---\n# Title words go here\n\nAlpha beta gamma delta. Alpha beta gamma delta.\n' > "$T/skills/x/SKILL.md"
printf 'Docs only line is here.\n' > "$T/docs/release-speed.md"
mk_tsv() { { printf '# base test\n'; printf '%s\n' "$@"; } > "$T/k.tsv"; }
TAB="$(printf '\t')"
mk_tsv "KEEP${TAB}skills/x/SKILL.md${TAB}2${TAB}Alpha beta gamma delta.${TAB}"
run bash "$ROWS" check "$T" "$T/k.tsv"
assert_rc "A2 a sentence present twice with base count 2: ok" 0
mk_tsv "KEEP${TAB}skills/x/SKILL.md${TAB}3${TAB}Alpha beta gamma delta.${TAB}"
run bash "$ROWS" check "$T" "$T/k.tsv"
assert_rc "A2 a sentence present twice with base count 3: FAIL" 1
assert_contains "A2 the FAIL gives found and base counts" "$OUT" "found 2 time(s), 3 at base"
mk_tsv "DOCS${TAB}skills/x/r.md${TAB}1${TAB}Docs only line is here.${TAB}"
run bash "$ROWS" check "$T" "$T/k.tsv"
assert_rc "A2 a DOCS row found in docs/release-speed.md: ok" 0
mk_tsv "DOCS${TAB}skills/x/r.md${TAB}1${TAB}Nowhere at all in any file.${TAB}"
run bash "$ROWS" check "$T" "$T/k.tsv"
assert_rc "A2 a DOCS row found nowhere: FAIL" 1
mk_tsv "EDIT${TAB}skills/x/SKILL.md${TAB}0${TAB}Alpha [a-z]+ gamma${TAB}C3 stops in one list"
run bash "$ROWS" check "$T" "$T/k.tsv"
assert_rc "A2 an EDIT row with a Cn reason whose pattern is found: ok" 0
mk_tsv "EDIT${TAB}skills/x/SKILL.md${TAB}0${TAB}references/full\.md${TAB}pointer to full.md"
run bash "$ROWS" check "$T" "$T/k.tsv"
assert_rc "A2 an EDIT pointer row whose pattern is not found: FAIL" 1
mk_tsv "EDIT${TAB}skills/x/SKILL.md${TAB}0${TAB}Alpha${TAB}reworded"
run bash "$ROWS" check "$T" "$T/k.tsv"
assert_rc "A2 an EDIT row whose reason names no Cn and no pointer: FAIL" 1
mk_tsv "RETIRE${TAB}skills/x/SKILL.md${TAB}0${TAB}Gone sentence of four words.${TAB}"
run bash "$ROWS" check "$T" "$T/k.tsv"
assert_rc "A2 a RETIRE row with an empty reason: FAIL" 1
mk_tsv "RETIRE${TAB}skills/x/SKILL.md${TAB}0${TAB}Gone sentence of four words.${TAB}C12 the rename rule is conditional"
run bash "$ROWS" check "$T" "$T/k.tsv"
assert_rc "A2 a RETIRE row with a Cn reason: ok" 0
mk_tsv "RETIRE${TAB}AGENTS.global.md${TAB}0${TAB}Gone sentence of four words.${TAB}P17 sections merged (F5)"
run bash "$ROWS" check "$T" "$T/k.tsv"
assert_rc "S4 a RETIRE row with a Part B reason (P17): ok" 0
mk_tsv "EDIT${TAB}AGENTS.global.md${TAB}0${TAB}Alpha [a-z]+ gamma${TAB}P8 pointer kept"
run bash "$ROWS" check "$T" "$T/k.tsv"
assert_rc "S4 an EDIT row with a Part B reason (P8) whose pattern is found: ok" 0
mk_tsv "RETIRE${TAB}AGENTS.global.md${TAB}0${TAB}Gone sentence of four words.${TAB}P99 is no paragraph"
run bash "$ROWS" check "$T" "$T/k.tsv"
assert_rc "S4 a RETIRE row whose reason names P99 (no such paragraph): FAIL" 1
mk_tsv "MOVE${TAB}skills/x/SKILL.md${TAB}1${TAB}Alpha beta gamma delta.${TAB}"
run bash "$ROWS" check "$T" "$T/k.tsv"
assert_rc "A2 an unknown kind: FAIL" 1
run bash "$ROWS" check "$T" "$T/missing.tsv"
assert_rc "A2 a missing keep list: FAIL" 1

echo "A2d row extraction"
F="$T/skills/x/units.md"
cat > "$F" <<'EOF'
---
description: Front matter is never a unit at all.
---
# Heading with four words

First sentence, e.g. Foo bar stays joined, version 2. Next stays joined too. **Why:** a bold
start splits here. Short.
- A list item one. `code` starts a second sentence here.
1. Numbered item text is a unit.
| Col one | Col two | Col three |
|---|---|---|
```
fenced code is never a unit here
```
EOF
U="$(bash "$ROWS" units "$F" | cut -f2)"
assert_not_contains "A2d front matter is dropped" "$U" "Front matter"
assert_not_contains "A2d fenced code is dropped" "$U" "fenced code"
assert_contains "A2d a heading is a unit without its #" "$U" "Heading with four words"
assert_contains "A2d no split after e.g. and none after a digit" "$U" "First sentence, e.g. Foo bar stays joined, version 2. Next stays joined too."
assert_contains "A2d a split before ** and the markup is stripped" "$U" "Why: a bold start splits here."
assert_not_contains "A2d units under 4 words are dropped" "$U" "Short."
assert_contains "A2d a list item loses its marker" "$U" "A list item one."
assert_contains "A2d a split before a backtick" "$U" "\`code\` starts a second sentence here."
assert_contains "A2d a numbered item loses its number" "$U" "Numbered item text is a unit."
assert_contains "A2d a table row is one unit, | becomes a space" "$U" "Col one Col two Col three"
assert_not_contains "A2d the table separator row is dropped" "$U" "---"

echo "A2c the key rules of playbook-tdd are found in skills/playbook-tdd/**"
assert_file "A2c tests/skill-keep-rules.txt exists" "$RULES"
TDDFLAT="$(bash "$ROWS" flat $(find "$PB_ROOT/skills/playbook-tdd" -type f -name '*.md' | LC_ALL=C sort))"
NR=0
while IFS= read -r re; do
  case "$re" in '' | '#'*) continue ;; esac
  NR=$((NR + 1))
  if printf '%s\n' "$TDDFLAT" | grep -qiE -- "$re"; then t_ok "A2c key rule: $re"; else t_bad "A2c key rule: $re" "not found in skills/playbook-tdd/**"; fi
done < "$RULES"
if [ "$NR" -ge 40 ]; then t_ok "A2c the key-rule list has at least 40 rules ($NR)"; else t_bad "A2c the key-rule list has at least 40 rules" "$NR rules"; fi

t_summary
