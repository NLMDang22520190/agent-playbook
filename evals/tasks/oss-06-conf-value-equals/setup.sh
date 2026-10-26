#!/usr/bin/env bash
# Builds the task repo in $1: a bash reader for KEY=VALUE config files (offline, fixed author and date). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest")" ]; }; then
  echo "setup: refusing non-empty $dest" >&2
  exit 2
fi
mkdir -p "$dest"
cd "$dest"
mkdir -p bin lib tests

cat > README.md <<'PB_TASK_EOF'
# confget

Reads settings from the `*.conf` files our deploy scripts use.

    bin/confget KEY FILE     prints the value of KEY in FILE

Scripts source `lib/conf.sh` and call `conf_get KEY FILE` directly.

## Config format

- One `KEY=VALUE` per line.
- KEY is made of letters, digits, `_` and `.` (for example `HTTP_PORT` or `db.url`).
- VALUE is everything after the first `=` up to the end of the line, kept exactly as written: it may be empty and may
  hold `=`, spaces, `#`, `*` and quotes. Nothing is trimmed or unquoted.
- Lines that start with `#` and empty lines are ignored.
- When a key is set on several lines, the last one wins.

`conf_get KEY FILE` prints the value of KEY and a newline and exits 0; when KEY is not set it prints nothing and exits 1.

Bash 3.2 compatible (macOS). Tests: `bash tests/conf.sh` from the repo root.
PB_TASK_EOF

cat > lib/conf.sh <<'PB_TASK_EOF'
# conf_get KEY FILE -> prints the value of KEY in the config FILE (format: README.md); exit 1 when KEY is not set
conf_get() {
  local line
  line="$(grep "^$1" "$2" | head -n 1)"
  [ -n "$line" ] || return 1
  echo $line | cut -d= -f2
}
PB_TASK_EOF

cat > bin/confget <<'PB_TASK_EOF'
#!/usr/bin/env bash
# confget KEY FILE: prints the value of KEY in FILE (format: README.md); exit 1 when KEY is not set, 2 on usage errors
set -u
here="$(cd "$(dirname "$0")/.." && pwd)"
. "$here/lib/conf.sh"
[ $# -eq 2 ] || { echo "usage: confget KEY FILE" >&2; exit 2; }
[ -r "$2" ] || { echo "confget: cannot read $2" >&2; exit 2; }
conf_get "$1" "$2"
PB_TASK_EOF

cat > tests/conf.sh <<'PB_TASK_EOF'
#!/usr/bin/env bash
# Run from the repo root: bash tests/conf.sh
set -u
fail=0
assert_eq() { # name want got
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: want [$2] got [$3]"; fail=1; fi
}
d="$(mktemp -d "${TMPDIR:-/tmp}/conf-test.XXXXXX")" || exit 2
trap 'rm -rf "$d"' EXIT
printf '# web\nHTTP_PORT=8080\nLOG_LEVEL=info\n' > "$d/app.conf"
assert_eq 'a plain value' 8080 "$(bash bin/confget HTTP_PORT "$d/app.conf")"
assert_eq 'another key' info "$(bash bin/confget LOG_LEVEL "$d/app.conf")"
bash bin/confget MISSING "$d/app.conf" >/dev/null
assert_eq 'a missing key exits 1' 1 "$?"
exit "$fail"
PB_TASK_EOF

chmod +x bin/confget tests/conf.sh

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git -c core.excludesFile=/dev/null add -f -A
git update-index --chmod=+x bin/confget
git update-index --chmod=+x tests/conf.sh
GIT_AUTHOR_DATE='2026-05-07T15:45:00Z' GIT_COMMITTER_DATE='2026-05-07T15:45:00Z' git commit -q -m "confget: read KEY=VALUE config files"
