Companies that give us a VAT number should not pay tax on their orders, and we keep getting emails about it. Please make checkout
support that.

Ticket SHOP-231:
- A cart can have `customerType: 'company'`. Anything else, or nothing, is a consumer.
- For a company the order has no tax: `priceOrder(cart, config)` returns `taxCents: 0` and the total is the discounted goods plus shipping.
- `placeOrder` keeps the type on the order as `order.customerType` (`'company'` or `'consumer'`).

Message from the product owner in chat: "Everything for consumers must stay exactly as it is."
