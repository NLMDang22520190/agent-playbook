// PB-HIDDEN-CANARY:pattern-11-date-parser-symptom
// Hidden FAIL_TO_PASS test: partner CSV dates are DD/MM/YYYY and a check-in is stored as a Date at 00:00 UTC of that
// calendar day, the same as web bookings (docs/import.md), whatever the machine time zone is.
// Each time zone runs in its own child process with TZ set explicitly (as pattern-06 does).
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const DATES = path.join(__dirname, '..', 'src', 'import', 'dates.js');
const CSV = path.join(__dirname, '..', 'src', 'import', 'partnerCsv.js');
const CHILD = [
  'const { parseDate } = require(process.argv[1]);',
  'const { parseRow } = require(process.argv[2]);',
  'const iso = (d) => (d instanceof Date && !Number.isNaN(d.getTime()) ? d.toISOString() : String(d));',
  'const dates = JSON.parse(process.argv[3]).map((s) => iso(parseDate(s)));',
  'const rows = JSON.parse(process.argv[4]).map((l) => { const r = parseRow(l); return { ref: r.ref, guest: r.guest, checkIn: iso(r.checkIn), nights: r.nights }; });',
  'process.stdout.write(JSON.stringify({ dates, rows }));',
].join('\n');

const DATE_CASES = [
  ['13/03/2026', '2026-03-13T00:00:00.000Z'],
  ['05/03/2026', '2026-03-05T00:00:00.000Z'],
  ['01/02/2026', '2026-02-01T00:00:00.000Z'],
  ['31/12/2026', '2026-12-31T00:00:00.000Z'],
];
const ROW_CASES = [
  ['B-1043;Lan Pham;13/03/2026;2', { ref: 'B-1043', guest: 'Lan Pham', checkIn: '2026-03-13T00:00:00.000Z', nights: 2 }],
  ['B-1044;Minh Tran;05/03/2026;3', { ref: 'B-1044', guest: 'Minh Tran', checkIn: '2026-03-05T00:00:00.000Z', nights: 3 }],
];

function runUnder(tz) {
  const env = { ...process.env, TZ: tz };
  delete env.NODE_TEST_CONTEXT;
  const r = spawnSync(process.execPath, ['-e', CHILD, DATES, CSV,
    JSON.stringify(DATE_CASES.map((c) => c[0])), JSON.stringify(ROW_CASES.map((c) => c[0]))], { env, encoding: 'utf8' });
  assert.equal(r.status, 0, `child under TZ=${tz} failed: ${r.stderr}`);
  return JSON.parse(r.stdout);
}

for (const tz of ['UTC', 'Asia/Ho_Chi_Minh', 'America/Los_Angeles']) {
  test(`partner DD/MM/YYYY dates become 00:00 UTC of that day under TZ=${tz}`, () => {
    assert.deepEqual(runUnder(tz).dates, DATE_CASES.map((c) => c[1]));
  });

  test(`partner rows keep the check-in day under TZ=${tz}`, () => {
    assert.deepEqual(runUnder(tz).rows, ROW_CASES.map((c) => c[1]));
  });
}
