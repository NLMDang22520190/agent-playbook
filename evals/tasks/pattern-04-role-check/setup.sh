#!/usr/bin/env bash
# Builds the task repo in $1: order permission checks (offline, fixed author and date). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest")" ]; }; then
  echo "setup: refusing non-empty $dest" >&2
  exit 2
fi
mkdir -p "$dest"
cd "$dest"
mkdir -p src tests

cat > package.json <<'EOF'
{
  "name": "order-desk",
  "version": "3.0.1",
  "private": true,
  "scripts": { "test": "node --test" }
}
EOF

cat > README.md <<'EOF'
# order-desk

Back office for print orders. Users have a role: `admin`, `staff`, `viewer` (read-only accounts for accountants and
partners) or `customer`. `src/auth.js` answers permission questions for the API handlers.
EOF

cat > src/auth.js <<'EOF'
'use strict';

// May this user cancel this order? Customers may only cancel their own orders.
// user: { id, role } of the signed-in user; order: { ownerId }.
function canCancel(user, order) {
  return user.role !== 'customer' || user.id === order.ownerId;
}

module.exports = { canCancel };
EOF

cat > tests/auth.test.js <<'EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { canCancel } = require('../src/auth');

test('an admin can cancel', () => {
  assert.equal(canCancel({ id: 'a', role: 'admin' }, { ownerId: 'c' }), true);
});

test('a customer can cancel their own order only', () => {
  assert.equal(canCancel({ id: 'c', role: 'customer' }, { ownerId: 'c' }), true);
  assert.equal(canCancel({ id: 'd', role: 'customer' }, { ownerId: 'c' }), false);
});
EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git add -A
GIT_AUTHOR_DATE='2026-01-08T09:00:00Z' GIT_COMMITTER_DATE='2026-01-08T09:00:00Z' git commit -q -m "Permission check for cancelling orders"
