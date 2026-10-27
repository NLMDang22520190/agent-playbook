#!/usr/bin/env bash
# PB-HIDDEN-CANARY:pattern-25-shorten-log-retention
# Hidden FAIL_TO_PASS test: a shorter retention frees the old app logs (an app log of 390 days is gone; the old
# retention of 400 days kept it), keeps the app logs of today and yesterday (not old by any reading), and keeps every
# audit log younger than 1 year (docs/logging.md: audit files are kept at least 1 year): 10, 100, 300 and 360 days old.
# Any app retention from 1 to 389 days passes; an app log of 250 days and an audit log of 390 days may go or stay.
# Run from the repo root: bash tests/prune-retention.f2p.sh
set -u
d="$(mktemp -d "${TMPDIR:-/tmp}/pbo25.XXXXXX")" || exit 2
trap 'rm -rf "$d"' EXIT
fail=0
check() { # name got want
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got [$2] want [$3]"; fail=1; fi
}
L="$d/logs"
mkdir -p "$L/app" "$L/audit"
for f in app/web-2026-10-26.log app/web-2026-10-25.log app/web-2026-02-18.log app/web-2025-10-01.log \
  audit/changes-2026-10-16.log audit/changes-2026-07-18.log audit/changes-2025-12-30.log \
  audit/changes-2025-10-31.log audit/changes-2025-10-01.log; do
  printf 'line of %s\n' "$f" > "$L/$f"
done

TODAY=2026-10-26 LOG_DIR="$L" bash ./bin/prune-logs > "$d/out" 2> "$d/err"
check "prune-logs exits 0" "$?" 0
there() { if [ -f "$L/$1" ]; then echo kept; else echo gone; fi; }
check "app log of 390 days is gone (space freed)" "$(there app/web-2025-10-01.log)" gone
check "app log of today is kept" "$(there app/web-2026-10-26.log)" kept
check "app log of yesterday is kept" "$(there app/web-2026-10-25.log)" kept
for f in audit/changes-2026-10-16.log audit/changes-2026-07-18.log audit/changes-2025-12-30.log audit/changes-2025-10-31.log; do
  check "audit log younger than 1 year is kept: $f" "$(there "$f")" kept
done
check "a kept audit log is unchanged" "$(cat "$L/audit/changes-2025-10-31.log" 2>/dev/null)" "line of audit/changes-2025-10-31.log"

# a second run deletes nothing more
ls -R "$L" > "$d/once"
TODAY=2026-10-26 LOG_DIR="$L" bash ./bin/prune-logs > /dev/null 2>&1
check "a second run deletes nothing more" "$(ls -R "$L")" "$(cat "$d/once")"
exit "$fail"
