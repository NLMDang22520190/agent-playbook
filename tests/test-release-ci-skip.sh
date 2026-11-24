#!/usr/bin/env bash
# Tests for tools/release.sh v0.37 slice S9, AC11 (Q8b) and R5: after the gate check passes and before tests/run-all.sh, release.sh asks
# GitHub (REST only: `gh api repos/OWNER/REPO/commits/<HEAD sha>/check-runs`; repo = PB_GATE_REPO or the origin URL, as release-gate.sh does)
# whether CI is green on exactly HEAD (= origin/main). Green = none pending, every run concluded success/skipped/neutral, at least one
# `success`, AND test (ubuntu-latest), test (macos-latest), test (windows-latest) present and `success` (the aggregators of
# tools/ci-tree-tested.sh; shards may be skipped) (strict: no "green except the Release gate step" rule). Green -> tests/run-all.sh is skipped with the line
# "tests/run-all.sh skipped: CI is green on <short sha> (use --local-suite to run it here)" (release.sh no longer reads a README test
# count, so there is no README line at all). --local-suite forces the old behaviour. R5: CI not green (pending, failing, no
# check runs, gh missing, API error, unparsable JSON, repo unknown) -> the suite runs exactly as before and release.sh says why.
# Spec: docs/v0.37-spec.md AC11, R5. Shared setup: release-ci-fixture.sh (real release.sh, stub gate, stub run-all, fake gh).
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/release-gate-fixture.sh"
command -v node >/dev/null 2>&1 || { t_skip 1 "node missing (the fake gh needs it)"; t_summary; exit $?; }
. "$(dirname "$0")/release-ci-fixture.sh"

# skipped_line SHORT -> the exact AC11 line
skipped_line() { printf 'tests/run-all.sh skipped: CI is green on %s (use --local-suite to run it here)' "$1"; }
has_line() { printf '%s\n' "$2" | grep -Fxq -- "$1"; }
# why_line OUT -> a line that names tests/run-all.sh and CI and does not claim a skip (the reason the suite runs)
why_line() { printf '%s\n' "$1" | grep 'run-all' | grep 'CI' | grep -v 'skipped' | head -n 1; }
r5_expect_suite() { # name -> after a release.sh run in the current fixture: suite once, no skip line, a reason line, a clean dry run
  assert_rc "R5 $1: dry run still ends -> exit 0" 0
  assert_eq "R5 $1: tests/run-all.sh was called once" "1" "$(suite_runs)"
  assert_not_contains "R5 $1: no skip line" "$OUT" "tests/run-all.sh skipped"
  if [ -n "$(why_line "$OUT")" ]; then t_ok "R5 $1: a line names tests/run-all.sh and CI as the reason"; else t_bad "R5 $1: a line names tests/run-all.sh and CI as the reason" "$OUT"; fi
}
# a gh that is not on PATH: a directory of links to the tools release.sh needs, without gh
mk_nogh_path() {
  local d t p; d="$(mk_tmp)/bin"; mkdir -p "$d"
  for t in bash env git sed grep awk cut tee mktemp rm cat head tail tr date node dirname basename sort uniq wc ls mkdir cp mv sleep readlink true false test xargs expr printf touch chmod ln find id uname; do
    p="$(command -v "$t" 2>/dev/null)" && case "$p" in /*) ln -sf "$p" "$d/$t" ;; esac
  done
  printf '%s' "$d"
}
# a gh that exits 0 and prints text that is not JSON
mk_junk_gh() {
  local d; d="$(mk_tmp)/bin"; mkdir -p "$d"
  printf '#!/usr/bin/env bash\necho "$*" >> "%s/junk.log"\nprintf "<html>502 bad gateway, not json\\n"\nexit 0\n' "$d/.." > "$d/gh"
  chmod 755 "$d/gh"; printf '%s' "$d"
}

echo "AC11 CI green on HEAD: the local suite is skipped and says so"
rc_setup
HEAD0="$(git -C "$C" rev-parse HEAD)"; SHORT0="$(git -C "$C" rev-parse --short HEAD)"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC11 green CI, --dry-run -> exit 0" 0
assert_eq "AC11 green CI: tests/run-all.sh was not called" "0" "$(suite_runs)"
if has_line "$(skipped_line "$SHORT0")" "$OUT"; then t_ok "AC11 green CI: prints the skip line with the short sha"; else t_bad "AC11 green CI: prints the skip line with the short sha" "want: $(skipped_line "$SHORT0") in: $OUT"; fi
assert_contains "AC11 green CI: the dry run still prints 'would tag'" "$OUT" "would tag v1.2.3"
assert_contains "AC11 CI was read for exactly HEAD (REST check-runs of the full sha)" "$(cat "$RGF_GH/gh.log")" "repos/acme/widgets/commits/$HEAD0/check-runs"
assert_eq "AC11 the CI read uses only 'gh api' (never gh pr checks): the fake refuses anything else" "0" "$(grep -vc '^api ' "$RGF_GH/gh.log" || true)"
assert_eq "AC11 the gate was still checked once (CI skip does not replace the gate)" "1" "$(gate_runs)"

echo "AC11 CI green: a real release skips the suite and still tags and pushes"
rc_setup
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC11 green CI, real release -> exit 0" 0
assert_eq "AC11 green CI, real release: tests/run-all.sh not called" "0" "$(suite_runs)"
assert_contains "AC11 green CI, real release: the tag is local" "$(tags_of "$C")" "v1.2.3"
assert_contains "AC11 green CI, real release: the tag is in the origin" "$(tags_of "$O")" "v1.2.3"
assert_contains "AC11 green CI, real release: released v1.2.3" "$OUT" "released v1.2.3"

echo "AC11 the repository comes from PB_GATE_REPO"
rc_setup
export PB_GATE_REPO="other/thing"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_contains "AC11 PB_GATE_REPO=other/thing is the repository asked" "$(cat "$RGF_GH/gh.log")" "repos/other/thing/commits/"
assert_not_contains "AC11 the default fixture repository is not asked then" "$(cat "$RGF_GH/gh.log")" "acme/widgets"

echo "AC11 boundaries of green: skipped and neutral count next to the test aggregators, success is needed"
# (updated: the old rule 'a single success/skipped/neutral run is green' is replaced by the need list, see the cases after this block)
for c in skipped neutral success; do
  rc_setup
  real_green_runs "11|only run|completed|$c"
  run_in "$C" bash tools/release.sh v1.2.3 --dry-run
  assert_rc "AC11 an extra check run concluded '$c' beside the aggregators is green -> exit 0" 0
  assert_eq "AC11 an extra '$c' run: the suite is skipped" "0" "$(suite_runs)"
done
rc_setup
real_green_runs "12|b|completed|skipped" "13|c|completed|neutral" "14|d|completed|success"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_eq "AC11 success + skipped + neutral together are green: suite skipped" "0" "$(suite_runs)"
rc_setup
rgf_gh_runs --per-page 2 "${RC_GREEN[@]}" "11|a|completed|success"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_eq "AC11 all green over several pages: suite skipped" "0" "$(suite_runs)"
rc_setup
rgf_gh_runs --per-page 2 "${RC_GREEN[@]}" "15|e|completed|failure"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_eq "AC11 a failure on the LAST page is seen: suite runs" "1" "$(suite_runs)"
assert_not_contains "AC11 a failure on the last page: no skip line" "$OUT" "tests/run-all.sh skipped"

echo "R5 green needs evidence: a success run AND the test aggregators (test (ubuntu-latest), test (macos-latest), test (windows-latest))"
rc_setup
rgf_gh_runs "11|changes|completed|skipped" "12|release|completed|skipped" "13|test (ubuntu-latest)|completed|skipped" \
  "14|test (macos-latest)|completed|skipped" "15|test (windows-latest)|completed|skipped"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
r5_expect_suite "everything skipped (docs-only shape): no test ran"
rc_setup
rgf_gh_runs "11|changes|completed|neutral" "12|test (ubuntu-latest)|completed|neutral" "13|test (macos-latest)|completed|neutral" "14|test (windows-latest)|completed|neutral"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
r5_expect_suite "everything neutral"
rc_setup
rgf_gh_runs "11|codecov/patch|completed|success"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
r5_expect_suite "only an unrelated third-party success run, no test jobs"
rc_setup
rgf_gh_runs "11|codecov/patch|completed|success" "12|changes|completed|success" "13|release|completed|skipped"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
r5_expect_suite "success runs but none of the test aggregators present"
for missing in "test (ubuntu-latest)" "test (macos-latest)" "test (windows-latest)"; do
  rc_setup
  runs=(); for g in "${RC_GREEN[@]}"; do case "$g" in *"|$missing|"*) ;; *) runs+=("$g") ;; esac; done
  rgf_gh_runs "${runs[@]}"
  run_in "$C" bash tools/release.sh v1.2.3 --dry-run
  r5_expect_suite "the aggregator '$missing' is missing"
done
for missing in "test (ubuntu-latest)" "test (macos-latest)" "test (windows-latest)"; do
  rc_setup
  runs=(); for g in "${RC_GREEN[@]}"; do case "$g" in *"|$missing|"*) runs+=("99|$missing|completed|skipped") ;; *) runs+=("$g") ;; esac; done
  rgf_gh_runs "${runs[@]}"
  run_in "$C" bash tools/release.sh v1.2.3 --dry-run
  r5_expect_suite "the aggregator '$missing' is skipped, not success"
done
rc_setup
real_green_runs
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_eq "R5 control: the real set (aggregators success, shards skipped) is green: suite skipped" "0" "$(suite_runs)"
assert_not_contains "R5 control: green, no 'runs here' reason" "$OUT" "runs here"

echo "R5 a read cut off after page 1 is never green"
rc_setup
rgf_gh_runs --per-page 3 "${RC_GREEN[@]}"
rgf_gh_fail partial
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
r5_expect_suite "gh api --paginate prints an all-green page 1 (with the aggregators), then exits non-zero"
rc_setup
rgf_gh_runs --per-page 3 "${RC_GREEN[@]}"
rgf_gh_fail partial
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "R5 partial read, real release: the suite runs and the release proceeds -> exit 0" 0
assert_eq "R5 partial read, real release: suite called once" "1" "$(suite_runs)"
assert_contains "R5 partial read, real release: tagged" "$(tags_of "$O")" "v1.2.3"

echo "AC11/AC4 (v0.38 T12) README test counts are not read: a wrong count is not refused, no README line"
rc_setup
set_readme "$(printf '# demo\n| Script tests | **11 passing** (see run-all) |\n')"   # the stub suite adds up to 9: 11 is wrong, and nobody cares
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC11 green CI + a wrong README count -> exit 0" 0
assert_not_contains "AC11 green CI: no README refusal text" "$OUT" "README.md test count is wrong"
assert_eq "AC11 green CI: no line mentions the README" "0" "$(printf '%s\n' "$OUT" | grep -c 'README')"
assert_eq "AC11 README case: the suite was not called" "0" "$(suite_runs)"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run --local-suite
assert_rc "AC4 --local-suite + a wrong README count is not refused -> exit 0" 0
assert_not_contains "AC4 --local-suite: no README refusal text" "$OUT" "README.md test count is wrong"
assert_eq "AC4 --local-suite: no line mentions the README" "0" "$(printf '%s\n' "$OUT" | grep -c 'README')"
assert_eq "AC11 --local-suite README case: the suite ran" "1" "$(suite_runs)"
rc_setup
set_readme "$(printf '# demo\n| Script tests | **9 passing** (see run-all) |\n')"
run_in "$C" bash tools/release.sh --local-suite v1.2.3 --dry-run
assert_rc "AC11 --local-suite (before the tag) + any README count -> exit 0" 0
assert_not_contains "AC11 --local-suite: the README is not reported as CI-verified" "$(printf '%s\n' "$OUT" | grep 'README' | grep 'CI')" "CI"

echo "AC11 --local-suite forces the suite even when CI is green"
rc_setup
run_in "$C" bash tools/release.sh v1.2.3 --dry-run --local-suite
assert_rc "AC11 --local-suite, green CI -> exit 0" 0
assert_eq "AC11 --local-suite: tests/run-all.sh was called once" "1" "$(suite_runs)"
assert_not_contains "AC11 --local-suite: no skip line" "$OUT" "tests/run-all.sh skipped"
rc_setup
run_in "$C" bash tools/release.sh v1.2.3 --local-suite
assert_rc "AC11 --local-suite, real release -> exit 0" 0
assert_eq "AC11 --local-suite real release: suite called once" "1" "$(suite_runs)"
assert_contains "AC11 --local-suite real release: tagged" "$(tags_of "$O")" "v1.2.3"
rc_setup
export PB_TEST_SUITE_RC=1
run_in "$C" bash tools/release.sh v1.2.3 --local-suite
assert_rc "AC11 --local-suite with a red suite -> refused, exit 1" 1
assert_eq "AC11 --local-suite red suite: no tag" "" "$(tags_of "$C")$(tags_of "$O")"
rc_setup
export PB_TEST_SUITE_RC=1
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC11 green CI: a suite that would fail is never called, release goes on -> exit 0" 0
assert_eq "AC11 green CI: no suite call even though it would fail" "0" "$(suite_runs)"

echo "AC11 the CI read comes after the gate check"
rc_setup
export PB_TEST_GATE_RC=1
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC11 a failing gate is refused before CI is read -> exit 1" 1
assert_eq "AC11 failing gate: no check-runs call yet" "0" "$(check_run_calls)"
assert_eq "AC11 failing gate: no suite" "0" "$(suite_runs)"
rc_setup
rgf_gh_fail all
export PB_TEST_GATE_RC=3
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC11 a gate with an environment error still exits 3" 3
assert_eq "AC11 gate exit 3: no check-runs call" "0" "$(check_run_calls)"

echo "R5 CI not green on HEAD: the suite runs as before and release.sh says why"
rc_setup
rgf_gh_runs "11|a|completed|success" "12|b|in_progress|"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
r5_expect_suite "one check run in progress"
rc_setup
rgf_gh_runs "11|a|completed|success" "12|b|queued|"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
r5_expect_suite "one check run queued"
rc_setup
rgf_gh_runs "11|a|completed|success" "12|b|completed|failure" "13|c|completed|success"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
r5_expect_suite "one check run failed"
for c in cancelled timed_out action_required stale startup_failure; do
  rc_setup
  rgf_gh_runs "11|a|completed|success" "12|b|completed|$c"
  run_in "$C" bash tools/release.sh v1.2.3 --dry-run
  r5_expect_suite "one check run concluded '$c'"
done
rc_setup
rgf_gh_runs
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
r5_expect_suite "no check runs at all (an empty list is no evidence)"
rc_setup
rgf_gh_sample_red_gate_only
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
r5_expect_suite "failed only in its Release gate step (that leniency is for PRs; on the main sha it is red)"
assert_eq "R5 Release-gate-step-only failure: the job endpoint is not read to excuse it" "0" "$(grep -c 'actions/jobs' "$RGF_GH/gh.log" || true)"
rc_setup
rgf_gh_fail checks
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
r5_expect_suite "gh api error on the check-runs call (HTTP 403)"
rc_setup
rgf_gh_fail all
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
r5_expect_suite "gh api error (HTTP 500 on everything)"
rc_setup
JB="$(mk_junk_gh)"; export PATH="$JB:$ORIG_PATH"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
r5_expect_suite "unparsable JSON from gh (exit 0, not JSON)"
assert_contains "R5 unparsable JSON: the junk gh was really called" "$(cat "$JB/../junk.log" 2>/dev/null)" "check-runs"
rc_setup
NG="$(mk_nogh_path)"
assert_eq "R5 control: the PATH of the next case really has no gh" "" "$(PATH="$NG" command -v gh || true)"
# probe (L-0004): every command release.sh needs must really run through the farm (on Windows the links are copies or unusable: exit 127)
farm_ok=1; farm_bad=""
for t in git sed grep awk cut tee mktemp rm cat head node dirname env ls date tr printf; do
  ( PATH="$NG"; "$t" --version >/dev/null 2>&1 ); [ $? -ne 127 ] || { farm_ok=0; farm_bad="$farm_bad $t"; }
done
if [ "$farm_ok" = 1 ]; then
  export PATH="$NG"
  run_in "$C" bash tools/release.sh v1.2.3 --dry-run
  export PATH="$RGF_GH/bin:$ORIG_PATH"
  r5_expect_suite "gh is not installed"
else
  t_skip 4 "R5 gh is not installed (PATH farm unusable here, not found through it:$farm_bad)"
fi
rc_setup
unset PB_GATE_REPO
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
r5_expect_suite "repository unknown (no PB_GATE_REPO, origin is not a GitHub URL)"
assert_eq "R5 unknown repository: gh was not asked for another repository's check runs" "0" "$(check_run_calls)"
export PB_GATE_REPO="acme/widgets"

echo "R5 a real release with CI not green: the suite decides, as before"
rc_setup
rgf_gh_runs "11|a|completed|failure"
export PB_TEST_SUITE_RC=1
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "R5 CI red + red suite -> refused, exit 1" 1
assert_contains "R5 CI red + red suite: refused by the suite" "$OUT" "release refused: tests/run-all.sh failed"
assert_eq "R5 CI red + red suite: no tag" "" "$(tags_of "$C")$(tags_of "$O")"
rc_setup
rgf_gh_runs "11|a|completed|failure"
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "R5 CI red + green local suite -> released, exit 0" 0
assert_eq "R5 CI red + green local suite: suite called once" "1" "$(suite_runs)"
assert_contains "R5 CI red + green local suite: tagged" "$(tags_of "$O")" "v1.2.3"
rc_setup
set_readme "$(printf '# demo\n| Script tests | **11 passing** (see run-all) |\n')"
rgf_gh_runs "11|a|completed|failure"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "R5 CI red: a wrong README count is not refused -> exit 0" 0
assert_not_contains "R5 CI red: no README refusal text" "$OUT" "README.md test count is wrong"

echo "AC11 usage: unknown flags still exit 2, --local-suite is a known flag"
rc_setup
run_in "$C" bash tools/release.sh v1.2.3 --bogus
assert_rc "AC11 unknown flag -> exit 2" 2
run_in "$C" bash tools/release.sh v1.2.3 --local-suite --bogus
assert_rc "AC11 --local-suite plus an unknown flag -> exit 2" 2
run_in "$C" bash tools/release.sh v1.2.3 --local-suite=yes
assert_rc "AC11 --local-suite=yes (not a flag with a value) -> exit 2" 2
run_in "$C" bash tools/release.sh --local-suite
assert_rc "AC11 --local-suite without a tag -> exit 2" 2
assert_eq "AC11 usage errors: nothing tagged, no gate, no suite, no CI read" "0" "$((  $(gate_runs) + $(suite_runs) + $(check_run_calls) ))"
assert_eq "AC11 usage errors: no tag" "" "$(tags_of "$C")$(tags_of "$O")"

# ---------------------------------------------------------------------------------------------------------------------------------
# v0.38 T7 (spec: docs/v0.38-t7-spec.md, AC1-AC9): on a merge commit whose tree was reused, CI has no `test (ubuntu-latest)` check run
# (the job `test` is skipped) while `test (macos-latest)` and `test (windows-latest)` are success. ci_state then prints a second line
# `reuse-candidate`; release.sh asks tools/ci-tree-tested.sh (a STUB here: installed, committed and pushed per case, never in rc_setup,
# so the cases above keep their old meaning (AC9); logs its arguments outside the work tree; never calls gh) and, for a numeric run id,
# skips the suite.
# ---------------------------------------------------------------------------------------------------------------------------------
echo "v0.38 T7 setup: the stub tools/ci-tree-tested.sh is per case, not in rc_setup (AC9)"
# the real shape of a reuse merge commit: job `test` skipped (no `test (ubuntu-latest)`), macOS and Windows aggregators success
RC_REUSE=(); for g in "${RC_GREEN[@]}"; do case "$g" in *"|test (ubuntu-latest)|"*) RC_REUSE+=("124850217910|test|completed|skipped") ;; *) RC_REUSE+=("$g") ;; esac; done
TT_LOG="$rc_work/tt.log"
tt_calls() { grep -c . "$TT_LOG" || true; }
tt_setup() { # rc_setup + the stub tool committed and pushed (clean tree), reuse-shaped check runs, empty call log
  rc_setup
  cat > "$C/tools/ci-tree-tested.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${PB_TEST_TT_LOG:?}"
[ -z "${PB_TEST_TT_ERR:-}" ] || printf '%s\n' "$PB_TEST_TT_ERR" >&2
[ -z "${PB_TEST_TT_OUT+x}" ] || printf '%b' "$PB_TEST_TT_OUT"
exit "${PB_TEST_TT_RC:-0}"
STUB
  ( cd "$C" && G add -A && G commit -qm tt-stub && git push -q origin main 2>/dev/null ) || echo "fixture setup failed: tt stub"
  : > "$TT_LOG"; export PB_TEST_TT_LOG="$TT_LOG"; unset PB_TEST_TT_OUT PB_TEST_TT_RC PB_TEST_TT_ERR
  rgf_gh_runs "${RC_REUSE[@]}"
  SHORT_T="$(git -C "$C" rev-parse --short HEAD)"; HEAD_T="$(git -C "$C" rev-parse HEAD)"
}
# tt_expect_suite NAME REASON -> the suite ran once, no skip line, and the exact "runs here" line with REASON in brackets
tt_expect_suite() {
  assert_rc "$1: dry run -> exit 0" 0
  assert_eq "$1: tests/run-all.sh ran once" "1" "$(suite_runs)"
  if has_line "tests/run-all.sh runs here: CI is not green on $SHORT_T ($2)" "$OUT"; then t_ok "$1: exact 'runs here' line with ($2)"
  else t_bad "$1: exact 'runs here' line with ($2)" "$OUT"; fi
  assert_not_contains "$1: no skip line" "$OUT" "tests/run-all.sh skipped"
  assert_not_contains "$1: no README-skipped line" "$OUT" "README test count check skipped"
}

echo "AC1 reuse shape + tool prints 4242: the suite is skipped with the exact R2 line, and no README line is printed"
tt_setup
export PB_TEST_TT_OUT='4242\n'
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC1 reuse candidate verified -> exit 0" 0
if has_line "tests/run-all.sh skipped: the tree of $SHORT_T was already tested by PR run 4242 (use --local-suite to run it here)" "$OUT"; then
  t_ok "AC1 exact suite-skipped line (real short sha, run id 4242)"; else t_bad "AC1 exact suite-skipped line (real short sha, run id 4242)" "$OUT"; fi
assert_not_contains "AC1 no README-skipped line" "$OUT" "README test count check skipped"
assert_eq "AC1 the suite did not run" "0" "$(suite_runs)"
assert_not_contains "AC1 no 'runs here' line" "$OUT" "runs here"
assert_contains "AC1 the dry run still ends" "$OUT" "would tag v1.2.3"
assert_eq "AC1 the tool was called exactly once" "1" "$(tt_calls)"
assert_eq "AC1 the tool got the full HEAD sha first, then --repo acme/widgets" "$HEAD_T --repo acme/widgets" "$(cat "$TT_LOG")"

echo "AC1 a real release on a reuse candidate tags and pushes without the suite"
tt_setup
export PB_TEST_TT_OUT='4242\n'
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC1 real release on a verified reuse candidate -> exit 0" 0
assert_eq "AC1 real release: the suite did not run" "0" "$(suite_runs)"
assert_contains "AC1 real release: tagged in origin" "$(tags_of "$O")" "v1.2.3"

echo "AC1 a wrong README count is not refused, and the id is whatever the tool printed"
tt_setup
set_readme "$(printf '# demo\n| Script tests | **11 passing** (see run-all) |\n')"
SHORT_T="$(git -C "$C" rev-parse --short HEAD)"
export PB_TEST_TT_OUT='777\n'
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC1 wrong README count + verified tree -> exit 0 (no refusal)" 0
assert_not_contains "AC1 no README refusal text" "$OUT" "README.md test count is wrong"
if has_line "tests/run-all.sh skipped: the tree of $SHORT_T was already tested by PR run 777 (use --local-suite to run it here)" "$OUT"; then
  t_ok "AC1 suite-skipped line carries the id the tool printed (777)"; else t_bad "AC1 suite-skipped line carries the id the tool printed (777)" "$OUT"; fi
assert_not_contains "AC1 no README-skipped line (777 case)" "$OUT" "README test count check skipped"
assert_eq "AC1 wrong README count: the suite did not run" "0" "$(suite_runs)"

echo "AC1 whitespace around a numeric id is trimmed"
tt_setup
export PB_TEST_TT_OUT='  4242 \n'
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
if has_line "tests/run-all.sh skipped: the tree of $SHORT_T was already tested by PR run 4242 (use --local-suite to run it here)" "$OUT"; then
  t_ok "AC1 '  4242 ' is accepted as 4242"; else t_bad "AC1 '  4242 ' is accepted as 4242" "$OUT"; fi
assert_eq "AC1 trimmed id: the suite did not run" "0" "$(suite_runs)"

echo "AC2 reuse shape + tool prints nothing: the suite runs once and says why (the first line of ci_state)"
tt_setup
export PB_TEST_TT_OUT=''
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
tt_expect_suite "AC2 empty tool output" "aggregator job test (ubuntu-latest) is not success"
assert_eq "AC2 the tool was asked once" "1" "$(tt_calls)"

echo "AC3 a tool answer that is not exactly one numeric id counts as none: the suite runs, no tool noise leaks"
n=0
for ans in 'abc\n' '42 43\n' '42x\n' '42\n43\n' ' \n  \n' '-5\n' '4.2\n' '0x2A\n'; do
  n=$((n + 1)); tt_setup
  export PB_TEST_TT_OUT="$ans" PB_TEST_TT_ERR="TT-FAKE-TOOL-ERROR"
  run_in "$C" bash tools/release.sh v1.2.3 --dry-run
  tt_expect_suite "AC3 answer #$n [$ans]" "aggregator job test (ubuntu-latest) is not success"
  assert_not_contains "AC3 answer #$n: the tool's stderr does not reach release.sh's output" "$OUT" "TT-FAKE-TOOL-ERROR"
done
tt_setup
export PB_TEST_TT_OUT='4242\n' PB_TEST_TT_RC=1 PB_TEST_TT_ERR="TT-FAKE-TOOL-ERROR"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
tt_expect_suite "AC3 tool exits 1 but printed 4242" "aggregator job test (ubuntu-latest) is not success"
assert_not_contains "AC3 tool exit 1: the tool's stderr does not reach the output" "$OUT" "TT-FAKE-TOOL-ERROR"
tt_setup
rm -f "$C/tools/ci-tree-tested.sh"; ( cd "$C" && G add -A && G commit -qm tt-gone && git push -q origin main 2>/dev/null )
SHORT_T="$(git -C "$C" rev-parse --short HEAD)"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
tt_expect_suite "AC3 the tool file does not exist" "aggregator job test (ubuntu-latest) is not success"
assert_not_contains "AC3 missing tool: no shell 'No such file' noise in the output" "$OUT" "No such file"

echo "AC4 the Windows aggregator is not success too: the tool is not asked, the suite runs, the first line is unchanged"
reuse_without() { # NAME NEWSPEC|"" -> RC_REUSE with the run named NAME dropped (NEWSPEC empty) or replaced
  local g; REUSE_X=(); for g in "${RC_REUSE[@]}"; do case "$g" in *"|$1|"*) [ -z "$2" ] || REUSE_X+=("$2") ;; *) REUSE_X+=("$g") ;; esac; done
}
tt_setup; reuse_without "test (windows-latest)" ""; rgf_gh_runs "${REUSE_X[@]}"
export PB_TEST_TT_OUT='4242\n'
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
tt_expect_suite "AC4 windows aggregator missing" "aggregator job test (ubuntu-latest) is not success"
assert_eq "AC4 windows missing: the tool was not called" "0" "$(tt_calls)"
tt_setup; reuse_without "test (windows-latest)" "99|test (windows-latest)|completed|skipped"; rgf_gh_runs "${REUSE_X[@]}"
export PB_TEST_TT_OUT='4242\n'
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
tt_expect_suite "AC4 windows aggregator skipped" "aggregator job test (ubuntu-latest) is not success"
assert_eq "AC4 windows skipped: the tool was not called" "0" "$(tt_calls)"
tt_setup; reuse_without "test (windows-latest)" "99|test (windows-latest)|completed|failure"; rgf_gh_runs "${REUSE_X[@]}"
export PB_TEST_TT_OUT='4242\n'
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
tt_expect_suite "AC4 windows aggregator failure" "1 check run(s) not successful"
assert_eq "AC4 windows failure: the tool was not called" "0" "$(tt_calls)"
tt_setup; reuse_without "test (macos-latest)" ""; rgf_gh_runs "${REUSE_X[@]}"
export PB_TEST_TT_OUT='4242\n'
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
tt_expect_suite "AC4 macos aggregator missing" "aggregator job test (ubuntu-latest) is not success"
assert_eq "AC4 macos missing: the tool was not called" "0" "$(tt_calls)"
tt_setup; reuse_without "test (windows-latest)" ""; reuse_without "test (macos-latest)" ""; rgf_gh_runs "${REUSE_X[@]}"
export PB_TEST_TT_OUT='4242\n'
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
tt_expect_suite "AC4 macos and windows both missing" "aggregator job test (ubuntu-latest) is not success"
assert_eq "AC4 both missing: the tool was not called" "0" "$(tt_calls)"

echo "AC5 another check run pending or failed on the reuse shape: the tool is not asked, the suite runs"
tt_setup; rgf_gh_runs "${RC_REUSE[@]}" "88|slow|in_progress|"
export PB_TEST_TT_OUT='4242\n'
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
tt_expect_suite "AC5 one check run in progress" "1 check run(s) not finished"
assert_eq "AC5 pending: the tool was not called" "0" "$(tt_calls)"
tt_setup; rgf_gh_runs "${RC_REUSE[@]}" "88|codecov/patch|completed|failure"
export PB_TEST_TT_OUT='4242\n'
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
tt_expect_suite "AC5 one other check run failed" "1 check run(s) not successful"
assert_eq "AC5 failure: the tool was not called" "0" "$(tt_calls)"
tt_setup; rgf_gh_runs "${RC_REUSE[@]}" "88|slow|queued|"
export PB_TEST_TT_OUT='4242\n'
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
tt_expect_suite "AC5 one check run queued" "1 check run(s) not finished"
assert_eq "AC5 queued: the tool was not called" "0" "$(tt_calls)"

echo "AC6 all three aggregators success: the old skip lines, word for word, and the tool is not asked"
tt_setup; real_green_runs
export PB_TEST_TT_OUT='4242\n'
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC6 green -> exit 0" 0
if has_line "$(skipped_line "$SHORT_T")" "$OUT"; then t_ok "AC6 old suite-skipped line"; else t_bad "AC6 old suite-skipped line" "$OUT"; fi
assert_not_contains "AC6 no README-skipped line" "$OUT" "README test count check skipped"
assert_not_contains "AC6 no PR-run wording" "$OUT" "PR run"
assert_eq "AC6 the suite did not run" "0" "$(suite_runs)"
assert_eq "AC6 the tool was not called" "0" "$(tt_calls)"

echo "AC7 --local-suite on the AC1 state: the suite runs, the tool is not asked"
tt_setup
export PB_TEST_TT_OUT='4242\n'
run_in "$C" bash tools/release.sh v1.2.3 --dry-run --local-suite
assert_rc "AC7 --local-suite -> exit 0" 0
assert_eq "AC7 the suite ran once" "1" "$(suite_runs)"
assert_eq "AC7 the tool was not called" "0" "$(tt_calls)"
assert_not_contains "AC7 no skip line" "$OUT" "skipped"
assert_not_contains "AC7 no 'PR run' wording" "$OUT" "PR run"

echo "AC8 the --repo argument: PB_GATE_REPO, else the origin URL"
tt_setup
export PB_GATE_REPO="o/r" PB_TEST_TT_OUT='4242\n'
rgf_gh_runs "${RC_REUSE[@]}"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_eq "AC8 PB_GATE_REPO=o/r: the tool got --repo o/r" "$HEAD_T --repo o/r" "$(cat "$TT_LOG")"
tt_setup
unset PB_GATE_REPO
OB="$(dirname "$O")/github.com/o2/r2.git"; mkdir -p "$(dirname "$OB")"
git init -q --bare "$OB" && git -C "$OB" symbolic-ref HEAD refs/heads/main && git -C "$C" push -q "$OB" main 2>/dev/null &&
  git -C "$C" remote set-url origin "$OB"
probe_repo="$(git -C "$C" remote get-url origin 2>/dev/null | sed -n 's#^.*github\.com[:/]\([^/][^/]*/[^/][^/]*\)$#\1#p' | sed 's#\.git$##; s#/$##')"
if [ "$probe_repo" = "o2/r2" ] && [ "$(git -C "$C" ls-remote origin refs/heads/main | cut -f1)" = "$HEAD_T" ]; then
  export PB_TEST_TT_OUT='4242\n'
  run_in "$C" bash tools/release.sh v1.2.3 --dry-run
  assert_rc "AC8 origin .../github.com/o2/r2.git: dry run -> exit 0" 0
  assert_eq "AC8 no PB_GATE_REPO: the tool got --repo o2/r2 (from the origin URL)" "$HEAD_T --repo o2/r2" "$(cat "$TT_LOG")"
  assert_eq "AC8 origin URL case: the suite did not run" "0" "$(suite_runs)"
else
  t_skip 3 "AC8 origin-URL case (path-shaped origin did not parse here: [$probe_repo])"
fi
export PB_GATE_REPO="acme/widgets"

echo "AC9 the stub is per case: rc_setup alone has no tools/ci-tree-tested.sh, so the old aggregator cases keep their meaning"
rc_setup
assert_no_path "AC9 rc_setup installs no ci-tree-tested.sh" "$C/tools/ci-tree-tested.sh"
unset PB_TEST_TT_OUT PB_TEST_TT_RC PB_TEST_TT_ERR PB_TEST_TT_LOG

t_summary
