# Outcome evals: claude, 2026-11-19

Workroot: `/tmp/pb-outcome.Oyx4Rk`
Tasks: `<tree-B-a90fe64a>/evals/tasks`

Model: claude-sonnet-5-5
Arms: with
Repeat: 10
Conf models: model_tester_reasoning_effort=high, model_implementer_reasoning_effort=high, model_reviewer_reasoning_effort=high, model_tester_claude=sonnet, model_implementer_claude=sonnet, model_reviewer_claude=opus, model_tester_opencode=session, model_implementer_opencode=session, model_reviewer_opencode=session, model_tester_codex=gpt-6-luna, model_implementer_codex=gpt-6-luna, model_reviewer_codex=gpt-6.1-sol
Variant: <tree-B-a90fe64a> (0.37.0, a90fe64), snapshot restored

## pass@1 and pass^10 per arm (check `hidden tests pass`)

- with: pass@1 0.10 (1/10 runs), pass^10 0.00 (0 of 1 complete tasks)

| Task | Arm | pass@1 | pass^K | n | Cost mean ± sd | Time mean ± sd |
|---|---|---|---|---|---|---|
| pattern-24-merge-duplicate-customers | with | 0.10 | no | 10 | 0.1536 ± 0.0097 | 46.8 ± 6.3 |

## Scope and visible tests per arm

- with: extra_files_changed mean 0.00 (runs > 0: 0 of 10), tests_weakened mean 0.00 (runs > 0: 0 of 10)

## Runs

| Run | Status | Hidden tests | Failed checks | Extra files | Tests weakened | Cost (USD) | Seconds |
|---|---|---|---|---|---|---|---|
| pattern-24-merge-duplicate-customers.with.1 | graded | FAIL | FAIL_TO_PASS tests/test_merge_decision_logged.py; hidden tests pass | 0 | 0 | 0.1537016 | 41 |
| pattern-24-merge-duplicate-customers.with.2 | graded | FAIL | FAIL_TO_PASS tests/test_merge_decision_logged.py; hidden tests pass | 0 | 0 | 0.1402769 | 41 |
| pattern-24-merge-duplicate-customers.with.3 | graded | FAIL | FAIL_TO_PASS tests/test_merge_decision_logged.py; hidden tests pass | 0 | 0 | 0.15447619999999998 | 48 |
| pattern-24-merge-duplicate-customers.with.4 | graded | FAIL | FAIL_TO_PASS tests/test_merge_decision_logged.py; hidden tests pass | 0 | 0 | 0.1444698 | 41 |
| pattern-24-merge-duplicate-customers.with.5 | graded | FAIL | FAIL_TO_PASS tests/test_merge_decision_logged.py; hidden tests pass | 0 | 0 | 0.1679649 | 58 |
| pattern-24-merge-duplicate-customers.with.6 | graded | PASS | - | 0 | 0 | 0.16435390000000002 | 54 |
| pattern-24-merge-duplicate-customers.with.7 | graded | FAIL | FAIL_TO_PASS tests/test_merge_decision_logged.py; hidden tests pass | 0 | 0 | 0.15057299999999998 | 49 |
| pattern-24-merge-duplicate-customers.with.8 | graded | FAIL | FAIL_TO_PASS tests/test_merge_decision_logged.py; hidden tests pass | 0 | 0 | 0.14786870000000002 | 43 |
| pattern-24-merge-duplicate-customers.with.9 | graded | FAIL | FAIL_TO_PASS tests/test_merge_decision_logged.py; hidden tests pass | 0 | 0 | 0.16626030000000003 | 52 |
| pattern-24-merge-duplicate-customers.with.10 | graded | FAIL | FAIL_TO_PASS tests/test_merge_decision_logged.py; hidden tests pass | 0 | 0 | 0.1456855 | 41 |

Total cost (USD, runs that reported it): 1.54
