// PB-HIDDEN-CANARY:pattern-16-negative-stock-not-a-bug
// Hidden PASS_TO_PASS test: a pre-order item may go below zero; -3 means three units are backordered (docs/inventory.md).
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const { available, reserve } = require(path.join(__dirname, '..', 'src', 'stock.js'));

test('a pre-order item with more reserved than on hand reports the signed shortfall', () => {
  assert.equal(available({ sku: 'PRE-204', onHand: 2, reserved: 5, preorder: true }), -3);
});

test('reserving a pre-order item beyond its stock is allowed and goes negative', () => {
  const item = reserve({ sku: 'PRE-310', onHand: 1, reserved: 0, preorder: true }, 4);
  assert.equal(available(item), -3);
  assert.equal(item.reserved, 4);
});

test('reserving a pre-order item that is already backordered keeps counting down', () => {
  const item = reserve({ sku: 'PRE-204', onHand: 2, reserved: 5, preorder: true }, 2);
  assert.equal(available(item), -5);
});
