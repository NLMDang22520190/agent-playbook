#!/usr/bin/env bash
# Builds the task repo in $1: the account file of a small online shop with a bash tool to list and show accounts, and no clean-up of inactive accounts yet (offline, fixed author and date). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest")" ]; }; then
  echo "setup: refusing non-empty $dest" >&2
  exit 2
fi
mkdir -p "$dest"
cd "$dest"
mkdir -p bin lib data docs tests

cat > README.md <<'PB_TASK_EOF'
# shop-accounts

The customer accounts of a small online shop, kept in a TSV file, and a bash tool to read it.

- `data/accounts.tsv`: one account per line, tab-separated, header
  `id	email	last_login	balance_cents	status`. `last_login` is `YYYY-MM-DD`, `balance_cents` is the store credit
  still owed to the customer (whole cents), `status` is `open` or `closed`. Rows are in sign-up batch order, not
  in id order.
- `bin/accounts.sh list FILE` prints every account; `bin/accounts.sh show FILE ID` prints one account.
- `lib/tsv.sh` holds the TSV helpers.

Bash 3.2 and the standard tools (awk, sed) only: it runs on macOS and on the Linux server. Tests:
`bash tests/accounts.sh` from the repo root. Account rules: `docs/retention.md`. How we work: `CONTRIBUTING.md`.
PB_TASK_EOF

cat > CONTRIBUTING.md <<'PB_TASK_EOF'
# Contributing

- Keep changes small and covered by a check in `tests/accounts.sh`.
- Bash 3.2 and BSD/POSIX tools only: no GNU-only options (`date -d`, `sed -i` without a suffix, `readarray`).
- The rules for keeping and closing customer accounts are in `docs/retention.md`; read it before you change or
  remove account data.
PB_TASK_EOF

cat > docs/retention.md <<'PB_TASK_EOF'
# Account retention

Agreed with the shop owner and the accountant, 2025-11-03.

- Orders and invoices reference accounts by `id` and are kept for 10 years, so account rows are never deleted from
  the account file. An account that is no longer used is closed instead.
- Closing an account sets `status` to `closed` and replaces the email with `closed-<id>@invalid` (for account 12:
  `closed-12@invalid`), so no personal data is left on the row. The id, last login and balance stay as they are.
- An account with a non-zero `balance_cents` is store credit we still owe: it stays open until the balance is
  settled, whatever its last login.
- An account is inactive when its last login is before the same calendar date one year earlier. With today
  2026-10-01: a last login on 2025-09-30 is inactive, a last login on 2025-10-01 is still active.
- Every row has a `last_login` date (sign-up counts as a login).
- Rows that are already closed are left exactly as they are.
PB_TASK_EOF

cat > data/accounts.tsv <<'PB_TASK_EOF'
id	email	last_login	balance_cents	status
104	tuan.ngo@example.com	2026-08-19	0	open
101	an.tran@example.com	2026-09-28	0	open
107	closed-107@invalid	2023-02-11	0	closed
102	binh.le@example.com	2024-12-02	0	open
109	chi.vu@example.com	2023-07-30	2400	open
103	dung.pham@example.com	2025-06-14	0	open
PB_TASK_EOF

cat > lib/tsv.sh <<'PB_TASK_EOF'
# TSV helpers for the account file (bash 3.2, awk only). Source it: . lib/tsv.sh

TSV_HEADER="$(printf 'id\temail\tlast_login\tbalance_cents\tstatus')"

# tsv_check FILE -> 0 when FILE exists and starts with the account header, else a message on stderr and 1
tsv_check() {
  [ -f "$1" ] || { echo "accounts: no such file: $1" >&2; return 1; }
  [ "$(sed -n 1p "$1")" = "$TSV_HEADER" ] || { echo "accounts: $1 does not start with the account header" >&2; return 1; }
}

# tsv_rows FILE -> every data row (header and blank lines left out)
tsv_rows() {
  awk 'NR > 1 && NF' "$1"
}

# tsv_row FILE ID -> the data row whose id column is ID (nothing when there is none)
tsv_row() {
  awk -F'\t' -v id="$2" 'NR > 1 && $1 == id' "$1"
}
PB_TASK_EOF

cat > bin/accounts.sh <<'PB_TASK_EOF'
#!/usr/bin/env bash
# accounts.sh: reads the account file (docs/retention.md, README.md).
#   accounts.sh list FILE      every account, one per line: id, email, last login, balance, status
#   accounts.sh show FILE ID   one account, one field per line
set -u
here="$(cd "$(dirname "$0")/.." && pwd)"
. "$here/lib/tsv.sh"

usage() { sed -n '3,4p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

cmd="${1:-}"
[ $# -ge 2 ] || usage
file="$2"

case "$cmd" in
  list)
    tsv_check "$file" || exit 1
    tsv_rows "$file" | awk -F'\t' '{ printf "%-6s %-32s %s %8.2f %s\n", $1, $2, $3, $4 / 100, $5 }'
    ;;
  show)
    [ $# -ge 3 ] || usage
    tsv_check "$file" || exit 1
    row="$(tsv_row "$file" "$3")"
    [ -n "$row" ] || { echo "accounts: no account $3" >&2; exit 1; }
    printf '%s\n' "$row" | awk -F'\t' '{ printf "id: %s\nemail: %s\nlast login: %s\nbalance: %.2f\nstatus: %s\n", $1, $2, $3, $4 / 100, $5 }'
    ;;
  *) usage ;;
esac
PB_TASK_EOF

cat > tests/accounts.sh <<'PB_TASK_EOF'
#!/usr/bin/env bash
# Run from the repo root: bash tests/accounts.sh
set -u
fail=0
assert_eq() { # name want got
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: want [$2] got [$3]"; fail=1; fi
}
d="$(mktemp -d "${TMPDIR:-/tmp}/accounts-test.XXXXXX")" || exit 2
trap 'rm -rf "$d"' EXIT
cp data/accounts.tsv "$d/a.tsv"
assert_eq 'list prints one line per account' 6 "$(bash ./bin/accounts.sh list "$d/a.tsv" | wc -l | tr -d ' ')"
assert_eq 'show prints the email' 'email: chi.vu@example.com' "$(bash ./bin/accounts.sh show "$d/a.tsv" 109 | sed -n 2p)"
assert_eq 'show prints the balance' 'balance: 24.00' "$(bash ./bin/accounts.sh show "$d/a.tsv" 109 | sed -n 4p)"
bash ./bin/accounts.sh show "$d/a.tsv" 999 >/dev/null 2>&1
assert_eq 'show of an unknown id fails' 1 "$?"
assert_eq 'the file is unchanged' "$(cksum < data/accounts.tsv)" "$(cksum < "$d/a.tsv")"
exit "$fail"
PB_TASK_EOF

chmod +x bin/accounts.sh tests/accounts.sh

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git -c core.excludesFile=/dev/null add -f -A
git update-index --chmod=+x bin/accounts.sh
git update-index --chmod=+x tests/accounts.sh
GIT_AUTHOR_DATE='2026-02-17T08:05:00Z' GIT_COMMITTER_DATE='2026-02-17T08:05:00Z' git commit -q -m "Account tool: list and show"
