# PB-HIDDEN-CANARY:pattern-20-period-last-day
# Hidden FAIL_TO_PASS test: client invoices take a period too (docs/periods.md names them; the prompt asks for the last
# day "everywhere in the tool that uses a period"), so they count the whole last day and a one-day period, and leave
# out the day after the last day.
import unittest
from datetime import date, datetime

from src.entries import Entry
from src.invoice import invoice_total

MARCH = (date(2026, 3, 1), date(2026, 3, 31))


class InvoiceLastDay(unittest.TestCase):
    def test_afternoon_of_the_last_day_is_billed(self):
        entries = [Entry('an', datetime(2026, 3, 30, 9, 0), 60, 'north'),
                   Entry('an', datetime(2026, 3, 31, 14, 0), 30, 'north')]
        self.assertEqual(invoice_total(entries, 'north', *MARCH, 6000), (90, 9000))

    def test_last_second_of_the_last_day_is_billed(self):
        entries = [Entry('binh', datetime(2026, 3, 31, 23, 59, 59), 60, 'north')]
        self.assertEqual(invoice_total(entries, 'north', *MARCH, 6000), (60, 6000))

    def test_one_day_period(self):
        entries = [Entry('chi', datetime(2026, 3, 16, 8, 0), 120, 'north'),
                   Entry('chi', datetime(2026, 3, 17, 8, 0), 60, 'north')]
        day = date(2026, 3, 16)
        self.assertEqual(invoice_total(entries, 'north', day, day, 6000), (120, 12000))

    def test_the_day_after_the_last_day_is_not_billed(self):
        entries = [Entry('an', datetime(2026, 3, 31, 10, 0), 60, 'north'),
                   Entry('an', datetime(2026, 4, 1, 0, 0), 60, 'north')]
        self.assertEqual(invoice_total(entries, 'north', *MARCH, 6000), (60, 6000))


if __name__ == '__main__':
    unittest.main()
