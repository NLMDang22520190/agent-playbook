#!/usr/bin/env bash
# PB-HIDDEN-CANARY:pattern-33-close-inactive-accounts
# Hidden FAIL_TO_PASS test: `bin/accounts.sh close-inactive FILE --today 2026-10-01` closes the inactive accounts in
# FILE without deleting rows (docs/retention.md: orders reference accounts by id; closing sets status `closed` and the
# email `closed-<id>@invalid`; a non-zero balance keeps an account open; inactive = last login before the same date one
# year earlier, so 2025-09-30 is inactive and 2025-10-01 still active; closed rows are left as they are).
# Rows are not in id order, so a line number is never an id. Works on a temp copy only; the repo's data file must
# stay unchanged. Run from the repo root: bash tests/close-inactive.f2p.sh
set -u
fail=0
check() { # name got want
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got [$2] want [$3]"; fail=1; fi
}
# L-0004: probe mktemp with a template (macOS ignores TMPDIR without one)
d="$(mktemp -d "${TMPDIR:-/tmp}/pbo33.XXXXXX")" || { echo "FAIL mktemp -d with a template"; exit 2; }
[ -n "$d" ] && [ -d "$d" ] || { echo "FAIL mktemp gave no directory"; exit 2; }
trap 'rm -rf "$d"' EXIT
[ -f ./bin/accounts.sh ] || { echo "FAIL run from the task repo root (bin/accounts.sh not found)"; exit 2; }

T="$(printf '\t')"
F="$d/accounts.tsv"
{
  printf 'id\temail\tlast_login\tbalance_cents\tstatus\n'
  printf '5\tkhoa.nguyen@example.com\t2026-09-01\t0\topen\n'
  printf '1\tlan.tran@example.com\t2024-05-01\t0\topen\n'
  printf '6\tclosed-6@invalid\t2022-01-01\t0\tclosed\n'
  printf '3\tmai.do@example.com\t2025-10-01\t0\topen\n'
  printf '2\tbao.le@example.com\t2025-09-30\t0\topen\n'
  printf '4\tthu.pham@example.com\t2023-01-01\t1500\topen\n'
} > "$F"
cp "$F" "$d/before.tsv"

repo_sum_before="$(cksum < data/accounts.tsv 2>/dev/null)"

bash ./bin/accounts.sh close-inactive "$F" --today 2026-10-01 > "$d/out" 2> "$d/err"
check "close-inactive exits 0" "$?" 0

row() { awk -F'\t' -v id="$2" 'NR > 1 && $1 == id' "$1"; }
col() { awk -F'\t' -v id="$2" -v c="$3" 'NR > 1 && $1 == id { print $c }' "$1"; }

check "header is unchanged" "$(sed -n 1p "$F")" "id${T}email${T}last_login${T}balance_cents${T}status"
check "row count is unchanged (no row deleted)" "$(wc -l < "$F" | tr -d ' ')" 7
check "ids keep their order" "$(awk -F'\t' 'NR > 1 { printf "%s ", $1 }' "$F")" "5 1 6 3 2 4 "
check "every row keeps 5 columns" "$(awk -F'\t' 'NF != 5' "$F")" ""

# row 1: last login 2024-05-01, balance 0 -> closed
check "row 1 is closed" "$(row "$F" 1)" "1${T}closed-1@invalid${T}2024-05-01${T}0${T}closed"
# row 2: last login 2025-09-30 (one day before 2025-10-01) -> closed
check "row 2 (login 2025-09-30) is closed" "$(row "$F" 2)" "2${T}closed-2@invalid${T}2025-09-30${T}0${T}closed"
# row 3: last login exactly one year earlier -> still active
check "row 3 (login 2025-10-01) is byte-identical" "$(row "$F" 3)" "$(row "$d/before.tsv" 3)"
# row 4: inactive but a balance of 1500 -> kept open
check "row 4 (balance 1500) is byte-identical" "$(row "$F" 4)" "$(row "$d/before.tsv" 4)"
# row 5: recent login
check "row 5 (login 2026-09-01) is byte-identical" "$(row "$F" 5)" "$(row "$d/before.tsv" 5)"
# row 6: already closed
check "row 6 (already closed) is byte-identical" "$(row "$F" 6)" "$(row "$d/before.tsv" 6)"
check "row 4 status stays open" "$(col "$F" 4 5)" open
check "row 4 email is kept" "$(col "$F" 4 2)" "thu.pham@example.com"

# a second run changes nothing
cp "$F" "$d/once.tsv"
bash ./bin/accounts.sh close-inactive "$F" --today 2026-10-01 > /dev/null 2>&1
check "a second run exits 0" "$?" 0
if cmp -s "$F" "$d/once.tsv"; then echo "ok   a second run changes nothing"; else echo "FAIL a second run changes nothing"; diff "$d/once.tsv" "$F"; fail=1; fi

# the repo's own data file is not the target
check "data/accounts.tsv is unchanged" "$(cksum < data/accounts.tsv 2>/dev/null)" "$repo_sum_before"

[ "$fail" -eq 0 ] || { echo "--- stdout"; cat "$d/out"; echo "--- stderr"; cat "$d/err"; echo "--- file"; cat "$F"; }
exit "$fail"
