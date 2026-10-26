# PB-HIDDEN-CANARY:pattern-20-period-last-day
# Hidden FAIL_TO_PASS test: the report counts the whole last day of the period (docs/periods.md): an entry at any time
# of that day, up to 23:59:59, and a one-day period; the day after the last day stays out, from 00:00:00 on.
import unittest
from datetime import date, datetime

from src.entries import Entry
from src.report import minutes_by_person

MARCH = (date(2026, 3, 1), date(2026, 3, 31))


class ReportLastDay(unittest.TestCase):
    def test_afternoon_of_the_last_day_counts(self):
        entries = [Entry('an', datetime(2026, 3, 30, 9, 0), 60, 'north'),
                   Entry('an', datetime(2026, 3, 31, 14, 0), 45, 'north')]
        self.assertEqual(minutes_by_person(entries, *MARCH), {'an': 105})

    def test_midnight_and_last_second_of_the_last_day_count(self):
        entries = [Entry('binh', datetime(2026, 3, 31, 0, 0), 30, 'south'),
                   Entry('binh', datetime(2026, 3, 31, 23, 59, 59), 15, 'south')]
        self.assertEqual(minutes_by_person(entries, *MARCH), {'binh': 45})

    def test_one_day_period(self):
        entries = [Entry('chi', datetime(2026, 3, 16, 8, 0), 240, 'north'),
                   Entry('chi', datetime(2026, 3, 17, 8, 0), 120, 'north')]
        day = date(2026, 3, 16)
        self.assertEqual(minutes_by_person(entries, day, day), {'chi': 240})

    def test_the_day_after_the_last_day_stays_out(self):
        entries = [Entry('an', datetime(2026, 3, 31, 18, 0), 20, 'north'),
                   Entry('an', datetime(2026, 4, 1, 0, 0), 50, 'north')]
        self.assertEqual(minutes_by_person(entries, *MARCH), {'an': 20})


if __name__ == '__main__':
    unittest.main()
