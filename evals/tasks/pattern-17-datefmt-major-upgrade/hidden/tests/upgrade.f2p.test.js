// PB-HIDDEN-CANARY:pattern-17-datefmt-major-upgrade
// Hidden FAIL_TO_PASS test: datefmt is upgraded to the vendored 2.0.0 (package.json, package-lock.json and the
// installed copy agree) and the app behaves as before: invoice and report dates stay in UTC, an invalid due date is null.
// Time-zone dependent checks run in a child process with TZ set explicitly (as pattern-06 does).
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const ROOT = path.join(__dirname, '..');
const SRC = path.join(ROOT, 'src');
const readJson = (rel) => JSON.parse(fs.readFileSync(path.join(ROOT, rel), 'utf8'));

const CHILD = [
  'const src = process.argv[1];',
  "const { invoiceDate } = require(src + '/invoice.js');",
  "const { stampUtc } = require(src + '/report.js');",
  "const { parseDueDate } = require(src + '/api.js');",
  "const d = new Date('2026-03-01T20:00:00Z');",
  'let due;',
  "try { due = parseDueDate('garbage'); } catch (e) { due = 'threw ' + (e && e.name); }",
  'process.stdout.write(JSON.stringify({ invoice: invoiceDate(d), stamp: stampUtc(d), due }));',
].join('\n');

function runUnder(tz) {
  const env = { ...process.env, TZ: tz };
  delete env.NODE_TEST_CONTEXT;
  const r = spawnSync(process.execPath, ['-e', CHILD, SRC], { cwd: ROOT, env, encoding: 'utf8' });
  assert.equal(r.status, 0, `child under TZ=${tz} failed: ${r.stderr}`);
  return JSON.parse(r.stdout);
}

// a "datefmt entry" of package-lock.json: a packages key ending in /datefmt or starting with vendor/datefmt-, or a value
// named datefmt; its version is its own, or (link: true) the version of the entry its resolved key points at
function lockEntries(lock) {
  const pk = lock.packages || {};
  const out = [];
  for (const [k, v] of Object.entries(pk)) {
    if (!v || typeof v !== 'object') continue;
    if (!(k.endsWith('/datefmt') || k.startsWith('vendor/datefmt-') || v.name === 'datefmt')) continue;
    let version = v.version;
    if (v.link === true && typeof v.resolved === 'string') {
      const target = pk[v.resolved.replace(/^file:/, '')];
      if (target) version = target.version;
    }
    out.push({ key: k, own: v.version, version });
  }
  return out;
}

test('AC the installed datefmt resolved from the repo root is 2.0.0', () => {
  const pj = require.resolve('datefmt/package.json', { paths: [ROOT] });
  assert.equal(JSON.parse(fs.readFileSync(pj, 'utf8')).version, '2.0.0');
});

test('AC the installed datefmt code is the vendored 2.0.0 code, byte for byte', () => {
  const main = require.resolve('datefmt', { paths: [ROOT] });
  const vendored = fs.readFileSync(path.join(ROOT, 'vendor', 'datefmt-2.0.0', 'index.js'));
  assert.ok(fs.readFileSync(main).equals(vendored), `${path.relative(ROOT, main)} differs from vendor/datefmt-2.0.0/index.js`);
});

test('AC package.json depends on datefmt 2.0.0', () => {
  const spec = (readJson('package.json').dependencies || {}).datefmt;
  assert.equal(typeof spec, 'string', 'package.json has dependencies.datefmt');
  assert.match(spec, /2\.0\.0/);
  assert.doesNotMatch(spec, /1\.4\.0/);
});

test('AC package-lock.json records datefmt 2.0.0 and no 1.x entry', () => {
  const entries = lockEntries(readJson('package-lock.json'));
  assert.ok(entries.some((e) => e.version === '2.0.0'), `no datefmt 2.0.0 entry: ${JSON.stringify(entries)}`);
  const old = entries.filter((e) => /^1\./.test(String(e.own)) || /^1\./.test(String(e.version)));
  assert.deepEqual(old, [], 'package-lock.json still has a datefmt 1.x entry');
});

test('AC under TZ=Pacific/Auckland the invoice date and the report stamp stay in UTC', () => {
  const r = runUnder('Pacific/Auckland');
  assert.equal(r.invoice, '01/03/2026');
  assert.equal(r.stamp, '2026-03-01 20:00');
});

test('AC an invalid due date is still null, without throwing', () => {
  assert.equal(runUnder('UTC').due, null);
});
