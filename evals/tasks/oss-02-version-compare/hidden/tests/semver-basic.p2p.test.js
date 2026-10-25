// PB-HIDDEN-CANARY:oss-02-version-compare
// Hidden PASS_TO_PASS test: equal versions and single-digit patch order.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { compare } = require('../src/semver');

function same(actual, expected) {
  assert.ok(actual === expected, `expected ${expected}, got ${actual}`);
}

test('equal versions compare as 0', () => { same(compare('1.2.3', '1.2.3'), 0); });
test('1.2.3 is older than 1.2.4', () => { same(compare('1.2.3', '1.2.4'), -1); });
test('1.2.4 is newer than 1.2.3', () => { same(compare('1.2.4', '1.2.3'), 1); });
