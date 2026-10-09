#!/usr/bin/env bash
# Runs every tests/test-*.sh plus the static skill checks. Exit 1 if anything fails.
cd "$(dirname "$0")/.." || exit 3
fail=0
for t in tests/test-*.sh; do
  echo "== $t"
  bash "$t" || fail=1
done
echo "== evals/run-checks.sh (static skill checks)"
bash evals/run-checks.sh || fail=1
if [ "$fail" -eq 0 ]; then echo "ALL GREEN"; else echo "FAILURES"; fi
exit "$fail"
