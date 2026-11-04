// PB-HIDDEN-CANARY:project-01-order-flow
// Hidden PASS_TO_PASS test: pricing, stock and the order page keep working as before.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { loadConfig } = require('../src/config');
const { createInventory } = require('../src/inventory');
const { placeOrder } = require('../src/orders');
const { orderSummary } = require('../src/order-page');
const { priceOrder } = require('../src/pricing');
const { toCents, formatCents } = require('../src/money');
const { dailyRevenue } = require('../src/reports');

const NOW = new Date('2026-03-01T10:00:00Z');

test('pricing: percent coupon, free shipping, tax on the discounted goods', () => {
  const t = priceOrder({ lines: [{ sku: 'A', qty: 2, unitCents: 3000 }], coupon: 'WELCOME10' }, loadConfig());
  assert.deepEqual(t, { goodsCents: 6000, discountCents: 600, discountedCents: 5400, shippingCents: 0, taxCents: 540, totalCents: 5940 });
});

test('pricing: a fixed coupon never takes the goods below zero', () => {
  const t = priceOrder({ lines: [{ sku: 'A', qty: 1, unitCents: 300 }], coupon: 'SAVE5' }, loadConfig());
  assert.equal(t.discountedCents, 0);
  assert.equal(t.taxCents, 0);
  assert.equal(t.totalCents, 490);
});

test('placing an order reserves the stock all or nothing', () => {
  const inventory = createInventory({ A: 5, B: 0 });
  const ctx = { inventory, config: loadConfig(), now: NOW };
  assert.throws(() => placeOrder({ lines: [{ sku: 'A', qty: 2, unitCents: 100 }, { sku: 'B', qty: 1, unitCents: 100 }], coupon: null }, ctx), { code: 'OUT_OF_STOCK' });
  assert.equal(inventory.stock('A'), 5);
});

test('a placed order is paid, has no refunds and its page matches the totals', () => {
  const ctx = { inventory: createInventory({ A: 5 }), config: loadConfig(), now: NOW };
  const order = placeOrder({ lines: [{ sku: 'A', qty: 1, unitCents: 1000 }], coupon: null }, ctx);
  assert.equal(order.status, 'paid');
  assert.deepEqual(order.refunds, []);
  assert.equal(orderSummary(order).totalCents, order.totals.totalCents);
});

test('daily revenue sums the orders placed that UTC day', () => {
  const inv = createInventory({ A: 9 });
  const config = loadConfig();
  const o1 = placeOrder({ lines: [{ sku: 'A', qty: 1, unitCents: 1000 }], coupon: null }, { inventory: inv, config, now: new Date('2026-03-01T00:00:01Z') });
  const o2 = placeOrder({ lines: [{ sku: 'A', qty: 1, unitCents: 2000 }], coupon: null }, { inventory: inv, config, now: new Date('2026-03-01T23:59:59Z') });
  const o3 = placeOrder({ lines: [{ sku: 'A', qty: 1, unitCents: 3000 }], coupon: null }, { inventory: inv, config, now: new Date('2026-03-02T00:00:00Z') });
  assert.equal(dailyRevenue([o1, o2, o3], '2026-03-01'), o1.totals.totalCents + o2.totals.totalCents);
  assert.equal(dailyRevenue([o1, o2, o3], '2026-03-02'), o3.totals.totalCents);
});

test('money helpers', () => {
  assert.equal(toCents('4.90'), 490);
  assert.equal(toCents('5'), 500);
  assert.equal(formatCents(490), '4.90');
});
