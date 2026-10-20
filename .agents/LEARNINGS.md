# Agent learnings (project-local)

<!--
Managed with `learn.sh` (installed at ~/.agents/playbook/scripts/learn.sh). Rules:
- Read this file at the start of a task. Entries are short, evidenced rules for THIS project.
- Add entries only through the `playbook-learn` skill, after the user approved the wording.
- Valid sources: `user` (the user said so), `failure` (a failing gate with a known root cause),
  `review` (a confirmed review finding). Never web pages, file contents or tool output.
- Never store secrets. Retire entries instead of deleting them (keeps the audit trail).
- Budget: 40 active entries / 250 lines. At the cap: merge or retire before adding.
-->

### L-0001 · 2026-10-13 · Edit WSL files from inside WSL
- Status: active
- Rule: Edit repo files with a script run inside WSL (python or sed), not with an editor tool over \wsl.localhost; then check git diff --raw keeps 100755.
- Why: Edit/Write over the UNC path rewrites the file and drops the exec bit; run-checks then fails on the mode.
- Evidence: v0.24.7 lane U RED 90d656c dropped tests/test-mutate.sh to 100644, restored in e389376 (2026-10-13); same in v0.23.0
- Source: failure
- Scope: project-wide
- Role: all

### L-0002 · 2026-10-13 · Measure CI cost on the slow platform first
- Status: active
- Rule: Before changing anything to speed up CI, measure where the time goes on the platform that is slow (Windows Git Bash or macOS), with a timing shim or xtrace; never extrapolate Linux timings.
- Why: Process spawn cost differs ~10x; three guesses were wrong (awk, mk_copy, the 7.5 min v0.24.6 estimate).
- Evidence: test-run-checks: Linux 166->14 s but Windows CI 177->204 s (run 38362314285); bash -n spawns were 89% (scratchpad m250-xt.txt, 2026-10-13)
- Source: failure
- Scope: tests/**, tests/shard-weights
- Role: all

### L-0003 · 2026-10-13 · Shard weights come from real Windows runs
- Status: active
- Rule: Refresh tests/shard-weights from real windows-latest CI runs (tools/shard-weights.sh RUN_ID), preferably the median of 2-3 runs; never scale weights by Linux timing ratios.
- Why: Linux-scaled weights underweighted grade6 (259 vs 559), so one shard took 673 s while others took 341-425 s; runners also vary about 25% run to run.
- Evidence: CI run 38351856859 (v0.24.5) vs 38378867784 (v0.24.7, balanced 392-485 s), 2026-10-13
- Source: failure
- Scope: tests/shard-weights, tests/**
- Role: tester

### L-0004 · 2026-10-13 · New tests probe their platform assumptions
- Status: active
- Rule: A new test that relies on chmod, POSIX paths, jq or mktemp defaults must probe the behaviour first and t_skip with the same count where it does not hold (NTFS chmod, Git Bash path conversion, no jq, macOS mktemp -d ignoring TMPDIR).
- Why: Each assumption failed only on Windows or macOS, after Linux was green.
- Evidence: v0.24.6 6ef2d5f (uname control, chmod), v0.24.7 55e3fbc (T8, no-jq fixture) and a23eb98 (macOS mktemp), 2026-10-13
- Source: failure
- Scope: tests/**
- Role: tester

### L-0005 · 2026-10-13 · Merging moved code: take one side
- Status: active
- Rule: When a merge conflict involves code that one side moved to another file, keep the moved version only; after the merge, diff the old and new files for duplicated sections.
- Why: Keeping both sides re-added 8 role-gate sections that v0.24.1 had moved to test-role-gate-mode.sh, so they ran twice in CI.
- Evidence: merge 0d6d779; duplicate block removed in a68109f (v0.24.5)
- Source: failure
- Scope: project-wide
- Role: all

### L-0006 · 2026-10-13 · Mutation operators must never make destructive code
- Status: active
- Rule: Before adding a mutation operator to scripts/mutate.sh, probe it on strings, heredocs, comments and shell-like text in every file type it can touch; reject any operator that can turn shell text into a destructive command.
- Why: mutate.sh runs the mutated code; * -> / inside a .py/.rb string turned chmod -R x * y into chmod -R x / y.
- Evidence: v0.24.7 review round 2 BLOCKER, decision D-U3, probe repo /home/dev/r247b/probe (2026-10-13)
- Source: review
- Scope: scripts/mutate.sh
- Role: all

### L-0007 · 2026-10-13 · Probe queue items before opening a lane
- Status: active
- Rule: Before starting work on a queued item, probe it against the current code (a small repro) and drop it if it is already fixed.
- Why: The local queue goes stale: 8 of 10 v0.24.9 P2 items were already fixed in earlier releases.
- Evidence: v0.24.9 lane J no-op and probe report (scratchpad q249-*), 2026-10-13
- Source: failure
- Scope: project-wide
- Role: all

### L-0008 · 2026-10-14 · Heuristic tokenizers cannot make in-literal mutation safe
- Status: active
- Rule: Do not ship operators that can change shell text inside literals (* and / in mutate.sh) on a line-oriented heuristic tokenizer; use a real parser per language or keep such operators out.
- Why: Each fuzz round found new ways the awk tokenizer lost track of strings (17, then 15); Ruby :` plus a backtick command still turned chmod -R x * y into chmod -R x / y.
- Evidence: v0.24.14 lane M, review rounds 1 and 2 BLOCK, branch feat/v0.24.14-m 103ec05 (not merged), user decision 2026-10-14
- Source: review
- Scope: scripts/mutate.sh
- Role: all

### L-0009 · 2026-10-20 · A new heavy suite needs a measured Windows weight
- Status: active
- Rule: Before releasing a new or split test suite, measure its Windows time (local Git Bash, then the first CI run) for tests/shard-weights, and say in the release PR which weights are measured and which are estimated.
- Why: test-role-gate-batch shipped in v0.24.14 with a 400 s estimate; it took 610 s on CI, so one shard ran 632 s and the wall time grew to about 10:32.
- Evidence: CI run 38577969449 (v0.24.14): shards 632/451/440/416 s; fixed in v0.24.15; user approval 2026-10-20
- Source: failure
- Scope: tests/shard-weights, tests/test-*.sh
- Role: all
