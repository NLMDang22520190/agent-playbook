# Project-level outcome tasks (pilot)

Tasks that build a feature across several files from an ambiguous brief, graded only by hidden tests like `evals/tasks/`
(same format: `evals/tasks/README.md`). They live in their own directory because `tests/test-outcome-corpus.sh` pins the
bug-fix corpus; run them with `--tasks-dir evals/tasks-project`.

Purpose: measure whether a planning layer (business flow, requirements, roadmap before the per-change spec) changes quality or
cost on work the bug-fix corpus cannot separate. The hidden tests are grouped on purpose:

| Group | Test file | What it checks |
|---|---|---|
| Stated rules | `refunds-rules` | rules in the ticket and `docs/policy.md`, on numbers that divide exactly |
| Invariants | `refunds-invariants` | no cent lost or invented in any return order, whatever allocation the agent chose |
| Cross-module | `refunds-page` | the order page follows the refunds |
| Ambiguity | `decisions-logged` | the open question is settled in `docs/decisions.md` (CONTRIBUTING.md names the file) |

Self-check: `bash evals/check-tasks.sh --tasks-dir evals/tasks-project` (also applies every `testdata/wrong-*.patch`).
Calibrate before use: run `--arm without --repeat 2` and keep the task only if it separates (not all pass, not all fail).

## Running it where `claude -p` has no write permission

The stock `claude` preset runs `claude -p` with no permission flag. In a cloud container every write is then refused, the agent
changes nothing and the run is graded FAIL (not ERROR), which looks like a hard task. Use the adapter, which accepts edits inside
the workdir and a short list of shell commands (the runner passes the model as `PB_EVAL_MODEL`; there is no playbook in that
container, so the without arm needs no extra isolation):

```bash
bash evals/run-outcome.sh --cmd "bash evals/tasks-project/claude-cloud-adapter.sh" --model claude-sonnet-5-5 \
  --tasks-dir evals/tasks-project --arm without --repeat 3 --clean-env --max-cost 4
```

## Calibration (2026-11-04, without the playbook, final version of the task)

| Model | Runs | Passed all hidden tests | Median cost per run | Where the others failed |
|---|---|---|---|---|
| claude-sonnet-5-5 | 3 | 1 | about 0.20 USD | an error code the ticket does not list (1), `reports.js` and the decision log not touched (1) |
| claude-haiku-5-5 | 3 | 1 | about 0.02 USD | `reports.js` not touched (2) |

k=3 is too small to separate the models. It shows the task is neither saturated nor impossible. Earlier versions of the task
were passed by Sonnet 2/2 in both attempts (the README named `reports.js` and said the docs can lag; those cues are removed). All
six runs used the 14 days of `config/returns.json`, so the docs-versus-config trap did not catch anyone. The decisive traps are the
hidden second place (`dailyRevenue` must subtract refunds on the day they are made) and following the ticket's list of error codes.

## First comparison with the playbook (2026-11-04, Sonnet 5.5, k=5 per arm, same adapter and settings)

| Hidden test | with playbook | without |
|---|---|---|
| `refunds-rules` | 5/5 | 4/5 |
| `refunds-invariants` | 5/5 | 5/5 |
| `refunds-page` | 5/5 | 5/5 |
| `refunds-report` (hidden second place) | **0/5** | 4/5 |
| `decisions-logged` | 4/5 | 4/5 |
| all hidden tests | **0/5** | 4/5 |

Median cost per run: about 0.80 USD with the playbook, 0.18 without (4.4 times). Read these numbers with care:

- **Found but not fixed.** In all five with-arm runs the final report names `dailyRevenue` as ignoring refunds, quotes `docs/finance.md`
  and leaves it out of scope for the user to decide ("I left it out of scope"). The hidden test grades the fix, so the run fails
  although the problem was surfaced. Four of the five without-arm runs fixed it without asking. This is the playbook's scope rule
  against its own "decide reversible things and log them" rule; the hidden test cannot tell "missed" from "surfaced". A transcript check
  for "surfaced" would separate them.
- **The with arm was degraded by the container.** Each run met about 4 to 11 refused tool calls (git writes in `.git`, reading
  `~/.agents`, commands with several operations); one final report says the playbook scripts were not reachable, so `role-gate.sh` and
  `cost.sh` did not run as intended. The adapter does not allow the `Agent` tool by name, yet 4 runs started sub-agents, so some did work.
- The invented error code of one earlier without-arm run did not recur: the with arm stayed on the two codes of the ticket in 5/5 runs.
- k=5 per arm. Without-arm pass rates seen for this task: 1/3 (first attempt), 4/5 (this one).
