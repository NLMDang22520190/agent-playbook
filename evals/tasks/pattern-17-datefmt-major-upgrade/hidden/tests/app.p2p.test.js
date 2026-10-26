// PB-HIDDEN-CANARY:pattern-17-datefmt-major-upgrade
// Hidden PASS_TO_PASS test: valid dates are formatted and parsed the same on datefmt 1.4.0 and 2.0.0 (TZ=UTC in a child
// process, so the machine time zone cannot matter).
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const ROOT = path.join(__dirname, '..');
const SRC = path.join(ROOT, 'src');

const CHILD = [
  'const src = process.argv[1];',
  "const { invoiceDate } = require(src + '/invoice.js');",
  "const { stampUtc } = require(src + '/report.js');",
  "const { parseDueDate } = require(src + '/api.js');",
  'const out = {',
  "  invoice: [invoiceDate(new Date('2026-03-01T20:00:00Z')), invoiceDate(new Date('2026-12-31T23:59:00Z'))],",
  "  stamp: [stampUtc(new Date('2026-03-01T20:00:00Z')), stampUtc(new Date('2026-07-04T05:07:00Z'))],",
  "  due: parseDueDate('2026-03-15').toISOString(),",
  '};',
  'process.stdout.write(JSON.stringify(out));',
].join('\n');

test('invoice dates, report stamps and due dates of valid input under TZ=UTC', () => {
  const env = { ...process.env, TZ: 'UTC' };
  delete env.NODE_TEST_CONTEXT;
  const r = spawnSync(process.execPath, ['-e', CHILD, SRC], { cwd: ROOT, env, encoding: 'utf8' });
  assert.equal(r.status, 0, `child failed: ${r.stderr}`);
  assert.deepEqual(JSON.parse(r.stdout), {
    invoice: ['01/03/2026', '31/12/2026'],
    stamp: ['2026-03-01 20:00', '2026-07-04 05:07'],
    due: '2026-03-15T00:00:00.000Z',
  });
});
