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

Give each concurrent task its own worktree (`git worktree add`) and never share one work tree between tasks: the gate judges every change in the tree, so another task's edits or a moved HEAD would land in your gate. Within one task, changes that already existed before the first role are recorded with a snapshot and passed to every gate.

```bash
git worktree add ../myrepo-task-a -b task-a
bash ~/.agents/playbook/scripts/role-gate.sh snapshot --out baseline.txt
bash ~/.agents/playbook/scripts/role-gate.sh check <role> --base <sha> --baseline baseline.txt
```

The gate has no option to ignore changes outside a role's scope, on purpose: a role could edit outside its scope unseen. A separate worktree gives the same isolation without that blind spot.

## Honest limit

The same model in fresh contexts still shares blind spots. A different reviewer model, the mutation spot-check, and the user's own review of the AC table reduce this but do not remove it.
