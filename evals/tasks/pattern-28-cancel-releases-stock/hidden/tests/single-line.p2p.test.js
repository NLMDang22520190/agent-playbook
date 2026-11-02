// PB-HIDDEN-CANARY:pattern-28-cancel-releases-stock
// Hidden PASS_TO_PASS test: what already worked keeps working (before and after the change): a single-line order is
// reserved and its cancel returns the units; a shipped order consumes its reservation (on hand drops) and cannot be
// cancelled (docs/stock-rules.md: Error('already_shipped'), stock unchanged).
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const SRC = path.join(__dirname, '..', 'src');
const { createInventory } = require(path.join(SRC, 'inventory.js'));
const { createOrders } = require(path.join(SRC, 'orders.js'));

test('a single-line order reserves and its cancel returns the units', () => {
  const inventory = createInventory({ A: 10, B: 5 });
  const orders = createOrders(inventory);
  orders.place('s1', [{ sku: 'A', qty: 3 }]);
  assert.equal(inventory.available('A'), 7);
  assert.equal(inventory.onHand('A'), 10);
  orders.cancel('s1');
  assert.equal(orders.status('s1'), 'cancelled');
  assert.equal(inventory.available('A'), 10);
  assert.equal(inventory.available('B'), 5);
});

test('a shipped order cannot be cancelled and its stock stays shipped', () => {
  const inventory = createInventory({ A: 10, B: 5 });
  const orders = createOrders(inventory);
  orders.place('s2', [{ sku: 'B', qty: 2 }]);
  orders.ship('s2');
  assert.equal(orders.status('s2'), 'shipped');
  assert.equal(inventory.onHand('B'), 3);
  assert.equal(inventory.available('B'), 3);
  assert.throws(() => orders.cancel('s2'), (e) => e instanceof Error && e.message === 'already_shipped');
  assert.equal(orders.status('s2'), 'shipped');
  assert.equal(inventory.onHand('B'), 3);
  assert.equal(inventory.available('B'), 3);
  assert.equal(inventory.onHand('A'), 10);
});
