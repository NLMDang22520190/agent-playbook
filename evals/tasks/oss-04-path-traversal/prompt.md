Security report (rated high): the static file handler serves files outside the public directory.

The reporter showed that requests like these get past our check and end up pointing outside `public/`:

- `/%2e%2e/secret.txt` (URL-encoded dots)
- a path into a sibling directory whose name starts with the same letters as the public root, e.g. `public2/`

Plain `..` segments are part of the same class of problem. Any URL path that would resolve to a location outside the
public root, encoded or not, must be refused (`resolvePublic` returns `null`). Normal paths, including ones with `..`
that stay inside the root, must keep working.

Please fix `resolvePublic` in `src/static.js`.
