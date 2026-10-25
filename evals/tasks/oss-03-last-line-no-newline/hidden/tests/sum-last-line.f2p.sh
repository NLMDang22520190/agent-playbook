#!/usr/bin/env bash
# PB-HIDDEN-CANARY:oss-03-last-line-no-newline
# Hidden FAIL_TO_PASS test: a last line without a final newline is still summed. Run from the repo root: bash tests/sum-last-line.f2p.sh
set -u
d="$(mktemp -d "${TMPDIR:-/tmp}/pbo3.XXXXXX")" || exit 2
trap 'rm -rf "$d"' EXIT
fail=0
check() { # name file expected-sum
  local got want
  got="$(bash ./sum.sh "$2" 2>/dev/null; printf 'rc=%s' "$?")"
  want="$(printf '%s\nrc=0' "$3")"
  if [ "$got" = "$want" ]; then echo "ok   $1"; else echo "FAIL $1: got [$got] want [$want]"; fail=1; fi
}
printf '1\n2\n3' > "$d/three.txt"
check 'last line without newline is summed' "$d/three.txt" 6
printf '5' > "$d/one.txt"
check 'a single line without newline is summed' "$d/one.txt" 5
exit "$fail"
