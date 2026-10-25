// PB-HIDDEN-CANARY:pattern-03-second-screen
// Hidden FAIL_TO_PASS test: system messages (author null) on the order-detail screen.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { renderOrderMessages } = require('../src/views/orderDetail');

test('a system message renders as _text_', () => {
  assert.deepEqual(renderOrderMessages([{ author: null, text: 'Order shipped' }]), ['_Order shipped_']);
});

test('user and system messages keep their order', () => {
  assert.deepEqual(
    renderOrderMessages([{ author: { name: 'Alice' }, text: 'hi' }, { author: null, text: 'Order shipped' }]),
    ['Alice: hi', '_Order shipped_'],
  );
});
