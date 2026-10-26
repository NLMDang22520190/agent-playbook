// PB-HIDDEN-CANARY:pattern-13-restore-value-label
// Hidden PASS_TO_PASS test: a value the product no longer has resets to the default choice; an unknown addon is dropped
// (docs/cart.md).
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { restoreCart } = require(path.join(__dirname, '..', 'src', 'cart', 'restore.js'));

const CATALOG = [
  {
    id: 'lamp',
    options: [{ name: 'shade', choices: [{ value: 'sh-lin', label: 'Linen' }, { value: 'sh-pap', label: 'Paper' }] }],
    addons: [{ value: 'bulb-led', label: 'LED bulb' }],
  },
];

test('a value the product no longer has resets to the first choice', () => {
  const out = restoreCart({ lines: [{ productId: 'lamp', options: { shade: 'sh-silk' }, addons: [] }] }, CATALOG);
  assert.deepEqual(out.lines[0].options, { shade: 'sh-lin' });
});

test('a missing option takes the first choice', () => {
  const out = restoreCart({ lines: [{ productId: 'lamp', options: {}, addons: [] }] }, CATALOG);
  assert.deepEqual(out.lines[0].options, { shade: 'sh-lin' });
});

test('an addon the product no longer has is dropped', () => {
  const out = restoreCart({ lines: [{ productId: 'lamp', options: {}, addons: ['gift-wrap'] }] }, CATALOG);
  assert.deepEqual(out.lines[0].addons, []);
});
