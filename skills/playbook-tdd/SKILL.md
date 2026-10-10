---
name: playbook-tdd
description: Use when adding or changing behaviour or fixing a bug in code - test-first with separate roles (tester writes failing tests, implementer passes them without touching tests, reviewer checks read-only), enforced by git role gates and evidence; Full or Lite weight by risk. Takes precedence over generic TDD or subagent skills. Skip for docs-only, config-only or spikes.
---

# TDD with separated roles

If a generic TDD or sub-agent skill also applies (for example Superpowers `test-driven-development`
or `subagent-driven-development`), borrow its techniques but keep these roles, gates and the
reviewer's re-run. Their "implementer writes and runs its own tests" model does not apply here.

At **Full** weight: three roles, three fresh contexts. The **orchestrator** (you, in the main
session) coordinates and does not write tests or production code itself, except in `none` mode
(see below). **Lite** weight runs the same discipline in one context (see "Pick the weight").

| Role | Writes | Must not | Prompt |
|---|---|---|---|
| Tester | tests only | production code | `roles/tester.md` |
| Implementer | production code only | any test file (edit, delete, skip, rename) | `roles/implementer.md` |
| Reviewer | the review report only | any file in the repo | `roles/reviewer.md` |

Mechanical enforcement: `~/.agents/playbook/scripts/role-gate.sh check <role> [--base REF]`.
Prompt rules alone are not enough. The gate runs after every role hand-back.

Test infrastructure (test runners, shared test helpers) is a fourth, opt-in role: set the project key
`test_infra_regex` and matching paths classify as `infra`, which neither the tester nor the
implementer may change. Order for an infra change: the tester first writes the tests that exercise
the infra change and sees them fail (`check tester`, commit RED); then a different context makes the
infra change and passes `role-gate.sh check infra --base $RED`. Without the key, infra files count as
tests, as before.

**Why:** an agent that writes both code and tests writes tests that agree with its own mistakes,
and a test nobody saw fail proves nothing. Separate contexts plus a git gate make "the tests were
changed to pass" impossible to miss.

New to TDD? Read `references/tdd-guide.md` first. Test quality and the mutation spot-check are in
`references/test-quality.md`.

## Pick the weight (before Phase 1)

| Weight | Use it when | What runs |
|---|---|---|
| **Full** | the change touches hard-to-reverse ground (public API or data shape, migrations, security, money, outward actions), core business logic, or the user asked for it | everything below: separate tester, implementer and reviewer contexts, gates after each hand-back |
| **Lite** | small and reversible: a bug fix or behaviour tweak inside one module, roughly ≤ 3 production files and ≤ 100 changed lines, nothing from the Full column | the Lite workflow below: one context, still test first and seen failing, gates, evidence, no reviewer sub-agent |
| **Exempt** | see "Exempt" below | no new tests; existing checks still run when cheap |

**Decide consistently.** Full when the change alters existing behaviour of code that is
documented as critical in the repo (billing, payments, auth, personal data), or meets any item in the Full column. A purely
additive change (a new function, existing behaviour untouched) inside such code is Lite unless another
Full item applies. The weight line quotes the file:line or rule that decided it.

State the weight and its reason in one line (in `decisions.md` and the final report). When unsure,
choose Full. **Escalate to Full** as soon as Lite work meets any Full criterion, grows past the size
limit, or a test looks wrong to you (a dispute needs fresh eyes): stop, keep the RED commit, and
continue with separate roles from there.

**Why:** spawning three fresh contexts costs minutes and tokens per slice; for a three-line
reversible fix that cost buys little, while for hard-to-reverse changes it is the cheapest insurance.

### Lite workflow
1. Spec in a few lines (goal, AC with source anchors, weight + reason) in `.agents/handoff/01-spec.md`.
2. Write the test, run it with `proof-run.sh --label red`, and see it fail for the right reason.
   Commit `test(red): ...` and note the sha as `RED`.
3. Write the least code to pass. Do not touch the test. `role-gate.sh check implementer --base $RED`
   must pass (this is what proves you did not bend the test after seeing it fail).
   `role-gate.sh size --base $RED` is the machine check of the Lite limits (≤ 3 production files,
   ≤ 100 changed lines); if it exits 1, escalate to Full.
4. Fresh run of test, lint and typecheck with `proof-run.sh`; one mutation spot-check on the new
   logic is recommended.
5. Final report with `Weight: Lite` and the line "no independent review". If the user wants one,
   run Phase 3 on the result.

### Exempt (say so in one line, e.g. "Exempt (docs-only): no tests added")
- **docs-only**: README, comments, guides; no executable or configuration change.
- **config-only** that does not change runtime behaviour: formatting, editor or lint settings, CI
  caching.
- **throwaway spike**: on a branch that will be deleted, to learn something; the real change is
  then redone at Lite or Full.

**Not exempt:** configuration that changes behaviour (feature flags, environment defaults, routing,
permissions, build or deploy settings), generated code that ships, "small" fixes in business logic,
and anything in the Full column. These are at least Lite.

## Slice size
A slice is one cohesive group of behaviours, about 1 to 5 tests. Avoid one-test slices (a single
test per round trip multiplies the startup cost of every role) and avoid slices that bundle
unrelated behaviours. Split a slice when it touches more than one public surface (for example a
CLI flag and a file format, or two endpoints).

**Why:** each slice costs a tester and an implementer start; cohesive slices keep that cost low
without hiding which behaviour broke.

## Preconditions
- git repo with a clean tree or a known baseline (`git status`).
- Commands known: `conf.sh get test_cmd` (also `lint_cmd`, `typecheck_cmd`). Unknown: detect,
  then confirm with the user (or run `playbook-setup`).
- Baseline: run the test command once with `proof-run.sh --label baseline`. Record tests that
  already fail, so nobody gets blamed for them and nobody "fixes" them in passing.
- `autonomy=ask-before-commit` (default): ask once at the start, "I will create local checkpoint
  commits (test(red) / feat(green)) on branch X. OK?"

## Workflow

### Phase 1: Spec (orchestrator)
Write `.agents/handoff/01-spec.md` from `templates/spec.md`: the source, acceptance criteria with
ids (AC1…) copied **verbatim** from the source with a source anchor each (quote + where), non-goals,
constraints, and **slices**. A slice is one observable behaviour, about 1 to 5 tests. Order the
slices so each one builds on the previous. Nothing goes into the spec that the source did not say.

Gaps, by reversibility: ask (one batched message) only about those that change assertions AND are
hard to reverse; for the rest choose a default, log it in `.agents/handoff/decisions.md` from
`templates/decisions.md`, and mark the code `DECISION[Dn]`. Get the user's OK on the AC list when
the request was ambiguous. Re-read the AC table before each commit.

### Phase 2: Loop per slice (vertical slices, never "all tests first")
For slice S:
1. **RED (tester).** Start a fresh tester with `roles/tester.md` and the inputs it lists. When it
   returns:
   - `role-gate.sh check tester`, which must pass;
   - run the tests yourself with `proof-run.sh --label red-S`: they must fail **for the right reason**
     (see `references/tdd-guide.md#right-reason`);
   - if the tester listed "Stubs needed" (compiled languages): run a short implementer pass limited
     to signatures whose bodies throw "not implemented", gate it as implementer, re-run RED;
   - commit the checkpoint: `git commit -m "test(red): S - <behaviour>"`. Note the sha as `RED`.
2. **GREEN (implementer).** Start a fresh implementer with `roles/implementer.md`, the spec slice
   and the RED sha. When it returns:
   - `role-gate.sh check implementer --base $RED`, which must pass;
   - `proof-run.sh --label green-S -- <test_cmd>`, all green apart from the recorded baseline failures;
   - commit: `git commit -m "feat(green): S - <behaviour>"`.
3. **Dispute.** If the implementer says a test is wrong, it stops and does not edit the test.
   Send the dispute to a **fresh tester**, which fixes the test or explains why it is right. At most
   2 rounds, then ask the user. Never let the implementer resolve a dispute itself.
4. **REFACTOR (optional, implementer).** Only on green, with tests untouched (same gate and
   `--base $RED`), and green again afterwards.

### Phase 3: Review (reviewer, read-only)
**One reviewer per feature, not per slice:** after the last slice, start one fresh reviewer with
`roles/reviewer.md` for the whole diff. Review a single slice early only when that slice alone is
hard to reverse (a migration, a public API change) and later slices build on it.
Prefer a different model (`conf.sh get model_reviewer`). Give it the spec, the base sha from before
slice 1, all slice reports, and the evidence logs. Then run `role-gate.sh check reviewer` (nothing in the repo changed).
Save its report to `.agents/handoff/05-review.md`. Verdict `CHANGES` sends the listed findings
back through a new RED (tester) or GREEN (implementer) round; findings without evidence are dropped.

### Phase 4: Close-out (orchestrator)
- Fresh full run of test, lint and typecheck through `proof-run.sh`, after the last change. Sub-agents
  ran focused tests only; this orchestrator run is the full suite. If it fails, the work goes back
  into a new RED/GREEN round (tester or implementer, as the failure requires); do not report done.
- Log each role run: `bash ~/.agents/playbook/scripts/cost.sh add --role <role> --tokens <N>
  --seconds <S> --model <M> --weight <Full|Lite>`, with tokens as the harness reports them (`0` if unknown,
  never a guess). Then put `cost.sh summary` into the final report.
- `git diff --stat <base>..HEAD`, which must match the spec scope.
- Fill `templates/final-report.md`: AC to tests to evidence, review verdict, assumptions, the
  logged defaults from `decisions.md` (for one batched review), found-not-fixed, and the
  [UNVERIFIED] list.
- Propose learnings (skill `playbook-learn`) when something non-obvious went wrong.
- Do not push or open a PR unless `autonomy=full` or the user asked.

## Starting roles per harness (`conf.sh get subagents`)
Resolve each role's model first: `bash ~/.agents/playbook/scripts/role-model.sh <role> --harness <h>`
(`--harness` takes `claude`, `codex` or `opencode`: the harness you are running in)
and pass it when starting the role. `session` means do not override the session model. Build every
sub-agent prompt from `templates/role-prompt.md` (fixed part first, then spec, then the slice), so
the fixed prefix is identical across runs and can be cached. For the mechanical RED or GREEN step
(gate, then the test command as evidence, optional checkpoint commit) use
`bash ~/.agents/playbook/scripts/tdd-step.sh red|green`.

**Why:** the reviewer should be a different, stronger model, and an unchanged prompt prefix is
cheaper to reuse than a rewritten one.

- **native**: spawn a sub-agent per role, each with a fresh context. Pass the full text of the role
  file plus paths of the allowed inputs, not your own conversation or opinions about the solution.
  - Claude Code: the `Agent`/`Task` tool; pass the resolved model in its `model` parameter (general-purpose for tester and implementer). For the
    reviewer a read-only agent type is fine: it returns the report text and you save it.
  - OpenCode: the `task` tool (a general sub-agent; an explore/read-only one for the reviewer). A model per role needs a
    per-role agent in `opencode.json`, each with its own `model`.
  - Codex: native only with the multi-agent feature enabled. Otherwise use manual mode (`codex exec -m <model>` per role).
- **manual**: run each role as a separate headless process or a new session, with the prompt
  built from the role file and the handoff paths. For example `claude -p "<prompt>"`,
  `codex exec "<prompt>"`, `opencode run "<prompt>"`. Flags differ by version: check `--help`.
  You run the gates between processes, exactly as above.
- **none** (degraded): you play the roles one after another. Between roles, commit, then re-read
  only the handoff files, never your earlier reasoning. Gates still run. Say "degraded mode: roles
  shared one context" in the final report, because the independence guarantee is weaker.

Honest limit: the same model in fresh contexts still shares blind spots. A different reviewer
model, the mutation spot-check, and the user's own review of the AC table reduce this. They do not
remove it.

## Stop and ask the user when
- an ambiguity changes assertions and is hard to reverse (reversible ones: log a default instead);
- a dispute is still open after 2 rounds;
- making a test pass seems to need weakening it, touching unrelated code, or adding a dependency;
- baseline failures make the RED/GREEN signal unreadable.

## Hand-off files (`.agents/handoff/`, git-ignored)
`01-spec.md` · `decisions.md` · `02-tests-<slice>.md` · `03-impl-<slice>.md` · `05-review.md` · `06-final-report.md`
· `evidence/*.log`. Templates are in `templates/`.
