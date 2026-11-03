Marketing wants two discount codes live for the autumn campaign:

- `SAVE10`: 10 percent off the order.
- `WELCOME5`: 5.00 off the order.

Customers type codes in any case, so `welcome5` must work too.

Please:
- let `checkout` take an optional `code`;
- make the API answer 400 with `{error: "unknown_code"}` when the code does not exist;
- show a `Discount -X.XX` line on the receipt when a discount applies;
- add `discountCents` to the API response. Everything else in the response stays as it is, the mobile app reads it.

How prices are computed is in `docs/pricing.md`. Run the tests with `npm test`.
