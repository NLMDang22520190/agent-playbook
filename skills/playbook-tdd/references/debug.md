# Debugging a bug

## When it applies
A reported bug, a failing test or a flaky test whose cause is not known yet. Weight: the fix takes Full or Lite from the weight table in SKILL.md (Lite for a small reversible fix inside one module, Full when a Full item applies).

## The loop
Follow it in order: reproduce, minimise, hypothesise, instrument, fix, regression test. Put each step's output in the evidence.
1. Reproduce: a command that shows the bug, with its output.
2. Minimise: cut the input and the setup until every part is needed.
3. Hypothesise: name one cause and the observation that would disprove it.
4. Instrument: add logs or asserts that test that cause. Remove them before GREEN.
5. Fix: the minimised reproduction becomes the RED test, seen failing; then the fix.
6. Regression test: the RED test stays in the suite.

## The bugfix spec
State three things:
- current behaviour: what happens now, with the reproduction;
- expected behaviour: what should happen instead;
- unchanged behaviour: inputs that work today and must keep working.

The unchanged rows go into `## Regression corpus` of the spec, and the first RED pins them: they pass before and after the fix, and only the bug row fails.

## Flaky tests
Use the same loop. Reproduce by repeated runs and record the counts (for example 3 failures in 50 runs). Never retry until green inside the evidence run. The fix is shown by the same number of repeated runs with 0 failures.
