#!/usr/bin/env bash
# Builds the task repo in $1: the shop of project-01-order-flow (without returns) plus an invoice module that repeats the tax rule (offline, fixed author and date). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
here="$(cd "$(dirname "$0")" && pwd)"
bash "$here/../project-01-order-flow/setup.sh" "$dest"
cd "$dest"

cat > docs/invoicing.md <<'PB_TASK_EOF'
# Invoicing

The invoice shows the same amounts as the order: its VAT line is the order's tax, and its total is the order's total. All amounts are
integer cents.
PB_TASK_EOF

cat > src/invoice.js <<'PB_TASK_EOF'
'use strict';

// The invoice of an order: what the customer is charged, line by line, in cents.
function invoiceFor(order, config) {
  const t = order.totals;
  const vatCents = Math.floor((t.discountedCents * config.tax_percent + 50) / 100);
  return {
    goodsCents: t.goodsCents,
    discountCents: t.discountCents,
    shippingCents: t.shippingCents,
    vatCents,
    totalCents: t.discountedCents + t.shippingCents + vatCents,
  };
}

module.exports = { invoiceFor };
PB_TASK_EOF

cat > tests/invoice.test.js <<'PB_TASK_EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createInventory } = require('../src/inventory');
const { placeOrder } = require('../src/orders');
const { invoiceFor } = require('../src/invoice');
const { loadConfig } = require('../src/config');

test('the invoice of a consumer order matches the order', () => {
  const config = loadConfig();
  const ctx = { inventory: createInventory({ A: 9 }), config, now: new Date('2026-03-01T10:00:00Z') };
  const order = placeOrder({ lines: [{ sku: 'A', qty: 2, unitCents: 1000 }], coupon: null }, ctx);
  const inv = invoiceFor(order, config);
  assert.equal(inv.vatCents, order.totals.taxCents);
  assert.equal(inv.totalCents, order.totals.totalCents);
});
PB_TASK_EOF

git -c core.excludesFile=/dev/null add -f -A
GIT_AUTHOR_DATE='2026-02-11T10:00:00Z' GIT_COMMITTER_DATE='2026-02-11T10:00:00Z' git commit -q -m "Invoice module"
