#!/usr/bin/env bash
# Check that a release tag matches VERSION and has a CHANGELOG.md entry; optionally print its notes.
#   tools/check-release.sh vX.Y.Z           check only
#   tools/check-release.sh --notes vX.Y.Z   check, then print the CHANGELOG section body to stdout
# Reads VERSION and CHANGELOG.md from the repository root (the parent of this script's directory).
# Exit codes: 0 ok, 1 VERSION mismatch or missing "## X.Y.Z " entry, 2 usage (tag not vX.Y.Z),
#             3 environment (VERSION or CHANGELOG.md unreadable).
set -u
cd "$(dirname "$0")/.." || exit 3

usage() { echo "usage: tools/check-release.sh [--notes] vX.Y.Z" >&2; exit 2; }

notes=0
if [ "${1:-}" = "--notes" ]; then notes=1; shift; fi
[ "$#" -eq 1 ] || usage
tag="$1"
printf '%s' "$tag" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || { echo "tag '$tag' is not vX.Y.Z" >&2; usage; }
ver="${tag#v}"

[ -r VERSION ] || { echo "VERSION not readable" >&2; exit 3; }
[ -r CHANGELOG.md ] || { echo "CHANGELOG.md not readable" >&2; exit 3; }

file_ver="$(tr -d ' \t\r\n' < VERSION)"
if [ "$file_ver" != "$ver" ]; then
  echo "VERSION is '$file_ver' but the tag is $tag" >&2
  exit 1
fi
if ! awk -v h="## $ver " 'index($0, h) == 1 { found = 1 } END { exit !found }' CHANGELOG.md; then
  echo "CHANGELOG.md has no '## $ver ' entry for $tag" >&2
  exit 1
fi

if [ "$notes" -eq 1 ]; then
  awk -v h="## $ver " '
    index($0, h) == 1 { on = 1; next }
    on && /^## / { exit }
    on { print }
  ' CHANGELOG.md
else
  echo "release $tag: VERSION and CHANGELOG.md ok"
fi
