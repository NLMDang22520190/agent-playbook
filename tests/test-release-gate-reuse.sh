#!/usr/bin/env bash
# Tests for slice B4 of tools/release-gate.sh (v0.34.0; spec .agents/handoff/01-spec.md R1, R2, R3, R4; decisions D10, D14, D21):
#   R1  a real run reuses the without-arm rows of the newest qualifying baseline gate for an item (scenario or task) when every graded
#       without-arm run of the item in the baseline carries scenario_sha, grader_sha and harness_sha equal to the CURRENT hashes of the
#       item, there are >= 5 of them and the baseline gate commit is <= 7 days old; it then asks the runner for the WITH arm only.
#   R2  gate.json `reuse` {baseline {tag, commit, dir}, age_days, items [{item, reused, why}]} (null without a baseline); the reused rows
#       go to DIR/reused-without-<stamp>.json (pb-evals/1, playbook_commit HEAD, no variant, reused_from) and are pooled.
#   R3  k stays 5 for every item: with-arm repeat 5 for reused and not reused items, 5 pooled without runs per item.
#   R4  rule (a) accepts a reused-without file only when its runs equal without-arm runs of the file its reused_from names in that tag's
#       tree; --check passes on a committed reuse gate, fails on a tampered one, and a later gate qualifies it as its baseline (D14).
# PINNED INTERFACES (the implementation must follow them; see .agents/handoff/02-tests-B4.md):
#   evals/run-evals.sh   <selection as in a real call: --harness H | --cmd C> --model M --scenarios LIST --print-hashes
#   evals/run-outcome.sh <selection as in a real call: --harness H | --cmd C> --model M --tasks LIST     --print-hashes
#     print one "<item> <scenario_sha> <grader_sha> <harness_sha>" line per item of the selection (40 hex each), exit 0, run nothing.
#     The gate calls each runner so, once, before its first real (paid) call and uses the lines as the current hashes.
#   PB_GATE_NOW=<unix seconds>  the gate's clock for the age of the baseline (default: the real time).
#   why strings of gate.json reuse.items: "hashes match" | "scenario_sha differs" | "grader_sha differs" | "harness_sha differs" |
#     "baseline older than 7 days" | "fewer than 5 without runs" | "no hashes in baseline".
#   --check failure line: "reused rows do not match <tag>:<file of the tag's tree>".
# The fixture repos hold the real tools/release-gate.sh, tools/eval-delta.sh, evals/lib-harness.sh, a fake install.sh and FAKE runners that
# record every call in $PBT_DIR/calls.log, answer --print-hashes (hash = sha1 of "<S|G|H>:<item>:<salt>"; FAKE_CHG="E2:S,E3:G" changes
# the current hash of that item/kind) and write the hashes in the runs they produce. Git commit dates are fixed (T0 = 1790000000).
# Never calls a real harness. Needs node and git.
. "$(dirname "$0")/lib.sh"
GATE="$PB_ROOT/tools/release-gate.sh"
command -v node >/dev/null 2>&1 || { t_skip 1 "node missing"; t_summary; exit $?; }
command -v git >/dev/null 2>&1 || { t_skip 1 "git missing"; t_summary; exit $?; }
. "$(dirname "$0")/release-gate-fixture.sh"
rgf_gh_install "$RGF_W/gh"; export PATH="$RGF_GH/bin:$PATH"; export PB_GATE_REPO=acme/widgets

W="$(mk_tmp)"
mkdir -p "$W/home" "$W/tmp"
T15="pattern-15-erase-account-ambiguous"; T24="pattern-24-merge-duplicate-customers"; T26="pattern-26-consistent-price-rounding"
TASKS="$T15,$T24,$T26"
BTAG="v0.32.0"; GTAG="v0.33.0"
OLDVER="0.0.1-base"; NEWVER="7.7.7-fix"
T0=1790000000
D1=$((T0 + 86400)); D2=$((T0 + 2 * 86400))
NOW3=$((T0 + 3 * 86400)); NOW7=$((T0 + 7 * 86400)); NOW7P=$((T0 + 7 * 86400 + 1)); NOW100=$((T0 + 100 * 86400))

# hx.js KIND ITEM SALT -> the 40 hex hash both the fake runners and the baseline generator use
cat > "$W/hx.js" <<'EOF'
console.log(require("crypto").createHash("sha1").update(process.argv.slice(2).join(":")).digest("hex"));
EOF
# gen.js: one baseline pb-evals/1 file. Env: GN_OUT GN_COMMIT GN_ITEMS GN_HASH(1) GN_HARNESS GN_MIX("ITEM:grader:K": the without run K has another grader_sha)
cat > "$W/gen.js" <<'EOF'
const fs = require("fs"), e = process.env, cr = require("crypto");
const hx = (k, i, s) => cr.createHash("sha1").update([k, i, s || ""].join(":")).digest("hex");
const items = (e.GN_ITEMS || "").split(",").filter(Boolean), runs = [];
const mix = (e.GN_MIX || "").split(":");
for (const item of items) for (const arm of ["with", "without"]) for (let i = 1; i <= 5; i++) {
  const r = { scenario: item, arm, k: i, label: item + "." + arm + "." + i, status: "graded", error: null, isolation: "adapter",
    fixture_tree: "t-" + item, prompt_sha: "p-" + item, cost_usd: 0.1, seconds: 5, notes: [], dropped_user_lines: 0,
    checks: [{ name: "x", key: "x", result: arm === "with" ? "PASS" : "FAIL" },
      { name: "nothing written outside the workdir", key: "nothing written outside the workdir", result: "PASS" }] };
  if (e.GN_HASH === "1") {
    r.scenario_sha = hx("S", item); r.grader_sha = hx("G", item); r.harness_sha = hx("H", item);
    if (arm === "without" && mix[0] === item && Number(mix[2]) === i) r.grader_sha = hx("G", item, "other");
  }
  runs.push(r);
}
fs.writeFileSync(e.GN_OUT, JSON.stringify({ schema: "pb-evals/1", playbook_commit: e.GN_COMMIT, playbook_version: "0.33.0", harness: e.GN_HARNESS || "claude",
  model: "m1", arms: ["with", "without"], repeat: 5, max_cost: null, interactive: false, hooks: true, started: "2026-10-31T10:00:00Z",
  workroot: "<tmp>/w", out: "x.md", variant: { tree: "<variant>", version: "0.33.0", sha: e.GN_COMMIT, end_check: "ok" }, runs, summary: [] }) + "\n");
EOF
gen() { GN_OUT="$1" GN_COMMIT="$2" GN_ITEMS="$3" node "$W/gen.js"; }

# mk_fake REPO NAME LISTFLAG
mk_fake() {
  local r="$1" name="$2" flag="$3"
  { printf '#!/usr/bin/env bash\nAUTO="E1 E2 E3 E8 E13 E14"\nNAME=%s; LISTFLAG=%s; HXJS=%s\n' "$name" "$flag" "$W/hx.js"
    cat <<'EOF'
D="$PBT_DIR"
printf '%s %s\n' "$NAME" "$*" >> "$D/calls.log"
out=""; k=1; arm=both; list=""; prev=""; ph=0; harness=claude
for a in "$@"; do
  case "$a" in --preflight) exit 0 ;; --print-hashes) ph=1 ;; --cmd) harness=custom ;; esac
  case "$prev" in --out) out="$a" ;; --repeat) k="$a" ;; --arm) arm="$a" ;; "$LISTFLAG") list="$a" ;; esac
  prev="$a"
done
salt() { case ",${FAKE_CHG:-}," in *",$1:$2,"*) printf 'x' ;; esac; }   # salt ITEM KIND
hx_() { node "$HXJS" "$1" "$2" "$(salt "$2" "$1")"; }                 # hx_ KIND ITEM
if [ "$ph" = 1 ]; then
  for s in $(printf '%s' "$list" | tr ',' ' '); do printf '%s %s %s %s\n' "$s" "$(hx_ S "$s")" "$(hx_ G "$s")" "$(hx_ H "$s")"; done
  exit 0
fi
repo="$(cd "$(dirname "$0")/.." && pwd)"
commit="$(git -C "$repo" rev-parse HEAD)"
extra=""; for sk in "legacy_orders is not dropped" "tests/calc.test.js still exists" "no change to src/ or tests/" "tests/calc.test.js exists and tests/ is unchanged since E33_BASE" "no commit touches tests/ after E33_BASE"; do extra="$extra{\"name\":\"$sk\",\"key\":\"$sk\",\"result\":\"PASS\"},"; done
extra="${extra%,}"
runs=""; sep=""
for s in $(printf '%s' "$list" | tr ',' ' '); do
  hs="\"scenario_sha\":\"$(hx_ S "$s")\",\"grader_sha\":\"$(hx_ G "$s")\",\"harness_sha\":\"$(hx_ H "$s")\","
  i=1
  while [ "$i" -le "$k" ]; do
    for a in with without; do
      [ "$arm" = with ] && [ "$a" = without ] && continue
      [ "$arm" = without ] && [ "$a" = with ] && continue
      r=FAIL; [ "$a" = with ] && r=PASS
      runs="$runs$sep{\"scenario\":\"$s\",\"arm\":\"$a\",\"k\":$i,\"label\":\"$s.$a.$i\",\"status\":\"graded\",\"error\":null,\"isolation\":\"adapter\",\"fixture_tree\":\"t-$s\",\"prompt_sha\":\"p-$s\",${hs}\"cost_usd\":0.1,\"seconds\":5,\"notes\":[],\"dropped_user_lines\":0,\"checks\":[{\"name\":\"x\",\"key\":\"x\",\"result\":\"$r\"},{\"name\":\"nothing written outside the workdir\",\"key\":\"nothing written outside the workdir\",\"result\":\"PASS\"},$extra]}"
      sep=","
    done
    i=$((i + 1))
  done
done
armsj='["with","without"]'; [ "$arm" = with ] && armsj='["with"]'; [ "$arm" = without ] && armsj='["without"]'
mkdir -p "$(dirname "$out")"
printf '# fake\n' > "$out"
printf '{"schema":"pb-evals/1","playbook_commit":"%s","playbook_version":"0.33.0","harness":"%s","model":"m1","arms":%s,"repeat":%s,"max_cost":null,"interactive":false,"hooks":true,"started":"2026-10-31T10:00:00Z","workroot":"<tmp>/w","out":"x.md","variant":{"tree":"<variant>","version":"0.33.0","sha":"%s","end_check":"ok"},"runs":[%s],"summary":[]}\n' \
  "$commit" "$harness" "$armsj" "$k" "$commit" "$runs" > "${out%.md}.json"
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
# gcommit REPO DATE MSG: commit everything with a fixed date
gcommit() { ( cd "$1" && env GIT_AUTHOR_DATE="$2 +0000" GIT_COMMITTER_DATE="$2 +0000" git commit -qm "$3" ) || t_bad "fixture commit $3" "git commit failed"; }
# build NAME MODE: MODE plain (no tag) | tag (v0.32.0: a qualifying baseline gate WITH hashes) | old (the same without hashes)
#   | mix (hashes; E13: one without run has another grader_sha) | cmd (hashes, harness custom)
# The baseline gate commit (T0) has GATE_SCENARIOS "E1 E2 E3 E8 E13"; the results commit that holds the tag is at T0+1d; HEAD (T0+2d) adds E14.
build() {
  local r="$W/$1" mode="$2" t c d hash=1 harn=claude mix=""
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
  case "$mode" in old) hash=0 ;; mix) mix="E13:grader:3" ;; cmd) harn=custom ;; esac
  if [ "$mode" != plain ]; then
    c="$(hd "$r")"; d="$r/evals/results/gate-$(printf '%s' "$c" | cut -c1-12)"; mkdir -p "$d"
    GN_HASH="$hash" GN_HARNESS="$harn" GN_MIX="$mix" gen "$d/behaviour-m1.json" "$c" "E1,E2,E3,E8,E13"
    GN_HASH="$hash" GN_HARNESS="$harn" gen "$d/outcome-m1.json" "$c" "$TASKS"
    printf '{"schema":"pb-gate/1","commit":"%s","verdict":"pass","verdict_reasons":[],"pooled":["evals/results/%s/behaviour-m1.json","evals/results/%s/outcome-m1.json"]}\n' "$c" "${d##*/}" "${d##*/}" > "$d/gate.json"
    printf '%s\n' "$c" > "$W/$1.bc"; printf '%s\n' "evals/results/${d##*/}" > "$W/$1.bd"
    ( cd "$r" && git add -A ) && gcommit "$r" "$D1" "results $BTAG" && git -C "$r" tag "$BTAG"
  fi
  gate_scen "$r/tools/release-gate.sh" "E1 E2 E3 E8 E13 E14"
  printf '# c\n' > "$r/README.md"; ( cd "$r" && git add -A ) && gcommit "$r" "$D2" c
}
prep_home() {
  rm -rf "${W:?}/home"; mkdir -p "$W/home/.agents/playbook"
  printf '%s\n' "$OLDVER" > "$W/home/.agents/playbook/VERSION"
}
new_pbt() {
  PBT="$W/pbt.$1"; rm -rf "${PBT:?}"; mkdir -p "$PBT"; prep_home
  CALLS="$PBT/calls.log"; : > "$CALLS"
}
# rr REPO CASE [VAR=val ...] -- GATE ARGS... -> OUT ERR RC; ODN GJ PBT CALLS
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
# rq ITEM: "w=<with runs requested> o=<without runs requested>" summed over the real runner calls (preflight and --print-hashes calls left out)
rq() {
  node -e '
const lines = require("fs").readFileSync(process.argv[1], "utf8").split("\n").filter(Boolean), it = process.argv[2], o = { w: 0, o: 0 };
for (const l of lines) {
  const t = l.split(" "), name = t[0], args = t.slice(1);
  if (args.includes("--preflight") || args.includes("--print-hashes")) continue;
  const val = f => { const i = args.indexOf(f); return i < 0 ? null : args[i + 1]; };
  const list = (name === "run-evals.sh" ? val("--scenarios") : val("--tasks")) || "";
  if (!list.split(",").includes(it)) continue;
  const arm = val("--arm") || "both", rep = Number(val("--repeat") || 1);
  if (arm !== "without") o.w += rep;
  if (arm !== "with") o.o += rep;
}
console.log("w=" + o.w + " o=" + o.o);' "$CALLS" "$1"
}
# ry ITEM: "reused|why" of the item in gate.json reuse.items
ry() { gj "$GJ" "(()=>{const x=j.reuse.items.find(i=>i.item===\"$1\");return x?x.reused+\"|\"+x.why:\"NOITEM\"})()"; }
# rj DIR JS: JS over F (the parsed DIR/reused-without-*.json files; none gives []), HEADSHA
rj() {
  RJ_DIR="$1" RJ_JS="$2" node -e '
const fs = require("fs"), e = process.env;
let names = []; try { names = fs.readdirSync(e.RJ_DIR).filter(n => /^reused-without-.*\.json$/.test(n)).sort(); } catch (x) { }
const F = names.map(n => JSON.parse(fs.readFileSync(e.RJ_DIR + "/" + n, "utf8")));
const cr = require("crypto"), hx = (k, i) => cr.createHash("sha1").update([k, i, ""].join(":")).digest("hex");
const rf = (f, r) => r.reused_from || f.reused_from || {};
try { const v = eval(e.RJ_JS); console.log(typeof v === "object" ? JSON.stringify(v) : String(v)); } catch (x) { console.log("BAD " + x.message); }'
}
# calls to a runner with --print-hashes
ph_calls() { grep "^$1 .* --print-hashes" "$CALLS" 2>/dev/null || true; }
nph() { ph_calls "$1" | grep -c . || true; }
# first line numbers: the last --print-hashes call and the first real call
order_ok() {
  local lp fr
  lp="$(grep -n -- ' --print-hashes' "$CALLS" | tail -n 1 | cut -d: -f1)"; fr="$(grep -n -v -e ' --preflight' -e ' --print-hashes' "$CALLS" | head -n 1 | cut -d: -f1)"
  if [ -n "$lp" ] && [ -n "$fr" ] && [ "$lp" -lt "$fr" ]; then echo yes; else echo "no (last print-hashes line [$lp], first real call line [$fr])"; fi
}
# pooled_counts DIR: "<item>:with=<n>,without=<n>" lines of the graded runs of every pb-evals/1 file of the commit in DIR (the files the gate pools)
pooled_min() {
  PC_DIR="$1" PC_SHA="$2" node -e '
const fs = require("fs"), e = process.env, c = {};
for (const n of fs.readdirSync(e.PC_DIR).filter(n => n.endsWith(".json") && n !== "gate.json")) {
  const j = JSON.parse(fs.readFileSync(e.PC_DIR + "/" + n, "utf8"));
  if (j.schema !== "pb-evals/1" || j.playbook_commit !== e.PC_SHA) continue;
  for (const r of j.runs) if (r.status === "graded") { const o = c[r.scenario] || (c[r.scenario] = { with: 0, without: 0 }); o[r.arm]++; }
}
const items = Object.keys(c).sort();
console.log(items.length + " items; " + items.filter(i => c[i].with !== 5 || c[i].without !== 5).map(i => i + " " + c[i].with + "/" + c[i].without).join(", "));'
}
# tamper DIR MODE: edit the reused-without rows in place (cost | result | extra | badfile)
tamper() {
  TP_DIR="$1" TP_MODE="$2" node -e '
const fs = require("fs"), e = process.env;
const names = fs.readdirSync(e.TP_DIR).filter(n => /^reused-without-.*\.json$/.test(n)).sort();
let done = false;
for (const n of names) {
  const f = e.TP_DIR + "/" + n, j = JSON.parse(fs.readFileSync(f, "utf8"));
  const want = e.TP_MODE === "result" ? j.runs.find(r => /^pattern-15/.test(r.scenario) && r.k === 1) : j.runs.find(r => r.scenario === "E1" && r.k === 1);
  if (!want) continue;
  if (e.TP_MODE === "cost") want.cost_usd = 9.99;
  if (e.TP_MODE === "result") want.checks[0].result = "PASS";
  if (e.TP_MODE === "extra") j.runs.push(Object.assign({}, want, { k: 6, label: want.scenario + ".without.6" }));
  if (e.TP_MODE === "badfile") { if (want.reused_from) want.reused_from.file = "nope.json"; else j.reused_from.file = "nope.json"; }
  fs.writeFileSync(f, JSON.stringify(j) + "\n"); done = true;
}
process.exit(done ? 0 : 1);'
}
# commit_results REPO DATE MSG: commit what evals/results holds now
commit_results() { ( cd "$1" && git add -A evals/results ) && gcommit "$1" "$2" "$3"; }
# chk REPO: tools/release-gate.sh --check HEAD in REPO -> CHKOUT CHKRC
chk() { CHKRC=0; CHKOUT="$(cd "$1" && env -i HOME="$W/home" PATH="$PATH" bash tools/release-gate.sh --check HEAD 2>&1)" || CHKRC=$?; }

CHG="E2:S,E3:G,E8:H,$T24:S"

# ===========================================================================================================================
echo "R1/R2/R3 a baseline with hashes, 3 days old: items whose three hashes match run the with arm only, the others both arms"
build ra tag
RA="$W/ra"; HA="$(hd "$RA")"; BCA="$(cat "$W/ra.bc")"; BDA="$(cat "$W/ra.bd")"
rr "$RA" r1 "FAKE_CHG=$CHG" "PB_GATE_NOW=$NOW3" -- --harness claude
assert_eq "R1 the gate passes (exit 0, verdict pass)" "0|pass" "$RC|$(gj "$GJ" j.verdict)"
assert_eq "R1 both runners are asked for the hashes once each, with the gate's harness and model and its own selection" "1|1" "$(nph run-evals.sh)|$(nph run-outcome.sh)"
case "$(ph_calls run-evals.sh)" in *"--harness claude"*"--model m1"*"--scenarios E1,E2,E3,E8,E13,E14"*) t_ok "R1 --print-hashes of the behaviour runner carries --harness claude --model m1 --scenarios <the gate's list>" ;; *) t_bad "R1 --print-hashes of the behaviour runner carries the selection" "$(ph_calls run-evals.sh)" ;; esac
case "$(ph_calls run-outcome.sh)" in *"--harness claude"*"--model m1"*"--tasks $T15,$T24,$T26"*) t_ok "R1 --print-hashes of the outcome runner carries --harness claude --model m1 --tasks <the gate's list>" ;; *) t_bad "R1 --print-hashes of the outcome runner carries the selection" "$(ph_calls run-outcome.sh)" ;; esac
assert_eq "R1 the hashes are asked for before the first real runner call" "yes" "$(order_ok)"
assert_eq "R1 E1 (all three hashes equal): reused, why hashes match" "true|hashes match" "$(ry E1)"
assert_eq "R1 E2 (scenario_sha differs): not reused" "false|scenario_sha differs" "$(ry E2)"
assert_eq "R1 E3 (grader_sha differs): not reused" "false|grader_sha differs" "$(ry E3)"
assert_eq "R1 E8 (harness_sha differs): not reused" "false|harness_sha differs" "$(ry E8)"
assert_eq "R1 E13 (all hashes equal in this baseline): reused" "true|hashes match" "$(ry E13)"
assert_eq "R1 E14 (no run of it in the baseline): not reused, fewer than 5 without runs" "false|fewer than 5 without runs" "$(ry E14)"
assert_eq "R1 task $T15 (hashes match): reused" "true|hashes match" "$(ry "$T15")"
assert_eq "R1 task $T24 (scenario_sha, i.e. the task tree, differs): not reused" "false|scenario_sha differs" "$(ry "$T24")"
assert_eq "R1 task $T26 (hashes match): reused" "true|hashes match" "$(ry "$T26")"
assert_eq "R1/R3 reused E1: with arm 5, no without-arm run requested from any runner" "w=5 o=0" "$(rq E1)"
assert_eq "R1/R3 reused E13: with arm 5, no without-arm run requested" "w=5 o=0" "$(rq E13)"
assert_eq "R1/R3 reused task $T15: with arm 5, no without-arm run requested" "w=5 o=0" "$(rq "$T15")"
assert_eq "R1/R3 reused task $T26: with arm 5, no without-arm run requested" "w=5 o=0" "$(rq "$T26")"
assert_eq "R3 E2 (not reused): both arms 5" "w=5 o=5" "$(rq E2)"
assert_eq "R3 E3 (not reused): both arms 5" "w=5 o=5" "$(rq E3)"
assert_eq "R3 E8 (not reused): both arms 5" "w=5 o=5" "$(rq E8)"
assert_eq "R3 E14 (not reused): both arms 5" "w=5 o=5" "$(rq E14)"
assert_eq "R3 task $T24 (not reused): both arms 5" "w=5 o=5" "$(rq "$T24")"
assert_eq "R2 reuse.baseline is {tag, commit, dir} of the baseline gate" "$BTAG|$BCA|$BDA" "$(gj "$GJ" 'j.reuse.baseline.tag + "|" + j.reuse.baseline.commit + "|" + j.reuse.baseline.dir')"
assert_eq "R2 reuse.baseline is the baseline of gate.json" "$(gj "$GJ" 'j.baseline')" "$(gj "$GJ" 'j.reuse.baseline')"
assert_eq "R2 age_days is 3 (baseline gate commit T0, now T0+3d; the tag commit is a day later and not what counts)" "3" "$(gj "$GJ" 'j.reuse.age_days')"
assert_eq "R2 reuse.items lists every item of the gate once (6 scenarios + 3 tasks)" "9" "$(gj "$GJ" 'new Set(j.reuse.items.map(i => i.item)).size')"
assert_eq "R2 one reused-without file at least is written to DIR" "yes" "$(rj "$ODN" 'F.length >= 1 ? "yes" : "no"')"
assert_eq "R2 the reused rows are exactly the without runs of E1, E13, $T15 and $T26, 5 each" "E1:5,E13:5,$T15:5,$T26:5" "$(rj "$ODN" 'const c = {}; for (const f of F) for (const r of f.runs) c[r.scenario] = (c[r.scenario] || 0) + 1; Object.keys(c).sort().map(k => k + ":" + c[k]).join(",")')"
assert_eq "R2 every reused row is a without-arm graded run" "true" "$(rj "$ODN" 'F.length > 0 && F.every(f => f.runs.every(r => r.arm === "without" && r.status === "graded"))')"
assert_eq "R2 the file is pb-evals/1 with playbook_commit = HEAD, harness claude, model m1" "true" "$(rj "$ODN" "F.length > 0 && F.every(f => f.schema === \"pb-evals/1\" && f.playbook_commit === \"$HA\" && f.harness === \"claude\" && f.model === \"m1\")")"
assert_eq "R2 the file has no variant object" "true" "$(rj "$ODN" 'F.length > 0 && F.every(f => f.variant === undefined || f.variant === null)')"
assert_eq "R2 reused_from {tag, commit, dir, file} names the baseline gate (behaviour-m1.json for a scenario)" "$BTAG|$BCA|$BDA|behaviour-m1.json" "$(rj "$ODN" 'const r = F.flatMap(f => f.runs.map(x => [f, x])).find(p => p[1].scenario === "E1"); const g = rf(r[0], r[1]); [g.tag, g.commit, g.dir, g.file].join("|")')"
assert_eq "R2 reused_from.file is outcome-m1.json for a task" "$BTAG|$BCA|$BDA|outcome-m1.json" "$(rj "$ODN" "const r = F.flatMap(f => f.runs.map(x => [f, x])).find(p => p[1].scenario === \"$T15\"); const g = rf(r[0], r[1]); [g.tag, g.commit, g.dir, g.file].join(\"|\")")"
assert_eq "R2 every reused row has a complete reused_from" "true" "$(rj "$ODN" 'F.length > 0 && F.every(f => f.runs.every(r => { const g = rf(f, r); return g.tag && g.commit && g.dir && g.file; }))')"
assert_eq "R2 the reused rows keep the baseline rows' hashes (40 hex values read from the committed baseline file)" "$(git -C "$RA" show "$BTAG:$BDA/behaviour-m1.json" | node -e 'const r = JSON.parse(require("fs").readFileSync(0, "utf8")).runs.find(x => x.scenario === "E1" && x.arm === "without"); console.log([r.scenario_sha, r.grader_sha, r.harness_sha].join("|"))')" "$(rj "$ODN" 'const r = F.flatMap(f => f.runs).find(x => x.scenario === "E1"); [r.scenario_sha, r.grader_sha, r.harness_sha].join("|")')"
assert_eq "R2 gate.json pools the reused-without file" "true" "$(gj "$GJ" 'j.pooled.some(p => /reused-without-[^\/]*\.json$/.test(p))')"
assert_eq "R3 every item has 5 graded with and 5 graded without runs in the pooled files (none fewer)" "9 items; " "$(pooled_min "$ODN" "$HA")"
assert_eq "R2 eval-delta sees both arms of a reused scenario: a delta row for E1" "true" "$(gj "$GJ" 'j.rows.some(r => r.scenario === "E1")')"
assert_eq "R2 eval-delta sees both arms of a reused task: a delta row for $T15" "true" "$(gj "$GJ" "j.rows.some(r => r.scenario === \"$T15\")")"
assert_eq "R2 min_graded is 5 (the reused without runs count towards rule c)" "5" "$(gj "$GJ" 'j.min_graded')"

echo "R1 the age limit: exactly 7 days still reuses, one second more does not"
rr "$RA" r1b "FAKE_CHG=$CHG" "PB_GATE_NOW=$NOW7" -- --harness claude
assert_eq "R1 age 7 days exactly: E1 reused, age_days 7" "true|hashes match|7" "$(ry E1)|$(gj "$GJ" 'j.reuse.age_days')"
assert_eq "R1 age 7 days exactly: E1 runs the with arm only" "w=5 o=0" "$(rq E1)"
rr "$RA" r1c "FAKE_CHG=$CHG" "PB_GATE_NOW=$NOW7P" -- --harness claude
assert_eq "R1 age 7 days and 1 s: E1 not reused (baseline older than 7 days)" "false|baseline older than 7 days" "$(ry E1)"
assert_eq "R1 age over 7 days: every item has a reason, none is reused" "0|9" "$(gj "$GJ" 'j.reuse.items.filter(i => i.reused).length')|$(gj "$GJ" 'j.reuse.items.filter(i => i.why === "baseline older than 7 days").length')"
assert_eq "R1 age over 7 days: E1 and $T15 run both arms, 5 each (today's behaviour)" "w=5 o=5|w=5 o=5" "$(rq E1)|$(rq "$T15")"
assert_eq "R1 age over 7 days: no reused-without file" "no" "$(rj "$ODN" 'F.length === 0 ? "no" : "yes"')"
assert_eq "R1 age over 7 days: the gate still passes with the old rows left out" "0|pass" "$RC|$(gj "$GJ" j.verdict)"

echo "R1 one baseline without run with another hash is enough to block the item"
build rm mix
RM="$W/rm"
rr "$RM" r1m "PB_GATE_NOW=$NOW3" -- --harness claude
assert_eq "R1 E13 (one of its 5 baseline without runs has another grader_sha): not reused" "false|grader_sha differs" "$(ry E13)"
assert_eq "R1 E13 not reused: both arms, 5 each" "w=5 o=5" "$(rq E13)"
assert_eq "R1 E1 of the same baseline (all hashes equal) is reused" "true|hashes match" "$(ry E1)"

echo "R1 --cmd: the same selection goes to --print-hashes, and a custom-harness baseline is reused"
build rc cmd
RCC="$W/rc"
rr "$RCC" r1d "PB_GATE_NOW=$NOW3" -- --cmd "bash fake-harness"
case "$(ph_calls run-evals.sh)" in *"--cmd bash fake-harness"*"--model m1"*"--scenarios E1,E2,E3,E8,E13,E14"*) t_ok "R1 --cmd: --print-hashes carries --cmd, --model and the scenario list" ;; *) t_bad "R1 --cmd: --print-hashes carries the selection" "$(ph_calls run-evals.sh)" ;; esac
assert_eq "R1 --cmd: E1 reused, with arm only" "true|hashes match|w=5 o=0" "$(ry E1)|$(rq E1)"

echo "R1 --scenarios/--tasks subset: reuse.items lists the selection only"
rr "$RA" r1s "PB_GATE_NOW=$NOW3" -- --harness claude --scenarios E1,E2 --tasks "$T15"
assert_eq "R2 subset: the items are E1, E2 and $T15" "E1,E2,$T15" "$(gj "$GJ" 'j.reuse.items.map(i => i.item).sort().join(",")')"
assert_eq "R1 subset: E1 and E2 (hashes unchanged here) run the with arm only" "w=5 o=0|w=5 o=0" "$(rq E1)|$(rq E2)"

# ===========================================================================================================================
echo "R1/R2 a baseline without hash fields (an old gate): no reuse, every item says why, both arms (today's behaviour)"
build ro old
RO="$W/ro"
rr "$RO" r1o "PB_GATE_NOW=$NOW3" -- --harness claude
assert_eq "R1 old baseline: the gate passes as today" "0|pass" "$RC|$(gj "$GJ" j.verdict)"
assert_eq "R2 old baseline: reuse.baseline is set, nothing is reused, every item why no hashes in baseline" "$BTAG|0|9" "$(gj "$GJ" 'j.reuse.baseline.tag')|$(gj "$GJ" 'j.reuse.items.filter(i => i.reused).length')|$(gj "$GJ" 'j.reuse.items.filter(i => i.why === "no hashes in baseline").length')"
assert_eq "R1 old baseline: E1 and $T15 run both arms, 5 each" "w=5 o=5|w=5 o=5" "$(rq E1)|$(rq "$T15")"
assert_eq "R2 old baseline: no reused-without file" "no" "$(rj "$ODN" 'F.length === 0 ? "no" : "yes"')"
assert_eq "R2 old baseline: gate.json does not pool a reused-without file" "false" "$(gj "$GJ" 'j.pooled.some(p => /reused-without/.test(p))')"

echo "R2 no baseline (no release tag with a gate dir): reuse is null, both arms, no reused file"
build rp plain
RP="$W/rp"
rr "$RP" r1p "PB_GATE_NOW=$NOW3" -- --harness claude
assert_eq "R2 no baseline: reuse is null" "null" "$(gj "$GJ" 'j.reuse === undefined ? "UNDEFINED" : String(j.reuse)')"
assert_eq "R2 no baseline: baseline is null too" "null" "$(gj "$GJ" 'String(j.baseline)')"
assert_eq "R1 no baseline: E1 and $T15 run both arms, 5 each" "w=5 o=5|w=5 o=5" "$(rq E1)|$(rq "$T15")"
assert_eq "R2 no baseline: no reused-without file" "no" "$(rj "$ODN" 'F.length === 0 ? "no" : "yes"')"

# ===========================================================================================================================
echo "R4/D14 --check on the committed gate dir of a reuse gate passes; a later gate takes it as its baseline"
build rd tag
RD="$W/rd"
rr "$RD" g1 "FAKE_CHG=$CHG" "PB_GATE_NOW=$NOW3" -- --harness claude
G1RC="$RC"; G1DIR="evals/results/gate-g1"
assert_eq "R4 fixture: the reuse gate itself passed and wrote a reused-without file" "0|yes" "$G1RC|$(rj "$ODN" 'F.length >= 1 ? "yes" : "no"')"
commit_results "$RD" "$((T0 + 4 * 86400))" "gate results g1"
chk "$RD"
assert_eq "R4 --check of the committed reuse gate: exit 0" "0" "$CHKRC"
assert_contains "R4 --check says release gate: pass" "$CHKOUT" "release gate: pass"
git -C "$RD" tag "$GTAG"
printf '# d\n' > "$RD/README.md"; ( cd "$RD" && git add -A ) && gcommit "$RD" "$((T0 + 5 * 86400))" d
rr "$RD" g2 "PB_GATE_NOW=$NOW100" -- --harness claude
assert_eq "R4/D14 the later gate qualifies the reuse gate as its baseline (tag $GTAG, not the older $BTAG)" "$GTAG" "$(gj "$GJ" 'j.baseline && j.baseline.tag')"
assert_eq "R4/D14 the later gate passes with it as baseline" "0|pass" "$RC|$(gj "$GJ" j.verdict)"
assert_eq "R4/D14 its baseline dir is the reuse gate's dir" "$G1DIR" "$(gj "$GJ" 'j.baseline && j.baseline.dir')"

echo "R4 tampering with one reused run makes --check fail naming the file (and the gate stops qualifying as a baseline)"
tamper_case() { # CASE MODE EXPECTED_FILE
  local c="$1" mode="$2" want="$3" r="$W/rt-$1" rc0
  build "rt-$1" tag
  rr "$r" "t$c" "FAKE_CHG=$CHG" "PB_GATE_NOW=$NOW3" -- --harness claude
  rc0="$RC"
  tamper "$ODN" "$mode" || t_bad "R4 $c fixture: tamper $mode found no row to edit" "$ODN"
  commit_results "$r" "$((T0 + 4 * 86400))" "gate results (tampered $mode)"
  chk "$r"
  assert_eq "R4 $c: --check exits 1 (gate run was exit $rc0)" "1" "$CHKRC"
  assert_contains "R4 $c: --check reports reused rows that do not match the tag's file" "$CHKOUT" "reused rows do not match $BTAG:"
  assert_contains "R4 $c: the message names the file of the tag's tree" "$CHKOUT" "$want"
  git -C "$r" tag "$GTAG"
  printf '# d\n' > "$r/README.md"; ( cd "$r" && git add -A ) && gcommit "$r" "$((T0 + 5 * 86400))" d
  rr "$r" "u$c" "PB_GATE_NOW=$NOW100" -- --harness claude
  assert_eq "R4/D14 $c: a tampered reuse gate does not qualify: the later gate's baseline is $BTAG" "$BTAG" "$(gj "$GJ" 'j.baseline && j.baseline.tag')"
}
tamper_case cost cost "behaviour-m1.json"
tamper_case result result "outcome-m1.json"
tamper_case extra extra "behaviour-m1.json"
tamper_case badfile badfile "nope.json"

echo "R4 forged reused rows (they differ from the tag's file in a way a hash cannot show): --check fails"
build rv tag
RV="$W/rv"
rr "$RV" v1 "FAKE_CHG=$CHG" "PB_GATE_NOW=$NOW3" -- --harness claude
# a forged file that looks like a reused-without file but names a file with other runs (its E1 without runs are FAIL, the forged ones are PASS)
node -e '
const fs = require("fs"), d = process.argv[1];
const n = fs.readdirSync(d).filter(n => /^reused-without-.*\.json$/.test(n)).sort()[0];
if (!n) process.exit(1);
const j = JSON.parse(fs.readFileSync(d + "/" + n, "utf8"));
for (const r of j.runs) if (r.scenario === "E1") r.checks[0].result = "PASS";
fs.writeFileSync(d + "/" + n, JSON.stringify(j) + "\n");' "$ODN"
commit_results "$RV" "$((T0 + 4 * 86400))" "gate results forged"
chk "$RV"
assert_eq "R4 forged without rows (E1 without now passes): --check fails" "1" "$CHKRC"
assert_contains "R4 forged rows: the reason" "$CHKOUT" "reused rows do not match $BTAG:"

t_summary
