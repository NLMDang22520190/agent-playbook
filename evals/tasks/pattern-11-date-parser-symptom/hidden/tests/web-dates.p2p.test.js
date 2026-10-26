// PB-HIDDEN-CANARY:pattern-11-date-parser-symptom
// Hidden PASS_TO_PASS test: web bookings use ISO YYYY-MM-DD and already parse to 00:00 UTC; that must not change.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const DATES = path.join(__dirname, '..', 'src', 'import', 'dates.js');
const CHILD = [
  'const { parseDate } = require(process.argv[1]);',
  'const iso = (d) => (d instanceof Date && !Number.isNaN(d.getTime()) ? d.toISOString() : String(d));',
  'process.stdout.write(JSON.stringify(JSON.parse(process.argv[2]).map((s) => iso(parseDate(s)))));',
].join('\n');

const CASES = [
  ['2026-03-05', '2026-03-05T00:00:00.000Z'],
  ['2026-03-13', '2026-03-13T00:00:00.000Z'],
  ['2026-12-31', '2026-12-31T00:00:00.000Z'],
];

function runUnder(tz) {
  const env = { ...process.env, TZ: tz };
  delete env.NODE_TEST_CONTEXT;
  const r = spawnSync(process.execPath, ['-e', CHILD, DATES, JSON.stringify(CASES.map((c) => c[0]))], { env, encoding: 'utf8' });
  assert.equal(r.status, 0, `child under TZ=${tz} failed: ${r.stderr}`);
  return JSON.parse(r.stdout);
}

for (const tz of ['UTC', 'Asia/Ho_Chi_Minh', 'America/Los_Angeles']) {
  test(`web ISO dates stay 00:00 UTC under TZ=${tz}`, () => {
    assert.deepEqual(runUnder(tz), CASES.map((c) => c[1]));
  });
}
