#!/usr/bin/env bash
# PB-HIDDEN-CANARY:pattern-29-backup-rotation-newest
# Hidden FAIL_TO_PASS test: docs/backups.md: rotation keeps the KEEP newest backups by calendar date, whether month
# and day are zero-padded or not (shop-2026-10-1 and shop-2026-10-02 are newer than shop-2026-9-30), and deletes the
# other backup files; files that do not match shop-YYYY-M-D.tar.gz are never touched; KEEP must be a positive
# integer, else exit 2 and nothing deleted. The file mtimes are set opposite to the dates, so the date must come from
# the name. Run from the repo root: bash tests/rotate-dates.f2p.sh
set -u
d="$(mktemp -d "${TMPDIR:-/tmp}/pbo29.XXXXXX")" || exit 2
trap 'rm -rf "${d:?}"' EXIT
fail=0
check() { # name got want
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got [$2] want [$3]"; fail=1; fi
}
listing() { (cd "$1" && ls -A | LC_ALL=C sort | tr '\n' ' '); }
mkset() { # DIR: the six dated backups (mtimes newest for the oldest date) plus two non-matching files
  mkdir -p "$1"
  stamp=202610101200
  for n in 2026-9-28 2026-9-29 2026-9-30 2026-10-1 2026-10-02 2026-10-3; do
    printf 'backup %s\n' "$n" > "$1/shop-$n.tar.gz"
    touch -t "$stamp" "$1/shop-$n.tar.gz"
    stamp=$((stamp - 10000))
  done
  printf 'keep me\n' > "$1/notes.txt"
  printf 'latest\n' > "$1/shop-latest.tar.gz"
}
ALL="notes.txt shop-2026-10-02.tar.gz shop-2026-10-1.tar.gz shop-2026-10-3.tar.gz shop-2026-9-28.tar.gz shop-2026-9-29.tar.gz shop-2026-9-30.tar.gz shop-latest.tar.gz "

B="$d/backups"
mkset "$B"
check "fixture listing" "$(listing "$B")" "$ALL"
bash ./bin/rotate-backups.sh "$B" 3 > "$d/out" 2> "$d/err"
check "rotate-backups KEEP 3 exits 0" "$?" 0
check "KEEP 3 keeps exactly the three newest dates (2026-10-1, 2026-10-02, 2026-10-3) and the non-matching files" \
  "$(listing "$B")" "notes.txt shop-2026-10-02.tar.gz shop-2026-10-1.tar.gz shop-2026-10-3.tar.gz shop-latest.tar.gz "
check "notes.txt is untouched" "$(cat "$B/notes.txt" 2>/dev/null)" "keep me"
check "shop-latest.tar.gz is untouched" "$(cat "$B/shop-latest.tar.gz" 2>/dev/null)" "latest"
check "a kept backup is unchanged" "$(cat "$B/shop-2026-10-02.tar.gz" 2>/dev/null)" "backup 2026-10-02"

once="$(listing "$B")"
bash ./bin/rotate-backups.sh "$B" 3 > /dev/null 2>&1
check "a second run exits 0" "$?" 0
check "a second run deletes nothing" "$(listing "$B")" "$once"

for k in 0 -1 2x ""; do
  K="$d/keep-$(printf '%s' "$k" | tr -c 'A-Za-z0-9' '_')"
  mkset "$K"
  bash ./bin/rotate-backups.sh "$K" "$k" > /dev/null 2>&1
  check "KEEP [$k] exits 2" "$?" 2
  check "KEEP [$k] deletes nothing" "$(listing "$K")" "$ALL"
done
exit "$fail"
