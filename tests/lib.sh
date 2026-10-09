#!/usr/bin/env bash
# Minimal test helpers. Bash 3.2 compatible (macOS default). Source this file.
PB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
T_PASS=0
T_FAIL=0
T_TMPS=""

t_ok()  { T_PASS=$((T_PASS + 1)); printf '  ok   %s\n' "$1"; }
t_bad() { T_FAIL=$((T_FAIL + 1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; return 0; }

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

# run CMD...  -> sets OUT (stdout+stderr) and RC
run() { OUT="$("$@" 2>&1)"; RC=$?; }
# run_in DIR CMD... -> same, executed in DIR (a subshell around `run` would lose OUT/RC)
run_in() { local d="$1"; shift; OUT="$(cd "$d" && "$@" 2>&1)"; RC=$?; }

mk_tmp() {
  local d base="${TMPDIR:-/tmp}"
  base="${base%/}"   # macOS TMPDIR ends with "/": avoid "//" paths that differ from normalised ones
  d="$(mktemp -d "$base/pbtest.XXXXXX")" || exit 3
  T_TMPS="$T_TMPS $d"
  printf '%s\n' "$d"
}
t_cleanup() { local d; for d in $T_TMPS; do rm -rf "$d"; done; }
trap t_cleanup EXIT

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
  printf '%s: %d passed, %d failed\n' "$(basename "$0")" "$T_PASS" "$T_FAIL"
  [ "$T_FAIL" -eq 0 ]
}
