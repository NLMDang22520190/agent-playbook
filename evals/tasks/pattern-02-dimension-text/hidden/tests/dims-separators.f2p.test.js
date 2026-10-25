// PB-HIDDEN-CANARY:pattern-02-dimension-text
// Hidden FAIL_TO_PASS test: the multiplication sign, spaced x and capital X are accepted separators.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { parseDims } = require('../src/dims');

const want = { l: 150, w: 100, h: 50 };

test('multiplication sign separators', () => {
  assert.deepEqual(parseDims('150×100×50'), want);
});

test('spaces around x', () => {
  assert.deepEqual(parseDims('150 x 100 x 50'), want);
});

test('capital X separators', () => {
  assert.deepEqual(parseDims('150X100X50'), want);
});
