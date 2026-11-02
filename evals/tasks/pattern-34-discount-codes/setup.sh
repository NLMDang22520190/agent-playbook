#!/usr/bin/env bash
# Builds the task repo in $1: the checkout of a small online shop, in node (cart, tax, shipping, receipt, API), with no discount codes yet (offline, fixed author and date). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest")" ]; }; then
  echo "setup: refusing non-empty $dest" >&2
  exit 2
fi
mkdir -p "$dest"
cd "$dest"
mkdir -p docs src tests

cat > package.json <<'PB_TASK_EOF'
{
  "name": "shop-checkout",
  "version": "2.3.0",
  "private": true,
  "scripts": { "test": "node --test" }
}
PB_TASK_EOF

cat > README.md <<'PB_TASK_EOF'
# shop-checkout

Checkout of a small online shop: cart subtotal, tax, shipping, the printed receipt and the JSON API the web shop and
the mobile app call.

- Money is in integer cents. A cart line is `{ unitCents, qty }`.
- `src/cart.js` `subtotalCents(lines)`, `src/tax.js` `taxCents(amountCents, ratePct)`,
  `src/shipping.js` `shippingCents(subtotalCents)`.
- `src/checkout.js` `checkout({ lines, ratePct })` puts them together and returns
  `{ subtotalCents, taxCents, shippingCents, totalCents }`.
- `src/receipt.js` `receiptLines(result)` turns a checkout result into the printed lines (`Subtotal 39.98`).
- `src/api.js` `handleCheckout(body)` is the `POST /checkout` handler; it returns `{ status, body }`.

Node 18+, no dependencies. Tests: `npm test` (or `node --test`). Pricing rules: `docs/pricing.md`. How we work:
`CONTRIBUTING.md`.
PB_TASK_EOF

cat > CONTRIBUTING.md <<'PB_TASK_EOF'
# Contributing

- Keep changes small and covered by a test under `tests/` (`node:test`).
- No npm dependencies.
- The API response is read by the mobile app: a change adds fields, it never renames or removes one.
- Pricing rules live in `docs/pricing.md`; update the doc together with the code.
PB_TASK_EOF

cat > docs/pricing.md <<'PB_TASK_EOF'
# Pricing

Agreed with finance, 2026-03-02. All amounts are integer cents.

## Order of operations
1. Subtotal: the sum of `unitCents * qty` over the cart lines.
2. Discount (only when a discount code is given): taken off the subtotal, which gives the discounted subtotal.
   Without a code the discount is 0 and the discounted subtotal is the subtotal.
3. Tax: `ratePct` percent of the discounted subtotal.
4. Shipping: 500, free when the subtotal before the discount is 5000 or more.
5. Total = discounted subtotal + tax + shipping.

## Rounding
Every percentage (tax, and a percent discount) is rounded half up to the cent: 287.5 -> 288, 287.49 -> 287.

## Discount codes
- A code is either a percentage of the subtotal or a fixed amount of cents.
- A fixed discount never takes the discounted subtotal below 0: it is at most the subtotal.
- Codes are case-insensitive: `save10` and `SAVE10` are the same code.
- An unknown code is rejected, never ignored: the API answers HTTP 400 with the body `{ "error": "unknown_code" }`.
- With discount codes, the result of `checkout()` gains `discountCents` (the discount taken off the subtotal, 0 without
  a code), next to its other fields; the API 200 response gains the same `discountCents` field.

## API
`POST /checkout` is handled by `handleCheckout(body)` in `src/api.js`. The request body has the same fields as
`checkout()`: `{ lines: [{ unitCents, qty }], ratePct, code }` (`code` optional). It returns `{ status, body }`:
- 200 with `{ subtotalCents, taxCents, shippingCents, totalCents }`;
- 400 with `{ error: "bad_request" }` when `lines` or `ratePct` is missing or invalid;
- 400 with `{ error: "unknown_code" }` for an unknown discount code.

## Receipt
`receiptLines(result)` prints one line per amount, label and amount in units with 2 decimals: `Subtotal 39.98`,
then `Discount -4.00` when a discount applies (no line otherwise), `Tax 2.88`, `Shipping 5.00`, `Total 43.86`.
PB_TASK_EOF

cat > src/cart.js <<'PB_TASK_EOF'
'use strict';

// subtotalCents(lines) -> the sum of unitCents * qty over the cart lines
function subtotalCents(lines) {
  return lines.reduce((sum, l) => sum + l.unitCents * l.qty, 0);
}

module.exports = { subtotalCents };
PB_TASK_EOF

cat > src/tax.js <<'PB_TASK_EOF'
'use strict';

// percentHalfUp(amountCents, pct) -> pct percent of a non-negative amount, rounded half up to the cent
function percentHalfUp(amountCents, pct) {
  return Math.floor((amountCents * pct + 50) / 100);
}

// taxCents(amountCents, ratePct) -> the tax on an amount (docs/pricing.md: half up)
function taxCents(amountCents, ratePct) {
  return percentHalfUp(amountCents, ratePct);
}

module.exports = { taxCents, percentHalfUp };
PB_TASK_EOF

cat > src/shipping.js <<'PB_TASK_EOF'
'use strict';

const SHIPPING_CENTS = 500;
const FREE_FROM_CENTS = 5000;

// shippingCents(subtotalCents) -> 500, free from a 5000 subtotal (docs/pricing.md)
function shippingCents(subtotalCents) {
  return subtotalCents >= FREE_FROM_CENTS ? 0 : SHIPPING_CENTS;
}

module.exports = { shippingCents, SHIPPING_CENTS, FREE_FROM_CENTS };
PB_TASK_EOF

cat > src/checkout.js <<'PB_TASK_EOF'
'use strict';

const { subtotalCents } = require('./cart');
const { taxCents } = require('./tax');
const { shippingCents } = require('./shipping');

// checkout({ lines, ratePct }) -> { subtotalCents, taxCents, shippingCents, totalCents } (docs/pricing.md)
function checkout({ lines, ratePct }) {
  const subtotal = subtotalCents(lines);
  const tax = taxCents(subtotal, ratePct);
  const shipping = shippingCents(subtotal);
  return {
    subtotalCents: subtotal,
    taxCents: tax,
    shippingCents: shipping,
    totalCents: subtotal + tax + shipping,
  };
}

module.exports = { checkout };
PB_TASK_EOF

cat > src/receipt.js <<'PB_TASK_EOF'
'use strict';

// money(cents) -> "39.98" (units with 2 decimals; a negative amount gets a leading "-")
function money(cents) {
  const sign = cents < 0 ? '-' : '';
  const abs = Math.abs(cents);
  return `${sign}${Math.floor(abs / 100)}.${String(abs % 100).padStart(2, '0')}`;
}

// receiptLines(result) -> the printed lines of a checkout result
function receiptLines(result) {
  return [
    `Subtotal ${money(result.subtotalCents)}`,
    `Tax ${money(result.taxCents)}`,
    `Shipping ${money(result.shippingCents)}`,
    `Total ${money(result.totalCents)}`,
  ];
}

module.exports = { receiptLines, money };
PB_TASK_EOF

cat > src/api.js <<'PB_TASK_EOF'
'use strict';

const { checkout } = require('./checkout');

function validLines(lines) {
  return Array.isArray(lines) && lines.length > 0 &&
    lines.every((l) => l && Number.isInteger(l.unitCents) && l.unitCents >= 0 && Number.isInteger(l.qty) && l.qty > 0);
}

// handleCheckout(body) -> { status, body }: the POST /checkout handler (docs/pricing.md, "API")
function handleCheckout(body) {
  if (!body || !validLines(body.lines) || typeof body.ratePct !== 'number' || body.ratePct < 0) {
    return { status: 400, body: { error: 'bad_request' } };
  }
  const r = checkout({ lines: body.lines, ratePct: body.ratePct });
  return {
    status: 200,
    body: {
      subtotalCents: r.subtotalCents,
      taxCents: r.taxCents,
      shippingCents: r.shippingCents,
      totalCents: r.totalCents,
    },
  };
}

module.exports = { handleCheckout };
PB_TASK_EOF

cat > tests/pricing.test.js <<'PB_TASK_EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { subtotalCents } = require('../src/cart');
const { taxCents } = require('../src/tax');
const { shippingCents } = require('../src/shipping');
const { checkout } = require('../src/checkout');

test('subtotal', () => {
  assert.equal(subtotalCents([{ unitCents: 250, qty: 3 }, { unitCents: 99, qty: 1 }]), 849);
});

test('tax rounds half up', () => {
  assert.equal(taxCents(3125, 10), 313);
  assert.equal(taxCents(3124, 10), 312);
});

test('shipping is free from 5000', () => {
  assert.equal(shippingCents(4999), 500);
  assert.equal(shippingCents(5000), 0);
});

test('checkout adds it up', () => {
  const r = checkout({ lines: [{ unitCents: 1000, qty: 2 }], ratePct: 10 });
  assert.equal(r.subtotalCents, 2000);
  assert.equal(r.taxCents, 200);
  assert.equal(r.shippingCents, 500);
  assert.equal(r.totalCents, 2700);
});
PB_TASK_EOF

cat > tests/api.test.js <<'PB_TASK_EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { handleCheckout } = require('../src/api');
const { receiptLines } = require('../src/receipt');
const { checkout } = require('../src/checkout');

test('the API answers 200 with the totals', () => {
  const res = handleCheckout({ lines: [{ unitCents: 1000, qty: 2 }], ratePct: 10 });
  assert.equal(res.status, 200);
  assert.equal(res.body.totalCents, 2700);
});

test('the API rejects a body without lines', () => {
  assert.deepEqual(handleCheckout({ ratePct: 10 }), { status: 400, body: { error: 'bad_request' } });
});

test('the receipt prints each amount', () => {
  assert.deepEqual(receiptLines(checkout({ lines: [{ unitCents: 1000, qty: 2 }], ratePct: 10 })),
    ['Subtotal 20.00', 'Tax 2.00', 'Shipping 5.00', 'Total 27.00']);
});
PB_TASK_EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git -c core.excludesFile=/dev/null add -f -A
GIT_AUTHOR_DATE='2026-09-09T07:45:00Z' GIT_COMMITTER_DATE='2026-09-09T07:45:00Z' git commit -q -m "Checkout: cart, tax, shipping, receipt, API"
