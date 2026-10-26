// PB-HIDDEN-CANARY:oss-07-csv-export-cells
// Hidden PASS_TO_PASS test: plain contacts export as before (header, one record per contact, a missing or null field is
// an empty cell, numbers as text), read back with the same strict RFC 4180 reader; both toCsv and the CLI.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const ROOT = path.join(__dirname, '..');
const { toCsv } = require(path.join(ROOT, 'src', 'csv.js'));
const COLUMNS = ['name', 'email', 'company', 'note'];

function parseCsv(text) {
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);
  const records = [];
  const n = text.length;
  if (n === 0) return records;
  let i = 0;
  let rec = [];
  const atEol = (k) => text[k] === '\n' || (text[k] === '\r' && text[k + 1] === '\n');
  for (;;) {
    let field = '';
    if (text[i] === '"') {
      i++;
      for (;;) {
        if (i >= n) throw new Error('unterminated quoted field');
        if (text[i] === '"') {
          if (text[i + 1] === '"') { field += '"'; i += 2; continue; }
          i++;
          break;
        }
        field += text[i];
        i++;
      }
      if (i < n && text[i] !== ',' && !atEol(i)) throw new Error(`text after a closing quote at offset ${i}`);
    } else {
      while (i < n && text[i] !== ',' && !atEol(i)) {
        if (text[i] === '"') throw new Error(`a quote inside an unquoted field at offset ${i}`);
        if (text[i] === '\r') throw new Error(`a bare CR in an unquoted field at offset ${i}`);
        field += text[i];
        i++;
      }
    }
    rec.push(field);
    if (i >= n) { records.push(rec); break; }
    if (text[i] === ',') { i++; continue; }
    i += text[i] === '\r' ? 2 : 1;
    records.push(rec);
    rec = [];
    if (i >= n) break;
  }
  return records;
}

const PLAIN = [
  { name: 'Pham Quoc Bao', email: 'bao@example.com', company: 'Mai Linh Books', note: 'prefers e-mail' },
  { name: 'Le Thu', email: 'thu@example.com' },
  { name: 'Tran Nam', email: 'nam@example.com', company: null, note: 42 },
];
const WANT = [
  COLUMNS,
  ['Pham Quoc Bao', 'bao@example.com', 'Mai Linh Books', 'prefers e-mail'],
  ['Le Thu', 'thu@example.com', '', ''],
  ['Tran Nam', 'nam@example.com', '', '42'],
];

test('toCsv: plain rows read back unchanged, and the text ends with a line break', () => {
  const out = toCsv(PLAIN, COLUMNS);
  assert.deepEqual(parseCsv(out), WANT);
  assert.match(out, /\n$/);
});

test('toCsv: no rows gives the header record only', () => {
  assert.deepEqual(parseCsv(toCsv([], COLUMNS)), [COLUMNS]);
});

test('bin/export.js prints the plain contacts as CSV', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'pbo07p-'));
  try {
    const file = path.join(dir, 'contacts.json');
    fs.writeFileSync(file, JSON.stringify(PLAIN));
    const r = spawnSync(process.execPath, [path.join(ROOT, 'bin', 'export.js'), file], { cwd: ROOT, encoding: 'utf8' });
    assert.equal(r.status, 0, r.stderr);
    assert.deepEqual(parseCsv(r.stdout), WANT);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
