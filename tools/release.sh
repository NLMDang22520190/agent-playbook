#!/usr/bin/env bash
# Cut a release of this repository (maintainers only): verify, run the suite, tag, push the tag.
#   tools/release.sh vX.Y.Z [--dry-run] [--local-suite]
# Refuses unless tools/check-release.sh passes, the work tree is clean (untracked files count),
# HEAD is branch main and equals origin/main, and the release gate passes (`tools/release-gate.sh --check HEAD`: exit 0 goes on,
# 1 refuses with "release refused: release gate: <its first output line>", any other code exits 3; its output is printed, so
# --dry-run shows the gate outcome and exits 1 when it fails). The gate is checked before the suite and before any tag.
# Gate once per sha: with PB_GATE_CACHE_DIR set (an existing directory; tools/ship.sh sets it for one ship and removes it on exit) a
# PASS of the gate check is recorded as a file named by the full HEAD sha, and the next run on that sha prints "release gate: pass
# (cached for <short sha> in this ship)" instead of calling the gate; a refusal or an environment error is never cached. Without the
# variable (or with a missing directory) every run calls the gate.
# CI instead of the local suite: after the gate and before tests/run-all.sh it reads the check runs of exactly HEAD (REST only:
# `gh api --paginate repos/OWNER/REPO/commits/<sha>/check-runs`; OWNER/REPO is PB_GATE_REPO, else parsed from the origin URL). When there is
# at least one check run, none is pending and all concluded success, skipped or neutral, tests/run-all.sh and the README count check are
# skipped (one line each says so) unless --local-suite is given. In every other state (not green, no runs, gh missing, API error, unreadable
# JSON, unknown repository) the suite runs as before and one line says why; reading CI never fails the release by itself.
# Then runs tests/run-all.sh (unless CI is green, see above). With --dry-run it prints
# the steps it would take (would tag, would push) and changes nothing; otherwise it creates the
# tag and pushes it (CI then creates the release). Repo root = the parent of this script's directory.
# Signing: with a non-empty effective user.signingkey the tag is a signed annotated tag (git tag -s,
# format from gpg.format); if signing fails it exits 3 with no tag and nothing pushed, never an
# unsigned fallback. Without a key the tag is lightweight and one line says it is unsigned.
# It only reads the signing settings and never generates keys. See docs/development.md, "Signing release tags".
# Exit codes: 0 ok, 1 refused (check, tree, branch, origin, gate or suite), 2 usage (not vX.Y.Z, extra
#             or unknown arguments), 3 environment (not a git repo, no origin, git failure, signing failed, release gate exit
#             code other than 0 or 1).
set -u
cd "$(dirname "$0")/.." || exit 3

usage() { echo "usage: tools/release.sh vX.Y.Z [--dry-run] [--local-suite]" >&2; exit 2; }
refuse() { echo "release refused: $1" >&2; exit 1; }

tag=""; dry=0; local_suite=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1 ;;
    --local-suite) local_suite=1 ;;
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

head_sha="$(git rev-parse HEAD)"; head_short="$(git rev-parse --short HEAD)"
gate_cached=""
if [ -n "${PB_GATE_CACHE_DIR:-}" ] && [ -d "$PB_GATE_CACHE_DIR" ] && [ -f "$PB_GATE_CACHE_DIR/$head_sha" ]; then
  gate_cached=1; echo "release gate: pass (cached for $head_short in this ship)"
fi
if [ -z "$gate_cached" ]; then
  gate_out="$(bash tools/release-gate.sh --check HEAD 2>&1)"; gate_rc=$?
  case "$gate_rc" in
    0) printf '%s\n' "$gate_out"
       if [ -n "${PB_GATE_CACHE_DIR:-}" ] && [ -d "$PB_GATE_CACHE_DIR" ]; then : > "$PB_GATE_CACHE_DIR/$head_sha" 2>/dev/null || true; fi ;;
    1) refuse "release gate: $(printf '%s\n' "$gate_out" | head -n 1)" ;;
    *) echo "release gate exited $gate_rc: $(printf '%s\n' "$gate_out" | head -n 1)" >&2; exit 3 ;;
  esac
fi

# ci_state: prints "green" or the reason CI is not green on HEAD; never fails (a failed read is just "not green")
ci_state() {
  local repo url runs
  repo="${PB_GATE_REPO:-}"
  if [ -z "$repo" ]; then
    url="$(git remote get-url origin 2>/dev/null)"
    repo="$(printf '%s' "$url" | sed -n 's#^.*github\.com[:/]\([^/][^/]*/[^/][^/]*\)$#\1#p' | sed 's#\.git$##; s#/$##')"
  fi
  [ -n "$repo" ] || { echo "repository unknown"; return 0; }
  command -v gh >/dev/null 2>&1 || { echo "gh is not installed"; return 0; }
  command -v node >/dev/null 2>&1 || { echo "node is not installed"; return 0; }
  runs="$(gh api --paginate "repos/$repo/commits/$head_sha/check-runs" --jq '.check_runs[]' </dev/null 2>/dev/null)" || { echo "gh api failed"; return 0; }
  printf '%s\n' "$runs" | node -e '
const lines = require("fs").readFileSync(0, "utf8").split("\n").filter(Boolean);
const ok = new Set(["success", "skipped", "neutral"]);
let n = 0, pending = 0, bad = 0, junk = 0;
for (const l of lines) {
  let r; try { r = JSON.parse(l); } catch (x) { junk++; continue; }
  if (!r || typeof r !== "object") { junk++; continue; }
  n++;
  if (r.status !== "completed") pending++;
  else if (!ok.has(r.conclusion)) bad++;
}
if (junk) console.log("unreadable check run data");
else if (n === 0) console.log("no check runs");
else if (pending) console.log(pending + " check run(s) not finished");
else if (bad) console.log(bad + " check run(s) not successful");
else console.log("green");
' 2>/dev/null || echo "unreadable check run data"
}

suite_skipped=0
if [ "$local_suite" -eq 0 ]; then
  ci="$(ci_state)"; ci="$(printf '%s' "$ci" | head -n 1)"
  if [ "$ci" = "green" ]; then
    suite_skipped=1
    echo "tests/run-all.sh skipped: CI is green on $head_short (use --local-suite to run it here)"
    echo "README test count check skipped: CI verified it on $head_short (use --local-suite to check it here)"
  else
    [ -n "$ci" ] || ci="no answer"
    echo "tests/run-all.sh runs here: CI is not green on $head_short ($ci)"
  fi
fi

if [ "$suite_skipped" -eq 0 ]; then
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
  git tag -s -m "release $tag" "$tag" || sign_ok=0
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
