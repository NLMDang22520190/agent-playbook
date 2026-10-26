#!/usr/bin/env bash
# PB-HIDDEN-CANARY:pattern-19-archive-spaces
# Hidden FAIL_TO_PASS test: names with spaces, a double space, a leading dash, an apostrophe and brackets are archived
# like any other name: each file copied once, listed once in MANIFEST, and the count matches.
# NTFS-legal names only (no * ? " < > | : tab newline), decision D13. Run from the repo root: bash tests/archive-names.f2p.sh
set -u
d="$(mktemp -d "${TMPDIR:-/tmp}/pbo19.XXXXXX")" || exit 2
trap 'rm -rf "$d"' EXIT
fail=0
check() { # name got want
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: got [$2] want [$3]"; fail=1; fi
}
src="$d/in"; dst="$d/out"
mkdir -p "$src" "$dst"
set -- 'my notes.txt' 'two  spaces.txt' '-draft.txt' "it's done.txt" 'report[1].txt' 'report1.txt'
for n in "$@"; do printf 'content of %s\n' "$n" > "$src/$n"; done

out="$(bash ./bin/archive "$src" "$dst" 2>"$d/stderr")"; rc=$?
check 'exit status' "$rc" 0
check 'reported count is the number of files' "$out" 'archived 6 files'
for n in "$@"; do
  if [ -f "$dst/$n" ]; then
    check "copied with its content: [$n]" "$(cat "$dst/$n")" "content of $n"
  else
    check "copied: [$n]" missing present
  fi
done
want="$(printf '%s\n' "$@" | LC_ALL=C sort)"
if [ -f "$dst/MANIFEST" ]; then
  check 'MANIFEST lists each name exactly once' "$(LC_ALL=C sort "$dst/MANIFEST")" "$want"
else
  check 'MANIFEST written' missing present
fi
check 'DEST holds the files and MANIFEST, nothing else' "$(ls -A "$dst" | LC_ALL=C sort)" "$(printf '%s\n' "$@" MANIFEST | LC_ALL=C sort)"
exit "$fail"
