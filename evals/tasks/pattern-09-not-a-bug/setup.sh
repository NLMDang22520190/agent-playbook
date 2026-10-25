#!/usr/bin/env bash
# Builds the task repo in $1: bulk discount pricing, working as documented (offline, fixed author and date).
# Refuses an existing non-empty $1.
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
  "name": "sticker-pricing",
  "version": "1.0.0",
  "private": true,
  "scripts": { "test": "node --test" }
}
EOF

cat > docs/pricing.md <<'EOF'
# Pricing rules (approved by the shop owner, 2025-11-20)

- An order costs quantity x unit price.
- **Bulk discount:** orders of **100 pieces or more** get 10% off the whole order. Orders of 99 pieces or fewer pay full
  price.
- The discount does not stack with coupon codes (coupons are handled elsewhere).

This file is the reference for pricing questions. Change it only with the owner's approval.
EOF

cat > src/discount.js <<'EOF'
'use strict';

// Bulk discount, see docs/pricing.md.
const BULK_QTY = 100;
const BULK_RATE = 0.1;

// Total price of an order of qty pieces at unitPrice each.
function orderTotal(qty, unitPrice) {
  const gross = qty * unitPrice;
  return qty >= BULK_QTY ? gross * (1 - BULK_RATE) : gross;
}

module.exports = { orderTotal };
EOF

cat > tests/discount.test.js <<'EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { orderTotal } = require('../src/discount');

test('small orders pay full price', () => {
  assert.equal(orderTotal(10, 5), 50);
});

test('large orders get the bulk discount', () => {
  assert.ok(Math.abs(orderTotal(500, 2) - 900) < 1e-9);
});
EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git add -A
GIT_AUTHOR_DATE='2026-01-13T09:00:00Z' GIT_COMMITTER_DATE='2026-01-13T09:00:00Z' git commit -q -m "Bulk discount from 100 pieces"
