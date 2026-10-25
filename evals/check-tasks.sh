#!/usr/bin/env bash
# Offline self-check of the outcome-eval tasks (evals/tasks/<id>/, format in evals/tasks/README.md).
#   check-tasks.sh [--tasks-dir DIR] [--tasks id1,id2]
# DIR defaults to evals/tasks next to this script; --tasks defaults to every task directory in DIR.
# Per task, nothing is written into DIR (every repo is built in a private temp dir, removed on exit):
#   - setup.sh passes bash -n, and no file of the task outside hidden/ carries the hidden-test canary;
#   - setup.sh succeeds twice into fresh directories and both repos have the same HEAD commit;
#   - unsolved (hidden/ copied over the first repo): every fail_to_pass file fails and every pass_to_pass file passes;
#   - solved (solution.patch applied with git apply to the second repo, then hidden/ copied over it): every hidden file
#     passes. A task without a solution.patch file skips the apply (allowed only when fail_to_pass is empty); an empty
#     solution.patch is BROKEN.
# Each hidden file runs alone from the repo root with the task's language command: node --test F, python3 -m unittest F,
# bash F (under `timeout 120` when the timeout command exists).
# DECISION[D11]: a language counts as present only when a real call works (python3 -c 'import sys'; the Windows Store
# python3 stub fails it); a task whose language is missing prints "<id> SELF-CHECK SKIPPED (no <language>)".
# Prints one line per task: "<id> SELF-CHECK OK" or "<id> SELF-CHECK BROKEN <reason>".
# Exit: 0 no task BROKEN, 1 any task BROKEN, 2 usage (unknown option, missing DIR or task id), 3 git missing.
# Bash 3.2 compatible.
set -u
EVALS="$(cd "$(dirname "$0")" && pwd -P)"
. "$EVALS/../scripts/lib.sh"

usage() { sed -n '2,3p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

TASKS_DIR="$EVALS/tasks"
SELECT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tasks-dir) [ $# -ge 2 ] || usage; TASKS_DIR="$2"; shift 2 ;;
    --tasks) [ $# -ge 2 ] || usage; SELECT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) printf 'check-tasks: unknown option %s\n' "$1" >&2; usage ;;
  esac
done
[ -d "$TASKS_DIR" ] || pb_die "no tasks directory: $TASKS_DIR" 2
TASKS_DIR="$(cd "$TASKS_DIR" && pwd -P)"
command -v git >/dev/null 2>&1 || pb_die "git is required" 3

# the user's git config (hooks, signing, autocrlf) must not change the task repos
GIT_CONFIG_NOSYSTEM=1; GIT_CONFIG_GLOBAL=/dev/null; export GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL
PYTHONDONTWRITEBYTECODE=1; export PYTHONDONTWRITEBYTECODE
CANARY="PB-HIDDEN-""CANARY"   # split so this file is not itself a canary hit
TIMEOUT=""
if command -v timeout >/dev/null 2>&1; then TIMEOUT="timeout 120"; fi   # DECISION[D8]

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pb-check-tasks.XXXXXX")" || pb_die "cannot create a temp dir" 3
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

HAVE_NODE=0; HAVE_PY=0
if node -e '' >/dev/null 2>&1; then HAVE_NODE=1; fi
if python3 -c 'import sys' >/dev/null 2>&1; then HAVE_PY=1; fi

# conf TASKDIR KEY -> value of KEY in task.conf (empty when absent), CR removed
conf() {
  local v
  v="$(pb_conf_read "$1/task.conf" "$2")" || v=""
  printf '%s' "$v" | tr -d '\r'
}

# run_hidden LANG REPO FILE -> exit status of the hidden test FILE run alone from the REPO root
run_hidden() {
  local lang="$1" repo="$2" f="$3"
  [ -f "$repo/$f" ] || return 127
  case "$lang" in
    node) (cd "$repo" && $TIMEOUT node --test "$f") >/dev/null 2>&1 ;;
    python3) (cd "$repo" && $TIMEOUT python3 -m unittest "$f") >/dev/null 2>&1 ;;
    bash) (cd "$repo" && $TIMEOUT bash "$f") >/dev/null 2>&1 ;;
    *) return 126 ;;
  esac
}

# check_task DIR -> prints the reason when BROKEN (return 1), "SKIPPED (...)" (return 2), nothing when OK (return 0)
check_task() {
  local d="$1" id lang f2p p2p w r1 r2 h1 h2 f leaked
  id="$(basename "$d")"
  lang="$(conf "$d" language)"; f2p="$(conf "$d" fail_to_pass)"; p2p="$(conf "$d" pass_to_pass)"
  [ -f "$d/task.conf" ] || { echo "no task.conf"; return 1; }
  [ "$(conf "$d" id)" = "$id" ] || { echo "task.conf id is not the directory name"; return 1; }
  [ -f "$d/setup.sh" ] || { echo "no setup.sh"; return 1; }
  [ -n "$p2p$f2p" ] || { echo "task.conf lists no hidden test"; return 1; }
  bash -n "$d/setup.sh" >/dev/null 2>&1 || { echo "setup.sh fails bash -n"; return 1; }
  leaked="$(cd "$d" && find . -type f ! -path './hidden/*' -exec grep -lF -- "$CANARY" {} + 2>/dev/null | tr '\n' ' ')"
  [ -z "$leaked" ] || { echo "hidden-test canary outside hidden/: $leaked"; return 1; }
  if [ -f "$d/solution.patch" ] && [ ! -s "$d/solution.patch" ]; then echo "solution.patch is empty"; return 1; fi
  if [ -n "$f2p" ] && [ ! -f "$d/solution.patch" ]; then echo "fail_to_pass is set but there is no solution.patch"; return 1; fi
  for f in $f2p $p2p; do
    [ -f "$d/hidden/$f" ] || { echo "hidden/$f is missing"; return 1; }
  done
  case "$lang" in
    node) [ "$HAVE_NODE" = 1 ] || { echo "SKIPPED (no node)"; return 2; } ;;
    python3) [ "$HAVE_PY" = 1 ] || { echo "SKIPPED (no python3)"; return 2; } ;;
    bash) ;;
    *) echo "unknown language [$lang]"; return 1 ;;
  esac
  w="$WORK/$id"; mkdir -p "$w"
  r1="$w/unsolved"; r2="$w/solved"
  (cd "$w" && bash "$d/setup.sh" "$r1") >"$w/setup1.log" 2>&1 || { echo "setup.sh failed (first run)"; return 1; }
  (cd "$w" && bash "$d/setup.sh" "$r2") >"$w/setup2.log" 2>&1 || { echo "setup.sh failed (second run)"; return 1; }
  h1="$(git -C "$r1" rev-parse HEAD 2>/dev/null)"; h2="$(git -C "$r2" rev-parse HEAD 2>/dev/null)"
  [ -n "$h1" ] || { echo "setup.sh made no commit"; return 1; }
  [ "$h1" = "$h2" ] || { echo "setup.sh is not deterministic (HEAD $h1 then $h2)"; return 1; }
  cp -R "$d/hidden/." "$r1/" || { echo "cannot copy hidden/ into the repo"; return 1; }
  for f in $f2p; do
    if run_hidden "$lang" "$r1" "$f"; then echo "unsolved: fail_to_pass $f already passes"; return 1; fi
  done
  for f in $p2p; do
    run_hidden "$lang" "$r1" "$f" || { echo "unsolved: pass_to_pass $f fails"; return 1; }
  done
  if [ -f "$d/solution.patch" ]; then
    (cd "$r2" && git apply "$d/solution.patch") >"$w/apply.log" 2>&1 || { echo "solution.patch does not apply"; return 1; }
  fi
  cp -R "$d/hidden/." "$r2/" || { echo "cannot copy hidden/ into the repo"; return 1; }
  for f in $f2p; do
    run_hidden "$lang" "$r2" "$f" || { echo "solved: fail_to_pass $f still fails"; return 1; }
  done
  for f in $p2p; do
    run_hidden "$lang" "$r2" "$f" || { echo "solved: pass_to_pass $f fails after solution.patch"; return 1; }
  done
  rm -rf "$w"
  return 0
}

# the task list: --tasks in the given order, else every directory of TASKS_DIR
ids=""
if [ -n "$SELECT" ]; then
  ids="$(printf '%s\n' "$SELECT" | tr ',' '\n' | sed '/^$/d')"
  for id in $ids; do
    case "$id" in */*|.|..) pb_die "not a task id: $id" 2 ;; esac
    [ -d "$TASKS_DIR/$id" ] || pb_die "no such task: $id (in $TASKS_DIR)" 2
  done
else
  ids="$(cd "$TASKS_DIR" && find . -mindepth 1 -maxdepth 1 -type d | sed 's#^\./##' | LC_ALL=C sort)"
fi

broken=0
for id in $ids; do
  reason="$(check_task "$TASKS_DIR/$id")"; rc=$?
  case "$rc" in
    0) printf '%s SELF-CHECK OK\n' "$id" ;;
    2) printf '%s SELF-CHECK %s\n' "$id" "$reason" ;;
    *) printf '%s SELF-CHECK BROKEN %s\n' "$id" "${reason:-unknown reason}"; broken=$((broken + 1)) ;;
  esac
done
[ "$broken" = 0 ] || exit 1
exit 0
