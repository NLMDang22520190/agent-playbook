#!/usr/bin/env bash
# Builds the task repo in $1: the order pricing of a small online shop, in node, in two releases: 1.4.0 (one shipping fee per order) and 1.5.0 (express shipping, and a refactor that charges the fee once for every order line), with the orders charged since 1.5.0 (offline, fixed authors and dates). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest")" ]; }; then
  echo "setup: refusing non-empty $dest" >&2
  exit 2
fi
mkdir -p "$dest"
cd "$dest"
mkdir -p data docs src tests

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false

# ---- commit 1: release 1.4.0 ----

cat > package.json <<'PB_TASK_EOF'
{
  "name": "shop-orders",
  "version": "1.4.0",
  "private": true,
  "scripts": { "test": "node --test" }
}
PB_TASK_EOF

cat > README.md <<'PB_TASK_EOF'
# shop-orders

Order pricing of a small online shop in Vietnam. Amounts are integers in VND.

- An order is `{ id, express, lines: [{ sku, qty, priceVnd }] }`.
- `src/goods.js` `goodsTotal(lines)`: the sum of `priceVnd * qty`.
- `src/shipping.js` `shippingFee(order)`: the shipping fee of an order.
- `src/orders.js` `orderTotal(order)`: goods total + shipping fee.

Node 18+, no dependencies. Tests: `npm test` (or `node --test`). Shipping rules: `docs/shipping.md`. Releases:
`CHANGELOG.md`. How we work: `CONTRIBUTING.md`.
PB_TASK_EOF

cat > CONTRIBUTING.md <<'PB_TASK_EOF'
# Contributing

- Keep changes small and covered by a test under `tests/` (`node:test`).
- No npm dependencies.
- Every release gets a `CHANGELOG.md` entry. A feature announced to customers is not taken back without the
  product owner.
- Shipping rules live in `docs/shipping.md`; update the doc together with the code.
PB_TASK_EOF

cat > docs/shipping.md <<'PB_TASK_EOF'
# Shipping

- One shipping fee per order, whatever the number of lines or items in it.
- Standard fee: 30000 VND, waived when the goods total (the sum of `priceVnd * qty` over the lines) is 500000 or more.
PB_TASK_EOF

cat > CHANGELOG.md <<'PB_TASK_EOF'
# Changelog

## 1.4.0 (2026-09-14)
- Free shipping from a goods total of 500000 VND.
PB_TASK_EOF

cat > src/goods.js <<'PB_TASK_EOF'
'use strict';

// goodsTotal(lines) -> the sum of priceVnd * qty over the order lines
function goodsTotal(lines) {
  return lines.reduce((sum, l) => sum + l.priceVnd * l.qty, 0);
}

module.exports = { goodsTotal };
PB_TASK_EOF

cat > src/shipping.js <<'PB_TASK_EOF'
'use strict';

const { goodsTotal } = require('./goods');

const STANDARD_FEE_VND = 30000;
const FREE_FROM_VND = 500000;

// shippingFee(order) -> the shipping fee of an order in VND (docs/shipping.md)
function shippingFee(order) {
  return goodsTotal(order.lines) >= FREE_FROM_VND ? 0 : STANDARD_FEE_VND;
}

module.exports = { shippingFee, STANDARD_FEE_VND, FREE_FROM_VND };
PB_TASK_EOF

cat > src/orders.js <<'PB_TASK_EOF'
'use strict';

const { goodsTotal } = require('./goods');
const { shippingFee } = require('./shipping');

// orderTotal(order) -> goods total + shipping fee, in VND
function orderTotal(order) {
  return goodsTotal(order.lines) + shippingFee(order);
}

module.exports = { orderTotal };
PB_TASK_EOF

cat > tests/shipping.test.js <<'PB_TASK_EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { shippingFee } = require('../src/shipping');
const { orderTotal } = require('../src/orders');

const one = (qty, priceVnd) => ({ id: 'T-1', express: false, lines: [{ sku: 'SKU-1', qty, priceVnd }] });

test('standard fee', () => {
  assert.equal(shippingFee(one(1, 120000)), 30000);
});

test('free from 500000', () => {
  assert.equal(shippingFee(one(1, 499999)), 30000);
  assert.equal(shippingFee(one(2, 250000)), 0);
});

test('order total', () => {
  assert.equal(orderTotal(one(3, 50000)), 180000);
});
PB_TASK_EOF

git -c core.excludesFile=/dev/null add -f -A
GIT_AUTHOR_DATE='2026-09-14T03:00:00Z' GIT_COMMITTER_DATE='2026-09-14T03:00:00Z' git commit -q -m "release 1.4.0"

# ---- commit 2: release 1.5.0 (express shipping; the fee loop is the bug) ----

cat > package.json <<'PB_TASK_EOF'
{
  "name": "shop-orders",
  "version": "1.5.0",
  "private": true,
  "scripts": { "test": "node --test" }
}
PB_TASK_EOF

cat > docs/shipping.md <<'PB_TASK_EOF'
# Shipping

- One shipping fee per order, whatever the number of lines or items in it.
- Standard fee: 30000 VND, waived when the goods total (the sum of `priceVnd * qty` over the lines) is 500000 or more.
- Express (`order.express` true, from 1.5.0): a surcharge of 20000 VND on top of the standard fee. The surcharge is
  always charged, also when the standard fee is waived: express on an order of 500000 or more costs 20000.
PB_TASK_EOF

cat > CHANGELOG.md <<'PB_TASK_EOF'
# Changelog

## 1.5.0 (2026-10-30)
- Express shipping: `order.express` adds a 20000 VND surcharge (announced to customers on 2026-10-23).
- Shipping fee computed line by line, to prepare split parcels.

## 1.4.0 (2026-09-14)
- Free shipping from a goods total of 500000 VND.
PB_TASK_EOF

cat > src/shipping.js <<'PB_TASK_EOF'
'use strict';

const { goodsTotal } = require('./goods');

const STANDARD_FEE_VND = 30000;
const FREE_FROM_VND = 500000;
const EXPRESS_SURCHARGE_VND = 20000;

// lineShipping(order, goods) -> the shipping of one parcel (one order line)
function lineShipping(order, goods) {
  let fee = goods >= FREE_FROM_VND ? 0 : STANDARD_FEE_VND;
  if (order.express) fee += EXPRESS_SURCHARGE_VND;
  return fee;
}

// shippingFee(order) -> the shipping fee of an order in VND (docs/shipping.md)
function shippingFee(order) {
  const goods = goodsTotal(order.lines);
  let fee = 0;
  for (const line of order.lines) {
    fee += lineShipping(order, goods);
  }
  return fee;
}

module.exports = { shippingFee, STANDARD_FEE_VND, FREE_FROM_VND, EXPRESS_SURCHARGE_VND };
PB_TASK_EOF

cat > tests/shipping.test.js <<'PB_TASK_EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { shippingFee } = require('../src/shipping');
const { orderTotal } = require('../src/orders');

const one = (qty, priceVnd, express = false) => ({ id: 'T-1', express, lines: [{ sku: 'SKU-1', qty, priceVnd }] });

test('standard fee', () => {
  assert.equal(shippingFee(one(1, 120000)), 30000);
});

test('free from 500000', () => {
  assert.equal(shippingFee(one(1, 499999)), 30000);
  assert.equal(shippingFee(one(2, 250000)), 0);
});

test('express adds 20000', () => {
  assert.equal(shippingFee(one(1, 120000, true)), 50000);
  assert.equal(shippingFee(one(1, 650000, true)), 20000);
});

test('order total', () => {
  assert.equal(orderTotal(one(3, 50000)), 180000);
});
PB_TASK_EOF

cat > data/orders-incident.json <<'PB_TASK_EOF'
[
  { "id": "DH-3001", "express": false, "chargedShipping": 30000,
    "lines": [{ "sku": "AO-SOMI", "qty": 1, "priceVnd": 150000 }] },
  { "id": "DH-3002", "express": false, "chargedShipping": 60000,
    "lines": [{ "sku": "QUAN-JEAN", "qty": 1, "priceVnd": 180000 }, { "sku": "THAT-LUNG", "qty": 1, "priceVnd": 50000 }] },
  { "id": "DH-3003", "express": true, "chargedShipping": 50000,
    "lines": [{ "sku": "OP-LUNG", "qty": 2, "priceVnd": 60000 }] },
  { "id": "DH-3004", "express": true, "chargedShipping": 150000,
    "lines": [{ "sku": "SACH", "qty": 2, "priceVnd": 85000 }, { "sku": "BUT", "qty": 4, "priceVnd": 10000 },
              { "sku": "SO-TAY", "qty": 2, "priceVnd": 50000 }] },
  { "id": "DH-3005", "express": false, "chargedShipping": 0,
    "lines": [{ "sku": "TAI-NGHE", "qty": 1, "priceVnd": 590000 }, { "sku": "CAP-SAC", "qty": 1, "priceVnd": 50000 }] },
  { "id": "DH-3006", "express": true, "chargedShipping": 40000,
    "lines": [{ "sku": "DONG-HO", "qty": 1, "priceVnd": 650000 }, { "sku": "DAY-DONG-HO", "qty": 1, "priceVnd": 50000 }] }
]
PB_TASK_EOF

git -c core.excludesFile=/dev/null add -f -A
GIT_AUTHOR_DATE='2026-10-30T01:30:00Z' GIT_COMMITTER_DATE='2026-10-30T01:30:00Z' git commit -q -m "release 1.5.0: express shipping"
