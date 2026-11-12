// PB-HIDDEN-CANARY:project-07-wide-refactor
// Hidden FAIL_TO_PASS test, ticket REP-33: every report starts with its title and the generation date taken from ctx.now (docs/reports.md).
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { MODULES, runAll } = require('../src/reports');

const NOW1 = new Date('2026-03-01T10:00:00Z');
const NOW2 = new Date('2026-12-31T23:59:59Z');
const ROWS = [{ sku: 'A1', name: 'Shirt', qty: 1, totalCents: 1999 }];

for (const m of MODULES) {
  test('header of ' + m.meta.id, () => {
    assert.equal(m.render(ROWS, { now: NOW1 }).split('\n')[0], '# ' + m.meta.title + ' (generated 2026-03-01)');
    assert.equal(m.render(ROWS, { now: NOW2 }).split('\n')[0], '# ' + m.meta.title + ' (generated 2026-12-31)');
  });
}

test('runAll passes ctx.now on to the reports', () => {
  const out = runAll([{ id: 1, lines: [{ sku: 'A1', name: 'Shirt', qty: 1, unitCents: 1999 }] }], { now: NOW2 });
  for (const m of MODULES) assert.ok(out[m.meta.id].startsWith('# ' + m.meta.title + ' (generated 2026-12-31)'));
});

test('no report reads the clock', () => {
  const dir = path.join(__dirname, '..', 'src', 'reports');
  for (const f of fs.readdirSync(dir).filter((x) => x.endsWith('.js'))) {
    const src = fs.readFileSync(path.join(dir, f), 'utf8');
    assert.ok(!/new Date\(\s*\)|Date\.now\(/.test(src), f + ' reads the clock');
  }
});
