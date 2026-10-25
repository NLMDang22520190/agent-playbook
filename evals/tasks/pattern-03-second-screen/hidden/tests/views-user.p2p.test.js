// PB-HIDDEN-CANARY:pattern-03-second-screen
// Hidden PASS_TO_PASS test: user messages render as "Name: text" on both screens.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { renderOrderMessages } = require('../src/views/orderDetail');
const { renderInboxPreview } = require('../src/views/inbox');

test('order detail shows a user message', () => {
  assert.deepEqual(renderOrderMessages([{ author: { name: 'Alice' }, text: 'hi' }]), ['Alice: hi']);
});

test('inbox shows a user message', () => {
  assert.deepEqual(renderInboxPreview([{ author: { name: 'Alice' }, text: 'hi' }]), ['Alice: hi']);
});
