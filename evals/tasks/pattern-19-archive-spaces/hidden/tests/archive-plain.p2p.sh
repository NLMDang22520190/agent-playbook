#!/usr/bin/env bash
# PB-HIDDEN-CANARY:pattern-19-archive-spaces
# Hidden PASS_TO_PASS test: plain names in nested directories are archived flat; an empty SRC gives "archived 0 files".
# Run from the repo root: bash tests/archive-plain.p2p.sh
set -u
d="$(mktemp -d "${TMPDIR:-/tmp}/pbo19.XXXXXX")" || exit 2
trap 'rm -rf "$d"' EXIT
fail=0
check() { # name got want
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got [$2] want [$3]"; fail=1; fi
}

src="$d/in"; dst="$d/out"
mkdir -p "$src/sub/deeper" "$dst"
printf 'alpha\n' > "$src/a.txt"
printf 'bravo\n' > "$src/sub/b.txt"
printf 'charlie\n' > "$src/sub/deeper/c.log"
out="$(bash ./bin/archive "$src" "$dst" 2>/dev/null)"; rc=$?
check 'nested: exit status' "$rc" 0
check 'nested: reported count' "$out" 'archived 3 files'
check 'nested: a.txt copied flat' "$(cat "$dst/a.txt" 2>/dev/null)" alpha
check 'nested: b.txt copied flat' "$(cat "$dst/b.txt" 2>/dev/null)" bravo
check 'nested: c.log copied flat' "$(cat "$dst/c.log" 2>/dev/null)" charlie
check 'nested: MANIFEST lists the three names' "$(LC_ALL=C sort "$dst/MANIFEST" 2>/dev/null)" "$(printf 'a.txt\nb.txt\nc.log')"

empty="$d/empty"; dst2="$d/out2"
mkdir -p "$empty" "$dst2"
out="$(bash ./bin/archive "$empty" "$dst2" 2>/dev/null)"; rc=$?
check 'empty: exit status' "$rc" 0
check 'empty: reported count' "$out" 'archived 0 files'
if [ -f "$dst2/MANIFEST" ]; then
  check 'empty: MANIFEST has no line' "$(wc -l < "$dst2/MANIFEST" | tr -d ' ')" 0
else
  check 'empty: MANIFEST written' missing present
fi
exit "$fail"
