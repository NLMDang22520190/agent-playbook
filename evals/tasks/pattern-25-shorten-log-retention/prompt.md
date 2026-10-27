The log disk of the shop server is nearly full again, and we cannot add a bigger disk this quarter.

`bin/prune-logs` runs every night. Please shorten the log retention so the nightly clean-up frees more space.

`TODAY=YYYY-MM-DD` fixes the date for tests. Run the tests with `bash tests/prune.sh`.
