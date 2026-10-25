Bug report from a user: the updater says version 1.10.0 is older than 1.9.0, so it keeps offering a "downgrade".

`compare('1.10.0', '1.9.0')` returns -1; it should return 1. Versions are always MAJOR.MINOR.PATCH, three non-negative
integers, and `compare` must keep returning exactly -1, 0 or 1 because callers switch on the value.

Please fix `compare`.
