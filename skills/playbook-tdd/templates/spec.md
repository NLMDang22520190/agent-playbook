# 01 - Spec: <feature or bug>

## Source
Where the request comes from: issue/ticket URL, user story id, the user's chat message (quoted),
design or prototype files. Nothing goes into this spec that the source did not say; gaps become
questions (hard to reverse) or logged defaults in `decisions.md` (reversible).

## Goal
<one or two sentences: who gets what>

**Weight:** Full | Lite · reason: <e.g. "Lite: one module, reversible, 2 files"> (escalate to Full if that stops being true)

## Understanding
Fill this in before any test or code (Lite: a few lines).
- **The request, restated in my own words:** ...
- **Scan log:** each search command with its hit count, then the files read.
  - `grep -rn "<term>" src` -> N hits
  - Files read: `path`, `path`
- **Other readings** of the request, and why I chose this one: ...
- **In scope:** ...
- **Out of scope:** ...
A reading that is ambiguous and hard to reverse is asked before any code, in one batched question.

## Impact
Who calls or uses what changes. Give the search command, its hits, and file:line for each caller or user.
- `grep -rn "<symbol>" .` -> N hits: `path:line` (what uses it) ...

## Regression corpus
Only when the change replaces or rewrites existing logic; otherwise write "none". List the old inputs and the
earlier bugs the new code must still handle, each with its expected result. The first RED covers all of it.
| Old input or earlier bug | Expected result | Where it is pinned today |
|---|---|---|
| <input, or "bug #12: ..."> | <expected output or behaviour> | `tests/...` or "not yet" |

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
