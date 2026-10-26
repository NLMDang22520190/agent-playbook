// PB-HIDDEN-CANARY:pattern-12-hidden-receipt
// Hidden FAIL_TO_PASS test: the receipt e-mail is a customer-facing document too, so it greets the customer by
// displayName() (docs/naming.md "Every customer-facing document (invoice, receipt e-mail, packing slip) ...").
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { receiptGreeting } = require(path.join(__dirname, '..', 'src', 'mail', 'receipt.js'));

function greet(customer) {
  return receiptGreeting({ id: 'ORD-7001', customer });
}

test('a customer with a name is greeted by name', () => {
  assert.equal(greet({ name: 'Tran Thi Lan', email: 'lan@example.com' }), 'Xin chào Tran Thi Lan,');
});

test('a company-only customer is greeted by company', () => {
  assert.equal(greet({ company: 'Hoa Sen Trading', email: 'ap@hoasen.example' }), 'Xin chào Hoa Sen Trading,');
});

test('a customer with only an e-mail is greeted by the full address', () => {
  assert.equal(greet({ email: 'minh@example.com' }), 'Xin chào minh@example.com,');
});
