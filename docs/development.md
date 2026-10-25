# Development notes

For people who change agent-playbook itself or tune it beyond the defaults. Users need only the [README](../README.md).

## CI

CI cancels superseded runs of the same PR (concurrency, never on main or tags) and every job has a timeout.

A main push reuses a green same-repo PR run of the identical tree (a merge commit or a squash of an up-to-date PR) and skips its own suites; `tools/ci-tree-tested.sh` finds that run through `gh api` only. A rebase merge reuses a PR run only when its single resulting commit has the PR head tree and its parent is P, the base the PR head was last updated on. A rebase of several commits, and any merge of a PR that is not up to date, run the tests.

A PR that adds tests updates the README count with `tools/readme-count.sh LOG` (LOG is a `tests/run-all.sh` output). The Ubuntu job runs `tools/readme-count.sh --check` on full runs, so a stale count fails the PR. A PR that changes only `README.md` and `CHANGELOG.md` (test counts unchanged, found by `tools/docs-only.sh`) runs a reduced set of checks in the test jobs: the suites that read those two files, `tests/test-content.sh` and `evals/run-checks.sh`. A main push never takes the reduced path, and `tools/ci-tree-tested.sh` reuses a PR run only when the full `Tests and static checks` step succeeded in all five suite jobs.

## Development checks

`tools/bsd-check.sh [SUITE...]` runs the suites (default: all) with one-true-awk (`original-awk` or `nawk`) first on PATH, which is the awk macOS ships (`sudo apt install original-awk` on Ubuntu or WSL).

For the static checks, `run-checks.sh` runs shellcheck when it is installed (`sudo apt install shellcheck` on Ubuntu or WSL,
`brew install shellcheck` on macOS) and skips it otherwise. It also refuses GNU-only options that macOS lacks (grep with the PCRE flag, readlink canonicalise, date with a string, stat with a format flag, find with a print format, xargs with no-run-if-empty, sed extended).

## Pre-commit hook

An optional pre-commit hook (opt-in) catches a lost executable bit, which agents often drop when they edit a script with an edit tool. `tools/install-hooks.sh` installs `tools/pre-commit` into this repo's hooks dir (`--force` replaces a different hook, `--uninstall` removes only the one it installed). The hook refuses a commit that would store a script as git mode 100644 and names each path with the fix (`git update-index --chmod=+x PATH`). It runs `evals/run-checks.sh --only modes`, so it follows the same rule as the CI check. The leak guard takes priority: if `.git/hooks/pre-commit` is the leak-check hook (`scripts/leak-check.sh install-hooks`), `tools/install-hooks.sh` refuses to replace or remove it, even with `--force` (exit 1). Only one pre-commit hook fits there, so run the check by hand with `bash evals/run-checks.sh --only modes`. Installed in the other order, `leak-check.sh install-hooks` leaves our hook alone and exits 1. Nothing installs it automatically.

## Leak guard

A leak guard, `scripts/leak-check.sh`, refuses tokens, keys and your own private strings (`leak_literals`) in added lines. A `leak_patterns` entry for a key prefix should start with a token-start boundary, for example `(^|[^A-Za-z0-9_-])sk-[A-Za-z0-9_-]{12,}`, so words like `task-...` do not match. `install-hooks` adds pre-commit and pre-push hooks. After upgrading the playbook, re-run `leak-check.sh install-hooks` to get the per-remote pre-push scan. A push to a URL no configured remote owns scans every commit; `PB_LEAK_SCAN_BASE=<full 40-hex commit id>` limits that scan to that id..pushed commit (an invalid id, an empty range or a non-ancestor exits 3).

## Models, cost and quality scripts

Each role gets its own model, per harness. Setup lists the models your harness offers and recommends a strong model (or another vendor) for the reviewer, mid-tier for the implementer, and mid- or low-tier for the tester; you accept or pick. `scripts/role-model.sh <role> --harness <h>` resolves it (`model_<role>_<harness>` → `model_<role>` → `session`), and `role-model.sh plan` prints the line the agent shows before it starts roles. A configured model is binding: the agent does not upgrade or downgrade it on its own. `confirm_models=always|on-change|never` (default `on-change`) sets when it asks you: on-change asks once, and only when it wants a different model or a role resolves to session on a Full task. Reasoning effort per role: `model_<role>_reasoning_effort[_<harness>]`.

Mechanical steps are scripts: `scripts/tdd-step.sh red|green` (gate + evidence + optional commit), and `tools/release.sh` for maintainers.

Quality checks run by script. `scripts/mutate.sh --base REF --test CMD` flips operators on the changed lines in a throwaway worktree and lists the mutants your tests missed. `tools/eval-guard.sh --base REF` names the behaviour evals that a skill-wording change should re-run, with a capped command; it never runs them, and `tools/ship.sh` prints it before the tag. `cost.sh calibrate` shows per weight, from tasks logged with `--task`, whether Full reviews found anything (advice only). Disjoint slices may run in parallel in separate worktrees, and `learn.sh add --role` and `learn.sh checklist ROLE` turn project learnings into per-role checklists.

Cost is measured: `scripts/cost.sh add` per role run, and `cost.sh summary` in the final report (per role and per phase, with rework rounds and review majors; `--phase`, `--rework`, `--majors`). `scripts/pr-body.sh` builds the PR description from the spec, the final report and the review verdict. Models can be routed by task type: `spec_reviewer` for the Full-weight spec reviewer sub-agent (falls back to the reviewer's model), `reviewer_light` for diffs of tests, docs or skill text, and `mechanical` for release prep and counts. `evals/run-evals.sh --max-cost USD` stops running scenarios once the known costs reach USD.

## Measured cost

Two old measurements, kept for scale. Neither is a benchmark.

- v0.3.1 fix at Full: about 5 minutes and 225k tokens for the three roles.
- v0.6.0 at Full: 11 sub-agent runs and 891k tokens (tester and implementer on Sonnet, reviewer on Opus).

## Maintainer tools

`tools/` holds the release and CI helpers: `release.sh`, `ship.sh`, `check-release.sh` (VERSION and CHANGELOG per tag), `release-pr-check.sh` (check-release on a PR that changes VERSION), `readme-count.sh` (README test count), `docs-only.sh`, `ci-tree-tested.sh`, `shard-weights.sh`, `eval-guard.sh`, `bsd-check.sh`, `get-bash32.sh`, `setup-labels.sh` (feedback issue labels), and `pre-commit` with `install-hooks.sh` (the opt-in hook above), and `clean-pbtest.sh` (manual: removes stale `pbtest.*` temp dirs a killed suite left; dry run unless `--yes`). `report-usage.sh OWNER/REPO [--limit N] [--since YYYY-MM-DD]` counts, numbers only, how many merged PR bodies carry each report part (Weight line, proof labels, Not checked, Pre-mortem, Playbook feedback, Request coverage, Models used); it reads them with `gh pr list` and needs no jq.
