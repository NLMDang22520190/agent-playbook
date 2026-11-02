# PB-HIDDEN-CANARY:pattern-32-new-season-reset
"""Hidden PASS_TO_PASS test: what the loyalty module already did keeps working (before and after the change):
add_points adds to both season and lifetime points of that member only, and tier() maps lifetime points to
"bronze", "silver" (>= 1000) and "gold" (>= 5000), boundaries included."""
import unittest

from src.loyalty import add_points, tier
from src.store import seed


def make_db():
    db = seed()
    db["members"] = [
        {"id": "m4", "name": "An Vo", "season_points": 120, "lifetime_points": 950, "tier": "bronze"},
        {"id": "m1", "name": "Binh Do", "season_points": 10, "lifetime_points": 3000, "tier": "silver"},
    ]
    return db


class PointsBasic(unittest.TestCase):
    def test_seed_shape(self):
        db = seed()
        self.assertEqual(db["season"], "2025")
        self.assertIsInstance(db["members"], list)
        self.assertEqual(db["history"], [])
        for m in db["members"]:
            for k in ("id", "name", "season_points", "lifetime_points", "tier"):
                self.assertIn(k, m)

    def test_add_points_adds_to_season_and_lifetime(self):
        db = make_db()
        add_points(db, "m4", 75)
        m4, m1 = db["members"]
        self.assertEqual((m4["season_points"], m4["lifetime_points"]), (195, 1025))
        self.assertEqual((m1["season_points"], m1["lifetime_points"]), (10, 3000), "another member is untouched")

    def test_tier_thresholds(self):
        cases = {0: "bronze", 999: "bronze", 1000: "silver", 4999: "silver", 5000: "gold", 12000: "gold"}
        self.assertEqual({n: tier(n) for n in cases}, cases)


if __name__ == "__main__":
    unittest.main()
