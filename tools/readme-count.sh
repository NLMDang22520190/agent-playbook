#!/usr/bin/env bash
# Writes the README test count from a run-all log (maintainers).
#   tools/readme-count.sh LOG           total = sum of passed + skipped over the suite summary lines "<suite>.sh: N passed, M failed[, K skipped]";
#                                       rewrites the badge "tests-N", "**N passing**" and "N tests, run in sandboxes" in
#                                       README.md (next to the tools directory) and prints "README: N tests (passed + skipped)"
#   tools/readme-count.sh --check LOG   only compares (the flag may also come after LOG); nothing is written
# Same total as tools/release.sh. Exit: 0 ok, 1 a non-zero failed count, no summary line, or (--check) a mismatch, 2 usage.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
README="$ROOT/README.md"

usage() { echo "usage: tools/readme-count.sh [--check] LOG" >&2; exit 2; }

check=0; log=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check) check=1 ;;
    -*) usage ;;
    *) [ -z "$log" ] || usage; log="$1" ;;
  esac
  shift
done
[ -n "$log" ] || usage
[ -r "$log" ] || { echo "cannot read $log" >&2; exit 2; }
[ -r "$README" ] || { echo "cannot read $README" >&2; exit 2; }

lines="$(grep -E '^[^[:space:]]+\.sh: [0-9]+ passed, [0-9]+ failed' "$log" | grep -oE '[0-9]+ passed, [0-9]+ failed(, [0-9]+ skipped)?')"
[ -n "$lines" ] || { echo "no 'N passed, M failed' summary line in $log" >&2; exit 1; }
failed="$(printf '%s\n' "$lines" | awk '{ f += $3 } END { print f + 0 }')"
[ "$failed" -eq 0 ] || { echo "the log has $failed failed test(s); the README is not changed" >&2; exit 1; }
total="$(printf '%s\n' "$lines" | awk '{ t += $1; if (NF >= 6) t += $5 } END { print t + 0 }')"

PLACES='badge/tests-[0-9]+|\*\*[0-9]+ passing\*\*|[0-9]+ tests, run in sandboxes'
if [ "$check" -eq 1 ]; then
  bad=0; seen=0
  for n in $(grep -oE "$PLACES" "$README" | grep -oE '[0-9]+'); do
    seen=$((seen + 1))
    [ "$n" = "$total" ] || { echo "README.md says $n tests but the log has $total (passed + skipped)" >&2; bad=1; }
  done
  [ "$seen" -gt 0 ] || { echo "README.md has no test count to compare (log total: $total)" >&2; exit 1; }
  [ "$bad" -eq 0 ] || exit 1
  echo "README: $total tests (passed + skipped)"
  exit 0
fi

tmp="$(mktemp "${TMPDIR:-/tmp}/pbreadme.XXXXXX")" || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -f "${tmp:?}"' EXIT
sed -E -e "s#badge/tests-[0-9]+#badge/tests-$total#g" \
       -e "s#\\*\\*[0-9]+ passing\\*\\*#**$total passing**#g" \
       -e "s#[0-9]+ tests, run in sandboxes#$total tests, run in sandboxes#g" "$README" > "$tmp" || exit 1
cat "$tmp" > "$README" || exit 1   # keeps the file's mode
echo "README: $total tests (passed + skipped)"
