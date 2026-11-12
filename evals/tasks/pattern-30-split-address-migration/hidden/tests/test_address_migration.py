# PB-HIDDEN-CANARY:pattern-30-split-address-migration
"""Hidden FAIL_TO_PASS test: a new migration adds the columns street, district and city, filled from address for the
rows that already exist (docs/address-format.md: "street, district, city" with district optional, the street may
contain commas, parts are trimmed; city is the last part, district the one before it when there are 3 or more parts,
street the rest joined with ", "; a NULL address gives NULL parts), and city_of(conn, cid) returns the city. The
address column stays as it was (the invoicing export reads it), every row stays, and running migrate again changes
no row. The rows are inserted at schema version 2 (migrate(conn, target=2)), before the new migration runs."""
import os
import shutil
import tempfile
import unittest

import src.customers as customers
from src.customers import get_address
from src.db import connect, migrate

ROWS = [
    (1, "An", "12 Ly Thuong Kiet, Hoan Kiem, Ha Noi"),
    (2, "Binh", "5 Tran Phu, Da Nang"),
    (3, "Cuong", "Lot 5, Block B, 12 Hang Bai, Hoan Kiem, Ha Noi"),
    (4, "Dung", None),
    (5, "Em", "  7 Le Loi ,  Quan 1 , HCM  "),
]
CITY = {1: "Ha Noi", 2: "Da Nang", 3: "Ha Noi", 4: None, 5: "HCM"}
STREET = {1: "12 Ly Thuong Kiet", 2: "5 Tran Phu", 3: "Lot 5, Block B, 12 Hang Bai", 4: None, 5: "7 Le Loi"}
DISTRICT = {1: "Hoan Kiem", 3: "Hoan Kiem", 4: None, 5: "Quan 1"}  # row 2: None or ""


class AddressMigration(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="pbo30.")
        self.conn = connect(os.path.join(self.dir, "shop.db"))
        migrate(self.conn, target=2)
        self.conn.executemany("INSERT INTO customers (id, name, address) VALUES (?, ?, ?)", ROWS)
        self.conn.commit()
        migrate(self.conn)

    def tearDown(self):
        self.conn.close()
        shutil.rmtree(self.dir, ignore_errors=True)

    def col(self, name, cid):
        return self.conn.execute("SELECT %s FROM customers WHERE id = ?" % name, (cid,)).fetchone()[0]

    def snapshot(self):
        return self.conn.execute("SELECT * FROM customers ORDER BY id").fetchall()

    def test_ac_city_of_each_existing_row(self):
        for cid, want in CITY.items():
            self.assertEqual(customers.city_of(self.conn, cid), want, "city_of(%d)" % cid)

    def test_ac_city_column_filled_for_existing_rows(self):
        for cid, want in CITY.items():
            self.assertEqual(self.col("city", cid), want, "city of row %d" % cid)

    def test_ac_street_and_district_columns_filled_for_existing_rows(self):
        for cid, want in STREET.items():
            self.assertEqual(self.col("street", cid), want, "street of row %d" % cid)
        for cid, want in DISTRICT.items():
            self.assertEqual(self.col("district", cid), want, "district of row %d" % cid)
        self.assertIn(self.col("district", 2), (None, ""))

    def test_ac_address_is_kept_as_is(self):
        cols = [r[1] for r in self.conn.execute("PRAGMA table_info(customers)").fetchall()]
        self.assertIn("address", cols)
        for cid, _name, address in ROWS:
            self.assertEqual(get_address(self.conn, cid), address, "get_address(%d)" % cid)
            self.assertEqual(self.col("address", cid), address, "address column of row %d" % cid)

    def test_ac_every_row_stays(self):
        self.assertEqual(self.conn.execute("SELECT COUNT(*) FROM customers").fetchone()[0], 5)
        self.assertEqual([r[0] for r in self.conn.execute("SELECT name FROM customers ORDER BY id")],
                         ["An", "Binh", "Cuong", "Dung", "Em"])

    def test_ac_a_second_migrate_changes_no_row(self):
        before = self.snapshot()
        migrate(self.conn)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(customers.city_of(self.conn, 3), "Ha Noi")


if __name__ == "__main__":
    unittest.main()
