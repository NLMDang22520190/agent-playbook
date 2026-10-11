#!/usr/bin/env bash
# Refresh tests/shard-weights from the suite timings of a CI run.
#   tools/shard-weights.sh RUN_ID [--repo OWNER/NAME] [--out FILE]
# Reads the logs of the run's "windows shard K/N" jobs, takes every "== tests/test-x.sh (N s)" heading that
# tests/run-all.sh prints, and writes "test-x.sh N" lines sorted by seconds (largest first; a suite seen twice
# keeps the larger number) under a "#" header naming the run. Default output: tests/shard-weights in this repo.
# Exit: 0 written, 1 no timings found (file untouched), 2 usage, 3 gh failed (file untouched).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)" || exit 3

usage() { echo "usage: tools/shard-weights.sh RUN_ID [--repo OWNER/NAME] [--out FILE]" >&2; exit 2; }

run=""; repo=""; out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) [ $# -ge 2 ] && [ -n "$2" ] || usage; repo="$2"; shift ;;
    --out)  [ $# -ge 2 ] && [ -n "$2" ] || usage; out="$2"; shift ;;
    -*) usage ;;
    *) [ -z "$run" ] || usage; run="$1" ;;
  esac
  shift
done
case "$run" in '' | *[!0123456789]*) usage ;; esac
[ -n "$out" ] || out="$ROOT/tests/shard-weights"
R=""; [ -n "$repo" ] && R="--repo $repo"

jobs_json="$(gh run view "$run" $R --json jobs)" || { echo "gh run view $run failed" >&2; exit 3; }
ids="$(printf '%s' "$jobs_json" | node -e 'let s=""; process.stdin.on("data", d => s += d).on("end", () => { const j = JSON.parse(s).jobs || []; for (const x of j) if (/^windows shard \d+\/\d+$/.test(x.name || "")) console.log(x.databaseId) })')" ||
  { echo "cannot read the jobs of run $run" >&2; exit 3; }

logs=""
for id in $ids; do
  log="$(gh run view --job "$id" $R --log)" || { echo "gh run view --job $id failed" >&2; exit 3; }
  logs="$logs
$log"
done

body="$(printf '%s\n' "$logs" | tr -d '\r' |
  sed -n 's/.*== tests\/\(test-[A-Za-z0-9_.-]*\.sh\) (\([0-9][0-9]*\) s).*/\1 \2/p' |
  awk '{ if (!($1 in w) || $2 + 0 > w[$1] + 0) w[$1] = $2 } END { for (k in w) print k, w[k] }' |
  LC_ALL=C sort -k2,2nr -k1,1)"
[ -n "$body" ] || { echo "no suite timings found in the windows shard jobs of run $run" >&2; exit 1; }

dir="$(dirname "$out")"
tmp="$(mktemp "$dir/.shard-weights.XXXXXX")" || exit 3
{ printf '# Seconds per suite on the windows-latest CI runner (shard jobs), run %s.\n' "$run"
  printf '# Used by tests/run-all.sh to balance PB_SHARD; refresh with tools/shard-weights.sh RUN_ID.\n'
  printf '%s\n' "$body"; } > "$tmp" && mv "$tmp" "$out" || { rm -f "$tmp"; exit 3; }
echo "wrote $out ($(printf '%s\n' "$body" | wc -l | tr -d ' ') suites, run $run)"
