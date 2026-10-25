#!/usr/bin/env bash
# Tests for tools/rubric-table.sh (v0.26.0 lane N, slice S1, spec AC11 and AC12): the scenario table of evals/RUBRIC.md is built from the
# "## E<n> <title>" headings of evals/scenarios.md, one row "| E<n> <title> | | | | |" per heading, in file order.
#   tools/rubric-table.sh            prints the table (nothing written)
#   tools/rubric-table.sh --write    replaces the table in evals/RUBRIC.md (text outside the table unchanged)
#   tools/rubric-table.sh --check    exit 0 when RUBRIC.md matches, 1 when not (naming the first differing row); other arguments exit 2
# Files are resolved next to the tools directory (as tools/readme-count.sh), so a temp copy laid out as <T>/tools and <T>/evals is graded on its own files.
# Row counts are compared with the heading count, never with a literal (decision D17: lane W adds E35-E39 later).
. "$(dirname "$0")/lib.sh"

TOOL="$PB_ROOT/tools/rubric-table.sh"
# rows_of FILE -> the expected table rows built from the "## E<n> <title>" headings of a scenarios.md
rows_of() { sed -n 's/^## \(E[0-9][0-9]*\) \(.*\)$/| \1 \2 | | | | |/p' "$1"; }
# table_of FILE -> the "| E<n> ..." rows of a RUBRIC.md
table_of() { grep '^| E[0-9]' "$1"; }
# outside_of FILE -> every line of a RUBRIC.md that is not a scenario row
outside_of() { grep -v '^| E[0-9]' "$1"; }
# mk_copy -> a temp dir <T> with tools/rubric-table.sh (when it exists), evals/scenarios.md and evals/RUBRIC.md of this repo
mk_copy() { local t; t="$(mk_tmp)"; mkdir -p "$t/tools" "$t/evals"
  [ -f "$TOOL" ] && cp "$TOOL" "$t/tools/rubric-table.sh"
  cp "$PB_ROOT/evals/scenarios.md" "$PB_ROOT/evals/RUBRIC.md" "$t/evals/"
  printf '%s\n' "$t"; }

echo "AC12 the real RUBRIC.md is up to date"
run bash "$TOOL" --check
assert_rc "AC12 tools/rubric-table.sh --check exits 0 on the real repo (RUBRIC.md matches scenarios.md)" 0
NH="$(grep -c '^## E[0-9]' "$PB_ROOT/evals/scenarios.md")"
assert_eq "AC12 RUBRIC.md has one scenario row per '## E' heading of scenarios.md (derived count, D17)" "$NH" "$(table_of "$PB_ROOT/evals/RUBRIC.md" | grep -c .)"
assert_eq "AC11 the real RUBRIC.md rows are exactly the rows built from the headings, in file order" "$(rows_of "$PB_ROOT/evals/scenarios.md")" "$(table_of "$PB_ROOT/evals/RUBRIC.md")"

for e in E32 E33 E34; do   # v0.26.0 lane N S8: the scenarios this lane adds have a row (regenerated table)
  if grep -q "^| $e " "$PB_ROOT/evals/RUBRIC.md"; then t_ok "AC12 S8 RUBRIC.md has a row for $e"; else t_bad "AC12 S8 RUBRIC.md has a row for $e" "no '| $e ' row"; fi
done

echo "AC11 printing the table writes nothing"
T="$(mk_copy)"
cp "$T/evals/RUBRIC.md" "$T/rubric.before"
run bash "$T/tools/rubric-table.sh"
assert_rc "AC11 no argument prints the table and exits 0" 0
assert_eq "AC11 the printed rows are one per heading, in scenarios.md order" "$(rows_of "$T/evals/scenarios.md")" "$(printf '%s\n' "$OUT" | grep '^| E[0-9]')"
if cmp -s "$T/rubric.before" "$T/evals/RUBRIC.md"; then t_ok "AC11 printing leaves RUBRIC.md byte-identical"; else t_bad "AC11 printing leaves RUBRIC.md byte-identical" "RUBRIC.md changed"; fi

echo "AC11 --write regenerates a stale table and keeps the text around it"
T="$(mk_copy)"
# a stale table: drop every row after the first two (like the old E1-E17 table against E1-E31)
awk '/^\| E[0-9]/ { n++; if (n > 2) next } { print }' "$PB_ROOT/evals/RUBRIC.md" > "$T/evals/RUBRIC.md"
outside_of "$T/evals/RUBRIC.md" > "$T/outside.before"
run bash "$T/tools/rubric-table.sh" --check
assert_rc "AC11 --check exits 1 on a stale table" 1
run bash "$T/tools/rubric-table.sh" --write
assert_rc "AC11 --write exits 0" 0
assert_eq "AC11 after --write the rows are the rows built from the headings" "$(rows_of "$T/evals/scenarios.md")" "$(table_of "$T/evals/RUBRIC.md")"
outside_of "$T/evals/RUBRIC.md" > "$T/outside.after"
if cmp -s "$T/outside.before" "$T/outside.after"; then t_ok "AC11 --write leaves the text outside the table byte-identical"; else t_bad "AC11 --write leaves the text outside the table byte-identical" "$(diff "$T/outside.before" "$T/outside.after" | head -5)"; fi
assert_contains "AC11 the header row is kept above the rows" "$(grep -n -A1 '^| Scenario |' "$T/evals/RUBRIC.md" | tail -1)" "|---|"
hl="$(grep -n -m1 '^| Scenario |' "$T/evals/RUBRIC.md" | cut -d: -f1)"; fl="$(grep -n -m1 '^| E[0-9]' "$T/evals/RUBRIC.md" | cut -d: -f1)"
assert_eq "AC11 the first row follows the header and its separator line" "$((hl + 2))" "$fl"
run bash "$T/tools/rubric-table.sh" --check
assert_rc "AC12 --check exits 0 right after --write" 0

echo "AC12 a new scenario heading makes --check fail until --write"
cat >> "$T/evals/scenarios.md" <<'EOF'

## E99 Rubric probe heading added by the test
**Prompt:** "Probe."
**Pass if:** probe.
**Fail if:** probe.
EOF
cp "$T/evals/RUBRIC.md" "$T/rubric.before"
run bash "$T/tools/rubric-table.sh" --check
assert_rc "AC12 --check exits 1 when scenarios.md has a heading that RUBRIC.md lacks" 1
assert_contains "AC11 --check names the first differing row (E99)" "$OUT" "E99"
if cmp -s "$T/rubric.before" "$T/evals/RUBRIC.md"; then t_ok "AC11 --check writes nothing"; else t_bad "AC11 --check writes nothing" "RUBRIC.md changed"; fi
outside_of "$T/evals/RUBRIC.md" > "$T/outside.before"
run bash "$T/tools/rubric-table.sh" --write
assert_rc "AC12 --write exits 0 with the new heading" 0
assert_contains "AC12 the new row is in RUBRIC.md" "$(table_of "$T/evals/RUBRIC.md")" "| E99 Rubric probe heading added by the test | | | | |"
assert_eq "AC12 the new row is the last row" "| E99 Rubric probe heading added by the test | | | | |" "$(table_of "$T/evals/RUBRIC.md" | tail -1)"
outside_of "$T/evals/RUBRIC.md" > "$T/outside.after"
if cmp -s "$T/outside.before" "$T/outside.after"; then t_ok "AC12 the text outside the table is byte-identical after adding a row"; else t_bad "AC12 the text outside the table is byte-identical after adding a row" "$(diff "$T/outside.before" "$T/outside.after" | head -5)"; fi
run_in / bash "$T/tools/rubric-table.sh" --check
assert_rc "AC11 --check from another working directory reads the files next to the tools dir (exit 0)" 0

echo "AC11 usage"
run bash "$T/tools/rubric-table.sh" --bogus
assert_rc "AC11 an unknown option exits 2" 2
run bash "$T/tools/rubric-table.sh" extra
assert_rc "AC11 a stray argument exits 2" 2
cp "$T/evals/RUBRIC.md" "$T/rubric.before"
run bash "$T/tools/rubric-table.sh" --write --bogus
assert_rc "AC11 --write with an unknown option exits 2" 2
if cmp -s "$T/rubric.before" "$T/evals/RUBRIC.md"; then t_ok "AC11 a usage error writes nothing"; else t_bad "AC11 a usage error writes nothing" "RUBRIC.md changed"; fi

t_summary
