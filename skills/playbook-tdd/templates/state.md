# State (resume file)
The orchestrator updates this file after each phase and reads it first when resuming.
Keep it short: it points at the other hand-off files, it does not repeat them.

- **Phase:** spec | spec review | RED | GREEN | review | close-out
- **Slice:** <S1, S2, ... or "all">
- **Weight:** Full | Lite
- **Last sha per role:**
  - tester: <sha>
  - implementer: <sha>
  - reviewer: <the sha it reviewed, or "none yet">
- **Next step:** <the single next action, e.g. "start the implementer for S2 with RED=<sha>">
- **Open questions:** <asked and unanswered, or "none">
