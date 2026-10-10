# Playbook update lifecycle

```
Work session (Claude / Codex / OpenCode, any machine)
  └─ skill playbook-feedback: record evidenced proposals (passively, without interrupting the work)
       └─ end of task, at most once per feedback_interval_days: preview → you approve → feedback.sh submit
            └─ issue on your private feedback repo (feedback_repo; submit refuses a public repo)
               (duplicate check, labels harness/kind/source)
You triage (monthly)
  └─ an agent drafts a PR: the skill change + its eval scenario + VERSION/CHANGELOG
       └─ CI (Ubuntu + macOS + Windows Git Bash, all required on main) runs tests/run-all.sh → you review → merge
            └─ tools/release.sh vX.Y.Z tags main and pushes the tag
                 └─ CI on the tag re-runs the tests; the release job creates the GitHub Release
Each machine
  └─ install.sh update --check  (cron / Task Scheduler / by hand)
       └─ install.sh update --yes → check out the tag → re-install every target recorded in .install-targets → doctor
            (roll back: install.sh update --to vX.Y.Z --yes)
Quarterly: re-check docs/harness-notes.md against the official docs, run E1–E18 in full on each harness
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
1. On the feature branch: edit `VERSION`, add the `## X.Y.Z - date` entry to `CHANGELOG.md`, then run
   `bash tools/check-release.sh vX.Y.Z` (VERSION and CHANGELOG agree) and `bash tests/run-all.sh` (must be green).
2. Open a PR. CI must pass on all three OS before `main` accepts the merge.
3. After the merge, on an up-to-date `main`:
   ```bash
   bash tools/release.sh vX.Y.Z --dry-run    # checks + full suite, prints what it would tag and push
   bash tools/release.sh vX.Y.Z              # tags HEAD of main and pushes the tag
   ```
   `release.sh` refuses when `check-release.sh` fails, the tree is not clean, HEAD is not on `main`,
   `main` differs from `origin/main`, the tag already exists, or the suite fails. CI on the tag runs
   the tests again and the `release` job publishes the GitHub Release from the CHANGELOG entry.
4. On each machine: `install.sh update --yes`.

One command for the merge, step 3 and step 4 on the development machine, once the PR is open and its CI is green:
`tools/ship.sh <PR> vX.Y.Z` (asks before the merge and before the tag; `--yes` only when you already
agreed). It merges, runs `release.sh` (dry run first), waits for the tag's CI, checks the GitHub Release
and runs `install.sh update --yes`.

## Automatic update reminders (optional)
Linux / WSL (cron, every Monday at 9:00):
```
0 9 * * 1 $HOME/agent-playbook/install.sh update --check >> ~/.agents/playbook-update.log 2>&1
```
Claude Code has a `SessionStart` hook that can run `install.sh update --check` and print a one-line
notice. Adding the hook changes the harness configuration, so only do it when you ask for it.
