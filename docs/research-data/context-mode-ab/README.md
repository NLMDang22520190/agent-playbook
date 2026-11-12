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
