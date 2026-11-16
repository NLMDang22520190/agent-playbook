# Full weight reference

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
A merge conflict makes those slices serial. Slices sharing one worktree gate each role with `--commits A..B`. Slices that
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

## Starting roles per harness (`conf.sh get subagents`)
Resolve each role's model first: `bash ~/.agents/playbook/scripts/role-model.sh <role> --harness <h>`
(`claude`, `codex` or `opencode`: the harness you run in)
and pass it when starting the role. `session` means do not override the session model.
A configured model is binding: the agent never upgrades or downgrades it on its own judgement (a hard task or Full weight is not a reason). Before starting roles, print `role-model.sh plan --harness <h>`.
Ask the user once, with the reason and the cost difference, only when you want a different model, when a role resolves to session on a Full task, or when confirm_models=always.
confirm_models=on-change is the default (an unknown value counts as on-change); never ask when confirm_models=never. Headless: use the conf, never upgrade, never block.
Two more roles route by task type. Mechanical work (release prep, counts, weights, formatting) uses the `mechanical` model (`role-model.sh mechanical`; which steps to hand it: `references/harnesses.md`), which never falls back to another role's model. Use `reviewer_light` for a review of a diff that only touches tests, docs or skill text; code changes keep the `reviewer` model (`reviewer_light` falls back to it when unset). Build every
sub-agent prompt from `templates/role-prompt.md`. For the mechanical RED or GREEN step
(gate, then the test command as evidence, optional checkpoint commit) use
`bash ~/.agents/playbook/scripts/tdd-step.sh red|green` (`--base` red, `--baseline` both).
How to start roles in each harness (native, manual, none), pass the model and effort, and cache the prompt prefix: `references/harnesses.md`.
Native roles get the full role file plus the allowed input paths, never your conversation or opinions; the context pack holds paths, excerpts and commands, not conclusions. In `none` mode play the roles one after another: commit between roles, re-read only the hand-off files, still run the gates, and report "degraded mode: roles shared one context".

**Why:** a different, stronger reviewer model catches what the author's model misses, and a role that
never saw your reasoning cannot inherit its mistakes.

## Resuming
The orchestrator updates `.agents/handoff/state.md` (from `templates/state.md`)
after each phase (spec, each RED, each GREEN, review, close-out) with the phase, the slice, the last sha per role,
the next step and the open questions. When a session resumes or a context was lost, read `state.md` first, then
the other hand-off files.

## Hand-off files (`.agents/handoff/`, git-ignored)
`state.md` · `01-spec.md` · `01b-spec-review.md` · `decisions.md` · `02-tests-<slice>.md` · `03-impl-<slice>.md` · `05-review.md` · `06-final-report.md`
· `evidence/*.log`. Templates are in `templates/`.
