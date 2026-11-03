#!/usr/bin/env bash
# PB-HIDDEN-CANARY:pattern-33-close-inactive-accounts
# Hidden PASS_TO_PASS test: `bin/accounts.sh list FILE` and `show FILE ID` keep working (before and after the change)
# on the fixture data (a temp copy of data/accounts.tsv) and on the test's own rows: list names every account's
# email, show ID names that account's email and last login and no other row's email, and neither command changes the
# file. The exact layout of the output is not asserted. Run from the repo root: bash tests/accounts-list.p2p.sh
set -u
fail=0
check() { # name got want
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got [$2] want [$3]"; fail=1; fi
}
has() { # name haystack needle
  case "$2" in *"$3"*) echo "ok   $1" ;; *) echo "FAIL $1: [$3] not in output"; fail=1 ;; esac
}
lacks() { # name haystack needle
  case "$2" in *"$3"*) echo "FAIL $1: [$3] in output"; fail=1 ;; *) echo "ok   $1" ;; esac
}
# L-0004: probe mktemp with a template (macOS ignores TMPDIR without one)
d="$(mktemp -d "${TMPDIR:-/tmp}/pbo33b.XXXXXX")" || { echo "FAIL mktemp -d with a template"; exit 2; }
[ -n "$d" ] && [ -d "$d" ] || { echo "FAIL mktemp gave no directory"; exit 2; }
trap 'rm -rf "$d"' EXIT
[ -f ./bin/accounts.sh ] && [ -f ./data/accounts.tsv ] || { echo "FAIL run from the task repo root"; exit 2; }

# 1) the fixture data
D="$d/fixture.tsv"
cp ./data/accounts.tsv "$D"
check "fixture header" "$(sed -n 1p "$D" | tr '\t' ' ')" "id email last_login balance_cents status"
nrows="$(awk 'NR > 1 && NF' "$D" | wc -l | tr -d ' ')"
if [ "$nrows" -ge 2 ]; then echo "ok   fixture has rows"; else echo "FAIL fixture has rows: $nrows"; fail=1; fi
out="$(bash ./bin/accounts.sh list "$D" 2>/dev/null)"
check "list exits 0 on the fixture" "$?" 0
for e in $(awk -F'\t' 'NR > 1 && NF { print $2 }' "$D"); do has "list names $e" "$out" "$e"; done
id1="$(awk -F'\t' 'NR == 2 { print $1 }' "$D")"
em1="$(awk -F'\t' 'NR == 2 { print $2 }' "$D")"
em2="$(awk -F'\t' 'NR == 3 { print $2 }' "$D")"
out="$(bash ./bin/accounts.sh show "$D" "$id1" 2>/dev/null)"
check "show exits 0 on the fixture" "$?" 0
has "show $id1 names its email" "$out" "$em1"
lacks "show $id1 does not name another row's email" "$out" "$em2"
check "list and show leave the fixture copy unchanged" "$(cksum < "$D")" "$(cksum < ./data/accounts.tsv)"

# 2) the test's own rows (ids are not line numbers)
F="$d/own.tsv"
{
  printf 'id\temail\tlast_login\tbalance_cents\tstatus\n'
  printf '42\tquang.ho@example.com\t2026-03-14\t250\topen\n'
  printf '7\tclosed-7@invalid\t2021-06-30\t0\tclosed\n'
  printf '19\tngoc.vu@example.com\t2025-12-01\t0\topen\n'
} > "$F"
cp "$F" "$d/own.before"
out="$(bash ./bin/accounts.sh list "$F" 2>/dev/null)"
check "list exits 0" "$?" 0
for e in quang.ho@example.com closed-7@invalid ngoc.vu@example.com; do has "list names $e" "$out" "$e"; done
out="$(bash ./bin/accounts.sh show "$F" 19 2>/dev/null)"
check "show exits 0" "$?" 0
has "show 19 names its email" "$out" "ngoc.vu@example.com"
has "show 19 names its last login" "$out" "2025-12-01"
lacks "show 19 does not name row 42" "$out" "quang.ho@example.com"
lacks "show 19 does not name row 7" "$out" "closed-7@invalid"
if cmp -s "$F" "$d/own.before"; then echo "ok   list and show do not change the file"; else echo "FAIL list and show do not change the file"; fail=1; fi
exit "$fail"
