#!/usr/bin/env bash
# The reproducible release gate (v0.30.0): both arms of the behaviour evals and of the separating outcome tasks, k >= 5, on
# the exact commit that will be released, then the Δ per check with 95% intervals from the runs of that commit only.
#   tools/release-gate.sh (--harness claude|codex|opencode | --cmd "COMMAND") --model M [--k K] [--scenarios E1,E2]
#                         [--tasks id1,id2] [--out-dir DIR] [--max-cost USD] [--timeout SECONDS] [--clean-env]
#                         [--json] [--dry-run | --pool-only]
# Runs, from the repository root:
#   bash evals/run-evals.sh   <harness> --model M --arm both --repeat K --scenarios <AUTO list of run-evals.sh> --out DIR/behaviour-<stamp>.md
#   bash evals/run-outcome.sh <harness> --model M --arm both --repeat K --tasks <the separating tasks> --out DIR/outcome-<stamp>.md
# with --max-cost, --timeout and --clean-env passed to both (--max-cost caps each runner). K defaults to 5; less than 5 is
# refused, because with k=3 per arm most 95% intervals include 0. The separating tasks are the outcome tasks whose Δ excluded 0
# in v0.29.0: pattern-15-erase-account-ambiguous, pattern-24-merge-duplicate-customers, pattern-26-consistent-price-rounding.
# DIR defaults to evals/results/gate-<first 12 hex of HEAD>. A runner that exits 0, 1 (a FAIL) or 4 (ERROR runs, left out of
# n) lets the gate go on; 2 or 3 stops it with that code.
# Pooling: every DIR/*.json is read; a pb-evals/1 file whose playbook_commit is HEAD and whose harness ("custom" for --cmd)
# and model match is pooled ("pooled: FILE"), any other is listed as "skipped: FILE (reason)" (not a pb-evals/1 file, other
# commit, other harness, other model). The pooled files go to tools/eval-delta.sh in one call, whose tables follow (Wilson
# 95% per arm, Newcombe 95% for Δ with its verdict, cost per passed run). Another batch on the same commit adds to n.
# A real run refuses a working tree with any change outside evals/results (tracked or untracked): the runs must belong to HEAD.
# --dry-run prints the commit, the tree state ("tree: clean" or "tree: dirty") and both commands, and runs nothing.
# --pool-only runs no harness and pools what DIR holds. --json prints one JSON object instead (schema pb-gate/1: commit,
# version, harness, model, k, scenarios, tasks, out_dir, tree, dry_run, pool_only, commands, runner_rc, pooled, skipped
# [{file, reason}], delta_rc, rows [{scenario, check, delta, lo, hi, verdict}] from the Newcombe table); the runners' output
# then goes to DIR/<kind>-<stamp>.log.
# Real runs spend money: run it on purpose, on the release commit, after the tests pass.
# Exit: tools/eval-delta.sh's code (0, or 1 when an isolation check FAILed) | 2 usage, unknown scenario or task, a dirty tree,
#       nothing to pool, or a runner's 2 | 3 environment (git, node) or a runner's 3.
set -u

usage() { sed -n '2,/^set -u/p' "$0" | sed '/^set -u/d' | sed 's/^# \{0,1\}//' >&2; exit 2; }
die() { printf 'error: %s\n' "$2" >&2; exit "$1"; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)" || exit 3
HARNESS=""; CMD=""; MODEL=""; K=5; SCEN=""; TASKS=""; OD=""; MAXC=""; TMO=""; CLEAN=0; JSON=0; DRY=0; POOL=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help) usage ;;
    --clean-env) CLEAN=1 ;;
    --json) JSON=1 ;;
    --dry-run) DRY=1 ;;
    --pool-only) POOL=1 ;;
    --harness | --cmd | --model | --k | --scenarios | --tasks | --out-dir | --max-cost | --timeout)
      [ $# -ge 2 ] || die 2 "$1 needs a value"
      case "$1" in
        --harness) HARNESS="$2" ;; --cmd) CMD="$2" ;; --model) MODEL="$2" ;; --k) K="$2" ;; --scenarios) SCEN="$2" ;;
        --tasks) TASKS="$2" ;; --out-dir) OD="$2" ;; --max-cost) MAXC="$2" ;; --timeout) TMO="$2" ;;
      esac
      shift ;;
    *) die 2 "unknown option: $1 (see --help)" ;;
  esac
  shift
done

if [ -n "$HARNESS" ] && [ -n "$CMD" ]; then die 2 "use either --harness or --cmd, not both"; fi
case "$HARNESS" in
  "") [ -n "$CMD" ] || die 2 "--harness or --cmd is required"; LABEL=custom ;;
  claude | codex | opencode) LABEL="$HARNESS" ;;
  *) die 2 "unknown harness: $HARNESS (use claude, codex, opencode or --cmd)" ;;
esac
[ -n "$MODEL" ] || die 2 "--model is required (the results must name the model to be pooled)"
case "$K" in "" | *[!0-9]* | 0*) die 2 "--k needs a whole number of at least 5, got: $K" ;; esac
[ "$K" -ge 5 ] && [ "$K" -le 99 ] || die 2 "--k must be at least 5 (and at most 99), got: $K"
[ "$DRY" = 1 ] && [ "$POOL" = 1 ] && die 2 "use either --dry-run or --pool-only"
command -v git >/dev/null 2>&1 || die 3 "git is required"
command -v node >/dev/null 2>&1 || die 3 "node (>= 18) is required"

AUTO="$(sed -n 's/^AUTO="\(.*\)"$/\1/p' "$ROOT/evals/run-evals.sh" | head -n 1)"
[ -n "$AUTO" ] || die 3 "no AUTO list in evals/run-evals.sh"
if [ -z "$SCEN" ]; then SCEN="$(printf '%s' "$AUTO" | tr -s ' ' ',')"; fi
for s in $(printf '%s' "$SCEN" | tr ',' ' '); do
  case " $AUTO " in *" $s "*) ;; *) die 2 "scenario $s is not in the AUTO list of evals/run-evals.sh" ;; esac
done
[ -n "$TASKS" ] || TASKS="pattern-15-erase-account-ambiguous,pattern-24-merge-duplicate-customers,pattern-26-consistent-price-rounding"
for t in $(printf '%s' "$TASKS" | tr ',' ' '); do
  case "$t" in "" | */* | .*) die 2 "bad task id: $t" ;; esac
  [ -d "$ROOT/evals/tasks/$t" ] || die 2 "unknown task: $t (no evals/tasks/$t)"
done

SHA="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)" || die 3 "not a git repository: $ROOT"
VER=""; [ -f "$ROOT/VERSION" ] && VER="$(tr -d ' \r\n' < "$ROOT/VERSION")"
[ -n "$OD" ] || OD="$ROOT/evals/results/gate-$(printf '%s' "$SHA" | cut -c1-12)"
case "$OD" in /*) ;; *) OD="$(pwd)/$OD" ;; esac
DIRTY="$(git -C "$ROOT" -c core.quotepath=off status --porcelain --untracked-files=all 2>/dev/null | grep -v '^.. "\{0,1\}evals/results/')"
TREE=clean; [ -z "$DIRTY" ] || TREE=dirty

STAMP="$(date -u +%Y%m%dT%H%M%SZ)-$$"
SEL=(); if [ -n "$HARNESS" ]; then SEL=(--harness "$HARNESS"); else SEL=(--cmd "$CMD"); fi
PASS=()
[ -z "$MAXC" ] || PASS+=(--max-cost "$MAXC")
[ -z "$TMO" ] || PASS+=(--timeout "$TMO")
[ "$CLEAN" = 0 ] || PASS+=(--clean-env)
B_ARGS=(evals/run-evals.sh "${SEL[@]}" --model "$MODEL" --arm both --repeat "$K" --scenarios "$SCEN" --out "$OD/behaviour-$STAMP.md" ${PASS[@]+"${PASS[@]}"})
O_ARGS=(evals/run-outcome.sh "${SEL[@]}" --model "$MODEL" --arm both --repeat "$K" --tasks "$TASKS" --out "$OD/outcome-$STAMP.md" ${PASS[@]+"${PASS[@]}"})
# show ARGS... -> "bash ARGS..." for display, quoting only the words that need it
show() {
  local out="bash" a
  for a in "$@"; do
    case "$a" in "" | *[!A-Za-z0-9_./,=:@%+-]*) a="$(printf '%q' "$a")" ;; esac
    out="$out $a"
  done
  printf '%s' "$out"
}
B_SHOW="$(show "${B_ARGS[@]}")"; O_SHOW="$(show "${O_ARGS[@]}")"

# jdoc POOLED SKIPPED DELTA_RC DELTA_OUT B_RC O_RC -> the pb-gate/1 object on stdout
jdoc() {
  PG_SHA="$SHA" PG_VER="$VER" PG_H="$LABEL" PG_M="$MODEL" PG_K="$K" PG_S="$SCEN" PG_T="$TASKS" PG_OD="$OD" PG_TREE="$TREE" \
  PG_DRY="$DRY" PG_POOL="$POOL" PG_B="$B_SHOW" PG_O="$O_SHOW" PG_POOLED="$1" PG_SKIPPED="$2" PG_DRC="$3" PG_DOUT="$4" \
  PG_BRC="$5" PG_ORC="$6" node -e '
const e = process.env, lines = s => s.split("\n").filter(Boolean), num = s => s === "" ? null : Number(s);
const rows = [];
let on = false;
for (const l of e.PG_DOUT.split("\n")) {
  if (/^## /.test(l)) { on = l.startsWith("## Δ with a 95% interval"); continue; }
  if (!on || !/^\| /.test(l) || /^\| Scenario /.test(l) || /^\|---/.test(l)) continue;
  const c = l.slice(2, -2).split(/ (?<!\\)\| /).map(x => x.replace(/\\\|/g, "|"));
  const m = /^\[(-?[0-9.]+), (-?[0-9.]+)\]$/.exec(c[3] || "");
  rows.push({ scenario: c[0], check: c[1], delta: Number(c[2]), lo: m ? Number(m[1]) : null, hi: m ? Number(m[2]) : null, verdict: c[4] });
}
const skipped = lines(e.PG_SKIPPED).map(l => { const i = l.lastIndexOf(" ("); return { file: l.slice(0, i), reason: l.slice(i + 2, -1) }; });
process.stdout.write(JSON.stringify({
  schema: "pb-gate/1", commit: e.PG_SHA, version: e.PG_VER || null, harness: e.PG_H, model: e.PG_M, k: Number(e.PG_K),
  scenarios: e.PG_S.split(","), tasks: e.PG_T.split(","), out_dir: e.PG_OD, tree: e.PG_TREE,
  dry_run: e.PG_DRY === "1", pool_only: e.PG_POOL === "1", commands: [e.PG_B, e.PG_O],
  runner_rc: { behaviour: num(e.PG_BRC), outcome: num(e.PG_ORC) },
  pooled: lines(e.PG_POOLED), skipped, delta_rc: num(e.PG_DRC), rows }, null, 2) + "\n");
'
}

if [ "$DRY" = 1 ]; then
  if [ "$JSON" = 1 ]; then jdoc "" "" "" "" "" ""; exit $?; fi
  printf 'release gate (dry run): commit %s%s, harness %s, model %s, k=%s per arm\n' "$SHA" "${VER:+ (v$VER)}" "$LABEL" "$MODEL" "$K"
  printf 'tree: %s%s\n' "$TREE" "$([ "$TREE" = dirty ] && printf ' (a real run refuses it)')"
  printf 'out dir: %s/\n%s\n%s\n' "$OD" "$B_SHOW" "$O_SHOW"
  exit 0
fi

B_RC=""; O_RC=""
if [ "$POOL" = 0 ]; then
  if [ "$TREE" = dirty ]; then
    printf '%s\n' "$DIRTY" >&2
    die 2 "the working tree is not clean (changes outside evals/results): commit or stash them, so the runs belong to $SHA"
  fi
  mkdir -p "$OD" || die 3 "cannot create $OD"
  # run_one KIND ARGS... -> the runner's exit code in RC; 2 and 3 stop the gate
  run_one() {
    local kind="$1"; shift
    if [ "$JSON" = 1 ]; then (cd "$ROOT" && bash "$@") > "$OD/$kind-$STAMP.log" 2>&1; RC=$?
    else printf '== %s: %s\n' "$kind" "$(show "$@")"; (cd "$ROOT" && bash "$@"); RC=$?; fi
    case "$RC" in
      0 | 1 | 4) ;;
      2 | 3) die "$RC" "$kind runner exited $RC; the gate stops" ;;
      *) die 3 "$kind runner exited $RC; the gate stops" ;;
    esac
  }
  run_one behaviour "${B_ARGS[@]}"; B_RC="$RC"
  run_one outcome "${O_ARGS[@]}"; O_RC="$RC"
fi

# pool: the pb-evals/1 files of this commit, harness and model
PL="$(PG_SHA="$SHA" PG_H="$LABEL" PG_M="$MODEL" PG_OD="$OD" node -e '
const fs = require("fs"), path = require("path"), e = process.env;
let names = [];
try { names = fs.readdirSync(e.PG_OD).filter(n => n.endsWith(".json")).sort(); } catch (x) { }
for (const n of names) {
  const f = path.join(e.PG_OD, n);
  let j = null;
  try { j = JSON.parse(fs.readFileSync(f, "utf8")); } catch (x) { }
  let why = "";
  if (!j || typeof j !== "object" || j.schema !== "pb-evals/1" || !Array.isArray(j.runs)) why = "not a pb-evals/1 file";
  else if (j.playbook_commit !== e.PG_SHA) why = "other commit";
  else if (j.harness !== e.PG_H) why = "other harness";
  else if (j.model !== e.PG_M) why = "other model";
  console.log(why ? "S" + f + " (" + why + ")" : "P" + f);
}')" || die 3 "node failed while pooling"
POOLED="$(printf '%s\n' "$PL" | sed -n 's/^P//p')"
SKIPPED="$(printf '%s\n' "$PL" | sed -n 's/^S//p')"
[ -n "$POOLED" ] || die 2 "nothing to pool in $OD for commit $SHA, harness $LABEL, model $MODEL"
FILES=()
while IFS= read -r f; do [ -n "$f" ] && FILES+=("$f"); done <<EOF
$POOLED
EOF
DOUT="$(bash "$ROOT/tools/eval-delta.sh" "${FILES[@]}" 2>&1)"; DRC=$?

if [ "$JSON" = 1 ]; then
  jdoc "$POOLED" "$SKIPPED" "$DRC" "$DOUT" "$B_RC" "$O_RC" || exit 3
else
  printf 'release gate: commit %s%s, harness %s, model %s, k=%s per arm\n' "$SHA" "${VER:+ (v$VER)}" "$LABEL" "$MODEL" "$K"
  printf '%s\n' "$POOLED" | sed 's/^/pooled: /'
  [ -z "$SKIPPED" ] || printf '%s\n' "$SKIPPED" | sed 's/^/skipped: /'
  printf '\n%s\n' "$DOUT"
fi
case "$DRC" in 0 | 1) exit "$DRC" ;; 2) exit 2 ;; *) exit 3 ;; esac
