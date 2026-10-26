#!/usr/bin/env bash
# Builds the task repo in $1: warehouse stock levels where some items may go below zero by design (offline, fixed author and date). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest")" ]; }; then
  echo "setup: refusing non-empty $dest" >&2
  exit 2
fi
mkdir -p "$dest"
cd "$dest"
mkdir -p docs src tests

cat > package.json <<'PB_TASK_EOF'
{
  "name": "inventory",
  "version": "1.0.0",
  "private": true,
  "scripts": { "test": "node --test" }
}
PB_TASK_EOF

cat > README.md <<'PB_TASK_EOF'
# inventory

Stock levels of the shop's warehouse.

- `src/stock.js` `available(item)` and `reserve(item, qty)`; an item is `{ sku, onHand, reserved, preorder }`.
- `src/dashboard.js` `stockLabel(item)`: the stock label on the inventory dashboard.
- `src/export.js` `stockCsvLine(item)`: one line of the nightly CSV export the warehouse imports.

Rules: `docs/inventory.md`. Tests: `npm test`.
PB_TASK_EOF

cat > docs/inventory.md <<'PB_TASK_EOF'
# Inventory rules

Agreed with the warehouse, 2026-01-20.

- Available stock is `onHand - reserved`.
- A regular item can never be reserved beyond what is available: `reserve` refuses it.
- Pre-order items can be reserved before the goods arrive, so they may go below zero: -3 means three units are
  backordered.
- The dashboard and the export show the signed number; the warehouse import parses it.
PB_TASK_EOF

cat > src/stock.js <<'PB_TASK_EOF'
'use strict';

function available(item) {
  return item.onHand - item.reserved;
}

function reserve(item, qty) {
  if (!item.preorder && qty > available(item)) {
    throw new Error(`cannot reserve ${qty} of ${item.sku}: only ${available(item)} available`);
  }
  item.reserved += qty;
  return item;
}

module.exports = { available, reserve };
PB_TASK_EOF

cat > src/dashboard.js <<'PB_TASK_EOF'
'use strict';
const { available } = require('./stock');

function stockLabel(item) {
  return `${available(item)} in stock`;
}

module.exports = { stockLabel };
PB_TASK_EOF

cat > src/export.js <<'PB_TASK_EOF'
'use strict';
const { available } = require('./stock');

function stockCsvLine(item) {
  return `${item.sku};${available(item)}`;
}

module.exports = { stockCsvLine };
PB_TASK_EOF

cat > tests/stock.test.js <<'PB_TASK_EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { available, reserve } = require('../src/stock');
const { stockLabel } = require('../src/dashboard');

test('available is on hand minus reserved', () => {
  assert.equal(available({ sku: 'MUG-01', onHand: 10, reserved: 4, preorder: false }), 6);
});

test('a regular item cannot be reserved beyond what is available', () => {
  assert.throws(() => reserve({ sku: 'MUG-01', onHand: 2, reserved: 0, preorder: false }, 3));
});

test('the dashboard label shows the available stock', () => {
  assert.equal(stockLabel({ sku: 'MUG-01', onHand: 10, reserved: 4, preorder: false }), '6 in stock');
});
PB_TASK_EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git -c core.excludesFile=/dev/null add -f -A
GIT_AUTHOR_DATE='2026-02-17T08:15:00Z' GIT_COMMITTER_DATE='2026-02-17T08:15:00Z' git commit -q -m "Inventory: stock levels, dashboard label and CSV export"
