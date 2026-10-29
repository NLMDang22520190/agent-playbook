<div align="center">

# agent-playbook

A software development process for AI coding agents, in one global skill pack for Claude Code, Codex and OpenCode.

![version](https://img.shields.io/badge/version-0.30.0-4F5BD5) ![harness](https://img.shields.io/badge/harness-Claude_Code:_evaluated_·_Codex:_partly_evaluated_·_OpenCode:_installable,_not_evaluated-1F9D63) ![os](https://img.shields.io/badge/os-Linux_·_macOS_·_Windows-5B6478) [![CI](https://github.com/NLMDang22520190/agent-playbook/actions/workflows/test.yml/badge.svg)](https://github.com/NLMDang22520190/agent-playbook/actions/workflows/test.yml) ![tests](https://img.shields.io/badge/tests-21436-1F9D63) ![always-on](https://img.shields.io/badge/always--on_block-39%2F60_lines-C98A00) ![status](https://img.shields.io/badge/status-alpha-orange) ![license](https://img.shields.io/badge/license-MIT-5B6478)

</div>

AI agents write code fast, and they also call work done without running it, see tests pass on the wrong screen, and write tests that agree with their own bugs. agent-playbook makes them check their work. It has three parts: a short rule block that every agent reads, five skills that load when they apply, and scripts that check the work through git.

## Quick start

```bash
git clone https://github.com/NLMDang22520190/agent-playbook.git ~/agent-playbook
cd ~/agent-playbook && bash tests/run-all.sh                 # must be green
./install.sh install --harness all --dry-run                 # preview
./install.sh install --harness all --yes && ./install.sh doctor
```

Then open a new agent session and say *"set up the playbook"*. Setup asks at most 8 questions, each with a default.

<p align="center">
  <img src="docs/flow.svg" alt="One change end to end: 1 Clarify by reversibility, 2 Spec with verbatim AC and source anchors, 3 RED by the tester, 4 GREEN by the implementer, 5 REVIEW read-only with UI check, 6 PROOF with fresh evidence, 7 LEARN and feedback. Git role gates between RED, GREEN and REVIEW." width="100%">
</p>

## The rules and why they exist

| Rule | Why |
|---|---|
| Read the repo first. Ask only when a choice is material and hard to reverse; otherwise pick a default, log it in `decisions.md` and review the defaults together at the end. | Waiting on choices that can be undone is slow. Guessing the ones that cannot causes rework or damage. |
| Claims that matter carry `[VERIFIED]`, `[INFERRED]` or `[UNVERIFIED]`, and "passes" needs output from a run in this session. | Tests have passed on the wrong screen, and a confident wrong explanation costs the next person a day. |
| The tester, implementer and reviewer run in three fresh contexts, and `role-gate.sh` enforces the split through git. | An agent that writes both the code and its tests writes tests that agree with its mistakes. |
| Acceptance criteria quote the request word for word, with a source anchor. | Paraphrasing a request is the fastest way to build what nobody asked for. |
| A UI change needs one real look at the running screen in this session: a screenshot or browser read, which the agent can take. | Passing tests cannot tell you the screen is right. |
| Stay in scope, and never loosen a test or a gate. | Unrequested changes hide in diffs nobody reviews, and a loosened gate protects no one. |
| When skills give opposite orders, the playbook wins. | Two skills with opposite orders make behaviour random. |

Project lessons go to `.agents/LEARNINGS.md`. Gaps in the playbook itself become issues once you approve them, then a fix, a release and `update` on every machine.

## What's inside

| Component | Loads when | Does |
|---|---|---|
| `AGENTS.global.md` | every session (the installer puts it in the global instruction file) | the rules above: clarify, proof, scope, precedence |
| [`playbook-setup`](skills/playbook-setup/SKILL.md) | first run, or "set up the playbook" | detects the harness, reads the project, asks at most 8 questions with defaults |
| [`playbook-tdd`](skills/playbook-tdd/SKILL.md) | adding or changing behaviour, fixing a bug | spec, failing tests first, code, review, final report |
| [`playbook-proof`](skills/playbook-proof/SKILL.md) | reporting results or "done" | confidence labels, evidence for each kind of claim, Definition of Done |
| [`playbook-learn`](skills/playbook-learn/SKILL.md) | you correct the agent, or a gate fails for a known reason | project lessons in `.agents/LEARNINGS.md`, after you approve them |
| [`playbook-feedback`](skills/playbook-feedback/SKILL.md) | a playbook rule misfires or is missing | notes it quietly, asks at most once at the end of a task, files an issue in your private feedback repo |

Scripts (bash 3.2+, no dependencies), all in `scripts/`:

- `role-gate.sh` and `tdd-step.sh` check each role's changes and record RED and GREEN evidence.
- `proof-run.sh` runs a command and prints an evidence block.
- `mutate.sh` flips operators on changed lines and lists the mutants your tests missed.
- `cost.sh` logs and sums the cost of role runs; `role-model.sh` picks the model for each role.
- `pr-body.sh` writes a PR description from the hand-off files.
- `leak-check.sh` refuses secrets and private strings in added lines.
- `conf.sh`, `learn.sh` and `feedback.sh` handle settings, project lessons and playbook feedback.

## When you do not need it

Not every change goes through three agents. The playbook picks a weight for each task and states it in the report:

- Docs, config that does not change behaviour, and throwaway spikes are Exempt: no new tests, and the agent says so in one line.
- A small, reversible fix (about 3 files and 100 changed lines at most) runs at Lite: one context, test first and seen failing, no reviewer. Say "quick" to ask for Lite.
- Config that changes behaviour, such as feature flags, defaults, permissions or deploy settings, is not Exempt.

## Three roles, one slice

<p align="center">
  <img src="docs/roles.svg" alt="Three roles, one slice: the orchestrator writes 01-spec.md with verbatim AC and source anchors, plus decisions.md, and sends the slice and spec without implementation hints to the tester, who returns failing tests and RED evidence; after the tester gate it commits test(red). The implementer gets the slice and the RED sha and returns code and GREEN evidence, or a dispute; after the implementer gate against RED it commits feat(green). The reviewer gets the spec, diff and evidence logs and returns a verdict, its own re-run, mutants and UI screenshots; after the reviewer gate the final report is written." width="100%">
</p>

The orchestrator runs a gate after each hand-off:

- `role-gate check tester --base <sha>`, then it commits `test(red)`
- `role-gate check implementer --base RED`, then it commits `feat(green)`
- `role-gate check reviewer --base <sha>`, then it writes the final report

| Role | May change | The gate fails when |
|---|---|---|
| Tester | test files only | production code is touched |
| Implementer | production code only | any test file is edited, deleted or added since the RED commit (test configuration counts as test) |
| Reviewer | nothing (report only) | anything in the repo changed |

### Weight by risk

| Weight | When | What runs |
|---|---|---|
| Full | public API, data shape, migrations, security, money, core logic; or when unsure | three roles in three contexts, a gate after every hand-off, one review per feature |
| Lite | small and reversible, ≤ 3 files and ≤ 100 lines (`role-gate.sh size` checks it) | one context: test written first and seen failing, `role-gate --base RED`, evidence; no reviewer |
| Exempt | docs, config that does not change behaviour, throwaway spikes | no new tests, stated in the report |

Lite moves up to Full when it touches hard-to-reverse ground, outgrows the size limit, or a test looks wrong. For scale: v0.6.0 was built at Full in 11 sub-agent runs and 891k tokens (see its CHANGELOG entry).

If the harness has sub-agents, each role is a sub-agent. If not, each role runs as a separate headless session. With a single context the playbook still runs, and the report says it ran in that weaker mode.

### What a final report looks like

An example, shortened from [`templates/final-report.md`](skills/playbook-tdd/templates/final-report.md):

```markdown
**Result:** add() now rejects NaN.
**Weight:** Lite (no independent review) · reason: one module, 2 files, 14 lines
| Request sentence (verbatim) | Status |
|---|---|
| "add() should reject NaN" | done: src/calc.js:12, AC1 |
Not checked: callers outside src/ were not run.
**Playbook feedback:** none
```

### Spending tokens where they buy safety

- Each role gets its own model, per harness. Setup lists the models your harness offers and suggests a strong model (or another vendor) for the reviewer, a mid-tier one for the implementer and a mid- or low-tier one for the tester. A configured model is binding: the agent does not swap it on its own. `confirm_models=always|on-change|never` (default `on-change`) sets when it asks you before using a different one.
- Sub-agents run focused tests, and the orchestrator does one fresh full run (test, lint, typecheck) at the end.
- The tester's prompt includes the reviewer's checklist, so fewer review rounds come back.
- Slices hold 1 to 5 tests, and every sub-agent prompt starts with the same fixed text so prompt caching can reuse it.
- The spec starts with `## Understanding` and `## Impact`, and the final report ends with a table that covers each sentence of the request.
- A leak guard, `scripts/leak-check.sh`, refuses tokens, keys and your own private strings (`leak_literals`) in added lines. `leak-check.sh install-hooks` adds pre-commit and pre-push hooks; re-run it after upgrading the playbook to get the per-remote pre-push scan. Pattern tips and the push scan are in [docs/development.md](docs/development.md#leak-guard).

## Ask or decide?

<p align="center">
  <img src="docs/ask-or-decide.svg" alt="Ask or decide: when an ambiguity is found and the repo can answer it, read it and proceed; if it is not material, proceed; if it is material and hard to reverse (API, data, migration, security, money, anything sent outside), ask once, batched, each question with a default; if it is material but reversible, choose a default, log it in decisions.md, mark it DECISION[Dn] and list it in the final summary for one batched review." width="100%">
</p>

## Install in every harness

<p align="center">
  <img src="docs/architecture.svg" alt="One source, every harness, every project: the agent-playbook repo is installed into Claude Code, Codex and OpenCode; each project keeps playbook.conf, LEARNINGS.md and hand-off files; feedback becomes GitHub issues and tagged releases are installed with install.sh update." width="100%">
</p>

The Quick start commands install into every harness found:

| Harness | Skills | Always-on rules |
|---|---|---|
| Claude Code | `~/.claude/skills/playbook-*` | managed block in `~/.claude/CLAUDE.md` |
| Codex CLI | `~/.agents/skills/playbook-*` | managed block in `~/.codex/AGENTS.md` |
| OpenCode | reads both folders above | `~/.config/opencode/AGENTS.md`, or falls back to the Claude file |

The installer is safe to re-run. It backs files up before changing them, never overwrites anything it does not own, and records every target so `update` refreshes them all.

Windows has two setups, both tested on Windows 11:

- Without WSL (needs [Git for Windows](https://git-scm.com/download/win)), clone anywhere and run `.\install.ps1 install -Harness claude,codex,opencode -Yes` from PowerShell. It finds Git Bash and installs copies, because Windows does not grant symlink rights by default. Re-run it after each `git pull`, or use `update` from Git Bash.
- With the repo inside WSL and the harness on Windows, run `./install.sh install --home /mnt/c/Users/<name> --harness all --copy --yes`.

In PowerShell, `bash` usually starts `C:\Windows\System32\bash.exe`, the WSL launcher, not Git Bash. Agents on Windows should run the playbook scripts with Git Bash (`"C:\Program Files\Git\bin\bash.exe" ~/.agents/playbook/scripts/...`); Claude Code's own shell tool already is Git Bash. WSL stops idle distros, which can kill long agent runs; the settings that prevent it are in [docs/harness-notes.md](docs/harness-notes.md#wsl).

```bash
./install.sh uninstall --harness all --yes   # removes only what the installer created; keeps config and backups
```

## Hooks (Claude Code, opt-in)

The rules ask the agent to stop before irreversible actions. In Claude Code, hooks can enforce part of that. They stay off until you say yes: say "set up the playbook" and answer yes to the hooks line (playbook-setup asks once, default no), or run

```bash
bash ~/.agents/playbook/scripts/claude-hooks.sh install     # merge into ~/.claude/settings.json (backup first)
bash ~/.agents/playbook/scripts/claude-hooks.sh status      # one line per handler
bash ~/.agents/playbook/scripts/claude-hooks.sh uninstall   # remove only the agent-playbook handlers
```

The merge needs node. Without it the script changes nothing and prints the JSON to add by hand. Your other settings and hooks stay as they are, `install.sh uninstall` removes ours too, and `install.sh doctor` says whether they are installed, partly installed or turned off by `disableAllHooks`.

| Event | Handler | What it does |
|---|---|---|
| PreToolUse (`Bash`, `PowerShell`, `Write`, `Edit`) | `guard-irreversible.sh` | Destructive SQL through a database client, force pushes, git commands that throw away uncommitted work, `rm -r` outside the project, and migration runs with a pending contract step: blocked in headless runs, a warning in interactive ones. Writing a migration file is allowed and marked pending. In the `PowerShell` tool (its own handler, `guard-ps`) it checks `git`, destructive SQL through `sqlcmd`, `sqlite3`, `psql` and the like, and `Remove-Item -Recurse` (aliases `rm`, `ri`, `del`, `rmdir`, `rd`) outside the project; see Limits. Tool names and input: [code.claude.com/docs/en/hooks](https://code.claude.com/docs/en/hooks) (section PowerShell). |
| SessionStart | `guard-irreversible.sh --session-start` | Records the commit the session started from. |
| SessionStart | `learnings-hook.sh` | Adds the active entries of `.agents/LEARNINGS.md` to the context, labelled as data, not instructions, only for trusted projects: those you list with `learn.sh trust` (`untrust` and `trusted` manage the list in `~/.agents/trusted-projects`) or all of them with `learnings_hook_trust=all` in the global conf (a project conf cannot set it). For any other project it prints one line saying the file was not injected. |
| Stop | `guard-irreversible.sh --stop` | Headless only. While the tree holds a dropped table or column, or a migration with a contract step, the agent may not finish: it must revert the change and report it as a pending proposal in its final reply. After three refusals the guard gives up and tells you what is left. |

Headless means `PB_HEADLESS=1`. When `PB_HEADLESS` is unset, `CI=true` counts as headless (GitHub Actions sets it). Claude Code tells a hook nothing about `claude -p`, so before a local `claude -p` run, `export PB_HEADLESS=1`, or the guard only warns. `PB_HEADLESS=0` forces warn-only, in CI too.

Codex has hooks as well ([learn.chatgpt.com/docs/hooks](https://learn.chatgpt.com/docs/hooks): PreToolUse, SessionStart, Stop), but the playbook does not install them yet, so Codex gets the text rule only. OpenCode plugins can refuse a tool call from `tool.execute.before` ([opencode.ai/docs/plugins](https://opencode.ai/docs/plugins/)), but no plugin ships yet: text rule only. On both, `learn.sh init --link-agents` adds a pointer to `.agents/LEARNINGS.md` in the project's `AGENTS.md`; that pointer is how their agents learn about the file.

### Limits

The guard reads the command text of one tool call. It does not see through:

- another shell or evaluator: `bash -c`, `sh -c`, `eval`, `$(...)` and backticks, subshells and brace groups, here-docs fed to a shell;
- interpreter one-liners (`node -e`, `python -c`, `perl -e`), or a script written to a file and then run;
- git aliases, `find -delete`, `xargs rm`, and keywords written with `\u` escapes or built by concatenation;
- SQL that reaches a database client through a file in a form it does not follow: a non-`.sql` file read from disk (`cp notes.txt f.sql`, `cat notes.txt > f.sql`), a file written by an earlier tool call, `&>` redirects, file names with spaces, client options glued to the file name (`psql --file=f.txt`, `psql -ff.txt`), and long prefix options with a separate value (`sudo --user x cp ...`);
- tools it is not attached to: NotebookEdit and MCP tools (a database MCP server, for example);
- in the PowerShell tool, the same kind of gaps, and these forms in particular: `Invoke-Expression` and `iex`, `powershell -Command`, `pwsh -c` and `-EncodedCommand`, `cmd /c` and `Start-Process` (the inner command is not read); scriptblocks that run later (`& { }`, `Invoke-Command`); the `--%` stop-parsing token; .NET calls such as `[IO.Directory]::Delete(...)`; variables other than `$HOME`, `$PWD`, `$env:USERPROFILE`, `$env:HOME`, `$env:TEMP`, `$env:TMP`, `$env:TMPDIR` and `$env:CLAUDE_PROJECT_DIR` in a delete target, which count as outside the project (they warn or block); an assignment in the same command to one of the listed variables (`$env:TEMP = ...`, a list assignment such as `$a, $env:TEMP = ...`, a compound one such as `+=`, `Set-Item env:TEMP ...`, `Set-Variable`, `Rename-Item` or `New-Item` naming it, `[Environment]::SetEnvironmentVariable('TEMP', ...)`) makes it unresolved from then on, so a delete through it warns or blocks (fail closed), and a value copied from one variable into another is not followed; splatting (`Remove-Item @p`) with no visible `-Recurse`; `Remove-Item` without `-Recurse`; registry and other provider paths, except that a target with `::` (such as `FileSystem::C:\x`) or a drive-relative one (`C:x`, `C:..\x`) warns or blocks; a SQL file written with `Set-Content` or `Out-File` and run later. The Unicode dashes U+2013 to U+2015 at the start of a word are read as `-`, curly quotes as quote characters, and these as word separators: the Unicode characters U+0085 (NEL), U+00A0, U+1680, U+2000 to U+200A, U+2028, U+2029, U+202F, U+205F and U+3000, and the raw form feed and vertical tab bytes (a JSON `\u000b` or `\u000c` escape is not decoded, so it does not separate words: a Limit); `$(...)` inside an expandable here-string runs like in a double-quoted string. The command on the right of an assignment (`$r = Remove-Item -Recurse ...`) is checked like any other, whatever the assignment target: a variable with a scope prefix (`$script:r = ...`), a property (`$x.a = ...`), an index (`$x[0] = ...`, `$h['k'] = ...`), a typed one (`[string] $r = ...`) or a comma list of these, with `=`, `+=`, `-=`, `*=`, `/=`, `%=` or `??=`; not seen through: an index or quoted member name with a space in it (`$h[$i + 1] = ...`, `$x.'a b' = ...`) and a glued dot call after the `=` (`$r = .$c ...`). `cd..` is followed as a move to the parent directory; `cd\` and a drive switch such as `D:` make later relative paths unresolved (fail closed). A call operator whose command is a group, a variable or a quoted name with an expansion (`& (Get-Command x) ...`, `& $cmd ...`, `& "Remove-$x" ...`, also with `.`, and `.$c`) is an unknown command: with a recursive switch in its arguments (also `-Rec:$true`), or `push` with a force form, it warns or blocks (fail closed). A pipeline-fed `Remove-Item -Recurse` has no target word, so it warns or blocks even inside the project (fail closed), for example `Get-ChildItem .\build | Remove-Item -Recurse`. The hook commands are `bash` commands: without Git Bash installed they cannot run, and the PowerShell tool is then unguarded;
- edits that switch it off: `disableAllHooks` or hook changes in `~/.claude/settings*.json` or `.claude/settings.local.json`, or edits to the guard itself;
- projects that are not a git repository, where the Stop check has no diff to compare;
- a session with no baseline file (its SessionStart hook did not run, or the file was removed outside the guard) on a branch with no upstream: the Stop check then compares with HEAD, so a drop committed earlier in that session is not seen.

The `learnings-hook.sh` trust gate covers only the automatic injection. The `AGENTS.global.md` text rule still tells agents to read `.agents/LEARNINGS.md`, so the file of an untrusted project can still be read as a text rule, and an agent could run `learn.sh trust` itself: only you should run it (the hook line and the `playbook-learn` skill say so).

For the file-based bypasses the Stop diff is the backstop: it judges the end state of the tree, whatever tool made the change.
SQL that a database client has already run through one of these bypasses has no backstop.

## Updates and feedback

<p align="center">
  <img src="docs/feedback-loop.svg" alt="Improves itself from real use: in a work session on any harness and machine, a playbook rule that misfires is captured quietly as pending feedback; at the end of a task, at most once every 7 days, you preview and approve it and it becomes an issue in your private feedback repo; the fix is a PR with an eval scenario that goes through tests and review, is merged and tagged vX.Y.Z, CI creates the release, and install.sh update refreshes every recorded install on WSL, Windows and other machines." width="100%">
</p>

```bash
./install.sh update --check             # is there a newer release?
./install.sh update --yes               # show the CHANGELOG, check out the tag, re-install everywhere, doctor
./install.sh update --to v0.2.0 --yes   # roll back
```

`update` checks the release tag with `git verify-tag` before it changes anything. An SSH signature that does not verify against a configured `gpg.ssh.allowedSignersFile` stops the update, even with `--allow-unsigned`. An unsigned tag, an SSH signature while no allowed signers file is set, or a PGP/x509 signature that does not verify (no key, no gpg, or a bad signature) prints a `WARN:` line and the update continues. `scripts/conf.sh set require_signed_tags yes` (global conf) makes those fatal; `--allow-unsigned` lets one through.

`feedback.sh submit` refuses to post to a public repository (or one whose visibility it cannot read) unless you pass `--allow-public`. Details: [`docs/update-lifecycle.md`](docs/update-lifecycle.md).

## Behaviour evals

Script tests show that the tools work. Only behaviour evals show whether an agent follows the rules. [`evals/scenarios.md`](evals/scenarios.md) has 43 scenarios, E1 to E43. `evals/run-evals.sh` runs the 39 that have automatic checks against a real harness in throwaway fixtures, grades each check PASS, FAIL or MANUAL, and writes a results file:

```bash
evals/run-evals.sh --harness claude --scenarios E1,E15 --workroot "$HOME/pb-evals-$(date +%s)" --max-cost 5
```

The presets do not sandbox the agent, and the opencode preset approves its own actions, so run them only in a throwaway workroot or a VM, never inside a real repo. Score the MANUAL items with [`evals/RUBRIC.md`](evals/RUBRIC.md).

`--variant DIR` (in `run-evals.sh` and `run-outcome.sh`) measures another tree of the playbook: the with arm otherwise loads the installed playbook, so the runner installs DIR into the harness home for the run and puts the snapshot of the previous install back afterwards. Other sessions on that home see the variant meanwhile; the headers of both scripts have the details.

## Quality, measured

| Metric | Value | Source |
|---|---|---|
| Script, installer and tool tests | **21436 passing** (see `bash tests/run-all.sh`) | `bash tests/run-all.sh`, WSL Ubuntu 24.04 |
| Static checks | frontmatter (incl. YAML parse), length budgets, a why for every rule, CRLF, syntax, shellcheck, evals | `evals/run-checks.sh` |
| Always-on block | 39 / 60 lines · 4,584 / 5,000 bytes | `wc -l -c AGENTS.global.md` |
| Skill descriptions | 1,372 / 2,000 characters (Codex truncates long skill lists) | `run-checks.sh` |
| CI | Ubuntu (bash 5, shellcheck), macOS (bash 3.2, BSD tools) and Windows (Git Bash, copy mode) on every push and PR | `.github/workflows/test.yml` |
| Behaviour evals | Claude Code 2.1.296 is the only harness evaluated in full; Codex is partly evaluated (Run C1: k=3, through a `--cmd` adapter kept outside the repo); OpenCode is installable but not evaluated. Runs 25-44 (2026-10-26 and 27, with vs without the playbook, k=2 to 10, Run 38 on claude-opus-5-5) are summarised per rule in [`docs/delta-audit.md`](docs/delta-audit.md): at k=10 (Run 44) E2, E3, E4, E6 and E29 show Δ > 0 with 95% intervals that exclude 0, E14 and E21 are inconclusive; with the opt-in hooks Δ > 0 for E13 and E34. Of the 33 outcome tasks, pattern-26, pattern-15 and pattern-24 separate the arms with intervals that exclude 0 (runs pooled across commits); pattern-19, 23 and 25 lean the same way but are inconclusive; pattern-12 did not replicate in Run 44; Δ = 0 on 20 tasks in two or more runs and on 6 in one run. Cost: about 2-2.5x per run with the playbook (Run 25: 2.5x, Run 26: 2.1x, Run 29: 2.1x). Earlier runs, with the failures and grader fixes they found: [2026-10-10](evals/results/2026-10-10-claude-code-2.1.296.md), [2026-10-12 to 26](evals/results/2026-10-12-claude-code-2.1.296.md) | [`evals/scenarios.md`](evals/scenarios.md) · [`RUBRIC.md`](evals/RUBRIC.md) |

## Alongside Superpowers or other skill packs

When the playbook conflicts with `test-driven-development`, `subagent-driven-development` or `brainstorming`, the playbook wins: separate tester, implementer and reviewer, the reviewer re-runs the tests, and questions go in one message with defaults. Scenario E11 checks this.

## Text other people read

Reports, PR descriptions, release notes and docs follow a short writing guide, [`references/writing.md`](skills/playbook-proof/references/writing.md) in `playbook-proof`. It leads with the answer and cuts chatbot openers and closers, inflated words, decorative headings, emojis and em dashes. It never changes the lines and labels the playbook requires (`**Weight:**`, `[VERIFIED]`, Not checked and the rest), and editing never adds a fact.

The guide condenses [humanizer](https://github.com/blader/humanizer). For a fuller pass, install that skill. Setup offers it (default no) and records `humanizer=ask|always|never`. With `ask`, the agent asks once whether to run it, only when the task produces text other people will read, and never in a headless run. Scenario E30 checks a headless PR description for chatbot wrappers and dashes.

## Limitations

- Fresh contexts on the same model still share blind spots. Use a different model for the reviewer if you can.
- `role-gate.sh` tells tests from code by path (a configurable regex). It cannot catch an implementer that special-cases test inputs in production code; the reviewer and the mutation check look for that.
- Rules written in prose (ask, attach evidence) depend on the model following them. The gates enforce only the mechanical part.
- Codex has sub-agents only with its multi-agent feature on; otherwise the playbook runs in `manual` mode.

## Repository layout

```
agent-playbook/
├── AGENTS.global.md        always-on rules (the installer puts them in each harness's global file)
├── skills/                 setup · tdd (roles/, templates/, references/) · proof · learn · feedback
├── scripts/                role-gate · tdd-step · proof-run · mutate · cost · role-model · pr-body · leak-check · conf · learn · feedback · lib
├── templates/LEARNINGS.md
├── install.sh / install.ps1
├── tests/                  21436 tests, run in sandboxes, never touch the real HOME
├── evals/                  run-evals.sh (headless evals) · run-checks.sh · scenarios.md (E1–E43) · RUBRIC.md · make-fixture.sh
├── tools/                  maintainer scripts: release, CI, README count, hooks (see docs/development.md)
└── docs/                   diagrams · tdd-for-beginners.md · harness-notes.md · update-lifecycle.md · development.md
```

## Contributing

A PR that adds tests updates the README count with `tools/readme-count.sh LOG`. CI details, the docs-only path, the opt-in pre-commit hook, BSD and shellcheck checks are in [docs/development.md](docs/development.md).

## Credits

The content is written for this repo. Ideas came from:

- [obra/superpowers](https://github.com/obra/superpowers): TDD discipline and "evidence before claims".
- [Agent Skills](https://agentskills.io) and [AGENTS.md](https://agents.md): the open formats that let one skill pack run across harnesses.
- [forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills): surgical changes, stated assumptions.
- [mattpocock/skills](https://github.com/mattpocock/skills): concise skill writing.
- [blader/humanizer](https://github.com/blader/humanizer) (MIT): the writing guide condenses its patterns.
- An internal B2B delivery playbook: decide by reversibility, a why for every rule, verbatim AC with anchors, and looking at the UI.

## License

[MIT](LICENSE)

---

<div align="center">
<sub>agent-playbook · alpha · TDD guide for beginners: <a href="docs/tdd-for-beginners.md">docs/tdd-for-beginners.md</a> · Harness notes with sources: <a href="docs/harness-notes.md">docs/harness-notes.md</a></sub>
</div>
