#!/usr/bin/env bash
# Print the model to use for a TDD role.
#   role-model.sh ROLE [--harness H] [--effort]  ROLE = tester|implementer|reviewer|reviewer_light|mechanical
#                                        --effort prints the reasoning effort instead (empty when unset)
#   role-model.sh list [--harness H]     one line per role: tester=<m>, implementer=<m>, reviewer=<m>,
#                                        reviewer_light=<m>, mechanical=<m>; "<m> (<effort>)" when an effort is set
#   role-model.sh plan [--harness H]     one line: Models: tester=<m>, implementer=<m>, reviewer=<m> - from conf
#                                        (or "- session (no conf)" when no role has a key in a conf; an explicit session counts as from conf)
#   role-model.sh check [--harness H]    warn about generic model_<role> keys (they apply to every
#                                        harness) and unknown model_* keys; exit 1 if any, 0 if none
# Lookup (project conf before global, per pb_conf_get): model_<role>_<harness>,
# then model_<role>, else "session" (= do not override the session model).
# reviewer_light falls back to the reviewer's model before "session"; mechanical never falls back
# to another role (a diff of tests/docs/skill text uses reviewer_light, release prep and counts use mechanical).
# Effort lookup: model_<role>_reasoning_effort_<harness>, then model_<role>_reasoning_effort; reviewer_light
# falls back to the reviewer's effort, mechanical has no fallback.
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

effort_for() { # role harness
  local v=""
  if [ -n "$2" ]; then v="$(pb_conf_get "model_$1_reasoning_effort_$2")" || v=""; fi
  [ -n "$v" ] || { v="$(pb_conf_get "model_$1_reasoning_effort")" || v=""; }
  if [ -z "$v" ] && [ "$1" = reviewer_light ]; then v="$(effort_for reviewer "$2")"; fi
  printf '%s' "$v"
}

# role_line ROLE HARNESS -> "<model>" or "<model> (<effort>)"
role_line() {
  local m e
  m="$(model_for "$1" "$2")"; e="$(effort_for "$1" "$2")"
  if [ -n "$e" ]; then printf '%s (%s)' "$m" "$e"; else printf '%s' "$m"; fi
}

# known_model_key KEY: model_<role>[_<harness>] or model_<role>_reasoning_effort[_<harness>]
known_model_key() {
  local k="$1" r h
  for r in reviewer_light tester implementer reviewer mechanical; do
    case "$k" in
      "model_$r" | "model_${r}_reasoning_effort") return 0 ;;
      "model_${r}_reasoning_effort_"*) h="${k#"model_${r}_reasoning_effort_"}"; valid_harness "$h" && return 0 ;;
    esac
    case "$k" in
      "model_${r}_"*) h="${k#"model_${r}_"}"; valid_harness "$h" && return 0 ;;
    esac
  done
  return 1
}

cmd="${1:-}"
[ $# -gt 0 ] && shift
case "$cmd" in
  tester | implementer | reviewer | reviewer_light | mechanical | list | plan | check) ;;
  *) pb_die "usage: role-model.sh tester|implementer|reviewer|reviewer_light|mechanical [--effort] | list | plan | check [--harness H]" 2 ;;
esac

harness="${PLAYBOOK_HARNESS:-}"
want_effort=0
while [ $# -gt 0 ]; do
  case "$1" in
    --harness)
      [ $# -ge 2 ] || pb_die "--harness needs a value" 2
      valid_harness "$2" || pb_die "invalid harness: $2 (use [a-z0-9-]+)" 2
      harness="$2"; shift ;;
    --effort)
      case "$cmd" in list | plan | check) pb_die "--effort applies to a single role" 2 ;; esac
      want_effort=1 ;;
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
  for origin in global project; do
    if [ "$origin" = global ]; then f="$g"; else f="$p"; [ "$p" = "$g" ] && continue; fi
    [ -f "$f" ] || continue
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in model_*=*) ;; *) continue ;; esac
      key="${line%%=*}"
      known_model_key "$key" && continue
      found=1
      printf 'warning: unknown key %s (%s) is not read by role-model.sh\n' "$key" "$origin"
    done < "$f"
  done
  [ "$found" = 1 ] && exit 1
  echo "ok: no generic model keys"
  exit 0
fi

if [ "$cmd" = "list" ]; then
  for r in tester implementer reviewer reviewer_light mechanical; do
    printf '%s=%s\n' "$r" "$(role_line "$r" "$harness")"
  done
elif [ "$cmd" = "plan" ]; then
  out="Models:"; src="session (no conf)"; sep=" "
  for r in tester implementer reviewer; do
    # a key present in any conf counts as from conf, also when its value is session
    if [ -n "$harness" ] && pb_conf_get "model_${r}_${harness}" >/dev/null; then src="from conf"
    elif pb_conf_get "model_$r" >/dev/null; then src="from conf"; fi
    out="$out$sep$r=$(role_line "$r" "$harness")"; sep=", "
  done
  printf '%s - %s\n' "$out" "$src"
elif [ "$want_effort" = 1 ]; then
  printf '%s\n' "$(effort_for "$cmd" "$harness")"
else
  printf '%s\n' "$(model_for "$cmd" "$harness")"
fi
