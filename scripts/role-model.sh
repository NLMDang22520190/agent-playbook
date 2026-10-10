#!/usr/bin/env bash
# Print the model to use for a TDD role.
#   role-model.sh ROLE [--harness H]     ROLE = tester|implementer|reviewer
#   role-model.sh list [--harness H]     tester=<m>, implementer=<m>, reviewer=<m>
# Lookup (project conf before global, per pb_conf_get): model_<role>_<harness>,
# then model_<role>, else "session" (= do not override the session model).
# Harness: --harness H, else env PLAYBOOK_HARNESS, else none. H matches [a-z0-9-]+.
# Exit: 0 ok, 2 usage error.
set -u
. "$(dirname "$0")/lib.sh"

valid_harness() { case "$1" in "" | *[!abcdefghijklmnopqrstuvwxyz0123456789-]*) return 1 ;; esac; return 0; }

model_for() { # role harness
  local v=""
  if [ -n "$2" ]; then v="$(pb_conf_get "model_$1_$2")" || v=""; fi
  [ -n "$v" ] || v="$(pb_conf_get "model_$1" session)"
  printf '%s' "$v"
}

cmd="${1:-}"
[ $# -gt 0 ] && shift
case "$cmd" in
  tester | implementer | reviewer | list) ;;
  *) pb_die "usage: role-model.sh tester|implementer|reviewer|list [--harness H]" 2 ;;
esac

harness="${PLAYBOOK_HARNESS:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --harness)
      [ $# -ge 2 ] || pb_die "--harness needs a value" 2
      valid_harness "$2" || pb_die "invalid harness: $2 (use [a-z0-9-]+)" 2
      harness="$2"; shift ;;
    *) pb_die "unknown option: $1" 2 ;;
  esac
  shift
done
if [ -n "$harness" ]; then
  valid_harness "$harness" || pb_die "invalid harness: $harness (use [a-z0-9-]+)" 2
fi

if [ "$cmd" = "list" ]; then
  for r in tester implementer reviewer; do
    printf '%s=%s\n' "$r" "$(model_for "$r" "$harness")"
  done
else
  printf '%s\n' "$(model_for "$cmd" "$harness")"
fi
