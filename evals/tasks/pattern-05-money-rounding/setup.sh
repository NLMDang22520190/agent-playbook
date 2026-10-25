#!/usr/bin/env bash
# Builds the task repo in $1: invoice line totals (offline, fixed author and date). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest")" ]; }; then
  echo "setup: refusing non-empty $dest" >&2
  exit 2
fi
mkdir -p "$dest"
cd "$dest"
mkdir -p src tests

cat > README.md <<'EOF'
# invoicing

Invoice amounts for the shop. Quantities and unit prices come from the order as decimal strings ("3", "0.835");
amounts are returned as strings with exactly 2 decimals.

Run the tests with `python3 -m unittest discover -s tests -t .`
EOF

: > src/__init__.py
: > tests/__init__.py

cat > src/invoice.py <<'EOF'
"""Invoice amounts. Inputs are decimal strings; results are strings with 2 decimals."""


def line_total(qty, unit_price):
    """Amount of one invoice line: quantity times unit price, rounded to 2 decimals."""
    return '%.2f' % round(float(qty) * float(unit_price), 2)


def invoice_total(lines):
    """Sum of the line totals of [(qty, unit_price), ...]."""
    return '%.2f' % sum(float(line_total(qty, price)) for qty, price in lines)
EOF

cat > tests/test_invoice.py <<'EOF'
import unittest

from src.invoice import invoice_total, line_total


class InvoiceTest(unittest.TestCase):
    def test_line(self):
        self.assertEqual(line_total('4', '2.50'), '10.00')

    def test_invoice(self):
        self.assertEqual(invoice_total([('4', '2.50'), ('1', '0.99')]), '10.99')


if __name__ == '__main__':
    unittest.main()
EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git add -A
GIT_AUTHOR_DATE='2026-01-09T09:00:00Z' GIT_COMMITTER_DATE='2026-01-09T09:00:00Z' git commit -q -m "Invoice line totals"
