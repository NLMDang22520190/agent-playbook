# Writing for readers

Load this when you write the final report or any text others will read: a PR description, release notes or CHANGELOG, README or docs, an issue comment. Skip it for short chat replies.

## Rules

- Lead with the answer or the decision. The reader already knows the task, so do not re-explain it.
- Cut the "not X but Y" contrast. State Y.
- Cut one-line closers that repeat the paragraph and staged run-ups that announce what comes next.
- Cut sayings that sound deep but say nothing.
- Cut inflated significance (a pivotal moment, a lasting legacy). Say what changed.
- Watch for overused AI words: delve, crucial, pivotal, tapestry, testament, landscape, robust, showcase, underscore, vibrant, intricate. Use the plain word.
- No decorative headings or emojis.
- No chatbot residue: openers like "Great question" or "Certainly", closers, and offers such as "Let me know" or "Would you like".
- Use no em or en dashes outside code spans, code blocks, commands and paths. Use a comma, a colon, a period or parentheses.

## What these rules never touch

Leave these exactly as written:

- the lines `**Result:**`, `**Weight:**`, `**Mode:**`, `**Models used:**` and `**Playbook feedback:**`, with their bold kept;
- the labels [VERIFIED], [INFERRED] and [UNVERIFIED];
- the user's sentences quoted verbatim in Request coverage;
- the Not checked and Pre-mortem sections;
- evidence such as commands, outputs and path:line references.

The same holds for Request coverage, Not checked, Review and Weight, which scripts/pr-body.sh copies into a PR description.

## Editing limits

Editing may cut or reorder, but never add a fact, name, number or promise that is not in the source.

## Humanizer

If a humanizer skill is installed and the `humanizer` key is `ask`, ask whether to run it in full on text others will read. If the task has no other question, ask about humanizer only when the main deliverable is text others will read. Otherwise use these rules without asking, and never ask in a headless run. The `humanizer` config key sets this: `ask` (default) asks as above; `always` runs humanizer in full without asking; `never` uses only these rules and never asks; an unknown value counts as `ask`.

Credit: these rules are condensed from humanizer (https://github.com/blader/humanizer, MIT license).
