#!/usr/bin/env bash
# One RED or GREEN step of the TDD workflow: role gate, then the test command as evidence.
#   tdd-step.sh red   --message M [--commit] -- CMD [ARGS...]
#   tdd-step.sh green --base REF --message M [--commit] -- CMD [ARGS...]
# red:   role-gate.sh check tester, then proof-run.sh --label red -- CMD. Passes only if the gate
#        passes AND CMD fails (a test that does not fail is not RED). --commit commits all changes
#        as "test(red): M" and prints RED=<sha>.
# green: role-gate.sh check implementer --base REF, then proof-run.sh --label green -- CMD. Passes
#        only if the gate passes AND CMD exits 0. --commit commits all changes as "feat(green): M".
# --commit adds .agents/handoff/ to .git/info/exclude when not ignored (prints a notice).
# Without --commit nothing is committed; the commit command is printed instead (ask-before-commit).
# Runs in the current project (git top-level). Gate and evidence output pass through.
# Exit codes: 0 pass, 1 gate or expectation failed (nothing committed), 2 usage,
#             3 environment (not a git work tree, cannot commit).
set -u
. "$(dirname "$0")/lib.sh"
here="$(cd "$(dirname "$0")" && pwd)"

usage() {
  echo "usage: tdd-step.sh red --message M [--commit] -- CMD..." >&2
  echo "       tdd-step.sh green --base REF --message M [--commit] -- CMD..." >&2
  exit 2
}

step="${1:-}"
case "$step" in red|green) shift ;; *) usage ;; esac

msg=""; base=""; commit=0
while [ $# -gt 0 ]; do
  case "$1" in
    --message) [ $# -ge 2 ] || usage; msg="$2"; shift 2 ;;
    --base)    [ $# -ge 2 ] || usage; base="$2"; shift 2 ;;
    --commit)  commit=1; shift ;;
    --) shift; break ;;
    *) usage ;;
  esac
done
[ -n "$msg" ] || usage
[ $# -ge 1 ] || usage
if [ "$step" = "green" ]; then [ -n "$base" ] || usage; fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || pb_die "not inside a git work tree" 3
cd "$(pb_root_dir)" || pb_die "cannot enter the project root" 3

if [ "$step" = "red" ]; then
  bash "$here/role-gate.sh" check tester || exit 1
  subject="test(red): $msg"
else
  bash "$here/role-gate.sh" check implementer --base "$base" || exit 1
  subject="feat($step): $msg"
fi

bash "$here/proof-run.sh" --label "$step" -- "$@"
rc=$?
if [ "$step" = "red" ]; then
  if [ "$rc" -eq 0 ]; then
    echo "error: the test command did not fail - this is not RED, nothing committed" >&2
    exit 1
  fi
elif [ "$rc" -ne 0 ]; then
  echo "error: the test command failed (exit $rc) - this is not GREEN, nothing committed" >&2
  exit 1
fi

if [ "$commit" -eq 1 ]; then
  # evidence logs live under .agents/handoff/: never commit them, and keep them
  # out of 'git status' via the local exclude file (not the project's .gitignore)
  if ! git check-ignore -q .agents/handoff/x 2>/dev/null; then
    excl="$(git rev-parse --git-path info/exclude 2>/dev/null)" || excl=""
    if [ -n "$excl" ]; then
      mkdir -p "$(dirname "$excl")" && printf '%s\n' '.agents/handoff/' >> "$excl" \
        && echo "notice: added .agents/handoff/ to $excl (local exclude, not .gitignore)"
    fi
  fi
  git add -A || pb_die "git add failed" 3
  git reset -q -- .agents/handoff 2>/dev/null || true
  git commit -q -m "$subject" || pb_die "git commit failed" 3
  if [ "$step" = "red" ]; then echo "RED=$(git rev-parse HEAD)"; else echo "committed: $(git rev-parse HEAD)"; fi
else
  echo "not committing (no --commit). To commit: git add -A && git commit -m \"$subject\""
fi
exit 0
