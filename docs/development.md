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

Each role gets its own model, per harness. Setup lists the models your harness offers and recommends a strong model (or another vendor) for the reviewer, mid-tier for the implementer, and mid- or low-tier for the tester; you accept or pick. `scripts/role-model.sh <role> --harness <h>` resolves it (`model_<role>_<harness>` → `model_<role>` → `session`), and `role-model.sh plan` prints the line the agent shows before it starts roles. Under the claude harness the reviewer default is sonnet when no key sets it (spec_reviewer and reviewer_light follow it); to undo it, set `model_reviewer=session` or `model_reviewer_claude=session`. A configured model is binding: the agent does not upgrade or downgrade it on its own. `confirm_models=always|on-change|never` (default `on-change`) sets when it asks you: on-change asks once, and only when it wants a different model or a role resolves to session on a Full task. Reasoning effort per role: `model_<role>_reasoning_effort[_<harness>]`.

Mechanical steps are scripts: `scripts/tdd-step.sh red|green` (gate + evidence + optional commit), and `tools/release.sh` for maintainers.

Quality checks run by script. `scripts/mutate.sh --base REF --test CMD` flips operators on the changed lines in a throwaway worktree and lists the mutants your tests missed. `tools/eval-guard.sh --base REF` names the behaviour evals that a skill-wording change should re-run, with a capped command; it never runs them, and `tools/ship.sh` prints it before the tag. `cost.sh calibrate` shows per weight, from tasks logged with `--task`, whether Full reviews found anything (advice only). Disjoint slices may run in parallel in separate worktrees, and `learn.sh add --role` and `learn.sh checklist ROLE` turn project learnings into per-role checklists.

Cost is measured: `scripts/cost.sh add` per role run, and `cost.sh summary` in the final report (per role and per phase, with rework rounds and review majors; `--phase`, `--rework`, `--majors`). `scripts/pr-body.sh` builds the PR description from the spec, the final report and the review verdict. Models can be routed by task type: `spec_reviewer` for the Full-weight spec reviewer sub-agent (falls back to the reviewer's model), `reviewer_light` for diffs of tests, docs or skill text, and `mechanical` for release prep and counts. `evals/run-evals.sh --max-cost USD` stops running scenarios once the known costs reach USD.

## Measured cost

Two old measurements, kept for scale. Neither is a benchmark.

- v0.3.1 fix at Full: about 5 minutes and 225k tokens for the three roles.
- v0.6.0 at Full: 11 sub-agent runs and 891k tokens (tester and implementer on Sonnet, reviewer on Opus).

## Maintainer tools

Release flow: each lane or item ends with its hand-off files. The release PR body is the `scripts/pr-body.sh` output, one block per item for a release of several items (`bash scripts/pr-body.sh --handoff <worktree>/.agents/handoff >> pr-body.md`), and the PR is opened with `gh pr create --body-file pr-body.md`. The steps, in order:

1. Run the full suite (`tests/run-all.sh`) and update the README test count (`tools/readme-count.sh`).
2. Make the release commit (VERSION, CHANGELOG) and push it.
3. On that exact commit, with a clean tree, run `tools/release-gate.sh --harness claude --model <model>`. It spends money (about 150 paid runs per release, k=5, both arms). It measures the scenarios that `docs/delta-audit.md` marks KEEP or INCONCLUSIVE, the "gate: safety" rows E8 and E33, plus the three default tasks, so a change that breaks a scenario outside the gate set (ZERO, ZERO-1, PROCESS-ONLY or UNMEASURED) is not caught. E24 gives a signal only with `--harness claude`. E13 and E34 are KEEP because of the hooks, which are installed by default since v0.33.0; the gate runs the behaviour runner with `--hooks` for claude and `--cmd`, and a pooled file without `"hooks": true` fails rule a. Before the first paid run the gate calls both runners with `--preflight` (node, git, the harness CLI, python3 for a python3 task) and stops with exit 3 if one fails. It measures HEAD through `--variant` in a detached worktree. Besides rules a to e, rule f fails the gate when a with-arm check passes clearly less often than in the previous release gate (the baseline: the newest earlier released tag with a qualifying gate of the same harness and model; Newcombe 95% interval of the change wholly below 0; no earlier gate means no baseline and the rule passes, earlier gates with none qualifying means it fails), and rule g requires the safety floors (E13 table not dropped, the E8 and E33 injection checks, nothing written outside the workdir) to pass in every with-arm run. Set `PB_VARIANT_HOME` to install the variant into another harness home. Exit 0 means pass; 1 means fail and prints the reasons.
4. Commit only `evals/results/gate-<sha>/` (the `.gitignore` in it keeps transcripts out) and push.
5. Nothing else may merge into main before ship. If main moves, update the PR branch, re-run the gate on the new head and commit its results; ship refuses a PR that does not contain origin/main or whose head has no passing gate.
6. Open the PR with the `scripts/pr-body.sh` output as its body (`gh pr create --body-file pr-body.md`) and run `tools/ship.sh PR vX.Y.Z`, which checks the gate, merges, tags and installs.

The gate is the binding check: `tools/release-gate.sh --check` runs in `release.sh`, in `ship.sh` before any merge, in CI for a PR that changes VERSION and in the tag's release job. The eval-guard line that ship prints is advice only. The gate binds against a missing or failing result, not against forged `pb-evals` records, and `--pool-only` and `--check` cannot show that the tree was clean when the runs were made.

pr-body.sh copies Weight, Request coverage, Not checked, Review, Decisions and Unverified; the Pre-mortem, Models used and Playbook feedback lines stay in each hand-off report.

`tools/` holds the release and CI helpers: `release.sh`, `ship.sh`, `check-release.sh` (VERSION and CHANGELOG per tag), `release-pr-check.sh` (check-release on a PR that changes VERSION), `readme-count.sh` (README test count), `docs-only.sh`, `ci-tree-tested.sh`, `shard-weights.sh`, `eval-guard.sh`, `release-gate.sh` (the binding release gate: both arms of the KEEP and INCONCLUSIVE scenarios of `docs/delta-audit.md` and the three default outcome tasks at k >= 5, run with `--variant` on the release commit and pooled per commit into `evals/results/gate-<sha>/`; spends money unless `--dry-run`; `--check [REV]` recomputes the verdict from the committed files and spends nothing), `bsd-check.sh`, `get-bash32.sh`, `setup-labels.sh` (feedback issue labels), and `pre-commit` with `install-hooks.sh` (the opt-in hook above), and `clean-pbtest.sh` (manual: removes stale `pbtest.*` temp dirs a killed suite left; dry run unless `--yes`). `report-usage.sh OWNER/REPO [--limit N] [--since YYYY-MM-DD]` counts, numbers only, how many merged PR bodies carry each report part (Weight line, proof labels, Not checked, Pre-mortem, Playbook feedback, Request coverage, Models used); it reads them with `gh pr list` and needs no jq.

## Signing release tags

`tools/release.sh` signs the tag when a signing key is configured: a non-empty effective `user.signingkey` (global or repo config) makes it run `git tag -s`, so the release tag is a signed annotated tag. Without a key it makes the same lightweight tag as before and prints one line saying the tag is unsigned. If a key is set but signing fails (missing key file, `ssh-keygen` or gpg missing, locked agent), release.sh exits 3, leaves no tag and pushes nothing; it never falls back to an unsigned tag. A `--dry-run` changes nothing. release.sh only reads git config; it never generates a key or writes config.

Set it up once, with an ssh key (`git config --global gpg.format ssh`, `git config --global user.signingkey ~/.ssh/KEY.pub`) or a gpg key (`user.signingkey` set to the key id, `gpg.format` left at its default). To verify a signed tag, list the release key in an allowed signers file and point `gpg.ssh.allowedSignersFile` at it; then `git verify-tag vX.Y.Z` accepts the tag, and `install.sh update` reports "signature verified".

Watch the `main-ci` job of the first signed release. `.github/workflows/test.yml` finds the main run with `--commit "$GITHUB_SHA"`, and whether `GITHUB_SHA` is the commit or the tag object for a signed (annotated) tag push is not verified. If `main-ci` does not find the run or the release is not created, create the release by hand with `gh release create vX.Y.Z`, or change the lookup to resolve `$GITHUB_SHA^{commit}`.
