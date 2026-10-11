#!/usr/bin/env bash
# Runs every tests/test-*.sh plus the static skill checks. Exit 1 if anything fails.
# Suites run in parallel, at most PB_JOBS at a time (default 4; PB_JOBS=1 runs them one by one): a
# job pool, so the next suite starts as soon as any running one finishes. Each suite writes its own
# log, and the logs are printed in a fixed order. Process start-up is slow on Windows (Git Bash), so
# parallel runs cut the wall-clock time there the most. Bash 3.2 has no `wait -n`: the pool polls
# the running pids every 0.1 s (one `sleep` per poll, the check itself is builtin).
# PB_SHARD=k/n runs only the suites at sorted positions i with (i-1) % n == k-1 (evals/run-checks.sh only
# in shard 1), so CI can split the slow Windows run over several machines. Unset: everything.
# PB_RERUN (default 1; 0 turns it off, any other value means 1): after FAILURES (and the hint) each of the first 3
# failing suites (non-zero or missing .rc; never evals/run-checks.sh) is re-run alone with its output discarded and
# classified: "rerun: test-x.sh passed alone (flaky or load)" or "... failed again (real)"; when the hint fired
# (environment problem) nothing is re-run. The exit code always reflects the first run.
# With tests/shard-weights ("test-x.sh SECONDS" lines, # comments; unknown suites weigh 10) the suites are
# assigned greedily instead: heaviest first (ties by name), each to the lightest shard so far (ties: lowest).
cd "$(dirname "$0")/.." || exit 3
SHARD="${PB_SHARD:-}"; SK=1; SN=1
if [ -n "$SHARD" ]; then
  bad_shard() { echo "PB_SHARD must be k/n with 1 <= k <= n, got: $SHARD" >&2; exit 2; }
  case "$SHARD" in */*/* | /* | */) bad_shard ;; */*) ;; *) bad_shard ;; esac
  SK="${SHARD%/*}"; SN="${SHARD#*/}"
  case "$SK" in '' | *[!0123456789]*) bad_shard ;; esac
  case "$SN" in '' | *[!0123456789]*) bad_shard ;; esac
  case "$SK$SN" in 0* ) bad_shard ;; esac
  case "$SN" in 0*) bad_shard ;; esac   # leading zeros would be read as octal by $(( ))
  [ "$SK" -ge 1 ] && [ "$SN" -ge 1 ] && [ "$SK" -le "$SN" ] || bad_shard
fi
RERUN="${PB_RERUN:-1}"
case "$RERUN" in 0) ;; *) RERUN=1 ;; esac
unset PB_SHARD   # suites (and run-all copies they start) always see a full run
JOBS="${PB_JOBS:-4}"
case "$JOBS" in '' | *[!0123456789]* | 0) JOBS=1 ;; esac
base="${TMPDIR:-/tmp}"; base="${base%/}"
OUTD="$(mktemp -d "$base/pbrunall.XXXXXX")" || exit 3
trap 'rm -rf "$OUTD"' EXIT

# live_jobs: keep only the pids still running (kill -0 is a builtin). A wrapper that dies without
# writing its .rc is no longer running, so the pool moves on and the missing .rc fails the run.
PIDS=""
live_jobs() { LIVE=0; local p keep=""; for p in $PIDS; do kill -0 "$p" 2>/dev/null && { LIVE=$((LIVE + 1)); keep="$keep $p"; }; done; PIDS="$keep"; }
set -- tests/test-*.sh
if [ -n "$SHARD" ] && [ -f tests/shard-weights ]; then
  tab="$(printf '\t')"
  sel="$(for t in "$@"; do printf '%s\n' "$t"; done |
    awk 'FILENAME != "-" { if ($0 ~ /^[ \t]*(#|$)/) next; w[$1] = $2; next }
         { b = $0; sub(/^.*\//, "", b); printf "%s\t%s\t%s\n", ((b in w) ? w[b] + 0 : 10), b, $0 }' tests/shard-weights - |
    LC_ALL=C sort -t "$tab" -k1,1nr -k2,2 |
    awk -F '\t' -v k="$SK" -v n="$SN" '{ m = 1; for (i = 2; i <= n; i++) if (tot[i] < tot[m]) m = i; tot[m] += $1; if (m == k) print $3 }' |
    LC_ALL=C sort)"
  set -- $sel   # tests/test-*.sh paths have no spaces
elif [ -n "$SHARD" ]; then
  i=0; sel=""
  for t in "$@"; do i=$((i + 1)); [ $(( (i - 1) % SN )) -eq $((SK - 1)) ] && sel="$sel $t"; done
  set -- $sel   # tests/test-*.sh paths have no spaces
fi
for t in "$@"; do
  live_jobs
  while [ "$LIVE" -ge "$JOBS" ]; do sleep 0.1; live_jobs; done
  n="$(basename "$t" .sh)"
  ( s=$(date +%s); bash "$t" > "$OUTD/$n.out" 2>&1; r=$?; echo $(( $(date +%s) - s )) > "$OUTD/$n.time"
    echo "$r" > "$OUTD/$n.tmp"; mv "$OUTD/$n.tmp" "$OUTD/$n.rc" ) &
  PIDS="$PIDS $!"
done
wait

fail=0
for t in "$@"; do
  n="$(basename "$t" .sh)"
  echo "== $t ($(cat "$OUTD/$n.time" 2>/dev/null || echo 0) s)"
  cat "$OUTD/$n.out"
  [ "$(cat "$OUTD/$n.rc" 2>/dev/null)" = "0" ] || fail=1
done
if [ "$SK" -eq 1 ]; then
  echo "== evals/run-checks.sh (static skill checks)"
  bash evals/run-checks.sh || fail=1
fi
if [ "$fail" -eq 0 ]; then echo "ALL GREEN"; else echo "FAILURES"
  # most failing assertions got nothing at all: the machine, not the code, is the likely cause
  nf="$(cat "$OUTD"/*.out 2>/dev/null | grep -c '^  FAIL ')"
  ne="$(cat "$OUTD"/*.out 2>/dev/null | grep -c ' got \[\]$')"
  if [ "$ne" -ge 20 ] && [ $((ne * 2)) -ge "$nf" ]; then
    echo "hint: $ne of $nf failing assertions got empty output, likely an environment problem (machine restart, missing node, full disk); re-run one suite alone to confirm"
    HINTED=1
  fi
  if [ "$RERUN" = 1 ]; then
    if [ "${HINTED:-0}" = 1 ]; then
      echo "rerun: skipped, environment problem (see hint)"
    else
      # the first 3 failing suites in run order are re-run alone, output discarded (evals/run-checks.sh is not a suite here)
      done_n=0; skipped=0
      for t in "$@"; do
        n="$(basename "$t" .sh)"
        [ "$(cat "$OUTD/$n.rc" 2>/dev/null)" = "0" ] && continue
        if [ "$done_n" -ge 3 ]; then skipped=$((skipped + 1)); continue; fi
        done_n=$((done_n + 1))
        # a subshell wrapper, as in the first run: a suite that kills its parent (see tests) must not kill run-all
        if ( bash "$t" > /dev/null 2>&1; r=$?; exit "$r" ); then
          echo "rerun: $n.sh passed alone (flaky or load)"
        else
          echo "rerun: $n.sh failed again (real)"
        fi
      done
      [ "$skipped" -eq 0 ] || echo "rerun: skipped for $skipped more suite(s)"
    fi
  fi
fi
exit "$fail"
