#!/usr/bin/env bash
# One RED or GREEN step of the TDD workflow: role gate, then the test command as evidence.
#   tdd-step.sh red   --message M [--base REF] [--baseline FILE] [--commit] -- CMD [ARGS...]
#   tdd-step.sh green --base REF --message M [--baseline FILE] [--commit] -- CMD [ARGS...]
# red:   role-gate.sh check tester [--base REF], then proof-run.sh --label red -- CMD. Passes only if the
#        gate passes AND CMD fails (a test that does not fail is not RED). --commit commits all changes
#        as "test(red): M" and prints RED=<sha>. Pass --base <sha recorded before the tester started>
#        so a tester that commits is judged; without it the step prints a note (stderr) and the gate
#        compares with HEAD.
# green: role-gate.sh check implementer --base REF, then proof-run.sh --label green -- CMD. Passes
#        only if the gate passes AND CMD exits 0. --commit commits all changes as "feat(green): M".
# --baseline FILE (red and green): passed to the gate (a manifest from role-gate.sh snapshot, for a repo
#        that was already dirty when the role started). Then --commit commits ONLY the role's paths:
#        git status (-z, all untracked files, both sides of a rename) minus the paths the gate reported
#        as unchanged since the baseline minus .agents/handoff/; a path with a control character other
#        than TAB is refused (commit by hand); an empty list commits nothing; the work tree is
#        snapshotted before and after CMD and the gate runs again after it: a changed manifest, a moved
#        HEAD or other unchanged-notes refuse the commit. Role paths are committed with literal
#        pathspecs (GIT_LITERAL_PATHSPECS=1) and the baseline paths keep their index and work-tree
#        state. Without --commit the exact commands are printed, every path shell-quoted.
# --commit adds .agents/handoff/ to .git/info/exclude when not ignored (prints a notice).
# Without --commit nothing is committed; the commit command is printed instead (ask-before-commit).
# Runs in the current project (git top-level). Gate and evidence output pass through.
# Exit codes: 0 pass, 1 gate or expectation failed (nothing committed), 2 usage,
#             3 environment (not a git work tree, cannot commit).
set -u
. "$(dirname "$0")/lib.sh"
here="$(cd "$(dirname "$0")" && pwd)"

usage() {
  echo "usage: tdd-step.sh red [--base REF] [--baseline FILE] --message M [--commit] -- CMD..." >&2
  echo "       tdd-step.sh green --base REF [--baseline FILE] --message M [--commit] -- CMD..." >&2
  exit 2
}

step="${1:-}"
case "$step" in red|green) shift ;; *) usage ;; esac

msg=""; base=""; baseline=""; commit=0
while [ $# -gt 0 ]; do
  case "$1" in
    --message)  [ $# -ge 2 ] || usage; msg="$2"; shift 2 ;;
    --base)     [ $# -ge 2 ] || usage; base="$2"; shift 2 ;;
    --baseline) [ $# -ge 2 ] && [ -n "$2" ] || usage; baseline="$2"; shift 2 ;;
    --commit)   commit=1; shift ;;
    --) shift; break ;;
    *) usage ;;
  esac
done
[ -n "$msg" ] || usage
[ $# -ge 1 ] || usage
if [ "$step" = "green" ]; then [ -n "$base" ] || usage; fi
# a relative manifest path is the caller's, not the project root's
if [ -n "$baseline" ]; then
  case "$baseline" in /* | [A-Za-z]:[/\\]*) ;; *) baseline="$PWD/$baseline" ;; esac
fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || pb_die "not inside a git work tree" 3
cd "$(pb_root_dir)" || pb_die "cannot enter the project root" 3

NL=$'\n'
NOTEP="note: unchanged since the baseline: "
gate_args=()
if [ "$step" = "red" ]; then
  role=tester
  if [ -n "$base" ]; then
    gate_args=(--base "$base")
  else
    echo "note: no --base: a tester that commits is not judged; pass the sha from before the role" >&2
  fi
  subject="test(red): $msg"
else
  role=implementer
  gate_args=(--base "$base")
  subject="feat($step): $msg"
fi
if [ -n "$baseline" ]; then gate_args+=(--baseline "$baseline"); fi

run_gate() { bash "$here/role-gate.sh" check "$role" ${gate_args[@]+"${gate_args[@]}"}; }
refuse() { echo "error: $1 - nothing committed" >&2; exit 1; }
# the "unchanged since the baseline" note lines of a gate output
notes_of() { printf '%s\n' "$1" | grep -F "$NOTEP" || true; }

# Before tdd-step stages anything: remember HEAD and the index file (a copy outside the work tree).
save_state() {
  pre_head="$(git rev-parse HEAD)" || pb_die "cannot read HEAD" 3
  idx="$(git rev-parse --git-path index)" || pb_die "cannot find the index" 3
  idx_had=0
  if [ -f "$idx" ]; then cp -p "$idx" "$tmpd/index.save" || pb_die "cannot save the index" 3; idx_had=1; fi
}

# After git commit. Args: the judged paths. The commit must sit directly on the pre-run HEAD and hold
# exactly the judged paths (a git hook may add a path or commit on top). Otherwise: HEAD back to the
# pre-run HEAD, the saved index file restored byte for byte, the reason and the extra paths named, exit 1.
check_commit() {
  local -a extra=(); local g e hit why=""
  while IFS= read -r -d '' g; do
    hit=0
    for e in "$@"; do if [ "$e" = "$g" ]; then hit=1; break; fi; done
    [ "$hit" -eq 1 ] || extra+=("$g")
  done < <(git diff-tree --root --no-commit-id --name-only -r -z --no-renames HEAD)
  if [ "$(git rev-parse -q --verify 'HEAD^' 2>/dev/null)" != "$pre_head" ]; then
    why="HEAD is not a single commit on the pre-run HEAD (a git hook committed on top)"
  fi
  if [ ${#extra[@]} -gt 0 ]; then
    why="${why:+$why; }the commit held paths that were not judged (a git hook added them)"
  fi
  [ -n "$why" ] || return 0
  git reset -q --soft "$pre_head" || pb_die "cannot undo the commit" 3
  if [ "$idx_had" -eq 1 ]; then
    cp -p "$tmpd/index.save" "$idx" || pb_die "cannot restore the index" 3
  else
    rm -f "$idx"
  fi
  echo "error: $why; the commit is undone, HEAD and the index are restored, the work tree is kept - nothing committed:" >&2
  for g in ${extra[@]+"${extra[@]}"}; do printf '  %s\n' "$g" >&2; done
  exit 1
}

tmpd="$(mktemp -d "${TMPDIR:-/tmp}/tdd-step.XXXXXX")" || pb_die "cannot create a temp dir" 3
trap 'rm -rf "$tmpd"' EXIT
if [ -z "$baseline" ]; then
  run_gate || exit 1
else
  gout="$(run_gate)"; grc=$?
  [ -z "$gout" ] || printf '%s\n' "$gout"
  [ "$grc" -eq 0 ] || exit 1
  notes1="$(notes_of "$gout")"
  if [ "$commit" -eq 1 ]; then
    # a newline in a path makes the snapshot die (exit 3): refuse it like the other control characters
    git -c core.quotepath=off status --porcelain=v1 -z --untracked-files=all > "$tmpd/status0" || pb_die "git status failed" 3
    if [ "$(LC_ALL=C tr '\0' 'x' < "$tmpd/status0" | wc -l)" -gt 0 ]; then
      echo "error: a changed path contains a newline: commit the role's paths by hand - nothing committed" >&2
      exit 1
    fi
    bash "$here/role-gate.sh" snapshot --out "$tmpd/before" >/dev/null || pb_die "cannot snapshot the work tree" 3
    head_before="$(git rev-parse HEAD)" || pb_die "cannot read HEAD" 3
  fi
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

# --baseline: the role's paths, from git status after the test command
paths=(); untr=()
if [ -n "$baseline" ]; then
  notes="$notes1"
  if [ "$commit" -eq 1 ]; then
    bash "$here/role-gate.sh" snapshot --out "$tmpd/after" >/dev/null || refuse "cannot snapshot the work tree after the test command"
    cmp -s "$tmpd/before" "$tmpd/after" || refuse "the test command changed the work tree (a file was written, edited or committed)"
    [ "$(git rev-parse HEAD)" = "$head_before" ] || refuse "HEAD moved while the test command ran"
    gout2="$(run_gate)"; grc2=$?
    [ "$grc2" -eq 0 ] || { printf '%s\n' "$gout2"; refuse "the role gate fails after the test command"; }
    notes="$(notes_of "$gout2")"
    [ "$notes" = "$notes1" ] || refuse "the paths unchanged since the baseline differ after the test command"
  fi
  exempt="$NL"
  while IFS= read -r nl; do
    [ -n "$nl" ] || continue
    exempt+="${nl#"$NOTEP"}$NL"
  done <<EOF
$notes
EOF
  git -c core.quotepath=off status --porcelain=v1 -z --untracked-files=all > "$tmpd/status" || pb_die "git status failed" 3
  nxt=0; ctl=0
  while IFS= read -r -d '' ent; do
    if [ "$nxt" -eq 1 ]; then p="$ent"; nxt=0; xy="  "; else
      xy="${ent:0:2}"; p="${ent:3}"
      case "$xy" in R? | C? | ?R | ?C) nxt=1 ;; esac
    fi
    case "$p" in .agents/handoff/*) continue ;; esac
    case "${p//$'\t'/}" in *[[:cntrl:]]*) ctl=1 ;; esac
    case "$exempt" in *"$NL$p$NL"*) continue ;; esac
    paths+=("$p")
    [ "$xy" != "??" ] || untr+=("$p")
  done < "$tmpd/status"
  if [ "$ctl" -eq 1 ]; then
    echo "error: a changed path contains a control character: commit the role's paths by hand - nothing committed" >&2
    exit 1
  fi
  if [ ${#paths[@]} -eq 0 ]; then
    echo "error: nothing of the role's to commit (every change is a baseline path or under .agents/handoff/)" >&2
    exit 1
  fi
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
  save_state
  if [ -n "$baseline" ]; then
    if [ ${#untr[@]} -gt 0 ]; then
      GIT_LITERAL_PATHSPECS=1 git add -- "${untr[@]}" || pb_die "git add failed" 3
    fi
    GIT_LITERAL_PATHSPECS=1 git commit -q -m "$subject" -- "${paths[@]}" || pb_die "git commit failed" 3
    check_commit "${paths[@]}"
  else
    git add -A || pb_die "git add failed" 3
    git reset -q -- .agents/handoff 2>/dev/null || true
    judged=()
    while IFS= read -r -d '' g; do judged+=("$g"); done < <(git diff --cached --name-only --no-renames -z)
    git commit -q -m "$subject" || pb_die "git commit failed" 3
    check_commit ${judged[@]+"${judged[@]}"}
  fi
  if [ "$step" = "red" ]; then echo "RED=$(git rev-parse HEAD)"; else echo "committed: $(git rev-parse HEAD)"; fi
elif [ -n "$baseline" ]; then
  echo "not committing (no --commit). To commit only the role's paths:"
  if [ ${#untr[@]} -gt 0 ]; then
    printf 'GIT_LITERAL_PATHSPECS=1 git add --'
    for p in "${untr[@]}"; do printf ' %q' "$p"; done
    printf '\n'
  fi
  printf 'GIT_LITERAL_PATHSPECS=1 git commit -m %q --' "$subject"
  for p in "${paths[@]}"; do printf ' %q' "$p"; done
  printf '\n'
else
  echo "not committing (no --commit). To commit: git add -A && git commit -m \"$subject\""
fi
exit 0
