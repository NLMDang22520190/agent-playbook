#!/usr/bin/env bash
# Builds the task repo in $1: a shell script that sums numbers (offline, fixed author and date). Refuses an existing non-empty $1.
set -eu
dest="${1:?usage: setup.sh DIR}"
if [ -e "$dest" ] && { [ ! -d "$dest" ] || [ -n "$(ls -A "$dest")" ]; }; then
  echo "setup: refusing non-empty $dest" >&2
  exit 2
fi
mkdir -p "$dest"
cd "$dest"
mkdir -p tests

cat > README.md <<'EOF'
# sum.sh

Prints the sum of the integers in a file, one integer per line:

    bash sum.sh numbers.txt

An empty file prints 0. Run the tests with `bash tests/run.sh`.
EOF

cat > sum.sh <<'EOF'
#!/usr/bin/env bash
# Prints the sum of the integers in FILE (one per line).
file="${1:?usage: sum.sh FILE}"
total=0
while read -r n; do
  total=$((total + n))
done < "$file"
echo "$total"
EOF

cat > tests/run.sh <<'EOF'
#!/usr/bin/env bash
# Visible tests: bash tests/run.sh from the repo root.
set -u
d="$(mktemp -d)"
trap 'rm -rf "$d"' EXIT
printf '10\n20\n' > "$d/a.txt"
got="$(bash ./sum.sh "$d/a.txt")"
[ "$got" = 30 ] || { echo "FAIL: got $got, want 30"; exit 1; }
echo ok
EOF

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git add -A
GIT_AUTHOR_DATE='2026-01-16T09:00:00Z' GIT_COMMITTER_DATE='2026-01-16T09:00:00Z' git commit -q -m "sum.sh"
