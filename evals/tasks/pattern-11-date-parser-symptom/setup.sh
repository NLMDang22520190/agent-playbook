#!/usr/bin/env bash
# Builds the task repo in $1: a bookings report fed by partner CSV files and web bookings (offline, fixed author and date). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest")" ]; }; then
  echo "setup: refusing non-empty $dest" >&2
  exit 2
fi
mkdir -p "$dest"
cd "$dest"
mkdir -p docs samples scripts src/import src/report tests

cat > README.md <<'PB_TASK_EOF'
# bookings-report

Monthly bookings report for the front desk. Bookings arrive from two channels:

- partner agencies upload a CSV file each month (`src/import/partnerCsv.js`);
- the web site sends JSON bookings (`src/import/web.js`).

`src/report/render.js` prints one line per booking. Print a partner file with:

    node scripts/report.js samples/partner-2026-03.csv

Import rules: see `docs/import.md`. Run the tests with `npm test`.
PB_TASK_EOF

cat > docs/import.md <<'PB_TASK_EOF'
# Importing bookings

## Partner CSV

- One booking per line, fields separated by `;`: `ref;guest;check-in;nights`.
- Partner CSV dates are DD/MM/YYYY (day first, as the agencies write them).
- `nights` is a whole number.

## Web bookings

- JSON objects `{ ref, guest, checkIn, nights }`; `checkIn` is an ISO date `YYYY-MM-DD`.

## Stored form

- A check-in is a calendar date, stored as a Date at 00:00 UTC, the same as web bookings, whatever the time zone of the
  server that runs the import.
PB_TASK_EOF

cat > package.json <<'PB_TASK_EOF'
{
  "name": "bookings-report",
  "version": "1.6.2",
  "private": true,
  "scripts": {
    "test": "node --test",
    "report": "node scripts/report.js"
  }
}
PB_TASK_EOF

cat > samples/partner-2026-03.csv <<'PB_TASK_EOF'
B-1041;Hoa Nguyen;03/03/2026;1
B-1042;Quang Do;03/03/2026;4
B-1043;Lan Pham;13/03/2026;2
B-1044;Minh Tran;17/03/2026;3
B-1045;Thu Vu;21/03/2026;2
B-1046;Khanh Bui;28/03/2026;5
PB_TASK_EOF

cat > scripts/report.js <<'PB_TASK_EOF'
'use strict';

// Prints the report lines of one partner CSV file: node scripts/report.js FILE
const fs = require('node:fs');
const { parseRow } = require('../src/import/partnerCsv');
const { renderRow } = require('../src/report/render');

const file = process.argv[2];
if (!file) {
  console.error('usage: node scripts/report.js FILE');
  process.exit(2);
}
for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
  if (line.trim() === '') continue;
  console.log(renderRow(parseRow(line)));
}
PB_TASK_EOF

cat > src/import/dates.js <<'PB_TASK_EOF'
'use strict';

// Turns a booking date string into a Date. Partner CSV files and web bookings both come through here.
function parseDate(str) {
  return new Date(str);
}

module.exports = { parseDate };
PB_TASK_EOF

cat > src/import/partnerCsv.js <<'PB_TASK_EOF'
'use strict';

const { parseDate } = require('./dates');

// One partner CSV row: ref;guest;check-in;nights
function parseRow(line) {
  const [ref, guest, checkIn, nights] = line.split(';').map((s) => s.trim());
  return { ref, guest, checkIn: parseDate(checkIn), nights: Number(nights) };
}

module.exports = { parseRow };
PB_TASK_EOF

cat > src/import/web.js <<'PB_TASK_EOF'
'use strict';

const { parseDate } = require('./dates');

// One web booking: { ref, guest, checkIn: 'YYYY-MM-DD', nights }
function fromWeb(booking) {
  return { ref: booking.ref, guest: booking.guest, checkIn: parseDate(booking.checkIn), nights: Number(booking.nights) };
}

module.exports = { fromWeb };
PB_TASK_EOF

cat > src/report/render.js <<'PB_TASK_EOF'
'use strict';

function pad(n) {
  return String(n).padStart(2, '0');
}

// One report line: ref | guest | check-in (DD/MM/YYYY) | nights
function renderRow(booking) {
  const d = booking.checkIn;
  const day = `${pad(d.getUTCDate())}/${pad(d.getUTCMonth() + 1)}/${d.getUTCFullYear()}`;
  return `${booking.ref} | ${booking.guest} | ${day} | ${booking.nights}`;
}

module.exports = { renderRow };
PB_TASK_EOF

cat > tests/report.test.js <<'PB_TASK_EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { fromWeb } = require('../src/import/web');
const { renderRow } = require('../src/report/render');

test('a web booking keeps its check-in day', () => {
  const b = fromWeb({ ref: 'W-0301', guest: 'Thao Ly', checkIn: '2026-03-14', nights: '2' });
  assert.equal(b.checkIn.toISOString(), '2026-03-14T00:00:00.000Z');
  assert.equal(b.nights, 2);
});

test('a report line shows ref, guest, check-in and nights', () => {
  const b = { ref: 'W-0301', guest: 'Thao Ly', checkIn: new Date(Date.UTC(2026, 2, 14)), nights: 2 };
  assert.equal(renderRow(b), 'W-0301 | Thao Ly | 14/03/2026 | 2');
});
PB_TASK_EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git -c core.excludesFile=/dev/null add -f -A
GIT_AUTHOR_DATE='2026-03-02T08:30:00Z' GIT_COMMITTER_DATE='2026-03-02T08:30:00Z' git commit -q -m "Import partner CSV bookings into the monthly report"
