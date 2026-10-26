// PB-HIDDEN-CANARY:pattern-12-hidden-receipt
// Hidden PASS_TO_PASS test: displayName() keeps its documented fallback order: name, else company, else e-mail.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { displayName } = require(path.join(__dirname, '..', 'src', 'names.js'));

test('name first', () => {
  assert.equal(displayName({ name: 'Le Van Nam', company: 'Hoa Sen Trading', email: 'nam@hoasen.example' }), 'Le Van Nam');
});

test('company when the name is missing or empty', () => {
  assert.equal(displayName({ company: 'Hoa Sen Trading', email: 'ap@hoasen.example' }), 'Hoa Sen Trading');
  assert.equal(displayName({ name: '', company: 'Hoa Sen Trading', email: 'ap@hoasen.example' }), 'Hoa Sen Trading');
});

test('e-mail last', () => {
  assert.equal(displayName({ email: 'minh@example.com' }), 'minh@example.com');
});
