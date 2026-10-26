// PB-HIDDEN-CANARY:pattern-11-date-parser-symptom
// Hidden PASS_TO_PASS test: the report prints a valid check-in Date as DD/MM/YYYY of its UTC day, in any time zone.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const RENDER = path.join(__dirname, '..', 'src', 'report', 'render.js');
const CHILD = [
  'const { renderRow } = require(process.argv[1]);',
  'const rows = JSON.parse(process.argv[2]).map((b) => renderRow({ ...b, checkIn: new Date(b.checkIn) }));',
  'process.stdout.write(JSON.stringify(rows));',
].join('\n');

const BOOKINGS = [
  { ref: 'B-2001', guest: 'An Le', checkIn: '2026-03-05T00:00:00.000Z', nights: 2 },
  { ref: 'W-0310', guest: 'Bao Vo', checkIn: '2026-12-31T00:00:00.000Z', nights: 1 },
];

function runUnder(tz) {
  const env = { ...process.env, TZ: tz };
  delete env.NODE_TEST_CONTEXT;
  const r = spawnSync(process.execPath, ['-e', CHILD, RENDER, JSON.stringify(BOOKINGS)], { env, encoding: 'utf8' });
  assert.equal(r.status, 0, `child under TZ=${tz} failed: ${r.stderr}`);
  return JSON.parse(r.stdout);
}

for (const tz of ['UTC', 'America/Los_Angeles']) {
  test(`report rows print the UTC calendar day under TZ=${tz}`, () => {
    const rows = runUnder(tz);
    assert.match(rows[0], /^B-2001\b/);
    assert.match(rows[0], /An Le/);
    assert.match(rows[0], /\b05\/03\/2026\b/);
    assert.match(rows[1], /\b31\/12\/2026\b/);
  });
}
