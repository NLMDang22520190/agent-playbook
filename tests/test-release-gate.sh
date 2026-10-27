#!/usr/bin/env bash
# Tests for tools/release-gate.sh (v0.30.0 lane g, queue P0-3, spec AC1-AC6): the reproducible release gate runs the AUTO
# scenarios and the separating outcome tasks in both arms, k >= 5, on the exact HEAD commit, and pools only same-commit
# results through tools/eval-delta.sh. The tool is copied into a throw-away repo whose evals/run-evals.sh and
# evals/run-outcome.sh are RECORDING fakes that write synthetic pb-evals/1 files; tools/eval-delta.sh is the real one.
# Never calls a real harness.
. "$(dirname "$0")/lib.sh"
GATE="$PB_ROOT/tools/release-gate.sh"
command -v node >/dev/null 2>&1 || { t_skip 1 "node missing"; t_summary; exit $?; }

echo "AC1 the tool exists"
assert_file "AC1 tools/release-gate.sh exists" "$GATE"

W="$(mk_tmp)"
CALLS="$W/calls.log"; : > "$CALLS"
R="$W/repo"; mkdir -p "$R/tools" "$R/evals/tasks" "$R/skills"
[ -f "$GATE" ] && cp -p "$GATE" "$R/tools/release-gate.sh"
cp -p "$PB_ROOT/tools/eval-delta.sh" "$R/tools/eval-delta.sh"
for t in pattern-15-erase-account-ambiguous pattern-24-merge-duplicate-customers pattern-26-consistent-price-rounding pattern-01-option-value-label; do
  mkdir -p "$R/evals/tasks/$t"; printf 'x\n' > "$R/evals/tasks/$t/prompt.md"
done
# fake runner: records "<name> <args>", writes ${OUT%.md}.json with both arms; with passes check x, without fails it
# FAKE_RC_<NAME> sets its exit code
mk_fake() { # NAME LISTFLAG
  cat > "$R/evals/$1" <<EOF
#!/usr/bin/env bash
# fake $1
AUTO="E1 E2 E3"
NAME=$1; LISTFLAG=$2; CALLS='$CALLS'
EOF
  cat >> "$R/evals/$1" <<'EOF'
printf '%s %s\n' "$NAME" "$*" >> "$CALLS"
out=""; model=""; harness="custom"; list=""; k=1; prev=""
for a in "$@"; do
  case "$prev" in
    --out) out="$a" ;; --model) model="$a" ;; --harness) harness="$a" ;; --repeat) k="$a" ;; "$LISTFLAG") list="$a" ;;
  esac
  prev="$a"
done
rcv="FAKE_RC_${NAME%%.sh}"; rcv="${rcv//-/_}"; rc="${!rcv:-0}"
[ "$rc" = 2 ] || [ "$rc" = 3 ] && exit "$rc"
commit="$(git -C "$(dirname "$0")/.." rev-parse HEAD)"
runs=""; sep=""
for s in $(printf '%s' "$list" | tr ',' ' '); do
  i=1
  while [ "$i" -le "$k" ]; do
    for arm in with without; do
      r=PASS; [ "$arm" = without ] && r=FAIL
      runs="$runs$sep{\"scenario\":\"$s\",\"arm\":\"$arm\",\"k\":$i,\"label\":\"$s.$arm.$i\",\"status\":\"graded\",\"error\":null,\"isolation\":\"adapter\",\"fixture_tree\":\"t-$s\",\"prompt_sha\":\"p-$s\",\"cost_usd\":0.1,\"seconds\":5,\"notes\":[],\"dropped_user_lines\":0,\"checks\":[{\"name\":\"x\",\"key\":\"x\",\"result\":\"$r\"}]}"
      sep=","
    done
    i=$((i + 1))
  done
done
mkdir -p "$(dirname "$out")"
printf '# fake\n' > "$out"
printf '{"schema":"pb-evals/1","playbook_commit":"%s","playbook_version":"0.30.0","harness":"%s","model":"%s","arms":["with","without"],"repeat":%s,"max_cost":null,"interactive":false,"started":"2026-10-27T10:00:00Z","workroot":"/w","runs":[%s],"summary":[]}\n' \
  "$commit" "$harness" "$model" "$k" "$runs" > "${out%.md}.json"
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
assert_contains "AC2 the behaviour command: AUTO set, both arms, k=5" "$OUT" "evals/run-evals.sh --harness claude --model m1 --arm both --repeat 5 --scenarios E1,E2,E3"
assert_contains "AC2 the outcome command: the separating tasks, both arms, k=5" "$OUT" "evals/run-outcome.sh --harness claude --model m1 --arm both --repeat 5 --tasks $TASKS"
assert_contains "AC2 the default out dir is evals/results/gate-<sha12>" "$OUT" "evals/results/gate-$SHA12/"
assert_contains "AC3 a clean tree is reported" "$OUT" "tree: clean"
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
assert_contains "AC2 run-evals.sh got the gate's arguments" "$(grep '^run-evals.sh ' "$CALLS")" "--harness claude --model m1 --arm both --repeat 5 --scenarios E1,E2,E3 --out $OD/"
assert_contains "AC2 run-outcome.sh got the gate's arguments" "$(grep '^run-outcome.sh ' "$CALLS")" "--harness claude --model m1 --arm both --repeat 5 --tasks $TASKS --out $OD/"
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
assert_rc "AC1 --cmd run -> exit 0" 0
assert_contains "AC1 --cmd reaches run-evals.sh" "$(grep '^run-evals.sh ' "$CALLS")" "--cmd bash /x/adapter.sh"
assert_contains "AC4 the claude files are skipped for a custom run" "$OUT" "(other harness)"

echo "AC1 the help text"
RC=0; OUT="$(bash "$GATE" --help 2>&1)" || RC=$?
assert_rc "AC1 --help -> exit 2" 2
assert_contains "AC1 the help names --pool-only" "$OUT" "--pool-only"

t_summary
