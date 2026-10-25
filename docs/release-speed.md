# Release speed rules

Maintainer rules for releases of this repository (moved out of the `playbook-tdd` skill). The review-round cap is in
`skills/playbook-tdd/references/full.md` (Phase 3) and the introduced/pre-existing rule in `skills/playbook-tdd/roles/reviewer.md`.

These rules keep a release from dragging. They apply to the work of one release, not to a single small fix.

## Weight per item (AC3.3)
The weight is chosen per item or slice, not per release, so one release may hold Full and Lite items. Full for security and core logic; Lite for docs, wording, nits and test refactors.

**Why:** one weight for a whole release either overpays for the small items or under-checks the risky ones.

## Slow platforms (AC3.4)
A slow platform run (for example the Windows Git Bash suites) runs once before the PR, not every fix round. CI is the cross-platform gate.

**Why:** a slow suite repeated on each fix round adds minutes to every round and finds nothing CI would not.

## Release size (AC3.5)
Prefer releases of 3-5 items: small enough to review, large enough to be worth shipping.
