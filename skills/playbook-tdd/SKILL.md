---
name: playbook-tdd
description: Use when adding or changing behaviour or fixing a bug in code - test-first with separate roles (tester writes failing tests, implementer passes them without touching tests, reviewer checks read-only), enforced by git role gates and evidence; Lite or Full weight by risk, also when the user says "quick" (runs Lite). Takes precedence over generic TDD or subagent skills. Skip for docs-only, config-only or spikes.
---

# TDD with separated roles

If a generic TDD or sub-agent skill applies (for example Superpowers `test-driven-development`
or `subagent-driven-development`), borrow its techniques but keep these roles, gates and the
reviewer's re-run, not their "implementer writes and runs its own tests" model.

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

Test infrastructure (test runners, shared test helpers) is a fourth, opt-in role: set the project key
`test_infra_regex` and matching paths classify as `infra`, which neither the tester nor the
implementer may change. Order: the tester first writes tests that exercise the infra change and sees
them fail (`check tester --base <sha before the role>`, commit RED); then a different context makes the change and passes
`role-gate.sh check infra --base $RED`. Without the key, infra files count as tests.

**Why:** an agent that writes both code and tests writes tests that agree with its own mistakes,
and a test nobody saw fail proves nothing. Separate contexts plus a git gate make "the tests were
changed to pass" impossible to miss.

New to TDD? Read `references/tdd-guide.md` first. Test quality and the mutation spot-check are in
`references/test-quality.md`.

## Pick the weight (before Phase 1)

| Weight | Use it when | What runs |
|---|---|---|
| **Full** | the change touches hard-to-reverse ground (a change to an existing public API or data shape, migrations, security, money, outward actions), core business logic, or the user asked for it | everything below: separate tester, implementer and reviewer contexts, gates after each hand-back |
| **Lite** | small and reversible: a bug fix or behaviour tweak inside one module, roughly ≤ 3 production files and ≤ 100 changed lines, nothing from the Full column | the Lite workflow below: one context, still test first and seen failing, gates, evidence, no reviewer sub-agent |
| **Exempt** | see "Exempt" below | no new tests; existing checks still run when cheap |

**Decide consistently.** Code is critical when the repo's documentation or notes say it serves billing, payments, auth or personal data.
Full when the change alters or removes existing behaviour of critical code, or meets any item in the Full column.
A purely additive change inside critical code, such as a new internal helper or a new function beside existing ones that leaves existing behaviour untouched, changes no existing public API or data shape and moves no money, is Lite unless another Full item applies.
A new exported function is additive and changes no existing public API; removing or renaming an exported symbol is a public API change: Full.
A change limited to user-visible message or comment text (a typo, a wording fix), with no control flow and no data shape touched, is Lite even in a sensitive module, provided the string is not parsed, matched or sent as data (an error code, a key, a log format or a message another system matches on is data, so Full applies). State the sensitivity as a risk line in the spec and the report (for example "risk: billing module, message text only"), not as the reason for Full.
The weight line quotes the file:line or rule that decided it.

State the weight and its reason in one line (in `decisions.md` and the final report). When unsure,
choose Full. **Escalate to Full** as soon as Lite work meets any Full criterion, grows past the size
limit, or a test looks wrong to you (a dispute needs fresh eyes): stop, keep the RED commit, and
continue with separate roles from there.

**User override (Full to Lite).** When the work meets a Full criterion and the user asks for Lite, ask once, naming the Full
trigger (a file:line or rule) and what is lost: no independent reviewer, no separate contexts; in a headless or non-interactive
run follow the user with no question. Record `Weight: Lite (user override; Full criteria: <x>)` in decisions.md and the final report.
The tests are never skipped: the test comes first and is seen failing, role gates and evidence still run; the skip-tests rule is unchanged. The override covers only the Full criteria named in the question; a new Full criterion, passing the size limit, or a test that looks wrong still escalates (ask again).

**The user says "quick"** (or "quick one", "do it quick"): that counts as asking for Lite; run Lite at once with the label `Weight: Lite (user said quick)`, test first and seen failing, the skip-tests rule unchanged.
If the work meets a Full criterion, the user override above applies, with its label. If quick work grows past the Lite size limit
with no Full criterion, ask once before going to Full; headless, stay Lite and label it (over the size limit).

**Why:** three fresh contexts cost minutes and tokens per slice: little gain for a small
reversible fix.

### Lite workflow
1. Spec in a few lines (goal, AC with source anchors, weight + reason) in `.agents/handoff/01-spec.md`,
   with short `## Understanding` and `## Impact` sections (as in Phase 1) written before any test or code.
   An ambiguous, hard-to-reverse reading (or a missing oracle, Phase 1) is asked before any code, in one
   batched question; else a logged default.
2. Write the test, run it with `proof-run.sh --label red`, and see it fail for the right reason.
   Commit `test(red): ...` and note the sha as `RED`.
3. Write the least code to pass. Do not touch the test. `role-gate.sh check implementer --base $RED`
   must pass. `role-gate.sh size --base $RED` checks the Lite limits;
   if it exits 1, escalate to Full.
4. Fresh run of test, lint and typecheck with `proof-run.sh`; one mutation spot-check on the new
   logic is recommended. A user-visible change (UI, HTTP API, CLI output, file format) needs one
   real observation of the behaviour in this session (screenshot or browser read, curl, the CLI
   command); unit tests alone are not enough. If it cannot be run, say so under "Not checked".
5. Final report with `Weight: Lite`, the line "no independent review", the `## Request coverage` section (every raw-request sentence), the `## Not checked` section, a Confidence column in the AC table, a `## Pre-mortem` (for Lite one line per risk is enough).
   The report always ENDS with exactly this line, copied verbatim, never paraphrased: `**Playbook feedback:** <captured fb- ids or none>`.
   If the user wants a review, run Phase 3 on the result. If a rule,
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

**Why:** each slice costs a tester and an implementer start; cohesive slices keep that cost low.

## Preconditions
- git repo with a clean tree or a known baseline (`git status`). With a dirty tree, run `role-gate.sh snapshot` before the first role, pass `--baseline <file>` to every gate and to `tdd-step.sh` (check the digest matches), or commit only the role's paths by hand.
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
constraints, and **slices**, each building on the previous. Nothing goes into the spec that the source did not say.

**Regression corpus.** When a change replaces or rewrites existing logic, the spec lists the regression corpus
(`## Regression corpus`): the old inputs and the earlier bugs, each with its expected result. The corpus comes from the existing
code and tests plus the earlier bug reports, not from the source. The first RED covers
the whole corpus, so a rewrite cannot quietly drop a case an earlier round fixed.

Before the ACs, write `## Understanding` (the request restated in your own words, a scan log with each
search command, its hit count and the files read, other readings and why this one, in and out of scope) and
`## Impact` (who calls or uses what changes: command, hits, file:line). Search for every place the request
touches before you fix the scope.

**Spec review (Full).** Run the spec reviewer (`roles/spec-reviewer.md`) before the first tester: a fresh
context gets the raw request verbatim and `01-spec.md`, re-runs your searches, and compares every request
sentence with the ACs. Its report is its only output: the orchestrator saves it to `.agents/handoff/01b-spec-review.md` and
runs `role-gate.sh check reviewer --base <sha before the role>`. A REVISE verdict goes back to the spec (fix it, then review again; after 2
rounds ask the user). Only an OK lets the first tester start. Lite has no spec reviewer.

Gaps, by reversibility: a reading that is ambiguous and hard to reverse is asked before any
code, in one batched message; for the rest choose a default, log it in `.agents/handoff/decisions.md` from
`templates/decisions.md`, and mark the code `DECISION[Dn]`. Get the user's OK on the AC list when
the request was ambiguous. Re-read the AC table before each commit.

Oracle rule: when the request hinges on an ambiguous direction, unit, sign or convention, the spec needs a worked example with a concrete expected result, confirmed by the user or a source document and recorded as an AC that the tests use verbatim; without one, ask (headless: log it in decisions.md as open and label every claim that depends on it [UNVERIFIED]); details: `references/tdd-guide.md#oracle`.

### Phase 2: Loop per slice (vertical slices, never "all tests first")
**Context pack.** The orchestrator builds a context pack once per slice from the spec's Impact section and scan log, and puts it into section 2b of the role prompt (`templates/role-prompt.md`): the files to read with line ranges (path:line-line), the functions or sections involved, short excerpts and the commands to run. The role reads the pack first and opens other files only when it is not enough.

For slice S:
1. **RED (tester).** Start a fresh tester with `roles/tester.md` and the inputs it lists. When it
   returns:
   - `role-gate.sh check tester --base <sha before the role>`, which must pass;
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

**First-slice checkpoint.** When more than one slice repeats a pattern (screens, endpoints or files), in an
interactive run show the first finished slice to the user and wait for an OK before the rest. With
`autonomy=full`, show it in the report and do not wait. In a non-interactive run, continue without waiting and log in
`decisions.md` that the checkpoint was skipped.

**Why:** a wrong pattern copied into five slices costs five fixes.

**Parallel slices.** Slices whose files are disjoint (per the spec's Impact section)
may run in parallel: each slice gets its own git worktree on its own branch, where its tester then its
implementer work, with its own red and green commits and role gates (`role-gate.sh check ... --base` the
slice's own RED sha, run inside that worktree). The orchestrator merges the slice branches into the feature branch.
A merge conflict means the slices were not disjoint, so those slices go back to serial work. Slices that
share a file stay serial from the start. After the merge, one review covers the merged feature (Phase 3), never
one per parallel slice. Remove the slice worktrees once their branches are merged.

**Why:** disjoint slices cannot break each other.

### Phase 3: Review (reviewer, read-only)
**One reviewer per feature, not per slice:** after the last slice, start one fresh reviewer with
`roles/reviewer.md` for the whole diff. Review a single slice early only when that slice alone is
hard to reverse (a migration, a public API change) and later slices build on it.
Prefer a different model (resolve it with `role-model.sh reviewer --harness <h>`). Give it the spec, the base sha from before
slice 1, all slice reports, and the evidence logs. Then run `role-gate.sh check reviewer --base <sha before the role>` (nothing in the repo changed).
Save its report to `.agents/handoff/05-review.md`. Verdict `CHANGES` sends the listed findings
back through a new RED (tester) or GREEN (implementer) round; findings without evidence are dropped.
Release speed rules (review-round cap, introduced vs pre-existing findings, per-item weight, slow runs once) are in `references/release.md`.

### Phase 4: Close-out (orchestrator)
- Fresh full run of test, lint and typecheck through `proof-run.sh`, after the last change. Sub-agents
  ran focused tests only; this orchestrator run is the full suite. If it fails, the work goes back
  into a new RED/GREEN round (tester or implementer, as the failure requires); do not report done.
- Log each role run: `bash ~/.agents/playbook/scripts/cost.sh add --role <role> --tokens <N>
  --seconds <S> --model <M> --weight <Full|Lite> --phase <spec|red|green|review|fix|release> --rework <N>
  --majors <N> --task <id>`, with tokens as the harness reports them (`0` if unknown, never a guess); `--rework` is the
  rework round (0 = first pass) and `--majors` the review majors found. Then put `cost.sh summary` into the
  final report's Cost section.
- `git diff --stat <base>..HEAD`, which must match the spec scope.
- For a user-visible change the gates include one real observation of the behaviour in this session
  (screenshot or browser read, curl, the CLI command), as `playbook-proof` describes; unit tests alone are not enough. If it cannot be run, it goes under "Not checked".
- Fill `templates/final-report.md`: the request coverage (each sentence of the raw request, verbatim: done where, read as, or not done), AC to tests to evidence with a confidence for each AC, review verdict, assumptions, the
  logged defaults from `decisions.md` (for one batched review), found-not-fixed, and the
  [UNVERIFIED] list. Also fill `## Not checked` (what was not exercised) and `## Pre-mortem` (three ways
  the result could still be wrong, each with the command run to check it and its outcome).
- The report ENDS with exactly the line `**Playbook feedback:** <captured fb- ids or none>`, copied verbatim from `templates/final-report.md`, never paraphrased, with nothing after it.
- When sub-agents ran, the report has the line `**Models used:** tester=<m> (<effort>), implementer=..., reviewer=... (Lite: session, one context)`, copied verbatim from `templates/final-report.md` with the models filled in, placed before `## Learnings proposed`; naming the models only in prose is not enough.
- Optional calibration: when role runs were logged with `--task <id>`, `cost.sh calibrate` shows per weight how many
  review majors and rework rounds the tasks had; advice only, it changes no setting.
- Propose learnings (skill `playbook-learn`) when something non-obvious went wrong.
- If a playbook rule, gate or script misfired during the task (a false positive, a wrong verdict, a check that let something through), capture it with skill `playbook-feedback` before the final report, with no need to ask (capture is local): one line per misfire, with its evidence.
- Do not push or open a PR unless `autonomy=full` or the user asked.

## When the user says it is wrong
Do not defend the result and do not patch at once.
1. Restate in two lines what the user expected and what was delivered.
2. Classify the cause as one of: misread request, missed place (scan), wrong assumption, not verified
   live, real bug. Give the evidence for that cause (a command and its output, or a file:line).
3. Fix it test-first: a failing test or eval for the miss, seen failing, then the fix. For a docs-only
   (Exempt) misread, fix it and re-check the result against the request; no test is needed.
4. If the cause is a playbook gap, capture it with `playbook-feedback` (kind `gap`, source `user`) and
   propose a regression eval scenario in the item. If the cause is specific to this project, propose a
   lesson with `playbook-learn` instead.

**Why:** a patch without a named cause fixes one symptom and repeats the miss.

## Starting roles per harness (`conf.sh get subagents`)
Resolve each role's model first: `bash ~/.agents/playbook/scripts/role-model.sh <role> --harness <h>`
(`claude`, `codex` or `opencode`: the harness you run in)
and pass it when starting the role. `session` means do not override the session model.
A configured model is binding: the agent never upgrades or downgrades it on its own judgement (a hard task or Full weight is not a reason). Before starting roles, print `role-model.sh plan --harness <h>`.
Ask the user once, with the reason and the cost difference, only when you want a different model, when a role resolves to session on a Full task, or when confirm_models=always.
confirm_models=on-change is the default (an unknown value counts as on-change); never ask when confirm_models=never. Headless: use the conf, never upgrade, never block.
Two more roles route by task type. Mechanical work (release prep, counts, weights, formatting) uses the `mechanical` model (`role-model.sh mechanical`), which never falls back to another role's model. Use `reviewer_light` for a review of a diff that only touches tests, docs or skill text; code changes keep the `reviewer` model (`reviewer_light` falls back to it when unset). Build every
sub-agent prompt from `templates/role-prompt.md`. For the mechanical RED or GREEN step
(gate, then the test command as evidence, optional checkpoint commit) use
`bash ~/.agents/playbook/scripts/tdd-step.sh red|green` (`--base` red, `--baseline` both).
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

## Resuming
The orchestrator keeps `.agents/handoff/state.md` (from `templates/state.md`) up to date: it updates the file
after each phase (spec, each RED, each GREEN, review, close-out) with the phase, the slice, the last sha per role,
the next step and the open questions. When a session resumes or a context was lost, read `state.md` first, then
the other hand-off files.

## Hand-off files (`.agents/handoff/`, git-ignored)
`state.md` · `01-spec.md` · `01b-spec-review.md` · `decisions.md` · `02-tests-<slice>.md` · `03-impl-<slice>.md` · `05-review.md` · `06-final-report.md`
· `evidence/*.log`. Templates are in `templates/`.
