# Review scope: what the reviewer reads and how many rounds

This page describes the reviewer role of `playbook-tdd` as it is written in the repo today. It does not add a rule. Sources: `skills/playbook-tdd/roles/reviewer.md`, `skills/playbook-tdd/references/release.md`.

## What the reviewer reads
- The whole change, not the last commit: `git diff <BASE_SHA>..HEAD`, where `<BASE_SHA>` is the base recorded when the work started (`roles/reviewer.md`, input list).
- With it: `.agents/handoff/01-spec.md`, the slice reports `02-*` and `03-*`, and the final report.
- Test files are compared against the base too (`git diff <BASE_SHA>..HEAD -- <test paths>`) to check that no test was weakened, and `git diff --raw` is read for a mode change from `100755` to `100644`.
- The reviewer opens the running app itself for a UI change (mobile width first, then desktop). Tests and diffs cannot show the screen.

## Introduced or pre-existing
Each finding is marked `introduced` (this change caused it) or `pre-existing` (also present at the base sha, checked with `git show <BASE_SHA>:<path>`). When unsure, the reviewer marks it introduced. Pre-existing findings go to the queue, written under "Found, not fixed" in the final report. A pre-existing security MAJOR is raised to the user in one line (fix now or queue) and never fixed silently.

## Rounds
- Phase 3 code-review rounds are capped at **2 per lane or slice**. From round 3 on, fix only a MAJOR that this change introduced, and give it one more round. Everything else goes to the queue (`references/release.md`, "Review rounds").
- Spec-review and dispute limits are unchanged.

## Weight decides whether there is a reviewer
Full has the reviewer role. Lite does not: the same agent makes the check and reports what it saw (`SKILL.md`, Lite steps). A UI change at Lite therefore relies on that agent's own observation.

## `/code-review`
- The playbook does not call or mention Claude Code's built-in `/code-review` command anywhere in `skills/`, `AGENTS.global.md` or the README (searched with `git grep` on 2026-11-14).
- [CHƯA KIỂM CHỨNG] How `/code-review` overlaps with the reviewer role: what it reads, how many rounds it runs, and whether it separates introduced from pre-existing findings. This page does not claim either way. Run it as an extra read on a finished diff if you want one, and treat its findings as input to the reviewer's list, not as a replacement for the role.
