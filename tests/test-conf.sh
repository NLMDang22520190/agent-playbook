#!/usr/bin/env bash
# Tests for scripts/conf.sh
. "$(dirname "$0")/lib.sh"
CONF="$PB_ROOT/scripts/conf.sh"

H="$(mk_tmp)"; P="$(mk_tmp)"
export PLAYBOOK_HOME="$H"

echo "conf.sh"
run bash "$CONF" get language
assert_rc "get on missing key exits 1" 1

run bash "$CONF" set language vi --global
assert_rc "set --global ok" 0
assert_file "global file created" "$H/.agents/playbook.conf"
run bash "$CONF" get language
assert_eq "get returns global value" "vi" "$OUT"

run bash "$CONF" set language en --global
run bash "$CONF" get language
assert_eq "set overwrites" "en" "$OUT"
assert_eq "no duplicate lines" "1" "$(grep -c '^language=' "$H/.agents/playbook.conf")"

run_in "$P" bash "$CONF" set language fr --project
assert_rc "set --project ok (in a dir)" 0
assert_file "project file created" "$P/.agents/playbook.conf"
run_in "$P" bash "$CONF" get language
assert_eq "project overrides global" "fr" "$OUT"
run bash "$CONF" get language
assert_eq "global unaffected outside project" "en" "$OUT"

run bash "$CONF" set "Bad Key" x --global
assert_rc "invalid key rejected" 2
run bash "$CONF" set k "line1
line2" --global
assert_rc "multi-line value rejected" 2

run bash "$CONF" set test_cmd "npm test -- --runInBand" --global
run bash "$CONF" get test_cmd
assert_eq "values with spaces and dashes preserved" "npm test -- --runInBand" "$OUT"

run bash "$CONF" set regex '^(a|b)/=x$' --global
run bash "$CONF" get regex
assert_eq "value containing = and regex chars preserved" '^(a|b)/=x$' "$OUT"

run_in "$P" bash "$CONF" list
assert_contains "list shows origin" "$OUT" "language=fr"
assert_contains "list marks project origin" "$OUT" "project"

t_summary
