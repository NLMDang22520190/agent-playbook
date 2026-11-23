#!/usr/bin/env bash
# Tests for tools/replay-graders.sh (v0.38 G5): re-runs the transcript based auth classification of both runners on stored
# stream-json run logs, free. One TSV line per log: <log>\t<evals verdict>\t<outcome verdict> (+ \tstray|none with --stray).
# Small synthetic logs only; never calls a model.
. "$(dirname "$0")/lib.sh"
TOOL="$PB_ROOT/tools/replay-graders.sh"
TAB=$'\t'

W="$(mk_tmp)"; L="$W/logs"; mkdir -p "$L"
RES_OK='"type":"result","subtype":"success","is_error":false'
# (1) a success result line that opens with duration_api_ms and quotes the weak phrase in its result field
printf '%s\n' '{"type":"system","subtype":"init"}' \
  "{\"duration_api_ms\":5,$RES_OK,\"result\":\"Defaults (Not logged in decisions.md)\"}" > "$L/c1.log"
# (2) a task_notification line quoting the weak phrase, then a success result
printf '%s\n' '{"type":"system","subtype":"task_notification","summary":"kept `not logged in` out of decisions.md"}' \
  "{$RES_OK,\"result\":\"done\"}" > "$L/c2.log"
# (3) a strong marker
printf '%s\n' '{"type":"system","subtype":"init"}' \
  '{"type":"result","subtype":"error_during_execution","is_error":true,"result":"API Error: invalid x-api-key"}' > "$L/c3.log"
# (4) an is_error true result line with a weak phrase
printf '%s\n' '{"type":"system","subtype":"init"}' \
  '{"type":"result","subtype":"error_during_execution","is_error":true,"result":"Not logged in - please run /login"}' > "$L/c4.log"
# stray fixtures: a Bash tool_use writing to ../ and one that does not
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"echo hi > ../out.txt"}}]}}' \
  "{$RES_OK,\"result\":\"done\"}" > "$L/s-yes.log"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"echo hi > out.txt"}}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"echo hi > \"$TEMP/x\""}}]}}' \
  "{$RES_OK,\"result\":\"done\"}" > "$L/s-no.log"

echo "G5 verdict columns"
run bash "$TOOL" "$L/c1.log"
assert_rc "G5 (1) exits 0" 0
assert_eq "G5 (1) success result opening with duration_api_ms quoting 'Not logged in': ok in both runners" \
  "$L/c1.log${TAB}ok${TAB}ok" "$OUT"
run bash "$TOOL" "$L/c2.log"
# both runners skip a task_notification line for the weak phrases (run-evals.sh since this fix, run-outcome.sh since v0.37.0)
assert_eq "G5 (2) task_notification quoting it: ok in both runners" \
  "$L/c2.log${TAB}ok${TAB}ok" "$OUT"
run bash "$TOOL" "$L/c3.log"
assert_eq "G5 (3) strong marker invalid x-api-key: auth in both" "$L/c3.log${TAB}auth${TAB}auth" "$OUT"
run bash "$TOOL" "$L/c4.log"
assert_eq "G5 (4) is_error true result with 'not logged in': auth in both" "$L/c4.log${TAB}auth${TAB}auth" "$OUT"
run bash "$TOOL" "$L/c1.log" "$L/c3.log"
assert_eq "G5 two logs give two lines in argument order" "2" "$(printf '%s\n' "$OUT" | grep -c "$TAB")"

echo "G5 --fail-on-auth"
run bash "$TOOL" --fail-on-auth "$L/c3.log"
assert_rc "G5 (5) --fail-on-auth exits 1 when both runners say auth" 1
assert_contains "G5 (5) the line is still printed" "$OUT" "$L/c3.log${TAB}auth${TAB}auth"
run bash "$TOOL" --fail-on-auth "$L/c1.log"
assert_rc "G5 (5) --fail-on-auth exits 0 when both say ok" 0
run bash "$TOOL" --fail-on-auth "$L/c2.log"
assert_rc "G5 (5) --fail-on-auth exits 0 for a task_notification quote (both runners ok since v0.37.0; no realistic log splits them now)" 0
run bash "$TOOL" "$L/c3.log"
assert_rc "G5 without --fail-on-auth an auth log still exits 0" 0

echo "G5 directory expansion"
D="$W/dir"; mkdir -p "$D/sub"; cp "$L/c1.log" "$L/c3.log" "$D/"; cp "$L/c4.log" "$D/sub/c4.log"; : > "$D/notes.txt"
run bash "$TOOL" "$D"
assert_rc "G5 (6) a directory exits 0" 0
assert_eq "G5 (6) two *.log files of the directory give two lines" "2" "$(printf '%s\n' "$OUT" | grep -c "$TAB")"
assert_contains "G5 (6) c1.log of the directory is listed" "$OUT" "c1.log${TAB}ok${TAB}ok"
assert_not_contains "G5 (6) expansion is not recursive" "$OUT" "c4.log"
assert_not_contains "G5 (6) non-.log files are not read" "$OUT" "notes.txt"

echo "G5 --stray"
run bash "$TOOL" --stray "$L/s-yes.log"
assert_eq "G5 (7) a Bash command redirecting to ../out.txt: stray" "$L/s-yes.log${TAB}ok${TAB}ok${TAB}stray" "$OUT"
run bash "$TOOL" --stray "$L/s-no.log"
assert_eq "G5 (7) > out.txt and > \"\$TEMP/x\" are not stray" "$L/s-no.log${TAB}ok${TAB}ok${TAB}none" "$OUT"
run bash "$TOOL" "$L/s-yes.log"
assert_not_contains "G5 (7) without --stray there is no third column" "$OUT" "stray"
for pat in 'echo a >> ../x' 'echo a | tee ../x' 'cp a.txt ../' 'mv a.txt ../b.txt'; do
  printf '%s\n' "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"id\":\"t\",\"name\":\"Bash\",\"input\":{\"command\":\"$pat\"}}]}}" > "$L/p.log"
  run bash "$TOOL" --stray "$L/p.log"
  assert_contains "G5 (7) '$pat' is stray" "$OUT" "${TAB}stray"
done
run bash "$TOOL" --help
assert_contains "G5 (7) the help text says --stray is a lower bound" "$OUT" "lower bound"

echo "G5 usage errors"
run bash "$TOOL"
assert_rc "G5 (8) no LOG exits 2" 2
run bash -c "bash '$TOOL' 2>&1 >/dev/null"
assert_contains "G5 (8) the usage text goes to stderr" "$OUT" "usage"
run bash "$TOOL" "$W/missing.log"
assert_rc "G5 (8) an unreadable log exits 2" 2
run bash "$TOOL" --bogus "$L/c1.log"
assert_rc "G5 (8) an unknown option exits 2" 2
run bash -c "bash '$TOOL' --bogus '$L/c1.log' 2>&1 >/dev/null"
assert_contains "G5 (8) the unknown option is named on stderr" "$OUT" "--bogus"
NB="$(mk_tmp)"; ln -s "$(command -v bash)" "$NB/bash"; ln -s "$(command -v dirname)" "$NB/dirname"
# probe: on Git Bash a linked bash.exe cannot start without its DLLs, so the case cannot run there
if env PATH="$NB" "$NB/bash" -c 'exit 0' >/dev/null 2>&1; then
  run env PATH="$NB" "$NB/bash" "$TOOL" "$L/c1.log"
  assert_rc "G5 (8) node missing from PATH exits 2" 2
else t_skip 1 "G5 (8) node missing from PATH exits 2 (a linked bash does not start on this platform)"; fi

echo "G5 writes nothing"
# snap DIR -> sorted file list with a checksum of each (names and bytes; recursive)
snap() { (cd "$1" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(cksum < "$f")"; done); }
# fresh log directories, so earlier runs cannot have left files that hide a write
F="$(mk_tmp)"; mkdir -p "$F/logs"
cp "$L"/c1.log "$L"/c2.log "$L"/c3.log "$L"/c4.log "$L"/s-yes.log "$L"/s-no.log "$F/logs/"
SNAP_REPO="$(cd "$PB_ROOT" && git status --porcelain 2>/dev/null | cksum)"
SNAP_LOGS="$(snap "$F/logs")"
run bash "$TOOL" --stray "$F/logs"
assert_rc "G5 (9) a full replay of the log directory exits 0" 0
assert_eq "G5 (9) the repo working tree status is unchanged" "$SNAP_REPO" "$(cd "$PB_ROOT" && git status --porcelain 2>/dev/null | cksum)"
assert_eq "G5 (9) the log directory is unchanged (same files, same bytes; no file written next to the logs)" "$SNAP_LOGS" "$(snap "$F/logs")"

echo "G5 leaves the log directory untouched"
# (a) one log WITH a success result line, run by file path
A="$(mk_tmp)"; mkdir -p "$A/logs"
printf '%s\n' '{"type":"system","subtype":"init"}' \
  "{$RES_OK,\"result\":\"Not logged in\"}" > "$A/logs/r.log"
SNAP_A="$(snap "$A/logs")"
run bash "$TOOL" "$A/logs/r.log"
assert_rc "G5 (10a) a log with a result line exits 0" 0
assert_eq "G5 (10a) the directory of a log with a result line is byte-for-byte unchanged" "$SNAP_A" "$(snap "$A/logs")"
assert_no_path "G5 (10a) no <log>.result is created next to the log" "$A/logs/r.log.result"
# (b) a pre-existing <log>.result next to a log WITHOUT a result line survives
B="$(mk_tmp)"; mkdir -p "$B/logs"
printf '%s\n' '{"type":"system","subtype":"init"}' > "$B/logs/n.log"
printf 'my stored reply\n' > "$B/logs/n.log.result"
run bash "$TOOL" "$B/logs/n.log"
assert_rc "G5 (10b) a log without a result line exits 0" 0
assert_file "G5 (10b) a pre-existing <log>.result next to a log without a result line is not deleted" "$B/logs/n.log.result"
assert_eq "G5 (10b) its content is unchanged" "my stored reply" "$(cat "$B/logs/n.log.result" 2>/dev/null)"
# (c) a pre-existing <log>.result next to a log WITH a result line keeps its content
C="$(mk_tmp)"; mkdir -p "$C/logs"
cp "$A/logs/r.log" "$C/logs/r.log"
printf 'my stored reply\n' > "$C/logs/r.log.result"
run bash "$TOOL" "$C/logs"
assert_rc "G5 (10c) a directory run exits 0" 0
assert_eq "G5 (10c) a pre-existing <log>.result next to a log with a result line keeps its content" "my stored reply" "$(cat "$C/logs/r.log.result" 2>/dev/null)"
assert_file "G5 the tool exists" "$TOOL"

# =====================================================================================================================================
# v0.38 G5 remainder (docs/v0.38-g5-spec.md R1, R2; AC1 to AC6): --against RESULT.json adds the columns recorded<TAB>change, and
# --fail-on-change exits 1 on error->ok or graded->auth. RESULT.json is a synthetic pb-evals/1 file shaped like F3 of the spec (label,
# status, error); the logs are the small synthetic ones above. Never calls a model.
echo "G5R against: fixtures"
G="$(mk_tmp)"; GL="$G/logs"; mkdir -p "$GL"
AUTH_ERR='auth or harness error in the transcript'
# a task_notification quoting the weak phrase, then a success result: ok in both runners (the spec's AC1 shape)
cp "$L/c2.log" "$GL/E24.with.5.log"                       # recorded error (auth or harness error) -> error->ok
cp "$L/c3.log" "$GL/E21.with.1.log"                       # strong marker, recorded graded -> graded->auth
cp "$L/c1.log" "$GL/E2.with.1.log"                        # ok, recorded graded -> unchanged
cp "$L/c3.log" "$GL/E3.with.1.log"                        # auth, recorded error (auth or harness error) -> unchanged
cp "$L/c1.log" "$GL/E4.with.1.log"                        # ok, recorded error with another error (adapter exited 1) -> unchanged
cp "$L/c2.log" "$GL/E5.with.1.log"                        # ok, recorded error with a LONGER error that starts with the prefix -> error->ok
cp "$L/c3.log" "$GL/E6.with.1.log"                        # auth, recorded skipped -> unchanged (graded->auth needs status graded)
cp "$L/c1.log" "$GL/E7.with.1.log"                        # ok, recorded error with a null error -> unchanged
cp "$L/c1.log" "$GL/zz-not-in-result.log"                 # no run with this label -> unmatched
# gres FILE LABEL|STATUS|ERROR ... : a pb-evals/1 file; an empty ERROR is null
gres() {
  local out="$1" runs="" sep="" a lab st er; shift
  for a in "$@"; do
    lab="${a%%|*}"; a="${a#*|}"; st="${a%%|*}"; er="${a#*|}"
    if [ -n "$er" ]; then er="\"$er\""; else er=null; fi
    runs="$runs$sep{\"scenario\":\"x\",\"arm\":\"with\",\"k\":1,\"label\":\"$lab\",\"status\":\"$st\",\"error\":$er,\"checks\":[]}"; sep=","
  done
  printf '{"schema":"pb-evals/1","playbook_commit":"abc","harness":"claude","model":"m1","runs":[%s],"summary":[]}\n' "$runs" > "$out"
}
RJ="$G/result.json"
gres "$RJ" "E24.with.5|error|$AUTH_ERR" "E21.with.1|graded|" "E2.with.1|graded|" "E3.with.1|error|$AUTH_ERR" \
  "E4.with.1|error|adapter exited 1" "E5.with.1|error|$AUTH_ERR: more text" "E6.with.1|skipped|" "E7.with.1|error|"
ag() { run bash "$TOOL" --against "$RJ" "$@"; }   # the usual call; stdout and stderr in $OUT

echo "G5R AC1 error->ok: a recorded auth or harness error whose log both runners now call ok"
ag "$GL/E24.with.5.log"
assert_rc "AC1 exits 0 without --fail-on-change" 0
assert_eq "AC1 the line is log, ok, ok, error, error->ok" "$GL/E24.with.5.log${TAB}ok${TAB}ok${TAB}error${TAB}error->ok" "$OUT"
ag "$GL/E5.with.1.log"
assert_contains "AC1 an error that only STARTS with 'auth or harness error' counts" "$OUT" "${TAB}error${TAB}error->ok"

echo "G5R AC2 graded->auth: a recorded graded run whose log a runner now calls auth"
ag "$GL/E21.with.1.log"
assert_eq "AC2 the line is log, auth, auth, graded, graded->auth" "$GL/E21.with.1.log${TAB}auth${TAB}auth${TAB}graded${TAB}graded->auth" "$OUT"

echo "G5R AC3 unchanged"
ag "$GL/E2.with.1.log"
assert_eq "AC3 an ok log of a graded run: unchanged" "$GL/E2.with.1.log${TAB}ok${TAB}ok${TAB}graded${TAB}unchanged" "$OUT"
ag "$GL/E3.with.1.log"
assert_eq "AC3 an error run whose replay also says auth: unchanged" "$GL/E3.with.1.log${TAB}auth${TAB}auth${TAB}error${TAB}unchanged" "$OUT"
ag "$GL/E4.with.1.log"
assert_eq "AC3 an error run with another error (adapter exited 1) and an ok log: unchanged" "$GL/E4.with.1.log${TAB}ok${TAB}ok${TAB}error${TAB}unchanged" "$OUT"
ag "$GL/E6.with.1.log"
assert_eq "AC3 a skipped run with an auth log is not graded->auth: unchanged" "$GL/E6.with.1.log${TAB}auth${TAB}auth${TAB}skipped${TAB}unchanged" "$OUT"
ag "$GL/E7.with.1.log"
assert_eq "AC3 an error run with a null error and an ok log: unchanged" "$GL/E7.with.1.log${TAB}ok${TAB}ok${TAB}error${TAB}unchanged" "$OUT"

echo "G5R AC4 unmatched, and the output without --against is byte for byte the old one"
ag "$GL/zz-not-in-result.log"
assert_eq "AC4 a label that no run has: recorded -, change unmatched" "$GL/zz-not-in-result.log${TAB}ok${TAB}ok${TAB}-${TAB}unmatched" "$OUT"
ag "$GL/E2.with.1.log" "$GL/zz-not-in-result.log" "$GL/E21.with.1.log"
assert_eq "AC4 several logs: one line each, in argument order, each with its own columns" \
  "$GL/E2.with.1.log${TAB}ok${TAB}ok${TAB}graded${TAB}unchanged
$GL/zz-not-in-result.log${TAB}ok${TAB}ok${TAB}-${TAB}unmatched
$GL/E21.with.1.log${TAB}auth${TAB}auth${TAB}graded${TAB}graded->auth" "$OUT"
ag "$GL"
assert_eq "AC4 a directory argument gives one line per *.log, all with the new columns" "9" "$(printf '%s\n' "$OUT" | grep -c "${TAB}\(unchanged\|unmatched\|error->ok\|graded->auth\)$")"
# snapshot of today's output (v0.37.0 code) for the same logs, with and without --stray, written out by hand
SNAPD="$(mk_tmp)"; mkdir -p "$SNAPD/s"
cp "$L/c1.log" "$L/c2.log" "$L/c3.log" "$L/c4.log" "$L/s-yes.log" "$SNAPD/s/"
SNAP_PLAIN="$SNAPD/s/c1.log${TAB}ok${TAB}ok
$SNAPD/s/c2.log${TAB}ok${TAB}ok
$SNAPD/s/c3.log${TAB}auth${TAB}auth
$SNAPD/s/c4.log${TAB}auth${TAB}auth
$SNAPD/s/s-yes.log${TAB}ok${TAB}ok"
run bash "$TOOL" "$SNAPD/s"
assert_eq "AC4 without --against the output is the recorded snapshot, byte for byte" "$SNAP_PLAIN" "$OUT"
run bash "$TOOL" --stray "$SNAPD/s/c1.log" "$SNAPD/s/s-yes.log"
assert_eq "AC4 --stray without --against is the recorded snapshot, byte for byte" "$SNAPD/s/c1.log${TAB}ok${TAB}ok${TAB}none
$SNAPD/s/s-yes.log${TAB}ok${TAB}ok${TAB}stray" "$OUT"
run bash "$TOOL" --fail-on-auth "$SNAPD/s/c3.log"
assert_eq "AC4 --fail-on-auth without --against keeps its line and exit 1" "$SNAPD/s/c3.log${TAB}auth${TAB}auth|1" "$OUT|$RC"
SAV="$G/saved.json"; cp "$RJ" "$SAV"
ag "$GL"
assert_eq "AC4 --against only reads RESULT.json (unchanged bytes)" "$(cksum < "$SAV")" "$(cksum < "$RJ")"

echo "G5R --stray with --against: the stray column stays before the two new columns"
run bash "$TOOL" --against "$RJ" --stray "$GL/E24.with.5.log" "$GL/zz-not-in-result.log"
assert_eq "AC4 --stray --against: log, ok, ok, none, error, error->ok" "$GL/E24.with.5.log${TAB}ok${TAB}ok${TAB}none${TAB}error${TAB}error->ok
$GL/zz-not-in-result.log${TAB}ok${TAB}ok${TAB}none${TAB}-${TAB}unmatched" "$OUT"

echo "G5R AC5 a RESULT.json that is missing, not JSON, or not pb-evals/1: exit 2 with one error line"
printf 'this is not json\n' > "$G/notjson.json"
printf '{"schema":"pb-evals/2","runs":[]}\n' > "$G/otherschema.json"
printf '{"runs":[]}\n' > "$G/noschema.json"
: > "$G/empty.json"
for bad in "$G/missing.json" "$G/notjson.json" "$G/otherschema.json" "$G/noschema.json" "$G/empty.json"; do
  bn="${bad##*/}"
  run bash "$TOOL" --against "$bad" "$GL/E2.with.1.log"
  assert_rc "AC5 --against $bn exits 2" 2
  ERRTXT="$(bash "$TOOL" --against "$bad" "$GL/E2.with.1.log" 2>&1 >/dev/null)"
  assert_eq "AC5 --against $bn: exactly one line on stderr" "1" "$(printf '%s\n' "$ERRTXT" | grep -c .)"
  assert_not_contains "AC5 --against $bn: the error is about RESULT.json, not an unknown option" "$ERRTXT" "unknown option"
  assert_eq "AC5 --against $bn: no result line is printed on stdout" "" "$(bash "$TOOL" --against "$bad" "$GL/E2.with.1.log" 2>/dev/null)"
done
run bash "$TOOL" --against
assert_rc "AC5 --against without a value exits 2" 2

echo "G5R AC6 --fail-on-change"
run bash "$TOOL" --against "$RJ" --fail-on-change "$GL/E24.with.5.log"
assert_rc "AC6 error->ok (AC1) exits 1" 1
assert_contains "AC6 error->ok: the line is still printed" "$OUT" "$GL/E24.with.5.log${TAB}ok${TAB}ok${TAB}error${TAB}error->ok"
run bash "$TOOL" --against "$RJ" --fail-on-change "$GL/E21.with.1.log"
assert_rc "AC6 graded->auth (AC2) exits 1" 1
assert_contains "AC6 graded->auth: the line is still printed" "$OUT" "$GL/E21.with.1.log${TAB}auth${TAB}auth${TAB}graded${TAB}graded->auth"
run bash "$TOOL" --against "$RJ" --fail-on-change "$GL/E2.with.1.log" "$GL/E3.with.1.log"
assert_rc "AC6 unchanged lines (AC3) exit 0" 0
run bash "$TOOL" --against "$RJ" --fail-on-change "$GL/zz-not-in-result.log"
assert_rc "AC6 unmatched (AC4) exits 0" 0
run bash "$TOOL" --against "$RJ" --fail-on-change "$GL/E2.with.1.log" "$GL/E21.with.1.log" "$GL/zz-not-in-result.log"
assert_rc "AC6 one changed line among others exits 1" 1
assert_eq "AC6 and all three lines are printed" "3" "$(printf '%s\n' "$OUT" | grep -c "$TAB")"
run bash "$TOOL" --against "$RJ" "$GL/E24.with.5.log" "$GL/E21.with.1.log"
assert_rc "AC6 without --fail-on-change a changed line exits 0" 0
run bash "$TOOL" --fail-on-change --against "$RJ" "$GL/E24.with.5.log"
assert_rc "AC6 the flags may come in either order" 1
run bash "$TOOL" --against "$RJ" --fail-on-change "$GL"
assert_rc "AC6 a directory with changed lines exits 1" 1
run bash "$TOOL" --fail-on-change "$GL/E2.with.1.log"
assert_rc "AC6 --fail-on-change without --against exits 2" 2
assert_not_contains "AC6 --fail-on-change without --against: not 'unknown option'" "$OUT" "unknown option"
run bash "$TOOL" --fail-on-change
assert_rc "AC6 --fail-on-change alone, no LOG at all, still exits 2" 2
assert_not_contains "AC6 --fail-on-change alone: the --against check comes first (not 'unknown option')" "$OUT" "unknown option"
run bash "$TOOL" --against "$G/notjson.json" --fail-on-change "$GL/E2.with.1.log"
assert_rc "AC6 --fail-on-change with an invalid RESULT.json exits 2" 2
run bash "$TOOL" --against "$G/missing.json" --fail-on-change "$GL/E2.with.1.log"
assert_rc "AC6 --fail-on-change with a missing RESULT.json exits 2" 2
run bash "$TOOL" --against "$RJ" --fail-on-auth "$GL/E24.with.5.log"
assert_rc "AC6 --fail-on-auth keeps its meaning: an error->ok log with verdicts ok exits 0" 0
run bash "$TOOL" --against "$RJ" --fail-on-auth "$GL/E21.with.1.log"
assert_rc "AC6 --fail-on-auth keeps its meaning: an auth verdict exits 1" 1
run bash "$TOOL" --against "$RJ" --fail-on-auth "$GL/E3.with.1.log"
assert_rc "AC6 --fail-on-auth still exits 1 on an auth verdict that is 'unchanged'" 1
run bash "$TOOL" --against "$RJ" --fail-on-auth --fail-on-change "$GL/E2.with.1.log"
assert_rc "AC6 both flags and nothing wrong exit 0" 0

echo "G5R a split verdict (one runner ok, the other auth): error->ok needs BOTH ok, graded->auth needs at least ONE auth"
# no real log splits the two runners today, so a copy of the tool and runners (in a temp tree) gets an outcome runner whose auth_marker says auth for every log
SPLT="$(mk_tmp)"; mkdir -p "$SPLT/tools" "$SPLT/evals"
cp -p "$TOOL" "$SPLT/tools/replay-graders.sh"; cp -p "$PB_ROOT/evals/transcript.js" "$PB_ROOT/evals/run-evals.sh" "$PB_ROOT/evals/run-outcome.sh" "$SPLT/evals/"
awk '/^auth_marker\(\)/ { print "auth_marker() { return 0; }"; skip = 1; next } skip { if (/^}/) skip = 0; next } { print }' "$PB_ROOT/evals/run-outcome.sh" > "$SPLT/evals/run-outcome.sh"
run bash "$SPLT/tools/replay-graders.sh" "$GL/E2.with.1.log"
assert_eq "split fixture: the evals runner says ok and the patched outcome runner says auth" "$GL/E2.with.1.log${TAB}ok${TAB}auth" "$OUT"
run bash "$SPLT/tools/replay-graders.sh" --against "$RJ" "$GL/E24.with.5.log"
assert_eq "split: a recorded auth error with ok/auth now is NOT error->ok (both runners must say ok)" "$GL/E24.with.5.log${TAB}ok${TAB}auth${TAB}error${TAB}unchanged" "$OUT"
run bash "$SPLT/tools/replay-graders.sh" --against "$RJ" "$GL/E2.with.1.log"
assert_eq "split: a graded run with ok/auth is graded->auth (one runner is enough)" "$GL/E2.with.1.log${TAB}ok${TAB}auth${TAB}graded${TAB}graded->auth" "$OUT"
run bash "$SPLT/tools/replay-graders.sh" --against "$RJ" --fail-on-change "$GL/E2.with.1.log"
assert_rc "split: --fail-on-change exits 1 on it" 1

t_summary
