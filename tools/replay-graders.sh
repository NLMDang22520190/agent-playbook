#!/usr/bin/env bash
# Re-runs the auth classification of both runners on stored stream-json run logs, free (v0.38 G5; never calls a model).
#   tools/replay-graders.sh [--fail-on-auth] [--stray] LOG...
# One TSV line per log, in argument order: <log> TAB <evals verdict> TAB <outcome verdict> [TAB <stray|none>].
# A verdict is "auth" when the runner's auth_marker finds an auth failure in the log, else "ok". auth_lines and auth_marker are
# read from the CURRENT evals/run-evals.sh and evals/run-outcome.sh at run time (sed/awk extraction, no copied regexes), and
# result_ok comes from evals/transcript.js as each runner's load_transcript gets it, so a change to a runner shows here at once.
# A directory argument expands to its *.log files (not recursive). The logs are only read; nothing is written next to them.
#   --fail-on-auth   exit 1 when any log gets "auth" from either runner (the lines are still printed)
#   --stray          add a fourth column: "stray" when a Bash tool_use command of the log writes outside the work dir
#                    (a redirect, tee, cp or mv aimed at a ../ path), else "none". It is a lower bound: a write the
#                    command text does not show (a script, a variable, an absolute path) is not seen.
#   -h, --help       this text
# Exit: 0 ok | 1 --fail-on-auth and a log is "auth" | 2 usage, unreadable log, node missing or a runner function not found.
# Bash 3.2 compatible.
set -u

usage() { echo "usage: tools/replay-graders.sh [--fail-on-auth] [--stray] LOG..." >&2; exit 2; }
die() { echo "replay-graders: $1" >&2; exit 2; }

FAIL_AUTH=0 STRAY=0 logs=""
nl='
'
while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help) sed -n '2,/^set -u/p' "$0" | sed '/^set -u/d' | sed 's/^# \{0,1\}//'; echo "usage: tools/replay-graders.sh [--fail-on-auth] [--stray] LOG..."; exit 0 ;;
    --fail-on-auth) FAIL_AUTH=1 ;;
    --stray) STRAY=1 ;;
    --) shift; break ;;
    -*) echo "replay-graders: unknown option: $1" >&2; usage ;;
    *) break ;;
  esac
  shift
done
[ $# -ge 1 ] || usage

command -v node >/dev/null 2>&1 || die "node is needed (evals/transcript.js) and is not on PATH"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EVALS="$ROOT/evals"

for a in "$@"; do
  if [ -d "$a" ]; then
    for f in "$a"/*.log; do [ -f "$f" ] && logs="$logs$f$nl"; done
  elif [ -r "$a" ] && [ -f "$a" ]; then
    logs="$logs$a$nl"
  else
    die "cannot read: $a"
  fi
done
[ -n "$logs" ] || die "no log files given"

W="$(mktemp -d "${TMPDIR:-/tmp}/pbreplay.XXXXXX")" || die "cannot make a temp dir"
trap 'rm -rf "$W"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# extract RUNNER.sh -> prints result_ok (when defined), auth_lines and auth_marker as the runner has them now
extract() {
  awk '/^result_ok\(\)/ { print; next }
       /^auth_lines\(\)/ { print; next }
       /^auth_marker\(\)/ { on = 1 }
       on { print }
       on && /^}/ { on = 0 }' "$1"
}
extract "$EVALS/run-evals.sh" > "$W/evals.fn"
extract "$EVALS/run-outcome.sh" > "$W/outcome.fn"
for r in evals outcome; do
  grep -q '^auth_lines()' "$W/$r.fn" && grep -q '^auth_marker()' "$W/$r.fn" && grep -q '^}' "$W/$r.fn" ||
    die "auth_lines or auth_marker not found in the $r runner"
done

# verdict RUNNER LOG RESULT_OK -> auth | ok, the runner's own functions on LOG in a subshell
verdict() {
  ( LOG="$2"; T_result_ok="$3"
    # shellcheck disable=SC1090
    . "$W/$1.fn" || exit 2
    if auth_marker; then echo auth; else echo ok; fi )
}

# stray LOG -> stray | none: a Bash tool_use whose command writes to a ../ path
STRAYJS='
const fs = require("fs"); let hit = false;
for (const l of fs.readFileSync(process.argv[1], "utf8").split("\n")) {
  let o; try { o = JSON.parse(l); } catch (e) { continue; }
  const c = o && o.message && o.message.content; if (!Array.isArray(c)) continue;
  for (const b of c) {
    if (b && b.type === "tool_use" && b.name === "Bash" && b.input && typeof b.input.command === "string" &&
        /(>>?|\btee\b|\bcp\b|\bmv\b)[^|;&\n]*[\s>"\x27=]\.\.\//.test(b.input.command)) hit = true;
  }
}
console.log(hit ? "stray" : "none");'

anyauth=0
while IFS= read -r log; do
  [ -n "$log" ] || continue
  rok=0
  while IFS='=' read -r k v; do
    [ "$k" = result_ok ] && rok="$v"
  done <<EOF
$(node "$EVALS/transcript.js" "$log" 2>/dev/null)
EOF
  ve="$(verdict evals "$log" "$rok")" || die "the evals auth functions failed on $log"
  vo="$(verdict outcome "$log" "$rok")" || die "the outcome auth functions failed on $log"
  [ "$ve" = auth ] || [ "$vo" = auth ] && anyauth=1
  line="$log	$ve	$vo"
  if [ "$STRAY" = 1 ]; then
    st="$(node -e "$STRAYJS" "$log" 2>/dev/null)" || st=none
    line="$line	$st"
  fi
  printf '%s\n' "$line"
done <<EOF
$logs
EOF
[ "$FAIL_AUTH" = 1 ] && [ "$anyauth" = 1 ] && exit 1
exit 0
