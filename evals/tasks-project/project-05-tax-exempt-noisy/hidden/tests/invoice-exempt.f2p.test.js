// PB-HIDDEN-CANARY:project-05-tax-exempt-noisy
// Hidden FAIL_TO_PASS test: docs/invoicing.md says the invoice shows the order's tax and total. The ticket does not mention it.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { loadConfig } = require('../src/config');
const { createInventory } = require('../src/inventory');
const { placeOrder } = require('../src/orders');
const { invoiceFor } = require('../src/invoice');

function order(cart) {
  const ctx = { inventory: createInventory({ A: 9 }), config: loadConfig(), now: new Date('2026-03-01T10:00:00Z') };
  return placeOrder(cart, ctx);
}

test('the invoice of a company order has no VAT and the order total', () => {
  const o = order({ lines: [{ sku: 'A', qty: 2, unitCents: 1000 }], coupon: null, customerType: 'company' });
  const inv = invoiceFor(o, loadConfig());
  assert.equal(inv.vatCents, 0);
  assert.equal(inv.totalCents, o.totals.totalCents);
  assert.equal(inv.totalCents, 2490);
});

test('the invoice of a company order with a coupon follows the order', () => {
  const o = order({ lines: [{ sku: 'A', qty: 2, unitCents: 3000 }], coupon: 'WELCOME10', customerType: 'company' });
  const inv = invoiceFor(o, loadConfig());
  assert.equal(inv.vatCents, 0);
  assert.equal(inv.totalCents, 5400);
});

test('the invoice of a consumer order is unchanged', () => {
  const o = order({ lines: [{ sku: 'A', qty: 2, unitCents: 1000 }], coupon: null });
  const inv = invoiceFor(o, loadConfig());
  assert.equal(inv.vatCents, 200);
  assert.equal(inv.totalCents, 2690);
});
