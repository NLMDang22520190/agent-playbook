# Quick weight

Quick is the cheapest weight. It is for a tiny change that one person could review at a glance. It is chosen when the
change is at most 1 production file and at most 20 changed lines with nothing from the Full column, or when the user
asks for it. It keeps the test-first rule and drops the paperwork.

Removing or renaming an exported symbol is a public API change, so it is in the Full column and never Quick, even when it is one line. The always-on line in AGENTS.global.md is only a summary: load `playbook-tdd` first, then pick the weight.

**Why:** at this size the hand-off files and the review ritual cost more than the change. The test, the evidence and an
honest report are what protect the user, so those stay.

## Quick workflow

Keep: a one-sentence restatement of the request in chat; one grep of the call sites, with the hit count printed; a behaviour change tested first and seen failing; one proof-run after the last change and `git diff --stat`.

Drop: hand-off files, the detailed scan log, Impact, Pre-mortem, the Confidence column, the mutation spot-check, cost.sh, and the Playbook feedback line unless a rule misfired.

Report in 3-5 lines (understanding / change / evidence / not checked) plus a weight line, either `Weight: Quick` or `Weight: Quick (user-requested)`.

## When the user asks for Quick

The user asks for it when they say "quick", "quick one" or "do it quick", or ask for the Quick weight. Run Quick at once, with no re-assessment: the user chose it, and a second guess wastes their time.

There are two stops. At a stop, ask the user once and never auto-upgrade, because the choice of weight is theirs:
- (a) the diff touches the Full column (money, auth, migration, public API or data shape);
- (b) the diff exceeds the Quick limits, measured with `role-gate.sh size --quick` (the same check as in the escalation below; exit 1 means over).

Headless (nobody answers): do not block and do Quick, and label the report "over the limit, user chose Quick" so the risk is visible. For stop (a) also name the Full item in the risk line.

The skip-tests rule still applies inside Quick: write the test first, or ask once and label the result untested. Quick never means no tests.

## When Quick must escalate to Lite

An agent-chosen Quick that exceeds the limits or touches the Full column escalates to Lite. The agent chose Quick, so it also owns the correction.

1. Quick makes no checkpoint commits. After the change, run `role-gate.sh size --quick` against HEAD (the check of stop (b) too). Exit 0 means stay at Quick.
2. On exit 1 (over the limit), stop at Lite. Commit the test files alone as `test(red)`: that sha is RED.
3. Continue at Lite from step 3 (the code that passes the test, gated with `--base $RED`), and write the Lite spec then, with the weight line `Weight: Lite` and the reason.

An agent-chosen Quick is allowed in code the repo documents as critical when the change is message text only or purely additive (the same rule as "Decide consistently" in SKILL.md). State the sensitivity as a risk line.
