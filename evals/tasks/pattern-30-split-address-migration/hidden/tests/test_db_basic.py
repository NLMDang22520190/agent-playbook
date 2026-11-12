# PB-HIDDEN-CANARY:pattern-30-split-address-migration
"""Hidden PASS_TO_PASS test: what already worked keeps working (before and after the change): migrate(conn) on a fresh
database creates the customers table with id, name, address and phone, and get_address returns a new row's address
text as it was stored."""
import os
import shutil
import tempfile
import unittest

from src.customers import get_address
from src.db import connect, migrate


class DbBasic(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="pbo30b.")
        self.conn = connect(os.path.join(self.dir, "fresh.db"))

    def tearDown(self):
        self.conn.close()
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_fresh_migrate_creates_customers_with_phone(self):
        migrate(self.conn)
        cols = [r[1] for r in self.conn.execute("PRAGMA table_info(customers)").fetchall()]
        for c in ("id", "name", "address", "phone"):
            self.assertIn(c, cols)

    def test_get_address_of_a_new_row(self):
        migrate(self.conn)
        self.conn.execute("INSERT INTO customers (id, name, address, phone) VALUES (?, ?, ?, ?)",
                          (42, "Giang", "9 Nguyen Hue, Quan 1, HCM", "+84 90 000 0042"))
        self.conn.commit()
        self.assertEqual(get_address(self.conn, 42), "9 Nguyen Hue, Quan 1, HCM")


if __name__ == "__main__":
    unittest.main()
