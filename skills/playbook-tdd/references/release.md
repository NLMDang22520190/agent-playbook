# Release speed rules

These rules keep a release from dragging. They apply to the work of one release, not to a single small fix.

## Review rounds (AC3.1)
Phase 3 code-review rounds are capped at 2 per lane or slice. From round 3 on, fix only a MAJOR introduced by this change, and give it one more round. Every other finding goes to the queue, written under "Found, not fixed" in the final report. Spec-review and dispute limits are unchanged.

**Why:** a third round mostly finds smaller things, and each round costs a full review. The queue keeps them without holding the release.

## Introduced or pre-existing (AC3.2)
The reviewer marks each finding `introduced` (this change caused it) or `pre-existing` (also present at the base sha, checked with `git show <base sha>:<path>`). Pre-existing findings go to the queue, "Found, not fixed". A pre-existing security MAJOR is raised to the user in one line (fix now or queue), and never fixed silently.

**Why:** fixing old problems inside a new change grows the diff and hides what the change really did. The user still hears about a security risk at once.

## Weight per item (AC3.3)
The weight is chosen per item or slice, not per release, so one release may hold Full and Lite items. Full for security and core logic; Lite for docs, wording, nits and test refactors.

**Why:** one weight for a whole release either overpays for the small items or under-checks the risky ones.

## Slow platforms (AC3.4)
A slow platform run (for example the Windows Git Bash suites) runs once before the PR, not every fix round. CI is the cross-platform gate.

**Why:** a slow suite repeated on each fix round adds minutes to every round and finds nothing CI would not.

## Release size (AC3.5)
Prefer releases of 3-5 items: small enough to review, large enough to be worth shipping.
