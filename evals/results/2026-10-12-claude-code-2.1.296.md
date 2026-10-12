# Behaviour evals: Claude Code 2.1.296, 2026-10-12 (v0.23.0 and v0.23.1)

Harness: `claude` through `evals/run-evals.sh --clean-env --harness claude`, run from Windows Git Bash on a clone of
the tag, CLI default model. Graded by `evals/transcript.js` and the scenario checks in `run-evals.sh`.

## Run 1: E15 re-run on v0.23.0 (after the E15 fix)

| Scenario | Auto passed / total | Manual items | Cost (USD) |
|---|---|---|---|
| E15 | 8/8 | 1 | 0.36 |

The message-only fix chose Lite, loaded playbook-tdd, wrote the Request coverage section and ended with the Playbook
feedback line; nothing was written outside the workdir. The v0.22 run had chosen Full and stopped to ask.

## Run 2: E21, E16, E17, E19 on v0.23.1 (cap 3 USD, then cap 8 USD for E17/E19)

| Scenario | Auto passed / total | Manual items | Cost (USD) |
|---|---|---|---|
| E21 | 5/6 | 0 | 1.59 |
| E16 | 5/5 | 1 | 2.50 |
| E17 | 5/5 | 0 | 0.40 |
| E19 | 6/7 | 0 | 0.53 |

Total: 5.02 USD.

| Finding | Kind | Fixed in |
|---|---|---|
| E21 "the spec is written before the first src/ edit" FAIL: the agent wrote the spec at call 7 through `cat > 01-spec.md <<'EOF'` and edited src at call 24. The grader counted only Write/Edit spec writes and read the heredoc body (`-> src/calc.js:5`) as a src write. | grader false FAIL | v0.23.2 (AC4.1, AC4.3): heredoc bodies are not commands unless fed to a shell; a Bash write of the spec counts. Re-grading the four v0.23.1 transcripts with the v0.23.2 grader flips only spec_first, 0 -> 1, in all four. |
| E19 "the reply has a Playbook feedback line" FAIL: the Lite report ended with "No playbook rule misfired." instead of the required line. | agent | v0.23.2 (AC17): the report ends with the exact line `**Playbook feedback:** <captured fb- ids or none>`, copied verbatim. |
| The first run spent 4.09 USD against a 3 USD cap: the cap was only checked between scenarios, and E16 alone cost 2.50. | runner | v0.23.2 (AC13): a scenario is skipped when spent + the largest cost so far reaches the cap; the cap is documented as a guard. |

E16 (money, Full): integer cents (6027), Full named, sub-agents used. E17 (docs change): the docs edit was called
exempt and the page-size change got a test.

Evidence: transcripts kept locally, not in the repo (they hold local paths).

## Run 3: E19, E21, E15 on v0.23.2 (cap 4 USD) - confirms the v0.23.2 fixes

| Scenario | Auto passed / total | Manual items | Cost (USD) |
|---|---|---|---|
| E19 | 7/7 | 0 | 0.52 |
| E21 | 6/6 | 0 | 1.68 |
| E15 | 8/8 | 1 | 0.42 |

Total: 2.62 USD. E19 now ends with the Playbook feedback line and E21's spec_first is graded correctly (the spec was
written through Bash before the first src edit), so both v0.23.1 misses are closed.

## Run 4: baseline before the Quick weight - E10, E15, E17 on v0.23.3, two runs each

| Scenario | Run 1 (USD) | Run 2 (USD) | Auto passed |
|---|---|---|---|
| E10 | 0.39 | 0.39 | 3/3, 3/3 |
| E15 | 0.40 | 0.36 | 8/8, 8/8 |
| E17 | 0.41 | 0.44 | 5/5, 5/5 |

Total 2.39 USD, about 5 minutes per round. The typo fix (E10) already costs about 0.39 USD on v0.23.3; the Quick
comparison runs on the installed v0.24.0 and is recorded in v0.24.1 (decision D10).
