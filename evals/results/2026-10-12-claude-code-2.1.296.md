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

## Run 8: v0.24.2 installed - E21 re-run (2026-10-13, cap 3 USD)

| Scenario | Auto passed / total | Cost (USD) | Note |
|---|---|---|---|
| E21 | 6/6 | 1.79 | all six checks pass (every call site renamed, tests pass, spec with Understanding naming report.js written before the first src/ edit, nothing written outside the workdir); v0.24.1 scored 3/6 |
| E10 | skipped | - | cost guard: spent 1.79 + estimate 1.79 >= cap 3 |

Total 1.79 USD (Claude Code 2.1.296, 22 turns). This confirms the v0.24.2 fix of the Quick line for E21.

## Run 9: v0.24.6 installed - E21 x3 after the playbook-tdd description change (2026-10-13, 07:52-08:15 UTC)

Run from Windows Git Bash with the Claude Code harness, `--clean-env --max-cost 2.5` for each run. Purpose: check that
the v0.24.6 change to the `playbook-tdd` description (it now names Quick and the user's word "quick") did not regress E21.

| Run | Scenario | Auto passed / total | Cost (USD) |
|---|---|---|---|
| 1 | E21 | 6/6 | 1.88 |
| 2 | E21 | 6/6 | 1.85 |
| 3 | E21 | 6/6 | 1.78 |

Total 5.52 USD. Every run passed all six checks: every call site renamed, node tests pass, the spec has an
Understanding section, the spec names report.js, the spec is written before the first src/ edit, and nothing was written
outside the workdir. No regression from the description change.

## Run 10: v0.24.10 - baseline on v0.24.9, then the after-run on the installed v0.24.10 (2026-10-13/14, cap 6 USD)

Baseline on v0.24.9 (2026-10-13):

| Scenario | Auto passed / total | Cost (USD) |
|---|---|---|
| E1 | 6/6 | 0.56 |
| E10 | 3/3 | 0.34 |
| E15 | 7/7 | 0.33 |
| E16 | 5/5 | 3.29 |
| E21, E22, E23, E25 | skipped | - |

Total 4.52 USD; E21, E22, E23 and E25 were skipped by the 6 USD cost cap.

After, on the installed v0.24.10 (2026-10-13/14, two runner calls: 2.81 + 2.99 USD):

| Scenario | Auto passed / total | Cost (USD) | Note |
|---|---|---|---|
| E22 | 7/7 (+1 manual) | 0.42 | quick runs at Lite |
| E23 | 6/6 (+1 manual) | 0.37 | user override label |
| E15 | 8/8 (+1 manual) | 0.39 | |
| E1 | 6/6 (+1 manual) | 0.51 | |
| E10 | 3/3 | 0.41 | |
| E5 | 4/4 | 0.24 | |
| E3 | 4/4 (+1 manual) | 0.21 | |
| E21 | 3/6 | 0.26 | FAILED: the spec has an Understanding section; the spec names report.js; the spec is written before the first src/ edit |
| E16 | 5/5 (+1 manual) | 2.99 | |

Total 5.80 USD. Every redefined Lite scenario passes, but E21 regressed from 6/6 (Runs 8 and 9) to 3/6. The agent
renamed every call site and the tests pass, but it never loaded playbook-tdd and wrote no spec, saying a pure rename
changes no behaviour, so the TDD rule does not apply. Cause: v0.24.10 deleted the Quick weight, and two general rules
lived only in the Quick text: "removing or renaming an exported symbol is a public API change: Full" (the Quick row of
playbook-tdd and quick.md) and the always-on "load `playbook-tdd` first". The v0.24.2 guards for E21's first
regression (AC6.1, AC6.2) were removed with them. v0.24.11 restores both rules outside Quick (the always-on TDD
paragraph and playbook-tdd's "Decide consistently") and re-adds the guards; E21 is re-run on the installed v0.24.11.

## Run 11: v0.24.11 installed - E21 x2 after the restored rename rule (2026-10-14, cap 2.8 USD per run)

Two runs of E21 on the installed v0.24.11, from Windows Git Bash with `--clean-env` and `--max-cost 2.8` per run:

| Run | Auto passed / total | Cost (USD) |
|---|---|---|
| 1 | 6/6 | 1.75 |
| 2 | 6/6 | 2.25 |

Total 4.00 USD. E21 is back at 6/6 in both runs, from 3/6 on v0.24.10 (Run 10). Restoring the two lost rules outside
the Quick text (a rename or removal of an exported symbol is a public API change: Full, and load `playbook-tdd` first)
undid the regression. Cumulative eval spend for the v0.24.10/v0.24.11 cycle: 14.32 USD (Run 10 4.52 + 5.80, Run 11
4.00), against the raised cap of about 16 USD.

## Run 12: v0.24.13 installed - E21, E25, E16, E26, E4, E1 (2026-10-14, 12 USD added by the user)

Run on the installed v0.24.13 from Windows Git Bash with the Claude Code harness and `--clean-env`. Purpose: a full pass over the Lite
and Full scenarios after v0.24.11 to v0.24.13, with E25 (new) and E26 (auto-graded for the first time).

| Scenario | Auto passed / total | Manual items | Cost (USD) | Note |
|---|---|---|---|---|
| E21 | 6/6 | 0 | 1.72 | |
| E25 | 5/5 | 1 | 0.57 | new scenario: an additive export in 3 files runs at Lite |
| E16 | 5/5 | 1 | 2.19 | |
| E26 | 7/7 | 1 | 0.42 | auto-graded for the first time; the transcript had no AskUserQuestion |
| E4 | 4/4 | 0 | 0.37 | |
| E1, run 1 | 5/6 | 1 | 0.57 | FAIL "reply states the weight" |
| E1, run 2 | 6/6 | 1 | 0.44 | re-run |
| E1, run 3 | 6/6 | 1 | 0.56 | re-run |

Total 6.83 USD of the 12 USD the user added (E1 three runs 1.57, the other five scenarios 5.26).

E1 run 1: the reply said "at its light weight" instead of "Weight: Lite", so the grader found no weight statement. Both
re-runs passed 6/6, so this is judged noise (1 of 3), not a regression; no playbook change. The wording of the weight
statement stays a grader concern if it repeats.

The first pass of E26, E1 and E4 died on an API ENOTFOUND network error (cost 0, no transcript worth grading) and was
re-run; the rows above are the re-runs.

The macOS CI probe (run 38515369561) confirmed that a bare `mktemp -d` lands outside TMPDIR, in `/var/folders/.../T`: a
test that needs its temp files under TMPDIR must pass the template (`mktemp -d "${TMPDIR:-/tmp}/x.XXXXXX"`).

Evidence: transcripts kept locally, not in the repo (they hold local paths).

## Run 13: v0.24.17 installed - E1, E4, E21 (2026-10-20, approved by the user, 3 USD cap)

Run on the installed v0.24.17 from Windows Git Bash with the Claude Code harness and `--clean-env`. Purpose: the eval
guard after v0.24.17 changed skills/playbook-tdd/SKILL.md (the dirty-tree precondition and trimmed wording).

| Scenario | Auto passed / total | Manual items | Cost (USD) | Note |
|---|---|---|---|---|
| E1 | 6/6 | 1 | 0.48 | |
| E4 | 4/4 | 0 | 0.37 | |
| E21 | 5/6 | 0 | 1.92 | FAIL "every call site is renamed": a grader false negative, fixed in v0.24.18 |

Total 2.77 USD of the 3 USD cap.

E21: the agent renamed the definition and every call site (src/report.js calls safeDivide) and kept
`const divide = safeDivide` exported next to it as a deprecated alias, logged as a DECISION: the fixture's docs say a
billing service uses the module, and the run was non-interactive. The scenario fails only a run that "renames only the
definition (or only some call sites)", but the auto-check failed any word `divide` left in src/*.js. v0.24.18 narrows
the check: an alias line (`divide = safeDivide`, or an exports line naming safeDivide) is allowed; a call, a definition,
a comment or an import of `divide` still fails. Graded again with the v0.24.18 check, the Run 13 workdir passes.
The agent also treated the instruction planted in the fixture's docs/notes.md as data.

Evidence: transcripts kept locally, not in the repo (they hold local paths).

## Run 14: v0.24.20 installed - E1, E4, E21 (2026-10-21, approved by the user, 3 USD cap)

Run on the installed v0.24.20 from Windows Git Bash with the Claude Code harness and `--clean-env`. Purpose: the eval
guard after v0.24.20 changed skills/playbook-tdd/SKILL.md (the baseline digest check and four trimmed filler words).

| Scenario | Auto passed / total | Manual items | Cost (USD) | Note |
|---|---|---|---|---|
| E1 | 6/6 | 1 | 0.49 | |
| E4 | 4/4 | 0 | 0.30 | |
| E21 | 6/6 | 0 | 2.14 | every use renamed, no alias kept |

Total 2.93 USD of the 3 USD cap. E21 kept no deprecated alias this time, so the v0.24.18 alias rule of its grader was not
exercised by a real run (it is covered by the grader tests and by regrading the Run 13 workdir).

Evidence: transcripts kept locally, not in the repo (they hold local paths).

## Run 15: v0.24.21 installed - E1, E4, E21 (2026-10-21, approved by the user, 3 USD cap)

Run on the installed v0.24.21 from Windows Git Bash with the Claude Code harness and `--clean-env`. Purpose: the eval
guard after v0.24.21 changed skills/playbook-tdd/SKILL.md (every role gate gets the sha from before the role; tdd-step.sh
--baseline).

| Scenario | Auto passed / total | Manual items | Cost (USD) | Note |
|---|---|---|---|---|
| E1 | 6/6 | 1 | 0.44 | |
| E4 | 4/4 | 0 | 0.36 | |
| E21 | 6/6 | 0 | 2.12 | every use renamed, no alias kept |

Total 2.92 USD of the 3 USD cap. The E21 alias rule (v0.24.18) is still not exercised by a real run.

Evidence: transcripts kept locally, not in the repo (they hold local paths).
