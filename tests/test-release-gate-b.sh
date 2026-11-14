#!/usr/bin/env bash
# Second half of tests/test-release-gate.sh (the sections from the AC7 preflight case on); the shared setup is in tests/release-gate-suite-fixture.sh.
. "$(dirname "$0")/release-gate-suite-fixture.sh"
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

# =====================================================================================================================================
# v0.34.0 slice B1: G1 (a real run reads the CI check runs of HEAD first), G2 (--skip-ci-check, ci_check in gate.json), M1/D13 (a used DIR
# is refused unless --add-batch). The fake gh (tests/release-gate-fixture.sh) serves REST payloads: names, ids, statuses and step names of
# a captured payload (the check runs of a PR head whose `test (ubuntu-latest)` job failed only in its "Release gate" step), repository
# anonymised to acme/widgets. Decisions D3 (what counts as green), D4 (owner/repo, exit codes, ci_check), D13 (--add-batch).
echo "G1 a real run reads the check runs of HEAD (REST, paginated) before anything else; green runs on"
rgf_gh_green
rcase g1-green ""
assert_rc "G1 all check runs green (success, skipped) -> the gate runs and passes, exit 0" 0
GHL="$(rgf_gh_calls)"
assert_contains "G1 the check runs of HEAD are read through the REST endpoint of the owner/repo of PB_GATE_REPO" "$GHL" "repos/acme/widgets/commits/$SHA/check-runs"
assert_contains "G1 the read is paginated" "$(printf '%s\n' "$GHL" | grep 'check-runs')" "--paginate"
assert_eq "G1 no gh command other than api is used (never gh pr checks)" "0" "$(printf '%s\n' "$GHL" | grep -vc '^api ' || true)"
assert_eq "G2 gate.json ci_check.skipped is false without the flag" "false" "$(gj "$GJ" j.ci_check.skipped)"
assert_eq "G2 gate.json ci_check.sha is the gate commit" "$SHA" "$(gj "$GJ" j.ci_check.sha)"
assert_eq "G2 gate.json ci_check.state is a non-empty string (D4)" "string" "$(gj "$GJ" 'typeof j.ci_check.state==="string"&&j.ci_check.state.length>0?"string":"no"')"
assert_eq "G2 gate.json ci_check.checks maps each name to its own conclusion (windows -> success, release -> skipped)" "success|skipped" "$(gj "$GJ" 'j.ci_check.checks.find(c=>c.name==="test (windows-latest)").conclusion+"|"+j.ci_check.checks.find(c=>c.name==="release").conclusion')"
assert_eq "G2 gate.json ci_check.checks lists all four check runs" "4" "$(gj "$GJ" j.ci_check.checks.length)"

echo "G1/D3 a check run red only because its job failed in the Release gate step counts as green (captured payload)"
rgf_gh_sample_red_gate_only
rcase g1-gateonly ""
assert_rc "D3 test (ubuntu-latest) failed only in the Release gate step -> exit 0" 0
GHL="$(rgf_gh_calls)"
assert_contains "D3 the job of the red check run is read (REST actions/jobs/<check run id>)" "$GHL" "repos/acme/widgets/actions/jobs/124850217910"
assert_eq "D3 the gate ran both runners" "1|1" "$(ncalls run-evals.sh)|$(ncalls run-outcome.sh)"
assert_eq "G2 ci_check is recorded with skipped false" "false" "$(gj "$GJ" j.ci_check.skipped)"
assert_eq "G2 ci_check.checks names the check run that was red only in the gate" "1" "$(gj "$GJ" 'j.ci_check.checks.filter(c=>c.name==="test (ubuntu-latest)").length')"
# v0.36.0 C4: gate.json names the failed step of a check run that counts as green only because that step is the gate's own
assert_eq "C4 the excused check run lists its failed step names (the Release gate step)" "Release gate (a PR that changes VERSION needs a committed passing gate)" "$(gj "$GJ" 'j.ci_check.checks.find(c=>c.name==="test (ubuntu-latest)").failed_steps.join("|")')"
assert_eq "C4 a check run that was green has no failed_steps" "undefined" "$(gj "$GJ" 'typeof j.ci_check.checks.find(c=>c.name==="test (windows-latest)").failed_steps')"

# rc_short NAME RC: assert_rc, but a failure shows only the first lines of the output (a gate that ran prints its tables)
rc_short() { local full="$OUT"; OUT="$(printf '%s\n' "$OUT" | head -n 3 | cut -c1-200)"; assert_rc "$1" "$2"; OUT="$full"; }
# out_has NAME NEEDLE: the output contains NEEDLE (a failure shows only the first lines of the output)
out_has() { if printf '%s' "$OUT" | grep -qF -- "$2"; then t_ok "$1"; else t_bad "$1" "missing [$2] in: $(printf '%s\n' "$OUT" | head -n 3 | cut -c1-200)"; fi; }
# no_start NAME: nothing started - no runner (preflight included), no worktree, no out dir, no temp dir of the gate
no_start() {
  assert_eq "$1: no runner and no preflight was called" "0" "$(grep -c . "$CALLS" || true)"
  assert_eq "$1: no worktree was made" "1" "$(git -C "$R" worktree list | wc -l | tr -d ' ')"
  assert_no_path "$1: no out dir was created" "$ODN"
  assert_eq "$1: no temp dir of the gate is left" "0" "$(ls "$W/tmp" 2>/dev/null | grep -c '^pbbase\.\|^pbgate\.' || true)"
}
# refused NAME NEEDLE...: exit 2, every needle (the offending check names) in the output, nothing started
refused() {
  local n="$1" w; shift
  rc_short "$n -> refused, exit 2" 2
  for w in "$@"; do out_has "$n: the message names [$w]" "$w"; done
  no_start "$n"
}

echo "G1/D3 not green -> exit 2 naming the checks, before the baseline, worktree, preflight and any runner"
rgf_gh_sample_red_gate_only
rgf_gh_job 124850217910 "test (ubuntu-latest)" failure "1|Set up job|success" "6|Tests and static checks|failure" \
  "7|Release gate (a PR that changes VERSION needs a committed passing gate)|skipped" "8|README test count (Linux only)|skipped"
rcase g1-realfail ""
refused "G1 test (ubuntu-latest) failed in Tests and static checks" "test (ubuntu-latest)"
rgf_gh_job 124850217910 "test (ubuntu-latest)" failure "1|Set up job|success" "6|Tests and static checks|failure" \
  "7|Release gate (a PR that changes VERSION needs a committed passing gate)|failure"
rcase g1-bothfail ""
refused "D3 tests failed AND the Release gate step failed (not solely the gate)" "test (ubuntu-latest)"
rgf_gh_job 124850217910 "test (ubuntu-latest)" failure "1|Set up job|success" "6|Tests and static checks|success" \
  "7|Release gate (a PR that changes VERSION needs a committed passing gate)|failure" "8|README test count (Linux only)|failure"
rcase g1-countfail ""
refused "D3 the Release gate step and the README count step failed (a non-gate step failed too)" "test (ubuntu-latest)"
rgf_gh_green
rgf_gh_runs "1|test (ubuntu-latest)|completed|success" "2|windows shard 3/8|in_progress|" "3|macos shard 1/2|queued|" "4|changes|completed|success"
rcase g1-pending ""
refused "G1 pending check runs (in_progress, queued)" "windows shard 3/8" "macos shard 1/2"
assert_not_contains "G1 a green check run is not named as an offender" "$(printf '%s\n' "$OUT" | grep -i 'changes' || true)" "changes"
for cc in failure cancelled timed_out action_required stale; do
  rgf_gh_green
  rgf_gh_runs "1|test (ubuntu-latest)|completed|success" "2|lint-$cc|completed|$cc" "3|changes|completed|success"
  rgf_gh_job 2 "lint-$cc" failure "1|Set up job|success" "2|Lint|failure"
  rcase "g1-$cc" ""
  refused "G1 a check run concluded $cc" "lint-$cc"
done
rgf_gh_green
rgf_gh_runs "1|test (ubuntu-latest)|completed|neutral" "2|release|completed|skipped" "3|changes|completed|success"
rcase g1-neutral ""
assert_rc "G1 neutral and skipped count as green -> exit 0" 0
rgf_gh_runs
rcase g1-zero ""
refused "G1 zero check runs (CI has not started)"
rgf_gh_green
rgf_gh_runs "1|test (ubuntu-latest)|completed|success" "2|test (windows-latest)|completed|success" "3|test (macos-latest)|in_progress|"
rcase g1-mixed ""
refused "G1 one pending check among green ones" "test (macos-latest)"

echo "G1 pagination: every page is read (the red check run is on the last page)"
rgf_gh_green
rgf_gh_runs --per-page 2 "1|a1|completed|success" "2|a2|completed|success" "3|a3|completed|success" "4|a4|completed|success" "5|late-red|completed|cancelled"
rgf_gh_job 5 late-red failure "1|Set up job|success" "2|Work|failure"
rcase g1-page-red ""
refused "G1 failure only on page 3" "late-red"
rgf_gh_runs --per-page 2 "1|a1|completed|success" "2|a2|completed|success" "3|a3|completed|success" "4|a4|completed|success" "5|a5|completed|success"
rcase g1-page-green ""
assert_rc "G1 five green check runs over three pages -> exit 0" 0
assert_eq "G2 ci_check.checks has all five check runs of the three pages" "5" "$(gj "$GJ" j.ci_check.checks.length)"

echo "D4 owner/repo: PB_GATE_REPO, else the origin URL (https and ssh forms of github.com)"
rgf_gh_green
git -C "$R" remote add origin https://github.com/zed/gadgets.git
oc() { # URL EXPECTED-REPO NAME: PB_GATE_REPO unset, origin = URL
  git -C "$R" remote set-url origin "$1"
  rgf_gh_green; rcase "g1-origin-$3" "-u PB_GATE_REPO"
  assert_rc "D4 origin $1 -> the gate runs, exit 0" 0
  assert_contains "D4 origin $1 -> the check runs are read for $2" "$(rgf_gh_calls)" "repos/$2/commits/$SHA/check-runs"
}
oc https://github.com/zed/gadgets.git zed/gadgets https-git
oc https://github.com/zed/gadgets zed/gadgets https
oc git@github.com:zed/gadgets.git zed/gadgets scp
oc ssh://git@github.com/zed/gadgets.git zed/gadgets ssh
rgf_gh_green; rcase g1-env-wins ""
assert_contains "D4 PB_GATE_REPO wins over the origin URL" "$(rgf_gh_calls)" "repos/acme/widgets/commits/$SHA/check-runs"
assert_not_contains "D4 ... and the origin repository is not read" "$(rgf_gh_calls)" "zed/gadgets"
git -C "$R" remote remove origin

echo "D4 gh missing or an API error -> exit 3, nothing started"
NOGH="$W/nogh"; mkdir -p "$NOGH"
for d in $(printf '%s' "$PATH" | tr ':' ' '); do
  [ "$d" = "$RGF_GH/bin" ] && continue
  [ -d "$d" ] || continue
  for f in "$d"/*; do [ -x "$f" ] && [ -f "$f" ] && [ "${f##*/}" != gh ] && [ ! -e "$NOGH/${f##*/}" ] && ln -s "$f" "$NOGH/${f##*/}"; done
done
rgf_gh_green; GE_PATH="$NOGH" rcase g1-nogh ""
assert_eq "D4 fixture: gh is not on the stripped PATH" "0" "$(env PATH="$NOGH" bash -c 'command -v gh >/dev/null 2>&1 && echo 1 || echo 0')"
rc_short "D4 gh is not installed -> exit 3" 3
no_start "D4 gh missing"
rgf_gh_green; rgf_gh_fail checks
rcase g1-apierr ""
rc_short "D4 the check-runs call fails (API error) -> exit 3" 3
no_start "D4 API error"
rgf_gh_green; rgf_gh_fail all
rcase g1-apierr-all ""
rc_short "D4 every gh call fails -> exit 3" 3
no_start "D4 every call fails"
rgf_gh_sample_red_gate_only; rgf_gh_fail jobs
rcase g1-joberr ""
rc_short "D4 the job of a red check run cannot be read (API error) -> exit 3, not green" 3
no_start "D4 job API error"

echo "G1 the check comes before the baseline, worktree and preflight: a red CI wins over a missing baseline and a failing preflight"
RB1="$W/repo-b1order"; git clone -q "$R" "$RB1" && ( cd "$RB1" && git config user.email t@example.invalid && git config user.name tester && git config commit.gpgsign false &&
  git config tag.gpgsign false && mkdir -p evals/results/gate-aaaaaaaaaaaa && printf '{}\n' > evals/results/gate-aaaaaaaaaaaa/other.json &&
  git add -f -A && git commit -qm "an old gate dir" && git tag v0.0.1 && printf 'x\n' >> README.md && git add -A && git commit -qm "head" ) || t_bad "fixture repo 5" "clone or commit failed"
GR="$RB1"; rgf_gh_green
rcase g1-order-ctl ""
rc_short "G1 control: a green CI and a tag whose gate dir has no qualifying group -> exit 3 (the baseline)" 3
rgf_gh_runs "1|test (ubuntu-latest)|completed|failure"
rgf_gh_job 1 "test (ubuntu-latest)" failure "1|Set up job|success" "2|Tests|failure"
rcase g1-order-red ""
rc_short "G1 a red CI and a baseline that would stop with 3 -> exit 2 (the CI check comes first)" 2
assert_eq "G1 ... no runner or preflight call" "0" "$(grep -c . "$CALLS" || true)"
GR=""
rgf_gh_green
rcase g1-order-pf-ctl "FAKE_PF_FAIL=run-evals.sh"
rc_short "G1 control: a green CI and a runner whose --preflight exits 3 -> exit 3 (the preflight is reached)" 3
rgf_gh_runs "1|test (ubuntu-latest)|completed|failure"
rgf_gh_job 1 "test (ubuntu-latest)" failure "1|Set up job|success" "2|Tests|failure"
rcase g1-order-pf-red "FAKE_PF_FAIL=run-evals.sh"
rc_short "G1 a red CI and a runner whose --preflight exits 3 -> exit 2 (no preflight call)" 2
assert_eq "G1 ... the runners were not called at all" "0" "$(grep -c . "$CALLS" || true)"

echo "G1/G2 --dry-run, --pool-only and --check never read the CI"
rgf_gh_runs "1|test (ubuntu-latest)|completed|failure"
rgf_gh_job 1 "test (ubuntu-latest)" failure "1|Set up job|success" "2|Tests|failure"
rgf_gh_clearlog
ge "" --harness claude --model m1 --dry-run
assert_rc "G1 --dry-run with a red CI -> exit 0" 0
ge "" --harness claude --model m1 --out-dir evals/results/g1-green --pool-only
rc_short "G1 --pool-only with a red CI -> not refused (exit 0 on a passing dir)" 0
assert_eq "G1 --dry-run and --pool-only made no gh call" "0" "$(rgf_gh_ncalls)"
rgf_gh_green

echo "G2 --skip-ci-check: no check is read, the run goes on, gate.json records it"
rgf_gh_runs "1|test (ubuntu-latest)|completed|failure" "2|windows shard 1/8|in_progress|"
rgf_gh_job 1 "test (ubuntu-latest)" failure "1|Set up job|success" "2|Tests|failure"
rgf_gh_clearlog
rcase g2-skip "" --skip-ci-check
assert_rc "G2 a red and pending CI with --skip-ci-check -> the gate runs, exit 0" 0
assert_eq "G2 the check runs were not read at all (no gh call)" "0" "$(rgf_gh_ncalls)"
assert_eq "G2 both runners ran" "1|1" "$(ncalls run-evals.sh)|$(ncalls run-outcome.sh)"
assert_eq "G2 gate.json ci_check.skipped is true" "true" "$(gj "$GJ" j.ci_check.skipped)"
# A PATH where gh is unusable but node and the rest stay reachable (a symlink-farm PATH loses node on Windows Git Bash): a shim gh
# that records a call and fails like a missing command; --skip-ci-check must not call it.
DEADGH="$W/deadgh"; mkdir -p "$DEADGH"; : > "$W/deadgh.calls"
printf '#!/bin/sh\necho call >> "%s"\nexit 127\n' "$W/deadgh.calls" > "$DEADGH/gh"; chmod +x "$DEADGH/gh"
GE_PATH="$DEADGH:$PATH" rcase g2-skip-nogh "" --skip-ci-check
assert_rc "G2 --skip-ci-check needs no gh: gh missing -> exit 0" 0
assert_eq "G2 --skip-ci-check never called the unusable gh" "0" "$(grep -c call "$W/deadgh.calls" || true)"
assert_eq "G2 gate.json ci_check.skipped is true (no gh)" "true" "$(gj "$GJ" j.ci_check.skipped)"
rcase g2-skip-json "" --skip-ci-check --json
assert_rc "G2 --skip-ci-check --json -> exit 0" 0
assert_eq "G2 a --json run records ci_check in gate.json too" "true" "$(gj "$GJ" j.ci_check.skipped)"
rgf_gh_green
RC=0; OUT="$(bash "$GATE" --help 2>&1)" || RC=$?
out_has "G2 the help names --skip-ci-check" "--skip-ci-check"
out_has "M1 the help names --add-batch" "--add-batch"

echo "M1/D13 a real run refuses an out DIR that already holds pb-evals/1 files or a gate.json, unless --add-batch"
rgf_gh_green
rcase m1-first ""
assert_rc "M1 control: a fresh DIR -> exit 0" 0
N1="$(ls "$ODN" | wc -l | tr -d ' ')"; H1="$(cat "$ODN"/*.json | cksum)"
rcase m1-first ""
rc_short "M1 the same DIR again (pb-evals/1 files and gate.json) -> refused, exit 2" 2
out_has "M1 the message names the DIR" "evals/results/m1-first"
assert_not_contains "M1 the refused run started no runner (no '== behaviour:' line)" "$OUT" "== behaviour:"
assert_eq "M1 the refused run called no runner, preflight included" "0" "$(grep -c . "$CALLS" || true)"
assert_eq "M1 the refused run made no worktree" "1" "$(git -C "$R" worktree list | wc -l | tr -d ' ')"
assert_eq "M1 the refused run changed nothing in DIR (same file count and content)" "$N1|$H1" "$(ls "$ODN" | wc -l | tr -d ' ')|$(cat "$ODN"/*.json | cksum)"
rcase m1-first "" --add-batch
assert_rc "M1 --add-batch on the same DIR -> the batch is added, exit 0" 0
assert_eq "M1 --add-batch: n adds up (min_graded 5 + 5)" "10" "$(gj "$GJ" j.min_graded)"
assert_eq "M1 --add-batch: four files are pooled" "4" "$(gj "$GJ" j.pooled.length)"
rcase m1-fresh-add "" --add-batch
assert_rc "M1 --add-batch on a fresh DIR is accepted -> exit 0" 0
assert_eq "M1 --add-batch on a fresh DIR: two files pooled" "2" "$(gj "$GJ" j.pooled.length)"
mkdir -p "$R/evals/results/m1-gj"
printf '{"schema":"pb-gate/1","verdict":"pass"}\n' > "$R/evals/results/m1-gj/gate.json"
rcase m1-gj ""
rc_short "M1 a DIR holding only a gate.json -> refused, exit 2" 2
out_has "M1 gate.json only: the message names the DIR" "evals/results/m1-gj"
assert_eq "M1 gate.json only: no runner was called" "0" "$(grep -c . "$CALLS" || true)"
assert_eq "M1 gate.json only: the old gate.json is untouched" '{"schema":"pb-gate/1","verdict":"pass"}' "$(cat "$R/evals/results/m1-gj/gate.json")"
mkdir -p "$R/evals/results/m1-ef"
printf '{"schema":"pb-evals/1","playbook_commit":"%s","harness":"claude","model":"m1","runs":[]}\n' "$SHA" > "$R/evals/results/m1-ef/earlier.json"
rcase m1-ef ""
rc_short "M1 a DIR holding one pb-evals/1 file and no gate.json -> refused, exit 2" 2
out_has "M1 pb-evals/1 file only: the message names the DIR" "evals/results/m1-ef"
mkdir -p "$R/evals/results/m1-other"
printf 'notes\n' > "$R/evals/results/m1-other/notes.md"; printf 'log\n' > "$R/evals/results/m1-other/behaviour.log"; printf '{"a":1}\n' > "$R/evals/results/m1-other/other.json"
rcase m1-other ""
rc_short "M1 a DIR holding only a .md, a .log and a JSON that is not pb-evals/1 -> not refused, exit 0" 0
mkdir -p "$R/evals/results/m1-empty"
rcase m1-empty ""
rc_short "M1 an existing empty DIR -> not refused, exit 0" 0
ge "" --harness claude --model m1 --out-dir evals/results/m1-first --dry-run
assert_rc "M1 --dry-run into a DIR that holds results -> exit 0 (only a real run refuses)" 0
ge "" --harness claude --model m1 --out-dir evals/results/m1-first --pool-only
assert_rc "M1 --pool-only into a DIR that holds results -> exit 0" 0

echo "AC1 the help text"
RC=0; OUT="$(bash "$GATE" --help 2>&1)" || RC=$?
rc_short "AC1 --help -> exit 2" 2
assert_contains "AC1 the help names --pool-only" "$OUT" "--pool-only"

t_summary
