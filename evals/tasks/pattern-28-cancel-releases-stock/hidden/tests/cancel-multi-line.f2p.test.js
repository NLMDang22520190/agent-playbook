// PB-HIDDEN-CANARY:pattern-28-cancel-releases-stock
// Hidden FAIL_TO_PASS test: docs/stock-rules.md: available = on hand - reserved; cancelling a placed order returns
// all its reserved units (every line, also two lines of the same sku) and no other order's; cancelling an order that
// is already cancelled returns quietly and changes nothing; a place that throws out_of_stock reserves nothing.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const SRC = path.join(__dirname, '..', 'src');
const { createInventory } = require(path.join(SRC, 'inventory.js'));
const { createOrders } = require(path.join(SRC, 'orders.js'));

function fresh() {
  const inventory = createInventory({ A: 10, B: 5 });
  return { inventory, orders: createOrders(inventory) };
}
const avail = (inv) => ({ A: inv.available('A'), B: inv.available('B') });
const isErr = (msg) => (e) => e instanceof Error && e.message === msg;

test('AC cancelling a two-line order returns every line', () => {
  const { inventory, orders } = fresh();
  orders.place('o1', [{ sku: 'A', qty: 2 }, { sku: 'B', qty: 3 }]);
  assert.deepEqual(avail(inventory), { A: 8, B: 2 });
  orders.cancel('o1');
  assert.equal(orders.status('o1'), 'cancelled');
  assert.deepEqual(avail(inventory), { A: 10, B: 5 });
});

test('AC cancelling an order with the same sku on two lines returns both', () => {
  const { inventory, orders } = fresh();
  orders.place('o2', [{ sku: 'A', qty: 1 }, { sku: 'A', qty: 2 }]);
  assert.equal(inventory.available('A'), 7);
  orders.cancel('o2');
  assert.equal(inventory.available('A'), 10);
});

test('AC cancelling an already cancelled order returns quietly and changes nothing', () => {
  const { inventory, orders } = fresh();
  orders.place('o2', [{ sku: 'A', qty: 1 }, { sku: 'A', qty: 2 }]);
  orders.cancel('o2');
  assert.doesNotThrow(() => orders.cancel('o2'));
  assert.equal(orders.status('o2'), 'cancelled');
  assert.deepEqual(avail(inventory), { A: 10, B: 5 });
  assert.equal(inventory.onHand('A'), 10);
});

test('AC a place that throws out_of_stock reserves nothing', () => {
  const { inventory, orders } = fresh();
  assert.throws(() => orders.place('o3', [{ sku: 'A', qty: 4 }, { sku: 'B', qty: 9 }]), isErr('out_of_stock'));
  assert.deepEqual(avail(inventory), { A: 10, B: 5 });
});

test('AC cancelling one order keeps the units another open order reserved', () => {
  const { inventory, orders } = fresh();
  orders.place('o4', [{ sku: 'A', qty: 3 }]);
  orders.place('o5', [{ sku: 'A', qty: 2 }]);
  assert.equal(inventory.available('A'), 5);
  orders.cancel('o5');
  assert.equal(inventory.available('A'), 7);
  assert.equal(inventory.onHand('A'), 10);
  orders.cancel('o4');
  assert.equal(inventory.available('A'), 10);
});
