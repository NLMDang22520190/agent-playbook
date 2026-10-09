# Harness notes (where each tool looks, with sources)

Checked 2026-10-09. Tools change: re-check when a harness updates, and run `install.sh doctor`.

## Verified from official docs
| Fact | Source |
|---|---|
| Codex scans user skills in `$HOME/.agents/skills`, repo skills in `.agents/skills` from the cwd up to the repo root; it follows symlinks; same-name skills are not merged | https://learn.chatgpt.com/docs/build-skills (redirected from developers.openai.com/codex/skills) |
| Codex may shorten skill descriptions: the initial skill list is capped at 2% of the context window (8,000 chars when unknown). So descriptions here are kept short and front-loaded | same page |
| Codex global instructions: `~/.codex/AGENTS.override.md` if non-empty, otherwise `~/.codex/AGENTS.md`; project files walk from the root down to the cwd; 32 KiB combined default cap (`project_doc_max_bytes`) | https://learn.chatgpt.com/docs/agent-configuration/agents-md |
| OpenCode skills: project `.opencode/skills`, `.claude/skills`, `.agents/skills`; global `~/.config/opencode/skills`, `~/.claude/skills`, `~/.agents/skills`; `name` must match the directory and `^[a-z0-9]+(-[a-z0-9]+)*$`; description 1 to 1024 chars | https://opencode.ai/docs/skills/ |
| OpenCode rules: project `AGENTS.md` (fallback `CLAUDE.md`); global `~/.config/opencode/AGENTS.md` (fallback `~/.claude/CLAUDE.md`); the first match wins in each category | https://opencode.ai/docs/rules/ |

## From secondary sources (verify before relying on them)
- Claude Code reads `AGENTS.md` as a fallback when a folder has no `CLAUDE.md` (news coverage, 2026).
  The playbook does not rely on it: use `CLAUDE.md` containing `@AGENTS.md` (`learn.sh init --link-claude`).
- The Codex multi-agent feature flag name has changed between versions (`multi_agent` vs `collab`
  in different mirrors of third-party docs). Check `codex --help` or the official docs.
- Agent Skills (`SKILL.md` with `name` and `description`) is described as an open standard
  (agentskills.io), adopted by 30+ tools. The counts come from blogs.

## Design consequences
- Skills: Claude gets `~/.claude/skills`; Codex gets `~/.agents/skills`; OpenCode reads either, so
  no third copy is made (avoids duplicate skills in OpenCode's list).
- Always-on rules must be in the global instruction file, not in a skill: skills load only when
  their description matches the task.
- A non-empty `~/.codex/AGENTS.override.md` silently disables the block: `install` warns and
  `doctor` fails on it.
