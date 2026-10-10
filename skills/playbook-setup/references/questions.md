# Setup questions

Ask only what inspection could not settle. Every question has a default; "defaults" accepts all.

| # | Key (scope) | Question | Default | Why it matters |
|---|---|---|---|---|
| 1 | `language` (global) | Which language should I answer in? | the language of the user's message | Skill files stay in English for model stability; answers follow this. |
| 2 | `harness` (global) | I detected `<harness>`. Correct? | the detection | Picks the sub-agent mechanism and the global instruction file. |
| 3 | `subagents` (global) | Can I start isolated sub-agents here? `native` / `manual` (separate sessions or headless CLI runs) / `none` | `native` for Claude Code and OpenCode; for Codex `native` only when the multi-agent feature is on, else `manual` | Role separation (tester / implementer / reviewer) depends on it. `none` = degraded mode, reported as such. |
| 4 | `model_<role>_<harness>` (global; also the older `model_<role>`) | Which model for each role (tester, implementer, reviewer) on this harness? List what the harness reports (Claude Code: the Agent tool's model choices; OpenCode: `opencode models`; Codex: its configured models), print a recommendation table with a reason and relative cost per role, and let the user accept or pick others. | `session` (no override) for all if the harness reports nothing; otherwise the recommendation: reviewer = strongest available or another vendor, implementer = mid-tier, tester = mid- or low-tier (rank only from what the harness or user says) | A different, stronger reviewer reduces shared blind spots; cheaper models for the tester and implementer cut cost. Stored with `conf.sh set model_<role>_<harness> <m> --global`. |
| 5 | `test_cmd`, `lint_cmd`, `typecheck_cmd` (project) | I found `<commands>` in `<file>`. Use them? | the detection | The gates and the evidence run these exact commands. |
| 6 | `autonomy` (global) | What may I do without asking? `ask-before-commit` / `commit-locally` / `full` (push, PR) | `ask-before-commit` | The TDD flow commits RED/GREEN checkpoints. With `ask-before-commit` it asks once per task. |
| 7 | `test_path_regex` (project) | Tests live in `<dirs>`. Does the default pattern recognise them? | the built-in default (only ask if detection shows a mismatch) | The role gate uses it to tell tests from production code. |

| 8 | `feedback_repo` (global), `feedback_interval_days` (global) | Where should playbook improvement proposals go, and how often may I ask? | a **private** repo the user owns (OWNER/REPO; suggest creating one, e.g. `gh repo create OWNER/playbook-feedback --private`), never the public playbook repo; `7` days | `playbook-feedback` sends approved proposals there as issues. `submit` refuses (exit 5) a public repo or one whose visibility it cannot read, unless `--allow-public` is passed. |

Optional, only when relevant:
- `learnings_path` (project): default `.agents/LEARNINGS.md`.
- `learn_max_entries` (project): default `40`.

## Example (single numbered message for harnesses without a question tool)

> Setup for the agent playbook (reply "defaults" to accept all):
> 1. Language for answers: **Vietnamese** (from your message)?
> 2. Harness: **Codex CLI** (I see `apply_patch` and `~/.codex`)?
> 3. Sub-agents: multi-agent is not enabled in `~/.codex/config.toml`, so **manual** (each role in a separate `codex exec` run)?
> 4. Models: **same as session** for all roles? (A recommendation table follows from `codex` configured models; a different model for the reviewer is recommended.)
> 5. Commands from `package.json`: test `pnpm test`, lint `pnpm lint`, typecheck `pnpm tsc --noEmit`?
> 6. Autonomy: **ask before commit**?

## Checking the test-path pattern

```bash
G=~/.agents/playbook/scripts/role-gate.sh
git ls-files | head -200 | while read -r f; do printf '%s %s\n' "$(bash $G classify "$f")" "$f"; done | sort | uniq -c | sort -rn | head
```
If real test files show as `code`, or production files show as `test`, propose a project
`test_path_regex` (an ERE matched against repo-relative paths) and show it working on 3 samples.
The default treats every `*.snap` and `__snapshots__/` file as a test (snapshots are test
expectations, so an implementer must not rewrite them); if the project has `.snap` files that are
not tests (for example Ubuntu snap packages), propose a regex without the bare `\.snap$`.
