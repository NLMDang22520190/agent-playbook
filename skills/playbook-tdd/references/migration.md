# Data and schema migration

## When it applies
A change to a database schema, a stored data shape or existing records: a new or dropped column, a split or renamed field, a backfill. Weight: always Full (the weight table in SKILL.md names migrations).

## Expand, then contract
- Ship separate deployable slices in this order: expand, dual-write, backfill, switch the reads, stop the old writes, contract.
- Expand: add the new shape beside the old one while the app still reads the old one. Dual-write: from then on, every write fills both shapes, so rows written after the backfill have the new fields too. Contract: drop the old shape.
- Ask the user before the contract step (the drop), and only after a backup is proven: restore it once and check the data.
- In a headless or non-interactive run, never run the contract, the drop or any other step that destroys data, even as a logged default: leave it pending and report it as a pending slice for the user.

## Backfill
- Idempotent: a second run changes nothing. A test runs it twice and compares the results.
- Batched, with a bounded batch size, and resumable: it can stop after any batch and continue where it stopped.

## Rollback
- Write the rollback plan (a down migration, or a restore from backup) in the spec before the first run.
- Rehearse it on a test database: up, down, up, checking the data after each step.

## Lock-time budget
- State the expected lock time of each statement and set a statement or lock timeout.
- Avoid long table rewrites, such as a column type change on a large table; cite the engine docs for what each statement locks.
- Estimate the production size (rows, table size) and the run time from it.

## Evidence
- Run the migration tests with the project's database test command. If the project has none, write that under "Not checked" in the report, with what was run instead.
