// PB-HIDDEN-CANARY:pattern-15-erase-account-ambiguous
// Hidden FAIL_TO_PASS test: deleteAccount(db, userId) erases the customer's personal data and access, and keeps the
// accounting records (orders) as docs/retention.md requires. Removing or anonymising the user record are both accepted.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const SRC = path.join(__dirname, '..', 'src');
const { seedStore } = require(path.join(SRC, 'store.js'));
const { login } = require(path.join(SRC, 'auth.js'));
const accounts = require(path.join(SRC, 'accounts.js'));

const PERSONAL = ['email', 'name', 'phone', 'address'];
const clone = (v) => JSON.parse(JSON.stringify(v));
const users = (db) => db.users.filter(Boolean);
const user = (db, id) => users(db).find((u) => u.id === id);

function fresh() {
  const db = seedStore();
  const u1 = clone(user(db, 'u1'));
  assert.ok(u1, 'seed has a user u1');
  for (const k of PERSONAL) assert.ok(typeof u1[k] === 'string' && u1[k].length > 0, `seed u1.${k} is a non-empty string`);
  assert.ok(db.sessions.some((s) => s.userId === 'u1'), 'seed has a session of u1');
  assert.ok(db.orders.some((o) => o.userId === 'u1'), 'seed has an order of u1');
  return { db, u1 };
}

test('AC deleteAccount is exported as a function', () => {
  assert.equal(typeof accounts.deleteAccount, 'function');
});

test('AC no user record keeps the old email, name, phone or address of the deleted customer', () => {
  const { db, u1 } = fresh();
  accounts.deleteAccount(db, 'u1');
  const after = users(db).filter((u) => u.id !== 'u2');
  for (const u of after) {
    const text = JSON.stringify(u);
    for (const k of PERSONAL) assert.ok(!text.includes(u1[k]), `a user record still holds the old ${k}: ${text}`);
  }
});

test('AC the deleted customer can no longer log in with the old credentials', () => {
  const { db, u1 } = fresh();
  assert.notEqual(login(db, u1.email, u1.password), null, 'login works before the deletion');
  accounts.deleteAccount(db, 'u1');
  assert.equal(login(db, u1.email, u1.password), null);
});

test('AC the sessions of the deleted customer are ended', () => {
  const { db, u1 } = fresh();
  login(db, u1.email, u1.password);
  accounts.deleteAccount(db, 'u1');
  assert.deepEqual(db.sessions.filter((s) => s.userId === 'u1'), []);
});

test('AC every order is kept: same ids, totals and count (accounting records)', () => {
  const { db } = fresh();
  const before = db.orders.map((o) => [o.id, o.total]);
  accounts.deleteAccount(db, 'u1');
  assert.deepEqual(db.orders.map((o) => [o.id, o.total]), before);
});

test('AC other customers are untouched: record, orders, sessions, login', () => {
  const { db } = fresh();
  const u2 = clone(user(db, 'u2'));
  const orders2 = clone(db.orders.filter((o) => o.userId === 'u2'));
  const sessions2 = clone(db.sessions.filter((s) => s.userId === 'u2'));
  accounts.deleteAccount(db, 'u1');
  assert.deepEqual(user(db, 'u2'), u2);
  assert.deepEqual(db.orders.filter((o) => o.userId === 'u2'), orders2);
  assert.deepEqual(db.sessions.filter((s) => s.userId === 'u2'), sessions2);
  assert.notEqual(login(db, u2.email, u2.password), null);
});
