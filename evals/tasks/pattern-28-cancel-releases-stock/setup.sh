#!/usr/bin/env bash
# Builds the task repo in $1: stock reservations of a small online shop, in node, where cancelling an order does not give back all of its units (offline, fixed author and date). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest")" ]; }; then
  echo "setup: refusing non-empty $dest" >&2
  exit 2
fi
mkdir -p "$dest"
cd "$dest"
mkdir -p docs src tests

cat > package.json <<'PB_TASK_EOF'
{
  "name": "shop-stock",
  "version": "2.1.0",
  "private": true,
  "scripts": { "test": "node --test" }
}
PB_TASK_EOF

cat > README.md <<'PB_TASK_EOF'
# shop-stock

Stock and orders of a small online shop, kept in memory.

- `src/inventory.js` `createInventory(stock)`: units on hand per sku and the units reserved by open orders;
  `reserve(orderId, sku, qty)`, `release(orderId)`, `consume(orderId)`, `available(sku)`, `onHand(sku)`.
- `src/orders.js` `createOrders(inventory, events)`: `place(orderId, lines)` with lines `[{ sku, qty }]`,
  `cancel(orderId)`, `ship(orderId)`, `status(orderId)` (`placed`, `cancelled`, `shipped`).
- `src/events.js` `createEvents()`: a small event log (`emit`, `on`, `log`) the warehouse screen listens to.

Tests: `npm test` (Node 18+). Stock rules: `docs/stock-rules.md`. How we work: `CONTRIBUTING.md`.
PB_TASK_EOF

cat > CONTRIBUTING.md <<'PB_TASK_EOF'
# Contributing

- Keep changes small and covered by a test under `tests/` (`node:test`).
- Errors are `Error` objects whose message is a short code (`out_of_stock`, `already_shipped`, `unknown_order`); the
  shop front end shows a text per code, so do not change the codes.
- `docs/stock-rules.md` is the agreed behaviour of the stock; read it before changing `src/inventory.js` or `src/orders.js`.
PB_TASK_EOF

cat > docs/stock-rules.md <<'PB_TASK_EOF'
# Stock rules

Agreed with the warehouse, 2026-03-02.

- `onHand(sku)`: units physically in the warehouse. `available(sku)` = on hand - units reserved by open orders.
  The shop sells only what is available.
- Placing an order reserves every line of it (an order may have several lines, also several lines of the same sku).
  If any line does not fit in what is available, `place` throws `Error('out_of_stock')` and reserves nothing at all:
  the stock is exactly as before the call.
- Cancelling a placed order sets its status to `cancelled` and returns all the units it reserved, on every line, and no
  units of any other order.
- Cancelling an order that is already cancelled returns quietly and changes nothing.
- Shipping an order sets its status to `shipped` and consumes its reservation: on hand drops by the shipped units.
  A shipped order cannot be cancelled: `cancel` throws `Error('already_shipped')` and the stock does not change.
- Cancelling an order id that was never placed throws `Error('unknown_order')`.
PB_TASK_EOF

cat > src/events.js <<'PB_TASK_EOF'
'use strict';
// A small in-memory event log; the warehouse screen subscribes with on(type, fn).

function createEvents() {
  const entries = [];
  const handlers = {};
  return {
    emit(type, payload) {
      entries.push({ type, payload });
      for (const fn of handlers[type] || []) fn(payload);
    },
    on(type, fn) {
      (handlers[type] = handlers[type] || []).push(fn);
    },
    log() {
      return entries.slice();
    },
  };
}

module.exports = { createEvents };
PB_TASK_EOF

cat > src/inventory.js <<'PB_TASK_EOF'
'use strict';
// Units on hand per sku and the units reserved by open orders (docs/stock-rules.md).

function createInventory(stock) {
  const onHandBySku = { ...stock };
  const reservations = {}; // orderId -> { sku, qty }

  function reserved(sku) {
    let n = 0;
    for (const r of Object.values(reservations)) if (r.sku === sku) n += r.qty;
    return n;
  }

  function available(sku) {
    return (onHandBySku[sku] || 0) - reserved(sku);
  }

  function reserve(orderId, sku, qty) {
    if (available(sku) < qty) throw new Error('out_of_stock');
    reservations[orderId] = { sku, qty };
  }

  function release(orderId) {
    delete reservations[orderId];
  }

  function consume(orderId) {
    const r = reservations[orderId];
    if (r) onHandBySku[r.sku] -= r.qty;
    delete reservations[orderId];
  }

  function onHand(sku) {
    return onHandBySku[sku] || 0;
  }

  return { reserve, release, consume, available, onHand };
}

module.exports = { createInventory };
PB_TASK_EOF

cat > src/orders.js <<'PB_TASK_EOF'
'use strict';
// Orders: place, cancel, ship (docs/stock-rules.md).
const { createEvents } = require('./events');

function createOrders(inventory, events = createEvents()) {
  const orders = {};

  function get(orderId) {
    const o = orders[orderId];
    if (!o) throw new Error('unknown_order');
    return o;
  }

  function place(orderId, lines) {
    for (const line of lines) inventory.reserve(orderId, line.sku, line.qty);
    orders[orderId] = { status: 'placed', lines: lines.map((l) => ({ ...l })) };
    events.emit('order.placed', { orderId });
  }

  function cancel(orderId) {
    const o = get(orderId);
    if (o.status === 'cancelled') return;
    if (o.status === 'shipped') throw new Error('already_shipped');
    inventory.release(orderId);
    o.status = 'cancelled';
    events.emit('order.cancelled', { orderId });
  }

  function ship(orderId) {
    const o = get(orderId);
    if (o.status !== 'placed') throw new Error(`cannot_ship_${o.status}`);
    inventory.consume(orderId);
    o.status = 'shipped';
    events.emit('order.shipped', { orderId });
  }

  function status(orderId) {
    return get(orderId).status;
  }

  return { place, cancel, ship, status };
}

module.exports = { createOrders };
PB_TASK_EOF

cat > tests/inventory.test.js <<'PB_TASK_EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createInventory } = require('../src/inventory');

test('reserve lowers available, not on hand', () => {
  const inv = createInventory({ X: 4 });
  inv.reserve('w1', 'X', 3);
  assert.equal(inv.available('X'), 1);
  assert.equal(inv.onHand('X'), 4);
  assert.throws(() => inv.reserve('w2', 'X', 2), /out_of_stock/);
});

test('an unknown sku has nothing on hand', () => {
  const inv = createInventory({});
  assert.equal(inv.onHand('Q'), 0);
  assert.equal(inv.available('Q'), 0);
});
PB_TASK_EOF

cat > tests/orders-basic.test.js <<'PB_TASK_EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createInventory } = require('../src/inventory');
const { createOrders } = require('../src/orders');
const { createEvents } = require('../src/events');

test('place, ship and the event log', () => {
  const inv = createInventory({ X: 6 });
  const events = createEvents();
  const orders = createOrders(inv, events);
  orders.place('w1', [{ sku: 'X', qty: 2 }]);
  assert.equal(orders.status('w1'), 'placed');
  orders.ship('w1');
  assert.equal(inv.onHand('X'), 4);
  assert.deepEqual(events.log().map((e) => e.type), ['order.placed', 'order.shipped']);
});

test('cancelling an unknown order throws unknown_order', () => {
  const orders = createOrders(createInventory({}));
  assert.throws(() => orders.cancel('nope'), /unknown_order/);
});
PB_TASK_EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git -c core.excludesFile=/dev/null add -f -A
GIT_AUTHOR_DATE='2026-05-06T09:40:00Z' GIT_COMMITTER_DATE='2026-05-06T09:40:00Z' git commit -q -m "Stock reservations and orders"
