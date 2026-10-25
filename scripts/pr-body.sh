#!/usr/bin/env bash
# Print a PR description from the handoff files of a finished task.
#   pr-body.sh [--handoff DIR]      default DIR = .agents/handoff
# Output (markdown):
#   ## Summary           first paragraph of the spec's Understanding (else Goal), then the
#                        final report's Result text
#   ## Request coverage  copied from 06-final-report.md
#   ## Not checked       copied from 06-final-report.md
#   ## Review            copied from 06-final-report.md
#   ## Weight            the report's Weight line
#   ## Decisions         from decisions.md: the table's ID, Decision, How to undo and Status columns
#                        (a file without a table is copied minus its title); left out when there is none
#   ## Unverified        every report line with [UNVERIFIED], headings excepted; left out when there is none
# It adds no harness or vendor text; the caller appends any footer its harness requires.
# Exit: 0 ok, 1 01-spec.md or 06-final-report.md missing (names the file), 2 usage.
set -u
. "$(dirname "$0")/lib.sh"

dir=""
dir_set=0
while [ $# -gt 0 ]; do
  case "$1" in
    --handoff)
      [ $# -ge 2 ] || pb_die "--handoff needs a value" 2
      [ -n "$2" ] || pb_die "--handoff needs a non-empty directory" 2
      dir="$2"; dir_set=1; shift 2 ;;
    *) pb_die "usage: pr-body.sh [--handoff DIR]" 2 ;;
  esac
done
[ "$dir_set" = 1 ] || dir="$(pb_root_dir)/.agents/handoff"

spec="$dir/01-spec.md"
report="$dir/06-final-report.md"
[ -f "$spec" ] || pb_die "missing file: $spec (01-spec.md)" 1
[ -f "$report" ] || pb_die "missing file: $report (06-final-report.md)" 1

# first_para FILE HEADING -> first paragraph of the section "## HEADING" (empty if none)
first_para() {
  tr -d '\r' < "$1" | awk -v h="## $2" '
    done { next }
    !inside && ($0 == h || index($0, h " ") == 1) { inside = 1; next }
    inside && /^## / { done = 1; next }
    inside {
      if ($0 ~ /^[ \t]*$/) { if (started) done = 1; next }
      started = 1; print
    }'
}

# section FILE HEADING -> the lines of the section "## HEADING", without leading or trailing blank lines
section() {
  tr -d '\r' < "$1" | awk -v h="## $2" '
    !inside && !done && ($0 == h || index($0, h " ") == 1) { inside = 1; next }
    inside && /^## / { inside = 0; done = 1; next }
    inside {
      if ($0 ~ /^[ \t]*$/) { blank++; next }
      if (started) { for (i = 0; i < blank; i++) print "" }
      blank = 0; started = 1; print
    }'
}

para="$(first_para "$spec" Understanding)"
[ -n "$para" ] || para="$(first_para "$spec" Goal)"
result="$(tr -d '\r' < "$report" | awk '
  index($0, "**Result:**") == 1 { s = substr($0, 12); sub(/^[ \t]+/, "", s); print s; exit }')"
weight="$(tr -d '\r' < "$report" | awk 'index($0, "**Weight:**") == 1 { print; exit }')"

echo "## Summary"
echo
[ -n "$para" ] && printf '%s\n\n' "$para"
[ -n "$result" ] && printf '%s\n\n' "$result"
for s in "Request coverage" "Not checked" "Review"; do
  echo "## $s"
  echo
  body="$(section "$report" "$s")"
  [ -n "$body" ] && printf '%s\n\n' "$body"
done
if [ -n "$weight" ]; then
  echo "## Weight"
  echo
  printf '%s\n' "$weight"
fi
decisions=""
[ -f "$dir/decisions.md" ] && decisions="$(tr -d '\r' < "$dir/decisions.md" | awk '
  function trim(t) { sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t); return t }
  function row(l,   c, n, i, o) {
    n = split(l, c, "|"); o = "|"
    for (i = 1; i <= nk; i++) o = o " " trim(c[k[i]]) " |"
    return o
  }
  intable && /^\|/ { if ($0 !~ /^\|[ \t:|-]*$/) rows[++nr] = row($0); next }
  intable { intable = 0 }
  !table && /^\|/ {
    n = split($0, c, "|"); nk = 0
    for (i = 2; i < n; i++) {
      t = trim(c[i])
      if (t == "ID" || index(t, "Decision") == 1 || index(t, "How to undo") == 1 || t == "Status") k[++nk] = i
    }
    if (nk) { table = 1; intable = 1; head = row($0); next }
  }
  !/^# / { free[++nf] = $0 }
  END {
    if (table) {
      if (!nr) exit
      print head; sep = "|"; for (i = 1; i <= nk; i++) sep = sep "---|"; print sep
      for (i = 1; i <= nr; i++) print rows[i]
      exit
    }
    a = 1; while (a <= nf && free[a] ~ /^[ \t]*$/) a++
    b = nf; while (b >= a && free[b] ~ /^[ \t]*$/) b--
    for (i = a; i <= b; i++) print free[i]
  }')"
if [ -n "$decisions" ]; then
  printf '\n## Decisions\n\n%s\n' "$decisions"
fi
unverified="$(tr -d '\r' < "$report" | awk 'index($0, "[UNVERIFIED]") && !/^#/ {
  if ($0 ~ /^[ \t]*[-*] /) print; else print "- " $0 }')"
if [ -n "$unverified" ]; then
  printf '\n## Unverified\n\n%s\n' "$unverified"
fi
exit 0
