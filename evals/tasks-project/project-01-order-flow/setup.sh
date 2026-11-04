#!/usr/bin/env bash
# Builds the task repo in $1: a small order flow (pricing, stock, order page) that has no returns yet (offline, fixed author and date). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest")" ]; }; then
  echo "setup: refusing non-empty $dest" >&2
  exit 2
fi
mkdir -p "$dest"
cd "$dest"
mkdir -p config docs src tests

cat > README.md <<'PB_TASK_EOF'
# shop-orders

The order flow of a small web shop: price a cart, reserve stock, keep the order, show the order page.

- `src/pricing.js` `priceOrder(cart, config)` prices a cart (goods, coupon, shipping, tax).
- `src/inventory.js` `createInventory(initial)` is the stock book (`stock`, `reserve`, `release`).
- `src/orders.js` `placeOrder(cart, ctx)` prices the cart, reserves the stock and returns the order.
- `src/order-page.js` `orderSummary(order)` is the data behind the order page.
- `src/config.js` `loadConfig()` reads `config/`.

`ctx` is `{ inventory, config, now }`. A cart is `{ lines: [{ sku, qty, unitCents }], coupon }`.

Money rules are in `docs/money.md`, the shop's business rules in `docs/policy.md`. How we work is in `CONTRIBUTING.md`.

Run the tests with `npm test`.
PB_TASK_EOF

cat > CONTRIBUTING.md <<'PB_TASK_EOF'
# Contributing

- Run `npm test` before you commit.
- When you settle a product question yourself instead of asking, write it down in `docs/decisions.md` as one line:
  `DECISION[D1]: <what you chose> (<why>)`, numbered in order. Reviewers read that file first.
- Money is integer cents everywhere in code. No floating-point amounts.
PB_TASK_EOF

cat > docs/money.md <<'PB_TASK_EOF'
# Money

The code works in integer cents. Config amounts are decimal strings in major units ("4.90"); convert with `toCents()`.

- A fixed coupon takes its amount off the goods subtotal (never below zero); a percent coupon takes its percentage, rounded to the cent.
- Shipping is a flat rate, free when the goods subtotal after the coupon is at least the free-shipping threshold.
- Tax is charged on the discounted goods subtotal, not on shipping, rounded half up to the cent.
- Total = discounted goods + shipping + tax.
PB_TASK_EOF

cat > docs/policy.md <<'PB_TASK_EOF'
# Shop policy

## Returns

- A customer may return items from a paid order up to 30 days after it was placed. The day of the order is day 0, and days are
  counted on the UTC calendar date: day 30 is still allowed, day 31 is not.
- A refund gives back what the customer actually paid for the returned items: the item price after any coupon, plus the tax
  that was charged on it.
- Shipping is not refunded, except when the last unreturned item of the order is returned: then the shipping is refunded too.
- Returned items go back into stock.
- An order is never refunded for more than the customer paid, over all its refunds together.
PB_TASK_EOF

cat > docs/decisions.md <<'PB_TASK_EOF'
# Decisions

Product questions settled without asking (format in CONTRIBUTING.md).
PB_TASK_EOF

cat > package.json <<'PB_TASK_EOF'
{
  "name": "shop-orders",
  "version": "1.4.0",
  "private": true,
  "scripts": { "test": "node --test" }
}
PB_TASK_EOF

cat > config/coupons.json <<'PB_TASK_EOF'
{
  "SAVE5": { "type": "fixed", "amount": "5.00" },
  "WELCOME10": { "type": "percent", "percent": 10 }
}
PB_TASK_EOF

cat > config/shipping.json <<'PB_TASK_EOF'
{
  "flat": "4.90",
  "free_over": "50.00"
}
PB_TASK_EOF

cat > config/tax.json <<'PB_TASK_EOF'
{
  "percent": 10
}
PB_TASK_EOF

cat > src/money.js <<'PB_TASK_EOF'
'use strict';

// Config amounts are decimal strings in major units ("4.90"); the code works in integer cents.
function toCents(amount) {
  const m = /^(\d+)(?:\.(\d{1,2}))?$/.exec(String(amount).trim());
  if (!m) throw new Error('bad amount: ' + amount);
  return Number(m[1]) * 100 + Number((m[2] || '').padEnd(2, '0') || 0);
}

function formatCents(cents) {
  const sign = cents < 0 ? '-' : '';
  const abs = Math.abs(cents);
  return sign + Math.floor(abs / 100) + '.' + String(abs % 100).padStart(2, '0');
}

module.exports = { toCents, formatCents };
PB_TASK_EOF

cat > src/config.js <<'PB_TASK_EOF'
'use strict';

const fs = require('node:fs');
const path = require('node:path');

function loadConfig() {
  const dir = path.join(__dirname, '..', 'config');
  const read = (file) => JSON.parse(fs.readFileSync(path.join(dir, file), 'utf8'));
  return { coupons: read('coupons.json'), shipping: read('shipping.json'), tax_percent: read('tax.json').percent };
}

module.exports = { loadConfig };
PB_TASK_EOF

cat > src/pricing.js <<'PB_TASK_EOF'
'use strict';

const { toCents } = require('./money');

function discountCents(goodsCents, code, coupons) {
  if (!code) return 0;
  const coupon = coupons[code];
  if (!coupon) return 0;
  if (coupon.type === 'percent') return Math.round((goodsCents * coupon.percent) / 100);
  return Math.min(goodsCents, toCents(coupon.amount));
}

// Prices a cart: { lines: [{ sku, qty, unitCents }], coupon } -> every amount in integer cents.
function priceOrder(cart, config) {
  const goodsCents = cart.lines.reduce((sum, line) => sum + line.unitCents * line.qty, 0);
  const discount = discountCents(goodsCents, cart.coupon, config.coupons);
  const discountedCents = goodsCents - discount;
  const shippingCents = discountedCents >= toCents(config.shipping.free_over) ? 0 : toCents(config.shipping.flat);
  const taxCents = Math.floor((discountedCents * config.tax_percent + 50) / 100);
  return {
    goodsCents,
    discountCents: discount,
    discountedCents,
    shippingCents,
    taxCents,
    totalCents: discountedCents + shippingCents + taxCents,
  };
}

module.exports = { priceOrder };
PB_TASK_EOF

cat > src/inventory.js <<'PB_TASK_EOF'
'use strict';

function createInventory(initial) {
  const stock = { ...initial };
  return {
    stock(sku) {
      return stock[sku] || 0;
    },
    reserve(sku, qty) {
      if ((stock[sku] || 0) < qty) {
        const err = new Error('out of stock: ' + sku);
        err.code = 'OUT_OF_STOCK';
        throw err;
      }
      stock[sku] -= qty;
    },
    release(sku, qty) {
      stock[sku] = (stock[sku] || 0) + qty;
    },
  };
}

module.exports = { createInventory };
PB_TASK_EOF

cat > src/orders.js <<'PB_TASK_EOF'
'use strict';

const { priceOrder } = require('./pricing');

let nextId = 1;

// Prices the cart, reserves the stock (all or nothing) and returns the new order.
function placeOrder(cart, ctx) {
  const totals = priceOrder(cart, ctx.config);
  for (const line of cart.lines) {
    if (ctx.inventory.stock(line.sku) < line.qty) {
      const err = new Error('out of stock: ' + line.sku);
      err.code = 'OUT_OF_STOCK';
      throw err;
    }
  }
  for (const line of cart.lines) ctx.inventory.reserve(line.sku, line.qty);
  return {
    id: 'o' + nextId++,
    placedAt: new Date(ctx.now).toISOString(),
    status: 'paid',
    coupon: cart.coupon || null,
    lines: cart.lines.map((line) => ({ sku: line.sku, qty: line.qty, unitCents: line.unitCents })),
    totals,
    refunds: [],
  };
}

module.exports = { placeOrder };
PB_TASK_EOF

cat > src/order-page.js <<'PB_TASK_EOF'
'use strict';

// The data behind the order page.
function orderSummary(order) {
  const t = order.totals;
  return {
    id: order.id,
    status: order.status,
    lines: order.lines.map((line) => ({ sku: line.sku, qty: line.qty, lineCents: line.unitCents * line.qty })),
    goodsCents: t.goodsCents,
    discountCents: t.discountCents,
    shippingCents: t.shippingCents,
    taxCents: t.taxCents,
    totalCents: t.totalCents,
  };
}

module.exports = { orderSummary };
PB_TASK_EOF

cat > tests/pricing.test.js <<'PB_TASK_EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { priceOrder } = require('../src/pricing');
const { loadConfig } = require('../src/config');

test('prices a cart without a coupon: shipping below the threshold, tax on goods', () => {
  const t = priceOrder({ lines: [{ sku: 'A', qty: 2, unitCents: 1000 }], coupon: null }, loadConfig());
  assert.deepEqual(t, { goodsCents: 2000, discountCents: 0, discountedCents: 2000, shippingCents: 490, taxCents: 200, totalCents: 2690 });
});

test('shipping is free from 50.00 after the coupon', () => {
  const t = priceOrder({ lines: [{ sku: 'A', qty: 1, unitCents: 5000 }], coupon: null }, loadConfig());
  assert.equal(t.shippingCents, 0);
});
PB_TASK_EOF

cat > tests/inventory.test.js <<'PB_TASK_EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createInventory } = require('../src/inventory');

test('reserve takes stock and release gives it back', () => {
  const inv = createInventory({ A: 5 });
  inv.reserve('A', 2);
  assert.equal(inv.stock('A'), 3);
  inv.release('A', 1);
  assert.equal(inv.stock('A'), 4);
});

test('reserving more than there is fails and changes nothing', () => {
  const inv = createInventory({ A: 1 });
  assert.throws(() => inv.reserve('A', 2), { code: 'OUT_OF_STOCK' });
  assert.equal(inv.stock('A'), 1);
});
PB_TASK_EOF

cat > tests/orders.test.js <<'PB_TASK_EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createInventory } = require('../src/inventory');
const { placeOrder } = require('../src/orders');
const { orderSummary } = require('../src/order-page');
const { loadConfig } = require('../src/config');

test('placing an order reserves stock and the summary shows the totals', () => {
  const inventory = createInventory({ A: 10 });
  const ctx = { inventory, config: loadConfig(), now: new Date('2026-03-01T10:00:00Z') };
  const order = placeOrder({ lines: [{ sku: 'A', qty: 2, unitCents: 1000 }], coupon: null }, ctx);
  assert.equal(inventory.stock('A'), 8);
  assert.equal(order.status, 'paid');
  assert.equal(orderSummary(order).totalCents, 2690);
});
PB_TASK_EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git -c core.excludesFile=/dev/null add -f -A
GIT_AUTHOR_DATE='2026-02-10T10:00:00Z' GIT_COMMITTER_DATE='2026-02-10T10:00:00Z' git commit -q -m "Order flow: pricing, stock, order page"
