#!/usr/bin/env bash
# Tests for tools/ship.sh T11 (v0.38.0, docs/v0.38-t11-spec.md): ship works where only the REST API is reachable. The PR is read with
# `gh api repos/O/R/pulls/N` (raw REST JSON), merged with `gh api -X PUT repos/O/R/pulls/N/merge -f merge_method=merge -f sha=HEAD`, the head branch is
# deleted with `gh api -X DELETE repos/O/R/git/refs/heads/REF`; only --auto still uses `gh pr merge --auto` (GraphQL) and then probes GraphQL first.
# Every run first probes REST (the PR read and actions/runs), before anything is changed. OWNER/REPO is PB_GATE_REPO, else parsed from the origin URL.
# Shared setup (the fake gh answers REST and refuses every `gh pr ...` except `gh pr merge --auto`): ship-fixture.sh. AC11 (diff check) is for the reviewer.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/ship-fixture.sh"

# line number of the first log line matching $1 (empty when none)
first_line() { grep -n -- "$1" "$FAKE_LOG" | head -n 1 | cut -d: -f1; }
before() { # name A B -> the first log line matching A comes before the first matching B
  local a b; a="$(first_line "$2")"; b="$(first_line "$3")"
  if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then t_ok "$1"; else t_bad "$1" "line of '$2' = [$a], line of '$3' = [$b]"; fi
}
gh_pr_lines() { grep -c '^gh pr ' "$FAKE_LOG" || true; }
graphql_lines() { grep -c '^gh api graphql' "$FAKE_LOG" || true; }
runs_lines() { grep -c '^gh api .*/actions/runs' "$FAKE_LOG" || true; }
writes_logged() { grep -cE '^gh api .*(-X|--method)[ =](PUT|DELETE|PATCH|POST)|^gh pr merge' "$FAKE_LOG" || true; }
cur_branch() { git -C "$F/repo" rev-parse --abbrev-ref HEAD; }
R3_MSG="ship refused: --auto needs the GitHub GraphQL API, which is not reachable here; run without --auto, or from a machine with GraphQL access"

echo "AC1 direct merge through REST: GET the PR, PUT merge with merge_method=merge and sha=<head>, DELETE the branch, then on as before"
fx
pr_ahead
H1="$(pr_head)"
sh_run 12 v1.2.3 --yes
assert_rc "AC1 open + clean PR, --yes: exit 0" 0
assert_eq "AC1 the flow is the full one" "$FULL_YES" "$(steps)"
assert_eq "AC1 exactly one PUT merge, to repos/o/r/pulls/12/merge, with merge_method=merge and the sha pair (head sha of the PR)" \
  "gh api -X PUT repos/o/r/pulls/12/merge -f merge_method=merge -f sha=$H1" "$(put_lines)"
assert_eq "AC1 exactly one DELETE, of the head branch feat/x" "gh api -X DELETE repos/o/r/git/refs/heads/feat/x" "$(del_lines)"
before "AC1 the PR is read before the merge" '^gh api repos/o/r/pulls/12' '^gh api .*PUT'
before "AC1 the merge comes before the branch delete" '^gh api .*PUT' '^gh api .*DELETE'
before "AC1 the branch delete comes before release.sh" '^gh api .*DELETE' '^release.sh'
assert_eq "AC1 the gate was asked about the same head the PUT pins" "release-gate.sh --check $H1" "$(gate_calls)"
assert_eq "AC1 no 'gh pr' command at all in the log (they are GraphQL)" "0" "$(gh_pr_lines)"
assert_eq "AC1 the merge reached origin" "1" "$(origin_merges)"
assert_contains "AC1 shipped" "$OUT" "shipped v1.2.3"
echo "AC1 the same with the questions answered by a terminal is covered by test-ship-b.sh; PR 345 and another repo:"
fx
export FAKE_PR=345 FAKE_TAG=v10.20.30 PB_GATE_REPO=acme/widgets
sh_run 345 v10.20.30 --yes
assert_rc "AC1 PR 345 in acme/widgets: exit 0" 0
assert_contains "AC1 PR 345 in acme/widgets: PUT repos/acme/widgets/pulls/345/merge" "$(put_lines)" "gh api -X PUT repos/acme/widgets/pulls/345/merge "
assert_contains "AC1 PR 345 in acme/widgets: DELETE repos/acme/widgets/git/refs/heads/feat/x" "$(del_lines)" "repos/acme/widgets/git/refs/heads/feat/x"
assert_eq "AC1 PR 345: no 'gh pr' command" "0" "$(gh_pr_lines)"

echo "AC2 merged:true + merge_commit_sha on origin/main -> 'already merged' as before; an OPEN PR with a (trial) merge_commit_sha is not merged"
fx
merged_on_main
sh_run 12 v1.2.3 --yes
assert_rc "AC2 merged:true with its merge commit on origin/main: exit 0" 0
assert_eq "AC2 merged: no merge call, update main, release, CI, release check, install" "$MERGED_YES" "$(steps)"
assert_eq "AC2 merged: no PUT, no DELETE, no gh pr merge" "0" "$(writes_logged)"
assert_eq "AC2 merged: one '== ' line says the PR is already merged" "1" "$(printf '%s\n' "$OUT" | grep '^== ' | grep -ci 'already merged')"
assert_eq "AC2 merged: no 'gh pr' command" "0" "$(gh_pr_lines)"
echo "AC2 a payload shaped like PR #102 (closed, merged true, mergeable_state unknown): the merge state does not matter"
fx
export FAKE_PR=102
merged_on_main
export FAKE_GH_MERGE_STATE=UNKNOWN
sh_run 102 v1.2.3 --yes
assert_rc "AC2 PR #102 shape (closed/merged/unknown): exit 0" 0
assert_eq "AC2 PR #102 shape: the merged flow ran" "$MERGED_YES" "$(steps)"
echo "AC2 OPEN PR whose JSON carries a merge_commit_sha (GitHub's trial merge): not treated as merged, merged for real"
fx
export FAKE_GH_MERGE_COMMIT=0123456789abcdef0123456789abcdef01234567
sh_run 12 v1.2.3 --yes
assert_rc "AC2 OPEN + trial merge_commit_sha: exit 0 (the flow of an open PR)" 0
assert_eq "AC2 OPEN + trial merge_commit_sha: the full flow, with a merge" "$FULL_YES" "$(steps)"
assert_eq "AC2 OPEN + trial merge_commit_sha: one PUT merge" "1" "$(put_lines | wc -l | tr -d ' ')"
assert_not_contains "AC2 OPEN + trial merge_commit_sha: not announced as already merged" "$OUT" "already merged"
echo "AC2 OPEN PR whose trial merge_commit_sha IS on origin/main: still not merged (merged is false)"
fx
( cd "$F/work" && git pull -q --ff-only origin main >/dev/null 2>&1; MC0="$(git rev-parse HEAD)"; echo "$MC0" > "$F/mc0" )
export FAKE_GH_MERGE_COMMIT="$(cat "$F/mc0")"
sh_run 12 v1.2.3 --yes
assert_not_contains "AC2 OPEN + trial sha on origin/main: not announced as already merged" "$OUT" "already merged"
assert_eq "AC2 OPEN + trial sha on origin/main: one PUT merge (not skipped)" "1" "$(put_lines | wc -l | tr -d ' ')"

echo "AC3 not mergeable: the refusal names STATE/MSTATE in upper case, a null or missing mergeable_state is UNKNOWN"
for combo in "OPEN BLOCKED" "OPEN BEHIND" "OPEN DIRTY" "OPEN UNSTABLE" "OPEN DRAFT" "OPEN UNKNOWN" "OPEN NULL" "OPEN MISSING" "CLOSED CLEAN" "CLOSED UNKNOWN"; do
  fx
  st="${combo% *}"; ms="${combo#* }"
  export FAKE_GH_STATE="$st" FAKE_GH_MERGE_STATE="$ms"
  want_ms="$ms"; case "$ms" in NULL | MISSING) want_ms=UNKNOWN ;; esac
  sh_run 12 v1.2.3 --yes
  assert_rc "AC3 $combo: exit 1" 1
  assert_contains "AC3 $combo: PR #12 is $st/$want_ms, needs OPEN/CLEAN (checks green, mergeable), or --auto" "$OUT" "PR #12 is $st/$want_ms, needs OPEN/CLEAN (checks green, mergeable), or --auto"
  assert_eq "AC3 $combo: nothing merged, nothing released" "view" "$(steps)"
  assert_eq "AC3 $combo: no write call at all" "0" "$(writes_logged)"
done

echo "AC4 the PUT fails (405, 409, 422): refused, no DELETE, no release.sh"
for code in 405 409 422; do
  fx
  export FAKE_GH_FAIL="merge$code"
  sh_run 12 v1.2.3 --yes
  assert_rc "AC4 PUT merge fails with $code: exit 1" 1
  assert_contains "AC4 PUT merge fails with $code: 'ship refused:' line" "$OUT" "ship refused: "
  assert_eq "AC4 PUT merge fails with $code: the refusal names the merge" "1" "$(printf '%s\n' "$OUT" | grep '^ship refused: ' | grep -ci 'merge')"
  assert_eq "AC4 PUT merge fails with $code: the PUT was tried once" "1" "$(put_lines | wc -l | tr -d ' ')"
  assert_eq "AC4 PUT merge fails with $code: no DELETE" "" "$(del_lines)"
  assert_eq "AC4 PUT merge fails with $code: release.sh and install.sh not run" "0" "$(logged '^release.sh\|^install.sh')"
  assert_eq "AC4 PUT merge fails with $code: steps stop at the merge" "view merge" "$(steps)"
  assert_eq "AC4 PUT merge fails with $code: nothing reached origin's main" "0" "$(origin_merges)"
  assert_not_contains "AC4 PUT merge fails with $code: not claimed shipped" "$OUT" "shipped v1.2.3"
done

echo "AC5 the DELETE fails after a successful merge: one warning line, ship goes on and exits 0"
fx
export FAKE_GH_FAIL="delete"
sh_run 12 v1.2.3 --yes
assert_rc "AC5 DELETE fails: exit 0" 0
assert_eq "AC5 DELETE fails: the flow ran to the end" "$FULL_YES" "$(steps)"
assert_eq "AC5 DELETE fails: the DELETE was tried once" "1" "$(del_lines | wc -l | tr -d ' ')"
assert_eq "AC5 DELETE fails: exactly one warning line (a line saying 'warning', case-insensitive) [wording is not fixed by the spec]" "1" "$(printf '%s\n' "$OUT" | grep -ci 'warning')"
assert_contains "AC5 DELETE fails: shipped" "$OUT" "shipped v1.2.3"
echo "AC5 no DELETE for a fork head, a null head.repo, or a head branch equal to the target branch (the merge still happens)"
for case_ in "fork:FAKE_GH_HEAD_REPO=forker/r" "nullrepo:FAKE_GH_HEAD_REPO=null" "headmain:FAKE_GH_HEAD_REF=main"; do
  fx
  export "${case_#*:}"
  sh_run 12 v1.2.3 --yes
  assert_rc "AC5 ${case_%%:*}: exit 0" 0
  assert_eq "AC5 ${case_%%:*}: the PUT merge ran" "1" "$(put_lines | wc -l | tr -d ' ')"
  assert_eq "AC5 ${case_%%:*}: no DELETE call" "" "$(del_lines)"
  assert_eq "AC5 ${case_%%:*}: no warning either" "0" "$(printf '%s\n' "$OUT" | grep -ci 'warning')"
  assert_eq "AC5 ${case_%%:*}: the full flow ran" "$FULL_YES" "$(steps)"
done

echo "AC6 --auto with GraphQL unreachable: refused before the tree check, git switch, git fetch and any write; the sentence is in the log file"
fx
git -C "$F/repo" fetch -q origin 2>/dev/null
origin_advance
OM_BEFORE="$(git -C "$F/repo" rev-parse origin/main)"
printf 'dirt\n' > "$F/repo/untracked-dirt.txt"
export FAKE_GH_FAIL="graphql" FAKE_GH_MERGE_STATE=BLOCKED PB_SHIP_LOG="$F/ship.log"
sh_run 12 v1.2.3 --yes --auto
assert_rc "AC6 --auto, GraphQL fails: exit 1" 1
assert_contains "AC6 --auto, GraphQL fails: the exact sentence" "$OUT" "$R3_MSG"
assert_not_contains "AC6 --auto, GraphQL fails: refused before the dirty-tree check" "$OUT" "not clean"
assert_eq "AC6 --auto, GraphQL fails: the clone was not switched to main" "feat/x" "$(cur_branch)"
assert_eq "AC6 --auto, GraphQL fails: origin/main was not fetched" "$OM_BEFORE" "$(git -C "$F/repo" rev-parse origin/main)"
assert_eq "AC6 --auto, GraphQL fails: no write call (no PUT, DELETE, gh pr merge)" "0" "$(writes_logged)"
assert_eq "AC6 --auto, GraphQL fails: the sentence is in the log file too" "1" "$(grep -cF "$R3_MSG" "$F/ship.log" 2>/dev/null || true)"
assert_eq "AC6 --auto, GraphQL fails: no release, no install" "0" "$(logged '^release.sh\|^install.sh')"
unset PB_SHIP_LOG
echo "AC6 --auto with GraphQL fine: gh pr merge --auto ... --match-head-commit <head> as before"
fx
pr_ahead
HA="$(pr_head)"
export FAKE_GH_MERGE_STATE=BLOCKED
sh_run 12 v1.2.3 --yes --auto
assert_rc "AC6 --auto, GraphQL ok: exit 0" 0
assert_eq "AC6 --auto, GraphQL ok: the auto-merge call is unchanged" "$AUTO_MERGE_CALL" "$(merge_call)"
assert_contains "AC6 --auto, GraphQL ok: the call pins --match-head-commit <head sha>" "$(grep '^gh pr merge' "$FAKE_LOG")" "--match-head-commit $HA"
assert_eq "AC6 --auto, GraphQL ok: no PUT merge" "" "$(put_lines)"
assert_eq "AC6 --auto, GraphQL ok: the only 'gh pr' call is the auto-merge" "1" "$(gh_pr_lines)"
echo "AC6 --auto and the gh pr merge --auto call itself failing (the GraphQL probe was fine): refused, nothing else"
fx
export FAKE_GH_MERGE_STATE=BLOCKED FAKE_GH_FAIL="merge"
sh_run 12 v1.2.3 --yes --auto
assert_rc "AC6 --auto, gh pr merge --auto fails: exit 1" 1
assert_eq "AC6 --auto, gh pr merge --auto fails: view, merge only" "view merge" "$(steps)"

echo "AC7 no --auto: GraphQL is never probed; --auto: GraphQL and both REST probes are called"
fx
sh_run 12 v1.2.3 --yes
assert_rc "AC7 no --auto: exit 0" 0
assert_eq "AC7 no --auto: no 'gh api graphql' call" "0" "$(graphql_lines)"
assert_eq "AC7 no --auto: exactly one actions/runs probe (path: repos/o/r/actions/runs?per_page=1)" "1" "$(runs_lines)"
assert_contains "AC7 no --auto: the probe path" "$(grep '^gh api .*actions/runs' "$FAKE_LOG")" "repos/o/r/actions/runs?per_page=1"
before "AC7 the actions/runs probe comes before the merge" '^gh api .*actions/runs' '^gh api .*PUT'
before "AC7 the PR read comes before the merge" '^gh api repos/o/r/pulls/12' '^gh api .*PUT'
fx
export FAKE_GH_MERGE_STATE=BLOCKED
sh_run 12 v1.2.3 --yes --auto
assert_rc "AC7 --auto: exit 0" 0
assert_eq "AC7 --auto: one 'gh api graphql' call" "1" "$(graphql_lines)"
assert_eq "AC7 --auto: the actions/runs probe ran too" "1" "$(runs_lines)"
assert_contains "AC7 --auto: the GraphQL probe is a per-repo query (not viewer)" "$(grep '^gh api graphql' "$FAKE_LOG")" 'repository(owner:"o",name:"r")'
assert_not_contains "AC7 --auto: the GraphQL probe does not use viewer" "$(grep '^gh api graphql' "$FAKE_LOG")" "viewer"
before "AC7 --auto: the GraphQL probe comes before the merge" '^gh api graphql' '^gh pr merge'
echo "AC7 REST unreachable: refused before git switch and before every PUT/DELETE (a dirty tree is not even looked at)"
for word in prview runs; do
  for mode in plain auto; do
    fx
    printf 'dirt\n' > "$F/repo/untracked-dirt.txt"
    export FAKE_GH_FAIL="$word"
    flag=""; [ "$mode" = auto ] && flag="--auto"
    sh_run 12 v1.2.3 --yes $flag
    assert_rc "AC7 REST $word fails ($mode): exit 1" 1
    assert_contains "AC7 REST $word fails ($mode): 'ship refused: the GitHub REST API is not reachable for o/r ('" "$OUT" "ship refused: the GitHub REST API is not reachable for o/r ("
    assert_not_contains "AC7 REST $word fails ($mode): refused before the dirty-tree check" "$OUT" "not clean"
    assert_eq "AC7 REST $word fails ($mode): the clone was not switched" "feat/x" "$(cur_branch)"
    assert_eq "AC7 REST $word fails ($mode): no PUT, no DELETE, no gh pr merge" "0" "$(writes_logged)"
    assert_eq "AC7 REST $word fails ($mode): no release, no install" "0" "$(logged '^release.sh\|^install.sh')"
    assert_eq "AC7 REST $word fails ($mode): origin untouched" "0" "$(origin_merges)"
  done
done

echo "AC8 repository: PB_GATE_REPO, else the origin URL, else refused; never gh repo view"
fx
sh_run 12 v1.2.3 --yes
bad="$(grep '^gh api repos/\|^gh api -X [A-Z]* repos/' "$FAKE_LOG" | grep -vc 'repos/o/r/' || true)"
assert_eq "AC8 PB_GATE_REPO=o/r: every REST path is repos/o/r/..." "0" "$bad"
assert_eq "AC8 PB_GATE_REPO=o/r: there are REST calls" "1" "$([ "$(grep -c '^gh api .*repos/o/r/' "$FAKE_LOG")" -ge 4 ] && echo 1 || echo 0)"
assert_eq "AC8 no 'gh repo view'" "0" "$(logged '^gh repo view')"
fx
export PB_GATE_REPO=acme/widgets
sh_run 12 v1.2.3 --yes
assert_rc "AC8 PB_GATE_REPO=acme/widgets: exit 0" 0
assert_eq "AC8 PB_GATE_REPO=acme/widgets: no REST path of another repo" "0" "$(grep '^gh api .*repos/' "$FAKE_LOG" | grep -vc 'repos/acme/widgets/' || true)"
assert_contains "AC8 PB_GATE_REPO=acme/widgets: PUT repos/acme/widgets/pulls/12/merge" "$(put_lines)" "repos/acme/widgets/pulls/12/merge"
echo "AC8 no PB_GATE_REPO, origin is a path ending in github.com/o2/r2.git: repos/o2/r2/..."
fx
OB="$F/github.com/o2/r2.git"; mkdir -p "$F/github.com/o2"
git clone -q --mirror "$F/origin.git" "$OB" 2>/dev/null && git -C "$OB" symbolic-ref HEAD refs/heads/main
git -C "$F/repo" remote set-url origin "$OB"; git -C "$F/work" remote set-url origin "$OB"
export FAKE_ORIGIN_GIT="$OB"
probe="$(git -C "$F/repo" remote get-url origin 2>/dev/null | sed -n 's#^.*github\.com[:/]\([^/][^/]*/[^/][^/]*\)$#\1#p' | sed 's#\.git$##; s#/$##')"
assert_eq "AC8 fixture check: the origin URL parses as o2/r2 and main is fetchable" "o2/r2 $(git -C "$OB" rev-parse main)" "$probe $(git -C "$F/repo" ls-remote origin refs/heads/main | cut -f1)"
unset PB_GATE_REPO
sh_run 12 v1.2.3 --yes
assert_rc "AC8 origin .../github.com/o2/r2.git, no PB_GATE_REPO: exit 0" 0
assert_eq "AC8 origin URL: REST paths are repos/o2/r2/... (and no other repo)" "0" "$(grep '^gh api .*repos/' "$FAKE_LOG" | grep -vc 'repos/o2/r2/' || true)"
assert_contains "AC8 origin URL: PUT repos/o2/r2/pulls/12/merge" "$(put_lines)" "repos/o2/r2/pulls/12/merge"
assert_eq "AC8 origin URL: no 'gh repo view'" "0" "$(logged '^gh repo view')"
echo "AC8 repository unknown (no PB_GATE_REPO, origin is a plain path; also PB_GATE_REPO set but empty): refused at the start"
for setting in unset empty; do
  fx
  if [ "$setting" = unset ]; then unset PB_GATE_REPO; else export PB_GATE_REPO=""; fi
  printf 'dirt\n' > "$F/repo/untracked-dirt.txt"
  sh_run 12 v1.2.3 --yes
  assert_rc "AC8 repo unknown ($setting): exit 1" 1
  assert_contains "AC8 repo unknown ($setting): the exact sentence" "$OUT" "ship refused: cannot work out OWNER/REPO from PB_GATE_REPO or the origin URL"
  assert_not_contains "AC8 repo unknown ($setting): refused before the dirty-tree check" "$OUT" "not clean"
  assert_eq "AC8 repo unknown ($setting): the clone was not switched" "feat/x" "$(cur_branch)"
  assert_eq "AC8 repo unknown ($setting): no write call" "0" "$(writes_logged)"
  assert_eq "AC8 repo unknown ($setting): no gh repo view" "0" "$(logged '^gh repo view')"
  assert_eq "AC8 repo unknown ($setting): no release, no install" "0" "$(logged '^release.sh\|^install.sh')"
done
export PB_GATE_REPO=o/r

echo "AC9 every gh call carries GH_REPO=<repo>; tools/ci-tree-tested.sh gets --repo <repo>"
fx
export FAKE_SHARDS_7777=none FAKE_TREE_RUN=5555 FAKE_SHARDS_5555="300,100,200"   # the main push skipped its shards: ship asks ci-tree-tested.sh
sh_run 12 v1.2.3 --yes
assert_rc "AC9 full flow with the shard report: exit 0" 0
NGH="$(grep -c '^gh ' "$FAKE_LOG")"
assert_eq "AC9 every gh call was recorded with its GH_REPO" "$NGH" "$(wc -l < "$FAKE_LOG.ghrepo" | tr -d ' ')"
assert_eq "AC9 there were gh calls to check (REST, run list, run watch, release view)" "1" "$([ "$NGH" -ge 8 ] && echo 1 || echo 0)"
assert_eq "AC9 no gh call without GH_REPO=o/r" "0" "$(grep -vc '^GH_REPO=o/r gh ' "$FAKE_LOG.ghrepo" || true)"
assert_eq "AC9 the gh release view call was recorded, with GH_REPO=o/r" "1" "$(grep -c '^GH_REPO=o/r gh release view' "$FAKE_LOG.ghrepo")"
assert_contains "AC9 ci-tree-tested.sh is called with --repo o/r" "$(grep '^ci-tree-tested.sh' "$FAKE_LOG")" "--repo o/r"
echo "AC9 another repo: GH_REPO and --repo follow PB_GATE_REPO"
fx
export PB_GATE_REPO=acme/widgets FAKE_SHARDS_7777=none FAKE_TREE_RUN=5555 FAKE_SHARDS_5555="300,100,200"
sh_run 12 v1.2.3 --yes
assert_rc "AC9 acme/widgets: exit 0" 0
assert_eq "AC9 acme/widgets: no gh call without GH_REPO=acme/widgets" "0" "$(grep -vc '^GH_REPO=acme/widgets gh ' "$FAKE_LOG.ghrepo" || true)"
assert_contains "AC9 acme/widgets: ci-tree-tested.sh is called with --repo acme/widgets" "$(grep '^ci-tree-tested.sh' "$FAKE_LOG")" "--repo acme/widgets"
echo "AC9 a GH_REPO from the caller's environment does not win: ship sets it from PB_GATE_REPO"
fx
export GH_REPO=stale/other
sh_run 12 v1.2.3 --yes
unset GH_REPO
assert_rc "AC9 stale GH_REPO in the environment: exit 0" 0
assert_eq "AC9 stale GH_REPO in the environment: every gh call carries GH_REPO=o/r" "0" "$(grep -vc '^GH_REPO=o/r gh ' "$FAKE_LOG.ghrepo" || true)"

t_summary
