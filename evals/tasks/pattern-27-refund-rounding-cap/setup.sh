#!/usr/bin/env bash
# Builds the task repo in $1: orders and refunds of a small web shop, in python, where refunds round differently from the order total and ignore what was already refunded (offline, fixed author and date). Refuses an existing non-empty $1.
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
# shop-orders

Orders and refunds of a small web shop. Money is in integer cents (EUR), never floats.

- `src/money.py`: `half_up(numer, denom)` (integer division, halves away from zero) and `fmt(cents)` -> `"12.34"`.
- `src/orders.py`: `make_order(order_id, lines)` builds an order (`id`, `lines`, `paid_cents`, `refunds`); a line is
  `{"id", "unit_cents", "qty", "tax_pct"}`; `line_total(line, qty)` is what `qty` units of a line cost with tax.
- `src/refunds.py`: `refund(order, line_id, qty)` gives back money for returned units and records it in
  `order["refunds"]` as `{"line_id", "qty", "cents"}`.
- `src/reports.py`: `refund_report(orders)` -> rows `(order_id, refunded_cents, remaining_cents)` for the accountant,
  `report_text(orders)` prints them.

Python 3.8+, standard library only. Tests: `python3 -m unittest discover -s tests -t .` from the repo root.
Money rules: `docs/money-rules.md`. How we work: `CONTRIBUTING.md`.
PB_TASK_EOF

cat > CONTRIBUTING.md <<'PB_TASK_EOF'
# Contributing

- Keep changes small and covered by a test under `tests/` (`unittest`).
- Every amount is an integer number of cents; rounding goes through `src/money.py`, never through floats.
- `docs/money-rules.md` is agreed with the accountant: code follows it, and a change to a rule is agreed first.
PB_TASK_EOF

cat > docs/money-rules.md <<'PB_TASK_EOF'
# Money rules

Agreed with the accountant, 2026-02-10. Amounts are integer cents.

## Rounding
- Every rounding of money is half up: to the nearest cent, an exact half cent away from zero
  (`half_up(numer, denom)` in `src/money.py`). 12.5 cents is 13, never 12 (no banker's rounding, no float `round`).

## Order total
- `line_total(line, qty) = unit_cents * qty + half_up(unit_cents * qty * tax_pct, 100)` (tax per line, rounded once).
- `paid_cents` of an order is the sum of `line_total(line, line["qty"])` over its lines.

## Refunds
- A refund of k units of a line gives back `line_total(line, k)`.
- When a refund gives back the last units of a line that have not been refunded yet, it gives back
  `line_total(line, line["qty"])` minus what was already refunded on that line. So a line refunded in several steps
  gives back exactly what was paid for it, and the refunds of an order never add up to more than its `paid_cents`.
- Asking for more units than are left to refund on a line (also after the line is fully refunded) raises
  `ValueError` and records nothing.
- Each refund is recorded in `order["refunds"]` as `{"line_id", "qty", "cents"}`.

## Reports
- `refund_report` shows per order the cents refunded and the cents the shop keeps (`paid_cents` - refunded).
PB_TASK_EOF

: > src/__init__.py
: > tests/__init__.py

cat > src/money.py <<'PB_TASK_EOF'
"""Integer-cent money helpers (docs/money-rules.md)."""


def half_up(numer, denom):
    """numer / denom rounded to the nearest integer, an exact half away from zero (denom > 0)."""
    q, r = divmod(abs(numer), denom)
    if 2 * r >= denom:
        q += 1
    return q if numer >= 0 else -q


def fmt(cents):
    """12345 -> "123.45", -5 -> "-0.05"."""
    sign = "-" if cents < 0 else ""
    c = abs(cents)
    return "%s%d.%02d" % (sign, c // 100, c % 100)
PB_TASK_EOF

cat > src/orders.py <<'PB_TASK_EOF'
"""Orders: lines with a unit price in cents, a quantity and a tax percent (docs/money-rules.md)."""
from src.money import half_up


def line_total(line, qty):
    """What qty units of line cost, tax included, in cents."""
    net = line["unit_cents"] * qty
    return net + half_up(net * line["tax_pct"], 100)


def make_order(order_id, lines):
    lines = [dict(line) for line in lines]
    return {
        "id": order_id,
        "lines": lines,
        "paid_cents": sum(line_total(line, line["qty"]) for line in lines),
        "refunds": [],
    }


def find_line(order, line_id):
    for line in order["lines"]:
        if line["id"] == line_id:
            return line
    raise KeyError("no line %s in order %s" % (line_id, order["id"]))
PB_TASK_EOF

cat > src/refunds.py <<'PB_TASK_EOF'
"""Refunds of returned units (docs/money-rules.md)."""
from src.orders import find_line


def refund(order, line_id, qty):
    """Gives back the money for qty returned units of a line; records the refund and returns the cents."""
    line = find_line(order, line_id)
    net = line["unit_cents"] * qty
    cents = net + round(net * line["tax_pct"] / 100)
    order["refunds"].append({"line_id": line_id, "qty": qty, "cents": cents})
    return cents


def refunded_cents(order, line_id=None):
    """Cents refunded so far on an order, or on one of its lines."""
    return sum(r["cents"] for r in order["refunds"] if line_id is None or r["line_id"] == line_id)
PB_TASK_EOF

cat > src/reports.py <<'PB_TASK_EOF'
"""Refund report for the accountant."""
from src.money import fmt
from src.refunds import refunded_cents


def refund_report(orders):
    """Rows (order_id, refunded_cents, remaining_cents), one per order, in the given order."""
    rows = []
    for order in orders:
        done = refunded_cents(order)
        rows.append((order["id"], done, order["paid_cents"] - done))
    return rows


def report_text(orders):
    out = ["order      refunded      kept"]
    for order_id, done, kept in refund_report(orders):
        out.append("%-8s %10s %9s" % (order_id, fmt(done), fmt(kept)))
    return "\n".join(out)
PB_TASK_EOF

cat > tests/test_money.py <<'PB_TASK_EOF'
import unittest

from src.money import fmt, half_up


class Money(unittest.TestCase):
    def test_half_up(self):
        self.assertEqual(half_up(1250, 100), 13)
        self.assertEqual(half_up(1249, 100), 12)
        self.assertEqual(half_up(1050, 100), 11)
        self.assertEqual(half_up(-1250, 100), -13)

    def test_fmt(self):
        self.assertEqual(fmt(12345), "123.45")
        self.assertEqual(fmt(5), "0.05")
        self.assertEqual(fmt(-5), "-0.05")


if __name__ == "__main__":
    unittest.main()
PB_TASK_EOF

cat > tests/test_orders.py <<'PB_TASK_EOF'
import unittest

from src.orders import find_line, line_total, make_order


class Orders(unittest.TestCase):
    def test_line_total_rounds_tax_per_line(self):
        line = {"id": "x", "unit_cents": 999, "qty": 2, "tax_pct": 5}
        self.assertEqual(line_total(line, 2), 2098)  # 1998 + half_up(9990, 100)

    def test_make_order(self):
        order = make_order("W-1", [{"id": "a", "unit_cents": 500, "qty": 2, "tax_pct": 20}])
        self.assertEqual(order["paid_cents"], 1200)
        self.assertEqual(order["refunds"], [])
        self.assertEqual(find_line(order, "a")["qty"], 2)


if __name__ == "__main__":
    unittest.main()
PB_TASK_EOF

cat > tests/test_report_text.py <<'PB_TASK_EOF'
import unittest

from src.orders import make_order
from src.refunds import refund
from src.reports import refund_report, report_text


class ReportText(unittest.TestCase):
    def test_refund_of_a_tax_free_unit_shows_in_the_report(self):
        order = make_order("W-2", [{"id": "b", "unit_cents": 300, "qty": 2, "tax_pct": 0}])
        self.assertEqual(refund(order, "b", 1), 300)
        self.assertEqual(refund_report([order]), [("W-2", 300, 300)])
        self.assertIn("W-2", report_text([order]))
        self.assertIn("3.00", report_text([order]))


if __name__ == "__main__":
    unittest.main()
PB_TASK_EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git -c core.excludesFile=/dev/null add -f -A
GIT_AUTHOR_DATE='2026-04-14T08:20:00Z' GIT_COMMITTER_DATE='2026-04-14T08:20:00Z' git commit -q -m "Orders, refunds and the refund report"
