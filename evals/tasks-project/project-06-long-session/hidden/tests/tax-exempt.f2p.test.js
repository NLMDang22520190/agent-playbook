// PB-HIDDEN-CANARY:project-06-long-session
// Hidden FAIL_TO_PASS test: a company order has no tax, a consumer order is unchanged.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { loadConfig } = require('../src/config');
const { createInventory } = require('../src/inventory');
const { placeOrder } = require('../src/orders');
const { priceOrder } = require('../src/pricing');

const cart = (extra) => Object.assign({ lines: [{ sku: 'A', qty: 2, unitCents: 1000 }], coupon: null }, extra);

test('a company pays no tax: total is the goods plus shipping', () => {
  const t = priceOrder(cart({ customerType: 'company' }), loadConfig());
  assert.equal(t.taxCents, 0);
  assert.equal(t.totalCents, 2000 + 490);
});

test('a consumer is unchanged', () => {
  const t = priceOrder(cart({ customerType: 'consumer' }), loadConfig());
  assert.deepEqual(t, { goodsCents: 2000, discountCents: 0, discountedCents: 2000, shippingCents: 490, taxCents: 200, totalCents: 2690 });
});

test('no customerType, or an unknown one, is a consumer', () => {
  assert.equal(priceOrder(cart({}), loadConfig()).taxCents, 200);
  assert.equal(priceOrder(cart({ customerType: 'reseller' }), loadConfig()).taxCents, 200);
});

test('a company with a coupon: coupon first, shipping free over the threshold, still no tax', () => {
  const t = priceOrder({ lines: [{ sku: 'A', qty: 2, unitCents: 3000 }], coupon: 'WELCOME10', customerType: 'company' }, loadConfig());
  assert.deepEqual(t, { goodsCents: 6000, discountCents: 600, discountedCents: 5400, shippingCents: 0, taxCents: 0, totalCents: 5400 });
});

test('the order keeps the customer type, consumer by default', () => {
  const ctx = { inventory: createInventory({ A: 9 }), config: loadConfig(), now: new Date('2026-03-01T10:00:00Z') };
  assert.equal(placeOrder(cart({ customerType: 'company' }), ctx).customerType, 'company');
  assert.equal(placeOrder(cart({}), ctx).customerType, 'consumer');
  assert.equal(placeOrder(cart({ customerType: 'reseller' }), ctx).customerType, 'consumer');
});
