#!/usr/bin/env bash
# Builds the task repo in $1: the shop of project-01-order-flow (without returns) plus a catalog module whose listProducts disagrees with its doc (offline, fixed author and date). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
here="$(cd "$(dirname "$0")" && pwd)"
bash "$here/../project-01-order-flow/setup.sh" "$dest"
cd "$dest"

cat > docs/catalog.md <<'PB_TASK_EOF'
# Catalog

`listProducts(products)` returns the products sorted by name, A to Z, ignoring case. A product is `{ sku, name, priceCents }`.
PB_TASK_EOF

cat > src/catalog.js <<'PB_TASK_EOF'
'use strict';

// The product list of the shop page: [{ sku, name, priceCents }].
function listProducts(products) {
  return products.slice().sort((a, b) => a.priceCents - b.priceCents);
}

module.exports = { listProducts };
PB_TASK_EOF

cat > tests/catalog.test.js <<'PB_TASK_EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { listProducts } = require('../src/catalog');

test('listProducts returns every product', () => {
  const products = [{ sku: 'b', name: 'Bag', priceCents: 900 }, { sku: 'a', name: 'Apron', priceCents: 1200 }];
  assert.equal(listProducts(products).length, 2);
});
PB_TASK_EOF

git -c core.excludesFile=/dev/null add -f -A
GIT_AUTHOR_DATE='2026-02-11T10:00:00Z' GIT_COMMITTER_DATE='2026-02-11T10:00:00Z' git commit -q -m "Catalog module"
