#!/usr/bin/env bash
# Ship a release in one command: merge the PR, tag it, wait for the tag's CI, update the local installs.
#   tools/ship.sh PR vX.Y.Z [--yes] [--auto]
# --auto: an OPEN PR whose checks are still running gets GitHub auto-merge and ship stops; run it again
# after GitHub merged. A PR that is already MERGED is released when its merge commit is on origin/main.
# Steps: PR must be OPEN and CLEAN (checks green, mergeable) -> pre-merge gate: PR contains origin/main and
# tools/release-gate.sh --check <PR head> passes (also before arming --auto) -> ask, merge (merge commit, delete branch)
# -> main up to date -> tools/release.sh --dry-run -> ask, tools/release.sh -> wait for the tag's CI run
# -> the GitHub Release exists -> ./install.sh update --yes.
# Questions need a terminal on stdin; --yes answers them (use only when the user already said yes).
# The dry run always runs, also with --yes: --yes therefore runs the release.sh checks twice (dry run, then the
# real run) and the full suite twice when CI tree reuse (T7) does not apply.
# Exit: 0 shipped, 1 refused or a step failed (release.sh's own status is passed on), 2 usage,
#       3 cannot enter the repository.
# Eval guard (advice only): when skill text changed since the previous release, ship prints
# "eval guard: <capped run-evals command>" before it tags and again at the end. It never runs the command.
# Log: stdout and stderr are also written to .agents/handoff/ship-<tag>-<YYYYMMDD-HHMMSS>.log (PB_SHIP_LOG=<file>
# overrides; usage errors write none). Step lines read "== [HH:MM:SS +Ns] title" (N = seconds since ship started);
# a successful ship ends with "total time: Ns".
# Gate once per sha: ship creates a temporary directory, exports it as PB_GATE_CACHE_DIR and removes it on exit, so release.sh
# (dry run, then the real run on the same HEAD) calls `release-gate.sh --check HEAD` once; a failing gate is never cached.
# Waiting for the tag's CI run: PB_SHIP_WAIT_TRIES (default 12) x PB_SHIP_WAIT_SECS (default 5).
set -u
# The whole body is one function called on the last line: `git pull` below rewrites this file while
# it runs, and bash reads a script as it goes, so the rest of the old file must already be parsed.
main() {
  cd "$(dirname "$0")/.." || exit 3

  usage() { echo "usage: tools/ship.sh PR vX.Y.Z [--yes] [--auto]" >&2; exit 2; }
  t0=$SECONDS
  step() { printf '== [%s +%ss] %s\n' "$(date +%H:%M:%S)" "$((SECONDS - t0))" "$1"; }
  fail() { echo "ship refused: $1" >&2; exit 1; }

  yes=0; auto=0; pr=""; tag=""
  for a in "$@"; do
    case "$a" in
      --yes) yes=1 ;;
      --auto) auto=1 ;;
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

  # log: from here on (usage errors write none) stdout and stderr also go to a log file; stdin stays the terminal
  logf="${PB_SHIP_LOG:-.agents/handoff/ship-$tag-$(date +%Y%m%d-%H%M%S).log}"
  case "$logf" in */*) mkdir -p "${logf%/*}" 2>/dev/null || fail "cannot create the directory of the log $logf" ;; esac
  : >> "$logf" 2>/dev/null || fail "cannot write the log $logf"
  exec > >(tee -a "$logf") 2>&1
  tpid=$!
  # on every exit: close our stdout/stderr so tee sees EOF, then wait for it, so the last lines reach the log
  # (the exit status is unchanged: the trap ends with `true`)
  # gate cache: one temporary directory for this ship, removed on every exit (the same trap, extended)
  gate_cache="$(mktemp -d "${TMPDIR:-/tmp}/pbgate.XXXXXX" 2>/dev/null)" || gate_cache=""
  [ -z "$gate_cache" ] || export PB_GATE_CACHE_DIR="$gate_cache"
  trap '[ -z "$gate_cache" ] || rm -rf "$gate_cache"; exec >&- 2>&-; [ -z "$tpid" ] || wait "$tpid" 2>/dev/null; true' EXIT

  # repo: PB_GATE_REPO, else OWNER/REPO parsed from the origin URL (the same parsing as ci_repo in tools/release.sh; copied here
  # because ship.sh must stay self-contained). Every gh call below goes to this repo.
  repo="${PB_GATE_REPO:-}"
  if [ -z "$repo" ]; then
    url="$(git remote get-url origin 2>/dev/null)"
    repo="$(printf '%s' "$url" | sed -n 's#^.*github\.com[:/]\([^/][^/]*/[^/][^/]*\)$#\1#p' | sed 's#\.git$##; s#/$##')"
  fi
  [ -n "$repo" ] || fail "cannot work out OWNER/REPO from PB_GATE_REPO or the origin URL"
  export GH_REPO="$repo"
  # preflight, before anything is changed: --auto needs GraphQL (a per-repo query), every run needs REST for the PR and for
  # the Actions runs that the steps after the merge and the tag read (nothing can be undone after the merge)
  if [ "$auto" = 1 ]; then
    gh api graphql -f query="query{repository(owner:\"${repo%%/*}\",name:\"${repo#*/}\"){id}}" >/dev/null 2>&1 ||
      fail "--auto needs the GitHub GraphQL API, which is not reachable here; run without --auto, or from a machine with GraphQL access"
  fi
  rest_fail=0; rest_err=""
  if prjson="$(gh api "repos/$repo/pulls/$pr" 2>&1)"; then
    rest_err="$(gh api "repos/$repo/actions/runs?per_page=1" 2>&1 >/dev/null)" || rest_fail=1
  else
    rest_fail=1; rest_err="$prjson"
  fi
  [ "$rest_fail" = 0 ] || fail "the GitHub REST API is not reachable for $repo ($(printf '%s' "${rest_err:-no detail}" | head -n 1))"

  # shard_hint: after a green release, say when the Windows shards of the main run were unbalanced
  # (longest > 1.5 x shortest) so tests/shard-weights gets refreshed; missing data says nothing.
  # A main push that reused a tested tree skipped its shards (fewer than 2 completed shard jobs): then
  # tools/ci-tree-tested.sh names the PR run that tested the same tree, and that run is the data source.
  shard_hint() {
    local hs hr hj out wrc ndone ci
    hs="$(git rev-parse "$tag^{commit}" 2>/dev/null)" || return 0
    hr="$(gh run list --branch main --event push --commit "$hs" --limit 1 --json databaseId --jq '.[0].databaseId // empty' 2>/dev/null)" || return 0
    case "$hr" in '' | null | *[!0123456789]*) return 0 ;; esac
    hj="$(gh run view "$hr" --json jobs 2>/dev/null)" || return 0
    ndone="$(printf '%s' "$hj" | node -e 'let s = ""; process.stdin.on("data", d => s += d).on("end", () => { try { let n = 0; for (const j of JSON.parse(s).jobs || []) { if (/^windows shard \d+\/\d+$/.test(j.name || "") && j.conclusion === "success" && j.completedAt && !/^0001-/.test(j.completedAt)) n++ } console.log(n) } catch (e) {} })' 2>/dev/null)" || ndone=""
    case "$ndone" in '' | *[!0123456789]*) return 0 ;; esac
    if [ "$ndone" -lt 2 ]; then
      ci="$(bash tools/ci-tree-tested.sh --repo "$repo" "$hs" 2>/dev/null)" || ci=""
      case "$ci" in '' | *[!0123456789]*) return 0 ;; esac
      hr="$ci"
      hj="$(gh run view "$hr" --json jobs 2>/dev/null)" || return 0
    fi
    out="$(printf '%s' "$hj" | node -e 'let s = ""; process.stdin.on("data", d => s += d).on("end", () => { try { const d = []; for (const j of JSON.parse(s).jobs || []) { if (!/^windows shard \d+\/\d+$/.test(j.name || "") || !j.completedAt || /^0001-/.test(j.completedAt)) continue; const x = (Date.parse(j.completedAt) - Date.parse(j.startedAt)) / 1000; if (x >= 0) d.push(Math.round(x)) } if (d.length < 2) return; const lo = Math.min(...d), hi = Math.max(...d); if (hi > 1.5 * lo) console.log("shards unbalanced (" + lo + " s .. " + hi + " s): run tools/shard-weights.sh " + process.argv[1]) } catch (e) {} })' "$hr" 2>/dev/null)" || true
    [ -n "$out" ] || return 0
    printf '%s\n' "$out"
    # unbalanced: write fresh weights next to the handoff files; never commit, push or edit tests/shard-weights
    mkdir -p .agents/handoff 2>/dev/null || return 0
    wrc=0
    bash tools/shard-weights.sh "$hr" --out .agents/handoff/shard-weights.next >/dev/null 2>&1 || wrc=$?
    if [ "$wrc" -eq 0 ]; then
      echo "shard weights refreshed: copy .agents/handoff/shard-weights.next to tests/shard-weights in the next PR"
    else
      echo "shard weights not refreshed (shard-weights.sh exit $wrc)"
    fi
  }

  # eval_hint: the capped command that checks the skill wording changed since the previous release (printed, never run)
  eval_hint=""
  find_eval_hint() {
    local msha prev g
    eval_hint=""
    msha="HEAD"
    if [ "$merged" = 1 ] && git rev-parse -q --verify "$oid^{commit}" >/dev/null 2>&1; then msha="$oid"; fi
    prev="$(git describe --tags --abbrev=0 --match 'v[0-9]*' "$msha^" 2>/dev/null)" || prev=""
    [ -n "$prev" ] || return 0
    [ -f tools/eval-guard.sh ] || return 0
    g="$(bash tools/eval-guard.sh --base "$prev" 2>/dev/null)" || return 0
    eval_hint="$(printf '%s
' "$g" | grep '^bash evals/run-evals.sh ' | head -n 1)"
    return 0
  }

  ask() { # question -> 0 on y/yes; refuses without a terminal
    [ "$yes" = 1 ] && return 0
    [ -t 0 ] || fail "'$1' needs an answer and stdin is not a terminal (pass --yes only if the user agreed)"
    local ans=""
    printf '%s [y/N] ' "$1"
    IFS= read -r ans || ans=""
    case "$ans" in y | Y | yes | YES | Yes) return 0 ;; esac
    return 1
  }

  # (the ship log itself, when it lies inside the repository, does not count as dirt)
  # a dirty tree would make the local part of the merge (switch, pull, delete branch) fail after GitHub merged
  # exempt only the log file itself: path relative to the repo root, and only while untracked ("?? <path>").
  # -z gives unquoted NUL-separated entries (paths with spaces are not quoted).
  # the repo-relative path comes from git itself (--show-prefix), never from comparing path spellings
  # (Git Bash spells the same directory differently in pwd -P and --show-toplevel).
  logdir="."; [ "$logf" = "${logf##*/}" ] || logdir="${logf%/*}"; [ -n "$logdir" ] || logdir="/"
  logrel=""
  if prefix="$(git -C "$logdir" rev-parse --show-prefix 2>/dev/null)"; then logrel="${prefix}${logf##*/}"; fi
  dirty=""
  while IFS= read -r -d '' ent; do
    [ "$ent" = "?? $logrel" ] || dirty=1
  done < <(git status --porcelain -z --untracked-files=all)
  [ -z "$dirty" ] || fail "work tree is not clean (commit or stash first)"
  # merge from main: on a detached HEAD (left by install.sh update) gh merges on GitHub, then fails locally
  cur="$(git symbolic-ref -q --short HEAD || echo 'detached HEAD')"
  if [ "$cur" != main ]; then
    step "switch to main (was $cur)"
    git switch -q main || fail "cannot switch to main (checked out in another worktree?)"
  fi

  # pre-merge check (OPEN PR): the head contains origin/main and the release gate passed for that exact commit
  pre_merge_check() {
    local gout
    [ -n "$head" ] || fail "cannot read PR #$pr head"
    git fetch -q origin main || fail "cannot fetch origin main"
    git fetch -q origin "refs/pull/$pr/head" 2>/dev/null || git fetch -q origin "$headref" 2>/dev/null ||
      fail "cannot fetch the head of PR #$pr"
    git merge-base --is-ancestor origin/main "$head" 2>/dev/null ||
      fail "PR is not up to date with main: update it and re-run the gate"
    gout="$(bash tools/release-gate.sh --check "$head" 2>&1)" || fail "release gate: $(printf %s "$gout" | head -n 1)"
  }

  step "check PR #$pr"
  # the PR JSON read by the preflight (REST): state, merge state, merge commit (only when merged), head sha and ref, head repo, base repo and ref
  st="$(printf '%s' "$prjson" | node -e 'let s = ""; process.stdin.on("data", d => s += d).on("end", () => { try { const p = JSON.parse(s); const v = x => (x === undefined || x === null || x === "" ? "-" : String(x)); const h = p.head || {}, b = p.base || {}; console.log([p.merged === true ? "MERGED" : p.state === "open" ? "OPEN" : "CLOSED", String(p.mergeable_state || "unknown").toUpperCase(), p.merged === true ? v(p.merge_commit_sha) : "-", v(h.sha), v(h.ref), v(h.repo && h.repo.full_name), v(b.repo && b.repo.full_name), v(b.ref)].join(" ")) } catch (e) { process.exit(1) } })')" || fail "cannot read PR #$pr"
  set -- $st
  state="${1:-}"; mstate="${2:-}"; oid="${3:-}"; head="${4:-}"; headref="${5:-}"; headrepo="${6:-}"; baserepo="${7:-}"; baseref="${8:-}"
  [ "$oid" != - ] || oid=""
  [ "$head" != - ] || head=""
  merged=0
  if [ "$state" = MERGED ]; then
    # merged already (e.g. by GitHub auto-merge): release it if its merge commit is on origin/main
    [ -n "$oid" ] && [ "$oid" != null ] || fail "PR #$pr is MERGED but has no merge commit"
    git fetch -q origin || fail "cannot fetch origin"
    git merge-base --is-ancestor "$oid" origin/main 2>/dev/null ||
      fail "PR #$pr merge commit $oid is not on origin/main"
    step "PR #$pr already merged (merge commit $oid is on origin/main)"
    merged=1
  elif [ "$state" = OPEN ] && [ "$mstate" != CLEAN ] && [ "$auto" = 1 ]; then
    pre_merge_check
    # checks still running: let GitHub merge when they pass (auto-merge must be allowed on the repo)
    gh pr merge "$pr" --auto --merge --delete-branch --match-head-commit "$head" || fail "gh pr merge $pr --auto failed"
    echo "auto-merge enabled for PR #$pr: GitHub will merge when the checks pass; then run tools/ship.sh $pr $tag again to release"
    exit 0
  elif [ "$state" != OPEN ] || [ "$mstate" != CLEAN ]; then
    fail "PR #$pr is ${state:-?}/${mstate:-?}, needs OPEN/CLEAN (checks green, mergeable), or --auto"
  fi

  if [ "$merged" = 0 ]; then
    pre_merge_check
    ask "merge PR #$pr?" || fail "not merged (answer was not yes)"
    step "merge PR #$pr"
    gh api -X PUT "repos/$repo/pulls/$pr/merge" -f merge_method=merge -f sha="$head" >/dev/null || fail "merging PR #$pr failed (gh api PUT pulls/$pr/merge)"
    # delete the head branch only when it lives in the target repo and is not the base branch
    if [ "$headrepo" = "$repo" ] && [ "$baserepo" = "$repo" ] && [ "$headref" != - ] && [ "$headref" != "$baseref" ]; then
      gh api -X DELETE "repos/$repo/git/refs/heads/$headref" >/dev/null 2>&1 || echo "warning: could not delete the branch $headref"
    fi
  fi

  step "update main"
  git switch -q main && git pull -q --ff-only || fail "could not bring main up to date"
  find_eval_hint
  [ -z "$eval_hint" ] || echo "eval guard: $eval_hint"

  step "release $tag (dry run)"
  bash tools/release.sh "$tag" --dry-run; rc=$?
  [ "$rc" -eq 0 ] || { echo "ship stopped: tools/release.sh --dry-run exited $rc" >&2; exit "$rc"; }
  [ "$yes" = 1 ] || ask "tag and push $tag?" || fail "not tagged (answer was not yes)"
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
  shard_hint || true

  step "check the release"
  gh release view "$tag" >/dev/null || fail "GitHub Release $tag not found"

  step "update the installs"
  ./install.sh update --yes || fail "install.sh update failed"
  # install.sh update checks out the tag; the development checkout goes back to main
  git switch -q main || fail "installed, but could not switch back to main"
  echo "back on branch main"
  [ -z "$eval_hint" ] || echo "eval guard: $eval_hint"
  echo "shipped $tag"
  echo "total time: $((SECONDS - t0))s"
}

main "$@"; exit $?
