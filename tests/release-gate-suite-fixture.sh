#!/usr/bin/env bash
# shellcheck shell=bash
# Shared setup of the release gate suites, sourced by tests/test-release-gate.sh and tests/test-release-gate-b.sh (not a suite).
. "$(dirname "$0")/lib.sh"
GATE="$PB_ROOT/tools/release-gate.sh"
command -v node >/dev/null 2>&1 || { t_skip 1 "node missing"; t_summary; exit $?; }
# v0.34.0 B1 (G1/D4): a real run reads the CI check runs of HEAD through `gh api`; a fake gh on PATH serves green check runs by default
# (tests/release-gate-fixture.sh), so every real-run case below runs the check without --skip-ci-check. PB_GATE_REPO names the repository.
. "$(dirname "$0")/release-gate-fixture.sh"
rgf_gh_install "$RGF_W/gh"; export PATH="$RGF_GH/bin:$PATH"; export PB_GATE_REPO=acme/widgets
W="$(mk_tmp)"
CALLS="$W/calls.log"; : > "$CALLS"
OBS="$W/obs.log"; : > "$OBS"
R="$W/repo"; mkdir -p "$R/tools" "$R/evals/tasks" "$R/skills"
# v0.32.0 S6 (AC7''): the fixture's copy of the gate gets GATE_SCENARIOS="E1 E2 E3" (a subset of the fake AUTO) before the base commit.
# The line is replaced when the script has one, else inserted before DEFAULT_TASKS (no-op for a script that does not read it yet).
gate_scen() { # FILE LIST
  local f="$1" l="$2" t
  [ -f "$f" ] || return 0
  t="$(mktemp)" || return 1
  if grep -q '^GATE_SCENARIOS=' "$f"; then sed "s/^GATE_SCENARIOS=.*/GATE_SCENARIOS=\"$l\"/" "$f" > "$t"
  else awk -v l="$l" '/^DEFAULT_TASKS=/ && !d { print "GATE_SCENARIOS=\"" l "\""; d = 1 } { print }' "$f" > "$t"; fi
  cat "$t" > "$f"; rm -f "$t"
}
[ -f "$GATE" ] && cp -p "$GATE" "$R/tools/release-gate.sh"
gate_scen "$R/tools/release-gate.sh" "E1 E2 E3"
cp -p "$PB_ROOT/tools/eval-delta.sh" "$R/tools/eval-delta.sh"
# D6 (v0.34.0 B2): with --harness the gate installs the variant once through evals/lib-harness.sh (pbh_variant_begin: lock, snapshot,
# install.sh install + doctor, VERSION check) and hands the runners --variant-held DIR. The fixture ships the real lib and a fake install.sh.
cp -p "$PB_ROOT/evals/lib-harness.sh" "$R/evals/lib-harness.sh"
printf '7.7.7-fix\n' > "$R/VERSION"
cat > "$R/install.sh" <<'IEOF'
#!/usr/bin/env bash
D="$(cd "$(dirname "$0")" && pwd)"
cmd="$1"; shift
H=""
while [ $# -gt 0 ]; do case "$1" in --home) H="$2"; shift ;; esac; shift; done
case "$cmd" in
  install) rm -rf "${H:?}/.agents/playbook"; mkdir -p "$H/.agents/playbook"; cp "$D/VERSION" "$H/.agents/playbook/VERSION" ;;
esac
exit 0
IEOF
chmod 755 "$R/install.sh"
for t in pattern-15-erase-account-ambiguous pattern-24-merge-duplicate-customers pattern-26-consistent-price-rounding pattern-01-option-value-label; do
  mkdir -p "$R/evals/tasks/$t"; printf 'x\n' > "$R/evals/tasks/$t/prompt.md"
done
# fake runner: records "<name> <args>", writes ${OUT%.md}.json with both arms; with passes check x, without fails it
# FAKE_RC_<NAME> sets its exit code.
# v0.32.0 (AC7') and D6 (v0.34.0: the gate passes --variant-held DIR): the fake understands --variant-held DIR (the gate's detached worktree of HEAD). While it runs it records what it
# sees of DIR in $OBS, and its "variant" object (sha = HEAD of DIR, end_check ok) is null without --variant, like the real runners.
# Per-case controls (environment): FAKE_VARIANT=null|nullsha|badsha|changed, FAKE_SKIP=ID,ID (no runs for these items),
# FAKE_ERR=ID:ARM:N (the first N runs of that item and arm are ERROR runs), FAKE_INVERT=ID (with fails, without passes),
# FAKE_ISOFAIL=ID (the without-arm isolation check FAILs for that item), FAKE_HANG=NAME (waits for $W/release),
# FAKE_PF_FAIL=NAME (v0.33.0 AC7: that runner's --preflight exits 3), FAKE_HOOKS=false|none (v0.33.0 N3: the file says "hooks": false, or has no hooks field; default true). Every run also has the PASS
# check "nothing written outside the workdir" (rule (g) needs it in every item).
# It also writes local paths (workroot, --out, HOME, the repo; and their Windows forms where cygpath exists) into the json and
# the md, and evidence/log files next to them, so the tests can look for what the gate must rewrite or leave uncommitted.
mk_fake() { # NAME LISTFLAG
  cat > "$R/evals/$1" <<EOF
#!/usr/bin/env bash
# fake $1
AUTO="E1 E2 E3"
NAME=$1; LISTFLAG=$2; CALLS='$CALLS'; OBS='$OBS'; W='$W'
EOF
  cat >> "$R/evals/$1" <<'EOF'
printf '%s %s\n' "$NAME" "$*" >> "$CALLS"
# v0.33.0 AC7 (interface defined by the tests): `--preflight` = a no-cost check of what the runner would refuse with exit 3 for the
# selection on its command line: exit 0 with no output and no file when ready, exit 3 with the reason on stderr when not.
# FAKE_PF_FAIL=NAME makes this fake refuse (NAME = run-evals.sh or run-outcome.sh).
for a in "$@"; do
  if [ "$a" = --preflight ]; then
    if [ "${FAKE_PF_FAIL:-}" = "$NAME" ]; then echo "error: preflight: $NAME cannot start (fake: python3 is required)" >&2; exit 3; fi
    exit 0
  fi
done
out=""; model=""; harness="custom"; list=""; k=1; prev=""; vdir=""
for a in "$@"; do
  case "$prev" in
    --out) out="$a" ;; --model) model="$a" ;; --harness) harness="$a" ;; --repeat) k="$a" ;; --variant-held) vdir="$a" ;; "$LISTFLAG") list="$a" ;;
  esac
  prev="$a"
done
repo="$(cd "$(dirname "$0")/.." && pwd)"
commit="$(git -C "$repo" rev-parse HEAD)"
vh=""
if [ -n "$vdir" ]; then
  vh="$(git -C "$vdir" rev-parse HEAD 2>/dev/null)"
  lsh="$(git -C "$repo" ls-tree -r --name-only HEAD | LC_ALL=C sort)"
  lsv="$(git -C "$vdir" ls-files 2>/dev/null | LC_ALL=C sort)"
  ond="$(cd "$vdir" 2>/dev/null && find . -name .git -prune -o -type f -print | sed 's|^\./||' | LC_ALL=C sort)"
  lse=0; [ -n "$lsh" ] && [ "$lsh" = "$lsv" ] && lse=1
  one=0; [ -n "$lsh" ] && [ "$lsh" = "$ond" ] && one=1
  chg="$(git -C "$vdir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  wtl="$(git -C "$repo" worktree list | grep -cF "$(basename "$vdir")")"
  printf 'OBS %s dir=%s head=%s tracked=%s ondisk=%s changes=%s listed=%s\n' "$NAME" "$vdir" "$vh" "$lse" "$one" "$chg" "$wtl" >> "$OBS"
else
  printf 'OBS %s dir= worktrees=%s\n' "$NAME" "$(git -C "$repo" worktree list | wc -l | tr -d ' ')" >> "$OBS"
fi
if [ "${FAKE_HANG:-}" = "$NAME" ]; then
  trap ': > "$W/hang.done"; exit 143' TERM
  : > "$W/hang.started"
  n=0; while [ ! -e "$W/release" ] && [ "$n" -lt 300 ]; do sleep 0.1; n=$((n + 1)); done
  : > "$W/hang.done"
fi
rcv="FAKE_RC_${NAME%%.sh}"; rcv="${rcv//-/_}"; rc="${!rcv:-0}"
[ "$rc" = 2 ] || [ "$rc" = 3 ] && exit "$rc"
ISOK="without arm: no playbook file read and no playbook Skill call"
eid=""; earm=""; en=0
if [ -n "${FAKE_ERR:-}" ]; then eid="${FAKE_ERR%%:*}"; rest="${FAKE_ERR#*:}"; earm="${rest%%:*}"; en="${rest#*:}"; fi
runs=""; sep=""
for s in $(printf '%s' "$list" | tr ',' ' '); do
  case ",${FAKE_SKIP:-}," in *",$s,"*) continue ;; esac
  i=1
  while [ "$i" -le "$k" ]; do
    for arm in with without; do
      r=PASS; [ "$arm" = without ] && r=FAIL
      case ",${FAKE_INVERT:-}," in *",$s,"*) if [ "$r" = PASS ]; then r=FAIL; else r=PASS; fi ;; esac
      st=graded; er=null; cks="{\"name\":\"x\",\"key\":\"x\",\"result\":\"$r\"},{\"name\":\"nothing written outside the workdir\",\"key\":\"nothing written outside the workdir\",\"result\":\"PASS\"}"
      if [ "$s" = "$eid" ] && [ "$arm" = "$earm" ] && [ "$i" -le "$en" ]; then st=error; er='"boom"'; cks=""; fi
      if [ "$s" = "${FAKE_ISOFAIL:-}" ] && [ "$arm" = without ]; then cks="$cks,{\"name\":\"$ISOK\",\"key\":\"$ISOK\",\"result\":\"FAIL\"}"; fi
      runs="$runs$sep{\"scenario\":\"$s\",\"arm\":\"$arm\",\"k\":$i,\"label\":\"$s.$arm.$i\",\"status\":\"$st\",\"error\":$er,\"isolation\":\"adapter\",\"fixture_tree\":\"t-$s\",\"prompt_sha\":\"p-$s\",\"cost_usd\":0.1,\"seconds\":5,\"notes\":[],\"dropped_user_lines\":0,\"checks\":[$cks]}"
      sep=","
    done
    i=$((i + 1))
  done
done
vj=null
if [ -n "$vdir" ]; then
  vs="\"$vh\""; ve=ok
  case "${FAKE_VARIANT:-ok}" in
    nullsha) vs=null ;;
    badsha) vs='"0000000000000000000000000000000000000000"' ;;
    changed) ve=changed ;;
  esac
  [ "${FAKE_VARIANT:-ok}" = null ] || vj="{\"tree\":\"$vdir\",\"version\":\"0.30.0\",\"sha\":$vs,\"end_check\":\"$ve\"}"
fi
wr="${TMPDIR:-/tmp}/pbwork.$$"
hkj=',"hooks":true'
case "${FAKE_HOOKS:-true}" in false) hkj=',"hooks":false' ;; none) hkj="" ;; esac
wins=""; winj=""
if command -v cygpath >/dev/null 2>&1; then
  hm="$(cygpath -m "$HOME")"; hw="$(cygpath -w "$HOME")"; rm_="$(cygpath -m "$repo")"
  wins="home (windows, forward): $hm/.claude
home (windows, back): $hw\\.claude
repo (windows): $rm_/evals
"
  winj=",\"home_win_m\":\"$hm/.claude\",\"home_win_w\":\"${hw//\\/\\\\}\\\\.claude\",\"repo_win_m\":\"$rm_/evals\""
fi
mkdir -p "$(dirname "$out")" "${out%.md}.evidence" "${out%.md}.runs"
printf '# fake\nworkroot: %s\nout: %s\nhome: %s/.claude\nrepo: %s/evals\n%s' "$wr" "$out" "$HOME" "$repo" "$wins" > "$out"
if [ -n "${FAKE_EDGE:-}" ]; then
  { printf 'edge-neg-tmp: %s\n' "$W/tmpfoo/x"
    printf 'edge-neg-root: %s\n' "$repo-other/y"
    printf 'edge-neg-home: %s\n' "$W/homework/z"
    printf 'edge-pos-tmp-slash: %s\n' "$W/tmp/p1"
    printf 'edge-pos-tmp-quote: "%s"\n' "$W/tmp"
    printf 'edge-pos-tmp-space: %s tail\n' "$W/tmp"
    printf 'edge-pos-tmp-paren: (%s)\n' "$W/tmp"
    printf 'edge-pos-tmp-end: %s\n' "$W/tmp"
    printf 'edge-pos-root-slash: %s\n' "$repo/evals/z"
    printf 'edge-pos-root-quote: "%s"\n' "$repo"
    printf 'edge-pos-root-end: %s\n' "$repo"
    printf 'edge-pos-home-end: %s\n' "$HOME"
    printf 'edge-pos-tmp-comma: a %s, b\n' "$W/tmp"
    printf 'edge-pos-tmp-semi: x=%s;\n' "$W/tmp"
    printf 'edge-pos-tmp-colon: %s:other\n' "$W/tmp"
    printf 'edge-pos-tmp-bracket: [%s]\n' "$W/tmp"
    printf 'edge-pos-tmp-brace: {%s}\n' "$W/tmp"
    printf 'edge-pos-tmp-gt: <%s>\n' "$W/tmp"
    printf 'edge-pos-tmp-tick: `%s`\n' "$W/tmp"
    printf 'edge-pos-tmp-dot-end: see %s.\n' "$W/tmp"
    printf 'edge-pos-tmp-dot-space: see %s. Next\n' "$W/tmp"
    printf 'edge-pos-root-comma: %s,\n' "$repo"
    printf 'edge-pos-root-bracket: [%s]\n' "$repo"
    printf 'edge-pos-root-dot-end: see %s.\n' "$repo"
    printf 'edge-pos-home-comma: %s, x\n' "$HOME"
    printf 'edge-pos-home-semi: %s;\n' "$HOME"
    printf 'edge-neg-tmp-dash: %s\n' "$W/tmp-x"
    printf 'edge-neg-tmp-under: %s\n' "$W/tmp_x"
    printf 'edge-neg-tmp-dotname: %s\n' "$W/tmp.d"
    printf 'edge-neg-root-dash: %s\n' "$repo-x"
    printf 'edge-neg-root-under: %s\n' "${repo}_x"
    printf 'edge-neg-root-dotname: %s\n' "$repo.d"
    printf 'edge-neg-home-dash: %s\n' "$HOME-x"
    printf 'edge-neg-home-dotname: %s\n' "$HOME.d"; } >> "$out"
  winj="$winj,\"edge_json\":[\"$W/tmp,\",\"$W/tmp;\",\"$W/tmp]\",\"$W/tmp-x\",\"$W/tmp_x\",\"$W/tmp.d\"]"
fi
printf 'x\n' > "${out%.md}.evidence/ev.txt"; printf '{"schema":"pb-evals/1"}\n' > "${out%.md}.evidence/inner.json"
printf 'x\n' > "${out%.md}.runs/r.md"; printf 'log\n' > "${out%.md}.log"
printf '{"schema":"pb-evals/1","playbook_commit":"%s","playbook_version":"0.30.0","harness":"%s","model":"%s","arms":["with","without"],"repeat":%s,"max_cost":null,"interactive":false%s,"started":"2026-10-27T10:00:00Z","workroot":"%s","out":"%s","home_note":"%s/.claude","repo_note":"%s/evals"%s,"variant":%s,"runs":[%s],"summary":[]}\n' \
  "$commit" "$harness" "$model" "$k" "$hkj" "$wr" "$out" "$HOME" "$repo" "$winj" "$vj" "$runs" > "${out%.md}.json"
exit "$rc"
EOF
  chmod 755 "$R/evals/$1"
}
mk_fake run-evals.sh --scenarios
mk_fake run-outcome.sh --tasks
( cd "$R" && git init -q && git config user.email t@example.invalid && git config user.name tester &&
  git config commit.gpgsign false && git config core.autocrlf false && git add -A && git commit -qm base ) || t_bad "fixture repo" "git init failed"
SHA="$(git -C "$R" rev-parse HEAD)"; SHA12="$(printf '%s' "$SHA" | cut -c1-12)"
TASKS="pattern-15-erase-account-ambiguous,pattern-24-merge-duplicate-customers,pattern-26-consistent-price-rounding"
g() { RC=0; OUT="$(cd "$R" && env HOME="$W/home" bash tools/release-gate.sh "$@" 2>&1)" || RC=$?; }
ncalls() { grep "^$1 " "$CALLS" 2>/dev/null | grep -vc -- ' --preflight' || true; }   # real runs only: a --preflight call starts nothing
pf_real_calls() { grep -v -- ' --preflight' "$CALLS" | grep -c . || true; }   # v0.33.0 R1-3: lines of runners that really started
# --- v0.32.0 helpers (S1: AC1, AC2, AC2') ---
# assert_has_all NAME LINE PIECE... : every piece is in LINE (a displayed command: where --variant sits is not fixed by the spec)
assert_has_all() {
  local n="$1" line="$2" p; shift 2
  for p in "$@"; do case "$line" in *"$p"*) ;; *) t_bad "$n" "missing [$p] in [$line]"; return 0 ;; esac; done
  t_ok "$n"
}
# gj FILE JS-EXPRESSION over j (the parsed JSON file): prints the value, objects and arrays as JSON; MISSING when no file
gj() {
  [ -f "$1" ] || { echo MISSING; return 0; }
  node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);const v=eval(process.argv[1]);console.log(typeof v==="object"?JSON.stringify(v):String(v))}catch(e){console.log("BAD "+e.message)}})' "$2" < "$1"
}
obs_dir_of() { sed -n "s/^OBS $1 dir=\([^ ]*\) .*/\1/p" "$OBS" | head -n 1; }
idre() { printf '(^|[^A-Za-z0-9])%s([^A-Za-z0-9]|$)' "$1"; }
mkdir -p "$W/home" "$W/tmp"
# ge "ENV=v ENV2=w" ARGS... -> OUT, RC. HOME and TMPDIR are inside $W, so every local path the run writes is one this suite knows.
# GE_PATH, when set, is the PATH of the run, passed as one word (a PATH holds spaces on Windows; "ENV" is word-split).
# GR is the repository to run in (default $R).
ge() {
  local e="$1"; shift
  RC=0; OUT="$(cd "${GR:-$R}" && env $e ${GE_PATH+"PATH=$GE_PATH"} HOME="$W/home" TMPDIR="$W/tmp" bash tools/release-gate.sh "$@" 2>&1)" || RC=$?
}
# rcase NAME "ENV" ARGS... -> a real --harness claude run into evals/results/NAME; ODN is that dir, GJ its gate.json
rcase() {
  local n="$1" e="$2"; shift 2
  ODN="${GR:-$R}/evals/results/$n"; GJ="$ODN/gate.json"
  : > "$OBS"; : > "$CALLS"
  ge "$e" --harness claude --model m1 --out-dir "evals/results/$n" "$@"
}
# fail_case NAME "ENV" REASON-ERE ARGS... : one broken rule -> exit 1, verdict fail, exactly one reason matching the pattern,
# the same reason in gate.json and in the human output
fail_case() {
  local n="$1" e="$2" kw="$3" reason; shift 3
  rcase "$n" "$e" "$@"
  assert_rc "AC2 $n: verdict fail -> exit 1" 1
  assert_eq "AC2 $n: gate.json verdict is fail" "fail" "$(gj "$GJ" j.verdict)"
  assert_eq "AC2 $n: one reason for the one broken rule" "1" "$(gj "$GJ" j.verdict_reasons.length)"
  reason="$(gj "$GJ" 'j.verdict_reasons[0]')"
  if printf '%s' "$reason" | grep -Eiq -- "$kw"; then t_ok "AC2 $n: the reason names the broken rule ($kw)"; else t_bad "AC2 $n: the reason names the broken rule ($kw)" "reason: [$reason]"; fi
  assert_contains "AC2 $n: the reason is in the human output" "$OUT" "$reason"
}

