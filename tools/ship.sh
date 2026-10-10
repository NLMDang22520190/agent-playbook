#!/usr/bin/env bash
# Ship a release in one command: merge the PR, tag it, wait for the tag's CI, update the local installs.
#   tools/ship.sh PR vX.Y.Z [--yes]
# Steps: PR must be OPEN and CLEAN (checks green, mergeable) -> ask, merge (merge commit, delete branch)
# -> main up to date -> tools/release.sh --dry-run -> ask, tools/release.sh -> wait for the tag's CI run
# -> the GitHub Release exists -> ./install.sh update --yes.
# Questions need a terminal on stdin; --yes answers them (use only when the user already said yes).
# Exit: 0 shipped, 1 refused or a step failed (release.sh's own status is passed on), 2 usage,
#       3 cannot enter the repository.
# Waiting for the tag's CI run: PB_SHIP_WAIT_TRIES (default 12) x PB_SHIP_WAIT_SECS (default 5).
set -u
cd "$(dirname "$0")/.." || exit 3

usage() { echo "usage: tools/ship.sh PR vX.Y.Z [--yes]" >&2; exit 2; }
step() { printf '== %s\n' "$1"; }
fail() { echo "ship refused: $1" >&2; exit 1; }

yes=0; pr=""; tag=""
for a in "$@"; do
  case "$a" in
    --yes) yes=1 ;;
    -*) usage ;;
    *) if [ -z "$pr" ]; then pr="$a"; elif [ -z "$tag" ]; then tag="$a"; else usage; fi ;;
  esac
done
[ -n "$pr" ] && [ -n "$tag" ] || usage
case "$pr" in *[!0123456789]*) usage ;; esac
case "$tag" in *$'\n'*) usage ;; esac
printf '%s' "$tag" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || usage
tries="${PB_SHIP_WAIT_TRIES:-12}"; secs="${PB_SHIP_WAIT_SECS:-5}"
case "$tries" in '' | *[!0123456789]*) usage ;; esac
case "$secs" in '' | *[!0123456789]*) usage ;; esac

ask() { # question -> 0 on y/yes; refuses without a terminal
  [ "$yes" = 1 ] && return 0
  [ -t 0 ] || fail "'$1' needs an answer and stdin is not a terminal (pass --yes only if the user agreed)"
  local ans=""
  printf '%s [y/N] ' "$1"
  IFS= read -r ans || ans=""
  case "$ans" in y | Y | yes | YES | Yes) return 0 ;; esac
  return 1
}

# a dirty tree would make the local part of the merge (switch, pull, delete branch) fail after GitHub merged
[ -z "$(git status --porcelain)" ] || fail "work tree is not clean (commit or stash first)"
# merge from main: on a detached HEAD (left by install.sh update) gh merges on GitHub, then fails locally
cur="$(git symbolic-ref -q --short HEAD || echo 'detached HEAD')"
if [ "$cur" != main ]; then
  step "switch to main (was $cur)"
  git switch -q main || fail "cannot switch to main (checked out in another worktree?)"
fi

step "check PR #$pr"
st="$(gh pr view "$pr" --json state,mergeStateStatus --jq '.state + " " + .mergeStateStatus')" || fail "cannot read PR #$pr"
set -- $st
[ "${1:-}" = OPEN ] && [ "${2:-}" = CLEAN ] || fail "PR #$pr is ${1:-?}/${2:-?}, needs OPEN/CLEAN (checks green, mergeable)"

ask "merge PR #$pr?" || fail "not merged (answer was not yes)"
step "merge PR #$pr"
gh pr merge "$pr" --merge --delete-branch || fail "gh pr merge $pr failed"

step "update main"
git switch -q main && git pull -q --ff-only || fail "could not bring main up to date"

step "release $tag (dry run)"
bash tools/release.sh "$tag" --dry-run; rc=$?
[ "$rc" -eq 0 ] || { echo "ship stopped: tools/release.sh --dry-run exited $rc" >&2; exit "$rc"; }
ask "tag and push $tag?" || fail "not tagged (answer was not yes)"
step "release $tag"
bash tools/release.sh "$tag"; rc=$?
[ "$rc" -eq 0 ] || { echo "ship stopped: tools/release.sh exited $rc" >&2; exit "$rc"; }

step "wait for the CI run of $tag"
sha="$(git rev-parse "$tag^{commit}" 2>/dev/null)" || fail "tag $tag not found locally after release.sh"
run=""; n=0
while [ "$n" -lt "$tries" ]; do   # the run can take a few seconds to appear; only the run for this tag's commit
  run="$(gh run list --branch "$tag" --commit "$sha" --event push --limit 1 --json databaseId --jq '.[0].databaseId // empty')"
  [ "$run" = null ] && run=""
  [ -n "$run" ] && break
  n=$((n + 1)); [ "$n" -lt "$tries" ] && sleep "$secs"
done
[ -n "$run" ] || fail "no CI run found for $tag (commit $sha)"
gh run watch "$run" --exit-status || fail "CI run $run for $tag failed"

step "check the release"
gh release view "$tag" >/dev/null || fail "GitHub Release $tag not found"

step "update the installs"
./install.sh update --yes || fail "install.sh update failed"
# install.sh update checks out the tag; the development checkout goes back to main
git switch -q main || fail "installed, but could not switch back to main"
echo "back on branch main"
echo "shipped $tag"
