#!/usr/bin/env bash
# Runs an agent harness on the outcome-eval tasks (evals/tasks/<id>/, format in evals/tasks/README.md) and grades each run
# only by the task's hidden tests: every fail_to_pass file must pass and every pass_to_pass file must still pass.
#   run-outcome.sh (--harness claude|codex|opencode | --cmd "COMMAND") [--tasks-dir DIR] [--tasks id1,id2]
#                  [--workroot DIR] [--out FILE] [--timeout SECONDS] [--interactive] [--max-cost USD]
#                  [--model M] [--arm with|without|both] [--repeat K]
# --tasks-dir defaults to evals/tasks next to this script, --tasks to every task directory in it. Each run has the label
# <id>.<arm>.<k> (pattern-02-dimension-text.with.1), in the order task, then k, then arm (with before without). Per run:
# `bash DIR/<id>/setup.sh <workroot>/<label>` builds a fresh repo (no network), <workroot>/<label>.prompt gets prompt.md
# plus a non-interactive note (--interactive: none), and the adapter runs as COMMAND <workdir> <prompt-file> with
# stdout+stderr in <workroot>/<label>.log. The hidden tests never enter the workroot: after the adapter exits, the workdir
# is copied to a runner-private temp dir (outside the workroot and outside the agent's TMPDIR), hidden/ is copied over the
# copy (same relative paths, replacing the agent's files there), each hidden file runs alone from the copy's root
# (node --test F, python3 -m unittest F with stdlib unittest loaded before the repo root joins sys.path, or bash F, under
# `timeout 120` when it exists), and the copy is deleted. After each run (graded or ERROR) the transcript moves to
# ${OUT%.md}.runs/<label>.log, the agent's change against the setup commit is saved as ${OUT%.md}.runs/<label>.diff, and
# the workdir and prompt file leave the workroot, so no later run can read an earlier run's work.
# Checks per graded run: "hidden tests pass", "FAIL_TO_PASS <file>" and "PASS_TO_PASS <file>" per hidden file, "hidden
# tests not seen by the agent" (FAIL when the transcript holds the hidden-test canary: the run is CONTAMINATED and not
# passed), "nothing written outside the workdir", and in the without arm "without arm: no playbook file read and no
# playbook Skill call" (stream-json transcripts; MANUAL for plain text).
# Per graded run, two informational metrics that never change a check or the exit code (v0.28.0): extra_files_changed and
# extra_files (paths of the agent's change, renames as delete + add, outside the task.conf scope and outside tests/, .agents/,
# node_modules/, .gitignore, package-lock.json; null without scope; the list holds the first 50, C-sorted), tests_weakened
# and tests_weakened_files (visible test files under tests/ as setup.sh left them, counted again after the adapter, before
# grading). ERROR and SKIPPED runs carry them as null.
# --model, --arm, --repeat, --max-cost and --timeout work as in evals/run-evals.sh (its header has the details), and so
# does its leak probe (--harness claude with the without arm: exit 3 when claude still sees the playbook block); the
# presets, model flags, arm settings files, the pb-evals/1 JSON and its statistics come from evals/lib-harness.sh. Every
# run gets its own temp PLAYBOOK_HOME (with arm: a copy of the playbook conf without feedback_repo; without arm: empty)
# and its own TMPDIR, removed after the run; HOME stays the real one. --cmd adapters get PB_EVAL_MODEL and, with --arm or
# --repeat, PB_EVAL_ARM and PB_EVAL_SETTINGS.
# An adapter that exits non-zero, times out or shows an auth failure makes the run ERROR: it is not graded and no hidden
# file is copied. ERROR and SKIPPED runs never count in n.
# Writes a markdown results file (default evals/results/<YYYY-MM-DD>-outcome-<harness or custom>-<HHMMSS>.md) with one
# line per arm (pass@1 over all graded runs, pass^K = share of complete tasks whose every run passed) and one row per
# (task, arm), and ${OUT%.md}.json (schema pb-evals/1, scenario = task id) for tools/eval-delta.sh.
# The workroot must not be inside the playbook repository or inside --tasks-dir; <workroot>/<label> is only cleared when
# the workroot is runner-owned (marker .pb-eval-workroot, written when the runner creates it or finds it empty).
# Exit: 0 every graded run passed, 1 any FAIL (also CONTAMINATED, STRAY or an isolation FAIL), 2 usage, unknown task id
#       or a workroot the runner does not own or may not use, 3 environment (node, git, python3, a setup.sh that fails),
#       4 any ERROR. Bash 3.2 compatible. Needs node >= 18 and git.
set -u
EVALS="$(cd "$(dirname "$0")" && pwd -P)"
. "$EVALS/../scripts/lib.sh"
. "$EVALS/lib-harness.sh"
REPO="$(cd "$EVALS/.." && pwd -P)"

usage() { sed -n '2,/^set -u/p' "$0" | sed '/^set -u/d' | sed 's/^# \{0,1\}//' >&2; exit 2; }

CANARY="PB-HIDDEN-""CANARY:"   # split so this file is not itself a canary hit
HP="hidden tests pass"; SEEN="hidden tests not seen by the agent"; STRAYC="nothing written outside the workdir"
ISO="without arm: no playbook file read and no playbook Skill call"

# runner temp dirs of the running task and the pid of its adapter, for the traps
CUR_HOME=""; CUR_TMP=""; CUR_GRADE=""; CUR_IDX=""; CUR_BASE=""; SET_DIR=""; ND_FILE=""; ADPID=""
# rm_dir DIR: remove a runner temp dir (never following a link), also one the agent made unreadable
rm_dir() {
  [ -n "$1" ] || return 0
  rm -rf "$1" 2>/dev/null
  if [ -e "$1" ] && [ ! -L "$1" ]; then chmod -R u+rwx "$1" 2>/dev/null; rm -rf "$1" 2>/dev/null; fi
  return 0
}
cleanup() {
  rm_dir "$CUR_HOME"; rm_dir "$CUR_TMP"; rm_dir "$CUR_GRADE"; rm_dir "$CUR_IDX"; rm_dir "$CUR_BASE"; rm_dir "$SET_DIR"
  if [ -n "$ND_FILE" ]; then rm -f "$ND_FILE"; fi
  CUR_HOME=""; CUR_TMP=""; CUR_GRADE=""; CUR_IDX=""; CUR_BASE=""; SET_DIR=""; ND_FILE=""
}
stop_adapter() { if [ -n "$ADPID" ]; then kill "$ADPID" 2>/dev/null; wait "$ADPID" 2>/dev/null; ADPID=""; fi; }
trap cleanup EXIT
trap 'stop_adapter; cleanup; trap - EXIT; exit 130' INT
trap 'stop_adapter; cleanup; trap - EXIT; exit 143' TERM

HARNESS=""; CMD=""; TASKS_DIR="$EVALS/tasks"; SELECT=""; WORKROOT=""; OUT=""; TIMEOUT=""; INTERACTIVE=0
MAX_COST=""; MAX_COST_SET=0; MODEL=""; MODEL_SET=0; ARM_OPT=""; ARM_SET=0; REPEAT_OPT=""; REPEAT_SET=0
# where the conf copy is read from: the caller's playbook home (PLAYBOOK_HOME, else HOME), before any run replaces it
SRC_CONF="$(pb_home)/.agents/playbook.conf"
while [ $# -gt 0 ]; do
  case "$1" in
    --harness|--cmd|--tasks-dir|--tasks|--workroot|--out|--timeout|--max-cost|--model|--arm|--repeat)
      [ $# -ge 2 ] || pb_die "$1 needs a value" 2 ;;
  esac
  case "$1" in
    --harness)   HARNESS="$2"; shift ;;
    --cmd)       CMD="$2"; shift ;;
    --tasks-dir) TASKS_DIR="$2"; shift ;;
    --tasks)     SELECT="$2"; shift ;;
    --workroot)  WORKROOT="$2"; shift ;;
    --out)       OUT="$2"; shift ;;
    --timeout)   TIMEOUT="$2"; shift ;;
    --max-cost)  MAX_COST="$2"; MAX_COST_SET=1; shift ;;
    --model)     MODEL="$2"; MODEL_SET=1; shift ;;
    --arm)       ARM_OPT="$2"; ARM_SET=1; shift ;;
    --repeat)    REPEAT_OPT="$2"; REPEAT_SET=1; shift ;;
    --interactive) INTERACTIVE=1 ;;
    -h|--help)   usage ;;
    *) printf 'error: unknown option: %s\n' "$1" >&2; usage ;;
  esac
  shift
done

# the adapter runs as: bash -c "$ADAPTER" adapter <workdir> <prompt-file>; the presets live in evals/lib-harness.sh
if [ -n "$HARNESS" ] && [ -n "$CMD" ]; then pb_die "use either --harness or --cmd, not both" 2; fi
if [ -z "$HARNESS" ]; then
  [ -n "$CMD" ] || { printf 'error: --harness or --cmd is required\n' >&2; usage; }
  LABEL="custom"; ADAPTER="$CMD \"\$1\" \"\$2\""
else
  ADAPTER="$(pbh_preset_cmd "$HARNESS")" || pb_die "unknown harness: $HARNESS (use opencode, claude, codex or --cmd)" 2
  LABEL="$HARNESS"
fi
if [ -n "$TIMEOUT" ]; then
  case "$TIMEOUT" in "" | *[!0-9]*) pb_die "--timeout needs whole seconds, got: $TIMEOUT" 2 ;; esac
fi
if [ "$MAX_COST_SET" = 1 ]; then
  case "$MAX_COST" in "" | *[!0-9.]* | *. | *.*.*) pb_die "--max-cost needs a positive decimal amount in USD, got: $MAX_COST" 2 ;; esac
  case "$MAX_COST" in *[1-9]*) ;; *) pb_die "--max-cost needs a positive decimal amount in USD, got: $MAX_COST" 2 ;; esac
fi
if [ "$MODEL_SET" = 1 ]; then
  case "$MODEL" in "" | *[!A-Za-z0-9._:/@-]*) pb_die "--model needs a model name of letters, digits and . _ : / @ - only, got: $MODEL" 2 ;; esac
fi
ARMS="with"
if [ "$ARM_SET" = 1 ]; then
  case "$ARM_OPT" in
    with) ARMS="with" ;; without) ARMS="without" ;; both) ARMS="with without" ;;
    *) pb_die "--arm needs with, without or both, got: $ARM_OPT" 2 ;;
  esac
fi
REPEAT=1
if [ "$REPEAT_SET" = 1 ]; then
  case "$REPEAT_OPT" in
    [1-9] | [1-9][0-9]) REPEAT="$REPEAT_OPT" ;;
    *) pb_die "--repeat needs a whole number from 1 to 99, got: $REPEAT_OPT" 2 ;;
  esac
fi
# SET_MODE: --arm or --repeat given (both arms get a settings file, the prompt note is arm-neutral)
SET_MODE=0
if [ "$ARM_SET" = 1 ] || [ "$REPEAT_SET" = 1 ]; then SET_MODE=1; fi
if [ -n "$HARNESS" ] && [ "$SET_MODE" = 1 ] && [ "$MODEL_SET" = 0 ]; then
  pb_die "--model is required for a real harness run with --arm or --repeat" 2
fi
case " $ARMS " in
  *" without "*)
    if [ -n "$HARNESS" ]; then
      why="$(pbh_arm_supported "$HARNESS" without)" || pb_die "the without arm is not supported for $HARNESS: $why; use --arm with, or --cmd with your own isolation" 2
    fi ;;
esac
if [ -n "$HARNESS" ] && [ "$MODEL_SET" = 0 ]; then
  printf '%s\n' 'WARNING model not pinned (--model missing): the results say "CLI default"; tools/eval-delta.sh will not use them' >&2
fi
if [ -n "$HARNESS" ] && { [ "$MODEL_SET" = 1 ] || [ "$SET_MODE" = 1 ]; }; then
  ADAPTER="$ADAPTER \"\${@:3}\""   # the model flag and --settings, given per run after <workdir> <prompt-file>
fi
# the note after prompt.md; with --arm/--repeat it names nothing the without arm lacks, so both arms get the same prompt
if [ "$SET_MODE" = 1 ]; then NONINT="(Non-interactive run: nobody will answer questions here. Decide without asking and say what you assumed.)"
else NONINT="(Non-interactive run: nobody will answer questions here. Use the playbook's non-interactive rule.)"; fi

# the tasks: --tasks in the given order, else every directory of the tasks dir
[ -d "$TASKS_DIR" ] || pb_die "no tasks directory: $TASKS_DIR" 2
TASKS_DIR="$(cd "$TASKS_DIR" && pwd -P)"
# tconf ID KEY -> value of KEY in the task.conf of ID (empty when absent), CR removed
tconf() { local v; v="$(pb_conf_read "$TASKS_DIR/$1/task.conf" "$2")" || v=""; printf '%s' "$v" | tr -d '\r'; }
if [ -n "$SELECT" ]; then IDS="$(printf '%s\n' "$SELECT" | tr ',' '\n' | sed '/^$/d')"
else IDS="$(cd "$TASKS_DIR" && find . -mindepth 1 -maxdepth 1 -type d | sed 's#^\./##' | LC_ALL=C sort)"; fi
[ -n "$IDS" ] || pb_die "no task in $TASKS_DIR" 2
NEED_PY=0
for id in $IDS; do
  case "$id" in */* | . | ..) pb_die "not a task id: $id" 2 ;; esac
  { [ -f "$TASKS_DIR/$id/task.conf" ] && [ -f "$TASKS_DIR/$id/setup.sh" ]; } || pb_die "no such task: $id (in $TASKS_DIR)" 2
  case "$(tconf "$id" language)" in
    node | bash) ;;
    python3) NEED_PY=1 ;;
    *) pb_die "task $id: unknown language in task.conf (node, python3 or bash)" 2 ;;
  esac
done

# under PATH DIR -> 0 when PATH is DIR or below it
under() { case "$1" in "$2" | "$2"/*) return 0 ;; esac; return 1; }
# abs_of PATH -> the absolute physical path of PATH, also when its last components do not exist yet
abs_of() {
  local p="$1" rest=""
  case "$p" in /*) ;; *) p="$PWD/$p" ;; esac
  while [ ! -d "$p" ]; do
    case "${p##*/}" in . | ..) return 1 ;; esac
    rest="/${p##*/}$rest"; p="$(dirname "$p")"
  done
  printf '%s%s\n' "$(cd "$p" && pwd -P | sed 's#/$##')" "$rest"
}
# the agent must not be able to reach the hidden tests from its workdir: no workroot inside the repo or the tasks dir
if [ -n "$WORKROOT" ]; then
  WABS="$(abs_of "$WORKROOT")" || pb_die "--workroot must not end in . or .. below a missing directory: $WORKROOT" 2
  if under "$WABS" "$REPO"; then pb_die "refusing --workroot $WORKROOT: it is inside the playbook repository ($REPO), where the agent could read the hidden tests" 2; fi
  if under "$WABS" "$TASKS_DIR"; then pb_die "refusing --workroot $WORKROOT: it is inside --tasks-dir ($TASKS_DIR), where the agent could read the hidden tests" 2; fi
fi

command -v node >/dev/null 2>&1 || pb_die "node (>= 18) is required" 3
command -v git  >/dev/null 2>&1 || pb_die "git is required" 3
if [ "$NEED_PY" = 1 ] && ! python3 -c 'import sys' >/dev/null 2>&1; then pb_die "python3 is required by a selected task (python3 -c 'import sys' failed)" 3; fi
USE_TIMEOUT=0
if [ -n "$TIMEOUT" ]; then
  if command -v timeout >/dev/null 2>&1; then USE_TIMEOUT=1
  else printf "note: 'timeout' not found; running without --timeout %s\n" "$TIMEOUT" >&2; fi
fi
GTIMEOUT=""   # DECISION[D8]: each hidden file runs under a 120 s limit when `timeout` exists
if command -v timeout >/dev/null 2>&1; then GTIMEOUT="timeout 120"; fi

# the without arm cannot remove a block that Claude Code loads from a user rules file or an ancestor of the workroot
anc_refuse() { local why; why="$(pbh_without_refusal "$1" "$HOME")" || pb_die "the without arm cannot run: $why" 2; }

NEW_ROOT=0   # 1 when the runner creates the workroot or finds it empty
if [ -n "$WORKROOT" ]; then
  case " $ARMS " in *" without "*) anc_refuse "$WABS" ;; esac
  if [ ! -e "$WORKROOT" ]; then NEW_ROOT=1
  elif [ -d "$WORKROOT" ] && [ -z "$(ls -A "$WORKROOT")" ]; then NEW_ROOT=1; fi
  mkdir -p "$WORKROOT" || pb_die "cannot create $WORKROOT" 3
else
  WORKROOT="$(mktemp -d "${TMPDIR:-/tmp}/pb-outcome.XXXXXX")" || pb_die "mktemp failed" 3; NEW_ROOT=1
  case " $ARMS " in *" without "*) anc_refuse "$(cd "$WORKROOT" && pwd -P)" ;; esac
fi
WORKROOT="$(cd "$WORKROOT" && pwd -P)"
# the runs, in order: task, then k, then arm
RUNS=""
for id in $IDS; do
  k=1
  while [ "$k" -le "$REPEAT" ]; do
    for a in $ARMS; do RUNS="$RUNS $id:$a:$k"; done
    k=$((k + 1))
  done
done
if [ "$NEW_ROOT" = 1 ]; then : > "$WORKROOT/.pb-eval-workroot" || pb_die "cannot write $WORKROOT/.pb-eval-workroot" 3; fi
for r in $RUNS; do
  a="${r#*:}"; l="${r%%:*}.${a%%:*}.${a#*:}"
  if { [ -e "$WORKROOT/$l" ] || [ -e "$WORKROOT/$l.log" ] || [ -e "$WORKROOT/$l.prompt" ]; } && [ ! -f "$WORKROOT/.pb-eval-workroot" ]; then
    pb_die "refusing to delete $WORKROOT/$l: the workroot is not runner-owned (.pb-eval-workroot); move it or pick another --workroot" 2
  fi
done
NOW="$(date '+%Y-%m-%d %H%M%S')"; STARTED="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
case "$HARNESS" in
  "") ISO_MODE=adapter ;;
  claude) if [ "$SET_MODE" = 1 ]; then ISO_MODE=claude-settings; else ISO_MODE=none; fi ;;
  *) ISO_MODE=none ;;
esac
# the playbook skill names the isolation check looks for: the runner repo's skills and the playbook-* skills of HOME
ISO_NAMES=""
for f in "$REPO"/skills/*/SKILL.md "$HOME"/.claude/skills/playbook-*; do
  { [ -e "$f" ] || [ -L "$f" ]; } || continue
  case "$f" in */SKILL.md) f="${f%/SKILL.md}" ;; esac
  ISO_NAMES="$ISO_NAMES ${f##*/}"
done
[ -n "$OUT" ] || OUT="$EVALS/results/${NOW% *}-outcome-$LABEL-${NOW#* }.md"
mkdir -p "$(dirname "$OUT")" || pb_die "cannot create $(dirname "$OUT")" 3
# the settings file of each arm, in a runner temp dir outside the workroot and outside PLAYBOOK_HOME (removed on exit)
DROPPED=0
if [ "$SET_MODE" = 1 ]; then
  SET_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pb-evset.XXXXXX")" || pb_die "cannot create a temp dir for the settings files" 3
  for a in $ARMS; do
    n="$(pbh_arm_settings "$SET_DIR/$a.json" "$a" "$HOME" "$REPO")" || pb_die "cannot write the $a settings file" 3
    [ "$a" = without ] && DROPPED="$n"
  done
fi
# the leak probe, as in evals/run-evals.sh (--harness claude with the without arm): one claude call with the without settings,
# before any run and any workdir, asks whether the heading of the always-on block is in its context. YES: exit 3, nothing
# runs. The md records "leak probe: none", "inconclusive" (the isolation check of each run still applies) or "n/a" (--cmd).
LEAK_MD=""
case " $ARMS " in
  *" without "*)
    if [ "$HARNESS" = claude ]; then
      PBH_HEAD="$(sed -n 's/^## //p' "$REPO/AGENTS.global.md" 2>/dev/null | head -n 1)"
      [ -n "$PBH_HEAD" ] || pb_die "cannot read the heading of AGENTS.global.md for the leak probe" 3
      PDIR="$(mktemp -d "$WORKROOT/.pb-leak-probe.XXXXXX")" || pb_die "cannot create a temp dir for the leak probe" 3
      mkdir -p "$SET_DIR/probe-home" && pbh_leak_prompt "$PBH_HEAD" > "$SET_DIR/probe.prompt" || pb_die "cannot write the leak probe prompt" 3
      printf '== leak probe: asking claude whether the without arm still sees the playbook block\n' >&2
      (
        PLAYBOOK_HOME="$SET_DIR/probe-home"; export PLAYBOOK_HOME
        unset PB_EVAL_ARM PB_EVAL_MODEL PB_EVAL_SETTINGS
        cd "$PDIR" || exit 1
        set -- adapter "$PDIR" "$SET_DIR/probe.prompt"
        while IFS= read -r w; do [ -n "$w" ] && set -- "$@" "$w"; done <<EOF
$(pbh_model_args "$HARNESS" "$MODEL")
EOF
        set -- "$@" --settings "$SET_DIR/without.json"
        if [ "$USE_TIMEOUT" = 1 ]; then exec timeout "$TIMEOUT" bash -c "$ADAPTER" "$@" </dev/null >"$SET_DIR/probe.log" 2>&1
        else exec bash -c "$ADAPTER" "$@" </dev/null >"$SET_DIR/probe.log" 2>&1; fi
      )
      prc=$?
      LEAK="$(pbh_probe_answer "$SET_DIR/probe.log")"
      rm_dir "$PDIR"
      if [ "$LEAK" = YES ]; then
        pb_die "leak probe: the without arm still sees the playbook block (claude says the heading \"$PBH_HEAD\" is in its context); check claudeMdExcludes and the without settings before running the without arm" 3
      elif [ "$prc" = 0 ] && [ "$LEAK" = NO ]; then LEAK_MD="none"
      else
        LEAK_MD="inconclusive"
        printf 'WARNING leak probe inconclusive (exit %s, answer %s); the isolation check of each without run still applies\n' "$prc" "$LEAK" >&2
      fi
    else LEAK_MD="n/a"; fi ;;
esac
# each run's transcript and diff, kept outside the workroot (next to --out)
EV="${OUT%.md}.runs"
mkdir -p "$EV" || pb_die "cannot create $EV" 3

# Per-run state: ID, ARM, K, RL (label), TD (task dir), WD, PF, LOG
ANY_FAIL=0; ANY_ERROR=0; COST_SUM=""; NOTE_UNKNOWN=0; ND_RUNS=""; S_CHECKS=""; NOTES_J=""
record() { # RESULT CHECK
  printf '%s %s %s\n' "$RL" "$1" "$2"
  S_CHECKS="$S_CHECKS${S_CHECKS:+,}{\"name\":$(pbh_json_str "$2"),\"key\":$(pbh_json_str "$(pbh_check_key "$2")"),\"result\":\"$1\"}"
  if [ "$1" = FAIL ]; then ANY_FAIL=1; fi
}
note() { NOTES_J="$NOTES_J${NOTES_J:+,}$(pbh_json_str "$1")"; }
# run_json STATUS ERROR-TEXT COST SECONDS -> one NDJSON line of the run (pb-evals/1 run fields)
run_json() {
  local err=null cst=null sec=null ft=null ps=null dr=0
  [ -n "$2" ] && err="$(pbh_json_str "$2")"
  case "$3" in "" | *[!0-9.eE+-]*) ;; *) cst="$3" ;; esac
  case "$4" in "" | *[!0-9]*) ;; *) sec="$4" ;; esac
  [ -n "$FTREE" ] && ft="$(pbh_json_str "$FTREE")"
  [ -n "$PSHA" ] && ps="$(pbh_json_str "$PSHA")"
  [ "$ARM" = without ] && dr="$DROPPED"
  ND_RUNS="$ND_RUNS$(printf '{"scenario":%s,"arm":"%s","k":%s,"label":%s,"status":"%s","error":%s,"isolation":"%s","fixture_tree":%s,"prompt_sha":%s,"cost_usd":%s,"seconds":%s,"notes":[%s],"dropped_user_lines":%s,"checks":[%s],"extra_files_changed":%s,"extra_files":%s,"tests_weakened":%s,"tests_weakened_files":%s}' \
    "$(pbh_json_str "$ID")" "$ARM" "$K" "$(pbh_json_str "$RL")" "$1" "$err" "$ISO_MODE" "$ft" "$ps" "$cst" "$sec" "$NOTES_J" "$dr" "$S_CHECKS" \
    "$M_EXTRA" "$M_XFILES" "$M_TW" "$M_TWFILES")
"
}
# json_list MAX -> the non-empty lines of stdin as a JSON array of strings, at most MAX of them (0: all)
json_list() {
  local l o="" n=0
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    n=$((n + 1))
    [ "$1" = 0 ] || [ "$n" -le "$1" ] || break
    o="$o${o:+,}$(pbh_json_str "$l")"
  done
  printf '[%s]' "$o"
}
# load_transcript: one pass of evals/transcript.js over $LOG
load_transcript() {
  T_json=0; T_result_ok=0; T_cost=""
  local k v
  while IFS='=' read -r k v; do
    case "$k" in json) T_json="$v" ;; result_ok) T_result_ok="$v" ;; cost) T_cost="$v" ;; esac
  done <<EOF
$(node "$EVALS/transcript.js" "$LOG" 2>/dev/null)
EOF
}
# auth_lines -> the log lines to search for auth errors (an api_retry the run recovered from is not one)
auth_lines() { if [ "$T_result_ok" = 1 ]; then grep -v '"subtype":"api_retry"' "$LOG"; else cat "$LOG"; fi; }
# unlink_on_path ROOT REL -> removes every symbolic link among ROOT/REL and its parent dirs below ROOT, so a copy to
# ROOT/REL cannot be redirected outside ROOT
unlink_on_path() {
  local p="$1" rest="$2" c
  while [ -n "$rest" ]; do
    c="${rest%%/*}"
    case "$rest" in */*) rest="${rest#*/}" ;; *) rest="" ;; esac
    p="$p/$c"
    if [ -L "$p" ]; then rm -f "$p"; fi
  done
}
# run_hidden GRADEDIR FILE -> exit status of the hidden test FILE run alone from the root of the grading copy. Python: -I
# keeps the repo root off sys.path until the stdlib unittest is loaded, so a unittest/ or unittest.py the agent left in the
# repo cannot stand in for the runner; then the root is added so the test can import the repo's modules.
run_hidden() {
  # shellcheck disable=SC2086   # GTIMEOUT is "timeout 120" or empty
  ( cd "$1/repo" || exit 1
    TMPDIR="$1/tmp"; PYTHONDONTWRITEBYTECODE=1; export TMPDIR PYTHONDONTWRITEBYTECODE
    case "$TLANG" in
      node) exec $GTIMEOUT node --test "$2" ;;
      python3) exec $GTIMEOUT python3 -I -c 'import sys, unittest; sys.path.insert(0, ""); unittest.main(module=None, argv=["python3 -m unittest"] + sys.argv[1:])' "$2" ;;
      bash) exec $GTIMEOUT bash "$2" ;;
    esac
    exit 126 ) </dev/null >/dev/null 2>&1
}
# grade -> copies the workdir to a runner-private dir, copies hidden/ over it, records one check per hidden file;
# returns 0 when every fail_to_pass and pass_to_pass file passed. The copy is deleted before it returns.
grade() {
  local g rel f rc=0
  g="$(mktemp -d "${TMPDIR:-/tmp}/pb-outgrade.XXXXXX")" || pb_die "cannot create a grading dir" 3
  CUR_GRADE="$g"
  { mkdir -p "$g/tmp" && cp -R "$WD" "$g/repo"; } || pb_die "cannot copy $WD for grading" 3
  while IFS= read -r rel; do
    rel="${rel#./}"
    [ -n "$rel" ] || continue
    unlink_on_path "$g/repo" "$rel"
    { mkdir -p "$g/repo/$(dirname "$rel")" && rm -rf "$g/repo/$rel" && cp "$TD/hidden/$rel" "$g/repo/$rel"; } ||
      pb_die "cannot copy hidden/$rel of $ID for grading" 3
  done <<EOF
$(cd "$TD/hidden" && find . -type f | LC_ALL=C sort)
EOF
  for f in $(tconf "$ID" fail_to_pass); do
    if run_hidden "$g" "$f"; then record PASS "FAIL_TO_PASS $f"; else record FAIL "FAIL_TO_PASS $f"; rc=1; fi
  done
  for f in $(tconf "$ID" pass_to_pass); do
    if run_hidden "$g" "$f"; then record PASS "PASS_TO_PASS $f"; else record FAIL "PASS_TO_PASS $f"; rc=1; fi
  done
  rm_dir "$g"; CUR_GRADE=""
  return "$rc"
}
# save_diff -> $EV/$RL.diff: the agent's change against the setup commit $SHEAD, new files included (a temp index, so the
# agent's own index is not used; no external diff or textconv command of the repo config runs). From the same index:
# DIFF_NAMES, the changed paths (renames as delete + add) one per line, and DIFF_OK=1 when they could be listed.
save_diff() {
  local ix
  DIFF_NAMES=""; DIFF_OK=0
  ix="$(mktemp -d "${TMPDIR:-/tmp}/pb-evidx.XXXXXX")" || pb_die "cannot create a temp dir for the diff of $RL" 3
  CUR_IDX="$ix"
  if ! ( cd "$WD" && export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_INDEX_FILE="$ix/index" &&
         git -c core.fsmonitor=false add -A . >/dev/null 2>&1 &&
         git -c core.fsmonitor=false diff --cached --no-ext-diff --no-textconv --binary "$SHEAD" ) > "$EV/$RL.diff" 2>/dev/null; then
    printf 'note: no diff for %s (git add/diff failed in the workdir)\n' "$RL" >&2
    printf '# no diff: git add/diff failed in the workdir\n' > "$EV/$RL.diff"
  elif ( cd "$WD" && export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_INDEX_FILE="$ix/index" &&
         git -c core.fsmonitor=false diff --cached --no-renames --name-only -z "$SHEAD" ) > "$ix/names" 2>/dev/null; then
    DIFF_NAMES="$(tr '\000' '\n' < "$ix/names")"; DIFF_OK=1
  fi
  rm_dir "$ix"; CUR_IDX=""
}
# drop_run -> the run's workdir and prompt file leave the workroot (its transcript and diff are already in $EV)
drop_run() { rm_dir "$WD"; rm -f "$PF"; rm_dir "$CUR_BASE"; CUR_BASE=""; }
spent_of() { printf '%s\n' $COST_SUM | awk '{ s += $1 } END { printf "%.6g", s }'; }
estimate_of() { printf '%s\n' $COST_SUM | awk '{ if ($1 + 0 > m) m = $1 + 0 } END { printf "%.6g", m }'; }

for RUN in $RUNS; do
  ID="${RUN%%:*}"; ARM="${RUN#*:}"; K="${ARM#*:}"; ARM="${ARM%%:*}"; RL="$ID.$ARM.$K"
  TD="$TASKS_DIR/$ID"; TLANG="$(tconf "$ID" language)"
  FTREE=""; PSHA=""; S_CHECKS=""; NOTES_J=""; M_EXTRA=null; M_XFILES=null; M_TW=null; M_TWFILES=null
  note "language=$TLANG"; note "source=$(tconf "$ID" source)"; note "expected_weight=$(tconf "$ID" expected_weight)"
  note "tasks_dir=$TASKS_DIR"
  if [ "$MAX_COST_SET" = 1 ] && [ -n "$COST_SUM" ]; then
    # as run-evals: reached = spent >= USD; else spent + the largest single cost so far >= USD
    skip_why=""
    if printf '%s\n' $COST_SUM | awk -v max="$MAX_COST" '{ s += $1 } END { exit !(s + 0.000000001 >= max + 0) }'; then
      skip_why="budget reached (spent $(spent_of) of $MAX_COST)"
    elif printf '%s\n' $COST_SUM | awk -v max="$MAX_COST" '{ s += $1; if ($1 + 0 > m) m = $1 + 0 } END { exit !(s + m + 0.000000001 >= max + 0) }'; then
      skip_why="budget: spent $(spent_of) + estimate $(estimate_of) >= cap $MAX_COST"
    fi
    if [ -n "$skip_why" ]; then
      printf '%s SKIPPED %s\n' "$RL" "$skip_why"
      note "SKIPPED $skip_why"
      run_json skipped "" "" ""
      continue
    fi
  fi
  WD="$WORKROOT/$RL"; PF="$WORKROOT/$RL.prompt"; LOG="$WORKROOT/$RL.log"
  rm -rf "$WD" "$PF" "$LOG" || pb_die "cannot remove $WD" 3
  # the user's git config (hooks, signing, autocrlf) must not change the task repo
  if ! sout="$(cd "$WORKROOT" && GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null bash "$TD/setup.sh" "$WD" 2>&1)"; then
    printf '%s\n' "$sout" >&2
    pb_die "the setup.sh of task $ID failed (target $WD)" 3
  fi
  if [ "$INTERACTIVE" = 1 ]; then printf '%s\n' "$(cat "$TD/prompt.md")" > "$PF"
  else printf '%s\n%s\n' "$(cat "$TD/prompt.md")" "$NONINT" > "$PF"; fi
  SHEAD="$(git -C "$WD" rev-parse HEAD 2>/dev/null)"
  FTREE="$(git -C "$WD" rev-parse 'HEAD^{tree}' 2>/dev/null)"; PSHA="$(git hash-object "$PF" 2>/dev/null)"
  # DECISION[D6]: the visible tests as setup.sh left them, kept outside the workroot for tests_weakened
  CUR_BASE="$(mktemp -d "${TMPDIR:-/tmp}/pb-evbase.XXXXXX")" || pb_die "cannot create a temp dir for the visible tests of $RL" 3
  if [ -d "$WD/tests" ]; then cp -R "$WD/tests" "$CUR_BASE/tests" || pb_die "cannot copy the visible tests of $RL" 3; fi
  SC_HOME="$(mktemp -d "${TMPDIR:-/tmp}/pb-evhome.XXXXXX")" || pb_die "cannot create a temp playbook home" 3
  CUR_HOME="$SC_HOME"
  mkdir -p "$SC_HOME/.agents" || pb_die "cannot create $SC_HOME/.agents" 3
  SC_TMP="$(mktemp -d "${TMPDIR:-/tmp}/pb-evtmp.XXXXXX")" || pb_die "cannot create a temp dir for the adapter" 3
  CUR_TMP="$SC_TMP"
  if [ "$ARM" = with ] && [ -f "$SRC_CONF" ]; then   # the without arm keeps PLAYBOOK_HOME empty
    grep -v '^[[:space:]]*feedback_repo[[:space:]]*=' "$SRC_CONF" > "$SC_HOME/.agents/playbook.conf"
    [ -f "$SC_HOME/.agents/playbook.conf" ] || pb_die "cannot copy the playbook conf for $RL" 3
  fi
  SETF=""; if [ "$SET_MODE" = 1 ]; then SETF="$SET_DIR/$ARM.json"; fi
  BEFORE="$(ls -A "$WORKROOT" | LC_ALL=C sort)"
  printf '== %s: running the adapter in %s\n' "$RL" "$WD" >&2
  (
    TMPDIR="$SC_TMP"; PLAYBOOK_HOME="$SC_HOME"; export TMPDIR PLAYBOOK_HOME
    cd "$WD" || exit 1
    # PB_EVAL_* reach --cmd adapters only; a preset gets the model flag and --settings as arguments
    unset PB_EVAL_ARM PB_EVAL_MODEL PB_EVAL_SETTINGS
    set -- adapter "$WD" "$PF"
    if [ -z "$HARNESS" ]; then
      if [ "$MODEL_SET" = 1 ]; then PB_EVAL_MODEL="$MODEL"; export PB_EVAL_MODEL; fi
      if [ -n "$SETF" ]; then PB_EVAL_ARM="$ARM"; PB_EVAL_SETTINGS="$SETF"; export PB_EVAL_ARM PB_EVAL_SETTINGS; fi
    else
      while IFS= read -r w; do [ -n "$w" ] && set -- "$@" "$w"; done <<EOF
$(pbh_model_args "$HARNESS" "$MODEL")
EOF
      if [ "$HARNESS" = claude ] && [ -n "$SETF" ]; then set -- "$@" --settings "$SETF"; fi
    fi
    if [ "$USE_TIMEOUT" = 1 ]; then exec timeout "$TIMEOUT" bash -c "$ADAPTER" "$@" </dev/null >"$LOG" 2>&1
    else exec bash -c "$ADAPTER" "$@" </dev/null >"$LOG" 2>&1; fi
  ) &
  ADPID=$!; T0=$SECONDS
  wait "$ADPID"
  rc=$?; ADPID=""; SECS=$((SECONDS - T0))
  # anything new in the workroot besides this run's own entries was written outside the workdir
  STRAY="$(printf '%s\n' "$(ls -A "$WORKROOT" | LC_ALL=C sort)" | LC_ALL=C comm -23 - <(printf '%s\n' "$BEFORE") |
    grep -vxF -e "$RL" -e "$RL.log" -e "$RL.prompt" | tr '\n' ' ')"
  mv -f "$LOG" "$EV/$RL.log" || pb_die "cannot move $LOG to $EV" 3
  LOG="$EV/$RL.log"
  save_diff
  rm_dir "$SC_TMP"; CUR_TMP=""
  rm_dir "$SC_HOME"; CUR_HOME=""
  if [ "$ARM" = without ] && [ "$DROPPED" -gt 0 ]; then
    DNOTE="NOTE the without arm also drops $DROPPED non-playbook lines of ~/.claude/CLAUDE.md"
    printf '%s %s\n' "$RL" "$DNOTE"; note "$DNOTE"
  fi
  load_transcript
  herr=""
  if [ "$USE_TIMEOUT" = 1 ] && [ "$rc" -eq 124 ]; then herr="timed out after ${TIMEOUT}s"
  elif [ "$rc" -ne 0 ]; then herr="adapter exited $rc"
  elif auth_lines | grep -qiE 'invalid x-api-key|invalid api key|unauthori[sz]ed|authentication failed|authentication_failed|not logged in|(status|code|http|error)[^0-9A-Za-z]{0,20}401([^0-9]|$)|(^|[^0-9])401 +unauthori'; then
    herr="auth or harness error in the transcript"
  fi
  c=""
  if [ -n "$T_cost" ]; then c="$T_cost"; printf '%s COST %s\n' "$RL" "$c"; COST_SUM="$COST_SUM $c"
  elif [ "$MAX_COST_SET" = 1 ] && [ "$NOTE_UNKNOWN" = 0 ]; then
    NOTE_UNKNOWN=1; printf 'note: cost unknown for %s; the budget counts known costs only\n' "$RL"
  fi
  if [ -n "$herr" ]; then   # not graded: no hidden file is copied anywhere
    printf '%s ERROR harness: %s (see %s)\n' "$RL" "$herr" "$LOG"
    ANY_ERROR=1
    run_json error "$herr" "$c" "$SECS"
    drop_run
    continue
  fi
  # the hygiene metrics (DECISION[D2]: informational, never a check), from the workdir before grading
  SCOPE="$(tconf "$ID" scope)"
  if [ -n "$SCOPE" ]; then
    if [ "$DIFF_OK" = 1 ]; then
      XF="$(printf '%s\n' "$DIFF_NAMES" | pbh_scope_extra "$SCOPE")"
      if [ -z "$XF" ]; then M_EXTRA=0; else M_EXTRA="$(printf '%s\n' "$XF" | wc -l | tr -d ' ')"; fi
      M_XFILES="$(printf '%s\n' "$XF" | json_list 50)"
    else
      note "extra_files_changed unknown: git could not list the changed paths"
    fi
  fi
  TWO="$(pbh_tests_weakened "$CUR_BASE" "$WD")"
  M_TW="$(printf '%s\n' "$TWO" | sed -n 1p)"
  M_TWFILES="$(printf '%s\n' "$TWO" | sed 1d | json_list 0)"
  CONT=0
  if LC_ALL=C grep -qF "$CANARY" "$LOG" 2>/dev/null; then CONT=1; fi
  if grade && [ "$CONT" = 0 ]; then record PASS "$HP"; else record FAIL "$HP"; fi
  if [ "$CONT" = 0 ]; then record PASS "$SEEN"
  else
    record FAIL "$SEEN"
    printf '%s CONTAMINATED the transcript shows hidden test content; the run is not passed\n' "$RL"
  fi
  if [ -z "${STRAY// /}" ]; then record PASS "$STRAYC"
  else
    record FAIL "$STRAYC"
    printf '%s NOTE new in the workroot: %s\n' "$RL" "${STRAY% }"; note "STRAY new in the workroot: ${STRAY% }"
  fi
  if [ "$ARM" = without ]; then
    # shellcheck disable=SC2086   # ISO_NAMES is a list of skill names
    if [ "$T_json" = 1 ]; then record "$(pbh_iso_check "$LOG" "$HOME" "$WD" "${SC_HOME:-}" "${SET_DIR:-}" $ISO_NAMES)" "$ISO"
    else record MANUAL "$ISO"; fi
  fi
  run_json graded "" "$c" "$SECS"
  drop_run
done

# the JSON results: top-level fields, then one line per run, through pbh_results_json
JF="${OUT%.md}.json"
jnum() { awk -v v="$1" 'BEGIN { printf "%.10g", v + 0 }'; }
PCOMMIT="$(git -C "$REPO" rev-parse HEAD 2>/dev/null)" && PCOMMIT="$(pbh_json_str "$PCOMMIT")" || PCOMMIT=null
PVER=null; [ -f "$REPO/VERSION" ] && PVER="$(pbh_json_str "$(tr -d ' \r\n' < "$REPO/VERSION")")"
JMODEL=null; [ "$MODEL_SET" = 1 ] && JMODEL="$(pbh_json_str "$MODEL")"
JMAX=null; [ "$MAX_COST_SET" = 1 ] && JMAX="$(jnum "$MAX_COST")"
JARMS=""; for a in $ARMS; do JARMS="$JARMS${JARMS:+,}\"$a\""; done
JINT=false; [ "$INTERACTIVE" = 1 ] && JINT=true
ND_FILE="$(mktemp "${TMPDIR:-/tmp}/pb-evnd.XXXXXX")" || pb_die "mktemp failed" 3
{ printf '{"playbook_commit":%s,"playbook_version":%s,"harness":%s,"model":%s,"arms":[%s],"repeat":%s,"max_cost":%s,"interactive":%s,"started":"%s","workroot":%s}\n' \
    "$PCOMMIT" "$PVER" "$(pbh_json_str "$LABEL")" "$JMODEL" "$JARMS" "$REPEAT" "$JMAX" "$JINT" "$STARTED" "$(pbh_json_str "$WORKROOT")"
  printf '%s' "$ND_RUNS"
} > "$ND_FILE" && pbh_results_json "$ND_FILE" "$JF"
jrc=$?; rm -f "$ND_FILE"; ND_FILE=""
[ "$jrc" = 0 ] || pb_die "cannot write $JF" 3
# md_body -> the arm lines, the table per (task, arm) and the run list, read from the summary pbh_stats wrote
md_body() {
  node -e '
const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
const HP = process.argv[2], SEEN = process.argv[3], ISO = process.argv[4], K = j.repeat || 1, S = j.summary || [], R = j.runs || [];
const f = (v, d) => (v === null || v === undefined) ? "-" : String(Number(v.toFixed(d)));
const cell = s => String(s).replace(/\|/g, "\\|");
const res = (r, n) => ((r.checks || []).find(c => c.name === n) || {}).result;
const nv = v => (v === null || v === undefined) ? "-" : String(v);
let o = "## pass@1 and pass^" + K + " per arm (check `" + HP + "`)\n\n";
for (const arm of j.arms || []) {
  let n = 0, p = 0, c = 0, a = 0;
  for (const e of S) if (e.arm === arm && e.key === HP) { n += e.n; p += e.passes; if (e.complete) { c++; if (e.pass_all) a++; } }
  o += "- " + arm + ": pass@1 " + (n ? (p / n).toFixed(2) : "-") + " (" + p + "/" + n + " runs), pass^" + K + " " + (c ? (a / c).toFixed(2) : "-") + " (" + a + " of " + c + " complete tasks)\n";
}
o += "\n| Task | Arm | pass@1 | pass^K | n | Cost mean ± sd | Time mean ± sd |\n|---|---|---|---|---|---|---|\n";
for (const e of S) if (e.key === null) {
  const h = S.find(x => x.scenario === e.scenario && x.arm === e.arm && x.key === HP) || {};
  const pk = h.complete ? (h.pass_all ? "yes" : "no") : "-";
  o += "| " + cell(e.scenario) + " | " + e.arm + " | " + (h.n ? h.pass_at_1.toFixed(2) : "-") + " | " + pk + " | " + (h.n || 0) +
    (e.errors ? " (+" + e.errors + " error)" : "") + (e.skipped ? " (+" + e.skipped + " skipped)" : "") + " | " +
    f(e.cost_mean, 4) + " ± " + f(e.cost_sd, 4) + " | " + f(e.seconds_mean, 1) + " ± " + f(e.seconds_sd, 1) + " |\n";
}
const flags = [];
for (const r of R) {
  if (res(r, SEEN) === "FAIL") flags.push("- CONTAMINATED: " + r.label + ": the transcript shows hidden test content; the run is not passed.");
  if (r.arm === "without" && res(r, ISO) === "FAIL") flags.push("- Invalid: the without arm result of " + r.scenario + " (run " + r.label + " failed the isolation check).");
}
if (flags.length) o += "\n" + flags.join("\n") + "\n";
o += "\n## Scope and visible tests per arm\n\n";
for (const arm of j.arms || []) {
  const g = R.filter(r => r.arm === arm && r.status === "graded");
  const ms = k => { const v = g.map(r => r[k]).filter(x => typeof x === "number");
    return [v.length ? (v.reduce((s, x) => s + x, 0) / v.length).toFixed(2) : "-", v.filter(x => x > 0).length, v.length]; };
  const e = ms("extra_files_changed"), t = ms("tests_weakened");
  o += "- " + arm + ": extra_files_changed mean " + e[0] + " (runs > 0: " + e[1] + " of " + e[2] + "), tests_weakened mean " + t[0] +
    " (runs > 0: " + t[1] + " of " + t[2] + ")\n";
}
o += "\n## Runs\n\n| Run | Status | Hidden tests | Failed checks | Extra files | Tests weakened | Cost (USD) | Seconds |\n|---|---|---|---|---|---|---|---|\n";
for (const r of R) {
  const failed = (r.checks || []).filter(c => c.result === "FAIL").map(c => cell(c.name)).join("; ");
  o += "| " + cell(r.label) + " | " + r.status + (r.error ? ": " + cell(r.error) : "") + " | " + (res(r, HP) || "-") + " | " + (failed || "-") + " | " +
    nv(r.extra_files_changed) + " | " + nv(r.tests_weakened) + " | " +
    (r.cost_usd === null ? "-" : r.cost_usd) + " | " + (r.seconds === null ? "-" : r.seconds) + " |\n";
}
process.stdout.write(o);' "$JF" "$HP" "$SEEN" "$ISO"
}
{
  printf '# Outcome evals: %s, %s\n\n' "$LABEL" "$(date +%Y-%m-%d)"
  printf 'Workroot: `%s`\n' "$WORKROOT"
  printf 'Tasks: `%s`\n\n' "$TASKS_DIR"
  if [ "$MODEL_SET" = 1 ]; then printf 'Model: %s\n' "$MODEL"; else printf 'Model: not pinned (CLI default)\n'; fi
  if [ "$ARM_SET" = 1 ]; then printf 'Arms: %s\n' "$(printf '%s' "$ARMS" | sed 's/ /, /g')"; fi
  if [ "$REPEAT_SET" = 1 ]; then printf 'Repeat: %s\n' "$REPEAT"; fi
  if [ -n "$LEAK_MD" ]; then printf 'Without arm, leak probe: %s\n' "$LEAK_MD"; fi
  printf '\n'
  [ -n "$TIMEOUT" ] && [ "$USE_TIMEOUT" = 0 ] && printf "Note: 'timeout' was not available; ran without a time limit.\n\n"
  md_body || pb_die "cannot write the summary of $OUT" 3
  if [ -n "$COST_SUM" ]; then
    printf '\nTotal cost (USD, runs that reported it): %s\n' "$(printf '%s\n' $COST_SUM | awk '{ s += $1 } END { printf "%.2f", s }')"
  fi
} > "$OUT" || pb_die "cannot write $OUT" 3
printf 'results: %s\n' "$OUT"
printf 'json: %s\n' "$JF"
[ "$ANY_ERROR" = 1 ] && exit 4
exit "$ANY_FAIL"
