#!/usr/bin/env bash
# Mechanical enforcement of role separation in the TDD workflow.
#   role-gate.sh check <tester|implementer|reviewer> [--base REF]
#   role-gate.sh classify <path>        prints "test" or "code"
#
# What each role may change (relative to REF, default HEAD; includes staged, unstaged
# and untracked files):
#   tester       only test paths            -> production code changed = violation
#   implementer  only non-test paths        -> any test path changed (even deleted) = violation
#   reviewer     nothing                    -> any change = violation
# Files under .agents/handoff/ are always allowed (role hand-off notes, evidence logs).
#
# Exit: 0 ok | 1 violation | 2 usage | 3 environment (not a git repo, bad ref)
set -u
. "$(dirname "$0")/lib.sh"

DEFAULT_REGEX='(^|/)(test|tests|__tests__|spec|specs|e2e|__mocks__|fixtures|testdata)(/|$)|(\.test\.|\.spec\.|_test\.|_spec\.)|(^|/)test_[^/]*$|(^|/)conftest\.py$|\.feature$|Tests?\.(java|kt|cs|swift)$'

test_regex() { pb_conf_get test_path_regex "$DEFAULT_REGEX"; }

classify() {
  if printf '%s\n' "$1" | grep -Eq -- "$(test_regex)"; then echo test; else echo code; fi
}

cmd="${1:-}"
[ $# -gt 0 ] && shift

case "$cmd" in
  classify)
    [ $# -eq 1 ] || pb_die "usage: role-gate.sh classify <path>" 2
    classify "$1"
    ;;
  check)
    role="${1:-}"
    [ $# -gt 0 ] && shift
    case "$role" in tester|implementer|reviewer) ;; *) pb_die "role must be tester|implementer|reviewer" 2 ;; esac
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
        tester)      [ "$kind" = "code" ] && bad=1 ;;
        implementer) [ "$kind" = "test" ] && bad=1 ;;
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
  *)
    pb_die "usage: role-gate.sh check <role> [--base REF] | classify <path>" 2
    ;;
esac
