# PB-HIDDEN-CANARY:pattern-32-new-season-reset
"""Hidden FAIL_TO_PASS test: start_new_season(db, name) starts a new season without losing data
(docs/loyalty-rules.md): every member's season points go to 0; lifetime points and tier stay (a tier comes from
lifetime points and never drops); db["season"] becomes the new name; the old season's points are archived in
db["history"] as one {"season", "member_id", "points"} entry per member (also for 0 points; the yearly awards read
it); earlier history entries are kept; starting the season that is already current changes nothing.
start_new_season is looked up in src.loyalty, then src.store (both are in scope)."""
import copy
import unittest

import src.loyalty as loyalty
import src.store as store


def start_new_season(db, name):
    fn = getattr(loyalty, "start_new_season", None) or getattr(store, "start_new_season", None)
    if fn is None:
        raise AssertionError("start_new_season is not defined in src.loyalty or src.store")
    return fn(db, name)


def member(mid, name, season, lifetime, tier):
    return {"id": mid, "name": name, "season_points": season, "lifetime_points": lifetime, "tier": tier}


OLD_ENTRY = {"season": "2024", "member_id": "m7", "points": 880}


def make_db():
    """A seed() copy with the test's own members (ids differ from list positions) and one earlier history entry."""
    db = store.seed()
    db["season"] = "2025"
    db["members"] = [
        member("m7", "Lan Tran", 300, 1200, "silver"),
        member("m2", "Minh Pham", 0, 40, "bronze"),
        member("m9", "Hoa Le", 4100, 5100, "gold"),
    ]
    db["history"] = [dict(OLD_ENTRY)]
    return db


def entry(e):
    return (e.get("season"), e.get("member_id"), e.get("points"))


class NewSeason(unittest.TestCase):
    def test_season_points_go_to_zero_and_the_season_name_changes(self):
        db = make_db()
        start_new_season(db, "2026")
        self.assertEqual({m["id"]: m["season_points"] for m in db["members"]}, {"m7": 0, "m2": 0, "m9": 0})
        self.assertEqual(db["season"], "2026")

    def test_lifetime_points_and_tier_are_unchanged(self):
        db = make_db()
        start_new_season(db, "2026")
        got = {m["id"]: (m["lifetime_points"], m["tier"]) for m in db["members"]}
        self.assertEqual(got, {"m7": (1200, "silver"), "m2": (40, "bronze"), "m9": (5100, "gold")})
        self.assertEqual([m["id"] for m in db["members"]], ["m7", "m2", "m9"], "no member is removed or added")
        for m in db["members"]:
            self.assertEqual(loyalty.tier(m["lifetime_points"]), m["tier"])

    def test_old_season_points_are_archived_once_per_member_including_zero(self):
        db = make_db()
        start_new_season(db, "2026")
        hist = db["history"]
        self.assertEqual(len(hist), 4, "one earlier entry plus exactly one entry per member")
        new = sorted(entry(e) for e in hist if entry(e) != entry(OLD_ENTRY))
        self.assertEqual(new, [("2025", "m2", 0), ("2025", "m7", 300), ("2025", "m9", 4100)])

    def test_earlier_history_entries_are_kept(self):
        db = make_db()
        start_new_season(db, "2026")
        self.assertIn(OLD_ENTRY, db["history"])

    def test_starting_the_current_season_again_changes_nothing(self):
        db = make_db()
        start_new_season(db, "2026")
        snap = copy.deepcopy(db)
        start_new_season(db, "2026")
        self.assertEqual(db, snap)

    def test_starting_the_current_season_again_keeps_points_earned_in_it(self):
        db = make_db()
        start_new_season(db, "2026")
        loyalty.add_points(db, "m2", 75)
        snap = copy.deepcopy(db)
        start_new_season(db, "2026")
        self.assertEqual(db, snap)
        self.assertEqual(next(m for m in db["members"] if m["id"] == "m2")["season_points"], 75)


if __name__ == "__main__":
    unittest.main()
