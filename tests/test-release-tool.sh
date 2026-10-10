#!/usr/bin/env bash
# Tests for tools/release.sh (AC4) against a throw-away clone with its own bare origin.
. "$(dirname "$0")/lib.sh"
REL_SRC="$PB_ROOT/tools/release.sh"
export PLAYBOOK_HOME="$(mk_tmp)"
G() { git -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }

# setup -> sets C (clone) and O (bare origin). main is pushed; VERSION 1.2.3 with a CHANGELOG entry.
# tests/run-all.sh is a stub (exit 0) so release.sh's own suite run is cheap.
setup() {
  local w; w="$(mk_tmp)"
  O="$w/origin.git"; C="$w/clone"
  git init -q --bare "$O"
  mkdir -p "$C/tools" "$C/tests" "$C/scripts"
  cp "$PB_ROOT/tools/check-release.sh" "$C/tools/"
  cp "$PB_ROOT/scripts/lib.sh" "$C/scripts/"
  [ -f "$REL_SRC" ] && cp "$REL_SRC" "$C/tools/release.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$C/tests/run-all.sh"
  printf '1.2.3\n' > "$C/VERSION"
  printf '# Changelog\n\n## 1.2.3 - 2026-01-01\n- thing\n' > "$C/CHANGELOG.md"
  ( cd "$C" && git init -q && git checkout -q -b main && G add -A && G commit -qm init &&
    git remote add origin "$O" && git push -q origin main ) || { echo "fixture setup failed"; exit 3; }
}
tags_of() { git -C "$1" tag -l | tr '\n' ' '; }
origin_tags() { git -C "$O" tag -l | tr '\n' ' '; }

echo "refusals"
setup
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC4 control: valid setup passes the checks (dry run) -> exit 0" 0

setup
run_in "$C" bash tools/release.sh v1.2.4
assert_rc "AC4 refuses on VERSION mismatch -> exit 1" 1
assert_eq "AC4 VERSION mismatch creates no tag" "" "$(tags_of "$C")$(origin_tags)"

setup
printf '1.2.4\n' > "$C/VERSION"; ( cd "$C" && G commit -qam bump && git push -q origin main )
run_in "$C" bash tools/release.sh v1.2.4
assert_rc "AC4 refuses on missing CHANGELOG entry -> exit 1" 1
assert_eq "AC4 CHANGELOG refusal creates no tag" "" "$(tags_of "$C")$(origin_tags)"

setup
printf 'wip\n' >> "$C/CHANGELOG.md"
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC4 refuses on a dirty tree -> exit 1" 1
assert_eq "AC4 dirty refusal creates no tag" "" "$(tags_of "$C")$(origin_tags)"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC4 refuses on a dirty tree even with --dry-run -> exit 1" 1

setup
printf 'new\n' > "$C/untracked.txt"
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC4 refuses when an untracked file is present -> exit 1" 1

setup
( cd "$C" && git checkout -q -b feature )
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC4 refuses when not on main -> exit 1" 1
assert_eq "AC4 not-on-main creates no tag" "" "$(tags_of "$C")$(origin_tags)"

setup
( cd "$C" && printf 'x\n' > extra.txt && G add -A && G commit -qm local-only )
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC4 refuses when main is ahead of origin/main -> exit 1" 1
assert_eq "AC4 ahead-of-origin creates no tag" "" "$(tags_of "$C")$(origin_tags)"

setup
W2="$(mk_tmp)"; git clone -q "$O" "$W2/other" 2>/dev/null
( cd "$W2/other" && git config user.email t@example.invalid && git config user.name tester && git config commit.gpgsign false &&
  printf 'y\n' > other.txt && git add -A && git commit -qm upstream && git push -q origin main )
( cd "$C" && git fetch -q origin )
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC4 refuses when main is behind origin/main -> exit 1" 1
assert_eq "AC4 behind-origin creates no tag" "" "$(tags_of "$C")$(origin_tags)"

setup
printf '#!/usr/bin/env bash\nexit 1\n' > "$C/tests/run-all.sh"
( cd "$C" && G commit -qam red-suite && git push -q origin main )
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC4 refuses when tests/run-all.sh fails -> exit 1" 1
assert_eq "AC4 red suite creates no tag" "" "$(tags_of "$C")$(origin_tags)"

echo "dry run"
setup
HEAD0="$(git -C "$C" rev-parse HEAD)"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC4 --dry-run on a valid setup -> exit 0" 0
assert_contains "AC4 --dry-run prints 'would tag'" "$OUT" "would tag"
assert_contains "AC4 --dry-run prints 'would push'" "$OUT" "would push"
assert_contains "AC4 --dry-run names the tag" "$OUT" "v1.2.3"
assert_eq "AC4 --dry-run creates no local tag" "" "$(tags_of "$C")"
assert_eq "AC4 --dry-run pushes nothing to origin" "" "$(origin_tags)"
assert_eq "AC4 --dry-run leaves HEAD alone" "$HEAD0" "$(git -C "$C" rev-parse HEAD)"
run_in "$C" bash tools/release.sh --dry-run v1.2.3
assert_rc "AC4 flag order is free (--dry-run before the tag) -> exit 0" 0
assert_eq "AC4 still no tag after the second dry run" "" "$(tags_of "$C")$(origin_tags)"

echo "release"
setup
HEAD0="$(git -C "$C" rev-parse HEAD)"
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC4 release on a valid setup -> exit 0" 0
assert_contains "AC4 tag exists locally" "$(tags_of "$C")" "v1.2.3"
assert_contains "AC4 tag exists in the origin" "$(origin_tags)" "v1.2.3"
assert_eq "AC4 tag points at HEAD (origin)" "$HEAD0" "$(git -C "$O" rev-parse 'v1.2.3^{commit}')"
assert_eq "AC4 release leaves HEAD alone" "$HEAD0" "$(git -C "$C" rev-parse HEAD)"
assert_eq "AC4 release leaves the tree clean" "" "$(git -C "$C" status --porcelain)"

echo "usage"
setup
run_in "$C" bash tools/release.sh
assert_rc "AC4 no tag -> exit 2" 2
run_in "$C" bash tools/release.sh 1.2.3
assert_rc "AC4 tag without the leading v -> exit 2" 2
run_in "$C" bash tools/release.sh v1.2
assert_rc "AC4 tag not vX.Y.Z -> exit 2" 2
run_in "$C" bash tools/release.sh v1.2.3 --bogus
assert_rc "AC4 unknown flag -> exit 2" 2
run_in "$C" bash tools/release.sh v1.2.3 v1.2.4
assert_rc "AC4 two tags -> exit 2" 2
assert_eq "AC4 usage errors create no tag" "" "$(tags_of "$C")$(origin_tags)"

t_summary
