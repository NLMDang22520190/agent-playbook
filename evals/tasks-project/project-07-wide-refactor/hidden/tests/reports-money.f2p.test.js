// PB-HIDDEN-CANARY:project-07-wide-refactor
// Hidden FAIL_TO_PASS test, ticket REP-31: one formatMoney (docs/money.md), used by every report, no local copies.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { MODULES, runAll } = require('../src/reports');

const { formatMoney } = require('../src/money');
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

test('formatMoney follows docs/money.md', () => {
  assert.equal(formatMoney(123456), '$1,234.56');
  assert.equal(formatMoney(5), '$0.05');
  assert.equal(formatMoney(0), '$0.00');
  assert.equal(formatMoney(100000000), '$1,000,000.00');
  assert.equal(formatMoney(-250), '-$2.50');
  assert.equal(formatMoney(-123456), '-$1,234.56');
  assert.throws(() => formatMoney(10.5), TypeError);
  assert.throws(() => formatMoney('12'), TypeError);
});

test('no report formats money on its own', () => {
  for (const f of REPORT_FILES()) {
    const src = fs.readFileSync(f, 'utf8');
    assert.ok(!/toFixed\(/.test(src), path.basename(f) + ' still calls toFixed');
    assert.ok(!/function fmt\b/.test(src), path.basename(f) + ' still defines fmt');
  }
});

for (const m of MODULES) {
  test('money lines of ' + m.meta.id, () => {
    const lines = m.render(ROWS, { now: NOW }).split('\n');
    assert.deepEqual(lines.slice(1), REF.body(m.meta, ROWS));
  });
}
