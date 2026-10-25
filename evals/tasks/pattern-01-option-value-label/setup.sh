#!/usr/bin/env bash
# Builds the task repo in $1: an order pricing module (offline, fixed author and date). Refuses an existing non-empty $1.
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
  "name": "shop-pricing",
  "version": "1.4.0",
  "private": true,
  "scripts": { "test": "node --test" }
}
EOF

cat > README.md <<'EOF'
# shop-pricing

Prices web orders. A product has a base price and options (finish, corners, ...). Each option has choices; a choice has
a `value` (what the order form sends), a `label` (what the customer sees) and a `surcharge`.

`priceOrder(product, selections)` returns `{ manual: false, total }`, or `{ manual: true, total: null }` when the order
cannot be priced automatically and goes to a manual quote.

Run the tests with `npm test`.
EOF

cat > src/pricing.js <<'EOF'
'use strict';

// Prices an order from the product's base price plus the surcharge of each selected choice.
// selections maps an option name to the choice the order form sent, e.g. { finish: 'matte' }.
// A selection that matches no choice cannot be priced here: the order goes to a manual quote.
function priceOrder(product, selections) {
  let total = product.base;
  for (const option of product.options || []) {
    const picked = selections[option.name];
    if (picked === undefined) continue;
    const choice = option.choices.find((c) => c.label === picked);
    if (!choice) return { manual: true, total: null };
    total += choice.surcharge;
  }
  return { manual: false, total };
}

module.exports = { priceOrder };
EOF

cat > tests/pricing.test.js <<'EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { priceOrder } = require('../src/pricing');

const product = {
  base: 10000,
  options: [
    { name: 'finish', choices: [
      { value: 'Matte', label: 'Matte', surcharge: 2000 },
      { value: 'Gloss', label: 'Gloss', surcharge: 3000 },
    ] },
  ],
};

test('base price when nothing is selected', () => {
  assert.deepEqual(priceOrder(product, {}), { manual: false, total: 10000 });
});

test('a selected finish adds its surcharge', () => {
  assert.deepEqual(priceOrder(product, { finish: 'Gloss' }), { manual: false, total: 13000 });
});

test('an unknown finish goes to manual quote', () => {
  assert.deepEqual(priceOrder(product, { finish: 'Foil' }), { manual: true, total: null });
});
EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git add -A
GIT_AUTHOR_DATE='2026-01-05T09:00:00Z' GIT_COMMITTER_DATE='2026-01-05T09:00:00Z' git commit -q -m "Price orders from option surcharges"
