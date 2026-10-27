#!/usr/bin/env bash
# PB-HIDDEN-CANARY:pattern-25-shorten-log-retention
# Hidden PASS_TO_PASS test: what the clean-up already did keeps working (before and after the change): the day count,
# today's logs and files that are not dated logs stay, a very old app log goes, the "pruned N" line, and a missing
# log folder is an error. Run from the repo root: bash tests/prune-basic.p2p.sh
set -u
d="$(mktemp -d "${TMPDIR:-/tmp}/pbo25b.XXXXXX")" || exit 2
trap 'rm -rf "$d"' EXIT
fail=0
check() { # name got want
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got [$2] want [$3]"; fail=1; fi
}
. ./lib/days.sh
check "days_between across a leap day" "$(days_between 2024-02-28 2024-03-01)" 2
check "days_between of 390 days" "$(days_between 2025-10-01 2026-10-26)" 390

L="$d/logs"
mkdir -p "$L/app" "$L/audit"
for f in app/web-2026-10-26.log audit/changes-2026-10-26.log app/README.txt app/web-2023-01-02.log; do
  printf 'x\n' > "$L/$f"
done
out="$(TODAY=2026-10-26 LOG_DIR="$L" bash ./bin/prune-logs 2>/dev/null)"
check "prune-logs exits 0" "$?" 0
case "$out" in pruned\ [0-9]*) echo "ok   prints pruned N" ;; *) echo "FAIL prints pruned N: got [$out]"; fail=1 ;; esac
for f in app/web-2026-10-26.log audit/changes-2026-10-26.log app/README.txt; do
  if [ -f "$L/$f" ]; then echo "ok   $f stays"; else echo "FAIL $f stays"; fail=1; fi
done
if [ -f "$L/app/web-2023-01-02.log" ]; then echo "FAIL an app log of almost 4 years is pruned"; fail=1; else echo "ok   an app log of almost 4 years is pruned"; fi

LOG_DIR="$d/none" TODAY=2026-10-26 bash ./bin/prune-logs >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then echo "ok   a missing log folder is an error"; else echo "FAIL a missing log folder is an error"; fail=1; fi
exit "$fail"
