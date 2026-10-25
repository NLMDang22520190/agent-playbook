#!/usr/bin/env bash
# Tests for tools/clean-pbtest.sh (v0.25.1): the manual clean tool for stale test temp dirs. Each case uses a private TMPDIR
# (a mk_tmp dir of this suite); entries are aged with `touch -t` to a fixed old time. The real /tmp is never touched.
#   AC1 dry run (the default) lists only old pbtest.* dirs and pblist.* files owned by you, prints a count, removes nothing
#   AC2 --yes removes exactly those; fresh entries, other names and a symlink named pbtest.* are untouched
#   AC3 --hours N moves the age limit; N must be a positive integer (else exit 2); --help exits 0; unknown option exits 2
#   AC4 TMPDIR set but empty, or resolving to /, is refused (exit 2); a trailing slash on TMPDIR works
# Runtime estimate for tests/shard-weights: about 2 seconds (estimate, L-0009).
. "$(dirname "$0")/lib.sh"
TOOL="$PB_ROOT/tools/clean-pbtest.sh"

OLD=202001010000
age() { touch -t "$OLD" "$@"; }
# mkbase -> a private TMPDIR holding old and fresh candidates and bystanders; sets B
mkbase() {
  B="$(mk_tmp)"
  mkdir "$B/pbtest.old1" "$B/pbtest.old2" "$B/pbtest.fresh" "$B/other.old" "$B/pbtestx.old"
  touch "$B/pbtest.old1/f" "$B/pbtest.old2/f"
  : > "$B/pblist.old"; : > "$B/pblist.fresh"; : > "$B/notes.old"
  mkdir "$B/elsewhere"; touch "$B/elsewhere/keep"
  ln -s "$B/elsewhere" "$B/pbtest.link"
  # a pbtest.* regular file and a pblist.* dir are not candidates either
  : > "$B/pbtest.afile"; mkdir "$B/pblist.adir"
  age "$B/pbtest.old1/f" "$B/pbtest.old2/f" "$B/pbtest.old1" "$B/pbtest.old2" "$B/pblist.old" "$B/other.old" "$B/pbtestx.old" "$B/notes.old" "$B/pbtest.afile" "$B/pblist.adir" "$B/elsewhere/keep" "$B/elsewhere"
  touch -h -t "$OLD" "$B/pbtest.link" 2>/dev/null || true
}
tool() { run env TMPDIR="$B" bash "$TOOL" "$@"; }

echo "AC1 dry run"
mkbase
tool
assert_rc "AC1 dry run exits 0" 0
assert_contains "AC1 lists the old dir" "$OUT" "$B/pbtest.old1"
assert_contains "AC1 lists the second old dir" "$OUT" "$B/pbtest.old2"
assert_contains "AC1 lists the old list file" "$OUT" "$B/pblist.old"
assert_not_contains "AC1 does not list the fresh dir" "$OUT" "pbtest.fresh"
assert_not_contains "AC1 does not list the fresh list file" "$OUT" "pblist.fresh"
assert_not_contains "AC1 does not list other names" "$OUT" "other.old"
assert_not_contains "AC1 does not list pbtestx.*" "$OUT" "pbtestx.old"
assert_not_contains "AC1 does not list a symlink named pbtest.*" "$OUT" "pbtest.link"
assert_not_contains "AC1 does not list a pbtest.* regular file" "$OUT" "pbtest.afile"
assert_not_contains "AC1 does not list a pblist.* dir" "$OUT" "pblist.adir"
assert_contains "AC1 prints the count" "$OUT" "3 stale"
assert_dir "AC1 dry run removed nothing (dir)" "$B/pbtest.old1"
assert_file "AC1 dry run removed nothing (file)" "$B/pblist.old"
assert_contains "AC1 says how to remove" "$OUT" "--yes"

echo "AC2 --yes"
tool --yes
assert_rc "AC2 --yes exits 0" 0
assert_no_path "AC2 old dir removed" "$B/pbtest.old1"
assert_no_path "AC2 second old dir removed with its content" "$B/pbtest.old2"
assert_no_path "AC2 old list file removed" "$B/pblist.old"
assert_dir "AC2 fresh dir kept" "$B/pbtest.fresh"
assert_file "AC2 fresh list file kept" "$B/pblist.fresh"
assert_dir "AC2 other name kept" "$B/other.old"
assert_dir "AC2 pbtestx.* kept" "$B/pbtestx.old"
assert_file "AC2 notes.old kept" "$B/notes.old"
assert_file "AC2 pbtest.* regular file kept" "$B/pbtest.afile"
assert_dir "AC2 pblist.* dir kept" "$B/pblist.adir"
assert_link_to "AC2 the symlink named pbtest.link is kept, not followed" "$B/pbtest.link" "$B/elsewhere"
assert_file "AC2 the symlink target content is kept" "$B/elsewhere/keep"
assert_contains "AC2 reports the removal" "$OUT" "removed 3"
tool --yes
assert_rc "AC2 a second --yes run exits 0" 0
assert_contains "AC2 second run finds nothing" "$OUT" "0 stale"

echo "AC3 --hours and usage"
mkbase
age "$B/pbtest.fresh"
touch -t "$(date +%Y%m%d%H%M)" "$B/pbtest.fresh"
tool --hours 100000
assert_rc "AC3 a huge --hours exits 0" 0
assert_contains "AC3 nothing is old enough" "$OUT" "0 stale"
tool --hours 1
assert_contains "AC3 --hours 1 still keeps the fresh dir" "$OUT" "3 stale"
assert_not_contains "AC3 --hours 1 does not list the fresh dir" "$OUT" "pbtest.fresh"
for bad in 0 -1 abc 1.5 "" 007x; do
  tool --hours "$bad"
  assert_rc "AC3 --hours [$bad] exits 2" 2
done
tool --hours
assert_rc "AC3 --hours without a value exits 2" 2
tool --bogus
assert_rc "AC3 an unknown option exits 2" 2
tool extra
assert_rc "AC3 a stray argument exits 2" 2
tool --help
assert_rc "AC3 --help exits 0" 0
assert_contains "AC3 --help names the usage" "$OUT" "usage"
assert_dir "AC3 usage errors removed nothing" "$B/pbtest.old1"

echo "AC4 TMPDIR guards"
run env TMPDIR="" bash "$TOOL" --yes
assert_rc "AC4 TMPDIR set but empty exits 2" 2
run env TMPDIR=/ bash "$TOOL" --yes
assert_rc "AC4 TMPDIR=/ exits 2" 2
run env TMPDIR=// bash "$TOOL" --yes
assert_rc "AC4 TMPDIR=// exits 2" 2
run env TMPDIR="$B/elsewhere/.." bash "$TOOL"
assert_rc "AC4 a TMPDIR with .. that resolves to a real dir works" 0
run env TMPDIR="$B/" bash "$TOOL"
assert_rc "AC4 a trailing slash works" 0
assert_contains "AC4 a trailing slash still lists" "$OUT" "pbtest.old1"
run env TMPDIR="$B/missing" bash "$TOOL"
assert_rc "AC4 a missing TMPDIR exits 2" 2
assert_dir "AC4 guards removed nothing" "$B/pbtest.old1"
t_summary
