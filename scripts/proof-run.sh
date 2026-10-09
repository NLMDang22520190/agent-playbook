#!/usr/bin/env bash
# Run a command and print a verbatim, redacted evidence block (markdown) for pasting into
# answers, PRs and issues. The full redacted log is stored with its sha256.
#   proof-run.sh [--label NAME] [--tail N] [--dir DIR] -- COMMAND [ARGS...]
# Exit code = the command's exit code (so failures stay visible to callers).
# Exit 2 usage. Default log dir: <project>/.agents/handoff/evidence
set -u
. "$(dirname "$0")/lib.sh"

label="run"
tail_n=40
dir=""
while [ $# -gt 0 ]; do
  case "$1" in
    --label) [ $# -ge 2 ] || pb_die "--label needs a value" 2; label="$2"; shift 2 ;;
    --tail)  [ $# -ge 2 ] || pb_die "--tail needs a value" 2; tail_n="$2"; shift 2 ;;
    --dir)   [ $# -ge 2 ] || pb_die "--dir needs a value" 2; dir="$2"; shift 2 ;;
    --) shift; break ;;
    *) pb_die "usage: proof-run.sh [--label NAME] [--tail N] [--dir DIR] -- COMMAND [ARGS...]" 2 ;;
  esac
done
[ $# -ge 1 ] || pb_die "usage: proof-run.sh [--label NAME] [--tail N] [--dir DIR] -- COMMAND [ARGS...]" 2
case "$tail_n" in ''|*[!0-9]*) pb_die "--tail must be a number" 2 ;; esac

safe_label="$(printf '%s' "$label" | tr -c 'A-Za-z0-9._-' '-')"
[ -n "$dir" ] || dir="$(pb_root_dir)/.agents/handoff/evidence"
mkdir -p "$dir" || pb_die "cannot create $dir" 3
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
log="$dir/$stamp-$safe_label.log"
n=0
while [ -e "$log" ]; do n=$((n + 1)); log="$dir/$stamp-$safe_label.$n.log"; done

raw="$(mktemp "${TMPDIR:-/tmp}/pbproof.XXXXXX")" || pb_die "mktemp failed" 3
trap 'rm -f "$raw"' EXIT

"$@" > "$raw" 2>&1
rc=$?

pb_redact < "$raw" > "$log"
lines="$(wc -l < "$log" | tr -d ' ')"
digest="$(pb_sha256 < "$log")"

if sha="$(git rev-parse --short HEAD 2>/dev/null)"; then
  [ -n "$(git status --porcelain 2>/dev/null)" ] && sha="$sha+dirty"
else
  sha="n/a"
fi

cmdline="$(printf '%s' "$*" | pb_redact)"

printf '### Evidence: %s\n' "$label"
printf -- '- command: `%s`\n' "$cmdline"
printf -- '- exit: %s\n' "$rc"
printf -- '- time (UTC): %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf -- '- git: %s\n' "$sha"
printf -- '- full log: %s (sha256: %s, %s lines)\n' "$log" "$digest" "$lines"
printf '```text\n'
tail -n "$tail_n" "$log"
printf '```\n'
exit "$rc"
