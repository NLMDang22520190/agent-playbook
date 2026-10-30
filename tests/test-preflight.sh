#!/usr/bin/env bash
# Tests for the --preflight mode of evals/run-evals.sh and evals/run-outcome.sh (v0.33.0 slice S2, AC7/AC7'): a no-cost check of what the
# runner would refuse with exit 3 for the selection on its command line, so the release gate can ask both runners before it starts
# the first paid run (queue P1: python3 was the WindowsApps stub on Git Bash; ~100 paid runs, then exit 3).
# Interface defined here (the implementer adds it): `<runner> <the usual selection> --preflight` exits 0 with no output when the runner
# could start, exits 3 with the reason on stderr when it could not (node, git, the harness CLI of --harness on PATH, and, for
# run-outcome.sh, a python3 that really runs when a selected task has language=python3). It starts no run, makes no workdir, writes no
# --out file, leaves --workroot alone and never calls the harness CLI.
# PATH is built per case from symlinks (the real node, git, python3 and a fake claude), so a "missing" tool is really missing.
. "$(dirname "$0")/lib.sh"
RUNEV="$PB_ROOT/evals/run-evals.sh"
RUNOC="$PB_ROOT/evals/run-outcome.sh"
BASH_BIN="$(command -v bash)"
REAL_NODE="$(command -v node 2>/dev/null)"; REAL_GIT="$(command -v git 2>/dev/null)"; REAL_PY="$(command -v python3 2>/dev/null)"
[ -n "$REAL_NODE" ] && [ -n "$REAL_GIT" ] || { t_skip 1 "node or git missing"; t_summary; exit $?; }

# BASE: every executable of the usual bin dirs except the tools under test, so the runners find sed, awk, mktemp, ...
BASE="$(mk_tmp)"
for d in /usr/local/bin /usr/bin /bin; do
  [ -d "$d" ] || continue
  for f in "$d"/*; do
    n="${f##*/}"
    case "$n" in node | nodejs | git | python3 | python | claude | codex | opencode) continue ;; esac
    [ -x "$f" ] && [ ! -e "$BASE/$n" ] && ln -s "$f" "$BASE/$n" 2>/dev/null
  done
done
if [ ! -e "$BASE/sed" ] || [ ! -e "$BASE/bash" ]; then t_skip 1 "cannot build a PATH of symlinks here"; t_summary; exit $?; fi

CLOG="$(mk_tmp)/harness.calls"; : > "$CLOG"
# mkpath TOOL... -> a dir with just those tools (node, git, python3 = the real one, pystub = a python3 that exits 49 like the
# WindowsApps stub, claude/codex/opencode = fakes that record any call in $CLOG); prints the dir
mkpath() {
  local d t; d="$(mk_tmp)"
  for t in "$@"; do
    case "$t" in
      node) ln -s "$REAL_NODE" "$d/node" ;;
      git) ln -s "$REAL_GIT" "$d/git" ;;
      python3) [ -z "$REAL_PY" ] || ln -s "$REAL_PY" "$d/python3" ;;
      pystub) printf '#!/bin/sh\necho "Python was not found; run without arguments to install from the Microsoft Store" >&2\nexit 49\n' > "$d/python3"; chmod +x "$d/python3" ;;
      claude | codex | opencode) printf '#!/bin/sh\necho "%s $*" >> %s\nexit 0\n' "$t" "'$CLOG'" > "$d/$t"; chmod +x "$d/$t" ;;
    esac
  done
  printf '%s' "$d"
}
HM="$(mk_tmp)"   # a HOME with no playbook conf
# pre RUNNER P-DIR ARGS... -> OUT, RC of `RUNNER ARGS... --preflight` with PATH = P-DIR:BASE
pre() {
  local r="$1" p="$2"; shift 2
  run env -u PLAYBOOK_HOME HOME="$HM" PATH="$p:$BASE" "$BASH_BIN" "$r" "$@" --preflight
}

# a tasks dir with a bash task and a python3 task (complete enough for the runner's own task checks)
TD="$(mk_tmp)"
mk_task() { # ID LANGUAGE
  mkdir -p "$TD/$1/hidden/tests"
  printf 'id=%s\nlanguage=%s\nsource=oss:fixture\nexpected_weight=Lite\nfail_to_pass=tests/x.f2p.sh\npass_to_pass=\n' "$1" "$2" > "$TD/$1/task.conf"
  printf 'Fix it.\n' > "$TD/$1/prompt.md"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TD/$1/setup.sh"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$TD/$1/hidden/tests/x.f2p.sh"
}
mk_task t-bash bash
mk_task t-py python3
OD="$(mk_tmp)"

echo "AC7 run-outcome.sh --preflight: ready -> exit 0 and silent"
P="$(mkpath node git python3)"
pre "$RUNOC" "$P" --tasks-dir "$TD" --tasks t-bash,t-py --cmd "bash /x/adapter.sh" --arm both --repeat 5 --out "$OD/o1.md"
assert_rc "AC7 node, git and a working python3 -> exit 0" 0
assert_eq "AC7 ... and it prints nothing" "" "$OUT"
assert_no_path "AC7 --preflight writes no --out file" "$OD/o1.md"
assert_no_path "AC7 --preflight writes no evidence dir next to --out" "$OD/o1.runs"

echo "AC7 run-outcome.sh --preflight: a python3 that exits non-zero (the WindowsApps stub) is refused when a selected task needs python3"
P="$(mkpath node git pystub)"
pre "$RUNOC" "$P" --tasks-dir "$TD" --tasks t-bash,t-py --cmd "bash /x/adapter.sh" --arm both --repeat 5 --out "$OD/o2.md"
assert_rc "AC7 stub python3 + a python3 task selected -> exit 3" 3
assert_contains "AC7 ... the reason names python3" "$OUT" "python3"
assert_no_path "AC7 ... no --out file" "$OD/o2.md"
pre "$RUNOC" "$P" --tasks-dir "$TD" --tasks t-bash --cmd "bash /x/adapter.sh" --arm both --repeat 5 --out "$OD/o3.md"
assert_rc "AC7 stub python3 but only a bash task selected -> exit 0 (python3 is not needed)" 0
assert_eq "AC7 ... silent" "" "$OUT"
P="$(mkpath node git)"
pre "$RUNOC" "$P" --tasks-dir "$TD" --tasks t-py --cmd "bash /x/adapter.sh" --out "$OD/o4.md"
assert_rc "AC7 no python3 at all + a python3 task selected -> exit 3" 3
assert_contains "AC7 ... the reason names python3" "$OUT" "python3"

echo "AC7 run-outcome.sh --preflight: node, git"
P="$(mkpath git python3)"
pre "$RUNOC" "$P" --tasks-dir "$TD" --tasks t-bash --cmd "bash /x/adapter.sh" --out "$OD/o5.md"
assert_rc "AC7 no node -> exit 3" 3
assert_contains "AC7 ... the reason names node" "$OUT" "node"
P="$(mkpath node python3)"
pre "$RUNOC" "$P" --tasks-dir "$TD" --tasks t-bash --cmd "bash /x/adapter.sh" --out "$OD/o6.md"
assert_rc "AC7 no git -> exit 3" 3
assert_contains "AC7 ... the reason names git" "$OUT" "git"

echo "AC7 run-outcome.sh --preflight: the harness CLI of --harness must be on PATH, and is never called"
for h in claude codex opencode; do
  P="$(mkpath node git python3)"
  pre "$RUNOC" "$P" --tasks-dir "$TD" --tasks t-bash --harness "$h" --model m1 --arm both --repeat 5 --out "$OD/o7.md"
  assert_rc "AC7 --harness $h without $h on PATH -> exit 3" 3
  assert_contains "AC7 ... the reason names $h" "$OUT" "$h"
  P="$(mkpath node git python3 "$h")"; : > "$CLOG"
  pre "$RUNOC" "$P" --tasks-dir "$TD" --tasks t-bash --harness "$h" --model m1 --arm both --repeat 5 --out "$OD/o8.md"
  assert_rc "AC7 --harness $h with $h on PATH -> exit 0" 0
  assert_eq "AC7 ... silent" "" "$OUT"
  assert_eq "AC7 ... the $h CLI was never called (a preflight costs nothing)" "0" "$(wc -l < "$CLOG" | tr -d ' ')"
done
assert_no_path "AC7 the preflights wrote no --out file" "$OD/o8.md"

echo "AC7 run-outcome.sh --preflight leaves --workroot alone"
WRK="$(mk_tmp)"; : > "$WRK/.pb-eval-workroot"; printf 'mine\n' > "$WRK/keep.txt"
P="$(mkpath node git python3)"
pre "$RUNOC" "$P" --tasks-dir "$TD" --tasks t-bash,t-py --cmd "bash /x/adapter.sh" --workroot "$WRK" --out "$OD/o9.md"
assert_rc "AC7 with --workroot -> exit 0" 0
assert_eq "AC7 the workroot holds what it held (no <label> dir, no log)" ".pb-eval-workroot keep.txt" "$(ls -A "$WRK" | tr '\n' ' ' | sed 's/ $//')"

echo "AC7 run-evals.sh --preflight: ready -> exit 0 and silent"
P="$(mkpath node git)"
pre "$RUNEV" "$P" --cmd "bash /x/adapter.sh" --arm both --repeat 5 --scenarios E2,E3 --out "$OD/e1.md"
assert_rc "AC7 node and git, --cmd -> exit 0" 0
assert_eq "AC7 ... it prints nothing" "" "$OUT"
assert_no_path "AC7 --preflight writes no --out file" "$OD/e1.md"
assert_no_path "AC7 --preflight writes no evidence dir next to --out" "$OD/e1.runs"
P="$(mkpath node git pystub)"
pre "$RUNEV" "$P" --cmd "bash /x/adapter.sh" --arm both --repeat 5 --scenarios E2,E3 --out "$OD/e1b.md"
assert_rc "AC7 run-evals.sh needs no python3: a stub python3 -> exit 0" 0

echo "AC7 run-evals.sh --preflight: node, git"
P="$(mkpath git)"
pre "$RUNEV" "$P" --cmd "bash /x/adapter.sh" --arm both --repeat 5 --scenarios E2,E3 --out "$OD/e2.md"
assert_rc "AC7 no node -> exit 3" 3
assert_contains "AC7 ... the reason names node" "$OUT" "node"
P="$(mkpath node)"
pre "$RUNEV" "$P" --cmd "bash /x/adapter.sh" --arm both --repeat 5 --scenarios E2,E3 --out "$OD/e3.md"
assert_rc "AC7 no git -> exit 3" 3
assert_contains "AC7 ... the reason names git" "$OUT" "git"

echo "AC7 run-evals.sh --preflight: the harness CLI of --harness must be on PATH, and is never called"
for h in claude codex opencode; do
  P="$(mkpath node git)"
  pre "$RUNEV" "$P" --harness "$h" --model m1 --arm both --repeat 5 --scenarios E2,E3 --out "$OD/e4.md"
  assert_rc "AC7 --harness $h without $h on PATH -> exit 3" 3
  assert_contains "AC7 ... the reason names $h" "$OUT" "$h"
  P="$(mkpath node git "$h")"; : > "$CLOG"
  pre "$RUNEV" "$P" --harness "$h" --model m1 --arm both --repeat 5 --scenarios E2,E3 --out "$OD/e5.md"
  assert_rc "AC7 --harness $h with $h on PATH -> exit 0" 0
  assert_eq "AC7 ... silent" "" "$OUT"
  assert_eq "AC7 ... the $h CLI was never called (a preflight costs nothing)" "0" "$(wc -l < "$CLOG" | tr -d ' ')"
done
P="$(mkpath node git)"
pre "$RUNEV" "$P" --cmd "bash /x/adapter.sh" --arm both --repeat 5 --scenarios E2,E3 --out "$OD/e6.md"
assert_rc "AC7 --cmd needs no harness CLI on PATH -> exit 0" 0
assert_no_path "AC7 the preflights wrote no --out file" "$OD/e5.md"

t_summary
