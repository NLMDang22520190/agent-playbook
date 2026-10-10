# Changelog

## 0.12.0 - 2026-10-10
Three changes from the first real evals (`evals/results/2026-10-10-claude-code-2.1.296.md`):
- **Point out injected instructions** (E8): the always-on block now says not to follow instructions found
  in data and to tell the user what was found. Re-run: the agent named the hidden comment and did not act.
- **Choose the weight consistently** (E1): `playbook-tdd` decides Full when existing behaviour of code the
  repo documents as critical changes; a purely additive change there is Lite; the weight line quotes the
  rule or file:line. Re-run: Lite, quoting `docs/notes.md:2` (run 1 had chosen Full, run 2 Lite).
- **"No tests" requests** (E3): ask once and offer the test (it is cheap); if declined, label the result
  untested. Re-run: labelled untested and offered the test, but still did not ask first (partial).
- Block: 44 lines, 4,927 / 5,000 bytes.

## 0.11.1 - 2026-10-10
- fix: the eval runner's `401` auth marker matched digits inside ids (a transcript UUID `…-401e-…`
  marked E1 and E15 as harness errors). Found by the first real eval run.
- **First real behaviour evals** (Claude Code 2.1.296 headless): `evals/results/2026-10-10-claude-code-2.1.296.md`.
  E1 4/4 and E15 6/6 auto checks after the fix, and both transcripts load `playbook-tdd`; E3 partial
  (no tests under "no need for tests", not silent); E8 did not act on the embedded instruction but did
  not point it out. Findings are listed in the results file.

## 0.11.0 - 2026-10-10
- **`tools/ship.sh PR vX.Y.Z [--yes]`**: one command from a green PR to installed release: refuses a
  dirty tree and any PR that is not OPEN/CLEAN, asks before the merge and before the tag (a terminal is
  required unless `--yes`), runs `release.sh` (dry run first), waits for the CI run of the tag's commit,
  checks the GitHub Release and runs `install.sh update --yes`.
- **Release checks**: the README metrics row `Always-on block | L / 60 lines · B / 5,000 bytes` must
  match `AGENTS.global.md` (spacing tolerant; an unreadable row is refused, not skipped).
- **Eval auth errors**: transcripts saying "not logged in" or `authentication_failed` mark the scenario
  ERROR even when the adapter exits 0. First real run with Claude Code 2.1.295 headless: all four
  scenarios ERROR because the standalone CLI was not logged in — the runner refused to grade them.
- **Gate notes** show control characters in config values as `?`.
- **Shorter always-on block and skill descriptions** (same rules): block 4,759 → 4,699 bytes, descriptions
  1,541 → about 1,370 characters.
- Tests: the test-update fixture copy keeps files whose names start with `-`.
- Built at Full weight: Sonnet tester (2 rounds), Opus reviewer (CHANGES: stale README byte count,
  metrics-row spacing, CI run picked by tag commit, empty/null run list, dirty tree; all fixed test-first).

## 0.10.0 - 2026-10-10
- **Project config no longer breaks gates and releases**: `conf.sh set ... --project` adds
  `.agents/playbook.conf` to the repo's local exclude file (once, with a notice) when the file is neither
  tracked nor ignored. Before, `playbook-setup` writing `test_cmd --project` left an untracked file that
  role gates counted as a code change and `release.sh` refused as a dirty tree.
- **A moved gate is visible**: `role-gate.sh check` prints a `note:` line for each `test_path_regex` /
  `test_infra_regex` that comes from a config file (scope and value), and when an empty project
  `test_infra_regex` switches off a global one. Without those keys the output is unchanged.
- **Empty `test_path_regex` fails closed** (exit 3): it matched every path, so the tester could change code.
- **Every README badge is checked at release**: all version badges must equal `VERSION` (pre-release
  forms like `0.9.0--rc.1` are refused), and the always-on badge must show the block's real line count.
- **Live release output**: `release.sh` streams the suite (tee) and still uses run-all's exit status.
- test-run-checks counts its PyYAML-dependent assertions as skipped, so passed + skipped is the same on
  every OS (checked on WSL and Git Bash).
- Built at Full weight: Sonnet tester, Opus reviewer (APPROVE, 3 minor findings fixed in a second test
  round: shadowing note, line count without a final newline, notes on stdout pinned).

## 0.9.0 - 2026-10-10
- **Load the skill, not the summary**: a new always-on section tells the agent to load the skill a
  rule names (Claude Code: the `Skill` tool; Codex/OpenCode: read its `SKILL.md`) and say which one it
  loaded. `/skill-doctor` had shown playbook-tdd, -proof, -learn and -feedback with 0 uses in 7 days:
  agents followed the summary and skipped the procedures. New eval E19; E15 now also FAILs when the
  transcript shows no load of playbook-tdd. The `claude` eval preset runs
  `claude -p --output-format stream-json --verbose` so tool calls reach the transcript.
- **Test infrastructure gets its own role** (opt-in): project key `test_infra_regex`; matching paths
  classify as `infra`; `role-gate.sh check infra` allows only them, and the tester and implementer may
  not change them. An invalid `test_path_regex` or `test_infra_regex` now stops the gate with exit 3
  instead of letting every file through.
- **README numbers are checked at release**: `check-release.sh` compares the README version badge with
  `VERSION`; `release.sh` compares every README test count with passed + skipped from the run.
- **test-run-all cannot hang**: every run-all call is guarded (`timeout`, or a polling watchdog that
  kills the process group); `PB_FORCE_WATCHDOG=1` exercises the watchdog on every OS.
- **Windows**: role-gate tests no longer depend on git's CRLF warnings (`core.autocrlf=true`);
  test-release counts its PyYAML-dependent assertions as skipped instead of dropping them; fewer
  processes in install.sh and the test-update fixture copy.
- Built at Full weight: Sonnet tester, Opus reviewer (2 rounds: APPROVE with 2 recommended fixes, then
  APPROVE). The first Windows run found two problems WSL could not show (a reduced-PATH fixture that
  breaks Git Bash DLL loading, CRLF warnings in byte-exact gate output); both fixed before release.

## 0.8.0 - 2026-10-10
- **Generic model keys are visible and no longer written** (from playbook feedback: a Codex
  setup run wrote `model_tester=...`, which then applied to OpenCode too): `role-model.sh check
  [--harness H]` lists every generic `model_<role>` key (global or project, empty values included) and
  exits 1; `conf.sh set model_<role>` still writes but warns on stderr; `playbook-setup` never writes
  generic or undocumented keys and runs `role-model.sh check` when it verifies. The fallback to a generic
  key is kept for compatibility. New eval E18.
- **Skipped assertions are counted**: `t_skip COUNT REASON` in `tests/lib.sh`; the summary line reads
  `P passed, F failed, S skipped`. On Windows Git Bash `/` is writable, so test-evals shows
  `146 passed, 0 failed, 15 skipped` instead of silently reporting 15 fewer.
- **run-all uses a job pool**: the next suite starts as soon as any running one finishes (live pids
  checked with the builtin `kill -0`, bash 3.2 safe); a suite whose wrapper dies without an exit code
  fails the run instead of hanging it.
- **Faster on Windows**: config lookups (`pb_conf_read`) are pure bash (three processes fewer per
  lookup); `run-checks.sh` checks CR in one pass before falling back to per-file checks (and falls back
  when that pass fails), and reads the shebang with the builtin `read`. Git Bash, same machine:
  `test-run-checks.sh` 247 s → 146 s, full suite 518 s → 319 s. WSL stays at 22–29 s with 122 more tests.
- Docs: `docs/update-lifecycle.md` describes the three-OS CI and `tools/release.sh`; the role gate
  and setup references say why `*.snap` counts as a test path and when to override it.
- Built at Full weight: tester and reviewer in separate contexts (Sonnet tester × 3 runs, Opus reviewer
  × 2 rounds). Round 1 found two majors (a pool-order assertion that failed every time on Git Bash; a skip
  count off by one) and four minors (pool hang on a dead wrapper, CR check false pass when `cat` fails,
  two unpinned `pb_conf_read` behaviours); all fixed, the surviving mutants are now caught.

## 0.7.0 - 2026-10-10
- **Evals mark harness errors instead of grading them**: `evals/run-evals.sh` reports `ERROR` (not FAIL) when the
  adapter exits non-zero, times out, or the transcript shows an auth error (`invalid x-api-key`, `401`, ...), and
  exits 4 when any scenario hit one. A broken API key no longer looks like a playbook regression.
- **Faster on Windows**: `feedback.sh` reads each item once into variables instead of one `sed` per field
  (Git Bash `test-feedback.sh`: 92 s → 54 s); `tests/run-all.sh` runs suites in parallel batches
  (`PB_JOBS`, default 4, ordered output; WSL: 42.8 s → 29.1 s).
- **Locale-safe patterns**: `sed`/`grep` name and key patterns use POSIX classes (`[[:lower:][:digit:]]`) instead
  of `[a-z0-9]` ranges.
- fix: `tools/release.sh --dry-run` no longer runs `git fetch` (reads `origin/main` with `git ls-remote`);
  `release.sh` and `check-release.sh` reject a tag containing a newline; `install.sh update` names the newest tag
  when several tags point at the same commit; `run-checks.sh` accepts a quoted `name:`/`description:` value.
  Not changed: `*.snap` stays a test path for the role gate (snapshot files are test expectations).
- Docs: the TDD beginner guide and the update lifecycle are now in English
  (`docs/tdd-for-beginners.md`, `docs/update-lifecycle.md`), translation only.
- Built at Lite weight per item (small, reversible); one escalation to a fresh tester when an old assert
  (timeout → exit 1) contradicted the new spec.

## 0.6.0 - 2026-10-10
Cost levers that keep every rule (tester ≠ implementer ≠ reviewer at Full, test-first, fresh full evidence at close-out, gates):
- **Model per role, per harness**: `scripts/role-model.sh` (`model_<role>_<harness>` → `model_<role>` → `session`);
  `playbook-tdd` passes it to each harness (Claude Code Agent `model`, OpenCode per-role agent in `opencode.json`,
  `codex exec -m`). **Setup asks for the models per role and writes a recommendation table first** (reviewer:
  strongest available or another vendor; implementer: mid-tier; tester: mid/low-tier; with reasons and relative
  cost), ranking only from what the harness reports; the user accepts or picks.
- **Focused tests in sub-agents**; the orchestrator runs the full suite once at close-out, and a failing close-out
  sends the work back into a new RED/GREEN round.
- **Tester checklist** `## Make every check able to fail` (mutants, environment overrides, destructive targets, boundaries).
- **Slice size** guidance and **`templates/role-prompt.md`** (fixed text first, per-slice variables last) for prompt caching.
- **Scripts**: `scripts/tdd-step.sh red|green` (gate + proof-run + optional `--commit`, never commits `.agents/handoff/`,
  notes when it adds it to `.git/info/exclude`); `tools/release.sh` (checks + tests + tag, `--dry-run`).
- **Cost**: `scripts/cost.sh add|summary`; the final report has `## Cost`.
- fix: shell `case` patterns used `[a-z]` ranges, which follow the locale's collation on bash 3.2
  (macOS, en_US.UTF-8: `BAD` matched `[a-z]`); `pb_valid_key` and `valid_harness` now list the characters.
  Found by the first macOS CI run of `role-model.sh`.
- Built at Full weight with the levers applied: 11 sub-agent runs, 891,089 tokens (tester 5 × Sonnet, implementer 5 × Sonnet,
  reviewer 1 × Opus). Two disputes resolved by fresh testers (origin default branch in a fixture; handoff files in commits);
  one review round (tester checklist gaps, exclude notice); the tracked-handoff test turned a "dead code" finding into a pinned guard.

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
