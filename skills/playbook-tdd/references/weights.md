# Weight overrides

A change limited to user-visible message or comment text (a typo, a wording fix), with no control flow and no data shape touched, is Lite even in a sensitive module, provided the string is not parsed, matched or sent as data (an error code, a key, a log format or a message another system matches on is data, so Full applies). State the sensitivity as a risk line in the spec and the report (for example "risk: billing module, message text only"), not as the reason for Full.

**User override (Full to Lite).** When the work meets a Full criterion and the user asks for Lite, ask once, naming the Full
trigger (a file:line or rule) and what is lost: no independent reviewer, no separate contexts; in a headless or non-interactive
run follow the user with no question. Record `Weight: Lite (user override; Full criteria: <x>)` in decisions.md and the final report.
The tests are never skipped: the test comes first and is seen failing, role gates and evidence still run; the skip-tests rule is unchanged. The override covers only the Full criteria named in the question; a new Full criterion, passing the size limit, or a test that looks wrong still escalates (ask again).

**The user says "quick"** (or "quick one", "do it quick"): that counts as asking for Lite; run Lite at once with the label `Weight: Lite (user said quick)`, test first and seen failing, the skip-tests rule unchanged.
If the work meets a Full criterion, the user override above applies, with its label. If quick work grows past the Lite size limit
with no Full criterion, ask once before going to Full; headless, stay Lite and label it (over the size limit).

**Not exempt:** configuration that changes behaviour (feature flags, environment defaults, routing,
permissions, build or deploy settings), generated code that ships, "small" fixes in business logic,
and anything in the Full column. These are at least Lite.
