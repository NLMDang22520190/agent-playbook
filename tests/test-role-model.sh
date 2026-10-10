#!/usr/bin/env bash
# Tests for scripts/role-model.sh (slice S1, AC1; default D1)
. "$(dirname "$0")/lib.sh"
RM="$PB_ROOT/scripts/role-model.sh"

# Fresh, isolated world per scenario: own PLAYBOOK_HOME and own project dir (not inside any repo).
H="$(mk_tmp)"; P="$(mk_tmp)"
export PLAYBOOK_HOME="$H"
unset PLAYBOOK_HARNESS
mkdir -p "$H/.agents" "$P/.agents"
G="$H/.agents/playbook.conf"; L="$P/.agents/playbook.conf"

reset() { rm -f "$G" "$L"; unset PLAYBOOK_HARNESS; }
role() { run_in "$P" bash "$RM" "$@"; }   # sets OUT, RC

echo "role-model.sh"

# --- default: nothing configured -> session
reset
role tester
assert_rc "AC1 unset role exits 0" 0
assert_eq "AC1 nothing configured -> session" "session" "$OUT"
role reviewer
assert_eq "AC1 reviewer default -> session" "session" "$OUT"

# --- generic key, one role at a time (a mutant ignoring the role would fail)
reset
printf 'model_tester=tmod\nmodel_implementer=imod\nmodel_reviewer=rmod\n' > "$G"
role tester;      assert_eq "AC1 generic tester"      "tmod" "$OUT"
role implementer; assert_eq "AC1 generic implementer" "imod" "$OUT"
role reviewer;    assert_eq "AC1 generic reviewer"    "rmod" "$OUT"

# --- generic wins over session (session is only the fallback)
reset
printf 'model_reviewer=strong\n' > "$G"
role reviewer;    assert_eq "AC1 generic beats session fallback" "strong" "$OUT"
role tester;      assert_eq "AC1 unconfigured sibling role still session" "session" "$OUT"

# --- per-harness key wins over generic (D1), via --harness
reset
printf 'model_tester=gen\nmodel_tester_claude-code=perh\nmodel_tester_opencode=other\n' > "$G"
role tester --harness claude-code
assert_eq "AC1 per-harness key beats generic (--harness)" "perh" "$OUT"
role tester --harness opencode
assert_eq "AC1 picks the key of the requested harness" "other" "$OUT"
role tester --harness codex
assert_eq "AC1 harness without own key falls back to generic" "gen" "$OUT"
role tester
assert_eq "AC1 no harness -> only generic key applies" "gen" "$OUT"

# --- per-harness key for a harness, other role not affected
reset
printf 'model_tester_codex=cx\n' > "$G"
role implementer --harness codex
assert_eq "AC1 per-harness key is per role" "session" "$OUT"
role tester --harness codex
assert_eq "AC1 per-harness only, no generic" "cx" "$OUT"
role tester
assert_eq "AC1 per-harness key ignored without harness" "session" "$OUT"

# --- harness from env PLAYBOOK_HARNESS
reset
printf 'model_tester=gen\nmodel_tester_codex=cx\n' > "$G"
export PLAYBOOK_HARNESS=codex
role tester
assert_eq "AC1 harness from PLAYBOOK_HARNESS" "cx" "$OUT"
role tester --harness claude-code
assert_eq "AC1 --harness overrides PLAYBOOK_HARNESS" "gen" "$OUT"
unset PLAYBOOK_HARNESS
role tester
assert_eq "AC1 env unset again -> generic" "gen" "$OUT"

# --- project overrides global, at generic level and per-harness level
reset
printf 'model_reviewer=g\nmodel_reviewer_codex=gh\n' > "$G"
printf 'model_reviewer=p\n' > "$L"
role reviewer
assert_eq "AC1 project generic overrides global generic" "p" "$OUT"
role reviewer --harness codex
assert_eq "AC1 per-harness global beats project generic (D1: key specificity first)" "gh" "$OUT"
printf 'model_reviewer=p\nmodel_reviewer_codex=ph\n' > "$L"
role reviewer --harness codex
assert_eq "AC1 project per-harness overrides global per-harness" "ph" "$OUT"
reset
printf 'model_implementer=pimp\n' > "$L"
role implementer
assert_eq "AC1 project-only value used when global empty" "pimp" "$OUT"

# --- list
reset
printf 'model_tester=t\nmodel_reviewer=r\nmodel_reviewer_codex=rc\n' > "$G"
role list
assert_rc "AC1 list exits 0" 0
assert_eq "AC1 list prints three lines in order" "tester=t
implementer=session
reviewer=r" "$OUT"
role list --harness codex
assert_eq "AC1 list --harness applies per-harness keys" "tester=t
implementer=session
reviewer=rc" "$OUT"
export PLAYBOOK_HARNESS=codex
role list
assert_eq "AC1 list honours PLAYBOOK_HARNESS" "tester=t
implementer=session
reviewer=rc" "$OUT"
unset PLAYBOOK_HARNESS
reset
role list
assert_eq "AC1 list with no conf" "tester=session
implementer=session
reviewer=session" "$OUT"

# --- invalid input exits 2 and prints no model
reset
printf 'model_tester=t\n' > "$G"
role bogus
assert_rc "AC1 bad role exits 2" 2
role Tester
assert_rc "AC1 role is case-sensitive (Tester rejected)" 2
role
assert_rc "AC1 missing role exits 2" 2
role tester --harness "Bad Name"
assert_rc "AC1 harness with space/uppercase exits 2" 2
role tester --harness "a_b"
assert_rc "AC1 harness with underscore exits 2" 2
role tester --harness ""
assert_rc "AC1 empty harness exits 2" 2
role tester --harness 'x;y'
assert_rc "AC1 harness with shell metachar exits 2" 2
role list --harness "BAD"
assert_rc "AC1 list with bad harness exits 2" 2
export PLAYBOOK_HARNESS="BAD NAME"
role tester
assert_rc "AC1 bad PLAYBOOK_HARNESS exits 2" 2
unset PLAYBOOK_HARNESS
role tester --harness
assert_rc "AC1 --harness without value exits 2" 2

t_summary
