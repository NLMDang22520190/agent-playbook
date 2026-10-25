#!/usr/bin/env bash
# PB-HIDDEN-CANARY:oss-03-last-line-no-newline
# Hidden PASS_TO_PASS test: files ending in a newline and empty files. Run from the repo root: bash tests/sum-newline.p2p.sh
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
printf '1\n2\n3\n' > "$d/three.txt"
check 'a file ending in a newline is summed once' "$d/three.txt" 6
: > "$d/empty.txt"
check 'an empty file prints 0' "$d/empty.txt" 0
exit "$fail"
