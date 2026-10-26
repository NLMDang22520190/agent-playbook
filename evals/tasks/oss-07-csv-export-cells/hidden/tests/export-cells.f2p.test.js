// PB-HIDDEN-CANARY:oss-07-csv-export-cells
// Hidden FAIL_TO_PASS test: whatever text a contact field holds, the exported file reads back (RFC 4180 reader below)
// as one record per contact with every value in its own column, unchanged. The prompt names a comma; "whatever text"
// also covers a double quote inside a value, a value that starts with a quote, a line break inside a value (LF and
// CRLF), accents and edge spaces. Any valid quoting style passes (quote all, quote when needed, CRLF or LF records).
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const ROOT = path.join(__dirname, '..');
const COLUMNS = ['name', 'email', 'company', 'note'];

// parseCsv(text) -> array of records (arrays of strings). Strict RFC 4180: a field is either unquoted (no quote, comma,
// CR or LF in it) or quoted with "" for a quote inside; records end in LF or CRLF; the last line end is optional; a
// leading UTF-8 BOM is ignored. Throws on anything else.
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

// exportContacts(contacts) -> the stdout of bin/export.js run on a JSON file holding contacts
function exportContacts(contacts) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'pbo07-'));
  try {
    const file = path.join(dir, 'contacts.json');
    fs.writeFileSync(file, JSON.stringify(contacts));
    const r = spawnSync(process.execPath, [path.join(ROOT, 'bin', 'export.js'), file], { cwd: ROOT, encoding: 'utf8' });
    assert.equal(r.status, 0, `export.js exit status (stderr: ${r.stderr})`);
    return r.stdout;
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

function expectRoundTrip(contacts) {
  const out = exportContacts(contacts);
  let got;
  try {
    got = parseCsv(out);
  } catch (e) {
    assert.fail(`the export is not valid CSV (${e.message}); output: ${JSON.stringify(out)}`);
  }
  const want = [COLUMNS, ...contacts.map((c) => COLUMNS.map((k) => (c[k] === undefined || c[k] === null ? '' : String(c[k]))))];
  assert.deepEqual(got, want, `output: ${JSON.stringify(out)}`);
}

const base = { name: 'Hoang Minh', email: 'minh@example.com', company: 'Minh Signs', note: 'regular' };
const withField = (k, v) => [{ ...base, [k]: v }, { name: 'Le Thu', email: 'thu@example.com', company: 'Thu Print', note: 'new' }];

test('a comma inside a value (the reported company)', () => {
  expectRoundTrip(withField('company', 'Nguyen, Tran & Partners'));
});

test('a double quote inside a value', () => {
  expectRoundTrip(withField('company', 'The "Blue Door" Cafe'));
});

test('a value that starts with a double quote', () => {
  expectRoundTrip(withField('company', '"Best" Prints'));
});

test('a quote and a comma in the same value', () => {
  expectRoundTrip(withField('note', 'said "yes, next month" on the phone'));
});

test('a line break inside a value', () => {
  expectRoundTrip(withField('note', 'Floor 3\nask for Minh at the desk'));
});

test('a Windows line break inside a value', () => {
  expectRoundTrip(withField('note', 'first call done\r\nsend the price list'));
});

test('accents and spaces at the edges are kept', () => {
  expectRoundTrip(withField('name', '  Đặng Thị Hà  '));
});

test('all of them in one file: one record per contact, every value in its column', () => {
  expectRoundTrip([
    { name: 'Hoang Minh', email: 'minh@example.com', company: 'Nguyen, Tran & Partners', note: '' },
    { name: 'Vo An', email: 'an@example.com', company: 'The "Blue Door" Cafe', note: 'met at the fair' },
    { name: 'Do Lan', email: 'lan@example.com', company: '"Best" Prints', note: 'call after 5pm, not before' },
    { name: 'Bui Hai', email: 'hai@example.com', company: 'Hai Studio', note: 'Floor 3\nask for Hai' },
    { name: 'Ngo Thu', email: 'thu@example.com', note: 'said "yes, next month", then\r\nsent the brief' },
  ]);
});
