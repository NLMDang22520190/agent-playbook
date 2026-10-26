# PB-HIDDEN-CANARY:pattern-20-period-last-day
# Hidden PASS_TO_PASS test: entries inside the period count, entries before the first day do not, the first day counts
# from 00:00:00, and the invoice bills only its client with cents rounded down.
import unittest
from datetime import date, datetime

from src.entries import Entry
from src.invoice import invoice_total
from src.report import minutes_by_person

MARCH = (date(2026, 3, 1), date(2026, 3, 31))


class InsideThePeriod(unittest.TestCase):
    def test_report_inside_and_before(self):
        entries = [Entry('an', datetime(2026, 2, 28, 23, 59, 59), 10, 'north'),
                   Entry('an', datetime(2026, 3, 1, 0, 0), 20, 'north'),
                   Entry('binh', datetime(2026, 3, 15, 12, 0), 40, 'south')]
        self.assertEqual(minutes_by_person(entries, *MARCH), {'an': 20, 'binh': 40})

    def test_report_empty(self):
        self.assertEqual(minutes_by_person([], *MARCH), {})

    def test_invoice_one_client_rounded_down(self):
        entries = [Entry('an', datetime(2026, 2, 28, 16, 0), 60, 'north'),
                   Entry('an', datetime(2026, 3, 2, 9, 0), 25, 'north'),
                   Entry('binh', datetime(2026, 3, 3, 9, 0), 60, 'south')]
        self.assertEqual(invoice_total(entries, 'north', *MARCH, 5000), (25, 2083))


if __name__ == '__main__':
    unittest.main()
