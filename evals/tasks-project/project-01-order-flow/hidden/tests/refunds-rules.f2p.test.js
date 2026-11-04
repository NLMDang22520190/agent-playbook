// PB-HIDDEN-CANARY:project-01-order-flow
// Hidden FAIL_TO_PASS test: the refund rules the ticket and docs/policy.md state, on numbers that divide exactly.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { loadConfig } = require('../src/config');
const { createInventory } = require('../src/inventory');
const { placeOrder } = require('../src/orders');
const { refundItems } = require('../src/refunds');

const NOW = new Date('2026-03-01T10:00:00Z');
function setup(lines, coupon, stock, now) {
  const inventory = createInventory(stock);
  const ctx = { inventory, config: loadConfig(), now: now || NOW };
  const order = placeOrder({ lines, coupon: coupon || null }, ctx);
  return { inventory, ctx, order };
}

test('one of two shirts back: its price plus its tax, no shipping, stock back', () => {
  const { inventory, ctx, order } = setup([{ sku: 'A', qty: 2, unitCents: 1000 }], null, { A: 10 });
  assert.equal(order.totals.totalCents, 2690);
  const r = refundItems(order, [{ sku: 'A', qty: 1 }], ctx);
  assert.equal(r.refundCents, 1100);
  assert.equal(order.status, 'partially_refunded');
  assert.equal(inventory.stock('A'), 9);
  assert.equal(order.refunds.length, 1);
  assert.equal(order.refunds[0].refundCents, 1100);
});

test('the last unreturned item brings the shipping back too, and the order is refunded', () => {
  const { inventory, ctx, order } = setup([{ sku: 'A', qty: 2, unitCents: 1000 }], null, { A: 10 });
  refundItems(order, [{ sku: 'A', qty: 1 }], ctx);
  const r = refundItems(order, [{ sku: 'A', qty: 1 }], ctx);
  assert.equal(r.refundCents, 1590);
  assert.equal(order.status, 'refunded');
  assert.equal(inventory.stock('A'), 10);
  assert.equal(order.refunds.length, 2);
});

test('everything in one call refunds exactly what was paid', () => {
  const { ctx, order } = setup([{ sku: 'A', qty: 2, unitCents: 1000 }], null, { A: 10 });
  assert.equal(refundItems(order, [{ sku: 'A', qty: 2 }], ctx).refundCents, 2690);
});

test('two different lines are refunded in proportion to their price', () => {
  const { ctx, order } = setup([{ sku: 'A', qty: 1, unitCents: 1000 }, { sku: 'B', qty: 1, unitCents: 3000 }], null, { A: 5, B: 5 });
  assert.equal(order.totals.totalCents, 4890);
  assert.equal(refundItems(order, [{ sku: 'B', qty: 1 }], ctx).refundCents, 3300);
  assert.equal(refundItems(order, [{ sku: 'A', qty: 1 }], ctx).refundCents, 1590);
});

test('a percent coupon: the refund is what was actually paid for the item', () => {
  const { ctx, order } = setup([{ sku: 'A', qty: 2, unitCents: 3000 }], 'WELCOME10', { A: 10 });
  assert.equal(order.totals.totalCents, 5940);
  assert.equal(refundItems(order, [{ sku: 'A', qty: 1 }], ctx).refundCents, 2970);
  assert.equal(refundItems(order, [{ sku: 'A', qty: 1 }], ctx).refundCents, 2970);
});

test('a fixed coupon: both items carry half of the discount, the last return adds shipping', () => {
  const { ctx, order } = setup([{ sku: 'A', qty: 1, unitCents: 1500 }, { sku: 'B', qty: 1, unitCents: 1500 }], 'SAVE5', { A: 5, B: 5 });
  assert.equal(order.totals.totalCents, 3240);
  assert.equal(refundItems(order, [{ sku: 'B', qty: 1 }], ctx).refundCents, 1375);
  assert.equal(refundItems(order, [{ sku: 'A', qty: 1 }], ctx).refundCents, 1865);
});

test('day 30 by UTC date is still allowed, day 31 is not', () => {
  const placed = new Date('2026-01-01T23:59:59Z');
  const { inventory, ctx, order } = setup([{ sku: 'A', qty: 2, unitCents: 1000 }], null, { A: 10 }, placed);
  const late = { ...ctx, now: new Date('2026-02-01T00:00:00Z') };
  assert.throws(() => refundItems(order, [{ sku: 'A', qty: 1 }], late), { code: 'RETURN_WINDOW_CLOSED' });
  assert.equal(order.refunds.length, 0);
  assert.equal(order.status, 'paid');
  assert.equal(inventory.stock('A'), 8);
  const edge = { ...ctx, now: '2026-01-31T00:00:01Z' };
  assert.equal(refundItems(order, [{ sku: 'A', qty: 1 }], edge).refundCents, 1100);
});

test('returning more than was bought is refused, also over several calls', () => {
  const { inventory, ctx, order } = setup([{ sku: 'A', qty: 2, unitCents: 1000 }], null, { A: 10 });
  assert.throws(() => refundItems(order, [{ sku: 'A', qty: 3 }], ctx), { code: 'RETURN_EXCEEDS_PURCHASE' });
  refundItems(order, [{ sku: 'A', qty: 2 }], ctx);
  assert.throws(() => refundItems(order, [{ sku: 'A', qty: 1 }], ctx), { code: 'RETURN_EXCEEDS_PURCHASE' });
  assert.equal(order.refunds.length, 1);
  assert.equal(inventory.stock('A'), 10);
});

test('an item that is not on the order is refused', () => {
  const { ctx, order } = setup([{ sku: 'A', qty: 1, unitCents: 1000 }], null, { A: 5 });
  assert.throws(() => refundItems(order, [{ sku: 'Z', qty: 1 }], ctx), { code: 'RETURN_EXCEEDS_PURCHASE' });
});

test('a refused call changes nothing, even when only a later line is wrong', () => {
  const { inventory, ctx, order } = setup([{ sku: 'A', qty: 1, unitCents: 1000 }, { sku: 'B', qty: 1, unitCents: 1000 }], null, { A: 5, B: 5 });
  assert.throws(() => refundItems(order, [{ sku: 'A', qty: 1 }, { sku: 'B', qty: 5 }], ctx), { code: 'RETURN_EXCEEDS_PURCHASE' });
  assert.equal(inventory.stock('A'), 4);
  assert.equal(inventory.stock('B'), 4);
  assert.equal(order.refunds.length, 0);
  assert.equal(order.status, 'paid');
});
