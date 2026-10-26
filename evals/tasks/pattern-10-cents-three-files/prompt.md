Checkout totals have been wrong since the v2.3.0 release, the one that moved the checkout to integer cents.

Example from support today: one lamp at 49.99, coupon SAVE5 (5.00 off), 8% tax, flat shipping 4.90, free shipping
from 50.00. The customer should pay 53.49, but the order page shows a total of `53.93.52`, which is not even a
valid amount.

Please fix the checkout so totals are right again.
