// PB-HIDDEN-CANARY:pattern-12-hidden-receipt
// Hidden PASS_TO_PASS test: the packing slip already uses displayName() and must keep doing so.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { packingSlipHeader } = require(path.join(__dirname, '..', 'src', 'docs', 'packingSlip.js'));

function shipTo(customer) {
  return packingSlipHeader({ id: 'ORD-7002', customer }).split('\n')[0];
}

test('the packing slip names the customer', () => {
  assert.equal(shipTo({ name: 'Tran Thi Lan', email: 'lan@example.com' }), 'Ship to: Tran Thi Lan');
});

test('the packing slip names the company when there is no name', () => {
  assert.equal(shipTo({ company: 'Hoa Sen Trading', email: 'ap@hoasen.example' }), 'Ship to: Hoa Sen Trading');
});
