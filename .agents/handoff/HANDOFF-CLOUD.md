# HANDOFF (cloud session, v0.35.0)

## Log
- 2026-11-02 setup: branch feat/v0.35.0 from origin/main b9f407a; `bash install.sh install --yes` ok (claude harness, 5 hooks);
  `bash evals/run-checks.sh` -> "run-checks: all ok"; baseline `bash tests/run-all.sh` started in background (as root).
- ~/.agents/playbook.conf missing; writing it via conf.sh was refused by the session's permission classifier, so roles run with
  the session model (role-model resolves to session) and autonomy is taken from the user's message (push + PR asked for).
- Spec written: .agents/handoff/01-spec.md; spec reviewer started (fresh context, raw request verbatim).
- Baseline run-all at b9f407a (as root, this container): EXIT 1. Failing suites (environment, not touched by v0.35.0):
  test-guard-restore.sh 88, test-guard-restore-r9.sh 62, test-guard-restore-symlink.sh 34, test-guard-restore-r12.sh 2 (all
  "[today FAIL]/[guard-rail] ... restore" cases: the guard's restore allow path in this container), test-release-tool.sh 4 (the
  container's global git config sets user.signingkey, gpg cannot sign the fixture tag), test-run-all.sh 1 ("the killed run's
  child (sleep 60) is gone", process timing). Log: .agents/handoff/evidence/baseline-run-all.log (git-ignored).
