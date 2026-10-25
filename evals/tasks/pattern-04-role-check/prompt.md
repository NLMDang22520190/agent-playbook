Incident from this morning: an order was cancelled by an account with the `viewer` role. Viewer accounts are read-only
(we hand them to accountants and partners) and must never be able to change an order.

The rule we want: only `admin` and `staff` may cancel any order; a `customer` may cancel only their own order. Nobody
else may cancel, and that includes roles we add later and requests with no signed-in user.

Please fix the permission check in `src/auth.js`. It should return `true` or `false`.
