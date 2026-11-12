# Context Mode A/B (untested, run it on your own machine)

Measures whether the Context Mode plugin changes cost and tokens on `project-01-order-flow` and `project-02-tax-exempt`
(without the playbook, same model, interleaved). Written because the research container's permission classifier refused to run it.

1. Check out the research branch (it holds `evals/run-outcome.sh` and `evals/tasks-project/`). Use Git Bash or WSL on Windows.
2. Clone `https://github.com/mksglu/context-mode` somewhere outside this repo. You need Node 24.15 or newer (set `CM_NODE_DIR` if it is not the default `node`).
3. Run: `CM_PLUGIN=<context-mode>/plugins/claude-code K=3 BUDGET=3.5 bash docs/research-data/context-mode-ab/run-ab.sh`
4. Paste `summary.md` back. Spend stops at `BUDGET` USD (default 3.5, under the 5 USD ceiling); the real total may exceed it by about one run.

Check first that "Plugin loaded" is not 0 for the context-mode arm. Nothing is installed globally: the plugin loads with `--plugin-dir`
for that run only. The plugin writes `~/.context-mode` (SQLite index of the test runs); delete it afterwards if you want.

## Second run: large tool output (task project-05-tax-exempt-noisy)

The first run (project-01 and project-02) never triggered the plugin: the model made 0 `ctx_*` calls because every file was under 16 KB.
`project-05-tax-exempt-noisy` is project-02 plus generated noise so a natural run meets large output: `npm test` prints about 65 KB
(400 generated cases), `docs/tax-history.md` is 33 KB and `data/orders-2025.csv` is 62 KB. The ticket, hidden tests and solution are those of
project-02 (self-check OK). Estimated cost: about 0.3 to 0.5 USD per run, so use `K=3 BUDGET=2.5` (6 runs):

`TASKS=project-05-tax-exempt-noisy CM_PLUGIN=<context-mode>/plugins/claude-code K=3 BUDGET=2.5 bash docs/research-data/context-mode-ab/run-ab.sh`

New column in the summary: median tool-result KB per run (bytes of tool results in the transcript), the quantity Context Mode claims to cut.
Read the `ctx tool calls` column first: if it is 0 again, the model ignored the plugin and the arm says nothing about its benefit.
Runner exit 1 means some run failed a hidden test (a normal FAIL), not an error.

## Third benchmark: long session (task project-06-long-session)

One prompt with three tickets done in order in ONE session: company tax exemption (project-02), returns (project-01) and a duplicate-charge
incident in `logs/payments.log` (1419 events, 107 KB, 7 orders charged twice; rule in `docs/payments.md`). Hidden tests are the union of
project-01 and project-02 plus `tests/incident.f2p.test.js`. Same noisy shop as project-05 (matrix test, 33 KB tax history, 62 KB sample
orders). Self-check OK. It is meant to make the context grow far beyond the small tasks. The summary now has a column
*Median peak context tokens* (largest input side of any API call in the run), which is the quantity that decides whether a context
compressor has anything to compress.

Estimated cost 0.5 to 1.2 USD per run [SUY LUẬN, not measured]; run ONE baseline run first to read the real peak context and cost, then
decide k and the ceiling:

`TASKS=project-06-long-session CM_PLUGIN=<context-mode>/plugins/claude-code K=1 BUDGET=2 bash docs/research-data/context-mode-ab/run-ab.sh`

For billion-context the same task is the benchmark, but only with a throwaway key and the isolation steps in `docs/research-context-tools-2026-11-11.md`.

## Fourth benchmark: wide refactor, large context (task project-07-wide-refactor), ceiling 15 USD

Why: project-06 peaked at about 59K context tokens, below the regime where either tool claims value. `project-07-wide-refactor` is a reports
module with 24 report files (8 over 16 KB, so Context Mode's hook denies a full Read of them) and three tickets that each touch every
report (one money formatter, rename of the row field, generation date from `ctx.now`). Self-check OK. The setup repo is about 190 KB of
source, so a session that reads and edits everything can pass 100K context tokens. Whether it does is what phase 1 measures.

The adapter now also allows `cd`, `echo`, `pwd`, `diff` and `sort` for both arms, because a denied `cd . && ...` compound command changed the run
in the project-06 pilot (a permission artefact, not the plugin).

Ceiling 15 USD in total, 3.684 USD used before this benchmark, so 11.3 USD left. Plan with a stop rule:

Phase 1 (one run per arm): `TASKS=project-07-wide-refactor CM_PLUGIN=<context-mode>/plugins/claude-code K=1 BUDGET=4 OUT_DIR=<dir> bash docs/research-data/context-mode-ab/run-ab.sh`
Read peak context and cost per run in `summary.md`. Stop if a run costs more than 2.5 USD or if peak context is under 100K (the task still does not reach the regime).
Phase 2 (only if phase 1 is under 2.0 USD per run and peak context is over 100K): `START=2 K=3 BUDGET=9 OUT_DIR=<same dir> ...` gives 3 runs per arm.
Total spend stays under 15 USD; the script stops starting runs once the sum of `cost_usd` reaches `BUDGET`.

## Step A before any more paid runs: addressable share of context (`docs/research-data/addressable-share.js`)

Free, runs on YOUR transcripts (Claude Code keeps them as `.jsonl` under `~/.claude/projects/<project>/`, plus `subagents/`). Prints aggregates only
(no message text). Usage:

`node docs/research-data/addressable-share.js ~/.claude/projects/<your-project> --json share.json`

It computes the share of all input-side reads that comes from tool results of 4 KB or more (Context Mode indexes output above 4 KB and denies a
full Read above 16 KB), plus the ideal saving if those were cut by 50, 80 or 95 percent, per tool, and the peak context per transcript.
Thresholds fixed BEFORE looking at any data: under 10% means Context Mode cannot matter much (stop); 20% or more means a paired best-case run
(step B) is worth its cost; between is gray. Sanity run by the author on one cloud research transcript (WebFetch heavy, 175 calls, 2 compactions):
headline 10.0% (4 to 16 KB: 5.7%, 16 KB or more: 4.3%), all tool results 14.3%; gray zone, not representative of your work. Paste your run's output back.

## Step A2 for billion-context: cost share of re-reading old history (`docs/research-data/history-share.js`)

Free, runs on your transcripts, prints aggregates only. Run it twice, with the default multipliers and with the other documented pair:

`node docs/research-data/history-share.js ~/.claude/projects/<your-project> --json share2.json`
`node docs/research-data/history-share.js ~/.claude/projects/<your-project> --read-mult 0.05 --write-mult 2 --json share2b.json`

Headline: cost share of re-reading history older than 50 calls (what a history compressor could shrink), plus the cold-restart share of cost.
Pre-registered: under 10% means stop; 25% or more means a paired test with a throwaway key could be worth its cost; between is gray.
