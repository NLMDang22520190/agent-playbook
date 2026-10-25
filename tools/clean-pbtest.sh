#!/usr/bin/env bash
# Manual clean tool for stale test temp entries (maintainers). A suite killed with SIGKILL skips its traps, so the
# pbtest.* dirs and the pblist.* list file that tests/lib.sh makes (mktemp, directly under ${TMPDIR:-/tmp}) stay behind.
#   tools/clean-pbtest.sh [--hours N] [--yes]   dry run by default: prints each candidate and a count, removes nothing
#   --yes        remove the candidates (never automatic; nothing in the playbook calls this tool)
#   --hours N    age limit in hours, a positive integer (default 24)
#   --help       this text
# Candidates: pbtest.* directories and pblist.* regular files directly under ${TMPDIR:-/tmp}, owned by the current user,
# whose mtime is older than the limit (find -mmin; a running suite's entries are fresh). Symlinks are never followed or
# removed (find without -L, -type d / -type f do not match a link), and nothing else in TMPDIR is touched.
# Refuses (exit 2) when TMPDIR is set but empty, is not a directory, or resolves to /.
# Portable: only find -maxdepth/-name/-type/-user/-mmin, no GNU-only flags (tools/bsd-check.sh rules).
# Exit: 0 ok (also when nothing is stale), 2 usage or refused TMPDIR.
set -u

usage() { echo "usage: tools/clean-pbtest.sh [--hours N] [--yes]   (dry run unless --yes; default age 24 hours)" >&2; exit 2; }

hours=24; yes=0
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) yes=1 ;;
    --help|-h) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; echo "usage: tools/clean-pbtest.sh [--hours N] [--yes]"; exit 0 ;;
    --hours)
      [ $# -ge 2 ] || { echo "clean-pbtest: --hours needs a value" >&2; usage; }
      shift; hours="$1" ;;
    *) usage ;;
  esac
  shift
done
case "$hours" in
  '' | *[!0-9]*) echo "clean-pbtest: --hours must be a positive integer, got [$hours]" >&2; exit 2 ;;
esac
hours="$(printf '%s' "$hours" | sed 's/^0*//')"
if [ -z "$hours" ] || [ "${#hours}" -gt 9 ]; then echo "clean-pbtest: --hours must be a positive integer (at most 9 digits)" >&2; exit 2; fi
mins=$((hours * 60))

if [ "${TMPDIR+set}" = set ] && [ -z "$TMPDIR" ]; then echo "clean-pbtest: TMPDIR is set but empty; refusing" >&2; exit 2; fi
raw="${TMPDIR:-/tmp}"
base="$(cd "$raw" 2>/dev/null && pwd -P)" || { echo "clean-pbtest: TMPDIR [$raw] is not a directory; refusing" >&2; exit 2; }
trimmed="$base"; while [ "${trimmed%/}" != "$trimmed" ]; do trimmed="${trimmed%/}"; done
if [ -z "$trimmed" ]; then echo "clean-pbtest: TMPDIR resolves to /; refusing" >&2; exit 2; fi
base="$trimmed"

uid="$(id -u)"
cands="$(
  find "$base" -maxdepth 1 -name 'pbtest.*' -type d -user "$uid" -mmin "+$mins" -print 2>/dev/null
  find "$base" -maxdepth 1 -name 'pblist.*' -type f -user "$uid" -mmin "+$mins" -print 2>/dev/null
)"

n=0; removed=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  # defensive: only a single path component named pbtest.* / pblist.* directly under the base (a name with a newline is split)
  rest="${p#"$base"/}"
  case "$p" in "$base"/*) ;; *) continue ;; esac
  case "$rest" in */*) continue ;; pbtest.*) [ -d "$p" ] && [ ! -L "$p" ] || continue ;; pblist.*) [ -f "$p" ] && [ ! -L "$p" ] || continue ;; *) continue ;; esac
  n=$((n + 1))
  if [ "$yes" = 1 ]; then
    if rm -rf "$p" 2>/dev/null && [ ! -e "$p" ]; then removed=$((removed + 1)); echo "removed $p"; else echo "could not remove $p" >&2; fi
  else
    echo "$p"
  fi
done <<EOT
$cands
EOT

if [ "$yes" = 1 ]; then
  echo "removed $removed of $n stale entries older than $hours hours under $base"
else
  echo "$n stale entries older than $hours hours under $base (dry run; add --yes to remove)"
fi
exit 0
