#!/usr/bin/env bash
# v0.35.0 slice A (AC15, AC16 as revised by R1-2, R1-7, R2-5, R2-6): content pins.
# - AC16 (R2-6): the committed gate evals/results/gate-8a96ad9cfbc6 is marked voided: gate.json says "verdict": "voided" (never
#   "pass"), has a "voided" object with a non-empty reason, keeps its "commit"; VOIDED.md says the run is voided and names 7f9cdd8,
#   the commit v0.33.0 shipped on. (The find_baseline skip of a voided group is pinned in tests/test-release-gate-rules.sh.)
# - AC15 (R1-7): scripts/claude-hooks.sh lines 1-3 no longer call the hooks opt-in and say they are installed by default; its --help
#   (lines 4-10 of the file) prints the same usage as before. scripts/guard-irreversible.sh is not pinned here (another branch owns it).
# Reads files only; needs node for the JSON (no jq).
. "$(dirname "$0")/lib.sh"

G="$PB_ROOT/evals/results/gate-8a96ad9cfbc6"
GC="8a96ad9cfbc62838fde3559c5f746845d13cd125"

echo "AC16 the gate-8a96ad9cfbc6 run is voided"
if command -v node >/dev/null 2>&1 && node -e '' >/dev/null 2>&1; then
  # one line: parse|verdict|commit|typeof voided|voided.reason is a non-empty string
  R="$(node -e '
const fs = require("fs");
let j;
try { j = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); } catch (e) { console.log("BAD|" + e.message); process.exit(0); }
const v = j.voided;
const okr = !!v && typeof v === "object" && typeof v.reason === "string" && v.reason.trim().length > 0;
console.log(["ok", j.verdict, j.commit, (v === null ? "null" : typeof v), okr].join("|"));' "$G/gate.json" 2>&1)"
  assert_eq "AC16 gate.json parses" "ok" "${R%%|*}"
  assert_eq "AC16 gate.json verdict is voided (not pass)" "voided" "$(printf '%s' "$R" | cut -d'|' -f2)"
  assert_eq "AC16 gate.json commit is unchanged" "$GC" "$(printf '%s' "$R" | cut -d'|' -f3)"
  assert_eq "AC16 gate.json has a voided object" "object" "$(printf '%s' "$R" | cut -d'|' -f4)"
  assert_eq "AC16 gate.json voided.reason is a non-empty string" "true" "$(printf '%s' "$R" | cut -d'|' -f5)"
else
  t_skip 5 "AC16 gate.json pins (node missing)"
fi

assert_file "AC16 VOIDED.md exists in the gate dir" "$G/VOIDED.md"
V="$(cat "$G/VOIDED.md" 2>/dev/null | tr -d '\r')"
assert_contains "AC16 VOIDED.md names 7f9cdd8 (the commit v0.33.0 shipped on)" "$V" "7f9cdd8"
if printf '%s\n' "$V" | grep -qiE 'voided'; then t_ok "AC16 VOIDED.md says the run is voided"
else t_bad "AC16 VOIDED.md says the run is voided" "no 'voided' in VOIDED.md"; fi

echo "AC15 scripts/claude-hooks.sh header: hooks are on by default, usage unchanged"
CHS="$PB_ROOT/scripts/claude-hooks.sh"
H3="$(sed -n '1,3p' "$CHS" | tr -d '\r')"
if printf '%s\n' "$H3" | grep -qi 'opt-in'; then t_bad "AC15 header lines 1-3 do not say opt-in" "$H3"
else t_ok "AC15 header lines 1-3 do not say opt-in"; fi
if printf '%s\n' "$H3" | grep -qiE 'by default'; then t_ok "AC15 header lines 1-3 say the hooks are installed by default"
else t_bad "AC15 header lines 1-3 say the hooks are installed by default" "$H3"; fi
# usage() prints lines 4-10 of the file: the header must stay at three lines so the same usage comes out (captured at 2a68fe4)
RC=0; U="$(bash "$CHS" --help 2>&1 | tr -d '\r')" || RC=$?
assert_rc "AC15 claude-hooks.sh --help exits 0" 0
assert_eq "AC15 --help first line is empty (line 4 of the file is a bare #)" "" "$(printf '%s\n' "$U" | sed -n 1p)"
assert_eq "AC15 --help line 2 is the Usage line" "Usage: claude-hooks.sh install|uninstall|status [--home DIR] [--dry-run]" "$(printf '%s\n' "$U" | sed -n 2p)"
assert_eq "AC15 --help last line is the --home line" "--home defaults to the playbook home (PLAYBOOK_HOME, else the user's home)." "$(printf '%s\n' "$U" | sed -n 7p)"
assert_not_contains "AC15 --help shows no header text" "$U" "agent-playbook (v0."

t_summary
