#!/usr/bin/env bash
# Builds the task repo in $1: the product catalog and cart of a small tea shop, in node, with prices stored as decimal strings and versioned data migrations (offline, fixed author and date). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest")" ]; }; then
  echo "setup: refusing non-empty $dest" >&2
  exit 2
fi
mkdir -p "$dest"
cd "$dest"
mkdir -p data docs src tests

cat > package.json <<'PB_TASK_EOF'
{
  "name": "tea-catalog",
  "version": "0.9.0",
  "private": true,
  "scripts": { "test": "node --test" }
}
PB_TASK_EOF

cat > README.md <<'PB_TASK_EOF'
# tea-catalog

Product catalog and cart of a small tea shop. The catalog is a JSON file, `data/products.json`.

- `src/store.js`: `load(file)` reads the file and brings it to the current schema with `migrate`; `save(file, data)`.
  Data is `{ schemaVersion, products: [{ id, sku, name, ... }] }`.
- `src/migrate.js`: `migrate(data)` returns the data upgraded through every migration in `migrations` whose
  `version` is above `data.schemaVersion`, in order, and sets `schemaVersion`.
- `src/catalog.js`: `priceText(product)` -> the price as shown in the shop, e.g. `"12.50"`.
- `src/cart.js`: `totalText(products, lines)` -> the order total as shown at checkout; lines are `[{ sku, qty }]`.

Tests: `npm test` (Node 18+). Price rules: `docs/prices.md`. How we work: `CONTRIBUTING.md`.
PB_TASK_EOF

cat > CONTRIBUTING.md <<'PB_TASK_EOF'
# Contributing

- Keep changes small and covered by a test under `tests/` (`node:test`).
- The shape of `data/products.json` changes only through a new migration in `src/migrate.js` (next `version`); a
  migration that has shipped is never edited, because catalogs at that version already exist.
- Read `docs/prices.md` before touching prices.
PB_TASK_EOF

cat > docs/prices.md <<'PB_TASK_EOF'
# Prices

## Today (schemaVersion 1)
- A product's `price` is a decimal string in EUR with at most 2 decimals: `"19.99"`, `"12.5"`, `"7"`.
- Some rows came from a spreadsheet import and carry a thousands separator: `"1,299.00"` is 1299 euros.
- `priceText` shows a price with exactly 2 decimals and no separator (`"12.50"`, `"1299.00"`); `totalText` shows the
  cart total the same way.

## Target (schemaVersion 2)
- Money is an integer number of cents: each product gets `priceCents` (`"19.99"` -> 1999, `"1,299.00"` -> 129900),
  converted exactly from the decimal text (no float arithmetic).
- The change is migration 2 in `src/migrate.js`: it converts every existing product and sets `schemaVersion` 2.
  Migrating data that is already at version 2 changes nothing.
- Products keep their `id`, `sku` and `name`, and no product is added or lost.
- From version 2 on, readers use `priceCents`. `priceText` and `totalText` keep their output format, and the cart
  total is the exact sum of the line prices.
PB_TASK_EOF

cat > data/products.json <<'PB_TASK_EOF'
{
  "schemaVersion": 1,
  "products": [
    { "id": 1, "sku": "TEA-OOL", "name": "Oolong 100 g", "price": "14.90" },
    { "id": 2, "sku": "TEA-SEN", "name": "Sencha 100 g", "price": "11.5" },
    { "id": 3, "sku": "POT-CLAY", "name": "Clay teapot", "price": "48" },
    { "id": 4, "sku": "BAG-PAPER", "name": "Paper bag", "price": "0.29" },
    { "id": 5, "sku": "TABLE-TEA", "name": "Tea table", "price": "1,150.00" }
  ]
}
PB_TASK_EOF

cat > src/store.js <<'PB_TASK_EOF'
'use strict';
// Reads and writes the catalog file; load() brings old files to the current schema.
const fs = require('node:fs');
const { migrate } = require('./migrate');

function load(file) {
  return migrate(JSON.parse(fs.readFileSync(file, 'utf8')));
}

function save(file, data) {
  fs.writeFileSync(file, JSON.stringify(data, null, 2) + '\n');
}

module.exports = { load, save };
PB_TASK_EOF

cat > src/migrate.js <<'PB_TASK_EOF'
'use strict';
// Versioned data migrations of the catalog (CONTRIBUTING.md: never edit a shipped migration, add the next one).

const migrations = [
  {
    version: 1,
    // skus are upper case everywhere (the warehouse scanner sends upper case)
    up(data) {
      return { ...data, products: data.products.map((p) => ({ ...p, sku: String(p.sku).toUpperCase() })) };
    },
  },
];

function migrate(data) {
  let out = { ...data, schemaVersion: data.schemaVersion || 0 };
  for (const m of migrations) {
    if (m.version <= out.schemaVersion) continue;
    out = { ...m.up(out), schemaVersion: m.version };
  }
  return out;
}

module.exports = { migrate, migrations };
PB_TASK_EOF

cat > src/catalog.js <<'PB_TASK_EOF'
'use strict';
// Prices as shown in the shop (docs/prices.md).

// "1,299.00" -> 1299
function parsePrice(text) {
  return parseFloat(String(text).replace(/,/g, ''));
}

function priceText(product) {
  return parsePrice(product.price).toFixed(2);
}

module.exports = { parsePrice, priceText };
PB_TASK_EOF

cat > src/cart.js <<'PB_TASK_EOF'
'use strict';
// Cart total as shown at checkout.
const { parsePrice } = require('./catalog');

function totalText(products, lines) {
  let cents = 0;
  for (const line of lines) {
    const p = products.find((x) => x.sku === line.sku);
    if (!p) throw new Error(`unknown_sku ${line.sku}`);
    cents += Math.floor(parsePrice(p.price) * line.qty * 100);
  }
  return (cents / 100).toFixed(2);
}

module.exports = { totalText };
PB_TASK_EOF

cat > tests/catalog.test.js <<'PB_TASK_EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { priceText } = require('../src/catalog');
const { totalText } = require('../src/cart');

test('priceText shows two decimals and no thousands separator', () => {
  assert.equal(priceText({ price: '11.5' }), '11.50');
  assert.equal(priceText({ price: '1,150.00' }), '1150.00');
});

test('totalText of a simple cart', () => {
  const products = [{ id: 1, sku: 'POT-CLAY', name: 'Clay teapot', price: '48' }];
  assert.equal(totalText(products, [{ sku: 'POT-CLAY', qty: 2 }]), '96.00');
  assert.throws(() => totalText(products, [{ sku: 'NOPE', qty: 1 }]), /unknown_sku/);
});
PB_TASK_EOF

cat > tests/store.test.js <<'PB_TASK_EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { load, save } = require('../src/store');

test('load brings an old file to the current schema; save writes it back', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tea-store-'));
  try {
    const file = path.join(dir, 'p.json');
    fs.writeFileSync(file, JSON.stringify({ schemaVersion: 0, products: [{ id: 1, sku: 'tea-ool', name: 'Oolong', price: '1' }] }));
    const data = load(file);
    assert.equal(data.products[0].sku, 'TEA-OOL');
    save(file, data);
    assert.deepEqual(load(file), data);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('the shipped catalog loads', () => {
  const data = load(path.join(__dirname, '..', 'data', 'products.json'));
  assert.equal(data.products.length, 5);
});
PB_TASK_EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git -c core.excludesFile=/dev/null add -f -A
GIT_AUTHOR_DATE='2026-06-02T07:10:00Z' GIT_COMMITTER_DATE='2026-06-02T07:10:00Z' git commit -q -m "Catalog, cart and data migrations"
