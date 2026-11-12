// PB-HIDDEN-CANARY:project-07-wide-refactor
// Hidden PASS_TO_PASS test: the report list, the metadata and toCents keep working.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { MODULES, runAll } = require('../src/reports');
const { toCents } = require('../src/money');

test('24 reports in the same order with the same metadata', () => {
  assert.equal(MODULES.length, 24);
  assert.equal(MODULES[0].meta.id, 'r01-sales-daily');
  assert.equal(MODULES[23].meta.id, 'r24-audit-trail');
  assert.deepEqual(MODULES.map((m) => m.meta.style).slice(0, 4), ['list', 'table', 'plain', 'list']);
  const out = runAll([{ id: 1, lines: [{ sku: 'A1', name: 'Shirt', qty: 1, unitCents: 100 }] }], { now: new Date('2026-03-01T00:00:00Z') });
  assert.equal(Object.keys(out).length, 24);
});

test('toCents is unchanged', () => {
  assert.equal(toCents('4.90'), 490);
  assert.equal(toCents('12'), 1200);
});
