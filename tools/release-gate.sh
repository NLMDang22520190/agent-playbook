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
# Variant (v0.32.0): a real run with --harness makes a detached git worktree of HEAD under ${TMPDIR:-/tmp}, passes --variant DIR to both
# runners (the "with" arm is that tree, so variant.sha in the results is HEAD) and removes it on every exit path (git worktree
# remove --force + prune, also on a runner's 2 or 3 and on INT/TERM). --cmd never gets --variant (its runs have no variant and fail
# the verdict). The environment passes through unchanged: PB_VARIANT_HOME selects the harness home the variant is installed into.
# Verdict (one function, over the pooled files): pass needs (a) every pooled file has a variant object with end_check "ok" and
# variant.sha = HEAD, (b) the full set: every scenario of AUTO in evals/run-evals.sh and every id of DEFAULT_TASKS below,
# (c) at least 5 graded runs (ERROR runs do not count) per item and arm, (d) tools/eval-delta.sh exits 0, (e) no delta whose 95%
# interval is wholly below 0. Otherwise fail, with one reason per broken rule, printed. A real run and --pool-only write
# DIR/gate.json (pb-gate/1 + variant, full_set, min_graded, verdict, verdict_reasons) and DIR/.gitignore (only *.json, *.md and
# .gitignore are committed), and rewrite local paths in DIR/*.json and *.md (repo root -> relative; HOME -> <home>; TMPDIR ->
# <tmp>; the variant dir -> <variant>; POSIX and, where cygpath exists, Windows forms) so no local path is committed.
# Real runs spend money: run it on purpose, on the release commit, after the tests pass.
# Exit: 0 verdict pass | 1 verdict fail | 2 usage, unknown scenario or task, a dirty tree, nothing to pool, or a runner's 2 |
#       3 environment (git, node) or a runner's 3.
set -u
DEFAULT_TASKS="pattern-15-erase-account-ambiguous,pattern-24-merge-duplicate-customers,pattern-26-consistent-price-rounding"

usage() { sed -n '2,/^set -u/p' "$0" | sed '/^set -u/d' | sed 's/^# \{0,1\}//' >&2; exit 2; }
die() { printf 'error: %s\n' "$2" >&2; exit "$1"; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)" || exit 3
HARNESS=""; CMD=""; MODEL=""; K=5; SCEN=""; TASKS=""; OD=""; MAXC=""; TMO=""; CLEAN=0; JSON=0; DRY=0; POOL=0; CHECK=0; REV=""; POS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help) usage ;;
    --clean-env) CLEAN=1 ;;
    --json) JSON=1 ;;
    --dry-run) DRY=1 ;;
    --pool-only) POOL=1 ;;
    --check) CHECK=1 ;;
    --harness | --cmd | --model | --k | --scenarios | --tasks | --out-dir | --max-cost | --timeout)
      [ $# -ge 2 ] || die 2 "$1 needs a value"
      case "$1" in
        --harness) HARNESS="$2" ;; --cmd) CMD="$2" ;; --model) MODEL="$2" ;; --k) K="$2" ;; --scenarios) SCEN="$2" ;;
        --tasks) TASKS="$2" ;; --out-dir) OD="$2" ;; --max-cost) MAXC="$2" ;; --timeout) TMO="$2" ;;
      esac
      shift ;;
    -*) die 2 "unknown option: $1 (see --help)" ;;
    *) POS+=("$1") ;;
  esac
  shift
done
[ "${#POS[@]}" -eq 0 ] || [ "$CHECK" = 1 ] || die 2 "unknown option: ${POS[0]} (see --help)"
[ "${#POS[@]}" -le 1 ] || die 2 "--check takes one REV, got: ${POS[*]}"
REV="${POS[0]:-}"

if [ "$CHECK" = 0 ]; then
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
[ -n "$TASKS" ] || TASKS="$DEFAULT_TASKS"
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
# build_args VARIANT_DIR -> B_ARGS and O_ARGS (--variant only with --harness)
build_args() {
  local v=(); [ -z "$HARNESS" ] || v=(--variant "$1")
  B_ARGS=(evals/run-evals.sh "${SEL[@]}" --model "$MODEL" --arm both --repeat "$K" --scenarios "$SCEN" --out "$OD/behaviour-$STAMP.md" ${PASS[@]+"${PASS[@]}"} ${v[@]+"${v[@]}"})
  O_ARGS=(evals/run-outcome.sh "${SEL[@]}" --model "$MODEL" --arm both --repeat "$K" --tasks "$TASKS" --out "$OD/outcome-$STAMP.md" ${PASS[@]+"${PASS[@]}"} ${v[@]+"${v[@]}"})
}
build_args "${TMPDIR:-/tmp}/pbgate.XXXXXX/variant"
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
fi

# jdoc POOLED SKIPPED DELTA_RC DELTA_OUT B_RC O_RC -> the pb-gate/1 object on stdout
jdoc() {
  PG_SHA="$SHA" PG_VER="$VER" PG_H="$LABEL" PG_M="$MODEL" PG_K="$K" PG_S="$SCEN" PG_T="$TASKS" PG_OD="$OD" PG_TREE="$TREE" \
  PG_DRY="$DRY" PG_POOL="$POOL" PG_B="$B_SHOW" PG_O="$O_SHOW" PG_POOLED="$1" PG_SKIPPED="$2" PG_DRC="$3" PG_DOUT="$4" \
  PG_BRC="$5" PG_ORC="$6" PG_AUTO="$AUTO" PG_DT="$DEFAULT_TASKS" node -e '
const fs = require("fs"), path = require("path");
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
const V = {};
if (e.PG_DRY !== "1") {
  const bad = [], seen = {}, cnt = {}, why = [];
  for (const f of lines(e.PG_POOLED)) {
    let j = {};
    try { j = JSON.parse(fs.readFileSync(f, "utf8")); } catch (x) { }
    const v = j.variant;
    if (!(v && typeof v === "object" && v.end_check === "ok" && v.sha === e.PG_SHA)) bad.push(path.basename(f));
    for (const r of j.runs || []) {
      seen[r.scenario] = 1;
      if (r.status === "graded") { const c = cnt[r.scenario] || (cnt[r.scenario] = {}); c[r.arm] = (c[r.arm] || 0) + 1; }
    }
  }
  const need = (e.PG_AUTO + " " + e.PG_DT).split(/[ ,]+/).filter(Boolean), miss = need.filter(s => !seen[s]), low = [];
  let min = null;
  for (const s of need) for (const a of ["with", "without"]) {
    if (!seen[s]) continue;
    const n = (cnt[s] || {})[a] || 0;
    if (min === null || n < min) min = n;
    if (n < 5) low.push(s + " " + a + " (" + n + ")");
  }
  const neg = [...new Set(rows.filter(r => r.hi !== null && r.hi < 0).map(r => r.scenario))];
  if (bad.length) why.push("variant: " + bad.length + " pooled file(s) lack a variant object with end_check ok and variant.sha = the gate commit (" + bad.join(", ") + ")");
  if (miss.length) why.push("full set: no runs for " + miss.join(", "));
  if (low.length) why.push("fewer than 5 graded runs per arm: " + low.join(", "));
  if (e.PG_DRC !== "0") why.push("tools/eval-delta.sh exited " + e.PG_DRC + " (an isolation check failed or the pooled files are unusable)");
  if (neg.length) why.push("delta wholly below 0 (95% interval) for " + neg.join(", "));
  Object.assign(V, { variant: bad.length === 0, full_set: miss.length === 0, min_graded: min === null ? 0 : min,
    verdict: why.length ? "fail" : "pass", verdict_reasons: why });
}
process.stdout.write(JSON.stringify({
  schema: "pb-gate/1", commit: e.PG_SHA, version: e.PG_VER || null, harness: e.PG_H, model: e.PG_M, k: Number(e.PG_K),
  scenarios: e.PG_S.split(","), tasks: e.PG_T.split(","), out_dir: e.PG_OD, tree: e.PG_TREE,
  dry_run: e.PG_DRY === "1", pool_only: e.PG_POOL === "1", commands: [e.PG_B, e.PG_O],
  runner_rc: { behaviour: num(e.PG_BRC), outcome: num(e.PG_ORC) },
  pooled: lines(e.PG_POOLED), skipped, delta_rc: num(e.PG_DRC), ...V, rows }, null, 2) + "\n");
'
}

# --check [REV] (v0.32.0): reads only the committed tree of REV, spends nothing, calls no runner
if [ "$CHECK" = 1 ]; then
  command -v git >/dev/null 2>&1 || die 3 "git is required"
  command -v node >/dev/null 2>&1 || die 3 "node (>= 18) is required"
  G=(git -c core.quotepath=off -C "$ROOT")
  RV="$("${G[@]}" rev-parse --verify -q "${REV:-HEAD}^{commit}" 2>/dev/null)" || die 3 "not a commit: ${REV:-HEAD}"
  CT="$(mktemp -d "${TMPDIR:-/tmp}/pbcheck.XXXXXX")" || die 3 "cannot make a temp dir"
  trap 'rm -rf "$CT"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  VER=""; LABEL=""; TREE=clean; B_SHOW=""; O_SHOW=""; SCEN=""; TASKS=""; OD=""; MODEL=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    mkdir -p "$CT/x/${f%/*}" && "${G[@]}" show "$RV:$f" > "$CT/x/$f" || die 3 "cannot read $f at $RV"
  done <<EOT
$("${G[@]}" ls-tree -r --name-only "$RV" evals/results 2>/dev/null | grep '^evals/results/gate-[^/]*/[^/]*\.json$')
EOT
  # one line per pb-evals/1 file: dir, playbook_commit, harness, model, file name
  GL="$(PG_X="$CT/x/evals/results" node -e '
const fs = require("fs"), b = process.env.PG_X, ls = d => { try { return fs.readdirSync(d).sort(); } catch (x) { return []; } };
for (const d of ls(b).filter(n => /^gate-/.test(n))) for (const n of ls(b + "/" + d).filter(n => n.endsWith(".json") && n !== "gate.json")) {
  let j = null;
  try { j = JSON.parse(fs.readFileSync(b + "/" + d + "/" + n, "utf8")); } catch (x) { }
  if (j && j.schema === "pb-evals/1" && Array.isArray(j.runs))
    console.log(["evals/results/" + d, j.playbook_commit, j.harness, j.model, n].map(String).join("\t"));
}')" || die 3 "node failed while grouping"
  TAB="$(printf '\t')"; WHY=""
  while IFS="$TAB" read -r d c h m; do
    [ -n "$d" ] || continue
    C12="$(printf '%s' "$c" | cut -c1-12)"; R=""
    if ! "${G[@]}" cat-file -e "$c^{commit}" 2>/dev/null; then R="gate commit $c is not in this repository"$'\n'
    else
      "${G[@]}" merge-base --is-ancestor "$c" "$RV" || R="gate commit $C12 is neither REV nor an ancestor of it"$'\n'
      X="$("${G[@]}" diff --no-renames --name-only "$c" "$RV" | grep -v '^evals/results/' | head -n 1)"
      [ -z "$X" ] || R="${R}changes outside evals/results since $C12: $X"$'\n'
      AUTO="$("${G[@]}" show "$c:evals/run-evals.sh" 2>/dev/null | sed -n 's/^AUTO="\(.*\)"$/\1/p' | head -n 1)"
      DEFAULT_TASKS="$("${G[@]}" show "$c:tools/release-gate.sh" 2>/dev/null | sed -n 's/^DEFAULT_TASKS="\(.*\)"$/\1/p' | head -n 1)"
      if [ -z "$AUTO" ] || [ -z "$DEFAULT_TASKS" ]; then R="${R}no AUTO list or DEFAULT_TASKS at $C12"$'\n'
      else
        FILES=()
        while IFS= read -r f; do FILES+=("$CT/x/$d/$f"); done <<EOT
$(printf '%s\n' "$GL" | awk -F'\t' -v k="$d	$c	$h	$m" '$1 "\t" $2 "\t" $3 "\t" $4 == k { print $5 }')
EOT
        DOUT="$(bash "$ROOT/tools/eval-delta.sh" "${FILES[@]}" 2>&1)"; DRC=$?
        SHA="$c"; LABEL="$h"; MODEL="$m"
        VR="$(jdoc "$(printf '%s\n' "${FILES[@]}")" "" "$DRC" "$DOUT" "" "" | node -e 'const j=JSON.parse(require("fs").readFileSync(0,"utf8"));console.log(j.verdict);console.log(j.min_graded);j.verdict_reasons.forEach(r=>console.log(r))')" || die 3 "node failed while computing the verdict"
        MING="$(printf '%s\n' "$VR" | sed -n 2p)"
        if [ "$(printf '%s\n' "$VR" | head -n 1)" != pass ]; then
          R="$R$(printf '%s\n' "$VR" | sed '1,2d')"$'\n'
          GV="$(node -e 'try{process.stdout.write(String(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).verdict))}catch(x){}' "$CT/x/$d/gate.json")"
          [ "$GV" != pass ] || R="${R}gate.json says pass, the recomputed verdict is fail"$'\n'
        fi
      fi
    fi
    if [ -z "$R" ]; then
      printf 'release gate: pass (commit %s, harness %s, model %s, min graded %s per arm, %s)\n' "$c" "$h" "$m" "$MING" "$d"
      exit 0
    fi
    WHY="$WHY$(printf '%s' "$R" | sed "s|^|$d (commit $C12, harness $h, model $m): |")"$'\n'
  done <<EOT
$(printf '%s\n' "$GL" | cut -f1-4 | sort -u)
EOT
  if [ -n "$WHY" ]; then printf '%s' "$WHY"; else printf 'no gate result under evals/results/gate-*/ at REV\n'; fi
  exit 1
fi

if [ "$DRY" = 1 ]; then
  if [ "$JSON" = 1 ]; then jdoc "" "" "" "" "" ""; exit $?; fi
  printf 'release gate (dry run): commit %s%s, harness %s, model %s, k=%s per arm\n' "$SHA" "${VER:+ (v$VER)}" "$LABEL" "$MODEL" "$K"
  printf 'tree: %s%s\n' "$TREE" "$([ "$TREE" = dirty ] && printf ' (a real run refuses it)')"
  printf 'out dir: %s/\n%s\n%s\n' "$OD" "$B_SHOW" "$O_SHOW"
  exit 0
fi

B_RC=""; O_RC=""; VT=""; VDIR=""
# cleanup: remove the variant worktree (idempotent); also on every exit and on INT/TERM
cleanup() {
  [ -z "$VT" ] || {
    git -C "$ROOT" worktree remove --force "$VDIR" >/dev/null 2>&1
    git -C "$ROOT" worktree prune >/dev/null 2>&1
    rm -rf "$VT"; VT=""
  }
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# rewrite_paths: local absolute paths in DIR/*.json and *.md -> repo-relative or <home>/<tmp>/<variant> (POSIX and Windows forms)
rewrite_paths() {
  local m="" p t
  for p in "$ROOT:." "${HOME:-}:<home>" "${TMPDIR:-/tmp}:<tmp>" "${VDIR:-}:<variant>"; do
    t="${p%%:*}"; [ "${#t}" -gt 1 ] || continue
    t="${t%/}"; p="$t:${p#*:}"
    m="$m$p"$'\n'
    if command -v cygpath >/dev/null 2>&1; then m="$m$(cygpath -m "$t"):${p#*:}"$'\n'"$(cygpath -w "$t"):${p#*:}"$'\n'; fi
  done
  PG_OD="$OD" PG_MAP="$m" node -e '
const fs = require("fs"), path = require("path"), e = process.env;
const esc = x => x.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const pairs = [];
for (const l of e.PG_MAP.split("\n")) {
  const i = l.lastIndexOf(":"); if (i < 2) continue;
  const f = l.slice(0, i), to = l.slice(i + 1);
  pairs.push([f, to], [f.replace(/\\/g, "\\\\"), to]);
}
pairs.sort((a, b) => b[0].length - a[0].length);
for (const n of fs.readdirSync(e.PG_OD)) {
  if (!/\.(json|md)$/.test(n)) continue;
  const f = path.join(e.PG_OD, n);
  let s = fs.readFileSync(f, "utf8"), o = s;
  for (const [from, to] of pairs)
    s = s.replace(new RegExp(esc(from) + "(?:(\\\\\\\\|[\\\\/])|(?![A-Za-z0-9_-]|\\.[A-Za-z0-9_-]))", "g"), (m, sep) => (to === "." ? (sep ? "" : ".") : to + (sep ? "/" : "")));
  if (s !== o) fs.writeFileSync(f, s);
}' || die 3 "node failed while rewriting paths"
}
if [ "$POOL" = 0 ]; then
  if [ "$TREE" = dirty ]; then
    printf '%s\n' "$DIRTY" >&2
    die 2 "the working tree is not clean (changes outside evals/results): commit or stash them, so the runs belong to $SHA"
  fi
  mkdir -p "$OD" || die 3 "cannot create $OD"
  if [ -n "$HARNESS" ]; then
    VT="$(mktemp -d "${TMPDIR:-/tmp}/pbgate.XXXXXX")" || die 3 "cannot make a temp dir"
    VDIR="$VT/variant"
    git -C "$ROOT" worktree add -q --detach "$VDIR" HEAD >/dev/null 2>&1 || die 3 "cannot make a worktree of HEAD at $VDIR"
    build_args "$VDIR"; B_SHOW="$(show "${B_ARGS[@]}")"; O_SHOW="$(show "${O_ARGS[@]}")"
  fi
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
  cleanup
fi

[ -d "$OD" ] && rewrite_paths
# pool: the pb-evals/1 files of this commit, harness and model
PL="$(PG_SHA="$SHA" PG_H="$LABEL" PG_M="$MODEL" PG_OD="$OD" node -e '
const fs = require("fs"), path = require("path"), e = process.env;
let names = [];
try { names = fs.readdirSync(e.PG_OD).filter(n => n.endsWith(".json") && n !== "gate.json").sort(); } catch (x) { }
for (const n of names) {
  const f = path.join(e.PG_OD, n);
  let j = null;
  try { j = JSON.parse(fs.readFileSync(f, "utf8")); } catch (x) { }
  let why = "";
  if (!j || typeof j !== "object" || j.schema !== "pb-evals/1" || !Array.isArray(j.runs)) why = "not a pb-evals/1 file";
  else if (j.playbook_commit !== e.PG_SHA) why = "other commit";
  else if (j.harness !== e.PG_H) why = "other harness";
  else if (j.model !== e.PG_M) why = "other model";
  // the bare name: node turns /tmp into a Windows path on Windows, so the shell adds $OD
  console.log(why ? "S" + n + " (" + why + ")" : "P" + n);
}')" || die 3 "node failed while pooling"
POOLED="$(printf '%s\n' "$PL" | awk -v d="$OD" 'sub(/^P/, "") { print d "/" $0 }')"
SKIPPED="$(printf '%s\n' "$PL" | awk -v d="$OD" 'sub(/^S/, "") { print d "/" $0 }')"
[ -n "$POOLED" ] || die 2 "nothing to pool in $OD for commit $SHA, harness $LABEL, model $MODEL"
FILES=()
while IFS= read -r f; do [ -n "$f" ] && FILES+=("$f"); done <<EOF
$POOLED
EOF
DOUT="$(bash "$ROOT/tools/eval-delta.sh" "${FILES[@]}" 2>&1)"; DRC=$?
case "$DRC" in 0 | 1) ;; 2) exit 2 ;; *) exit 3 ;; esac

printf '*\n!*.json\n!*.md\n!.gitignore\n' > "$OD/.gitignore"
jdoc "$POOLED" "$SKIPPED" "$DRC" "$DOUT" "$B_RC" "$O_RC" > "$OD/gate.json" || exit 3
rewrite_paths
VR="$(node -e 'const j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log(j.verdict);j.verdict_reasons.forEach(r=>console.log(r))' "$OD/gate.json")" || exit 3

if [ "$JSON" = 1 ]; then
  cat "$OD/gate.json"
else
  printf 'release gate: commit %s%s, harness %s, model %s, k=%s per arm\n' "$SHA" "${VER:+ (v$VER)}" "$LABEL" "$MODEL" "$K"
  printf '%s\n' "$POOLED" | sed 's/^/pooled: /'
  [ -z "$SKIPPED" ] || printf '%s\n' "$SKIPPED" | sed 's/^/skipped: /'
  printf '\n%s\n\nverdict: %s\n' "$DOUT" "$(printf '%s\n' "$VR" | head -n 1)"
  printf '%s\n' "$VR" | sed '1d; s/^/  - /'
fi
[ "$(printf '%s\n' "$VR" | head -n 1)" = pass ] && exit 0
exit 1
