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
run bash "$CONF" set BADKEY x --global
assert_rc "uppercase key rejected (no locale-dependent ranges)" 2
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


echo "#11 list ignores keys that are not lowercase"
printf 'BADKEY=x\n' >> "$H/.agents/playbook.conf"
run bash "$CONF" list
assert_not_contains "#11 list skips an uppercase key line" "$OUT" "BADKEY"

echo "#1 AC1.2 generic model keys warn on set"
for r in tester implementer reviewer; do
  rm -f "$H/.agents/playbook.conf"
  ERR="$(bash "$CONF" set "model_$r" "val-$r" --global 2>&1 >/dev/null)"; RC=$?
  OUT="$ERR"
  assert_rc "AC1.2 set model_$r exits 0" 0
  assert_contains "AC1.2 model_$r warns: applies to every harness" "$ERR" "applies to every harness"
  assert_contains "AC1.2 model_$r warns: names model_<role>_<harness>" "$ERR" "model_<role>_<harness>"
  run bash "$CONF" get "model_$r"
  assert_eq "AC1.2 model_$r is still written" "val-$r" "$OUT"
  OUTONLY="$(bash "$CONF" set "model_$r" "val2-$r" --global 2>/dev/null)"
  assert_not_contains "AC1.2 model_$r warning goes to stderr, not stdout" "$OUTONLY" "applies to every harness"
done
ERR="$(bash "$CONF" set model_tester_codex cx --global 2>&1 >/dev/null)"
assert_eq "AC1.2 model_tester_codex prints nothing on stderr" "" "$ERR"
run bash "$CONF" get model_tester_codex
assert_eq "AC1.2 model_tester_codex is written" "cx" "$OUT"
ERR="$(bash "$CONF" set language vi --global 2>&1 >/dev/null)"
assert_eq "AC1.2 unrelated key prints nothing on stderr" "" "$ERR"
ERR="$(bash "$CONF" set model_testers x --global 2>&1 >/dev/null)"
assert_eq "AC1.2 near-miss key model_testers prints nothing" "" "$ERR"
ERR="$(cd "$P" && bash "$CONF" set model_reviewer pm --project 2>&1 >/dev/null)"
assert_contains "AC1.2 warning also for --project" "$ERR" "applies to every harness"

t_summary
