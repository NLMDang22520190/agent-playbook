#!/usr/bin/env bash
# PB-HIDDEN-CANARY:pattern-29-backup-rotation-newest
# Hidden PASS_TO_PASS test: what already worked keeps working (before and after the change), with zero-padded names
# in one month: KEEP 2 keeps the two newest, a KEEP larger than the number of backups deletes nothing, and --dry-run
# prints "would delete <name>" per file it would delete and deletes nothing (docs/backups.md).
# Run from the repo root: bash tests/rotate-plain.p2p.sh
set -u
d="$(mktemp -d "${TMPDIR:-/tmp}/pbo29p.XXXXXX")" || exit 2
trap 'rm -rf "${d:?}"' EXIT
fail=0
check() { # name got want
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got [$2] want [$3]"; fail=1; fi
}
listing() { (cd "$1" && ls -A | LC_ALL=C sort | tr '\n' ' '); }
mkset() {
  mkdir -p "$1"
  for n in 2026-08-01 2026-08-05 2026-08-10 2026-08-20; do printf 'backup %s\n' "$n" > "$1/shop-$n.tar.gz"; done
}
ALL="shop-2026-08-01.tar.gz shop-2026-08-05.tar.gz shop-2026-08-10.tar.gz shop-2026-08-20.tar.gz "

B="$d/keep2"
mkset "$B"
bash ./bin/rotate-backups.sh "$B" 2 > /dev/null 2>&1
check "KEEP 2 exits 0" "$?" 0
check "KEEP 2 keeps the two newest" "$(listing "$B")" "shop-2026-08-10.tar.gz shop-2026-08-20.tar.gz "

B="$d/keep10"
mkset "$B"
bash ./bin/rotate-backups.sh "$B" 10 > /dev/null 2>&1
check "KEEP 10 exits 0" "$?" 0
check "KEEP larger than the count deletes nothing" "$(listing "$B")" "$ALL"

B="$d/dry"
mkset "$B"
bash ./bin/rotate-backups.sh "$B" 2 --dry-run > "$d/out" 2> "$d/err"
check "--dry-run exits 0" "$?" 0
check "--dry-run deletes nothing" "$(listing "$B")" "$ALL"
for n in 2026-08-01 2026-08-05; do
  if grep -qx "would delete shop-$n.tar.gz" "$d/out"; then echo "ok   --dry-run prints would delete shop-$n.tar.gz"
  else echo "FAIL --dry-run prints would delete shop-$n.tar.gz: got [$(cat "$d/out")]"; fail=1; fi
done
for n in 2026-08-10 2026-08-20; do
  if grep -q "would delete.*shop-$n" "$d/out"; then echo "FAIL --dry-run names a kept backup shop-$n.tar.gz"; fail=1
  else echo "ok   --dry-run does not name the kept shop-$n.tar.gz"; fi
done
exit "$fail"
