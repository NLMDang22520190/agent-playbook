# Test quality and the mutation spot-check

Coverage shows which lines ran. It does not show that a wrong result would be noticed.
Mutation testing does: change the code slightly (a "mutant") and check that some test fails ("killed").

## Mutation spot-check (manual, reviewer, about 10 minutes)
Do it in a throwaway worktree so the main tree stays untouched (the reviewer gate checks this):
```bash
WT="$(git rev-parse --show-toplevel)/.agents/handoff/mutants-wt"
git worktree add --detach "$WT" HEAD
cd "$WT"
# mutant 1: flip a comparison in the new logic (> to >=), save, run the slice's tests
# mutant 2: drop a branch, or return early with a default value
# mutant 3: off-by-one in a loop bound, or swap two arguments
bash ~/.agents/playbook/scripts/proof-run.sh --label mutant-1 -- <slice test command>
git checkout -- .     # reset between mutants
cd - && git worktree remove --force "$WT"
```
Expected: each mutant makes at least one test fail (a non-zero exit). A surviving mutant points to a
missing or too-weak assertion, which is a `major` finding when it is on core logic.

## Mutation tools (for larger suites; check each tool's docs for current usage)
| Ecosystem | Tool |
|---|---|
| JavaScript / TypeScript | StrykerJS |
| .NET | Stryker.NET |
| Python | mutmut, cosmic-ray |
| Java / JVM | PIT (pitest) |
| Rust | cargo-mutants |
| Go | go-mutesting, gremlins |
| PHP | Infection |
Run them on changed files only; whole-repo runs are slow.

## Review checklist for tests
- [ ] Each AC has at least one test that exercises it through behaviour.
- [ ] Assertions are specific (exact values or structures, error types and messages).
- [ ] Boundaries tested: empty, one, many, max, invalid.
- [ ] Error paths tested, not only the happy path.
- [ ] No mocks of internal modules; boundary mocks verified against real contract shapes.
- [ ] Deterministic: no sleeps, fixed clock and seed, independent of order.
- [ ] No test was weakened (`git diff <base>..HEAD -- <test paths>` reviewed).
- [ ] Test names describe behaviour.

## Flaky tests
A flaky test is a failing test. Quarantine it with an issue link, and fix the cause (time, order,
shared state, network). Never "retry until green" inside the evidence run.
