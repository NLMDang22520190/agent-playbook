// PB-HIDDEN-CANARY:pattern-10-cents-three-files
// Hidden FAIL_TO_PASS test: shipping rules are decimal strings in major units; shipping is free from 50.00 of goods
// (docs/money.md "shipping is free from 50.00"; the prompt says the same).
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { shippingCents } = require(path.join(__dirname, '..', 'src', 'shipping.js'));

const RULES = { flat: '4.90', free_over: '50.00' };

test('below the threshold: 49.99 pays the flat 4.90', () => {
  assert.equal(shippingCents(4999, RULES), 490);
});

test('at the threshold: 50.00 ships free', () => {
  assert.equal(shippingCents(5000, RULES), 0);
});

test('above the threshold: 50.01 ships free', () => {
  assert.equal(shippingCents(5001, RULES), 0);
});

test('a small order pays the flat rate of its own rules', () => {
  assert.equal(shippingCents(1000, { flat: '3.25', free_over: '20.00' }), 325);
});
