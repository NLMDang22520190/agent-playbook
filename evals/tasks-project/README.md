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

### Fixed, surfaced or missed (`outcome-classes.js`)

`node evals/tasks-project/outcome-classes.js RESULT.json` reads the runner's JSON and each run's final reply (`<stem>.runs/<label>.log.result`)
and splits a failed hidden test into SURFACED (the reply names the problem, so it is left for the user) and MISSED, using
`surface.json` of the task. It is a text heuristic; it prints the matching line so a reader can confirm it.

| Arm (Sonnet 5.5) | Runs | Finance report: fixed | surfaced | missed |
|---|---|---|---|---|
| with playbook, first run (all tools denied often) | 5 | 0 | 5 | 0 |
| with playbook, second run (`--add-dir` for the playbook home, `Agent` allowed) | 3 | 1 | 2 | 0 |
| without | 5 | 4 | 1 | 0 |

No run missed the problem. What differs is what the run does about it: the with arm names it and leaves it for the user in 7 of 8 runs,
the without arm fixes it in 4 of 5. The second with-arm run still met 5 to 10 refused tool calls per run (git writes, commands with several
operations, heredocs with braces); the bypass-permissions mode that would remove them is blocked in this session, so the with-arm cost
(0.30 to 0.79 USD per run, 0.18 without) is an upper bound.

Other hidden tests, with arm over its 8 runs: `refunds-rules` 8/8 (without 4/5), `decisions-logged` 7/8 (without 4/5).

## Consequence-rule experiment (2026-11-04, P1')

Question: does making "a documented rule the change falsifies becomes an AC" part of the spec's Impact (P1') change what the with arm does
about a consequence of its own change, without making it fix things that were already wrong? Three tasks on one shop repo:

| Task | Family | What it tests |
|---|---|---|
| `project-01-order-flow` | consequence | refunds make `dailyRevenue` wrong (`docs/finance.md`) |
| `project-02-tax-exempt` | consequence | a company pays no tax, `src/invoice.js` repeats the tax rule (`docs/invoicing.md`) |
| `project-03-product-search` | scope control | `listProducts` sorts by price although `docs/catalog.md` says by name; it was already so, and must be left alone (`catalog-scope.p2p`) |

Variant A is the playbook at 1355bcf, variant B the same tree with P1' (four files: `SKILL.md`, `templates/spec.md`, `roles/spec-reviewer.md`,
`roles/implementer.md`). Each variant has its own scratch home (`install.sh install --home DIR --copy`), chosen per run through
`PB_EVAL_WITH_HOME`; this avoids `--variant`, which needs the stock preset (no write permission in a cloud container). Sonnet 5.5, with arm,
k=3 (the third `project-03` run of each variant was skipped by the budget brake).

| Task | A passes all | B passes all | median cost A / B (USD) |
|---|---|---|---|
| project-01 | 1/3 | 2/3 | 1.28 / 1.04 |
| project-02 | 3/3 | 3/3 | 0.42 / 0.48 |
| project-03 (control) | 2/2 | 2/2 | 0.20 / 0.14 |

Without the playbook, Sonnet passed project-02 2/2 and project-03 2/2 (0.04 to 0.13 USD per run).

Reading it: **inconclusive.** Only project-01 differs (fixed 2/3 against 1/3; difference +0.33, 95% interval [-0.32, +0.72]); the two other
tasks are at the ceiling for both variants, so the current playbook already fixes a consequence that is a copy of the logic (project-02)
and already leaves the control alone. The control stays flat under B (no scope creep seen, n=2). Costs do not move beyond run-to-run noise.
Caveats:

- The operative text of P1' sits in `templates/spec.md`; `SKILL.md` only says "see the template" (it is at its 3700-word budget). The
  new `SKILL.md` sentence was seen in all 8 B runs but the template was opened in 1 of 8, so the dose was weak.
- `outcome-classes.js` reads the last `result` of the transcript. One B run ended on a follow-up turn ("that step is already done"), so it was
  classed MISSED although the transcript names `dailyRevenue` 29 times.
- Pooling every current-playbook run on project-01 over three set-ups gives 2/11 fixed against 2/3 for B (difference +0.48, interval
  [-0.06, +0.79]); the set-ups differ (permissions, `--add-dir`), so this is a hint only.
- The adapter stops a long invocation without killing the runner when a file `.pb-eval-stop` exists next to it (later runs exit 3 and
  count as ERROR); the result file of the runner is written only at the end.
