Checkout totals are drifting: a customer bought 3 bags of green tea at 19.99, 3 paper bags at 0.29 and 10 card
sleeves at 0.10 and the checkout showed 61.83. That is a cent short, and the accountant has found more orders like it.

We have talked about this for a while: prices should stop being decimal strings and become integer cents. Please do
that now: add `priceCents` to every product in our catalog files (there are copies of `data/products.json` at older
versions on the shop servers, so it has to go through our data migrations), and make the shop and checkout read it.
Prices shown in the shop must not change.

Price rules: `docs/prices.md`. How we change the data: `CONTRIBUTING.md`. Tests: `npm test`.
