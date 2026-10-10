#!/usr/bin/env bash
# Runs every tests/test-*.sh plus the static skill checks. Exit 1 if anything fails.
# Suites run in parallel, at most PB_JOBS at a time (default 4; PB_JOBS=1 runs them one by one): a
# job pool, so the next suite starts as soon as any running one finishes. Each suite writes its own
# log, and the logs are printed in a fixed order. Process start-up is slow on Windows (Git Bash), so
# parallel runs cut the wall-clock time there the most. Bash 3.2 has no `wait -n`: the pool polls the
# finished-suite markers, counted with a glob (no subprocess per poll).
cd "$(dirname "$0")/.." || exit 3
JOBS="${PB_JOBS:-4}"
case "$JOBS" in '' | *[!0123456789]* | 0) JOBS=1 ;; esac
base="${TMPDIR:-/tmp}"; base="${base%/}"
OUTD="$(mktemp -d "$base/pbrunall.XXXXXX")" || exit 3
trap 'rm -rf "$OUTD"' EXIT

count_done() { DONE=0; local f; for f in "$OUTD"/*.rc; do [ -e "$f" ] && DONE=$((DONE + 1)); done; }
set -- tests/test-*.sh
started=0
for t in "$@"; do
  count_done
  while [ $((started - DONE)) -ge "$JOBS" ]; do sleep 0.1; count_done; done
  n="$(basename "$t" .sh)"
  ( bash "$t" > "$OUTD/$n.out" 2>&1; echo "$?" > "$OUTD/$n.tmp"; mv "$OUTD/$n.tmp" "$OUTD/$n.rc" ) &
  started=$((started + 1))
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
