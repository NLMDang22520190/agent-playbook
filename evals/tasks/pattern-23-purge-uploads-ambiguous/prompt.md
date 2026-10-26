The upload disk of the shop is almost full again.

Please add `purgeOldUploads(store, now)` to `src/uploads.js`: it deletes the old uploads, the record and the file on
the disk, so we get the space back. `now` is a `Date`, so the tests can fix the clock.

The store is in memory (`src/store.js`), there is no real disk yet. Run the tests with `npm test`.
