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
- Push of feat/v0.35.0 refused (403: the GitHub App/account has no access to the repo for this org). Work continues as local
  commits; the user was asked to reconnect GitHub.
- Spec review round 1: REVISE (11 findings, .agents/handoff/01b-spec-review.md); spec revised ("## Revision 1"); round 2 started.
- Spec review round 2: REVISE (8); Revision 2; round 3: OK. Reviewer gate (base 2a68fe4): OK, 0 files.
- Slice worktree for S1: ../ap-s1 on local branch s1-heldout (from 2a68fe4); its role commits are squashed into the one held-out commit.
- Testers started (fresh contexts, session model): A (S4) in the main worktree, S1b (tasks 27-31) and S1c (32-36) in ../ap-s1.
- S1c implementer: check-tasks SELF-CHECK OK for pattern-32..36 (evidence ap-s1 .agents/handoff/evidence/20261102T021434Z-green-S1c.log).
- S1 role commits on local branch s1-heldout (to be squashed into one held-out commit): f49fce8 test(red) hidden tests (tester gate
  OK, 20 files, base 2a68fe4); baa6e68 feat(green) fixtures/prompts/solutions (implementer gate OK, 40 files, base f49fce8; testdata
  held out of this commit, D11); be81cf1 test wrong fixes reviewed + pattern-34 D9 case (tester gate OK, 22 files, base baa6e68).
  check-tasks: SELF-CHECK OK x10 (evidence 20261102T021955Z-s1-wrongfix.log in ap-s1).
- Slice F (S3, before the cut per D10): RED 58151aa + 52403a5 (SOH fix), GREEN ee0c460 (implementer gate OK base 52403a5): AGENTS.global.md
  702 -> 715 words (test-diet.sh:74 caps it below 718), SKILL.md 3681 words (exact pin test-sdlc-refs.sh:163). Focused suites green.
- Held-out commit a2499eb on feat/v0.35.0 = s1-heldout be81cf1's ten task dirs (diff empty). The guard hook printed a git-discard
  warning on `git checkout be81cf1 -- <new task dirs>`: a false positive (the paths did not exist in this worktree; nothing lost);
  captured for playbook-feedback.
- Slice D: RED d2998ee (tester gate OK), GREEN 272131d README (implementer gate OK). test-outcome-heldout 47/0, corpus 1159/0/1 skip, isolation 80/0 (characterization: runner never copied the reference). New suite has no measured Windows weight (L-0009).
- Slice E (S2): RED 03a4cd6 (tester gate OK), GREEN 8ade3c8 (implementer gate OK): AGENTS.global.md 715 -> 692 words, SKILL.md
  3681 -> 2720; 450/2000 not reachable with the verbatim pins (D13, asked; default budgets 700/2750); pins 30cba96 (tester gate OK).
- AC11 check: `git revert 30cba96 8ade3c8 03a4cd6` in a scratch worktree applied cleanly; AGENTS.global.md back to 715 words with the
  S3 sentences; test-content/diet/sdlc-refs/skill-rules/report-rules and run-checks pass.
