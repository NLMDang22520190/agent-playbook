// PB-HIDDEN-CANARY:project-06-long-session
// Hidden FAIL_TO_PASS test: whatever way the discount and the tax are shared out, no cent is lost or invented, in any return order.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { loadConfig } = require('../src/config');
const { createInventory } = require('../src/inventory');
const { placeOrder } = require('../src/orders');
const { refundItems } = require('../src/refunds');

const NOW = new Date('2026-03-01T10:00:00Z');
function setup(lines, coupon, stock) {
  const inventory = createInventory(stock);
  const ctx = { inventory, config: loadConfig(), now: NOW };
  const order = placeOrder({ lines, coupon: coupon || null }, ctx);
  return { inventory, ctx, order };
}
function permutations(items) {
  if (items.length <= 1) return [items];
  const out = [];
  items.forEach((x, i) => {
    for (const rest of permutations(items.slice(0, i).concat(items.slice(i + 1)))) out.push([x].concat(rest));
  });
  return out;
}
const taxUp = (cents) => Math.ceil((cents * 10) / 100);

// every way to send the units back one at a time
function check(lines, coupon, stock) {
  const units = [];
  for (const l of lines) for (let n = 0; n < l.qty; n++) units.push(l);
  const idx = units.map((_, i) => i);
  for (const perm of permutations(idx)) {
    const { inventory, ctx, order } = setup(lines, coupon, stock);
    const paid = order.totals.totalCents;
    const paidForGoods = paid - order.totals.shippingCents;
    let sum = 0;
    perm.forEach((u, k) => {
      const unit = units[u];
      const r = refundItems(order, [{ sku: unit.sku, qty: 1 }], ctx);
      assert.ok(Number.isInteger(r.refundCents) && r.refundCents >= 0, 'an integer number of cents, never negative');
      const last = k === perm.length - 1;
      if (!last) assert.ok(r.refundCents <= unit.unitCents + taxUp(unit.unitCents), 'an item is never refunded above its price plus its tax');
      sum += r.refundCents;
      if (!last) assert.ok(sum <= paidForGoods, 'before the last item nothing beyond the goods and tax is refunded');
    });
    assert.equal(sum, paid, 'all refunds together are exactly what was paid');
    assert.equal(order.refunds.reduce((a, r) => a + r.refundCents, 0), paid);
    assert.equal(order.status, 'refunded');
    for (const l of lines) assert.equal(inventory.stock(l.sku), stock[l.sku], 'stock is back to where it started');
  }
}

test('a percent coupon with awkward prices, units returned in every order', () => {
  check([{ sku: 'A', qty: 3, unitCents: 1999 }, { sku: 'B', qty: 2, unitCents: 333 }, { sku: 'C', qty: 1, unitCents: 4567 }], 'WELCOME10', { A: 9, B: 9, C: 9 });
});

test('a fixed coupon below the free-shipping line, units returned in every order', () => {
  check([{ sku: 'A', qty: 2, unitCents: 333 }, { sku: 'B', qty: 1, unitCents: 701 }], 'SAVE5', { A: 9, B: 9 });
});

test('no coupon and prices that do not divide, units returned in every order', () => {
  check([{ sku: 'A', qty: 3, unitCents: 337 }, { sku: 'B', qty: 1, unitCents: 1103 }], null, { A: 9, B: 9 });
});

test('several units per call add up the same as one at a time', () => {
  const lines = [{ sku: 'A', qty: 3, unitCents: 1999 }, { sku: 'B', qty: 2, unitCents: 333 }];
  const { ctx, order } = setup(lines, 'WELCOME10', { A: 9, B: 9 });
  const r1 = refundItems(order, [{ sku: 'A', qty: 2 }], ctx);
  const r2 = refundItems(order, [{ sku: 'A', qty: 1 }, { sku: 'B', qty: 2 }], ctx);
  assert.equal(r1.refundCents + r2.refundCents, order.totals.totalCents);
});

test('the same call twice in a row is the same as one call for both', () => {
  const lines = [{ sku: 'A', qty: 4, unitCents: 1250 }];
  const one = setup(lines, 'SAVE5', { A: 9 });
  const two = setup(lines, 'SAVE5', { A: 9 });
  const whole = refundItems(one.order, [{ sku: 'A', qty: 4 }], one.ctx).refundCents;
  const parts = refundItems(two.order, [{ sku: 'A', qty: 2 }], two.ctx).refundCents + refundItems(two.order, [{ sku: 'A', qty: 2 }], two.ctx).refundCents;
  assert.equal(parts, whole);
});
