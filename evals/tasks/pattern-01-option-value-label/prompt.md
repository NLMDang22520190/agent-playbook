Every web order that picks a finish ends up as "manual quote" instead of getting a price. Support has been quoting these
by hand for two days.

Example from today: product with base price 10000 and a finish option whose choices are

- value `matte`, label "Matte finish", surcharge 2000
- value `gloss`, label "Gloss finish", surcharge 3000

The order form sends `{ finish: 'matte' }` (the option value, as it always has) and the order comes back
`{ manual: true, total: null }`. We expected 12000.

Orders without options are priced fine, and the tests in this repo are green, so something must be off in how the
selection is matched. Please fix the pricing so these orders are priced automatically again. The API takes option values
only; labels are not accepted, so a choice the product does not have (a label sent in place of a value included) should
still go to manual quote.
