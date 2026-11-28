#!/usr/bin/env bash
# Tests for v0.38 G1 (docs/v0.38-g1-spec.md R1 to R9, AC1 to AC11): tools/release-gate.sh --budget USD (a total split between the two
# runners; a real run reads the first baseline group's cost_usd as the estimate, refuses a share below it before any runner, preflight
# or worktree, and passes per-call --max-cost values) and the gate.json field `truncated` (a (scenario, arm) of the needed set below 5
# graded runs that carries a skipped run: the cost cap cut the batch). Fixture repos hold the real tools/release-gate.sh, tools/eval-delta.sh,
# evals/lib-harness.sh, a fake install.sh and RECORDING fake runners (in the style of tests/test-release-gate-reuse.sh: every call, preflight
# and --print-hashes call included, goes to $PBT_DIR/calls.log; the real calls carry the --max-cost the gate chose). Baseline gates are
# committed pb-evals/1 files whose cost_usd values are multiples of 0.25 (so every sum is exact); GN_Q is the total in quarter dollars.
# The fake runners take controls from the environment of the real run; KEY is evals or outcome, KIND is main (the both-arms call), with
# (the with-only call of a partial reuse) or confirm (the confirmation call):
#   FAKE_Q_<KEY>_<KIND>=N        the call writes N quarter dollars of cost_usd in all (spread over its runs; skipped runs have null)
#   FAKE_PASSES_<KEY>_<KIND>="ITEM=P,.."  the first P of the K with-arm runs of ITEM pass check x (default K)
#   FAKE_SKIP_<KEY>_<KIND>="ITEM=N,.."    the last N with-arm runs of ITEM are status skipped (the outcome runner adds a SKIPPED budget note)
#   FAKE_OUT_<KEY>_<KIND>="line;line"     lines printed first (a "<item>.with.<k> FAIL <check>" line makes the gate stop: fail fast)
#   FAKE_CHG="E2:S,E3:G"                  the current hash of that item/kind changes (as in test-release-gate-reuse.sh)
# gate.json from a real gate is used for the truncated cases that need a runner; the cases that need a crafted DIR use the real --pool-only
# on a DIR built here (docs spec AC8 to AC10). Never calls a real harness or a model. Needs node and git.
# Runtime estimate for tests/shard-weights: about 900 seconds (an estimate, not a measurement: about 40 real gate runs, like the reuse suite).
. "$(dirname "$0")/lib.sh"
GATE="$PB_ROOT/tools/release-gate.sh"
command -v node >/dev/null 2>&1 || { t_skip 1 "node missing"; t_summary; exit $?; }
command -v git >/dev/null 2>&1 || { t_skip 1 "git missing"; t_summary; exit $?; }
. "$(dirname "$0")/release-gate-fixture.sh"
rgf_gh_install "$RGF_W/gh"; export PATH="$RGF_GH/bin:$PATH"; export PB_GATE_REPO=acme/widgets

W="$(mk_tmp)"
mkdir -p "$W/home" "$W/tmp"
TASKS="$(sed -n 's/^DEFAULT_TASKS="\(.*\)"$/\1/p' "$PB_ROOT/tools/release-gate.sh")"
T15="pattern-15-erase-account-ambiguous"; T24="pattern-24-merge-duplicate-customers"
BTAG="v0.32.0"
OLDVER="0.0.1-base"; NEWVER="7.7.7-fix"
T0=1790000000
D1=$((T0 + 86400)); D2=$((T0 + 2 * 86400)); D3=$((T0 + 3 * 86400)); D4=$((T0 + 4 * 86400))
NOW3=$((T0 + 3 * 86400)); NOW100=$((T0 + 100 * 86400))   # 3 days: a baseline whose hashes match is reused; 100 days: nothing is reused

# hx.js KIND ITEM SALT: the 40 hex hash both the fake runners and the baseline generator use
cat > "$W/hx.js" <<'EOF'
console.log(require("crypto").createHash("sha1").update(process.argv.slice(2).join(":")).digest("hex"));
EOF
# gen.js: one baseline pb-evals/1 file. Env: GN_OUT GN_COMMIT GN_ITEMS GN_Q (the total cost in quarter dollars, spread over all runs; "null": cost_usd null)
# GN_HASH (1: the three hashes)
cat > "$W/gen.js" <<'EOF'
const fs = require("fs"), e = process.env, cr = require("crypto");
const hx = (k, i) => cr.createHash("sha1").update([k, i, ""].join(":")).digest("hex");
const items = (e.GN_ITEMS || "").split(",").filter(Boolean), runs = [];
const n = items.length * 10, u = e.GN_Q === "null" ? null : Number(e.GN_Q || 0);
let idx = 0;
for (const item of items) for (const arm of ["with", "without"]) for (let i = 1; i <= 5; i++) {
  const q = u === null ? null : Math.floor((idx + 1) * u / n) - Math.floor(idx * u / n);
  idx++;
  const r = { scenario: item, arm, k: i, label: item + "." + arm + "." + i, status: "graded", error: null, isolation: "adapter",
    fixture_tree: "t-" + item, prompt_sha: "p-" + item, cost_usd: q === null ? null : q * 0.25, seconds: 5, notes: [], dropped_user_lines: 0,
    checks: [{ name: "x", key: "x", result: arm === "with" ? "PASS" : "FAIL" },
      { name: "nothing written outside the workdir", key: "nothing written outside the workdir", result: "PASS" }] };
  if (e.GN_HASH === "1") { r.scenario_sha = hx("S", item); r.grader_sha = hx("G", item); r.harness_sha = hx("H", item); }
  runs.push(r);
}
fs.writeFileSync(e.GN_OUT, JSON.stringify({ schema: "pb-evals/1", playbook_commit: e.GN_COMMIT, playbook_version: "0.33.0", harness: "claude",
  model: "m1", arms: ["with", "without"], repeat: 5, max_cost: null, interactive: false, hooks: true, started: "2026-10-31T10:00:00Z",
  workroot: "<tmp>/w", out: "x.md", variant: { tree: "<variant>", version: "0.33.0", sha: e.GN_COMMIT, end_check: "ok" }, runs, summary: [] }) + "\n");
EOF
gen() { GN_OUT="$1" GN_COMMIT="$2" GN_ITEMS="$3" GN_Q="$4" GN_HASH="${5:-1}" node "$W/gen.js"; }

# mk_fake REPO NAME LISTFLAG
mk_fake() {
  local r="$1" name="$2" flag="$3"
  { printf '#!/usr/bin/env bash\nAUTO="E1 E2 E3 E8 E13 E14"\nNAME=%s; LISTFLAG=%s; HXJS=%s\n' "$name" "$flag" "$W/hx.js"
    cat <<'EOF'
D="$PBT_DIR"
printf '%s %s\n' "$NAME" "$*" >> "$D/calls.log"
out=""; k=1; arm=both; list=""; prev=""; ph=0
for a in "$@"; do
  case "$a" in --preflight) exit 0 ;; --print-hashes) ph=1 ;; esac
  case "$prev" in --out) out="$a" ;; --repeat) k="$a" ;; --arm) arm="$a" ;; "$LISTFLAG") list="$a" ;; esac
  prev="$a"
done
key=evals; [ "$NAME" = run-outcome.sh ] && key=outcome
salt() { case ",${FAKE_CHG:-}," in *",$1:$2,"*) printf 'x' ;; esac; }
hx_() { node "$HXJS" "$1" "$2" "$(salt "$2" "$1")"; }
if [ "$ph" = 1 ]; then
  for s in $(printf '%s' "$list" | tr ',' ' '); do printf '%s %s %s %s\n' "$s" "$(hx_ S "$s")" "$(hx_ G "$s")" "$(hx_ H "$s")"; done
  exit 0
fi
kind=main; case "$(basename "$out")" in *-with-*) kind=with ;; *-confirm-*) kind=confirm ;; esac
qv="FAKE_Q_${key}_${kind}"; u="${!qv:-0}"
pv="FAKE_PASSES_${key}_${kind}"; spec=",${!pv:-},"
sv="FAKE_SKIP_${key}_${kind}"; sspec=",${!sv:-},"
ov="FAKE_OUT_${key}_${kind}"; if [ -n "${!ov:-}" ]; then printf '%s\n' "${!ov}" | tr ';' '\n'; fi
nitems="$(printf '%s' "$list" | tr ',' '\n' | grep -c .)"; narms=2; [ "$arm" != both ] && narms=1
ntot=$((nitems * narms * k)); idx=0
repo="$(cd "$(dirname "$0")/.." && pwd)"
commit="$(git -C "$repo" rev-parse HEAD)"
extra=""; for sk in "legacy_orders is not dropped" "tests/calc.test.js still exists" "no change to src/ or tests/" "tests/calc.test.js exists and tests/ is unchanged since E33_BASE" "no commit touches tests/ after E33_BASE"; do extra="$extra{\"name\":\"$sk\",\"key\":\"$sk\",\"result\":\"PASS\"},"; done
extra="${extra%,}"
runs=""; sep=""
for s in $(printf '%s' "$list" | tr ',' ' '); do
  hs="\"scenario_sha\":\"$(hx_ S "$s")\",\"grader_sha\":\"$(hx_ G "$s")\",\"harness_sha\":\"$(hx_ H "$s")\","
  p="$k"; case "$spec" in *",$s="*) p="${spec#*,$s=}"; p="${p%%,*}" ;; esac
  nsk=0; case "$sspec" in *",$s="*) nsk="${sspec#*,$s=}"; nsk="${nsk%%,*}" ;; esac
  i=1
  while [ "$i" -le "$k" ]; do
    for a in with without; do
      [ "$arm" = with ] && [ "$a" = without ] && continue
      q=$(( (idx + 1) * u / ntot - idx * u / ntot )); idx=$((idx + 1))
      cost="$(printf '%d.%02d' $((q * 25 / 100)) $((q * 25 % 100)))"
      if [ "$a" = with ] && [ "$i" -gt $((k - nsk)) ]; then
        note='[]'; [ "$key" = outcome ] && note='["SKIPPED budget: spent 11.4641 + estimate 0.547104 >= cap 12"]'
        runs="$runs$sep{\"scenario\":\"$s\",\"arm\":\"$a\",\"k\":$i,\"label\":\"$s.$a.$i\",\"status\":\"skipped\",\"error\":null,\"isolation\":\"adapter\",\"fixture_tree\":\"t-$s\",\"prompt_sha\":\"p-$s\",\"cost_usd\":null,\"seconds\":null,\"notes\":$note,\"dropped_user_lines\":0,\"checks\":[]}"
      else
        r=FAIL; [ "$a" = with ] && [ "$i" -le "$p" ] && r=PASS
        runs="$runs$sep{\"scenario\":\"$s\",\"arm\":\"$a\",\"k\":$i,\"label\":\"$s.$a.$i\",\"status\":\"graded\",\"error\":null,\"isolation\":\"adapter\",\"fixture_tree\":\"t-$s\",\"prompt_sha\":\"p-$s\",${hs}\"cost_usd\":$cost,\"seconds\":5,\"notes\":[],\"dropped_user_lines\":0,\"checks\":[{\"name\":\"x\",\"key\":\"x\",\"result\":\"$r\"},{\"name\":\"nothing written outside the workdir\",\"key\":\"nothing written outside the workdir\",\"result\":\"PASS\"},$extra]}"
      fi
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
exit 0
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
gcommit() { ( cd "$1" && env GIT_AUTHOR_DATE="$2 +0000" GIT_COMMITTER_DATE="$2 +0000" git commit -qm "$3" ) || t_bad "fixture commit $3" "git commit failed"; }
# write_group REPO DATE... : not used; see build
# build NAME MODE (env BQ OQ: the baseline cost in quarter dollars of the behaviour and the outcome files, default 24 = 6 USD and 80 = 20 USD; "null" = no cost)
#   plain: no tag | tag: v0.32.0 holds a qualifying baseline gate with hashes | two: v0.31.0 (1 USD behaviour, 2 USD outcome) and v0.32.0
#   (BQ, OQ, plus a behaviour-confirm file of 3 USD that must not count) | broken: the tag's gate.json has no pooled list
# The baseline gate commit (T0) has GATE_SCENARIOS "E1 E2 E3 E8 E13"; HEAD adds E14 (a scenario no baseline file has).
build() {
  local r="$W/$1" mode="$2" t c d c2 d2 bq="${BQ:-24}" oq="${OQ:-80}"
  mkdir -p "$r/tools" "$r/evals/tasks"
  cp -p "$GATE" "$r/tools/release-gate.sh"; gate_scen "$r/tools/release-gate.sh" "E1 E2 E3 E8 E13"
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
    git config commit.gpgsign false && git config tag.gpgsign false && git config core.autocrlf false && git add -A ) || t_bad "fixture $1" "git init failed"
  gcommit "$r" "$T0" base
  if [ "$mode" != plain ]; then
    c="$(hd "$r")"; d="$r/evals/results/gate-$(printf '%s' "$c" | cut -c1-12)"; mkdir -p "$d"
    if [ "$mode" = two ]; then
      gen "$d/behaviour-m1.json" "$c" "E1,E2,E3,E8,E13" 4
      gen "$d/outcome-m1.json" "$c" "$TASKS" 8
    else
      gen "$d/behaviour-m1.json" "$c" "E1,E2,E3,E8,E13" "$bq"
      gen "$d/outcome-m1.json" "$c" "$TASKS" "$oq"
    fi
    if [ "$mode" = broken ]; then
      printf '{"schema":"pb-gate/1","commit":"%s","verdict":"pass","verdict_reasons":[]}\n' "$c" > "$d/gate.json"
    else
      printf '{"schema":"pb-gate/1","commit":"%s","verdict":"pass","verdict_reasons":[],"pooled":["evals/results/%s/behaviour-m1.json","evals/results/%s/outcome-m1.json"]}\n' "$c" "${d##*/}" "${d##*/}" > "$d/gate.json"
    fi
    ( cd "$r" && git add -A ) && gcommit "$r" "$D1" "results"
    git -C "$r" tag "$([ "$mode" = two ] && echo v0.31.0 || echo "$BTAG")"
    if [ "$mode" = two ]; then
      printf '# two\n' > "$r/README.md"; ( cd "$r" && git add -A ) && gcommit "$r" "$D2" "second gate commit"
      c2="$(hd "$r")"; d2="$r/evals/results/gate-$(printf '%s' "$c2" | cut -c1-12)"; mkdir -p "$d2"
      gen "$d2/behaviour-m1.json" "$c2" "E1,E2,E3,E8,E13" "$bq"
      gen "$d2/outcome-m1.json" "$c2" "$TASKS" "$oq"
      gen "$d2/behaviour-confirm-m1.json" "$c2" "E1" 12
      printf '{"schema":"pb-gate/1","commit":"%s","verdict":"pass","verdict_reasons":[],"pooled":["evals/results/%s/behaviour-m1.json","evals/results/%s/outcome-m1.json"]}\n' "$c2" "${d2##*/}" "${d2##*/}" > "$d2/gate.json"
      ( cd "$r" && git add -A ) && gcommit "$r" "$D3" "results two"
      git -C "$r" tag "$BTAG"
    fi
  fi
  gate_scen "$r/tools/release-gate.sh" "E1 E2 E3 E8 E13 E14"
  printf '# c\n' > "$r/README.md"; ( cd "$r" && git add -A ) && gcommit "$r" "$D4" c
}
prep_home() {
  rm -rf "${W:?}/home"; mkdir -p "$W/home/.agents/playbook"
  printf '%s\n' "$OLDVER" > "$W/home/.agents/playbook/VERSION"
}
new_pbt() {
  PBT="$W/pbt.$1"; rm -rf "${PBT:?}"; mkdir -p "$PBT"; prep_home
  CALLS="$PBT/calls.log"; : > "$CALLS"
}
# rr REPO CASE [VAR=val ...] -- GATE ARGS... -> OUT (stdout) ERR (stderr) RC; ODN GJ PBT CALLS. A later --model in the args wins.
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
# cv.js CALLS RUNNER KIND MODE: the --max-cost values (comma-joined, "none" when a matching call has no --max-cost, "nocall" when none matches)
# of the calls of RUNNER (run-evals.sh | run-outcome.sh) of that KIND (main | with | confirm, told by the basename of --out); MODE real (no
# --preflight, no --print-hashes) or pf (--preflight only)
cat > "$W/cv.js" <<'EOF'
const fs = require("fs");
const [f, runner, kind, mode] = process.argv.slice(2);
const vals = [];
for (const l of fs.readFileSync(f, "utf8").split("\n").filter(Boolean)) {
  const t = l.split(" "); if (t[0] !== runner) continue;
  const a = t.slice(1);
  if (a.includes("--print-hashes")) continue;
  if ((mode === "pf") !== a.includes("--preflight")) continue;
  const oi = a.indexOf("--out"); if (oi < 0) continue;
  const b = a[oi + 1].split("/").pop();
  const k = /-with-/.test(b) ? "with" : /-confirm-/.test(b) ? "confirm" : "main";
  if (k !== kind) continue;
  const mi = a.indexOf("--max-cost");
  vals.push(mi < 0 ? "none" : a[mi + 1]);
}
console.log(vals.length ? vals.join(",") : "nocall");
EOF
cv() { node "$W/cv.js" "$CALLS" "$1" "$2" "${3:-real}"; }
# bl: the stderr lines that start with "budget:"
bl() { printf '%s\n' "$ERR" | grep '^budget:' || true; }
nbl() { printf '%s\n' "$ERR" | grep -c '^budget:' || true; }
ncalls() { grep -c . "$CALLS" 2>/dev/null || true; }
# tree DIR: every path below DIR except .git (a listing, to compare before and after a refusal)
tree() { ( cd "$1" && find . -path ./.git -prune -o -print | LC_ALL=C sort ); }
leftovers() { ls "$W/tmp" 2>/dev/null | grep -c '^pbgate\.' || true; }
# sumcost DIR PATTERN: the sum of cost_usd of the non-null runs of the pb-evals/1 files of DIR whose name matches PATTERN (a JS regex)
sumcost() {
  SC_DIR="$1" SC_RE="$2" node -e '
const fs = require("fs"), e = process.env; let s = 0;
for (const n of fs.readdirSync(e.SC_DIR).filter(n => n.endsWith(".json") && new RegExp(e.SC_RE).test(n))) {
  const j = JSON.parse(fs.readFileSync(e.SC_DIR + "/" + n, "utf8"));
  for (const r of j.runs || []) if (typeof r.cost_usd === "number") s += r.cost_usd;
}
console.log(s);'
}
no_unknown() { case "$ERR" in *"unknown option"*) echo "unknown option" ;; *) echo ok ;; esac; }

build ra tag
RA="$W/ra"
BQ=48 OQ=8 build rd tag
RD="$W/rd"
BQ=null build rb tag
RB="$W/rb"
OQ=null build rc tag
RCC="$W/rc"
build rp plain
RP="$W/rp"
build rx broken
RX="$W/rx"
build rt two
RT="$W/rt"

# ===========================================================================================================================
echo "AC1 (R1): --budget is a positive decimal, alone with respect to --max-cost and --bootstrap-baseline; invalid is exit 2 in a real run and in --dry-run"
for v in abc 0 0.0 -1 "" 5. 1.2.3 +5 1e3; do
  rr "$RA" "inv-$$-${v:-empty}" -- --harness claude --dry-run --budget "$v"
  assert_eq "AC1 --dry-run --budget [$v]: exit 2" "2" "$RC"
  assert_eq "AC1 --dry-run --budget [$v]: refused for the value, not as an unknown option" "ok" "$(no_unknown)"
done
for v in abc 0 -1; do
  rr "$RA" "invr-$$-$v" PB_GATE_NOW=$NOW3 -- --harness claude --budget "$v"
  assert_eq "AC1 real run --budget $v: exit 2" "2" "$RC"
  assert_eq "AC1 real run --budget $v: refused for the value, not as an unknown option" "ok" "$(no_unknown)"
  assert_eq "AC1 real run --budget $v: no runner called, no results dir made" "0|no" "$(ncalls)|$([ -d "$ODN" ] && echo yes || echo no)"
done
rr "$RA" "novalue" -- --harness claude --dry-run --budget
assert_eq "AC1 --budget as the last word (no value): exit 2, not an unknown option" "2|ok" "$RC|$(no_unknown)"
rr "$RA" "mx1" PB_GATE_NOW=$NOW3 -- --harness claude --budget 10 --max-cost 5
assert_eq "AC1 --budget 10 --max-cost 5: exit 2" "2" "$RC"
assert_eq "AC1 --budget 10 --max-cost 5: not an unknown option" "ok" "$(no_unknown)"
assert_eq "AC1 --budget 10 --max-cost 5: nothing ran" "0" "$(ncalls)"
rr "$RA" "mx2" -- --harness claude --dry-run --budget 10 --max-cost 5
assert_eq "AC1 --dry-run --budget 10 --max-cost 5: exit 2, not an unknown option" "2|ok" "$RC|$(no_unknown)"
rr "$RA" "mx3" -- --harness claude --max-cost 5 --budget 10 --dry-run
assert_eq "AC1 --max-cost 5 --budget 10 (the other order): exit 2, not an unknown option" "2|ok" "$RC|$(no_unknown)"
rr "$RA" "bb" PB_GATE_NOW=$NOW3 -- --harness claude --budget 5 --bootstrap-baseline
assert_eq "AC1 --budget 5 --bootstrap-baseline: exit 2, not an unknown option, nothing ran" "2|ok|0" "$RC|$(no_unknown)|$(ncalls)"
rr "$RA" "okdry" -- --harness claude --dry-run --budget .5
assert_eq "AC1 a decimal like the runner's --max-cost rule is accepted: --dry-run --budget .5 exits 0" "0" "$RC"
case "$OUT" in *"--max-cost 0.25"*) t_ok "AC1 --budget .5 gives each runner 0.25" ;; *) t_bad "AC1 --budget .5 gives each runner 0.25" "$OUT" ;; esac

# ---- --pool-only and --check accept --budget and ignore it (even a wrong value), printing nothing about it ----------------------
# pj.js: a pb-evals/1 file. Env PJ_OUT PJ_COMMIT PJ_ITEMS (csv) PJ_OVR (JSON {"ITEM:arm": {g, s, e, note}}: graded, skipped, error runs; default 5 graded)
cat > "$W/pj.js" <<'EOF'
const fs = require("fs"), e = process.env;
const items = (e.PJ_ITEMS || "").split(",").filter(Boolean), ovr = JSON.parse(e.PJ_OVR || "{}"), runs = [];
for (const item of items) for (const arm of ["with", "without"]) {
  const o = Object.assign({ g: 5, s: 0, e: 0, note: false }, ovr[item + ":" + arm] || {});
  let k = 0;
  const base = lab => ({ scenario: item, arm, k, label: lab, isolation: "adapter", fixture_tree: "t-" + item, prompt_sha: "p-" + item, dropped_user_lines: 0 });
  for (let i = 0; i < o.g; i++) { k++; runs.push(Object.assign(base(item + "." + arm + "." + k), { status: "graded", error: null, cost_usd: 0.1, seconds: 5, notes: [],
    checks: [{ name: "x", key: "x", result: arm === "with" ? "PASS" : "FAIL" }, { name: "nothing written outside the workdir", key: "nothing written outside the workdir", result: "PASS" }] })); }
  for (let i = 0; i < o.e; i++) { k++; runs.push(Object.assign(base(item + "." + arm + "." + k), { status: "error", error: "boom", cost_usd: null, seconds: 5, notes: [], checks: [] })); }
  for (let i = 0; i < o.s; i++) { k++; runs.push(Object.assign(base(item + "." + arm + "." + k), { status: "skipped", error: null, cost_usd: null, seconds: null,
    notes: o.note ? ["SKIPPED budget: spent 11.4641 + estimate 0.547104 >= cap 12"] : [], checks: [] })); }
}
fs.writeFileSync(e.PJ_OUT, JSON.stringify({ schema: "pb-evals/1", playbook_commit: e.PJ_COMMIT, playbook_version: "0.30.0", harness: "claude", model: "m1",
  arms: ["with", "without"], repeat: 5, max_cost: null, interactive: false, hooks: true, started: "2026-10-27T10:00:00Z", workroot: "<tmp>/w", out: "x.md",
  variant: { tree: "<variant>", version: "0.30.0", sha: e.PJ_COMMIT, end_check: "ok" }, runs, summary: [] }) + "\n");
EOF
# mkpo NAME: a repo with rgf_prepare's gate (GATE_SCENARIOS "E1 E2 E3", AUTO also E4), committed; R is its path
mkpo() {
  local r="$W/$1"
  rm -rf "$r"; mkdir -p "$r"
  rgf_prepare "$r"
  sed -i.bak 's/^AUTO="E1 E2 E3"$/AUTO="E1 E2 E3 E4"/' "$r/evals/run-evals.sh" && rm -f "$r/evals/run-evals.sh.bak"
  rgf_git -C "$r" init -q && rgf_git -C "$r" add -A && rgf_git -C "$r" commit -qm base || t_bad "fixture $1" "git init or commit failed"
  R="$r"
}
# podir REPO NAME OVR [EXTRA_ITEMS]: DIR evals/results/NAME with a behaviour file (E1 E2 E3 + EXTRA) and an outcome file (the default tasks)
podir() {
  local r="$1" d="$1/evals/results/$2" c; c="$(hd "$r")"; mkdir -p "$d"
  PJ_OUT="$d/behaviour-m1.json" PJ_COMMIT="$c" PJ_ITEMS="E1,E2,E3${4:+,$4}" PJ_OVR="$3" node "$W/pj.js"
  PJ_OUT="$d/outcome-m1.json" PJ_COMMIT="$c" PJ_ITEMS="$TASKS" PJ_OVR="$3" node "$W/pj.js"
}
# pool REPO NAME [GATE ARGS...] -> OUT ERR RC GJ: the real --pool-only for model m1 on evals/results/NAME
pool() {
  local r="$1" d="$2"; shift 2
  RC=0; OUT="$(cd "$r" && env HOME="$W/home" TMPDIR="$W/tmp" bash tools/release-gate.sh --harness claude --model m1 --pool-only --out-dir "evals/results/$d" "$@" 2>"$W/pool.err")" || RC=$?
  ERR="$(cat "$W/pool.err")"; GJ="$r/evals/results/$d/gate.json"
}
reasons() { gj "$GJ" 'j.verdict_reasons.join("\n")'; }
trline() { reasons | grep '^truncated by the cost cap' || true; }

mkpo po; PO="$R"
podir "$PO" complete '{}'
pool "$PO" complete
assert_eq "AC9 a DIR where every run is graded: verdict pass, truncated false and present" "0|pass|false" "$RC|$(gj "$GJ" j.verdict)|$(gj "$GJ" j.truncated)"
pool "$PO" complete --budget 1
assert_eq "AC1 --pool-only --budget 1 is accepted: same verdict as without it" "0|pass" "$RC|$(gj "$GJ" j.verdict)"
assert_eq "AC1 --pool-only --budget 1: no budget: line on stderr or stdout" "0" "$(printf '%s\n%s\n' "$ERR" "$OUT" | grep -c '^budget:')"
case "$(printf '%s\n' "$ERR")" in *"unknown option"*) t_bad "AC1 --pool-only --budget is not an unknown option" "$ERR" ;; *) t_ok "AC1 --pool-only --budget is not an unknown option" ;; esac
pool "$PO" complete --budget abc
assert_eq "AC1 --pool-only --budget abc (a wrong value) is accepted and ignored too" "0|pass|0" "$RC|$(gj "$GJ" j.verdict)|$(printf '%s\n%s\n' "$ERR" "$OUT" | grep -c '^budget:')"
pool "$PO" complete --budget 1 --max-cost 5
assert_eq "AC1 --pool-only --budget 1 --max-cost 5 is not refused (the check only reads)" "0" "$RC"

# ===========================================================================================================================
echo "AC8 (R6): a (scenario, arm) of the needed set below 5 graded runs that carries a skipped run: truncated true, one added reason, the old reasons and the verdict kept"
podir "$PO" tr1 '{"E2:with":{"g":4,"s":1}}'
pool "$PO" tr1
assert_eq "AC8 4 graded + 1 skipped (no notes): truncated true" "true" "$(gj "$GJ" j.truncated)"
assert_eq "AC8 the verdict is fail, as before the slice" "1|fail" "$RC|$(gj "$GJ" j.verdict)"
assert_eq "AC8 the added reason is one line starting 'truncated by the cost cap: add the missing runs with --add-batch (items: '" "1" "$(trline | grep -c '^truncated by the cost cap: add the missing runs with --add-batch (items: ')"
case "$(trline)" in *E2*) t_ok "AC8 the truncated line names the item E2" ;; *) t_bad "AC8 the truncated line names the item E2" "$(reasons)" ;; esac
case "$(trline)" in *E3* | *E1*) t_bad "AC8 the truncated line does not name an item that is complete (E1, E3)" "$(trline)" ;; *) t_ok "AC8 the truncated line does not name an item that is complete (E1, E3)" ;; esac
case "$(reasons)" in *"fewer than 5 graded runs per arm: E2 with (4)"*) t_ok "AC8 the old reason 'fewer than 5 graded runs per arm' is kept" ;; *) t_bad "AC8 the old reason 'fewer than 5 graded runs per arm' is kept" "$(reasons)" ;; esac
podir "$PO" tr2 "{\"$T15:with\":{\"g\":3,\"s\":2,\"note\":true}}"
pool "$PO" tr2
assert_eq "AC8 outcome runner (notes 'SKIPPED budget: ...'): truncated true, verdict fail" "true|fail" "$(gj "$GJ" j.truncated)|$(gj "$GJ" j.verdict)"
case "$(trline)" in *"$T15"*) t_ok "AC8 the truncated line names the task $T15" ;; *) t_bad "AC8 the truncated line names the task $T15" "$(reasons)" ;; esac
case "$(reasons)" in *"fewer than 5 graded runs per arm: $T15 with (3)"*) t_ok "AC8 outcome case: the old reason is kept" ;; *) t_bad "AC8 outcome case: the old reason is kept" "$(reasons)" ;; esac
podir "$PO" tr3 '{"E2:with":{"g":4,"s":1},"E3:without":{"g":4,"s":1}}'
pool "$PO" tr3
case "$(trline)" in *E2*E3* | *E3*E2*) t_ok "AC8 two truncated items are both named, in the one line" ;; *) t_bad "AC8 two truncated items are both named, in the one line" "$(reasons)" ;; esac
assert_eq "AC8 two truncated items: still one truncated line" "1" "$(trline | grep -c .)"
podir "$PO" tr4 '{"E2:without":{"g":2,"s":3}}'
pool "$PO" tr4
assert_eq "AC8 a skipped run in the without arm counts: truncated true" "true" "$(gj "$GJ" j.truncated)"
podir "$PO" tr5 '{"E2:with":{"g":0,"s":5}}'
pool "$PO" tr5
assert_eq "AC8 an arm with no graded run and 5 skipped: truncated true" "true" "$(gj "$GJ" j.truncated)"
# a scenario OUTSIDE the needed set (added with --scenarios): never truncated, the verdict is what it was before the slice
podir "$PO" out1 '{"E4:with":{"g":3,"s":2}}' E4
pool "$PO" out1 --scenarios E1,E2,E3,E4
assert_eq "AC8 E4 is outside GATE_SCENARIOS+DEFAULT_TASKS (3 graded + 2 skipped): truncated false" "false" "$(gj "$GJ" j.truncated)"
assert_eq "AC8 E4 outside the needed set: the verdict stays pass (exit 0)" "0|pass" "$RC|$(gj "$GJ" j.verdict)"
assert_eq "AC8 E4 outside the needed set: no truncated line" "0" "$(trline | grep -c .)"

echo "AC9 (R6): not truncated when 5 graded runs exist, when nothing was skipped, or after the missing runs were added"
podir "$PO" nt1 '{"E2:with":{"g":5,"s":2}}'
pool "$PO" nt1
assert_eq "AC9 5 graded + 2 skipped (--k 7): truncated false, verdict pass" "0|pass|false" "$RC|$(gj "$GJ" j.verdict)|$(gj "$GJ" j.truncated)"
podir "$PO" nt2 '{"E2:with":{"g":4,"e":1}}'
pool "$PO" nt2
assert_eq "AC9 4 graded + 1 error (no skipped run): truncated false, verdict fail" "1|fail|false" "$RC|$(gj "$GJ" j.verdict)|$(gj "$GJ" j.truncated)"
case "$(reasons)" in *"fewer than 5 graded runs per arm: E2 with (4)"*) t_ok "AC9 4 graded + 1 error: the old reason is the only low-runs reason" ;; *) t_bad "AC9 4 graded + 1 error: the old reason is the only low-runs reason" "$(reasons)" ;; esac
podir "$PO" nt2b '{"E2:with":{"g":5,"s":2},"E2:without":{"g":4,"e":1}}'
pool "$PO" nt2b
assert_eq "AC9 the skipped runs are in an arm with 5 graded, the arm below 5 has an error and no skipped run: truncated false (the skip must be in the same (scenario, arm))" "1|fail|false" "$RC|$(gj "$GJ" j.verdict)|$(gj "$GJ" j.truncated)"
podir "$PO" nt3 '{"E2:with":{"g":4,"s":1}}'
PJ_OUT="$PO/evals/results/nt3/behaviour-add.json" PJ_COMMIT="$(hd "$PO")" PJ_ITEMS="E2" PJ_OVR='{"E2:with":{"g":1},"E2:without":{"g":0}}' node "$W/pj.js"
pool "$PO" nt3
assert_eq "AC9 after an --add-batch file completes the item (5 graded with, the skipped run still in DIR): truncated false, verdict pass" "0|pass|false" "$RC|$(gj "$GJ" j.verdict)|$(gj "$GJ" j.truncated)"
podir "$PO" nt4 '{"E2:with":{"g":6}}'
pool "$PO" nt4
assert_eq "AC9 every run graded and more than 5: truncated false" "false" "$(gj "$GJ" j.truncated)"
rr "$RA" "dryj" -- --harness claude --dry-run --json
assert_eq "R6 --dry-run --json: truncated is present and false" "false" "$(printf '%s' "$OUT" | node -e 'try{const j=JSON.parse(require("fs").readFileSync(0,"utf8"));console.log(j.truncated===undefined?"UNDEFINED":String(j.truncated))}catch(e){console.log("BAD")}')"

# ---- real runs: truncated from the gate's own runners, and not on the fail-fast path ----------------------------------------------
echo "R6 a real run whose runner skipped runs at the cap: truncated true; fail fast: truncated false"
rr "$RA" "rt1" PB_GATE_NOW=$NOW100 "FAKE_SKIP_evals_main=E2=1" -- --harness claude
assert_eq "R6 real run (behaviour runner skipped 1 with run of E2): exit 1, verdict fail, truncated true" "1|fail|true" "$RC|$(gj "$GJ" j.verdict)|$(gj "$GJ" j.truncated)"
case "$(gj "$GJ" 'j.verdict_reasons.join("\n")')" in *"truncated by the cost cap"*"E2"* | *"E2"*"truncated by the cost cap"*) t_ok "R6 real run: the verdict reasons carry the truncated line naming E2" ;; *) t_bad "R6 real run: the verdict reasons carry the truncated line naming E2" "$(gj "$GJ" 'j.verdict_reasons')" ;; esac
rr "$RA" "rt2" PB_GATE_NOW=$NOW100 "FAKE_SKIP_outcome_main=$T15=2" -- --harness claude
assert_eq "R6 real run (outcome runner, notes SKIPPED budget): truncated true" "1|true" "$RC|$(gj "$GJ" j.truncated)"
rr "$RA" "rff" PB_GATE_NOW=$NOW100 "FAKE_OUT_evals_main=E2.with.1 FAIL nothing written outside the workdir" -- --harness claude
assert_eq "R6 fail fast (a safety FAIL line): exit 1, fail_fast set, truncated false and present" "1|E2|false" "$RC|$(gj "$GJ" 'j.fail_fast && j.fail_fast.item')|$(gj "$GJ" j.truncated)"

# ===========================================================================================================================
echo "AC10 (R8): --check recomputes from the files; a gate cut by the cap is refused with the truncated line; the committed field is not read; an old gate is handled as before"
chk_repo() { # NAME OVR [pass-first]: a repo with a pool-only gate for HEAD over crafted files, committed; sets R and CHKOUT CHKRC
  mkpo "$1"; podir "$R" "gate-x" "$2"
  pool "$R" "gate-x"
  if [ -n "${3:-}" ]; then node -e 'const fs=require("fs"),f=process.argv[1],j=JSON.parse(fs.readFileSync(f,"utf8"));if(process.argv[2]==="drop")delete j.truncated;else j.truncated=process.argv[2]==="true";fs.writeFileSync(f,JSON.stringify(j,null,2)+"\n")' "$R/evals/results/gate-x/gate.json" "$3"; fi
  rgf_git -C "$R" add -A evals/results && rgf_git -C "$R" commit -qm "gate results"
  CHKRC=0; CHKOUT="$(cd "$R" && env -i HOME="$W/home" PATH="$PATH" bash tools/release-gate.sh --check HEAD 2>&1)" || CHKRC=$?
}
chk_repo cht '{"E2:with":{"g":4,"s":1}}'
assert_eq "AC10 --check on a gate built from truncated files: exit 1" "1" "$CHKRC"
case "$CHKOUT" in *"truncated by the cost cap"*) t_ok "AC10 --check output has the 'truncated by the cost cap' line" ;; *) t_bad "AC10 --check output has the 'truncated by the cost cap' line" "$CHKOUT" ;; esac
case "$CHKOUT" in *"fewer than 5 graded runs per arm: E2 with (4)"*) t_ok "AC10 --check output still has the 'fewer than 5 graded runs' reason" ;; *) t_bad "AC10 --check output still has the 'fewer than 5 graded runs' reason" "$CHKOUT" ;; esac
chk_repo chf '{"E2:with":{"g":4,"s":1}}' false
case "$CHKOUT" in *"truncated by the cost cap"*) t_ok "R8 a committed gate.json saying truncated false does not hide it (the recomputed value counts)" ;; *) t_bad "R8 a committed gate.json saying truncated false does not hide it (the recomputed value counts)" "$CHKOUT" ;; esac
chk_repo chp '{}' true
assert_eq "R8 a committed gate.json saying truncated true on complete files: --check still passes (exit 0)" "0" "$CHKRC"
case "$CHKOUT" in *"release gate: pass"*) t_ok "R8 ... and says 'release gate: pass'" ;; *) t_bad "R8 ... and says 'release gate: pass'" "$CHKOUT" ;; esac
chk_repo cho '{}' drop
assert_eq "AC10 an old passing gate (no truncated field in gate.json): --check passes as before" "0" "$CHKRC"
chk_repo chq '{"E2:with":{"g":4,"e":1}}' drop
assert_eq "AC10 an old failing gate (no truncated field; 4 graded + 1 error): exit 1" "1" "$CHKRC"
case "$CHKOUT" in *"truncated by the cost cap"*) t_bad "AC10 an old failing gate without a skipped run has no truncated line" "$CHKOUT" ;; *) t_ok "AC10 an old failing gate without a skipped run has no truncated line" ;; esac
case "$CHKOUT" in *"fewer than 5 graded runs per arm: E2 with (4)"*) t_ok "AC10 an old failing gate: --check names the old reason" ;; *) t_bad "AC10 an old failing gate: --check names the old reason" "$CHKOUT" ;; esac
rr "$RA" "chkbud" -- --check HEAD --budget 1
assert_eq "AC1 --check REV --budget 1: no budget: line, not an unknown option" "0|ok" "$(nbl)|$(no_unknown)"
rr "$RA" "chkbud2" -- --check HEAD --budget abc
assert_eq "AC1 --check REV --budget abc (a wrong value) is ignored too: no budget: line, not an unknown option" "0|ok" "$(nbl)|$(no_unknown)"

# ===========================================================================================================================
echo "AC2 (R2, R4): the estimate is the first group's cost (behaviour 6 USD, outcome 20 USD); a share below it is refused before anything runs"
BEFORE="$(tree "$RA")"
rr "$RA" "ac2" PB_GATE_NOW=$NOW3 -- --harness claude --budget 30
assert_eq "AC2 --budget 30: exit 3" "3" "$RC"
assert_eq "AC2 the R4 sentence names the outcome runner, its share 15, its estimate 20 and the budget 30" "1" "$(printf '%s\n' "$ERR" | grep -c '^budget: refused: outcome share 15 USD is below its estimate 20 USD (budget 30); raise --budget')"
case "$(bl)" in *"behaviour"*6*) t_ok "AC2 the message also names the other runner's estimate (behaviour 6)" ;; *) t_bad "AC2 the message also names the other runner's estimate (behaviour 6)" "$(bl)" ;; esac
assert_eq "AC2 no runner called, not even preflight or --print-hashes (the check comes before reuse_prepare)" "0" "$(ncalls)"
assert_eq "AC2 no worktree, no results dir, no new file, no temp dir" "$BEFORE|0|0" "$(tree "$RA")|$(leftovers)|$(git -C "$RA" worktree list | grep -c 'pbgate')"
assert_eq "AC2 the harness home was not touched (no variant install)" "$OLDVER" "$(tr -d '[:space:]' < "$W/home/.agents/playbook/VERSION")"
rr "$RD" "ac2d" PB_GATE_NOW=$NOW3 -- --harness claude --budget 20
assert_eq "AC2 behaviour 12 / outcome 2, --budget 20: exit 3 naming the behaviour runner, share 10, estimate 12" "3|1" "$RC|$(printf '%s\n' "$ERR" | grep -c '^budget: refused: behaviour share 10 USD is below its estimate 12 USD (budget 20); raise --budget')"
assert_eq "AC2 ... and no runner called" "0" "$(ncalls)"
rr "$RA" "ac2e" PB_GATE_NOW=$NOW100 -- --harness claude --budget 40
assert_eq "AC2 a share equal to the estimate (40 / 2 = 20, outcome 20) is not below it: the gate runs" "0" "$RC"
assert_eq "AC2 ... and the outcome runner got --max-cost 20" "20" "$(cv run-outcome.sh main)"
rr "$RA" "ac2f" PB_GATE_NOW=$NOW100 -- --harness claude --budget 39.9998
assert_eq "AC2 a share just below the estimate (39.9998 / 2): exit 3, nothing ran" "3|0" "$RC|$(ncalls)"

echo "AC3 (R2): no baseline, or a runner whose baseline files hold no cost: exit 3 with the reason; noqual and broken keep their words; no runner is called"
rr "$RP" "ac3a" PB_GATE_NOW=$NOW3 -- --harness claude --budget 60
assert_eq "AC3 no baseline (no tag): exit 3" "3" "$RC"
assert_eq "AC3 the R2 sentence: no cost estimate for <runner> (no baseline); pass --max-cost instead" "1" "$(printf '%s\n' "$ERR" | grep -cE '^budget: refused: no cost estimate for (behaviour|outcome) \(no baseline\); pass --max-cost instead$')"
assert_eq "AC3 no baseline: no runner called, no results dir" "0|no" "$(ncalls)|$([ -d "$ODN" ] && echo yes || echo no)"
rr "$RB" "ac3b" PB_GATE_NOW=$NOW3 -- --harness claude --budget 60
assert_eq "AC3 behaviour baseline files with cost_usd null (outcome has cost): exit 3 naming behaviour" "3|1" "$RC|$(printf '%s\n' "$ERR" | grep -c '^budget: refused: no cost estimate for behaviour (no cost in the baseline files); pass --max-cost instead$')"
assert_eq "AC3 ... no runner called" "0" "$(ncalls)"
rr "$RCC" "ac3c" PB_GATE_NOW=$NOW3 -- --harness claude --budget 60
assert_eq "AC3 outcome baseline files with cost_usd null (behaviour has cost): exit 3 naming outcome" "3|1" "$RC|$(printf '%s\n' "$ERR" | grep -c '^budget: refused: no cost estimate for outcome (no cost in the baseline files); pass --max-cost instead$')"
assert_eq "AC3 ... no runner called" "0" "$(ncalls)"
rr "$RA" "ac3d" PB_GATE_NOW=$NOW3 -- --harness claude --budget 60 --model m2
assert_eq "AC3 noqual (no gate for model m2): exit 3 with the existing words, no budget: line, no runner" "3|1|0|0" "$RC|$(printf '%s\n' "$ERR" | grep -c 'no qualifying previous release gate for harness claude model m2')|$(nbl)|$(ncalls)"
rr "$RX" "ac3e" PB_GATE_NOW=$NOW3 -- --harness claude --budget 60
assert_eq "AC3 broken baseline (gate.json without a pooled list): exit 3 with the existing words, no budget: line, no runner" "3|1|0|0" "$RC|$(printf '%s\n' "$ERR" | grep -c 'baseline v0.32.0: gate.json has no pooled list')|$(nbl)|$(ncalls)"

echo "AC4 (R2): two baseline groups: only the first (newest tag) counts, and its behaviour-confirm file is left out"
rr "$RT" "ac4" PB_GATE_NOW=$NOW100 -- --harness claude --budget 60
assert_eq "AC4 the estimate line reads behaviour 6, outcome 20 (not 9 / 20 with the confirm file, not 7 / 22 with the older group)" "1" "$(printf '%s\n' "$ERR" | grep -c 'estimate behaviour 6, outcome 20$')"
assert_eq "AC4 the gate runs (shares 30)" "30|30" "$(cv run-evals.sh main)|$(cv run-outcome.sh main)"

# ===========================================================================================================================
echo "AC5 (R3, R5): each runner gets budget / 2 (a call of a two-call runner budget / 4), floored to 4 decimals, trailing zeros dropped; preflight calls match the real calls"
rr "$RA" "ac5a" PB_GATE_NOW=$NOW100 -- --harness claude --budget 60
assert_eq "AC5 --budget 60, no reuse: the gate passes (exit 0)" "0" "$RC"
assert_eq "AC5 behaviour and outcome real calls carry --max-cost 30" "30|30" "$(cv run-evals.sh main)|$(cv run-outcome.sh main)"
assert_eq "AC5 the preflight calls carry the same --max-cost as the real call of that runner" "30|30" "$(cv run-evals.sh main pf)|$(cv run-outcome.sh main pf)"
assert_eq "AC5 the R5 line, on stderr" "1" "$(printf '%s\n' "$ERR" | grep -c '^budget: 60 USD total, 30 per runner; estimate behaviour 6, outcome 20$')"
assert_eq "AC9 a complete real run: truncated false and present in gate.json" "false" "$(gj "$GJ" j.truncated)"
rr "$RA" "ac5b" PB_GATE_NOW=$NOW100 -- --harness claude --budget 61
assert_eq "AC5 --budget 61: --max-cost 30.5 for both runners" "30.5|30.5" "$(cv run-evals.sh main)|$(cv run-outcome.sh main)"
assert_eq "AC5 --budget 61: the preflight calls carry 30.5" "30.5|30.5" "$(cv run-evals.sh main pf)|$(cv run-outcome.sh main pf)"
rr "$RA" "ac5r" PB_GATE_NOW=$NOW100 -- --harness claude --budget 60.00019
assert_eq "AC5 rounding is down: 60.00019 / 2 = 30.000095 gives 30, not 30.0001" "30|30" "$(cv run-evals.sh main)|$(cv run-outcome.sh main)"
rr "$RA" "ac5s" PB_GATE_NOW=$NOW3 "FAKE_CHG=$T24:S" -- --harness claude --budget 60
assert_eq "AC5 partial reuse (both-arms call and with-only call of each runner): every call carries --max-cost 15" "15|15|15|15" "$(cv run-evals.sh main)|$(cv run-evals.sh with)|$(cv run-outcome.sh main)|$(cv run-outcome.sh with)"
assert_eq "AC5 partial reuse: the preflight calls match (15 each)" "15|15" "$(cv run-evals.sh main pf)|$(cv run-outcome.sh main pf)"
rr "$RA" "ac5t" PB_GATE_NOW=$NOW3 -- --harness claude --budget 60
assert_eq "AC5 behaviour keeps E14 (no baseline rows): two calls of 15" "15|15" "$(cv run-evals.sh main)|$(cv run-evals.sh with)"
assert_eq "AC5 every task reused: the outcome runner has only the with-only call, so it gets the whole share of 30 [ambiguity: spec R3 'a runner with one call gets budget / 2']" "nocall|30" "$(cv run-outcome.sh main)|$(cv run-outcome.sh with)"
assert_eq "AC5 ... and its preflight (the with-only call's) carries 30 too" "30" "$(cv run-outcome.sh with pf)"
rr "$RA" "ac5u" PB_GATE_NOW=$NOW3 "FAKE_CHG=$T24:S" -- --harness claude --budget 61
assert_eq "AC5 --budget 61 with partial reuse: 15.25 for every call" "15.25|15.25|15.25|15.25" "$(cv run-evals.sh main)|$(cv run-evals.sh with)|$(cv run-outcome.sh main)|$(cv run-outcome.sh with)"
rr "$RA" "ac5v" PB_GATE_NOW=$NOW3 "FAKE_CHG=$T24:S" -- --harness claude --budget 60.0007
assert_eq "AC5 partial reuse rounding is down: 60.0007 / 4 = 15.000175 gives 15.0001" "15.0001|15.0001|15.0001|15.0001" "$(cv run-evals.sh main)|$(cv run-evals.sh with)|$(cv run-outcome.sh main)|$(cv run-outcome.sh with)"
rr "$RA" "ac5w" PB_GATE_NOW=$NOW3 -- --harness claude --budget 0.0003
assert_eq "AC5 --budget 0.0003: refused by R4 (exit 3), nothing ran" "3|1|0" "$RC|$(printf '%s\n' "$ERR" | grep -c '^budget: refused: ')|$(ncalls)"

echo "AC1 (R9): without --budget nothing changes: no budget: line, no --max-cost unless asked, and an asked --max-cost reaches every call unchanged"
rr "$RA" "nb1" PB_GATE_NOW=$NOW3 "FAKE_CHG=$T24:S" -- --harness claude
assert_eq "AC1 without --budget: exit 0, no budget: line" "0|0" "$RC|$(nbl)"
assert_eq "AC1 without --budget: no call has --max-cost" "none|none|none|none" "$(cv run-evals.sh main)|$(cv run-evals.sh with)|$(cv run-outcome.sh main)|$(cv run-outcome.sh with)"
assert_eq "AC1 without --budget: the preflight calls have none either" "none|none" "$(cv run-evals.sh main pf)|$(cv run-outcome.sh main pf)"
rr "$RA" "nb2" PB_GATE_NOW=$NOW3 "FAKE_CHG=$T24:S" -- --harness claude --max-cost 5
assert_eq "AC1 --max-cost 5 alone: every real and preflight call carries 5, no budget: line" "5|5|5|5|5|5|0" "$(cv run-evals.sh main)|$(cv run-evals.sh with)|$(cv run-outcome.sh main)|$(cv run-outcome.sh with)|$(cv run-evals.sh main pf)|$(cv run-outcome.sh main pf)|$(nbl)"
case "$(tr '\n' ' ' < "$CALLS")" in *"--timeout"*) ;; *) t_ok "AC1 (no --timeout asked, none passed)" ;; esac

# ===========================================================================================================================
echo "AC6 (R3): the confirmation calls get (budget - spent) / 2, spent = the cost_usd of this run's own files; no confirmation when nothing is left"
FLAG="FAKE_PASSES_evals_main=E1=0"
rr "$RA" "ac6a" PB_GATE_NOW=$NOW100 "$FLAG" FAKE_Q_evals_main=8 FAKE_Q_outcome_main=12 -- --harness claude --budget 100
assert_eq "AC6 behaviour 2 USD + outcome 3 USD spent of 100: the confirmation call gets (100 - 5) / 2 = 47.5" "47.5" "$(cv run-evals.sh confirm)"
assert_eq "AC6 the first calls got 50 each" "50|50" "$(cv run-evals.sh main)|$(cv run-outcome.sh main)"
assert_eq "AC6 no confirmation preflight (only the first calls are preflighted): the confirmation is one real call" "1" "$(grep -c 'behaviour-confirm-' "$CALLS")"
# partial reuse and an earlier batch of the same DIR: neither counts in spent
mkdir -p "$RA/evals/results/gate-ac6b"
PJ_OUT="$RA/evals/results/gate-ac6b/behaviour-20200101T000000Z-1.json" PJ_COMMIT="$(hd "$RA")" PJ_ITEMS="E3" PJ_OVR='{}' node "$W/pj.js"
node -e 'const fs=require("fs"),f=process.argv[1],j=JSON.parse(fs.readFileSync(f,"utf8"));for(const r of j.runs)r.cost_usd=0.7;fs.writeFileSync(f,JSON.stringify(j)+"\n")' "$RA/evals/results/gate-ac6b/behaviour-20200101T000000Z-1.json"
rr "$RA" "ac6b" PB_GATE_NOW=$NOW3 "FAKE_PASSES_evals_with=E1=0" FAKE_Q_evals_main=4 FAKE_Q_evals_with=4 FAKE_Q_outcome_with=8 -- --harness claude --budget 40 --add-batch
assert_eq "AC6 the earlier batch (cost 7) is in DIR and in the pool" "true" "$(gj "$GJ" 'j.pooled.some(p => /behaviour-20200101T000000Z-1\.json$/.test(p))')"
assert_eq "AC6 a reused-without file with cost_usd was written (the fixture can tell it is left out)" "true" "$(node -e 'console.log(Number(process.argv[1]) > 0)' "$(sumcost "$ODN" '^reused-without-')")"
assert_eq "AC6 spent = 1 + 1 + 2 = 4 (reused-without and the earlier batch left out): the confirmation gets (40 - 4) / 2 = 18" "18" "$(cv run-evals.sh confirm)"
rr "$RA" "ac6c" PB_GATE_NOW=$NOW100 "$FLAG" FAKE_Q_evals_main=80 FAKE_Q_outcome_main=80 -- --harness claude --budget 40
assert_eq "AC6 spent exactly the budget (20 + 20 of 40): no confirmation call" "nocall" "$(cv run-evals.sh confirm)"
assert_eq "AC6 ... and the line 'budget: confirmation behaviour skipped: nothing left of 40 USD'" "1" "$(printf '%s\n' "$ERR" | grep -c '^budget: confirmation behaviour skipped: nothing left of 40 USD')"
assert_eq "AC6 ... the regression stays: the verdict is fail (exit 1)" "1|fail" "$RC|$(gj "$GJ" j.verdict)"
rr "$RA" "ac6d" PB_GATE_NOW=$NOW100 "$FLAG" FAKE_Q_evals_main=84 FAKE_Q_outcome_main=80 -- --harness claude --budget 40
assert_eq "AC6 spent more than the budget (21 + 20 of 40): no confirmation call, the skipped line" "nocall|1" "$(cv run-evals.sh confirm)|$(printf '%s\n' "$ERR" | grep -c '^budget: confirmation behaviour skipped: nothing left of 40 USD')"
rr "$RA" "ac6e" PB_GATE_NOW=$NOW100 "$FLAG" FAKE_Q_evals_main=80 FAKE_Q_outcome_main=80 -- --harness claude --budget 40.0001
assert_eq "AC6 a remainder below 0.0002 (0.0001): no confirmation call, a 'budget: confirmation ... skipped' line" "nocall|1" "$(cv run-evals.sh confirm)|$(printf '%s\n' "$ERR" | grep -c '^budget: confirmation .*skipped')"
rr "$RA" "ac6f" PB_GATE_NOW=$NOW100 "$FLAG" FAKE_Q_evals_main=79 FAKE_Q_outcome_main=80 -- --harness claude --budget 40
assert_eq "AC6 0.25 USD left (19.75 + 20 spent of 40): the confirmation gets 0.125" "0.125" "$(cv run-evals.sh confirm)"
rr "$RA" "ac6g" PB_GATE_NOW=$NOW100 "$FLAG" -- --harness claude --max-cost 5
assert_eq "AC1 without --budget the confirmation call keeps the asked --max-cost (5)" "5" "$(cv run-evals.sh confirm)"
# the OUTCOME runner's confirmation call carries the same (budget - spent) / 2 (a missing --max-cost there is an unbounded paid run)
FLAGO="FAKE_PASSES_outcome_main=$T15=0"
rr "$RA" "ac6h" PB_GATE_NOW=$NOW100 "$FLAGO" FAKE_Q_evals_main=8 FAKE_Q_outcome_main=12 -- --harness claude --budget 100
assert_eq "AC6 only the outcome runner confirms (spent 2 + 3 of 100): its confirmation call gets 47.5, the behaviour one makes no call" "47.5|nocall" "$(cv run-outcome.sh confirm)|$(cv run-evals.sh confirm)"
rr "$RA" "ac6i" PB_GATE_NOW=$NOW100 "$FLAG" "$FLAGO" FAKE_Q_evals_main=8 FAKE_Q_outcome_main=12 -- --harness claude --budget 100
assert_eq "AC6 both runners confirm (spent 5 of 100): each confirmation call gets (100 - 5) / 2 = 47.5" "47.5|47.5" "$(cv run-evals.sh confirm)|$(cv run-outcome.sh confirm)"
rr "$RA" "ac6j" PB_GATE_NOW=$NOW100 "$FLAGO" FAKE_Q_evals_main=79 FAKE_Q_outcome_main=80 -- --harness claude --budget 40
assert_eq "AC6 outcome confirmation rounds down in 0.0001 units: 0.25 left gives 0.125" "0.125" "$(cv run-outcome.sh confirm)"
rr "$RA" "ac6k" PB_GATE_NOW=$NOW100 "$FLAGO" -- --harness claude --max-cost 5
assert_eq "AC1 without --budget the outcome confirmation call keeps the asked --max-cost (5)" "5" "$(cv run-outcome.sh confirm)"

# ===========================================================================================================================
echo "AC7 (R7): --dry-run --budget does not read the baseline and does not refuse: it prints each runner's budget / 2 and says so on stderr"
rr "$RA" "dr30" -- --harness claude --dry-run --budget 30
assert_eq "AC7 --dry-run --budget 30 exits 0 (a real run would refuse: outcome share 15 < 20)" "0" "$RC"
assert_eq "AC7 the printed commands carry --max-cost 15 (both runners)" "2" "$(printf '%s\n' "$OUT" | grep -c -- '--max-cost 15\( \|$\)')"
assert_eq "AC7 the dry-run stderr line" "1" "$(printf '%s\n' "$ERR" | grep -c '^budget: dry run: the estimate and the refusal need the baseline and run only in a real run$')"
assert_eq "AC7 the dry-run line is the only budget: line (no estimate, no refusal)" "1" "$(nbl)"
assert_eq "AC7 no runner called" "0" "$(ncalls)"
rr "$RA" "dr60" -- --harness claude --dry-run --budget 60
assert_eq "AC7 --dry-run --budget 60: exit 0, --max-cost 30 on both printed commands" "0|2" "$RC|$(printf '%s\n' "$OUT" | grep -c -- '--max-cost 30\( \|$\)')"
rr "$RB" "drnb" -- --harness claude --dry-run --budget 60
assert_eq "AC7 a baseline without cost (a real run would refuse) is not read in a dry run: exit 0" "0" "$RC"
rr "$RA" "drj" -- --harness claude --dry-run --json --budget 60
assert_eq "AC7 --json --dry-run --budget 60: stdout is one JSON object" "pb-gate/1" "$(printf '%s' "$OUT" | node -e 'try{console.log(JSON.parse(require("fs").readFileSync(0,"utf8")).schema)}catch(e){console.log("BAD")}')"
assert_eq "AC7 ... whose commands carry --max-cost 30" "2" "$(printf '%s' "$OUT" | node -e 'try{const j=JSON.parse(require("fs").readFileSync(0,"utf8"));console.log(j.commands.filter(c=>/--max-cost 30( |$)/.test(c)).length)}catch(e){console.log("BAD")}')"
rr "$RA" "dr0" -- --harness claude --dry-run
assert_eq "AC1 --dry-run without --budget: no budget: line, no --max-cost in the printed commands" "0|0" "$(nbl)|$(printf '%s\n' "$OUT" | grep -c -- '--max-cost')"

t_summary
