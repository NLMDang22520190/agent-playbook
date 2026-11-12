// PB-HIDDEN-CANARY:pattern-31-price-cents-migration
// Hidden PASS_TO_PASS test: what already worked keeps working (before and after the change): migration 1 upper-cases
// the skus of a version-0 dataset (migrate runs every migration above the data's schemaVersion, so the result is at
// least version 1), and priceText of a legacy price "5" is "5.00".
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const SRC = path.join(__dirname, '..', 'src');
const { migrate } = require(path.join(SRC, 'migrate.js'));
const { priceText } = require(path.join(SRC, 'catalog.js'));

test('migration 1 upper-cases the skus of a version-0 dataset', () => {
  const data = {
    schemaVersion: 0,
    products: [
      { id: 7, sku: 'tea-blk', name: 'Black tea', price: '4.20' },
      { id: 8, sku: 'Cup-S', name: 'Small cup', price: '3' },
    ],
  };
  const out = migrate(JSON.parse(JSON.stringify(data)));
  assert.deepEqual(out.products.map((p) => p.sku), ['TEA-BLK', 'CUP-S']);
  assert.deepEqual(out.products.map((p) => [p.id, p.name]), [[7, 'Black tea'], [8, 'Small cup']]);
  assert.ok(out.schemaVersion >= 1, `schemaVersion ${out.schemaVersion} is at least 1`);
});

test('priceText of a legacy price "5" is "5.00"', () => {
  assert.equal(priceText({ id: 9, sku: 'PIN-5', name: 'Pin', price: '5' }), '5.00');
});
