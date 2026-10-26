Checkout totals are wrong since we moved the checkout to integer cents (v2.3.0).

Example from support today: one lamp at 49.99, coupon SAVE5 (5.00 off), 8% tax, flat shipping 4.90, free shipping from
50.00. The customer should pay 53.49. The order page instead shows a discount of 0.05, shipping 0.00, and a tax and a
total with odd fractions (total `53.93.52`).

The config files have not changed since before the release. Please fix the checkout so totals are right again.
