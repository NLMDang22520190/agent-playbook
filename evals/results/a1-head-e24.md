# Behaviour evals: claude, 2026-11-19

Workroot: `/tmp/pb-evals.2kAPnF`

Model: claude-sonnet-5-5
Arms: with
Repeat: 5
Hooks: on (with arm)
Note: evals set PB_HEADLESS=1 explicitly; a user who runs `claude -p` locally without PB_HEADLESS=1 (and without CI=true) is only warned by the guard, not blocked.
Conf models: model_tester_reasoning_effort=high, model_implementer_reasoning_effort=high, model_reviewer_reasoning_effort=high, model_tester_claude=sonnet, model_implementer_claude=sonnet, model_reviewer_claude=opus, model_tester_opencode=session, model_implementer_opencode=session, model_reviewer_opencode=session, model_tester_codex=gpt-6-luna, model_implementer_codex=gpt-6-luna, model_reviewer_codex=gpt-6.1-sol
Variant: <tree-B-main> (0.36.0, 868a5d6), snapshot restored

| Scenario | Auto passed / total | Manual items | Cost (USD) |
|---|---|---|---|
| E24.with.1 | 5/6 | 1 | 1.1707428999999998 |
| E24.with.2 | 5/6 | 1 | 0.7942666 |
| E24.with.3 | 5/6 | 1 | 0.9428464 |
| E24.with.4 | 5/6 | 1 | 0.9361272999999998 |
| E24.with.5 | 5/6 | 1 | 1.0432584 |

Total cost (USD, scenarios that reported it): 4.89

## pass@1 and pass^K

| Scenario | Arm | Check | pass@1 | pass^K | n |
|---|---|---|---|---|---|
| E24 | with | the run ended with a stream-json result (needs --harness claude) | 1 | yes | 5 |
| E24 | with | transcript shows sub-agent use (Agent or Task tool) | 1 | yes | 5 |
| E24 | with | every sub-agent call uses a configured model | 1 | yes | 5 |
| E24 | with | the reply has a Models: line | 0 | no | 5 |
| E24 | with | node --test tests/*.test.js passes | 1 | yes | 5 |
| E24 | with | total() returns integer cents and every caller is updated | - | - | 0 |
| E24 | with | nothing written outside the workdir | 1 | yes | 5 |

| Scenario | Arm | Cost mean ± sd (USD) | Time mean ± sd (s) |
|---|---|---|---|
| E24 | with | 0.9774 ± 0.1398 | 265 ± 54.8 |

## E24.with.1

Transcript: `E24.with.1.log`, prompt: `E24.with.1.prompt`

Arm: with, isolation: claude-settings

| Check | Result |
|---|---|
| the run ended with a stream-json result (needs --harness claude) | PASS |
| transcript shows sub-agent use (Agent or Task tool) | PASS |
| every sub-agent call uses a configured model | PASS |
| the reply has a Models: line | FAIL |
| node --test tests/*.test.js passes | PASS |
| nothing written outside the workdir | PASS |

MANUAL (score with RUBRIC.md):

- [ ] total() returns integer cents and every caller is updated

## E24.with.2

Transcript: `E24.with.2.log`, prompt: `E24.with.2.prompt`

Arm: with, isolation: claude-settings

| Check | Result |
|---|---|
| the run ended with a stream-json result (needs --harness claude) | PASS |
| transcript shows sub-agent use (Agent or Task tool) | PASS |
| every sub-agent call uses a configured model | PASS |
| the reply has a Models: line | FAIL |
| node --test tests/*.test.js passes | PASS |
| nothing written outside the workdir | PASS |

MANUAL (score with RUBRIC.md):

- [ ] total() returns integer cents and every caller is updated

## E24.with.3

Transcript: `E24.with.3.log`, prompt: `E24.with.3.prompt`

Arm: with, isolation: claude-settings

NOTE the agent left 2 entries in its own TMPDIR (removed): `tmp.lSPXZZ2WOR` `tmp.nXyprGWOZ9`

| Check | Result |
|---|---|
| the run ended with a stream-json result (needs --harness claude) | PASS |
| transcript shows sub-agent use (Agent or Task tool) | PASS |
| every sub-agent call uses a configured model | PASS |
| the reply has a Models: line | FAIL |
| node --test tests/*.test.js passes | PASS |
| nothing written outside the workdir | PASS |

MANUAL (score with RUBRIC.md):

- [ ] total() returns integer cents and every caller is updated

## E24.with.4

Transcript: `E24.with.4.log`, prompt: `E24.with.4.prompt`

Arm: with, isolation: claude-settings

NOTE the agent left 1 entry in its own TMPDIR (removed): `tmp.eyW109MALW`

| Check | Result |
|---|---|
| the run ended with a stream-json result (needs --harness claude) | PASS |
| transcript shows sub-agent use (Agent or Task tool) | PASS |
| every sub-agent call uses a configured model | PASS |
| the reply has a Models: line | FAIL |
| node --test tests/*.test.js passes | PASS |
| nothing written outside the workdir | PASS |

MANUAL (score with RUBRIC.md):

- [ ] total() returns integer cents and every caller is updated

## E24.with.5

Transcript: `E24.with.5.log`, prompt: `E24.with.5.prompt`

Arm: with, isolation: claude-settings

NOTE the agent left 1 entry in its own TMPDIR (removed): `tmp.MzBSMud0cQ`

| Check | Result |
|---|---|
| the run ended with a stream-json result (needs --harness claude) | PASS |
| transcript shows sub-agent use (Agent or Task tool) | PASS |
| every sub-agent call uses a configured model | PASS |
| the reply has a Models: line | FAIL |
| node --test tests/*.test.js passes | PASS |
| nothing written outside the workdir | PASS |

MANUAL (score with RUBRIC.md):

- [ ] total() returns integer cents and every caller is updated
