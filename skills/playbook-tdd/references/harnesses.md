# Starting roles in each harness

The binding rules are in the `SKILL.md` section "Starting roles per harness": resolve each role's model with `role-model.sh <role> --harness <h>`, never upgrade or downgrade a configured model on your own judgement, print `role-model.sh plan`, and ask once as `confirm_models` says. This file holds the plumbing: how to start a role in each harness, how to pass its model and effort, and how to keep the prompt prefix cacheable.

## Spawn mode (`conf.sh get subagents`)

- **native**: spawn a sub-agent per role, each with a fresh context. Pass the full text of the role file plus paths of the allowed inputs, not your conversation or opinions about the solution.
  - Claude Code: the `Agent`/`Task` tool; pass the resolved model in its `model` parameter (general-purpose for tester and implementer). For the reviewer a read-only agent type is fine: it returns the report text and you save it.
  - OpenCode: the `task` tool (a general sub-agent; an explore/read-only one for the reviewer). A model per role needs a per-role agent in `opencode.json`, each with its own `model`.
  - Codex: native only with the multi-agent feature enabled. Otherwise use manual mode (`codex exec -m <model>` per role).
- **manual**: run each role as a separate headless process or a new session, with the prompt built from the role file and the handoff paths. For example `claude -p "<prompt>"`, `codex exec "<prompt>"`, `opencode run "<prompt>"`. Flags differ by version: check `--help`. You run the gates between processes.
- **none** (degraded): you play the roles one after another. Between roles, commit, then re-read only the handoff files, never your earlier reasoning. Gates still run. Say "degraded mode: roles shared one context" in the final report, because the independence guarantee is weaker.

## Effort

Pass the effort (`role-model.sh <role> --harness <h> --effort`) where the harness supports it: Agent `effort` parameter, `codex exec -c model_reasoning_effort=<e>`, OpenCode per-agent config; otherwise print it only.

## Prompt prefix

Build every sub-agent prompt from `templates/role-prompt.md` (fixed part first, then spec, then the slice), so the fixed prefix can be cached.

## Several tasks, one repository

Separate worktrees stay the first choice for concurrent tasks (`git worktree add`): the gate judges every change in the tree, so another task's edits or a moved HEAD would land in your gate. Within one task, changes that already existed before the first role are recorded with a snapshot and passed to every gate.

```bash
git worktree add ../myrepo-task-a -b task-a
bash ~/.agents/playbook/scripts/role-gate.sh snapshot --out "$(git rev-parse --git-path pb-gate-baseline-a)"
bash ~/.agents/playbook/scripts/role-gate.sh check <role> --base <sha> --baseline "$(git rev-parse --git-path pb-gate-baseline-a)"
```

When you must use one checkout, share it only with a scope file per task, plus a baseline per task when foreign work exists or may start. The scope file lists `own` paths (judged as always) and `other` paths (another task's, not judged). The gate accepts `--scope` without `--baseline`, then only `other` entries exempt foreign work; a baseline also exempts the paths recorded in it.

- The scope file format: the first line is `# role-gate scope v1`, then one entry per line, `own<TAB>path` or `other<TAB>path` (a TAB between the kind and the path). A path is an exact path or a `dir/` prefix (it ends in a slash), relative to the top of the work tree, with no globs. Write the file with LF line ends and no BOM; the gate refuses anything else (exit 3).
- `--base` is the sha printed by `git rev-parse HEAD` before the role, never the word `HEAD`: a base that moves with HEAD hides the role's own commits.
- Per-task files in the git dir: `$(git rev-parse --git-path pb-scope-<task>)` for the scope file and `snapshot --out "$(git rev-parse --git-path pb-gate-baseline-<task>)"` for the baseline (the default `pb-gate-baseline` is one per checkout, so two tasks would overwrite it). Record `git hash-object` of the scope file when you write it and compare it with the digest in the gate's scope note after each gate; `tdd-step.sh` refuses when the scope file or the manifest changes between its two gate runs.
- The no-checkpoint-commit workflow: before each role record `git rev-parse HEAD` and take a snapshot instead of committing between roles, then pass `--base <that sha> --baseline <that file> --scope <task file>` to the role's gate (and to `tdd-step.sh`, which then commits or prints only the changed `own` paths).
- Keep `other` entries as narrow as possible: exact paths over prefixes, never a path the task's own tests or code read.
- The gate does not judge the notes `another task's path` and `changed since the baseline`, so attribute every such note of a test kind to the other task for an implementer, and every such note for a reviewer, before you accept the verdict.
- A path the gate names as outside the task scope and not in the baseline, and that passed, is probably the task's own work: add it to `own` or commit it before the next snapshot, or the next snapshot records it and exempts every later edit to it (r5).
- A path you cannot attribute is a stop, never a reason to reset, stash or revert concurrent work.
- Two scope errors stop `role-gate.sh` and `tdd-step.sh` with no verdict:
  - `error: cannot classify the changed paths` exits 3: the path classifier failed; run the command again.
  - `error: the scope file changed while it was read: FILE` exits 3: the scope file was edited while the command ran; stop the writer, then run the command again.
  - Exit 3 is an environment error, never a pass.
- The mode check exempts nothing with `--scope`: another task's exec-bit drop fails the gate; attribute it, then run the gate again with that path in `PB_ALLOW_MODE_CHANGE`.

The blind spot: a role could still write outside its scope unseen. The scope closes it only for unknown paths (rule 4, judged as without a scope and named in a note); declared and recorded paths stay a residual risk, which you check by attribution:

- r1: an `other` directory prefix exempts every path under it, also a new file a role writes there.
- r2: a recorded path is exempt for every further edit, also an edit by the role.
- r3: a role that commits over `other` or recorded paths passes, because those commits are exempt too.
- r4: an edit to a declared or recorded path that the task's own tests read can change the RED or GREEN signal.
- r5: laundering through the next snapshot (see above).

A separate worktree gives the same isolation without that blind spot.

## Honest limit

The same model in fresh contexts still shares blind spots. A different reviewer model, the mutation spot-check, and the user's own review of the AC table reduce this but do not remove it.
