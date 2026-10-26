#!/usr/bin/env bash
# Cut a release of this repository (maintainers only): verify, run the suite, tag, push the tag.
#   tools/release.sh vX.Y.Z [--dry-run]
# Refuses unless tools/check-release.sh passes, the work tree is clean (untracked files count),
# HEAD is branch main and equals origin/main. Then runs tests/run-all.sh. With --dry-run it prints
# the steps it would take (would tag, would push) and changes nothing; otherwise it creates the
# tag and pushes it (CI then creates the release). Repo root = the parent of this script's directory.
# Signing: with a non-empty effective user.signingkey the tag is a signed annotated tag (git tag -s,
# format from gpg.format); if signing fails it exits 3 with no tag and nothing pushed, never an
# unsigned fallback. Without a key the tag is lightweight and one line says it is unsigned.
# It only reads the signing settings and never generates keys. See docs/development.md, "Signing release tags".
# Exit codes: 0 ok, 1 refused (check, tree, branch, origin or suite), 2 usage (not vX.Y.Z, extra
#             or unknown arguments), 3 environment (not a git repo, no origin, git failure, signing failed).
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
case "$tag" in *$'\n'*) echo "tag contains a newline" >&2; usage ;; esac   # grep matches per line
printf '%s' "$tag" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || { echo "tag '$tag' is not vX.Y.Z" >&2; usage; }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git work tree" >&2; exit 3; }

bash tools/check-release.sh "$tag" || refuse "tools/check-release.sh failed"

[ -z "$(git status --porcelain)" ] || refuse "work tree is not clean (untracked files count)"
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || refuse "HEAD is not on main"
# Read origin's main without updating local refs (also in --dry-run).
remote_main="$(git ls-remote origin refs/heads/main 2>/dev/null | cut -f1)"
[ -n "$remote_main" ] || { echo "cannot read main from origin" >&2; exit 3; }
[ "$(git rev-parse HEAD)" = "$remote_main" ] || refuse "main is not equal to origin/main"
git rev-parse -q --verify "refs/tags/$tag" >/dev/null && refuse "tag $tag already exists"

suite_log="$(mktemp "${TMPDIR:-/tmp}/pbrelease.XXXXXX")" || { echo "mktemp failed" >&2; exit 3; }
trap 'rm -f "$suite_log"' EXIT
bash tests/run-all.sh 2>&1 | tee "$suite_log"; suite_rc=${PIPESTATUS[0]}   # live output, run-all's status
[ "$suite_rc" -eq 0 ] || refuse "tests/run-all.sh failed"
# README test counts (badge, "**N passing**", "N tests, run in sandboxes") must equal passed + skipped.
total="$(grep -E '^[^[:space:]]+\.sh: [0-9]+ passed, [0-9]+ failed' "$suite_log" | grep -oE '[0-9]+ passed, [0-9]+ failed(, [0-9]+ skipped)?' |
  awk '{ t += $1; if (NF >= 6) t += $5 } END { print t + 0 }')"
if [ -r README.md ]; then
  for n in $(grep -oE 'badge/tests-[0-9]+|\*\*[0-9]+ passing\*\*|[0-9]+ tests, run in sandboxes' README.md | grep -oE '[0-9]+' ); do
    [ "$n" = "$total" ] || refuse "README.md test count is wrong: expected $total (the suite ran $total, passed + skipped), found $n"
  done
fi

if [ "$dry" -eq 1 ]; then
  echo "dry run: would tag $tag at $(git rev-parse --short HEAD)"
  echo "dry run: would push $tag to origin"
  exit 0
fi
signkey="$(git config --get user.signingkey 2>/dev/null || true)"
if [ -n "$signkey" ]; then
  # git 2.43 with gpg.format=ssh and a missing key file prints an error, exits 0 and leaves an unsigned
  # annotated tag, so check the tag object for a signature block as well as the exit status.
  sign_ok=1
  git tag -s -m "$tag" "$tag" || sign_ok=0
  if [ "$sign_ok" -eq 1 ]; then
    git cat-file tag "$tag" 2>/dev/null | LC_ALL=C grep -Eq '^-----BEGIN (SSH|PGP|SIGNED MESSAGE)' || sign_ok=0
  fi
  if [ "$sign_ok" -eq 0 ]; then
    git rev-parse -q --verify "refs/tags/$tag" >/dev/null && git tag -d "$tag" >/dev/null 2>&1
    echo "signing failed for tag $tag (user.signingkey is set); no tag created, nothing pushed" >&2
    exit 3
  fi
else
  git tag "$tag" || { echo "git tag failed" >&2; exit 3; }
fi
git push origin "$tag" || { echo "git push failed (tag $tag exists locally)" >&2; exit 3; }
[ -n "$signkey" ] || echo "note: tag $tag is unsigned (no user.signingkey; see docs/development.md, Signing release tags)"
echo "released $tag"
