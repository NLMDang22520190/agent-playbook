// PB-HIDDEN-CANARY:pattern-18-split-name-migration
// Hidden FAIL_TO_PASS test: migration 4 splits users.name into first_name / last_name (last_name = text after the last
// space; one word -> last_name ''), keeps name (expand/contract, docs/migrations.md), and its down restores the data
// exactly (round trip). fullName reads the new fields.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const SRC = path.join(__dirname, '..', 'src');
const { migrate } = require(path.join(SRC, 'migrate.js'));
const { fullName } = require(path.join(SRC, 'users.js'));

const clone = (v) => JSON.parse(JSON.stringify(v));
// a store at schema 0; migrations 001-003 bring it to schema 3
const V0 = () => ({
  schema_version: 0,
  tables: {
    users: [
      { id: 1, name: 'Ada Lovelace', email: 'ada@example.com' },
      { id: 2, name: 'Mary Ann Smith', email: 'mary@example.com' },
      { id: 3, name: 'Cher', email: 'cher@example.com' },
      { id: 4, name: 'Jean-Luc  Picard', email: 'jl@example.com' },
      { id: 5, name: '', email: 'anon@example.com' },
    ],
    orders: [{ id: 10, user_id: 1, total: 1200 }, { id: 11, user_id: 4, total: 350 }],
  },
});
const at3 = () => migrate(V0(), 3);
const byId = (db, id) => db.tables.users.find((u) => u.id === id);

test('AC migrating 3 -> 4 sets schema_version 4', () => {
  assert.equal(migrate(at3(), 4).schema_version, 4);
});

test('AC up splits at the last space: Ada Lovelace, Mary Ann Smith, Cher', () => {
  const db = migrate(at3(), 4);
  assert.deepEqual([byId(db, 1).first_name, byId(db, 1).last_name], ['Ada', 'Lovelace']);
  assert.deepEqual([byId(db, 2).first_name, byId(db, 2).last_name], ['Mary Ann', 'Smith']);
  assert.deepEqual([byId(db, 3).first_name, byId(db, 3).last_name], ['Cher', '']);
});

test('AC up keeps the old name field unchanged (expand/contract)', () => {
  const before = at3();
  const names = before.tables.users.map((u) => u.name);
  const db = migrate(before, 4);
  assert.deepEqual(db.tables.users.map((u) => u.name), names);
});

test('AC down after up restores the store exactly, double spaces and empty names included', () => {
  const db3 = at3();
  const snapshot = clone(db3);
  const back = migrate(migrate(db3, 4), 3);
  assert.deepEqual(clone(back), snapshot);
});

test('AC fullName reads first_name and last_name, not the old name', () => {
  assert.equal(fullName({ first_name: 'Mary Ann', last_name: 'Smith', name: 'stale' }), 'Mary Ann Smith');
});

test('AC fullName of a one-word name has no trailing space', () => {
  assert.equal(fullName({ first_name: 'Cher', last_name: '', name: 'stale' }), 'Cher');
});
