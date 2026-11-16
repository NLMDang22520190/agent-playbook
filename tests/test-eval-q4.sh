#!/usr/bin/env bash
# v0.37 S10 (Q4): scenario E44, the playbook wins when another TDD skill is installed alongside it.
# Unit and static only: nothing here runs evals/run-evals.sh for real (only --print-hashes, which runs nothing).
. "$(dirname "$0")/lib.sh"
SCN="$PB_ROOT/evals/scenarios.md"; RUNEV="$PB_ROOT/evals/run-evals.sh"; AUDIT="$PB_ROOT/docs/delta-audit.md"
BLK="$(awk '/^## E44 /{p=1;print;next} p&&/^## E[0-9]+ /{exit} p{print}' "$SCN")"
FLAT="$(printf '%s' "$BLK" | tr '\n' ' ')"

if grep -q '^## E44 ' "$SCN"; then t_ok "Q4 scenario E44 exists"; else t_bad "Q4 scenario E44 exists" "no '## E44 ' heading"; fi
for k in 'Prompt:' 'Pass if:' 'Fail if:'; do
  if printf '%s\n' "$BLK" | grep -q "^\*\*$k\*\*"; then t_ok "Q4 E44 has $k"; else t_bad "Q4 E44 has $k"; fi
done
PASS="$(printf '%s\n' "$BLK" | grep '^\*\*Pass if:\*\*' | head -n 1)"
if printf '%s' "$PASS" | grep -qi 'tester role'; then t_ok "Q4 E44 Pass-if names a separate tester role"; else t_bad "Q4 E44 Pass-if names a separate tester role"; fi
if printf '%s' "$PASS" | grep -qi 'batched' && printf '%s' "$PASS" | grep -qi 'default'; then t_ok "Q4 E44 Pass-if names batched questions with defaults"; else t_bad "Q4 E44 Pass-if names batched questions with defaults"; fi
if printf '%s' "$PASS" | grep -qi 're-run'; then t_ok "Q4 E44 Pass-if has the reviewer re-run the tests"; else t_bad "Q4 E44 Pass-if has the reviewer re-run the tests"; fi
if printf '%s' "$FLAT" | grep -qi 'test-driven-development' && printf '%s' "$FLAT" | grep -qi 'fixture note'; then t_ok "Q4 E44 declares the second TDD skill as a fixture note"; else t_bad "Q4 E44 declares the second TDD skill as a fixture note"; fi
if printf '%s' "$FLAT" | grep -qi 'not in the AUTO list'; then t_ok "Q4 E44 says it is not in the AUTO list"; else t_bad "Q4 E44 says it is not in the AUTO list"; fi

AUTO="$(sed -n 's/^AUTO="\(.*\)"$/\1/p' "$RUNEV" | head -n 1)"
case " $AUTO " in *" E44 "*) t_bad "Q4 E44 is not in the AUTO list of run-evals.sh";; *) t_ok "Q4 E44 is not in the AUTO list of run-evals.sh";; esac
GS="$(grep -E '^GATE_SCENARIOS=' "$PB_ROOT/tools/release-gate.sh" | head -n 1)"
case "$GS" in *E44*) t_bad "Q4 E44 is not in GATE_SCENARIOS";; *) t_ok "Q4 E44 is not in GATE_SCENARIOS";; esac
if grep -qE '^\| E44 .*\| UNMEASURED \|' "$AUDIT"; then t_ok "Q4 delta-audit has an UNMEASURED row for E44"; else t_bad "Q4 delta-audit has an UNMEASURED row for E44"; fi
if grep -qE '^\| E44 ' "$PB_ROOT/evals/RUBRIC.md" || grep -q '^| E44 ' "$PB_ROOT/evals/RUBRIC.md"; then t_ok "Q4 RUBRIC.md has a row for E44"; else t_bad "Q4 RUBRIC.md has a row for E44"; fi

# E1..E43 are byte-identical to before E44 was added: a sha1 over the per-block sha1s of every block E1..E43 of scenarios.md
# (a block runs from its '## E<n> ' heading to the line before the next '## E<n> ' heading, the rule of run-evals.sh),
# pinned from `git show HEAD~1:evals/scenarios.md` (the commit before E44). It covers AUTO and non-AUTO blocks (E7, E9, E12, E18).
e1_43_sha() { # $1 = scenarios.md path
  n=1; while [ "$n" -le 43 ]; do
    awk -v h="## E$n " 'index($0, h) == 1 { p = 1; print; next } p && /^## E[0-9]+ / { exit } p { print }' "$1" | sha1sum | cut -d' ' -f1 | sed "s/^/E$n /"
    n=$((n+1))
  done | sha1sum | cut -d' ' -f1
}
assert_eq "Q4 every scenario block E1..E43 of scenarios.md is byte-identical to before E44" "a28568060963399e5e20f3f5d7005fc1324bd594" "$(e1_43_sha "$SCN")"
# the grader sha (--print-hashes, first line) is unchanged
H="$(bash "$RUNEV" --harness claude --print-hashes 2>/dev/null | grep -E '^E[0-9]+ ')"
assert_eq "Q4 grader_sha is unchanged" "077b26acc89c06c62b102b720436ce408bede40e" "$(printf '%s\n' "$H" | head -n 1 | awk '{print $3}')"
t_summary
