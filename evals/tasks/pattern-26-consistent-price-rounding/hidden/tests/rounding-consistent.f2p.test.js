// PB-HIDDEN-CANARY:pattern-26-consistent-price-rounding
// Hidden FAIL_TO_PASS test: a new invoice's total equals the cart total of the same lines, stored and printed, for
// carts with fractions of a cent (.5 exactly, below and above, one and several lines). Any one rounding is accepted
// (per line or on the sum; half up, half even, down or up; the cart may change too): the total is an integer of cents
// within one cent per line of the exact amount, and cart and invoice agree.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const SRC = path.join(__dirname, '..', 'src');
const { seedStore } = require(path.join(SRC, 'store.js'));
const { cartTotal } = require(path.join(SRC, 'cart.js'));
const { issueInvoice, printInvoice } = require(path.join(SRC, 'invoice.js'));
const { formatCents } = require(path.join(SRC, 'money.js'));

const L = (sku, unitPrice, qty, discountPct) => ({ sku, unitPrice, qty, discountPct });
const CARTS = [
  [L('POSTER', 2475, 1, 10), L('TUBE', 199, 3, 10)],
  [L('MUG-BLUE', 1230, 1, 15), L('CARD', 350, 2, 0)],
  [L('MUG-BLUE', 1230, 1, 15)],
  [L('TEE-L', 1999, 2, 25)],
  [L('TEE-M', 1999, 1, 25), L('TEE-S', 1999, 1, 25), L('CAP', 1250, 1, 30)],
  [L('PEN', 199, 7, 15), L('PAD', 333, 3, 5)],
  [L('CARD', 350, 2, 0)],
];
// exact amount of the cart in hundredths of a cent (an integer)
const exact100 = (lines) => lines.reduce((s, l) => s + l.unitPrice * l.qty * (100 - l.discountPct), 0);

test('AC a new invoice has the cart total of its lines', () => {
  for (const lines of CARTS) {
    const store = seedStore();
    const cart = cartTotal(lines);
    const inv = issueInvoice(store, lines.map((l) => ({ ...l })), '2026-10-26');
    assert.equal(inv.total, cart, `invoice ${inv.total} vs cart ${cart} for ${JSON.stringify(lines)}`);
  }
});

test('AC the totals are whole cents close to the exact amount', () => {
  for (const lines of CARTS) {
    const cart = cartTotal(lines);
    assert.ok(Number.isInteger(cart), `cart total ${cart} is an integer`);
    assert.ok(Math.abs(cart * 100 - exact100(lines)) < 100 * lines.length, `cart total ${cart} near ${exact100(lines) / 100}`);
  }
});

test('AC the printed total of a new invoice is the cart total', () => {
  for (const lines of CARTS) {
    const store = seedStore();
    const inv = issueInvoice(store, lines.map((l) => ({ ...l })), '2026-10-26');
    const text = printInvoice(store, inv.id);
    const row = String(text).split('\n').find((r) => r.startsWith('Total:'));
    assert.equal(row, `Total: ${formatCents(cartTotal(lines))}`, String(text));
  }
});
