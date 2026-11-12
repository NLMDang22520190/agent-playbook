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
