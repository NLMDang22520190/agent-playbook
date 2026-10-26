#!/usr/bin/env bash
# Builds the task repo in $1: a furniture shop cart that saves and restores carts (offline, fixed author and date). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest")" ]; }; then
  echo "setup: refusing non-empty $dest" >&2
  exit 2
fi
mkdir -p "$dest"
cd "$dest"
mkdir -p data docs src/cart tests

cat > README.md <<'PB_TASK_EOF'
# furniture-cart

Cart of a small furniture shop. Products (`data/products.json`) have options (size, finish, ...) with choices, and
optional add-ons.

- `src/cart/save.js` turns the live cart into the form we store when a customer leaves.
- `src/cart/restore.js` rebuilds that stored cart against the current catalog when the customer comes back.

Notes are in `docs/`. Run the tests with `npm test`.
PB_TASK_EOF

cat > data/products.json <<'PB_TASK_EOF'
[
  {
    "id": "desk",
    "name": "Desk",
    "options": [
      { "name": "size", "choices": [
        { "value": "w120", "label": "120 × 60 cm" },
        { "value": "w140", "label": "140 × 70 cm" }
      ] },
      { "name": "finish", "choices": [
        { "value": "oak-nat", "label": "Natural oak" },
        { "value": "walnut", "label": "Dark walnut" }
      ] }
    ],
    "addons": [
      { "value": "cable-tray", "label": "Cable tray" },
      { "value": "monitor-arm", "label": "Monitor arm" }
    ]
  },
  {
    "id": "shelf",
    "name": "Shelf",
    "options": [
      { "name": "height", "choices": [
        { "value": "Low", "label": "Low" },
        { "value": "Tall", "label": "Tall" }
      ] }
    ],
    "addons": [
      { "value": "Wall anchor", "label": "Wall anchor" }
    ]
  }
]
PB_TASK_EOF

cat > docs/cart.md <<'PB_TASK_EOF'
# Cart

## Live cart

- A cart holds at most 20 lines; quantity per line is 1 to 9.
- Prices are never stored in the cart; checkout reads them from the catalog.

## Saved carts

- A cart is saved when the customer leaves and kept for 30 days.
- Saved carts store choice values and addon values, never labels: labels are display text and get reworded.
- On restore, a choice value the product no longer has resets to the default choice (the first choice of the option);
  an option missing from the saved cart takes the default choice too.
- On restore, an addon value the product no longer has is dropped.
- A product that is no longer in the catalog is dropped from the cart.
PB_TASK_EOF

cat > package.json <<'PB_TASK_EOF'
{
  "name": "furniture-cart",
  "version": "0.9.4",
  "private": true,
  "scripts": { "test": "node --test" }
}
PB_TASK_EOF

cat > src/cart/restore.js <<'PB_TASK_EOF'
'use strict';

// Rebuilds a saved cart against the current catalog.
// saved:   { lines: [{ productId, options: { <option name>: <saved choice> }, addons: [<saved addon>] }] }
// catalog: [{ id, options: [{ name, choices: [{ value, label }] }], addons: [{ value, label }] }]
// Returns  { lines: [{ productId, options: { <option name>: <choice value> }, addons: [<addon value>] }] }
function restoreCart(saved, catalog) {
  const lines = [];
  for (const line of saved.lines || []) {
    const product = catalog.find((p) => p.id === line.productId);
    if (!product) continue;
    const options = {};
    for (const option of product.options || []) {
      const want = (line.options || {})[option.name];
      const choice = option.choices.find((c) => c.label === want) || option.choices[0];
      options[option.name] = choice.value;
    }
    const addons = [];
    for (const want of line.addons || []) {
      const addon = (product.addons || []).find((a) => a.label === want);
      if (addon) addons.push(addon.value);
    }
    lines.push({ productId: product.id, options, addons });
  }
  return { lines };
}

module.exports = { restoreCart };
PB_TASK_EOF

cat > src/cart/save.js <<'PB_TASK_EOF'
'use strict';

// Turns a live cart into the stored form: a plain copy of the lines, so later edits to the live cart do not leak in.
// cart: { lines: [{ productId, options: { <option name>: <choice> }, addons: [...] }] }
function saveCart(cart) {
  return {
    lines: (cart.lines || []).map((line) => ({
      productId: line.productId,
      options: { ...(line.options || {}) },
      addons: [...(line.addons || [])],
    })),
  };
}

module.exports = { saveCart };
PB_TASK_EOF

cat > tests/restore.test.js <<'PB_TASK_EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const catalog = require('../data/products.json');
const { saveCart } = require('../src/cart/save');
const { restoreCart } = require('../src/cart/restore');

test('a saved Shelf comes back with its height and anchor', () => {
  const saved = saveCart({ lines: [{ productId: 'shelf', options: { height: 'Tall' }, addons: ['Wall anchor'] }] });
  assert.deepEqual(restoreCart(saved, catalog), {
    lines: [{ productId: 'shelf', options: { height: 'Tall' }, addons: ['Wall anchor'] }],
  });
});

test('a height the Shelf no longer has falls back to the first one', () => {
  const saved = { lines: [{ productId: 'shelf', options: { height: 'Medium' }, addons: [] }] };
  assert.deepEqual(restoreCart(saved, catalog).lines[0].options, { height: 'Low' });
});

test('a product no longer in the catalog is dropped', () => {
  const saved = { lines: [{ productId: 'stool', options: {}, addons: [] }] };
  assert.deepEqual(restoreCart(saved, catalog), { lines: [] });
});
PB_TASK_EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git -c core.excludesFile=/dev/null add -f -A
GIT_AUTHOR_DATE='2026-02-24T11:15:00Z' GIT_COMMITTER_DATE='2026-02-24T11:15:00Z' git commit -q -m "Save and restore carts"
