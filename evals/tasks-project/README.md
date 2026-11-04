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
Status: `project-01-order-flow` is written and self-checked; it has not been calibrated with a real agent run.
