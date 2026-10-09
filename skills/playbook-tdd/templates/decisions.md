# Decisions: <feature or bug>

Defaults chosen without asking because they are reversible. Review them in one batch at the end.
Ask instead (and do not log here) when a choice is hard to reverse: public API or data shape,
migrations, security, money, anything sent outside, or a product choice that belongs to the user.

| ID | Decision (the default taken) | Why this default | Alternatives | How to undo | Where (`path:line`, marker) | Status |
|---|---|---|---|---|---|---|
| D1 | Sort orders newest first | the existing list views do (`src/orders/list.ts:40`) | oldest first | flip the comparator | `src/orders/api.ts:88` `DECISION[D1]` | open |

Status: `open` (waiting for review) · `confirmed` (the user agreed) · `changed` (replaced, see the new row).
Mark each place in the code with a short comment `DECISION[Dn]` so the default can be found and undone.
