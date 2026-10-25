// PB-HIDDEN-CANARY:oss-02-version-compare
// Hidden FAIL_TO_PASS test: MAJOR.MINOR.PATCH parts compare as numbers; the result is exactly -1, 0 or 1.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { compare } = require('../src/semver');

function same(actual, expected) {
  assert.ok(actual === expected, `expected ${expected}, got ${actual}`);
}

test('1.10.0 is newer than 1.9.0', () => { same(compare('1.10.0', '1.9.0'), 1); });
test('1.9.0 is older than 1.10.0', () => { same(compare('1.9.0', '1.10.0'), -1); });
test('10.0.0 is newer than 2.0.0', () => { same(compare('10.0.0', '2.0.0'), 1); });
test('1.0.10 is newer than 1.0.9', () => { same(compare('1.0.10', '1.0.9'), 1); });
test('2.0.0 is newer than 1.99.99', () => { same(compare('2.0.0', '1.99.99'), 1); });
