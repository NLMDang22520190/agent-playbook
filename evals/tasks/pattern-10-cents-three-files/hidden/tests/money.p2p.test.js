// PB-HIDDEN-CANARY:pattern-10-cents-three-files
// Hidden PASS_TO_PASS test: the money helpers and percent coupons were right before the bug and must stay right.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { toCents, formatCents } = require(path.join(__dirname, '..', 'src', 'money.js'));
const { applyCoupon } = require(path.join(__dirname, '..', 'src', 'coupons.js'));

test('toCents reads decimal strings in major units', () => {
  assert.equal(toCents('4.90'), 490);
  assert.equal(toCents('50.00'), 5000);
  assert.equal(toCents('0.07'), 7);
  assert.equal(toCents('12'), 1200);
});

test('formatCents prints major units with two decimals', () => {
  assert.equal(formatCents(5349), '53.49');
  assert.equal(formatCents(5), '0.05');
  assert.equal(formatCents(5000), '50.00');
});

test('a percent coupon takes its percentage of the subtotal', () => {
  assert.equal(applyCoupon(5000, 'WELCOME10', { WELCOME10: { type: 'percent', percent: 10 } }), 4500);
});

test('no coupon code leaves the subtotal unchanged', () => {
  assert.equal(applyCoupon(4999, undefined, { SAVE5: { type: 'fixed', amount: '5.00' } }), 4999);
});
