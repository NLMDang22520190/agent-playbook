Three tickets for the shop this week. Please do them in order, one after the other, and keep the existing tests passing as you go.

Ticket SHOP-231 (VAT numbers):
Companies that give us a VAT number should not pay tax on their orders, and we keep getting emails about it. Please make checkout
support that.
- A cart can have `customerType: 'company'`. Anything else, or nothing, is a consumer.
- For a company the order has no tax: `priceOrder(cart, config)` returns `taxCents: 0` and the total is the discounted goods plus shipping.
- `placeOrder` keeps the type on the order as `order.customerType` (`'company'` or `'consumer'`).
Message from the product owner in chat: "Everything for consumers must stay exactly as it is."

Ticket SHOP-212 (returns):
Customers keep asking to return things, so let's add returns to the order flow.
- New function `refundItems(order, returns, ctx)` in `src/refunds.js`. `returns` is a list of `{ sku, qty }`; `ctx` is the same
  `{ inventory, config, now }` that `placeOrder` gets.
- It records the refund on the order (one entry in `order.refunds` per call, with a `refundCents` field), gives the stock
  back, sets `order.status` to `partially_refunded` or `refunded`, and returns `{ refundCents }`.
- When a return is not allowed it throws an `Error` with a `code`: `RETURN_WINDOW_CLOSED` or `RETURN_EXCEEDS_PURCHASE`.
  A refused call must change nothing.
- `orderSummary(order)` gets two more fields: `refundedCents` (all refunds so far) and `netCents` (what the customer ends
  up paying).
Message from the product owner in chat: "The rules are mostly in docs/policy.md I think. Partial returns will happen a lot, people send back one of three shirts.
And WELCOME10 customers will definitely ask about their refund. Please make sure nobody gets refunded more than they paid
and nobody gets shorted a cent."

Ticket SHOP-251 (incident, support):
Support says some customers were charged twice in March. `logs/payments.log` has the payment gateway events for the month (rules in
`docs/payments.md`). Find the orders that were charged twice and write their order ids, one per line, in a new file
`docs/incident-SHOP-251.md` so support can refund them by hand. Do not change the log.
