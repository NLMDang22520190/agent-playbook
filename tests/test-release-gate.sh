#!/usr/bin/env bash
# Tests for tools/release-gate.sh (v0.30.0 lane g, queue P0-3, spec AC1-AC6): the reproducible release gate runs the AUTO
# scenarios and the separating outcome tasks in both arms, k >= 5, on the exact HEAD commit, and pools only same-commit
# results through tools/eval-delta.sh. The tool is copied into a throw-away repo whose evals/run-evals.sh and
# evals/run-outcome.sh are RECORDING fakes that write synthetic pb-evals/1 files; tools/eval-delta.sh is the real one.
# Never calls a real harness.
# v0.32.0 (slice S1: AC1, AC2, AC2', AC7', m-b, m-d): the gate measures a detached worktree of HEAD (--variant DIR), computes one
# verdict (variant, full set, >= 5 graded per item and arm, eval-delta rc 0, no Δ below 0), writes DIR/gate.json and a DIR/.gitignore,
# rewrites local paths in the pooled files, and exits 1 on a failed verdict. The fake runners below write a variant object.
. "$(dirname "$0")/lib.sh"
GATE="$PB_ROOT/tools/release-gate.sh"
command -v node >/dev/null 2>&1 || { t_skip 1 "node missing"; t_summary; exit $?; }

echo "AC1 the tool exists"
assert_file "AC1 tools/release-gate.sh exists" "$GATE"

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
for t in pattern-15-erase-account-ambiguous pattern-24-merge-duplicate-customers pattern-26-consistent-price-rounding pattern-01-option-value-label; do
  mkdir -p "$R/evals/tasks/$t"; printf 'x\n' > "$R/evals/tasks/$t/prompt.md"
done
# fake runner: records "<name> <args>", writes ${OUT%.md}.json with both arms; with passes check x, without fails it
# FAKE_RC_<NAME> sets its exit code.
# v0.32.0 (AC7'): the fake understands --variant DIR (the gate's detached worktree of HEAD). While it runs it records what it
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
    --out) out="$a" ;; --model) model="$a" ;; --harness) harness="$a" ;; --repeat) k="$a" ;; --variant) vdir="$a" ;; "$LISTFLAG") list="$a" ;;
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
g() { RC=0; OUT="$(cd "$R" && bash tools/release-gate.sh "$@" 2>&1)" || RC=$?; }
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
# GR is the repository to run in (default $R).
ge() {
  local e="$1"; shift
  RC=0; OUT="$(cd "${GR:-$R}" && env $e HOME="$W/home" TMPDIR="$W/tmp" bash tools/release-gate.sh "$@" 2>&1)" || RC=$?
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

echo "AC1 usage: --model is required, K >= 5"
g --harness claude --dry-run
assert_rc "AC1 no --model -> exit 2" 2
g --harness claude --model m1 --k 3 --dry-run
assert_rc "AC1 --k 3 -> exit 2" 2
assert_contains "AC1 --k 3: the message names the minimum" "$OUT" "at least 5"
g --harness claude --model m1 --k x --dry-run
assert_rc "AC1 --k x -> exit 2" 2
g --model m1 --dry-run
assert_rc "AC1 neither --harness nor --cmd -> exit 2" 2
g --harness claude --cmd "bash x" --model m1 --dry-run
assert_rc "AC1 both --harness and --cmd -> exit 2" 2
g --harness claude --model m1 --bogus --dry-run
assert_rc "AC1 an unknown option -> exit 2" 2

echo "AC2/AC3 --dry-run prints the commands and runs nothing"
: > "$CALLS"
g --harness claude --model m1 --dry-run
assert_rc "AC2 --dry-run -> exit 0" 0
assert_eq "AC2 --dry-run calls no runner" "0" "$(wc -l < "$CALLS" | tr -d ' ')"
assert_contains "AC2 the commit is the full HEAD sha" "$OUT" "$SHA"
assert_has_all "AC2 the behaviour command: the GATE_SCENARIOS set (AC14; the fixture's equals its AUTO), both arms, k=5 (AC7': now with --variant)" "$(printf '%s\n' "$OUT" | grep 'evals/run-evals.sh')" "evals/run-evals.sh" "--harness claude" "--model m1" "--arm both --repeat 5" "--scenarios E1,E2,E3" "--variant "
assert_has_all "AC2 the outcome command: the separating tasks, both arms, k=5 (AC7': now with --variant)" "$(printf '%s\n' "$OUT" | grep 'evals/run-outcome.sh')" "evals/run-outcome.sh" "--harness claude" "--model m1" "--arm both --repeat 5" "--tasks $TASKS" "--variant "
assert_contains "AC2 the default out dir is evals/results/gate-<sha12>" "$OUT" "evals/results/gate-$SHA12/"
assert_contains "AC3 a clean tree is reported" "$OUT" "tree: clean"
assert_eq "AC1 --dry-run makes no worktree" "1" "$(git -C "$R" worktree list | wc -l | tr -d ' ')"
g --cmd "bash /x/adapter.sh" --model m1 --dry-run
assert_not_contains "AC1 --dry-run with --cmd displays no --variant" "$OUT" "--variant"
g --harness claude --model m1 --dry-run
g --harness claude --model m1 --k 7 --scenarios E2,E3 --tasks pattern-01-option-value-label --max-cost 4 --timeout 600 --clean-env --dry-run
assert_contains "AC2 --k, --scenarios and pass-through flags reach the behaviour command" "$OUT" "--arm both --repeat 7 --scenarios E2,E3"
assert_contains "AC2 --tasks replaces the default tasks" "$OUT" "--tasks pattern-01-option-value-label"
assert_contains "AC2 --max-cost reaches the commands" "$OUT" "--max-cost 4"
assert_contains "AC2 --timeout reaches the commands" "$OUT" "--timeout 600"
assert_contains "AC2 --clean-env reaches the commands" "$OUT" "--clean-env"
g --harness claude --model m1 --scenarios E9 --dry-run
assert_rc "AC2 a scenario outside the AUTO list -> exit 2" 2
g --harness claude --model m1 --tasks nope-task --dry-run
assert_rc "AC2 an unknown task -> exit 2" 2

echo "AC6 --dry-run --json"
g --harness claude --model m1 --dry-run --json
assert_rc "AC6 --dry-run --json -> exit 0" 0
J="$(printf '%s' "$OUT" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);console.log([j.schema,j.commit,j.harness,j.model,j.k,j.scenarios.join(","),j.tasks.join(","),j.dry_run,j.commands.length,j.tree].join("|"))}catch(e){console.log("BAD "+e.message)}})')"
assert_eq "AC6 the JSON fields" "pb-gate/1|$SHA|claude|m1|5|E1,E2,E3|$TASKS|true|2|clean" "$J"
printf '%s\n' "$OUT" > "$W/dry.json"
assert_contains "AC1 (AC7') the JSON commands carry --variant" "$(gj "$W/dry.json" 'j.commands.join(" ")')" "--variant "

echo "AC3 a real run refuses changes to tracked files; untracked results do not count"
printf 'changed\n' >> "$R/evals/tasks/pattern-01-option-value-label/prompt.md"
: > "$CALLS"
g --harness claude --model m1
assert_rc "AC3 a changed tracked file -> exit 2" 2
assert_contains "AC3 the message says why" "$OUT" "not clean"
assert_eq "AC3 no runner ran" "0" "$(wc -l < "$CALLS" | tr -d ' ')"
g --harness claude --model m1 --dry-run
assert_rc "AC3 --dry-run on a dirty tree -> exit 0" 0
assert_contains "AC3 --dry-run reports the dirty tree" "$OUT" "tree: dirty"
git -C "$R" checkout -q -- .
printf 'new\n' > "$R/skills/new.md"
g --harness claude --model m1
assert_rc "AC3 an untracked file outside evals/results -> exit 2" 2
rm -f "$R/skills/new.md"

echo "AC2/AC4 a real run: both runners, then eval-delta on the pooled same-commit files"
OD="$R/evals/results/gate-$SHA12"
mkdir -p "$OD"
# a stale file from another commit and one of another model: listed, never pooled
printf '{"schema":"pb-evals/1","playbook_commit":"0000000000000000000000000000000000000000","harness":"claude","model":"m1","runs":[]}\n' > "$OD/old.json"
printf '{"schema":"pb-evals/1","playbook_commit":"%s","harness":"claude","model":"m2","runs":[]}\n' "$SHA" > "$OD/other-model.json"
printf 'not json\n' > "$OD/broken.json"
: > "$CALLS"
g --harness claude --model m1
assert_rc "AC4 every with run passes, every without run fails, no isolation FAIL -> exit 0" 0
assert_eq "AC2 run-evals.sh ran once" "1" "$(ncalls run-evals.sh)"
assert_eq "AC2 run-outcome.sh ran once" "1" "$(ncalls run-outcome.sh)"
assert_has_all "AC2 run-evals.sh got the gate's arguments (AC7': now with --variant)" "$(grep '^run-evals.sh ' "$CALLS")" "--harness claude" "--model m1" "--arm both --repeat 5" "--scenarios E1,E2,E3" "--out $OD/" "--variant "
assert_has_all "AC2 run-outcome.sh got the gate's arguments (AC7': now with --variant)" "$(grep '^run-outcome.sh ' "$CALLS")" "--harness claude" "--model m1" "--arm both --repeat 5" "--tasks $TASKS" "--out $OD/" "--variant "
assert_contains "AC4 the Newcombe table is printed" "$OUT" "## Δ with a 95% interval (Newcombe hybrid score)"
assert_contains "AC4 the per-arm Wilson table is printed" "$OUT" "## Per arm: passes/n and Wilson 95% interval"
assert_contains "AC4 an outcome task row is in the Δ table" "$OUT" "| pattern-26-consistent-price-rounding | x | 1.000 |"
assert_contains "AC4 a behaviour row is in the Δ table" "$OUT" "| E1 | x | 1.000 |"
assert_contains "AC4 the other commit is skipped with the reason" "$OUT" "skipped: $OD/old.json (other commit)"
assert_contains "AC4 the other model is skipped with the reason" "$OUT" "skipped: $OD/other-model.json (other model)"
assert_contains "AC4 a file that is not JSON is skipped with the reason" "$OUT" "skipped: $OD/broken.json (not a pb-evals/1 file)"
assert_eq "AC4 two files are pooled" "2" "$(printf '%s\n' "$OUT" | grep -c '^pooled: ')"

echo "AC4 --pool-only runs nothing and pools what is there (a second batch adds up)"
: > "$CALLS"
g --harness claude --model m1 --pool-only
assert_rc "AC4 --pool-only -> exit 0" 0
assert_eq "AC4 --pool-only calls no runner" "0" "$(wc -l < "$CALLS" | tr -d ' ')"
assert_eq "AC4 --pool-only pools the same two files" "2" "$(printf '%s\n' "$OUT" | grep -c '^pooled: ')"
g --harness claude --model m1
assert_eq "AC4 a second real run pools four files" "4" "$(printf '%s\n' "$OUT" | grep -c '^pooled: ')"
assert_contains "AC4 pooled n doubles (k=5 twice: 10/10)" "$OUT" "| E1 | x | with | 10/10 |"

echo "AC4 --pool-only with no matching file -> exit 2"
g --harness claude --model m9 --pool-only
assert_rc "AC4 nothing to pool -> exit 2" 2

echo "AC6 a real run with --json"
g --harness claude --model m1 --pool-only --json
assert_rc "AC6 --json -> exit 0" 0
J="$(printf '%s' "$OUT" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const j=JSON.parse(s);const r=j.rows.find(x=>x.scenario==="E1"&&x.check==="x");console.log([j.dry_run,j.pooled.length,j.skipped.length,j.delta_rc,r&&r.delta,r&&r.lo>0,r&&r.hi,r&&r.verdict].join("|"))}catch(e){console.log("BAD "+e.message)}})')"
assert_eq "AC6 rows from the Newcombe table, pooled and skipped lists" "false|4|3|0|1|true|1|Δ>0 (interval excludes 0)" "$J"

echo "AC4 a commit that shares the first 12 characters of HEAD but differs later is not pooled (full-SHA match only)"
NEAR="${SHA:0:12}$(printf '%s' "${SHA:12}" | tr '0-9a-f' '1-9a-f0')"
printf '{"schema":"pb-evals/1","playbook_commit":"%s","harness":"claude","model":"m1","runs":[]}\n' "$NEAR" > "$OD/near-sha.json"
g --harness claude --model m1 --pool-only
assert_rc "AC4 near-SHA fixture: --pool-only -> exit 0" 0
assert_eq "AC4 the near-SHA fixture differs from HEAD but shares its 12-char prefix" "${SHA:0:12}|1" "${NEAR:0:12}|$([ "$NEAR" != "$SHA" ] && echo 1)"
assert_contains "AC4 the near-SHA file is skipped as another commit" "$OUT" "skipped: $OD/near-sha.json (other commit)"
assert_eq "AC4 the near-SHA file is not pooled (still four files)" "4" "$(printf '%s\n' "$OUT" | grep -c '^pooled: ')"
rm -f "$OD/near-sha.json"

echo "AC5 runner exit codes: 1 and 4 continue, 2 and 3 stop"
for rc in 1 4; do
  : > "$CALLS"
  RC=0; OUT="$(cd "$R" && FAKE_RC_run_evals="$rc" bash tools/release-gate.sh --harness claude --model m1 2>&1)" || RC=$?
  assert_eq "AC5 run-evals.sh exit $rc: run-outcome.sh still runs" "1" "$(ncalls run-outcome.sh)"
  assert_contains "AC5 run-evals.sh exit $rc: the delta still prints" "$OUT" "## Δ with a 95% interval"
done
for rc in 2 3; do
  : > "$CALLS"
  RC=0; OUT="$(cd "$R" && FAKE_RC_run_evals="$rc" bash tools/release-gate.sh --harness claude --model m1 2>&1)" || RC=$?
  assert_rc "AC5 run-evals.sh exit $rc -> the gate exits $rc" "$rc"
  assert_eq "AC5 run-evals.sh exit $rc: run-outcome.sh does not run" "0" "$(ncalls run-outcome.sh)"
done

echo "AC1/AC4 --cmd: the harness label is custom"
: > "$CALLS"
g --cmd "bash /x/adapter.sh" --model m1
assert_rc "AC1 --cmd run -> exit 1 (AC7': no variant, verdict fail by AC2 (a); it was exit 0)" 1
assert_not_contains "AC1 --cmd: no --variant reaches run-evals.sh" "$(grep '^run-evals.sh ' "$CALLS")" "--variant"
assert_contains "AC1 --cmd reaches run-evals.sh" "$(grep '^run-evals.sh ' "$CALLS")" "--cmd bash /x/adapter.sh"
assert_contains "AC4 the claude files are skipped for a custom run" "$OUT" "(other harness)"

echo "m-b the default tasks are one top-level line of the gate"
assert_eq "m-b tools/release-gate.sh has a top-level DEFAULT_TASKS line with the three separating tasks" "1" \
  "$(grep -c '^DEFAULT_TASKS="pattern-15-erase-account-ambiguous,pattern-24-merge-duplicate-customers,pattern-26-consistent-price-rounding"$' "$GATE" 2>/dev/null || true)"

echo "AC1 a real run with --harness measures a detached worktree of HEAD: --variant DIR goes to both runners"
rcase ac1 ""
assert_rc "AC1 baseline run (variant ok, full set, k=5) -> exit 0" 0
BL="$(grep '^run-evals.sh ' "$CALLS")"; OL="$(grep '^run-outcome.sh ' "$CALLS")"
assert_contains "AC1 run-evals.sh gets --variant" "$BL" "--variant "
assert_contains "AC1 run-outcome.sh gets --variant" "$OL" "--variant "
VB="$(printf '%s' "$BL" | sed -n 's/.*--variant \([^ ]*\).*/\1/p')"
VO="$(printf '%s' "$OL" | sed -n 's/.*--variant \([^ ]*\).*/\1/p')"
assert_eq "AC1 the variant directory is named on the command line" "1" "$([ -n "$VB" ] && echo 1 || echo 0)"
assert_eq "AC1 both runners get the same directory" "$VB" "$VO"
for nm in run-evals.sh run-outcome.sh; do
  OB="$(grep "^OBS $nm " "$OBS")"
  assert_contains "AC1 $nm: while it runs, git -C DIR rev-parse HEAD is the gate commit" "$OB" "head=$SHA "
  assert_contains "AC1 $nm: while it runs, DIR's tracked files equal git ls-files of HEAD" "$OB" "tracked=1 "
  assert_contains "AC1 $nm: DIR holds exactly those files (no untracked results, no extras)" "$OB" "ondisk=1 "
  assert_contains "AC1 $nm: DIR has no change against its HEAD" "$OB" "changes=0 "
  assert_contains "AC1 $nm: DIR is a worktree entry of the repository" "$OB" "listed=1"
done
assert_no_path "AC1 DIR is removed after the run" "$VB"
assert_eq "AC1 no worktree entry is left (only the repository itself)" "1" "$(git -C "$R" worktree list | wc -l | tr -d ' ')"

echo "AC1 the worktree is removed also when a runner exits 2 or 3"
i=0
for spec in run_evals:2 run_evals:3 run_outcome:2 run_outcome:3; do
  i=$((i + 1)); who="${spec%%:*}"; want="${spec#*:}"
  rcase "ac1-rc$i" "FAKE_RC_$who=$want"
  assert_rc "AC1 $who exit $want -> the gate exits $want" "$want"
  VD="$(sed -n 's/.*--variant \([^ ]*\).*/\1/p' "$CALLS" | head -n 1)"
  assert_eq "AC1 $who exit $want: the variant directory was passed to the runner" "1" "$([ -n "$VD" ] && echo 1 || echo 0)"
  assert_no_path "AC1 $who exit $want: DIR is removed" "$VD"
  assert_eq "AC1 $who exit $want: no worktree entry is left" "1" "$(git -C "$R" worktree list | wc -l | tr -d ' ')"
done

echo "AC1 the worktree is removed when the gate gets TERM while a runner runs"
rm -f "$W/hang.started" "$W/hang.done" "$W/release"; : > "$OBS"; : > "$CALLS"
( cd "$R" && exec env FAKE_HANG=run-evals.sh HOME="$W/home" TMPDIR="$W/tmp" bash tools/release-gate.sh --harness claude --model m1 --out-dir evals/results/ac1-term ) > "$W/term.out" 2>&1 &
TP=$!
n=0; while [ ! -e "$W/hang.started" ] && [ "$n" -lt 300 ]; do sleep 0.1; n=$((n + 1)); done
assert_file "AC1 TERM: the fake runner is running" "$W/hang.started"
kill -TERM "$TP" 2>/dev/null
: > "$W/release"   # lets a fake that the gate leaves running finish; a gate that traps TERM has already acted
wait "$TP" 2>/dev/null
n=0; while [ ! -e "$W/hang.done" ] && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
VD="$(obs_dir_of run-evals.sh)"
assert_eq "AC1 TERM: the variant directory was passed to the runner" "1" "$([ -n "$VD" ] && echo 1 || echo 0)"
assert_no_path "AC1 TERM: DIR is removed" "$VD"
assert_eq "AC1 TERM: no worktree entry is left" "1" "$(git -C "$R" worktree list | wc -l | tr -d ' ')"

echo "AC1/AC2 --cmd passes no --variant, so its runs have no variant and the gate fails them"
: > "$OBS"; : > "$CALLS"
ge "" --cmd "bash /x/adapter.sh" --model m1 --out-dir evals/results/ac1-cmd
assert_rc "AC2 (a) a --cmd run has no variant -> verdict fail, exit 1" 1
assert_not_contains "AC1 --cmd: run-evals.sh gets no --variant" "$(grep '^run-evals.sh ' "$CALLS")" "--variant"
assert_not_contains "AC1 --cmd: run-outcome.sh gets no --variant" "$(grep '^run-outcome.sh ' "$CALLS")" "--variant"
assert_contains "AC1 --cmd: no worktree is made for the runners" "$(cat "$OBS")" "worktrees=1"
assert_eq "AC2' --cmd: gate.json says variant false" "false" "$(gj "$R/evals/results/ac1-cmd/gate.json" j.variant)"
assert_eq "AC2' --cmd: gate.json verdict is fail" "fail" "$(gj "$R/evals/results/ac1-cmd/gate.json" j.verdict)"

echo "AC2/AC2' pass: variant ok, full set, 5 graded per arm; gate.json with repo-relative paths"
rcase paths ""
assert_rc "AC2 pass: every rule holds -> exit 0" 0
assert_eq "AC2' gate.json schema" "pb-gate/1" "$(gj "$GJ" j.schema)"
assert_eq "AC2' gate.json commit" "$SHA" "$(gj "$GJ" j.commit)"
assert_eq "AC2' gate.json variant is true when (a) holds" "true" "$(gj "$GJ" j.variant)"
assert_eq "AC2' gate.json full_set is true" "true" "$(gj "$GJ" j.full_set)"
assert_eq "AC2' gate.json min_graded is the observed minimum (5)" "5" "$(gj "$GJ" j.min_graded)"
assert_eq "AC2' gate.json verdict is pass" "pass" "$(gj "$GJ" j.verdict)"
assert_eq "AC2' gate.json verdict_reasons is empty" "[]" "$(gj "$GJ" j.verdict_reasons)"
assert_eq "AC2' gate.json out_dir is repo-relative" "evals/results/paths" "$(gj "$GJ" 'j.out_dir.replace(/\/+$/,"")')"
assert_eq "AC2' gate.json pooled lists the two files, repo-relative" "2|true" "$(gj "$GJ" '[j.pooled.length,j.pooled.every(p=>p.indexOf("evals/results/paths/")===0)].join("|")')"
assert_eq "AC2' gate.json skipped is a list" "true" "$(gj "$GJ" 'Array.isArray(j.skipped)')"

echo "AC2' committed set: only *.json, *.md and .gitignore; no local path in them (m-d: POSIX and Windows forms)"
LIST="$(git -C "$R" add -n -A -- "evals/results/paths" 2>&1 | sed -n "s/^add '\(.*\)'\$/\1/p")"
assert_contains "AC2' the committed set holds gate.json" "$LIST" "evals/results/paths/gate.json"
assert_contains "AC2' the committed set holds .gitignore" "$LIST" "evals/results/paths/.gitignore"
assert_eq "AC2' the committed set holds the behaviour json and md" "1|1" "$(printf '%s\n' "$LIST" | grep -c '^evals/results/paths/behaviour-[^/]*\.json$')|$(printf '%s\n' "$LIST" | grep -c '^evals/results/paths/behaviour-[^/]*\.md$')"
assert_eq "AC2' the committed set holds the outcome json and md" "1|1" "$(printf '%s\n' "$LIST" | grep -c '^evals/results/paths/outcome-[^/]*\.json$')|$(printf '%s\n' "$LIST" | grep -c '^evals/results/paths/outcome-[^/]*\.md$')"
assert_eq "AC2' nothing else is in the committed set (no *.evidence, *.runs, *.log)" "0" "$(printf '%s\n' "$LIST" | grep -Ev '(\.json|\.md)$|/\.gitignore$' | grep -c . || true)"
EVD="$(cd "$ODN" && ls -d behaviour-*.evidence 2>/dev/null | head -n 1)"; RND="$(cd "$ODN" && ls -d behaviour-*.runs 2>/dev/null | head -n 1)"; LGF="$(cd "$ODN" && ls behaviour-*.log 2>/dev/null | head -n 1)"
assert_eq "AC2' the runner evidence is on disk (the gate does not delete it)" "1" "$([ -f "$ODN/$EVD/ev.txt" ] && [ -f "$ODN/$RND/r.md" ] && [ -f "$ODN/$LGF" ] && echo 1 || echo 0)"
for f in "$EVD/ev.txt" "$EVD/inner.json" "$RND/r.md" "$LGF"; do
  if git -C "$R" check-ignore -q -- "evals/results/paths/$f"; then t_ok "AC2' ignored: $(printf '%s' "$f" | sed 's/[0-9TZ-]\{10,\}/<stamp>/')"; else t_bad "AC2' ignored: $f" "git check-ignore says it would be committed"; fi
done
BJ="$(cd "$ODN" && ls behaviour-*.json 2>/dev/null | head -n 1)"; BM="$(cd "$ODN" && ls behaviour-*.md 2>/dev/null | head -n 1)"
for f in gate.json .gitignore "$BJ" "$BM"; do
  if git -C "$R" check-ignore -q -- "evals/results/paths/$f"; then t_bad "AC2' not ignored: $f" "git check-ignore says it is ignored"; else t_ok "AC2' not ignored: $(printf '%s' "$f" | sed 's/[0-9TZ-]\{10,\}/<stamp>/')"; fi
done
FORMS=("$W"); WIN=0
if command -v cygpath >/dev/null 2>&1; then
  WM="$(cygpath -m "$W")"; WW="$(cygpath -w "$W")"; FORMS+=("$WM" "$WW" "${WW//\\/\\\\}"); WIN=1
fi
LEAK=""
for f in $LIST; do
  for form in "${FORMS[@]}"; do grep -qF -- "$form" "$R/$f" 2>/dev/null && LEAK="$LEAK [$form in $(printf '%s' "$f" | sed 's/[0-9TZ-]\{10,\}/<stamp>/')]"; done
done
assert_eq "AC2' no temp dir, home or repo path (POSIX form) in the committed files" "" "$LEAK"
if [ "$WIN" = 1 ]; then t_ok "AC2' (m-d) the Windows forms of the temp dir and home were looked for too"; else t_skip 1 "AC2' (m-d) Windows path forms need cygpath (Git Bash); the POSIX form is checked above"; fi
assert_eq "AC2' the rewrite keeps playbook_commit, variant sha, version, end_check and the run count" "$SHA|$SHA|0.30.0|ok|30" \
  "$(gj "$ODN/$BJ" '[j.playbook_commit,j.variant&&j.variant.sha,j.variant&&j.variant.version,j.variant&&j.variant.end_check,j.runs.length].join("|")')"
assert_eq "AC2' the rewrite keeps runs and checks" "E1.with.1|PASS|E1.without.1|FAIL" \
  "$(gj "$ODN/$BJ" '[j.runs[0].label,j.runs[0].checks[0].result,j.runs[1].label,j.runs[1].checks[0].result].join("|")')"
assert_eq "AC2' variant.tree is still a string (a relative path or a placeholder)" "string" "$(gj "$ODN/$BJ" 'typeof j.variant.tree')"

echo "AC13 the path rewrite replaces a path only as a whole path prefix (/tmpfoo and <ROOT>-other stay; a path before / quote space ) or the end is replaced)"
rcase edge "FAKE_EDGE=1"
assert_rc "AC13 fixture: the run with edge strings passes -> exit 0" 0
EM="$(cat "$ODN"/behaviour-*.md 2>/dev/null)"
assert_contains "AC13 a string that only starts with the temp dir (/tmpfoo) is not rewritten" "$EM" "edge-neg-tmp: $W/tmpfoo/x"
assert_contains "AC13 a string that only starts with the repo root (<ROOT>-other) is not rewritten" "$EM" "edge-neg-root: $R-other/y"
assert_contains "AC13 a string that only starts with HOME (/homework) is not rewritten" "$EM" "edge-neg-home: $W/homework/z"
assert_contains "AC13 temp dir followed by / -> <tmp>/" "$EM" "edge-pos-tmp-slash: <tmp>/p1"
assert_contains "AC13 temp dir followed by a quote -> <tmp>" "$EM" 'edge-pos-tmp-quote: "<tmp>"'
assert_contains "AC13 temp dir followed by whitespace -> <tmp>" "$EM" "edge-pos-tmp-space: <tmp> tail"
assert_contains "AC13 temp dir followed by ) -> <tmp>" "$EM" "edge-pos-tmp-paren: (<tmp>)"
assert_contains "AC13 temp dir at the end of the line -> <tmp>" "$EM" "edge-pos-tmp-end: <tmp>"
assert_contains "AC13 repo root followed by / -> relative path" "$EM" "edge-pos-root-slash: evals/z"
assert_contains "AC13 repo root followed by a quote -> ." "$EM" 'edge-pos-root-quote: "."'
assert_contains "AC13 repo root at the end of the line -> ." "$EM" "edge-pos-root-end: ."
assert_contains "AC13 HOME at the end of the line -> <home>" "$EM" "edge-pos-home-end: <home>"
assert_contains "AC13' temp dir followed by , is rewritten" "$EM" 'edge-pos-tmp-comma: a <tmp>, b'
assert_contains "AC13' temp dir followed by ; is rewritten" "$EM" 'edge-pos-tmp-semi: x=<tmp>;'
assert_contains "AC13' temp dir followed by : is rewritten" "$EM" 'edge-pos-tmp-colon: <tmp>:other'
assert_contains "AC13' temp dir followed by ] is rewritten" "$EM" 'edge-pos-tmp-bracket: [<tmp>]'
assert_contains "AC13' temp dir followed by } is rewritten" "$EM" 'edge-pos-tmp-brace: {<tmp>}'
assert_contains "AC13' temp dir followed by > is rewritten" "$EM" 'edge-pos-tmp-gt: <<tmp>>'
assert_contains "AC13' temp dir followed by a backtick is rewritten" "$EM" 'edge-pos-tmp-tick: `<tmp>`'
assert_contains "AC13' temp dir followed by a sentence-end dot at the end of the line is rewritten" "$EM" 'edge-pos-tmp-dot-end: see <tmp>.'
assert_contains "AC13' temp dir followed by a sentence-end dot and a space is rewritten" "$EM" 'edge-pos-tmp-dot-space: see <tmp>. Next'
assert_contains "AC13' repo root followed by , is rewritten" "$EM" 'edge-pos-root-comma: .,'
assert_contains "AC13' repo root followed by ] is rewritten" "$EM" 'edge-pos-root-bracket: [.]'
assert_contains "AC13' repo root followed by a sentence-end dot is rewritten" "$EM" 'edge-pos-root-dot-end: see ..'
assert_contains "AC13' HOME followed by , is rewritten" "$EM" 'edge-pos-home-comma: <home>, x'
assert_contains "AC13' HOME followed by ; is rewritten" "$EM" 'edge-pos-home-semi: <home>;'
assert_contains "AC13' /tmp-x (dash) is not rewritten" "$EM" "edge-neg-tmp-dash: $W/tmp-x"
assert_contains "AC13' /tmp_x (underscore) is not rewritten" "$EM" "edge-neg-tmp-under: $W/tmp_x"
assert_contains "AC13' /tmp.d (dot and a letter) is not rewritten" "$EM" "edge-neg-tmp-dotname: $W/tmp.d"
assert_contains "AC13' <ROOT>-x (dash) is not rewritten" "$EM" "edge-neg-root-dash: $R-x"
assert_contains "AC13' <ROOT>_x (underscore) is not rewritten" "$EM" "edge-neg-root-under: ${R}_x"
assert_contains "AC13' <ROOT>.d (dot and a letter) is not rewritten" "$EM" "edge-neg-root-dotname: $R.d"
assert_contains "AC13' HOME-x (dash) is not rewritten" "$EM" "edge-neg-home-dash: $W/home-x"
assert_contains "AC13' HOME.d (dot and a letter) is not rewritten" "$EM" "edge-neg-home-dotname: $W/home.d"
EJ="$(cat "$ODN"/behaviour-*.json 2>/dev/null)"
assert_contains "AC13' json: temp dir followed by , is rewritten" "$EJ" '"<tmp>,"'
assert_contains "AC13' json: temp dir followed by ; is rewritten" "$EJ" '"<tmp>;"'
assert_contains "AC13' json: temp dir followed by ] is rewritten" "$EJ" '"<tmp>]"'
assert_contains "AC13' json: /tmp-x is not rewritten" "$EJ" "\"$W/tmp-x\""
assert_contains "AC13' json: /tmp_x is not rewritten" "$EJ" "\"$W/tmp_x\""
assert_contains "AC13' json: /tmp.d is not rewritten" "$EJ" "\"$W/tmp.d\""
ODN="$R/evals/results/paths"; GJ="$ODN/gate.json"   # the later AC2' sections read the "paths" run

echo "AC2' --pool-only writes gate.json too, runs no runner, and the rewritten files still pass"
rm -f "$GJ"; : > "$OBS"
ge "" --harness claude --model m1 --out-dir evals/results/paths --pool-only
assert_rc "AC2' --pool-only on a passing dir -> exit 0" 0
assert_eq "AC2' --pool-only writes gate.json with verdict pass" "pass" "$(gj "$GJ" j.verdict)"
assert_eq "AC2' --pool-only runs no runner and makes no worktree" "0" "$(wc -l < "$OBS" | tr -d ' ')"
rcase paths ""
assert_rc "AC2 a second batch on the same commit -> exit 0" 0
assert_eq "AC2' min_graded adds up over batches (5 + 5)" "10" "$(gj "$GJ" j.min_graded)"
assert_eq "AC2' four files are pooled" "4" "$(gj "$GJ" j.pooled.length)"
rcase jsonrun "" --json
assert_rc "AC2' --json run -> exit 0" 0
assert_eq "AC2' a --json run writes gate.json as well" "pass" "$(gj "$GJ" j.verdict)"

echo "AC2 (a) every pooled file needs a variant object, end_check ok and variant.sha = the gate commit"
fail_case a-null "FAKE_VARIANT=null" "variant|end_check"
assert_eq "AC2' a-null: gate.json variant is false" "false" "$(gj "$GJ" j.variant)"
rm -f "$GJ"
ge "" --harness claude --model m1 --out-dir evals/results/a-null --pool-only
assert_rc "AC2' --pool-only on a failing dir -> exit 1" 1
assert_eq "AC2' --pool-only on a failing dir writes verdict fail" "fail" "$(gj "$GJ" j.verdict)"
fail_case a-nullsha "FAKE_VARIANT=nullsha" "variant|end_check"
fail_case a-badsha "FAKE_VARIANT=badsha" "variant|end_check"
fail_case a-changed "FAKE_VARIANT=changed" "variant|end_check"
mkdir -p "$R/evals/results/a-extra"
printf '{"schema":"pb-evals/1","playbook_commit":"%s","playbook_version":"0.30.0","harness":"claude","model":"m1","arms":["with","without"],"repeat":1,"variant":null,"runs":[]}\n' "$SHA" > "$R/evals/results/a-extra/seed.json"
fail_case a-extra "" "variant|end_check"

echo "AC2 (b) the full AUTO set (read from the fixture's evals/run-evals.sh) and the three default tasks"
fail_case b-subset "" "$(idre E1)" --scenarios E2,E3
assert_eq "AC2' b-subset: gate.json full_set is false" "false" "$(gj "$GJ" j.full_set)"
fail_case b-tasks "" "pattern-15-erase-account-ambiguous" --tasks pattern-01-option-value-label
assert_eq "AC2' b-tasks: gate.json full_set is false" "false" "$(gj "$GJ" j.full_set)"
fail_case b-skip "FAKE_SKIP=E3" "$(idre E3)"
fail_case b-skip-task "FAKE_SKIP=pattern-24-merge-duplicate-customers" "pattern-24-merge-duplicate-customers"
R2="$W/repo2"
git clone -q "$R" "$R2" && ( cd "$R2" && git config user.email t@example.invalid && git config user.name tester && git config commit.gpgsign false &&
  git config core.autocrlf false && sed 's/^GATE_SCENARIOS="E1 E2 E3"$/GATE_SCENARIOS="E1 E2 E3 E4"/' tools/release-gate.sh > "$W/auto.tmp" && cat "$W/auto.tmp" > tools/release-gate.sh &&
  git add -A && git commit -qm "GATE_SCENARIOS gains E4" ) || t_bad "fixture repo 2" "clone or commit failed"
assert_eq "AC14'' fixture: repo 2's gate line gained E4 (AC7'': the b-auto case is now GATE_SCENARIOS, not AUTO)" "1" "$(grep -c '^GATE_SCENARIOS="E1 E2 E3 E4"$' "$R2/tools/release-gate.sh")"
# AC14'' (S6 revision 2): the AUTO check covers the list in use (here --scenarios E1,E2,E3, all in AUTO), so a GATE_SCENARIOS id that is
# only in the gate line is a verdict failure (exit 1, "full set: no runs for E4"), not a usage error (exit 2).
GR="$R2"; fail_case b-auto "" "$(idre E4)" --scenarios E1,E2,E3; GR=""
assert_eq "AC14'' b-auto: the reason is exactly 'full set: no runs for E4' (it is the gate line that gained E4)" "full set: no runs for E4" "$(gj "$R2/evals/results/b-auto/gate.json" 'j.verdict_reasons[0]')"

echo "AC2 (c) at least 5 graded runs per (item, arm); ERROR runs do not count; another batch fixes it"
fail_case c-err "FAKE_ERR=E1:without:1" "$(idre E1)"
assert_eq "AC2' c-err: min_graded is the observed minimum (4)" "4" "$(gj "$GJ" j.min_graded)"
assert_eq "AC2' c-err: the set is complete, so full_set is true" "true" "$(gj "$GJ" j.full_set)"
ge "" --harness claude --model m1 --out-dir evals/results/c-err
assert_rc "AC2 c-err: a second clean batch pooled -> exit 0" 0
assert_eq "AC2 c-err: verdict pass after the second batch" "pass" "$(gj "$GJ" j.verdict)"
assert_eq "AC2' c-err: min_graded is 4 + 5 = 9 for the item that had an ERROR" "9" "$(gj "$GJ" j.min_graded)"

echo "AC2 (d) tools/eval-delta.sh must exit 0 on the pooled files"
fail_case d-iso "FAKE_ISOFAIL=E1" "eval-delta|isolation"

echo "AC2 (e) no Δ row with its 95% interval wholly below 0"
fail_case e-neg "FAKE_INVERT=E2" "$(idre E2)"

echo "AC4 (v0.33.0) a real run passes --hooks to the behaviour runner (claude and --cmd, not codex and opencode); rule (a) needs hooks true"
rcase hk-claude ""
assert_rc "AC4 claude real run with hooks true -> exit 0" 0
assert_contains "AC4 claude: run-evals.sh got --hooks" "$(grep '^run-evals.sh ' "$CALLS")" " --hooks"
: > "$CALLS"
ge "" --harness codex --model m1 --out-dir evals/results/hk-codex
assert_rc "AC4' codex real run -> exit 0 (no hooks clause)" 0
assert_not_contains "AC4' codex: run-evals.sh got no --hooks" "$(grep '^run-evals.sh ' "$CALLS")" "--hooks"
ge "FAKE_HOOKS=false" --harness codex --model m1 --out-dir evals/results/hk-codex2
assert_rc "AC4' codex run whose file says hooks false -> exit 0 (clause is claude and --cmd only)" 0
: > "$CALLS"
ge "" --harness opencode --model m1 --out-dir evals/results/hk-opencode
assert_not_contains "AC4' opencode: run-evals.sh got no --hooks" "$(grep '^run-evals.sh ' "$CALLS")" "--hooks"
: > "$CALLS"
ge "" --cmd "bash /x/adapter.sh" --model m1 --out-dir evals/results/hk-cmd
assert_contains "AC4 --cmd: run-evals.sh got --hooks" "$(grep '^run-evals.sh ' "$CALLS")" " --hooks"
fail_case hk-off "FAKE_HOOKS=false" "hooks off in .*behaviour-"
fail_case hk-none "FAKE_HOOKS=none" "hooks off in .*behaviour-"

echo "AC7 preflight: a real gate run asks each runner (--preflight, same selection) before the first runner starts; a refusal exits 3 and starts nothing"
# pf_real: the non-preflight lines of $CALLS, and the line numbers of the first real run and the last preflight
pf_real() { grep -v -- ' --preflight' "$CALLS" | grep -c . || true; }
rcase pf-ok ""
assert_rc "AC7 both preflights ready -> the run goes on, exit 0" 0
assert_eq "AC7 run-evals.sh was asked --preflight once" "1" "$(grep '^run-evals.sh ' "$CALLS" | grep -c -- ' --preflight')"
assert_eq "AC7 run-outcome.sh was asked --preflight once" "1" "$(grep '^run-outcome.sh ' "$CALLS" | grep -c -- ' --preflight')"
assert_eq "AC7 and both runners ran after that (one real call each)" "1 1" "$(ncalls run-evals.sh) $(ncalls run-outcome.sh)"
PF_LAST="$(grep -n -- ' --preflight' "$CALLS" | tail -n 1 | cut -d: -f1)"
PF_FIRSTREAL="$(grep -vn -- ' --preflight' "$CALLS" | head -n 1 | cut -d: -f1)"
if [ -n "$PF_LAST" ] && [ -n "$PF_FIRSTREAL" ] && [ "$PF_LAST" -lt "$PF_FIRSTREAL" ]; then t_ok "AC7 both runners were preflighted before the first real run started"; else t_bad "AC7 both runners were preflighted before the first real run started" "last preflight line [$PF_LAST], first real line [$PF_FIRSTREAL]: $(cat "$CALLS")"; fi
PFE="$(grep '^run-evals.sh ' "$CALLS" | grep -- ' --preflight')"; PFO="$(grep '^run-outcome.sh ' "$CALLS" | grep -- ' --preflight')"
assert_has_all "AC7 the run-evals.sh preflight carries the selection (harness, scenarios)" "$PFE" "--harness claude" "--scenarios E1,E2,E3"
assert_has_all "AC7 the run-outcome.sh preflight carries the selection (harness, tasks)" "$PFO" "--harness claude" "--tasks pattern-15-erase-account-ambiguous,pattern-24-merge-duplicate-customers,pattern-26-consistent-price-rounding"
: > "$CALLS"
ge "" --cmd "bash /x/adapter.sh" --model m1 --out-dir evals/results/pf-ok-cmd2
assert_contains "AC7 --cmd: the run-outcome.sh preflight carries --cmd and the tasks" "$(grep '^run-outcome.sh ' "$CALLS" | grep -- ' --preflight')" "--cmd bash /x/adapter.sh"
for who in run-evals.sh run-outcome.sh; do
  rcase "pf-fail-$who" "FAKE_PF_FAIL=$who"
  assert_rc "AC7 $who refuses (exit 3) -> the gate exits 3" 3
  assert_contains "AC7 $who refuses: the output carries the runner's reason" "$OUT" "$who cannot start (fake: python3 is required)"
  assert_eq "AC7 $who refuses: no runner started (zero non-preflight calls)" "0" "$(pf_real)"
  assert_eq "AC7 $who refuses: no worktree entry is left" "1" "$(git -C "$R" worktree list | wc -l | tr -d ' ')"
  if [ -f "$GJ" ]; then assert_not_contains "AC7 $who refuses: gate.json is not a pass verdict" "$(cat "$GJ")" '"verdict": "pass"'; else t_ok "AC7 $who refuses: no gate.json is written"; fi
  assert_eq "AC7 $who refuses: no results file of a runner exists" "0" "$(ls "$ODN" 2>/dev/null | grep -c '^behaviour-\|^outcome-')"
done
rcase pf-fail-outcome-only "FAKE_PF_FAIL=run-outcome.sh"
assert_eq "AC7 run-outcome.sh alone refuses: run-evals.sh did not start either (nothing is spent before the outcome runner is known to start)" "0" "$(ncalls run-evals.sh)"
: > "$CALLS"
ge "FAKE_PF_FAIL=run-outcome.sh" --harness claude --model m1 --dry-run
assert_rc "AC7 --dry-run does not preflight (it starts nothing) -> exit 0" 0
ge "FAKE_PF_FAIL=run-outcome.sh" --harness claude --model m1 --pool-only --out-dir evals/results/pf-pool
assert_eq "AC7 --pool-only calls no runner, preflight included" "0" "$(wc -l < "$CALLS" | tr -d ' ')"

echo "R1-3 a real run resolves the baseline before any paid run: state noqual exits 3 with the reason and starts no runner"
R5="$W/repo5"
git clone -q "$R" "$R5" && ( cd "$R5" && git config user.email t@example.invalid && git config user.name tester && git config commit.gpgsign false &&
  git config core.autocrlf false && mkdir -p evals/results/gate-000000000000 &&
  printf '{"schema":"pb-evals/1","playbook_commit":"0000000000000000000000000000000000000000","harness":"claude","model":"m2","runs":[],"summary":[]}\n' > evals/results/gate-000000000000/behaviour-m2.json &&
  git add -A && git commit -qm "an earlier gate for another model" && git tag v0.32.0 && printf 'more\n' > more.txt && git add -A && git commit -qm "after the tag" ) || t_bad "fixture repo 5" "clone or commit failed"
assert_eq "R1-3 fixture: repo 5 has tag v0.32.0 on a commit that holds a gate dir (model m2 only)" "v0.32.0" "$(git -C "$R5" tag -l 'v*')"
GR="$R5"
rcase r13-noqual ""
assert_rc "R1-3 baseline state noqual (tag v0.32.0 holds a gate for model m2 only), real run for m1 -> exit 3" 3
assert_contains "R1-3 the reason is printed (exact text)" "$OUT" "no qualifying previous release gate for harness claude model m1"
assert_eq "R1-3 no runner was started (zero non-preflight calls; nothing was spent)" "0" "$(pf_real_calls)"
assert_eq "R1-3 no results file of a runner exists" "0" "$(ls "$ODN" 2>/dev/null | grep -c '^behaviour-\|^outcome-')"
assert_eq "R1-3 no worktree entry is left" "1" "$(git -C "$R5" worktree list | wc -l | tr -d ' ')"
rcase r13-noqual-cmd ""
GR=""

echo "AC14 the gate scope: GATE_SCENARIOS is a top-level line of the gate (KEEP and INCONCLUSIVE scenarios of docs/delta-audit.md plus the gate: safety rows E8 and E33, v0.33.0 AC3)"
assert_eq "AC14 tools/release-gate.sh has the top-level GATE_SCENARIOS line" "1" \
  "$(grep -c '^GATE_SCENARIOS="E2 E3 E4 E6 E8 E13 E14 E24 E26 E29 E33 E34"$' "$GATE" 2>/dev/null || true)"

# R3: its fake AUTO is E1..E5, its GATE_SCENARIOS is E2 E3: the default list, the AUTO check and the verdict can be told apart.
R3="$W/repo3"
git clone -q "$R" "$R3" && ( cd "$R3" && git config user.email t@example.invalid && git config user.name tester && git config commit.gpgsign false &&
  git config core.autocrlf false && sed 's/^AUTO="E1 E2 E3"$/AUTO="E1 E2 E3 E4 E5"/' evals/run-evals.sh > "$W/auto3.tmp" && cat "$W/auto3.tmp" > evals/run-evals.sh &&
  gate_scen tools/release-gate.sh "E2 E3" && git add -A && git commit -qm "scope: AUTO E1..E5, GATE_SCENARIOS E2 E3" ) || t_bad "fixture repo 3" "clone or commit failed"
assert_eq "AC14 fixture: repo 3 has AUTO E1..E5 and GATE_SCENARIOS E2 E3" "1|1" \
  "$(grep -c '^AUTO="E1 E2 E3 E4 E5"$' "$R3/evals/run-evals.sh")|$(grep -c '^GATE_SCENARIOS="E2 E3"$' "$R3/tools/release-gate.sh")"
GR="$R3"
ge "" --harness claude --model m1 --dry-run
assert_rc "AC14 --dry-run with GATE_SCENARIOS E2 E3 (AUTO E1..E5) -> exit 0" 0
RE="$(printf '%s\n' "$OUT" | grep 'evals/run-evals.sh')"
assert_contains "AC14 --dry-run: the behaviour command carries the GATE_SCENARIOS list" "$RE" "--scenarios E2,E3"
assert_not_contains "AC14 --dry-run: the AUTO-only scenario E1 is not in the behaviour command" "$RE" "E1"
assert_not_contains "AC14 --dry-run: the AUTO-only scenario E5 is not in the behaviour command" "$RE" "E5"
ge "" --harness claude --model m1 --dry-run --json
assert_rc "AC14 --dry-run --json -> exit 0" 0
printf '%s\n' "$OUT" > "$W/dry3.json"
assert_eq "AC14 --json: scenarios is the GATE_SCENARIOS list, not AUTO" "E2,E3" "$(gj "$W/dry3.json" 'j.scenarios.join(",")')"
ge "" --harness claude --model m1 --scenarios E1,E4 --dry-run --json
assert_rc "AC14 an explicit --scenarios (E1,E4: in AUTO, not in GATE_SCENARIOS) -> exit 0" 0
printf '%s\n' "$OUT" > "$W/dry3b.json"
assert_eq "AC14 an explicit --scenarios still overrides the default" "E1,E4" "$(gj "$W/dry3b.json" 'j.scenarios.join(",")')"
rcase ac14-real ""
assert_rc "AC14 a real run on the default list (the fakes run E2,E3 and the tasks) -> exit 0" 0
RE="$(grep '^run-evals.sh ' "$CALLS")"
assert_contains "AC14 a real run: run-evals.sh gets the GATE_SCENARIOS list as --scenarios" "$RE" "--scenarios E2,E3"
assert_not_contains "AC14 a real run: run-evals.sh does not get the AUTO-only scenario E5" "$RE" "E5"
assert_eq "AC14 a real run: gate.json verdict is pass" "pass" "$(gj "$GJ" j.verdict)"
GR=""

echo "AC15 verdict rule (b): GATE_SCENARIOS and the default tasks, not the whole AUTO list"
GR="$R3"
rcase ac15-pass "" --scenarios E2,E3
assert_rc "AC15 pooled runs cover GATE_SCENARIOS (E2,E3) and the tasks but not every AUTO scenario -> exit 0" 0
assert_eq "AC15 gate.json verdict is pass" "pass" "$(gj "$GJ" j.verdict)"
assert_eq "AC15 gate.json full_set (the gate set) is true" "true" "$(gj "$GJ" j.full_set)"
rcase ac15-extra "" --scenarios E1,E2,E3
assert_rc "AC15 extra scenarios (E1) beside the gate set are allowed -> exit 0" 0
assert_eq "AC15 extra scenarios: gate.json verdict is pass" "pass" "$(gj "$GJ" j.verdict)"
rcase ac15-miss "" --scenarios E2
assert_rc "AC15 a GATE_SCENARIOS id without runs (E3) -> exit 1" 1
assert_eq "AC15 gate.json verdict is fail" "fail" "$(gj "$GJ" j.verdict)"
assert_eq "AC15 the one reason names exactly the missing gate id (not the AUTO-only ids)" "full set: no runs for E3" "$(gj "$GJ" 'j.verdict_reasons.join("|")')"
assert_eq "AC15 gate.json full_set is false" "false" "$(gj "$GJ" j.full_set)"
rcase ac15-task "" --scenarios E2,E3 --tasks pattern-01-option-value-label
assert_rc "AC15 a default task without runs -> exit 1 (rule (b) still needs DEFAULT_TASKS)" 1
assert_contains "AC15 the reason names the missing task" "$(gj "$GJ" 'j.verdict_reasons.join("|")')" "pattern-15-erase-account-ambiguous"
GR=""

echo "AC14' every id of GATE_SCENARIOS is checked against AUTO (usage error, exit 2) as --scenarios is; the gate never reads docs/delta-audit.md"
R4="$W/repo4"
git clone -q "$R3" "$R4" && ( cd "$R4" && git config user.email t@example.invalid && git config user.name tester && git config commit.gpgsign false &&
  git config core.autocrlf false && gate_scen tools/release-gate.sh "E2 E9" && git add -A && git commit -qm "GATE_SCENARIOS names E9, which is not in AUTO" ) || t_bad "fixture repo 4" "clone or commit failed"
assert_eq "AC14' fixture: repo 4 gate line names E9 (not in its AUTO E1..E5)" "1|0" "$(grep -c '^GATE_SCENARIOS="E2 E9"$' "$R4/tools/release-gate.sh")|$(grep -c 'E9' "$R4/evals/run-evals.sh")"
assert_eq "AC14' fixture repos have no docs/delta-audit.md" "no" "$([ -e "$R4/docs/delta-audit.md" ] && echo yes || echo no)"
GR="$R4"
ge "" --harness claude --model m1 --dry-run
assert_rc "AC14' --dry-run with a GATE_SCENARIOS id outside AUTO -> exit 2" 2
assert_contains "AC14' --dry-run: the message names the scenario and the AUTO list" "$OUT" "scenario E9 is not in the AUTO list of evals/run-evals.sh"
ge "" --harness claude --model m1 --dry-run --json
assert_rc "AC14' --dry-run --json with such an id -> exit 2" 2
assert_contains "AC14' --dry-run --json: the same message" "$OUT" "scenario E9 is not in the AUTO list of evals/run-evals.sh"
: > "$CALLS"
ge "" --harness claude --model m1 --out-dir evals/results/ac14-bad
assert_rc "AC14' a real run with such an id -> exit 2" 2
assert_contains "AC14' a real run: the same message" "$OUT" "scenario E9 is not in the AUTO list of evals/run-evals.sh"
assert_eq "AC14' a real run: no runner ran (nothing was spent)" "0" "$(wc -l < "$CALLS" | tr -d ' ')"
ge "" --harness claude --model m1 --scenarios E1,E2 --dry-run
assert_rc "AC14'' with an explicit --scenarios the check covers that list only (E1,E2 in AUTO) -> exit 0" 0
ge "" --harness claude --model m1 --scenarios E1,E9 --dry-run
assert_rc "AC14'' an explicit --scenarios with an id outside AUTO -> exit 2" 2
assert_contains "AC14'' ... the message names E9" "$OUT" "scenario E9 is not in the AUTO list of evals/run-evals.sh"
GR=""

echo "AC1 the help text"
RC=0; OUT="$(bash "$GATE" --help 2>&1)" || RC=$?
assert_rc "AC1 --help -> exit 2" 2
assert_contains "AC1 the help names --pool-only" "$OUT" "--pool-only"

t_summary
