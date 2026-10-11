#!/usr/bin/env bash
# Which behaviour evals should run after a wording change? Prints them, never runs them.
#   tools/eval-guard.sh --base REF [--max-cost USD] [--harness H]
# Lists the files changed since REF (git diff REF...HEAD) that evals/scenario-map covers, and prints the
# capped command that would check them:
#   bash evals/run-evals.sh --harness H --scenarios E1,E3 --max-cost USD
# H (opencode, claude or codex; anything else exits 2) defaults to $PLAYBOOK_HARNESS, else claude; USD defaults to 3. Scenarios are listed once each, in map order.
# Nothing mapped changed: prints "no skill text changed". It never calls run-evals.sh or a harness:
# running evals spends money, so the user or the agent runs the printed command on purpose.
# evals/scenario-map: one line per rule, "<path glob> <scenario> [<scenario>...]" ('#' starts a comment line).
# Exit: 0 ok | 2 usage or unknown REF | 3 environment (no repository or map)
set -u

usage() { echo "usage: tools/eval-guard.sh --base REF [--max-cost USD] [--harness H]" >&2; exit 2; }

base=""; cost="3"; harness="${PLAYBOOK_HARNESS:-claude}"
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage
  case "$1" in
    --base) base="$2" ;;
    --max-cost) cost="$2" ;;
    --harness) harness="$2" ;;
    *) usage ;;
  esac
  shift 2
done
[ -n "$base" ] || usage
case "$cost" in "" | *[!0-9.]* | .* | *. | *.*.*) usage ;; esac
case "$harness" in opencode | claude | codex) ;; *) echo "error: the harness must be opencode, claude or codex" >&2; exit 2 ;; esac

root="$(cd "$(dirname "$0")/.." && pwd)" || exit 3
map="$root/evals/scenario-map"
[ -f "$map" ] || { echo "error: $map not found" >&2; exit 3; }
git -C "$root" rev-parse --verify -q "$base^{commit}" >/dev/null 2>&1 || { echo "error: unknown base: $base" >&2; exit 2; }
changed="$(git -C "$root" -c core.quotepath=off diff --name-only "$base...HEAD")" || { echo "error: git diff failed for $base...HEAD" >&2; exit 2; }

files=""; scenarios=""
set -f   # the globs in the map must not expand here
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in "" | "#"*) continue ;; esac
  # shellcheck disable=SC2086  # split the line into the glob and the scenarios on purpose
  set -- $line
  [ $# -ge 2 ] || continue
  glob="$1"; shift
  hit=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    # shellcheck disable=SC2254  # the map entry is a glob on purpose
    case "$f" in
      $glob)
        hit=1
        case "
$files
" in *"
$f
"*) ;; *) files="$files$f
" ;; esac
        ;;
    esac
  done <<EOF
$changed
EOF
  if [ "$hit" = 1 ]; then
    for sc in "$@"; do
      case " $scenarios " in *" $sc "*) ;; *) scenarios="$scenarios $sc" ;; esac
    done
  fi
done < "$map"
set +f

if [ -z "$scenarios" ]; then
  echo "no skill text changed since $base"
  exit 0
fi
echo "changed files covered by evals/scenario-map:"
printf '%s' "$files" | while IFS= read -r f; do printf '  %s\n' "$f"; done
list="$(printf '%s' "$scenarios" | sed 's/^ //; s/ /,/g')"
echo "check the wording change against the behaviour evals (capped, on purpose; this tool never runs them):"
echo "bash evals/run-evals.sh --harness $harness --scenarios $list --max-cost $cost"
exit 0
