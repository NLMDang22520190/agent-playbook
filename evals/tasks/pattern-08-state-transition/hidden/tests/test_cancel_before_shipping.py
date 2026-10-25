# PB-HIDDEN-CANARY:pattern-08-state-transition
# Hidden PASS_TO_PASS test: orders not yet shipped can be cancelled; a cancelled order cannot be cancelled again.
import unittest

from src.orders import cancel


class CancelBeforeShipping(unittest.TestCase):
    def assert_cancelled(self, status):
        order = {'id': 'o1', 'status': status}
        cancel(order)
        self.assertEqual(order['status'], 'cancelled')

    def test_new(self):
        self.assert_cancelled('new')

    def test_paid(self):
        self.assert_cancelled('paid')

    def test_printing(self):
        self.assert_cancelled('printing')

    def test_cancelled_again_is_refused(self):
        order = {'id': 'o1', 'status': 'cancelled'}
        with self.assertRaises(ValueError):
            cancel(order)
        self.assertEqual(order['status'], 'cancelled')


if __name__ == '__main__':
    unittest.main()
