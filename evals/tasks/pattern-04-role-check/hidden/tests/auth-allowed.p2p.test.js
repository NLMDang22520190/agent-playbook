// PB-HIDDEN-CANARY:pattern-04-role-check
// Hidden PASS_TO_PASS test: admin and staff cancel any order, a customer only their own.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { canCancel } = require('../src/auth');

const order = { ownerId: 'u1' };

test('admin cancels any order', () => {
  assert.equal(canCancel({ id: 'a1', role: 'admin' }, order), true);
});

test('staff cancels any order', () => {
  assert.equal(canCancel({ id: 's1', role: 'staff' }, order), true);
});

test('a customer cancels their own order', () => {
  assert.equal(canCancel({ id: 'u1', role: 'customer' }, order), true);
});

test("a customer cannot cancel another customer's order", () => {
  assert.equal(canCancel({ id: 'u9', role: 'customer' }, order), false);
});
