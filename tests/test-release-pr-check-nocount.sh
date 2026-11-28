#!/usr/bin/env bash
# Tests for tools/release-pr-check.sh after v0.38 T12 (spec: docs/v0.38-t12-spec.md, AC5): the "stale README test count" check is gone.
# A release PR (VERSION changed against BASE) whose tests/*.sh changed after the last commit, with no "release: README test count"
# commit, passes with the usual success line even when the README count changed in the release commit (the old history this branch
# may still carry); the VERSION/CHANGELOG rules are unchanged. Fixture repos only.
. "$(dirname "$0")/lib.sh"
RPC="$PB_ROOT/tools/release-pr-check.sh"
CL3='# Changelog

## 1.2.3 - 2026-10-09
- first line
'
CL4='# Changelog

## 1.2.4 - 2026-10-20
- new release

## 1.2.3 - 2026-10-09
- first line
'
cm() { ( cd "$1" && git add -A && git commit -q --allow-empty -m "${2:-c}" ); }
sha() { ( cd "$1" && git rev-parse HEAD ); }
# mk -> repo at VERSION 1.2.3, a README with a version badge and an OLD-style test count (100), tests/test-a.sh; this commit is BASE
mk() {
  local d; d="$(mk_tmp)"
  mkdir -p "$d/tools" "$d/tests"
  cp -p "$PB_ROOT/tools/check-release.sh" "$PB_ROOT/tools/release-pr-check.sh" "$d/tools/"
  printf '1.2.3\n' > "$d/VERSION"; printf '%s' "$CL3" > "$d/CHANGELOG.md"
  printf '![v](https://img.shields.io/badge/version-1.2.3-4F5BD5) ![t](https://img.shields.io/badge/tests-100-1F9D63)\n' > "$d/README.md"; printf 'echo a\n' > "$d/tests/test-a.sh"
  ( cd "$d" && git init -q && git config user.email t@example.invalid && git config user.name tester && git config commit.gpgsign false )
  cm "$d" base >/dev/null
  printf '%s\n' "$d"
}
bump() { printf '1.2.4\n' > "$1/VERSION"; printf '%s' "$CL4" > "$1/CHANGELOG.md"; printf '![v](https://img.shields.io/badge/version-1.2.4-4F5BD5) ![t](https://img.shields.io/badge/tests-105-1F9D63)\n' > "$1/README.md"; }
rpc() { run_in "$1" bash tools/release-pr-check.sh "$2"; }

echo "no stale README count check (v0.38 T12 AC5)"
assert_file "tool exists" "$RPC"
assert_not_contains "the tool no longer mentions readme-count" "$(cat "$RPC")" "readme-count"

# (a) release commit that changed the README count, then a tests change, no empty "release: README test count" commit -> passes
D="$(mk)"; B="$(sha "$D")"
bump "$D"; cm "$D" release
printf 'echo more\n' >> "$D/tests/test-a.sh"; printf 'echo n\n' > "$D/tests/test-new.sh"; cm "$D" fix
assert_eq "(a) the last commit is the plain fix commit (no README test count commit)" "fix" "$(git -C "$D" log -1 --format=%s)"
rpc "$D" "$B"
assert_rc "(a) tests/*.sh changed after the release commit, no README count commit: exit 0" 0
assert_contains "(a) the success line" "$OUT" "release PR check passed: v1.2.4"
assert_not_contains "(a) no stale-count message" "$OUT" "README test count may be stale"
assert_not_contains "(a) no failure line" "$OUT" "release PR check failed"

# (b) an uncommitted tests change passes too
printf 'echo dirty\n' >> "$D/tests/test-a.sh"
rpc "$D" "$B"
assert_rc "(b) an uncommitted tests/*.sh change: exit 0" 0
assert_contains "(b) the success line" "$OUT" "release PR check passed: v1.2.4"

# (c) the version rules still apply: no CHANGELOG entry for the new version is still refused
D="$(mk)"; B="$(sha "$D")"
printf '1.2.4\n' > "$D/VERSION"; cm "$D" bump-only
rpc "$D" "$B"
assert_rc "(c) VERSION bumped without a CHANGELOG entry: exit 1 (the other checks are not lost)" 1
assert_not_contains "(c) no success line" "$OUT" "release PR check passed"

t_summary
