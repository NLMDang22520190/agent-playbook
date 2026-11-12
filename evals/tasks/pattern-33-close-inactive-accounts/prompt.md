Our account file keeps growing, and most of it is people who signed up once and never came back.

We need to get rid of accounts nobody has used for over a year. Please add
`bin/accounts.sh close-inactive FILE --today DATE` (DATE as `YYYY-MM-DD`), so the nightly job can run it on the
account file.

The account rules are in `docs/`. Run the tests with `bash tests/accounts.sh`.
