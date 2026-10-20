#!/usr/bin/env bash
# Tests for tools/ship.sh (v0.11.0 AC6.1): the last part of test-ship.sh (split in v0.24.7, and again in v0.24.19 into test-ship.sh, test-ship-c.sh and this file, so that it is not the floor of a CI shard), from "AC4.1 missing or broken
# data prints nothing" to the end (shard report and weight refresh, prompts on a terminal, the PR run as the data source, the eval guard hint).
# Everything is stubbed as in test-ship.sh; shared setup: ship-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/ship-fixture.sh"

echo "AC4.1 missing or broken data prints nothing and never fails the ship"
fx
export FAKE_SHARDS=none
sh_run 12 v1.2.3 --yes
assert_rc "AC4.1 the run has no shard jobs: exit 0" 0
assert_eq "AC4.1 no shard jobs: no hint, the flow ran" "0 $FULL_YES" "$(unb) $(steps)"
fx
export FAKE_SHARDS=bad
sh_run 12 v1.2.3 --yes
assert_rc "AC4.1 gh run view prints something that is not JSON: exit 0" 0
assert_eq "AC4.1 not JSON: no hint, the flow ran" "0 $FULL_YES" "$(unb) $(steps)"
assert_not_contains "AC4.1 not JSON: no parser noise on the terminal" "$OUT" "SyntaxError"
for mode in empty null; do
  fx
  export FAKE_SHARDS="300,100" FAKE_SHARD_LIST="$mode"
  sh_run 12 v1.2.3 --yes
  assert_rc "AC4.1 no push-to-main run found ($mode): exit 0" 0
  assert_eq "AC4.1 no push-to-main run found ($mode): no hint, the flow ran" "0 $FULL_YES" "$(unb) $(steps)"
  assert_eq "AC4.1 no push-to-main run found ($mode): gh run view is not called" "0" "$(logged '^gh run view')"
done
for word in shardlist shardview; do
  fx
  export FAKE_SHARDS="300,100" FAKE_GH_FAIL="$word"
  sh_run 12 v1.2.3 --yes
  assert_rc "AC4.1 gh failing in the shard report ($word): exit 0" 0
  assert_eq "AC4.1 gh failing ($word): no hint, the flow ran" "0 $FULL_YES" "$(unb) $(steps)"
  assert_contains "AC4.1 gh failing ($word): shipped is still printed" "$OUT" "shipped v1.2.3"
done
fx
export FAKE_SHARDS="300,100" FAKE_GH_FAIL="runwatch"
sh_run 12 v1.2.3 --yes
assert_rc "AC4.1 the tag's CI run failed: exit 1 as before" 1
assert_eq "AC4.1 CI failed: no shard report (no hint, no gh run view)" "0 0" "$(unb) $(logged '^gh run view')"

echo "v0.22.2 AC3 ship refreshes the shard weights when the shards are unbalanced"
WN='.agents/handoff/shard-weights.next'
refreshed() { printf '%s\n' "$OUT" | grep -cF 'shard weights refreshed: copy .agents/handoff/shard-weights.next to tests/shard-weights in the next PR'; }
notref() { printf '%s\n' "$OUT" | grep -c 'shard weights not refreshed'; }
subjects() { git -C "$1" log --format=%s main | tr '\n' '|'; }
fx
export FAKE_SHARDS="300,100,200"
W_BEFORE="$(cat "$F/repo/tests/shard-weights")"
assert_no_path "AC3.1 before the run there is no .agents/handoff in the fixture" "$F/repo/.agents/handoff"
sh_run 12 v1.2.3 --yes
assert_rc "AC3.1 unbalanced: ship succeeds (exit 0)" 0
assert_eq "AC3.1 unbalanced: the whole flow ran as before" "$FULL_YES" "$(steps)"
assert_dir "AC3.1 unbalanced: .agents/handoff was created" "$F/repo/.agents/handoff"
assert_file "AC3.1 unbalanced: .agents/handoff/shard-weights.next was written" "$F/repo/$WN"
assert_eq "AC3.1 unbalanced: one 'shard weights refreshed: copy ...' line" "1" "$(refreshed)"
assert_eq "AC3.1 unbalanced: no 'not refreshed' line" "0" "$(notref)"
assert_contains "AC3.1 unbalanced: shipped is still printed" "$OUT" "shipped v1.2.3"
WNTXT="$(cat "$F/repo/$WN" 2>/dev/null)"
assert_contains "AC3.1 the weights file names the main push run (7777)" "$WNTXT" "run 7777"
assert_contains "AC3.1 the weights file has the suite timings from the shard logs (test-big.sh 120)" "$WNTXT" "test-big.sh 120"
assert_contains "AC3.1 the weights file has the other suite (test-small.sh 7)" "$WNTXT" "test-small.sh 7"
assert_contains "AC3.1 the refresh reads the shard jobs of run 7777 (gh run view 7777 --json jobs)" "$(grep '^gh run view' "$FAKE_LOG")" "7777"
assert_contains "AC3.1 the refresh reads a shard job log (gh run view --job)" "$(grep '^gh run view' "$FAKE_LOG")" "--job"
assert_eq "AC3.1 tests/shard-weights is unchanged" "$W_BEFORE" "$(cat "$F/repo/tests/shard-weights")"
assert_eq "AC3.1 git sees no change under tests/" "" "$(git -C "$F/repo" status --porcelain -- tests)"
assert_eq "AC3.1 no commit was made on main (only init and the fake merge)" "merge PR 12|init|" "$(subjects "$F/repo")"
assert_eq "AC3.1 nothing was pushed (origin main has only init and the fake merge)" "merge PR 12|init|" "$(subjects "$F/origin.git")"

fx
export FAKE_SHARDS="300,100,200" FAKE_GH_FAIL="shardlog"
sh_run 12 v1.2.3 --yes
assert_rc "AC3.1 shard-weights.sh fails: ship still exits 0" 0
assert_eq "AC3.1 shard-weights.sh fails: the flow ran" "$FULL_YES" "$(steps)"
assert_eq "AC3.1 shard-weights.sh fails (gh exit 3): 'shard weights not refreshed (shard-weights.sh exit 3)'" "1" \
  "$(printf '%s\n' "$OUT" | grep -cF 'shard weights not refreshed (shard-weights.sh exit 3)')"
assert_eq "AC3.1 shard-weights.sh fails: no 'refreshed: copy' line" "0" "$(refreshed)"
assert_no_path "AC3.1 shard-weights.sh fails: no .next file" "$F/repo/$WN"
assert_contains "AC3.1 shard-weights.sh fails: shipped is still printed" "$OUT" "shipped v1.2.3"
assert_eq "AC3.1 shard-weights.sh fails: tests/shard-weights is unchanged" "$W_BEFORE" "$(cat "$F/repo/tests/shard-weights")"

fx
export FAKE_SHARDS="300,100,200" FAKE_SHARD_LOG=none
sh_run 12 v1.2.3 --yes
assert_rc "AC3.1 no timings in the logs: ship still exits 0" 0
assert_eq "AC3.1 no timings (shard-weights.sh exit 1): 'shard weights not refreshed (shard-weights.sh exit 1)'" "1" \
  "$(printf '%s\n' "$OUT" | grep -cF 'shard weights not refreshed (shard-weights.sh exit 1)')"
assert_eq "AC3.1 no timings: no 'refreshed: copy' line" "0" "$(refreshed)"

echo "v0.24.19 AC5 six Windows shard jobs: the unbalanced hint is computed over all six"
fx
export FAKE_SHARDS="300,250,200,150,120,80"
sh_run 12 v1.2.3 --yes
assert_rc "AC5 six shards: exit 0" 0
assert_eq "AC5 six shards: one 'shards unbalanced' hint" "1" "$(unb)"
assert_contains "AC5 six shards: the hint spans the shortest (6th) and the longest (1st) of the six" "$OUT" "shards unbalanced (80 s .. 300 s)"
fx
export FAKE_SHARDS="100,100,100,100,100,200"
sh_run 12 v1.2.3 --yes
assert_eq "AC5 six shards, only the sixth is slow: the hint is there (the first five alone are balanced)" "1" "$(unb)"
assert_contains "AC5 six shards, only the sixth is slow: the hint names 100 s .. 200 s" "$OUT" "shards unbalanced (100 s .. 200 s)"
fx
export FAKE_SHARDS="100,110,120,130,140,150"
sh_run 12 v1.2.3 --yes
assert_eq "AC5 six balanced shards (150 s is not above 1.5 x 100 s): no hint" "0" "$(unb)"

echo "v0.22.2 AC3 balanced shards: no refresh"
fx
export FAKE_SHARDS="100,110,120"
sh_run 12 v1.2.3 --yes
assert_rc "AC3.1 balanced: exit 0" 0
assert_eq "AC3.1 balanced: no 'shard weights' line at all" "0" "$(printf '%s\n' "$OUT" | grep -c 'shard weights')"
assert_no_path "AC3.1 balanced: no .agents/handoff" "$F/repo/.agents/handoff"
assert_eq "AC3.1 balanced: the shard logs were not fetched (no gh run view --job)" "0" "$(logged '^gh run view .*--job')"
fx
export FAKE_SHARDS="300,100,200" FAKE_GH_FAIL="shardview"
sh_run 12 v1.2.3 --yes
assert_eq "AC3.1 no shard data (gh failed): no 'shard weights' line" "0" "$(printf '%s\n' "$OUT" | grep -c 'shard weights')"
assert_no_path "AC3.1 no shard data: no .agents/handoff" "$F/repo/.agents/handoff"
unset FAKE_SHARD_LOG

# ---- prompts, through a pseudo-terminal ----
PTY_OK=0
if [ -z "${PB_NO_PTY:-}" ] && command -v python3 >/dev/null 2>&1; then
  OUT="$(python3 "$W/ptyrun.py" -- bash -c '[ -t 0 ] && echo isatty' 2>/dev/null)"
  case "$OUT" in *isatty*) PTY_OK=1 ;; esac
fi
# pty_ship ANSWERS... -- ship args... : answers the "[y/N]" prompts in order
pty_ship() {
  local ans=() a
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do ans+=("$1"); shift; done
  shift
  OUT="$(cd "$F/repo" && python3 "$W/ptyrun.py" "${ans[@]}" -- bash tools/ship.sh "$@" 2>&1)"; RC=$?
}
pty_block() {
  echo "AC6.1 prompts answered on a terminal"
  fx
  pty_ship y y -- 12 v1.2.3
  assert_rc "AC6.1 answers y, y: exit 0" 0
  assert_eq "AC6.1 answers y, y: the full flow ran in order" "$FULL" "$(steps)"
  assert_contains "AC6.1 the first question is 'merge PR #12?'" "$OUT" "merge PR #12? [y/N]"
  assert_contains "AC6.1 the second question is 'tag and push v1.2.3?'" "$OUT" "tag and push v1.2.3? [y/N]"
  assert_eq "AC2.1 with the questions the dry run stays: exactly 'release.sh v1.2.3 --dry-run', on main with the merge pulled" \
    "release.sh v1.2.3 --dry-run | branch=main merged=yes" "$(grep '^release.sh .*--dry-run' "$FAKE_LOG")"
  assert_eq "AC2.1 with the questions: no '== ' line says the dry run is skipped" "0" "$(printf '%s\n' "$OUT" | grep '^== ' | grep -i 'dry' | grep -ci 'skip')"
  fx
  pty_ship yes yes -- 12 v1.2.3
  assert_rc "AC6.1 answers yes, yes: exit 0" 0
  assert_eq "AC6.1 answers yes, yes: the full flow ran" "$FULL" "$(steps)"
  for ans in n "" no maybe N; do
    fx
    pty_ship "$ans" -- 12 v1.2.3
    assert_rc "AC6.1 first answer [$ans]: exit 1" 1
    assert_eq "AC6.1 first answer [$ans]: only the PR check ran, nothing merged" "view" "$(steps)"
    assert_eq "AC6.1 first answer [$ans]: origin main is untouched" "0" "$(git -C "$F/origin.git" ls-tree -r --name-only main | grep -c '^merged-')"
  done
  fx
  pty_ship y n -- 12 v1.2.3
  assert_rc "AC6.1 second answer n: exit 1" 1
  assert_eq "AC6.1 second answer n: merged and dry-ran, but did not tag" "view merge dry" "$(steps)"
  fx
  pty_ship y "" -- 12 v1.2.3
  assert_rc "AC6.1 second answer empty: exit 1" 1
  assert_eq "AC6.1 second answer empty: did not tag" "view merge dry" "$(steps)"
  fx
  export FAKE_REL_DRY_RC=7
  pty_ship y y -- 12 v1.2.3
  assert_rc "AC2.1 with the questions a failing dry run (7) still stops ship.sh with its status" 7
  assert_eq "AC2.1 with the questions a failing dry run: no real release, nothing after" "view merge dry" "$(steps)"
  fx
  pty_ship -- 12 v1.2.3 --yes
  assert_rc "AC6.1 --yes on a terminal: exit 0 without any answer" 0
  assert_eq "AC2.1 --yes on a terminal: no dry run either" "$FULL_YES" "$(steps)"
  assert_not_contains "AC6.1 --yes on a terminal: no question is printed" "$OUT" "[y/N]"
  fx
  export FAKE_GH_STATE=MERGED
  pty_ship y y -- 12 v1.2.3
  assert_rc "AC6.1/AC2.2 a merged PR with no merge commit on origin/main is refused before any question" 1
  assert_not_contains "AC6.1/AC2.2 refusal comes before the first question" "$OUT" "[y/N]"
  fx
  merged_on_main
  pty_ship y -- 12 v1.2.3
  assert_rc "AC2.2 a merged PR on origin/main: the one answer (y) goes to the tag question: exit 0" 0
  assert_eq "AC2.2 a merged PR with the questions: no merge, the dry run stays" "$MERGED_Q" "$(steps)"
  assert_not_contains "AC2.2 a merged PR: the merge question is not asked" "$OUT" "merge PR #12? [y/N]"
  assert_contains "AC2.2 a merged PR: the tag question is asked" "$OUT" "tag and push v1.2.3? [y/N]"
}
PTY_N=38
if [ "$PTY_OK" = 1 ]; then pty_block; else t_skip "$PTY_N" "AC6.1 prompt assertions need python3 with a pty (not available here)"; fi


# ---- v0.22.3 AC6.3: a main push whose Windows shards were skipped (the tree was tested by a PR run) ----
# The main push run then has fewer than 2 completed "windows shard K/N" jobs. ship runs tools/ci-tree-tested.sh for the
# release commit (a stub in the fixture: it logs "ci-tree-tested.sh <args>" and prints $FAKE_TREE_RUN) and uses the PR run id
# it prints for the shard hint and the weights refresh. No id: no hint, no refresh. FAKE_SHARDS_<run id> sets the jobs of one run.
echo "v0.22.3 AC6.3 shards skipped on main: the PR run of the same tree is the data source"
tree_calls() { grep '^ci-tree-tested.sh' "$FAKE_LOG"; }
TREE_SKIPPED_MAIN=("none" "100" "100,running")
fx
export FAKE_SHARDS_7777=none FAKE_TREE_RUN=5555 FAKE_SHARDS_5555="300,100,200"
sh_run 12 v1.2.3 --yes
TAGSHA="$(cd "$F/repo" && git rev-parse 'v1.2.3^{commit}' 2>/dev/null)"
assert_rc "AC6.3 skipped shards on main, an id from ci-tree-tested.sh: ship exits 0" 0
assert_eq "AC6.3 the whole flow ran as before" "$FULL_YES" "$(steps)"
assert_eq "AC6.3 ci-tree-tested.sh ran exactly once" "1" "$(tree_calls | wc -l | tr -d ' ')"
assert_contains "AC6.3 ci-tree-tested.sh is given the release (merge) commit" "$(tree_calls)" "$TAGSHA"
assert_eq "AC6.3 the tool is run after the tag's CI run was watched" "1" "$(awk '/^gh run watch/ { w = NR } /^ci-tree-tested.sh/ { if (w && NR > w) ok = 1 } END { print ok + 0 }' "$FAKE_LOG")"
assert_eq "AC6.3 the hint names the PR run (5555), not the main run" "1" \
  "$(printf '%s\n' "$OUT" | grep -cF 'shards unbalanced (100 s .. 300 s): run tools/shard-weights.sh 5555')"
assert_not_contains "AC6.3 the hint does not name the main run (7777)" "$OUT" "shard-weights.sh 7777"
assert_eq "AC6.3 only one line talks about unbalanced shards" "1" "$(unb)"
assert_eq "AC6.3 the weights refresh reads the PR run's jobs (gh run view 5555 ...)" "1" "$(( $(grep -c '^gh run view 5555 .*--json jobs' "$FAKE_LOG") >= 1 ))"
assert_contains "AC6.3 the refresh reads a shard job log" "$(grep '^gh run view' "$FAKE_LOG")" "--job"
assert_eq "AC6.3 one 'shard weights refreshed: copy ...' line" "1" "$(refreshed)"
assert_file "AC6.3 .agents/handoff/shard-weights.next was written" "$F/repo/$WN"
assert_contains "AC6.3 the weights file names the PR run (run 5555)" "$(cat "$F/repo/$WN" 2>/dev/null)" "run 5555"
assert_eq "AC6.3 the weights file does not name the main run" "0" "$(grep -c 'run 7777' "$F/repo/$WN" 2>/dev/null || true)"
assert_eq "AC6.3 tests/shard-weights is unchanged" "# old weights, run 1
test-big.sh 50" "$(cat "$F/repo/tests/shard-weights")"
assert_contains "AC6.3 shipped is still printed" "$OUT" "shipped v1.2.3"

echo "v0.22.3 AC6.3 the PR run's shards are balanced: no hint, no refresh"
for main_shards in "${TREE_SKIPPED_MAIN[@]}"; do
  fx
  export FAKE_SHARDS_7777="$main_shards" FAKE_TREE_RUN=5555 FAKE_SHARDS_5555="100,110,120"
  sh_run 12 v1.2.3 --yes
  assert_rc "AC6.3 main shards [$main_shards], balanced PR run: exit 0" 0
  assert_eq "AC6.3 main shards [$main_shards]: ci-tree-tested.sh ran (fewer than 2 completed shard jobs)" "1" "$(tree_calls | wc -l | tr -d ' ')"
  assert_eq "AC6.3 main shards [$main_shards], balanced PR run: no hint" "0" "$(unb)"
  assert_eq "AC6.3 main shards [$main_shards], balanced PR run: no 'shard weights' line" "0" "$(printf '%s\n' "$OUT" | grep -c 'shard weights')"
  assert_eq "AC6.3 main shards [$main_shards], balanced PR run: no shard logs were fetched" "0" "$(logged '^gh run view .*--job')"
done
fx
export FAKE_SHARDS_7777=none FAKE_TREE_RUN=5555 FAKE_SHARDS_5555="250,100"
sh_run 12 v1.2.3 --yes
assert_eq "AC6.3 another PR run (two shards, 250 s and 100 s): the hint names 5555" "1" "$(printf '%s\n' "$OUT" | grep -cF 'shards unbalanced (100 s .. 250 s): run tools/shard-weights.sh 5555')"

echo "v0.22.3 AC6.3 no id from ci-tree-tested.sh: no hint, no refresh"
for main_shards in "${TREE_SKIPPED_MAIN[@]}"; do
  fx
  export FAKE_SHARDS_7777="$main_shards" FAKE_TREE_RUN= FAKE_SHARDS_5555="300,100,200"
  sh_run 12 v1.2.3 --yes
  assert_rc "AC6.3 main shards [$main_shards], no id: ship exits 0" 0
  assert_eq "AC6.3 main shards [$main_shards], no id: the whole flow ran" "$FULL_YES" "$(steps)"
  assert_eq "AC6.3 main shards [$main_shards], no id: ci-tree-tested.sh was asked once" "1" "$(tree_calls | wc -l | tr -d ' ')"
  assert_eq "AC6.3 main shards [$main_shards], no id: no hint" "0" "$(unb)"
  assert_eq "AC6.3 main shards [$main_shards], no id: no 'shard weights' line" "0" "$(printf '%s\n' "$OUT" | grep -c 'shard weights')"
  assert_no_path "AC6.3 main shards [$main_shards], no id: no .agents/handoff" "$F/repo/.agents/handoff"
  assert_eq "AC6.3 main shards [$main_shards], no id: no run other than the main one is read" "0" "$(logged '^gh run view 5555')"
  assert_contains "AC6.3 main shards [$main_shards], no id: shipped is still printed" "$OUT" "shipped v1.2.3"
done
echo "v0.22.3 AC6.3 ci-tree-tested.sh fails: ship goes on without a hint"
fx
export FAKE_SHARDS_7777=none FAKE_TREE_RUN= FAKE_TREE_RC=1 FAKE_SHARDS_5555="300,100,200"
sh_run 12 v1.2.3 --yes
assert_rc "AC6.3 the tool exits 1: ship still exits 0" 0
assert_eq "AC6.3 the tool exits 1: the whole flow ran" "$FULL_YES" "$(steps)"
assert_eq "AC6.3 the tool exits 1: no hint and no refresh" "0 0" "$(unb) $(printf '%s\n' "$OUT" | grep -c 'shard weights')"
assert_contains "AC6.3 the tool exits 1: shipped is still printed" "$OUT" "shipped v1.2.3"

echo "v0.22.3 AC6.3 the main push ran its shards: ci-tree-tested.sh is not needed"
fx
export FAKE_SHARDS="300,100,200" FAKE_TREE_RUN=5555 FAKE_SHARDS_5555="500,100,100"
sh_run 12 v1.2.3 --yes
assert_rc "AC6.3 three completed shards on main: exit 0" 0
assert_eq "AC6.3 three completed shards on main: ci-tree-tested.sh does not run" "0" "$(tree_calls | wc -l | tr -d ' ')"
assert_eq "AC6.3 three completed shards on main: the hint names the main run (7777), as before" "1" "$(printf '%s\n' "$OUT" | grep -cF 'shards unbalanced (100 s .. 300 s): run tools/shard-weights.sh 7777')"
assert_not_contains "AC6.3 three completed shards on main: the PR run (5555) is not used" "$OUT" "shard-weights.sh 5555"
fx
export FAKE_SHARDS="100,300" FAKE_TREE_RUN=5555 FAKE_SHARDS_5555="500,100,100"
sh_run 12 v1.2.3 --yes
assert_eq "AC6.3 two completed shards on main (the bound is 2): ci-tree-tested.sh does not run" "0" "$(tree_calls | wc -l | tr -d ' ')"
assert_eq "AC6.3 two completed shards on main: the hint names the main run" "1" "$(printf '%s\n' "$OUT" | grep -cF 'shards unbalanced (100 s .. 300 s): run tools/shard-weights.sh 7777')"

echo "v0.22.3 AC6.3 the tag's CI failed: no PR run lookup"
fx
export FAKE_SHARDS_7777=none FAKE_TREE_RUN=5555 FAKE_SHARDS_5555="300,100,200" FAKE_GH_FAIL="runwatch"
sh_run 12 v1.2.3 --yes
assert_rc "AC6.3 CI failed: ship exits 1" 1
assert_eq "AC6.3 CI failed: ci-tree-tested.sh does not run" "0" "$(tree_calls | wc -l | tr -d ' ')"
# ---- v0.22.4 AC2.3: the eval guard hint, printed before the tag and repeated in the summary ----
# The fixture gets the real tools/eval-guard.sh and its own evals/scenario-map (skills/fixt/* -> E1 E3), plus a recording
# evals/run-evals.sh that must never be called. eg_fx PREV_TAG CHANGED_FILE: with PREV_TAG a tag v1.2.2 is put on main's
# current commit; CHANGED_FILE is then changed on origin's main (the commit ship pulls), before the fake merge.
echo "v0.22.4 AC2.3 eval guard hint: skill text changed since the previous release"
EGGUARD="$SHIPDIR/eval-guard.sh"
eg_fx() { # TAG(yes|no) FILE
  fx
  local w="$F/work"
  mkdir -p "$w/tools" "$w/evals" "$w/skills/fixt" "$w/docs"
  [ -f "$EGGUARD" ] && cp -p "$EGGUARD" "$w/tools/eval-guard.sh"
  printf 'skills/fixt/* E1 E3\n' > "$w/evals/scenario-map"
  printf '#!/usr/bin/env bash\necho "run-evals.sh $*" >> "%s"\nexit 0\n' "$F/evals-called" > "$w/evals/run-evals.sh"
  printf 'v1\n' > "$w/skills/fixt/SKILL.md"; printf 'v1\n' > "$w/docs/x.md"
  ( cd "$w" && git add -A && GITID commit -qm "eval guard fixture" && git push -q origin HEAD:main 2>/dev/null ) || { echo "eval guard fixture failed"; exit 3; }
  if [ "$1" = yes ]; then
    git -C "$F/repo" fetch -q origin && git -C "$F/repo" tag v1.2.2 origin/main
  fi
  printf 'v2\n' > "$w/$2"
  ( cd "$w" && git add -A && GITID commit -qm "change $2" && git push -q origin HEAD:main 2>/dev/null ) || { echo "eval guard change failed"; exit 3; }
  unset PLAYBOOK_HARNESS
}
lineno() { printf '%s\n' "$OUT" | grep -n -- "$1" | cut -d: -f1; }   # all line numbers matching a fixed text

eg_fx yes skills/fixt/SKILL.md
sh_run 12 v1.2.3 --yes
assert_rc "v22.4 AC2.3 skill text changed since the previous tag: ship exits 0" 0
assert_eq "v22.4 AC2.3 the flow is unchanged (the hint is only output)" "$FULL_YES" "$(steps)"
GL="$(printf '%s\n' "$OUT" | grep '^eval guard: ')"
assert_eq "v22.4 AC2.3 'eval guard: <command>' is printed twice (before the tag and in the final summary)" "2" "$(printf '%s\n' "$GL" | grep -c '^eval guard: ')"
assert_contains "v22.4 AC2.3 the hint is the capped run-evals command" "$GL" "run-evals.sh"
assert_contains "v22.4 AC2.3 the hint names the mapped scenarios, comma separated" "$GL" "--scenarios E1,E3"
assert_contains "v22.4 AC2.3 the hint carries --max-cost" "$GL" "--max-cost"
assert_eq "v22.4 AC2.3 both lines are the same command" "1" "$(printf '%s\n' "$GL" | sort -u | wc -l | tr -d ' ')"
FIRST="$(lineno '^eval guard: ' | head -n 1)"; LAST="$(lineno '^eval guard: ' | tail -n 1)"
REL="$(lineno '^== release v1.2.3$' | head -n 1)"
CHK="$(lineno '^== check the release$' | head -n 1)"
if [ -n "$FIRST" ] && [ -n "$REL" ] && [ "$FIRST" -lt "$REL" ]; then t_ok "v22.4 AC2.3 the first hint comes BEFORE the '== release v1.2.3' (tag and push) step"; else t_bad "v22.4 AC2.3 the first hint comes BEFORE the '== release v1.2.3' (tag and push) step" "hint line [$FIRST], release step line [$REL]; output: $OUT"; fi
if [ -n "$LAST" ] && [ -n "$CHK" ] && [ "$LAST" -gt "$CHK" ]; then t_ok "v22.4 AC2.3 the repeated hint comes after the release was checked (final summary)"; else t_bad "v22.4 AC2.3 the repeated hint comes after the release was checked (final summary)" "last hint line [$LAST], '== check the release' line [$CHK]"; fi
assert_contains "v22.4 AC2.3 ship still says shipped" "$OUT" "shipped v1.2.3"
assert_no_path "v22.4 AC2.3 ship never runs the command (the recording run-evals.sh was not called)" "$F/evals-called"
assert_eq "v22.4 AC2.3 no gh call asks for an eval run" "0" "$(logged 'run-evals')"

echo "v0.22.4 AC2.3 the hint also appears with the questions flow (dry run kept): still before the tag"
if [ "$PTY_OK" = 1 ]; then
  eg_fx yes skills/fixt/SKILL.md
  pty_ship y y -- 12 v1.2.3
  assert_rc "v22.4 AC2.3 questions flow exits 0" 0
  FIRST="$(lineno '^eval guard: ' | head -n 1)"
  ASKTAG="$(lineno 'tag and push v1.2.3' | head -n 1)"
  if [ -n "$FIRST" ] && [ -n "$ASKTAG" ] && [ "$FIRST" -lt "$ASKTAG" ]; then t_ok "v22.4 AC2.3 the hint is printed before the 'tag and push' question"; else t_bad "v22.4 AC2.3 the hint is printed before the 'tag and push' question" "hint line [$FIRST], question line [$ASKTAG]; output: $OUT"; fi
else
  t_skip 2 "v22.4 AC2.3 questions flow (no python3 pty)"
fi

echo "v0.22.4 AC2.3 no previous tag: no hint, ship still succeeds"
eg_fx no skills/fixt/SKILL.md
sh_run 12 v1.2.3 --yes
assert_rc "v22.4 AC2.3 no previous v* tag: ship exits 0" 0
assert_eq "v22.4 AC2.3 no previous v* tag: the whole flow ran" "$FULL_YES" "$(steps)"
assert_eq "v22.4 AC2.3 no previous v* tag: no 'eval guard:' line" "0" "$(printf '%s\n' "$OUT" | grep -c 'eval guard:')"
assert_contains "v22.4 AC2.3 no previous v* tag: shipped is printed" "$OUT" "shipped v1.2.3"
assert_no_path "v22.4 AC2.3 no previous v* tag: nothing was run" "$F/evals-called"

echo "v0.22.4 AC2.3 only a non-v tag exists: describe fails, no hint, ship still succeeds"
eg_fx no skills/fixt/SKILL.md
git -C "$F/repo" fetch -q origin && git -C "$F/repo" tag nightly-1 origin/main
sh_run 12 v1.2.3 --yes
assert_rc "v22.4 AC2.3 only a non-v tag: ship exits 0" 0
assert_eq "v22.4 AC2.3 only a non-v tag: no 'eval guard:' line" "0" "$(printf '%s\n' "$OUT" | grep -c 'eval guard:')"
assert_contains "v22.4 AC2.3 only a non-v tag: shipped is printed" "$OUT" "shipped v1.2.3"

echo "v0.22.4 AC2.3 no mapped file changed since the previous tag: no hint"
eg_fx yes docs/x.md
sh_run 12 v1.2.3 --yes
assert_rc "v22.4 AC2.3 only docs changed: ship exits 0" 0
assert_eq "v22.4 AC2.3 only docs changed: no 'eval guard:' line" "0" "$(printf '%s\n' "$OUT" | grep -c 'eval guard:')"
assert_contains "v22.4 AC2.3 only docs changed: shipped is printed" "$OUT" "shipped v1.2.3"
assert_no_path "v22.4 AC2.3 only docs changed: nothing was run" "$F/evals-called"

echo "v0.22.4 AC2.3 a failing eval-guard.sh never fails the release"
eg_fx yes skills/fixt/SKILL.md
# replace the guard on origin's main (the commit ship pulls) with one that fails
printf '#!/usr/bin/env bash\necho "guard broke" >&2\nexit 7\n' > "$F/work/tools/eval-guard.sh"
( cd "$F/work" && git add -A && GITID commit -qm "broken guard on main" && git push -q origin HEAD:main 2>/dev/null )
sh_run 12 v1.2.3 --yes
assert_rc "v22.4 AC2.3 eval-guard.sh exits 7: ship still exits 0" 0
assert_eq "v22.4 AC2.3 eval-guard.sh exits 7: the whole flow ran" "$FULL_YES" "$(steps)"
assert_contains "v22.4 AC2.3 eval-guard.sh exits 7: shipped is printed" "$OUT" "shipped v1.2.3"
echo "v0.22.3 review Low-3: shard jobs that were skipped (conclusion skipped, with a completedAt) are not completed shards"
fx
export FAKE_SHARDS_7777="skip,skip,skip" FAKE_TREE_RUN=5555 FAKE_SHARDS_5555="300,100,200"
sh_run 12 v1.2.3 --yes
TAGSHA="$(cd "$F/repo" && git rev-parse 'v1.2.3^{commit}' 2>/dev/null)"
assert_rc "Low-3 three skipped shard jobs on main: exit 0" 0
assert_eq "Low-3 three skipped shard jobs on main: ci-tree-tested.sh runs" "1" "$(tree_calls | wc -l | tr -d ' ')"
assert_contains "Low-3 ... for the release commit" "$(tree_calls)" "$TAGSHA"
assert_eq "Low-3 ... and the hint names the PR run (5555)" "1" "$(printf '%s\n' "$OUT" | grep -cF 'shards unbalanced (100 s .. 300 s): run tools/shard-weights.sh 5555')"
assert_not_contains "Low-3 ... never the main run (7777): skipped jobs have no timings" "$OUT" "shard-weights.sh 7777"
fx
export FAKE_SHARDS_7777="skip,skip,skip" FAKE_TREE_RUN=
sh_run 12 v1.2.3 --yes
assert_eq "Low-3 three skipped shards and no PR run: the tool was asked" "1" "$(tree_calls | wc -l | tr -d ' ')"
assert_eq "Low-3 ... no hint and no refresh" "0 0" "$(unb) $(printf '%s\n' "$OUT" | grep -c 'shard weights')"
fx
export FAKE_SHARDS_7777="300,skip,skip" FAKE_TREE_RUN=
sh_run 12 v1.2.3 --yes
assert_eq "Low-3 one real shard and two skipped ones: fewer than 2 count, the tool is asked" "1" "$(tree_calls | wc -l | tr -d ' ')"

t_summary
