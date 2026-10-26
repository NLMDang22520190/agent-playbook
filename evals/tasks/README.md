# Outcome-eval tasks

Small offline bug-fix tasks, graded only by hidden tests: the agent gets a repo and a prompt, never the tests that
grade it. Every task here is synthetic: written from scratch for this corpus, with no code, names or data from any
private project and no vendored open-source code. `pattern-*` tasks rebuild a failure pattern seen in real work;
`oss-*` tasks are minimal reproductions of common open-source bug classes.

## Task format

One directory per task, `evals/tasks/<id>/`, where `<id>` is the directory name:

| File | What it holds |
|---|---|
| `task.conf` | `key=value` lines (no quoting): `id` (the directory name), `language` (`node`, `python3` or `bash`), `source` (`pattern:<slug>` or `oss:<bug class>`), `expected_weight` (`Lite` or `Full`, the playbook-tdd weight a careful agent should pick), `fail_to_pass` and `pass_to_pass` (space-separated paths relative to `hidden/`; `fail_to_pass` may be empty), and `scope=` (space-separated repo paths a correct fix may change: an entry ending in `/` is a prefix, any other a bash `case` glob on the whole path; `tests/`, `.agents/`, `node_modules/`, `.gitignore` and `package-lock.json` are always allowed) |
| `prompt.md` | The user's request as it would arrive in a ticket or chat, in English or Vietnamese. It describes the symptom and the rule, never the hidden tests. |
| `setup.sh` | `bash setup.sh DIR` builds the task repo in `DIR`: files, then one git commit with a fixed author and date, so two runs give the same HEAD. No network. Bash 3.2. It refuses an existing non-empty `DIR` (exit 2). |
| `solution.patch` | A correct fix as a `git diff` against the setup repo (`git apply`-able). Absent, never empty, and only when `fail_to_pass` is empty (a "do not change anything" task). |
| `testdata/wrong-*.patch` | Plausible wrong fixes, each a `git diff` against the setup repo. The self-check applies each to a fresh setup repo and requires at least one hidden file to fail. |
| `hidden/tests/...` | The hidden tests, copied over the repo (same relative paths) only for grading. Every file carries the marker `PB-HIDDEN-CANARY:<id>`; nothing outside `hidden/` may carry it. |

Grading runs each hidden file alone from the repo root: `node --test F`, `python3 -m unittest F` or `bash F`. The
task passes when every `fail_to_pass` file and every `pass_to_pass` file exits 0. `fail_to_pass` files fail on the
unsolved repo (they pin the bug); `pass_to_pass` files pass before and after (they catch a fix that breaks something
else, or a change where none was needed).

Node tests import `require('../src/<module>')` with named exports; python tests import `from src.<module> import f`
(the setup repo has `src/__init__.py`). Name the repo's own visible tests so they never collide with a hidden file,
unless the hidden file is meant to replace one.

## Adding a task

1. Pick the next id (`pattern-NN-<slug>` or `oss-NN-<slug>`) and write `setup.sh`, `prompt.md` and `task.conf`.
2. Write the hidden tests under `hidden/tests/` (the tester role owns these files; role-gate classifies them as tests).
3. Build the repo, fix it by hand, and save `git diff` as `solution.patch`.
4. Run the self-check: `bash evals/check-tasks.sh --tasks <id>`. It must print `<id> SELF-CHECK OK`: setup is
   deterministic, `fail_to_pass` fails and `pass_to_pass` passes unsolved, all pass after `solution.patch`, the patch
   stays inside `scope=`, and every `testdata/wrong-*.patch` fails at least one hidden file.
5. Run `bash tests/test-outcome-corpus.sh` (with `PB_CORPUS_DENYLIST=word1,word2` set locally to check for private
   names) and `scripts/leak-check.sh scan` over the new files before committing.

## Running the tasks

`evals/run-outcome.sh (--harness claude|codex|opencode | --cmd "COMMAND") [--tasks id1,id2]` runs an agent on each
task with the flags of `evals/run-evals.sh` (`--model`, `--arm`, `--repeat`, `--max-cost`, `--timeout`) and the same
isolation (a temp `PLAYBOOK_HOME` and `TMPDIR` per run). The hidden tests never enter the workroot: they are copied over
a private copy of the workdir after the agent exits, and a transcript that shows the canary makes the run
CONTAMINATED (not passed). It writes a markdown file with pass@1 and pass^K per arm and per task, and a `pb-evals/1`
JSON file that `tools/eval-delta.sh` reads. Each run costs real money with a real harness; the header of the script
has the details.

## Process

From v0.26.0 on, every real bug met while using the playbook is added here as a synthetic task (same failure pattern,
no private code, names or data); a corpus built from real private code stays local and is never committed.
