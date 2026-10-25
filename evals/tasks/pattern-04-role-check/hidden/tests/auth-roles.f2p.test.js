// PB-HIDDEN-CANARY:pattern-04-role-check
// Hidden FAIL_TO_PASS test: only admin and staff cancel any order; unknown roles and no user are refused.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { canCancel } = require('../src/auth');

const order = { ownerId: 'u1' };

test('a viewer cannot cancel an order', () => {
  assert.equal(canCancel({ id: 'u2', role: 'viewer' }, order), false);
});

test('an unknown role (guest) cannot cancel an order', () => {
  assert.equal(canCancel({ id: 'u3', role: 'guest' }, order), false);
});

test('no user cannot cancel an order', () => {
  assert.equal(canCancel(null, order), false);
});
