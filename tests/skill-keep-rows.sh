#!/usr/bin/env bash
# tests/skill-keep-rows.sh: the row extraction and the check behind tests/test-skill-keep.sh (lane C spec A2, A2d).
# It lives under tests/ because the tester role owns the keep guard (tools/ is production code under the role gate).
#   skill-keep-rows.sh units FILE...    one line per unit: FILE<TAB>TEXT
#   skill-keep-rows.sh flat FILE...     one line per file: the file's text normalised the same way, joined, not split
#   skill-keep-rows.sh gen ROOT FILE... KEEP rows for FILE... (paths relative to ROOT), each with its count in ROOT's tree
#   skill-keep-rows.sh check ROOT TSV   check TSV against ROOT; prints one FAIL line per bad row; exit 1 on any FAIL
# Units (A2d): front matter and fenced code blocks are dropped; each heading, table row, list item and paragraph is a block
# (a paragraph or list item joins its wrapped lines); paragraphs and list items are split into sentences at ". ", "? " or
# "! " followed by an uppercase letter, a backtick or "*", never after e.g., i.e., etc., vs. or a digit; markup is stripped
# (leading #s, "- ", "* ", "N. ", every "*", "|" becomes a space; backticks are kept); whitespace is collapsed; units under
# 4 words and table separator rows are dropped. The tree text (flat) gets the same stripping, so a sentence that moved to
# another file, list or paragraph, or was re-wrapped, is still found.
# TSV rows: KIND<TAB>SOURCE<TAB>COUNT<TAB>TEXT<TAB>REASON; lines starting with # are comments.
#   KEEP   TEXT occurs at least COUNT times in the flat text of ROOT/skills/**/*.md plus ROOT/AGENTS.global.md
#   DOCS   TEXT is in ROOT/docs/release-speed.md (or, before the move, still COUNT times in that tree)
#   EDIT   TEXT is an ERE found in that tree; REASON names a contradiction id (C1-C12) or "pointer"
#   RETIRE REASON names a contradiction id (C1-C12) or "pointer"
# Bash 3.2 and BWK awk compatible; LC_ALL=C (byte matching).
set -u
LC_ALL=C
export LC_ALL

# the shared per-line normaliser and block builder (awk functions, pasted into each program)
AWK_LIB='
function norm(s) {
  gsub(/\*/, "", s); gsub(/\|/, " ", s); gsub(/[ \t\r]+/, " ", s)
  sub(/^ /, "", s); sub(/ $/, "", s)
  return s
}
function nwords(s,   a) { return split(s, a, " ") }
# line_kind sets LK (H heading, T table row, L list item, B blank, C other) and LT (the line without its marker)
function line_kind(raw,   s) {
  s = raw; sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s)
  LT = s
  if (s == "") { LK = "B"; return }
  if (s ~ /^#+ /) { sub(/^#+ +/, "", s); LT = s; LK = "H"; return }
  if (s ~ /^\|/) { LK = "T"; return }
  if (s ~ /^[-*] /) { sub(/^[-*] +/, "", s); LT = s; LK = "L"; return }
  if (s ~ /^[0-9]+\. /) { sub(/^[0-9]+\. +/, "", s); LT = s; LK = "L"; return }
  LK = "C"
}
# skip(raw) -> 1 for front matter and fenced code (state per file in FM, FENCE)
function skip(raw) {
  if (FNR == 1) { FM = 0; FENCE = 0; if (raw ~ /^---[ \t\r]*$/) { FM = 1; return 1 } }
  if (FM) { if (raw ~ /^---[ \t\r]*$/) FM = 0; return 1 }
  if (raw ~ /^[ \t]*```/) { FENCE = !FENCE; return 1 }
  return FENCE
}
'

units() {
  awk "$AWK_LIB"'
function emit(u) { u = norm(u); if (u ~ /^[-: ]*$/) return; if (nwords(u) >= 4) print FILENAME "\t" u }
function sentences(s,   n, i, c, nx, start, pre) {
  n = length(s); start = 1
  for (i = 1; i <= n - 2; i++) {
    c = substr(s, i, 1)
    if (c != "." && c != "?" && c != "!") continue
    if (substr(s, i + 1, 1) != " ") continue
    nx = substr(s, i + 2, 1)
    if (nx !~ /[A-Z`*]/) continue
    if (c == ".") {
      pre = substr(s, start, i - start)
      if (pre ~ /(^|[^A-Za-z])(e\.g|i\.e|etc|vs)$/) continue
      if (substr(s, i - 1, 1) ~ /[0-9]/) continue
    }
    emit(substr(s, start, i - start + 1)); start = i + 2
  }
  emit(substr(s, start))
}
function flush() { if (BUF != "") sentences(BUF); BUF = "" }
FNR == 1 { flush() }
{
  if (skip($0)) next
  line_kind($0)
  if (LK == "B") { flush(); next }
  if (LK == "H" || LK == "T") { flush(); emit(LT); next }
  if (LK == "L") { flush(); BUF = LT; next }
  BUF = (BUF == "") ? LT : BUF " " LT
}
END { flush() }' "$@"
}

flat() {
  local f
  for f in "$@"; do
    awk "$AWK_LIB"'
{ if (skip($0)) next; line_kind($0); if (LK == "B") next; OUT = OUT " " LT }
END { print norm(OUT) }' "$f"
  done
}

# tree_files ROOT -> the keep haystack files, one per line (sorted)
tree_files() {
  [ -d "$1/skills" ] && find "$1/skills" -type f -name '*.md' | LC_ALL=C sort
  [ -f "$1/AGENTS.global.md" ] && printf '%s\n' "$1/AGENTS.global.md"
  return 0
}

# the counting program: stdin is the flat tree (one line per file), "@@DOCS", the docs line, "@@TSV", then the TSV
COUNT_AWK='
function occ(h, t,   n, p) { n = 0; while ((p = index(h, t)) > 0) { n++; h = substr(h, p + length(t)) } return n }
function tree(t,   i, n) { n = 0; for (i = 1; i <= NH; i++) n += occ(H[i], t); return n }
function tree_re(re,   i) { for (i = 1; i <= NH; i++) if (H[i] ~ re) return 1; return 0 }
function bad(m) { print "FAIL tsv line " TL ": " m; NBAD++ }
function reason_ok(r) { return (r ~ /(^|[^A-Za-z0-9])C([1-9]|1[0-2])([^0-9]|$)/ || r ~ /pointer/) }
$0 == "@@DOCS" { part = 1; next }
$0 == "@@TSV" { part = 2; TL = 0; next }
part == 0 { H[++NH] = $0; next }
part == 1 { D = D $0; next }
{
  TL++
  if ($0 ~ /^#/ || $0 ~ /^[ \t\r]*$/) next
  n = split($0, f, "\t")
  if (n < 4) { bad("fewer than 4 tab-separated fields"); next }
  k = f[1]; src = f[2]; cnt = f[3] + 0; txt = f[4]; why = (n >= 5) ? f[5] : ""
  NR_K[k]++
  if (k == "KEEP") {
    got = tree(txt)
    if (got < cnt) bad("KEEP (" src ") found " got " time(s), " cnt " at base: " txt)
  } else if (k == "DOCS") {
    if (index(D, txt) == 0 && tree(txt) < cnt) bad("DOCS (" src ") not in docs/release-speed.md: " txt)
  } else if (k == "EDIT") {
    if (!reason_ok(why)) bad("EDIT without a reason naming C1-C12 or pointer: " txt)
    else if (!tree_re(txt)) bad("EDIT (" src ") pattern not found in the skill tree: " txt)
  } else if (k == "RETIRE") {
    if (!reason_ok(why)) bad("RETIRE without a reason naming C1-C12 or pointer: " txt)
  } else bad("unknown kind [" k "]")
}
END {
  printf "rows: KEEP %d DOCS %d EDIT %d RETIRE %d; FAIL %d\n", NR_K["KEEP"], NR_K["DOCS"], NR_K["EDIT"], NR_K["RETIRE"], NBAD
  exit (NBAD > 0)
}'

check() {
  local root="$1" tsv="$2" files
  [ -f "$tsv" ] || { echo "FAIL no keep list: $tsv"; return 1; }
  files="$(tree_files "$root")"
  {
    # shellcheck disable=SC2086
    [ -n "$files" ] && flat $files
    echo "@@DOCS"
    if [ -f "$root/docs/release-speed.md" ]; then flat "$root/docs/release-speed.md"; else echo; fi
    echo "@@TSV"
    cat "$tsv"
  } | awk "$COUNT_AWK"
}

gen() {
  local root="$1" files f
  shift
  files="$(tree_files "$root")"
  {
    # shellcheck disable=SC2086
    flat $files
    echo "@@UNITS"
    for f in "$@"; do (cd "$root" && units "$f"); done
  } | awk -F'\t' '
function occ(h, t,   n, p) { n = 0; while ((p = index(h, t)) > 0) { n++; h = substr(h, p + length(t)) } return n }
$0 == "@@UNITS" { part = 1; next }
part == 0 { H[++NH] = $0; next }
{ if ($2 in SEEN) next; SEEN[$2] = 1; n = 0; for (i = 1; i <= NH; i++) n += occ(H[i], $2); print "KEEP\t" $1 "\t" n "\t" $2 "\t" }'
}

case "${1:-}" in
  units) shift; units "$@" ;;
  flat) shift; flat "$@" ;;
  gen) shift; [ "$#" -ge 2 ] || { echo "usage: skill-keep-rows.sh gen ROOT FILE..." >&2; exit 2; }; gen "$@" ;;
  check) shift; [ "$#" -eq 2 ] || { echo "usage: skill-keep-rows.sh check ROOT TSV" >&2; exit 2; }; check "$1" "$2" ;;
  *) echo "usage: skill-keep-rows.sh units|flat FILE... | gen ROOT FILE... | check ROOT TSV" >&2; exit 2 ;;
esac
