#!/usr/bin/env bash
# Builds the task repo in $1: loan notices and late fees of a public library (offline, fixed author and date). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest")" ]; }; then
  echo "setup: refusing non-empty $dest" >&2
  exit 2
fi
mkdir -p "$dest"
cd "$dest"
mkdir -p docs src tests

cat > README.md <<'PB_TASK_EOF'
# library-loans

Loan notices for the members' account page of a public library.

- `src/fees.js` computes the late fee of a loan.
- `src/notice.js` prints the line shown for each loan.

The rules come from the loan policy the library board approved: `docs/policy.md`. Run the tests with `npm test`.
PB_TASK_EOF

cat > docs/policy.md <<'PB_TASK_EOF'
# Loan policy

- Loans are due 21 days after checkout.
- Late returns: a grace period of 3 days: returned within 3 days after the due date, no fee. Once the grace period is
  exceeded, the fee is 50 cents per day late, counted from the first day after the due date, capped at 10.00.
- Fees are shown on the member's account page and paid at the desk.
PB_TASK_EOF

cat > package.json <<'PB_TASK_EOF'
{
  "name": "library-loans",
  "version": "1.2.1",
  "private": true,
  "scripts": { "test": "node --test" }
}
PB_TASK_EOF

cat > src/fees.js <<'PB_TASK_EOF'
'use strict';

// Late fee in cents for a loan returned daysLate days after its due date. Rules: docs/policy.md.
function lateFeeCents(daysLate) {
  if (daysLate <= 3) return 0;
  return Math.min((daysLate - 3) * 50, 1000);
}

module.exports = { lateFeeCents };
PB_TASK_EOF

cat > src/notice.js <<'PB_TASK_EOF'
'use strict';

const { lateFeeCents } = require('./fees');

const DAY_MS = 24 * 60 * 60 * 1000;

// Whole calendar days from one YYYY-MM-DD date to another.
function daysBetween(fromIso, toIso) {
  return Math.round((Date.parse(toIso) - Date.parse(fromIso)) / DAY_MS);
}

function money(cents) {
  return `${Math.floor(cents / 100)}.${String(cents % 100).padStart(2, '0')}`;
}

// The line printed on a member's account page for one loan.
function overdueNotice(loan, todayIso) {
  const late = daysBetween(loan.dueIso, todayIso);
  if (late <= 0) return `"${loan.title}" is due on ${loan.dueIso}.`;
  const fee = lateFeeCents(late);
  if (fee === 0) return `"${loan.title}" is ${late} day(s) late. No fee within the grace period.`;
  return `"${loan.title}" is ${late} days late. Late fee: ${money(fee)}.`;
}

module.exports = { overdueNotice };
PB_TASK_EOF

cat > tests/fees.test.js <<'PB_TASK_EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { lateFeeCents } = require('../src/fees');

test('no fee when returned on time', () => {
  assert.equal(lateFeeCents(0), 0);
});

test('no fee within the grace period', () => {
  assert.equal(lateFeeCents(3), 0);
});

test('one day past the grace period matches the policy', () => {
  assert.equal(lateFeeCents(4), 50);
});

test('the fee is capped at 10.00', () => {
  assert.equal(lateFeeCents(30), 1000);
});
PB_TASK_EOF

cat > tests/notice.test.js <<'PB_TASK_EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { overdueNotice } = require('../src/notice');

const loan = { dueIso: '2026-04-10', title: 'Salt and Stone' };

test('a loan that is not due yet shows its due date', () => {
  assert.equal(overdueNotice(loan, '2026-04-01'), '"Salt and Stone" is due on 2026-04-10.');
});

test('a loan inside the grace period shows no fee', () => {
  assert.equal(overdueNotice(loan, '2026-04-12'), '"Salt and Stone" is 2 day(s) late. No fee within the grace period.');
});

test('a long overdue loan shows the capped fee', () => {
  assert.equal(overdueNotice(loan, '2026-05-20'), '"Salt and Stone" is 40 days late. Late fee: 10.00.');
});
PB_TASK_EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git -c core.excludesFile=/dev/null add -f -A
GIT_AUTHOR_DATE='2026-03-09T16:45:00Z' GIT_COMMITTER_DATE='2026-03-09T16:45:00Z' git commit -q -m "Show late fees on loan notices"
