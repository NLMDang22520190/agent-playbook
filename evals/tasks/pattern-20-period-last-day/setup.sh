#!/usr/bin/env bash
# Builds the task repo in $1: a timesheet tool with a monthly report and client invoices over a period (offline, fixed author and date). Refuses an existing non-empty $1.
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
# timesheet

Time entries of a small team, with a report of minutes per person and client invoices.

- `src/entries.py`: the `Entry` record.
- `src/periods.py`: periods (a first day and a last day).
- `src/report.py`: minutes per person over a period.
- `src/invoice.py`: the invoice total of a client over a period.

How periods work: `docs/periods.md`. Standard library only. Run the tests with
`python3 -m unittest discover -s tests -t .`
PB_TASK_EOF

cat > docs/periods.md <<'PB_TASK_EOF'
# Periods

Everything in this tool that covers a span of days (the monthly report, client invoices, exports) takes a period: a
first day and a last day, both `datetime.date`.

- Both the first and the last day belong to the period. A period of one day has the same first and last day.
- A time entry belongs to the calendar day of its `when` timestamp, whatever the time of day (00:00:00 to 23:59:59).
- Timestamps are local time, without a time zone.
PB_TASK_EOF

: > src/__init__.py
: > tests/__init__.py

cat > src/entries.py <<'PB_TASK_EOF'
"""A time entry: who worked, when the work started, for how many minutes, and for which client."""
from collections import namedtuple

Entry = namedtuple('Entry', ['person', 'when', 'minutes', 'client'])
PB_TASK_EOF

cat > src/periods.py <<'PB_TASK_EOF'
"""Periods: a first day and a last day (see docs/periods.md)."""
from datetime import datetime, time


def period_bounds(first, last):
    """Returns the (start, end) datetimes of the period FIRST..LAST."""
    return datetime.combine(first, time()), datetime.combine(last, time())


def in_period(when, first, last):
    """True when the timestamp WHEN falls in the period FIRST..LAST."""
    start, end = period_bounds(first, last)
    return start <= when < end
PB_TASK_EOF

cat > src/report.py <<'PB_TASK_EOF'
"""Minutes worked per person over a period."""
from src.periods import in_period


def minutes_by_person(entries, first, last):
    """Returns {person: total minutes} for the entries in the period FIRST..LAST."""
    totals = {}
    for e in entries:
        if in_period(e.when, first, last):
            totals[e.person] = totals.get(e.person, 0) + e.minutes
    return totals
PB_TASK_EOF

cat > src/invoice.py <<'PB_TASK_EOF'
"""Invoice total of one client over a period."""
from datetime import datetime, time


def invoice_total(entries, client, first, last, cents_per_hour):
    """Returns (minutes, amount in cents) billed to CLIENT for the period FIRST..LAST; cents are rounded down."""
    start = datetime.combine(first, time())
    end = datetime.combine(last, time())
    minutes = sum(e.minutes for e in entries if e.client == client and start <= e.when < end)
    return minutes, minutes * cents_per_hour // 60
PB_TASK_EOF

cat > tests/test_timesheet.py <<'PB_TASK_EOF'
import unittest
from datetime import date, datetime

from src.entries import Entry
from src.invoice import invoice_total
from src.report import minutes_by_person


class TimesheetTest(unittest.TestCase):
    def test_report_sums_minutes_per_person(self):
        entries = [
            Entry('an', datetime(2026, 3, 10, 9, 0), 120, 'north'),
            Entry('an', datetime(2026, 3, 11, 9, 0), 60, 'north'),
            Entry('binh', datetime(2026, 3, 12, 13, 0), 90, 'south'),
        ]
        self.assertEqual(minutes_by_person(entries, date(2026, 3, 1), date(2026, 3, 31)), {'an': 180, 'binh': 90})

    def test_invoice_bills_one_client(self):
        entries = [
            Entry('an', datetime(2026, 3, 10, 9, 0), 120, 'north'),
            Entry('binh', datetime(2026, 3, 12, 13, 0), 90, 'south'),
        ]
        self.assertEqual(invoice_total(entries, 'north', date(2026, 3, 1), date(2026, 3, 31), 6000), (120, 12000))


if __name__ == '__main__':
    unittest.main()
PB_TASK_EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git -c core.excludesFile=/dev/null add -f -A
GIT_AUTHOR_DATE='2026-04-20T08:15:00Z' GIT_COMMITTER_DATE='2026-04-20T08:15:00Z' git commit -q -m "Monthly report and client invoices"
