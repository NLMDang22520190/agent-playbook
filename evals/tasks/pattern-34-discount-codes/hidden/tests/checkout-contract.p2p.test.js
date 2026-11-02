// PB-HIDDEN-CANARY:pattern-34-discount-codes
// Hidden PASS_TO_PASS test: a checkout without a code keeps its contract (before and after the change): the API
// answers 200 with subtotalCents, taxCents (half up), shippingCents (500, free from a 5000 subtotal) and totalCents at
// their old values, discountCents absent or 0; the receipt has no Discount line.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const SRC = path.join(__dirname, '..', 'src');
const { checkout } = require(path.join(SRC, 'checkout.js'));
const { receiptLines } = require(path.join(SRC, 'receipt.js'));
const { handleCheckout } = require(path.join(SRC, 'api.js'));

const CASES = [
  // 3998 * 8% = 319.84 -> 320
  { lines: [{ unitCents: 1999, qty: 2 }], ratePct: 8,
    want: { subtotalCents: 3998, taxCents: 320, shippingCents: 500, totalCents: 4818 } },
  // 5000: free shipping; 5000 * 10% = 500
  { lines: [{ unitCents: 2500, qty: 1 }, { unitCents: 1250, qty: 2 }], ratePct: 10,
    want: { subtotalCents: 5000, taxCents: 500, shippingCents: 0, totalCents: 5500 } },
];
const pick = (r) => ({ subtotalCents: r.subtotalCents, taxCents: r.taxCents, shippingCents: r.shippingCents,
  totalCents: r.totalCents });

test('AC no code: the API keeps its fields and values', async () => {
  for (const c of CASES) {
    const res = await handleCheckout({ lines: c.lines, ratePct: c.ratePct });
    assert.equal(res.status, 200);
    assert.deepEqual(pick(res.body), c.want);
    assert.ok(res.body.discountCents === undefined || res.body.discountCents === 0, 'discountCents absent or 0');
  }
});

test('AC no code: checkout keeps its values', () => {
  for (const c of CASES) {
    const r = checkout({ lines: c.lines, ratePct: c.ratePct });
    assert.deepEqual(pick(r), c.want);
    assert.ok(r.discountCents === undefined || r.discountCents === 0, 'discountCents absent or 0');
  }
});

test('AC no code: the receipt has no Discount line', () => {
  for (const c of CASES) {
    const lines = receiptLines(checkout({ lines: c.lines, ratePct: c.ratePct }));
    assert.ok(Array.isArray(lines) && lines.length > 0, 'receiptLines returns a non-empty array');
    assert.ok(!lines.some((l) => /^Discount\b/.test(l)), `no Discount line in ${JSON.stringify(lines)}`);
  }
});
