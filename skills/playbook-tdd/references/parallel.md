# Parallel slices

**Parallel slices.** Slices whose files are disjoint (per the spec's Impact section)
may run in parallel: each slice gets its own git worktree on its own branch, where its tester then its
implementer work, with its own red and green commits and role gates (`role-gate.sh check ... --base` the
slice's own RED sha, run inside that worktree). The orchestrator merges the slice branches into the feature branch.
A merge conflict makes those slices serial. Slices sharing one worktree gate each role with `--commits A..B`. Slices that
share a file stay serial from the start. After the merge, one review covers the merged feature (Phase 3), never
one per parallel slice. Remove the slice worktrees once their branches are merged.

**Why:** disjoint slices cannot break each other.
