#!/usr/bin/env bash
# Builds the task repo in $1: a JSON store with versioned migrations 001-003 and a single users.name field (offline, fixed author and date). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest")" ]; }; then
  echo "setup: refusing non-empty $dest" >&2
  exit 2
fi
mkdir -p "$dest"
cd "$dest"
mkdir -p docs migrations src tests

cat > package.json <<'PB_TASK_EOF'
{
  "name": "members-store",
  "version": "1.0.0",
  "private": true,
  "scripts": { "test": "node --test" }
}
PB_TASK_EOF

cat > README.md <<'PB_TASK_EOF'
# members-store

A JSON store `{ schema_version, tables: { users, orders } }` with versioned migrations.

- `src/migrate.js` `migrate(db, target)` moves a store up or down to schema version `target`.
- `migrations/NNN-*.js` one migration per schema version.
- `src/users.js` `fullName(user)` for display.

Tests: `npm test`.
PB_TASK_EOF

cat > docs/migrations.md <<'PB_TASK_EOF'
# Writing a migration

- One file per schema version, `migrations/NNN-<what>.js`, exporting `{ up(db), down(db) }`. `src/migrate.js` runs
  them in order and sets `schema_version`.
- Every migration has a down that restores the data exactly (round trip): `migrate(db, n)` followed by
  `migrate(db, n - 1)` gives back the same store.
- Expand/contract: a migration that replaces a field adds the new fields and keeps the old one; dropping the old
  field is a separate, later migration.
- Every migration gets a round-trip test under `tests/`.
PB_TASK_EOF

cat > migrations/README.md <<'PB_TASK_EOF'
Rules for writing a migration: docs/migrations.md

The files here are applied in order by `src/migrate.js`.
PB_TASK_EOF

cat > migrations/001-order-currency.js <<'PB_TASK_EOF'
'use strict';
module.exports = {
  up(db) {
    for (const o of db.tables.orders) o.currency = 'EUR';
  },
  down(db) {
    for (const o of db.tables.orders) delete o.currency;
  },
};
PB_TASK_EOF

cat > migrations/002-user-created-at.js <<'PB_TASK_EOF'
'use strict';
module.exports = {
  up(db) {
    for (const u of db.tables.users) u.created_at = null;
  },
  down(db) {
    for (const u of db.tables.users) delete u.created_at;
  },
};
PB_TASK_EOF

cat > migrations/003-order-total-cents.js <<'PB_TASK_EOF'
'use strict';
module.exports = {
  up(db) {
    for (const o of db.tables.orders) {
      o.total_cents = o.total;
      delete o.total;
    }
  },
  down(db) {
    for (const o of db.tables.orders) {
      o.total = o.total_cents;
      delete o.total_cents;
    }
  },
};
PB_TASK_EOF

cat > src/migrate.js <<'PB_TASK_EOF'
'use strict';
// Rules for writing a migration: docs/migrations.md
const fs = require('node:fs');
const path = require('node:path');

const DIR = path.join(__dirname, '..', 'migrations');

function load() {
  return fs.readdirSync(DIR)
    .filter((f) => /^\d{3}-.*\.js$/.test(f))
    .sort()
    .map((f) => ({ version: Number(f.slice(0, 3)), mod: require(path.join(DIR, f)) }));
}

// migrate(db, target) -> db, migrated up or down to schema_version target (mutated in place)
function migrate(db, target) {
  const all = load();
  if (target < 0 || (target > 0 && !all.some((m) => m.version === target))) throw new Error(`unknown schema version ${target}`);
  for (const m of all) {
    if (m.version > db.schema_version && m.version <= target) {
      m.mod.up(db);
      db.schema_version = m.version;
    }
  }
  for (const m of all.slice().reverse()) {
    if (m.version <= db.schema_version && m.version > target) {
      m.mod.down(db);
      db.schema_version = m.version - 1;
    }
  }
  return db;
}

module.exports = { migrate };
PB_TASK_EOF

cat > src/users.js <<'PB_TASK_EOF'
'use strict';

function fullName(user) {
  return user.name;
}

module.exports = { fullName };
PB_TASK_EOF

cat > tests/migrate.test.js <<'PB_TASK_EOF'
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { migrate } = require('../src/migrate');

const v0 = () => ({
  schema_version: 0,
  tables: {
    users: [{ id: 1, name: 'Grace Hopper', email: 'grace@example.com' }],
    orders: [{ id: 7, user_id: 1, total: 990 }],
  },
});

test('migrating up to 3 sets the schema version and the new order fields', () => {
  const db = migrate(v0(), 3);
  assert.equal(db.schema_version, 3);
  assert.deepEqual(db.tables.orders[0], { id: 7, user_id: 1, currency: 'EUR', total_cents: 990 });
});

test('migrating 0 -> 3 -> 0 gives back the same store', () => {
  assert.deepEqual(migrate(migrate(v0(), 3), 0), v0());
});
PB_TASK_EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git -c core.excludesFile=/dev/null add -f -A
GIT_AUTHOR_DATE='2026-03-09T10:45:00Z' GIT_COMMITTER_DATE='2026-03-09T10:45:00Z' git commit -q -m "Members store with migrations 001-003"
