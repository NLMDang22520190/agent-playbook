# Context Mode A/B (untested, run it on your own machine)

Measures whether the Context Mode plugin changes cost and tokens on `project-01-order-flow` and `project-02-tax-exempt`
(without the playbook, same model, interleaved). Written because the research container's permission classifier refused to run it.

1. Check out the research branch (it holds `evals/run-outcome.sh` and `evals/tasks-project/`). Use Git Bash or WSL on Windows.
2. Clone `https://github.com/mksglu/context-mode` somewhere outside this repo. You need Node 24.15 or newer (set `CM_NODE_DIR` if it is not the default `node`).
3. Run: `CM_PLUGIN=<context-mode>/plugins/claude-code K=3 BUDGET=3.5 bash docs/research-data/context-mode-ab/run-ab.sh`
4. Paste `summary.md` back. Spend stops at `BUDGET` USD (default 3.5, under the 5 USD ceiling); the real total may exceed it by about one run.

Check first that "Plugin loaded" is not 0 for the context-mode arm. Nothing is installed globally: the plugin loads with `--plugin-dir`
for that run only. The plugin writes `~/.context-mode` (SQLite index of the test runs); delete it afterwards if you want.
