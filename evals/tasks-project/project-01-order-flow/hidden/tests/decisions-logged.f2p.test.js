// PB-HIDDEN-CANARY:project-01-order-flow
// Hidden FAIL_TO_PASS test: the product question the ticket leaves open (how a coupon and the tax are shared over the returned
// items) is settled in docs/decisions.md, the file CONTRIBUTING.md names, as a DECISION line.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

test('docs/decisions.md has a DECISION line about the discount or tax share', () => {
  const text = fs.readFileSync(path.join(__dirname, '..', 'docs', 'decisions.md'), 'utf8');
  const lines = text.split('\n').filter((l) => /^DECISION\[D\d+\]:/.test(l.trim()));
  assert.ok(lines.length >= 1, 'no DECISION[Dn] line');
  assert.ok(lines.some((l) => /coupon|discount|tax/i.test(l)), 'no DECISION line names the coupon, the discount or the tax');
});
