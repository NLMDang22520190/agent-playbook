// PB-HIDDEN-CANARY:project-03-product-search
// Hidden FAIL_TO_PASS test: searchProducts as the ticket describes it.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { searchProducts } = require('../src/catalog');

const P = [
  { sku: 'TB-1', name: 'travel bag', priceCents: 900 },
  { sku: 'AP-7', name: 'Apron', priceCents: 1200 },
  { sku: 'BG-3', name: 'Beach Bag', priceCents: 1500 },
  { sku: 'CX-9', name: 'Cap', priceCents: 400 },
];
const names = (r) => r.map((p) => p.name);

test('matches the name, ignoring case, sorted by name A to Z ignoring case', () => {
  assert.deepEqual(names(searchProducts(P, 'BAG')), ['Beach Bag', 'travel bag']);
});

test('matches the sku too', () => {
  assert.deepEqual(names(searchProducts(P, 'ap-7')), ['Apron']);
});

test('a query inside a word matches', () => {
  assert.deepEqual(names(searchProducts(P, 'ap')), ['Apron', 'Cap']);
});

test('an empty query returns every product, sorted by name', () => {
  assert.deepEqual(names(searchProducts(P, '')), ['Apron', 'Beach Bag', 'Cap', 'travel bag']);
});

test('no match is an empty list', () => {
  assert.deepEqual(searchProducts(P, 'zzz'), []);
});

test('the input list is not changed', () => {
  const list = [{ sku: 'z-1', name: 'Zed', priceCents: 1 }, { sku: 'a-1', name: 'Aaa', priceCents: 2 }, { sku: 'm-1', name: 'Mid', priceCents: 3 }];
  const before = JSON.stringify(list);
  searchProducts(list, '');
  searchProducts(list, 'a');
  assert.equal(JSON.stringify(list), before);
});
