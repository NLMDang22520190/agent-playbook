Customers keep asking to return things, so let's add returns to the order flow.

Ticket SHOP-212:
- New function `refundItems(order, returns, ctx)` in `src/refunds.js`. `returns` is a list of `{ sku, qty }`; `ctx` is the same
  `{ inventory, config, now }` that `placeOrder` gets.
- It records the refund on the order (one entry in `order.refunds` per call, with a `refundCents` field), gives the stock
  back, sets `order.status` to `partially_refunded` or `refunded`, and returns `{ refundCents }`.
- When a return is not allowed it throws an `Error` with a `code`: `RETURN_WINDOW_CLOSED` or `RETURN_EXCEEDS_PURCHASE`.
  A refused call must change nothing.
- `orderSummary(order)` gets two more fields: `refundedCents` (all refunds so far) and `netCents` (what the customer ends
  up paying).

Message from the product owner in chat:
"The rules are mostly in docs/policy.md I think. Partial returns will happen a lot, people send back one of three shirts.
And WELCOME10 customers will definitely ask about their refund. Please make sure nobody gets refunded more than they paid
and nobody gets shorted a cent."
