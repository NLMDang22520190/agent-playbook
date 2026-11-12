#!/usr/bin/env bash
# Builds the task repo in $1: the daily sales export of a small online shop, in python, that prints every amount as USD with 2 decimals (offline, fixed author and date). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest")" ]; }; then
  echo "setup: refusing non-empty $dest" >&2
  exit 2
fi
mkdir -p "$dest"
cd "$dest"
mkdir -p docs src tests

cat > README.md <<'PB_TASK_EOF'
# sales-export

The daily sales export of a small online shop: a CSV file that the accountant and the reporting tool read every day.

- `src/models.py` `Sale(day, item, amount_minor, currency="USD")`: one sale; `amount_minor` is an integer in the
  currency's minor unit (cents for USD).
- `src/fmt.py` `format_amount(minor, currency="USD")` is the one function that prints an amount: it takes the
  amount and its currency (default USD, see `docs/currencies.md`). The first version only knows USD: it is still
  `format_amount(minor)` and prints every amount as cents with 2 decimals.
- `src/export_csv.py` `export(sales)` returns the CSV text.
- `src/cli.py` `main(argv, sales)` prints the export (`--day YYYY-MM-DD` keeps one day).

Python 3.8+, standard library only. Tests: `python3 -m unittest discover -s tests -t .` from the repo root.
Currencies: `docs/currencies.md`. Export format: `docs/export-format.md`. How we work: `CONTRIBUTING.md`.
PB_TASK_EOF

cat > CONTRIBUTING.md <<'PB_TASK_EOF'
# Contributing

- Keep changes small and covered by a test under `tests/` (`unittest`).
- Money is never a float: amounts are integers in the currency's minor unit until they are printed.
- The export is a contract with its readers: read `docs/export-format.md` before you change it.
PB_TASK_EOF

cat > docs/currencies.md <<'PB_TASK_EOF'
# Currencies

Amounts are stored as integers in the currency's minor unit and printed with exactly as many decimals as that
currency has minor-unit digits (ISO 4217):

| Currency | Minor-unit digits | 1 unit stored as | Printed |
|---|---|---|---|
| USD | 2 | 100 | `1.00` |
| EUR | 2 | 100 | `1.00` |
| VND | 0 | 1 | `1` |
| JPY | 0 | 1 | `1` |
| KWD | 3 | 1000 | `1.000` |

- Printing: a `-` sign for a negative amount, `.` as the decimal point, no thousands separator, no currency
  symbol. A currency with 0 digits is printed without a decimal point.
- A currency that is not in the table is an error (`ValueError`), never printed with a guessed number of decimals.
- USD is the shop's home currency: a sale or amount without a currency is USD.

## Printing function

Every amount is printed by one function, `format_amount(minor, currency="USD")` in `src/fmt.py`: `minor` is the
integer amount in the minor unit, `currency` the currency code, USD when not given. The export and any other
place that prints money call it; no other code formats amounts.
PB_TASK_EOF

cat > docs/export-format.md <<'PB_TASK_EOF'
# Sales export format

CSV, UTF-8, `\n` line ends, a header line first, then one line per sale in the order given. Values are written as
plain text (no quoting for these values).

Current columns:

| Column | Text |
|---|---|
| `day` | `YYYY-MM-DD` |
| `item` | the item name |
| `amount` | the amount printed as in `docs/currencies.md` |

Readers: the accountant's spreadsheet import and the reporting tool. Both read the columns by header name.

Rules for changing the format:
- A new column is appended at the end of the header and of every row; existing columns never move.
- Existing columns keep their name and their text for the same sale.
PB_TASK_EOF

: > src/__init__.py
: > tests/__init__.py

cat > src/models.py <<'PB_TASK_EOF'
"""The sales of the shop."""
from dataclasses import dataclass


@dataclass(frozen=True)
class Sale:
    day: str  # YYYY-MM-DD
    item: str
    amount_minor: int  # integer, in the currency's minor unit
    currency: str = "USD"
PB_TASK_EOF

cat > src/fmt.py <<'PB_TASK_EOF'
"""Printing amounts (docs/currencies.md)."""


def format_amount(minor):
    """An amount in cents printed with 2 decimals: 1999 -> "19.99", -500 -> "-5.00"."""
    sign = "-" if minor < 0 else ""
    cents = abs(minor)
    return "%s%d.%02d" % (sign, cents // 100, cents % 100)
PB_TASK_EOF

cat > src/export_csv.py <<'PB_TASK_EOF'
"""The daily sales export (docs/export-format.md)."""
from src.fmt import format_amount

HEADER = ["day", "item", "amount"]


def export(sales):
    """CSV text: the header, then one line per sale, "\\n" line ends."""
    lines = [",".join(HEADER)]
    for s in sales:
        lines.append(",".join([s.day, s.item, format_amount(s.amount_minor)]))
    return "\n".join(lines) + "\n"
PB_TASK_EOF

cat > src/cli.py <<'PB_TASK_EOF'
"""Prints the sales export: main(argv, sales); `--day YYYY-MM-DD` keeps the sales of one day."""
import sys

from src.export_csv import export


def main(argv, sales, out=None):
    out = out or sys.stdout
    if len(argv) == 2 and argv[0] == "--day":
        sales = [s for s in sales if s.day == argv[1]]
    elif argv:
        print("usage: cli [--day YYYY-MM-DD]", file=sys.stderr)
        return 2
    out.write(export(sales))
    return 0
PB_TASK_EOF

cat > tests/test_fmt.py <<'PB_TASK_EOF'
import unittest

from src.fmt import format_amount


class Fmt(unittest.TestCase):
    def test_cents(self):
        self.assertEqual(format_amount(1999), "19.99")
        self.assertEqual(format_amount(7), "0.07")
        self.assertEqual(format_amount(-250), "-2.50")


if __name__ == "__main__":
    unittest.main()
PB_TASK_EOF

cat > tests/test_cli.py <<'PB_TASK_EOF'
import io
import unittest

from src.cli import main
from src.models import Sale

SALES = [Sale("2026-09-30", "Cup", 450), Sale("2026-10-01", "Pen", 120)]


class Cli(unittest.TestCase):
    def test_one_day(self):
        out = io.StringIO()
        self.assertEqual(main(["--day", "2026-10-01"], SALES, out), 0)
        lines = out.getvalue().splitlines()
        self.assertEqual(len(lines), 2)
        self.assertTrue(lines[1].startswith("2026-10-01,Pen,1.20"))

    def test_every_day(self):
        out = io.StringIO()
        main([], SALES, out)
        self.assertEqual(len(out.getvalue().splitlines()), 3)


if __name__ == "__main__":
    unittest.main()
PB_TASK_EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git -c core.excludesFile=/dev/null add -f -A
GIT_AUTHOR_DATE='2026-08-24T09:30:00Z' GIT_COMMITTER_DATE='2026-08-24T09:30:00Z' git commit -q -m "Sales export: CSV of the day, USD"
