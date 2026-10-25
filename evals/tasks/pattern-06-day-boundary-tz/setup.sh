#!/usr/bin/env bash
# Builds the task repo in $1: a daily sales report (offline, fixed author and date). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest")" ]; }; then
  echo "setup: refusing non-empty $dest" >&2
  exit 2
fi
mkdir -p "$dest"
cd "$dest"
mkdir -p src tests docs

cat > package.json <<'EOF'
{
  "name": "sales-report",
  "version": "1.2.3",
  "private": true,
  "scripts": { "test": "node --test" }
}
EOF

cat > docs/report.md <<'EOF'
# Daily sales report

Order times are stored in UTC (`2026-03-01T23:30:00Z`).

The report groups orders by **shop day**: the calendar day in the shop's time zone, UTC+7 (no daylight saving time).
An order placed at 06:30 shop time on 2 March belongs to 2 March, whatever time zone the server runs in.

`dailyTotals(orders)` returns `{ 'YYYY-MM-DD': total amount }`, one key per shop day.
EOF

cat > src/report.js <<'EOF'
'use strict';

// Total order amount per day: { 'YYYY-MM-DD': amount }. See docs/report.md.
function dailyTotals(orders) {
  const totals = {};
  for (const order of orders) {
    const day = order.at.slice(0, 10);
    totals[day] = (totals[day] || 0) + order.amount;
  }
  return totals;
}

module.exports = { dailyTotals };
EOF

cat > tests/report.test.js <<'EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { dailyTotals } = require('../src/report');

test('an empty list has no days', () => {
  assert.deepEqual({ ...dailyTotals([]) }, {});
});

test('orders in the afternoon of one day', () => {
  const orders = [{ at: '2026-04-10T07:00:00Z', amount: 30 }, { at: '2026-04-10T08:00:00Z', amount: 12 }];
  assert.deepEqual({ ...dailyTotals(orders) }, { '2026-04-10': 42 });
});
EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git add -A
GIT_AUTHOR_DATE='2026-01-10T09:00:00Z' GIT_COMMITTER_DATE='2026-01-10T09:00:00Z' git commit -q -m "Daily sales report"
