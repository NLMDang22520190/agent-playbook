#!/usr/bin/env bash
# AC9 (v0.37 Q6): scripts/lib.sh pb_pybin sets PB_PY to python3, else python, else empty; a python3 that fails (Windows Store stub) does not count.
. "$(dirname "$0")/lib.sh"
LIBSH="$PB_ROOT/scripts/lib.sh"
REAL_PY="$(command -v python3 2>/dev/null)"
BASH_BIN="$(command -v bash)"
if [ -z "$REAL_PY" ]; then t_skip 6 "no real python3 on this host"; t_summary; exit 0; fi
# mk NAME... -> dir holding python3/python as: real (exec real python3), stub (exit 49), none; "python3=real python=stub"
mkd() { local d s; d="$(mk_tmp)"; for s in "$@"; do
  case "$s" in
    python3=real|python=real) printf '#!/bin/sh\nexec "%s" "$@"\n' "$REAL_PY" > "$d/${s%%=*}" ;;
    python3=stub|python=stub) printf '#!/bin/sh\necho stub >&2\nexit 49\n' > "$d/${s%%=*}" ;;
  esac; chmod +x "$d/${s%%=*}"; done; printf '%s' "$d"; }
# pick DIR -> PB_PY chosen with PATH=DIR only (bash by absolute path; the helper uses builtins and the python probes)
pick() { env -i PATH="$1" "$BASH_BIN" -c ". '$LIBSH'; pb_pybin; printf '%s' \"\$PB_PY\""; }

echo "AC9 pb_pybin"
assert_eq "AC9 python3 present is preferred" "python3" "$(pick "$(mkd python3=real python=real)")"
assert_eq "AC9 no python3, python present: falls back to python" "python" "$(pick "$(mkd python=real)")"
assert_eq "AC9 python3 stub that fails falls to python" "python" "$(pick "$(mkd python3=stub python=real)")"
assert_eq "AC9 neither works: empty" "" "$(pick "$(mkd python3=stub python=stub)")"
assert_eq "AC9 nothing at all: empty" "" "$(pick "$(mkd)")"
# a caller really runs through the fallback: evals/check-tasks.sh reports no SKIPPED(no python3) when only python exists
t_summary
