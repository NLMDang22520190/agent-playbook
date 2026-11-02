// PB-HIDDEN-CANARY:pattern-36-shipping-incident
// Hidden PASS_TO_PASS test: single-line orders were charged correctly before and after the fix (docs/shipping.md):
// standard 30000, express 30000 + 20000, and orderTotal = goods total + shipping.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const SRC = path.join(__dirname, '..', 'src');
const { shippingFee } = require(path.join(SRC, 'shipping.js'));
const { orderTotal } = require(path.join(SRC, 'orders.js'));

const order = (id, express, qty, priceVnd) => ({ id, express, lines: [{ sku: 'SKU-' + id, qty, priceVnd }] });

test('AC a single-line standard order pays 30000', () => {
  assert.equal(shippingFee(order('DH-2001', false, 3, 40000)), 30000);
});

test('AC a single-line express order pays 50000', () => {
  assert.equal(shippingFee(order('DH-2002', true, 1, 175000)), 50000);
});

test('AC orderTotal of a single-line order is goods plus shipping', () => {
  assert.equal(orderTotal(order('DH-2003', false, 2, 75000)), 180000);
  assert.equal(orderTotal(order('DH-2004', true, 1, 175000)), 225000);
});
