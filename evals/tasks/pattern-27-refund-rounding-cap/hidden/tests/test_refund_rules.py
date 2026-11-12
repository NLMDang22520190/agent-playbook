# PB-HIDDEN-CANARY:pattern-27-refund-rounding-cap
"""Hidden FAIL_TO_PASS test: refund(order, line_id, qty) follows docs/money-rules.md. A refund of k units refunds
line_total(line, k) = unit_cents*k + half_up(unit_cents*k*tax_pct, 100) (half away from zero, not banker's rounding),
except when it refunds the last remaining units of a line: then it refunds line_total(line, line qty) minus what was
already refunded on that line, so a fully refunded line (and a fully refunded order) gives back exactly what was paid.
Asking for more units than remain raises ValueError and records nothing."""
import copy
import unittest

from src.orders import line_total, make_order
from src.refunds import refund


def line(lid, unit_cents, qty, tax_pct):
    return {"id": lid, "unit_cents": unit_cents, "qty": qty, "tax_pct": tax_pct}


class RefundRules(unittest.TestCase):
    def test_ac_refund_of_one_unit_rounds_half_up(self):
        order = make_order("R-1001", [line("ln-7", 125, 1, 10)])
        self.assertEqual(refund(order, "ln-7", 1), 138)  # 125 + half_up(1250, 100) = 125 + 13
        self.assertEqual(order["refunds"], [{"line_id": "ln-7", "qty": 1, "cents": 138}])

    def test_ac_refund_of_one_unit_that_is_not_the_last_rounds_half_up(self):
        order = make_order("R-1002", [line("ln-3", 125, 2, 10)])
        self.assertEqual(refund(order, "ln-3", 1), 138)

    def test_ac_unit_by_unit_refunds_sum_to_the_line_total(self):
        order = make_order("R-1003", [line("ln-9", 335, 3, 10)])
        self.assertEqual(line_total(order["lines"][0], 3), 1106)
        got = [refund(order, "ln-9", 1) for _ in range(3)]
        self.assertEqual(got, [369, 369, 368])
        self.assertEqual(sum(got), 1106)
        self.assertEqual(sum(r["cents"] for r in order["refunds"]), 1106)

    def test_ac_refunding_every_line_of_an_order_gives_back_paid_cents(self):
        order = make_order("R-1004", [line("A-5", 125, 3, 10), line("B-2", 335, 3, 10), line("C-8", 999, 2, 5)])
        total = 0
        total += refund(order, "A-5", 1)
        total += refund(order, "A-5", 1)
        total += refund(order, "A-5", 1)
        total += refund(order, "B-2", 1)
        total += refund(order, "B-2", 2)
        total += refund(order, "C-8", 2)
        self.assertEqual(total, order["paid_cents"])
        self.assertEqual(sum(r["cents"] for r in order["refunds"]), order["paid_cents"])

    def test_ac_more_units_than_remain_raises_and_records_nothing(self):
        order = make_order("R-1005", [line("ln-4", 335, 3, 10)])
        with self.assertRaises(ValueError):
            refund(order, "ln-4", 4)
        self.assertEqual(order["refunds"], [])
        refund(order, "ln-4", 2)
        before = copy.deepcopy(order["refunds"])
        with self.assertRaises(ValueError):
            refund(order, "ln-4", 2)
        self.assertEqual(order["refunds"], before)

    def test_ac_one_more_unit_after_a_full_refund_raises(self):
        order = make_order("R-1006", [line("ln-1", 125, 2, 10)])
        refund(order, "ln-1", 2)
        before = copy.deepcopy(order["refunds"])
        with self.assertRaises(ValueError):
            refund(order, "ln-1", 1)
        self.assertEqual(order["refunds"], before)


if __name__ == "__main__":
    unittest.main()
