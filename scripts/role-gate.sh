#!/usr/bin/env bash
# Mechanical enforcement of role separation in the TDD workflow.
#   role-gate.sh check <tester|implementer|reviewer|infra> [--base REF]
#   role-gate.sh classify <path>        prints "infra", "test" or "code"
#   role-gate.sh size [--base REF] [--max-files N] [--max-lines M]
#                                       Lite size check (defaults 3 files, 100 lines)
#
# Test paths include test configuration and snapshots (jest/vitest/playwright/cypress
# config, karma.conf, .mocharc, pytest.ini, phpunit.xml, __snapshots__/, *.snap).
# *.snap counts as a test file anywhere: a snapshot is a test expectation, and an implementer who
# rewrites it makes a failing test pass without changing behaviour. A project whose *.snap files
# are not tests (e.g. Ubuntu snap packages) sets its own test_path_regex.
#
# size counts production files (non-test, outside .agents/handoff/) changed since REF
# (default HEAD; committed, staged, unstaged and untracked) and their added+deleted lines
# (git diff --numstat; a binary file counts as 1 line; an untracked file counts all its
# lines). Prints "files: F/N lines: L/M"; over either limit -> exit 1, escalate to Full.
#
# What each role may change (relative to REF, default HEAD; includes staged, unstaged
# and untracked files):
#   tester       only test paths            -> production code changed = violation
#   implementer  only non-test paths        -> any test path changed (even deleted) = violation
#   reviewer     nothing                    -> any change = violation
#   infra        only test-infra paths      -> any test or code path changed = violation
# Test infrastructure (runners, shared test helpers) is opt-in: project key test_infra_regex (ERE on
# repo-relative paths, empty = off). Matching paths classify as "infra" (before the test regex); the
# tester and the implementer may not change them, and size counts them like production files.
# Files under .agents/handoff/ are always allowed (role hand-off notes, evidence logs).
#
# Exit: 0 ok | 1 violation | 2 usage | 3 environment (not a git repo, bad ref)
set -u
. "$(dirname "$0")/lib.sh"

DEFAULT_REGEX='(^|/)(test|tests|__tests__|spec|specs|e2e|__mocks__|fixtures|testdata|__snapshots__)(/|$)|(\.test\.|\.spec\.|_test\.|_spec\.)|(^|/)test_[^/]*$|(^|/)conftest\.py$|\.feature$|Tests?\.(java|kt|cs|swift)$|(^|/)(jest|vitest|playwright|cypress)\.config\.[^/]+$|(^|/)karma\.conf\.[^/]+$|(^|/)\.mocharc(\.[^/]+)?$|(^|/)pytest\.ini$|(^|/)phpunit\.xml(\.dist)?$|\.snap$'

# Read both regexes once per run, and refuse an invalid one: grep exits 2 on a bad pattern, which
# would otherwise read as "no match" and let every file through (fail open).
# conf_src KEY -> sets SRC_VAL and SRC_SCOPE (project before global, like pb_conf_get); exit 1 if unset
conf_src() {
  SRC_VAL=""; SRC_SCOPE=""
  if SRC_VAL="$(pb_conf_read "$(pb_conf_project)" "$1")"; then SRC_SCOPE=project; return 0; fi
  if SRC_VAL="$(pb_conf_read "$(pb_conf_global)" "$1")"; then SRC_SCOPE=global; return 0; fi
  SRC_VAL=""; return 1
}
TEST_RE="$DEFAULT_REGEX"; TEST_SCOPE=""
if conf_src test_path_regex; then TEST_RE="$SRC_VAL"; TEST_SCOPE="$SRC_SCOPE"; fi
INFRA_RE=""; INFRA_SCOPE=""; INFRA_SHADOW=""
if conf_src test_infra_regex; then INFRA_RE="$SRC_VAL"; INFRA_SCOPE="$SRC_SCOPE"; fi
# an empty project value switches off a non-empty global one: worth a note (it moves the gate)
if [ -z "$INFRA_RE" ] && [ "$INFRA_SCOPE" = project ]; then
  INFRA_SHADOW="$(pb_conf_read "$(pb_conf_global)" test_infra_regex)" || INFRA_SHADOW=""
fi
valid_re() { printf 'x\n' | grep -Eq -- "$1" 2>/dev/null; [ $? -ne 2 ]; }

classify() {
  if [ -n "$INFRA_RE" ] && printf '%s\n' "$1" | grep -Eq -- "$INFRA_RE"; then echo infra; return; fi
  if printf '%s\n' "$1" | grep -Eq -- "$TEST_RE"; then echo test; else echo code; fi
}

cmd="${1:-}"
case "$cmd" in
  classify | check | size)
    # an empty test_path_regex would match every path: every file a test (fail open for the tester)
    [ -n "$TEST_RE" ] || pb_die "test_path_regex is empty in the $TEST_SCOPE conf; unset it to use the default" 3
    valid_re "$TEST_RE" || pb_die "invalid test_path_regex (grep -E rejects it): $TEST_RE" 3
    if [ -n "$INFRA_RE" ]; then valid_re "$INFRA_RE" || pb_die "invalid test_infra_regex (grep -E rejects it): $INFRA_RE" 3; fi
    ;;
esac
[ $# -gt 0 ] && shift

case "$cmd" in
  classify)
    [ $# -eq 1 ] || pb_die "usage: role-gate.sh classify <path>" 2
    classify "$1"
    ;;
  check)
    role="${1:-}"
    [ $# -gt 0 ] && shift
    case "$role" in tester|implementer|reviewer|infra) ;; *) pb_die "role must be tester|implementer|reviewer|infra" 2 ;; esac
    base="HEAD"
    while [ $# -gt 0 ]; do
      case "$1" in
        --base) [ $# -ge 2 ] || pb_die "--base needs a ref" 2; base="$2"; shift ;;
        *) pb_die "unknown option: $1" 2 ;;
      esac
      shift
    done
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || pb_die "not inside a git work tree (role gates need git)" 3
    git rev-parse --verify -q "$base^{commit}" >/dev/null 2>&1 || pb_die "base ref not found: $base" 3
    top="$(git rev-parse --show-toplevel)"
    cd "$top" || pb_die "cannot enter $top" 3
    # a config file can move the gate: show where the regexes come from, before the verdict
    # control characters (ESC, CR, ...) in a value could hide or rewrite the note in a terminal: show them as ?
    shown() { printf '%s' "$1" | LC_ALL=C tr '\000-\037\177' '?'; }
    [ -n "$TEST_SCOPE" ] && printf 'note: test_path_regex from the %s conf: %s\n' "$TEST_SCOPE" "$(shown "$TEST_RE")"
    [ -n "$INFRA_RE" ] && printf 'note: test_infra_regex from the %s conf: %s\n' "$INFRA_SCOPE" "$(shown "$INFRA_RE")"
    [ -n "$INFRA_SHADOW" ] && printf 'note: test_infra_regex is empty in the project conf and switches off the global value: %s\n' "$(shown "$INFRA_SHADOW")"

    changed="$( { git -c core.quotepath=off diff --name-only --no-renames "$base" --
                  git -c core.quotepath=off ls-files --others --exclude-standard; } | sort -u )"

    violations=0
    checked=0
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      case "$f" in .agents/handoff/*) continue ;; esac
      checked=$((checked + 1))
      kind="$(classify "$f")"
      bad=0
      case "$role" in
        tester)      [ "$kind" != "test" ] && bad=1 ;;
        implementer) [ "$kind" != "code" ] && bad=1 ;;
        infra)       [ "$kind" != "infra" ] && bad=1 ;;
        reviewer)    bad=1 ;;
      esac
      if [ "$bad" -eq 1 ]; then
        printf 'VIOLATION (%s): %s [%s]\n' "$role" "$f" "$kind"
        violations=$((violations + 1))
      fi
    done <<EOF
$changed
EOF
    if [ "$violations" -gt 0 ]; then
      printf 'role gate FAILED for %s: %d violation(s), base=%s\n' "$role" "$violations" "$base"
      exit 1
    fi
    printf 'OK: role gate passed for %s (%d file(s) checked, base=%s)\n' "$role" "$checked" "$base"
    ;;
  size)
    base="HEAD"; max_files=3; max_lines=100
    while [ $# -gt 0 ]; do
      case "$1" in
        --base)      [ $# -ge 2 ] || pb_die "--base needs a ref" 2; base="$2"; shift ;;
        --max-files) [ $# -ge 2 ] || pb_die "--max-files needs a number" 2; max_files="$2"; shift ;;
        --max-lines) [ $# -ge 2 ] || pb_die "--max-lines needs a number" 2; max_lines="$2"; shift ;;
        *) pb_die "unknown option: $1" 2 ;;
      esac
      shift
    done
    for n in "$max_files" "$max_lines"; do
      case "$n" in ''|*[!0-9]*) pb_die "limit must be a non-negative integer: $n" 2 ;; esac
    done
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || pb_die "not inside a git work tree (role gates need git)" 3
    git rev-parse --verify -q "$base^{commit}" >/dev/null 2>&1 || pb_die "base ref not found: $base" 3
    top="$(git rev-parse --show-toplevel)"
    cd "$top" || pb_die "cannot enter $top" 3

    # one "added<TAB>deleted<TAB>path" line per file; untracked files diffed against /dev/null
    stats="$( git -c core.quotepath=off diff --numstat --no-renames "$base" --
              git -c core.quotepath=off ls-files --others --exclude-standard |
                while IFS= read -r u; do
                  [ -n "$u" ] || continue
                  counts="$(git diff --no-index --numstat -- /dev/null "$u" | cut -f1,2)"
                  [ -n "$counts" ] || counts="$(printf '0\t0')"   # empty file: no numstat line
                  printf '%s\t%s\n' "$counts" "$u"
                done )"

    files=0
    lines=0
    while IFS=$'\t' read -r added deleted f; do
      [ -n "$f" ] || continue
      case "$f" in .agents/handoff/*) continue ;; esac
      [ "$(classify "$f")" != "test" ] || continue   # code and infra count
      files=$((files + 1))
      if [ "$added" = "-" ]; then
        lines=$((lines + 1))
      else
        lines=$((lines + added + deleted))
      fi
    done <<EOF
$stats
EOF
    printf 'files: %d/%d lines: %d/%d (base=%s)\n' "$files" "$max_files" "$lines" "$max_lines" "$base"
    if [ "$files" -gt "$max_files" ] || [ "$lines" -gt "$max_lines" ]; then
      printf 'over the Lite size limit: escalate to Full\n'
      exit 1
    fi
    ;;
  *)
    pb_die "usage: role-gate.sh check <role> [--base REF] | classify <path> | size [--base REF] [--max-files N] [--max-lines M]" 2
    ;;
esac
