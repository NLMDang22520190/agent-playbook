// PB-HIDDEN-CANARY:pattern-10-cents-three-files
// Hidden FAIL_TO_PASS test: tax returns whole cents, rounded half up to the cent
// (docs/money.md "rounded half up to the cent").
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { taxCents } = require(path.join(__dirname, '..', 'src', 'tax.js'));

test('8% of 44.99 is 3.60 (359.92 cents rounds to 360)', () => {
  assert.equal(taxCents(4499, 8), 360);
});

test('10% of 12.25 is 1.23: half a cent rounds up, not to even', () => {
  assert.equal(taxCents(1225, 10), 123);
});

test('8% of 50.00 is exactly 4.00', () => {
  assert.equal(taxCents(5000, 8), 400);
});

test('the result is an integer number of cents', () => {
  assert.ok(Number.isInteger(taxCents(4999, 8)));
});
