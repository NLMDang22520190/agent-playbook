# PB-HIDDEN-CANARY:pattern-05-money-rounding
# Hidden FAIL_TO_PASS test: each line is rounded half up to 2 decimals; the invoice sums the rounded lines.
import unittest

from src.invoice import invoice_total, line_total


class HalfUpPerLine(unittest.TestCase):
    def test_three_times_0_835_is_2_51(self):
        self.assertEqual(line_total('3', '0.835'), '2.51')

    def test_2_675_is_2_68(self):
        self.assertEqual(line_total('1', '2.675'), '2.68')

    def test_0_125_is_0_13(self):
        self.assertEqual(line_total('1', '0.125'), '0.13')

    def test_invoice_sums_the_rounded_lines(self):
        self.assertEqual(invoice_total([('3', '0.835'), ('1', '2.675')]), '5.19')


if __name__ == '__main__':
    unittest.main()
