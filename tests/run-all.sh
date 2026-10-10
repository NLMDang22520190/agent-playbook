#!/usr/bin/env bash
# Runs every tests/test-*.sh plus the static skill checks. Exit 1 if anything fails.
# Suites run in parallel batches of PB_JOBS (default 4; PB_JOBS=1 runs them one by one), each into its
# own log, and the logs are printed in a fixed order. Process start-up is slow on Windows (Git Bash),
# so parallel batches cut the wall-clock time there the most. Bash 3.2 has no `wait -n`: batches wait as a whole.
cd "$(dirname "$0")/.." || exit 3
JOBS="${PB_JOBS:-4}"
case "$JOBS" in '' | *[!0123456789]* | 0) JOBS=1 ;; esac
base="${TMPDIR:-/tmp}"; base="${base%/}"
OUTD="$(mktemp -d "$base/pbrunall.XXXXXX")" || exit 3
trap 'rm -rf "$OUTD"' EXIT

set -- tests/test-*.sh
i=0
for t in "$@"; do
  n="$(basename "$t" .sh)"
  ( bash "$t" > "$OUTD/$n.out" 2>&1; echo "$?" > "$OUTD/$n.rc" ) &
  i=$((i + 1))
  [ $((i % JOBS)) -eq 0 ] && wait
done
wait

fail=0
for t in "$@"; do
  n="$(basename "$t" .sh)"
  echo "== $t"
  cat "$OUTD/$n.out"
  [ "$(cat "$OUTD/$n.rc" 2>/dev/null)" = "0" ] || fail=1
done
echo "== evals/run-checks.sh (static skill checks)"
bash evals/run-checks.sh || fail=1
if [ "$fail" -eq 0 ]; then echo "ALL GREEN"; else echo "FAILURES"; fi
exit "$fail"
