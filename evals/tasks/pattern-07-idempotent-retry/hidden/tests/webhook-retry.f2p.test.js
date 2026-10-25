// PB-HIDDEN-CANARY:pattern-07-idempotent-retry
// Hidden FAIL_TO_PASS test: a retried webhook (same event id, a new object each delivery) credits once.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createStore, handlePayment } = require('../src/webhook');

test('the same event delivered twice credits once', () => {
  const store = createStore();
  handlePayment(store, { id: 'evt_1', account: 'acc_a', amount: 100 });
  handlePayment(store, { id: 'evt_1', account: 'acc_a', amount: 100 });
  assert.equal(store.balance.acc_a, 100);
});

test('a retry after another event still credits once', () => {
  const store = createStore();
  handlePayment(store, { id: 'evt_1', account: 'acc_a', amount: 100 });
  handlePayment(store, { id: 'evt_2', account: 'acc_a', amount: 50 });
  handlePayment(store, { id: 'evt_1', account: 'acc_a', amount: 100 });
  assert.equal(store.balance.acc_a, 150);
});
