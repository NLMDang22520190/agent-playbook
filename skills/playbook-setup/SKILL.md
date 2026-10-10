---
name: playbook-setup
description: Use once per machine or project to configure the agent playbook - when ~/.agents/playbook.conf is missing, when the user asks to set up or reconfigure the playbook, or when the harness, models or test commands changed. Not for ordinary coding tasks.
---

# Playbook setup

**Why:** the other skills run real commands and pick real capabilities; guessed values make
gates run the wrong thing silently.

Goal: one short round of questions that produces `~/.agents/playbook.conf` (global) and, inside a
project, `<project>/.agents/playbook.conf`. The other playbook skills read these values. Detect
what you can, propose defaults, guess nothing silently.

Scripts live at `~/.agents/playbook/scripts/` (installed by the playbook's `install.sh`).
If that directory is missing, stop and tell the user to run `install.sh install` from their
agent-playbook repo. Do not improvise an installation.

## Steps

1. **Current state.** Run `bash ~/.agents/playbook/scripts/conf.sh list`. If a config exists and
   the user did not ask to reconfigure, report it and stop.

2. **Identify the harness from your own tools.** Look at the tools you actually have; do not
   guess from the model name. Hints (tool names change between versions, so treat them as hints):

   | Harness | Typical signals | Sub-agents |
   |---|---|---|
   | Claude Code | `Skill`, `Agent` (or `Task`), `AskUserQuestion` tools; `~/.claude/` | native: the `Agent`/`Task` tool |
   | Codex CLI | shell + `apply_patch`; `~/.codex/` | only when the multi-agent feature is enabled in `~/.codex/config.toml` (check `codex --help` / Codex docs for the current flag name); otherwise manual |
   | OpenCode | `task`, `skill`, `question` tools; `~/.config/opencode/` | native: the `task` tool |
   | Other | read the harness docs | ask the user |

   State your conclusion. It is confirmed in step 4.

   On Windows, check which `bash` you get: `bash --version` must mention `msys`/`mingw` (Git Bash).
   `C:\Windows\System32\bash.exe` is the WSL launcher and would run the playbook scripts inside WSL
   against the wrong home. If so, call Git Bash by its full path (usually
   `"C:\Program Files\Git\bin\bash.exe"`) and say so in the summary.

3. **Inspect the project before asking** (skip outside a project):
   - test/lint/typecheck commands: `package.json` scripts, `Makefile`, `justfile`, `pyproject.toml`
     / `tox.ini` / `noxfile.py`, `go.mod`, `Cargo.toml`, `build.gradle*` / `pom.xml`, `composer.json`,
     `*.csproj`, CI workflow files (they show what CI really runs);
   - whether it is a git repo (role gates need git);
   - existing `AGENTS.md`, `CLAUDE.md`, `.agents/LEARNINGS.md`;
   - where the tests live (to confirm the test-path pattern; see `references/questions.md`).
   Present every detection as a proposed default, with the file it came from.

4. **Ask once, batched.** Use `references/questions.md`: at most 8 questions, each with a
   default and why it matters. Use the harness's structured question tool when it has one
   (Claude Code `AskUserQuestion`, OpenCode `question`); otherwise send one numbered message and
   accept "defaults" as an answer. Skip any question the inspection already answered beyond doubt.

   **Models per role** (question 4): list the models the harness reports (Claude Code: the model
   choices of the `Agent` tool and the ids you know; OpenCode: run `opencode models`; Codex: its
   configured models in `~/.codex/config.toml`). Rank only from what the harness reports or the
   user says; never call a model "strongest" without that basis. Print a recommendation table:
   reviewer = strongest available or another vendor, implementer = mid-tier, tester = mid- or
   low-tier, each with a reason and its relative cost. Label any sample table "example". The user
   accepts it or picks others. Store each pick with
   `conf.sh set model_<role>_<harness> <model> --global` (roles: tester, implementer, reviewer).
   Never write generic `model_<role>` keys: they apply to every harness on this machine. Also
   never write keys that are not documented in step 6 (no harness-specific extras).

5. **Non-interactive run** (CI, `claude -p`, `codex exec`, `opencode run`, or no reply possible):
   do not block. Write the defaults, add `setup=defaults-noninteractive`, and list every
   assumption in your final message.

6. **Write the values.**
   ```bash
   C=~/.agents/playbook/scripts/conf.sh
   bash $C set harness claude --global            # per-machine values: --global
   bash $C set test_cmd "pnpm test" --project     # per-project values: --project
   bash $C set setup done --global
   ```
   Global keys: `language`, `harness`, `subagents`, per-harness `model_<role>_<harness>`
   (the generic `model_tester`, `model_implementer`, `model_reviewer` are legacy: read as a fallback, not written), `autonomy`, `feedback_repo`, `feedback_interval_days`, `setup`. Project keys: `test_cmd`, `lint_cmd`,
   `typecheck_cmd`, `test_path_regex` (only if the default is wrong), `learnings_path`.

7. **Verify and report.**
   - `bash $C list` and paste the output.
   - `bash ~/.agents/playbook/scripts/role-model.sh check`: it must say "no generic model keys";
     otherwise tell the user which generic keys exist and offer to move them to per-harness keys.
   - Check that the always-on block is loaded: look for the `<!-- BEGIN agent-playbook` line in the
     global file of this harness (`~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` or
     `~/.config/opencode/AGENTS.md`, which falls back to `~/.claude/CLAUDE.md`). If it is missing,
     recommend `install.sh doctor`. Do not edit global files yourself without consent.
   - For Codex: if `~/.codex/AGENTS.override.md` is non-empty, warn that it shadows `AGENTS.md`.

8. **Project bootstrap (ask first).** Offer:
   `bash ~/.agents/playbook/scripts/learn.sh init --link-agents` (creates `.agents/LEARNINGS.md`,
   ignores `.agents/handoff/`, and adds a pointer to `AGENTS.md`). If the project has no
   `CLAUDE.md` and the user uses Claude Code, add `--link-claude` (creates `CLAUDE.md` containing `@AGENTS.md`).

9. **Summary** in at most 10 lines: what was written where, the assumptions, and how to change
   them later (`conf.sh set ...` or "reconfigure the playbook").

## Do not
- install packages, change harness settings or edit global instruction files without consent;
- run long test suites during setup (checking that the command exists is enough);
- ask more than the necessary questions, or ask what the repo already answers.
