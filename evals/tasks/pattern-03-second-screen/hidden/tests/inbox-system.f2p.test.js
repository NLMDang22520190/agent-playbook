// PB-HIDDEN-CANARY:pattern-03-second-screen
// Hidden FAIL_TO_PASS test: the second screen (inbox) shows system messages the same way.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { renderInboxPreview } = require('../src/views/inbox');

test('a system message renders as _text_ in the inbox', () => {
  assert.deepEqual(renderInboxPreview([{ author: null, text: 'Order shipped' }]), ['_Order shipped_']);
});

test('user and system messages keep their order in the inbox', () => {
  assert.deepEqual(
    renderInboxPreview([{ author: { name: 'Alice' }, text: 'hi' }, { author: null, text: 'Order shipped' }]),
    ['Alice: hi', '_Order shipped_'],
  );
});
