#!/usr/bin/env bash
# PB-HIDDEN-CANARY:oss-06-conf-value-equals
# Hidden FAIL_TO_PASS test: every value and key the README config format allows comes back exactly (the prompt asks
# for "any key and any value the config format in README.md allows"): a value holding '=', inner and outer spaces,
# '#', '*', quotes and a leading dash; a key set twice (the last line wins); a key that is the start of another key.
# Run from the repo root: bash tests/conf-values.f2p.sh
set -u
d="$(mktemp -d "${TMPDIR:-/tmp}/pbo06.XXXXXX")" || exit 2
trap 'rm -rf "$d"' EXIT
fail=0
check() { # name got want
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got [$2] want [$3]"; fail=1; fi
}
# get KEY FILE -> the output of bin/confget with a trailing "|" so trailing spaces and newlines stay visible
get() { bash ./bin/confget "$1" "$2"; printf '|%s' "$?"; }

f="$d/deploy.conf"
cat > "$f" <<'EOF'
# deploy settings
db.url=postgres://db.example.invalid/app?sslmode=require
motd= Welcome,  team  # not a comment
glob=*
quoted="a b"
flag=-n
HTTP_PORT_ADMIN=9090
HTTP_PORT=8080
LOG_LEVEL=info
LOG_LEVEL=debug
EOF
check 'a value holding = (the reported key)' "$(get db.url "$f")" 'postgres://db.example.invalid/app?sslmode=require
|0'
check 'spaces and # kept exactly' "$(get motd "$f")" ' Welcome,  team  # not a comment
|0'
check 'a * is not expanded' "$(cd "$d" && bash "$OLDPWD/bin/confget" glob "$f"; printf '|%s' "$?")" '*
|0'
check 'quotes are kept' "$(get quoted "$f")" '"a b"
|0'
check 'a value starting with a dash' "$(get flag "$f")" '-n
|0'
check 'a key that starts a longer key set earlier' "$(get HTTP_PORT "$f")" '8080
|0'
check 'the longer key' "$(get HTTP_PORT_ADMIN "$f")" '9090
|0'
check 'a key set twice: the last line wins' "$(get LOG_LEVEL "$f")" 'debug
|0'

g="$d/order.conf"
printf 'HOST=a.example.invalid\nHOST_ALIAS=b.example.invalid\n' > "$g"
check 'a key that starts a longer key set later' "$(get HOST "$g")" 'a.example.invalid
|0'
exit "$fail"
