# Mechanics of the TDD workflow

The binding rules stay in `SKILL.md`; this file holds the mechanics its sections point to (moved in v0.35.0, text unchanged).

## Test infrastructure role

Test infrastructure (test runners, shared test helpers) is a fourth, opt-in role: set the project key
`test_infra_regex` and matching paths classify as `infra`, which neither the tester nor the
implementer may change. Order: the tester first writes tests that exercise the infra change and sees
them fail (`check tester --base <sha before the role>`, commit RED); then a different context makes the change and passes
`role-gate.sh check infra --base $RED`. Without the key, infra files count as tests.

## Preconditions: dirty tree and concurrent tasks

- With a dirty tree, run `role-gate.sh snapshot` before the first role, pass `--baseline <file>` to every gate and to
  `tdd-step.sh` (check the digest matches), or commit only the role's paths by hand.
- Concurrent tasks: `--scope`, see `references/harnesses.md`.

## Phase 2: context pack, first-slice checkpoint, parallel slices

**Context pack.** The orchestrator builds a context pack once per slice from the spec's Impact section and scan log, and puts it into section 2b of the role prompt (`templates/role-prompt.md`): the files to read with line ranges (path:line-line), the functions or sections involved, short excerpts and the commands to run. The role reads the pack first and opens other files only when it is not enough.

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

## Phase 4: cost logging

- Log each role run: `bash ~/.agents/playbook/scripts/cost.sh add --role <role> --tokens <N>
  --seconds <S> --model <M> --weight <Full|Lite> --phase <spec|red|green|review|fix|release> --rework <N>
  --majors <N> --task <id>`, with tokens as the harness reports them (`0` if unknown, never a guess);
  `--rework` counts the rework round (`0` on the first pass) and `--majors` the review majors found. Then put `cost.sh summary` into the
  final report's Cost section.
- Optional: with runs logged by `--task <id>`, `cost.sh calibrate` shows per weight the review majors
  and rework rounds per task; advice only.

## When the user says it is wrong

Steps 3 and 4 in full (steps 1 and 2 are in `SKILL.md`):

3. Fix it test-first: a failing test or eval for the miss, seen failing, then the fix. For a docs-only
   (Exempt) misread, fix it and re-check the result against the request; no test is needed.
4. If the cause is a playbook gap, capture it with `playbook-feedback` (kind `gap`, source `user`) and
   propose a regression eval scenario in the item. If the cause is specific to this project, propose a
   lesson with `playbook-learn` instead.

## Resuming

The orchestrator updates `.agents/handoff/state.md` (from `templates/state.md`)
after each phase (spec, each RED, each GREEN, review, close-out) with the phase, the slice, the last sha per role,
the next step and the open questions. When a session resumes or a context was lost, read `state.md` first, then
the other hand-off files.
