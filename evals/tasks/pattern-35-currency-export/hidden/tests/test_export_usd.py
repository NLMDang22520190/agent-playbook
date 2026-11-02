# PB-HIDDEN-CANARY:pattern-35-currency-export
"""Hidden PASS_TO_PASS test: what consumers already read keeps working (before and after the change):
format_amount(minor) without a currency prints 2 decimals, and an export of USD-only sales has the old `day`, `item`
and `amount` columns, read by header name (docs/export-format.md), with the same text as before."""
import csv
import unittest

from src.export_csv import export
from src.fmt import format_amount
from src.models import Sale

SALES = [
    Sale("2026-10-01", "Mug", 1999),
    Sale("2026-10-02", "Sticker", 5),
    Sale("2026-10-05", "Lamp", 120000),
]
OLD = [
    {"day": "2026-10-01", "item": "Mug", "amount": "19.99"},
    {"day": "2026-10-02", "item": "Sticker", "amount": "0.05"},
    {"day": "2026-10-05", "item": "Lamp", "amount": "1200.00"},
]


class ExportUsd(unittest.TestCase):
    def test_format_amount_without_currency(self):
        self.assertEqual(format_amount(1999), "19.99")
        self.assertEqual(format_amount(5), "0.05")

    def test_old_columns_by_header_name(self):
        recs = list(csv.DictReader(export(SALES).splitlines()))
        self.assertEqual([{k: r[k] for k in ("day", "item", "amount")} for r in recs], OLD)

    def test_header_starts_with_the_old_columns_and_lines_end_with_newline_only(self):
        text = export(SALES)
        self.assertTrue(text.split("\n")[0].startswith("day,item,amount"))
        self.assertNotIn("\r", text)


if __name__ == "__main__":
    unittest.main()
