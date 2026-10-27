#!/usr/bin/env bash
# PB-HIDDEN-CANARY:pattern-21-unsubscribe-exact
# Hidden PASS_TO_PASS test: plain addresses unsubscribe as before; the last address leaves an empty list; a missing list
# is an error that creates nothing; subscribe still appends. Run from the repo root: bash tests/unsubscribe-plain.p2p.sh
set -u
d="$(mktemp -d "${TMPDIR:-/tmp}/pbo21p.XXXXXX")" || exit 2
trap 'rm -rf "$d"' EXIT
fail=0
check() { # name got want
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got [$2] want [$3]"; fail=1; fi
}

list="$d/list.txt"
printf '%s\n' an@example.com binh@example.com chi@example.com > "$list"
out="$(LIST="$list" bash ./bin/unsubscribe binh@example.com 2>/dev/null)"; rc=$?
check 'plain: exit status' "$rc" 0
check 'plain: output' "$out" 'removed 1'
check 'plain: the others stay in order' "$(cat "$list")" "$(printf 'an@example.com\nchi@example.com')"

one="$d/one.txt"
printf 'solo@example.com\n' > "$one"
out="$(LIST="$one" bash ./bin/unsubscribe solo@example.com 2>/dev/null)"
check 'last address: output' "$out" 'removed 1'
check 'last address: the list is empty' "$(wc -c < "$one" 2>/dev/null | tr -d ' ')" 0

LIST="$d/missing.txt" bash ./bin/unsubscribe an@example.com >/dev/null 2>&1; rc=$?
check 'missing list: non-zero exit' "$([ "$rc" != 0 ] && echo nonzero || echo zero)" nonzero
check 'missing list: no file created' "$([ -e "$d/missing.txt" ] && echo created || echo absent)" absent

out="$(LIST="$list" bash ./bin/subscribe dung@example.com 2>/dev/null)"
check 'subscribe: output' "$out" subscribed
check 'subscribe: appended at the end' "$(tail -n 1 "$list")" dung@example.com
exit "$fail"
