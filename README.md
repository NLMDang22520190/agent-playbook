<div align="center">

# agent-playbook

A software development process for AI coding agents, in one global skill pack for Claude Code, Codex and OpenCode.

![version](https://img.shields.io/badge/version-0.24.31-4F5BD5) ![harness](https://img.shields.io/badge/harness-Claude_Code_·_Codex_·_OpenCode-1F9D63) ![os](https://img.shields.io/badge/os-Linux_·_macOS_·_Windows-5B6478) [![CI](https://github.com/NLMDang22520190/agent-playbook/actions/workflows/test.yml/badge.svg)](https://github.com/NLMDang22520190/agent-playbook/actions/workflows/test.yml) ![tests](https://img.shields.io/badge/tests-14380-1F9D63) ![always-on](https://img.shields.io/badge/always--on_block-39%2F60_lines-C98A00) ![status](https://img.shields.io/badge/status-alpha-orange) ![license](https://img.shields.io/badge/license-MIT-5B6478)

</div>

Agents write code fast, and without verification that speed turns into slop: tests go green on the wrong screen, work is called done without a fresh run, and one agent writes both the code and its tests, so the tests agree with its mistakes. agent-playbook has three parts. An always-on rule block goes into each harness's global instruction file, where every agent reads it. Five skills load when they apply. Mechanical gates check the work.

<p align="center">
  <img src="docs/flow.svg" alt="One change end to end: 1 Clarify by reversibility, 2 Spec with verbatim AC and source anchors, 3 RED by the tester, 4 GREEN by the implementer, 5 REVIEW read-only with UI check, 6 PROOF with fresh evidence, 7 LEARN and feedback. Git role gates between RED, GREEN and REVIEW." width="100%">
</p>

## Philosophy

1. Clarify by reversibility. Read the repo first, and ask only when an ambiguity is both material and hard to reverse. Otherwise pick a default, log it in `decisions.md`, keep going, and review the defaults in one batch at the end.
2. Proof for every claim. Claims carry `[VERIFIED]`, `[INFERRED]` or `[UNVERIFIED]`, and "passes" needs the output of a run from this session.
3. Test author ≠ implementer ≠ reviewer. The three roles run in three fresh contexts, and `role-gate.sh` enforces the split through git as well as through instructions.
4. Learn in the project, improve at the source. Project lessons go to `LEARNINGS.md`. Gaps in the playbook itself become issues once you approve them, then a PR and a release, and every machine runs `update`.

### Why each rule exists

| Rule | Why it exists |
|---|---|
| Ask when hard to reverse, otherwise log a default | Waiting on choices that can be undone kills speed; guessing the ones that cannot causes rework or damage. |
| Evidence from a fresh run | Tests have gone green on the wrong screen; a confident wrong explanation costs the next person a day. |
| Separate tester / implementer / reviewer | An agent that writes both the code and its tests writes tests that agree with its own mistakes. |
| Verbatim AC with source anchors | Paraphrasing a request is the fastest way to build what nobody asked for. |
| UI changes need someone to look | Green tests cannot tell you the screen is right. |
| Stay in scope, never loosen a gate | Unrequested changes hide in diffs nobody reviews. A loosened gate protects no one. |
| The playbook wins when skills overlap | Two skills giving opposite orders make behaviour random. |

## What's inside

| Component | Triggers | Does |
|---|---|---|
| `AGENTS.global.md` | every session (the installer puts it in the global instruction file) | clarify by reversibility · proof · scope · precedence |
| [`playbook-setup`](skills/playbook-setup/SKILL.md) | first run, or "set up the playbook" | detects the harness, reads the project, asks at most 8 questions with defaults |
| [`playbook-tdd`](skills/playbook-tdd/SKILL.md) | adding or changing behaviour, fixing a bug | anchored spec, RED then GREEN per slice, review, final report |
| [`playbook-proof`](skills/playbook-proof/SKILL.md) | reporting results or "done" | confidence labels, evidence by claim type, Definition of Done |
| [`playbook-learn`](skills/playbook-learn/SKILL.md) | when you correct the agent, or a gate fails with a known cause | project lessons in `.agents/LEARNINGS.md` (you approve) |
| [`playbook-feedback`](skills/playbook-feedback/SKILL.md) | when a playbook rule misfires or is missing | captures quietly, asks at most once at the end of a task, files an issue in your private feedback repo |

Scripts (bash 3.2+, no dependencies): `role-gate.sh` · `proof-run.sh` · `conf.sh` · `learn.sh` · `feedback.sh`.

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

Not every change needs three sub-agents.

| Weight | When | What runs | Measured cost* |
|---|---|---|---|
| Full | public API, data shape, migrations, security, money, core logic; or when unsure | three roles, three contexts, a gate after every hand-off, one review per feature | ~5 min and ~225k tokens for the three roles (the v0.3.1 fix) |
| Lite | small and reversible, ≤ 3 files and ≤ 100 lines (`role-gate.sh size` checks it) | one context: test written first and seen failing, `role-gate --base RED`, evidence; no reviewer | test-first plus the gate |
| Exempt | docs, config that does not change behaviour, throwaway spikes | no new tests, but say so explicitly | negligible |

Lite escalates to Full when it touches hard-to-reverse ground, outgrows the size limit, or a test looks wrong. Configuration that changes behaviour (feature flags, defaults, permissions, deploy settings) is not exempt.
<sub>* Measured on the v0.3.1 fix, see the CHANGELOG. Not a benchmark.</sub>

### Spending tokens where they buy safety

- Each role gets its own model, per harness. Setup lists the models your harness offers and recommends a strong model (or another vendor) for the reviewer, mid-tier for the implementer, and mid- or low-tier for the tester; you accept or pick. `scripts/role-model.sh <role> --harness <h>` resolves it (`model_<role>_<harness>` → `model_<role>` → `session`), and `role-model.sh plan` prints the line the agent shows before it starts roles. A configured model is binding: the agent does not upgrade or downgrade it on its own. `confirm_models=always|on-change|never` (default `on-change`) sets when it asks you: on-change asks once, and only when it wants a different model or a role resolves to session on a Full task. Reasoning effort per role: `model_<role>_reasoning_effort[_<harness>]`.
- Sub-agents run focused tests, and the orchestrator does one fresh full run (test, lint, typecheck) at close-out.
- The reviewer's checklist is in the tester's prompt ("make every check able to fail"), so fewer review rounds come back.
- Slices are cohesive, 1–5 tests each, and every sub-agent prompt is built from `templates/role-prompt.md` (fixed text first) so prompt caching can reuse it.
- Mechanical steps are scripts: `scripts/tdd-step.sh red|green` (gate + evidence + optional commit), and `tools/release.sh` for maintainers.
- A leak guard, `scripts/leak-check.sh`, refuses tokens, keys and your own private strings (`leak_literals`) in added lines. A `leak_patterns` entry for a key prefix should start with a token-start boundary, for example `(^|[^A-Za-z0-9_-])sk-[A-Za-z0-9_-]{12,}`, so words like `task-...` do not match. `install-hooks` adds pre-commit and pre-push hooks. After upgrading the playbook, re-run `leak-check.sh install-hooks` to get the per-remote pre-push scan. A push to a URL no configured remote owns scans every commit; `PB_LEAK_SCAN_BASE=<full 40-hex commit id>` limits that scan to that id..pushed commit (an invalid id, an empty range or a non-ancestor exits 3).
- The whole request is found before any code. The spec starts with `## Understanding` and `## Impact`, a spec reviewer checks it against the raw request (Full), and the final report ends with a request coverage table.
- An optional pre-commit hook (opt-in) catches a lost executable bit, which agents often drop when they edit a script with an edit tool. `tools/install-hooks.sh` installs `tools/pre-commit` into this repo's hooks dir (`--force` replaces a different hook, `--uninstall` removes only the one it installed). The hook refuses a commit that would store a script as git mode 100644 and names each path with the fix (`git update-index --chmod=+x PATH`). It runs `evals/run-checks.sh --only modes`, so it follows the same rule as the CI check. The leak guard takes priority: if `.git/hooks/pre-commit` is the leak-check hook (`scripts/leak-check.sh install-hooks`), `tools/install-hooks.sh` refuses to replace or remove it, even with `--force` (exit 1). Only one pre-commit hook fits there, so run the check by hand with `bash evals/run-checks.sh --only modes`. Installed in the other order, `leak-check.sh install-hooks` leaves our hook alone and exits 1. Nothing installs it automatically.
- Quality checks run by script. `scripts/mutate.sh --base REF --test CMD` flips operators on the changed lines in a throwaway worktree and lists the mutants your tests missed. `tools/eval-guard.sh --base REF` names the behaviour evals that a skill-wording change should re-run, with a capped command; it never runs them, and `tools/ship.sh` prints it before the tag. `cost.sh calibrate` shows per weight, from tasks logged with `--task`, whether Full reviews found anything (advice only). Disjoint slices may run in parallel in separate worktrees, and `learn.sh add --role` and `learn.sh checklist ROLE` turn project learnings into per-role checklists.
- Cost is measured: `scripts/cost.sh add` per role run, and `cost.sh summary` in the final report (per role and per phase, with rework rounds and review majors; `--phase`, `--rework`, `--majors`). `scripts/pr-body.sh` builds the PR description from the spec, the final report and the review verdict. Models can be routed by task type: `spec_reviewer` for the Full-weight spec reviewer sub-agent (falls back to the reviewer's model), `reviewer_light` for diffs of tests, docs or skill text, and `mechanical` for release prep and counts. `evals/run-evals.sh --max-cost USD` stops running scenarios once the known costs reach USD. v0.6.0 itself took 11 sub-agent runs and 891k tokens (tester and implementer on Sonnet, reviewer on Opus).

If the harness has sub-agents, each role is a sub-agent. If not, each role runs as a separate headless session. With only a single context the playbook still runs, but the report says so, because that is the weaker mode.

## Ask or decide?

<p align="center">
  <img src="docs/ask-or-decide.svg" alt="Ask or decide: when an ambiguity is found and the repo can answer it, read it and proceed; if it is not material, proceed; if it is material and hard to reverse (API, data, migration, security, money, anything sent outside), ask once, batched, each question with a default; if it is material but reversible, choose a default, log it in decisions.md, mark it DECISION[Dn] and list it in the final summary for one batched review." width="100%">
</p>

## Install once, run in every harness

<p align="center">
  <img src="docs/architecture.svg" alt="One source, every harness, every project: the agent-playbook repo is installed into Claude Code, Codex and OpenCode; each project keeps playbook.conf, LEARNINGS.md and hand-off files; feedback becomes GitHub issues and tagged releases are installed with install.sh update." width="100%">
</p>

| Harness | Skills | Always-on rules |
|---|---|---|
| Claude Code | `~/.claude/skills/playbook-*` | managed block in `~/.claude/CLAUDE.md` |
| Codex CLI | `~/.agents/skills/playbook-*` | managed block in `~/.codex/AGENTS.md` |
| OpenCode | reads both folders above | `~/.config/opencode/AGENTS.md`, or falls back to the Claude file |

```bash
git clone https://github.com/NLMDang22520190/agent-playbook.git ~/agent-playbook
cd ~/agent-playbook && bash tests/run-all.sh                 # must be green
./install.sh install --harness all --dry-run                 # preview
./install.sh install --harness all --yes && ./install.sh doctor
```

Windows has two supported setups, both verified on Windows 11:
- Without WSL (needs [Git for Windows](https://git-scm.com/download/win)), clone anywhere and run `.\install.ps1 install -Harness claude,codex,opencode -Yes` from PowerShell. It finds Git Bash itself and installs in copy mode, because Windows does not grant symlink rights by default. Re-run it after each `git pull`, or use `update` from Git Bash.
- With the repo inside WSL and the harness on Windows, run `./install.sh install --home /mnt/c/Users/<name> --harness all --copy --yes`.

In PowerShell, `bash` usually resolves to `C:\Windows\System32\bash.exe`, which is the WSL launcher, not Git Bash. Agents on Windows should run the playbook scripts with Git Bash (`"C:\Program Files\Git\bin\bash.exe" ~/.agents/playbook/scripts/...`); Claude Code's own shell tool already is Git Bash.

WSL stops idle distros, which matters for long agent runs. The settings below come from Microsoft's [`.wslconfig` / `wsl.conf` reference](https://learn.microsoft.com/en-us/windows/wsl/wsl-config):
- A distro stops about 15 seconds after its last process exits: `instanceIdleTimeout` (key under `[general]` in `.wslconfig`, default 15000 ms, `-1` disables it). That kills background work such as dev servers or test runs started from a closed terminal.
- The WSL 2 VM itself stops after `vmIdleTimeout` (key under `[wsl2]`, default 60000 ms; Windows 11 only, per the footnote on the same Microsoft page).
- For a long session, keep a process alive (for example `wsl -e sleep infinity` in a spare terminal), or set `instanceIdleTimeout=-1` and run `wsl --shutdown`.
- `autoMemoryReclaim` is a key under `[experimental]`, not under `[wsl2]`.
- On one machine we observed `/tmp` inside WSL being wiped on each restart. That is an observation from one machine, not WSL documentation, so keep evidence and drafts under your home directory.

The installer is safe to re-run. It backs files up before changing them, never overwrites anything it does not own, and records every target so `update` refreshes them all. After installing, open a new session and say *"set up the playbook"*.

## Improves itself from real use

<p align="center">
  <img src="docs/feedback-loop.svg" alt="Improves itself from real use: in a work session on any harness and machine, a playbook rule that misfires is captured quietly as pending feedback; at the end of a task, at most once every 7 days, you preview and approve it and it becomes an issue in your private feedback repo; the fix is a PR with an eval scenario that goes through tests and review, is merged and tagged vX.Y.Z, CI creates the release, and install.sh update refreshes every recorded install on WSL, Windows and other machines." width="100%">
</p>

```bash
./install.sh update --check             # is there a newer release?
./install.sh update --yes               # show the CHANGELOG, check out the tag, re-install everywhere, doctor
./install.sh update --to v0.2.0 --yes   # roll back
```

`feedback.sh submit` refuses to post to a public repository (or one whose visibility it cannot read) unless you pass `--allow-public`. Details: [`docs/update-lifecycle.md`](docs/update-lifecycle.md).

## Behaviour evals

Script tests show that the tools work. Whether an agent follows the rules shows only in behaviour evals.
`evals/run-evals.sh` runs scenarios E1, E3, E8 and E15 against a real harness in throw-away fixtures, grades the mechanical part (PASS / FAIL / MANUAL per check) and writes a results file:

```bash
evals/run-evals.sh --harness opencode --scenarios E1,E15,E8 --workroot /tmp/pb-evals-$(date +%s)
evals/run-evals.sh --cmd "bash my-adapter.sh" ...   # adapter is called as: COMMAND <workdir> <prompt-file>
```

The presets do not sandbox the agent, and the opencode preset auto-approves its actions, so run them only in a throw-away workroot or a VM, never inside a real repo. Score the MANUAL items with [`evals/RUBRIC.md`](evals/RUBRIC.md).

## Quality, measured

| Metric | Value | Source |
|---|---|---|
| Script, installer and tool tests | **14380 passing** (see `bash tests/run-all.sh`) | `bash tests/run-all.sh`, WSL Ubuntu 24.04 |
| Static checks | frontmatter (incl. YAML parse), length budgets, a why for every rule, CRLF, syntax, shellcheck, evals | `evals/run-checks.sh` |
| Always-on block | 39 / 60 lines · 4,731 / 5,000 bytes | `wc -l -c AGENTS.global.md` |
| Skill descriptions | 1,372 / 2,000 characters (Codex truncates long skill lists) | `run-checks.sh` |
| CI | Ubuntu (bash 5, shellcheck) + macOS (bash 3.2, BSD tools) + Windows (Git Bash, copy mode) on every push and PR; release job on `v*` tags | `.github/workflows/test.yml` |
| Behaviour scenarios E1–E20 | Claude Code 2.1.296, three rounds with v0.13.0 wording: E3 3/3 and E8 3/3 auto checks every round (E8 names the injected instruction), E1 4/4 when graded; playbook-tdd loaded in every E1 ([results](evals/results/2026-10-10-claude-code-2.1.296.md)). Other scenarios and harnesses not run yet | [`evals/scenarios.md`](evals/scenarios.md) · [`RUBRIC.md`](evals/RUBRIC.md) |

## Alongside Superpowers or other skill packs

The always-on block has a *When other skills overlap* section. When it conflicts with `test-driven-development`, `subagent-driven-development` or `brainstorming`, these rules win: separate tester / implementer / reviewer, the reviewer re-runs the tests, and questions are batched in one message with defaults. Scenario E11 checks this.

## Text other people read

Reports, PR descriptions, release notes and docs follow a short writing guide, [`references/writing.md`](skills/playbook-proof/references/writing.md) in `playbook-proof`. It leads with the answer, cuts chatbot openers and closers, inflated words, decorative bold and em dashes, and never touches the lines and labels the playbook requires (`**Weight:**`, `[VERIFIED]`, Not checked and the rest). Editing may cut or reorder; it never adds a fact.

The rules are condensed from [humanizer](https://github.com/blader/humanizer). For a fuller pass, install that skill. Setup offers it (default no) and records `humanizer=ask|always|never`. With `ask`, the agent asks once whether to run humanizer in full, only when the task produces text other people will read and never in a headless run. Scenario E30 checks a headless PR description for chatbot wrappers and dashes.

## Limitations

- Fresh contexts on the same model still share blind spots. Prefer a different model for the reviewer.
- `role-gate.sh` tells tests from code by path (configurable regex). It cannot catch an implementer special-casing test inputs in production code; the reviewer and the mutation spot-check do that.
- Rules written in prose (ask, attach evidence) depend on the model following them. The gates only enforce the mechanical part.
- Codex only has sub-agents with its multi-agent feature enabled; otherwise the playbook runs in `manual` mode.

## Repository layout

```
agent-playbook/
├── AGENTS.global.md        always-on rules (the installer puts them in each harness's global file)
├── skills/                 setup · tdd (roles/, templates/, references/) · proof · learn · feedback
├── scripts/                role-gate · proof-run · conf · learn · feedback · leak-check · lib
├── templates/LEARNINGS.md
├── install.sh / install.ps1
├── tests/                  14380 tests, run in sandboxes, never touch the real HOME
├── evals/                  run-evals.sh (headless evals) · run-checks.sh · scenarios.md (E1–E30) · RUBRIC.md · make-fixture.sh
├── tools/                  setup-labels.sh (feedback issue labels) · check-release.sh (VERSION + CHANGELOG per tag) · release-pr-check.sh (check-release on a PR that changes VERSION) · readme-count.sh (README test count) · pre-commit + install-hooks.sh (opt-in exec-bit hook)
└── docs/                   flow.svg · architecture.svg · roles.svg · ask-or-decide.svg · feedback-loop.svg · tdd-for-beginners.md · harness-notes.md · update-lifecycle.md
```

```bash
./install.sh uninstall --harness all --yes   # removes only what the installer created; keeps config and backups
```

## Development

CI cancels superseded runs of the same PR (concurrency, never on main or tags) and every job has a timeout.

A main push reuses a green same-repo PR run of the identical tree (a merge commit or a squash of an up-to-date PR) and skips its own suites; `tools/ci-tree-tested.sh` finds that run through `gh api` only. A rebase merge reuses a PR run only when its single resulting commit has the PR head tree and its parent is P, the base the PR head was last updated on. A rebase of several commits, and any merge of a PR that is not up to date, run the tests.

A PR that adds tests updates the README count with `tools/readme-count.sh LOG` (LOG is a `tests/run-all.sh` output). The Ubuntu job runs `tools/readme-count.sh --check` on full runs, so a stale count fails the PR. A PR that changes only `README.md` and `CHANGELOG.md` (test counts unchanged, found by `tools/docs-only.sh`) runs a reduced set of checks in the test jobs: the suites that read those two files, `tests/test-content.sh` and `evals/run-checks.sh`. A main push never takes the reduced path, and `tools/ci-tree-tested.sh` reuses a PR run only when the full `Tests and static checks` step succeeded in all five suite jobs.

`tools/bsd-check.sh [SUITE...]` runs the suites (default: all) with one-true-awk (`original-awk` or `nawk`) first on PATH, which is the awk macOS ships (`sudo apt install original-awk` on Ubuntu or WSL).

For the static checks, `run-checks.sh` runs shellcheck when it is installed (`sudo apt install shellcheck` on Ubuntu or WSL,
`brew install shellcheck` on macOS) and skips it otherwise. It also refuses GNU-only options that macOS lacks (grep with the PCRE flag, readlink canonicalise, date with a string, stat with a format flag, find with a print format, xargs with no-run-if-empty, sed extended).

## Credits

The content is written for this repo. Ideas were learned from:
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
