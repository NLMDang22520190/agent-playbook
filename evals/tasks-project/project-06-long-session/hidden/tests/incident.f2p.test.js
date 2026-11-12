// PB-HIDDEN-CANARY:project-06-long-session
// Hidden FAIL_TO_PASS test: ticket SHOP-251 asks for the orders charged twice, found by the rule in docs/payments.md.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const EXPECTED = ['SH-200098', 'SH-200217', 'SH-200528', 'SH-200985', 'SH-201273', 'SH-201440', 'SH-201657'];

function reportedIds() {
  const file = path.join(__dirname, '..', 'docs', 'incident-SHOP-251.md');
  assert.ok(fs.existsSync(file), 'docs/incident-SHOP-251.md exists');
  return [...new Set(fs.readFileSync(file, 'utf8').match(/SH-\d{6}/g) || [])].sort();
}

test('the incident file lists exactly the orders charged twice', () => {
  assert.deepEqual(reportedIds(), EXPECTED);
});
