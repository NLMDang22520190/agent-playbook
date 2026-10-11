#!/usr/bin/env bash
# Run suites with one-true-awk first on PATH: the awk macOS ships, so BSD awk problems show up before CI.
#   tools/bsd-check.sh [SUITE...]      (default: tests/run-all.sh, everything)
# Uses `original-awk`, else `nawk`, linked as `awk` in a temp dir put first on PATH (a copy when links fail).
# Prints the awk it used. Exit: the suites' exit code; 2 when neither awk is installed (apt install original-awk).
set -u
cd "$(dirname "$0")/.." || exit 3

src=""; name=""
for c in original-awk nawk; do
  p="$(command -v "$c" 2>/dev/null)" || p=""
  [ -n "$p" ] && { src="$p"; name="$c"; break; }
done
if [ -z "$src" ]; then
  echo "bsd-check: no one-true-awk found (original-awk or nawk). Install it: apt install original-awk (Ubuntu, WSL) or use macOS's own awk." >&2
  exit 2
fi

base="${TMPDIR:-/tmp}"; base="${base%/}"
AWKD="$(mktemp -d "$base/pbbsdawk.XXXXXX")" || exit 3
trap 'rm -rf "$AWKD"' EXIT
ln -s "$src" "$AWKD/awk" 2>/dev/null && [ -x "$AWKD/awk" ] || { rm -f "$AWKD/awk"; cp "$src" "$AWKD/awk" && chmod +x "$AWKD/awk"; } || exit 3
echo "bsd-check: awk is $name ($src)"
export PATH="$AWKD:$PATH"

if [ "$#" -eq 0 ]; then
  bash tests/run-all.sh; rc=$?
else
  rc=0
  for s in "$@"; do
    bash "$s" || rc=$?
  done
fi
exit "$rc"
