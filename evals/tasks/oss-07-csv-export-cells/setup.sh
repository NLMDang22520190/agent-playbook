#!/usr/bin/env bash
# Builds the task repo in $1: a node CLI that exports contacts as CSV for a CRM import (offline, fixed author and date). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest")" ]; }; then
  echo "setup: refusing non-empty $dest" >&2
  exit 2
fi
mkdir -p "$dest"
cd "$dest"
mkdir -p bin src tests

cat > package.json <<'PB_TASK_EOF'
{
  "name": "contacts-export",
  "version": "1.4.0",
  "private": true,
  "scripts": { "test": "node --test" }
}
PB_TASK_EOF

cat > README.md <<'PB_TASK_EOF'
# contacts-export

`node bin/export.js contacts.json > contacts.csv` writes the contacts as CSV for the CRM import: a header line
`name,email,company,note`, then one line per contact. A missing field is an empty cell.

`src/csv.js` holds `toCsv(rows, columns)`. Tests: `npm test` (Node 18+).
PB_TASK_EOF

cat > bin/export.js <<'PB_TASK_EOF'
#!/usr/bin/env node
'use strict';
// export.js FILE: prints the contacts of the JSON array in FILE as CSV.
const fs = require('node:fs');
const { toCsv } = require('../src/csv');

const COLUMNS = ['name', 'email', 'company', 'note'];

const file = process.argv[2];
if (!file) {
  process.stderr.write('usage: export.js contacts.json\n');
  process.exit(2);
}
const contacts = JSON.parse(fs.readFileSync(file, 'utf8'));
process.stdout.write(toCsv(contacts, COLUMNS));
PB_TASK_EOF

cat > src/csv.js <<'PB_TASK_EOF'
'use strict';

// One CSV cell: a missing value is empty, anything else its text.
function cell(value) {
  if (value === undefined || value === null) return '';
  return String(value);
}

// toCsv(rows, columns) -> a header line with the column names, then one line per row, each line ending in "\n".
function toCsv(rows, columns) {
  const lines = [columns.join(',')];
  for (const row of rows) {
    lines.push(columns.map((c) => cell(row[c])).join(','));
  }
  return lines.join('\n') + '\n';
}

module.exports = { toCsv };
PB_TASK_EOF

cat > tests/csv.test.js <<'PB_TASK_EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { toCsv } = require('../src/csv');

test('header line, then one line per row', () => {
  const rows = [
    { name: 'Pham Quoc Bao', email: 'bao@example.com', company: 'Mai Linh Books', note: 'prefers e-mail' },
    { name: 'Le Thu', email: 'thu@example.com' },
  ];
  assert.equal(
    toCsv(rows, ['name', 'email', 'company', 'note']),
    'name,email,company,note\nPham Quoc Bao,bao@example.com,Mai Linh Books,prefers e-mail\nLe Thu,thu@example.com,,\n',
  );
});

test('no rows gives the header only', () => {
  assert.equal(toCsv([], ['name', 'email']), 'name,email\n');
});
PB_TASK_EOF

chmod +x bin/export.js

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git -c core.excludesFile=/dev/null add -f -A
git update-index --chmod=+x bin/export.js
GIT_AUTHOR_DATE='2026-04-02T10:15:00Z' GIT_COMMITTER_DATE='2026-04-02T10:15:00Z' git commit -q -m "contacts export as CSV for the CRM import"
