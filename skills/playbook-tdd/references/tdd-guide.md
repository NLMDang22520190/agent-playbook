# TDD guide (agent-facing)

## The cycle
1. **RED**: write one test for one observable behaviour. Run it and watch it fail for the right reason.
2. **GREEN**: write the least production code that makes it pass.
3. **REFACTOR**: improve names and structure with all tests green and unchanged. Run again.
Repeat per behaviour. If you never saw the test fail, you do not know that it tests anything.

## Vertical slices, not horizontal layers
Wrong: write 30 tests for the whole feature, then implement everything. The tests encode guesses,
and nobody sees each one fail on its own.
Right: one behaviour (1 to 5 tests), then its code, then the next behaviour. Order the slices so the
simplest happy path comes first, then variations, then the error paths.

## Right reason {#right-reason}
A valid RED fails because the behaviour is missing:
- an assertion mismatch (`expected 90, got 100`), or
- a deliberate "not implemented" error from a stub, or
- in dynamic languages, "X is not a function" for the brand-new API (acceptable for the first test only).
Not valid: syntax errors, wrong import paths, a missing test dependency, a broken test runner config,
timeouts, flakiness, a failure inside the setup or fixtures. Fix those, then look again.

## Writing good tests
- **Name = behaviour**: `rejects coupons past their expiry date`, not `test_coupon_3`.
- **Arrange / Act / Assert**, one Act per test.
- **Assert outcomes** (return values, persisted state, messages sent at a boundary), not internals.
- **Specific assertions**: `toEqual({total: 90})` beats `toBeTruthy()`.
- **Deterministic**: inject the clock, randomness and ids; no sleeps; no shared mutable state between tests.
- **Fast**: unit tests in milliseconds. Keep slow tests (DB, browser) few and focused.

## What to mock
Mock what you do not own or cannot control: the network, third-party APIs, time, randomness, email
and SMS. Do not mock your own modules just to isolate them: that tests the wiring, not the
behaviour, and breaks on every refactor.

## Test levels (the pyramid)
- Many **unit** tests for logic.
- Some **integration** tests: a real DB or filesystem, module boundaries.
- Few **end-to-end** tests for critical user journeys (login, checkout).
Choose the lowest level that can observe the behaviour.

## Bug fixes
1. Write a test that reproduces the bug through the public interface, and watch it fail.
2. Fix it. 3. Watch the test pass. 4. Keep the test: it is the regression guard.

## Legacy code without tests
Before changing it, write **characterization tests**: they record what the code does today, even
if that is odd. Then change it under that safety net. Say explicitly that these tests are
characterization tests (they pass immediately, on purpose).

## When TDD does not fit (say so explicitly)
- Throwaway spikes to learn an API: spike, learn, delete, then TDD the real thing.
- Pure visual styling: verify with screenshots or visual review instead.
- Generated code and pure configuration: test the behaviour they produce, not the files.

## Smells that mean the tests are lying
- They pass right after being written (and are not characterization tests).
- They break on every refactor that keeps the behaviour.
- They need many mocks to set up.
- They assert only that "something was called".
- Coverage is high, but a mutant survives (see `test-quality.md`).
