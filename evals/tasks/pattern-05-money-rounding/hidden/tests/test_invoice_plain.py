# PB-HIDDEN-CANARY:pattern-05-money-rounding
# Hidden PASS_TO_PASS test: exact amounts, zero quantity and values below the half keep their result.
import unittest

from src.invoice import invoice_total, line_total


class PlainLines(unittest.TestCase):
    def test_two_times_1_10(self):
        self.assertEqual(line_total('2', '1.10'), '2.20')

    def test_zero_quantity(self):
        self.assertEqual(line_total('0', '5'), '0.00')

    def test_below_the_half_rounds_down(self):
        self.assertEqual(line_total('1', '2.674'), '2.67')

    def test_just_below_the_half_rounds_down(self):
        self.assertEqual(line_total('1', '2.674999999999'), '2.67')

    def test_invoice_of_plain_lines(self):
        self.assertEqual(invoice_total([('2', '1.10'), ('0', '5')]), '2.20')


if __name__ == '__main__':
    unittest.main()
