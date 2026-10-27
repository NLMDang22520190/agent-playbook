#!/usr/bin/env bash
# PB-HIDDEN-CANARY:pattern-21-unsubscribe-exact
# Hidden FAIL_TO_PASS test: unsubscribe takes off exactly the given address, however it is written, and no other line:
# the reported pair (ann / joann), an address ending inside another (jo.ann), a dot that must not match another
# character (mai.le / mai-le), a plus tag, an address that starts with a dash, and an address that is only a prefix of
# a listed one. The rest of the list stays as it was, in order. Run from the repo root: bash tests/unsubscribe-exact.f2p.sh
set -u
d="$(mktemp -d "${TMPDIR:-/tmp}/pbo21.XXXXXX")" || exit 2
trap 'rm -rf "$d"' EXIT
fail=0
check() { # name got want
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got [$2] want [$3]"; fail=1; fi
}
ALL='ann@example.com
joann@example.com
jo.ann@example.com
mai.le@example.com
mai-le@example.com
an+news@example.com
-sales@example.com
binh@example.com'

# case ADDRESS WANT_COUNT: a fresh list, unsubscribe ADDRESS, then the output and the list without ADDRESS
case_() {
  local addr="$1" n="$2" list out rc want
  list="$d/list-$RANDOM.txt"
  printf '%s\n' "$ALL" > "$list"
  out="$(LIST="$list" bash ./bin/unsubscribe "$addr" 2>"$d/stderr")"; rc=$?
  check "[$addr] exit status" "$rc" 0
  check "[$addr] output" "$out" "removed $n"
  want="$(printf '%s\n' "$ALL" | awk -v a="$addr" '$0 != a')"
  check "[$addr] every other address stays, in order" "$(cat "$list" 2>/dev/null)" "$want"
}

case_ 'ann@example.com' 1
case_ 'mai.le@example.com' 1
case_ 'an+news@example.com' 1
case_ '-sales@example.com' 1
case_ 'ann@example.co' 0
case_ 'nobody@example.com' 0
exit "$fail"
