Three tickets for the reports this week. Please do them in order, one after the other, and keep the existing tests passing as you go.

Ticket REP-31 (money format):
Amounts are shown differently in different reports and some of them print `$-5.00` for a refund. Please add `formatMoney(cents)` to
`src/money.js` following `docs/money.md`, and use it in the reports so there is one place that formats money.

Ticket REP-32 (field name):
The money field on a report row is called `total` but it is in cents, and that name already caused two bugs. Rename it to `totalCents`.
Everything that makes or reads report rows has to follow.

Ticket REP-33 (generation date):
Every report should say on which day it was generated, as described in `docs/reports.md`. The time must come from `ctx.now`, not from the clock.
