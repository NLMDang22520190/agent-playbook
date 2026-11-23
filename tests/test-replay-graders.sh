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
assert_rc "G5 (5) --fail-on-auth exits 1 when a runner says auth" 1
assert_contains "G5 (5) the line is still printed" "$OUT" "$L/c3.log${TAB}auth${TAB}auth"
run bash "$TOOL" --fail-on-auth "$L/c1.log"
assert_rc "G5 (5) --fail-on-auth exits 0 when both say ok" 0
run bash "$TOOL" --fail-on-auth "$L/c2.log"
assert_rc "G5 (5) --fail-on-auth exits 1 when only one runner says auth" 1
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
run env PATH="$NB" "$NB/bash" "$TOOL" "$L/c1.log"
assert_rc "G5 (8) node missing from PATH exits 2" 2

echo "G5 writes nothing"
SNAP_REPO="$(cd "$PB_ROOT" && git status --porcelain 2>/dev/null | cksum)"
SNAP_LOGS="$(cd "$L" && ls -la | cksum)"
run bash "$TOOL" --stray "$L"
assert_rc "G5 (9) a full replay of the log directory exits 0" 0
assert_eq "G5 (9) the repo working tree status is unchanged" "$SNAP_REPO" "$(cd "$PB_ROOT" && git status --porcelain 2>/dev/null | cksum)"
assert_eq "G5 (9) the log directory is unchanged (no file written next to the logs)" "$SNAP_LOGS" "$(cd "$L" && ls -la | cksum)"
assert_file "G5 the tool exists" "$TOOL"

t_summary
