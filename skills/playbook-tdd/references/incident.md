# Production incident

## When it applies
Users are affected now in production: wrong results, errors, an outage, wrong charges. Weight: the mitigation is a restore, not new code; the forward fix takes Full or Lite from the weight table in SKILL.md, like any fix.

## 1. Mitigate first
- Mitigate first: revert the suspect commit(s) or turn the feature flag off. Put no new logic in the mitigation.
- A revert restores code that was tested before, so it is not the "patch at once" that SKILL.md forbids under "When the user says it is wrong".
- A revert is not safe when the bad deploy carries a schema or data migration: the old code meets the new schema, or data dropped by a contract stays lost.
- When the suspect change includes a migration, mitigate with the feature flag or a forward fix instead, and follow migration.md.
- Pushing or deploying needs the user's go-ahead or `autonomy=full`. In a headless run, prepare the revert or flag change and report it; do not push.
- With no revert or flag available, a forward hotfix may go first. Label it `[UNTESTED]` in the report, and write its test the same day as below.

## 2. Regression test the same day
- Write the regression test the same day. Run it against the bad version and see it fail before the fix.
- The forward fix then runs RED and GREEN at the weight the table gives it.
- Never skip or weaken an existing test to ship.

## 3. Fresh evidence
- Observe the mitigation and the fix each in this session: the suite through `proof-run.sh`, plus one real observation such as `curl` on the affected endpoint, a log line, or a post-deploy health or error check.
- A green run from before the incident does not count.

## 4. Report
- The weight line: `Weight: <Full|Lite> (incident: mitigated by <revert sha or flag>)`.
- A timeline: detected, mitigated, fixed, each with a time and its source.
- The cause, classified as in "When the user says it is wrong" in SKILL.md, with its evidence.
- A follow-up item for anything not done that day (the test, a root-cause fix, a monitor or alert).
