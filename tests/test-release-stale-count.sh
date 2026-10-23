#!/usr/bin/env bash
# Tests for the stale README test count check in tools/release-pr-check.sh (v0.24.28).
# A release PR (VERSION changed against BASE) is refused when a tests/*.sh file changed (committed after the last commit that
# changed the README count, or uncommitted in the work tree). Fixture repos only; the real repository is never touched.
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
# readme VERSION COUNT -> README text with the version badge and the three count places
readme() {
  printf '![v](https://img.shields.io/badge/version-%s-4F5BD5) ![t](https://img.shields.io/badge/tests-%s-1F9D63)\n| Tests | **%s passing** |\n%s tests, run in sandboxes\n' "$1" "$2" "$2" "$2"
}
cm() { ( cd "$1" && git add -A && git commit -q --allow-empty -m "${2:-c}" ); }
sha() { ( cd "$1" && git rev-parse HEAD ); }
# mk -> repo at VERSION 1.2.3, README count 100, tests/test-a.sh; this commit is BASE
mk() {
  local d; d="$(mk_tmp)"
  mkdir -p "$d/tools" "$d/tests"
  cp -p "$PB_ROOT/tools/check-release.sh" "$PB_ROOT/tools/release-pr-check.sh" "$d/tools/"
  printf '1.2.3\n' > "$d/VERSION"; printf '%s' "$CL3" > "$d/CHANGELOG.md"
  readme 1.2.3 100 > "$d/README.md"; printf 'echo a\n' > "$d/tests/test-a.sh"
  ( cd "$d" && git init -q && git config user.email t@example.invalid && git config user.name tester && git config commit.gpgsign false )
  cm "$d" base >/dev/null
  printf '%s\n' "$d"
}
bump() { printf '1.2.4\n' > "$1/VERSION"; printf '%s' "$CL4" > "$1/CHANGELOG.md"; }
rpc() { run_in "$1" bash tools/release-pr-check.sh "$2"; }

echo "stale README count"
assert_file "tool exists" "$RPC"

# (a) release PR: count commit, then a test change -> refused, names the count commit
D="$(mk)"; B="$(sha "$D")"
bump "$D"; readme 1.2.4 105 > "$D/README.md"; printf 'echo b\n' >> "$D/tests/test-a.sh"; cm "$D" release
C="$(sha "$D")"
printf 'echo more\n' >> "$D/tests/test-a.sh"; cm "$D" fix
rpc "$D" "$B"
assert_rc "(a) test changed after the count commit: exit 1" 1
assert_contains "(a) message names the staleness" "$OUT" "README test count may be stale: tests changed after ${C}"
assert_contains "(a) message names the fix" "$OUT" "rerun tests/run-all.sh and tools/readme-count.sh"
assert_not_contains "(a) no success line" "$OUT" "release PR check passed"

# (a2) a new tests file counts too
D="$(mk)"; B="$(sha "$D")"
bump "$D"; readme 1.2.4 105 > "$D/README.md"; cm "$D" release
printf 'echo n\n' > "$D/tests/test-new.sh"; cm "$D" fix
rpc "$D" "$B"
assert_rc "(a2) new tests/*.sh after the count commit: exit 1" 1

# (b) count commit after the last test change -> passes
D="$(mk)"; B="$(sha "$D")"
bump "$D"; printf 'echo b\n' >> "$D/tests/test-a.sh"; cm "$D" release
readme 1.2.4 105 > "$D/README.md"; cm "$D" count
rpc "$D" "$B"
assert_rc "(b) count commit after the last test change: exit 0" 0
assert_contains "(b) success line" "$OUT" "release PR check passed"

# (b2) a later non-test commit (docs) does not matter
printf 'note\n' > "$D/notes.txt"; cm "$D" docs
rpc "$D" "$B"
assert_rc "(b2) later non-test commit: exit 0" 0

# (c) non-release PR: unaffected even with stale count
D="$(mk)"; B="$(sha "$D")"
readme 1.2.3 105 > "$D/README.md"; cm "$D" count
printf 'echo b\n' >> "$D/tests/test-a.sh"; cm "$D" fix
rpc "$D" "$B"
assert_rc "(c) non-release PR: exit 0" 0
assert_contains "(c) not a release PR" "$OUT" "not a release PR"

# (d) uncommitted test change in the work tree -> refused
D="$(mk)"; B="$(sha "$D")"
bump "$D"; readme 1.2.4 105 > "$D/README.md"; cm "$D" release
printf 'echo wip\n' >> "$D/tests/test-a.sh"
rpc "$D" "$B"
assert_rc "(d) uncommitted tests change: exit 1" 1
assert_contains "(d) message names the staleness" "$OUT" "README test count may be stale"
D2="$(mk)"; B2="$(sha "$D2")"
bump "$D2"; readme 1.2.4 105 > "$D2/README.md"; cm "$D2" release
printf 'echo wip\n' > "$D2/tests/test-wip.sh"
rpc "$D2" "$B2"
assert_rc "(d2) untracked new tests/*.sh: exit 1" 1

# (e) a version-only README edit after a test change is not a count commit
D="$(mk)"; B="$(sha "$D")"
printf 'echo b\n' >> "$D/tests/test-a.sh"; cm "$D" fix
bump "$D"; readme 1.2.4 100 > "$D/README.md"; cm "$D" release
rpc "$D" "$B"
assert_rc "(e) test change after the last count commit (version bump keeps the count): exit 1" 1

# (f) no count anywhere in the README history: no check
D="$(mk)"; B="$(sha "$D")"
printf '![v](https://img.shields.io/badge/version-1.2.3-4F5BD5)\n' > "$D/README.md"; cm "$D" nocount
B="$(sha "$D")"
bump "$D"; printf '![v](https://img.shields.io/badge/version-1.2.4-4F5BD5)\n' > "$D/README.md"; printf 'echo b\n' >> "$D/tests/test-a.sh"; cm "$D" release
rpc "$D" "$B"
assert_rc "(f) README without a count: exit 0" 0

t_summary
