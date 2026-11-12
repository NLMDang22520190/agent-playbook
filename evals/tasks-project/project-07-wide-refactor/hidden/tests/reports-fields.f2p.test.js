// PB-HIDDEN-CANARY:project-07-wide-refactor
// Hidden FAIL_TO_PASS test, ticket REP-32: the row field is totalCents everywhere rows are made or read.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { MODULES, runAll } = require('../src/reports');

const REF = {
  money(c) {
    const a = Math.abs(c);
    const dollars = String(Math.floor(a / 100)).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    return (c < 0 ? '-' : '') + '$' + dollars + '.' + String(a % 100).padStart(2, '0');
  },
  line(style, r) {
    const m = REF.money(r.totalCents);
    if (style === 'list') return r.name + ': ' + m + ' (' + r.qty + ')';
    if (style === 'table') return '| ' + r.name + ' | ' + m + ' | ' + r.qty + ' |';
    return r.qty + ' x ' + r.name + ' = ' + m;
  },
  // the lines of a report after its header
  body(meta, rows) {
    return rows.map((r) => REF.line(meta.style, r)).concat(['Total: ' + REF.money(rows.reduce((s, r) => s + r.totalCents, 0))]);
  },
  rowsFrom(orders) {
    const by = new Map();
    for (const o of orders) for (const l of o.lines) {
      const r = by.get(l.sku) || { sku: l.sku, name: l.name, qty: 0, totalCents: 0 };
      r.qty += l.qty; r.totalCents += l.qty * l.unitCents; by.set(l.sku, r);
    }
    return [...by.values()].sort((a, b) => (a.sku < b.sku ? -1 : 1));
  },
};
const ROWS = [
  { sku: 'A1', name: 'Shirt', qty: 3, totalCents: 123456789 },
  { sku: 'B2', name: 'Mug', qty: -1, totalCents: -250 },
  { sku: 'C3', name: 'Pin', qty: 7, totalCents: 5 },
  { sku: 'D4', name: 'Zero', qty: 0, totalCents: 0 },
  { sku: 'E5', name: 'Big', qty: 1, totalCents: 100000 },
  { sku: 'F6', name: 'Refund', qty: -2, totalCents: -123456 },
];
const ORDERS = [
  { id: 1, lines: [{ sku: 'A1', name: 'Shirt', qty: 2, unitCents: 1999 }, { sku: 'B2', name: 'Mug', qty: 1, unitCents: 850 }] },
  { id: 2, lines: [{ sku: 'A1', name: 'Shirt', qty: 3, unitCents: 1999 }, { sku: 'C3', name: 'Pin', qty: 4, unitCents: 325 }] },
  { id: 3, lines: [{ sku: 'B2', name: 'Mug', qty: -1, unitCents: 850 }, { sku: 'D4', name: 'Lamp', qty: 12, unitCents: 99999 }] },
];
const NOW = new Date('2026-03-01T10:00:00Z');
const REPORT_FILES = () => fs.readdirSync(path.join(__dirname, '..', 'src', 'reports')).filter((f) => f.endsWith('.js')).map((f) => path.join(__dirname, '..', 'src', 'reports', f));

test('rowsFrom makes totalCents rows', () => {
  const { rowsFrom } = require('../src/reports');
  assert.deepEqual(rowsFrom(ORDERS), REF.rowsFrom(ORDERS));
});

test('no report reads the old total field', () => {
  for (const f of REPORT_FILES()) {
    const src = fs.readFileSync(f, 'utf8');
    assert.ok(!/\.total\b/.test(src), path.basename(f) + ' still reads .total');
  }
});

test('runAll shows the sums of the orders in every report', () => {
  const out = runAll(ORDERS, { now: NOW });
  const rows = REF.rowsFrom(ORDERS);
  for (const m of MODULES) assert.deepEqual(out[m.meta.id].split('\n').slice(1), REF.body(m.meta, rows), m.meta.id);
});
