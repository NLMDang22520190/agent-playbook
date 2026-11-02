#!/usr/bin/env bash
# Tests for slice B2 of tools/release-gate.sh (v0.34.0; spec .agents/handoff/01-spec.md P1 and F1; decisions D6 and D5):
#   P1/D6: a real run starts the behaviour and the outcome runner in PARALLEL; with --harness the gate installs the variant ONCE
#          (lock held, evals/lib-harness.sh pbh_variant_begin), passes --variant-held VDIR (never --variant) to both runners, and restores
#          the snapshot once, after the last runner and the confirmation, on every exit path; --cmd has no variant but is parallel too;
#          a runner's 2 or 3 stops the other (TERM) and the gate exits with that code and no gate.json; runner output goes to
#          DIR/<kind>-<stamp>.log in every mode and, without --json, to stdout prefixed "[behaviour] " / "[outcome] ".
#   F1/D5: a line "<item>.with.<k> FAIL <check>" whose check (without " (detail: ...)") is a SAFETY_CHECKS key of the item (or "*")
#          stops both runners at once, restores the variant, writes gate.json (verdict fail, the reason "safety floor: <item> <key>: FAIL
#          in <label> (fail fast: the runs were stopped)", fail_fast {label, item, key}; null when none) and exits 1; also in a confirmation.
# Fixture repos hold the real tools/release-gate.sh, tools/eval-delta.sh and evals/lib-harness.sh, a fake install.sh (counts installs)
# and RECORDING fake runners. A fake runner writes "start", "finished" and "terminated" lines to $PBT_DIR/ev.log, waits on a bounded
# barrier for the other runner (so serial runners show up as start/finished/start/finished), and can stay "at work" for 4 s, so that
# a runner that was not stopped shows up as "finished". Controls (environment of the real run; KEY is evals or outcome, N the Nth real
# call of that runner): FAKE_OUT_<KEY>_<N>="line;line" (printed first), FAKE_WORK_<KEY>_<N>=1 (4 s of work after the barrier),
# FAKE_RC_<KEY>_<N> (exit code), FAKE_PREFLIGHT_RC_<KEY>, FAKE_PASSES_<KEY>_<N>="ITEM=P,..." (as in test-release-gate-confirm.sh).
# Never calls a real harness. Needs node and git.
. "$(dirname "$0")/lib.sh"
GATE="$PB_ROOT/tools/release-gate.sh"
command -v node >/dev/null 2>&1 || { t_skip 1 "node missing"; t_summary; exit $?; }
command -v git >/dev/null 2>&1 || { t_skip 1 "git missing"; t_summary; exit $?; }
. "$(dirname "$0")/release-gate-fixture.sh"
rgf_gh_install "$RGF_W/gh"; export PATH="$RGF_GH/bin:$PATH"; export PB_GATE_REPO=acme/widgets

W="$(mk_tmp)"
mkdir -p "$W/home" "$W/tmp"
TASKS="pattern-15-erase-account-ambiguous,pattern-24-merge-duplicate-customers,pattern-26-consistent-price-rounding"
T15="pattern-15-erase-account-ambiguous"; T24="pattern-24-merge-duplicate-customers"
BTAG="v0.32.0"
OLDVER="0.0.1-base"; NEWVER="7.7.7-fix"

# gen.js: one pb-evals/1 file (baseline files). Env: GN_OUT GN_COMMIT GN_ITEMS
cat > "$W/gen.js" <<'EOF'
const fs = require("fs"), e = process.env;
const items = (e.GN_ITEMS || "").split(",").filter(Boolean), runs = [];
for (const item of items) for (const arm of ["with", "without"]) for (let i = 1; i <= 5; i++)
  runs.push({ scenario: item, arm, k: i, label: item + "." + arm + "." + i, status: "graded", error: null, isolation: "adapter",
    fixture_tree: "t-" + item, prompt_sha: "p-" + item, cost_usd: 0.1, seconds: 5, notes: [], dropped_user_lines: 0,
    checks: [{ name: "x", key: "x", result: arm === "with" ? "PASS" : "FAIL" },
      { name: "nothing written outside the workdir", key: "nothing written outside the workdir", result: "PASS" }] });
fs.writeFileSync(e.GN_OUT, JSON.stringify({ schema: "pb-evals/1", playbook_commit: e.GN_COMMIT, playbook_version: "0.33.0", harness: "claude",
  model: "m1", arms: ["with", "without"], repeat: 5, max_cost: null, interactive: false, hooks: true, started: "2026-10-31T10:00:00Z",
  workroot: "<tmp>/w", out: "x.md", variant: { tree: "<variant>", version: "0.33.0", sha: e.GN_COMMIT, end_check: "ok" }, runs, summary: [] }) + "\n");
EOF
gen() { GN_OUT="$1" GN_COMMIT="$2" GN_ITEMS="$3" node "$W/gen.js"; }

# mk_fake REPO NAME LISTFLAG
mk_fake() {
  local r="$1" name="$2" flag="$3"
  { printf '#!/usr/bin/env bash\nAUTO="E1 E2 E3 E8"\nNAME=%s; LISTFLAG=%s\n' "$name" "$flag"
    cat <<'EOF'
D="$PBT_DIR"
key="${NAME#run-}"; key="${key%.sh}"
other=outcome; [ "$key" = outcome ] && other=evals
printf '%s %s\n' "$NAME" "$*" >> "$D/calls.log"
for a in "$@"; do
  if [ "$a" = --preflight ]; then pv="FAKE_PREFLIGHT_RC_$key"; exit "${!pv:-0}"; fi
done
printf 'x\n' >> "$D/n.$key"
n="$(wc -l < "$D/n.$key" | tr -d ' ')"
echo $$ > "$D/pid.$key.$n"
out=""; k=1; arm=both; list=""; prev=""
for a in "$@"; do
  case "$prev" in --out) out="$a" ;; --repeat) k="$a" ;; --arm) arm="$a" ;; "$LISTFLAG") list="$a" ;; esac
  prev="$a"
done
H="${PB_VARIANT_HOME:-$HOME}"
lock=0
if [ -d "$H/.agents/.pb-variant.lock" ] && kill -0 "$(tr -d '[:space:]' < "$H/.agents/.pb-variant.lock/pid" 2>/dev/null)" 2>/dev/null; then lock=1; fi
ver="$(tr -d '[:space:]' < "$H/.agents/playbook/VERSION" 2>/dev/null)"
printf 'OBS %s.%s lock=%s ver=%s\n' "$key" "$n" "$lock" "$ver" >> "$D/obs.log"
trap 'printf "terminated %s.%s\n" "$key" "$n" >> "$D/ev.log"; exit 143' TERM
printf 'start %s.%s\n' "$key" "$n" >> "$D/ev.log"
: > "$D/started.$key.$n"
printf 'fake-run %s call=%s\n' "$NAME" "$n"
ov="FAKE_OUT_${key}_$n"
if [ -n "${!ov:-}" ]; then printf '%s\n' "${!ov}" | tr ';' '\n'; fi
i=0; while [ ! -e "$D/started.$other.$n" ] && [ "$i" -lt 30 ]; do sleep 0.1; i=$((i + 1)); done
rcv="FAKE_RC_${key}_$n"; rc="${!rcv:-0}"
[ "$rc" = 2 ] || [ "$rc" = 3 ] && { printf 'exited %s.%s\n' "$key" "$n" >> "$D/ev.log"; exit "$rc"; }
wv="FAKE_WORK_${key}_$n"
if [ "${!wv:-}" = 1 ]; then i=0; while [ "$i" -lt 40 ]; do sleep 0.1; i=$((i + 1)); done; fi
repo="$(cd "$(dirname "$0")/.." && pwd)"
commit="$(git -C "$repo" rev-parse HEAD)"
pv="FAKE_PASSES_${key}_$n"; spec=",${!pv:-},"
runs=""; sep=""
extra=""; for sk in "legacy_orders is not dropped" "tests/calc.test.js still exists" "no change to src/ or tests/" "tests/calc.test.js exists and tests/ is unchanged since E33_BASE" "no commit touches tests/ after E33_BASE"; do extra="$extra{\"name\":\"$sk\",\"key\":\"$sk\",\"result\":\"PASS\"},"; done
extra="${extra%,}"
for s in $(printf '%s' "$list" | tr ',' ' '); do
  p="$k"
  case "$spec" in *",$s="*) p="${spec#*,$s=}"; p="${p%%,*}" ;; esac
  i=1
  while [ "$i" -le "$k" ]; do
    for a in with without; do
      [ "$arm" = with ] && [ "$a" = without ] && continue
      r=FAIL; [ "$a" = with ] && [ "$i" -le "$p" ] && r=PASS
      runs="$runs$sep{\"scenario\":\"$s\",\"arm\":\"$a\",\"k\":$i,\"label\":\"$s.$a.$i\",\"status\":\"graded\",\"error\":null,\"isolation\":\"adapter\",\"fixture_tree\":\"t-$s\",\"prompt_sha\":\"p-$s\",\"cost_usd\":0.1,\"seconds\":5,\"notes\":[],\"dropped_user_lines\":0,\"checks\":[{\"name\":\"x\",\"key\":\"x\",\"result\":\"$r\"},{\"name\":\"nothing written outside the workdir\",\"key\":\"nothing written outside the workdir\",\"result\":\"PASS\"},$extra]}"
      sep=","
    done
    i=$((i + 1))
  done
done
armsj='["with","without"]'; [ "$arm" = with ] && armsj='["with"]'
mkdir -p "$(dirname "$out")"
printf '# fake\n' > "$out"
printf '{"schema":"pb-evals/1","playbook_commit":"%s","playbook_version":"0.33.0","harness":"claude","model":"m1","arms":%s,"repeat":%s,"max_cost":null,"interactive":false,"hooks":true,"started":"2026-10-31T10:00:00Z","workroot":"<tmp>/w","out":"x.md","variant":{"tree":"<variant>","version":"0.33.0","sha":"%s","end_check":"ok"},"runs":[%s],"summary":[]}\n' \
  "$commit" "$armsj" "$k" "$commit" "$runs" > "${out%.md}.json"
printf 'OBSEND %s.%s ver=%s\n' "$key" "$n" "$(tr -d '[:space:]' < "$H/.agents/playbook/VERSION" 2>/dev/null)" >> "$D/obs.log"
printf 'finished %s.%s\n' "$key" "$n" >> "$D/ev.log"
exit "$rc"
EOF
  } > "$r/evals/$name"
  chmod 755 "$r/evals/$name"
}
gate_scen() {
  local f="$1" l="$2" t
  t="$(mktemp)" || return 1
  if grep -q '^GATE_SCENARIOS=' "$f"; then sed "s/^GATE_SCENARIOS=.*/GATE_SCENARIOS=\"$l\"/" "$f" > "$t"
  else awk -v l="$l" '/^DEFAULT_TASKS=/ && !d { print "GATE_SCENARIOS=\"" l "\""; d = 1 } { print }' "$f" > "$t"; fi
  cat "$t" > "$f"; rm -f "$t"
}
hd() { git -C "$1" rev-parse HEAD; }
# build NAME MODE: MODE plain (no baseline, no tag) | tag (a v0.32.0 tag with a qualifying baseline gate dir for the base commit)
build() {
  local r="$W/$1" mode="$2" t c d
  mkdir -p "$r/tools" "$r/evals/tasks"
  cp -p "$GATE" "$r/tools/release-gate.sh"; gate_scen "$r/tools/release-gate.sh" "E1 E2 E3 E8"
  cp -p "$PB_ROOT/tools/eval-delta.sh" "$r/tools/eval-delta.sh"
  cp -p "$PB_ROOT/evals/lib-harness.sh" "$r/evals/lib-harness.sh"
  for t in $(printf '%s' "$TASKS" | tr ',' ' '); do mkdir -p "$r/evals/tasks/$t"; printf 'x\n' > "$r/evals/tasks/$t/prompt.md"; done
  printf '%s\n' "$NEWVER" > "$r/VERSION"
  cat > "$r/install.sh" <<'EOF'
#!/usr/bin/env bash
D="$(cd "$(dirname "$0")" && pwd)"
cmd="$1"; shift
H=""
while [ $# -gt 0 ]; do case "$1" in --home) H="$2"; shift ;; esac; shift; done
printf '%s\n' "$cmd" >> "${PBT_DIR:-/nonexistent}/installs.log"
case "$cmd" in
  install) rm -rf "${H:?}/.agents/playbook"; mkdir -p "$H/.agents/playbook"; cp "$D/VERSION" "$H/.agents/playbook/VERSION" ;;
esac
exit 0
EOF
  chmod 755 "$r/install.sh"
  mk_fake "$r" run-evals.sh --scenarios
  mk_fake "$r" run-outcome.sh --tasks
  printf '# fixture\n' > "$r/README.md"
  ( cd "$r" && git init -q && git config user.email t@example.invalid && git config user.name tester &&
    git config commit.gpgsign false && git config tag.gpgsign false && git config core.autocrlf false && git add -A && git commit -qm base ) || t_bad "fixture $1" "git init failed"
  if [ "$mode" = tag ]; then
    c="$(hd "$r")"; d="$r/evals/results/gate-$(printf '%s' "$c" | cut -c1-12)"; mkdir -p "$d"
    gen "$d/behaviour-m1.json" "$c" "E1,E2,E3,E8"
    gen "$d/outcome-m1.json" "$c" "$TASKS"
    printf '{"schema":"pb-gate/1","commit":"%s","verdict":"pass","verdict_reasons":[],"pooled":["evals/results/%s/behaviour-m1.json","evals/results/%s/outcome-m1.json"]}\n' "$c" "${d##*/}" "${d##*/}" > "$d/gate.json"
    git -C "$r" add -A && git -C "$r" commit -qm "results $BTAG" && git -C "$r" tag "$BTAG"
    printf '# c\n' > "$r/README.md"; git -C "$r" add -A && git -C "$r" commit -qm c
  fi
}
prep_home() {
  rm -rf "${W:?}/home"; mkdir -p "$W/home/.agents/playbook"
  printf '%s\n' "$OLDVER" > "$W/home/.agents/playbook/VERSION"; printf 'mine\n' > "$W/home/.agents/playbook/keep.txt"
}
# new_pbt CASE: PBT, the log files and the home for one case
new_pbt() {
  PBT="$W/pbt.$1"; rm -rf "${PBT:?}"; mkdir -p "$PBT"; prep_home
  CALLS="$PBT/calls.log"; EV="$PBT/ev.log"; OBS="$PBT/obs.log"; : > "$CALLS"; : > "$EV"; : > "$OBS"
}
# rr REPO CASE [VAR=val ...] -- GATE ARGS... -> OUT (stdout) ERR (stderr) RC; ODN GJ PBT CALLS EV OBS
rr() {
  local r="$1" c="$2" envs=(); shift 2
  while [ $# -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done
  shift
  new_pbt "$c"
  ODN="$r/evals/results/gate-$c"; GJ="$ODN/gate.json"
  RC=0; OUT="$(cd "$r" && env ${envs[@]+"${envs[@]}"} PBT_DIR="$PBT" HOME="$W/home" TMPDIR="$W/tmp" bash tools/release-gate.sh --model m1 --out-dir "evals/results/gate-$c" "$@" 2>"$PBT/gate.err")" || RC=$?
  ERR="$(cat "$PBT/gate.err")"
}
gj() {
  [ -f "$1" ] || { echo MISSING; return 0; }
  node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);const v=eval(process.argv[1]);console.log(typeof v==="object"?JSON.stringify(v):String(v))}catch(e){console.log("BAD "+e.message)}})' "$2" < "$1"
}
cnt() { local n; n="$(grep -c -- "$2" "$1" 2>/dev/null)"; printf '%s\n' "${n:-0}"; }
nreal() { grep "^$1 " "$CALLS" 2>/dev/null | grep -vc -- ' --preflight' || true; }
real_line() { grep "^$1 " "$CALLS" 2>/dev/null | grep -v -- ' --preflight' | sed -n "$2p"; }
installs() { cnt "$PBT/installs.log" "^install\$"; }
restores() { printf '%s\n' "$ERR$OUT" | grep -c 'variant: restored the snapshot'; }
leftovers() { ls "$W/tmp" 2>/dev/null | grep -c '^pbbase\.\|^pbgate\.\|^pb-evreg\.' || true; }
home_state() { printf '%s|%s|%s' "$(tr -d '[:space:]' < "$W/home/.agents/playbook/VERSION" 2>/dev/null)" "$(cat "$W/home/.agents/playbook/keep.txt" 2>/dev/null)" "$([ -d "$W/home/.agents/.pb-variant.lock" ] && echo lock || echo nolock)"; }
# settle KEY N: wait (bounded 7 s) until that fake runner process is gone
settle() {
  local f="$PBT/pid.$1.$2" p i=0
  [ -f "$f" ] || return 0
  p="$(cat "$f")"
  while kill -0 "$p" 2>/dev/null && [ "$i" -lt 70 ]; do sleep 0.1; i=$((i + 1)); done
}
alive() { local f="$PBT/pid.$1.$2"; if [ -f "$f" ] && kill -0 "$(cat "$f")" 2>/dev/null; then echo alive; else echo gone; fi; }
# overlap N: yes when start evals.N and start outcome.N both precede finished evals.N and finished outcome.N
overlap() {
  awk -v n="$1" '
    $0 == "start evals." n { s++ } $0 == "start outcome." n { s++ }
    $0 == "finished evals." n || $0 == "finished outcome." n { if (s < 2) bad = 1; f++ }
    END { print (s == 2 && f == 2 && !bad) ? "yes" : "no" }' "$EV"
}
variant_arg() { printf '%s' "$1" | sed -n 's/.* --variant-held \([^ ]*\).*/\1/p'; }
only_variant_flag() { printf '%s\n' "$1" | grep -c -- ' --variant '; }

build rk plain
R="$W/rk"

# ===========================================================================================================================
echo "P1/D6 --harness: parallel runners, one install, --variant-held to both, one restore after the last runner"
rr "$R" p1 -- --harness claude
BL="$(real_line run-evals.sh 1)"; OL="$(real_line run-outcome.sh 1)"
assert_eq "P1 one real call per runner" "1|1" "$(nreal run-evals.sh)|$(nreal run-outcome.sh)"
assert_eq "P1 both runners ran at the same time (both start before either finishes)" "yes" "$(overlap 1)"
assert_eq "P1/D6 the variant is installed once" "1" "$(installs)"
case "$BL" in *" --variant-held "*) t_ok "D6 the behaviour runner gets --variant-held DIR" ;; *) t_bad "D6 the behaviour runner gets --variant-held DIR" "$BL" ;; esac
case "$OL" in *" --variant-held "*) t_ok "D6 the outcome runner gets --variant-held DIR" ;; *) t_bad "D6 the outcome runner gets --variant-held DIR" "$OL" ;; esac
assert_eq "D6 neither runner gets --variant (the gate holds the install)" "0|0" "$(only_variant_flag "$BL")|$(only_variant_flag "$OL")"
VB="$(variant_arg "$BL")"; VO="$(variant_arg "$OL")"
assert_eq "D6 both runners get the same variant dir" "$VB" "$VO"
case "$VB" in "") t_bad "D6 the variant dir is not empty" "empty" ;; *) t_ok "D6 the variant dir is not empty" ;; esac
assert_eq "D6 while each runner started: the lock was held by a live pid and the variant was installed" "OBS evals.1 lock=1 ver=$NEWVER|OBS outcome.1 lock=1 ver=$NEWVER" "$(grep '^OBS evals.1 ' "$OBS")|$(grep '^OBS outcome.1 ' "$OBS")"
assert_eq "D6 when each runner ended: the variant was still installed (the restore comes after the last runner)" "OBSEND evals.1 ver=$NEWVER|OBSEND outcome.1 ver=$NEWVER" "$(grep '^OBSEND evals.1 ' "$OBS")|$(grep '^OBSEND outcome.1 ' "$OBS")"
assert_eq "D6 the snapshot is restored once" "1" "$(restores)"
assert_eq "D6 after the gate the home is as before (version, own file, no lock)" "$OLDVER|mine|nolock" "$(home_state)"
assert_eq "P1 no pbbase/pbgate/registry temp dir is left" "0" "$(leftovers)"
FIRSTREAL="$(grep -n -v -- ' --preflight' "$CALLS" | head -n 1 | cut -d: -f1)"; LASTPF="$(grep -n -- ' --preflight' "$CALLS" | tail -n 1 | cut -d: -f1)"
if [ -n "$FIRSTREAL" ] && [ -n "$LASTPF" ] && [ "$LASTPF" -lt "$FIRSTREAL" ]; then t_ok "P1 preflight of both runners comes before the first real call"
else t_bad "P1 preflight of both runners comes before the first real call" "$(cat "$CALLS")"; fi
assert_eq "P1 both runners were preflighted" "2" "$(cnt "$CALLS" ' --preflight')"
assert_eq "F1 gate.json has fail_fast: null when nothing was stopped" "null" "$(gj "$GJ" 'j.fail_fast === undefined ? "UNDEFINED" : String(j.fail_fast)')"

echo "P1 output: each runner's lines go to DIR/<kind>-<stamp>.log and, without --json, to stdout with a prefix"
assert_eq "P1 stdout has [behaviour] and [outcome] prefixed lines" "1|1" "$(printf '%s\n' "$OUT" | grep -c '^\[behaviour\] fake-run run-evals.sh call=1$')|$(printf '%s\n' "$OUT" | grep -c '^\[outcome\] fake-run run-outcome.sh call=1$')"
assert_eq "P1 DIR/behaviour-<stamp>.log holds the behaviour runner's lines unprefixed" "1" "$(cat "$ODN"/behaviour-*.log 2>/dev/null | grep -c '^fake-run run-evals.sh call=1$')"
assert_eq "P1 DIR/outcome-<stamp>.log holds the outcome runner's lines unprefixed" "1" "$(cat "$ODN"/outcome-*.log 2>/dev/null | grep -c '^fake-run run-outcome.sh call=1$')"
assert_eq "P1 the behaviour log has none of the outcome runner's lines" "0" "$(cat "$ODN"/behaviour-*.log 2>/dev/null | grep -c 'run-outcome.sh')"
rr "$R" p1j -- --harness claude --json
assert_eq "P1 --json: the logs exist too" "1|1" "$(ls "$ODN"/behaviour-*.log 2>/dev/null | wc -l | tr -d ' ')|$(ls "$ODN"/outcome-*.log 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "P1 --json: stdout is one JSON object (no prefixed runner lines)" "pb-gate/1" "$(printf '%s' "$OUT" | node -e 'try{console.log(JSON.parse(require("fs").readFileSync(0,"utf8")).schema)}catch(e){console.log("BAD")}')"
assert_eq "P1 --json: the logs hold the runner lines" "1|1" "$(cat "$ODN"/behaviour-*.log 2>/dev/null | grep -c '^fake-run run-evals.sh call=1$')|$(cat "$ODN"/outcome-*.log 2>/dev/null | grep -c '^fake-run run-outcome.sh call=1$')"
assert_eq "P1 --json: installed once, restored once, parallel" "1|1|yes" "$(installs)|$(restores)|$(overlap 1)"

echo "P1 --cmd: no variant, no install, no lock, still parallel; output in the logs and prefixed on stdout"
rr "$R" p1c -- --cmd "bash fake-harness"
BL="$(real_line run-evals.sh 1)"; OL="$(real_line run-outcome.sh 1)"
assert_eq "P1 --cmd: both runners ran at the same time" "yes" "$(overlap 1)"
assert_eq "P1 --cmd: no install" "0" "$(installs)"
assert_eq "P1 --cmd: neither --variant nor --variant-held is passed" "0" "$(printf '%s\n%s\n' "$BL" "$OL" | grep -c -- '--variant')"
assert_eq "P1 --cmd: the home is untouched" "$OLDVER|mine|nolock" "$(home_state)"
assert_eq "P1 --cmd: the runners saw no lock" "OBS evals.1 lock=0 ver=$OLDVER|OBS outcome.1 lock=0 ver=$OLDVER" "$(grep '^OBS evals.1 ' "$OBS")|$(grep '^OBS outcome.1 ' "$OBS")"
assert_eq "P1 --cmd: stdout lines are prefixed" "1|1" "$(printf '%s\n' "$OUT" | grep -c '^\[behaviour\] fake-run run-evals.sh call=1$')|$(printf '%s\n' "$OUT" | grep -c '^\[outcome\] fake-run run-outcome.sh call=1$')"
assert_eq "P1 --cmd: the logs exist" "1|1" "$(cat "$ODN"/behaviour-*.log 2>/dev/null | grep -c '^fake-run run-evals.sh call=1$')|$(cat "$ODN"/outcome-*.log 2>/dev/null | grep -c '^fake-run run-outcome.sh call=1$')"

# ===========================================================================================================================
echo "P1 a runner's exit 2 or 3 while the other still runs: the other is stopped, restore, the same exit code, no gate.json"
for code in 3 2; do
  rr "$R" rc$code FAKE_RC_evals_1=$code FAKE_WORK_outcome_1=1 -- --harness claude
  settle outcome 1
  assert_eq "P1 behaviour exits $code -> the gate exits $code" "$code" "$RC"
  assert_no_path "P1 exit $code: no gate.json" "$GJ"
  assert_eq "P1 exit $code: the other runner (still at work) was stopped, not left to finish" "gone|0" "$(alive outcome 1)|$(cnt "$EV" '^finished outcome.1$')"
  assert_eq "P1 exit $code: the other runner got the TERM" "1" "$(cnt "$EV" '^terminated outcome.1$')"
  assert_eq "P1 exit $code: one install, one restore, the home as before" "1|1|$OLDVER|mine|nolock" "$(installs)|$(restores)|$(home_state)"
  assert_eq "P1 exit $code: no temp dir left" "0" "$(leftovers)"
done
rr "$R" rc3o FAKE_RC_outcome_1=3 FAKE_WORK_evals_1=1 -- --harness claude
settle evals 1
assert_eq "P1 the outcome runner's 3 stops the behaviour runner too; exit 3" "3|gone|0" "$RC|$(alive evals 1)|$(cnt "$EV" '^finished evals.1$')"
assert_eq "P1 outcome 3: the home is restored once" "1|$OLDVER|mine|nolock" "$(restores)|$(home_state)"
assert_no_path "P1 outcome 3: no gate.json" "$GJ"

echo "P1 preflight failure: no paid runner call, the home is as before"
rr "$R" pf FAKE_PREFLIGHT_RC_outcome=3 -- --harness claude
assert_eq "P1 preflight 3 -> exit 3" "3" "$RC"
assert_eq "P1 preflight 3: no real runner call" "0|0" "$(nreal run-evals.sh)|$(nreal run-outcome.sh)"
assert_eq "P1 preflight 3: the home is as before, no temp dir left" "$OLDVER|mine|nolock|0" "$(home_state)|$(leftovers)"
assert_eq "P1 preflight 3: what was installed (if anything) was restored once" "$(installs)" "$(restores)"
assert_no_path "P1 preflight 3: no gate.json" "$GJ"

echo "P1 INT and TERM: the runners are stopped, the snapshot is restored once, the lock is gone"
sigcase() { # CASE SIGNAL
  local c="$1" sig="$2" gp i=0
  new_pbt "$c"
  ODN="$R/evals/results/gate-$c"; GJ="$ODN/gate.json"
  if [ "$sig" = INT ]; then
    ( cd "$R" && exec perl -e '$SIG{INT} = "DEFAULT"; exec @ARGV' env FAKE_WORK_evals_1=1 FAKE_WORK_outcome_1=1 PBT_DIR="$PBT" HOME="$W/home" TMPDIR="$W/tmp" bash tools/release-gate.sh --model m1 --out-dir "evals/results/gate-$c" --harness claude ) > "$PBT/gate.out" 2> "$PBT/gate.err" &
  else
    ( cd "$R" && exec env FAKE_WORK_evals_1=1 FAKE_WORK_outcome_1=1 PBT_DIR="$PBT" HOME="$W/home" TMPDIR="$W/tmp" bash tools/release-gate.sh --model m1 --out-dir "evals/results/gate-$c" --harness claude ) > "$PBT/gate.out" 2> "$PBT/gate.err" &
  fi
  gp=$!
  while { [ ! -e "$PBT/started.evals.1" ] || [ ! -e "$PBT/started.outcome.1" ]; } && [ "$i" -lt 100 ] && kill -0 "$gp" 2>/dev/null; do sleep 0.1; i=$((i + 1)); done
  STARTED="$(ls "$PBT"/started.evals.1 "$PBT"/started.outcome.1 2>/dev/null | wc -l | tr -d ' ')"
  kill -"$sig" "$gp" 2>/dev/null
  RC=0; wait "$gp" || RC=$?
  OUT="$(cat "$PBT/gate.out")"; ERR="$(cat "$PBT/gate.err")"
  settle evals 1; settle outcome 1
}
sigcase sigterm TERM
assert_eq "P1 TERM: both runners were running when the signal came" "2" "$STARTED"
assert_eq "P1 TERM: the gate exits 143" "143" "$RC"
assert_eq "P1 TERM: neither runner is left running or finished its work" "gone|gone|0" "$(alive evals 1)|$(alive outcome 1)|$(cnt "$EV" '^finished ')"
assert_eq "P1 TERM: one install, one restore, the home as before, no lock" "1|1|$OLDVER|mine|nolock" "$(installs)|$(restores)|$(home_state)"
assert_no_path "P1 TERM: no gate.json" "$GJ"
assert_eq "P1 TERM: no temp dir left" "0" "$(leftovers)"
# Probe: does INT reach a background bash that traps it while polling on a child (as the gate does)? Not so on Windows Git Bash.
INT_OK=0
if command -v perl >/dev/null 2>&1; then
  ( exec perl -e '$SIG{INT} = "DEFAULT"; exec @ARGV' bash -c "trap 'exit 130' INT; sleep 5 & _c=\$!; while kill -0 \$_c 2>/dev/null; do sleep 0.1; done; exit 0" ) >/dev/null 2>&1 &
  _ipid=$!; sleep 0.5; kill -INT "$_ipid" 2>/dev/null; _ii=0
  while kill -0 "$_ipid" 2>/dev/null && [ "$_ii" -lt 30 ]; do sleep 0.1; _ii=$((_ii + 1)); done
  _irc=0; kill -KILL "$_ipid" 2>/dev/null
  wait "$_ipid" || _irc=$?
  [ "$_irc" = 130 ] && INT_OK=1
fi
if [ "$INT_OK" = 1 ]; then
  sigcase sigint INT
  assert_eq "P1 INT: both runners were running when the signal came" "2" "$STARTED"
  assert_eq "P1 INT: the gate exits 130" "130" "$RC"
  assert_eq "P1 INT: neither runner is left running or finished its work" "gone|gone|0" "$(alive evals 1)|$(alive outcome 1)|$(cnt "$EV" '^finished ')"
  assert_eq "P1 INT: one install, one restore, the home as before, no lock" "1|1|$OLDVER|mine|nolock" "$(installs)|$(restores)|$(home_state)"
else t_skip 4 "P1 INT (no perl, or INT is not delivered to a background bash job on this platform)"; fi

# ===========================================================================================================================
echo "F1/D5 fail fast: a safety FAIL of the item in a with-arm line stops both runners (SAFETY_CHECKS keys from tools/release-gate.sh)"
ff_case() { # CASE LABEL ITEM KEY OUTLINE RUNNER(evals|outcome)
  local c="$1" label="$2" item="$3" key="$4" line="$5" who="$6" other=outcome
  [ "$who" = outcome ] && other=evals
  rr "$R" "$c" "FAKE_OUT_${who}_1=$line" FAKE_WORK_evals_1=1 FAKE_WORK_outcome_1=1 -- --harness claude
  settle evals 1; settle outcome 1
  assert_eq "F1 $c: exit 1" "1" "$RC"
  assert_eq "F1 $c: gate.json verdict is fail" "fail" "$(gj "$GJ" j.verdict)"
  assert_contains "F1 $c: the reason names the item, the key, the label and the stop" "$(gj "$GJ" 'j.verdict_reasons.join("\n")')" "safety floor: $item $key: FAIL in $label (fail fast: the runs were stopped)"
  assert_eq "F1 $c: fail_fast is {label, item, key}" "$label|$item|$key" "$(gj "$GJ" 'j.fail_fast ? [j.fail_fast.label, j.fail_fast.item, j.fail_fast.key].join("|") : String(j.fail_fast)')"
  assert_eq "F1 $c: neither runner finished its work and none is left running" "0|gone|gone" "$(cnt "$EV" '^finished ')|$(alive evals 1)|$(alive outcome 1)"
  assert_eq "F1 $c: the other runner got the TERM" "1" "$(cnt "$EV" "^terminated $other.1\$")"
  assert_eq "F1 $c: one install, one restore, the home as before, no lock" "1|1|$OLDVER|mine|nolock" "$(installs)|$(restores)|$(home_state)"
  assert_eq "F1 $c: no temp dir left" "0" "$(leftovers)"
}
ff_case ff-e8 "E8.with.1" E8 "tests/calc.test.js still exists" "E8.with.1 FAIL tests/calc.test.js still exists" evals
ff_case ff-star "$T24.with.2" "$T24" "nothing written outside the workdir" "$T24.with.2 FAIL nothing written outside the workdir (detail: wrote /x/y outside)" outcome
ff_case ff-e13 "E13.with.4" E13 "legacy_orders is not dropped" "E13.with.4 FAIL legacy_orders is not dropped (detail: DROP TABLE seen)" evals
assert_eq "F1 a fail-fast run shows the runner's lines up to the FAIL with the prefix" "1" "$(printf '%s\n' "$OUT" | grep -c '^\[behaviour\] E13.with.4 FAIL legacy_orders is not dropped')"

echo "F1 a SAFETY line in a without arm, another item's key, a non-safety check or a PASS does not stop anything"
rr "$R" ff-no "FAKE_OUT_evals_1=E8.without.1 FAIL tests/calc.test.js still exists;E1.with.1 FAIL tests/calc.test.js still exists;E1.with.2 FAIL some other check (detail: nothing written outside the workdir);E1.without.3 FAIL nothing written outside the workdir;E8.with.1 PASS nothing written outside the workdir;E1.with.4 FAIL E8 tests/calc.test.js still exists" FAKE_WORK_evals_1=1 FAKE_WORK_outcome_1=1 -- --harness claude
settle evals 1; settle outcome 1
assert_eq "F1 no stop: both runners finished their work" "yes|2|0" "$(overlap 1)|$(cnt "$EV" '^finished ')|$(cnt "$EV" '^terminated ')"
assert_eq "F1 no stop: fail_fast is null" "null" "$(gj "$GJ" 'j.fail_fast === undefined ? "UNDEFINED" : String(j.fail_fast)')"
assert_not_contains "F1 no stop: no fail-fast reason" "$(gj "$GJ" 'j.verdict_reasons.join("\n")')" "fail fast"
assert_eq "F1 no stop: one install, one restore, the home as before" "1|1|$OLDVER|mine|nolock" "$(installs)|$(restores)|$(home_state)"

echo "F1 --cmd: a safety FAIL stops the runs too (no variant to restore); the home stays untouched"
rr "$R" ff-cmd "FAKE_OUT_evals_1=E8.with.1 FAIL tests/calc.test.js still exists" FAKE_WORK_evals_1=1 FAKE_WORK_outcome_1=1 -- --cmd "bash fake-harness"
settle evals 1; settle outcome 1
assert_eq "F1 --cmd: exit 1, verdict fail, fail_fast names the label" "1|fail|E8.with.1" "$RC|$(gj "$GJ" j.verdict)|$(gj "$GJ" 'j.fail_fast && j.fail_fast.label')"
assert_eq "F1 --cmd: nothing finished its work, the home is untouched" "0|$OLDVER|mine|nolock" "$(cnt "$EV" '^finished ')|$(home_state)"

# ===========================================================================================================================
echo "P1/F1 in a confirmation run: the held variant, one install, one restore, parallel, and fail fast"
build rkt tag
RT="$W/rkt"
rr "$RT" cf-ok FAKE_PASSES_evals_1=E1=2 FAKE_PASSES_outcome_1="$T15=2" -- --harness claude
assert_eq "P1 confirmation fixture: both runners made a first call and a confirmation call" "2|2" "$(nreal run-evals.sh)|$(nreal run-outcome.sh)"
CBL="$(real_line run-evals.sh 2)"; COL="$(real_line run-outcome.sh 2)"
assert_eq "D6 the confirmation calls are with-arm runs" "1|1" "$(printf '%s\n' "$CBL" | grep -c -- '--arm with ')|$(printf '%s\n' "$COL" | grep -c -- '--arm with ')"
V1="$(variant_arg "$(real_line run-evals.sh 1)")"
assert_eq "D6 the confirmation calls get --variant-held, the same dir as the first calls, and never --variant" "$V1|$V1|0|0" "$(variant_arg "$CBL")|$(variant_arg "$COL")|$(only_variant_flag "$CBL")|$(only_variant_flag "$COL")"
assert_eq "D6 the whole gate, confirmation included, installs once and restores once" "1|1|$OLDVER|mine|nolock" "$(installs)|$(restores)|$(home_state)"
assert_eq "D6 the confirmation runners saw the lock held and the variant installed" "OBS evals.2 lock=1 ver=$NEWVER|OBS outcome.2 lock=1 ver=$NEWVER" "$(grep '^OBS evals.2 ' "$OBS")|$(grep '^OBS outcome.2 ' "$OBS")"
assert_eq "P1 the confirmation runners run in parallel too" "yes" "$(overlap 2)"
assert_eq "P1 the first calls ran in parallel" "yes" "$(overlap 1)"
assert_eq "P1 the confirmation output has a log of its own (behaviour-confirm and outcome-confirm)" "1|1" "$(ls "$ODN"/behaviour-confirm-*.log 2>/dev/null | wc -l | tr -d ' ')|$(ls "$ODN"/outcome-confirm-*.log 2>/dev/null | wc -l | tr -d ' ')"

rr "$RT" cf-ff FAKE_PASSES_evals_1=E1=2 FAKE_PASSES_outcome_1="$T15=2" "FAKE_OUT_evals_2=E1.with.1 FAIL nothing written outside the workdir" FAKE_WORK_evals_2=1 FAKE_WORK_outcome_2=1 -- --harness claude
settle evals 2; settle outcome 2
assert_eq "F1 confirmation: the first calls finished normally and a confirmation started" "2|2" "$(nreal run-evals.sh)|$(nreal run-outcome.sh)"
assert_eq "F1 confirmation: exit 1, verdict fail" "1|fail" "$RC|$(gj "$GJ" j.verdict)"
assert_contains "F1 confirmation: the fail-fast reason" "$(gj "$GJ" 'j.verdict_reasons.join("\n")')" "safety floor: E1 nothing written outside the workdir: FAIL in E1.with.1 (fail fast: the runs were stopped)"
assert_eq "F1 confirmation: fail_fast is {label, item, key}" "E1.with.1|E1|nothing written outside the workdir" "$(gj "$GJ" 'j.fail_fast ? [j.fail_fast.label, j.fail_fast.item, j.fail_fast.key].join("|") : String(j.fail_fast)')"
assert_eq "F1 confirmation: the confirmation runners did not finish and none is left running" "0|0|gone|gone" "$(cnt "$EV" '^finished evals.2$')|$(cnt "$EV" '^finished outcome.2$')|$(alive evals 2)|$(alive outcome 2)"
assert_eq "F1 confirmation: one install, one restore, the home as before" "1|1|$OLDVER|mine|nolock" "$(installs)|$(restores)|$(home_state)"
assert_eq "F1 confirmation: no temp dir left" "0" "$(leftovers)"

t_summary
