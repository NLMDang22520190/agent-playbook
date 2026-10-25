#!/usr/bin/env bash
# Builds the scenario table of evals/RUBRIC.md from the "## E<n> <title>" headings of evals/scenarios.md (maintainers).
#   tools/rubric-table.sh           prints the table: the header and separator lines of RUBRIC.md, then one row "| E<n> <title> | | | | |"
#                                   per heading, in scenarios.md order (nothing written)
#   tools/rubric-table.sh --write   replaces the rows under the "| Scenario |" header of RUBRIC.md; the text outside the table is unchanged
#   tools/rubric-table.sh --check   only compares: exit 0 when RUBRIC.md matches, 1 when not (the first differing row is named)
# Both files are read next to the tools directory (as tools/readme-count.sh). Exit: 0 ok, 1 out of date (--check) or no table in
# RUBRIC.md, 2 usage or a file that cannot be read.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
SCN="$ROOT/evals/scenarios.md"
RUB="$ROOT/evals/RUBRIC.md"

usage() { echo "usage: tools/rubric-table.sh [--write | --check]" >&2; exit 2; }

mode=print
case $# in
  0) ;;
  1) case "$1" in --write) mode="write" ;; --check) mode="check" ;; *) usage ;; esac ;;
  *) usage ;;
esac
[ -r "$SCN" ] || { echo "cannot read $SCN" >&2; exit 2; }
[ -r "$RUB" ] || { echo "cannot read $RUB" >&2; exit 2; }

TMPS=""
cleanup() { [ -z "$TMPS" ] || rm -f $TMPS; }
trap cleanup EXIT
tmpf() { local t; t="$(mktemp "${TMPDIR:-/tmp}/rubric-table.XXXXXX")" || { echo "mktemp failed" >&2; exit 2; }; TMPS="$TMPS $t"; printf '%s\n' "$t"; }

ROWS="$(tmpf)"
sed -n 's/^## \(E[0-9][0-9]*\) \(.*\)$/| \1 \2 | | | | |/p' "$SCN" > "$ROWS"

# the table of RUBRIC.md: the "| Scenario |" header line, the separator line after it, then the contiguous "| E<n>" rows
grep -q '^| Scenario |' "$RUB" || { echo "no '| Scenario |' table header in $RUB" >&2; exit 1; }

case "$mode" in
  print)
    awk '/^\| Scenario \|/ { print; getline; print; exit }' "$RUB"
    cat "$ROWS" ;;
  check)
    OLD="$(tmpf)"
    awk 's == 0 && /^\| Scenario \|/ { s = 1; next } s == 1 { s = 2; next } s == 2 && /^\| E[0-9]/ { print; next } s == 2 { exit }' "$RUB" > "$OLD"
    awk -v ef="$ROWS" -v of="$OLD" 'BEGIN {
      n = 0; m = 0
      while ((getline l < ef) > 0) a[++n] = l
      while ((getline l < of) > 0) b[++m] = l
      k = n > m ? n : m
      for (i = 1; i <= k; i++) if (!(i in a) || !(i in b) || a[i] != b[i]) {
        printf "evals/RUBRIC.md is out of date at table row %d: expected \"%s\", found \"%s\" (run tools/rubric-table.sh --write)\n", i, (i in a) ? a[i] : "(no row)", (i in b) ? b[i] : "(no row)"
        exit 1
      }
      exit 0 }' || exit 1 ;;
  write)
    NEW="$(tmpf)"
    awk -v rf="$ROWS" 'BEGIN { n = 0; while ((getline l < rf) > 0) r[++n] = l }
      s == 0 && /^\| Scenario \|/ { print; s = 1; next }
      s == 1 { print; s = 2; for (i = 1; i <= n; i++) print r[i]; next }
      s == 2 && /^\| E[0-9]/ { next }
      s == 2 { s = 3 }
      { print }' "$RUB" > "$NEW" || { echo "cannot build the new table" >&2; exit 2; }
    cat "$NEW" > "$RUB" || { echo "cannot write $RUB" >&2; exit 2; }
    echo "evals/RUBRIC.md: $(grep -c . "$ROWS") scenario rows" ;;
esac
