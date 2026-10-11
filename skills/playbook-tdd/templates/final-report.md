# 06 - Final report: <feature or bug>

**Result:** <one sentence>
**Weight:** Full | Lite (no independent review) | Exempt (docs-only / config-only / spike) · reason: <one line>
**Mode:** native | manual | none (degraded: roles shared one context)

## Request coverage
One row for each sentence of the raw request, copied verbatim. Leave none out. Each row says what happened to it.
| Request sentence (verbatim) | Status |
|---|---|
| "..." | done: where (file:line or AC) |
| "..." | read as: how I understood it, and why |
| "..." | not done: why, and who decides |

## AC to tests to evidence
| AC | Tests | Evidence | Confidence |
|---|---|---|---|
| AC1 | tests/x.test.ts:12 | green-S1 log (sha256 ...) | high: ran against the real endpoint |

Confidence is high | medium | low, with the reason in the same cell.

## Not checked
What was not exercised: environments, data, files and paths that were not run, tested or checked. Say "nothing" only when
it is true.
- ...

## Gates (fresh, after the last change)
<proof-run blocks: test, lint, typecheck>

## Pre-mortem
Three ways the result could still be wrong. For each: the command you ran to check it, and its outcome (one line per risk is enough at Lite).
1. risk: ... · command: ... · outcome: ...

## Cost
<paste `bash ~/.agents/playbook/scripts/cost.sh summary`>. Weight: Full | Lite. Wall-clock: <total>.
Tokens as reported by the harness (0 = unknown).

## Review
Verdict: ... (model: ...). Findings resolved: ... Open: ...

## Scope
<git diff --stat base..HEAD>. Out-of-scope changes: none / ...

## Assumptions
- ...

## Logged defaults (from decisions.md, for one batched review)
| ID | Default taken | How to undo | Status |
|---|---|---|---|

## Found, not fixed / [UNVERIFIED]
- ...

**Playbook feedback:** captured ids (fb-...) or none

## Learnings proposed
- ...
