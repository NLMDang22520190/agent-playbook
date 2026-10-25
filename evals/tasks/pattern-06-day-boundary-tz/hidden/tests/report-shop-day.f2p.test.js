// PB-HIDDEN-CANARY:pattern-06-day-boundary-tz
// Hidden FAIL_TO_PASS test: orders are keyed by the shop day (UTC+7, no DST), whatever the machine time zone is.
// Each time zone runs in its own child process with TZ set explicitly (spec "Test-portability rules").
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const MOD = path.join(__dirname, '..', 'src', 'report.js');
const CHILD = [
  'const m = require(process.argv[1]);',
  'const cases = JSON.parse(process.argv[2]);',
  'const out = cases.map((orders) => JSON.parse(JSON.stringify(m.dailyTotals(orders))));',
  'process.stdout.write(JSON.stringify(out));',
].join('\n');

const CASES = [
  [[{ at: '2026-03-01T23:30:00Z', amount: 1 }], { '2026-03-02': 1 }],
  [[{ at: '2026-03-01T16:59:59Z', amount: 1 }], { '2026-03-01': 1 }],
  [[{ at: '2026-03-01T17:00:00Z', amount: 1 }], { '2026-03-02': 1 }],
  [[{ at: '2026-02-28T17:00:00Z', amount: 1 }], { '2026-03-01': 1 }],
  [[{ at: '2025-12-31T18:00:00Z', amount: 1 }], { '2026-01-01': 1 }],
  [[{ at: '2026-03-01T18:00:00Z', amount: 100 }, { at: '2026-03-02T01:00:00Z', amount: 50 }], { '2026-03-02': 150 }],
];

function runUnder(tz) {
  const env = { ...process.env, TZ: tz };
  delete env.NODE_TEST_CONTEXT;
  const r = spawnSync(process.execPath, ['-e', CHILD, MOD, JSON.stringify(CASES.map((c) => c[0]))], { env, encoding: 'utf8' });
  assert.equal(r.status, 0, `child under TZ=${tz} failed: ${r.stderr}`);
  return JSON.parse(r.stdout);
}

for (const tz of ['UTC', 'Asia/Ho_Chi_Minh', 'America/New_York']) {
  test(`shop day keys under TZ=${tz}`, () => {
    assert.deepEqual(runUnder(tz), CASES.map((c) => c[1]));
  });
}
