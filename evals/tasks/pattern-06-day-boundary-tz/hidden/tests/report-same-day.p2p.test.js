// PB-HIDDEN-CANARY:pattern-06-day-boundary-tz
// Hidden PASS_TO_PASS test: midday orders keep their day and amounts are summed per day.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { dailyTotals } = require('../src/report');

function plain(x) { return JSON.parse(JSON.stringify(x)); }

test('a midday order keeps its date', () => {
  assert.deepEqual(plain(dailyTotals([{ at: '2026-03-01T05:00:00Z', amount: 100 }])), { '2026-03-01': 100 });
});

test('amounts are summed per day', () => {
  const orders = [
    { at: '2026-03-01T05:00:00Z', amount: 100 },
    { at: '2026-03-01T06:00:00Z', amount: 50 },
    { at: '2026-03-02T05:00:00Z', amount: 20 },
  ];
  assert.deepEqual(plain(dailyTotals(orders)), { '2026-03-01': 150, '2026-03-02': 20 });
});
