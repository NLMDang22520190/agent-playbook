# Spec: CI fixes for PR 64 (run 39739333418)
Weight: Lite (small, reversible: one probe function in evals/run-evals.sh plus test helpers; evals/run-evals.sh:679 probe29, additive to behaviour on Linux).

## Understanding
Three CI failures: (1) macOS BSD wc -l pads the count in the E29 fixture record; (2) macOS has no GNU timeout, so probe29 returns manual and the grade8b tests wrap the grader in timeout; (3) Windows is slow, the 20 s bound failed at 25 s.
Scan: grep probe29 evals/run-evals.sh (1 definition, 1 call); grep wc -l/-c in tests/test-evals-grade8*.sh and tests/evals-grade8-fixture.sh (1 unpadded use, E29_REC mentions=); grep timeout in same files (grade8b run(), probe29).

## Impact
probe29 only (evals/run-evals.sh:679), called from grade_E29.

## AC
- AC1: E29_REC trims the mentions count (tests/test-evals-grade8.sh:34).
- AC2: probe29 does not need GNU timeout: background node, watchdog TERM at 10 s then KILL 3 s later, a kill maps to manual, exit 127 stays manual. Bash 3.2 compatible.
- AC3: with a PATH without timeout, multiply and divide still grade; a SIGTERM-trapping module is still killed within about 20 s.
- AC4: tests use a portable helper (ptimeout) instead of timeout -k 5 40.
- AC5: hangload/hangfn bound is 35 s (Windows is slow).
