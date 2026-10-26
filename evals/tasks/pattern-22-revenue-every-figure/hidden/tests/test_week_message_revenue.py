# PB-HIDDEN-CANARY:pattern-22-revenue-every-figure
# Hidden FAIL_TO_PASS test: the Monday message to the owner is a revenue figure the shop gives the owner too (the prompt:
# every revenue figure, wherever it appears), so it follows counts_as_revenue(): cancelled and refunded orders are left
# out. Only the figure after "doanh thu" is checked.
import re
import unittest

from src.owner.week_message import week_message

WEEK = [
    {"id": "S1", "date": "2026-09-07", "status": "paid", "total": 300000},
    {"id": "S2", "date": "2026-09-09", "status": "shipped", "total": 450000},
    {"id": "S3", "date": "2026-09-10", "status": "cancelled", "total": 120000},
    {"id": "S4", "date": "2026-09-13", "status": "refunded", "total": 80000},
    {"id": "S5", "date": "2026-09-14", "status": "paid", "total": 999000},
]


def revenue_in(text):
    m = re.search(r"doanh thu ([0-9.]+) đ", text)
    if m is None:
        raise AssertionError("no 'doanh thu N đ' in: " + text)
    return m.group(1)


class WeekMessageRevenue(unittest.TestCase):
    def test_cancelled_order_is_not_revenue(self):
        orders = [o for o in WEEK if o["status"] != "refunded"]
        self.assertEqual(revenue_in(week_message(orders, "2026-09-07", "2026-09-13")), "750.000")

    def test_refunded_order_is_not_revenue(self):
        orders = [o for o in WEEK if o["status"] != "cancelled"]
        self.assertEqual(revenue_in(week_message(orders, "2026-09-07", "2026-09-13")), "750.000")


if __name__ == "__main__":
    unittest.main()
