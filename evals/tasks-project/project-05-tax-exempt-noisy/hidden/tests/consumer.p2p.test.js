// PB-HIDDEN-CANARY:project-05-tax-exempt-noisy
// Hidden PASS_TO_PASS test: consumer pricing, stock and the invoice keep working.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { loadConfig } = require('../src/config');
const { createInventory } = require('../src/inventory');
const { placeOrder } = require('../src/orders');
const { priceOrder } = require('../src/pricing');
const { invoiceFor } = require('../src/invoice');

test('consumer pricing: fixed coupon, tax half up', () => {
  const t = priceOrder({ lines: [{ sku: 'A', qty: 1, unitCents: 1500 }, { sku: 'B', qty: 1, unitCents: 1500 }], coupon: 'SAVE5' }, loadConfig());
  assert.deepEqual(t, { goodsCents: 3000, discountCents: 500, discountedCents: 2500, shippingCents: 490, taxCents: 250, totalCents: 3240 });
});

test('a consumer order and its invoice agree', () => {
  const config = loadConfig();
  const ctx = { inventory: createInventory({ A: 9 }), config, now: new Date('2026-03-01T10:00:00Z') };
  const o = placeOrder({ lines: [{ sku: 'A', qty: 3, unitCents: 337 }], coupon: 'WELCOME10' }, ctx);
  const inv = invoiceFor(o, config);
  assert.equal(inv.vatCents, o.totals.taxCents);
  assert.equal(inv.totalCents, o.totals.totalCents);
  assert.equal(ctx.inventory.stock('A'), 6);
});
