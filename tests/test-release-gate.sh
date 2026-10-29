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
[ -f "$GATE" ] && cp -p "$GATE" "$R/tools/release-gate.sh"
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
# FAKE_ISOFAIL=ID (the without-arm isolation check FAILs for that item), FAKE_HANG=NAME (waits for $W/release).
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
      st=graded; er=null; cks="{\"name\":\"x\",\"key\":\"x\",\"result\":\"$r\"}"
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
printf 'x\n' > "${out%.md}.evidence/ev.txt"; printf '{"schema":"pb-evals/1"}\n' > "${out%.md}.evidence/inner.json"
printf 'x\n' > "${out%.md}.runs/r.md"; printf 'log\n' > "${out%.md}.log"
printf '{"schema":"pb-evals/1","playbook_commit":"%s","playbook_version":"0.30.0","harness":"%s","model":"%s","arms":["with","without"],"repeat":%s,"max_cost":null,"interactive":false,"started":"2026-10-27T10:00:00Z","workroot":"%s","out":"%s","home_note":"%s/.claude","repo_note":"%s/evals"%s,"variant":%s,"runs":[%s],"summary":[]}\n' \
  "$commit" "$harness" "$model" "$k" "$wr" "$out" "$HOME" "$repo" "$winj" "$vj" "$runs" > "${out%.md}.json"
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
ncalls() { grep -c "^$1 " "$CALLS" 2>/dev/null || true; }
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
assert_has_all "AC2 the behaviour command: AUTO set, both arms, k=5 (AC7': now with --variant)" "$(printf '%s\n' "$OUT" | grep 'evals/run-evals.sh')" "evals/run-evals.sh" "--harness claude" "--model m1" "--arm both --repeat 5" "--scenarios E1,E2,E3" "--variant "
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
  git config core.autocrlf false && sed 's/^AUTO="E1 E2 E3"$/AUTO="E1 E2 E3 E4"/' evals/run-evals.sh > "$W/auto.tmp" && cat "$W/auto.tmp" > evals/run-evals.sh &&
  git add -A && git commit -qm "AUTO gains E4" ) || t_bad "fixture repo 2" "clone or commit failed"
GR="$R2"; fail_case b-auto "" "$(idre E4)" --scenarios E1,E2,E3; GR=""

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

echo "AC1 the help text"
RC=0; OUT="$(bash "$GATE" --help 2>&1)" || RC=$?
assert_rc "AC1 --help -> exit 2" 2
assert_contains "AC1 the help names --pool-only" "$OUT" "--pool-only"

t_summary
