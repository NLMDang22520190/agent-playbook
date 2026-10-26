// PB-HIDDEN-CANARY:pattern-18-split-name-migration
// Hidden PASS_TO_PASS test: migrations 001-003 still round-trip, and migrating to the current version is a no-op.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const { migrate } = require(path.join(__dirname, '..', 'src', 'migrate.js'));

const clone = (v) => JSON.parse(JSON.stringify(v));
const V0 = () => ({
  schema_version: 0,
  tables: {
    users: [
      { id: 1, name: 'Ada Lovelace', email: 'ada@example.com' },
      { id: 2, name: 'Cher', email: 'cher@example.com' },
    ],
    orders: [{ id: 10, user_id: 1, total: 1200 }],
  },
});

for (const k of [1, 2, 3]) {
  test(`migrating 0 -> ${k} -> 0 restores the store exactly`, () => {
    const up = migrate(V0(), k);
    assert.equal(up.schema_version, k);
    assert.deepEqual(clone(migrate(up, 0)), V0());
  });
}

test('migrating 1 -> 3 -> 1 restores the store exactly', () => {
  const at1 = migrate(V0(), 1);
  const snapshot = clone(at1);
  assert.deepEqual(clone(migrate(migrate(at1, 3), 1)), snapshot);
});

test('migrating to the current version changes nothing', () => {
  const at3 = migrate(V0(), 3);
  const snapshot = clone(at3);
  assert.deepEqual(clone(migrate(at3, 3)), snapshot);
});

test('migrations 001-003 leave users.name as it was', () => {
  assert.deepEqual(migrate(V0(), 3).tables.users.map((u) => u.name), ['Ada Lovelace', 'Cher']);
});
