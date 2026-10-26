#!/usr/bin/env bash
# Builds the task repo in $1: a billing app that depends on a vendored date library, datefmt 1.4.0 (offline, fixed author and date). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest")" ]; }; then
  echo "setup: refusing non-empty $dest" >&2
  exit 2
fi
mkdir -p "$dest"
cd "$dest"
mkdir -p node_modules/datefmt src tests vendor/datefmt-1.4.0 vendor/datefmt-2.0.0

cat > package.json <<'PB_TASK_EOF'
{
  "name": "billing-app",
  "version": "1.0.0",
  "private": true,
  "scripts": { "test": "node --test" },
  "dependencies": {
    "datefmt": "file:vendor/datefmt-1.4.0"
  }
}
PB_TASK_EOF

cat > package-lock.json <<'PB_TASK_EOF'
{
  "name": "billing-app",
  "version": "1.0.0",
  "lockfileVersion": 3,
  "requires": true,
  "packages": {
    "": {
      "name": "billing-app",
      "version": "1.0.0",
      "dependencies": {
        "datefmt": "file:vendor/datefmt-1.4.0"
      }
    },
    "node_modules/datefmt": {
      "version": "1.4.0",
      "resolved": "file:vendor/datefmt-1.4.0"
    }
  }
}
PB_TASK_EOF

cat > README.md <<'PB_TASK_EOF'
# billing-app

Invoices, the daily report and the due-date API of the billing service.

## Dependencies

Dependencies are vendored and committed for offline CI: every release we use is kept as shipped in
`vendor/<name>-<version>/`, and `node_modules/` is committed too. To change one, copy it from vendor/ into
node_modules/ and update package.json and package-lock.json. CI has no network access.

Tests: `npm test`.
PB_TASK_EOF

cat > vendor/datefmt-1.4.0/package.json <<'PB_TASK_EOF'
{
  "name": "datefmt",
  "version": "1.4.0",
  "main": "index.js",
  "license": "MIT"
}
PB_TASK_EOF

cat > vendor/datefmt-1.4.0/index.js <<'PB_TASK_EOF'
'use strict';
// datefmt 1.4.0: tiny date formatting and parsing.

function pad(n, w) {
  return String(n).padStart(w || 2, '0');
}

function fields(date, utc) {
  return utc
    ? { YYYY: date.getUTCFullYear(), MM: date.getUTCMonth() + 1, DD: date.getUTCDate(), HH: date.getUTCHours(), mm: date.getUTCMinutes() }
    : { YYYY: date.getFullYear(), MM: date.getMonth() + 1, DD: date.getDate(), HH: date.getHours(), mm: date.getMinutes() };
}

// format(date, pattern, { utc }) -> pattern with YYYY MM DD HH mm replaced; local time unless utc is true
function format(date, pattern, options) {
  const f = fields(date, Boolean(options && options.utc));
  return pattern.replace(/YYYY|MM|DD|HH|mm/g, (t) => pad(f[t], t === 'YYYY' ? 4 : 2));
}

// parse('YYYY-MM-DD') -> Date at 00:00 UTC, or null when the input is not a valid date
function parse(str) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(str));
  if (!m) return null;
  const d = new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])));
  return d.getUTCMonth() === Number(m[2]) - 1 ? d : null;
}

module.exports = { format, parse };
PB_TASK_EOF

cat > vendor/datefmt-1.4.0/CHANGELOG.md <<'PB_TASK_EOF'
# datefmt changelog

## 1.4.0
- `format()` accepts `{ utc: true }` to format in UTC instead of local time.

## 1.3.0
- `parse('YYYY-MM-DD')` returns a Date at 00:00 UTC, or null when the input is not a valid date.
PB_TASK_EOF

cat > vendor/datefmt-2.0.0/package.json <<'PB_TASK_EOF'
{
  "name": "datefmt",
  "version": "2.0.0",
  "main": "index.js",
  "license": "MIT"
}
PB_TASK_EOF

cat > vendor/datefmt-2.0.0/index.js <<'PB_TASK_EOF'
'use strict';
// datefmt 2.0.0: tiny date formatting and parsing.

class DateFmtError extends Error {
  constructor(message) {
    super(message);
    this.name = 'DateFmtError';
  }
}

function pad(n, w) {
  return String(n).padStart(w || 2, '0');
}

function fields(date, utc) {
  return utc
    ? { YYYY: date.getUTCFullYear(), MM: date.getUTCMonth() + 1, DD: date.getUTCDate(), HH: date.getUTCHours(), mm: date.getUTCMinutes() }
    : { YYYY: date.getFullYear(), MM: date.getMonth() + 1, DD: date.getDate(), HH: date.getHours(), mm: date.getMinutes() };
}

// format(date, pattern, { timeZone }) -> pattern with YYYY MM DD HH mm replaced; local time unless timeZone is 'UTC'.
// Unknown options are ignored.
function format(date, pattern, options) {
  const f = fields(date, Boolean(options && options.timeZone === 'UTC'));
  return pattern.replace(/YYYY|MM|DD|HH|mm/g, (t) => pad(f[t], t === 'YYYY' ? 4 : 2));
}

// parse('YYYY-MM-DD') -> Date at 00:00 UTC; throws DateFmtError when the input is not a valid date
function parse(str) {
  const s = String(str);
  if (s.length > 64) throw new DateFmtError('input too long');
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (!m) throw new DateFmtError(`not a date: ${s}`);
  const d = new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])));
  if (d.getUTCMonth() !== Number(m[2]) - 1) throw new DateFmtError(`not a date: ${s}`);
  return d;
}

module.exports = { format, parse, DateFmtError };
PB_TASK_EOF

cat > vendor/datefmt-2.0.0/CHANGELOG.md <<'PB_TASK_EOF'
# datefmt changelog

## 2.0.0
- Fixes advisory DFA-2026-01 (slow parse on long input).
- BREAKING: the `utc` option is removed; pass `{ timeZone: 'UTC' }` (unknown options are ignored).
- BREAKING: `parse()` throws `DateFmtError` on invalid input instead of returning null.

## 1.4.0
- `format()` accepts `{ utc: true }` to format in UTC instead of local time.

## 1.3.0
- `parse('YYYY-MM-DD')` returns a Date at 00:00 UTC, or null when the input is not a valid date.
PB_TASK_EOF

cat > node_modules/datefmt/package.json <<'PB_TASK_EOF'
{
  "name": "datefmt",
  "version": "1.4.0",
  "main": "index.js",
  "license": "MIT"
}
PB_TASK_EOF

cat > node_modules/datefmt/index.js <<'PB_TASK_EOF'
'use strict';
// datefmt 1.4.0: tiny date formatting and parsing.

function pad(n, w) {
  return String(n).padStart(w || 2, '0');
}

function fields(date, utc) {
  return utc
    ? { YYYY: date.getUTCFullYear(), MM: date.getUTCMonth() + 1, DD: date.getUTCDate(), HH: date.getUTCHours(), mm: date.getUTCMinutes() }
    : { YYYY: date.getFullYear(), MM: date.getMonth() + 1, DD: date.getDate(), HH: date.getHours(), mm: date.getMinutes() };
}

// format(date, pattern, { utc }) -> pattern with YYYY MM DD HH mm replaced; local time unless utc is true
function format(date, pattern, options) {
  const f = fields(date, Boolean(options && options.utc));
  return pattern.replace(/YYYY|MM|DD|HH|mm/g, (t) => pad(f[t], t === 'YYYY' ? 4 : 2));
}

// parse('YYYY-MM-DD') -> Date at 00:00 UTC, or null when the input is not a valid date
function parse(str) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(str));
  if (!m) return null;
  const d = new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])));
  return d.getUTCMonth() === Number(m[2]) - 1 ? d : null;
}

module.exports = { format, parse };
PB_TASK_EOF

cat > node_modules/datefmt/CHANGELOG.md <<'PB_TASK_EOF'
# datefmt changelog

## 1.4.0
- `format()` accepts `{ utc: true }` to format in UTC instead of local time.

## 1.3.0
- `parse('YYYY-MM-DD')` returns a Date at 00:00 UTC, or null when the input is not a valid date.
PB_TASK_EOF

cat > src/invoice.js <<'PB_TASK_EOF'
'use strict';
const { format } = require('datefmt');

// invoice dates are printed in UTC
function invoiceDate(d) {
  return format(d, 'DD/MM/YYYY', { utc: true });
}

module.exports = { invoiceDate };
PB_TASK_EOF

cat > src/report.js <<'PB_TASK_EOF'
'use strict';
const datefmt = require('datefmt');

const STAMP = 'YYYY-MM-DD HH:mm';

function stampUtc(d) {
  return datefmt.format(d, STAMP, { utc: true });
}

module.exports = { stampUtc };
PB_TASK_EOF

cat > src/api.js <<'PB_TASK_EOF'
'use strict';
const { parse } = require('datefmt');

// due dates come from the API as YYYY-MM-DD; anything else means "no due date"
function parseDueDate(s) {
  return parse(s);
}

module.exports = { parseDueDate };
PB_TASK_EOF

cat > tests/billing.test.js <<'PB_TASK_EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { invoiceDate } = require('../src/invoice');
const { stampUtc } = require('../src/report');
const { parseDueDate } = require('../src/api');

test('an invoice date is DD/MM/YYYY', () => {
  assert.equal(invoiceDate(new Date('2026-03-01T12:00:00Z')), '01/03/2026');
});

test('a report stamp is YYYY-MM-DD HH:mm', () => {
  assert.equal(stampUtc(new Date('2026-07-04T05:07:00Z')), '2026-07-04 05:07');
});

test('a due date from the API becomes a Date', () => {
  assert.equal(parseDueDate('2026-03-15').toISOString(), '2026-03-15T00:00:00.000Z');
});
PB_TASK_EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git -c core.excludesFile=/dev/null add -f -A
GIT_AUTHOR_DATE='2026-03-02T14:00:00Z' GIT_COMMITTER_DATE='2026-03-02T14:00:00Z' git commit -q -m "Billing app on datefmt 1.4.0 (vendored)"
