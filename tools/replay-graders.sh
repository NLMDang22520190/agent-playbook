#!/usr/bin/env bash
# Re-runs the auth classification of both runners on stored stream-json run logs, free (v0.38 G5; never calls a model).
#   tools/replay-graders.sh [--fail-on-auth] [--stray] [--against RESULT.json [--fail-on-change]] LOG...
# One TSV line per log, in argument order: <log> TAB <evals verdict> TAB <outcome verdict> [TAB <stray|none>] [TAB <recorded> TAB <change>].
# A verdict is "auth" when the runner's auth_marker finds an auth failure in the log, else "ok". auth_lines and auth_marker are
# read from the CURRENT evals/run-evals.sh and evals/run-outcome.sh at run time (sed/awk extraction, no copied regexes), and
# result_ok comes from evals/transcript.js as each runner's load_transcript gets it, so a change to a runner shows here at once.
# A directory argument expands to its *.log files (not recursive). The logs are only read (the graders run on a temp copy of each); nothing is written next to them.
#   --fail-on-auth   exit 1 when any log gets "auth" from either runner (the lines are still printed)
#   --stray          add a fourth column: "stray" when a Bash tool_use command of the log writes outside the work dir
#                    (a redirect, tee, cp or mv aimed at a ../ path), else "none". Since v0.37.0 run-outcome.sh tolerates one
#                    scratch level (../x), so this column is a superset of its stray FAILs. It is a lower bound: a write the
#                    command text does not show (a script, a variable, an absolute path) is not seen.
#   --against FILE   FILE is a pb-evals/1 result (RESULT.json). A log whose name (without .log) is the label of a run in it gets two
#                    more columns after the stray one: <recorded> (the run's status) and <change>: "error->ok" (recorded status error
#                    with an error that starts with "auth or harness error", and both runners now say ok), "graded->auth" (recorded
#                    graded and a runner now says auth), "unchanged" (any other matched log) or "unmatched" (no run has that label;
#                    recorded is "-"). Without --against the output is unchanged. FILE unreadable or not pb-evals/1: exit 2.
#   --fail-on-change with --against only (else exit 2): exit 1 when a line is error->ok or graded->auth (the lines are still printed)
#   -h, --help       this text
# Exit: 0 ok | 1 --fail-on-auth and a log is "auth", or --fail-on-change and a log changed | 2 usage, unreadable log or RESULT.json, node missing or a runner function not found.
# Bash 3.2 compatible.
set -u

usage() { echo "usage: tools/replay-graders.sh [--fail-on-auth] [--stray] [--against RESULT.json [--fail-on-change]] LOG..." >&2; exit 2; }
die() { echo "replay-graders: $1" >&2; exit 2; }

FAIL_AUTH=0 STRAY=0 FAIL_CHG=0 AGAINST="" TABC="$(printf '\t')" logs=""
nl='
'
while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help) sed -n '2,/^set -u/p' "$0" | sed '/^set -u/d' | sed 's/^# \{0,1\}//'; echo "usage: tools/replay-graders.sh [--fail-on-auth] [--stray] [--against RESULT.json [--fail-on-change]] LOG..."; exit 0 ;;
    --fail-on-auth) FAIL_AUTH=1 ;;
    --stray) STRAY=1 ;;
    --fail-on-change) FAIL_CHG=1 ;;
    --against) [ $# -ge 2 ] || { echo "replay-graders: --against needs a RESULT.json" >&2; usage; }; AGAINST="$2"; shift ;;
    --) shift; break ;;
    -*) echo "replay-graders: unknown option: $1" >&2; usage ;;
    *) break ;;
  esac
  shift
done
[ "$FAIL_CHG" = 0 ] || [ -n "$AGAINST" ] || die "--fail-on-change needs --against RESULT.json"
[ $# -ge 1 ] || usage

command -v node >/dev/null 2>&1 || die "node is needed (evals/transcript.js) and is not on PATH"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EVALS="$ROOT/evals"

# --against: label<TAB>status<TAB>1 (an error that starts with "auth or harness error") or 0, one line per run
AGMAP=""
if [ -n "$AGAINST" ]; then
  AGMAP="$(node -e '
const fs = require("fs"); let j;
try { j = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); } catch (x) { process.exit(2); }
if (!j || j.schema !== "pb-evals/1" || !Array.isArray(j.runs)) process.exit(2);
for (const r of j.runs) {
  if (!r || typeof r.label !== "string") continue;
  const pre = typeof r.error === "string" && r.error.indexOf("auth or harness error") === 0 ? 1 : 0;
  console.log(r.label.replace(/[\t\n]/g, " ") + "\t" + String(r.status).replace(/[\t\n]/g, " ") + "\t" + pre);
}' "$AGAINST" 2>/dev/null)" || die "cannot use $AGAINST: not a readable pb-evals/1 result file"
fi

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
  # shellcheck disable=SC2034 # LOG and T_result_ok are read by the auth_lines/auth_marker functions sourced below
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

anyauth=0 anychg=0 n=0
while IFS= read -r log; do
  [ -n "$log" ] || continue
  # transcript.js writes/deletes <log>.result and the runner functions read $LOG: work on a copy in our own temp dir
  n=$((n + 1)); mkdir "$W/c$n" || die "cannot make a temp dir"
  cp "$log" "$W/c$n/run.log" || die "cannot copy: $log"
  work="$W/c$n/run.log"
  rok=0
  while IFS='=' read -r k v; do
    [ "$k" = result_ok ] && rok="$v"
  done <<EOF
$(node "$EVALS/transcript.js" "$work" 2>/dev/null)
EOF
  ve="$(verdict evals "$work" "$rok")" || die "the evals auth functions failed on $log"
  vo="$(verdict outcome "$work" "$rok")" || die "the outcome auth functions failed on $log"
  [ "$ve" = auth ] || [ "$vo" = auth ] && anyauth=1
  line="$log	$ve	$vo"
  if [ "$STRAY" = 1 ]; then
    st="$(node -e "$STRAYJS" "$log" 2>/dev/null)" || st=none
    line="$line	$st"
  fi
  if [ -n "$AGAINST" ]; then
    lab="${log##*/}"; lab="${lab%.log}"; rec="-"; chg=unmatched; pre=0
    while IFS="$TABC" read -r ml ms mp; do
      [ "$ml" = "$lab" ] && { rec="$ms"; pre="$mp"; chg=unchanged; break; }
    done <<EOT
$AGMAP
EOT
    if [ "$rec" = error ] && [ "$pre" = 1 ] && [ "$ve" = ok ] && [ "$vo" = ok ]; then chg="error->ok"
    elif [ "$rec" = graded ] && { [ "$ve" = auth ] || [ "$vo" = auth ]; }; then chg="graded->auth"; fi
    case "$chg" in error*|graded*) anychg=1 ;; esac
    line="$line$TABC$rec$TABC$chg"
  fi
  printf '%s\n' "$line"
done <<EOF
$logs
EOF
[ "$FAIL_AUTH" = 1 ] && [ "$anyauth" = 1 ] && exit 1
[ "$FAIL_CHG" = 1 ] && [ "$anychg" = 1 ] && exit 1
exit 0
