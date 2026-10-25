// PB-HIDDEN-CANARY:pattern-07-idempotent-retry
// Hidden PASS_TO_PASS test: distinct events add up, an event without id throws, stores are independent.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createStore, handlePayment } = require('../src/webhook');

test('two distinct events are both credited', () => {
  const store = createStore();
  handlePayment(store, { id: 'evt_1', account: 'acc_a', amount: 100 });
  handlePayment(store, { id: 'evt_2', account: 'acc_a', amount: 50 });
  assert.equal(store.balance.acc_a, 150);
});

test('an event without id throws', () => {
  const store = createStore();
  assert.throws(() => handlePayment(store, { account: 'acc_a', amount: 10 }), Error);
});

test('two fresh stores each accept the same event id', () => {
  const first = createStore();
  const second = createStore();
  handlePayment(first, { id: 'evt_1', account: 'acc_a', amount: 100 });
  handlePayment(second, { id: 'evt_1', account: 'acc_a', amount: 100 });
  assert.equal(first.balance.acc_a, 100);
  assert.equal(second.balance.acc_a, 100);
});
