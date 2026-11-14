# Prompt cache and long sessions: what was measured

This page is for people and agents who run the playbook in long Claude Code sessions. It records measurements and says how sure each one is. It adds no rule to the always-loaded text.

Labels: **[ĐO]** measured on real data, with the source named; **[SUY LUẬN]** reasoning from measured facts; **[CHƯA KIỂM CHỨNG]** not checked. Do not read a [SUY LUẬN] as a fact.

Source of all numbers below: the research branch `claude/serene-galileo-4sr31t` (not merged into `main`): `docs/research-handoff.md` (R1, R2), `docs/research-data/ttl-2026-11-09.tsv`, `docs/research-local-results-2026-11-12.md`. Re-derive a number from those files before you quote it.

## Where the tokens go
- [ĐO] In two long release sessions, cache reads dominated: v0.34 read 344.0M tokens and wrote 15.93M; v0.35 prep read 219.4M and wrote 7.94M. A main-thread call read 390k to 430k tokens on average, and no compaction happened (highest context about 689k).
- [ĐO] Sub-agent starts always write a new cache. In v0.34 sub-agents made 83% of the writes.
- [ĐO, n = 2 sessions with different configurations] A cold restart (a call after more than 60 minutes of idle, writing more than 100k tokens) was about 14% of all writes in v0.34 and about 40% in v0.35. The two sessions did different work, so this is not a comparison of models.

## Cache lifetime
- [ĐO, `claude -p --resume`, Sonnet 5.5, one cloud container, one session per arm] The cache was written to the 1-hour bucket, and each read refreshed it. A call every 54 minutes kept it: the next call read 35,200 tokens and wrote 63 new ones. With no call in between, a call after 2 h 02 min read 0 and wrote 35,218 again.
- [CHƯA KIỂM CHỨNG] The same on the Claude desktop app on Windows.
- [SUY LUẬN] Idle longer than 1 hour costs a full rewrite of the context on the next call, so a long idle is cheaper to end with a short handoff note and a fresh session than to resume, once the context is large.

## Changing the model in a session
- [ĐO, one case] The first call after `/model` wrote 93,896 tokens and read 0.
- [SUY LUẬN] Pick the model at the start of a session. Switching it in the middle gives up the cache.

## Keeping the cache warm
- [ĐO] A session-scoped cron job (`CronCreate`) in the cloud container was lost when the session restarted: two hourly jobs vanished before their first run.
- [ĐO, one job] A local hourly job (minute 7) ran its first time 26 minutes after its nominal time. The tool says a fixed offset up to 30 minutes per job is possible.
- [SUY LUẬN] A nominal 50-minute keep-alive can exceed the 1-hour lifetime. Three runs were planned and not finished, so the real spread is not measured.
- [CHƯA KIỂM CHỨNG] Whether a job runs while the machine sleeps; whether one wake-up at minute 50 keeps the desktop cache warm.

## Plan limits
- [ĐO, one measurement, Team plan] About 25 calls reading roughly 90k cached tokens each (about 2.9M cache-read tokens in all) did not move the 5-hour limit (8%) or the weekly limit (29%).
- [SUY LUẬN] Cache reads count little or nothing toward the plan limit. The 1% rounding does not rule out a small share.
