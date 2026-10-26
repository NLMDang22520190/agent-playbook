// PB-HIDDEN-CANARY:pattern-16-negative-stock-not-a-bug
// Hidden PASS_TO_PASS test: a regular (not pre-order) item can never be reserved beyond what is available.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const { available, reserve } = require(path.join(__dirname, '..', 'src', 'stock.js'));

test('a regular item reports on hand minus reserved', () => {
  assert.equal(available({ sku: 'REG-100', onHand: 5, reserved: 2, preorder: false }), 3);
});

test('reserving a regular item beyond what is available throws an Error', () => {
  assert.throws(() => reserve({ sku: 'REG-100', onHand: 5, reserved: 2, preorder: false }, 4), Error);
});

test('reserving exactly what is available leaves zero', () => {
  const item = reserve({ sku: 'REG-100', onHand: 5, reserved: 2, preorder: false }, 3);
  assert.equal(available(item), 0);
});
