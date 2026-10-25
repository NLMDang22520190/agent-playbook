#!/usr/bin/env bash
# Builds the task repo in $1: order status changes (offline, fixed author and date). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest")" ]; }; then
  echo "setup: refusing non-empty $dest" >&2
  exit 2
fi
mkdir -p "$dest"
cd "$dest"
mkdir -p src tests docs

cat > README.md <<'EOF'
# orders

Order status changes for a print shop. Run the tests with `python3 -m unittest discover -s tests -t .`
EOF

cat > docs/orders.md <<'EOF'
# Order lifecycle

An order moves through these statuses:

    new -> paid -> printing -> shipped -> delivered

and can end as `cancelled`.

Cancelling: an order can be cancelled only before it is shipped, that is while it is `new`, `paid` or `printing`.
Once it is `shipped` or `delivered` it cannot be cancelled (the customer has to open a return instead). A cancelled
order cannot be cancelled again. A refused cancel raises `ValueError` and leaves the order as it was.
EOF

: > src/__init__.py
: > tests/__init__.py

cat > src/orders.py <<'EOF'
"""Order status changes. See docs/orders.md."""


def cancel(order):
    """Cancels the order (a dict with a 'status' key). Raises ValueError when it cannot be cancelled."""
    if order['status'] == 'cancelled':
        raise ValueError('order %s is already cancelled' % order.get('id'))
    order['status'] = 'cancelled'
EOF

cat > tests/test_orders.py <<'EOF'
import unittest

from src.orders import cancel


class CancelTest(unittest.TestCase):
    def test_paid_order_is_cancelled(self):
        order = {'id': 'o7', 'status': 'paid'}
        cancel(order)
        self.assertEqual(order['status'], 'cancelled')

    def test_cancelled_twice(self):
        with self.assertRaises(ValueError):
            cancel({'id': 'o8', 'status': 'cancelled'})


if __name__ == '__main__':
    unittest.main()
EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git add -A
GIT_AUTHOR_DATE='2026-01-12T09:00:00Z' GIT_COMMITTER_DATE='2026-01-12T09:00:00Z' git commit -q -m "Cancel orders"
