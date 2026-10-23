#!/usr/bin/env bash
# Opt-in installer for tools/pre-commit (maintainers and contributors of this repo; run it yourself, nothing calls it).
#   tools/install-hooks.sh              copy tools/pre-commit to <hooks dir>/pre-commit
#   tools/install-hooks.sh --force      also replace an existing pre-commit hook that is different
#   tools/install-hooks.sh --uninstall  remove the hook, only when it is exactly the one this script installs
# <hooks dir> is `git rev-parse --git-path hooks` of this repository, so a linked worktree installs into the shared hooks dir.
# The hook is a copy (a symlink needs rights Git for Windows often lacks); re-run after the hook changes.
# Exit: 0 done (also: already installed, or nothing to uninstall), 1 refused (a different pre-commit exists without --force,
# or --uninstall found a hook that is not ours), 2 usage or not a git checkout or tools/pre-commit missing.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
SRC="$ROOT/tools/pre-commit"
usage() { echo "usage: tools/install-hooks.sh [--force | --uninstall]" >&2; exit 2; }

force=0; un=0
while [ $# -gt 0 ]; do
  case "$1" in
    --force) force=1 ;;
    --uninstall) un=1 ;;
    *) usage ;;
  esac
  shift
done
[ "$force" -eq 0 ] || [ "$un" -eq 0 ] || usage

hd="$(cd "$ROOT" && git rev-parse --git-path hooks 2>/dev/null)" || { echo "install-hooks: $ROOT is not a git checkout" >&2; exit 2; }
case "$hd" in /* | [A-Za-z]:*) ;; *) hd="$ROOT/$hd" ;; esac
dst="$hd/pre-commit"
same() { cmp -s "$SRC" "$dst"; }

if [ "$un" -eq 1 ]; then
  [ -e "$dst" ] || [ -L "$dst" ] || { echo "install-hooks: no pre-commit hook at $dst; nothing to do"; exit 0; }
  [ -f "$SRC" ] && same || { echo "install-hooks: $dst is not the hook this script installs; left alone" >&2; exit 1; }
  rm -f "$dst" && echo "install-hooks: removed $dst"
  exit 0
fi

[ -f "$SRC" ] || { echo "install-hooks: $SRC not found" >&2; exit 2; }
if [ -e "$dst" ] || [ -L "$dst" ]; then
  if same; then echo "install-hooks: already installed: $dst"; chmod +x "$dst"; exit 0; fi
  if [ "$force" -ne 1 ]; then
    echo "install-hooks: $dst exists and is different; not overwritten (use --force to replace it)" >&2
    exit 1
  fi
  rm -f "$dst"
fi
mkdir -p "$hd" && cp "$SRC" "$dst" && chmod +x "$dst" || { echo "install-hooks: cannot write $dst" >&2; exit 2; }
echo "install-hooks: installed $dst (remove with tools/install-hooks.sh --uninstall)"
