# Weight: worked examples

`SKILL.md` "Pick the weight" holds the rules (Full, Lite, Exempt, decide consistently, user override, "quick"); this file
holds the worked example and the risk line that apply them (moved in v0.35.0, text unchanged).

## Pick the weight: message text in a sensitive module

A change limited to user-visible message or comment text (a typo, a wording fix), with no control flow and no data shape touched, is Lite even in a sensitive module, provided the string is not parsed, matched or sent as data (an error code, a key, a log format or a message another system matches on is data, so Full applies). State the sensitivity as a risk line in the spec and the report (for example "risk: billing module, message text only"), not as the reason for Full.
