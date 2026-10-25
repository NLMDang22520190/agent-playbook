# PB-HIDDEN-CANARY:pattern-08-state-transition
# Hidden FAIL_TO_PASS test: an order cannot be cancelled once shipped; the status is left unchanged.
import unittest

from src.orders import cancel


class CancelAfterShipping(unittest.TestCase):
    def assert_refused(self, status):
        order = {'id': 'o1', 'status': status}
        with self.assertRaises(ValueError):
            cancel(order)
        self.assertEqual(order['status'], status)

    def test_shipped_is_refused(self):
        self.assert_refused('shipped')

    def test_delivered_is_refused(self):
        self.assert_refused('delivered')


if __name__ == '__main__':
    unittest.main()
