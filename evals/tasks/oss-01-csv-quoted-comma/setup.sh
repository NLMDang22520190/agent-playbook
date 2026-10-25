#!/usr/bin/env bash
# Builds the task repo in $1: a small CSV column summer (offline, fixed author and date). Refuses an existing non-empty $1.
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
# csvsum

Sums an integer column of a CSV export. The first line is the header.

    from src.csvsum import total_by_column
    total_by_column(open('stock.csv').read(), 'qty')

Standard library only. Run the tests with `python3 -m unittest discover -s tests -t .`
EOF

: > src/__init__.py
: > tests/__init__.py

cat > src/csvsum.py <<'EOF'
"""Sum of an integer column of CSV text (the first line is the header)."""


def total_by_column(text, column):
    """Returns the sum of COLUMN over the data rows; raises KeyError when the header has no such column."""
    lines = [line for line in text.splitlines() if line]
    header = lines[0].split(',') if lines else []
    if column not in header:
        raise KeyError(column)
    index = header.index(column)
    return sum(int(line.split(',')[index]) for line in lines[1:])
EOF

cat > tests/test_csvsum.py <<'EOF'
import unittest

from src.csvsum import total_by_column


class CsvSumTest(unittest.TestCase):
    def test_sum(self):
        self.assertEqual(total_by_column('name,qty\npen,4\npad,6\n', 'qty'), 10)

    def test_header_only(self):
        self.assertEqual(total_by_column('name,qty\n', 'qty'), 0)


if __name__ == '__main__':
    unittest.main()
EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git add -A
GIT_AUTHOR_DATE='2026-01-14T09:00:00Z' GIT_COMMITTER_DATE='2026-01-14T09:00:00Z' git commit -q -m "Sum a CSV column"
