// PB-HIDDEN-CANARY:pattern-02-dimension-text
// Hidden PASS_TO_PASS test: the plain form, decimals and the invalid inputs keep working.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { parseDims } = require('../src/dims');

test('plain lowercase x', () => {
  assert.deepEqual(parseDims('150x100x50'), { l: 150, w: 100, h: 50 });
});

test('decimal sizes stay numbers', () => {
  assert.deepEqual(parseDims('15.5x10x5'), { l: 15.5, w: 10, h: 5 });
});

test('two sizes are invalid', () => {
  assert.equal(parseDims('150x100'), null);
});

test('text is invalid', () => {
  assert.equal(parseDims('abc'), null);
});

test('a zero size is invalid', () => {
  assert.equal(parseDims('0x10x10'), null);
});
