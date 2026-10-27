# PB-HIDDEN-CANARY:pattern-24-merge-duplicate-customers
"""Hidden FAIL_TO_PASS test: merge_duplicates(db) leaves one open account per email (case and spaces ignored); every
order is kept (same id and total, same order in the list) and points at that open account of its customer's email
(docs/data-rules.md: orders are linked to an account); the loyalty points of a group add up on the open account
(docs/data-rules.md: points are never lost). Any account of a group may win (oldest, newest, most orders, a new one),
its email may be any spelling of the group's; the other accounts may be removed or closed (active false, or
merged_into / deleted / closed set, or a status merged / closed / deleted / inactive)."""
import copy
import unittest

import src.customers as customers
from src.store import seed_store

CLOSED = ("merged", "closed", "deleted", "inactive")


def key(c):
    return c["email"].strip().lower()


def is_open(c):
    return (bool(c.get("active", True)) and not c.get("merged_into") and not c.get("deleted")
            and not c.get("closed") and c.get("status", "active") not in CLOSED)


def merged():
    db = seed_store()
    before = copy.deepcopy(db)
    customers.merge_duplicates(db)
    return before, db


class MergeDuplicates(unittest.TestCase):
    def test_merge_duplicates_is_a_function(self):
        self.assertTrue(callable(getattr(customers, "merge_duplicates", None)))

    def test_seed_has_two_duplicate_groups(self):
        groups = {}
        for c in seed_store()["customers"]:
            groups.setdefault(key(c), []).append(c["id"])
        self.assertEqual(sorted(len(v) for v in groups.values()), [1, 1, 2, 3])

    def test_one_open_account_per_email(self):
        before, db = merged()
        open_keys = sorted(key(c) for c in db["customers"] if is_open(c))
        self.assertEqual(open_keys, sorted(set(key(c) for c in before["customers"])))

    def test_every_order_is_kept_and_belongs_to_the_open_account(self):
        before, db = merged()
        self.assertEqual([(o["id"], o["total"]) for o in db["orders"]],
                         [(o["id"], o["total"]) for o in before["orders"]])
        owner = {c["id"]: key(c) for c in before["customers"]}
        by_id = {c["id"]: c for c in db["customers"]}
        for old, new in zip(before["orders"], db["orders"]):
            acc = by_id.get(new["customer_id"])
            self.assertIsNotNone(acc, "order %s points at no account" % new["id"])
            self.assertTrue(is_open(acc), "order %s points at a closed account %s" % (new["id"], acc))
            self.assertEqual(key(acc), owner[old["customer_id"]], "order %s moved to another email" % new["id"])

    def test_points_of_a_group_add_up_on_the_open_account(self):
        before, db = merged()
        want = {}
        for c in before["customers"]:
            want[key(c)] = want.get(key(c), 0) + c["points"]
        got = {}
        for c in db["customers"]:
            if is_open(c):
                got[key(c)] = got.get(key(c), 0) + c["points"]
        self.assertEqual(got, want)

    def test_accounts_without_a_duplicate_are_untouched(self):
        # only the fields the seed has are compared: a fix may add its own (e.g. a normalised email key)
        before, db = merged()
        for cid in ("c2", "c7"):
            old = next(c for c in before["customers"] if c["id"] == cid)
            new = [c for c in db["customers"] if c["id"] == cid]
            self.assertEqual(len(new), 1, "account %s is still there, once" % cid)
            self.assertEqual({k: new[0].get(k) for k in old}, old)

    def test_a_second_run_changes_nothing(self):
        _, db = merged()
        once = copy.deepcopy(db)
        customers.merge_duplicates(db)
        self.assertEqual(db, once)


if __name__ == "__main__":
    unittest.main()
