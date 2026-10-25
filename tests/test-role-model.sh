#!/usr/bin/env bash
# Tests for scripts/role-model.sh (slice S1, AC1; default D1)
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/role-model-fixture.sh"

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
assert_eq "AC1 list prints the three role lines in order (first three lines)" "tester=t
implementer=session
reviewer=r" "$(printf '%s
' "$OUT" | head -n 3)"
role list --harness codex
assert_eq "AC1 list --harness applies per-harness keys (reviewer line)" "reviewer=rc" "$(printf '%s
' "$OUT" | grep -x 'reviewer=.*')"
export PLAYBOOK_HARNESS=codex
role list
assert_eq "AC1 list honours PLAYBOOK_HARNESS (reviewer line)" "reviewer=rc" "$(printf '%s
' "$OUT" | grep -x 'reviewer=.*')"
unset PLAYBOOK_HARNESS
reset
role list
assert_eq "AC1 list with no conf (tester line)" "tester=session" "$(printf '%s
' "$OUT" | grep -x 'tester=.*')"
assert_eq "AC1 list with no conf (implementer line)" "implementer=session" "$(printf '%s
' "$OUT" | grep -x 'implementer=.*')"
assert_eq "AC1 list with no conf (reviewer line)" "reviewer=session" "$(printf '%s
' "$OUT" | grep -x 'reviewer=.*')"

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

# --- #1 AC1.1: `check` reports generic model keys
echo "role-model.sh check (#1 AC1.1)"
reset
role check
assert_rc "AC1.1 no generic keys -> exit 0" 0
assert_contains "AC1.1 no generic keys -> says so" "$OUT" "no generic model keys"
printf 'model_tester_codex=cx\nmodel_reviewer_opencode=rx\n' > "$G"
role check
assert_rc "AC1.1 per-harness keys alone -> exit 0" 0
assert_contains "AC1.1 per-harness keys alone -> no generic keys" "$OUT" "no generic model keys"
assert_not_contains "AC1.1 per-harness keys are not warnings" "$OUT" "warning"

for r in tester implementer reviewer; do
  reset
  printf 'model_%s=val-%s\n' "$r" "$r" > "$G"
  role check
  assert_rc "AC1.1 generic $r -> exit 1" 1
  assert_contains "AC1.1 generic $r named" "$OUT" "model_$r"
  assert_contains "AC1.1 generic $r value shown" "$OUT" "val-$r"
  assert_contains "AC1.1 generic $r says warning" "$OUT" "warning"
  assert_contains "AC1.1 generic $r says applies to every harness" "$OUT" "applies to every harness"
  assert_contains "AC1.1 generic $r suggests per-harness key" "$OUT" "model_${r}_"
  assert_not_contains "AC1.1 generic $r not reported as no-keys" "$OUT" "no generic model keys"
  for o in tester implementer reviewer; do
    [ "$o" = "$r" ] && continue
    assert_not_contains "AC1.1 only $r reported (not $o)" "$OUT" "model_$o"
  done
done

reset
printf 'model_tester=tmod\nmodel_implementer=imod\nmodel_reviewer=rmod\n' > "$G"
role check
assert_rc "AC1.1 three generic keys -> exit 1" 1
assert_eq "AC1.1 one warning line per key" "3" "$(printf '%s\n' "$OUT" | grep -c 'warning')"
assert_contains "AC1.1 implementer line carries its own value" "$(printf '%s\n' "$OUT" | grep 'model_implementer')" "imod"
assert_contains "AC1.1 reviewer line carries its own value" "$(printf '%s\n' "$OUT" | grep 'model_reviewer')" "rmod"
assert_not_contains "AC1.1 tester line has only its own value" "$(printf '%s\n' "$OUT" | grep 'model_tester')" "imod"

reset
printf 'model_tester=tmod\n' > "$G"
role check --harness codex
assert_rc "AC1.1 --harness: exit 1" 1
assert_contains "AC1.1 --harness fills the suggestion" "$OUT" "model_tester_codex"
export PLAYBOOK_HARNESS=opencode
role check
assert_contains "AC1.1 PLAYBOOK_HARNESS fills the suggestion" "$OUT" "model_tester_opencode"
role check --harness codex
assert_contains "AC1.1 --harness beats PLAYBOOK_HARNESS in suggestion" "$OUT" "model_tester_codex"
assert_not_contains "AC1.1 --harness beats PLAYBOOK_HARNESS (no opencode)" "$OUT" "model_tester_opencode"
unset PLAYBOOK_HARNESS

reset
printf 'model_tester=gmod\n' > "$G"
role check
assert_contains "AC1.1 global key names global" "$(printf '%s\n' "$OUT" | grep 'model_tester')" "global"
assert_not_contains "AC1.1 global key does not say project" "$(printf '%s\n' "$OUT" | grep 'model_tester')" "project"
reset
printf 'model_reviewer=pmod\n' > "$L"
role check
assert_rc "AC1.1 project-only generic key -> exit 1" 1
assert_contains "AC1.1 project key reported with value" "$OUT" "pmod"
assert_contains "AC1.1 project key names project" "$(printf '%s\n' "$OUT" | grep 'model_reviewer')" "project"
assert_not_contains "AC1.1 project key does not say global" "$(printf '%s\n' "$OUT" | grep 'model_reviewer')" "global"
reset
printf 'model_tester=gmod\n' > "$G"
printf 'model_reviewer=pmod\n' > "$L"
role check
assert_eq "AC1.1 global + project keys both reported" "2" "$(printf '%s\n' "$OUT" | grep -c 'warning')"

# existing commands keep their exact output when generic keys exist
reset
printf 'model_tester=tmod\nmodel_reviewer=rmod\n' > "$G"
role tester
assert_eq "AC1.1 tester output unchanged with generic keys" "tmod" "$OUT"
role list
assert_eq "AC1.1 list output unchanged with generic keys (first three lines)" "tester=tmod
implementer=session
reviewer=rmod" "$(printf '%s
' "$OUT" | head -n 3)"
ERR="$(cd "$P" && bash "$RM" tester 2>&1 >/dev/null)"
assert_eq "AC1.1 tester prints nothing on stderr with generic keys" "" "$ERR"
ERR="$(cd "$P" && bash "$RM" list 2>&1 >/dev/null)"
assert_eq "AC1.1 list prints nothing on stderr with generic keys" "" "$ERR"

reset
role check --bogus
assert_rc "AC1.1 check with unknown option exits 2" 2
role check --harness "Bad Name"
assert_rc "AC1.1 check with invalid harness exits 2" 2

echo "role-model.sh check: empty generic value"
reset
printf 'model_reviewer=\n' > "$G"
role check
assert_rc "an empty generic value is still reported: exit 1" 1
assert_contains "the empty generic key is named" "$OUT" "model_reviewer"
assert_contains "the empty generic key warns" "$OUT" "warning"
assert_contains "the empty generic key names its origin: global" "$(printf '%s\n' "$OUT" | grep 'model_reviewer')" "global"


# --- v0.22.3 AC3.1: roles reviewer_light and mechanical
echo "role-model.sh v0.22.3 AC3.1: reviewer_light"
reset
role reviewer_light
assert_rc "AC3.1 reviewer_light is a role: exit 0" 0
assert_eq "AC3.1 reviewer_light with nothing configured -> session" "session" "$OUT"

reset
printf 'model_reviewer=rmod\n' > "$G"
role reviewer_light
assert_eq "AC3.1 reviewer_light falls back to the reviewer's model" "rmod" "$OUT"

reset
printf 'model_reviewer=rgen\nmodel_reviewer_codex=rcx\n' > "$G"
role reviewer_light --harness codex
assert_eq "AC3.1 the fallback is the reviewer's model for that harness (per-harness reviewer key)" "rcx" "$OUT"
role reviewer_light
assert_eq "AC3.1 the fallback without a harness is the generic reviewer model" "rgen" "$OUT"

reset
printf 'model_reviewer_codex=rcx\n' > "$G"
role reviewer_light
assert_eq "AC3.1 a per-harness reviewer key is not used without a harness -> session" "session" "$OUT"

reset
printf 'model_reviewer=rgen\nmodel_reviewer_light=lgen\n' > "$G"
role reviewer_light
assert_eq "AC3.1 generic reviewer_light beats the reviewer's model" "lgen" "$OUT"
role reviewer
assert_eq "AC3.1 the reviewer role itself is not affected by reviewer_light" "rgen" "$OUT"

reset
printf 'model_reviewer=rgen\nmodel_reviewer_light=lgen\nmodel_reviewer_light_codex=lcx\nmodel_reviewer_light_opencode=lox\n' > "$G"
role reviewer_light --harness codex
assert_eq "AC3.1 reviewer_light_<harness> beats generic reviewer_light" "lcx" "$OUT"
role reviewer_light --harness opencode
assert_eq "AC3.1 reviewer_light picks the key of the requested harness" "lox" "$OUT"
role reviewer_light --harness claude-code
assert_eq "AC3.1 a harness without its own light key falls back to generic reviewer_light" "lgen" "$OUT"
export PLAYBOOK_HARNESS=codex
role reviewer_light
assert_eq "AC3.1 reviewer_light honours PLAYBOOK_HARNESS" "lcx" "$OUT"
role reviewer_light --harness opencode
assert_eq "AC3.1 --harness overrides PLAYBOOK_HARNESS for reviewer_light" "lox" "$OUT"
unset PLAYBOOK_HARNESS

reset
printf 'model_reviewer_light=gl\n' > "$G"
printf 'model_reviewer_light=pl\n' > "$L"
role reviewer_light
assert_eq "AC3.1 project reviewer_light overrides global" "pl" "$OUT"

reset
printf 'model_tester=t\nmodel_implementer=i\nmodel_mechanical=m\n' > "$G"
role reviewer_light
assert_eq "AC3.1 other roles' keys do not leak into reviewer_light" "session" "$OUT"

echo "role-model.sh v0.22.3 AC3.1: mechanical"
reset
role mechanical
assert_rc "AC3.1 mechanical is a role: exit 0" 0
assert_eq "AC3.1 mechanical with nothing configured -> session" "session" "$OUT"

reset
printf 'model_tester=t\nmodel_implementer=i\nmodel_reviewer=r\nmodel_reviewer_light=l\n' > "$G"
role mechanical
assert_eq "AC3.1 mechanical never falls back to another role's model -> session" "session" "$OUT"

reset
printf 'model_mechanical=mgen\nmodel_mechanical_codex=mcx\nmodel_mechanical_opencode=mox\n' > "$G"
role mechanical
assert_eq "AC3.1 generic mechanical" "mgen" "$OUT"
role mechanical --harness codex
assert_eq "AC3.1 mechanical_<harness> beats generic mechanical" "mcx" "$OUT"
role mechanical --harness opencode
assert_eq "AC3.1 mechanical picks the key of the requested harness" "mox" "$OUT"
role mechanical --harness claude-code
assert_eq "AC3.1 a harness without its own mechanical key falls back to generic" "mgen" "$OUT"
export PLAYBOOK_HARNESS=opencode
role mechanical
assert_eq "AC3.1 mechanical honours PLAYBOOK_HARNESS" "mox" "$OUT"
unset PLAYBOOK_HARNESS

reset
printf 'model_mechanical_codex=mcx\n' > "$G"
role mechanical
assert_eq "AC3.1 a per-harness mechanical key is ignored without a harness -> session" "session" "$OUT"

reset
printf 'model_mechanical=gm\n' > "$G"
printf 'model_mechanical=pm\n' > "$L"
role mechanical
assert_eq "AC3.1 project mechanical overrides global" "pm" "$OUT"

role Mechanical
assert_rc "AC3.1 role names are case-sensitive (Mechanical rejected)" 2
role reviewer-light
assert_rc "AC3.1 reviewer-light (hyphen) is not a role" 2

echo "role-model.sh v0.22.3 AC3.1: list prints both new roles"
reset
printf 'model_tester=t\nmodel_reviewer=r\nmodel_reviewer_light=l\nmodel_mechanical=m\nmodel_reviewer_light_codex=lc\nmodel_mechanical_codex=mc\n' > "$G"
role list
assert_rc "AC3.1 list exits 0" 0
assert_eq "AC3.1 list has the line reviewer_light=l" "reviewer_light=l" "$(printf '%s\n' "$OUT" | grep -x 'reviewer_light=.*')"
assert_eq "AC3.1 list has the line mechanical=m" "mechanical=m" "$(printf '%s\n' "$OUT" | grep -x 'mechanical=.*')"
assert_eq "AC3.1 list still has the line tester=t" "tester=t" "$(printf '%s\n' "$OUT" | grep -x 'tester=.*')"
assert_eq "AC3.1 list still has the line reviewer=r" "reviewer=r" "$(printf '%s\n' "$OUT" | grep -x 'reviewer=.*')"
role list --harness codex
assert_eq "AC3.1 list --harness: reviewer_light line uses the per-harness key" "reviewer_light=lc" "$(printf '%s\n' "$OUT" | grep -x 'reviewer_light=.*')"
assert_eq "AC3.1 list --harness: mechanical line uses the per-harness key" "mechanical=mc" "$(printf '%s\n' "$OUT" | grep -x 'mechanical=.*')"
reset
role list
assert_eq "AC3.1 list with no conf: reviewer_light=session" "reviewer_light=session" "$(printf '%s\n' "$OUT" | grep -x 'reviewer_light=.*')"
assert_eq "AC3.1 list with no conf: mechanical=session" "mechanical=session" "$(printf '%s\n' "$OUT" | grep -x 'mechanical=.*')"
reset
printf 'model_reviewer=rr\n' > "$G"
role list
assert_eq "AC3.1 list: reviewer_light shows the fallback to the reviewer's model" "reviewer_light=rr" "$(printf '%s\n' "$OUT" | grep -x 'reviewer_light=.*')"

echo "role-model.sh v0.22.3 AC3.1: check warns about the generic keys of the new roles"
reset
printf 'model_reviewer_light_codex=lc\nmodel_mechanical_opencode=mo\n' > "$G"
role check
assert_rc "AC3.1 per-harness reviewer_light and mechanical keys alone -> exit 0" 0
assert_contains "AC3.1 ... and the answer is the no-generic-keys line" "$OUT" "no generic model keys"
reset
printf 'model_reviewer_light=lval\n' > "$G"
role check --harness codex
assert_rc "AC3.1 generic model_reviewer_light -> exit 1" 1
WL="$(printf '%s\n' "$OUT" | grep 'warning' | grep 'model_reviewer_light')"
[ -n "$WL" ] && t_ok "AC3.1 a warning line names model_reviewer_light" || t_bad "AC3.1 a warning line names model_reviewer_light" "$OUT"
assert_contains "AC3.1 the warning shows the value" "$WL" "lval"
assert_contains "AC3.1 the warning says it applies to every harness" "$WL" "applies to every harness"
assert_contains "AC3.1 the warning names the global origin" "$WL" "global"
assert_contains "AC3.1 the warning suggests model_reviewer_light_<harness>" "$WL" "model_reviewer_light_codex"
assert_eq "AC3.1 exactly one warning line for the one key" "1" "$(printf '%s\n' "$OUT" | grep -c 'warning')"
reset
printf 'model_mechanical=mval\n' > "$G"
role check --harness codex
assert_rc "AC3.1 generic model_mechanical -> exit 1" 1
WM="$(printf '%s\n' "$OUT" | grep 'warning' | grep 'model_mechanical')"
[ -n "$WM" ] && t_ok "AC3.1 a warning line names model_mechanical" || t_bad "AC3.1 a warning line names model_mechanical" "$OUT"
assert_contains "AC3.1 the mechanical warning shows the value" "$WM" "mval"
assert_contains "AC3.1 the mechanical warning suggests model_mechanical_<harness>" "$WM" "model_mechanical_codex"
assert_eq "AC3.1 exactly one warning line for model_mechanical" "1" "$(printf '%s\n' "$OUT" | grep -c 'warning')"
reset
printf 'model_reviewer_light=pl\n' > "$L"
role check
assert_rc "AC3.1 a project-level generic model_reviewer_light -> exit 1" 1
assert_contains "AC3.1 ... and the warning names the project origin" "$(printf '%s\n' "$OUT" | grep 'model_reviewer_light')" "project"
reset
printf 'model_tester=t\nmodel_implementer=i\nmodel_reviewer=r\nmodel_reviewer_light=l\nmodel_mechanical=m\n' > "$G"
role check
assert_rc "AC3.1 all five generic keys -> exit 1" 1
assert_eq "AC3.1 one warning line per generic key (five)" "5" "$(printf '%s\n' "$OUT" | grep -c 'warning')"
for k in model_tester model_implementer model_reviewer model_reviewer_light model_mechanical; do
  if printf '%s\n' "$OUT" | grep 'warning' | grep -q "$k="; then t_ok "AC3.1 five keys: a warning for $k"; else t_bad "AC3.1 five keys: a warning for $k" "$OUT"; fi
done
reset
printf 'model_reviewer=rmod\n' > "$G"
role check
assert_eq "AC3.1 model_reviewer alone: one warning, not two (reviewer_light is not reported)" "1" "$(printf '%s\n' "$OUT" | grep -c 'warning')"

echo "role-model.sh v0.22.3 AC3.2/AC3.3: instructions route the two roles"
RMSKILL="$PB_ROOT/skills/playbook-tdd/SKILL.md"
RMHARN="$PB_ROOT/skills/playbook-tdd/references/harnesses.md"   # lane C (v0.26.3) S2: the task-type routing moved here
RMSETUP="$PB_ROOT/skills/playbook-setup/SKILL.md"
rm_flat_has() { # NAME FILE PATTERN
  if tr '\n' ' ' < "$2" 2>/dev/null | tr -s ' ' | grep -qiE -- "$3"; then t_ok "$1"; else t_bad "$1" "pattern [$3] not in the flattened $2"; fi
}
rm_flat_has "AC3.2 SKILL.md names the mechanical model" "$RMSKILL" 'mechanical'
rm_flat_has "AC3.2 references/harnesses.md: mechanical work uses the mechanical model (role-model.sh mechanical or the word model)" "$RMHARN" 'mechanical[^.]{0,200}(model|role-model)|(model|role-model)[^.]{0,120}mechanical'
rm_flat_has "AC3.2 references/harnesses.md: release prep is mechanical work" "$RMHARN" 'mechanical[^.]{0,250}release|release[^.]{0,250}mechanical'
rm_flat_has "AC3.2 references/harnesses.md: counts are mechanical work" "$RMHARN" 'mechanical[^.]{0,250}counts|counts[^.]{0,250}mechanical'
rm_flat_has "AC3.2 references/harnesses.md: weights are mechanical work" "$RMHARN" 'mechanical[^.]{0,250}weights|weights[^.]{0,250}mechanical'
rm_flat_has "AC3.2 references/harnesses.md: formatting is mechanical work" "$RMHARN" 'mechanical[^.]{0,250}formatting|formatting[^.]{0,250}mechanical'
rm_flat_has "AC3.2 references/harnesses.md names reviewer_light" "$RMHARN" 'reviewer_light'
rm_flat_has "AC3.2 references/harnesses.md: reviewer_light is for a diff that only touches tests, docs or skill text" "$RMHARN" 'reviewer_light[^.]{0,250}(only|just)[^.]{0,120}(tests?|docs?|skill)|(only|just)[^.]{0,120}(tests?)[^.]{0,80}(docs?)[^.]{0,80}skill[^.]{0,200}reviewer_light'
rm_flat_has "AC3.2 references/harnesses.md: code changes keep the reviewer model" "$RMHARN" 'code[^.]{0,120}(keep|keeps|use|uses|stay|stays)[^.]{0,80}`?reviewer`?|`?reviewer`?[^.]{0,80}code (change|diff)'
rm_flat_has "AC3.3 playbook-setup SKILL.md lists reviewer_light" "$RMSETUP" 'reviewer_light'
rm_flat_has "AC3.3 playbook-setup SKILL.md lists mechanical" "$RMSETUP" 'mechanical'
rm_flat_has "AC3.3 playbook-setup lists the keys with the per-harness form (model_reviewer_light_<harness>)" "$RMSETUP" 'model_reviewer_light_<harness>|model_reviewer_light_<h>|reviewer_light[^.]{0,80}<harness>'
rm_flat_has "AC3.3 playbook-setup lists the per-harness mechanical key (model_mechanical_<harness>)" "$RMSETUP" 'model_mechanical_<harness>|model_mechanical_<h>|mechanical[^.]{0,80}<harness>'

# --- v0.23.1 AC11.1: list under --harness and PLAYBOOK_HARNESS, every named line with its resolved model
# line_of NAME -> the one line of $OUT that starts with NAME=
line_of() { printf '%s\n' "$OUT" | grep -x "$1=.*"; }
reset
printf 'model_tester=t\nmodel_implementer_codex=ic\nmodel_reviewer=r\nmodel_reviewer_codex=rc\nmodel_mechanical=m\nmodel_mechanical_codex=mc\n' > "$G"
role list --harness codex
assert_rc "AC11.1 list --harness codex exits 0" 0
assert_eq "AC11.1 --harness codex: tester= (generic)" "tester=t" "$(line_of tester)"
assert_eq "AC11.1 --harness codex: implementer= (per-harness)" "implementer=ic" "$(line_of implementer)"
assert_eq "AC11.1 --harness codex: reviewer= (per-harness beats generic)" "reviewer=rc" "$(line_of reviewer)"
assert_eq "AC11.1 --harness codex: reviewer_light= (no own key: the reviewer's model for that harness)" "reviewer_light=rc" "$(line_of reviewer_light)"
assert_eq "AC11.1 --harness codex: mechanical= (per-harness)" "mechanical=mc" "$(line_of mechanical)"
assert_eq "AC11.1 --harness codex: exactly six role lines (v0.24.5 adds spec_reviewer)" "6" "$(printf '%s\n' "$OUT" | grep -c '=')"
export PLAYBOOK_HARNESS=codex
role list
assert_rc "AC11.1 list under PLAYBOOK_HARNESS=codex exits 0" 0
assert_eq "AC11.1 PLAYBOOK_HARNESS: tester=" "tester=t" "$(line_of tester)"
assert_eq "AC11.1 PLAYBOOK_HARNESS: implementer=" "implementer=ic" "$(line_of implementer)"
assert_eq "AC11.1 PLAYBOOK_HARNESS: reviewer=" "reviewer=rc" "$(line_of reviewer)"
assert_eq "AC11.1 PLAYBOOK_HARNESS: reviewer_light=" "reviewer_light=rc" "$(line_of reviewer_light)"
assert_eq "AC11.1 PLAYBOOK_HARNESS: mechanical=" "mechanical=mc" "$(line_of mechanical)"
role list --harness other
assert_eq "AC11.1 --harness other beats PLAYBOOK_HARNESS: tester=" "tester=t" "$(line_of tester)"
assert_eq "AC11.1 --harness other: implementer= (no key for it: session)" "implementer=session" "$(line_of implementer)"
assert_eq "AC11.1 --harness other: reviewer= (generic)" "reviewer=r" "$(line_of reviewer)"
assert_eq "AC11.1 --harness other: reviewer_light= (the generic reviewer)" "reviewer_light=r" "$(line_of reviewer_light)"
assert_eq "AC11.1 --harness other: mechanical= (generic)" "mechanical=m" "$(line_of mechanical)"
unset PLAYBOOK_HARNESS
reset
printf 'model_reviewer=r\nmodel_reviewer_light=rl\nmodel_reviewer_light_codex=rlc\nmodel_tester_codex=tc\nmodel_implementer=i\n' > "$G"
role list --harness codex
assert_eq "AC11.1 own reviewer_light per-harness key wins: reviewer_light=" "reviewer_light=rlc" "$(line_of reviewer_light)"
assert_eq "AC11.1 reviewer= falls to its generic key under codex" "reviewer=r" "$(line_of reviewer)"
assert_eq "AC11.1 tester= per-harness only" "tester=tc" "$(line_of tester)"
assert_eq "AC11.1 implementer= generic" "implementer=i" "$(line_of implementer)"
assert_eq "AC11.1 mechanical= never falls back to another role: session" "mechanical=session" "$(line_of mechanical)"
role list --harness claude-code
assert_eq "AC11.1 reviewer_light= generic key for another harness" "reviewer_light=rl" "$(line_of reviewer_light)"
assert_eq "AC11.1 tester= has no key for another harness: session" "tester=session" "$(line_of tester)"
export PLAYBOOK_HARNESS=codex
role list
assert_eq "AC11.1 PLAYBOOK_HARNESS (second config): reviewer_light=" "reviewer_light=rlc" "$(line_of reviewer_light)"
assert_eq "AC11.1 PLAYBOOK_HARNESS (second config): tester=" "tester=tc" "$(line_of tester)"
unset PLAYBOOK_HARNESS
reset


# ---- v0.24.0 AC2.1-AC2.3 (Full), R6, R7: effort lookup, check of unknown model_* keys, plan ----
echo "AC2.1 --effort: lookup model_<role>_reasoning_effort_<harness>, then model_<role>_reasoning_effort"
reset
role tester --effort
assert_rc "AC2.1 --effort with nothing configured exits 0" 0
assert_eq "AC2.1 --effort with nothing configured prints nothing" "" "$OUT"
role tester --harness codex --effort
assert_eq "AC2.1 --effort with --harness and nothing configured prints nothing" "" "$OUT"
printf 'model_tester_reasoning_effort=high\n' > "$G"
role tester --effort;                     assert_eq "AC2.1 generic effort" "high" "$OUT"
role tester --harness codex --effort;     assert_eq "AC2.1 generic effort applies to a harness without its own key" "high" "$OUT"
role implementer --effort;                assert_eq "AC2.1 the effort is per role (implementer unset)" "" "$OUT"
role reviewer --harness codex --effort;   assert_eq "AC2.1 the effort is per role (reviewer unset)" "" "$OUT"
role tester;                              assert_eq "AC2.1 without --effort the model is printed, not the effort (session)" "session" "$OUT"
printf 'model_tester_reasoning_effort=high\nmodel_tester_reasoning_effort_codex=low\nmodel_tester_reasoning_effort_claude-code=max\n' > "$G"
role tester --harness codex --effort;       assert_eq "AC2.1 per-harness effort beats generic (codex)" "low" "$OUT"
role tester --harness claude-code --effort; assert_eq "AC2.1 per-harness effort with a hyphenated harness" "max" "$OUT"
role tester --harness opencode --effort;    assert_eq "AC2.1 a harness without its own effort key falls back to the generic one" "high" "$OUT"
role tester --effort;                       assert_eq "AC2.1 no harness: only the generic effort applies" "high" "$OUT"
role tester --effort --harness codex
assert_eq "AC2.1 --effort before --harness gives the same answer" "low" "$OUT"
export PLAYBOOK_HARNESS=codex
role tester --effort;                       assert_eq "AC2.1 --effort honours PLAYBOOK_HARNESS" "low" "$OUT"
role tester --harness opencode --effort;    assert_eq "AC2.1 --harness beats PLAYBOOK_HARNESS for the effort" "high" "$OUT"
unset PLAYBOOK_HARNESS
# the effort is independent of the model keys
reset
printf 'model_implementer_codex=imod\nmodel_implementer_reasoning_effort_codex=medium\n' > "$G"
role implementer --harness codex;           assert_eq "AC2.1 the model is unchanged by an effort key" "imod" "$OUT"
role implementer --harness codex --effort;  assert_eq "AC2.1 the effort is printed with --effort" "medium" "$OUT"
printf 'model_implementer_reasoning_effort=high\n' > "$G"
role implementer --effort;                  assert_eq "AC2.1 an effort without a model key: --effort prints it" "high" "$OUT"
role implementer;                           assert_eq "AC2.1 an effort without a model key: the model is still session" "session" "$OUT"
# project conf beats global conf, as for models
reset
printf 'model_reviewer_reasoning_effort=low\n' > "$G"; printf 'model_reviewer_reasoning_effort=high\n' > "$L"
role reviewer --effort;                     assert_eq "AC2.1 project effort beats global effort" "high" "$OUT"
# an empty value counts as unset for the printed effort
reset
printf 'model_tester_reasoning_effort=\n' > "$G"
role tester --effort;                       assert_eq "AC2.1 an empty effort value prints nothing" "" "$OUT"

echo "AC2.1/R6 effort fallback: reviewer_light falls back to the reviewer's effort, mechanical has none"
reset
printf 'model_reviewer_reasoning_effort=high\n' > "$G"
role reviewer_light --effort;               assert_eq "R6 reviewer_light has no effort key: the reviewer's generic effort" "high" "$OUT"
role mechanical --effort;                   assert_eq "R6 mechanical never falls back to the reviewer's effort" "" "$OUT"
printf 'model_reviewer_reasoning_effort=high\nmodel_reviewer_reasoning_effort_codex=max\n' > "$G"
role reviewer_light --harness codex --effort; assert_eq "R6 reviewer_light falls back to the reviewer's per-harness effort first" "max" "$OUT"
role reviewer_light --harness claude --effort; assert_eq "R6 reviewer_light falls back to the reviewer's generic effort for another harness" "high" "$OUT"
role mechanical --harness codex --effort;   assert_eq "R6 mechanical: still no fallback under a harness" "" "$OUT"
printf 'model_reviewer_reasoning_effort=high\nmodel_reviewer_light_reasoning_effort=low\n' > "$G"
role reviewer_light --effort;               assert_eq "R6 reviewer_light's own generic effort beats the reviewer's" "low" "$OUT"
role reviewer --effort;                     assert_eq "R6 the reviewer keeps its own effort" "high" "$OUT"
printf 'model_reviewer_reasoning_effort=high\nmodel_reviewer_light_reasoning_effort_codex=min\nmodel_reviewer_light_reasoning_effort=low\n' > "$G"
role reviewer_light --harness codex --effort; assert_eq "R6 reviewer_light's own per-harness effort beats its generic one" "min" "$OUT"
role reviewer_light --harness claude --effort; assert_eq "R6 reviewer_light's own generic effort for another harness" "low" "$OUT"
printf 'model_reviewer_reasoning_effort_codex=max\nmodel_reviewer_light_reasoning_effort=low\n' > "$G"
role reviewer_light --harness codex --effort; assert_eq "R6 reviewer_light's own generic effort beats the reviewer's per-harness effort (as for models)" "low" "$OUT"
printf 'model_mechanical_reasoning_effort_codex=low\n' > "$G"
role mechanical --harness codex --effort;   assert_eq "R6 mechanical has its own effort keys" "low" "$OUT"
role mechanical --harness claude --effort;  assert_eq "R6 mechanical's per-harness effort is not used for another harness" "" "$OUT"

echo "AC2.1 list: role=model (effort) when an effort is set"
reset
printf 'model_tester_codex=tc\nmodel_tester_reasoning_effort_codex=high\nmodel_implementer_codex=ic\nmodel_reviewer_codex=rc\nmodel_reviewer_reasoning_effort=low\n' > "$G"
role list --harness codex
assert_rc "AC2.1 list exits 0" 0
assert_eq "AC2.1 list: an effort is shown in parentheses" "tester=tc (high)" "$(line_of tester)"
assert_eq "AC2.1 list: no effort set: the line is unchanged" "implementer=ic" "$(line_of implementer)"
assert_eq "AC2.1 list: generic effort shown" "reviewer=rc (low)" "$(line_of reviewer)"
assert_eq "AC2.1 list: reviewer_light shows the reviewer's effort and model it falls back to" "reviewer_light=rc (low)" "$(line_of reviewer_light)"
assert_eq "AC2.1 list: mechanical has no effort fallback" "mechanical=session" "$(line_of mechanical)"
assert_eq "AC2.1 list: exactly six lines (v0.24.5 adds spec_reviewer)" "6" "$(printf '%s\n' "$OUT" | grep -c '=')"
printf 'model_tester_reasoning_effort=high\n' > "$G"
role list
assert_eq "AC2.1 list: a session model with an effort" "tester=session (high)" "$(line_of tester)"
reset
role list
assert_eq "AC2.1 list: nothing configured, no parentheses anywhere" "0" "$(printf '%s\n' "$OUT" | grep -c '(')"
export PLAYBOOK_HARNESS=codex
printf 'model_tester_reasoning_effort_codex=xhigh\nmodel_tester_codex=t1\n' > "$G"
role list
assert_eq "AC2.1 list honours PLAYBOOK_HARNESS for the effort" "tester=t1 (xhigh)" "$(line_of tester)"
unset PLAYBOOK_HARNESS

t_summary
