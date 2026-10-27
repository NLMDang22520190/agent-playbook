#!/usr/bin/env bash
# Builds the task repo in $1: the reports and owner messages of a small web shop, in python (offline, fixed author and date). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest")" ]; }; then
  echo "setup: refusing non-empty $dest" >&2
  exit 2
fi
mkdir -p "$dest"
cd "$dest"
mkdir -p src src/reports src/owner src/exports tests

cat > README.md <<'PB_TASK_EOF'
# shop-figures

The numbers a small web shop shows its owner.

- `src/orders.py`: the order record and `counts_as_revenue(order)`, the one place that decides which orders are revenue.
- `src/reports/`: the daily and monthly reports in the admin page.
- `src/owner/`: scheduled jobs.
- `src/exports/`: files for the accountant.

An order is a dict: `id`, `date` (`YYYY-MM-DD`), `status` (`paid`, `shipped`, `cancelled`, `refunded`) and `total` (VND,
an integer). Python 3.8+, standard library only. Tests: `python3 -m unittest discover -s tests -t .` from the repo root.
PB_TASK_EOF

: > src/__init__.py
: > src/reports/__init__.py
: > src/owner/__init__.py
: > src/exports/__init__.py
: > tests/__init__.py

cat > src/orders.py <<'PB_TASK_EOF'
"""Order records of the shop and the revenue rule."""

NOT_REVENUE = ("cancelled", "refunded")


def counts_as_revenue(order):
    """True when the order's total is money the shop keeps."""
    return order["status"] not in NOT_REVENUE


def vnd(amount):
    """1250000 -> '1.250.000 đ'"""
    return "{:,}".format(amount).replace(",", ".") + " đ"
PB_TASK_EOF

cat > src/reports/daily.py <<'PB_TASK_EOF'
"""Daily report of the admin page."""
from src.orders import counts_as_revenue


def daily_summary(orders, day):
    """Orders of one day: how many, how many were cancelled, and the revenue."""
    todays = [o for o in orders if o["date"] == day]
    return {
        "day": day,
        "orders": len(todays),
        "cancelled": sum(1 for o in todays if o["status"] == "cancelled"),
        "revenue": sum(o["total"] for o in todays if counts_as_revenue(o)),
    }
PB_TASK_EOF

cat > src/reports/monthly.py <<'PB_TASK_EOF'
"""Monthly report of the admin page."""


def monthly_summary(orders, month):
    """Orders of one month ("YYYY-MM"): how many, and the revenue."""
    of_month = [o for o in orders if o["date"].startswith(month + "-")]
    return {
        "month": month,
        "orders": len(of_month),
        "revenue": sum(o["total"] for o in of_month),
    }
PB_TASK_EOF

cat > src/owner/week_message.py <<'PB_TASK_EOF'
"""The short message the shop sends its owner every Monday morning."""
from src.orders import vnd


def week_message(orders, first_day, last_day):
    """Text for the week first_day..last_day (both "YYYY-MM-DD", both included)."""
    week = [o for o in orders if first_day <= o["date"] <= last_day]
    total = 0
    for o in week:
        total += o["total"]
    return "Tuần {} - {}: {} đơn, doanh thu {}.".format(first_day, last_day, len(week), vnd(total))
PB_TASK_EOF

cat > src/exports/accounting.py <<'PB_TASK_EOF'
"""CSV lines for the accountant: every order of a month with its status, so the books can be matched."""


def accounting_lines(orders, month):
    lines = ["id,date,status,total"]
    for o in orders:
        if o["date"].startswith(month + "-"):
            lines.append("{},{},{},{}".format(o["id"], o["date"], o["status"], o["total"]))
    return lines
PB_TASK_EOF

cat > tests/test_reports.py <<'PB_TASK_EOF'
import unittest

from src.reports.daily import daily_summary
from src.reports.monthly import monthly_summary

ORDERS = [
    {"id": "A1", "date": "2026-08-03", "status": "paid", "total": 150000},
    {"id": "A2", "date": "2026-08-03", "status": "cancelled", "total": 90000},
    {"id": "A3", "date": "2026-08-20", "status": "shipped", "total": 200000},
]


class Reports(unittest.TestCase):
    def test_daily_leaves_out_the_cancelled_order(self):
        self.assertEqual(daily_summary(ORDERS, "2026-08-03"),
                         {"day": "2026-08-03", "orders": 2, "cancelled": 1, "revenue": 150000})

    def test_monthly_counts_the_orders_of_the_month(self):
        paid = [o for o in ORDERS if o["status"] != "cancelled"]
        self.assertEqual(monthly_summary(paid, "2026-08"), {"month": "2026-08", "orders": 2, "revenue": 350000})


if __name__ == "__main__":
    unittest.main()
PB_TASK_EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git -c core.excludesFile=/dev/null add -f -A
GIT_AUTHOR_DATE='2026-09-07T07:30:00Z' GIT_COMMITTER_DATE='2026-09-07T07:30:00Z' git commit -q -m "Reports, owner message and accountant export"
