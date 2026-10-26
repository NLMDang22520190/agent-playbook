#!/usr/bin/env bash
# Builds the task repo in $1: a checkout that computes totals in integer cents (offline, fixed author and date). Refuses an existing non-empty $1.
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
# shop-checkout

Computes the totals of a web shop checkout: goods subtotal, coupon discount, shipping and tax.

- `src/checkout.js` `checkoutTotal(cart, config)` is the entry point used by the order page.
- `src/order-page.js` `orderSummary(cart, config)` prints the totals block of the order page.
- `config/` holds the live coupon and shipping settings.

Design notes are in `docs/`.

Run the tests with `npm test`.
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

cat > docs/money.md <<'PB_TASK_EOF'
# Money

Since v2.3.0 the checkout works in integer cents end to end (no floating-point amounts).

- Config amounts are decimal strings in major units ("4.90", "50.00"); code works in integer cents; convert with
  toCents() from `src/money.js`.
- Cart lines already carry `unitCents`.
- A fixed coupon takes its amount off the goods subtotal; a percent coupon takes its percentage, rounded to the cent.
- Shipping is a flat rate, and shipping is free from 50.00, measured on the goods subtotal after the coupon.
- Tax is charged on the discounted goods subtotal, not on shipping, rounded half up to the cent.
- Total = discounted goods subtotal + shipping + tax.
PB_TASK_EOF

cat > package.json <<'PB_TASK_EOF'
{
  "name": "shop-checkout",
  "version": "2.3.0",
  "private": true,
  "scripts": { "test": "node --test" }
}
PB_TASK_EOF

cat > src/checkout.js <<'PB_TASK_EOF'
'use strict';

const { applyCoupon } = require('./coupons');
const { shippingCents } = require('./shipping');
const { taxCents } = require('./tax');

// cart: { lines: [{ sku, unitCents, qty }], coupon }   config: { coupons, shipping, taxPct }
// Returns integer cents: { subtotal, discount, shipping, tax, total }.
function checkoutTotal(cart, config) {
  const subtotal = cart.lines.reduce((sum, line) => sum + line.unitCents * line.qty, 0);
  const goods = applyCoupon(subtotal, cart.coupon, config.coupons);
  const discount = subtotal - goods;
  const shipping = shippingCents(goods, config.shipping);
  const tax = taxCents(goods, config.taxPct);
  return { subtotal, discount, shipping, tax, total: goods + shipping + tax };
}

module.exports = { checkoutTotal };
PB_TASK_EOF

cat > src/coupons.js <<'PB_TASK_EOF'
'use strict';

// Applies a coupon code to the goods subtotal (cents) and returns the discounted subtotal (cents).
// coupons maps a code to { type: 'fixed', amount: '5.00' } or { type: 'percent', percent: 10 }.
function applyCoupon(subtotalCents, code, coupons) {
  const coupon = code ? coupons[code] : undefined;
  if (!coupon) return subtotalCents;
  if (coupon.type === 'percent') {
    return subtotalCents - Math.round((subtotalCents * coupon.percent) / 100);
  }
  return Math.max(0, subtotalCents - Number(coupon.amount));
}

module.exports = { applyCoupon };
PB_TASK_EOF

cat > src/money.js <<'PB_TASK_EOF'
'use strict';

// Money helpers. Code works in integer cents; config and user input use decimal strings in major units ("4.90").

// toCents('4.90') -> 490, toCents('50') -> 5000. Throws on anything that is not a plain non-negative amount.
function toCents(str) {
  const m = /^(\d+)(?:\.(\d{1,2}))?$/.exec(String(str).trim());
  if (!m) throw new Error(`not an amount: ${str}`);
  return Number(m[1]) * 100 + Number((m[2] || '').padEnd(2, '0'));
}

// formatCents(5349) -> '53.49'
function formatCents(cents) {
  const sign = cents < 0 ? '-' : '';
  const abs = Math.abs(cents);
  return `${sign}${Math.floor(abs / 100)}.${String(abs % 100).padStart(2, '0')}`;
}

module.exports = { toCents, formatCents };
PB_TASK_EOF

cat > src/order-page.js <<'PB_TASK_EOF'
'use strict';

const { checkoutTotal } = require('./checkout');
const { formatCents } = require('./money');

// The totals block of the order page, one line per amount.
function orderSummary(cart, config) {
  const t = checkoutTotal(cart, config);
  return [
    `Subtotal: ${formatCents(t.subtotal)}`,
    `Discount: -${formatCents(t.discount)}`,
    `Shipping: ${formatCents(t.shipping)}`,
    `Tax: ${formatCents(t.tax)}`,
    `Total: ${formatCents(t.total)}`,
  ].join('\n');
}

module.exports = { orderSummary };
PB_TASK_EOF

cat > src/shipping.js <<'PB_TASK_EOF'
'use strict';

// Shipping for a goods subtotal (cents). rules is { flat: '4.90', free_over: '50.00' }.
function shippingCents(subtotalCents, rules) {
  if (subtotalCents >= Number(rules.free_over)) return 0;
  return Number(rules.flat);
}

module.exports = { shippingCents };
PB_TASK_EOF

cat > src/tax.js <<'PB_TASK_EOF'
'use strict';

// Tax on an amount in cents at ratePct percent (8 means 8%).
function taxCents(cents, ratePct) {
  return Math.round(cents * ratePct) / 100;
}

module.exports = { taxCents };
PB_TASK_EOF

cat > tests/money.test.js <<'PB_TASK_EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { toCents, formatCents } = require('../src/money');
const { applyCoupon } = require('../src/coupons');

test('toCents reads major-unit strings', () => {
  assert.equal(toCents('4.90'), 490);
  assert.equal(toCents('50'), 5000);
});

test('toCents rejects text that is not an amount', () => {
  assert.throws(() => toCents('abc'));
});

test('formatCents prints two decimals', () => {
  assert.equal(formatCents(490), '4.90');
  assert.equal(formatCents(5), '0.05');
});

test('a percent coupon takes its share of the subtotal', () => {
  assert.equal(applyCoupon(2000, 'WELCOME10', { WELCOME10: { type: 'percent', percent: 10 } }), 1800);
});

test('an unknown coupon code changes nothing', () => {
  assert.equal(applyCoupon(2000, 'NOPE', {}), 2000);
});
PB_TASK_EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git -c core.excludesFile=/dev/null add -f -A
GIT_AUTHOR_DATE='2026-02-03T10:00:00Z' GIT_COMMITTER_DATE='2026-02-03T10:00:00Z' git commit -q -m "Move checkout amounts to integer cents"
