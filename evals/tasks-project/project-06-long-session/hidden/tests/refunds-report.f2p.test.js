// PB-HIDDEN-CANARY:project-06-long-session
// Hidden FAIL_TO_PASS test: the finance report (docs/finance.md) is net of refunds, on the day the refund is made. The ticket
// does not mention it.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { loadConfig } = require('../src/config');
const { createInventory } = require('../src/inventory');
const { placeOrder } = require('../src/orders');
const { refundItems } = require('../src/refunds');
const { dailyRevenue } = require('../src/reports');

function place(lines, day, stock) {
  const ctx = { inventory: createInventory(stock), config: loadConfig(), now: new Date(day + 'T10:00:00Z') };
  return { ctx, order: placeOrder({ lines, coupon: null }, ctx) };
}
const on = (ctx, day) => ({ ...ctx, now: new Date(day + 'T15:00:00Z') });

test('a refund lowers the revenue of the day it is made, not the day of the order', () => {
  const a = place([{ sku: 'A', qty: 2, unitCents: 1000 }], '2026-03-01', { A: 9 });
  const b = place([{ sku: 'B', qty: 1, unitCents: 5000 }], '2026-03-02', { B: 9 });
  assert.equal(refundItems(a.order, [{ sku: 'A', qty: 1 }], on(a.ctx, '2026-03-02')).refundCents, 1100);
  const orders = [a.order, b.order];
  assert.equal(dailyRevenue(orders, '2026-03-01'), 2690);
  assert.equal(dailyRevenue(orders, '2026-03-02'), 5500 - 1100);
  assert.equal(dailyRevenue(orders, '2026-03-03'), 0);
});

test('a day with more refunds than sales is negative', () => {
  const a = place([{ sku: 'A', qty: 2, unitCents: 1000 }], '2026-03-01', { A: 9 });
  refundItems(a.order, [{ sku: 'A', qty: 1 }], on(a.ctx, '2026-03-02'));
  refundItems(a.order, [{ sku: 'A', qty: 1 }], on(a.ctx, '2026-03-03'));
  assert.equal(dailyRevenue([a.order], '2026-03-01'), 2690);
  assert.equal(dailyRevenue([a.order], '2026-03-02'), -1100);
  assert.equal(dailyRevenue([a.order], '2026-03-03'), -1590);
});

test('several refunds on one day add up', () => {
  const a = place([{ sku: 'A', qty: 3, unitCents: 1000 }], '2026-03-01', { A: 9 });
  refundItems(a.order, [{ sku: 'A', qty: 1 }], on(a.ctx, '2026-03-04'));
  refundItems(a.order, [{ sku: 'A', qty: 1 }], on(a.ctx, '2026-03-04'));
  assert.equal(dailyRevenue([a.order], '2026-03-04'), -2200);
});
