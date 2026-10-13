#!/usr/bin/env bash
# Tests for tools/ship.sh (v0.11.0 AC6.1): one command from an open PR to an installed release.
#   tools/ship.sh PR vX.Y.Z [--yes]
# Everything is stubbed: a fake `gh` first on PATH, stub tools/release.sh and install.sh inside a throw-away
# git repo (bare origin + clone). The stubs append one line per call to $FAKE_LOG, so the order of the steps
# and the arguments are asserted from that log. The fake `gh pr merge` simulates the merge by pushing a commit
# (merged-N.txt) to origin's main, so `git switch main && git pull --ff-only` has something to pull.
# Prompts are answered through a pseudo-terminal (python3 pty); where none is available those assertions are
# skipped with an exact count.
# Split in v0.24.7 so that it is not the floor of a CI shard: from "AC4.1 missing or broken data prints nothing" on the sections are in test-ship-b.sh;
# shared setup (the fake gh, the stubs, fx, steps): ship-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/ship-fixture.sh"

echo "AC6.1 the script exists"
assert_file "AC6.1 tools/ship.sh exists" "$SHIP"

echo "AC6.1 --yes: the whole flow, in order"
fx
sh_run 12 v1.2.3 --yes
assert_rc "AC6.1 --yes full flow exits 0" 0
assert_eq "AC6.1/AC2.1 order with --yes: view, merge, release, CI list, CI watch, release view, install (no dry run)" "$FULL_YES" "$(steps)"
assert_contains "AC6.1 pr view is asked about PR 12" "$(grep '^gh pr view' "$FAKE_LOG" | head -n 1)" "12"
L="$(grep '^gh pr merge' "$FAKE_LOG")"
assert_contains "AC6.1 merges PR 12" "$L" "pr merge 12"
assert_contains "AC6.1 merge uses --merge" "$L" "--merge"
assert_contains "AC6.1 merge deletes the branch" "$L" "--delete-branch"
assert_eq "AC2.1 --yes: no release.sh --dry-run call at all" "0" "$(logged '^release.sh .*--dry-run')"
assert_eq "AC2.1 --yes: release.sh is called exactly once" "1" "$(logged '^release.sh')"
SKIPLINE="$(printf '%s\n' "$OUT" | grep '^== ' | grep -i 'dry' | grep -i 'skip')"
if [ -n "$SKIPLINE" ]; then t_ok "AC2.1 --yes: a '== ' line says the dry run is skipped"; else t_bad "AC2.1 --yes: a '== ' line says the dry run is skipped" "'== ' lines: $(printf '%s\n' "$OUT" | grep '^== ' | tr '\n' '|')"; fi
assert_eq "AC2.1 --yes: exactly one '== ' line talks about the dry run" "1" "$(printf '%s\n' "$OUT" | grep '^== ' | grep -ci 'dry')"
assert_eq "AC6.1 real release is exactly 'release.sh v1.2.3', on main with the merge pulled" \
  "release.sh v1.2.3 | branch=main merged=yes" "$(grep '^release.sh' "$FAKE_LOG" | grep -v -- '--dry-run')"
assert_contains "AC6.1 CI run is looked up by the tag" "$(grep '^gh run list' "$FAKE_LOG" | head -n 1)" "--branch v1.2.3"
assert_contains "AC6.1 CI run is watched with --exit-status" "$(grep '^gh run watch' "$FAKE_LOG")" "--exit-status"
assert_contains "AC6.1 release view is for the tag" "$(grep '^gh release view' "$FAKE_LOG")" "v1.2.3"
assert_eq "AC6.1 install is exactly './install.sh update --yes'" "install.sh update --yes" "$(grep '^install.sh' "$FAKE_LOG")"
assert_eq "AC6.1 the local checkout ends on main" "main" "$(cd "$F/repo" && git rev-parse --abbrev-ref HEAD)"
assert_eq "AC6.1 the local main was fast-forwarded to origin's main" "$(git -C "$F/origin.git" rev-parse main)" "$(cd "$F/repo" && git rev-parse HEAD)"
NSTEP="$(printf '%s\n' "$OUT" | grep -c '^== ')"
if [ "$NSTEP" -ge 6 ]; then t_ok "AC6.1 prints a '== ' line per step ($NSTEP lines)"; else t_bad "AC6.1 prints a '== ' line per step" "only $NSTEP lines starting with '== ' in: $OUT"; fi
assert_not_contains "AC6.1 --yes asks nothing" "$OUT" "[y/N]"

echo "AC6.1 another PR number and tag are passed through"
fx
export FAKE_PR=345 FAKE_TAG=v10.20.30
sh_run 345 v10.20.30 --yes
assert_rc "AC6.1 PR 345 / v10.20.30 exits 0" 0
assert_contains "AC6.1 merges PR 345" "$(grep '^gh pr merge' "$FAKE_LOG")" "pr merge 345"
assert_eq "AC6.1 releases v10.20.30" "release.sh v10.20.30 | branch=main merged=yes" "$(grep '^release.sh' "$FAKE_LOG" | grep -v -- '--dry-run')"
assert_contains "AC6.1 looks up the CI run of v10.20.30" "$(grep '^gh run list' "$FAKE_LOG" | head -n 1)" "--branch v10.20.30"

echo "AC6.1 refusal: the PR must be OPEN and CLEAN (nothing merged); MERGED has its own rule (v0.17.0 AC2.2 below)"
for combo in "CLOSED CLEAN" "OPEN BLOCKED" "OPEN BEHIND" "OPEN DIRTY" "OPEN UNSTABLE" "OPEN UNKNOWN" "OPEN DRAFT" "OPEN HAS_HOOKS"; do
  fx
  export FAKE_GH_STATE="${combo% *}" FAKE_GH_MERGE_STATE="${combo#* }"
  sh_run 12 v1.2.3 --yes
  assert_rc "AC6.1 state/merge-state $combo with --yes: exit 1" 1
  assert_eq "AC6.1 $combo: nothing merged, nothing released" "view" "$(steps)"
done
fx
export FAKE_GH_FAIL="prview"
sh_run 12 v1.2.3 --yes
if [ "$RC" -ne 0 ]; then t_ok "AC6.1 gh pr view failing: non-zero exit"; else t_bad "AC6.1 gh pr view failing: non-zero exit" "exit $RC; output: $OUT"; fi
assert_eq "AC6.1 gh pr view failing: nothing merged" "view" "$(steps)"

echo "AC6.1 non-interactive stdin without --yes refuses at the first question"
fx
sh_run 12 v1.2.3
assert_rc "AC6.1 closed stdin, no --yes: exit 1" 1
assert_eq "AC6.1 closed stdin, no --yes: nothing merged" "view" "$(steps)"
assert_eq "AC6.1 closed stdin: origin main is untouched" "0" "$(git -C "$F/origin.git" ls-tree -r --name-only main | grep -c '^merged-')"
fx
OUT="$(cd "$F/repo" && printf 'y\ny\n' | bash tools/ship.sh 12 v1.2.3 2>&1)"; RC=$?
assert_rc "AC6.1 piped 'y' answers without a terminal are not accepted: exit 1" 1
assert_eq "AC6.1 piped answers: nothing merged" "view" "$(steps)"

echo "AC6.1 a failing release.sh stops ship.sh with its status"
fx
export FAKE_REL_DRY_RC=7
sh_run 12 v1.2.3 --yes
assert_rc "AC2.1 --yes never runs the dry run, so a dry run that would fail with 7 does not matter: exit 0" 0
assert_eq "AC2.1 --yes with a failing dry-run stub: the full flow without dry run" "$FULL_YES" "$(steps)"
fx
export FAKE_REL_REAL_RC=5
sh_run 12 v1.2.3 --yes
assert_rc "AC6.1 real release failing with 5: ship.sh exits 5" 5
assert_eq "AC6.1 failing release: no CI wait, no release view, no install" "view merge release" "$(steps)"

echo "AC6.1 CI and release checks"
fx
export FAKE_GH_FAIL="runwatch"
sh_run 12 v1.2.3 --yes
assert_rc "AC6.1 failed CI run: exit 1" 1
assert_contains "AC6.1 failed CI run: the message names the run" "$OUT" "4242"
assert_eq "AC6.1 failed CI run: no release view, no install" "view merge release runlist runwatch" "$(steps)"
fx
export FAKE_GH_FAIL="relview"
sh_run 12 v1.2.3 --yes
if [ "$RC" -ne 0 ]; then t_ok "AC6.1 missing GitHub release: non-zero exit"; else t_bad "AC6.1 missing GitHub release: non-zero exit" "exit $RC; output: $OUT"; fi
assert_contains "AC6.1 missing release: the message names the tag" "$OUT" "v1.2.3"
assert_eq "AC6.1 missing release: install is not run" "view merge release runlist runwatch relview" "$(steps)"
fx
export FAKE_GH_FAIL="merge"
sh_run 12 v1.2.3 --yes
if [ "$RC" -ne 0 ]; then t_ok "AC6.1 gh pr merge failing: non-zero exit"; else t_bad "AC6.1 gh pr merge failing: non-zero exit" "exit $RC; output: $OUT"; fi
assert_eq "AC6.1 gh pr merge failing: release.sh is not run" "view merge" "$(steps)"

echo "review round 1: the CI run is looked up by tag, tag commit and event"
fx
sh_run 12 v1.2.3 --yes
assert_rc "R1 full flow still exits 0 (the stub release.sh tags locally)" 0
RL="$(grep '^gh run list' "$FAKE_LOG" | head -n 1)"
TAGSHA="$(cd "$F/repo" && git rev-parse 'v1.2.3^{commit}' 2>/dev/null)"
assert_eq "R1 fixture: the tag points at the merged main" "$(cd "$F/repo" && git rev-parse HEAD)" "$TAGSHA"
assert_contains "R1 run list has --branch v1.2.3" "$RL" "--branch v1.2.3"
assert_contains "R1 run list has --commit <sha of the tag>" "$RL" "--commit $TAGSHA"
assert_contains "R1 run list has --event push" "$RL" "--event push"

echo "review round 1: no CI run found (empty list, null, gh failure)"
export PB_SHIP_WAIT_TRIES=2 PB_SHIP_WAIT_SECS=0
for mode in empty null; do
  fx
  export FAKE_RUN_LIST="$mode"
  sh_run 12 v1.2.3 --yes
  assert_rc "R1 run list $mode: exit 1" 1
  assert_contains "R1 run list $mode: says no CI run found" "$OUT" "no CI run found"
  assert_contains "R1 run list $mode: names the tag" "$OUT" "v1.2.3"
  assert_eq "R1 run list $mode: never calls run watch, release view or install" "view merge release runlist" "$(steps)"
  assert_eq "R1 run list $mode: no 'run watch' call at all" "0" "$(logged '^gh run watch')"
  if [ "$(logged '^gh run list')" -ge 2 ]; then t_ok "R1 run list $mode: retried (PB_SHIP_WAIT_TRIES=2)"; else t_bad "R1 run list $mode: retried (PB_SHIP_WAIT_TRIES=2)" "run list calls: $(logged '^gh run list')"; fi
done
unset FAKE_RUN_LIST
fx
export FAKE_GH_FAIL="runlist"
sh_run 12 v1.2.3 --yes
assert_rc "R1 gh run list failing: exit 1" 1
assert_contains "R1 gh run list failing: the gh error is shown, not hidden" "$OUT" "simulated runlist failure"
assert_contains "R1 gh run list failing: same refusal, no CI run found" "$OUT" "no CI run found"
assert_eq "R1 gh run list failing: no watch, no release view, no install" "view merge release runlist" "$(steps)"
unset PB_SHIP_WAIT_TRIES PB_SHIP_WAIT_SECS

echo "review round 1: a dirty work tree is refused before anything changes"
fx
printf 'edit
' >> "$F/repo/VERSION"
sh_run 12 v1.2.3 --yes
assert_rc "R1 modified tracked file: exit 1" 1
assert_contains "R1 modified tracked file: says the tree is not clean" "$OUT" "not clean"
assert_eq "R1 modified tracked file: no gh pr merge, no release" "0" "$(logged '^gh pr merge')"
assert_eq "R1 modified tracked file: nothing after the check" "" "$(steps | sed 's/^view$//')"
fx
printf 'x
' > "$F/repo/untracked-file.txt"
sh_run 12 v1.2.3 --yes
assert_rc "R1 untracked file: exit 1" 1
assert_contains "R1 untracked file: says the tree is not clean" "$OUT" "not clean"
assert_eq "R1 untracked file: no gh pr merge" "0" "$(logged '^gh pr merge')"
assert_eq "R1 untracked file: no release.sh or install.sh call" "0" "$(logged '^release.sh\|^install.sh')"

echo "AC6.1 usage errors exit 2 and touch nothing"
fx
usage_case() { local name="$1"; shift; sh_run "$@"; assert_rc "AC6.1 usage: $name" 2; }
usage_case "no arguments"
usage_case "PR without a tag" 12
usage_case "PR is not a number (abc)" abc v1.2.3
usage_case "PR is not a number (12x)" 12x v1.2.3
usage_case "PR is negative" -5 v1.2.3
usage_case "tag without the v (1.2.3)" 12 1.2.3
usage_case "tag with two parts (v1.2)" 12 v1.2
usage_case "tag with a suffix (v1.2.3-rc1)" 12 v1.2.3-rc1
usage_case "unknown option (--force)" 12 v1.2.3 --force
usage_case "unknown option before the arguments (--bogus)" --bogus 12 v1.2.3
usage_case "--auto alone, without a PR and a tag (v0.17.0)" --auto
usage_case "--auto and --yes but no PR and no tag (v0.17.0)" --yes --auto
usage_case "--auto with a PR but no tag (v0.17.0)" 12 --auto
assert_eq "AC6.1 usage errors: gh, release.sh and install.sh were never called" "" "$(steps)"
assert_eq "AC6.1 usage errors: the log is empty" "0" "$(wc -l < "$FAKE_LOG" | tr -d ' ')"

echo "v0.13.0 AC1.1 ship merges from main, whatever the clone was on"
merge_at() { grep '^merge-at ' "$FAKE_LOG" | head -n 1; }
# lines printed before the merge step
before_merge() { printf '%s\n' "$OUT" | awk '/^== merge PR/ { exit } { print }'; }
fx   # default fixture: the clone is on the branch feat/x
sh_run 12 v1.2.3 --yes
assert_rc "AC1.1 on another branch: exit 0" 0
assert_eq "AC1.1 on another branch: gh pr merge ran while the clone was on main" "merge-at main" "$(merge_at)"
assert_eq "AC1.1 on another branch: the full flow ran" "$FULL_YES" "$(steps)"
if before_merge | grep '^== ' | grep -q 'main'; then t_ok "AC1.1 on another branch: a '== ' line before the merge says it switches to main"
else t_bad "AC1.1 on another branch: a '== ' line before the merge says it switches to main" "output before the merge: $(before_merge)"; fi
fx
( cd "$F/repo" && git checkout -q --detach )
assert_eq "AC1.1 fixture check: the clone starts on a detached HEAD" "HEAD" "$(cd "$F/repo" && git rev-parse --abbrev-ref HEAD)"
sh_run 12 v1.2.3 --yes
assert_rc "AC1.1 detached HEAD: exit 0" 0
assert_eq "AC1.1 detached HEAD: gh pr merge ran while the clone was on main" "merge-at main" "$(merge_at)"
assert_eq "AC1.1 detached HEAD: the full flow ran" "$FULL_YES" "$(steps)"
assert_eq "AC1.1 detached HEAD: the local main got the merge" "$(git -C "$F/origin.git" rev-parse main)" "$(cd "$F/repo" && git rev-parse HEAD)"
if before_merge | grep '^== ' | grep -q 'main'; then t_ok "AC1.1 detached HEAD: a '== ' line before the merge says it switches to main"
else t_bad "AC1.1 detached HEAD: a '== ' line before the merge says it switches to main" "output before the merge: $(before_merge)"; fi
fx
( cd "$F/repo" && git switch -q main )
sh_run 12 v1.2.3 --yes
assert_rc "AC1.1 already on main: exit 0" 0
assert_eq "AC1.1 already on main: gh pr merge ran on main" "merge-at main" "$(merge_at)"
echo "AC1.1 the switch to main fails: refuse before merging"
for start in branch detached; do
  fx
  [ "$start" = detached ] && ( cd "$F/repo" && git checkout -q --detach )
  before="$(cd "$F/repo" && git rev-parse --abbrev-ref HEAD)"
  # main is checked out in a second work tree, so 'git switch main' fails in the clone
  git -C "$F/repo" worktree add -q "$F/wt" main >/dev/null 2>&1
  sh_run 12 v1.2.3 --yes
  assert_rc "AC1.1 ($start) switch to main impossible: exit 1" 1
  assert_eq "AC1.1 ($start) switch impossible: gh pr merge never called" "0" "$(logged '^gh pr merge')"
  assert_eq "AC1.1 ($start) switch impossible: no release, no install" "0" "$(logged '^release.sh\|^install.sh')"
  assert_eq "AC1.1 ($start) switch impossible: origin main is untouched" "0" "$(git -C "$F/origin.git" ls-tree -r --name-only main | grep -c '^merged-')"
  assert_eq "AC1.1 ($start) switch impossible: the clone stays where it was" "$before" "$(cd "$F/repo" && git rev-parse --abbrev-ref HEAD)"
done

echo "v0.13.0 AC1.2 after install.sh update the clone is back on main"
fx
export FAKE_INSTALL_DETACH=1
sh_run 12 v1.2.3 --yes
unset FAKE_INSTALL_DETACH
assert_rc "AC1.2 install leaves a detached HEAD: ship still exits 0" 0
assert_eq "AC1.2 the clone ends on main, not on a detached HEAD" "main" "$(cd "$F/repo" && git rev-parse --abbrev-ref HEAD)"
AFTER_INSTALL="$(printf '%s\n' "$OUT" | awk 'f { print } /^== update the installs/ { f = 1 }')"
assert_contains "AC1.2 the output after the install step names the branch it ends on" "$AFTER_INSTALL" "main"
fx
sh_run 12 v1.2.3 --yes
assert_eq "AC1.2 install leaves the branch alone: still on main" "main" "$(cd "$F/repo" && git rev-parse --abbrev-ref HEAD)"

echo "v0.13.0 AC1.3 invalid PB_SHIP_WAIT_* values exit 2 before anything is called"
for kv in "TRIES=abc" "TRIES=-1" "TRIES=1.5" "SECS=x" "SECS=-2" "SECS=0.5" "TRIES=4x"; do
  fx
  export "PB_SHIP_WAIT_${kv%%=*}=${kv#*=}"
  sh_run 12 v1.2.3 --yes
  unset PB_SHIP_WAIT_TRIES PB_SHIP_WAIT_SECS
  assert_rc "AC1.3 PB_SHIP_WAIT_$kv: exit 2" 2
  assert_eq "AC1.3 PB_SHIP_WAIT_$kv: gh, release.sh and install.sh were never called" "0" "$(wc -l < "$FAKE_LOG" | tr -d ' ')"
  assert_eq "AC1.3 PB_SHIP_WAIT_$kv: origin main is untouched" "0" "$(git -C "$F/origin.git" ls-tree -r --name-only main | grep -c '^merged-')"
done
fx
export PB_SHIP_WAIT_TRIES=3 PB_SHIP_WAIT_SECS=0
sh_run 12 v1.2.3 --yes
unset PB_SHIP_WAIT_TRIES PB_SHIP_WAIT_SECS
assert_rc "AC1.3 valid integers still ship" 0

echo "v0.14.0 AC1.1 ship survives the merge commit rewriting tools/ship.sh while it runs"
# the whole body is a function, called by the last line, so bash has read all of it before `git pull` runs
LASTLINE="$(grep -v '^[[:space:]]*$' "$SHIP" 2>/dev/null | tail -n 1)"
assert_eq "AC1.1 the last line of tools/ship.sh is exactly: main \"\$@\"; exit \$?" 'main "$@"; exit $?' "$LASTLINE"
assert_eq "AC1.1 tools/ship.sh defines main() exactly once" "1" "$(grep -cE '^main *\(\) *\{' "$SHIP" 2>/dev/null)"
assert_eq "AC1.1 main is called exactly once (nothing else calls it)" "1" "$(grep -cE '^main( |$)' "$SHIP" 2>/dev/null | head -n 1)"
for mode in exit99 trunc grow; do
  fx
  export FAKE_REWRITE_SHIP="$mode"
  sh_run 12 v1.2.3 --yes
  export FAKE_REWRITE_SHIP=""
  assert_eq "AC1.1 [$mode] the merge commit really rewrote tools/ship.sh in the fixture (fixture check)" "1" \
    "$([ "$(cd "$F/repo" && git rev-parse HEAD:tools/ship.sh)" != "$(git hash-object "$SHIP")" ] && echo 1 || echo 0)"
  assert_rc "AC1.1 [$mode] ship still exits 0 although tools/ship.sh was replaced mid-run" 0
  assert_eq "AC1.1 [$mode] every step still ran, in order" "$FULL_YES" "$(steps)"
  assert_contains "AC1.1 [$mode] the last message is still printed" "$OUT" "shipped v1.2.3"
  assert_eq "AC1.1 [$mode] the clone still ends on main" "main" "$(cd "$F/repo" && git rev-parse --abbrev-ref HEAD)"
done

# ---- v0.17.0: gh call shapes the tests fix (the implementer must use exactly these) ----
#  PR check:     gh pr view PR --json state,mergeStateStatus,mergeCommit --jq '...'   (gh prints mergeCommit as {"oid": "SHA"}, null until merged)
#  auto-merge:   gh pr merge PR --auto --merge --delete-branch     (exactly this argument order)
#  shard report: gh run list --branch main --event push --commit SHA --limit 1 --json databaseId [--jq ...]
#                gh run view RUN --json jobs                       (no --jq: parse the JSON with node, as tools/shard-weights.sh does)
#                jobs named "windows shard K/N" carry startedAt/completedAt; a job still running has completedAt 0001-01-01T00:00:00Z

echo "v0.17.0 AC2.1 --auto: an OPEN PR that is not CLEAN yet gets GitHub auto-merge and ship stops without releasing"
for st in BLOCKED UNSTABLE; do
  fx
  export FAKE_GH_MERGE_STATE="$st"
  sh_run 12 v1.2.3 --yes --auto
  assert_rc "AC2.1 OPEN/$st with --auto: exit 0" 0
  assert_eq "AC2.1 OPEN/$st with --auto: exactly one merge call, '$AUTO_MERGE_CALL'" "$AUTO_MERGE_CALL" "$(grep '^gh pr merge' "$FAKE_LOG")"
  assert_eq "AC2.1 OPEN/$st with --auto: only the PR check and the auto-merge call (no release, CI wait or install)" "view merge" "$(steps)"
  assert_eq "AC2.1 OPEN/$st with --auto: no release.sh and no install.sh call" "0" "$(logged '^release.sh\|^install.sh')"
  assert_eq "AC2.1 OPEN/$st with --auto: no tag was created" "" "$(git -C "$F/repo" tag)"
  assert_eq "AC2.1 OPEN/$st with --auto: nothing was merged into origin's main yet" "0" "$(origin_merges)"
  assert_contains "AC2.1 OPEN/$st with --auto: says auto-merge was enabled" "$OUT" "auto-merge"
  assert_contains "AC2.1 OPEN/$st with --auto: says it will merge when the checks pass" "$OUT" "will merge when the checks pass"
  assert_contains "AC2.1 OPEN/$st with --auto: names the command to run again (PR and tag)" "$OUT" "tools/ship.sh 12 v1.2.3"
  assert_contains "AC2.1 OPEN/$st with --auto: says to run ship again" "$OUT" "again"
  assert_not_contains "AC2.1 OPEN/$st with --auto: does not claim the release is shipped" "$OUT" "shipped v1.2.3"
done
fx
export FAKE_PR=345 FAKE_TAG=v10.20.30 FAKE_GH_MERGE_STATE=BLOCKED
sh_run --auto 345 v10.20.30 --yes   # the option may come first; another PR and tag
assert_rc "AC2.1 --auto before the arguments, PR 345: exit 0" 0
assert_eq "AC2.1 --auto PR 345: the merge call carries PR 345" "gh pr merge 345 --auto --merge --delete-branch" "$(grep '^gh pr merge' "$FAKE_LOG")"
assert_contains "AC2.1 --auto PR 345: the run-again command names PR 345 and v10.20.30" "$OUT" "tools/ship.sh 345 v10.20.30"
fx
export FAKE_GH_MERGE_STATE=BLOCKED
sh_run 12 v1.2.3 --auto --yes
assert_rc "AC2.1 '--auto --yes' (either order): exit 0" 0
assert_eq "AC2.1 '--auto --yes': one auto-merge call" "$AUTO_MERGE_CALL" "$(grep '^gh pr merge' "$FAKE_LOG")"
echo "AC2.1 --auto on a CLEAN PR merges and releases as usual; without --auto a non-CLEAN PR is still refused"
fx
sh_run 12 v1.2.3 --yes --auto
assert_rc "AC2.1 CLEAN PR with --auto: exit 0" 0
assert_eq "AC2.1 CLEAN PR with --auto: the whole flow ran" "$FULL_YES" "$(steps)"
assert_eq "AC2.1 CLEAN PR with --auto: a plain merge call, no --auto in it" "gh pr merge 12 --merge --delete-branch" "$(grep '^gh pr merge' "$FAKE_LOG")"
assert_eq "AC2.1 CLEAN PR with --auto: released from main with the merge pulled" "release.sh v1.2.3 | branch=main merged=yes" "$(grep '^release.sh' "$FAKE_LOG" | grep -v -- '--dry-run')"
for st in BLOCKED UNSTABLE; do
  fx
  export FAKE_GH_MERGE_STATE="$st"
  sh_run 12 v1.2.3 --yes
  assert_rc "AC2.1 OPEN/$st without --auto is still refused: exit 1" 1
  assert_eq "AC2.1 OPEN/$st without --auto: no merge call at all (not even an auto-merge)" "view" "$(steps)"
done
echo "AC2.1 --auto does not make other states acceptable"
fx
export FAKE_GH_STATE=CLOSED FAKE_GH_MERGE_STATE=BLOCKED
sh_run 12 v1.2.3 --yes --auto
assert_rc "AC2.1 CLOSED PR with --auto: exit 1" 1
assert_eq "AC2.1 CLOSED PR with --auto: nothing merged, nothing released" "view" "$(steps)"
fx
export FAKE_GH_MERGE_STATE=BLOCKED FAKE_GH_FAIL="merge"
sh_run 12 v1.2.3 --yes --auto
if [ "$RC" -ne 0 ]; then t_ok "AC2.1 enabling auto-merge fails (gh error): non-zero exit"; else t_bad "AC2.1 enabling auto-merge fails (gh error): non-zero exit" "exit $RC; output: $OUT"; fi
assert_eq "AC2.1 enabling auto-merge fails: no release, no install" "view merge" "$(steps)"
assert_not_contains "AC2.1 enabling auto-merge fails: does not say auto-merge is on" "$OUT" "will merge when the checks pass"

echo "v0.17.0 AC2.2 a PR already MERGED (auto-merge) whose merge commit is on origin/main goes on to the release"
fx
merged_on_main
assert_eq "AC2.2 fixture: the merge commit is not in the local clone yet (ship must fetch to see it on origin/main)" "no" \
  "$(git -C "$F/repo" cat-file -e "$MC^{commit}" 2>/dev/null && echo yes || echo no)"
sh_run 12 v1.2.3 --yes
assert_rc "AC2.2 MERGED, merge commit on origin/main: exit 0" 0
assert_eq "AC2.2 MERGED: no merge call; update main, release, CI, release check, install ran" "$MERGED_YES" "$(steps)"
assert_eq "AC2.2 MERGED: gh pr merge was never called" "0" "$(logged '^gh pr merge')"
assert_eq "AC2.2 MERGED: exactly one '== ' line says the PR is already merged" "1" "$(printf '%s\n' "$OUT" | grep '^== ' | grep -ci 'already merged')"
assert_eq "AC2.2 MERGED: no '== merge PR' step line" "0" "$(printf '%s\n' "$OUT" | grep -c '^== merge PR')"
assert_eq "AC2.2 MERGED: released from main with the merge commit pulled" "release.sh v1.2.3 | branch=main merged=yes" "$(grep '^release.sh' "$FAKE_LOG" | grep -v -- '--dry-run')"
assert_eq "AC2.2 MERGED: the local main is at origin's main" "$(git -C "$F/origin.git" rev-parse main)" "$(cd "$F/repo" && git rev-parse HEAD)"
assert_eq "AC2.2 MERGED: the local main has the merge commit" "yes" "$(git -C "$F/repo" cat-file -e "$MC^{commit}" 2>/dev/null && echo yes || echo no)"
assert_contains "AC2.2 MERGED: the last message is still printed" "$OUT" "shipped v1.2.3"
assert_eq "AC2.2 MERGED: the clone ends on main" "main" "$(cd "$F/repo" && git rev-parse --abbrev-ref HEAD)"
for ms in UNKNOWN BLOCKED DIRTY; do   # gh reports no useful merge state for a merged PR: only state and commit count
  fx
  merged_on_main
  export FAKE_GH_MERGE_STATE="$ms"
  sh_run 12 v1.2.3 --yes
  assert_rc "AC2.2 MERGED with merge state $ms and the commit on origin/main: exit 0" 0
  assert_eq "AC2.2 MERGED/$ms: the merged flow ran" "$MERGED_YES" "$(steps)"
done
fx
merged_on_main
sh_run 12 v1.2.3 --yes --auto
assert_rc "AC2.2 MERGED with --auto: exit 0" 0
assert_eq "AC2.2 MERGED with --auto: still no merge call (not even an auto-merge)" "0" "$(logged '^gh pr merge')"
assert_eq "AC2.2 MERGED with --auto: the merged flow ran" "$MERGED_YES" "$(steps)"
fx
merged_on_main
sh_run 12 v1.2.3
assert_rc "AC2.2 MERGED, closed stdin, no --yes: stops at the tag question: exit 1" 1
assert_eq "AC2.2 MERGED, closed stdin: no merge question, the dry run ran, nothing was tagged" "view dry" "$(steps)"
assert_not_contains "AC2.2 MERGED, closed stdin: the merge question is skipped" "$OUT" "merge PR #12?"
fx
merged_on_main
export FAKE_REL_REAL_RC=5
sh_run 12 v1.2.3 --yes
assert_rc "AC2.2 MERGED: a failing release.sh (5) still stops ship with its status" 5
assert_eq "AC2.2 MERGED with a failing release: nothing after it" "view release" "$(steps)"

echo "AC2.2 refused: MERGED but the merge commit is not on origin/main, or no merge commit; CLOSED"
fx
export FAKE_GH_STATE=MERGED FAKE_GH_MERGE_COMMIT=0123456789abcdef0123456789abcdef01234567
sh_run 12 v1.2.3 --yes
assert_rc "AC2.2 MERGED with a commit unknown to origin: exit 1" 1
assert_eq "AC2.2 MERGED with an unknown commit: nothing merged or released" "view" "$(steps)"
assert_contains "AC2.2 MERGED with an unknown commit: the refusal names origin/main" "$OUT" "origin/main"
assert_eq "AC2.2 MERGED with an unknown commit: gh pr merge never called" "0" "$(logged '^gh pr merge')"
fx
side_commit
export FAKE_GH_STATE=MERGED FAKE_GH_MERGE_COMMIT="$MC"
sh_run 12 v1.2.3 --yes
assert_rc "AC2.2 MERGED with a commit that is on origin but not on main: exit 1" 1
assert_eq "AC2.2 MERGED with a side-branch commit: nothing merged or released" "view" "$(steps)"
assert_contains "AC2.2 MERGED with a side-branch commit: the refusal names origin/main" "$OUT" "origin/main"
fx
export FAKE_GH_STATE=MERGED FAKE_GH_MERGE_STATE=CLEAN FAKE_GH_MERGE_COMMIT=""
sh_run 12 v1.2.3 --yes
assert_rc "AC2.2 MERGED with no merge commit reported: exit 1" 1
assert_eq "AC2.2 MERGED with no merge commit: nothing merged or released" "view" "$(steps)"
fx
merged_on_main
export FAKE_GH_STATE=CLOSED
sh_run 12 v1.2.3 --yes
assert_rc "AC2.2 CLOSED with a commit that is on origin/main: exit 1" 1
assert_eq "AC2.2 CLOSED: nothing merged or released" "view" "$(steps)"

echo "v0.17.0 AC4.1 unbalanced windows shards are reported after the tag's CI passes"
fx
export FAKE_SHARDS="300,100,200"
sh_run 12 v1.2.3 --yes
assert_rc "AC4.1 shards 300/100/200 s: ship still succeeds (exit 0)" 0
assert_eq "AC4.1 unbalanced: the whole flow ran as before" "$FULL_YES" "$(steps)"
assert_eq "AC4.1 unbalanced: one line names the shortest, the longest and the run id" "1" \
  "$(printf '%s\n' "$OUT" | grep -cF 'shards unbalanced (100 s .. 300 s): run tools/shard-weights.sh 7777')"
assert_eq "AC4.1 unbalanced: only one line talks about it" "1" "$(unb)"
assert_contains "AC4.1 unbalanced: shipped is still printed" "$OUT" "shipped v1.2.3"
TAGSHA="$(cd "$F/repo" && git rev-parse 'v1.2.3^{commit}' 2>/dev/null)"
assert_eq "AC4.1 exactly one lookup of the push-to-main run" "1" "$(shard_calls | wc -l | tr -d ' ')"
assert_contains "AC4.1 the lookup is for branch main" "$(shard_calls)" "--branch main"
assert_contains "AC4.1 the lookup is for event push" "$(shard_calls)" "--event push"
assert_contains "AC4.1 the lookup is for the release commit (the tag's commit)" "$(shard_calls)" "--commit $TAGSHA"
assert_eq "AC4.1/AC3.1 unbalanced: the jobs of that run are read twice, ship's own read and shard-weights.sh's: gh run view 7777 --json jobs" "2" "$(grep -c '^gh run view 7777 .*--json jobs' "$FAKE_LOG")"
WATCHN="$(grep -n '^gh run watch' "$FAKE_LOG" | head -n 1 | cut -d: -f1)"; VIEWN="$(grep -n '^gh run view' "$FAKE_LOG" | head -n 1 | cut -d: -f1)"
if [ -n "$WATCHN" ] && [ -n "$VIEWN" ] && [ "$VIEWN" -gt "$WATCHN" ]; then t_ok "AC4.1 the shard jobs are read after the CI run was watched"; else t_bad "AC4.1 the shard jobs are read after the CI run was watched" "watch at log line [$WATCHN], run view at [$VIEWN]"; fi
fx
export FAKE_SHARDS="250,100" FAKE_MAIN_RUN=9191
sh_run 12 v1.2.3 --yes
assert_eq "AC4.1 another run id (9191) and two shards: the hint names 9191" "1" "$(printf '%s\n' "$OUT" | grep -cF 'shards unbalanced (100 s .. 250 s): run tools/shard-weights.sh 9191')"
assert_not_contains "AC4.1 the hint names the push-to-main run, not the tag's run (4242)" "$OUT" "shard-weights.sh 4242"
echo "AC4.1 balanced shards print nothing (the other jobs of the run, 900 s and 30 s, are not shards)"
for sh in "100,120,110" "150,100" "100,100,100" "300"; do
  fx
  export FAKE_SHARDS="$sh"
  sh_run 12 v1.2.3 --yes
  assert_rc "AC4.1 shards [$sh]: exit 0" 0
  assert_eq "AC4.1 shards [$sh]: no unbalanced line (longest is not more than 1.5x the shortest)" "0" "$(unb)"
  assert_eq "AC4.1 shards [$sh]: the jobs were looked at (one gh run view)" "1" "$(logged '^gh run view')"
  assert_eq "AC4.1/AC3.1 shards [$sh]: balanced, the jobs of the run are read exactly once (no refresh read)" "1" "$(grep -c '^gh run view 7777 .*--json jobs' "$FAKE_LOG")"
done
fx
export FAKE_SHARDS="151,100"
sh_run 12 v1.2.3 --yes
assert_eq "AC4.1 151 s against 100 s is more than 1.5x: reported" "1" "$(printf '%s\n' "$OUT" | grep -cF 'shards unbalanced (100 s .. 151 s)')"
fx
export FAKE_SHARDS="300,100,running"
sh_run 12 v1.2.3 --yes
assert_eq "AC4.1 a shard without a finish time is ignored, the others are compared (100 s .. 300 s)" "1" "$(printf '%s\n' "$OUT" | grep -cF 'shards unbalanced (100 s .. 300 s)')"
fx
export FAKE_SHARDS="100,running"
sh_run 12 v1.2.3 --yes
assert_rc "AC4.1 one finished shard and one unfinished: exit 0" 0
assert_eq "AC4.1 one finished shard and one unfinished: nothing to compare, no hint" "0" "$(unb)"
t_summary
