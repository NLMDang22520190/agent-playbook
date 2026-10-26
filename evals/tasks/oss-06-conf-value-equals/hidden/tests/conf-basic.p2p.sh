#!/usr/bin/env bash
# PB-HIDDEN-CANARY:oss-06-conf-value-equals
# Hidden PASS_TO_PASS test: plain values, comments, an empty value, a missing key, a last line without a newline and
# the usage errors keep working.
# Run from the repo root: bash tests/conf-basic.p2p.sh
set -u
d="$(mktemp -d "${TMPDIR:-/tmp}/pbo06.XXXXXX")" || exit 2
trap 'rm -rf "$d"' EXIT
fail=0
check() { # name got want
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got [$2] want [$3]"; fail=1; fi
}
get() { bash ./bin/confget "$1" "$2"; printf '|%s' "$?"; }

f="$d/app.conf"
printf '# web\n\nHTTP_PORT=8080\n#LOG_LEVEL=trace\nLOG_LEVEL=info\nEMPTY=\nNAME=shop' > "$f"
check 'a plain value' "$(get HTTP_PORT "$f")" '8080
|0'
check 'a commented line is ignored' "$(get LOG_LEVEL "$f")" 'info
|0'
check 'an empty value prints an empty line' "$(get EMPTY "$f")" '
|0'
check 'the last line without a newline' "$(get NAME "$f")" 'shop
|0'
check 'a missing key prints nothing and exits 1' "$(get MISSING "$f")" '|1'
check 'a key only in a comment is not set' "$(get web "$f")" '|1'
bash ./bin/confget >/dev/null 2>&1
check 'usage error exits 2' "$?" 2
bash ./bin/confget HTTP_PORT "$d/nope.conf" >/dev/null 2>&1
check 'an unreadable file exits 2' "$?" 2

# the library is usable on its own
out="$(. ./lib/conf.sh && conf_get HTTP_PORT "$f")"
check 'conf_get from lib/conf.sh' "$out" 8080
exit "$fail"
