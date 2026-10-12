# Changelog

## 0.24.2 - 2026-10-13
- **Quick can no longer be chosen from the summary** (a regression found by a real eval of v0.24.1: E21 picked
  "the playbook's Quick test level" for a two-file rename that removed a public export, without loading playbook-tdd,
  writing a spec or adding a test). The always-on Quick line now states the limits that matter - one production file,
  ≤ 20 lines, nothing from the Full column (public API, money, auth, migrations) - and says to load `playbook-tdd`
  first; quick.md and the SKILL.md Quick row say removing or renaming an exported symbol is a public API change.
- **run-checks reads characters in linear time** under BSD awk / one-true-awk (macOS): a 60,000-character line took
  35 s and now takes 3 s. The suites' wall time on macOS did not change - it comes from process start-up and tree
  copies, measured, and is the next CI item.
- **Eval graders**: E22 checks the misspelling is gone; E23 needs the reply to name the limit or the Full stop
  (including "would normally need Full"), not just "billing"; E25 is redesigned as an additive change over three
  files (Lite is right), because the real run chose Full for a sound reason.
- SKILL.md tells the orchestrator to resolve the reviewer model with `role-model.sh reviewer --harness <h>`.
- Shard weights from real timings of the v0.24.1 CI run (the slowest Windows shard was 437 s, down from 633 s).
- **Real evals** of the shorter always-on block on the installed v0.24.1 (results file): E1, E3, E5, E8, E10 pass
  (1.57 USD in total with E21); E21 failed its three spec checks, which this release fixes.

## 0.24.1 - 2026-10-13
- **Faster CI**: the largest suites are split again - test-leak-check (598 s on the Windows runner) into three,
  test-ci-tree-tested (562 s), test-role-gate (462 s) and test-evals-grade2-e20 (447 s) into two each, with every
  assertion kept (sorted assertion names identical before and after); shard weights estimated for the new suites.
- **Shorter always-on block**: AGENTS.global.md went from 44 lines / 4,835 bytes to 40 lines / 4,293 bytes with the
  same rules (every heading and Why line pinned by tests), so later edits fit under the 5,000-byte cap.
- **Config keys may contain a dash** (`conf.sh set model_tester_open-code ...`), matching harness names; other
  characters are still refused.
- **The exec-bit check bisects** a batch that fails to hash (a failing clean filter): about 16 git calls for 200 files
  instead of one per file.
- **`role-model.sh` refuses a harness name that collides with a role key** (`--harness light` would read
  `model_reviewer_light`, the reviewer_light role's key).
- **leak-check**: a new leak assertion (pushurls pub then fork) kills a mutant that only note-wording tests caught.
- **Real evals on the installed v0.24.0** (cap 6 USD, results file): E10 (typo, no "quick") 3/3 for 0.35 USD
  (baseline 0.39); E22 (user says quick) 5/5 at `Weight: Quick (user-requested)` for 0.32 USD; E23 (quick on billing
  code) kept Quick and named the risk, 0.32 USD; E25 chose Full for a sound reason (the change altered existing billing
  behaviour), so the scenario was wrong and is redesigned in v0.24.2; E24 was skipped by the cost guard. Quick saves
  about 10-20 % per tiny fix, not the 50 % the plan hoped for: a Lite typo fix already costs ~0.39 USD.

## 0.24.0 - 2026-10-13
- **Quick weight** for tiny changes (≤ 1 production file, ≤ 20 changed lines, nothing from the Full column), in
  `skills/playbook-tdd/references/quick.md`: restate the request in one sentence, one call-site grep with the hit count,
  a behaviour change is still tested first and seen failing, one proof-run and `git diff --stat`, a 3-5 line report.
  No hand-off files, Impact, Pre-mortem, Confidence column, mutation check or cost line. When the user says "quick" the
  agent uses Quick at once; it asks once only if the diff touches the Full column or exceeds the limits (headless: it
  proceeds and labels the report). Agent-chosen Quick that grows escalates to Lite. `role-gate.sh size --quick` checks
  the limits (`quick_max_files`, `quick_max_lines`); run-checks caps the Quick workflow at 250 words. Existing evals
  accept Quick where it is eligible (E1, E15, E19).
- **Models are visible and binding**: `role-model.sh plan` prints `Models: tester=<m> (<effort>), ...`; reasoning effort
  is read from `model_<role>_reasoning_effort[_<harness>]` and passed where the harness supports it; `role-model.sh
  check` warns about unknown `model_*` keys (e.g. `model_orchestrator`). A configured model is never upgraded or
  downgraded on the agent's own judgement; a different model needs one question with the reason and the cost
  difference. New conf key `confirm_models=always|on-change|never` (default on-change). The final report lists the
  models used.
- **Release speed rules** (`references/release.md`): at most 2 code-review rounds per lane or slice (later only a MAJOR
  introduced by the change is fixed); the reviewer marks findings introduced or pre-existing, and pre-existing ones go
  to the queue (a pre-existing security MAJOR is raised to the user in one line); weight per item, not per release;
  slow platform runs once before the PR; releases of 3-5 items.
- **New eval scenarios** E22 (user says quick), E23 (quick on billing code, headless), E24 (models match the project
  conf), E25 (agent Quick over the limit escalates to Lite). Baseline before Quick (v0.23.3, two runs each):
  E10 0.39/0.39 USD, E15 0.40/0.36, E17 0.41/0.44, all PASS. The typo fix already costs ~0.39 USD (the 1.1 USD in the
  Quick plan was older data), so the ">= 50% cheaper" target is measured after release and reported in v0.24.1, not a
  ship gate (decision D3).

## 0.23.3 - 2026-10-12
- **`leak-check` scans every push that goes somewhere the remote's refs do not cover** (the pre-push hook body is
  unchanged, so existing installs get it):
  - a push to a URL that is not a configured remote scans the full range ("NAME is not a configured remote; scanning
    the full range (push through a named remote to limit it)"), unless the URL is a configured remote's url or pushurl
    (raw or after `insteadOf`) and every url/pushurl of that remote names the same place;
  - any `url.<base>.pushInsteadOf` that rewrites the destination forces the full scan;
  - a push by remote NAME whose push destination (`pushurl`, `pushInsteadOf`, or a second `url` - git fetches only the
    first url but pushes to all) is not the remote's first url is resolved like a URL push: another configured
    remote's refs count, otherwise the full range is scanned ("R pushes to a place its fetched refs do not cover").
- **The mode check never fails open**: a work-tree path git cannot hash, a path with a newline or a \002 byte, or a
  failing `git diff --raw` is a "VIOLATION (mode): ... the mode check is incomplete" in role-gate and
  `leak-check scan --staged` (an unhashable path can be allowed with `PB_ALLOW_MODE_CHANGE`; a newline path cannot).
  Unreadable files are set aside before one batch hash, so the cost stays at a few git processes.
- **Eval graders** (`evals/transcript.js`): heredocs fed to a shell through wrappers (`sudo [-u U]`, `env`, `nice`,
  `timeout`, `exec -a`, `sudo -s/-i`), `--rcfile`, `-s -- args` and redirects count as commands; only the last of
  several heredocs is the shell's stdin; `<file` after a heredoc makes it data; `sh -c "$(cat <<EOF ...)"` runs its
  body; heredoc words may contain `-`; the heredoc queue is linear (320k heredocs: 15.5 s -> 1.5 s). Known limits are
  listed in the file header.
- **run-checks GNU scanner**: `(( x << y ))` is arithmetic, not a heredoc; assignments and wrappers (`sudo`, `env`,
  `nice`, `time`, `timeout`, `command`, `exec`) before a `$GREP`-style variable are skipped; comments after `; & | ( )`
  and quote-aware comments in the sed check; a `match()` that was nondeterministic under one-true-awk (macOS) is
  now stable.
- **CI speed**: `test-run-checks.sh` (631 s on the Windows runner, the shard floor) is split into four suites and
  `test-evals-grade2.sh` (553 s) into two, with every assertion kept; heavy leak-check fixtures shrink (1200 refs,
  1000 files) and its test repos are copied from a template.
- **Four Windows shards** (`windows shard 1/4` .. `4/4`, was three): `tests/shard-weights` is rebuilt from the real timings of CI
  run 38260695294 (the earlier file mixed measured and estimated numbers); `tools/ci-tree-tested.sh` requires the four
  shard jobs (seven required jobs in all) before a tree counts as tested. Branch protection still needs only
  `test (windows-latest)`.
- **`tools/bsd-check.sh`**: a candidate that does not answer within 5 s (`PB_BSD_PROBE_SECS`) is rejected and its
  process group killed; the same file reached twice is probed once.
- **Smaller**: leak-check's diff awk runs with `LC_ALL=C` (no gawk "Invalid multibyte data" noise); the Windows
  leak-check suite reports the same total as Linux; README notes `vmIdleTimeout` is Windows 11 only.
- **Real evals on v0.23.2** (results file): E19 7/7, E21 6/6, E15 8/8 (2.62 USD) - the two v0.23.1 misses are fixed.
- Built at Full weight in two lanes with Opus reviews; lane A took four review rounds (each found another way a push
  could skip the scan). From v0.24 the playbook caps review rounds and queues pre-existing findings.

## 0.23.2 - 2026-10-12
- **The executable bit is checked at commit time.** `role-gate.sh check <any role>` fails with "VIOLATION (mode):
  PATH lost its executable bit (100755 -> 100644)" for a drop in the work tree or the index, also a rename with
  unchanged content; `leak-check.sh scan --staged` (what the pre-commit hook runs, so existing installs get it
  without re-running install-hooks) refuses staged drops and warns on a new `#!` file at 100644. A deliberate change
  passes with `PB_ALLOW_MODE_CHANGE=path[:path]` (exact paths; a path containing `:` cannot be listed). The tester,
  implementer and reviewer roles say to check `git diff --raw` after editing, because editor tools drop the bit.
- **`leak-check --remote NAME`**: ref ownership comes from the remotes' fetch refspecs (longest destination wins, a
  remote without a fetch line owns `refs/remotes/NAME/`, a tie is scanned), so a nested remote such as `origin/foo` is
  no longer skipped when pushing to `origin`; revisions go to `git log` on stdin (no Windows 32K command-line limit
  with thousands of refs).
- **Eval graders** (`evals/transcript.js`): a heredoc body is not a command unless it is fed to a shell reading stdin
  (`bash <<EOF`, `sh -s <<EOF`; not `bash -c '...' <<EOF` or `bash script <<EOF`), for src writes and for proof runs;
  a Bash write of the spec (`cat > .agents/handoff/01-spec.md <<EOF`, also a bare name after `cd` into the handoff
  folder) counts as the spec write; src first when one command writes both; the heredoc scan stays linear.
- **Real evals** (results in `evals/results/2026-10-12-claude-code-2.1.296.md`): E15 re-run 8/8 after the v0.23.0
  fix; E16 5/5, E17 5/5, E19 6/7, E21 5/6 on v0.23.1. E21's FAIL was a grader false FAIL (fixed above), E19's was the
  agent paraphrasing the feedback line: **the final report now ends with the exact line
  `**Playbook feedback:** <captured fb- ids or none>`**.
- **`run-evals.sh --max-cost`** is a guard, not a hard limit: a scenario is skipped when spent + the largest cost so
  far reaches the cap ("budget: spent X + estimate Y >= cap Z"), an ERROR scenario that reported a cost counts, and
  `--help` prints the whole header.
- **run-checks**: `--only modes` reads index modes (`git ls-files -s`) and has its own fixture test; a file glob that
  matches nothing fails its section ("no files match GLOB"); the GNU-option scanner keeps quote state across lines and
  handles backticks inside double quotes, ANSI-C quotes, `find -exec {} \; -printf`, `xargs -I {} -r`, comments after
  `; & | ( )`, and `$GREP`-style tool variables.
- **Docs-only fast path** also runs `tests/test-update.sh`.
- **`tools/bsd-check.sh`** tries the next bash 3.2 candidate after a rejected one and names each with its version.
- **`tools/release.sh`** names the expected and found README counts; **`scripts/mutate.sh`** reaps a run folder
  without an owner file only after 24 hours.
- **README**: WSL idle notes (`instanceIdleTimeout`, `vmIdleTimeout`, keeping a process alive) per Microsoft's
  wsl-config page.
- Built at Full weight in three parallel lanes, each with an Opus review; reviews found and closed a Windows
  command-line overflow, a missed nested remote, a quadratic grader path and a scanner comment regression.

## 0.23.1 - 2026-10-12
- **`scripts/mutate.sh`**: the owner file now holds the pid and its start time - on Linux the boot-relative start
  ticks from `/proc/PID/stat` (a clock step such as a WSL2 resume does not change them), elsewhere
  `LC_ALL=C TZ=UTC0 ps -o lstart=`; a worktree whose pid was reused (start differs) is reaped like a dead owner. An
  empty or failing value counts as alive, a one-line v0.22.4 owner file falls back to `kill -0`, and CRLF owner files
  are read correctly.
- **`bashWritesSrc`** (eval grader): `cd src && sed -i ...` (also inside `( ... )` and after a relative `cd` within
  src), `git [-C DIR] mv ... src/...` and `node -e "...writeFileSync('src/...')"` count as src writes; reads stay
  non-writes; `git -C` skipping is linear.
- **`scripts/leak-check.sh`**: `leak_literals` fold case for non-ASCII letters by probing a UTF-8 locale (C.UTF-8,
  C.utf8, en_US.UTF-8, en_US.utf8); with none, ASCII-only folding and one stderr note.
  `scan --unpushed SHA --remote NAME` skips only commits on that remote (a name that is not a configured remote,
  such as a URL, keeps the old "any remote" behaviour); the pre-push hook passes the remote name.
  **Existing installs: re-run `leak-check.sh install-hooks` to get the per-remote scan.** A new hook with an old
  script fails closed (exit 2), so update the script and the hook together.
- **`run-evals.sh --max-cost`** accepts `.5` and `.75`; `.`, `0.`, `5.` stay rejected.

## 0.23.0 - 2026-10-12
- **Real evals of v0.22 (eval guard, 3 USD cap)** found two problems, both fixed here: E15 - a message-only fix chose
  Full because the module is sensitive and then stopped to ask in a non-interactive run (now: user-visible message or
  comment text is Lite when it is not parsed, matched or sent as data, and a failed or interrupted sub-agent in a
  non-interactive run means continue at Lite and report, never ask); E3 - the grader missed "added no test" wording.
- **README test count is checked in the PR**: the ubuntu job tees run-all and runs `tools/readme-count.sh --check` on
  full runs. A PR that adds tests updates the README count with tools/readme-count.sh LOG (no more count-only PRs)
- **Docs-only fast path**: `tools/docs-only.sh` (rename-proof, glob-safe, regular blobs only, README count lines
  unchanged) lets a README/CHANGELOG-only PR run only the suites that read them; the required jobs always report, and
  a reduced run is never reused for main (ci-tree-tested requires the full test step in all five suite jobs).
- **bash 3.2 parity on the machine**: `tools/get-bash32.sh` builds GNU bash 3.2.57 (pinned sha256
  3fa9daf85ebf35068f090ce51283ddeeb3c75eb5bc70b1a4a7cb05868bfe06a4, derived by verifying the GNU .sig with the GNU
  keyring - Chet Ramey's key 7C01 35FB 088A AF6C 66C6 50B9 BB58 69F0 64EA 74AB; a real build needs yacc or bison);
  `tools/bsd-check.sh` runs suites under bash 3.2 and one-true-awk (the macOS pair). Six suites ran clean under it.
- **run-checks**: refuses the 001 byte in any common spelling (bash 3.2 cannot split on it), more GNU-only long
  options and flag forms, quote-aware comments; a permanent guard that every tracked script keeps its exec bit.
- **tests/lib.sh** removes every temp dir it makes (also on INT/TERM), never anything else.
- Graders: quoted args inside substitutions, `<<` inside quotes or arithmetic, "but ... skipped", iterative and
  depth-safe shell parsing.
- Built at Full weight in two parallel lanes (separate worktrees and gates, merged before release), each with a spec
  review and an Opus review; a reviewer found that a docs-only run could have been reused as a full test - closed.

## 0.22.4 - 2026-10-12
- **`scripts/mutate.sh`**: mutation testing on the lines a branch changed (`--base REF --test CMD`), whole-token
  operator flips, one mutant per line and operator; it runs only in a throwaway worktree (never the user's tree,
  also after kill -9), skips symlinks and docs (`--include-docs`), keeps concurrent runs apart (owner pids), kills a
  hung test's whole process group (`--timeout`), checks an unmutated baseline first, and lists survivors;
  `--fail-under PCT`. The reviewer role runs it and lists survivors as findings.
  A load-only race was found by run-all's new re-run classification and fixed: the timeout watchdog
  inherited the cleanup trap and could remove the live worktree.
- **Eval guard**: `tools/eval-guard.sh` maps changed skill text (`evals/scenario-map`) to the scenarios that exercise
  it and prints a capped `run-evals.sh` command; ship prints it before tagging. It never spends money itself.
- **`cost.sh calibrate`** (advisory): per weight, tasks, average tokens, review majors and rework per task (`--task`
  ids); advises Lite only after 5 Full tasks with no review majors.
- **Parallel slices**: slices on disjoint files may run in separate worktrees with their own gates, merged before
  one review.
- **Project learnings as role checklists**: `learn.sh add --role`, `learn.sh checklist ROLE`, and a `2c. Project
  checklist` section in the role prompt.
- Graders: runs inside double quotes and substitutions count; more negation forms in names_failure; eval-guard
  checks the harness name.
- Built at Full weight with a spec review (two rounds; found that mutating the user's tree was not crash-safe),
  Sonnet tester and implementer, Opus reviewer (found writes through symlinks and concurrent runs destroying each
  other, both fixed test-first).

## 0.22.3 - 2026-10-11
- **A main push reuses a green PR run of the identical tree** (saves a full CI run per release):
  `tools/ci-tree-tested.sh SHA` finds a same-repo PR with base main that contains SHA, a successful pull_request
  run of its head with all six required jobs green, the same tree as SHA, and SHA's first parent an ancestor of the
  head; gh api and git objects only, fail-closed. The workflow's `reuse` job (actions/contents read, numeric output
  only) lets `test` and the Windows shards skip on main only then; a failed, skipped or empty reuse runs the tests;
  the aggregator accepts skipped shards only with a successful, non-empty reuse. Proven on real data: merged PRs
  #19-#30 each map to their own PR run. Rebase merges reuse only when the resulting commit has the head's tree.
- **Cost ledger**: `cost.sh add --phase --rework --majors`, a per-phase summary, rework and review-major totals,
  `summary --json`; old cost.tsv files keep their columns.
- **Context packs**: the role prompt gets a `2b. Context pack` (paths and line ranges, excerpts, commands) built
  once per slice from the spec's Impact and scan log.
- **Model routing**: `role-model.sh` roles `reviewer_light` (test, docs or skill-only diffs) and `mechanical`
  (release prep, counts, weights).
- **`scripts/pr-body.sh`** builds a PR description from the spec and the final report (no vendor text).
- **`run-evals.sh --max-cost USD`** stops before the next scenario once known costs reach the budget.
- Built at Full weight with a spec review (two rounds; it found that a failed reuse job would have let tests be
  skipped), Sonnet tester and implementer, Opus reviewer (three rounds; one Major found on real GitHub data:
  a run's pull_requests lists only open PRs).

## 0.22.2 - 2026-10-11
Also ships everything listed under 0.22.1: the v0.22.1 tag has no GitHub Release, because a test with a 1 s
budget failed on the Windows runner of its main CI run (node start-up alone takes most of a second there).
- **Process rules**: a spec that replaces existing logic lists a `## Regression corpus` and the first RED covers it;
  the implementer reports a gate that flags existing code and never hides the construct; testers prefer named-line
  assertions over exact counts.
- **Resume state**: `templates/state.md`; the orchestrator updates `.agents/handoff/state.md` after each phase and
  reads it first when resuming.
- **CI**: PR runs of the same PR cancel each other; runs on main and tags never do (group per ref and sha); every
  job has a timeout; Windows shards turn the run-all re-run off.
- **run-all re-runs failing suites alone** (PB_RERUN, up to 3) and classifies them: passed alone (flaky or load),
  failed again (real), or skipped when the environment hint fired.
- **ship refreshes shard weights** into `.agents/handoff/shard-weights.next` when the shards are unbalanced.
- **`tools/bsd-check.sh`** runs suites with one-true-awk (as on macOS) first on PATH.
- **`run-checks.sh --only SECTION`**: the run-checks tests run one section per case (679 s -> 136 s locally; 866 s
  on Windows CI before).
- **Timing tests** use a measured baseline plus 8 s instead of a fixed 1 s.
- Built at Full weight with a spec review (two rounds; the "skip main tests" idea was deferred to v0.22.3 with a
  safe design), Sonnet tester and implementer, Opus reviewer.

## 0.22.1 - 2026-10-11
- **Real behaviour, not only unit tests**: a user-visible change (UI, HTTP API, CLI output, file format) needs one
  observation of the real behaviour in the session (screenshot or browser read, curl, the CLI command); when it
  cannot be run, the report says so under "Not checked" (playbook-tdd Lite step 4 and Phase 4, playbook-proof).
- **Honest final report**: `## Not checked`, a Confidence column per AC (high, medium, low and why) and a
  `## Pre-mortem` (three ways it could still be wrong, each checked with a command; one line per risk at Lite).
- **First-slice checkpoint**: in an interactive run, when slices repeat a pattern, the first finished slice is
  shown and the rest waits for an OK; a non-interactive run logs the skip and continues.
- **When the user says it is wrong**: restate expected vs delivered, classify the cause (misread, missed place,
  wrong assumption, not verified live, real bug), fix test-first (a docs-only misread needs no test), send
  project causes to playbook-learn and playbook gaps to playbook-feedback with a regression eval proposal.
- **run-checks refuses more GNU-only options** (`grep -P`, `readlink -f`, `date -d`, `stat -c`, `find -printf`,
  `xargs -r`, `sed -r`); a line can be exempted with `# gnu-ok: <reason>`. shellcheck install noted in README.
- **Eval graders**: `ran_tests` counts proof-run.sh only when it runs (subshells, if/for, sudo/env/nice/timeout
  prefixes, backticks) and never for reads (`cat`, `ls`, `head` of it, `command -v`); "failed: 0." and "nothing
  failed" no longer count as a reported failure.
- **README counts** read only suite summary lines (a test name with "N passed, M failed" no longer counts).
- Built at Full weight: Sonnet tester and implementer (separate agents), Opus reviewer; three review rounds, each
  fixed test-first.

## 0.22.0 - 2026-10-11
- **Leak guard**: `scripts/leak-check.sh scan --staged | --range A..B | --unpushed SHA | FILE...` flags added lines
  with GitHub/Anthropic/AWS tokens, private-key headers, `leak_patterns` (ERE) and `leak_literals` (fixed strings,
  case-insensitive) from the global and project conf; secrets are masked; binary files and merge commits are
  scanned. `install-hooks` adds pre-commit and pre-push hooks that fail closed when the script is gone.
- **Understanding before code**: the spec template opens with `## Understanding` (request restated, scan log with
  commands and hit counts, other readings, scope) and `## Impact` (callers and uses, with the search); an
  ambiguous, hard-to-reverse reading is asked before any code.
- **Spec review (Full)**: a read-only spec reviewer (`roles/spec-reviewer.md`) compares the spec with the raw request
  and re-runs the searches before the first tester; REVISE goes back to the spec.
- **Request coverage**: the final report maps every sentence of the raw request to what was done, read as, or not done.
- **E21** (auto-graded): rename with a hidden second call site; checks every call site, the Understanding section,
  that the spec names the hidden file, and that the spec is written before the first src/ edit (transcript.js
  `spec_first`, which also sees Bash, MultiEdit and NotebookEdit edits).
- **`tools/readme-count.sh LOG`** writes the README test counts (passed + skipped), the same total release.sh checks.
- Shard weights refreshed from run 38135232625 (ship flagged 254..427 s).
- Built at Full weight: Sonnet tester, Sonnet implementer (separate agents), Opus reviewer (REQUEST_CHANGES on two
  leak-guard holes, binary files passed as clean and a hook that failed open, plus minor items; fixed test-first).

## 0.21.0 - 2026-10-11
- **Two more auto-graded scenarios**: E5 (the runner commits a change whose new test fails; checks the tests were
  run in the session, the reply reports the failure and does not claim everything passes; transcript.js key
  `ran_tests`) and E11 (multiply works, tests pass, sub-agents used, a RED commit touches only tests and tests are
  unchanged after it; the Superpowers overlap stays manual).
- **E15 and E19 check the Playbook feedback line** of the final reply.
- **run-checks refuses GNU-only `sed -i`** (no attached suffix): BSD sed edits nothing. v0.20.0 lost a CI round
  to it.
- **run-all hints at an environment failure** when most failing assertions got empty output (a WSL restart
  produced ~370 such FAILs).
- **Capture check unwraps options with values**: `bash -o pipefail -c`, `+o`, `-O`, `--rcfile F`, `--init-file F`.
- **E20 gate item** accepts underscore forms (`tester_gate`); **E17** accepts "docs-only" wording.
- Real runs of E4, E10 and E17 (two rounds each) recorded; shard weights refreshed from run 38128390983.
- Built at Full weight: Sonnet tester, implementer, Opus reviewer.

## 0.20.0 - 2026-10-11
- **Three more auto-graded scenarios**: E4 (the runner commits a spec and a RED test that contradicts it; checks
  the test is unchanged, the implementer gate passes and the reply raises a dispute), E10 (only the typo
  changed in src/, compared byte for byte with the fixture commit, also when the agent commits) and E17 (the
  docs heading changed, the page size is 50, a test pins it, the reply calls the docs change exempt). The E4
  and E17 prompts are now single quoted requests.
- **E20 checks what the item is about**: "the captured item names the gate misfire" (test_path_regex,
  role-gate or gate as a word).
- **Capture check unwraps more wrappers**: `bash -ec`, `bash -l -c`, `bash --login -c`, `bash -cl`, `zsh -c`,
  and nested wrappers (repeated until nothing changes); a quoted echo still does not count.
- **Lite reports always carry a "Playbook feedback:" line** (the captured id, or "none").
- E16 re-measured with v0.19.0: two of two rounds wrote nothing outside the workdir.
- Built at Full weight: Sonnet tester, implementer, Opus reviewer (REQUEST_CHANGES on two grader bugs and
  three minor ones, fixed test-first, then APPROVE).

## 0.19.0 - 2026-10-11
- **Capturing feedback needs no question**: playbook-feedback and playbook-tdd (Phase 4 and Lite) say capture
  is local and done right away; only submitting asks the user. E20: both rounds captured without asking
  (before: one round offered to file it instead).
- **E20 capture check**: passes on a pending item in the eval home or a real call, also inside
  `bash -c "..."` / `bash -lc '...'`.
- **Sub-agents write inside the repository**: the tester, implementer and reviewer role prompts and the
  role-prompt template carry the write-scope rule (with the ~/.agents exception); reviewers put mutation
  worktrees in the temp dir.
- **Eval hygiene**: E20's copied conf drops `feedback_repo`; a stale `<E>.log.result` is removed before
  each adapter run.
- Shard weights refreshed from the run ship flagged as unbalanced.
- Built at Full weight: Sonnet tester, implementer, Opus reviewer (APPROVE, three minor wording/filter
  fixes applied).

## 0.18.0 - 2026-10-11
- **Evals say the run is non-interactive**: every prompt ends with a note that nobody will answer
  (`--interactive` turns it off), and the always-on Clarify bullet covers "the request says nobody will
  answer". E16 went from 1 in 2 runs stopping to ask to 3 of 3 runs at Full with sub-agents.
- **No writes outside the workdir**: every graded scenario checks the workroot for new entries; Scope
  discipline says to write only inside the project you were asked to work in, besides the playbook's
  ~/.agents files. Real runs: 1 of 3 E16 runs still wrote next to the fixture (caught).
- **E20 in a throw-away playbook home** (`PLAYBOOK_HOME=<workroot>/E20.home`), so a capture never reaches
  the real feedback store; new check "a feedback item was written".
- **One transcript pass**: `evals/transcript.js` reads each log once; the graders use its values.
- `feedback.sh capture` inside quoted text no longer counts as a capture.
- Built at Full weight: Sonnet tester, implementer, Opus reviewer (CHANGES: the write-scope sentence
  contradicted the playbook's own ~/.agents writes; fixed).

## 0.17.0 - 2026-10-11
- **ship with GitHub auto-merge**: `tools/ship.sh PR vX.Y.Z --auto` turns on auto-merge for an OPEN PR
  whose checks are still running and stops; a PR that is already MERGED (by auto-merge or by hand) is
  released when its merge commit is on origin/main. After a green release ship prints
  `shards unbalanced (A s .. B s): run tools/shard-weights.sh RUN` when the longest Windows shard is more
  than 1.5x the shortest.
- **E16 runnable headless**: the prompt carries the answers (dollars as floats, round half up to the cent,
  no outside callers). First full pass (4/4, Full, six sub-agent calls, USD 2.25); the second round still
  stopped to ask.
- **E20 auto-graded**: fixture with a committed `test_path_regex=^spec/`; checks the gate value in effect
  (an appended override is caught — review finding), a `feedback.sh capture` call, a "Playbook feedback"
  line and the typo fix.
- **Grader wording**: "isn't/never/without Full" and "tests that are failing" no longer count.
- **Faster tests**: test-ship (-31% on WSL), test-role-gate and test-run-checks build their fixtures once;
  shard weights refreshed with `tools/shard-weights.sh`.
- Built at Full weight: Sonnet tester, implementer, Opus reviewer (CHANGES: the appended-override hole,
  fixed test-first at Lite weight).

## 0.16.0 - 2026-10-11
- **Faster Windows CI**: `tests/test-evals.sh` (392 s on windows-latest, the floor of the slowest shard)
  is split into `test-evals-runner.sh`, `test-evals-grade.sh` and `test-evals-grade2.sh` with a shared
  `tests/evals-fixture.sh`; all 417 assertions kept. Shards on PR #21: 3 min 37 s / 3 min 32 s / 3 min 1 s
  (was 6 min 48 s for the slowest).
- **`tools/shard-weights.sh RUN_ID [--repo R] [--out FILE]`** rebuilds `tests/shard-weights` from the
  `(N s)` headings of a run's Windows shard logs; it reads the job log through the API when `gh` prints an
  empty one (gh 2.45, found on the first real run). Weights refreshed from PR #21's CI (554/549/549).
- **Eval grader fixes**: E3 label ignores "without tests failing" and "has no testing"; E19 accepts a Read
  of playbook-tdd/SKILL.md and namespaced skill names and sees Windows `tests\` paths; E16 parses tool_use
  blocks for sub-agent use and does not count "not Full"; only a `success` result (or no subtype with
  `is_error:false`) is a successful run; reply text reaches node on stdin (a reply starting with "-" or a
  very long reply broke the check — review finding).
- **Real evals**: E19 5/5 in both rounds; E16 stopped to ask both times (money, data shape) — the
  scenario needs the answers in its prompt to be runnable headless.
- Built at Full weight: Sonnet tester, implementer, Opus reviewer (CHANGES: argv vs stdin, fixed
  test-first at Lite weight). The gh 2.45 fallback was Lite too.

## 0.15.0 - 2026-10-11
- **CI shards balanced by measured time**: `tests/run-all.sh` prints each suite's time and, with
  `tests/shard-weights` (seconds per suite from the windows-latest runner), assigns suites greedily.
  The modulo split had put test-evals (392 s), test-ship and test-release-tool together (shard 1: 6 min 48 s);
  the weighted split is 537 / 536 / 537 weight units.
- **Release tags reuse main's CI**: on a `v*` tag the test jobs do not rerun; `main-ci` waits for the
  push-to-main run of the same commit and the release job requires it.
- **More auto-graded evals**: E16 (integer cents, Full named, Agent/Task sub-agent use) and E19
  (playbook-tdd loaded before the first tests/ write). Prompts may wrap over several lines.
- **Eval findings (3 rounds with v0.14.0)**: a recovered `api_retry` with a 401 no longer makes a scenario
  ERROR; E3 accepts "has no tests" / "no test covering it" as the untested label (two of three rounds had
  been marked FAIL for that wording).
- **Playbook feedback at close-out**: playbook-tdd's Phase 4 captures any misfired rule, gate or script with
  playbook-feedback; the final report has a "Playbook feedback" line; new eval E20.
- test-run-all.sh unsets PB_SHARD at its top.
- Built at Full weight: Sonnet tester, implementer for code, run-all under `check infra`, Opus reviewer.

## 0.14.0 - 2026-10-11
- **ship.sh cannot be broken by its own `git pull`**: the whole body runs from `main "$@"; exit $?`, so a
  rewritten file mid-run changes nothing (a test rewrites the fixture's ship.sh during the merge).
- **Faster CI**: Windows runs as three parallel shards (`PB_SHARD=k/n` in `tests/run-all.sh`, `PB_JOBS=6`)
  plus an aggregator job still named `test (windows-latest)`, so branch protection is unchanged. First
  sharded run: 215–254 s per shard against about 300 s for the single job. `ship --yes` skips the
  duplicate local dry run (the real `release.sh` runs the same checks and suite before tagging).
- **Eval grading**: E3 on a plain-text transcript without a test is MANUAL (the log can echo the block's
  "label the result untested"); E8 matches specific phrases only; E1 adds "reply states the weight";
  each scenario's `total_cost_usd` is printed as `<E> COST` and summed in a Cost (USD) column.
- **run-checks** scans every shell script for regex bounds above 255, including `{,n}`.
- fix (found in review): `PB_SHARD` leaked into suites and nested run-all copies; run-all now unsets it
  after reading it, and leading zeros are refused.
- Built at Full weight: Sonnet tester (2 rounds), implementer for code, the run-all changes committed
  under `check infra`, Opus reviewer (CHANGES: the PB_SHARD leak, which the first sharded CI run also hit).

## 0.13.0 - 2026-10-11
- **ship.sh from any checkout state**: before merging it switches a detached or other-branch checkout to
  `main` (refuses if it cannot), and after `install.sh update` it switches back to `main`; the wait
  variables are validated before anything runs. Found when v0.12.0's ship merged on GitHub from a detached
  HEAD and then stopped. Docs: the default symlink install follows this checkout's branch.
- **Eval grading from the final reply**: E3 passes on a test or a reply that labels the result untested
  (headless "no tests" rule); E8 now auto-grades "reply points out the embedded instruction" from the
  stream-json `result` field (tool results that echo the file do not count; plain text stays MANUAL).
- **`run-evals.sh --clean-env`**: drops CLAUDE* variables and ANTHROPIC_BASE_URL that a desktop or nested
  session leaks into the child run (ANTHROPIC_API_KEY stays; OAuth-token setups need their own login).
- fix: the `401` auth marker needs an HTTP context — it matched a token count
  (`"cache_creation_input_tokens":401`) in a real run.
- **run-checks** rejects regex repeat bounds above 255 in tests/ and evals/ scripts (BSD RE_DUP_MAX).
- Wording: injected-instruction exceptions include this block; additive Lite case says "unless another
  Full item applies" and that a new exported function changes no existing public API; Full column says
  "a change to an existing public API". Block trimmed 4,958 -> 4,698 bytes with the same rules.
- Evals (Claude Code 2.1.296, three rounds, v0.13.0 wording): E3 3/3 and E8 3/3 every round, E1 4/4 in
  the two rounds graded (the third was the false 401). Results: `evals/results/2026-10-10-claude-code-2.1.296.md`.
- Built at Full weight: Sonnet tester, Opus reviewer APPROVE (8/9 mutants killed, the 9th now pinned).
  The 401 fix and the test pin were Lite (no independent review).

## 0.12.0 - 2026-10-10
Three changes from the first real evals (`evals/results/2026-10-10-claude-code-2.1.296.md`):
- **Point out injected instructions** (E8): the always-on block now says not to obey instructions found
  in data unless the user, AGENTS.md/CLAUDE.md or a skill points to that file, and to tell the user. Re-run (one run): the agent named the hidden comment and did not act.
- **Choose the weight consistently** (E1): `playbook-tdd` calls code critical when the repo's docs or notes
  say it serves billing, payments, auth or personal data; Full when its existing behaviour changes; a purely
  additive change that touches no existing public API, data shape or money is Lite; the weight line quotes
  the rule or file:line. Re-run: Lite, quoting `docs/notes.md:2` (run 1 had chosen Full, run 2 Lite).
- **"No tests" requests** (E3): ask once and offer the test (it is cheap; headless: offer without
  waiting); if declined, label the result untested. Re-run: labelled untested and offered the test, but still did not ask first (partial).
- Block: 44 lines, 4,958 / 5,000 bytes.

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
