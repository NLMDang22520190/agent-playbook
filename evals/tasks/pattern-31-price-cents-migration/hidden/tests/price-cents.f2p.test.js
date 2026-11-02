// PB-HIDDEN-CANARY:pattern-31-price-cents-migration
// Hidden FAIL_TO_PASS test: docs/prices.md: migration 2 turns the legacy decimal price strings (at most 2 decimals,
// some with a thousands separator such as "1,299.00") into an integer priceCents and sets schemaVersion 2; migrate
// applied twice equals once; products keep their count and their id, sku and name; priceText and totalText keep their
// output (the cart total of 3 x 19.99 + 3 x 0.29 + 10 x 0.10 is exactly 61.84). The legacy `price` field may be kept or
// removed (not checked).
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const SRC = path.join(__dirname, '..', 'src');
const { migrate } = require(path.join(SRC, 'migrate.js'));
const { priceText } = require(path.join(SRC, 'catalog.js'));
const { totalText } = require(path.join(SRC, 'cart.js'));

const clone = (v) => JSON.parse(JSON.stringify(v));
const P = (id, sku, name, price) => ({ id, sku, name, price });
const LEGACY = {
  schemaVersion: 1,
  products: [
    P(101, 'TEA-GRN', 'Green tea 100 g', '19.99'),
    P(102, 'BAG-PAPER', 'Paper bag', '0.29'),
    P(103, 'MUG-WHT', 'White mug', '12.5'),
    P(104, 'SPOON-07', 'Tea spoon', '7'),
    P(105, 'KETTLE-1299', 'Electric kettle', '1,299.00'),
    P(106, 'CARD-10', 'Gift card sleeve', '0.10'),
  ],
};
const CENTS = [1999, 29, 1250, 700, 129900, 10];
const TEXT = ['19.99', '0.29', '12.50', '7.00', '1299.00', '0.10'];

test('AC migrate sets integer priceCents and schemaVersion 2', () => {
  const out = migrate(clone(LEGACY));
  assert.equal(out.schemaVersion, 2);
  assert.deepEqual(out.products.map((p) => p.priceCents), CENTS);
  for (const p of out.products) assert.ok(Number.isInteger(p.priceCents), `${p.sku} priceCents is an integer`);
});

test('AC priceText of a migrated product equals priceText of the legacy product', () => {
  const out = migrate(clone(LEGACY));
  assert.deepEqual(out.products.map((p) => priceText(p)), TEXT);
  assert.deepEqual(clone(LEGACY).products.map((p) => priceText(p)), TEXT);
});

test('AC totalText of 3 x 19.99 + 3 x 0.29 + 10 x 0.10 is 61.84', () => {
  const out = migrate(clone(LEGACY));
  const lines = [{ sku: 'TEA-GRN', qty: 3 }, { sku: 'BAG-PAPER', qty: 3 }, { sku: 'CARD-10', qty: 10 }];
  assert.equal(totalText(out.products, lines), '61.84');
});

test('AC migrate applied twice equals once', () => {
  const once = migrate(clone(LEGACY));
  const twice = migrate(clone(once));
  assert.deepEqual(twice, once);
  assert.deepEqual(twice.products.map((p) => p.priceCents), CENTS);
});

test('AC products keep their count, id, sku and name', () => {
  const out = migrate(clone(LEGACY));
  const pick = (p) => ({ id: p.id, sku: p.sku, name: p.name });
  assert.equal(out.products.length, LEGACY.products.length);
  assert.deepEqual(out.products.map(pick), LEGACY.products.map(pick));
});
