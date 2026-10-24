#!/usr/bin/env bash
# Tests for pb_scope_classify's temp file and the scope re-hash guard (v0.24.30 lane G, slice G2; .agents/handoff/01-spec.md AC6.4 and AC6.1).
#   AC6.4 a  normal and failure returns leave no pb-scope.* file (status as before)           [passes before and after: characterization]
#   AC6.4 b  a GROUP INT / TERM while the classify awk runs: no pb-scope.* file left, and the callers end as before
#            (tdd-step scope_cmd_diff 130/143, own_notes 130, role-gate 130/143, a main-shell caller; the commit-list classify
#            at tdd-step.sh:664 is 130/143 under bash 5 and 3 under bash 3.2, D8)                [RED before the change: the file is left]
#   AC6.4 c  a caller's EXIT trap is the same after a call in its main shell                  [characterization]
#   AC6.4 d  the template ${TMPDIR:-/tmp}/pb-scope.XXXXXX and exactly one mktemp per call     [characterization]
#   AC6.1    the scope re-hash guard of role-gate check: a scope file that changes between the two hashes is refused (cmp shim)
#            [characterization: passes today; mutant N3 (`true ||` on the guard) fails it]
# Signal rows (P5 recipe, D12): the step runs as a `set -m` job with stdin from /dev/null, so it leads its own process group; the
# test verifies `kill -0 -- -PID` before an awk shim may signal that group at the Nth classify call (a go-file holds the group's id);
# a platform without job control (Git Bash on Windows) skips those rows with t_skip and the same count. The shim never signals the
# runner's group: it signals the verified group id only. Shared setup: role-gate-fixture.sh and tdd-step-fixture.sh.
# The temp-file check runs once the job's whole process group has ended (bounded wait, `kill -0 -- -PGID`), not when the leader
# exits: the classify subshell is its own process and runs its handler after the leader may already be gone (Windows CI).
# INT rows need a deliverable SIGINT. A signal ignored on entry to a non-interactive shell cannot be trapped or reset (POSIX, bash),
# and children inherit it: bash 3.2 runs tests/run-all.sh's `( ... ) &` suite wrappers with INT and QUIT ignored (macOS CI), and the
# Windows CI step starts with INT ignored. A run-time probe (a `set -m` job, the gs_run shape, that sends itself INT and survives)
# then skips the INT rows with t_skip and the same count; the TERM rows still run.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/role-gate-fixture.sh"
. "$(dirname "$0")/tdd-step-fixture.sh"
unset PB_ALLOW_MODE_CHANGE
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
TAB="$(printf '\t')"

GS="$(mk_tmp)"; mkdir -p "$GS/sh" "$GS/shf" "$GS/shm" "$GS/shw" "$GS/shc" "$GS/tmp" "$GS/lt" "$GS/wf"
# The real tools are resolved ONCE here, before any shim dir is on PATH, as absolute paths outside the shim dirs. A shim never runs
# `command -v` itself: in Git Bash that found the shim again and recursed without end (the cmp shim, v0.24.30). Every shim also
# refuses to run when PB_SHIM_DEPTH is already set ("shim recursion" on stderr, exit 99), so a loop is one failed call, not a tree.
REAL_AWK="$(command -v awk)"; REAL_MKTEMP="$(command -v mktemp)"; REAL_CMP="$(command -v cmp)"
for _rt in "$REAL_AWK" "$REAL_MKTEMP" "$REAL_CMP"; do
  case "$_rt" in
    /*) case "$_rt" in "$GS"/*) echo "FAIL: a real tool resolved inside the shim dir: $_rt" >&2; exit 3 ;; esac ;;
    *) echo "FAIL: a real tool did not resolve to an absolute path: [$_rt]" >&2; exit 3 ;;
  esac
done
SHIM_GUARD='if [ -n "${PB_SHIM_DEPTH:-}" ]; then echo "shim recursion" >&2; exit 99; fi
export PB_SHIM_DEPTH=1'

# ---- PATH shims (bash scripts; the awk and mktemp shims act on pb_scope_classify's own calls only) ----
# sh/awk: counts the classify awk calls (SCF set); when PB_GSIG is set, at call PB_SIG_AT it waits for the go-file and signals the
# verified process group of the job (`kill -SIG -- -PGID`), then exits; without a go-file it just runs the real awk
cat > "$GS/sh/awk" <<EOF
#!/usr/bin/env bash
$SHIM_GUARD
if [ -n "\${SCF:-}" ]; then
  n=\$(cat "$GS/cnt" 2>/dev/null || echo 0); n=\$((n + 1)); echo "\$n" > "$GS/cnt"
  if [ -n "\${PB_GLOG:-}" ]; then
    in="\$(cat)"; echo "\$n: \$(printf '%s' "\$in" | tr '\n' ',')" >> "$GS/calls"
    printf '%s\n' "\$in" | "$REAL_AWK" "\$@"; exit \$?
  fi
  if [ -n "\${PB_GSIG:-}" ] && [ "\$n" = "\${PB_SIG_AT:-1}" ]; then
    i=0; while [ ! -s "$GS/go" ] && [ ! -e "$GS/nogo" ] && [ \$i -lt 100 ]; do sleep 0.1; i=\$((i + 1)); done
    if [ -s "$GS/go" ]; then
      read -r pg < "$GS/go"
      case "\$pg" in ''|*[!0-9]*|0|1) exit 9 ;; esac
      : > "$GS/fired"; kill -"\$PB_GSIG" -- -"\$pg"; sleep 2; exit 0
    fi
  fi
fi
exec "$REAL_AWK" "\$@"
EOF
# shf/awk: the classify awk fails (exit 2)
cat > "$GS/shf/awk" <<EOF
#!/usr/bin/env bash
$SHIM_GUARD
if [ -n "\${SCF:-}" ]; then exit 2; fi
exec "$REAL_AWK" "\$@"
EOF
# shm/mktemp: logs its argument, then makes the file in $GS/lt (so a missing TMPDIR still leaves nothing outside the test dir)
cat > "$GS/shm/mktemp" <<EOF
#!/usr/bin/env bash
$SHIM_GUARD
printf '%s\n' "\$*" >> "$GS/mklog"
case "\$1" in */pb-scope.XXXXXX) exec "$REAL_MKTEMP" "$GS/lt/pb-scope.XXXXXX" ;; esac
exec "$REAL_MKTEMP" "\$@"
EOF
# shw/mktemp: makes a DIRECTORY named pb-scope.d, so the redirect into it fails (the write-failed return)
cat > "$GS/shw/mktemp" <<EOF
#!/usr/bin/env bash
$SHIM_GUARD
case "\$1" in *pb-scope.*) mkdir -p "$GS/wf/pb-scope.d"; printf '%s\n' "$GS/wf/pb-scope.d"; exit 0 ;; esac
exec "$REAL_MKTEMP" "\$@"
EOF
# shc/cmp: runs the real cmp, then (only when PB_CMP_APPEND names a marker file that does not exist yet, and the last argument is
# PB_CMP_FILE) appends one valid entry to the scope file, once
cat > "$GS/shc/cmp" <<EOF
#!/usr/bin/env bash
$SHIM_GUARD
"$REAL_CMP" "\$@"; r=\$?
for last in "\$@"; do :; done
if [ -n "\${PB_CMP_APPEND:-}" ] && [ "\$last" = "\${PB_CMP_FILE:-}" ] && [ ! -e "\$PB_CMP_APPEND" ]; then
  : > "\$PB_CMP_APPEND"; printf 'other	zz
' >> "\$last"
fi
exit \$r
EOF
# shr/cmp: a shim whose "real tool" is itself (the guard row: it must end with 99 once, not a tree)
mkdir -p "$GS/shr"
cat > "$GS/shr/cmp" <<EOF
#!/usr/bin/env bash
$SHIM_GUARD
exec "$GS/shr/cmp" "\$@"
EOF
chmod +x "$GS/shr/cmp" "$GS/sh/awk" "$GS/shf/awk" "$GS/shm/mktemp" "$GS/shw/mktemp" "$GS/shc/cmp" 2>/dev/null
# the shims must really run here (NTFS chmod, path conversion): probe, then skip the rows that need them
SHIMS_OK=1
[ "$(PATH="$GS/shf:$PATH" SCF=x awk 'BEGIN{print 1}' 2>/dev/null; echo "rc=$?")" = "rc=2" ] || SHIMS_OK=0
printf 'a\n' > "$GS/pr"
PATH="$GS/shc:$PATH" PB_CMP_FILE="$GS/pr" PB_CMP_APPEND="$GS/prm" cmp -s "$GS/pr" "$GS/pr" 2>/dev/null
[ "$(tail -c 3 "$GS/pr")" = "zz" ] || SHIMS_OK=0

left_in() { ls "$1" 2>/dev/null | grep -c 'pb-scope\.' || true; }
# INT_IGN=1 when SIGINT is ignored on entry here (inherited SIG_IGN): a `set -m` job that sends itself INT survives
INT_IGN=0
[ "$( ( set -m; "$BASH" -c 'kill -INT $$; echo survived' < /dev/null 2>/dev/null & wait $! ) 2>/dev/null )" = survived ] && INT_IGN=1
blk_check() { if [ "$2" != "$3" ]; then t_bad "$1: the declared skip count ($2) matches the assertions run ($3)" ""; fi; }
dig() { git hash-object -- "$1" 2>/dev/null || printf 'NODIGEST'; }
has_line() { if printf '%s\n' "$OUT" | grep -Fx -- "$2" >/dev/null 2>&1; then t_ok "$1"; else t_bad "$1" "no line [$2] in: $OUT"; fi; }
sf() { local f="$1" e; shift; { printf '# role-gate scope v1\n'; for e in "$@"; do printf '%s\t%s\n' "${e%%:*}" "${e#*:}"; done; } > "$f"; }
new_repo() { R="$(mk_tmp)"; mk_repo "$R"; cd "$R" || exit 3; BASE="$(git rev-parse HEAD)"; SF="$(mk_tmp)/scope"; }
new_s() { R="$(fresh)"; BASE="$(head_of "$R")"; SF="$(mk_tmp)/scope"; BL=""; }

# gs_run SIG AT CMD...: run CMD as a `set -m` job (own process group, stdin /dev/null) with the shim PATH and TMPDIR=$GS/tmp. Verifies
# `kill -0 -- -JOB` before it writes the go-file (the group id); else it writes nogo and the mark file. Sets GRC (the job's status).
# SIG empty: no signal (a control run that only counts the classify calls).
gs_run() {
  local sig="$1" at="$2"; shift 2
  rm -f "$GS/cnt" "$GS/go" "$GS/nogo" "$GS/mark" "$GS/fired" "$GS/o" "$GS/tmp"/pb-scope.*
  GRC="$( set -m
    PATH="$GS/sh:$PATH" TMPDIR="$GS/tmp" PB_GSIG="$sig" PB_SIG_AT="$at" "$@" > "$GS/o" 2>&1 < /dev/null &
    jp=$!
    if kill -0 -- -"$jp" 2>/dev/null; then echo "$jp" > "$GS/go"; else : > "$GS/nogo"; : > "$GS/mark"; fi
    wait "$jp"; r=$?
    # files at the leader's exit, then wait (at most 30 s) until no process of the job's group is left
    a="$(left_in "$GS/tmp")"; i=0
    while kill -0 -- -"$jp" 2>/dev/null && [ $i -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
    if kill -0 -- -"$jp" 2>/dev/null; then d="the group still ran after 30 s"; else d="the group ended $i x 0.1 s after the leader"; fi
    echo "$a file(s) at the leader's exit; $d" > "$GS/drain"
    echo "$r" )"
}
GS_B0=0
# gs_go SIG AT N NAME CMD...: gs_run, then 0 when the rows can be judged; otherwise t_skip N and 1
gs_go() {
  local sig="$1" at="$2" n="$3" name="$4"; shift 4
  GS_B0=$((T_PASS + T_FAIL))
  if [ "$SHIMS_OK" != 1 ]; then t_skip "$n" "$name (the PATH shims do not run here)"; return 1; fi
  if [ "$sig" = INT ] && [ "$INT_IGN" = 1 ]; then t_skip "$n" "$name (SIGINT is ignored on entry here: an ignored-on-entry signal cannot be trapped or reset, so no group INT can reach the job)"; return 1; fi
  gs_run "$sig" "$at" "$@"
  if [ -e "$GS/mark" ]; then t_skip "$n" "$name (no own process group for a set -m job here: no job control)"; return 1; fi
  return 0
}
gs_end() { blk_check "$1" "$2" $((T_PASS + T_FAIL - GS_B0)); }
# gs_check NAME EXPECTED_RC: the signal was delivered at the classify call, the job ended with EXPECTED_RC, no pb-scope.* file is left
gs_check() {
  if [ -e "$GS/fired" ]; then t_ok "$1: the group signal was delivered while a classify awk ran"; else t_bad "$1: the group signal was delivered while a classify awk ran" "no signal sent (classify awk calls seen: $(cat "$GS/cnt" 2>/dev/null)); output: $(head -c 300 "$GS/o")"; fi
  if [ "$GRC" = "$2" ]; then t_ok "$1: exit $2"; else t_bad "$1: exit $2" "expected exit $2 got $GRC; output: $(head -c 300 "$GS/o")"; fi
  # judged after the job's whole process group ended (gs_run); the message keeps what was there at the leader's exit
  local lf; lf="$(left_in "$GS/tmp")"
  if [ "$lf" = 0 ]; then t_ok "$1: no pb-scope.* temp file left"; else t_bad "$1: no pb-scope.* temp file left" "$lf left after the group ended ($(cat "$GS/drain" 2>/dev/null))"; fi
}
no_cc() { assert_eq "$1: no 'cannot classify' line" "0" "$(grep -c 'cannot classify' "$GS/o" || true)"; }

# ================= AC6.4 (a) (c) (d): normal and failure returns, caller traps, template, one mktemp per call =================
cat > "$GS/lib1.sh" <<'EOF'
. "$LIBSH"
[ "${1:-}" != unset ] || unset TMPDIR
SC_ENTRIES="$(printf 'own\tsrc/\nother\tx')"
printf 'src/a\nx\nq\n' > "$GS/in"
trap 'echo CALLER-TRAP' EXIT
trap -p EXIT > "$GS/tb"
pb_scope_classify < "$GS/in" > "$GS/out1"; echo "rc1=$?"
x="$(pb_scope_classify < "$GS/in")"; echo "rc2=$?"; printf '%s\n' "$x" > "$GS/out2"
printf 'src/a\n' | pb_scope_classify > "$GS/out3"; echo "rc3=$?"
trap -p EXIT > "$GS/ta"
EOF
cat > "$GS/lib2.sh" <<'EOF'
. "$LIBSH"
SC_ENTRIES="$(printf 'own\tsrc/')"
printf 'src/a\n' | pb_scope_classify > "$GS/o2" 2>/dev/null; echo "rc=${PIPESTATUS[1]}"
EOF
export GS LIBSH="$PB_ROOT/scripts/lib.sh"
if [ "$SHIMS_OK" = 1 ]; then
echo "AC6.4 (a)(c)(d) a normal call in the caller's main shell, in \$(...) and in a pipeline: same output and status, nothing left, the caller's EXIT trap unchanged, template \${TMPDIR:-/tmp}/pb-scope.XXXXXX, exactly one mktemp per call"
for MODE in set unset; do
  rm -f "$GS/mklog" "$GS/lt"/pb-scope.*
  run env TMPDIR="$GS/lt" PATH="$GS/shm:$PATH" "$BASH" "$GS/lib1.sh" $MODE
  assert_eq "AC6.4a [$MODE] output, status and the caller's EXIT trap run as before" "rc1=0|rc2=0|rc3=0|CALLER-TRAP|" "$(printf '%s\n' "$OUT" | tr '\n' '|')"
  assert_eq "AC6.4a [$MODE] main-shell call: one verdict per input line" "own|other|none|" "$(tr '\n' '|' < "$GS/out1")"
  assert_eq "AC6.4a [$MODE] \$(...) call: same verdicts" "own|other|none|" "$(tr '\n' '|' < "$GS/out2")"
  assert_eq "AC6.4a [$MODE] pipeline call: own" "own|" "$(tr '\n' '|' < "$GS/out3")"
  assert_eq "AC6.4a [$MODE] no pb-scope.* file left after normal returns" "0" "$(left_in "$GS/lt")"
  if cmp -s "$GS/tb" "$GS/ta" && grep -q 'CALLER-TRAP' "$GS/tb"; then t_ok "AC6.4c [$MODE] trap -p EXIT is the same before and after a main-shell call (the caller's trap kept)"; else t_bad "AC6.4c [$MODE] trap -p EXIT is the same before and after a main-shell call (the caller's trap kept)" "before: [$(cat "$GS/tb")] after: [$(cat "$GS/ta")]"; fi
  if [ "$MODE" = set ]; then TPL="$GS/lt/pb-scope.XXXXXX"; else TPL="/tmp/pb-scope.XXXXXX"; fi
  assert_eq "AC6.4d [$MODE] exactly one mktemp per call (3 calls, 3 mktemp)" "3" "$(wc -l < "$GS/mklog" | tr -d ' ')"
  assert_eq "AC6.4d [$MODE] every mktemp uses the template \${TMPDIR:-/tmp}/pb-scope.XXXXXX" "$TPL" "$(sort -u "$GS/mklog")"
done
echo "AC6.4 (a) failure returns: no temp dir (1), the classify awk fails (awk's status), the temp file cannot be written (1); nothing left"
run env TMPDIR="$GS/nonexistent-dir" "$BASH" "$GS/lib2.sh"
assert_eq "AC6.4a no temp dir: status 1" "rc=1" "$OUT"
rm -f "$GS/lt"/pb-scope.*
run env TMPDIR="$GS/lt" PATH="$GS/shf:$PATH" "$BASH" "$GS/lib2.sh"
assert_eq "AC6.4a awk fails (exit 2): the status is awk's, 2" "rc=2" "$OUT"
assert_eq "AC6.4a awk fails: no pb-scope.* file left" "0" "$(left_in "$GS/lt")"
run env TMPDIR="$GS/lt" PATH="$GS/shw:$PATH" "$BASH" "$GS/lib2.sh"
assert_eq "AC6.4a the temp file cannot be written: status 1" "rc=1" "$OUT"
else t_skip 20 "AC6.4 (a)(c)(d) lib rows (the PATH shims do not run here)"; fi

# ================= AC6.4 (b): group INT / TERM while the classify awk runs =================
cat > "$GS/caller1.sh" <<'EOF'
. "$LIBSH"
tmpd="$(mktemp -d "$TMPDIR/tdd-step.XXXXXX")"; printf '%s\n' "$tmpd" > "$GS/tmpd"
trap 'rm -rf "$tmpd"' EXIT
SC_ENTRIES="$(printf 'own\tsrc/')"
printf 'src/a\n' > "$tmpd/dpaths"
pb_scope_classify < "$tmpd/dpaths" > "$tmpd/dcls" || { echo "error: cannot classify the changed paths" >&2; exit 3; }
echo "continued normally"
EOF
cat > "$GS/caller2.sh" <<'EOF'
. "$LIBSH"
SC_ENTRIES="$(printf 'own\tsrc/')"
c="$(printf 'src/a\n' | pb_scope_classify)" || c=own
echo "continued c=$c"
EOF
for SIG in INT TERM; do
  if [ "$SIG" = INT ]; then EX=130; else EX=143; fi
  echo "AC6.4 (b) a group $SIG while a main-shell caller's classify awk runs (the tdd-step.sh:150 shape): exit $EX, never 'cannot classify' (3), nothing left, the caller's EXIT trap still ran"
  rm -f "$GS/tmpd"
  if gs_go "$SIG" 1 6 "AC6.4b main-shell caller group $SIG" "$BASH" "$GS/caller1.sh"; then
    gs_check "AC6.4b main-shell caller group $SIG" "$EX"
    no_cc "AC6.4b main-shell caller group $SIG"
    assert_eq "AC6.4b main-shell caller group $SIG: the caller did not go on after the signal" "0" "$(grep -c 'continued' "$GS/o" || true)"
    if [ -n "$(cat "$GS/tmpd" 2>/dev/null)" ] && [ ! -e "$(cat "$GS/tmpd")" ]; then t_ok "AC6.4b main-shell caller group $SIG: the caller's EXIT trap removed its own temp dir"; else t_bad "AC6.4b main-shell caller group $SIG: the caller's EXIT trap removed its own temp dir" "tmpd: [$(cat "$GS/tmpd" 2>/dev/null)]"; fi
    gs_end "AC6.4b main-shell caller group $SIG" 6
  fi
done
echo "AC6.4 (b) a group INT while a \$(...) caller's classify awk runs, with '|| c=own' (the own_notes shape): exit 130, the fallback does not swallow it, nothing left"
if gs_go INT 1 4 "AC6.4b command-substitution caller group INT" "$BASH" "$GS/caller2.sh"; then
  gs_check "AC6.4b command-substitution caller group INT" 130
  assert_eq "AC6.4b command-substitution caller group INT: the '|| c=own' fallback did not run on" "0" "$(grep -c 'continued' "$GS/o" || true)"
  gs_end "AC6.4b command-substitution caller group INT" 4
fi
for SIG in INT TERM; do
  if [ "$SIG" = INT ]; then EX=130; else EX=143; fi
  echo "AC6.4 (b) role-gate check --scope, a group $SIG while the classify awk runs: exit $EX, no verdict, nothing left"
  new_repo; sf "$SF" own:src/; printf 'module.exports = 2;\n' > src/app.js
  if gs_go "$SIG" 1 4 "AC6.4b role-gate check --scope group $SIG" env PLAYBOOK_HOME="$IH" "$BASH" "$GATE" check implementer --base "$BASE" --scope "$SF"; then
    gs_check "AC6.4b role-gate check --scope group $SIG" "$EX"
    case "$(cat "$GS/o")" in *"OK: role gate"*|*"role gate FAILED"*) t_bad "AC6.4b role-gate check --scope group $SIG: no verdict line" "$(head -c 300 "$GS/o")" ;; *) t_ok "AC6.4b role-gate check --scope group $SIG: no verdict line" ;; esac
    gs_end "AC6.4b role-gate check --scope group $SIG" 4
  fi
done

# tdd-step green --scope: three scenarios; each has a control run that counts the classify calls (the order the signal index relies on)
scn_cmd_diff() { new_s; sf "$SF" own:src/; printf 'b\n' > "$R/src/app.js"; cd "$R" || exit 3
  SCN=("$BASH" "$STEP" green --base "$BASE" --scope "$SF" --message m -- sh -c 'printf x >> README.md'); }
scn_own_notes() { new_s; dirty "$R"; BL="$(snap "$R")"; sf "$SF" own:src/mine.js; printf 'm\n' > "$R/src/mine.js"; cd "$R" || exit 3
  SCN=("$BASH" "$STEP" green --base "$BASE" --scope "$SF" --baseline "$BL" --message m -- sh -c "printf 'more\n' >> README.md"); }
scn_commit_list() { new_s; sf "$SF" own:src/; printf 'b\n' > "$R/src/app.js"; cd "$R" || exit 3
  SCN=("$BASH" "$STEP" green --base "$BASE" --scope "$SF" --message m --commit -- true); }
# ctl NAME TOTAL AT INPUT: a normal run of the scenario makes TOTAL classify awk calls, call AT gets INPUT (paths joined by commas), and it succeeds
ctl() {
  GS_B0=$((T_PASS + T_FAIL))
  if [ "$SHIMS_OK" != 1 ]; then t_skip 3 "$1 control (the PATH shims do not run here)"; return; fi
  rm -f "$GS/calls"
  PB_GLOG=1 gs_run "" 1 "${SCN[@]}"
  if [ -e "$GS/mark" ]; then t_skip 3 "$1 control (no job control here)"; return; fi
  [ -z "${GS_SHOWCALLS:-}" ] || { echo "calls of $1:"; cat "$GS/calls"; }
  assert_eq "$1 control: a normal run makes $2 classify awk calls (the signal row hits one of them)" "$2" "$(cat "$GS/cnt" 2>/dev/null || echo 0)"
  assert_eq "$1 control: classify call $3 is the one the signal row hits (its input)" "$3: $4" "$(sed -n "${3}p" "$GS/calls")"
  assert_eq "$1 control: a normal run exits 0" "0" "$GRC"
}
for SIG in INT TERM; do
  if [ "$SIG" = INT ]; then EX=130; else EX=143; fi
  echo "AC6.4 (b) tdd-step green --scope, a group $SIG while scope_cmd_diff's classify awk runs (2nd classify call): exit $EX, never 3, no 'cannot classify', nothing left"
  scn_cmd_diff
  if gs_go "$SIG" 2 4 "AC6.4b tdd-step scope_cmd_diff group $SIG" "${SCN[@]}"; then
    gs_check "AC6.4b tdd-step scope_cmd_diff group $SIG" "$EX"
    no_cc "AC6.4b tdd-step scope_cmd_diff group $SIG"
    gs_end "AC6.4b tdd-step scope_cmd_diff group $SIG" 4
  fi
done
scn_cmd_diff; ctl "AC6.4b scope_cmd_diff scenario" 4 2 README.md

echo "AC6.4 (b) tdd-step green --scope --baseline, a group INT while own_notes' classify awk runs (4th classify call, the first note line): exit 130, not swallowed by '|| c=own'"
scn_own_notes
if gs_go INT 4 4 "AC6.4b tdd-step own_notes group INT" "${SCN[@]}"; then
  gs_check "AC6.4b tdd-step own_notes group INT" 130
  no_cc "AC6.4b tdd-step own_notes group INT"
  gs_end "AC6.4b tdd-step own_notes group INT" 4
fi
scn_own_notes; ctl "AC6.4b own_notes scenario" 7 4 src/app.js

echo "AC6.4 (b) tdd-step green --scope --commit, a group signal while the commit-list classify awk runs (tdd-step.sh:664, a pipeline member): bash 5 exit 130 / 143, bash 3.2 exit 3 as today (D8); nothing left"
CLAT=3
case "${BASH_VERSINFO[0]}" in
  3) CLI=3; CLT="" ;;
  [5-9]|[1-9][0-9]) CLI=130; CLT=143 ;;
  *) CLI=""; CLT="" ;;
esac
if [ -z "$CLI" ]; then t_skip 8 "AC6.4b tdd-step commit-list group INT / TERM (bash $BASH_VERSION: the row is pinned for bash 5 and bash 3.2 only)"
else
  scn_commit_list
  if gs_go INT "$CLAT" 4 "AC6.4b tdd-step commit-list group INT (bash ${BASH_VERSINFO[0]})" "${SCN[@]}"; then
    gs_check "AC6.4b tdd-step commit-list group INT (bash ${BASH_VERSINFO[0]})" "$CLI"
    if [ "$CLI" = 3 ]; then has_cc=1; else has_cc=0; fi
    assert_eq "AC6.4b tdd-step commit-list group INT: the 'cannot classify' line appears only where the exit is 3 (bash 3.2)" "$has_cc" "$(grep -c 'cannot classify' "$GS/o" || true)"
    gs_end "AC6.4b tdd-step commit-list group INT" 4
  fi
  if [ -n "$CLT" ]; then
    scn_commit_list
    if gs_go TERM "$CLAT" 4 "AC6.4b tdd-step commit-list group TERM (bash 5)" "${SCN[@]}"; then
      gs_check "AC6.4b tdd-step commit-list group TERM (bash 5)" "$CLT"
      no_cc "AC6.4b tdd-step commit-list group TERM (bash 5)"
      gs_end "AC6.4b tdd-step commit-list group TERM" 4
    fi
  else t_skip 4 "AC6.4b tdd-step commit-list group TERM (bash 3.2: the TERM exit is not pinned, D8)"; fi
fi
scn_commit_list; ctl "AC6.4b commit-list scenario" 3 3 src/app.js

# ================= AC6.1: the scope re-hash guard of role-gate check =================
e1() { printf 'note: scope %s (%s own, %s other entries, digest %s): %s path(s) outside the scope not checked' "$SF" "$1" "$2" "$(dig "$SF")" "$3"; }
if [ "$SHIMS_OK" = 1 ]; then
  echo "AC6.1 control: the cmp shim installed but not mutating: today's E1 note and OK verdict"
  new_repo; sf "$SF" own:src/; printf 'module.exports = 2;\n' > src/app.js
  run env PLAYBOOK_HOME="$IH" PATH="$GS/shc:$PATH" PB_CMP_FILE="$SF" bash "$GATE" check implementer --base "$BASE" --scope "$SF"
  assert_rc "AC6.1 control (shim, no change): exit 0" 0
  has_line "AC6.1 control: the OK verdict" "OK: role gate passed for implementer (1 file(s) checked, base=$BASE)"
  has_line "AC6.1 control: the E1 note" "$(e1 1 0 0)"
  echo "AC6.1 the scope file gains a valid entry between the first hash and the re-hash: exit 3, G-E2 with the file, no verdict, no E1 note"
  new_repo; sf "$SF" own:src/; printf 'module.exports = 2;\n' > src/app.js
  rm -f "$GS/cmpfired"
  run env PLAYBOOK_HOME="$IH" PATH="$GS/shc:$PATH" PB_CMP_FILE="$SF" PB_CMP_APPEND="$GS/cmpfired" bash "$GATE" check implementer --base "$BASE" --scope "$SF"
  if [ -e "$GS/cmpfired" ] && [ "$(tail -n 1 "$SF")" = "other${TAB}zz" ]; then t_ok "AC6.1 the shim changed the scope file once, between the hashes (a valid 'other' entry was appended)"; else t_bad "AC6.1 the shim changed the scope file once, between the hashes (a valid 'other' entry was appended)" "marker: $([ -e "$GS/cmpfired" ] && echo yes || echo no); last line: $(tail -n 1 "$SF")"; fi
  assert_rc "AC6.1 a scope file changed while it was read: exit 3" 3
  has_line "AC6.1 the message is G-E2 and names the file" "error: the scope file changed while it was read: $SF"
  case "$OUT" in *"OK: role gate"*|*"role gate FAILED"*|*VIOLATION*) t_bad "AC6.1 no verdict line (OK:, FAILED, VIOLATION)" "$OUT" ;; *) t_ok "AC6.1 no verdict line (OK:, FAILED, VIOLATION)" ;; esac
  case "$OUT" in *"note: scope "*) t_bad "AC6.1 no E1 note (the gate stopped before judging)" "$OUT" ;; *) t_ok "AC6.1 no E1 note (the gate stopped before judging)" ;; esac
else t_skip 8 "AC6.1 re-hash guard (the cmp shim does not run here)"; fi

# ================= shim recursion guard: a shim whose real tool is itself ends with 99 once =================
echo "shim guard: a shim that calls itself ends with exit 99 and 'shim recursion', not a process tree"
printf 'a
' > "$GS/pg"
# a portable watchdog (no `timeout` on macOS): a background loop kills the shim after 60 s if it still runs
env -u PB_SHIM_DEPTH "$GS/shr/cmp" "$GS/pg" "$GS/pg" > "$GS/sgo" 2>&1 &
sgp=$!
( i=0; while kill -0 "$sgp" 2>/dev/null && [ $i -lt 600 ]; do sleep 0.1; i=$((i + 1)); done
  if kill -0 "$sgp" 2>/dev/null; then echo "WATCHDOG: still running after 60 s" >> "$GS/sgo"; kill -9 "$sgp" 2>/dev/null; fi ) &
sgw=$!
wait "$sgp"; sgr=$?; wait "$sgw"
SGOUT="$(cat "$GS/sgo"; echo "rc=$sgr")"
assert_eq "shim guard: a self-calling shim stops at the second call: 'shim recursion', exit 99" "shim recursion|rc=99|" "$(printf '%s
' "$SGOUT" | tr '
' '|')"

t_summary
