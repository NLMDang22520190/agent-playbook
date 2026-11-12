#!/usr/bin/env bash
# Builds the task repo in $1: the loyalty programme of a small coffee chain, in python, with seasons and yearly awards but no new-season step yet (offline, fixed author and date). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest")" ]; }; then
  echo "setup: refusing non-empty $dest" >&2
  exit 2
fi
mkdir -p "$dest"
cd "$dest"
mkdir -p docs src tests

cat > README.md <<'PB_TASK_EOF'
# coffee-loyalty

Loyalty programme of a small coffee chain, kept in an in-memory store.

- `src/store.py` `seed()` builds the store: the current `season` name, the `members` (id, name, `season_points`,
  `lifetime_points`, `tier`) and the `history` of finished seasons.
- `src/loyalty.py` holds the point operations and the tier rule.
- `src/awards.py` picks the yearly award winners from the history.

Python 3.8+, standard library only. Tests: `python3 -m unittest discover -s tests -t .` from the repo root.
Programme rules: `docs/loyalty-rules.md`. How we work: `CONTRIBUTING.md`.
PB_TASK_EOF

cat > CONTRIBUTING.md <<'PB_TASK_EOF'
# Contributing

- Keep changes small and covered by a test under `tests/` (`unittest`).
- The programme rules in `docs/loyalty-rules.md` are agreed with the shop owners and printed on the member card;
  read them before you change how points or tiers work.
PB_TASK_EOF

cat > docs/loyalty-rules.md <<'PB_TASK_EOF'
# Loyalty rules

Agreed with the shop owners, 2025-01-06. Printed on the back of the member card.

## Points
- A member earns 1 point per 10.000 VND spent. Each purchase adds the points to the member's `season_points` (this
  season) and to `lifetime_points` (since the member joined).
- Points are whole numbers.

## Tiers
- The tier comes from lifetime points: `bronze` below 1000, `silver` from 1000, `gold` from 5000.
- A tier never drops: a member keeps the tier they reached, also when a new season starts.

## Seasons
- A season runs one calendar year and is named after it (`"2025"`). `db["season"]` is the current season.
- Season points count for the season ranking only; they start again from 0 in a new season.
- At the end of a season each member's season points are archived in `db["history"]`, one entry per member, also
  for a member with 0 points: `{"season": "<the season that ended>", "member_id": "<id>", "points": <season points>}`.
  The yearly awards (`src/awards.py`) read this history, so entries of earlier seasons are never removed or changed.
- Starting the season that is already current changes nothing (the step may be run twice by the scheduler).
PB_TASK_EOF

: > src/__init__.py
: > tests/__init__.py

cat > src/store.py <<'PB_TASK_EOF'
"""In-memory store of the loyalty programme: the current season, the members and the history of finished seasons."""


def seed():
    return {
        "season": "2025",
        "members": [
            {"id": "m1", "name": "Lan Tran", "season_points": 320, "lifetime_points": 1450, "tier": "silver"},
            {"id": "m2", "name": "Minh Pham", "season_points": 0, "lifetime_points": 60, "tier": "bronze"},
            {"id": "m3", "name": "Hoa Le", "season_points": 2210, "lifetime_points": 6020, "tier": "gold"},
            {"id": "m4", "name": "Duc Vo", "season_points": 95, "lifetime_points": 95, "tier": "bronze"},
        ],
        "history": [],
    }
PB_TASK_EOF

cat > src/loyalty.py <<'PB_TASK_EOF'
"""Point operations and the tier rule of the loyalty programme (docs/loyalty-rules.md)."""

TIERS = [(5000, "gold"), (1000, "silver"), (0, "bronze")]
RANK = {"bronze": 0, "silver": 1, "gold": 2}


def tier(lifetime_points):
    """The tier for this many lifetime points."""
    for floor, name in TIERS:
        if lifetime_points >= floor:
            return name
    return "bronze"


def find_member(db, member_id):
    for m in db["members"]:
        if m["id"] == member_id:
            return m
    raise KeyError(member_id)


def add_points(db, member_id, n):
    """Adds n points to the member's season and lifetime points; the tier only goes up."""
    m = find_member(db, member_id)
    m["season_points"] += n
    m["lifetime_points"] += n
    new = tier(m["lifetime_points"])
    if RANK[new] > RANK[m["tier"]]:
        m["tier"] = new
    return m


def ranking(db):
    """Members by season points, highest first (ties by id)."""
    return sorted(db["members"], key=lambda m: (-m["season_points"], m["id"]))
PB_TASK_EOF

cat > src/awards.py <<'PB_TASK_EOF'
"""Yearly awards: the member with the most points in a finished season (read from db["history"])."""


def season_winner(db, season):
    """The member id with the most points in that finished season (ties by id), or None."""
    entries = [e for e in db["history"] if e["season"] == season]
    if not entries:
        return None
    return sorted(entries, key=lambda e: (-e["points"], e["member_id"]))[0]["member_id"]
PB_TASK_EOF

cat > tests/test_loyalty.py <<'PB_TASK_EOF'
import unittest

from src.loyalty import add_points, ranking, tier
from src.store import seed


class Loyalty(unittest.TestCase):
    def test_tier(self):
        self.assertEqual([tier(n) for n in (0, 1000, 5000)], ["bronze", "silver", "gold"])

    def test_add_points_raises_the_tier(self):
        db = seed()
        m = add_points(db, "m4", 905)
        self.assertEqual((m["season_points"], m["lifetime_points"], m["tier"]), (1000, 1000, "silver"))

    def test_ranking(self):
        self.assertEqual([m["id"] for m in ranking(seed())], ["m3", "m1", "m4", "m2"])


if __name__ == "__main__":
    unittest.main()
PB_TASK_EOF

cat > tests/test_awards.py <<'PB_TASK_EOF'
import unittest

from src.awards import season_winner
from src.store import seed


class Awards(unittest.TestCase):
    def test_winner_of_a_finished_season(self):
        db = seed()
        db["history"] = [
            {"season": "2024", "member_id": "m1", "points": 900},
            {"season": "2024", "member_id": "m3", "points": 1200},
        ]
        self.assertEqual(season_winner(db, "2024"), "m3")

    def test_no_history_no_winner(self):
        self.assertIsNone(season_winner(seed(), "2024"))


if __name__ == "__main__":
    unittest.main()
PB_TASK_EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git -c core.excludesFile=/dev/null add -f -A
GIT_AUTHOR_DATE='2025-12-15T02:40:00Z' GIT_COMMITTER_DATE='2025-12-15T02:40:00Z' git commit -q -m "Loyalty: points, tiers, ranking, yearly awards"
