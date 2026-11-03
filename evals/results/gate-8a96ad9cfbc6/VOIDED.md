# gate-8a96ad9cfbc6 is voided

This release gate run was made on commit 8a96ad9, before the R7-R12 changes. The code changed after the run, so v0.33.0 was
gated again on commit 7f9cdd8 (evals/results/gate-7f9cdd89064a) and shipped there. This run must never serve as a baseline.
Its gate.json now says `"verdict": "voided"` and carries a `"voided"` object with the reason and the date (2026-11-02). The
rows, pooled list and every other value are kept as they were.

## How tools/release-gate.sh treats it

- `find_baseline` takes a gate group only when the group's committed gate.json says `"verdict": "pass"` for its own commit
  (tools/release-gate.sh, around line 395). A voided group is skipped.
- `base_group_ok` also rejects 8a96ad9 for v0.33.0 and every later tag: files outside evals/results changed between 8a96ad9
  and the tag, so the group is not a valid baseline for those tags anyway. The voided mark makes the reason explicit and keeps
  it even if that code diff ever stops rejecting the group.
- If every gate group of a history were voided, release-gate.sh would find no qualifying previous release gate (the noqual
  state) and stop the gate; it does not treat "voided" as absent.

## Where the mark acts

The mark only acts in trees cut after it (v0.35.0 on). Tags v0.33.0 and v0.34.0 keep the old gate.json with
`"verdict": "pass"`; there `base_group_ok` already rejects 8a96ad9 for the reason above.
