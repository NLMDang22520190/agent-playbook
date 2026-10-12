#!/usr/bin/env bash
# Run suites with one-true-awk first on PATH: the awk macOS ships, so BSD awk problems show up before CI.
#   tools/bsd-check.sh [SUITE...]      (default: tests/run-all.sh, everything)
# Suite paths are relative to the repo root (the script runs from there), e.g. tests/test-learn.sh.
# Uses `original-awk`, else `nawk`, linked as `awk` in a temp dir put first on PATH (a copy when links fail).
# Also links bash 3.2 (the bash macOS ships) as `bash` in that dir, so nested `bash tests/...` calls use it: PB_BASH32, else
# ~/.local/bin/bash3.2, else `bash3.2` on PATH (build one with tools/get-bash32.sh). Prints "bsd-check: bash is <path>";
# without one it prints a hint and runs with the bash on PATH.
# Prints the awk it used. Exit: the suites' exit code; 2 when neither awk is installed (apt install original-awk).
set -u
cd "$(dirname "$0")/.." || exit 3

src=""; name=""
for c in original-awk nawk; do
  p="$(command -v "$c" 2>/dev/null)" || p=""
  [ -n "$p" ] && { src="$p"; name="$c"; break; }
done
if [ -z "$src" ]; then
  echo "bsd-check: no one-true-awk found (original-awk or nawk). Install it: apt install original-awk (Ubuntu, WSL) or use macOS's own awk." >&2
  exit 2
fi

base="${TMPDIR:-/tmp}"; base="${base%/}"
AWKD="$(mktemp -d "$base/pbbsdawk.XXXXXX")" || exit 3
trap 'rm -rf "$AWKD"' EXIT
ln -s "$src" "$AWKD/awk" 2>/dev/null && [ -x "$AWKD/awk" ] || { rm -f "$AWKD/awk"; cp "$src" "$AWKD/awk" && chmod +x "$AWKD/awk"; } || exit 3
echo "bsd-check: awk is $name ($src)"

b32=""
if [ -n "${PB_BASH32:-}" ] && [ -x "$PB_BASH32" ]; then b32="$PB_BASH32"
elif [ -x "${HOME:-/nonexistent}/.local/bin/bash3.2" ]; then b32="$HOME/.local/bin/bash3.2"
else b32="$(command -v bash3.2 2>/dev/null)" || b32=""; fi
if [ -n "$b32" ]; then
  ln -s "$b32" "$AWKD/bash" 2>/dev/null && [ -x "$AWKD/bash" ] || { rm -f "$AWKD/bash"; cp "$b32" "$AWKD/bash" && chmod +x "$AWKD/bash"; } || exit 3
  echo "bsd-check: bash is $b32"
else
  echo "bsd-check: no bash 3.2 found; the suites run under $(command -v bash). Build one with tools/get-bash32.sh (installs ~/.local/bin/bash3.2) to match macOS." >&2
fi
export PATH="$AWKD:$PATH"

if [ "$#" -eq 0 ]; then
  bash tests/run-all.sh; rc=$?
else
  rc=0
  for s in "$@"; do
    bash "$s" || rc=$?
  done
fi
exit "$rc"
