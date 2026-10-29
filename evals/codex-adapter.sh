#!/usr/bin/env bash
# The Codex adapter of the eval runners (v0.30.0; the shape of Run C1's adapter, moved into the repo).
#   codex-adapter.sh WORKDIR PROMPT-FILE [--pb-arm with|without] [CODEX-ARGS...]
# Runs `codex exec --sandbox workspace-write --skip-git-repo-check --json --ephemeral CODEX-ARGS... "<prompt>"` in WORKDIR
# (--json: the JSONL transcript that evals/codex-jsonl.js reads). The runners' codex preset (evals/lib-harness.sh) calls it
# with the model flag (-m M) and, with --arm or --repeat, --pb-arm ARM; --pb-arm never reaches codex.
# The with arm keeps HOME. The without arm gives codex a fresh HOME that holds only .codex/auth.json, copied from
# ${CODEX_HOME:-$HOME/.codex}, with CODEX_HOME=<fresh HOME>/.codex: ~/.codex/AGENTS.md, ~/.codex/config.toml and the skills in
# ~/.agents/skills stay out of reach. The fresh HOME is removed afterwards.
# BASH_XTRACEFD is unset first, so a traced caller cannot leak its trace into codex's shells (Run C1).
# Exit: codex's exit code | 2 usage | 3 environment (no codex on PATH, no auth.json for the without arm, mktemp failed).
set +x
unset BASH_XTRACEFD
set -u

die() { printf 'codex-adapter: %s\n' "$2" >&2; exit "$1"; }
[ $# -ge 2 ] || die 2 "usage: codex-adapter.sh WORKDIR PROMPT-FILE [--pb-arm with|without] [CODEX-ARGS...]"
wd="$1"; pf="$2"; shift 2
[ -d "$wd" ] || die 2 "no such workdir: $wd"
[ -f "$pf" ] || die 2 "no such prompt file: $pf"
arm=with
args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --pb-arm)
      [ $# -ge 2 ] || die 2 "--pb-arm needs with or without"
      case "$2" in with | without) arm="$2" ;; *) die 2 "--pb-arm needs with or without, got: $2" ;; esac
      shift 2 ;;
    *) args+=("$1"); shift ;;
  esac
done
command -v codex >/dev/null 2>&1 || die 3 "codex is not on PATH"
prompt="$(cat "$pf")"
cd "$wd" || die 3 "cannot cd to $wd"
flags=(exec --sandbox workspace-write --skip-git-repo-check --json --ephemeral)

if [ "$arm" = with ]; then
  codex "${flags[@]}" ${args[@]+"${args[@]}"} "$prompt"
  exit $?
fi

src="${CODEX_HOME:-$HOME/.codex}/auth.json"
[ -f "$src" ] || die 3 "the without arm needs $src (sign in to codex first)"
fh="$(mktemp -d "${TMPDIR:-/tmp}/pb-codex-home.XXXXXX")" || die 3 "mktemp failed"
trap 'rm -rf "$fh"' EXIT
mkdir -p "$fh/.codex" && cp "$src" "$fh/.codex/auth.json" || die 3 "cannot copy $src"
HOME="$fh" CODEX_HOME="$fh/.codex" codex "${flags[@]}" ${args[@]+"${args[@]}"} "$prompt"
exit $?
