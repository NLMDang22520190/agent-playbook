# 01 - Spec: <feature or bug>

## Source
Where the request comes from: issue/ticket URL, user story id, the user's chat message (quoted),
design or prototype files. Nothing goes into this spec that the source did not say; gaps become
questions (hard to reverse) or logged defaults in `decisions.md` (reversible).

## Goal
<one or two sentences: who gets what>

**Weight:** Full | Lite · reason: <e.g. "Lite: one module, reversible, 2 files"> (escalate to Full if that stops being true)

## Acceptance criteria
Copy the wording **verbatim** from the source when it exists; rephrase only into Given/When/Then and
keep the original next to it. Each AC points back to where it came from.

| AC | Criterion (Given / When / Then) | Source anchor (verbatim quote + where) |
|---|---|---|
| AC1 | Given <state>, when <action>, then <observable result>. | "Customers can cancel within 24h" (issue #42, 2nd bullet) |
| AC2 | ... | `design/checkout.fig` frame "Cancel" · label text "Cancel order" |

## Non-goals
- ...

## Constraints and context
- Conventions, existing helpers to reuse, performance or security limits.
- Baseline: `<test_cmd>` at <sha>: <N> failing before we start (list them).

## Slices (in order)
| Slice | Behaviour | ACs | Notes |
|---|---|---|---|
| S1 | <simplest happy path> | AC1 | |
| S2 | <variation> | AC2 | |
| S3 | <error path> | AC3 | |

## Open questions and logged defaults
- [ask] ... (hard to reverse; default if no answer: ...)
- [default D1] see `decisions.md`
