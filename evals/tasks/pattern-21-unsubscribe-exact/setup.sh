#!/usr/bin/env bash
# Builds the task repo in $1: a bash mailing-list tool whose unsubscribe removes addresses from a plain-text list (offline, fixed author and date). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest")" ]; }; then
  echo "setup: refusing non-empty $dest" >&2
  exit 2
fi
mkdir -p "$dest"
cd "$dest"
mkdir -p bin tests

cat > README.md <<'PB_TASK_EOF'
# newsletter-list

The newsletter goes to every address in `list.txt`, one address per line (`LIST=path` uses another file).

- `bin/subscribe ADDRESS` adds ADDRESS at the end of the list and prints `subscribed`.
- `bin/unsubscribe ADDRESS` takes ADDRESS off the list and prints `removed N`, N = the number of lines removed.

Bash 3.2 compatible (macOS). Tests: `bash tests/list.sh` from the repo root.
PB_TASK_EOF

cat > bin/subscribe <<'PB_TASK_EOF'
#!/usr/bin/env bash
# subscribe ADDRESS: adds ADDRESS at the end of the mailing list ($LIST, default list.txt) and prints "subscribed".
set -u
addr="${1:?usage: subscribe ADDRESS}"
list="${LIST:-list.txt}"
printf '%s\n' "$addr" >> "$list" || exit 1
echo "subscribed"
PB_TASK_EOF

cat > bin/unsubscribe <<'PB_TASK_EOF'
#!/usr/bin/env bash
# unsubscribe ADDRESS: takes ADDRESS off the mailing list ($LIST, default list.txt) and prints "removed N".
set -u
addr="${1:?usage: unsubscribe ADDRESS}"
list="${LIST:-list.txt}"
[ -f "$list" ] || { echo "unsubscribe: no list $list" >&2; exit 1; }
before="$(wc -l < "$list" | tr -d ' ')"
tmp="$list.tmp.$$"
grep -v "$addr" "$list" > "$tmp"
mv "$tmp" "$list"
after="$(wc -l < "$list" | tr -d ' ')"
echo "removed $((before - after))"
PB_TASK_EOF

cat > tests/list.sh <<'PB_TASK_EOF'
#!/usr/bin/env bash
# Run from the repo root: bash tests/list.sh
set -u
fail=0
assert_eq() { # name want got
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: want [$2] got [$3]"; fail=1; fi
}
d="$(mktemp -d "${TMPDIR:-/tmp}/list-test.XXXXXX")" || exit 2
trap 'rm -rf "$d"' EXIT
export LIST="$d/list.txt"
assert_eq 'subscribe an' subscribed "$(bash ./bin/subscribe an@example.com)"
assert_eq 'subscribe binh' subscribed "$(bash ./bin/subscribe binh@example.com)"
assert_eq 'unsubscribe binh' 'removed 1' "$(bash ./bin/unsubscribe binh@example.com)"
assert_eq 'an stays' an@example.com "$(cat "$LIST")"
exit "$fail"
PB_TASK_EOF

chmod +x bin/subscribe bin/unsubscribe tests/list.sh

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git -c core.excludesFile=/dev/null add -f -A
git update-index --chmod=+x bin/subscribe
git update-index --chmod=+x bin/unsubscribe
git update-index --chmod=+x tests/list.sh
GIT_AUTHOR_DATE='2026-05-11T08:45:00Z' GIT_COMMITTER_DATE='2026-05-11T08:45:00Z' git commit -q -m "newsletter list: subscribe and unsubscribe"
