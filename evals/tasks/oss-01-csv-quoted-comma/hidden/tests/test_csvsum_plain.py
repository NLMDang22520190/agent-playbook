# PB-HIDDEN-CANARY:oss-01-csv-quoted-comma
# Hidden PASS_TO_PASS test: plain CSV sums and a missing column raises KeyError.
import unittest

from src.csvsum import total_by_column


class PlainCsv(unittest.TestCase):
    def test_plain_sum(self):
        self.assertEqual(total_by_column('item,qty\na,1\nb,2\n', 'qty'), 3)

    def test_plain_sum_without_final_newline(self):
        self.assertEqual(total_by_column('item,qty\na,1\nb,2', 'qty'), 3)

    def test_missing_column_raises_key_error(self):
        with self.assertRaises(KeyError):
            total_by_column('item,qty\na,1\n', 'price')


if __name__ == '__main__':
    unittest.main()
