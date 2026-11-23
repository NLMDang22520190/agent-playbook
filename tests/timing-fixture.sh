#!/usr/bin/env bash
# Helper for wall-clock threshold checks in suites (not a suite: run-all only starts tests/test-*.sh). Bash 3.2 compatible.
# Source it after lib.sh. A single slow run on a loaded CI runner (Windows) must not fail a "took N ms (< MAX)" check, so the
# timed command is re-run and the best (minimum) time is compared with the limit.
#
#   best_of_ms N MAXMS CMD...
#     Runs CMD (in the current shell, so its globals such as RC and OUT survive) up to N times (empty or invalid N means 3),
#     times each run with tf_now_ms, stops at the first run under MAXMS (no wasted re-runs). Sets TF_BEST_MS (minimum ms),
#     TF_ATTEMPTS (runs made) and TF_CMD_RC (0, or the exit status of the first CMD run that failed), and prints one line
#     "best_ms=.. attempts=.. max_ms=.. cmd_rc=..". A failing CMD is never retried and never masked: it stops the loop and
#     the return status is 3 (TF_CMD_RC holds the command's own status). Otherwise returns 0 when TF_BEST_MS < MAXMS, else 1.
#   tf_now_ms: milliseconds clock; a suite or test may redefine it after sourcing this file (deterministic fake clock).
if ! type tf_now_ms >/dev/null 2>&1; then
  tf_now_ms() { if type now_ms >/dev/null 2>&1; then now_ms; else echo $(( $(date +%s%N) / 1000000 )); fi; }
fi

best_of_ms() {
  local n="${1:-3}" max="$2" t0 t1 d
  shift 2
  case "$n" in '' | *[!0-9]* | 0) n=3 ;; esac
  TF_BEST_MS=""; TF_ATTEMPTS=0; TF_CMD_RC=0
  while [ "$TF_ATTEMPTS" -lt "$n" ]; do
    t0="$(tf_now_ms)"
    "$@"; TF_CMD_RC=$?
    t1="$(tf_now_ms)"
    TF_ATTEMPTS=$((TF_ATTEMPTS + 1))
    d=$((t1 - t0))
    if [ -z "$TF_BEST_MS" ] || [ "$d" -lt "$TF_BEST_MS" ]; then TF_BEST_MS="$d"; fi
    [ "$TF_CMD_RC" -ne 0 ] && break
    [ "$d" -lt "$max" ] && break
  done
  printf 'best_ms=%s attempts=%s max_ms=%s cmd_rc=%s\n' "$TF_BEST_MS" "$TF_ATTEMPTS" "$max" "$TF_CMD_RC"
  [ "$TF_CMD_RC" -ne 0 ] && return 3
  [ "$TF_BEST_MS" -lt "$max" ]
}
