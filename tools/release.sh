#!/usr/bin/env bash
# Cut a release of this repository (maintainers only): verify, run the suite, tag, push the tag.
#   tools/release.sh vX.Y.Z [--dry-run]
# Refuses unless tools/check-release.sh passes, the work tree is clean (untracked files count),
# HEAD is branch main and equals origin/main. Then runs tests/run-all.sh. With --dry-run it prints
# the steps it would take (would tag, would push) and changes nothing; otherwise it creates the
# tag and pushes it (CI then creates the release). Repo root = the parent of this script's directory.
# Exit codes: 0 ok, 1 refused (check, tree, branch, origin or suite), 2 usage (not vX.Y.Z, extra
#             or unknown arguments), 3 environment (not a git repo, no origin, git failure).
set -u
cd "$(dirname "$0")/.." || exit 3

usage() { echo "usage: tools/release.sh vX.Y.Z [--dry-run]" >&2; exit 2; }
refuse() { echo "release refused: $1" >&2; exit 1; }

tag=""; dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1 ;;
    -*) usage ;;
    *) [ -z "$tag" ] || usage; tag="$1" ;;
  esac
  shift
done
[ -n "$tag" ] || usage
printf '%s' "$tag" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || { echo "tag '$tag' is not vX.Y.Z" >&2; usage; }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git work tree" >&2; exit 3; }

bash tools/check-release.sh "$tag" || refuse "tools/check-release.sh failed"

[ -z "$(git status --porcelain)" ] || refuse "work tree is not clean (untracked files count)"
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || refuse "HEAD is not on main"
git fetch -q origin || { echo "cannot fetch origin" >&2; exit 3; }
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main 2>/dev/null)" ] || refuse "main is not equal to origin/main"
git rev-parse -q --verify "refs/tags/$tag" >/dev/null && refuse "tag $tag already exists"

bash tests/run-all.sh || refuse "tests/run-all.sh failed"

if [ "$dry" -eq 1 ]; then
  echo "dry run: would tag $tag at $(git rev-parse --short HEAD)"
  echo "dry run: would push $tag to origin"
  exit 0
fi
git tag "$tag" || { echo "git tag failed" >&2; exit 3; }
git push origin "$tag" || { echo "git push failed (tag $tag exists locally)" >&2; exit 3; }
echo "released $tag"
