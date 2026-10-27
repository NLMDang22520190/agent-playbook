#!/usr/bin/env bash
# Builds the task repo in $1: the customer accounts of a small web shop, in python, with duplicate sign-ups and no merge yet (offline, fixed author and date). Refuses an existing non-empty $1.
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
# shop-customers

Customer accounts of a small web shop, kept in an in-memory store.

- `src/store.py` `seed_store()` builds the store: `customers` (id, email, name, phone, created `YYYY-MM-DD`, loyalty
  `points`, `active`) and `orders` (id, customer_id, total in VND).
- `src/customers.py` holds the account operations.

Python 3.8+, standard library only. Tests: `python3 -m unittest discover -s tests -t .` from the repo root.
Data rules: `docs/data-rules.md`. How we work: `CONTRIBUTING.md`.
PB_TASK_EOF

cat > CONTRIBUTING.md <<'PB_TASK_EOF'
# Contributing

- Keep changes small and covered by a test under `tests/` (`unittest`).
- A choice the ticket does not settle goes into docs/decisions.md as a new `## ` entry (date, decision, why), so the
  next person knows what was assumed.
- Rules for customer data are in `docs/data-rules.md`; read it before you change or remove customer data.
PB_TASK_EOF

cat > docs/data-rules.md <<'PB_TASK_EOF'
# Data rules

Approved by the shop owner and the accountant, 2025-10-02.

- Orders are accounting records: kept 10 years, each one linked to a customer account.
- Loyalty points are owed to the customer: they are spent or they expire, they are never lost.
- An account may be closed (`active` false); a closed account cannot sign in.
PB_TASK_EOF

cat > docs/decisions.md <<'PB_TASK_EOF'
# Decisions

## 2026-01-12 Customers live in memory
Decision: the store is a plain dict in memory until the database lands. Why: one process serves everything.

## 2026-02-03 Points are whole numbers
Decision: loyalty points are integers, 1 point per 10.000 VND spent. Why: the shop's card printer shows whole points.
PB_TASK_EOF

: > src/__init__.py
: > tests/__init__.py

cat > src/store.py <<'PB_TASK_EOF'
"""In-memory store of the shop: customer accounts and their orders (totals in VND)."""


def seed_store():
    return {
        "customers": [
            {"id": "c1", "email": "an@example.com", "name": "An Tran", "phone": "+84 90 000 0001",
             "created": "2023-04-02", "points": 120, "active": True},
            {"id": "c2", "email": "binh@example.com", "name": "Binh Le", "phone": "+84 90 000 0002",
             "created": "2023-06-10", "points": 40, "active": True},
            {"id": "c3", "email": "An@Example.com", "name": "An Tran", "phone": "+84 90 000 0011",
             "created": "2025-01-15", "points": 35, "active": True},
            {"id": "c4", "email": "AN@EXAMPLE.COM", "name": "Tran An", "phone": "+84 90 000 0011",
             "created": "2026-08-20", "points": 0, "active": True},
            {"id": "c5", "email": "cuong@example.com", "name": "Cuong Pham", "phone": "+84 90 000 0005",
             "created": "2024-02-01", "points": 10, "active": True},
            {"id": "c6", "email": "Cuong@example.com", "name": "Cuong Pham", "phone": "+84 90 000 0005",
             "created": "2026-03-03", "points": 55, "active": True},
            {"id": "c7", "email": "dung@example.com", "name": "Dung Vo", "phone": "+84 90 000 0007",
             "created": "2025-05-05", "points": 5, "active": True},
        ],
        "orders": [
            {"id": "o1", "customer_id": "c1", "total": 250000},
            {"id": "o2", "customer_id": "c3", "total": 99000},
            {"id": "o3", "customer_id": "c4", "total": 410000},
            {"id": "o4", "customer_id": "c2", "total": 120000},
            {"id": "o5", "customer_id": "c6", "total": 76000},
            {"id": "o6", "customer_id": "c5", "total": 18000},
            {"id": "o7", "customer_id": "c3", "total": 33000},
            {"id": "o8", "customer_id": "c7", "total": 54000},
        ],
    }
PB_TASK_EOF

cat > src/customers.py <<'PB_TASK_EOF'
"""Customer accounts of the shop."""


def find_by_email(db, email):
    """The open account with exactly this email, or None."""
    for c in db["customers"]:
        if c["email"] == email and c.get("active", True):
            return c
    return None


def add_customer(db, email, name, phone, created):
    """Opens a new account and returns it."""
    customer = {
        "id": "c%d" % (len(db["customers"]) + 1),
        "email": email,
        "name": name,
        "phone": phone,
        "created": created,
        "points": 0,
        "active": True,
    }
    db["customers"].append(customer)
    return customer


def customer_orders(db, customer_id):
    """The orders of one account, in store order."""
    return [o for o in db["orders"] if o["customer_id"] == customer_id]
PB_TASK_EOF

cat > tests/test_customers.py <<'PB_TASK_EOF'
import unittest

from src.customers import add_customer, customer_orders, find_by_email
from src.store import seed_store


class Customers(unittest.TestCase):
    def test_find_by_email(self):
        db = seed_store()
        self.assertEqual(find_by_email(db, "binh@example.com")["id"], "c2")
        self.assertIsNone(find_by_email(db, "nobody@example.com"))

    def test_add_customer(self):
        db = seed_store()
        c = add_customer(db, "em@example.com", "Em Ngo", "+84 90 000 0009", "2026-10-01")
        self.assertEqual(c["id"], "c8")
        self.assertIs(find_by_email(db, "em@example.com"), c)

    def test_customer_orders(self):
        self.assertEqual([o["id"] for o in customer_orders(seed_store(), "c3")], ["o2", "o7"])


if __name__ == "__main__":
    unittest.main()
PB_TASK_EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git -c core.excludesFile=/dev/null add -f -A
GIT_AUTHOR_DATE='2026-04-08T03:15:00Z' GIT_COMMITTER_DATE='2026-04-08T03:15:00Z' git commit -q -m "Customer accounts: store, find, add, orders"
