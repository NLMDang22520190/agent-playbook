// PB-HIDDEN-CANARY:pattern-12-hidden-receipt
// Hidden FAIL_TO_PASS test: the invoice addresses the customer by displayName() (docs/naming.md; the prompt names the
// invoice): name, else company, else e-mail.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { invoiceHeader } = require(path.join(__dirname, '..', 'src', 'docs', 'invoice.js'));

function billTo(customer) {
  return invoiceHeader({ id: 'INV-7001', customer }).split('\n')[0];
}

test('a customer with a name is billed by name, not by e-mail', () => {
  assert.equal(billTo({ name: 'Tran Thi Lan', email: 'lan@example.com' }), 'Bill to: Tran Thi Lan');
});

test('a company-only customer is billed by company', () => {
  assert.equal(billTo({ company: 'Hoa Sen Trading', email: 'ap@hoasen.example' }), 'Bill to: Hoa Sen Trading');
});

test('name wins over company', () => {
  assert.equal(billTo({ name: 'Le Van Nam', company: 'Hoa Sen Trading', email: 'nam@hoasen.example' }), 'Bill to: Le Van Nam');
});
