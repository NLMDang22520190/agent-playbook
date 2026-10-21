#!/usr/bin/env bash
# Minimal test helpers. Bash 3.2 compatible (macOS default). Source this file.
PB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# Canonical layout only: the suite that sources this file must live in "$PB_ROOT/tests" (both resolved with pwd -P). A copy
# run from anywhere else (v0.24.21: .agents/handoff/test-x.sh inside the real repo) would point PB_ROOT at a real tree and
# its helpers could commit or edit there, so it stops here with exit 2 before any helper runs. PB_LIB_ALLOW_ANYWHERE=1 is
# for the throwaway stub suites that tests/test-lib*.sh generate in temp dirs; never set it for a real suite.
PB_CALLER="${BASH_SOURCE[1]:-}"
PB_CALLER_DIR=""
if [ -n "$PB_CALLER" ]; then PB_CALLER_DIR="$(cd "$(dirname "$PB_CALLER")" 2>/dev/null && pwd -P)"; fi
if [ "${PB_LIB_ALLOW_ANYWHERE:-}" != 1 ] && [ "$PB_CALLER_DIR" != "$PB_ROOT/tests" ]; then
  printf 'tests/lib.sh: refusing to run: %s is not in %s/tests (a copy of a suite could change the repo it points at)\n' "${PB_CALLER:-<no sourcing script>}" "$PB_ROOT" >&2
  exit 2
fi
T_PASS=0
T_FAIL=0
T_SKIP=0
T_TMPS=""

t_ok()  { T_PASS=$((T_PASS + 1)); printf '  ok   %s\n' "$1"; }
t_bad() { T_FAIL=$((T_FAIL + 1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; return 0; }
# t_skip COUNT REASON: COUNT assertions not run here (shown in the summary, never a failure)
t_skip() { T_SKIP=$((T_SKIP + $1)); printf '  skip %s (%d assertions)\n' "$2" "$1"; }

assert_eq() { # name expected actual
  if [ "$2" = "$3" ]; then t_ok "$1"; else t_bad "$1" "expected [$2] got [$3]"; fi
}
assert_contains() { # name haystack needle
  case "$2" in *"$3"*) t_ok "$1" ;; *) t_bad "$1" "missing [$3] in [$2]" ;; esac
}
assert_not_contains() { # name haystack needle
  case "$2" in *"$3"*) t_bad "$1" "unexpected [$3] in [$2]" ;; *) t_ok "$1" ;; esac
}
assert_file()    { if [ -f "$2" ]; then t_ok "$1"; else t_bad "$1" "no such file: $2"; fi; }
assert_dir()     { if [ -d "$2" ]; then t_ok "$1"; else t_bad "$1" "no such dir: $2"; fi; }
assert_no_path() { if [ ! -e "$2" ] && [ ! -L "$2" ]; then t_ok "$1"; else t_bad "$1" "should not exist: $2"; fi; }
assert_link_to() { # name link expected-target
  if [ -L "$2" ] && [ "$(readlink "$2")" = "$3" ]; then t_ok "$1"; else t_bad "$1" "link $2 -> [$(readlink "$2" 2>/dev/null)] want [$3]"; fi
}
assert_rc() { # name expected_rc (uses $RC)
  if [ "$RC" = "$2" ]; then t_ok "$1"; else t_bad "$1" "expected exit $2 got $RC; output: $OUT"; fi
}

# Symlinks: Windows (Git Bash) without symlink rights cannot create them. Tests that install use
# MODEFLAG ("" or "--copy") and assert_installed, so the same suite runs in either mode.
pb_probe_symlink() {
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/pbprobe.XXXXXX")" || return 1
  ln -s "$d" "$d/link" 2>/dev/null && [ -L "$d/link" ]; local rc=$?
  rm -rf "$d"; return $rc
}
if pb_probe_symlink; then SYMLINKS=1; MODEFLAG=""; else SYMLINKS=0; MODEFLAG="--copy"; fi
# assert_installed name path source -> a symlink to source (link mode) or an equal copy (copy mode)
assert_installed() {
  if [ "$SYMLINKS" = 1 ]; then assert_link_to "$1" "$2" "$3"; return; fi
  if [ -e "$2" ] && [ ! -L "$2" ] && diff -r -q --exclude=.playbook-managed "$3" "$2" >/dev/null 2>&1; then
    t_ok "$1 (copy mode)"; else t_bad "$1 (copy mode)" "$2 is not an equal copy of $3"; fi
}

# run CMD...  -> sets OUT (stdout+stderr) and RC
run() { OUT="$("$@" 2>&1)"; RC=$?; }
# run_in DIR CMD... -> same, executed in DIR (a subshell around `run` would lose OUT/RC)
run_in() { local d="$1"; shift; OUT="$(cd "$d" && "$@" 2>&1)"; RC=$?; }

# Temp dirs. At load time lib.sh fixes the base (TMPDIR without a trailing slash) and makes one list file
# ($PB_TMPBASE/pblist.XXXXXX). mk_tmp appends every dir it makes to that file, so dirs made inside $(...) are recorded
# too (a T_TMPS update there would be lost). t_cleanup removes only absolute entries directly under the base whose name
# starts with pbtest. or pbguard. (from the list file or from T_TMPS), refuses empty entries, / and anything containing
# .., then removes the list file. It runs on EXIT, and on INT/TERM (exit 130/143); running it twice is harmless.
# t_squeeze PATH -> PATH with every run of / collapsed to one (a loop: ${x//\/\//\/} is wrong on bash 3.2); sets T_SQ
t_squeeze() {
  local x="$1" y=""
  while [ -n "$x" ]; do
    case "$x" in
      //*) x="${x#/}" ;;
      *) y="$y${x%"${x#?}"}"; x="${x#?}" ;;
    esac
  done
  T_SQ="$y"
}
PB_TMPBASE="${TMPDIR:-/tmp}"
case "$PB_TMPBASE" in /*) ;; ./*) PB_TMPBASE="$PWD/${PB_TMPBASE#./}" ;; *) PB_TMPBASE="$PWD/$PB_TMPBASE" ;; esac   # a relative TMPDIR is made absolute
t_squeeze "$PB_TMPBASE"; PB_TMPBASE="${T_SQ%/}"   # macOS TMPDIR ends with "/": avoid "//" paths that differ from normalised ones
PB_TMPLIST="$(mktemp "$PB_TMPBASE/pblist.XXXXXX")" || exit 3
mk_tmp() {
  local d
  d="$(mktemp -d "$PB_TMPBASE/pbtest.XXXXXX")" || exit 3
  T_TMPS="$T_TMPS $d"
  printf '%s\n' "$d" >> "$PB_TMPLIST"
  printf '%s\n' "$d"
}
# t_rm_ok ENTRY -> 0 only for an absolute path directly under the load-time base named pbtest.* or pbguard.*
t_rm_ok() {
  local e rest
  t_squeeze "$1"; e="$T_SQ"
  case "$e" in '' | / | *..* | *[*?[]*) return 1 ;; esac
  case "$e" in "$PB_TMPBASE"/*) rest="${e#"$PB_TMPBASE"/}" ;; *) return 1 ;; esac
  case "$rest" in '' | */*) return 1 ;; pbtest.* | pbguard.*) return 0 ;; esac
  return 1
}
t_cleanup() {
  local d line noglob=""
  if [ -f "$PB_TMPLIST" ]; then
    while IFS= read -r line; do if t_rm_ok "$line"; then rm -rf "$line"; fi; done < "$PB_TMPLIST"
  fi
  case "$-" in *f*) noglob=1 ;; esac
  set -f   # a glob in T_TMPS must not expand into dirs the suite did not make
  for d in $T_TMPS; do if t_rm_ok "$d"; then rm -rf "$d"; fi; done
  [ -n "$noglob" ] || set +f
  rm -f "$PB_TMPLIST"
  return 0
}
trap t_cleanup EXIT
trap 't_cleanup; exit 130' INT
trap 't_cleanup; exit 143' TERM

# mk_repo DIR -> git repo with src/app.js, tests/app.test.js, README.md committed
mk_repo() {
  local d="$1"
  mkdir -p "$d/src" "$d/tests"
  ( cd "$d" &&
    git init -q &&
    git config user.email t@example.invalid &&
    git config user.name tester &&
    git config commit.gpgsign false &&
    printf 'module.exports = 1;\n' > src/app.js &&
    printf 'test("x", () => {});\n' > tests/app.test.js &&
    printf '# demo\n' > README.md &&
    git add -A && git commit -q -m init )
}

t_summary() {
  if [ "$T_SKIP" -gt 0 ]; then
    printf '%s: %d passed, %d failed, %d skipped\n' "$(basename "$0")" "$T_PASS" "$T_FAIL" "$T_SKIP"
  else
    printf '%s: %d passed, %d failed\n' "$(basename "$0")" "$T_PASS" "$T_FAIL"
  fi
  [ "$T_FAIL" -eq 0 ]
}
