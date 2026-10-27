# PB-HIDDEN-CANARY:pattern-22-revenue-every-figure
# Hidden FAIL_TO_PASS test: the monthly report's revenue follows counts_as_revenue() (README: "the one place that decides
# which orders are revenue"): cancelled orders (the report) and refunded orders are left out. Only the revenue figure is
# checked; the order count is left to the fix.
import unittest

from src.reports.monthly import monthly_summary

SEPT = [
    {"id": "S1", "date": "2026-09-02", "status": "paid", "total": 300000},
    {"id": "S2", "date": "2026-09-15", "status": "shipped", "total": 450000},
    {"id": "S3", "date": "2026-09-18", "status": "cancelled", "total": 120000},
    {"id": "S4", "date": "2026-09-29", "status": "refunded", "total": 80000},
    {"id": "A9", "date": "2026-08-31", "status": "paid", "total": 999000},
    {"id": "O1", "date": "2026-10-01", "status": "paid", "total": 555000},
]


class MonthlyRevenue(unittest.TestCase):
    def test_cancelled_order_is_not_revenue(self):
        orders = [o for o in SEPT if o["status"] != "refunded"]
        self.assertEqual(monthly_summary(orders, "2026-09")["revenue"], 750000)

    def test_refunded_order_is_not_revenue(self):
        orders = [o for o in SEPT if o["status"] != "cancelled"]
        self.assertEqual(monthly_summary(orders, "2026-09")["revenue"], 750000)

    def test_only_the_months_kept_orders(self):
        self.assertEqual(monthly_summary(SEPT, "2026-09")["revenue"], 750000)
        self.assertEqual(monthly_summary(SEPT, "2026-08")["revenue"], 999000)


if __name__ == "__main__":
    unittest.main()
