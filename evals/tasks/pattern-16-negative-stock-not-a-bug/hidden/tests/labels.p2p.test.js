// PB-HIDDEN-CANARY:pattern-16-negative-stock-not-a-bug
// Hidden PASS_TO_PASS test: the dashboard and the export show the signed number; the warehouse import parses it
// (docs/inventory.md), so neither may hide the minus sign.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const { stockLabel } = require(path.join(__dirname, '..', 'src', 'dashboard.js'));
const { stockCsvLine } = require(path.join(__dirname, '..', 'src', 'export.js'));

const PRE = { sku: 'PRE-204', onHand: 2, reserved: 5, preorder: true };
const REG = { sku: 'REG-100', onHand: 5, reserved: 2, preorder: false };

test('the dashboard label keeps the sign of a backordered pre-order item', () => {
  assert.equal(stockLabel(PRE), '-3 in stock');
});

test('the CSV export line keeps the sign of a backordered pre-order item', () => {
  assert.equal(stockCsvLine(PRE), 'PRE-204;-3');
});

test('a regular item shows its positive stock in both places', () => {
  assert.equal(stockLabel(REG), '3 in stock');
  assert.equal(stockCsvLine(REG), 'REG-100;3');
});
