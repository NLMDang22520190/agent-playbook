#!/usr/bin/env bash
# Tests for scripts/role-model.sh: the second half of test-role-model.sh (split in v0.24.19 so that it is not the floor of a CI shard), from "AC2.2/R6 check: unknown
# model_* keys warn (exit 1), known ones do not" to the end. Shared setup: role-model-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/role-model-fixture.sh"

echo "AC2.2/R6 check: unknown model_* keys warn (exit 1), known ones do not"
reset
printf 'model_orchestrator=opus\n' > "$G"
role check
assert_rc "AC2.2 an unknown key model_orchestrator: exit 1" 1
assert_contains "AC2.2 the warning names model_orchestrator" "$OUT" "model_orchestrator"
assert_contains "AC2.2 the output is a warning line" "$OUT" "warning:"
assert_not_contains "AC2.2 not the clean message" "$OUT" "ok: no generic model keys"
reset
printf 'model_foo_bar=x\nmodel_orchestrator=opus\n' > "$G"
role check
assert_rc "AC2.2 two unknown keys: exit 1" 1
assert_contains "AC2.2 names model_foo_bar" "$OUT" "model_foo_bar"
assert_contains "AC2.2 names model_orchestrator too" "$OUT" "model_orchestrator"
assert_eq "AC2.2 one warning line per unknown key" "2" "$(printf '%s\n' "$OUT" | grep -c '^warning:')"
reset
printf 'model_orchestrator=opus\n' > "$L"
role check
assert_rc "AC2.2 an unknown key in the project conf: exit 1" 1
assert_contains "AC2.2 the project-conf key is named" "$OUT" "model_orchestrator"
reset
printf 'model_tester=gen\nmodel_orchestrator=opus\n' > "$G"
role check
assert_rc "AC2.2 a generic key and an unknown key: exit 1" 1
assert_contains "AC2.2 the generic key warning is kept" "$OUT" "model_tester=gen"
assert_contains "AC2.2 the unknown key is also named" "$OUT" "model_orchestrator"
for k in model_unknownrole_codex model_reasoning_effort model_tester_Codex model_tester_reasoning_effort_codex_extra \
         model_reviewer_light_foo_bar model_tester_reasoning_effort_ model_models_tester; do
  reset
  printf '%s=x\n' "$k" > "$G"
  role check
  assert_rc "AC2.2 unknown key $k: exit 1" 1
  assert_contains "AC2.2 unknown key $k is named" "$OUT" "$k"
done
# known keys: model_R, model_R_H, model_R_reasoning_effort, model_R_reasoning_effort_H for every role (R6)
for r in tester implementer reviewer reviewer_light mechanical; do
  reset
  printf 'model_%s_codex=m\nmodel_%s_claude-code=m\nmodel_%s_reasoning_effort=high\nmodel_%s_reasoning_effort_codex=low\nmodel_%s_reasoning_effort_opencode-2=low\n' "$r" "$r" "$r" "$r" "$r" > "$G"
  role check
  assert_rc "R6 $r: per-harness model keys and the effort keys are known: exit 0" 0
  assert_eq "R6 $r: the clean output stays 'ok: no generic model keys'" "ok: no generic model keys" "$OUT"
done
reset
printf 'model_reviewer_light_codex=a\nmodel_reviewer_light_reasoning_effort_codex=b\nmodel_reviewer_light_reasoning_effort=c\nmodel_mechanical_claude=d\n' > "$G"
role check
assert_rc "R6 longest role first: reviewer_light keys are known, not reviewer + a bad harness" 0
assert_eq "R6 reviewer_light/mechanical keys: clean output" "ok: no generic model keys" "$OUT"
reset
printf 'model_tester_reasoning_effort=high\n' > "$L"
role check
assert_rc "R6 a generic model_R_reasoning_effort key gets no warning (the documented fallback)" 0
assert_eq "R6 generic effort key: clean output" "ok: no generic model keys" "$OUT"
reset
printf 'model_tester=gen\n' > "$G"
role check
assert_rc "AC2.2 regression: a generic model key still warns (exit 1)" 1
assert_contains "AC2.2 regression: the generic warning text is unchanged" "$OUT" "applies to every harness; use model_tester_"
reset
printf 'default_autonomy=ask\nmodels_note=x\n' > "$G"
role check
assert_rc "AC2.2 keys that do not start with model_ are ignored" 0
assert_eq "AC2.2 non-model keys: clean output" "ok: no generic model keys" "$OUT"
reset
role check
assert_eq "AC2.2 no conf at all: clean output" "ok: no generic model keys" "$OUT"

echo "AC2.3/R7 plan: the Models line"
reset
role plan
assert_rc "AC2.3 plan exits 0" 0
assert_eq "AC2.3 nothing configured: every role is session, no conf" "Models: tester=session, implementer=session, reviewer=session - session (no conf)" "$OUT"
printf 'model_tester_claude=sonnet\nmodel_implementer_claude=sonnet\nmodel_reviewer_claude=opus\n' > "$G"
role plan --harness claude
assert_eq "AC2.3 three roles from conf" "Models: tester=sonnet, implementer=sonnet, reviewer=opus - from conf" "$OUT"
assert_eq "AC2.3 exactly one line" "1" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
role plan --harness codex
assert_eq "AC2.3 another harness without keys: session, no conf" "Models: tester=session, implementer=session, reviewer=session - session (no conf)" "$OUT"
role plan
assert_eq "AC2.3 no harness: per-harness keys do not apply" "Models: tester=session, implementer=session, reviewer=session - session (no conf)" "$OUT"
printf 'model_tester_claude=sonnet\nmodel_implementer_claude=sonnet\nmodel_reviewer_claude=opus\nmodel_tester_reasoning_effort_claude=high\nmodel_reviewer_reasoning_effort=max\n' > "$G"
role plan --harness claude
assert_eq "AC2.3 the effort is shown only when set (per-harness and generic)" "Models: tester=sonnet (high), implementer=sonnet, reviewer=opus (max) - from conf" "$OUT"
printf 'model_reviewer_claude=opus\n' > "$G"
role plan --harness claude
assert_eq "AC2.3 one role from conf is enough for 'from conf'; the others show session" "Models: tester=session, implementer=session, reviewer=opus - from conf" "$OUT"
printf 'model_tester=gen\nmodel_implementer=gen2\nmodel_reviewer=gen3\n' > "$G"
role plan --harness claude
assert_eq "AC2.3 generic keys resolve like list" "Models: tester=gen, implementer=gen2, reviewer=gen3 - from conf" "$OUT"
printf 'model_tester_claude=sonnet\n' > "$G"; printf 'model_tester_claude=haiku\nmodel_reviewer_claude=opus\n' > "$L"
role plan --harness claude
assert_eq "AC2.3 the project conf beats the global conf in the plan" "Models: tester=haiku, implementer=session, reviewer=opus - from conf" "$OUT"
reset
printf 'model_tester_reasoning_effort=high\n' > "$G"
role plan
assert_contains "AC2.3 a session model with an effort still shows the effort" "$OUT" "tester=session (high)"
reset
printf 'model_reviewer_light_claude=lite\nmodel_mechanical_claude=mech\n' > "$G"
role plan --harness claude
assert_not_contains "AC2.3 reviewer_light is not part of the plan line" "$OUT" "reviewer_light"
assert_not_contains "AC2.3 mechanical is not part of the plan line" "$OUT" "mechanical"
assert_contains "AC2.3 the line starts with Models:" "$OUT" "Models: tester="
reset
printf 'model_tester_codex=tc\nmodel_implementer_codex=ic\nmodel_reviewer_codex=rc\nmodel_tester_claude=tcl\n' > "$G"
export PLAYBOOK_HARNESS=codex
role plan
assert_eq "AC2.3/R6 plan honours PLAYBOOK_HARNESS" "Models: tester=tc, implementer=ic, reviewer=rc - from conf" "$OUT"
role plan --harness claude
assert_eq "AC2.3/R6 --harness beats PLAYBOOK_HARNESS in plan" "Models: tester=tcl, implementer=session, reviewer=session - from conf" "$OUT"
unset PLAYBOOK_HARNESS
role plan --harness "bad harness";  assert_rc "AC2.3 plan: an invalid harness exits 2" 2
role plan --harness;                assert_rc "AC2.3 plan: --harness without a value exits 2" 2
role plan --bogus;                  assert_rc "AC2.3 plan: an unknown option exits 2" 2
reset
role no-such-command
assert_rc "R6 the usage error exits 2" 2
assert_contains "R6 the usage line mentions plan" "$OUT" "plan"
reset


echo "v0.24.0 review round 2 F5: a key present in any conf counts as from conf, even when it says session"
reset
printf 'model_tester_claude=session\n' > "$G"
role plan --harness claude
assert_eq "F5 an explicit model_tester_claude=session in the global conf: from conf" "Models: tester=session, implementer=session, reviewer=session - from conf" "$OUT"
reset
printf 'model_reviewer_claude=session\n' > "$L"
role plan --harness claude
assert_eq "F5 an explicit session key in the project conf: from conf" "Models: tester=session, implementer=session, reviewer=session - from conf" "$OUT"
reset
printf 'model_implementer=session\n' > "$G"
role plan --harness claude
assert_eq "F5 an explicit generic session key: from conf" "Models: tester=session, implementer=session, reviewer=session - from conf" "$OUT"
reset
printf 'model_tester_codex=session\n' > "$G"
role plan --harness claude
assert_eq "F5 a session key of another harness does not count" "Models: tester=session, implementer=session, reviewer=session - session (no conf)" "$OUT"
reset
role plan --harness claude
assert_eq "F5 nothing set at all: session (no conf)" "Models: tester=session, implementer=session, reviewer=session - session (no conf)" "$OUT"
reset
echo "v0.24.1: a harness name that makes model_<role>_<H> equal another role's key is rejected"
MSG="harness name 'light' collides with role reviewer_light"
reset
printf 'model_reviewer=rm\nmodel_reviewer_light=lm\n' > "$G"
role reviewer --harness light
assert_rc "v0.24.1 reviewer --harness light exits 2" 2
assert_contains "v0.24.1 reviewer --harness light says why" "$OUT" "$MSG"
role list --harness light
assert_rc "v0.24.1 list --harness light exits 2" 2
assert_contains "v0.24.1 list --harness light says why" "$OUT" "$MSG"
role plan --harness light
assert_rc "v0.24.1 plan --harness light exits 2" 2
assert_contains "v0.24.1 plan --harness light says why" "$OUT" "$MSG"
role check --harness light
assert_rc "v0.24.1 check --harness light exits 2" 2
assert_contains "v0.24.1 check --harness light says why" "$OUT" "$MSG"
role reviewer --effort --harness light
assert_rc "v0.24.1 reviewer --effort --harness light exits 2" 2
assert_contains "v0.24.1 reviewer --effort --harness light says why" "$OUT" "$MSG"
export PLAYBOOK_HARNESS=light
role reviewer
assert_rc "v0.24.1 PLAYBOOK_HARNESS=light reviewer exits 2" 2
assert_contains "v0.24.1 PLAYBOOK_HARNESS=light reviewer says why" "$OUT" "$MSG"
role list
assert_rc "v0.24.1 PLAYBOOK_HARNESS=light list exits 2" 2
role plan
assert_rc "v0.24.1 PLAYBOOK_HARNESS=light plan exits 2" 2
role check
assert_rc "v0.24.1 PLAYBOOK_HARNESS=light check exits 2" 2
role reviewer --effort
assert_rc "v0.24.1 PLAYBOOK_HARNESS=light --effort exits 2" 2
assert_contains "v0.24.1 PLAYBOOK_HARNESS=light --effort says why" "$OUT" "$MSG"
unset PLAYBOOK_HARNESS

reset
printf 'model_reviewer=rm\nmodel_reviewer_light=lm\nmodel_reviewer_codex=cx\nmodel_reviewer_opencode=oc\nmodel_reviewer_claude=cl\nmodel_reviewer_open-code=ocd\n' > "$G"
for h in codex opencode claude open-code; do
  role reviewer --harness "$h"
  assert_rc "v0.24.1 reviewer --harness $h still exits 0" 0
done
role reviewer --harness codex;     assert_eq "v0.24.1 codex unchanged" "cx" "$OUT"
role reviewer --harness opencode;  assert_eq "v0.24.1 opencode unchanged" "oc" "$OUT"
role reviewer --harness claude;    assert_eq "v0.24.1 claude unchanged" "cl" "$OUT"
role reviewer --harness open-code; assert_eq "v0.24.1 open-code unchanged" "ocd" "$OUT"

reset
printf 'model_reviewer=rm\nmodel_reviewer_light=lm\n' > "$G"
role reviewer_light
assert_rc "v0.24.1 reviewer_light role still exits 0" 0
assert_eq "v0.24.1 model_reviewer_light=X resolves for the reviewer_light role" "lm" "$OUT"
role reviewer_light --harness codex
assert_eq "v0.24.1 reviewer_light with another harness still reads model_reviewer_light" "lm" "$OUT"
reset


echo "v0.24.5: the spec_reviewer role (Full weight's spec reviewer sub-agent) falls back to the reviewer"
reset
role spec_reviewer
assert_rc "v0.24.5 spec_reviewer is a known role (exit 0)" 0
assert_eq "v0.24.5 spec_reviewer with nothing configured -> session" "session" "$OUT"
reset
printf 'model_reviewer=rv\n' > "$G"
role spec_reviewer
assert_eq "v0.24.5 spec_reviewer falls back to the reviewer's generic model" "rv" "$OUT"
reset
printf 'model_reviewer=rv\nmodel_spec_reviewer=sv\n' > "$G"
role spec_reviewer
assert_eq "v0.24.5 model_spec_reviewer beats the reviewer's model" "sv" "$OUT"
role reviewer
assert_eq "v0.24.5 the reviewer itself is not changed by model_spec_reviewer" "rv" "$OUT"
reset
printf 'model_reviewer_codex=rcx\nmodel_reviewer=rv\n' > "$G"
role spec_reviewer --harness codex
assert_eq "v0.24.5 spec_reviewer falls back to the reviewer's per-harness model" "rcx" "$OUT"
reset
printf 'model_reviewer_codex=rcx\nmodel_spec_reviewer_codex=scx\nmodel_spec_reviewer=sv\n' > "$G"
role spec_reviewer --harness codex
assert_eq "v0.24.5 model_spec_reviewer_<harness> wins" "scx" "$OUT"
role spec_reviewer --harness claude
assert_eq "v0.24.5 another harness reads the generic model_spec_reviewer" "sv" "$OUT"
reset
printf 'model_reviewer_reasoning_effort=high\n' > "$G"
role spec_reviewer --effort
assert_eq "v0.24.5 spec_reviewer effort falls back to the reviewer's effort" "high" "$OUT"
reset
printf 'model_reviewer_reasoning_effort=high\nmodel_spec_reviewer_reasoning_effort_codex=low\n' > "$G"
role spec_reviewer --effort --harness codex
assert_eq "v0.24.5 model_spec_reviewer_reasoning_effort_<harness> wins" "low" "$OUT"
reset
printf 'model_reviewer=rv\nmodel_spec_reviewer=sv\n' > "$G"
role list
assert_eq "v0.24.5 list has the spec_reviewer line" "spec_reviewer=sv" "$(printf '%s\n' "$OUT" | grep -x 'spec_reviewer=.*')"
assert_eq "v0.24.5 list puts spec_reviewer right after reviewer" "reviewer=rv
spec_reviewer=sv" "$(printf '%s\n' "$OUT" | grep -A1 -x 'reviewer=.*')"
reset
printf 'model_tester=t\nmodel_implementer=i\nmodel_reviewer=rv\nmodel_spec_reviewer=sv\n' > "$G"
role plan
assert_eq "v0.24.5 plan shows spec_reviewer after the reviewer when it differs" "Models: tester=t, implementer=i, reviewer=rv, spec_reviewer=sv - from conf" "$OUT"
reset
printf 'model_tester=t\nmodel_implementer=i\nmodel_reviewer=rv\n' > "$G"
role plan
assert_eq "v0.24.5 plan hides spec_reviewer when it equals the reviewer" "Models: tester=t, implementer=i, reviewer=rv - from conf" "$OUT"
reset
printf 'model_spec_reviewer=sv\n' > "$G"
role plan
assert_eq "v0.24.5 a spec_reviewer key alone counts as from conf" "Models: tester=session, implementer=session, reviewer=session, spec_reviewer=sv - from conf" "$OUT"
reset
printf 'model_spec_reviewer=sv\nmodel_spec_reviewer_codex=sc\nmodel_spec_reviewer_reasoning_effort=low\nmodel_spec_reviewer_reasoning_effort_codex=high\n' > "$G"
role check
assert_rc "v0.24.5 check knows every model_spec_reviewer key form (only generic warnings)" 1
assert_not_contains "v0.24.5 check does not call model_spec_reviewer_codex unknown" "$OUT" "unknown key model_spec_reviewer_codex"
assert_not_contains "v0.24.5 check does not call the spec_reviewer effort keys unknown" "$OUT" "unknown key model_spec_reviewer_reasoning"
assert_contains "v0.24.5 check warns about the generic model_spec_reviewer" "$OUT" "model_spec_reviewer=sv"
reset
printf 'model_spec_reviewerx=1\n' > "$G"
role check
assert_contains "v0.24.5 check still flags a misspelt spec_reviewer key" "$OUT" "unknown key model_spec_reviewerx"
reset
role spec_reviewer --harness light
assert_rc "v0.24.5 the harness collision check still works with spec_reviewer in the lists" 2
assert_contains "v0.24.5 the collision names reviewer_light" "$OUT" "collides with role reviewer_light"
reset
t_summary
