#!/usr/bin/env bash
# Tests for fix round R7 of tools/release-gate.sh (v0.33.0; spec "Revision 10", "10b", "10c"; decisions D12): a real run reads the
# baseline (R7-1), a baseline that cannot be read fails closed (R7-2'/R7-2''), a flagged regression is confirmed once with K more
# with-arm runs and the pooled files decide (R7-3/R7-3'), gate.json records "confirm" (R7-4/R7-4'), --check recomputes from the
# committed files (R7-5). Fixture repos hold the real tools/release-gate.sh and tools/eval-delta.sh and RECORDING fake runners
# (written here; they honour --arm, --repeat and the list flag, and take per-call controls from the environment). A committed
# vX.Y.Z tag holds a baseline gate dir (a gate.json with a "pooled" list, a behaviour file over E1,E2,E3,E9 and an outcome file
# over the three default tasks, all 5/5 on check x). Never calls a real harness. Needs node and git.
# Controls (environment of the real run): FAKE_PASSES_<evals|outcome>_<N>="ITEM=P,ITEM=P" (the Nth real call of that runner: the first
# P of its K with-arm runs of ITEM pass check x; default K), FAKE_RC_<evals|outcome>_<N> (exit code of that call),
# FAKE_SAFEFAIL=ID,ID (the with-arm "nothing written outside the workdir" check FAILs), FAKE_VARIANT=changed.
. "$(dirname "$0")/lib.sh"
GATE="$PB_ROOT/tools/release-gate.sh"
command -v node >/dev/null 2>&1 || { t_skip 1 "node missing"; t_summary; exit $?; }
command -v git >/dev/null 2>&1 || { t_skip 1 "git missing"; t_summary; exit $?; }

W="$(mk_tmp)"
mkdir -p "$W/home" "$W/tmp" "$W/ctmp"
TASKS="pattern-15-erase-account-ambiguous,pattern-24-merge-duplicate-customers,pattern-26-consistent-price-rounding"
T15="pattern-15-erase-account-ambiguous"
BTAG="v0.32.0"

# gen.js: one pb-evals/1 file. Env: GN_OUT GN_COMMIT GN_ITEMS GN_ARMS (both|with) GN_N (runs per item and arm, default 5)
# GN_PASSES "ITEM=P,..." (with-arm runs 1..P pass check x, the rest FAIL; the without arm always FAILs x; default all N pass)
cat > "$W/gen.js" <<'EOF'
const fs = require("fs"), e = process.env;
const items = (e.GN_ITEMS || "").split(",").filter(Boolean), arms = e.GN_ARMS === "with" ? ["with"] : ["with", "without"];
const n = Number(e.GN_N || 5), pass = {};
for (const s of (e.GN_PASSES || "").split(",").filter(Boolean)) { const p = s.split("="); pass[p[0]] = Number(p[1]); }
const runs = [];
for (const item of items) for (const arm of arms) for (let i = 1; i <= n; i++) {
  const p = item in pass ? pass[item] : n;
  const x = arm === "with" && i <= p ? "PASS" : "FAIL";
  runs.push({ scenario: item, arm, k: i, label: item + "." + arm + "." + i, status: "graded", error: null, isolation: "adapter",
    fixture_tree: "t-" + item, prompt_sha: "p-" + item, cost_usd: 0.1, seconds: 5, notes: [], dropped_user_lines: 0,
    checks: [{ name: "x", key: "x", result: x },
      { name: "nothing written outside the workdir", key: "nothing written outside the workdir", result: "PASS" }] });
}
const o = { schema: "pb-evals/1", playbook_commit: e.GN_COMMIT, playbook_version: "0.33.0", harness: "claude", model: "m1",
  arms, repeat: n, max_cost: null, interactive: false, hooks: true, started: "2026-10-31T10:00:00Z", workroot: "<tmp>/w", out: "x.md",
  variant: { tree: "<variant>", version: "0.33.0", sha: e.GN_COMMIT, end_check: "ok" }, runs, summary: [] };
fs.writeFileSync(e.GN_OUT, JSON.stringify(o) + "\n");
EOF
# gen OUT COMMIT ITEMS [ARMS] [PASSES] [N]
gen() { GN_OUT="$1" GN_COMMIT="$2" GN_ITEMS="$3" GN_ARMS="${4:-both}" GN_PASSES="${5:-}" GN_N="${6:-5}" node "$W/gen.js"; }

# mk_fake REPO NAME LISTFLAG: the recording fake runner. Its lines in REPO's calls log: "<NAME> <args>"; its OBS lines show what the
# variant worktree looked like while it ran.
mk_fake() {
  local r="$1" name="$2" flag="$3"
  { printf '#!/usr/bin/env bash\nAUTO="E1 E2 E3"\nNAME=%s; LISTFLAG=%s; CALLS='"'%s'"'; OBS='"'%s'"'\n' "$name" "$flag" "$W/calls.${r##*/}.log" "$W/obs.${r##*/}.log"
    cat <<'EOF'
printf '%s %s\n' "$NAME" "$*" >> "$CALLS"
for a in "$@"; do [ "$a" = --preflight ] && exit 0; done
n="$(grep "^$NAME " "$CALLS" | grep -vc -- ' --preflight' || true)"
key="${NAME#run-}"; key="${key%.sh}"
out=""; k=1; arm=both; list=""; vdir=""; prev=""
for a in "$@"; do
  case "$prev" in
    --out) out="$a" ;; --repeat) k="$a" ;; --arm) arm="$a" ;; --variant) vdir="$a" ;; "$LISTFLAG") list="$a" ;;
  esac
  prev="$a"
done
repo="$(cd "$(dirname "$0")/.." && pwd)"
commit="$(git -C "$repo" rev-parse HEAD)"
vh=""; wtl=0
if [ -n "$vdir" ]; then
  vh="$(git -C "$vdir" rev-parse HEAD 2>/dev/null)"
  wtl="$(git -C "$repo" worktree list | grep -cF "$(basename "$vdir")")"
fi
printf 'OBS %s call=%s dir=%s head=%s listed=%s\n' "$NAME" "$n" "$vdir" "$vh" "$wtl" >> "$OBS"
printf 'fake-run %s call=%s\n' "$NAME" "$n"
rcv="FAKE_RC_${key}_$n"; rc="${!rcv:-0}"
[ "$rc" = 2 ] || [ "$rc" = 3 ] && exit "$rc"
pv="FAKE_PASSES_${key}_$n"; spec=",${!pv:-},"
runs=""; sep=""
for s in $(printf '%s' "$list" | tr ',' ' '); do
  p="$k"
  case "$spec" in *",$s="*) p="${spec#*,$s=}"; p="${p%%,*}" ;; esac
  i=1
  while [ "$i" -le "$k" ]; do
    for a in with without; do
      [ "$arm" = with ] && [ "$a" = without ] && continue
      r=FAIL; [ "$a" = with ] && [ "$i" -le "$p" ] && r=PASS
      sf=PASS; case ",${FAKE_SAFEFAIL:-}," in *",$s,"*) [ "$a" = with ] && sf=FAIL ;; esac
      runs="$runs$sep{\"scenario\":\"$s\",\"arm\":\"$a\",\"k\":$i,\"label\":\"$s.$a.$i\",\"status\":\"graded\",\"error\":null,\"isolation\":\"adapter\",\"fixture_tree\":\"t-$s\",\"prompt_sha\":\"p-$s\",\"cost_usd\":0.1,\"seconds\":5,\"notes\":[],\"dropped_user_lines\":0,\"checks\":[{\"name\":\"x\",\"key\":\"x\",\"result\":\"$r\"},{\"name\":\"nothing written outside the workdir\",\"key\":\"nothing written outside the workdir\",\"result\":\"$sf\"}]}"
      sep=","
    done
    i=$((i + 1))
  done
done
ve=ok; [ "${FAKE_VARIANT:-ok}" = changed ] && ve=changed
armsj='["with","without"]'; [ "$arm" = with ] && armsj='["with"]'
mkdir -p "$(dirname "$out")"
printf '# fake\n' > "$out"
printf '{"schema":"pb-evals/1","playbook_commit":"%s","playbook_version":"0.33.0","harness":"claude","model":"m1","arms":%s,"repeat":%s,"max_cost":null,"interactive":false,"hooks":true,"started":"2026-10-31T10:00:00Z","workroot":"<tmp>/w","out":"x.md","variant":{"tree":"<variant>","version":"0.33.0","sha":"%s","end_check":"%s"},"runs":[%s],"summary":[]}\n' \
  "$commit" "$armsj" "$k" "$vh" "$ve" "$runs" > "${out%.md}.json"
exit "$rc"
EOF
  } > "$r/evals/$name"
  chmod 755 "$r/evals/$name"
}
gate_scen() { # FILE LIST: GATE_SCENARIOS line replaced, or inserted before DEFAULT_TASKS
  local f="$1" l="$2" t
  t="$(mktemp)" || return 1
  if grep -q '^GATE_SCENARIOS=' "$f"; then sed "s/^GATE_SCENARIOS=.*/GATE_SCENARIOS=\"$l\"/" "$f" > "$t"
  else awk -v l="$l" '/^DEFAULT_TASKS=/ && !d { print "GATE_SCENARIOS=\"" l "\""; d = 1 } { print }' "$f" > "$t"; fi
  cat "$t" > "$f"; rm -f "$t"
}
hd() { git -C "$1" rev-parse HEAD; }
gcommit() { printf '%s\n' "$3" > "$1/$2"; git -C "$1" add -A && git -C "$1" commit -qm "$4"; }
# base_dir REPO MODE: a baseline gate dir for HEAD of REPO (not committed). MODE: ok | nopooled | missing (the outcome file named in
# "pooled" does not exist) | corrupt (the behaviour file is not JSON)
base_dir() {
  local r="$1" mode="$2" c d pl
  c="$(hd "$r")"; d="$r/evals/results/gate-$(printf '%s' "$c" | cut -c1-12)"; mkdir -p "$d"
  gen "$d/behaviour-m1.json" "$c" "E1,E2,E3,E9"
  gen "$d/outcome-m1.json" "$c" "$TASKS"
  pl="[\"evals/results/${d##*/}/behaviour-m1.json\",\"evals/results/${d##*/}/outcome-m1.json\"]"
  case "$mode" in
    nopooled) printf '{"schema":"pb-gate/1","commit":"%s","verdict":"pass","verdict_reasons":[]}\n' "$c" > "$d/gate.json" ;;
    *) printf '{"schema":"pb-gate/1","commit":"%s","verdict":"pass","verdict_reasons":[],"pooled":%s}\n' "$c" "$pl" > "$d/gate.json" ;;
  esac
  case "$mode" in
    missing) rm -f "$d/outcome-m1.json" ;;
    corrupt) printf '{not json\n' > "$d/behaviour-m1.json" ;;
  esac
}
# build NAME MODE -> $W/NAME: commit A (tools, fakes, tasks), a results commit with the baseline gate dir for A tagged v0.32.0
# (MODE as in base_dir; older: a good v0.31.0 baseline for A, then A2 and a broken v0.32.0 baseline for A2), then commit C = HEAD.
build() {
  local r="$W/$1" mode="$2" t
  mkdir -p "$r/tools" "$r/evals/tasks"
  cp -p "$GATE" "$r/tools/release-gate.sh"; gate_scen "$r/tools/release-gate.sh" "E1 E2 E3"
  cp -p "$PB_ROOT/tools/eval-delta.sh" "$r/tools/eval-delta.sh"
  for t in $(printf '%s' "$TASKS" | tr ',' ' '); do mkdir -p "$r/evals/tasks/$t"; printf 'x\n' > "$r/evals/tasks/$t/prompt.md"; done
  mk_fake "$r" run-evals.sh --scenarios
  mk_fake "$r" run-outcome.sh --tasks
  printf '# fixture\n' > "$r/README.md"
  ( cd "$r" && git init -q && git config user.email t@example.invalid && git config user.name tester &&
    git config commit.gpgsign false && git config tag.gpgsign false && git config core.autocrlf false && git add -A && git commit -qm base ) || t_bad "fixture $1" "git init failed"
  if [ "$mode" = older ]; then
    base_dir "$r" ok; git -C "$r" add -A && git -C "$r" commit -qm "results v0.31.0" && git -C "$r" tag v0.31.0
    gcommit "$r" README.md "# a2" "a2"
    base_dir "$r" missing
  else
    base_dir "$r" "$mode"
  fi
  git -C "$r" add -A && git -C "$r" commit -qm "results $BTAG" && git -C "$r" tag "$BTAG"
  gcommit "$r" README.md "# c" "c"
}
# rr REPO CASE "ENV" ARGS... -> a real run into evals/results/gate-CASE: OUT RC ODN GJ CALLS OBS
rr() {
  local r="$1" c="$2" e="$3"; shift 3
  ODN="$r/evals/results/gate-$c"; GJ="$ODN/gate.json"
  CALLS="$W/calls.${r##*/}.log"; OBS="$W/obs.${r##*/}.log"; : > "$CALLS"; : > "$OBS"
  RC=0; OUT="$(cd "$r" && env $e HOME="$W/home" TMPDIR="$W/tmp" bash tools/release-gate.sh --harness claude --model m1 --out-dir "evals/results/gate-$c" "$@" 2>&1)" || RC=$?
}
chk() { local r="$1"; shift; RC=0; OUT="$(cd "$r" && env HOME="$W/home" TMPDIR="$W/ctmp" bash tools/release-gate.sh --check "$@" 2>&1)" || RC=$?; }
pool() { # REPO DIRNAME -> the real --pool-only on evals/results/DIRNAME
  local r="$1" d="$2"; ODN="$r/evals/results/$d"; GJ="$ODN/gate.json"
  RC=0; OUT="$(cd "$r" && env HOME="$W/home" TMPDIR="$W/tmp" bash tools/release-gate.sh --harness claude --model m1 --pool-only --out-dir "evals/results/$d" 2>&1)" || RC=$?
}
gj() {
  [ -f "$1" ] || { echo MISSING; return 0; }
  node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);const v=eval(process.argv[1]);console.log(typeof v==="object"?JSON.stringify(v):String(v))}catch(e){console.log("BAD "+e.message)}})' "$2" < "$1"
}
# real (non-preflight) calls of a runner: count, and the Nth line
nreal() { grep "^$1 " "$CALLS" 2>/dev/null | grep -vc -- ' --preflight' || true; }
real_line() { grep "^$1 " "$CALLS" 2>/dev/null | grep -v -- ' --preflight' | sed -n "$2p"; }
n_obs() { grep -c "^OBS $1 " "$OBS" 2>/dev/null || true; }
leftovers() { ls "$W/tmp" 2>/dev/null | grep -c '^pbbase\.\|^pbgate\.' || true; }
reasons() { gj "$GJ" 'j.verdict_reasons.join("\n")'; }
has_words() { # NAME LINE WORD... : every word is in LINE
  local n="$1" l="$2" w; shift 2
  for w in "$@"; do case "$l" in *"$w"*) ;; *) t_bad "$n" "missing [$w] in [$l]"; return 0 ;; esac; done
  t_ok "$n"
}
# commit_dir REPO DIRNAME : commit a gate dir the real run wrote (its .gitignore keeps only *.json, *.md and itself)
commit_dir() { git -C "$1" add -- "evals/results/$2" && git -C "$1" commit -qm "results $2"; }

build rk ok
R="$W/rk"; SHA="$(hd "$R")"; SHA12="$(printf '%s' "$SHA" | cut -c1-12)"
RB="$BTAG"

echo "R7 fixture sanity: the baseline tag is readable and a control run with equal rates passes (no flag, no confirmation)"
assert_eq "fixture: tag $BTAG exists and holds a gate dir with a gate.json that has a pooled list" "2" "$(git -C "$R" show "$BTAG:evals/results/$(git -C "$R" ls-tree --name-only "$BTAG" evals/results/ | head -n 1 | sed 's|.*/||')/gate.json" | node -e 'console.log(JSON.parse(require("fs").readFileSync(0,"utf8")).pooled.length)')"
rr "$R" ctl ""
assert_rc "R7 control: a run equal to the baseline -> exit 0" 0
assert_eq "R7 control: verdict pass" "pass" "$(gj "$GJ" j.verdict)"
assert_eq "R7 control: no confirmation ran: gate.json has \"confirm\": null" "null" "$(gj "$GJ" 'String(j.confirm)')"
assert_eq "R7 control: one real call per runner" "1|1" "$(nreal run-evals.sh)|$(nreal run-outcome.sh)"
assert_not_contains "R7 control: no confirmation line in the output" "$OUT" "-confirm:"

# ===========================================================================================================================
echo "R7-3/R7-4/R7-1' case 1: baseline 5/5, first run 2/5, the confirmation also 2/5 -> fail with the pooled counts"
rr "$R" c1 "FAKE_PASSES_evals_1=E1=2 FAKE_PASSES_evals_2=E1=2"
assert_rc "R7-3 (1) flagged and still regressing after the confirmation -> exit 1" 1
assert_eq "R7-3 (1) gate.json verdict is fail" "fail" "$(gj "$GJ" j.verdict)"
assert_contains "R7-3 (1) the final reason is a regression vs $RB on the pooled counts (4/10)" "$(reasons)" "regression vs $RB: E1 x: with 5/5 -> 4/10"
assert_eq "R7-3 (1) the only reason is that one regression" "1" "$(gj "$GJ" j.verdict_reasons.length)"
assert_eq "R7-4 (1) confirm.items names the flagged item" '["E1"]' "$(gj "$GJ" 'j.confirm && j.confirm.items')"
assert_eq "R7-4 (1) confirm.repeat is K" "5" "$(gj "$GJ" 'j.confirm && j.confirm.repeat')"
assert_eq "R7-4' (1) confirm.first_reasons is the one first-run regression line (-> 2/5)" "1|true" "$(gj "$GJ" 'j.confirm ? [j.confirm.first_reasons.length, /regression vs '"$RB"': E1 x: with 5\/5 -> 2\/5/.test(j.confirm.first_reasons[0])].join("|") : "no confirm"')"
assert_eq "R7-4' (1) confirm.commands has the one confirmation command" "1" "$(gj "$GJ" 'j.confirm && j.confirm.commands.length')"
has_words "R7-4' (1) the recorded command is the with-arm run of E1 only" "$(gj "$GJ" 'j.confirm && j.confirm.commands.join(" ")')" "evals/run-evals.sh" "--arm with" "--repeat 5" "--scenarios E1"
assert_eq "R7-4' (1) confirm.runner_rc: behaviour 0, outcome null" '{"behaviour":0,"outcome":null}' "$(gj "$GJ" 'j.confirm && j.confirm.runner_rc')"
assert_eq "R7-3 (1) run-evals.sh was called exactly twice (the first run and one confirmation)" "2" "$(nreal run-evals.sh)"
assert_eq "R7-3 (1) no outcome-confirm call: no task was flagged (run-outcome.sh once)" "1" "$(nreal run-outcome.sh)"
CL="$(real_line run-evals.sh 2)"
has_words "R7-3 (1) the second run-evals call: --arm with, --repeat 5, the same harness, model, hooks, variant" "$CL" "--arm with" "--repeat 5" "--harness claude" "--model m1" "--hooks" "--variant "
assert_eq "R7-3 (1) the second call selects --scenarios E1 only (not E2, E3)" "1" "$(printf '%s\n' "$CL" | grep -Ec -- '--scenarios E1( |$)')"
assert_eq "R7-3 (1) the second call has its own out name behaviour-confirm-<stamp>.md" "1" "$(printf '%s\n' "$CL" | grep -c -- 'behaviour-confirm-[^ ]*\.md')"
assert_eq "R7-1' (1) the confirmation's OBS line: variant worktree still listed (listed=1)" "1" "$(grep '^OBS run-evals.sh call=2 ' "$OBS" | grep -c 'listed=1')"
assert_eq "R7-1' (1) the confirmation's OBS line: variant head = the gate commit" "1" "$(grep '^OBS run-evals.sh call=2 ' "$OBS" | grep -c "head=$SHA ")"
assert_eq "R7-3 (1) the confirmation file is pooled (behaviour-confirm-*.json in DIR)" "1" "$(ls "$ODN" | grep -c '^behaviour-confirm-.*\.json$')"
assert_eq "R7-3 (1) gate.json pooled lists 3 files, one of them the confirmation" "3|1" "$(gj "$GJ" '[j.pooled.length, j.pooled.filter(p=>/behaviour-confirm-/.test(p)).length].join("|")')"
assert_contains "R7-4 (1) the text output prints the confirmation command before it runs (== behaviour-confirm: ...)" "$OUT" "== behaviour-confirm: bash evals/run-evals.sh"
assert_contains "R7-3 (1) the human output has the final reason" "$OUT" "regression vs $RB: E1 x: with 5/5 -> 4/10"
assert_eq "R7-1' (1) after the gate: the variant worktree is gone (only the main one)" "1" "$(git -C "$R" worktree list | wc -l | tr -d ' ')"
assert_eq "R7-1 (1) after the gate: no pbbase/pbgate temp dir is left" "0" "$(leftovers)"

# ===========================================================================================================================
echo "R7-3 case 2: the confirmation is 5/5 -> pooled 7/10 vs 5/5 is not a regression -> pass, confirm recorded"
build rk2 ok
R2="$W/rk2"
rr "$R2" cf2 "FAKE_PASSES_evals_1=E1=2 FAKE_PASSES_evals_2=E1=5"
assert_rc "R7-3 (2) pooled 7/10 -> exit 0" 0
assert_eq "R7-3 (2) verdict pass, no reasons" "pass|" "$(gj "$GJ" 'j.verdict+"|"+j.verdict_reasons.join("|")')"
assert_eq "R7-4 (2) confirm is recorded: items [E1], repeat 5" '["E1"]|5' "$(gj "$GJ" 'j.confirm ? JSON.stringify(j.confirm.items)+"|"+j.confirm.repeat : "no confirm"')"
assert_eq "R7-4' (2) confirm.first_reasons names the 2/5 regression that triggered it" "1|true" "$(gj "$GJ" 'j.confirm ? [j.confirm.first_reasons.length, /E1 x: with 5\/5 -> 2\/5/.test(j.confirm.first_reasons[0])].join("|") : "no confirm"')"
assert_eq "R7-3 (2) two run-evals calls, one run-outcome call" "2|1" "$(nreal run-evals.sh)|$(nreal run-outcome.sh)"
assert_eq "R7-3 (2) gate.json pooled lists the confirmation file too" "3" "$(gj "$GJ" j.pooled.length)"
assert_eq "R7-3 (2) the baseline is recorded (tag $RB)" "$RB" "$(gj "$GJ" j.baseline.tag)"

echo "R7-5 case 8: --check on the committed dir of the confirmed run gives the gate.json verdict (pass)"
commit_dir "$R2" gate-cf2
chk "$R2"
assert_rc "R7-5 (8) --check on the committed confirmed run -> exit 0 (the confirmation file is pooled)" 0
assert_contains "R7-5 (8) the pass line names the dir" "$OUT" "evals/results/gate-cf2)"
assert_not_contains "R7-5 (8) no disagreement with gate.json" "$OUT" "gate.json says pass"
echo "R7-5 case 8b: --check on the committed dir of the failed confirmed run (case 1) gives fail, same as its gate.json"
build rk1 ok
R1="$W/rk1"
rr "$R1" cf1 "FAKE_PASSES_evals_1=E1=2 FAKE_PASSES_evals_2=E1=2"
V1="$(gj "$GJ" j.verdict)"; RS1="$(reasons)"
commit_dir "$R1" gate-cf1
chk "$R1"
assert_eq "R7-5 (8b) fixture: the real run says fail" "fail" "$V1"
assert_rc "R7-5 (8b) --check -> exit 1 (same verdict as gate.json)" 1
assert_contains "R7-5 (8b) --check prints the gate.json reason (pooled counts, confirmation included)" "$OUT" "$RS1"
assert_not_contains "R7-5 (8b) fail on both sides: no 'gate.json says pass' disagreement" "$OUT" "gate.json says pass"

# ===========================================================================================================================
echo "R7-3 case 1b/1c: a flagged task is confirmed through run-outcome.sh --tasks (outcome-confirm); a scenario and a task flagged -> two confirmations"
rr "$R" c1b "FAKE_PASSES_outcome_1=$T15=2"
assert_rc "R7-3 (1b) a task confirmed at 5/5 -> pass, exit 0" 0
assert_eq "R7-4 (1b) confirm.items is the task id" "[\"$T15\"]" "$(gj "$GJ" 'j.confirm && j.confirm.items')"
assert_eq "R7-3 (1b) run-evals.sh once, run-outcome.sh twice" "1|2" "$(nreal run-evals.sh)|$(nreal run-outcome.sh)"
OL="$(real_line run-outcome.sh 2)"
has_words "R7-3 (1b) the second run-outcome call: --arm with, --repeat 5, the one flagged task, outcome-confirm out name" "$OL" "--arm with" "--repeat 5" "--tasks $T15" "--harness claude" "--model m1" "--variant " "outcome-confirm-"
assert_eq "R7-3 (1b) the second call selects exactly that task (--tasks $T15 and no other)" "1" "$(printf '%s\n' "$OL" | grep -Ec -- "--tasks $T15( |\$)")"
assert_eq "R7-4' (1b) confirm.runner_rc: behaviour null, outcome 0" '{"behaviour":null,"outcome":0}' "$(gj "$GJ" 'j.confirm && j.confirm.runner_rc')"
assert_contains "R7-4 (1b) the output prints the outcome-confirm command" "$OUT" "== outcome-confirm: bash evals/run-outcome.sh"
rr "$R" c1c "FAKE_PASSES_evals_1=E1=2 FAKE_PASSES_outcome_1=$T15=2"
assert_rc "R7-3 (1c) both confirmed at 5/5 -> exit 0" 0
assert_eq "R7-4 (1c) confirm.items has both, sorted (scenario first)" "[\"E1\",\"$T15\"]" "$(gj "$GJ" 'j.confirm && j.confirm.items')"
assert_eq "R7-3 (1c) two calls of each runner" "2|2" "$(nreal run-evals.sh)|$(nreal run-outcome.sh)"

# ===========================================================================================================================
echo "R7-3 case 3: a regression plus another failing rule -> no confirmation (D12), verdict fail, confirm null"
rr "$R" c3 "FAKE_PASSES_evals_1=E1=2 FAKE_SAFEFAIL=E2"
assert_rc "R7-3 (3) regression and a safety floor -> exit 1" 1
assert_eq "R7-3 (3) verdict fail" "fail" "$(gj "$GJ" j.verdict)"
assert_contains "R7-3 (3) the regression reason is there (first-run counts 2/5)" "$(reasons)" "regression vs $RB: E1 x: with 5/5 -> 2/5"
assert_contains "R7-3 (3) the safety floor reason is there" "$(reasons)" "safety floor: E2 nothing written outside the workdir"
assert_eq "R7-3 (3) no confirmation call: one run-evals call, one run-outcome call" "1|1" "$(nreal run-evals.sh)|$(nreal run-outcome.sh)"
assert_eq "R7-4 (3) gate.json has \"confirm\": null" "null" "$(gj "$GJ" 'String(j.confirm)')"
rr "$R" c3b "FAKE_PASSES_evals_1=E1=2 FAKE_VARIANT=changed"
assert_rc "R7-3 (3b) regression plus rule (a) (variant end_check changed) -> exit 1" 1
assert_eq "R7-3 (3b) no confirmation call" "1|1" "$(nreal run-evals.sh)|$(nreal run-outcome.sh)"
assert_eq "R7-4 (3b) confirm is null" "null" "$(gj "$GJ" 'String(j.confirm)')"

# ===========================================================================================================================
echo "R7-1 case 4: the baseline is read in a real run (a run at 2/5 against a 5/5 baseline used to pass). Flagged item outside the gate set: no confirmation, fail with the first reasons"
mkdir -p "$R/evals/results/gate-c4"
gen "$R/evals/results/gate-c4/behaviour-earlier.json" "$SHA" "E9" both "E9=2"
rr "$R" c4 ""
assert_rc "R7-1 (4) E9 at 2/5 (an earlier batch in DIR) against the 5/5 baseline -> exit 1 (today: 0)" 1
assert_eq "R7-1 (4) verdict fail" "fail" "$(gj "$GJ" j.verdict)"
assert_eq "R7-1 (4) the reason is the first one: E9 x with 5/5 -> 2/5" "regression vs $RB: E9 x: with 5/5 -> 2/5" "$(reasons)"
assert_eq "R7-3' (4) E9 is in neither GATE_SCENARIOS nor the tasks: no confirmation call" "1|1" "$(nreal run-evals.sh)|$(nreal run-outcome.sh)"
assert_eq "R7-4 (4) confirm is null" "null" "$(gj "$GJ" 'String(j.confirm)')"
assert_eq "R7-1 (4) gate.json names the baseline" "$RB" "$(gj "$GJ" j.baseline.tag)"

# ===========================================================================================================================
echo "R7-6 case 6: a confirmation runner exiting 3 (or 2) stops the gate, no gate.json, the message says the dir is incomplete"
rr "$R" c6 "FAKE_PASSES_evals_1=E1=2 FAKE_RC_evals_2=3"
assert_rc "R7-3' (6) confirmation runner exit 3 -> gate exit 3" 3
assert_no_path "R7-3' (6) no gate.json in DIR" "$GJ"
case "$(printf '%s' "$OUT" | tr 'A-Z' 'a-z')" in *"incomplete confirmation"*) t_ok "R7-3' (6) the message says DIR holds an incomplete confirmation" ;; *) t_bad "R7-3' (6) the message says DIR holds an incomplete confirmation" "output: $OUT" ;; esac
assert_eq "R7-3' (6) the confirmation was started (2 run-evals calls)" "2" "$(nreal run-evals.sh)"
assert_eq "R7-1' (6) the variant worktree and temp dirs are cleaned on that exit path" "1|0" "$(git -C "$R" worktree list | wc -l | tr -d ' ')|$(leftovers)"
rr "$R" c6b "FAKE_PASSES_evals_1=E1=2 FAKE_RC_evals_2=2"
assert_rc "R7-3' (6b) confirmation runner exit 2 -> gate exit 2" 2
assert_no_path "R7-3' (6b) no gate.json in DIR" "$GJ"

# ===========================================================================================================================
echo "R7-2'/R7-2'' case 5: a baseline that cannot be read fails closed: real run exit 3 before any runner call; --pool-only and --check fail naming it; no fall-through"
chk_broken() { # NAME MODE REASON
  local n="$1" mode="$2" why="$3" r="$W/b-$1"
  build "b-$n" "$mode"
  rr "$r" bk ""
  assert_rc "R7-2'' ($n) real run -> exit 3" 3
  assert_contains "R7-2'' ($n) the output prints [$why]" "$OUT" "$why"
  assert_eq "R7-2' ($n) the runner record is empty: no runner (preflight included) was called" "0" "$(grep -c . "$CALLS" || true)"
  assert_no_path "R7-2' ($n) no gate.json written" "$GJ"
  assert_eq "R7-2' ($n) no worktree and no temp dir left" "1|0" "$(git -C "$r" worktree list | wc -l | tr -d ' ')|$(leftovers)"
  # a committed gate dir for the commit at HEAD, pooled by the real tool: --pool-only and --check see the same baseline
  mkdir -p "$r/evals/results/gate-bk2"
  gen "$r/evals/results/gate-bk2/behaviour-m1.json" "$(hd "$r")" "E1,E2,E3"
  gen "$r/evals/results/gate-bk2/outcome-m1.json" "$(hd "$r")" "$TASKS"
  pool "$r" gate-bk2
  assert_rc "R7-2'' ($n) --pool-only -> exit 1 (verdict fail)" 1
  assert_eq "R7-2'' ($n) --pool-only: the reason is in gate.json" "1" "$(reasons | grep -cF -- "$why")"
  commit_dir "$r" gate-bk2
  chk "$r"
  assert_rc "R7-2'' ($n) --check -> exit 1" 1
  assert_contains "R7-2'' ($n) --check names [$why]" "$OUT" "$why"
  case "$OUT" in *"release gate: pass"*) t_bad "R7-2'' ($n) --check prints no pass line" "$OUT" ;; *) t_ok "R7-2'' ($n) --check prints no pass line" ;; esac
}
chk_broken nopooled nopooled "baseline $RB: gate.json has no pooled list"
chk_broken missing missing "baseline $RB: cannot read outcome-m1.json"
chk_broken corrupt corrupt "baseline $RB: cannot read behaviour-m1.json"
chk_broken older older "baseline $RB: cannot read outcome-m1.json"
RO="$W/b-older"
assert_eq "R7-2'' (older) fixture: an older tag v0.31.0 with a good baseline exists and is not used" "v0.31.0" "$(git -C "$RO" tag -l 'v0.31.0')"

# ===========================================================================================================================
echo "R7-6 (m7) case 7: a both-arm file and a with-only confirmation file pooled through the real tools/eval-delta.sh: the verdict is computed"
mkdir -p "$R/evals/results/gate-c7"
gen "$R/evals/results/gate-c7/behaviour-first.json" "$SHA" "E1,E2,E3"
gen "$R/evals/results/gate-c7/outcome-first.json" "$SHA" "$TASKS"
gen "$R/evals/results/gate-c7/behaviour-confirm-x.json" "$SHA" "E1" with
pool "$R" gate-c7
case "$RC" in 0 | 1) t_ok "R7-6 (7) --pool-only exits 0 or 1 (a verdict), not 2: eval-delta takes the mixed-arm set" ;; *) t_bad "R7-6 (7) --pool-only exits 0 or 1 (a verdict), not 2" "exit $RC: $OUT" ;; esac
assert_eq "R7-6 (7) gate.json has a verdict and 3 pooled files" "true|3" "$(gj "$GJ" '[j.verdict==="pass"||j.verdict==="fail", j.pooled.length].join("|")')"
assert_eq "R7-6 (7) eval-delta ran (delta_rc 0 or 1)" "true" "$(gj "$GJ" 'j.delta_rc===0||j.delta_rc===1')"
assert_eq "R7-6 (7) a with-only confirmation file raises E1 with to 10 graded runs: min_graded is 5 (without arm)" "5" "$(gj "$GJ" j.min_graded)"

# ===========================================================================================================================
echo "R7-3' case 9: --json: confirmation logs are separate files (behaviour-confirm-<stamp>.log), the first logs are not overwritten"
build rkj ok
RJ="$W/rkj"
rr "$RJ" cj "FAKE_PASSES_evals_1=E1=2 FAKE_PASSES_evals_2=E1=5" --json
assert_rc "R7-3' (9) --json confirmed pass -> exit 0" 0
printf '%s\n' "$OUT" > "$W/cj.out.json"
assert_eq "R7-4 (9) the printed JSON has the confirm object (items [E1])" '["E1"]' "$(gj "$W/cj.out.json" 'j.confirm && j.confirm.items')"
assert_eq "R7-3' (9) one confirmation log: behaviour-confirm-*.log" "1" "$(ls "$ODN" | grep -c '^behaviour-confirm-.*\.log$')"
assert_eq "R7-3' (9) one first behaviour log (behaviour-<stamp>.log)" "1" "$(ls "$ODN" | grep -c '^behaviour-[0-9].*\.log$')"
FL="$(ls "$ODN"/behaviour-[0-9]*.log 2>/dev/null | head -n 1)"; CLG="$(ls "$ODN"/behaviour-confirm-*.log 2>/dev/null | head -n 1)"
assert_contains "R7-3' (9) the first log still holds the first call's output (call=1)" "$(cat "$FL" 2>/dev/null)" "fake-run run-evals.sh call=1"
assert_contains "R7-3' (9) the confirmation log holds the confirmation call's output (call=2)" "$(cat "$CLG" 2>/dev/null)" "fake-run run-evals.sh call=2"
assert_eq "R7-3' (9) the confirmation json and md are separate files too" "1|1" "$(ls "$ODN" | grep -c '^behaviour-confirm-.*\.json$')|$(ls "$ODN" | grep -c '^behaviour-confirm-.*\.md$')"

t_summary
