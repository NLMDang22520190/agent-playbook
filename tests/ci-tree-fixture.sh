#!/usr/bin/env bash
# Shared setup of tests/test-ci-tree-tested.sh and its split part (test-ci-tree-tested-steps.sh; split in v0.24.1 so that neither part is the
# floor of a CI shard): the fake gh, the JSON builders, world and tool. Source it after lib.sh. It is not a suite: run-all.sh only starts
# tests/test-*.sh.
TOOL="$PB_ROOT/tools/ci-tree-tested.sh"

W="$(mk_tmp)"; BIN="$W/bin"; DATA="$W/data"; LOG="$W/log"; mkdir -p "$BIN" "$DATA"

# ---- fake gh: `gh api repos/...[?query]` answered from $FAKE_DATA/<path with / as _>[_hs_<head_sha>] ----
# FAKE_FAIL=<text>: a request whose path contains <text> exits 1 (HTTP error); FAKE_BAD=<text>: prints text that is not JSON.
# --jq / -q are applied with jq when jq exists, else ignored (the whole JSON is printed).
cat > "$BIN/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >> "$FAKE_LOG"
[ "${1:-}" = api ] || { echo "fake gh: only 'gh api' is allowed, got: $*" >&2; exit 1; }
path=""; expr=""; prev=""
for a in "$@"; do
  case "$a" in repos/* | /repos/*) path="${a#/}" ;; esac
  case "$prev" in --jq | -q) expr="$a" ;; esac
  prev="$a"
done
[ -n "$path" ] || { echo "fake gh: no repos/ path in: $*" >&2; exit 1; }
if [ -n "${FAKE_FAIL:-}" ]; then case "$path" in *"$FAKE_FAIL"*) echo "gh: HTTP 500 (simulated)" >&2; exit 1 ;; esac; fi
if [ -n "${FAKE_BAD:-}" ]; then case "$path" in *"$FAKE_BAD"*) echo '{"this is": not json,'; exit 0 ;; esac; fi
key="${path%%\?*}"
f="${key//\//_}"   # builtins only: this fake runs once per gh call (no tr, no cat)
case "$path" in *head_sha=*) hs="${path#*head_sha=}"; hs="${hs%%&*}"; f="${f}_hs_$hs" ;; esac
[ -f "$FAKE_DATA/$f" ] || { echo "gh: HTTP 404 Not Found ($path)" >&2; exit 1; }
# read -d '' returns 1 at end of file: fine here (no set -e in this fake); the fixtures hold no NUL byte
if [ -n "$expr" ] && command -v jq >/dev/null 2>&1; then jq -r "$expr" < "$FAKE_DATA/$f"; else IFS= read -r -d '' body < "$FAKE_DATA/$f"; printf '%s' "$body"; fi
EOF
chmod +x "$BIN/gh"

R="own/repo"
h40() { printf '%040d' "$1"; }          # 40 digits are a valid hex sha
SHA="$(h40 1)"; PAR="$(h40 2)"; HEAD="$(h40 3)"; TREE="$(h40 4)"
NAMES=("test (ubuntu-latest)" "test (macos-latest)" "test (windows-latest)" "windows shard 1/6" "windows shard 2/6" "windows shard 3/6" "windows shard 4/6" "windows shard 5/6" "windows shard 6/6")

# put KEYPATH JSON -> the response of `gh api <KEYPATH>` (query string left out; runs also by head sha: use put_runs)
put() { local v="$2"; printf '%s\n' "${v//$'\r'/}" > "$DATA/${1//\//_}"; }
put_runs() { put_raw "repos/$R/actions/workflows/test.yml/runs" "$1" "$2"; }
put_raw() { printf '%s\n' "$3" > "$DATA/${1//\//_}_hs_$2"; }
pull_json() { # NUMBER HEADSHA [REPO] [BASEREF]  (REPO "null" = a deleted head repository; the PR is closed: it is merged)
  local b="${4:-main}"
  if [ "${3:-}" = null ]; then printf '{"number":%s,"state":"closed","base":{"ref":"%s"},"head":{"sha":"%s","repo":null}}' "$1" "$b" "$2"
  else printf '{"number":%s,"state":"closed","base":{"ref":"%s"},"head":{"sha":"%s","repo":{"full_name":"%s"}}}' "$1" "$b" "$2" "${3:-$R}"; fi
}
run_json() { # ID HEADSHA [CONCLUSION] [LISTED-BASEREF]  (pull_requests[] is empty: GitHub lists only OPEN PRs there)
  local prs='[]'
  [ -n "${4:-}" ] && prs="[{\"number\":7,\"base\":{\"ref\":\"$4\"}}]"
  printf '{"id":%s,"head_sha":"%s","event":"pull_request","status":"completed","conclusion":"%s","pull_requests":%s}' "$1" "$2" "${3:-success}" "$prs"
}
runs_json() { printf '{"total_count":%s,"workflow_runs":[%s]}' "$1" "$2"; }
jobs_json() { # MODE NAME [STEPKIND]: MODE ok (all nine success) | skipped|failure|cancelled NAME | missing NAME
  # | steps NAME STEPKIND: the jobs are all success; NAME's step list is changed (v0.23.0 AC5.3):
  #   docsonly (only a Docs-only checks step), both (full step skipped + Docs-only success), fullskipped (full step skipped, no other),
  #   fullfailed (full step failure), fullmissing (setup steps only), nosteps (no steps field), fullcancelled, fullnotdone
  # Every other suite job has the full step with conclusion success.
  local mode="${1:-ok}" bad="${2:-}" kind="${3:-}" out="" sep="" n c st steps
  for n in "${NAMES[@]}"; do
    c=success
    if [ "$n" = "$bad" ]; then
      case "$mode" in missing) continue ;; steps) ;; *) c="$mode" ;; esac
    fi
    st=completed
    if [ "$n" = "$bad" ] && [ "$mode" = notcompleted ]; then c=success; st=in_progress; fi
    steps="$(steps_json "$n" "$([ "$n" = "$bad" ] && [ "$mode" = steps ] && echo "$kind" || echo full)")"
    out="$out$sep{\"name\":\"$n\",\"status\":\"$st\",\"conclusion\":\"$c\"$steps}"; sep=","
  done
  # jobs that are not required checks never matter (the PR run skips reuse and main-ci)
  out="$out$sep{\"name\":\"reuse\",\"status\":\"completed\",\"conclusion\":\"skipped\"},{\"name\":\"main-ci\",\"status\":\"completed\",\"conclusion\":\"skipped\"}"
  printf '{"total_count":11,"jobs":[%s]}' "$out"
}
# step_one NAME CONCLUSION NUMBER [STATUS]
step_one() { printf '{"name":"%s","status":"%s","conclusion":"%s","number":%s}' "$1" "${4:-completed}" "$2" "$3"; }
# steps_json JOBNAME KIND -> ,"steps":[...] for the eight suite jobs (the aggregator has none), "" for others
steps_json() {
  local n="$1" kind="$2" full='Tests and static checks' pre
  case "$n" in "test (windows-latest)") return 0 ;; "windows shard "*) full='Tests and static checks (shard)' ;; esac
  pre="$(step_one 'Set up job' success 1),$(step_one 'Run actions/checkout@v5' success 2)"
  case "$kind" in
    full)        printf ',"steps":[%s,%s]' "$pre" "$(step_one "$full" success 3)" ;;
    docsonly)    printf ',"steps":[%s,%s]' "$pre" "$(step_one 'Docs-only checks' success 3)" ;;
    both)        printf ',"steps":[%s,%s,%s]' "$pre" "$(step_one "$full" skipped 3)" "$(step_one 'Docs-only checks' success 4)" ;;
    fullskipped) printf ',"steps":[%s,%s]' "$pre" "$(step_one "$full" skipped 3)" ;;
    fullfailed)  printf ',"steps":[%s,%s]' "$pre" "$(step_one "$full" failure 3)" ;;
    fullcancelled) printf ',"steps":[%s,%s]' "$pre" "$(step_one "$full" cancelled 3)" ;;
    fullnotdone) printf ',"steps":[%s,%s]' "$pre" "$(step_one "$full" success 3 in_progress)" ;;
    fullmissing) printf ',"steps":[%s]' "$pre" ;;
    nosteps)     return 0 ;;
  esac
}
commit_json() { printf '{"sha":"%s","tree":{"sha":"%s"},"parents":[{"sha":"%s"}]}' "$1" "$2" "$3"; }
compare_json() { printf '{"status":"%s","ahead_by":1,"behind_by":%s}' "$1" "$2"; }

# world -> the happy path: merge commit SHA of a same-repo PR (head HEAD) whose run 111 was green; same tree; parent is an ancestor of HEAD
world() {
  rm -rf "$DATA"; mkdir -p "$DATA"; : > "$LOG"
  put "repos/$R/commits/$SHA/pulls" "[$(pull_json 7 "$HEAD")]"
  put_runs "$HEAD" "$(runs_json 1 "$(run_json 111 "$HEAD")")"
  put "repos/$R/actions/runs/111/jobs" "$(jobs_json ok)"
  put "repos/$R/git/commits/$SHA" "$(commit_json "$SHA" "$TREE" "$PAR")"
  put "repos/$R/git/commits/$HEAD" "$(commit_json "$HEAD" "$TREE" "$PAR")"
  put "repos/$R/compare/$PAR...$HEAD" "$(compare_json ahead 0)"
}
# tool ARGS... -> OUT = stdout only, RC = exit code; the fake gh is first on PATH
tool() {
  OUT="$(PATH="$BIN:$PATH" FAKE_DATA="$DATA" FAKE_LOG="$LOG" bash "$TOOL" "$@" 2>/dev/null)"; RC=$?
}
logged() { grep -cF -- "$1" "$LOG" 2>/dev/null || true; }
nothing() { # NAME -> exit 0 and empty stdout
  assert_rc "AC6.1 $1: exit 0" 0
  assert_eq "AC6.1 $1: prints nothing" "" "$OUT"
}
