#!/usr/bin/env bash
# Builds the task repo in $1: the customer database of a small web shop, in python with sqlite3 and numbered migrations, where the address is one text column (offline, fixed author and date). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest")" ]; }; then
  echo "setup: refusing non-empty $dest" >&2
  exit 2
fi
mkdir -p "$dest"
cd "$dest"
mkdir -p docs src/migrations tests

cat > README.md <<'PB_TASK_EOF'
# shop-customers-db

Customer database of a small web shop (sqlite3).

- `src/db.py`: `connect(path)` opens the database; `migrate(conn, target=None)` brings the schema up to date.
- `src/migrations/NNN_name.py`: one module per schema change, with `VERSION` (int) and `up(conn)`.
- `src/customers.py`: `get_address(conn, cid)` and the other customer queries.
- `src/invoicing.py`: `export_rows(conn)`, the customer lines of the monthly invoicing export.

Python 3.8+, standard library only. Tests: `python3 -m unittest discover -s tests -t .` from the repo root.
Schema changes: `docs/migrations.md`. Address format: `docs/address-format.md`. How we work: `CONTRIBUTING.md`.
PB_TASK_EOF

cat > CONTRIBUTING.md <<'PB_TASK_EOF'
# Contributing

- Keep changes small and covered by a test under `tests/` (`unittest`).
- The production database already holds customers: a schema change is a new migration under `src/migrations/`
  (see `docs/migrations.md`), never an edit of a migration that has already run.
- Read `docs/address-format.md` before touching addresses.
PB_TASK_EOF

cat > docs/migrations.md <<'PB_TASK_EOF'
# Migrations

- Each schema change is a module `src/migrations/NNN_name.py` with `VERSION = NNN` (an int, one higher than the last
  one) and `up(conn)`, which changes the schema and the rows that already exist.
- `migrate(conn, target=None)` (`src/db.py`) runs, in VERSION order, every migration whose VERSION is above the
  version stored in the table `schema_version` and at most `target` (all of them when `target` is None), and stores
  each VERSION after it ran. A migration whose VERSION is at or below the stored version is skipped, so running
  `migrate` again changes nothing.
- A migration that already ran in production is never edited; a fix is a new migration.
PB_TASK_EOF

cat > docs/address-format.md <<'PB_TASK_EOF'
# Address format

- A customer's address is stored as one text, `street, district, city`. The district is optional (`street, city`).
- The street itself may contain commas (`Lot 5, Block B, 12 Hang Bai`).
- Each part is trimmed (spaces around the commas and at both ends are not part of it).
- The city is the last part; the district is the part before it when the address has 3 or more parts; the street is
  the rest, joined with ", ". With 2 parts there is no district.
- A customer without an address (NULL) has no street, district or city (all NULL).
- The `address` text is read as it is by the invoicing export (`src/invoicing.py`) and by `get_address`; it is not
  reformatted or removed.
- Shipping labels need the city on its own.
PB_TASK_EOF

: > src/__init__.py
: > tests/__init__.py

cat > src/db.py <<'PB_TASK_EOF'
"""sqlite3 connection and schema migrations (docs/migrations.md)."""
import importlib.util
import os
import sqlite3

MIGRATIONS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "migrations")


def connect(path):
    return sqlite3.connect(path)


def _load(path):
    name = "migration_" + os.path.splitext(os.path.basename(path))[0]
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def migrations():
    """The migration modules, in VERSION order."""
    names = [n for n in os.listdir(MIGRATIONS_DIR) if n[:3].isdigit() and n.endswith(".py")]
    mods = [_load(os.path.join(MIGRATIONS_DIR, n)) for n in names]
    return sorted(mods, key=lambda m: m.VERSION)


def current_version(conn):
    conn.execute("CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL)")
    return conn.execute("SELECT MAX(version) FROM schema_version").fetchone()[0] or 0


def migrate(conn, target=None):
    """Runs the migrations above the stored version and at most target (all when None); returns the new version."""
    done = current_version(conn)
    for m in migrations():
        if m.VERSION <= done or (target is not None and m.VERSION > target):
            continue
        m.up(conn)
        conn.execute("INSERT INTO schema_version (version) VALUES (?)", (m.VERSION,))
        conn.commit()
        done = m.VERSION
    return done
PB_TASK_EOF

cat > src/migrations/001_customers.py <<'PB_TASK_EOF'
"""The customers table."""
VERSION = 1


def up(conn):
    conn.execute("CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT, address TEXT)")
PB_TASK_EOF

cat > src/migrations/002_phone.py <<'PB_TASK_EOF'
"""A phone number per customer (optional)."""
VERSION = 2


def up(conn):
    conn.execute("ALTER TABLE customers ADD COLUMN phone TEXT")
PB_TASK_EOF

cat > src/customers.py <<'PB_TASK_EOF'
"""Customer queries."""


def get_address(conn, cid):
    """The address text of customer cid, as stored (None when the customer has none)."""
    row = conn.execute("SELECT address FROM customers WHERE id = ?", (cid,)).fetchone()
    return row[0] if row else None


def find_by_name(conn, name):
    return [r[0] for r in conn.execute("SELECT id FROM customers WHERE name = ? ORDER BY id", (name,))]
PB_TASK_EOF

cat > src/invoicing.py <<'PB_TASK_EOF'
"""Customer lines of the monthly invoicing export: id;name;address (the address text as stored)."""


def export_rows(conn):
    rows = conn.execute("SELECT id, name, address FROM customers ORDER BY id").fetchall()
    return ["%d;%s;%s" % (cid, name, address or "") for cid, name, address in rows]
PB_TASK_EOF

cat > tests/test_migrate_versions.py <<'PB_TASK_EOF'
import os
import shutil
import tempfile
import unittest

from src.db import connect, current_version, migrate


class MigrateVersions(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.conn = connect(os.path.join(self.dir, "t.db"))

    def tearDown(self):
        self.conn.close()
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_target_stops_early_and_a_second_run_continues(self):
        self.assertEqual(migrate(self.conn, target=1), 1)
        cols = [r[1] for r in self.conn.execute("PRAGMA table_info(customers)")]
        self.assertNotIn("phone", cols)
        self.assertGreaterEqual(migrate(self.conn), 2)
        self.assertEqual(migrate(self.conn), current_version(self.conn))


if __name__ == "__main__":
    unittest.main()
PB_TASK_EOF

cat > tests/test_invoicing_export.py <<'PB_TASK_EOF'
import os
import shutil
import tempfile
import unittest

from src.db import connect, migrate
from src.invoicing import export_rows


class InvoicingExport(unittest.TestCase):
    def test_export_keeps_the_address_text(self):
        d = tempfile.mkdtemp()
        try:
            conn = connect(os.path.join(d, "t.db"))
            migrate(conn)
            conn.execute("INSERT INTO customers (id, name, address) VALUES (7, 'Hoa', '3 Hai Ba Trung, Quan 1, HCM')")
            conn.execute("INSERT INTO customers (id, name, address) VALUES (8, 'Khoa', NULL)")
            conn.commit()
            self.assertEqual(export_rows(conn), ["7;Hoa;3 Hai Ba Trung, Quan 1, HCM", "8;Khoa;"])
            conn.close()
        finally:
            shutil.rmtree(d, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
PB_TASK_EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git -c core.excludesFile=/dev/null add -f -A
GIT_AUTHOR_DATE='2026-03-17T02:30:00Z' GIT_COMMITTER_DATE='2026-03-17T02:30:00Z' git commit -q -m "Customers database with migrations"
