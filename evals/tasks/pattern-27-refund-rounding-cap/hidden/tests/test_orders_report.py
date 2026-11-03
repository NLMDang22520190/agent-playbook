# PB-HIDDEN-CANARY:pattern-27-refund-rounding-cap
"""Hidden PASS_TO_PASS test: what already worked keeps working (before and after the change): make_order adds up
paid_cents from line_total (docs/money-rules.md: unit_cents*qty + half_up(unit_cents*qty*tax_pct, 100)), the refund
report of an order with no refunds, and a full refund of a tax-free line equals unit_cents*qty."""
import unittest

from src.orders import line_total, make_order
from src.refunds import refund
from src.reports import refund_report


def line(lid, unit_cents, qty, tax_pct):
    return {"id": lid, "unit_cents": unit_cents, "qty": qty, "tax_pct": tax_pct}


class OrdersReport(unittest.TestCase):
    def test_make_order_paid_cents_of_a_two_line_order(self):
        order = make_order("P-2001", [line("K-4", 1000, 2, 10), line("M-6", 125, 1, 10)])
        self.assertEqual(line_total(order["lines"][0], 2), 2200)
        self.assertEqual(line_total(order["lines"][1], 1), 138)
        self.assertEqual(order["paid_cents"], 2338)
        self.assertEqual(order["refunds"], [])

    def test_refund_report_of_an_order_with_no_refunds(self):
        order = make_order("P-2002", [line("K-4", 1000, 2, 10)])
        rows = [tuple(r) for r in refund_report([order])]
        self.assertEqual(rows, [("P-2002", 0, 2200)])

    def test_full_refund_of_a_tax_free_line_equals_unit_times_qty(self):
        order = make_order("P-2003", [line("Z-0", 450, 3, 0)])
        self.assertEqual(refund(order, "Z-0", 3), 1350)


if __name__ == "__main__":
    unittest.main()
