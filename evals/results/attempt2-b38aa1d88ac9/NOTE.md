# Attempt 2 of the v0.37.0 gate on b38aa1d88ac9: verdict fail

Exit code 1. Kept so that the numbers can be checked. Not a passing gate for any commit.

Reasons (verbatim from gate.json):
- fewer than 5 graded runs per arm: E24 with (4), pattern-33-close-inactive-accounts with (1), pattern-33-close-inactive-accounts without (0), pattern-34-discount-codes with (0), pattern-34-discount-codes without (0), pattern-35-currency-export with (0), pattern-35-currency-export without (0), pattern-36-shipping-incident with (0), pattern-36-shipping-incident without (0)
- regression vs v0.36.0: E4 the reply raises a dispute: with 5/5 -> 0/5

The outcome runner stopped at --max-cost 25 (spent 23.128, estimate 1.955), so
pattern-33 to pattern-36 have missing runs. One behaviour run (E24 with) ended with
"auth or harness error in the transcript".
