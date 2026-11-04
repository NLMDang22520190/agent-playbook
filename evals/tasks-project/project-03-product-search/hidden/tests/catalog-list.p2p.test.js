// PB-HIDDEN-CANARY:project-03-product-search
// Hidden PASS_TO_PASS test: listProducts still returns every product.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { listProducts } = require('../src/catalog');

test('every product comes back and the input is not changed', () => {
  const products = [{ sku: 'b', name: 'Bag', priceCents: 900 }, { sku: 'a', name: 'Apron', priceCents: 1200 }];
  const copy = products.map((p) => ({ ...p }));
  assert.equal(listProducts(products).length, 2);
  assert.deepEqual(products, copy);
});
