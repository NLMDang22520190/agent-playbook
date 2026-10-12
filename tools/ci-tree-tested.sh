#!/usr/bin/env bash
# Was the tree of a main commit already tested by a green run of the same repository's pull request?
#   tools/ci-tree-tested.sh SHA [--repo OWNER/NAME]
# Prints the id of a green PR run whose tree equals the tree of SHA, or prints nothing. Exit 0 either way,
# 2 on a usage error. Repository: --repo, else $GITHUB_REPOSITORY, else the current gh repository.
# Lookup (gh api only; never logs, artifacts or job outputs):
#   1. repos/R/commits/SHA/pulls: at most 5 PRs, each with its head sha H; a PR whose head repo is not R, or whose base.ref is not main, is skipped
#   2. repos/R/actions/workflows/test.yml/runs?event=pull_request&head_sha=H&status=success&per_page=10 (newest first);
#   3. repos/R/actions/runs/ID/jobs?filter=latest&per_page=100: test (ubuntu-latest), test (macos-latest),
#      test (windows-latest) and windows shard 1/4, 2/4, 3/4, 4/4 all concluded success (none skipped or missing); and in each
#      of the six suite jobs (not the aggregator) the step "Tests and static checks" (shards: "Tests and static checks
#      (shard)") completed with conclusion success, from the jobs API `steps`: a docs-only PR run reports the same seven green
#      jobs but its full step is skipped (a "Docs-only checks" step ran instead), and such a run is never reused
#   4. tree(SHA) equals tree(H) (repos/R/git/commits/X, .tree.sha)
#   5. the first parent P of SHA is an ancestor of H: repos/R/compare/P...H is "ahead" or "identical", behind_by 0
# A merge commit or a squash of an up-to-date PR passes; a rebase merge fails step 5 and so does a merge of a PR
# that is not up to date. Any gh error or malformed JSON prints nothing (the tests then run).
# The JSON is parsed with node. Bash 3.2 compatible.
set -u

usage() { echo "usage: ci-tree-tested.sh SHA [--repo OWNER/NAME]" >&2; exit 2; }

sha=""; repo=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) [ $# -ge 2 ] || usage; repo="$2"; shift 2 ;;
    -*) usage ;;
    *) [ -z "$sha" ] || usage; sha="$1"; shift ;;
  esac
done
[ -n "$sha" ] || usage
case "$sha" in *[!0-9a-fA-F]*) usage ;; esac
[ "${#sha}" -ge 7 ] && [ "${#sha}" -le 64 ] || usage
if [ -z "$repo" ]; then
  repo="${GITHUB_REPOSITORY:-}"
  [ -n "$repo" ] || repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" || repo=""
fi
case "$repo" in
  "" | */*/* | /* | */ | *[!A-Za-z0-9._/-]*) usage ;;
  */*) ;;
  *) usage ;;
esac

# everything below prints nothing on any problem
quiet_exit() { exit 0; }

read -r -d '' JS <<'EOF'
const fs = require("fs");
const mode = process.argv[1];
const arg = process.argv[2] || "";
let d;
try { d = JSON.parse(fs.readFileSync(0, "utf8")); } catch (e) { process.exit(1); }
const hex = (s) => typeof s === "string" && /^[0-9a-fA-F]{7,64}$/.test(s);
const out = [];
if (mode === "pulls") {
  if (!Array.isArray(d)) process.exit(1);
  for (const p of d.slice(0, 5)) {
    const h = p && p.head;
    if (!h || !hex(h.sha) || !h.repo || h.repo.full_name !== arg) continue;
    // the merged PR must have targeted main (the run own list of PRs is empty after a merge, so it is not used)
    if (!p.base || p.base.ref !== "main") continue;
    out.push(h.sha);
  }
} else if (mode === "runs") {
  if (!d || !Array.isArray(d.workflow_runs)) process.exit(1);
  for (const r of d.workflow_runs.slice(0, 10)) {
    if (!r || r.conclusion !== "success" || r.status !== "completed") continue;
    if (r.head_sha !== undefined && r.head_sha !== arg) continue;
    if (!/^[0-9]+$/.test(String(r.id))) continue;
    out.push(String(r.id));
  }
} else if (mode === "jobs") {
  if (!d || !Array.isArray(d.jobs)) process.exit(1);
  const need = ["test (ubuntu-latest)", "test (macos-latest)", "test (windows-latest)",
    "windows shard 1/4", "windows shard 2/4", "windows shard 3/4", "windows shard 4/4"];
  for (const n of need) {
    const js = d.jobs.filter((j) => j && j.name === n);
    if (js.length === 0 || !js.every((j) => j.status === "completed" && j.conclusion === "success")) process.exit(1);
    const full = n === "test (windows-latest)" ? "" : n.indexOf("windows shard") === 0 ? "Tests and static checks (shard)" : "Tests and static checks";
    if (full && !js.every((j) => Array.isArray(j.steps) && j.steps.some((s) => s && s.name === full && s.status === "completed" && s.conclusion === "success"))) process.exit(1);
  }
} else if (mode === "commit") {
  if (!d || !d.tree || !hex(d.tree.sha)) process.exit(1);
  const par = Array.isArray(d.parents) && d.parents[0] && hex(d.parents[0].sha) ? d.parents[0].sha : "-";
  out.push(d.tree.sha + " " + par);
} else if (mode === "compare") {
  if (!d || (d.status !== "ahead" && d.status !== "identical") || d.behind_by !== 0) process.exit(1);
} else {
  process.exit(1);
}
if (out.length) console.log(out.join("\n"));
EOF

pj() { node -e "$JS" -- "$@"; } # parse stdin JSON; $1 = mode, $2 = argument

api() { gh api "$1" 2>/dev/null; } # exit non-zero on any gh error

pulls="$(api "repos/$repo/commits/$sha/pulls")" || quiet_exit
heads="$(printf '%s' "$pulls" | pj pulls "$repo")" || quiet_exit

sha_tree=""; sha_parent=""; have_sha=0
for h in $heads; do
  runs="$(api "repos/$repo/actions/workflows/test.yml/runs?event=pull_request&head_sha=$h&status=success&per_page=10")" || quiet_exit
  ids="$(printf '%s' "$runs" | pj runs "$h")" || quiet_exit
  for id in $ids; do
    jobs="$(api "repos/$repo/actions/runs/$id/jobs?filter=latest&per_page=100")" || quiet_exit
    printf '%s' "$jobs" | pj jobs >/dev/null || continue
    # the jobs are green: check the tree and the ancestry once for this PR; a failure moves on to the next PR
    if [ "$have_sha" = 0 ]; then
      c="$(api "repos/$repo/git/commits/$sha")" || quiet_exit
      cc="$(printf '%s' "$c" | pj commit)" || quiet_exit
      sha_tree="${cc% *}"; sha_parent="${cc#* }"; have_sha=1
    fi
    c="$(api "repos/$repo/git/commits/$h")" || quiet_exit
    hc="$(printf '%s' "$c" | pj commit)" || quiet_exit
    [ "${hc% *}" = "$sha_tree" ] || break
    [ "$sha_parent" != "-" ] || break
    cmp="$(api "repos/$repo/compare/$sha_parent...$h")" || quiet_exit
    printf '%s' "$cmp" | pj compare >/dev/null || break
    printf '%s\n' "$id"
    exit 0
  done
done
exit 0
