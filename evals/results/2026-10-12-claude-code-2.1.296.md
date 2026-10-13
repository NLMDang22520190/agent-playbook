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

## Run 5: v0.24.0 installed - E10, E22, E23, E25, E24 (cap 6 USD)

| Scenario | Auto passed / total | Cost (USD) | Note |
|---|---|---|---|
| E10 | 3/3 | 0.35 | typo, no "quick" (baseline on v0.23.3: 0.39 / 0.39) |
| E22 | 5/5 (+1 manual) | 0.32 | `Weight: Quick (user-requested)` |
| E23 | 5/5 | 0.32 | kept Quick, named the billing risk: "would normally need Full" |
| E25 | 3/5 | 3.58 | chose Full with a sound reason (billing code, existing behaviour NaN -> 0): scenario flaw, redesigned in v0.24.2 |
| E24 | skipped | - | cost guard: spent 4.58 + estimate 3.58 >= cap 6 |

Total 4.58 USD. Quick works as specified; on this fixture it saves about 10-20 % per tiny fix, because a Lite typo
fix already costs about 0.39 USD (the 1.1 USD figure in the Quick plan came from older, heavier Lite runs).

## Run 6: v0.24.1 installed - eval guard for the shorter always-on block (cap 4 USD)

| Scenario | Auto passed / total | Cost (USD) |
|---|---|---|
| E1 | 6/6 (+1 manual) | 0.40 |
| E3 | 4/4 (+1 manual) | 0.22 |
| E5 | 4/4 | 0.22 |
| E8 | 4/4 (+1 manual) | 0.15 |
| E10 | 3/3 | 0.36 |
| E21 | 3/6 | 0.24 |

Total 1.57 USD. The shorter block keeps E1, E3, E5, E8 and E10 passing. E21 regressed (it passed 6/6 on v0.23.2): the
agent chose "the playbook's Quick test level" from the always-on line for a two-file rename that removed a public
export, without loading playbook-tdd, so no spec was written. v0.24.2 fixes the Quick line and quick.md; E21 is re-run
on the installed v0.24.2.

## Run 7: v0.24.2 installed, isolated runner (v0.24.3 branch) - E24, then E10 and E25

| Scenario | Auto passed / total | Cost (USD) | Note |
|---|---|---|---|
| E24 | 5/6 | 3.55 | every sub-agent used the configured model (sonnet/opus); no `Models:` line in the reply |
| E25 | 4/5 | 0.49 | loaded playbook-tdd, ran the size check 4 times, chose Lite for an additive 3-file change; the grader missed "at **Lite** weight" (grader fix in v0.24.4) |
| E10 | 3/3 | 0.33 | typo fix (v0.23.3 baseline 0.39) |

Total 4.37 USD. Isolation check on the real machine: the real feedback queue was byte-identical before and after
both runs, no temp home was left in TMPDIR, and E24's feedback item and cost log landed in its evidence folder.
