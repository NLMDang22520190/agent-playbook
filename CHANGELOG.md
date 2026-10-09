# Changelog

## Unreleased
- docs: the 0.3.1 entry below was missing from the v0.3.1 tag (added afterwards; the GitHub release v0.3.1 carries the same notes).

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
