# TDD for beginners (and how the playbook uses it)

## 1. TDD in one sentence
Write **one small test for one behaviour** first, **watch it fail**, write **the least code** that makes it pass,
then **clean up the code** while the test stays green. Repeat.

Why watch it fail? A test that has never failed may test nothing at all (an assertion in the wrong place,
everything mocked). Seeing it fail for the right reason is the evidence that it measures the right thing.

## 2. The loop, with a concrete example
Request: "The cart applies a 10% coupon".

**RED**: a test for the first behaviour.
```js
test('applies a 10% coupon to the cart total', () => {
  const cart = { items: [{ price: 100, qty: 1 }] };
  expect(totalWithCoupon(cart, { type: 'percent', value: 10 })).toBe(90);
});
```
Run it and watch it fail: `totalWithCoupon is not a function`. This is failing for the right reason: the function does not exist yet.
If it fails because of a wrong import path, it is failing for the **wrong** reason. Fix that and run it again.

**GREEN**: the least code.
```js
function totalWithCoupon(cart, coupon) {
  const t = cart.items.reduce((s, i) => s + i.price * i.qty, 0);
  return t - t * coupon.value / 100;
}
```
**REFACTOR**: if it duplicates the existing `total()`, reuse that, run again, still green.

**The next behaviour** (the next slice): an expired coupon is rejected, the discount never exceeds the total, money is rounded...
Each behaviour is its own RED, GREEN, REFACTOR loop.

## 3. Five mistakes beginners make
1. **Writing all the tests first, then the code** (horizontal slices). The tests encode guesses, and you never see each one fail.
2. **Testing how instead of what**: asserting "function X was called twice" instead of "the total is 90". Any refactor breaks it.
3. **Mocking everything**: the tests stay green forever and prove nothing. Mock only external boundaries (network, time, third parties).
4. **Loose assertions**: `toBeTruthy()` instead of the exact value.
5. **Editing a test to make it pass**: that deletes the evidence; it does not fix the bug.

## 4. Why three separate agents
An agent that writes both the code and the tests writes tests that **match its own code**, even when the code
is wrong. Separating the roles means:
- The **tester** sees only the spec, so the tests reflect the requirement, not the solution.
- The **implementer** may not edit tests, so the only way to green is the right behaviour.
- The **reviewer** only reads, re-runs the tests and tries "mutating" the code (mutation) to see whether the tests catch it.

The playbook enforces this with `role-gate.sh`: after each role, the gate compares the diff with the checkpoint commit. If the implementer
touches a test file, the gate turns red at once; nobody has to take anyone's word for it.

## 5. What a full round looks like
```
01-spec.md (AC1..AC3, slices S1..S3)
S1: tester -> gate tester ✓ -> RED evidence -> commit test(red)
    implementer -> gate implementer --base RED ✓ -> GREEN evidence -> commit feat(green)
S2: ...
reviewer (read-only, a different model) -> gate reviewer ✓ -> 05-review.md (APPROVE/CHANGES)
close-out: re-run test/lint/typecheck -> 06-final-report.md (AC -> test -> evidence table)
```

## 6. Check whether your tests are "real" (mutation spot-check)
Break the code on purpose: change `>` to `>=`, remove an `if` branch, shift a loop bound by one.
Run the tests. **If they stay green, the tests are weak.** Automated tools: StrykerJS (JS/TS),
mutmut (Python), PIT (Java), cargo-mutants (Rust).

## 7. When not to do TDD (and say so)
- A spike to try an API: go fast, learn, then **delete it** and TDD the real thing.
- Purely visual UI tweaks: check them with screenshots or by looking at the screen.
- Configuration files or generated code: test the behaviour they produce.

## 8. A suggested practice plan
1. Week 1: small katas (FizzBuzz, String Calculator, Bowling) by hand, just to get used to the RED, GREEN, REFACTOR rhythm.
2. Week 2: fix real bugs with the process: a test that reproduces the bug, then the fix.
3. Week 3: use `playbook-tdd` for a small feature. Read `01-spec.md` and the AC table in the final report yourself.
   This is where a human controls quality most effectively.
4. From week 4: add the mutation spot-check to reviews and run `evals/scenarios.md` regularly.

Documentation for agents (in English, shorter): `skills/playbook-tdd/references/tdd-guide.md`.
