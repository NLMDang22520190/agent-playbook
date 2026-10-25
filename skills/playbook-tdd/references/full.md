# Full workflow

**Why:** an agent that writes both code and tests writes tests that agree with its own mistakes,
and a test nobody saw fail proves nothing. Separate contexts plus a git gate make "the tests were
changed to pass" impossible to miss.

New to TDD? Read `references/tdd-guide.md` first. Test quality and the mutation spot-check are in
`references/test-quality.md`.

If a generic TDD or sub-agent skill applies (for example Superpowers `test-driven-development`
or `subagent-driven-development`), borrow its techniques but keep these roles, gates and the
reviewer's re-run, not their "implementer writes and runs its own tests" model.

## Test infrastructure role

Test infrastructure (test runners, shared test helpers) is a fourth, opt-in role: set the project key
`test_infra_regex` and matching paths classify as `infra`, which neither the tester nor the
implementer may change. Order: the tester first writes tests that exercise the infra change and sees
them fail (`check tester --base <sha before the role>`, commit RED); then a different context makes the change and passes
`role-gate.sh check infra --base $RED`. Without the key, infra files count as tests.

## Workflow

### Phase 1: Spec (orchestrator)
Commands known: `conf.sh get test_cmd` (also `lint_cmd`, `typecheck_cmd`). Unknown: detect,
then confirm with the user (or run `playbook-setup`).

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

Oracle rule: when the request hinges on an ambiguous direction, unit, sign or convention, the spec needs a worked example with a concrete expected result, confirmed by the user or a source document and recorded as an AC that the tests use verbatim; without one, ask (headless: log it in decisions.md as open and label every claim that depends on it [UNVERIFIED] (a test on it: [UNVERIFIED] or Dn)); details: `references/tdd-guide.md#oracle`.

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

Parallel slices: `references/parallel.md`.

### Phase 3: Review (reviewer, read-only)
**One reviewer per feature, not per slice:** after the last slice, start one fresh reviewer with
`roles/reviewer.md` for the whole diff. Review a single slice early only when that slice alone is
hard to reverse (a migration, a public API change) and later slices build on it.
Prefer a different model (resolve it with `role-model.sh reviewer --harness <h>`). Give it the spec, the base sha from before
slice 1, all slice reports, and the evidence logs. Then run `role-gate.sh check reviewer --base <sha before the role>` (nothing in the repo changed).
Save its report to `.agents/handoff/05-review.md`. Verdict `CHANGES` sends the listed findings
back through a new RED (tester) or GREEN (implementer) round; findings without evidence are dropped.
If the user wants a review, run Phase 3 on the result.

Phase 3 code-review rounds are capped at 2 per lane or slice. From round 3 on, fix only a MAJOR introduced by this change, and give it one more round. Every other finding goes to the queue, written under "Found, not fixed" in the final report. Spec-review and dispute limits are unchanged.

**Why:** a third round mostly finds smaller things, and each round costs a full review. The queue keeps them without holding the release.

### Phase 4: Close-out (orchestrator)
- Fresh full run of test, lint and typecheck through `proof-run.sh`, after the last change. Sub-agents
  ran focused tests only; this orchestrator run is the full suite. If it fails, the work goes back
  into a new RED/GREEN round (tester or implementer, as the failure requires); do not report done.
- Cost logging: `references/cost.md`.
- `git diff --stat <base>..HEAD`, which must match the spec scope.
- For a user-visible change the gates include one real observation of the behaviour in this session
  (screenshot or browser read, curl, the CLI command), as `playbook-proof` describes; unit tests alone are not enough. If it cannot be run, it goes under "Not checked".
- Fill `templates/final-report.md`: the request coverage (each sentence of the raw request, verbatim: done where, read as, or not done), AC to tests to evidence with a confidence for each AC, review verdict, assumptions, the
  logged defaults from `decisions.md` (for one batched review), found-not-fixed, and the
  [UNVERIFIED] list. Also fill `## Not checked` (what was not exercised) and `## Pre-mortem` (three ways
  the result could still be wrong, each with the command run to check it and its outcome).
- The report ENDS with exactly the line `**Playbook feedback:** <captured fb- ids or none>`, copied verbatim from `templates/final-report.md`, never paraphrased, with nothing after it.
- When sub-agents ran, the report has the line `**Models used:** tester=<m> (<effort>), implementer=..., reviewer=... (Lite: session, one context)`, copied verbatim from `templates/final-report.md` with the models filled in, placed before `## Learnings proposed`; naming the models only in prose is not enough.
- Propose learnings (skill `playbook-learn`) when something non-obvious went wrong.
- If a playbook rule, gate or script misfired during the task (a false positive, a wrong verdict, a check that let something through), capture it with skill `playbook-feedback` before the final report, with no need to ask (capture is local): one line per misfire, with its evidence.
- Do not push or open a PR unless `autonomy=full` or the user asked; the PR description is the `pr-body.sh` output.

## Resuming
The orchestrator updates `.agents/handoff/state.md` (from `templates/state.md`)
after each phase (spec, each RED, each GREEN, review, close-out) with the phase, the slice, the last sha per role,
the next step and the open questions. When a session resumes or a context was lost, read `state.md` first, then
the other hand-off files.
