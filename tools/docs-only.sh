#!/usr/bin/env bash
# Is a pull request a docs-only change? (v0.23.0 AC5.1; used by the changes job of .github/workflows/test.yml)
#   tools/docs-only.sh BASE HEAD     run inside the repository; prints "true" or "false", exit 0 always.
# true only when `git diff --name-only --no-renames BASE...HEAD` lists at least one path, every path is exactly
# README.md or CHANGELOG.md at the repo root, and the README's test-count places (badge/tests-N, **N passing**,
# N tests, run in sandboxes) are identical at the merge base and at HEAD (a count change needs the full run,
# because the count check runs only there). Zero paths, any git error, a rename, any other path -> false.
# Bash 3.2 compatible.
set -u

say_false() { echo false; exit 0; }

base="${1:-}"; head="${2:-}"
[ -n "$base" ] && [ -n "$head" ] || say_false

paths="$(git diff --name-only --no-renames "$base...$head" 2>/dev/null)" || say_false
[ -n "$paths" ] || say_false

readme=0
oldifs="$IFS"; IFS='
'
for p in $paths; do
  case "$p" in
    README.md) readme=1 ;;
    CHANGELOG.md) ;;
    *) say_false ;;
  esac
done
IFS="$oldifs"

if [ "$readme" -eq 1 ]; then
  mb="$(git merge-base "$base" "$head" 2>/dev/null)" || say_false
  [ -n "$mb" ] || say_false
  PLACES='badge/tests-[0-9]+|\*\*[0-9]+ passing\*\*|[0-9]+ tests, run in sandboxes'
  old="$(git show "$mb:README.md" 2>/dev/null)" || say_false
  new="$(git show "$head:README.md" 2>/dev/null)" || say_false
  a="$(printf '%s\n' "$old" | grep -oE "$PLACES")"
  b="$(printf '%s\n' "$new" | grep -oE "$PLACES")"
  [ "$a" = "$b" ] || say_false
fi
echo true
exit 0
