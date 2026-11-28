#!/usr/bin/env bash
# Tests for v0.38 G5 remainder, R3 to R5 (docs/v0.38-g5-spec.md AC7 to AC11): tools/release-gate.sh replays the stored outcome run
# logs (evals/results/<dir>/outcome-<stamp>.runs/<label>.log, the path run-outcome.sh writes: EV="${OUT%.md}.runs") against their
# outcome-<stamp>.json with tools/replay-graders.sh --against, before it finds a baseline or starts anything. A run whose verdict
# would change (error->ok, graded->auth) is refused with exit 2; --skip-replay bypasses the step; --dry-run has its own call.
# Fixture: rgf_prepare (fake runners that exit 99 and say so) in a git repo; tools/replay-graders.sh and evals/transcript.js are copied
# in and the REAL auth_lines/auth_marker/result_ok of evals/run-*.sh are grafted into the fake runners (before their `exit 99`, which
# stays their main exit), because replay-graders.sh reads those functions from $ROOT/evals/run-*.sh. Never calls a model.
# Runtime estimate for tests/shard-weights: about 40 seconds (estimate, L-0009).
. "$(dirname "$0")/lib.sh"
command -v node >/dev/null 2>&1 || { t_skip 1 "node missing"; t_summary; exit $?; }
command -v git >/dev/null 2>&1 || { t_skip 1 "git missing"; t_summary; exit $?; }
. "$(dirname "$0")/release-gate-fixture.sh"
rgf_gh_install "$RGF_W/gh"; export PATH="$RGF_GH/bin:$PATH"; export PB_GATE_REPO=acme/widgets
W="$RGF_W"
TAB=$'\t'
AUTH_ERR='auth or harness error in the transcript'
RES_OK='"type":"result","subtype":"success","is_error":false'
MSG_STALE_TAIL='); the recorded batch is stale: use another --out-dir, or pass --skip-replay'

# ---- logs (synthetic stream-json, the shapes of tests/test-replay-graders.sh) ------------------------------------------------------
# ok in both runners: a task_notification quoting the weak phrase "not logged in" (the shape of the real attempt 3 and 4 failures)
mklog_ok() { printf '%s\n' '{"type":"system","subtype":"task_notification","summary":"kept `not logged in` out of decisions.md"}' "{$RES_OK,\"result\":\"done\"}" > "$1"; }
# auth in both runners: a strong marker
mklog_auth() { printf '%s\n' '{"type":"system","subtype":"init"}' '{"type":"result","subtype":"error_during_execution","is_error":true,"result":"API Error: invalid x-api-key"}' > "$1"; }

# ---- fixture repo -------------------------------------------------------------------------------------------------------------------
# graft FILE REAL: FILE (a fake runner ending in `exit 99`) gets the result_ok / auth_lines / auth_marker functions of REAL inserted before its last line
graft() {
  local f="$1" real="$2" t
  t="$(mktemp)" || return 1
  { sed '$d' "$f"
    awk '/^result_ok\(\)/ { print; next }
         /^auth_lines\(\)/ { print; next }
         /^auth_marker\(\)/ { on = 1 }
         on { print }
         on && /^}/ { on = 0 }' "$real"
    echo 'exit 99'; } > "$t"
  cat "$t" > "$f"; rm -f "$t"
}
# mkrepo NAME: a committed repo with the gate, the fake runners (grafted) and the replay tool; HEAD is clean
mkrepo() {
  local r="$W/$1"
  rm -rf "$r"; mkdir -p "$r"
  rgf_prepare "$r"
  cp -p "$PB_ROOT/tools/replay-graders.sh" "$r/tools/replay-graders.sh"
  cp -p "$PB_ROOT/evals/transcript.js" "$r/evals/transcript.js"
  graft "$r/evals/run-evals.sh" "$PB_ROOT/evals/run-evals.sh"
  graft "$r/evals/run-outcome.sh" "$PB_ROOT/evals/run-outcome.sh"
  rgf_git -C "$r" init -q && rgf_git -C "$r" add -A && rgf_git -C "$r" commit -qm base || t_bad "fixture $1" "git init or commit failed"
  R="$r"
}
# recommit REPO: commit whatever the test changed in tools/ (a stub replay tool), so the tree stays clean
recommit() { rgf_git -C "$1" add -A && rgf_git -C "$1" commit -qm stub; }

# ---- out dirs -----------------------------------------------------------------------------------------------------------------------
# outjson FILE LABEL|STATUS|ERROR ... : an outcome pb-evals/1 file (F3 shape: label, status, error); an empty ERROR is null
outjson() {
  local out="$1" runs="" sep="" a lab st er; shift
  for a in "$@"; do
    lab="${a%%|*}"; a="${a#*|}"; st="${a%%|*}"; er="${a#*|}"
    if [ -n "$er" ]; then er="\"$er\""; else er=null; fi
    runs="$runs$sep{\"scenario\":\"x\",\"arm\":\"with\",\"k\":1,\"label\":\"$lab\",\"status\":\"$st\",\"error\":$er,\"checks\":[]}"; sep=","
  done
  printf '{"schema":"pb-evals/1","playbook_commit":"abc","harness":"claude","model":"m1","runs":[%s],"summary":[]}\n' "$runs" > "$out"
}
# mkout REPO DIR KIND...: DIR under evals/results with outcome-s1.json and outcome-s1.runs/<label>.log; KIND is one of
#   chg-err   recorded error (auth or harness error), the log is ok now      -> error->ok
#   chg-auth  recorded graded, the log shows invalid x-api-key               -> graded->auth
#   same-ok   recorded graded, the log is ok                                 -> unchanged
#   same-err  recorded error "adapter exited 1", the log is ok               -> unchanged
#   unm       a log whose label no run has                                   -> unmatched
mkout() {
  local r="$1" d="$2" k i=0 d0 runs=(); shift 2
  d0="$r/evals/results/$d"; mkdir -p "$d0/outcome-s1.runs"
  for k in "$@"; do
    i=$((i + 1))
    case "$k" in
      chg-err)  mklog_ok "$d0/outcome-s1.runs/pattern-0$i.with.1.log"; runs+=("pattern-0$i.with.1|error|$AUTH_ERR") ;;
      chg-auth) mklog_auth "$d0/outcome-s1.runs/pattern-0$i.with.1.log"; runs+=("pattern-0$i.with.1|graded|") ;;
      same-ok)  mklog_ok "$d0/outcome-s1.runs/pattern-0$i.with.1.log"; runs+=("pattern-0$i.with.1|graded|") ;;
      same-err) mklog_ok "$d0/outcome-s1.runs/pattern-0$i.with.1.log"; runs+=("pattern-0$i.with.1|error|adapter exited 1") ;;
      unm)      mklog_ok "$d0/outcome-s1.runs/pattern-0$i.with.1.log" ;;
    esac
  done
  outjson "$d0/outcome-s1.json" "${runs[@]}"
}

# ---- running the gate ---------------------------------------------------------------------------------------------------------------
# gate REPO ARGS...: RC, GOUT (stdout), GERR (stderr); TMPDIR is a fresh empty directory (SNAPTMP lists what the gate left in it)
gate() {
  local r="$1"; shift
  rm -rf "$W/gtmp"; mkdir -p "$W/gtmp"
  RC=0; ( cd "$r" && env HOME="$W/home" TMPDIR="$W/gtmp" bash tools/release-gate.sh "$@" > "$W/g.out" 2> "$W/g.err" ) || RC=$?
  GOUT="$(cat "$W/g.out")"; GERR="$(cat "$W/g.err")"; OUT="$GOUT$GERR"
  SNAPTMP="$(ls -A "$W/gtmp" | tr '\n' ' ')"
}
# real REPO DIR ARGS...: a real run that adds a batch to DIR (the only real run that can find a used DIR), CI check skipped
real() { local r="$1" d="$2"; shift 2; gate "$r" --harness claude --model m1 --add-batch --skip-ci-check --out-dir "evals/results/$d" "$@"; }
# snap REPO: every file of the repo outside .git (name and checksum), the worktree list, so a refusal can be shown to have created nothing
snap() { ( cd "$1" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(cksum < "$f")"; done; git worktree list | wc -l ); }
# normd NAME: the dry-run report with the out dir name and the run stamp (time and pid) replaced
normd() { sed -e "s#$1#D#g" -e 's#[0-9]\{8\}T[0-9]\{6\}Z-[0-9]*#STAMP#g'; }
# nlines TEXT: the number of non-empty lines
nlines() { printf '%s\n' "$1" | grep -c . || true; }
# replay_lines: the stderr lines that start with "replay:"
replay_lines() { printf '%s\n' "$GERR" | grep '^replay:' || true; }
# calls LOG: how many lines a stub replay tool recorded
calls() { if [ -f "$1" ]; then grep -c . "$1" || true; else echo 0; fi; }

# a stub tools/replay-graders.sh that records its arguments in $STUBLOG and then does STUBBODY (default: exit 0 with no output)
STUBLOG="$W/stub.log"
mkstub() { # REPO BODY
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\n%s\n' "$STUBLOG" "$2" > "$1/tools/replay-graders.sh"; chmod 755 "$1/tools/replay-graders.sh"
  recommit "$1"
}

echo "G5R fixture sanity: the fake runners keep exit 99 as their main exit and carry the real auth functions"
mkrepo base; BASE="$R"
for rn in run-evals.sh run-outcome.sh; do
  RC=0; OUT="$(cd "$BASE" && bash "evals/$rn" 2>&1)" || RC=$?
  assert_eq "fixture $rn still exits 99" "99" "$RC"
  assert_contains "fixture $rn still says it was called" "$OUT" "fixture runner called"
  assert_eq "fixture $rn has the real auth_marker" "1" "$(grep -c '^auth_marker()' "$BASE/evals/$rn")"
done
mklog_ok "$W/fx-ok.log"; mklog_auth "$W/fx-auth.log"
RC=0; OUT="$(cd "$BASE" && bash tools/replay-graders.sh "$W/fx-ok.log" "$W/fx-auth.log" 2>&1)" || RC=$?
assert_eq "fixture: the copied replay tool gives ok/ok for the task_notification log and auth/auth for the key log" \
  "$W/fx-ok.log${TAB}ok${TAB}ok
$W/fx-auth.log${TAB}auth${TAB}auth" "$OUT"

echo "G5R AC7 a real --add-batch run on a DIR with a recorded error that now grades ok: refused with exit 2, nothing started"
mkrepo ac7; A7="$R"
mkout "$A7" d-err chg-err same-ok
BEFORE="$(snap "$A7")"
real "$A7" d-err
assert_rc "AC7 error->ok in the stored batch: exit 2" 2
assert_not_contains "AC7 no runner was called (its fixture line is absent)" "$OUT" "fixture runner called"
assert_eq "AC7 stdout is empty" "" "$GOUT"
assert_contains "AC7 the message says how many runs were graded differently" "$GERR" "replay: 1 run(s) were graded differently than the current graders would grade them ("
assert_contains "AC7 the message names the label" "$GERR" "pattern-01.with.1"
assert_not_contains "AC7 the unchanged label is not named" "$GERR" "pattern-02.with.1"
assert_contains "AC7 the message ends with the way out" "$GERR" "$MSG_STALE_TAIL"
assert_eq "AC7 the replay line is on stderr (stdout has no 'replay:')" "0" "$(printf '%s\n' "$GOUT" | grep -c 'replay:' || true)"
assert_eq "AC7 no file was created or changed, no worktree (repo tree before and after)" "$BEFORE" "$(snap "$A7")"
assert_eq "AC7 the gate left nothing in its TMPDIR" "" "$SNAPTMP"
assert_no_path "AC7 no gate.json" "$A7/evals/results/d-err/gate.json"
# the baseline step comes after: a refusal must not be the noqual exit 3 of find_baseline
assert_not_contains "AC7 the later steps (baseline, preflight) were not reached" "$GERR" "preflight"

echo "G5R AC7 graded->auth is refused the same way; two files, one stale: refused"
mkout "$A7" d-auth same-ok chg-auth
real "$A7" d-auth
assert_rc "AC7 graded->auth in the stored batch: exit 2" 2
assert_contains "AC7 graded->auth: the label is named" "$GERR" "pattern-02.with.1"
assert_contains "AC7 graded->auth: the message is the same sentence" "$GERR" "$MSG_STALE_TAIL"
assert_not_contains "AC7 graded->auth: no runner called" "$OUT" "fixture runner called"
mkout "$A7" d-two same-ok
mkdir -p "$A7/evals/results/d-two/outcome-s2.runs"
mklog_auth "$A7/evals/results/d-two/outcome-s2.runs/pattern-09.with.1.log"
outjson "$A7/evals/results/d-two/outcome-s2.json" "pattern-09.with.1|graded|"
real "$A7" d-two
assert_rc "AC7 a clean outcome file next to a stale one: exit 2 (every outcome file is replayed)" 2
assert_contains "AC7 the stale file's label is named" "$GERR" "pattern-09.with.1"
mkout "$A7" d-two2 chg-err chg-err
real "$A7" d-two2
assert_contains "AC7 two changed runs: the count is 2" "$GERR" "replay: 2 run(s) were graded differently"
assert_contains "AC7 two changed runs: both labels" "$GERR" "pattern-02.with.1"
assert_contains "AC7 two changed runs: first label too" "$GERR" "pattern-01.with.1"

echo "G5R AC7 with the CI check on (no --skip-ci-check) the replay comes after ci_check"
rgf_gh_green
gate "$A7" --harness claude --model m1 --add-batch --out-dir evals/results/d-err
assert_rc "AC7 CI green + stale batch: exit 2 from the replay" 2
assert_contains "AC7 CI green: the replay refusal is printed" "$GERR" "$MSG_STALE_TAIL"
assert_eq "AC7 CI green: the check runs were read before the refusal" "1" "$(rgf_gh_ncalls)"
rgf_gh_fail all
gate "$A7" --harness claude --model m1 --add-batch --out-dir evals/results/d-err
assert_rc "AC7 CI unreadable + stale batch: the CI error comes first (exit 3)" 3
assert_not_contains "AC7 CI unreadable: no replay refusal (ci_check stops the gate first)" "$GERR" "graded differently"
rgf_gh_green

echo "G5R AC8 every line unchanged or unmatched: replay: <n> logs, 0 changed, and the gate goes on as before (baseline, then the preflight)"
mkrepo ac8; A8="$R"
mkout "$A8" d-ok same-ok same-err unm
real "$A8" d-ok
assert_eq "AC8 exactly one replay line" "1" "$(nlines "$(replay_lines)")"
assert_eq "AC8 the line is 'replay: 3 logs, 0 changed' (unmatched and unchanged logs all count)" "replay: 3 logs, 0 changed" "$(replay_lines)"
assert_rc "AC8 the gate went on: the fixture runner refuses the preflight (exit 99), so the gate exits 3" 3
assert_contains "AC8 the later step ran (preflight, after the baseline)" "$GERR" "error: preflight: run-evals.sh cannot start (exit 99)"
assert_not_contains "AC8 no refusal" "$GERR" "graded differently"
assert_eq "AC8 stdout is empty" "" "$GOUT"

echo "G5R AC9a no outcome-*.json in DIR: not one byte more than before (stdout and stderr)"
mkdir -p "$A8/evals/results/d-none" "$A8/evals/results/d-only/x" "$A8/evals/results/d-beh" "$A8/evals/results/d-schema"
printf '{}\n' > "$A8/evals/results/d-only/gate.json"
printf '{"schema":"pb-evals/1","runs":[]}\n' > "$A8/evals/results/d-only/reused-without-s1.json"
# a behaviour file with a .runs directory of a changed log: only OUTCOME runs are replayed
outjson "$A8/evals/results/d-beh/behaviour-s1.json" "pattern-01.with.1|error|$AUTH_ERR"
mkdir -p "$A8/evals/results/d-beh/behaviour-s1.runs"; mklog_ok "$A8/evals/results/d-beh/behaviour-s1.runs/pattern-01.with.1.log"
# an outcome-*.json that is not pb-evals/1 (the used_dir filter) with a .runs directory
printf '{"schema":"other/1","runs":[{"label":"pattern-01.with.1","status":"error","error":"%s"}]}\n' "$AUTH_ERR" > "$A8/evals/results/d-schema/outcome-s1.json"
mkdir -p "$A8/evals/results/d-schema/outcome-s1.runs"; mklog_ok "$A8/evals/results/d-schema/outcome-s1.runs/pattern-01.with.1.log"
for d in d-missing d-none d-only d-beh d-schema; do
  real "$A8" "$d"
  assert_rc "AC9a $d: the gate goes on to the preflight (exit 3, as before)" 3
  assert_eq "AC9a $d: stdout is empty" "" "$GOUT"
  assert_eq "AC9a $d: stderr is the two lines of before (the runner's preflight call and the gate's error), nothing else" "2" "$(nlines "$GERR")"
  assert_contains "AC9a $d: the gate's error is the preflight one" "$GERR" "error: preflight: run-evals.sh cannot start (exit 99)"
  assert_not_contains "AC9a $d: no replay line" "$GERR" "replay:"
  assert_not_contains "AC9a $d: no note line" "$GERR" "note:"
done
gate "$A8" --harness claude --model m1 --dry-run --out-dir evals/results/d-none
REF_RC="$RC"; REF_OUT="$GOUT"; REF_ERR="$GERR"
assert_rc "AC9a --dry-run on a DIR with no outcome file: exit 0" 0
assert_eq "AC9a --dry-run: stderr is empty" "" "$REF_ERR"
assert_contains "AC9a --dry-run: stdout is the dry-run report" "$REF_OUT" "release gate (dry run)"
gate "$A8" --harness claude --model m1 --dry-run --out-dir evals/results/d-missing
assert_eq "AC9a --dry-run on a DIR that does not exist: stderr is empty" "" "$GERR"
gate "$A8" --harness claude --model m1 --dry-run --out-dir evals/results/d-beh
assert_eq "AC9a --dry-run with a behaviour file and a changed .runs log: stderr is empty" "" "$GERR"
assert_rc "AC9a --dry-run with a behaviour file: exit 0" 0

echo "G5R AC9b DIR with an outcome file and no .runs: exactly one note line on stderr, stdout unchanged"
mkdir -p "$A8/evals/results/d-noruns" "$A8/evals/results/d-emptyruns/outcome-s1.runs"
outjson "$A8/evals/results/d-noruns/outcome-s1.json" "pattern-01.with.1|graded|"
outjson "$A8/evals/results/d-emptyruns/outcome-s1.json" "pattern-01.with.1|graded|"
for d in d-noruns d-emptyruns; do
  real "$A8" "$d"
  assert_eq "AC9b $d: exactly one replay line" "1" "$(nlines "$(replay_lines)")"
  assert_eq "AC9b $d: the line is the nothing-to-replay note for DIR" "replay: no stored outcome run logs in $A8/evals/results/$d (nothing to replay)" "$(replay_lines)"
  assert_rc "AC9b $d: the gate goes on (exit 3 at the preflight)" 3
  assert_eq "AC9b $d: stdout is empty (as before)" "" "$GOUT"
  assert_contains "AC9b $d: the preflight error follows" "$GERR" "error: preflight: run-evals.sh cannot start (exit 99)"
  assert_eq "AC9b $d: stderr is the replay line plus the two lines of before" "3" "$(nlines "$GERR")"
done
gate "$A8" --harness claude --model m1 --dry-run --out-dir evals/results/d-noruns
assert_rc "AC9b --dry-run: exit 0" 0
assert_eq "AC9b --dry-run: stdout equals the stdout without any outcome file (out dir name aside)" \
  "$(printf '%s\n' "$REF_OUT" | normd d-none)" "$(printf '%s\n' "$GOUT" | normd d-noruns)"
assert_eq "AC9b --dry-run: the one replay line is on stderr" "replay: no stored outcome run logs in $A8/evals/results/d-noruns (nothing to replay)" "$GERR"

echo "G5R AC9c a replay tool that fails: exit 3 with the tool-failure sentence, not 'graded differently'"
mkrepo ac9c; A9="$R"
mkout "$A9" d-err chg-err
mkstub "$A9" 'echo "replay-graders: cannot read: x" >&2; exit 2'
real "$A9" d-err
assert_rc "AC9c the replay tool exits 2: exit 3" 3
assert_contains "AC9c the message names the tool failure and its exit code" "$GERR" "replay: the replay tool failed (exit 2); fix it, or pass --skip-replay"
assert_not_contains "AC9c it is not counted as a change" "$GERR" "graded differently"
assert_not_contains "AC9c no runner was called" "$OUT" "fixture runner called"
mkstub "$A9" 'exit 7'
real "$A9" d-err
assert_rc "AC9c any other failing exit (7): exit 3" 3
assert_contains "AC9c the exit code is named" "$GERR" "replay: the replay tool failed (exit 7); fix it, or pass --skip-replay"
rm -f "$A9/tools/replay-graders.sh"; recommit "$A9"
real "$A9" d-err
assert_rc "AC9c the replay tool is missing: exit 3" 3
assert_contains "AC9c a missing tool is the tool-failure sentence" "$GERR" "replay: the replay tool failed"
assert_not_contains "AC9c a missing tool is not 'graded differently'" "$GERR" "graded differently"
assert_not_contains "AC9c no runner was called" "$OUT" "fixture runner called"
# control: a healthy replay tool is not reported as failed
mkout "$A9" d-fine same-ok
mkrepo ac9d; A9D="$R"
mkout "$A9D" d-fine same-ok
real "$A9D" d-fine
assert_contains "AC9c control: a healthy replay tool is not reported as failed" "$GERR" "replay: 1 logs, 0 changed"

echo "G5R AC10 --skip-replay: the replay tool is not called, a note goes to stderr, the run goes on even over a changed log"
mkrepo ac10; A10="$R"
mkout "$A10" d-err chg-err
mkstub "$A10" 'exit 0'
rm -f "$STUBLOG"
real "$A10" d-err
calls_ctl="$(calls "$STUBLOG")"
assert_eq "AC10 control: without --skip-replay the replay tool IS called (once, for the one outcome file)" "1" "$calls_ctl"
assert_contains "AC10 control: it is called with --against, the outcome json and the .runs directory" "$(cat "$STUBLOG" 2>/dev/null)" "--against $A10/evals/results/d-err/outcome-s1.json"
assert_contains "AC10 control: and the .runs directory" "$(cat "$STUBLOG" 2>/dev/null)" "$A10/evals/results/d-err/outcome-s1.runs"
rm -f "$STUBLOG"
real "$A10" d-err --skip-replay
assert_eq "AC10 --skip-replay: the replay tool was not called" "0" "$(calls "$STUBLOG")"
assert_eq "AC10 --skip-replay: the note is on stderr, once" "note: --skip-replay: the stored run logs were not replayed" "$(printf '%s\n' "$GERR" | grep '^note: --skip-replay' || true)"
assert_eq "AC10 --skip-replay: no replay: line" "0" "$(printf '%s\n' "$OUT" | grep -c '^replay:' || true)"
assert_eq "AC10 --skip-replay: stdout is empty" "" "$GOUT"
assert_rc "AC10 --skip-replay: the run went on to the preflight (exit 3), no refusal" 3
assert_contains "AC10 --skip-replay: the preflight error follows" "$GERR" "error: preflight: run-evals.sh cannot start (exit 99)"
# the same with the REAL replay tool and a changed log: refused without the flag, goes on with it
mkrepo ac10b; A10B="$R"
mkout "$A10B" d-err chg-err
real "$A10B" d-err
assert_rc "AC10 control: the real replay tool refuses the changed batch (exit 2)" 2
real "$A10B" d-err --skip-replay
assert_rc "AC10 --skip-replay with the real tool and a changed log: not refused (exit 3 at the preflight)" 3
assert_not_contains "AC10 --skip-replay: no 'graded differently'" "$GERR" "graded differently"
assert_no_path "AC10 --skip-replay writes nothing to gate.json (no gate.json at all here)" "$A10B/evals/results/d-err/gate.json"

echo "G5R AC11 --dry-run replays too; --pool-only, --check and --skip-replay do not call the replay tool"
mkrepo ac11; A11="$R"
mkout "$A11" d-err chg-err same-ok
mkout "$A11" d-ok same-ok same-err unm
BEFORE="$(snap "$A11")"
gate "$A11" --harness claude --model m1 --dry-run --out-dir evals/results/d-err
assert_rc "AC11 --dry-run on the stale DIR: exit 2" 2
assert_contains "AC11 the refusal sentence" "$GERR" "replay: 1 run(s) were graded differently than the current graders would grade them ("
assert_contains "AC11 the sentence ends with the way out" "$GERR" "$MSG_STALE_TAIL"
assert_contains "AC11 the label is named" "$GERR" "pattern-01.with.1"
assert_eq "AC11 stdout is empty (the dry-run report is not printed)" "" "$GOUT"
assert_eq "AC11 nothing was created or changed" "$BEFORE" "$(snap "$A11")"
gate "$A11" --harness claude --model m1 --dry-run --json --out-dir evals/results/d-err
assert_rc "AC11 --dry-run --json on the stale DIR: exit 2" 2
assert_eq "AC11 --dry-run --json refused: stdout is empty (no half JSON)" "" "$GOUT"
BEFORE="$(snap "$A11")"
gate "$A11" --harness claude --model m1 --dry-run --out-dir evals/results/d-ok
assert_rc "AC11 --dry-run on the unchanged DIR: exit 0" 0
assert_eq "AC11 the replay line is on stderr" "replay: 3 logs, 0 changed" "$GERR"
OKOUT="$GOUT"
gate "$A11" --harness claude --model m1 --dry-run --out-dir evals/results/d-missing
assert_eq "AC11 stdout is the dry-run report of a DIR with nothing to replay, byte for byte (out dir name aside)" \
  "$(printf '%s\n' "$GOUT" | normd d-missing)" "$(printf '%s\n' "$OKOUT" | normd d-ok)"
gate "$A11" --harness claude --model m1 --dry-run --json --out-dir evals/results/d-ok
assert_rc "AC11 --dry-run --json on the unchanged DIR: exit 0" 0
assert_eq "AC11 --dry-run --json: the replay line is on stderr" "replay: 3 logs, 0 changed" "$GERR"
printf '%s\n' "$GOUT" > "$W/dry.json"
assert_eq "AC11 --dry-run --json: stdout is one JSON object" "object" "$(node -e 'try{const j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log(j&&typeof j==="object"&&!Array.isArray(j)?"object":"other")}catch(e){console.log("not json")}' "$W/dry.json")"
assert_eq "AC11 the dry runs created nothing (tree before and after)" "$BEFORE" "$(snap "$A11")"
# --skip-replay with --dry-run
mkstub "$A11" 'exit 0'
rm -f "$STUBLOG"
gate "$A11" --harness claude --model m1 --dry-run --skip-replay --out-dir evals/results/d-err
assert_rc "AC11 --dry-run --skip-replay on the stale DIR: exit 0" 0
assert_eq "AC11 --dry-run --skip-replay: the replay tool was not called" "0" "$(calls "$STUBLOG")"
assert_contains "AC11 --dry-run --skip-replay: the note is on stderr" "$GERR" "note: --skip-replay: the stored run logs were not replayed"
# the control: the stub is called by --dry-run without the flag
rm -f "$STUBLOG"
gate "$A11" --harness claude --model m1 --dry-run --out-dir evals/results/d-err
assert_eq "AC11 control: --dry-run without --skip-replay calls the replay tool once" "1" "$(calls "$STUBLOG")"
# --pool-only and --check never call it, with or without --skip-replay, and print neither a replay line nor the note
for extra in "" "--skip-replay"; do
  rm -f "$STUBLOG"
  gate "$A11" --harness claude --model m1 --pool-only --out-dir evals/results/d-err $extra
  assert_eq "AC11 --pool-only $extra: the replay tool was not called" "0" "$(calls "$STUBLOG")"
  assert_not_contains "AC11 --pool-only $extra: no replay: line" "$OUT" "replay:"
  assert_not_contains "AC11 --pool-only $extra: no skip note" "$OUT" "--skip-replay: the stored"
  assert_not_contains "AC11 --pool-only $extra: the flag is accepted (not an unknown option)" "$OUT" "unknown option"
  rm -f "$STUBLOG"
  gate "$A11" --check HEAD $extra
  assert_eq "AC11 --check $extra: the replay tool was not called" "0" "$(calls "$STUBLOG")"
  assert_not_contains "AC11 --check $extra: no replay: line" "$OUT" "replay:"
  assert_not_contains "AC11 --check $extra: no skip note" "$OUT" "--skip-replay: the stored"
  assert_not_contains "AC11 --check $extra: the flag is accepted (not an unknown option)" "$OUT" "unknown option"
done

t_summary
