# Playbook update lifecycle

```
Work session (Claude / Codex / OpenCode, any machine)
  └─ skill playbook-feedback: record evidenced proposals (passively, without interrupting the work)
       └─ end of task, at most once per feedback_interval_days: preview → you approve → feedback.sh submit
            └─ issue on the playbook repo (duplicate check, labels harness/kind/source)
You triage (monthly)
  └─ an agent drafts a PR: the skill change + its eval scenario
       └─ CI (Ubuntu + macOS) runs tests/run-all.sh → you review → merge
            └─ bump VERSION, update CHANGELOG, tag vX.Y.Z, push the tag
Each machine
  └─ install.sh update --check  (cron / Task Scheduler / by hand)
       └─ install.sh update --yes → check out the tag → re-install every target recorded in .install-targets → doctor
            (roll back: install.sh update --to vX.Y.Z --yes)
Quarterly: re-check docs/harness-notes.md against the official docs, run E1–E12 in full on each harness
```

## Principles
- **Update from evidence, not on a schedule.** The schedule is only for reviews.
- **One behaviour change = one eval scenario** (new or updated). No eval, no merge.
- **Budgets:** `run-checks.sh` blocks descriptions that are too long, a SKILL.md over 300 lines, and an always-on block
  over 60 lines. Adding a rule means considering removing one.
- **Never edit an installed skill directly:** it is overwritten on update and never reaches other machines.
- **The development machine** (where you edit the repo) uses `git pull` + `install.sh install`. `update`
  checks out a tag (detached HEAD), which suits machines that only use the playbook.

## Releasing a new version (on the development machine)
```bash
bash tests/run-all.sh                     # must be green
# edit VERSION + CHANGELOG.md
git commit -am "release: vX.Y.Z" && git tag -a vX.Y.Z -m vX.Y.Z
git push origin main vX.Y.Z               # CI runs on the tag
```

## Automatic update reminders (optional)
Linux / WSL (cron, every Monday at 9:00):
```
0 9 * * 1 $HOME/agent-playbook/install.sh update --check >> ~/.agents/playbook-update.log 2>&1
```
Claude Code has a `SessionStart` hook that can run `install.sh update --check` and print a one-line
notice. Adding the hook changes the harness configuration, so only do it when you ask for it.
