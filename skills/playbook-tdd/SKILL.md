---
name: playbook-tdd
description: Use when adding or changing behaviour or fixing a bug in code - test-first with separate roles (tester writes failing tests, implementer passes them without touching tests, reviewer checks read-only), enforced by git role gates and evidence; Lite or Full weight by risk, also when the user says "quick" (runs Lite). Takes precedence over generic TDD or subagent skills. Skip for docs-only, config-only or spikes.
---

# TDD with separated roles

At **Full** weight the **orchestrator** (you) coordinates and writes no tests or
production code, except in `none` mode (see below); **Lite** runs in one context (see "Pick the weight").

| Role | Writes | Must not | Prompt |
|---|---|---|---|
| Tester | tests only | production code | `roles/tester.md` |
| Implementer | production code only | any test file (edit, delete, skip, rename) | `roles/implementer.md` |
| Reviewer | the review report only | any file in the repo | `roles/reviewer.md` |
| Spec reviewer (Full) | the spec review report only | any file in the repo | `roles/spec-reviewer.md` |

Mechanical enforcement: `~/.agents/playbook/scripts/role-gate.sh check <role> [--base REF]`.
Before each role and every pass, record `git rev-parse HEAD` as the role's `--base` (a committing role is judged). The gate runs after every hand-back.

## Pick the weight (before Phase 1)

| Weight | Use it when | What runs |
|---|---|---|
| **Full** | the change touches hard-to-reverse ground (a change to an existing public API or data shape, migrations, security, money, outward actions), core business logic, or the user asked for it | everything below: separate tester, implementer and reviewer contexts, gates after each hand-back |
| **Lite** | small and reversible: a bug fix or behaviour tweak inside one module, roughly ≤ 3 production files and ≤ 100 changed lines, nothing from the Full column | the Lite workflow below: one context, still test first and seen failing, gates, evidence, no reviewer sub-agent |
| **Exempt** | see "Exempt" below | no new tests; existing checks still run when cheap |

Incident, upgrade, migration and debug work, and squashing before a merge: `references/<kind>.md` (incident, upgrade, migration, debug, team) sets the weight and the steps.

**Decide consistently.** Code is critical when the repo's documentation or notes say it serves billing, payments, auth or personal data.
Full when the change alters or removes existing behaviour of critical code, or meets any item in the Full column.
A purely additive change inside critical code, such as a new internal helper or a new function beside existing ones that leaves existing behaviour untouched, changes no existing public API or data shape and moves no money, is Lite unless another Full item applies.
A new exported function is additive and changes no existing public API; removing or renaming an exported symbol is a public API change: Full.
The weight line quotes the file:line or rule that decided it.

State the weight and its reason in one line (in `decisions.md` and the final report). When unsure,
choose Full. **Escalate to Full** as soon as Lite work meets any Full criterion, grows past the size
limit, or a test looks wrong to you (a dispute needs fresh eyes): stop, keep the RED commit, and
continue with separate roles from there.

User override, "quick" and message-text changes: `references/weights.md`.


### Lite workflow
1. Spec in a few lines (goal, AC with source anchors, weight + reason) in `.agents/handoff/01-spec.md`,
   with short `## Understanding` and `## Impact` sections (as in Phase 1) written before any test or code.
   An ambiguous, hard-to-reverse reading (or a missing confirmed worked example, the oracle of Phase 1) is asked before any code, in one
   batched question; else a logged default.
2. Write the test (unconfirmed oracle Dn: the test's name or a comment carries `Dn` or `[UNVERIFIED]`), run it with
   `proof-run.sh --label red`, and see it fail for the right reason.
   Commit `test(red): ...` and note the sha as `RED`.
3. Write the least code to pass. Do not touch the test. `role-gate.sh check implementer --base $RED`
   must pass. `role-gate.sh size --base $RED` checks the Lite limits;
   if it exits 1, escalate to Full; exit 3: fix named file, run again.
4. Fresh run of test, lint and typecheck with `proof-run.sh`; one mutation spot-check on the new
   logic is recommended. On an unconfirmed oracle, a killed mutant pins the assumed reading; it does not catch a bug. A user-visible change (UI, HTTP API, CLI output, file format) needs one
   real observation of the behaviour in this session (screenshot or browser read, curl, the CLI
   command); unit tests alone are not enough. If it cannot be run, say so under "Not checked".
5. Final report with `Weight: Lite`, the line "no independent review", the `## Request coverage` section (every raw-request sentence), the `## Not checked` section, a Confidence column in the AC table, a `## Pre-mortem` (for Lite one line per risk is enough; a test on Dn pins the assumed reading, cannot tell which is right).
   The report always ENDS with exactly this line, copied verbatim, never paraphrased: `**Playbook feedback:** <captured fb- ids or none>`.
   If a rule,
   gate or script misfired, capture it with `playbook-feedback` first, with no need to ask.

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
A slice is one cohesive group of behaviours, about 1 to 5 tests. Avoid one-test slices and slices
that bundle unrelated behaviours. Split a slice when it touches more than one public surface (for example a
CLI flag and a file format, or two endpoints).

## Preconditions
- git repo with a clean tree or a known baseline (`git status`). Dirty tree: `references/harnesses.md`. Concurrent tasks: `--scope`, see `references/harnesses.md`.
- Baseline: run the test command once with `proof-run.sh --label baseline`. Record tests that
  already fail, so nobody gets blamed for them and nobody "fixes" them in passing.
- `autonomy=ask-before-commit` (default): ask once at the start, "I will create local checkpoint
  commits (test(red) / feat(green)) on branch X. OK?"

## Workflow

At Full, read `references/full.md` before Phase 1 (spec review, disputes, **One reviewer per feature, not per slice**); log defaults from `templates/decisions.md`. Also `references/parallel.md`, `references/cost.md`.

## When the user says it is wrong
Do not defend the result and do not patch at once; in a production incident, mitigate first (`references/incident.md`).
Steps: `references/wrong.md`.


## Starting roles per harness (`conf.sh get subagents`)
Resolve each role's model first: `bash ~/.agents/playbook/scripts/role-model.sh <role> --harness <h>`
(`claude`, `codex` or `opencode`: the harness you run in)
and pass it when starting the role. `session` means do not override the session model.
A configured model is binding: the agent never upgrades or downgrades it on its own judgement (a hard task or Full weight is not a reason). Before starting roles, print `role-model.sh plan --harness <h>`.
Ask the user once, with the reason and the cost difference, only when you want a different model, when a role resolves to session on a Full task, or when confirm_models=always.
confirm_models=on-change is the default (an unknown value counts as on-change); never ask when confirm_models=never. Headless: use the conf, never upgrade, never block.
How to start roles in each harness (native, manual, none), pass the model and effort, and cache the prompt prefix: `references/harnesses.md`.
Native roles get the full role file plus the allowed input paths, never your conversation or opinions. In `none` mode play the roles one after another: commit between roles, re-read only the hand-off files, still run the gates, and report "degraded mode: roles shared one context".

**Why:** a different, stronger reviewer model catches what the author's model misses, and a role that
never saw your reasoning cannot inherit its mistakes.

## Stop and ask the user when
- an ambiguity changes assertions and is hard to reverse (reversible ones: log a default instead);
- a dispute is still open after 2 rounds;
- making a test pass seems to need weakening it, touching unrelated code, or adding a dependency;
- baseline failures make the RED/GREEN signal unreadable.

In a non-interactive run (CI, headless, or the request says nobody will answer), when a sub-agent fails, is interrupted or times out, the orchestrator never stops to ask. It continues at Lite in its own context (or finishes the current phase itself) and reports that in the final report.


## Hand-off files (`.agents/handoff/`, git-ignored)
`state.md` · `01-spec.md` · `01b-spec-review.md` · `decisions.md` · `02-tests-<slice>.md` · `03-impl-<slice>.md` · `05-review.md` · `06-final-report.md`
· `evidence/*.log`. Templates are in `templates/`.