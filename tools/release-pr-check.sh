#!/usr/bin/env bash
# Release PR gate: when a PR changes VERSION, run tools/check-release.sh for the new version.
#   tools/release-pr-check.sh BASE    BASE is the commit the PR merges into (CI: the pull request base sha)
# Compares the trimmed VERSION at BASE and at HEAD (trim as in check-release.sh). Unchanged: not a release PR, exit 0.
# Changed: HEAD must hold X.Y.Z digits, then tools/check-release.sh vX.Y.Z runs on the checked-out tree.
# Exit codes: 0 ok or not a release PR, 1 release check failed (any non-zero exit of check-release.sh, or a VERSION
#             value that is not X.Y.Z, or VERSION missing at HEAD), 2 usage, 3 environment (not a git repository,
#             BASE is not a commit).
set -u
cd "$(dirname "$0")/.." || exit 3

usage() { echo "usage: tools/release-pr-check.sh BASE" >&2; exit 2; }
[ "$#" -eq 1 ] || usage
base="$1"

# validate BASE first: "git show" exits 128 for both a bad revision and a missing path
git rev-parse --verify -q "$base^{commit}" >/dev/null 2>&1 || { echo "BASE '$base' is not a commit in this git repository" >&2; exit 3; }

# ver_at REV -> prints the trimmed VERSION at REV; returns 1 when REV has no VERSION file
ver_at() {
  git cat-file -e "$1:VERSION" 2>/dev/null || return 1
  git show "$1:VERSION" | tr -d ' \t\r\n'
}

base_present=1
base_ver="$(ver_at "$base")" || base_present=0
head_present=1
head_ver="$(ver_at HEAD)" || head_present=0

if [ "$head_present" -eq 0 ]; then
  if [ "$base_present" -eq 0 ]; then echo "VERSION unchanged (absent at BASE and HEAD): not a release PR"; exit 0; fi
  echo "VERSION is missing at HEAD but present at BASE ($base_ver)" >&2
  echo "release PR check failed" >&2
  exit 1
fi
if [ "$base_present" -eq 1 ] && [ "$base_ver" = "$head_ver" ]; then
  echo "VERSION unchanged ($head_ver): not a release PR"
  exit 0
fi

if ! printf '%s\n' "$head_ver" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "VERSION at HEAD is '$head_ver', want X.Y.Z digits" >&2
  echo "release PR check failed" >&2
  exit 1
fi

if ! bash tools/check-release.sh "v$head_ver"; then
  echo "release PR check failed: tools/check-release.sh v$head_ver" >&2
  exit 1
fi

# Stale README test count: the count (badge, "**N passing**", "N tests, run in sandboxes") can only be measured by a full run,
# but a tests/*.sh change after the last commit that changed it (or an uncommitted one) means it may be out of date.
# count_of REV -> the three count places of README.md at REV, on one line ("" when none)
count_of() { git show "$1:README.md" 2>/dev/null | grep -oE 'badge/tests-[0-9]+|\*\*[0-9]+ passing\*\*|[0-9]+ tests, run in sandboxes' | tr '\n' ' '; }
count_sha=""
for c in $(git log --format=%H HEAD -- README.md); do
  now="$(count_of "$c")"
  [ -n "$now" ] || continue
  if git rev-parse --verify -q "$c^" >/dev/null 2>&1; then
    [ "$now" != "$(count_of "$c^")" ] || continue
  fi
  count_sha="$c"; break
done
if [ -n "$count_sha" ]; then
  changed="$(git diff --name-only "$count_sha" HEAD -- 'tests/*.sh' 2>/dev/null)$(git status --porcelain -- 'tests/*.sh' 2>/dev/null)"
  if [ -n "$changed" ]; then
    echo "README test count may be stale: tests changed after $count_sha; rerun tests/run-all.sh and tools/readme-count.sh" >&2
    echo "release PR check failed" >&2
    exit 1
  fi
fi
echo "release PR check passed: v$head_ver"
