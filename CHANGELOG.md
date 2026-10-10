# Changelog

## 0.5.1 - 2026-10-10
Windows without WSL, verified on Windows 11 (Git for Windows, `core.autocrlf=true`):
- `install.ps1` and `install.sh --copy` install and pass `doctor` (first real run of `install.ps1`).
- `evals/run-checks.sh` CRLF check fixed for Git Bash. Root cause: MSYS grep handles a CR pattern in
  text mode, so `grep -rIl $'\r'` matched either nothing or every file (CI listed every file as CRLF).
  CR is now detected with `tr -cd '\r'`. Tracked files are judged by what git stores
  (`git ls-files --eol`, `i/crlf`/`i/mixed`), untracked files and non-git copies by their bytes.
  A first diagnosis ("Windows checkouts convert to CRLF") was wrong: the checkout and the copies were
  LF all along; the helper added for it was reverted. Lite weight, escalated once to a fresh tester
  when a test asserted an unreachable case (`eol=lf` normalises CRLF on add); the rewritten case
  (`-text`) kills a mutant of the index check.
- Test suites run in `--copy` mode where symlinks are unavailable (`MODEFLAG`, `assert_installed`),
  so the whole suite runs in Git Bash.
- CI runs on `windows-latest` (Git Bash) next to Ubuntu and macOS.
- Docs: Windows setup in the README; `playbook-setup` warns that `bash` in PowerShell may be the WSL launcher.

## 0.5.0 - 2026-10-09
- **Behaviour-eval runner** `evals/run-evals.sh`: runs E1/E3/E8/E15 against a real harness (presets for
  opencode/claude/codex, or a `--cmd` adapter called as `COMMAND <workdir> <prompt-file>`) in throw-away
  fixtures, grades the mechanical part (PASS/FAIL/MANUAL) and writes a results file. Deletion-safe:
  `make-fixture.sh` refuses empty, root (`/`, `//`, `/./`), `$HOME`, the cwd and any non-fixture
  directory (marker `.git/pb-fixture`); the runner only clears `<workroot>/<E>` it owns
  (`.pb-eval-workroot`). Three review rounds (CHANGES, CHANGES, APPROVE); mutant m10, which could
  delete a real repository through a broken guard, is now killed.
- **role-gate**: test configuration counts as test (`jest/vitest/playwright/cypress` configs,
  `karma.conf.*`, `.mocharc*`, `pytest.ini`, `phpunit.xml[.dist]`, `__snapshots__/`, `*.snap`), so an
  implementer cannot weaken tests through config. New `role-gate.sh size [--base REF]` checks the Lite
  limits (default 3 production files, 100 lines; exit 1 says "escalate to Full").
- **Releases**: `tools/check-release.sh vX.Y.Z` (VERSION matches, CHANGELOG has the entry, `--notes`
  prints it); CI runs it on `v*` tags and creates the GitHub Release from the CHANGELOG (job-scoped
  `contents: write`, never overwrites).
- **run-checks**: unquoted `name`/`description` containing `: ` fails (the YAML trap that silently drops
  a skill in OpenCode); frontmatter is parsed with PyYAML when available; shellcheck also covers
  `tools/` and `evals/`.
- Full weight throughout: separate tester / implementer / reviewer sub-agents, one dispute (a test ran
  inside a repo whose config overrode the regex) resolved by a fresh tester.

## 0.4.1 - 2026-10-09
- security(feedback): `feedback.sh submit` now checks the target repo's visibility once, before any
  item is processed, and refuses (exit 5, items stay pending) when the repo is public or its
  visibility cannot be determined, also in `--dry-run`; `--allow-public` is the explicit opt-in.
  The setup default for `feedback_repo` is a private repo the user owns, never the public playbook repo.
  Full weight: tester / implementer / reviewer sub-agents; 24 new assertions seen failing first;
  review APPROVE with 5/5 mutants killed and bypass probes (case, whitespace, CRLF, config repo) refused.

## 0.4.0 - 2026-10-09
Make the discipline cheaper where mistakes are cheap:
- **Full / Lite weight by risk.** `playbook-tdd` picks a weight before Phase 1 and states the reason.
  Full keeps three separate contexts for hard-to-reverse ground, core logic, or when unsure. Lite runs
  in one context for small reversible changes (≤ 3 production files, ≤ 100 lines): the test is still
  written first and seen failing, `role-gate.sh check implementer --base RED` still proves the test
  was not bent, evidence is still fresh; no reviewer sub-agent, and the report says so. Lite
  escalates to Full on any Full criterion, size overrun, or a doubted test. Evals E15, E16.
- **One reviewer per feature, not per slice** (early review only for a hard-to-reverse slice that
  later slices build on).
- **Exemptions spelled out**: docs-only, config-only without behaviour change, throwaway spikes, each
  stated in one line; behaviour-changing config (flags, defaults, permissions, deploy settings) is
  not exempt. Eval E17.
- Spec and final-report templates record `Weight:` and its reason.
- docs: the 0.3.1 entry below was missing from the v0.3.1 tag (added afterwards; the GitHub release
  v0.3.1 carries the same notes).

## 0.3.1 - 2026-10-09
- fix(update): `install.sh update --check` compared tag *names*, so any checkout not sitting exactly
  on the newest tag was told "UPDATE AVAILABLE", even a development checkout ahead of it. It now
  compares commits and reports: up to date (same commit, also when two tags share it), ahead of
  the newest tag by N commits, behind (UPDATE AVAILABLE), or diverged (pick a release with `--to`).
  Built with the playbook's own three-role flow: 7 assertions written first by a tester sub-agent
  and seen failing, the fix by a separate implementer sub-agent, read-only review with 4/4 mutants killed.
- Known, not fixed: when two tags share HEAD's commit the message may name the older tag (the status is correct).
- docs: visual README, MIT license and credits, live CI badge; CI runs on Ubuntu (shellcheck) and macOS (bash 3.2).

## 0.3.0 - 2026-10-09
Four lessons adopted from an internal B2B delivery playbook, kept project-neutral:
- **Decide by reversibility.** The clarify rule now asks only about ambiguities that are material
  AND hard to reverse; reversible gaps get a default logged in `.agents/handoff/decisions.md`
  (template, `DECISION[Dn]` markers) and are reviewed in one batch. Eval E13.
- **Every rule carries its why.** Each always-on section has a `Why:` line; each skill states its
  `**Why:**`. Rules without a reason become candidates for removal during feedback triage.
- **AC verbatim with source anchors.** `spec.md` starts from the source and keeps each AC's
  original wording and where it came from; testers name tests by AC id and assert on literal copy.
- **UI changes need someone to look.** The reviewer opens the running app at mobile width first,
  then desktop, compares copy and flow with the source anchors, keeps a screenshot per AC, and
  never approves a UI AC it could not open. Eval E14.

## 0.2.0 - 2026-10-09
- Precedence over overlapping skills: the always-on block and `playbook-tdd` state that the
  playbook's role split, reviewer re-run and batched questions win over Superpowers
  `test-driven-development`, `subagent-driven-development` and `brainstorming`. Eval E11.
- New skill `playbook-feedback` and `scripts/feedback.sh`: capture evidenced improvement proposals
  quietly, ask at most once per interval at the end of a task, preview, then file GitHub issues
  (duplicate search, labels, redaction, offline-safe). Eval E12. `tools/setup-labels.sh`, issue template.
- `install.sh update`: fetch release tags, show the changelog, check out the newest tag (or `--to`
  for rollback) and re-install every recorded target (registry `.install-targets`, including copy-mode
  Windows homes); `--check` only reports. Install and uninstall maintain the registry.
- CI: GitHub Actions runs the full suite on Ubuntu and macOS (bash 3.2 / BSD tools).
- Setup asks for `feedback_repo` and `feedback_interval_days`.

## 0.1.0 - 2026-10-09
- Always-on block: clarify gate (verbatim user rule), proof labels, scope discipline, TDD and
  learnings pointers, first-run setup.
- Skills: playbook-setup, playbook-tdd (tester / implementer / reviewer roles), playbook-proof,
  playbook-learn.
- Scripts: conf.sh, role-gate.sh, proof-run.sh (with secret redaction), learn.sh.
- Installer for Claude Code, Codex and OpenCode: symlink or copy mode, managed blocks, backups,
  status, doctor, uninstall.
- Tests for every script and the installer; static checks; 10 behaviour scenarios with a rubric.
