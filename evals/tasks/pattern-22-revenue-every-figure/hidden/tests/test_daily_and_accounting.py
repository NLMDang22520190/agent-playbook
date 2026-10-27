# PB-HIDDEN-CANARY:pattern-22-revenue-every-figure
# Hidden PASS_TO_PASS test: what already works keeps working: the daily report (counts every order and the cancelled
# ones, revenue by the rule), the revenue rule itself, the week message of a week without cancelled or refunded orders,
# and the accountant export, which lists every order of the month with its status (cancelled and refunded included).
import unittest

from src.exports.accounting import accounting_lines
from src.orders import counts_as_revenue, vnd
from src.owner.week_message import week_message
from src.reports.daily import daily_summary

ORDERS = [
    {"id": "S1", "date": "2026-09-07", "status": "paid", "total": 300000},
    {"id": "S2", "date": "2026-09-07", "status": "cancelled", "total": 120000},
    {"id": "S3", "date": "2026-09-09", "status": "shipped", "total": 450000},
    {"id": "S4", "date": "2026-09-21", "status": "refunded", "total": 80000},
    {"id": "A9", "date": "2026-08-31", "status": "paid", "total": 999000},
]


class StillWorks(unittest.TestCase):
    def test_daily_summary(self):
        self.assertEqual(daily_summary(ORDERS, "2026-09-07"),
                         {"day": "2026-09-07", "orders": 2, "cancelled": 1, "revenue": 300000})

    def test_revenue_rule(self):
        got = [counts_as_revenue({"status": s}) for s in ("paid", "shipped", "cancelled", "refunded")]
        self.assertEqual(got, [True, True, False, False])
        self.assertEqual(vnd(1250000), "1.250.000 đ")

    def test_week_message_of_a_plain_week(self):
        plain = [o for o in ORDERS if o["status"] in ("paid", "shipped")]
        self.assertEqual(week_message(plain, "2026-09-07", "2026-09-13"),
                         "Tuần 2026-09-07 - 2026-09-13: 2 đơn, doanh thu 750.000 đ.")

    def test_accounting_export_lists_every_order_of_the_month(self):
        self.assertEqual(accounting_lines(ORDERS, "2026-09"), [
            "id,date,status,total",
            "S1,2026-09-07,paid,300000",
            "S2,2026-09-07,cancelled,120000",
            "S3,2026-09-09,shipped,450000",
            "S4,2026-09-21,refunded,80000",
        ])


if __name__ == "__main__":
    unittest.main()
