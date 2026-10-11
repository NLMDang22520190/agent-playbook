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
exit 0
