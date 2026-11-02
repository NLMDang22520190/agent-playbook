The accountant flagged two things in last month's refund report:

- Order R-0412 shows "kept: -0.01". The customer returned the three mugs of that order one at a time, and the three
  refunds add up to one cent more than the customer paid for them.
- A customer returned one item that cost 1.38 with tax on the receipt and got 1.37 back.

Please fix this so the refunds follow `docs/money-rules.md`; that file is agreed with the accountant and is the
source of truth for how refunds are calculated.

Tests run with `python3 -m unittest discover -s tests -t .`.
