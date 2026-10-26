#!/usr/bin/env bash
# Builds the task repo in $1: a bash archive script that copies files flat and writes a name list (offline, fixed author and date). Refuses an existing non-empty $1.
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
# archive

`bin/archive SRC DEST` copies every regular file under SRC into DEST (flat), writes `DEST/MANIFEST` with one file
name per line, and prints `archived N files`.

Bash 3.2 compatible (macOS). Tests: `bash tests/archive.sh` from the repo root.
PB_TASK_EOF

cat > bin/archive <<'PB_TASK_EOF'
#!/usr/bin/env bash
# archive SRC DEST: copies every regular file under SRC into DEST (flat), writes DEST/MANIFEST (one name per line) and
# prints "archived N files", N = the number of MANIFEST lines.
set -u
here="$(cd "$(dirname "$0")/.." && pwd)"
. "$here/lib/collect.sh"
. "$here/lib/manifest.sh"
src="${1:?usage: archive SRC DEST}"
dest="${2:?usage: archive SRC DEST}"
mkdir -p "$dest" && dest="$(cd "$dest" && pwd)" || exit 1
cd "$src" || exit 1
files="$(collect_files .)"
for f in $files; do
  cp $f "$dest/" 2>/dev/null
done
write_manifest "$dest" $files
echo "archived $(wc -l < "$dest/MANIFEST" | tr -d ' ') files"
PB_TASK_EOF

cat > lib/collect.sh <<'PB_TASK_EOF'
# collect_files SRC -> the regular files under SRC, relative to SRC, one per line
collect_files() {
  local f
  for f in $(cd "$1" && find . -type f); do
    printf '%s\n' "${f#./}"
  done
}
PB_TASK_EOF

cat > lib/manifest.sh <<'PB_TASK_EOF'
# write_manifest DEST PATH... -> DEST/MANIFEST with the file name of each PATH, one per line
write_manifest() {
  local dest="$1" p
  shift
  : > "$dest/MANIFEST"
  for p in $*; do
    echo $(basename $p) >> "$dest/MANIFEST"
  done
}
PB_TASK_EOF

cat > tests/archive.sh <<'PB_TASK_EOF'
#!/usr/bin/env bash
# Run from the repo root: bash tests/archive.sh
set -u
fail=0
assert_eq() { # name want got
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: want [$2] got [$3]"; fail=1; fi
}
d="$(mktemp -d "${TMPDIR:-/tmp}/archive-test.XXXXXX")" || exit 2
trap 'rm -rf "$d"' EXIT
mkdir -p "$d/in/sub" "$d/out"
printf 'one\n' > "$d/in/one.txt"
printf 'two\n' > "$d/in/sub/two.txt"
out="$(bash ./bin/archive "$d/in" "$d/out")"
assert_eq 'count' 'archived 2 files' "$out"
assert_eq 'one.txt copied' one "$(cat "$d/out/one.txt")"
assert_eq 'two.txt copied flat' two "$(cat "$d/out/two.txt")"
assert_eq 'name list' "$(printf 'one.txt\ntwo.txt')" "$(LC_ALL=C sort "$d/out/MANIFEST")"
exit "$fail"
PB_TASK_EOF

chmod +x bin/archive tests/archive.sh

git init -q
git config user.name "Task Author"
git config user.email "author@example.invalid"
git config commit.gpgsign false
git config core.autocrlf false
git -c core.excludesFile=/dev/null add -f -A
git update-index --chmod=+x bin/archive
git update-index --chmod=+x tests/archive.sh
GIT_AUTHOR_DATE='2026-03-16T16:20:00Z' GIT_COMMITTER_DATE='2026-03-16T16:20:00Z' git commit -q -m "archive: flat copy with a name list and a count"
