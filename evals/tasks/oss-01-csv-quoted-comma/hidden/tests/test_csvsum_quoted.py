# PB-HIDDEN-CANARY:oss-01-csv-quoted-comma
# Hidden FAIL_TO_PASS test: quoted fields may hold commas and doubled quotes.
import unittest

from src.csvsum import total_by_column


class QuotedFields(unittest.TestCase):
    def test_quoted_comma_before_the_column(self):
        text = 'desc,qty\n"Pens, blue",3\nPaper,2\n'
        self.assertEqual(total_by_column(text, 'qty'), 5)

    def test_quoted_comma_with_the_column_in_the_middle(self):
        text = 'desc,qty,note\n"Pens, blue",3,x\nPaper,2,y\n'
        result = total_by_column(text, 'qty')
        self.assertIsInstance(result, int)
        self.assertEqual(result, 5)

    def test_doubled_quotes_inside_a_quoted_field(self):
        text = 'desc,qty\n"He said ""hi, there""",2\nPlain,1\n'
        self.assertEqual(total_by_column(text, 'qty'), 3)


if __name__ == '__main__':
    unittest.main()
