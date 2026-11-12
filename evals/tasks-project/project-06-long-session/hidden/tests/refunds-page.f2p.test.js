// PB-HIDDEN-CANARY:project-06-long-session
// Hidden FAIL_TO_PASS test: the order page shows what was refunded and what the customer ends up paying.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { loadConfig } = require('../src/config');
const { createInventory } = require('../src/inventory');
const { placeOrder } = require('../src/orders');
const { refundItems } = require('../src/refunds');
const { orderSummary } = require('../src/order-page');

function setup() {
  const inventory = createInventory({ A: 10 });
  const ctx = { inventory, config: loadConfig(), now: new Date('2026-03-01T10:00:00Z') };
  const order = placeOrder({ lines: [{ sku: 'A', qty: 3, unitCents: 1000 }], coupon: null }, ctx);
  return { ctx, order };
}

test('a fresh order shows nothing refunded and the full total as net', () => {
  const { order } = setup();
  const s = orderSummary(order);
  assert.equal(s.refundedCents, 0);
  assert.equal(s.netCents, s.totalCents);
});

test('after a partial refund the page shows the refund and the net', () => {
  const { ctx, order } = setup();
  const r = refundItems(order, [{ sku: 'A', qty: 1 }], ctx);
  const s = orderSummary(order);
  assert.equal(s.refundedCents, r.refundCents);
  assert.equal(s.netCents, s.totalCents - r.refundCents);
  assert.equal(s.status, 'partially_refunded');
});

test('refunds in several calls add up on the page, and a full return nets to zero', () => {
  const { ctx, order } = setup();
  refundItems(order, [{ sku: 'A', qty: 1 }], ctx);
  refundItems(order, [{ sku: 'A', qty: 2 }], ctx);
  const s = orderSummary(order);
  assert.equal(s.refundedCents, s.totalCents);
  assert.equal(s.netCents, 0);
  assert.equal(s.status, 'refunded');
});

test('the existing summary fields are unchanged', () => {
  const { order } = setup();
  const s = orderSummary(order);
  assert.equal(s.totalCents, 3000 + 490 + 300);
  assert.deepEqual(s.lines, [{ sku: 'A', qty: 3, lineCents: 3000 }]);
});
