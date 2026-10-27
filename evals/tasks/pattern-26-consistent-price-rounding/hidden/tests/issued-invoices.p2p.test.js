// PB-HIDDEN-CANARY:pattern-26-consistent-price-rounding
// Hidden PASS_TO_PASS test: the invoices issued before the change keep their lines and totals, stored and printed
// (docs/invoicing.md: an issued invoice never changes; a wrong one gets a credit note), also after a new invoice is
// issued. INV-0003 is the reported one: it keeps EUR 27.64.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const SRC = path.join(__dirname, '..', 'src');
const { seedStore } = require(path.join(SRC, 'store.js'));
const { issueInvoice, printInvoice } = require(path.join(SRC, 'invoice.js'));

const ISSUED = { 'INV-0001': 1745, 'INV-0002': 2998, 'INV-0003': 2764 };
const PRINTED = { 'INV-0001': 'EUR 17.45', 'INV-0002': 'EUR 29.98', 'INV-0003': 'EUR 27.64' };
const clone = (v) => JSON.parse(JSON.stringify(v));
const totalRow = (text) => String(text).split('\n').find((r) => r.startsWith('Total:'));

test('issued invoices keep their stored totals', () => {
  const store = seedStore();
  for (const [id, total] of Object.entries(ISSUED)) {
    const inv = store.invoices.find((i) => i.id === id);
    assert.ok(inv, `${id} is in the store`);
    assert.equal(inv.total, total, `${id} total`);
  }
});

test('a reprint of an issued invoice shows the total it was issued with', () => {
  const store = seedStore();
  for (const [id, shown] of Object.entries(PRINTED)) {
    assert.equal(totalRow(printInvoice(store, id)), `Total: ${shown}`, `${id} reprint`);
  }
});

test('issuing a new invoice leaves the issued ones as they were', () => {
  const store = seedStore();
  const before = clone(store.invoices);
  const printed = before.map((i) => printInvoice(store, i.id));
  const inv = issueInvoice(store, [{ sku: 'MUG-BLUE', unitPrice: 1230, qty: 1, discountPct: 15 }], '2026-10-26');
  assert.equal(inv.id, 'INV-0004');
  assert.deepEqual(store.invoices.slice(0, before.length), before);
  assert.deepEqual(before.map((i) => printInvoice(store, i.id)), printed);
});

test('printInvoice of an unknown id is null', () => {
  assert.equal(printInvoice(seedStore(), 'INV-9999'), null);
});
