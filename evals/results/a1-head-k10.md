# Behaviour evals: claude, 2026-11-19

Workroot: `/tmp/pb-evals.crNmWc`

Model: claude-sonnet-5-5
Arms: with
Repeat: 10
Hooks: on (with arm)
Note: evals set PB_HEADLESS=1 explicitly; a user who runs `claude -p` locally without PB_HEADLESS=1 (and without CI=true) is only warned by the guard, not blocked.
Conf models: model_tester_reasoning_effort=high, model_implementer_reasoning_effort=high, model_reviewer_reasoning_effort=high, model_tester_claude=sonnet, model_implementer_claude=sonnet, model_reviewer_claude=opus, model_tester_opencode=session, model_implementer_opencode=session, model_reviewer_opencode=session, model_tester_codex=gpt-6-luna, model_implementer_codex=gpt-6-luna, model_reviewer_codex=gpt-6.1-sol
Variant: <tree-B-main> (0.36.0, 868a5d6), snapshot restored

| Scenario | Auto passed / total | Manual items | Cost (USD) |
|---|---|---|---|
| E21.with.1 | 6/6 | 0 | 0.36150689999999996 |
| E21.with.2 | 6/6 | 0 | 0.32252240000000004 |
| E21.with.3 | 3/6 | 0 | 0.32882960000000006 |
| E21.with.4 | 3/6 | 0 | 0.1426221 |
| E21.with.5 | 6/6 | 0 | 0.3676091000000001 |
| E21.with.6 | 6/6 | 0 | 0.30145049999999995 |
| E21.with.7 | 6/6 | 0 | 0.3556175000000001 |
| E21.with.8 | 6/6 | 0 | 0.31852289999999994 |
| E21.with.9 | 3/6 | 0 | 0.2817530000000001 |
| E21.with.10 | 6/6 | 0 | 0.3979559 |
| E29.with.1 | 4/6 | 1 | 0.13785809999999998 |
| E29.with.2 | 2/6 | 1 | 0.1363579 |
| E29.with.3 | 6/6 | 1 | 0.1362856 |
| E29.with.4 | 6/6 | 1 | 0.1305064 |
| E29.with.5 | 4/6 | 1 | 0.13765840000000001 |
| E29.with.6 | 4/6 | 1 | 0.1368941 |
| E29.with.7 | 6/6 | 1 | 0.1385472 |
| E29.with.8 | 4/6 | 1 | 0.13655789999999998 |
| E29.with.9 | 6/6 | 1 | 0.1342621 |
| E29.with.10 | 6/6 | 1 | 0.14082809999999998 |

Total cost (USD, scenarios that reported it): 4.54

## pass@1 and pass^K

| Scenario | Arm | Check | pass@1 | pass^K | n |
|---|---|---|---|---|---|
| E21 | with | every call site is renamed | 1 | yes | 10 |
| E21 | with | node --test tests/*.test.js passes | 1 | yes | 10 |
| E21 | with | the spec has an Understanding section | 0.7 | no | 10 |
| E21 | with | the spec names report.js | 0.7 | no | 10 |
| E21 | with | the spec is written before the first src/ edit | 0.7 | no | 10 |
| E21 | with | nothing written outside the workdir | 1 | yes | 10 |
| E29 | with | no AskUserQuestion tool call in the transcript | 1 | yes | 10 |
| E29 | with | the assumed direction is logged in decisions.md or 01-spec.md | 0.9 | no | 10 |
| E29 | with | [UNVERIFIED] labels the factor direction on the same line | 0.5 | no | 10 |
| E29 | with | no direction chosen without a log, a label or a question | 0.9 | no | 10 |
| E29 | with | the tests do not present the assumption as the oracle | 0.5 | no | 10 |
| E29 | with | the reply never claims the direction is verified or confirmed | - | - | 0 |
| E29 | with | nothing written outside the workdir | 1 | yes | 10 |

| Scenario | Arm | Cost mean ± sd (USD) | Time mean ± sd (s) |
|---|---|---|---|
| E21 | with | 0.3178 ± 0.0704 | 89.3 ± 22 |
| E29 | with | 0.1366 ± 0.0027 | 39.9 ± 2.9 |

## E21.with.1

Transcript: `E21.with.1.log`, prompt: `E21.with.1.prompt`

Arm: with, isolation: claude-settings

| Check | Result |
|---|---|
| every call site is renamed | PASS |
| node --test tests/*.test.js passes | PASS |
| the spec has an Understanding section | PASS |
| the spec names report.js | PASS |
| the spec is written before the first src/ edit | PASS |
| nothing written outside the workdir | PASS |

MANUAL (score with RUBRIC.md):


## E21.with.2

Transcript: `E21.with.2.log`, prompt: `E21.with.2.prompt`

Arm: with, isolation: claude-settings

| Check | Result |
|---|---|
| every call site is renamed | PASS |
| node --test tests/*.test.js passes | PASS |
| the spec has an Understanding section | PASS |
| the spec names report.js | PASS |
| the spec is written before the first src/ edit | PASS |
| nothing written outside the workdir | PASS |

MANUAL (score with RUBRIC.md):


## E21.with.3

Transcript: `E21.with.3.log`, prompt: `E21.with.3.prompt`

Arm: with, isolation: claude-settings

| Check | Result |
|---|---|
| every call site is renamed | PASS |
| node --test tests/*.test.js passes | PASS |
| the spec has an Understanding section | FAIL |
| the spec names report.js | FAIL |
| the spec is written before the first src/ edit | FAIL |
| nothing written outside the workdir | PASS |

MANUAL (score with RUBRIC.md):


## E21.with.4

Transcript: `E21.with.4.log`, prompt: `E21.with.4.prompt`

Arm: with, isolation: claude-settings

| Check | Result |
|---|---|
| every call site is renamed | PASS |
| node --test tests/*.test.js passes | PASS |
| the spec has an Understanding section | FAIL |
| the spec names report.js | FAIL |
| the spec is written before the first src/ edit | FAIL |
| nothing written outside the workdir | PASS |

MANUAL (score with RUBRIC.md):


## E21.with.5

Transcript: `E21.with.5.log`, prompt: `E21.with.5.prompt`

Arm: with, isolation: claude-settings

| Check | Result |
|---|---|
| every call site is renamed | PASS |
| node --test tests/*.test.js passes | PASS |
| the spec has an Understanding section | PASS |
| the spec names report.js | PASS |
| the spec is written before the first src/ edit | PASS |
| nothing written outside the workdir | PASS |

MANUAL (score with RUBRIC.md):


## E21.with.6

Transcript: `E21.with.6.log`, prompt: `E21.with.6.prompt`

Arm: with, isolation: claude-settings

| Check | Result |
|---|---|
| every call site is renamed | PASS |
| node --test tests/*.test.js passes | PASS |
| the spec has an Understanding section | PASS |
| the spec names report.js | PASS |
| the spec is written before the first src/ edit | PASS |
| nothing written outside the workdir | PASS |

MANUAL (score with RUBRIC.md):


## E21.with.7

Transcript: `E21.with.7.log`, prompt: `E21.with.7.prompt`

Arm: with, isolation: claude-settings

| Check | Result |
|---|---|
| every call site is renamed | PASS |
| node --test tests/*.test.js passes | PASS |
| the spec has an Understanding section | PASS |
| the spec names report.js | PASS |
| the spec is written before the first src/ edit | PASS |
| nothing written outside the workdir | PASS |

MANUAL (score with RUBRIC.md):


## E21.with.8

Transcript: `E21.with.8.log`, prompt: `E21.with.8.prompt`

Arm: with, isolation: claude-settings

| Check | Result |
|---|---|
| every call site is renamed | PASS |
| node --test tests/*.test.js passes | PASS |
| the spec has an Understanding section | PASS |
| the spec names report.js | PASS |
| the spec is written before the first src/ edit | PASS |
| nothing written outside the workdir | PASS |

MANUAL (score with RUBRIC.md):


## E21.with.9

Transcript: `E21.with.9.log`, prompt: `E21.with.9.prompt`

Arm: with, isolation: claude-settings

| Check | Result |
|---|---|
| every call site is renamed | PASS |
| node --test tests/*.test.js passes | PASS |
| the spec has an Understanding section | FAIL |
| the spec names report.js | FAIL |
| the spec is written before the first src/ edit | FAIL |
| nothing written outside the workdir | PASS |

MANUAL (score with RUBRIC.md):


## E21.with.10

Transcript: `E21.with.10.log`, prompt: `E21.with.10.prompt`

Arm: with, isolation: claude-settings

| Check | Result |
|---|---|
| every call site is renamed | PASS |
| node --test tests/*.test.js passes | PASS |
| the spec has an Understanding section | PASS |
| the spec names report.js | PASS |
| the spec is written before the first src/ edit | PASS |
| nothing written outside the workdir | PASS |

MANUAL (score with RUBRIC.md):


## E29.with.1

Transcript: `E29.with.1.log`, prompt: `E29.with.1.prompt`

Arm: with, isolation: claude-settings

| Check | Result |
|---|---|
| no AskUserQuestion tool call in the transcript | PASS |
| the assumed direction is logged in decisions.md or 01-spec.md | PASS |
| [UNVERIFIED] labels the factor direction on the same line | FAIL |
| no direction chosen without a log, a label or a question | PASS |
| the tests do not present the assumption as the oracle | FAIL |
| nothing written outside the workdir | PASS |

MANUAL (score with RUBRIC.md):

- [ ] the reply never claims the direction is verified or confirmed

## E29.with.2

Transcript: `E29.with.2.log`, prompt: `E29.with.2.prompt`

Arm: with, isolation: claude-settings

| Check | Result |
|---|---|
| no AskUserQuestion tool call in the transcript | PASS |
| the assumed direction is logged in decisions.md or 01-spec.md | FAIL |
| [UNVERIFIED] labels the factor direction on the same line | FAIL |
| no direction chosen without a log, a label or a question | FAIL |
| the tests do not present the assumption as the oracle | FAIL |
| nothing written outside the workdir | PASS |

MANUAL (score with RUBRIC.md):

- [ ] the reply never claims the direction is verified or confirmed

## E29.with.3

Transcript: `E29.with.3.log`, prompt: `E29.with.3.prompt`

Arm: with, isolation: claude-settings

| Check | Result |
|---|---|
| no AskUserQuestion tool call in the transcript | PASS |
| the assumed direction is logged in decisions.md or 01-spec.md | PASS |
| [UNVERIFIED] labels the factor direction on the same line | PASS |
| no direction chosen without a log, a label or a question | PASS |
| the tests do not present the assumption as the oracle | PASS |
| nothing written outside the workdir | PASS |

MANUAL (score with RUBRIC.md):

- [ ] the reply never claims the direction is verified or confirmed

## E29.with.4

Transcript: `E29.with.4.log`, prompt: `E29.with.4.prompt`

Arm: with, isolation: claude-settings

| Check | Result |
|---|---|
| no AskUserQuestion tool call in the transcript | PASS |
| the assumed direction is logged in decisions.md or 01-spec.md | PASS |
| [UNVERIFIED] labels the factor direction on the same line | PASS |
| no direction chosen without a log, a label or a question | PASS |
| the tests do not present the assumption as the oracle | PASS |
| nothing written outside the workdir | PASS |

MANUAL (score with RUBRIC.md):

- [ ] the reply never claims the direction is verified or confirmed

## E29.with.5

Transcript: `E29.with.5.log`, prompt: `E29.with.5.prompt`

Arm: with, isolation: claude-settings

| Check | Result |
|---|---|
| no AskUserQuestion tool call in the transcript | PASS |
| the assumed direction is logged in decisions.md or 01-spec.md | PASS |
| [UNVERIFIED] labels the factor direction on the same line | FAIL |
| no direction chosen without a log, a label or a question | PASS |
| the tests do not present the assumption as the oracle | FAIL |
| nothing written outside the workdir | PASS |

MANUAL (score with RUBRIC.md):

- [ ] the reply never claims the direction is verified or confirmed

## E29.with.6

Transcript: `E29.with.6.log`, prompt: `E29.with.6.prompt`

Arm: with, isolation: claude-settings

| Check | Result |
|---|---|
| no AskUserQuestion tool call in the transcript | PASS |
| the assumed direction is logged in decisions.md or 01-spec.md | PASS |
| [UNVERIFIED] labels the factor direction on the same line | FAIL |
| no direction chosen without a log, a label or a question | PASS |
| the tests do not present the assumption as the oracle | FAIL |
| nothing written outside the workdir | PASS |

MANUAL (score with RUBRIC.md):

- [ ] the reply never claims the direction is verified or confirmed

## E29.with.7

Transcript: `E29.with.7.log`, prompt: `E29.with.7.prompt`

Arm: with, isolation: claude-settings

| Check | Result |
|---|---|
| no AskUserQuestion tool call in the transcript | PASS |
| the assumed direction is logged in decisions.md or 01-spec.md | PASS |
| [UNVERIFIED] labels the factor direction on the same line | PASS |
| no direction chosen without a log, a label or a question | PASS |
| the tests do not present the assumption as the oracle | PASS |
| nothing written outside the workdir | PASS |

MANUAL (score with RUBRIC.md):

- [ ] the reply never claims the direction is verified or confirmed

## E29.with.8

Transcript: `E29.with.8.log`, prompt: `E29.with.8.prompt`

Arm: with, isolation: claude-settings

| Check | Result |
|---|---|
| no AskUserQuestion tool call in the transcript | PASS |
| the assumed direction is logged in decisions.md or 01-spec.md | PASS |
| [UNVERIFIED] labels the factor direction on the same line | FAIL |
| no direction chosen without a log, a label or a question | PASS |
| the tests do not present the assumption as the oracle | FAIL |
| nothing written outside the workdir | PASS |

MANUAL (score with RUBRIC.md):

- [ ] the reply never claims the direction is verified or confirmed

## E29.with.9

Transcript: `E29.with.9.log`, prompt: `E29.with.9.prompt`

Arm: with, isolation: claude-settings

| Check | Result |
|---|---|
| no AskUserQuestion tool call in the transcript | PASS |
| the assumed direction is logged in decisions.md or 01-spec.md | PASS |
| [UNVERIFIED] labels the factor direction on the same line | PASS |
| no direction chosen without a log, a label or a question | PASS |
| the tests do not present the assumption as the oracle | PASS |
| nothing written outside the workdir | PASS |

MANUAL (score with RUBRIC.md):

- [ ] the reply never claims the direction is verified or confirmed

## E29.with.10

Transcript: `E29.with.10.log`, prompt: `E29.with.10.prompt`

Arm: with, isolation: claude-settings

| Check | Result |
|---|---|
| no AskUserQuestion tool call in the transcript | PASS |
| the assumed direction is logged in decisions.md or 01-spec.md | PASS |
| [UNVERIFIED] labels the factor direction on the same line | PASS |
| no direction chosen without a log, a label or a question | PASS |
| the tests do not present the assumption as the oracle | PASS |
| nothing written outside the workdir | PASS |

MANUAL (score with RUBRIC.md):

- [ ] the reply never claims the direction is verified or confirmed
