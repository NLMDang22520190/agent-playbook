#!/usr/bin/env bash
# Tests for tests/lib.sh temp-dir cleanup (v0.23.0 AC3): every dir mk_tmp makes is removed when a suite ends, also when
# mk_tmp ran inside $(...) (the 270 real callers), on INT and TERM, and the cleanup never removes what it did not make.
# Each case runs a stub suite in its own process with a private TMPDIR (a mk_tmp dir of this suite) and then looks at it.
#   AC3.1 lib.sh makes one list file (pblist.XXXXXX, same base, not matching pbtest.*) when it loads; mk_tmp records in it;
#         T_TMPS keeps working (tests/test-run-all.sh appends to it directly)
#   AC3.2 t_cleanup removes only absolute paths under the load-time base named pbtest.* or pbguard.* (or in T_TMPS),
#         refuses "", "/" and anything outside the base, then removes the list file; runs on EXIT; INT/TERM clean up and
#         exit 130/143; running it twice is harmless
#   AC3.3 a stub suite with a private TMPDIR leaves that TMPDIR empty
. "$(dirname "$0")/lib.sh"

case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) t_skip 40 "AC3 signal cases need POSIX signals (not possible on Git Bash)"; t_summary; exit $? ;;
esac

SD="$(mk_tmp)"    # the stubs live here, outside every private TMPDIR
# stub NAME BODY -> SD/NAME.sh sources lib.sh and runs BODY; STUB is its path
stub() { STUB="$SD/$1.sh"; printf 'PB_LIB_ALLOW_ANYWHERE=1\n. "%s/tests/lib.sh"\n%s\n' "$PB_ROOT" "$2" > "$STUB"; }
# run_stub PRIV -> runs STUB with TMPDIR=PRIV; sets OUT and RC
run_stub() { run env TMPDIR="$1" bash "$STUB"; }
# run_stub_sig PRIV -> like run_stub, for stubs that signal themselves. A suite started in the background (run-all, CI, bsd-check
# on macOS bash 3.2) inherits SIGINT as ignored, and a non-interactive bash cannot trap or receive what was ignored on entry,
# not even under set -m. perl (on macOS and Linux) resets INT to the default before it execs the stub, so the signal the
# stub sends itself is delivered whatever the caller's state. Without perl the stub is run as it is.
run_stub_sig() {
  if command -v perl >/dev/null 2>&1; then
    run perl -e '$SIG{INT} = "DEFAULT"; exec @ARGV' env TMPDIR="$1" bash "$STUB"
  else
    run env TMPDIR="$1" bash "$STUB"
  fi
}
# left PRIV -> what is still in PRIV (names, one per line)
left() { ls -A "$1" 2>/dev/null; }
# priv -> a fresh private TMPDIR (a mk_tmp dir of this suite)
priv() { mk_tmp; }

echo "AC3.3 a normal exit leaves the private TMPDIR empty, also for mk_tmp called inside \$(...)"
P="$(priv)"
stub normal 'a=$(mk_tmp); b=$(mk_tmp); c=$(mk_tmp)
touch "$a/f"; mkdir "$b/sub"; touch "$b/sub/g"
[ -d "$a" ] && [ -d "$b" ] && [ -d "$c" ] && echo "dirs-exist"
case "$a" in "'"$P"'"/pbtest.*) echo "under-base" ;; esac
echo "lists=$(ls "'"$P"'" | grep -c "^pblist\.")"
t_summary'
run_stub "$P"
assert_rc "AC3.3 the stub suite exits 0" 0
assert_contains "AC3.3 the dirs existed during the run" "$OUT" "dirs-exist"
assert_contains "AC3.3 mk_tmp dirs are under the private TMPDIR, named pbtest.*" "$OUT" "under-base"
assert_contains "AC3.1 exactly one pblist.* file exists while the suite runs" "$OUT" "lists=1"
assert_eq "AC3.3 the private TMPDIR is empty after a normal exit" "" "$(left "$P")"

echo "AC3.3 a failing suite (exit 1) is cleaned too, and keeps its exit code"
P="$(priv)"
stub failing 'a=$(mk_tmp); t_bad "x"; t_summary'
run_stub "$P"
assert_rc "AC3.3 a suite with a failure still exits 1" 1
assert_eq "AC3.3 the private TMPDIR is empty after a failing suite" "" "$(left "$P")"

echo "AC3.3 an explicit exit 7 inside the suite is cleaned too"
P="$(priv)"
stub exit7 'a=$(mk_tmp); b=$(mk_tmp); exit 7'
run_stub "$P"
assert_rc "AC3.3 exit 7 is kept" 7
assert_eq "AC3.3 the private TMPDIR is empty after exit 7" "" "$(left "$P")"

echo "AC3.1 the list file is made at load: a suite that never calls mk_tmp leaves nothing either"
P="$(priv)"
stub nocall 'echo "lists=$(ls "'"$P"'" | grep -c "^pblist\.")"; t_summary'
run_stub "$P"
assert_rc "AC3.1 a suite with no mk_tmp call exits 0" 0
assert_contains "AC3.1 the list file exists after load" "$OUT" "lists=1"
assert_eq "AC3.1 and is gone after exit" "" "$(left "$P")"

echo "AC3.2 INT: cleans up and exits 130"
P="$(priv)"
stub sigint 'a=$(mk_tmp); b=$(mk_tmp); echo "ready"; kill -INT $$; sleep 5; echo "not-reached"'
run_stub_sig "$P"
assert_rc "AC3.2 INT: exit 130" 130
assert_contains "AC3.2 INT: the suite got as far as the signal" "$OUT" "ready"
assert_not_contains "AC3.2 INT: the suite stopped" "$OUT" "not-reached"
assert_eq "AC3.2 INT: the private TMPDIR is empty" "" "$(left "$P")"

echo "AC3.2 TERM: cleans up and exits 143"
P="$(priv)"
stub sigterm 'a=$(mk_tmp); b=$(mk_tmp); echo "ready"; kill -TERM $$; sleep 5; echo "not-reached"'
run_stub_sig "$P"
assert_rc "AC3.2 TERM: exit 143" 143
assert_contains "AC3.2 TERM: the suite got as far as the signal" "$OUT" "ready"
assert_not_contains "AC3.2 TERM: the suite stopped" "$OUT" "not-reached"
assert_eq "AC3.2 TERM: the private TMPDIR is empty" "" "$(left "$P")"

echo "AC3.2 a signal from outside while the suite waits"
P="$(priv)"
stub waiting 'a=$(mk_tmp); echo "$$" > "'"$SD"'/waiting.pid"; echo "ready"; sleep 4 & wait $!'
env TMPDIR="$P" bash "$STUB" > "$SD/waiting.out" 2>&1 &
WP=$!
n=0; while [ ! -s "$SD/waiting.pid" ] && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
kill -TERM "$(cat "$SD/waiting.pid" 2>/dev/null)" 2>/dev/null
wait "$WP" 2>/dev/null; RC=$?
OUT="$(cat "$SD/waiting.out")"
assert_rc "AC3.2 TERM from outside: exit 143" 143
assert_eq "AC3.2 TERM from outside: the private TMPDIR is empty" "" "$(left "$P")"

echo "AC3.2 the cleanup refuses injected list entries and removes the legit ones"
P="$(priv)"
DECOY_ROOT="$(mk_tmp)"            # outside the private base
mkdir "$DECOY_ROOT/pbtest.decoy" "$DECOY_ROOT/pbguard.decoy" "$DECOY_ROOT/plain-decoy"
touch "$DECOY_ROOT/pbtest.decoy/keep" "$DECOY_ROOT/pbguard.decoy/keep" "$DECOY_ROOT/plain-decoy/keep"
mkdir "$P/keep-dir" "$P/pbother.x"; touch "$P/keep-dir/keep" "$P/pbother.x/keep"
UP="$P/../$(basename "$DECOY_ROOT")/pbtest.decoy"       # under the base by prefix, outside it by resolution
stub inject 'a=$(mk_tmp); b=$(mk_tmp)
list=$(ls -d "'"$P"'"/pblist.* | head -n 1)
[ -f "$list" ] || { echo "no-list-file"; exit 9; }
{ printf "%s\n" "/"; printf "\n"; printf "%s\n" "//"
  printf "%s\n" "'"$DECOY_ROOT"'/pbtest.decoy" "'"$DECOY_ROOT"'/pbguard.decoy" "'"$DECOY_ROOT"'/plain-decoy"
  printf "%s\n" "'"$P"'/keep-dir" "'"$P"'/pbother.x" "'"$P"'" "'"$UP"'" "pbtest.relative"; } >> "$list"
T_TMPS="$T_TMPS /"
echo "injected"; t_summary'
run_stub "$P"
assert_rc "AC3.2 inject: the suite itself exits 0" 0
assert_contains "AC3.2 inject: entries were injected into the list file" "$OUT" "injected"
assert_not_contains "AC3.2 inject: no 'it is dangerous' rm refusal leaks out" "$OUT" "dangerous"
assert_dir "AC3.2 a pbtest.* dir outside the base survives" "$DECOY_ROOT/pbtest.decoy"
assert_file "AC3.2 and its content" "$DECOY_ROOT/pbtest.decoy/keep"
assert_dir "AC3.2 a pbguard.* dir outside the base survives" "$DECOY_ROOT/pbguard.decoy"
assert_dir "AC3.2 a differently named dir outside the base survives" "$DECOY_ROOT/plain-decoy"
assert_file "AC3.2 an entry with .. that resolves outside the base: the decoy survives" "$DECOY_ROOT/pbtest.decoy/keep"
assert_dir "AC3.2 a dir under the base not named pbtest./pbguard. survives (keep-dir)" "$P/keep-dir"
assert_dir "AC3.2 a dir under the base named pbother.* survives" "$P/pbother.x"
assert_dir "AC3.2 the base itself survives" "$P"
assert_dir "AC3.2 the real root is still there" "/"
assert_dir "AC3.2 / and // entries did not remove the system dirs (usr)" "/usr"
assert_eq "AC3.2 inject: only the two foreign dirs are left in the base, no pbtest.* and no pblist.*" "keep-dir
pbother.x" "$(left "$P" | sort)"

echo "AC3.2 T_TMPS entries (as tests/test-run-all.sh uses them) are removed; / in T_TMPS is refused"
P="$(priv)"
DECOY_ROOT2="$(mk_tmp)"; mkdir "$DECOY_ROOT2/pbtest.d2"
stub tmps 'f=$(mktemp "${TMPDIR:-/tmp}/pbguard.XXXXXX"); : > "$f.timeout"
T_TMPS="$T_TMPS $f $f.timeout /"
d=$(mktemp -d "${TMPDIR:-/tmp}/pbtest.XXXXXX"); T_TMPS="$T_TMPS $d"
touch "$d/x"
[ -e "$f" ] && [ -e "$f.timeout" ] && echo "guard-exist"
t_summary'
run_stub "$P"
assert_rc "AC3.2 T_TMPS: the suite exits 0" 0
assert_contains "AC3.2 T_TMPS: the guard files existed" "$OUT" "guard-exist"
assert_eq "AC3.2 T_TMPS: pbguard.* files, their .timeout and a pbtest dir are removed" "" "$(left "$P")"
assert_dir "AC3.2 T_TMPS: a decoy elsewhere is untouched" "$DECOY_ROOT2/pbtest.d2"

echo "AC3.2 running the cleanup twice is harmless"
P="$(priv)"
stub twice 'a=$(mk_tmp); b=$(mk_tmp); t_cleanup; echo "first-done"; t_cleanup; echo "second-done"
echo "left=$(ls -A "'"$P"'" | wc -l | tr -d " ")"
t_summary'
run_stub "$P"
assert_rc "AC3.2 twice: exit 0" 0
assert_contains "AC3.2 twice: the first cleanup returned" "$OUT" "first-done"
assert_contains "AC3.2 twice: the second cleanup returned" "$OUT" "second-done"
assert_contains "AC3.2 twice: nothing is left after the explicit cleanups" "$OUT" "left=0"
assert_not_contains "AC3.2 twice: no error text" "$OUT" "No such file"
assert_eq "AC3.2 twice: the private TMPDIR is empty at the end (the EXIT cleanup is a third run)" "" "$(left "$P")"

echo "AC3.2 a cleanup after the list file vanished is harmless"
P="$(priv)"
stub nolist 'a=$(mk_tmp); rm -f "'"$P"'"/pblist.*; echo "list-removed"; t_summary'
run_stub "$P"
assert_rc "AC3.2 vanished list: exit 0" 0
assert_not_contains "AC3.2 vanished list: no error text" "$OUT" "No such file"

echo "AC3.1 two suites at once keep separate lists: one cleaning does not remove the other's dirs"
P="$(priv)"
stub holder 'a=$(mk_tmp); echo "$a" > "'"$SD"'/holder.dir"; echo "ready"; sleep 3'
env TMPDIR="$P" bash "$STUB" > "$SD/holder.out" 2>&1 &
HP=$!
n=0; while [ ! -s "$SD/holder.dir" ] && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
stub quick 'b=$(mk_tmp); t_summary'
run_stub "$P"
HD="$(cat "$SD/holder.dir" 2>/dev/null)"
assert_dir "AC3.1 the other suite's dir survives while it still runs" "$HD"
wait "$HP" 2>/dev/null
assert_eq "AC3.1 after both ended the private TMPDIR is empty" "" "$(left "$P")"


# ---- v0.23.0 review: TMPDIR forms ("//", relative) and a glob in T_TMPS ----
# bash_list -> the bash binaries to run a stub with: the one on PATH, and bash 3.2 when ~/.local/bin/bash3.2 exists
BASHES="bash"
B32=""
if [ -n "${PB_BASH32:-}" ] && [ -x "$PB_BASH32" ]; then B32="$PB_BASH32"
elif [ -x "${HOME:-/nonexistent}/.local/bin/bash3.2" ]; then B32="$HOME/.local/bin/bash3.2"
else B32="$(command -v bash3.2 2>/dev/null)" || B32=""; fi
[ -n "$B32" ] && BASHES="bash $B32"

echo "AC3.2 review: a TMPDIR with // (internal or trailing) leaves no pbtest.* behind, under every bash"
for BB in $BASHES; do
  for form in trailing double-trailing internal; do
    P="$(priv)"; mkdir "$P/sub"
    case "$form" in
      trailing) TD="$P/sub/" ;;
      double-trailing) TD="$P/sub//" ;;
      internal) TD="$P//sub" ;;
    esac
    stub slashes 'a=$(mk_tmp); b=$(mk_tmp); touch "$a/x"; t_summary'
    run env TMPDIR="$TD" "$BB" "$STUB"
    assert_rc "AC3.2 review: [$form] under $(basename "$BB"): exit 0" 0
    assert_eq "AC3.2 review: [$form] under $(basename "$BB"): the TMPDIR is empty afterwards" "" "$(left "$P/sub")"
  done
done

if [ -z "$B32" ]; then t_skip 6 "AC3.2 review: the // TMPDIR cases under bash 3.2 (no bash 3.2: set PB_BASH32 or build ~/.local/bin/bash3.2 with tools/get-bash32.sh)"; fi

echo "AC3.2 review: a relative TMPDIR is refused at load or made absolute, never left behind"
P="$(priv)"; mkdir "$P/rel"
stub relative 'a=$(mk_tmp); touch "$a/x"; t_summary'
run_in "$P" env TMPDIR=rel bash "$STUB"
assert_eq "AC3.2 review: a relative TMPDIR leaves nothing in rel/" "" "$(left "$P/rel")"
assert_eq "AC3.2 review: and nothing in the working directory" "rel" "$(left "$P")"
P="$(priv)"; mkdir "$P/rel"
stub relative2 'a=$(mk_tmp); touch "$a/x"; t_summary'
run_in "$P" env TMPDIR=./rel bash "$STUB"
assert_eq "AC3.2 review: TMPDIR=./rel leaves nothing in rel/" "" "$(left "$P/rel")"

echo "AC3.2 review: a glob in T_TMPS does not delete a dir the suite did not create"
P="$(priv)"
stub globbed 'a=$(mk_tmp); echo "a=$a"
mkdir "$TMPDIR/pbtest.other"; touch "$TMPDIR/pbtest.other/keep"
T_TMPS="$T_TMPS $TMPDIR/pbtest.*"
t_summary'
run_stub "$P"
assert_rc "AC3.2 review: the globbing suite exits 0" 0
assert_dir "AC3.2 review: the decoy pbtest.other survives a glob in T_TMPS" "$P/pbtest.other"
assert_file "AC3.2 review: and its content" "$P/pbtest.other/keep"
GA="$(printf '%s\n' "$OUT" | sed -n 's/^a=//p')"
assert_no_path "AC3.2 review: the dir the suite did create is gone" "$GA"

echo "AC3.4 a forked child that inherited the trap must not run the owner's cleanup (BASHPID shells)"
P="$(priv)"
stub childclean 'a=$(mk_tmp); touch "$a/f"
if [ -z "${BASHPID:-}" ]; then echo "nobashpid"; t_summary; exit $?; fi
( t_cleanup ); [ -d "$a" ] && echo "sub-kept" || echo "sub-wiped"
f() { while :; do :; done; }
w=0; i=0
while [ $i -lt 12 ]; do f & p=$!; kill -TERM $p 2>/dev/null; wait $p 2>/dev/null; [ -d "$a" ] || { w=$((w + 1)); a=$(mk_tmp); }; i=$((i + 1)); done
echo "race-wiped=$w"
t_summary'
for BB in $BASHES; do
  run env TMPDIR="$P" "$BB" "$STUB"
  case "$OUT" in
    *nobashpid*) t_skip 3 "AC3.4 under $(basename "$BB"): no BASHPID, the inherited-trap race does not exist there" ;;
    *)
      assert_contains "AC3.4 under $(basename "$BB"): t_cleanup in a subshell keeps the owner's dir" "$OUT" "sub-kept"
      assert_contains "AC3.4 under $(basename "$BB"): TERM right after a fork never wipes the owner's dir" "$OUT" "race-wiped=0"
      assert_eq "AC3.4 under $(basename "$BB"): the private TMPDIR is empty afterwards" "" "$(left "$P")" ;;
  esac
done

t_summary
