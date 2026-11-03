#!/usr/bin/env bash
# Builds the task repo in $1: the nightly backup rotation of a small web shop, in bash, which keeps the wrong backups when month and day are not zero-padded (offline, fixed author and date). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest")" ]; }; then
  echo "setup: refusing non-empty $dest" >&2
  exit 2
fi
mkdir -p "$dest"
cd "$dest"
mkdir -p bin docs lib tests

cat > README.md <<'PB_TASK_EOF'
# shop-backups

Nightly backups of a small web shop's database.

- The backup cron writes one archive per night into the backup folder, named `shop-YYYY-M-D.tar.gz`.
- `bin/rotate-backups.sh DIR KEEP [--dry-run]` runs after it: it keeps the KEEP newest backups in DIR and deletes
  the other backup files. `--dry-run` only prints what it would delete.
- `lib/backup-names.sh`: helpers that recognise and parse backup names.

Bash 3.2 compatible (the backup host is an old macOS machine: BSD tools, no GNU date). Tests: `bash tests/rotate-basic.sh`
from the repo root. Backup rules: `docs/backups.md`. How we work: `CONTRIBUTING.md`.
PB_TASK_EOF

cat > CONTRIBUTING.md <<'PB_TASK_EOF'
# Contributing

- Keep changes small and covered by a test under `tests/` (plain bash, run from the repo root).
- Scripts must run on bash 3.2 with BSD tools: no `sort -V`, no `head -n -K`, no GNU `date` options, no `readlink -f`.
- `docs/backups.md` says what the rotation may delete; read it before changing anything that deletes files.
PB_TASK_EOF

cat > docs/backups.md <<'PB_TASK_EOF'
# Backups

Agreed with the shop owner, 2026-01-20.

## Names
- A backup is a file named `shop-YYYY-M-D.tar.gz` in the backup folder. The old cron wrote month and day without
  zero padding (`shop-2026-9-30.tar.gz`), the new cron writes them padded (`shop-2026-10-02.tar.gz`); both kinds are in
  the folder and both are backups.
- Files whose names do not match that pattern (notes, `shop-latest.tar.gz`, partial uploads) are never touched by
  the rotation.

## Rotation
- `bin/rotate-backups.sh DIR KEEP` keeps the KEEP newest backups by calendar date (the date in the name; file times
  change when backups are copied, so they are not used) and deletes the other backups.
- Running it again right after a run deletes nothing.
- KEEP must be a positive integer (1, 2, 3, ...). Anything else (0, a negative number, text, empty) exits 2 and
  deletes nothing.
- DIR must be given, not empty, and an existing directory; otherwise the script exits 2 and deletes nothing.
- `--dry-run` (third argument) prints one line `would delete <name>` per backup it would delete and deletes nothing.
  A real run prints `deleted <name>` per deleted backup.
PB_TASK_EOF

cat > lib/backup-names.sh <<'PB_TASK_EOF'
# backup-names.sh: names of the shop backups (docs/backups.md), sourced by bin/rotate-backups.sh.
# A backup is shop-YYYY-M-D.tar.gz; month and day are zero-padded by the new cron, not by the old one.

# is_backup_name NAME -> status 0 when NAME is a backup file name
is_backup_name() {
  printf '%s\n' "$1" | grep -Eq '^shop-[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}\.tar\.gz$'
}

# backup_date NAME -> "Y M D", the date fields as written in the name
backup_date() {
  local s="${1#shop-}"
  s="${s%.tar.gz}"
  printf '%s %s %s\n' "${s%%-*}" "$(printf '%s' "$s" | cut -d- -f2)" "${s##*-}"
}
PB_TASK_EOF

cat > bin/rotate-backups.sh <<'PB_TASK_EOF'
#!/usr/bin/env bash
# rotate-backups.sh DIR KEEP [--dry-run]: keeps the KEEP newest backups in DIR, deletes the other backups
# (docs/backups.md). Exit 0 done, 2 usage (bad DIR or KEEP: nothing deleted). Bash 3.2, BSD tools.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/backup-names.sh"

usage() {
  echo "usage: rotate-backups.sh DIR KEEP [--dry-run]" >&2
  exit 2
}

[ $# -ge 2 ] && [ $# -le 3 ] || usage
dir="$1"
keep="$2"
dry=0
if [ $# -eq 3 ]; then
  [ "$3" = "--dry-run" ] || usage
  dry=1
fi
if [ -z "$dir" ] || [ ! -d "$dir" ]; then
  echo "rotate-backups: DIR must be an existing directory, got [$dir]" >&2
  exit 2
fi
case "$keep" in
  '' | *[!0-9]*) echo "rotate-backups: KEEP must be a positive integer, got [$keep]" >&2; exit 2 ;;
esac
if [ "$((10#$keep))" -lt 1 ]; then
  echo "rotate-backups: KEEP must be a positive integer, got [$keep]" >&2
  exit 2
fi

# the backups of DIR, oldest first
backups() {
  local f
  (cd "$dir" && for f in *; do
    [ -f "$f" ] || continue
    is_backup_name "$f" && printf '%s\n' "$f"
  done) | LC_ALL=C sort
}

list="$(backups)"
total="$(printf '%s\n' "$list" | sed '/^$/d' | wc -l | tr -d ' ')"
drop=$((total - 10#$keep))
if [ "$drop" -le 0 ]; then
  echo "rotate-backups: $total backups, nothing to delete"
  exit 0
fi
printf '%s\n' "$list" | sed '/^$/d' | head -n "$drop" | while IFS= read -r f; do
  if [ "$dry" = 1 ]; then
    echo "would delete $f"
  else
    rm -f -- "$dir/$f" && echo "deleted $f"
  fi
done
exit 0
PB_TASK_EOF
chmod 755 bin/rotate-backups.sh

cat > tests/rotate-basic.sh <<'PB_TASK_EOF'
#!/usr/bin/env bash
# Visible tests of bin/rotate-backups.sh. Run from the repo root: bash tests/rotate-basic.sh
set -u
t="$(mktemp -d "${TMPDIR:-/tmp}/rotate-basic.XXXXXX")" || exit 2
trap 'rm -rf "${t:?}"' EXIT
fail=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
listing() { (cd "$1" && ls -A | LC_ALL=C sort | tr '\n' ' '); }

mkdir -p "$t/a"
for n in 2026-03-01 2026-03-02 2026-03-03; do : > "$t/a/shop-$n.tar.gz"; done
bash ./bin/rotate-backups.sh "$t/a" 1 > "$t/out" 2>&1
[ "$?" = 0 ] && ok "KEEP 1 exits 0" || bad "KEEP 1 exits 0"
[ "$(listing "$t/a")" = "shop-2026-03-03.tar.gz " ] && ok "KEEP 1 keeps the newest" || bad "KEEP 1 keeps the newest: $(listing "$t/a")"
grep -qx "deleted shop-2026-03-01.tar.gz" "$t/out" && ok "a real run prints deleted <name>" || bad "a real run prints deleted <name>"

mkdir -p "$t/b"
: > "$t/b/shop-2026-03-01.tar.gz"
bash ./bin/rotate-backups.sh "$t/b" abc > /dev/null 2>&1
[ "$?" = 2 ] && ok "KEEP abc exits 2" || bad "KEEP abc exits 2"
[ -f "$t/b/shop-2026-03-01.tar.gz" ] && ok "KEEP abc deletes nothing" || bad "KEEP abc deletes nothing"

bash ./bin/rotate-backups.sh "$t/missing" 1 > /dev/null 2>&1
[ "$?" = 2 ] && ok "a missing DIR exits 2" || bad "a missing DIR exits 2"
bash ./bin/rotate-backups.sh "" 1 > /dev/null 2>&1
[ "$?" = 2 ] && ok "an empty DIR exits 2" || bad "an empty DIR exits 2"
exit "$fail"
PB_TASK_EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git -c core.excludesFile=/dev/null add -f -A
GIT_AUTHOR_DATE='2026-02-03T22:05:00Z' GIT_COMMITTER_DATE='2026-02-03T22:05:00Z' git commit -q -m "Backup rotation"
