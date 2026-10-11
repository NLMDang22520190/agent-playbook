#!/usr/bin/env bash
# Print the model to use for a TDD role.
#   role-model.sh ROLE [--harness H]     ROLE = tester|implementer|reviewer|reviewer_light|mechanical
#   role-model.sh list [--harness H]     one line per role: tester=<m>, implementer=<m>, reviewer=<m>,
#                                        reviewer_light=<m>, mechanical=<m>
#   role-model.sh check [--harness H]    warn about generic model_<role> keys (they apply to every
#                                        harness); exit 1 if any, 0 if none
# Lookup (project conf before global, per pb_conf_get): model_<role>_<harness>,
# then model_<role>, else "session" (= do not override the session model).
# reviewer_light falls back to the reviewer's model before "session"; mechanical never falls back
# to another role (a diff of tests/docs/skill text uses reviewer_light, release prep and counts use mechanical).
# Harness: --harness H, else env PLAYBOOK_HARNESS, else none. H matches [a-z0-9-]+.
# Exit: 0 ok, 1 generic keys found (check), 2 usage error.
set -u
. "$(dirname "$0")/lib.sh"

valid_harness() { case "$1" in "" | *[!abcdefghijklmnopqrstuvwxyz0123456789-]*) return 1 ;; esac; return 0; }

model_for() { # role harness
  local v=""
  if [ -n "$2" ]; then v="$(pb_conf_get "model_$1_$2")" || v=""; fi
  if [ -z "$v" ]; then
    if [ "$1" = reviewer_light ]; then
      v="$(pb_conf_get "model_reviewer_light")" || v=""
      [ -n "$v" ] || v="$(model_for reviewer "$2")"
    else
      v="$(pb_conf_get "model_$1" session)"
    fi
  fi
  printf '%s' "$v"
}

cmd="${1:-}"
[ $# -gt 0 ] && shift
case "$cmd" in
  tester | implementer | reviewer | reviewer_light | mechanical | list | check) ;;
  *) pb_die "usage: role-model.sh tester|implementer|reviewer|reviewer_light|mechanical|list|check [--harness H]" 2 ;;
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

if [ "$cmd" = "check" ]; then
  found=0
  g="$(pb_conf_global)"; p="$(pb_conf_project)"
  for origin in global project; do
    if [ "$origin" = global ]; then f="$g"; else f="$p"; [ "$p" = "$g" ] && continue; fi
    [ -f "$f" ] || continue
    for r in tester implementer reviewer reviewer_light mechanical; do
      v="$(pb_conf_read "$f" "model_$r")" || continue   # an empty value counts: it overrides "session" too
      found=1
      printf 'warning: model_%s=%s (%s) applies to every harness; use model_%s_%s instead\n' \
        "$r" "$v" "$origin" "$r" "${harness:-<harness>}"
    done
  done
  [ "$found" = 1 ] && exit 1
  echo "ok: no generic model keys"
  exit 0
fi

if [ "$cmd" = "list" ]; then
  for r in tester implementer reviewer reviewer_light mechanical; do
    printf '%s=%s\n' "$r" "$(model_for "$r" "$harness")"
  done
else
  printf '%s\n' "$(model_for "$cmd" "$harness")"
fi
