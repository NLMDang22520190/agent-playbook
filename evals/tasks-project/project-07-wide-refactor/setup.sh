#!/usr/bin/env bash
# Builds the task repo in $1: a reporting module with 24 report files (8 of them over 16 KB), each with its own copy of the money
# formatting, a row field called `total` and no generation date (offline, fixed author and date). Three tickets touch every report, so a
# session reads and edits many files and the context grows (the regime that Context Mode and billion-context claim to help).
# Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
here="$(cd "$(dirname "$0")" && pwd)"
if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest")" ]; }; then
  echo "setup: refusing non-empty $dest" >&2
  exit 2
fi
mkdir -p "$dest"
cd "$dest"
mkdir -p docs src tests

cat > package.json <<'PB_TASK_EOF'
{
  "name": "shop-reports",
  "version": "2.1.0",
  "private": true,
  "scripts": { "test": "node --test" }
}
PB_TASK_EOF

cat > README.md <<'PB_TASK_EOF'
# shop-reports

Text reports about the shop's orders. `src/reports/index.js` builds the rows (`rowsFrom`) and renders all reports (`runAll(orders, ctx)`).
Each report is one file in `src/reports/`. Money rules: `docs/money.md`. Report layout: `docs/reports.md`. Run the tests with `npm test`.
PB_TASK_EOF

cat > CONTRIBUTING.md <<'PB_TASK_EOF'
# Contributing

- Run `npm test` before you commit.
- Money is integer cents everywhere in code. No floating-point amounts.
- When you settle a product question yourself instead of asking, write it down in `docs/decisions.md` as one line:
  `DECISION[D1]: <what you chose> (<why>)`.
PB_TASK_EOF

cat > docs/money.md <<'PB_TASK_EOF'
# Money

All amounts are integer cents. Money is shown as dollars with a thousands separator and exactly two decimals:

- `formatMoney(123456)` is `$1,234.56`, `formatMoney(5)` is `$0.05`, `formatMoney(0)` is `$0.00`.
- A negative amount puts the minus sign before the dollar sign: `formatMoney(-250)` is `-$2.50`, `formatMoney(-123456)` is `-$1,234.56`.
- An amount that is not an integer number of cents is a bug in the caller: `formatMoney` throws a `TypeError`.

`formatMoney` lives in `src/money.js`. There is one place that formats money; reports must not format it themselves.
PB_TASK_EOF

cat > docs/reports.md <<'PB_TASK_EOF'
# Reports

Every report starts with its title and the day it was generated, on one line: `# <title> (generated YYYY-MM-DD)`, where the date is the
UTC date of `ctx.now`. The time always comes from `ctx.now` (a `Date` given by the caller), never from the clock, so a report can be
rendered again for any day. Rows have `sku`, `name`, `qty` and `totalCents` (the money of the row, in cents).
PB_TASK_EOF

cat > src/money.js <<'PB_TASK_EOF'
'use strict';

// Config amounts are decimal strings in major units ("4.90"); the code works in integer cents.
function toCents(amount) {
  const m = /^(\d+)(?:\.(\d{1,2}))?$/.exec(String(amount).trim());
  if (!m) throw new Error('bad amount: ' + amount);
  return Number(m[1]) * 100 + Number((m[2] || '').padEnd(2, '0') || 0);
}

module.exports = { toCents };
PB_TASK_EOF

tmpjs="$(mktemp)"
cp "$here/gen.js.txt" "$tmpjs"
node "$tmpjs"
rm -f "$tmpjs"

cat > tests/smoke.test.js <<'PB_TASK_EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { runAll, MODULES } = require('../src/reports');

test('every report renders for a small order list', () => {
  const orders = [{ id: 1, lines: [{ sku: 'A1', name: 'Shirt', qty: 2, unitCents: 1999 }, { sku: 'B2', name: 'Mug', qty: 1, unitCents: 850 }] }];
  const out = runAll(orders, { now: new Date('2026-03-01T10:00:00Z') });
  assert.equal(Object.keys(out).length, MODULES.length);
  for (const text of Object.values(out)) assert.ok(text.includes('Shirt'));
});
PB_TASK_EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git -c core.excludesFile=/dev/null add -f -A
GIT_AUTHOR_DATE='2026-02-14T10:00:00Z' GIT_COMMITTER_DATE='2026-02-14T10:00:00Z' git commit -q -m "Reports module"
