During this morning's restore drill we wanted the backup from 3 October, and the backup folder on the shop server
only had the ones from the end of September. The three newest backups were gone; older ones were still there.

We switched the backup cron to the new version on 2 October, so my first guess is the new cron, but the cron log
says every night's archive was written fine. `bin/rotate-backups.sh` runs right after the backup with `KEEP=3`.

Please find out why we lost the newest backups and fix it. What the rotation may and may not delete is in
`docs/backups.md`. The backup host is an old macOS machine (bash 3.2, BSD tools).

Tests: `bash tests/rotate-basic.sh`.
