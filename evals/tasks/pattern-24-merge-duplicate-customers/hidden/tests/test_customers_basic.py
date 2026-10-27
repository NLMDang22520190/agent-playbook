# PB-HIDDEN-CANARY:pattern-24-merge-duplicate-customers
"""Hidden PASS_TO_PASS test: the existing account operations keep working (before and after the change)."""
import unittest

from src.customers import add_customer, customer_orders, find_by_email
from src.store import seed_store


class CustomersBasic(unittest.TestCase):
    def test_find_by_email_of_a_single_account(self):
        db = seed_store()
        self.assertEqual(find_by_email(db, "dung@example.com")["id"], "c7")
        self.assertIsNone(find_by_email(db, "nobody@example.com"))

    def test_add_customer_opens_an_account_with_no_points(self):
        db = seed_store()
        c = add_customer(db, "giang@example.com", "Giang Do", "+84 90 000 0010", "2026-10-20")
        self.assertEqual((c["points"], bool(c.get("active", True))), (0, True))
        self.assertIn(c, db["customers"])

    def test_customer_orders(self):
        self.assertEqual([o["id"] for o in customer_orders(seed_store(), "c2")], ["o4"])

    def test_seed_store_is_fresh_on_each_call(self):
        a = seed_store()
        a["customers"].clear()
        a["orders"].clear()
        self.assertGreaterEqual(len(seed_store()["customers"]), 7)
        self.assertGreaterEqual(len(seed_store()["orders"]), 8)


if __name__ == "__main__":
    unittest.main()
