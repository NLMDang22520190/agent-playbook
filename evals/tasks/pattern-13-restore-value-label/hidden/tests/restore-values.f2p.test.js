// PB-HIDDEN-CANARY:pattern-13-restore-value-label
// Hidden FAIL_TO_PASS test: saved carts store choice values and addon values (docs/cart.md), so a restore matches on
// value. This file builds its own catalog whose values differ from their labels; a value == label fixture hides the bug.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { restoreCart } = require(path.join(__dirname, '..', 'src', 'cart', 'restore.js'));

const CATALOG = [
  {
    id: 'desk',
    options: [
      { name: 'size', choices: [{ value: 'w120', label: '120 × 60 cm' }, { value: 'w140', label: '140 × 70 cm' }] },
      { name: 'finish', choices: [{ value: 'oak-nat', label: 'Natural oak' }, { value: 'walnut', label: 'Dark walnut' }] },
    ],
    addons: [{ value: 'cable-tray', label: 'Cable tray' }, { value: 'monitor-arm', label: 'Monitor arm' }],
  },
];

function restoreOne(options, addons) {
  return restoreCart({ lines: [{ productId: 'desk', options, addons }] }, CATALOG).lines[0];
}

test('saved option values are kept (non-default size and finish)', () => {
  assert.deepEqual(restoreOne({ size: 'w140', finish: 'walnut' }, []).options, { size: 'w140', finish: 'walnut' });
});

test('saved addon values are kept, in order', () => {
  assert.deepEqual(restoreOne({ size: 'w120', finish: 'oak-nat' }, ['monitor-arm', 'cable-tray']).addons,
    ['monitor-arm', 'cable-tray']);
});

test('a label saved where a value belongs is not a value: the option resets to the default choice', () => {
  assert.deepEqual(restoreOne({ size: '140 × 70 cm', finish: 'Dark walnut' }, []).options, { size: 'w120', finish: 'oak-nat' });
});

test('an addon label saved where a value belongs is dropped', () => {
  assert.deepEqual(restoreOne({ size: 'w120', finish: 'oak-nat' }, ['Monitor arm']).addons, []);
});

test('the restored line keeps its product id', () => {
  assert.equal(restoreOne({ size: 'w140', finish: 'walnut' }, ['cable-tray']).productId, 'desk');
});
