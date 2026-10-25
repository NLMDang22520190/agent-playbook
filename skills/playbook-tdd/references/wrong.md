## When the user says it is wrong
Do not defend the result and do not patch at once; in a production incident, mitigate first (`references/incident.md`).
1. Restate in two lines what the user expected and what was delivered.
2. Classify the cause as one of: misread request, missed place (scan), wrong assumption, not verified
   live, real bug. Give the evidence for that cause (a command and its output, or a file:line).
3. Fix it test-first: a failing test or eval for the miss, seen failing, then the fix. For a docs-only
   (Exempt) misread, fix it and re-check the result against the request; no test is needed.
4. If the cause is a playbook gap, capture it with `playbook-feedback` (kind `gap`, source `user`) and
   propose a regression eval scenario in the item. If the cause is specific to this project, propose a
   lesson with `playbook-learn` instead.

**Why:** a patch without a named cause fixes one symptom and repeats the miss.
