#!/usr/bin/env bash
# Tests for v0.38 G2a (docs/v0.38-g2-spec.md R1 to R3, R4', AC1 to AC8): tools/release-gate.sh checks, in a real run, that HEAD is the
# head of origin/<branch> (git ls-remote; exit 3 when it differs, the branch is not on origin or origin cannot be read; no origin or a
# detached HEAD skips it; --skip-head-check bypasses it) and has a free mode, --verify, that runs the refusals of a real run that cost
# nothing and stops before the worktree. Fixture repos hold the real tools/release-gate.sh, tools/eval-delta.sh, a fake install.sh and
# RECORDING fake runners (the fixtures of tests/test-release-gate-budget.sh: every runner call, --preflight and --print-hashes included,
# goes to $PBT_DIR/calls.log); each repo gets a bare ORIGIN (<repo>.git) that the helpers move (match, ahead, behind, branch missing,
# unreadable). `gh` is the fake of tests/release-gate-fixture.sh (its call log must stay empty when the head check refuses). A wrapping
# `git` (a script in its own directory, put first on PATH for the runs that need it) records every call and the GIT_TERMINAL_PROMPT it saw.
# Never calls a model. Needs node and git.
# AC9 is the setup of six fixture places of tests/test-release-gate.sh and -b.sh (see their diff); this suite does not test it.
# Runtime estimate for tests/shard-weights: about 300 seconds on the Windows runner (an estimate, not a measurement: about 60 gate invocations, most of them
# refusals that start no runner, and 5 full real runs with fake runners).
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

# ===========================================================================================================================
# ---- fixture: origins, a wrapping git, comparison helpers ------------------------------------------------------------------
ncalls() { grep -c . "$CALLS" 2>/dev/null || true; }
# tree DIR: every path below DIR except .git (a listing, to compare before and after a refusal)
tree() { ( cd "$1" && find . -path ./.git -prune -o -print | LC_ALL=C sort ); }
# origin helpers: REPO's bare origin is "$REPO.git"; BRN is the branch name of the repos (the same for all of them)
brn() { git -C "$1" symbolic-ref --short -q HEAD; }
orig() { git --git-dir="$1.git" rev-parse -q --verify "refs/heads/$(brn "$1")"; }
mkorigin() { git init -q --bare "$1.git" && git -C "$1" remote add origin "$1.git" && git -C "$1" push -q origin "HEAD:refs/heads/$(brn "$1")" || t_bad "fixture origin of $1" "git push failed"; }
o_url() { git -C "$1" remote set-url origin "$1.git"; }                     # the readable URL again
o_match() { o_url "$1"; git -C "$1" push -q -f origin "HEAD:refs/heads/$(brn "$1")" 2>/dev/null; }   # origin/<branch> is HEAD
o_behind() { o_url "$1"; git --git-dir="$1.git" update-ref "refs/heads/$(brn "$1")" "$(git -C "$1" rev-parse HEAD~1)"; }   # origin has HEAD's parent
o_ahead() { # origin has a commit HEAD does not have (on top of HEAD)
  local c; o_url "$1"
  c="$(git -C "$1" commit-tree 'HEAD^{tree}' -p HEAD -m other)" && git -C "$1" push -q -f origin "$c:refs/heads/$(brn "$1")" 2>/dev/null
}
o_gone() { o_url "$1"; git --git-dir="$1.git" update-ref -d "refs/heads/$(brn "$1")"; }   # the branch is not on origin
o_unreadable() { git -C "$1" remote set-url origin "$W/nowhere/x.git"; }   # a path that does not exist
# the wrapping git: records "GTP=<GIT_TERMINAL_PROMPT as the call saw it>|<args>" in $GITLOG, then runs the real git
GW="$W/gitwrap"; mkdir -p "$GW"
export GW_REAL_GIT="$(command -v git)"
cat > "$GW/git" <<'EOF'
#!/usr/bin/env bash
printf 'GTP=%s|%s\n' "${GIT_TERMINAL_PROMPT-unset}" "$*" >> "${GITLOG:-/dev/null}"
exec "$GW_REAL_GIT" "$@"
EOF
chmod 755 "$GW/git"
GITLOG="$W/git.log"
WRAP=("PATH=$GW:$PATH" "GITLOG=$GITLOG" "GIT_TERMINAL_PROMPT=1")   # rr envs: the wrapper first on PATH; the gate must set the prompt off itself
lsr_calls() { grep -c 'ls-remote' "$GITLOG" 2>/dev/null || true; }
nst() { sed 's#[0-9]\{8\}T[0-9]\{6\}Z-[0-9]*#STAMP#g'; }
runs_but_hashes() { grep -v -- '--print-hashes' "$CALLS" | grep -c . || true; }   # runner calls other than --print-hashes (preflight included)
real_calls() { grep -v -- '--preflight\|--print-hashes' "$CALLS" | grep -c . || true; }   # the real runner calls (no preflight, no --print-hashes)
nworktrees() { git -C "$1" worktree list | wc -l | tr -d ' '; }
tmp_left() { ls -A "$W/tmp" | wc -l | tr -d ' '; }
gh_red() { rgf_gh_runs "1|test (ubuntu-latest)|completed|failure"; rgf_gh_job 1 "test (ubuntu-latest)" failure "1|Set up job|success" "2|Tests|failure"; }
cnt() { printf '%s\n' "$1" | grep -c -- "$2" || true; }

build ra tag; RA="$W/ra"
build rx broken; RX="$W/rx"
build rs tag; RS="$W/rs"
build rn tag; RN="$W/rn"
# RS: a replay tool that reports one changed log (error->ok), for the stale-replay refusal
cat > "$RS/tools/replay-graders.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\t%s\t%s\n' "$3/pattern-01.with.1.log" error 'error->ok'
exit 1
EOF
chmod 755 "$RS/tools/replay-graders.sh"
( cd "$RS" && git add -A ) && gcommit "$RS" "$((D4 + 60))" "stub replay tool"
for r in "$RA" "$RX" "$RS"; do mkorigin "$r"; done      # RN has no origin on purpose
BRN="$(brn "$RA")"
LOC="$(hd "$RA")"; L12="$(printf '%s' "$LOC" | cut -c1-12)"
assert_eq "fixture: the repos are on a branch and RN has no origin" "yes|yes|no" "$([ -n "$BRN" ] && echo yes || echo no)|$([ "$(brn "$RN")" = "$BRN" ] && echo yes || echo no)|$(git -C "$RN" remote | grep -c origin | sed 's/^0$/no/')"
rgf_gh_green

# ===========================================================================================================================
echo "AC1 (R1): HEAD differs from origin/<branch>: exit 3 with the exact sentence (both 12-hex shas), nothing run, no gh call"
nothing_made() { # NAME REPO TREE_BEFORE: no runner, no gh call, no file, no worktree, nothing left in TMPDIR, no results dir
  assert_eq "$1: no runner was called (not even a preflight or --print-hashes)" "0" "$(ncalls)"
  assert_eq "$1: gh was not called" "0" "$(rgf_gh_ncalls)"
  assert_eq "$1: no file was made (tree before and after)" "$3" "$(tree "$2")"
  assert_eq "$1: no worktree" "1" "$(nworktrees "$2")"
  assert_eq "$1: nothing left in TMPDIR" "0" "$(tmp_left)"
  assert_no_path "$1: no results dir" "$ODN"
}
o_behind "$RA"; rgf_gh_green; T0_="$(tree "$RA")"
O12="$(orig "$RA" | cut -c1-12)"
assert_eq "fixture: origin has the parent of HEAD (two different 12-hex shas)" "yes" "$([ "$O12" != "$L12" ] && [ "${#O12}" = 12 ] && echo yes || echo no)"
rr "$RA" ac1-behind PB_GATE_NOW=$NOW100 -- --harness claude
assert_eq "AC1 origin behind HEAD: exit 3" "3" "$RC"
assert_contains "AC1 the exact sentence, HEAD first and origin's sha in brackets" "$ERR" "head check: HEAD $L12 is not the head of origin/$BRN ($O12); push or pull so they match (or pass --skip-head-check)"
assert_eq "AC1 stdout is empty" "" "$OUT"
nothing_made "AC1 behind" "$RA" "$T0_"
o_ahead "$RA"; O12="$(orig "$RA" | cut -c1-12)"
rr "$RA" ac1-ahead PB_GATE_NOW=$NOW100 -- --harness claude
assert_eq "AC1 origin ahead of HEAD (a commit HEAD lacks): exit 3" "3" "$RC"
assert_contains "AC1 the sentence names HEAD $L12 and origin's other sha $O12" "$ERR" "head check: HEAD $L12 is not the head of origin/$BRN ($O12); push or pull so they match (or pass --skip-head-check)"
nothing_made "AC1 ahead" "$RA" "$T0_"
# a branch name with a slash is compared as a whole (refs/heads/feat/head-1), and named whole in the sentence
git -C "$RA" checkout -q -b feat/head-1 && git -C "$RA" push -q -f origin HEAD:refs/heads/feat/head-1 && git --git-dir="$RA.git" update-ref refs/heads/feat/head-1 "$(git -C "$RA" rev-parse HEAD~1)"
rr "$RA" ac1-slash PB_GATE_NOW=$NOW100 -- --harness claude
assert_eq "AC1 a branch feat/head-1 whose origin copy is behind: exit 3" "3" "$RC"
assert_contains "AC1 the sentence names origin/feat/head-1" "$ERR" "is not the head of origin/feat/head-1 ($(git --git-dir="$RA.git" rev-parse refs/heads/feat/head-1 | cut -c1-12)); push or pull so they match"
git -C "$RA" push -q -f origin HEAD:refs/heads/feat/head-1
rgf_gh_clearlog
rr "$RA" ac3-slash PB_GATE_NOW=$NOW100 -- --harness claude --budget 10
assert_eq "AC3 feat/head-1 matching origin: the gate goes on past the head check (to the budget refusal, exit 3)" "3" "$RC"
assert_contains "AC3 feat/head-1: the budget refusal is what stopped it" "$ERR" "budget: refused"
assert_not_contains "AC3 feat/head-1 matching: no head check text" "$ERR" "head check"
git -C "$RA" checkout -q "$BRN"; git -C "$RA" branch -q -D feat/head-1
rgf_gh_green

echo "AC2 (R1): branch not on origin, and an origin that cannot be read: exit 3 with their sentences"
o_gone "$RA"; T0_="$(tree "$RA")"
rr "$RA" ac2-gone PB_GATE_NOW=$NOW100 -- --harness claude
assert_eq "AC2 branch not on origin: exit 3" "3" "$RC"
assert_contains "AC2 the exact sentence" "$ERR" "head check: branch $BRN is not on origin; push it first (or pass --skip-head-check)"
assert_eq "AC2 stdout is empty" "" "$OUT"
nothing_made "AC2 gone" "$RA" "$T0_"
o_unreadable "$RA"
rr "$RA" ac2-unreadable PB_GATE_NOW=$NOW100 -- --harness claude
assert_eq "AC2 origin path does not exist (ls-remote fails): exit 3" "3" "$RC"
assert_contains "AC2 the sentence starts" "$ERR" "head check: cannot read origin ("
assert_contains "AC2 the sentence ends with the way out" "$ERR" "); pass --skip-head-check to go on without it"
assert_not_contains "AC2 the short error is not empty" "$ERR" "cannot read origin ()"
assert_eq "AC2 the sentence is on one line" "1" "$(cnt "$ERR" 'head check: cannot read origin (.*); pass --skip-head-check to go on without it')"
assert_eq "AC2 stdout is empty" "" "$OUT"
nothing_made "AC2 unreadable" "$RA" "$T0_"
o_match "$RA"

echo "AC3 (R1): HEAD equal to origin/<branch>: silent and on to the next steps; no origin: silent; detached HEAD: one note"
rgf_gh_clearlog
rr "$RA" ac3-match PB_GATE_NOW=$NOW100 -- --harness claude
assert_eq "AC3 matching origin: the full run with fake runners goes through (exit 0)" "0" "$RC"
assert_not_contains "AC3 matching: no head check text on stderr" "$ERR" "head check"
assert_not_contains "AC3 matching: no detached or skip note on stderr" "$ERR" "head check was skipped"
assert_not_contains "AC3 matching: nothing about --skip-head-check on stderr" "$ERR" "skip-head-check"
assert_not_contains "AC3 matching: nothing about it on stdout" "$OUT" "head check"
assert_eq "AC3 matching: the later steps ran (gh was read once, both runners really ran, gate.json exists)" "1|2|yes" "$(rgf_gh_ncalls)|$(real_calls)|$([ -f "$GJ" ] && echo yes || echo no)"
rgf_gh_green
rr "$RN" ac3-noorigin PB_GATE_NOW=$NOW100 -- --harness claude --budget 10
assert_eq "AC3 no origin: the gate goes on to the budget refusal (exit 3)" "3" "$RC"
assert_contains "AC3 no origin: it is the budget refusal" "$ERR" "budget: refused"
assert_not_contains "AC3 no origin: no head check text" "$ERR" "head check"
assert_not_contains "AC3 no origin: no note about the head" "$ERR" "head check was skipped"
assert_eq "AC3 no origin: stderr has no 'note:' line at all" "0" "$(cnt "$ERR" '^note:')"
assert_eq "AC3 no origin: stdout is empty" "" "$OUT"
# detached HEAD in a repo that has an origin: here origin differs from HEAD, so a skip is told from a pass
o_behind "$RA"; git -C "$RA" checkout -q --detach
assert_eq "fixture: HEAD of RA is detached" "" "$(brn "$RA")"
rr "$RA" ac3-detached PB_GATE_NOW=$NOW100 -- --harness claude --budget 10
assert_eq "AC3 detached HEAD, origin differs: the gate goes on to the budget refusal (exit 3)" "3" "$RC"
assert_contains "AC3 detached: it is the budget refusal that stopped it" "$ERR" "budget: refused"
assert_contains "AC3 detached: the note, exactly" "$ERR" "note: detached HEAD: the head check was skipped"
assert_eq "AC3 detached: one line starts with 'note: detached HEAD'" "1" "$(cnt "$ERR" '^note: detached HEAD')"
assert_eq "AC3 detached: that is the only note line" "1" "$(cnt "$ERR" '^note:')"
assert_not_contains "AC3 detached: no refusal" "$ERR" "head check:"
git -C "$RA" checkout -q "$BRN"
rr "$RA" ac3-attached PB_GATE_NOW=$NOW100 -- --harness claude --budget 10
assert_eq "AC3 control: the same repo on its branch is refused (exit 3 with the head sentence)" "3|1" "$RC|$(cnt "$ERR" 'head check: HEAD ')"
o_match "$RA"

echo "AC4 (R2): --skip-head-check: no git ls-remote, one note, the run goes on; the other modes print nothing about it"
o_behind "$RA"; : > "$GITLOG"
rr "$RA" ac4-ctl PB_GATE_NOW=$NOW100 "${WRAP[@]}" -- --harness claude
assert_eq "AC4 control: without the flag the head check refuses (exit 3)" "3|1" "$RC|$(cnt "$ERR" 'head check: HEAD ')"
assert_eq "AC4 control: the head check called git ls-remote once, with GIT_TERMINAL_PROMPT=0 (the environment said 1)" "1|1" "$(lsr_calls)|$(grep 'ls-remote' "$GITLOG" | grep -c '^GTP=0|')"
assert_contains "AC4 control: ls-remote asks for the branch ref on origin" "$(grep 'ls-remote' "$GITLOG")" "ls-remote origin refs/heads/$BRN"
: > "$GITLOG"
rr "$RA" ac4-skip PB_GATE_NOW=$NOW100 "${WRAP[@]}" -- --harness claude --skip-head-check --budget 10
assert_eq "AC4 --skip-head-check on the AC1 case: the gate goes on to the budget refusal (exit 3)" "3" "$RC"
assert_contains "AC4 it is the budget refusal that stopped it" "$ERR" "budget: refused"
assert_eq "AC4 git ls-remote was not called" "0" "$(lsr_calls)"
assert_eq "AC4 the note is on stderr, once, exactly" "note: --skip-head-check: HEAD was not compared with origin" "$(printf '%s\n' "$ERR" | grep -- 'skip-head-check' || true)"
assert_not_contains "AC4 no head check refusal" "$ERR" "head check:"
assert_eq "AC4 stdout is empty" "" "$OUT"
o_unreadable "$RA"; : > "$GITLOG"
rr "$RA" ac4-unread PB_GATE_NOW=$NOW100 "${WRAP[@]}" -- --harness claude --skip-head-check --budget 10
assert_eq "AC4 --skip-head-check with an unreadable origin: goes on (budget refusal, exit 3)" "3|1" "$RC|$(cnt "$ERR" 'budget: refused')"
assert_eq "AC4 unreadable origin: ls-remote not called" "0" "$(lsr_calls)"
o_gone "$RA"
rr "$RA" ac4-gone PB_GATE_NOW=$NOW100 -- --harness claude --skip-head-check --budget 10
assert_eq "AC4 --skip-head-check with the branch missing on origin: goes on (budget refusal, exit 3)" "3|1" "$RC|$(cnt "$ERR" 'budget: refused')"
o_behind "$RA"
# the other modes: the flag is accepted, prints nothing and changes nothing
mkdir -p "$RA/evals/results/gate-ac4pool"
gen "$RA/evals/results/gate-ac4pool/behaviour-m1.json" "$(hd "$RA")" "E1,E2,E3,E8,E13,E14" 4
gen "$RA/evals/results/gate-ac4pool/outcome-m1.json" "$(hd "$RA")" "$TASKS" 8
modes_run() { # LABEL EXTRA...: dry-run, pool-only and --check, each without and with the extra word; results in M_<mode>_<0|1>_{RC,OUT,ERR}
  local x="$1" mode; shift
  rr "$RA" "m-dry" -- --harness claude --dry-run "$@"; M_dry_RC="$RC"; M_dry_OUT="$(printf '%s\n' "$OUT" | nst)"; M_dry_ERR="$ERR"
  rr "$RA" "ac4pool" -- --harness claude --pool-only "$@"; M_pool_RC="$RC"; M_pool_OUT="$(printf '%s\n' "$OUT" | nst)"; M_pool_ERR="$ERR"
  rr "$RA" "m-chk" -- --check HEAD "$@"; M_chk_RC="$RC"; M_chk_OUT="$(printf '%s\n' "$OUT" | nst)"; M_chk_ERR="$ERR"
}
modes_run base
B_dry="$M_dry_RC|$M_dry_OUT|$M_dry_ERR"; B_pool="$M_pool_RC|$M_pool_OUT|$M_pool_ERR"; B_chk="$M_chk_RC|$M_chk_OUT|$M_chk_ERR"
: > "$GITLOG"
modes_run skip --skip-head-check
assert_eq "AC4 --dry-run --skip-head-check: same exit, stdout and stderr as without the flag" "$B_dry" "$M_dry_RC|$M_dry_OUT|$M_dry_ERR"
assert_eq "AC4 --pool-only --skip-head-check: same exit, stdout and stderr as without the flag" "$B_pool" "$M_pool_RC|$M_pool_OUT|$M_pool_ERR"
assert_eq "AC4 --check --skip-head-check: same exit, stdout and stderr as without the flag" "$B_chk" "$M_chk_RC|$M_chk_OUT|$M_chk_ERR"
assert_eq "AC4 --dry-run --skip-head-check: exit 0, stderr empty" "0|" "$M_dry_RC|$M_dry_ERR"
assert_not_contains "AC4 --pool-only --skip-head-check: the flag is accepted and silent" "$M_pool_ERR$M_pool_OUT" "skip-head-check"
assert_not_contains "AC4 --check --skip-head-check: the flag is accepted and silent" "$M_chk_ERR$M_chk_OUT" "skip-head-check"
assert_not_contains "AC4 --check --skip-head-check: not an unknown option" "$M_chk_ERR$M_chk_OUT" "unknown option"
assert_not_contains "AC4 --pool-only --skip-head-check: not an unknown option" "$M_pool_ERR$M_pool_OUT" "unknown option"
assert_not_contains "AC4 --dry-run --skip-head-check: not an unknown option" "$M_dry_ERR$M_dry_OUT" "unknown option"
o_match "$RA"

echo "AC5 (R1, R2): --dry-run, --pool-only and --check never run the head check (a mismatching or unreadable origin changes nothing)"
o_behind "$RA"; : > "$GITLOG"
modes_run mismatch
MM_dry="$M_dry_RC|$M_dry_OUT"; MM_pool="$M_pool_RC|$M_pool_OUT"; MM_chk="$M_chk_RC|$M_chk_OUT"
MM_derr="$M_dry_ERR"; MM_perr="$M_pool_ERR"; MM_cerr="$M_chk_ERR"
o_unreadable "$RA"
rr "$RA" "m-dry" "${WRAP[@]}" -- --harness claude --dry-run
assert_eq "AC5 --dry-run, origin behind vs origin unreadable: same exit and stdout" "$MM_dry" "$RC|$(printf '%s\n' "$OUT" | nst)"
assert_eq "AC5 --dry-run: stderr is the same with an unreadable origin" "$MM_derr" "$ERR"
rr "$RA" "ac4pool" "${WRAP[@]}" -- --harness claude --pool-only
assert_eq "AC5 --pool-only, origin behind vs unreadable: same exit and stdout" "$MM_pool" "$RC|$(printf '%s\n' "$OUT" | nst)"
assert_eq "AC5 --pool-only: stderr is the same with an unreadable origin" "$MM_perr" "$ERR"
rr "$RA" "m-chk" "${WRAP[@]}" -- --check HEAD
assert_eq "AC5 --check, origin behind vs unreadable: same exit and stdout" "$MM_chk" "$RC|$(printf '%s\n' "$OUT" | nst)"
assert_eq "AC5 --check: stderr is the same with an unreadable origin" "$MM_cerr" "$ERR"
assert_eq "AC5 --dry-run with a mismatching origin: exit 0, the dry-run report, stderr empty" "0|1|" "${MM_dry%%|*}|$(cnt "$MM_dry" 'release gate (dry run)')|$MM_derr"
assert_eq "AC5 none of the three modes printed anything about the head check" "0" "$(printf '%s\n' "$MM_derr$MM_perr$MM_cerr$MM_dry$MM_pool$MM_chk" | grep -c 'head check' || true)"
assert_eq "AC5 --pool-only did pool (not a refusal): its exit is the verdict's, 0 or 1" "yes" "$(case "${MM_pool%%|*}" in 0 | 1) echo yes ;; *) echo no ;; esac)"
assert_eq "AC5 git ls-remote was never called by --dry-run, --pool-only or --check (mismatching, then unreadable origin)" "0" "$(lsr_calls)"
o_match "$RA"

echo "AC6 (R3): order of the refusals: dirty tree, used DIR, head, CI"
used_dir_make() { mkdir -p "$1/evals/results/gate-$2"; printf '{}\n' > "$1/evals/results/gate-$2/gate.json"; }
# dirty tree beats used DIR (head also mismatches)
o_behind "$RA"; printf 'x\n' > "$RA/junk.txt"; used_dir_make "$RA" ac6-dirty
rr "$RA" ac6-dirty PB_GATE_NOW=$NOW100 -- --harness claude
assert_eq "AC6 dirty tree + used DIR + head mismatch: exit 2" "2" "$RC"
assert_contains "AC6 the dirty tree wins" "$ERR" "the working tree is not clean"
assert_not_contains "AC6 ... not the used DIR" "$ERR" "already holds results"
assert_not_contains "AC6 ... not the head" "$ERR" "head check"
rm -f "$RA/junk.txt"
# used DIR beats head mismatch
used_dir_make "$RA" ac6-used; rgf_gh_clearlog
rr "$RA" ac6-used PB_GATE_NOW=$NOW100 -- --harness claude
assert_eq "AC6 clean tree + used DIR + head mismatch: exit 2" "2" "$RC"
assert_contains "AC6 the used DIR wins" "$ERR" "already holds results of an earlier run"
assert_not_contains "AC6 ... not the head" "$ERR" "head check"
assert_eq "AC6 ... and gh was not read" "0" "$(rgf_gh_ncalls)"
# head mismatch beats a red CI
gh_red; rgf_gh_clearlog
rr "$RA" ac6-head PB_GATE_NOW=$NOW100 -- --harness claude
assert_eq "AC6 head mismatch + red CI: exit 3 (the head, not the CI's 2)" "3" "$RC"
assert_contains "AC6 the head sentence" "$ERR" "head check: HEAD $L12 is not the head of origin/$BRN ("
assert_not_contains "AC6 ... not the CI refusal" "$ERR" "is not green"
assert_eq "AC6 ... gh was not called" "0" "$(rgf_gh_ncalls)"
o_match "$RA"; rgf_gh_clearlog
rr "$RA" ac6-ci PB_GATE_NOW=$NOW100 -- --harness claude
assert_eq "AC6 control: with the head matching, the red CI is what stops it (exit 2)" "2|1" "$RC|$(cnt "$ERR" 'is not green')"
assert_eq "AC6 control: gh was read" "yes" "$([ "$(rgf_gh_ncalls)" -ge 1 ] && echo yes || echo no)"
rgf_gh_green

echo "AC6 (R3): --verify gives the exit and the text of the real run in every refusal, calls no runner but --print-hashes, makes nothing"
pair() { # REPO CASE [VAR=val ...] -- GATE ARGS...: the real run, then the same with --verify (same environment, same DIR)
  local r="$1" c="$2"; P_REPO="$r"; shift 2
  rgf_gh_clearlog; P_T0="$(tree "$r")"
  rr "$r" "$c" "$@"; R_RC="$RC"; R_OUT="$OUT"; R_ERR="$ERR"; R_GH="$(rgf_gh_ncalls)"; R_N="$(ncalls)"
  rgf_gh_clearlog
  rr "$r" "$c" "$@" --verify; V_RC="$RC"; V_OUT="$OUT"; V_ERR="$ERR"; V_GH="$(rgf_gh_ncalls)"; V_RUNS="$(runs_but_hashes)"
  V_T1="$(tree "$r")"; V_WT="$(nworktrees "$r")"; V_TMP="$(tmp_left)"; V_ODN="$([ -e "$ODN" ] && echo yes || echo no)"
}
same_refusal() { # NAME RC PATTERN
  local n="$1" rc="$2" pat="$3"
  assert_eq "$n: the real run exits $rc" "$rc" "$R_RC"
  assert_contains "$n: the real run says it" "$R_ERR" "$pat"
  assert_eq "$n: --verify exits like the real run" "$R_RC" "$V_RC"
  assert_eq "$n: --verify prints the same stderr" "$R_ERR" "$V_ERR"
  assert_eq "$n: --verify prints the same stdout (none)" "$R_OUT" "$V_OUT"
  assert_eq "$n: --verify reads gh as often as the real run" "$R_GH" "$V_GH"
  assert_eq "$n: --verify called no runner but --print-hashes" "0" "$V_RUNS"
  assert_eq "$n: --verify made no file (tree before the pair and after --verify)" "$P_T0" "$V_T1"
  assert_eq "$n: --verify left no worktree and nothing in TMPDIR, made no results dir (unless the case had one)" "1|0" "$V_WT|$V_TMP"
}
o_behind "$RA"
pair "$RA" v-head PB_GATE_NOW=$NOW3 -- --harness claude
same_refusal "AC6 verify head mismatch" 3 "head check: HEAD $L12 is not the head of origin/$BRN ("
assert_eq "AC6 verify head mismatch: no gh call" "0" "$V_GH"
assert_eq "AC6 verify head mismatch: no results dir" "no" "$V_ODN"
o_gone "$RA"
pair "$RA" v-gone PB_GATE_NOW=$NOW3 -- --harness claude
same_refusal "AC6 verify branch not on origin" 3 "head check: branch $BRN is not on origin"
o_unreadable "$RA"
pair "$RA" v-unread PB_GATE_NOW=$NOW3 -- --harness claude
same_refusal "AC6 verify origin unreadable" 3 "head check: cannot read origin ("
o_match "$RA"
printf 'x\n' > "$RA/junk.txt"
pair "$RA" v-dirty PB_GATE_NOW=$NOW3 -- --harness claude
same_refusal "AC6 verify dirty tree" 2 "the working tree is not clean"
assert_contains "AC6 verify dirty tree: the changed file is listed" "$V_ERR" "junk.txt"
rm -f "$RA/junk.txt"
used_dir_make "$RA" v-used
pair "$RA" v-used PB_GATE_NOW=$NOW3 -- --harness claude
same_refusal "AC6 verify used DIR" 2 "already holds results of an earlier run"
assert_eq "AC6 verify used DIR: the DIR is as before (gate.json only)" "gate.json" "$(ls "$RA/evals/results/gate-v-used")"
gh_red
pair "$RA" v-ci PB_GATE_NOW=$NOW3 -- --harness claude
same_refusal "AC6 verify CI red" 2 "CI of $(hd "$RA") is not green"
assert_eq "AC6 verify CI red: gh was read" "yes" "$([ "$V_GH" -ge 1 ] && echo yes || echo no)"
rgf_gh_green
pair "$RA" v-noqual PB_GATE_NOW=$NOW3 -- --harness claude --model m2
same_refusal "AC6 verify noqual baseline (the tag holds a gate for m1 only, the run is for m2)" 3 "no qualifying previous release gate for harness claude model m2"
pair "$RX" v-broken PB_GATE_NOW=$NOW3 -- --harness claude
same_refusal "AC6 verify broken baseline" 3 "baseline $BTAG: gate.json has no pooled list"
pair "$RA" v-budget PB_GATE_NOW=$NOW3 -- --harness claude --budget 10
same_refusal "AC6 verify budget too small (share 5 USD below the 6 USD behaviour estimate)" 3 "budget: refused"
assert_contains "AC6 verify budget too small: the estimate line" "$V_ERR" "estimate behaviour 6, outcome 20"
# the stale replay: DIR holds an outcome file and a log; --add-batch so the used-DIR check does not stop first
mkdir -p "$RS/evals/results/gate-v-stale/outcome-s1.runs"
printf '{"schema":"pb-evals/1","runs":[]}\n' > "$RS/evals/results/gate-v-stale/outcome-s1.json"; printf 'log\n' > "$RS/evals/results/gate-v-stale/outcome-s1.runs/pattern-01.with.1.log"
pair "$RS" v-stale PB_GATE_NOW=$NOW3 -- --harness claude --add-batch
same_refusal "AC6 verify stale replay" 2 "replay: 1 run(s) were graded differently than the current graders would grade them (pattern-01.with.1); the recorded batch is stale"
# the order holds under --verify too (same three pairs)
o_behind "$RA"; printf 'x\n' > "$RA/junk.txt"; used_dir_make "$RA" w-dirty
rr "$RA" w-dirty PB_GATE_NOW=$NOW3 -- --harness claude --verify
assert_eq "AC6 --verify: dirty tree + used DIR + head mismatch: the dirty tree wins (exit 2)" "2|1" "$RC|$(cnt "$ERR" 'the working tree is not clean')"
rm -f "$RA/junk.txt"; used_dir_make "$RA" w-used
rr "$RA" w-used PB_GATE_NOW=$NOW3 -- --harness claude --verify
assert_eq "AC6 --verify: used DIR + head mismatch: the used DIR wins (exit 2)" "2|1|0" "$RC|$(cnt "$ERR" 'already holds results')|$(cnt "$ERR" 'head check')"
gh_red; rgf_gh_clearlog
rr "$RA" w-head PB_GATE_NOW=$NOW3 -- --harness claude --verify
assert_eq "AC6 --verify: head mismatch + red CI: the head wins (exit 3, gh not called)" "3|1|0" "$RC|$(cnt "$ERR" 'head check: HEAD ')|$(rgf_gh_ncalls)"
rgf_gh_green; o_match "$RA"

echo "AC7 (R3): --verify when everything passes: exit 0, the verify lines, the runner commands of the real run, nothing spent"
# vr NAME [VAR=val ...] -- GATE ARGS...: --verify (V_*), then the real run (R_*) in the same DIR; the command lines of both, normalized
# a runner command with an empty selection (--tasks '' / --scenarios '': a both-arms call of an all-reused kind) is not one the real run makes
# [spec ambiguity: R3 says "the main runner commands of the real run"; whether --verify lists that empty call is not stated]: it is left out here
cmds_verify() { printf '%s\n' "$1" | grep '^bash ' | grep -v -- "--tasks '' \|--scenarios '' " | sed -e 's#^bash evals/##' -e 's# --variant-held [^ ]*##' | nst | LC_ALL=C sort; }
cmds_real() { grep -v -- '--preflight\|--print-hashes' "$CALLS" | sed -e 's# --variant-held [^ ]*##' | nst | LC_ALL=C sort; }
vr() {
  local r="$RA" c="$1"; shift
  rgf_gh_clearlog; P_T0="$(tree "$r")"
  rr "$r" "$c" "$@" --verify; V_RC="$RC"; V_OUT="$OUT"; V_ERR="$ERR"; V_GH="$(rgf_gh_ncalls)"; V_RUNS="$(runs_but_hashes)"; V_HASHES="$(grep -c -- '--print-hashes' "$CALLS" || true)"
  V_T1="$(tree "$r")"; V_WT="$(nworktrees "$r")"; V_TMP="$(tmp_left)"; V_ODN="$([ -e "$ODN" ] && echo yes || echo no)"
  V_CMDS="$(cmds_verify "$V_OUT")"
  rr "$r" "$c" "$@"; R_RC="$RC"; R_CMDS="$(cmds_real)"
}
vr v-ok PB_GATE_NOW=$NOW3 -- --harness claude
assert_eq "AC7 exit 0" "0" "$V_RC"
assert_eq "AC7 stdout starts with 'verify: commit <12 hex of HEAD>, harness, model, k'" "verify: commit $L12, harness claude, model m1, k=5" "$(printf '%s\n' "$V_OUT" | head -n 1)"
assert_eq "AC7 stdout ends with the ok line" "verify: ok, a real run would start now" "$(printf '%s\n' "$V_OUT" | tail -n 1)"
assert_not_contains "AC7 no 'release gate (dry run)' line" "$V_OUT" "release gate (dry run)"
assert_not_contains "AC7 no '(a real run refuses it)' text" "$V_OUT" "(a real run refuses it)"
assert_contains "AC7 the both-arms behaviour command carries only the item with no baseline (E14, the rest is reused)" "$V_OUT" "evals/run-evals.sh --harness claude --model m1 --arm both --repeat 5 --scenarios E14 --out "
assert_contains "AC7 the reused items run with the with arm only (behaviour)" "$V_OUT" "--arm with --repeat 5 --scenarios E1,E2,E3,E8,E13 --out $ODN/behaviour-with-"
assert_contains "AC7 the reused tasks run with the with arm only (outcome)" "$V_OUT" "evals/run-outcome.sh --harness claude --model m1 --arm with --repeat 5 --tasks $TASKS --out $ODN/outcome-with-"
assert_contains "AC7 the variant path is the placeholder of the dry run, not a real worktree" "$V_OUT" "pbgate.XXXXXX/variant"
assert_eq "AC7 three runner commands with a selection are shown (behaviour both, behaviour with, outcome with)" "3" "$(printf '%s\n' "$V_CMDS" | grep -c .)"
assert_eq "AC7 verify: gh was read once (the CI check ran)" "1" "$V_GH"
assert_eq "AC7 verify: only --print-hashes was called on the runners (one call each, no preflight, no real run)" "0|2" "$V_RUNS|$V_HASHES"
assert_eq "AC7 verify: no file made (tree before and after)" "$P_T0" "$V_T1"
assert_eq "AC7 verify: no worktree, nothing left in TMPDIR (BROOT is cleaned), no results dir" "1|0|no" "$V_WT|$V_TMP|no"
assert_eq "AC7 the real run of the same case exits 0 (fixture sanity)" "0" "$R_RC"
assert_eq "AC7 the commands --verify shows are the commands the real run executed (reuse applied; paths, variant and stamp aside)" "$R_CMDS" "$V_CMDS"
vr v-budget PB_GATE_NOW=$NOW3 -- --harness claude --budget 100
assert_eq "AC7 --budget 100: exit 0 and ok line" "0|verify: ok, a real run would start now" "$V_RC|$(printf '%s\n' "$V_OUT" | tail -n 1)"
assert_contains "AC7 --budget 100: the behaviour runner has two calls, each gets 25 (a quarter)" "$V_OUT" "--scenarios E14 --out $ODN/behaviour-"
assert_eq "AC7 --budget 100: both behaviour commands carry a quarter share, the outcome command a half" "2|1" "$(printf '%s\n' "$V_OUT" | grep '^bash evals/run-evals.sh' | grep -cE -- '--max-cost 25( |$)')|$(printf '%s\n' "$V_OUT" | grep '^bash evals/run-outcome.sh' | grep -v -- "--tasks ''" | grep -cE -- '--max-cost 50( |$)')"
assert_contains "AC7 --budget 100: the budget line goes to stderr" "$V_ERR" "budget: 100 USD total, 50 per runner; estimate behaviour 6, outcome 20"
assert_eq "AC7 --budget 100: the commands --verify shows are the commands the real run executed (the budget split applied)" "$R_CMDS" "$V_CMDS"
assert_eq "AC7 --budget 100: no file, no worktree, no runner but --print-hashes" "$P_T0|1|0" "$V_T1|$V_WT|$V_RUNS"
vr v-fresh PB_GATE_NOW=$NOW100 -- --harness claude
assert_eq "AC7 a baseline older than 7 days: exit 0, no reuse (no --arm with command, one call per runner)" "0|2|0" "$V_RC|$(printf '%s\n' "$V_CMDS" | grep -c .)|$(cnt "$V_OUT" ' --arm with ')"
assert_eq "AC7 no reuse: the commands --verify shows are the commands the real run executed" "$R_CMDS" "$V_CMDS"
# --skip-ci-check and the CI check with a fake gh
gh_red; rgf_gh_clearlog
rr "$RA" v-skipci PB_GATE_NOW=$NOW3 -- --harness claude --verify --skip-ci-check
assert_eq "AC7 --verify --skip-ci-check with a red CI: exit 0, gh not called" "0|0|verify: ok, a real run would start now" "$RC|$(rgf_gh_ncalls)|$(printf '%s\n' "$OUT" | tail -n 1)"
rgf_gh_green
rr "$RA" v-skipci2 PB_GATE_NOW=$NOW3 -- --harness claude --verify
assert_eq "AC7 --verify with a green gh: exit 0" "0" "$RC"
# no detail lost on the way: with the real baseline missing nothing is shown as ok
rr "$RA" v-noqual2 PB_GATE_NOW=$NOW3 -- --harness claude --model m2 --verify
assert_eq "AC7 control: a refusal does not print the ok line" "0" "$(cnt "$OUT$ERR" 'verify: ok')"

echo "AC8 (R3): --verify with --json, --pool-only, --check, --bootstrap-baseline: exit 2 with the R3 sentence; --verify --dry-run is --verify"
combo() { # FLAGS...: --verify with them
  local f="$1"; shift
  rgf_gh_clearlog; P_T0="$(tree "$RA")"
  rr "$RA" "c8" PB_GATE_NOW=$NOW3 -- --harness claude --verify "$@"
  assert_eq "AC8 --verify $*: exit 2" "2" "$RC"
  assert_contains "AC8 --verify $*: the sentence" "$ERR" "--verify cannot be combined with $f"
  assert_eq "AC8 --verify $*: nothing ran, nothing was made, gh not called" "0|$P_T0|0" "$(ncalls)|$(tree "$RA")|$(rgf_gh_ncalls)"
  assert_eq "AC8 --verify $*: stdout is empty" "" "$OUT"
}
combo --json --json
combo --pool-only --pool-only
combo --check --check HEAD
combo --bootstrap-baseline --bootstrap-baseline
combo --bootstrap-baseline --bootstrap-baseline --dry-run
rr "$RA" "c8" PB_GATE_NOW=$NOW3 -- --harness claude --check HEAD --verify
assert_eq "AC8 --check HEAD --verify (the other order): exit 2 with the sentence" "2|1" "$RC|$(cnt "$ERR" '--verify cannot be combined with --check')"
rr "$RA" "c8" PB_GATE_NOW=$NOW3 -- --harness claude --verify --dry-run --pool-only
assert_eq "AC8 --verify --dry-run --pool-only: exit 2" "2" "$RC"
assert_contains "AC8 it gets the --verify sentence (the combination check of --verify runs first)" "$ERR" "--verify cannot be combined with --pool-only"
assert_not_contains "AC8 ... not the sentence of --dry-run with --pool-only" "$ERR" "use either --dry-run or --pool-only"
# --verify --dry-run behaves as --verify, also with --budget (the shares are those of a real run, not of a dry run)
rr "$RA" "c8v" PB_GATE_NOW=$NOW3 -- --harness claude --verify; A_RC="$RC"; A_OUT="$(printf '%s\n' "$OUT" | nst)"; A_ERR="$ERR"
rr "$RA" "c8v" PB_GATE_NOW=$NOW3 -- --harness claude --verify --dry-run
assert_eq "AC8 --verify --dry-run: same exit, stdout and stderr as --verify" "$A_RC|$A_OUT|$A_ERR" "$RC|$(printf '%s\n' "$OUT" | nst)|$ERR"
assert_not_contains "AC8 --verify --dry-run: no dry run report" "$OUT" "release gate (dry run)"
assert_eq "AC8 --verify --dry-run: stdout starts with the verify line" "verify: commit $L12, harness claude, model m1, k=5" "$(printf '%s\n' "$OUT" | head -n 1)"
rr "$RA" "c8v" PB_GATE_NOW=$NOW3 -- --harness claude --dry-run --verify; B_RC="$RC"
assert_eq "AC8 --dry-run --verify (the other order): same stdout as --verify" "$A_OUT" "$(printf '%s\n' "$OUT" | nst)"
rr "$RA" "c8b" PB_GATE_NOW=$NOW3 -- --harness claude --verify --budget 100; A_RC="$RC"; A_OUT="$(printf '%s\n' "$OUT" | nst)"; A_ERR="$ERR"
rr "$RA" "c8b" PB_GATE_NOW=$NOW3 -- --harness claude --verify --dry-run --budget 100
assert_eq "AC8 --verify --dry-run --budget 100: same exit, stdout and stderr as --verify --budget 100 (real-run shares and budget line)" "$A_RC|$A_OUT|$A_ERR" "$RC|$(printf '%s\n' "$OUT" | nst)|$ERR"
assert_contains "AC8 --verify --dry-run --budget 100: the budget line is the real run's" "$ERR" "budget: 100 USD total, 50 per runner; estimate behaviour 6, outcome 20"
assert_not_contains "AC8 --verify --dry-run --budget 100: not the dry run's budget line" "$ERR" "budget: dry run"
# --verify --dry-run still refuses like a real run (it is not a dry run): a mismatching head
o_behind "$RA"
rr "$RA" "c8h" PB_GATE_NOW=$NOW3 -- --harness claude --verify --dry-run
assert_eq "AC8 --verify --dry-run with a mismatching head: refused like --verify (exit 3, the head sentence)" "3|1" "$RC|$(cnt "$ERR" 'head check: HEAD ')"
o_match "$RA"

t_summary
