# PB-HIDDEN-CANARY:pattern-35-currency-export
"""Hidden FAIL_TO_PASS test: amounts are printed with their currency's minor units (docs/currencies.md: USD 2,
EUR 2, VND 0, JPY 0, KWD 3; exactly that many decimals, "-" for negatives, no thousands separator; an unknown
currency raises ValueError) and the export appends a `currency` column at the end (docs/export-format.md: consumers
read columns by header name, new columns go at the end, existing columns keep their text)."""
import csv
import unittest

from src.export_csv import export
from src.fmt import format_amount
from src.models import Sale


class FormatAmount(unittest.TestCase):
    def test_zero_decimal_currencies(self):
        self.assertEqual(format_amount(150000, "VND"), "150000")
        self.assertEqual(format_amount(1200, "JPY"), "1200")

    def test_three_decimal_currency(self):
        self.assertEqual(format_amount(1234, "KWD"), "1.234")
        self.assertEqual(format_amount(5, "KWD"), "0.005")

    def test_negative_usd(self):
        self.assertEqual(format_amount(-500, "USD"), "-5.00")

    def test_unknown_currency_raises_value_error(self):
        with self.assertRaises(ValueError):
            format_amount(1, "XYZ")


class ExportWithCurrency(unittest.TestCase):
    SALES = [
        Sale("2026-10-01", "Mug", 1999, "USD"),
        Sale("2026-10-02", "Pho", 150000, "VND"),
        Sale("2026-10-03", "Dates", 1234, "KWD"),
    ]

    def test_header_appends_currency_at_the_end(self):
        text = export(self.SALES)
        self.assertEqual(text.split("\n")[0], "day,item,amount,currency")

    def test_rows_print_each_amount_with_its_currency_decimals(self):
        text = export(self.SALES)
        rows = [l for l in text.split("\n")[1:] if l]
        self.assertEqual(rows, ["2026-10-01,Mug,19.99,USD", "2026-10-02,Pho,150000,VND", "2026-10-03,Dates,1.234,KWD"])

    def test_rows_read_by_header_name(self):
        recs = list(csv.DictReader(export(self.SALES).splitlines()))
        self.assertEqual([(r["amount"], r["currency"]) for r in recs],
                         [("19.99", "USD"), ("150000", "VND"), ("1.234", "KWD")])

    def test_a_sale_without_currency_exports_as_usd(self):
        recs = list(csv.DictReader(export([Sale("2026-10-04", "Tea", 250)]).splitlines()))
        self.assertEqual([(r["amount"], r["currency"]) for r in recs], [("2.50", "USD")])


if __name__ == "__main__":
    unittest.main()
