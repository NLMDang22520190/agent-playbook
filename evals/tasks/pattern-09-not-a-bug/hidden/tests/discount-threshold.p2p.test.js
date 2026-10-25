// PB-HIDDEN-CANARY:pattern-09-not-a-bug
// Hidden PASS_TO_PASS test: 10% off from 100 pieces, as docs/pricing.md says. Nothing here should change.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { orderTotal } = require('../src/discount');

function near(actual, expected) {
  assert.equal(typeof actual, 'number');
  assert.ok(Math.abs(actual - expected) < 1e-9, `expected ${expected}, got ${actual}`);
}

test('99 pieces get no discount', () => {
  near(orderTotal(99, 10), 990);
});

test('100 pieces get 10% off', () => {
  near(orderTotal(100, 10), 900);
});

test('101 pieces get 10% off', () => {
  near(orderTotal(101, 10), 909);
});
