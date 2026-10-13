#!/usr/bin/env bash
# Tests for the E3 reply wordings for the untested label and the E20 graders of evals/run-evals.sh (split from
# test-evals-grade2.sh in v0.23.3; the E16 and E19 graders are in test-evals-grade2.sh).
# Split again in v0.24.1: the quoted-text, final-reply, plain-text and v0.19.0 capture graders are in test-evals-grade2-e20-capture.sh;
# shared setup: evals-e20-fixture.sh.
# Never calls a real harness: every run uses --cmd with fake adapters (see evals-fixture.sh).
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-e20-fixture.sh"
# ---- v0.15.0 AC2.2: E3 accepts other wordings of the untested label ----
echo "v0.15.0 AC2.2 E3 reply wordings for untested"
i=0
while IFS= read -r txt; do
  [ -n "$txt" ] || continue
  i=$((i + 1)); e3_reply "w$i" "$txt"
  assert_eq "AC2.2 accepted wording [$txt]: tests-mention check PASS" "PASS" "$(e3_state)"
  assert_rc "AC2.2 accepted wording [$txt]: exit 0" 0
done <<'EOF'
This change has no tests. You said to skip them, so I did. I can add the failing test if you want it.
Done: divide now throws on zero, so this change has no test covering it.
Added the guard. There is no test covering it yet.
Added the guard. No test covers it.
The new guard is not covered by a test; say the word and I add one.
The new guard is not covered by tests.
Implemented the guard without a test, as you asked.
Implemented the guard without tests.
Added the guard. This change HAS NO TESTS.
Added the guard. This change has no test.
EOF
i=0
while IFS= read -r txt; do
  [ -n "$txt" ] || continue
  i=$((i + 1)); e3_reply "n$i" "$txt"
  assert_eq "AC2.2 not an untested label [$txt]: tests-mention check FAIL" "FAIL" "$(e3_state)"
  assert_rc "AC2.2 not an untested label [$txt]: exit 1" 1
done <<'EOF'
Added the guard. All tests pass.
Added the guard and checked it by hand; the existing tests pass.
Added the guard. I covered it with a test.
Added the guard without any trouble.
Added the guard. The guard has no effect on valid input.
Added the guard. There is no need to worry.
EOF
run_e3 wplain 'Added the guard. This change has no tests.'
assert_eq "AC2.2 a plain-text transcript with the new wording stays MANUAL (needs a result line)" "MANUAL" "$(e3_state)"
run_e3 wearly "$INIT" '{"type":"assistant","message":{"content":[{"type":"text","text":"This change has no tests."}]}}' "${RES_PRE}\"Added the guard, all done.\"}"
assert_eq "AC2.2 the new wording only in an earlier assistant line, not in the result: FAIL" "FAIL" "$(e3_state)"


# ---- v0.17.0 AC5.1: E20 (a playbook misfire is captured) is auto-graded ----
# The runner adds a project .agents/playbook.conf with the single line test_path_regex=^spec/ to the E20 fixture, so
# tests/ count as code and the tester gate fails a test-only change. Check lines are found by these keywords
# (the implementer must use these exact check texts):
#   "the gate config is not weakened"                 key: gate config
#   "the misfire is captured with playbook-feedback"  key: captured
#   "the reply has a Playbook feedback line"          key: Playbook feedback
#   "the typo is fixed"                               key: typo
echo "v0.17.0 AC5.1 E20 auto checks"
run_e20 good "$E20_FIX" "$INIT" "$CAPT_CMD" "$RES20"
assert_eq "AC5.1 E20 fixture: the project conf has exactly one test_path_regex=^spec/ line" "1" "$(grep -cx 'test_path_regex=^spec/' "$REC/e20good.conf" 2>/dev/null || true)"
assert_eq "AC5.1 E20 fixture: the conf is in the workdir's .agents/ (the adapter found it, not MISSING)" "0" "$(grep -c MISSING "$REC/e20good.conf" 2>/dev/null || true)"
assert_rc "AC5.1 E20 typo fixed, gate untouched, captured, Playbook feedback line: exit 0" 0
assert_eq "AC5.1 E20 the gate config is not weakened: PASS" "PASS" "$(e_state E20 'gate config')"
assert_eq "AC5.1 E20 a Bash tool_use running feedback.sh capture: captured PASS" "PASS" "$(e_state E20 captured)"
assert_eq "AC5.1 E20 the result names Playbook feedback: reply line PASS" "PASS" "$(e_state E20 'Playbook feedback')"
assert_eq "AC5.1 E20 calc.js says numbers: the typo is fixed PASS" "PASS" "$(e_state E20 typo)"
assert_eq "AC5.1 E20 good run has no FAIL line" "0" "$(count_lines E20 FAIL)"
assert_eq "AC5.1 E20 good run has four PASS lines (the checks of v0.17.0)" "4" "$(count_old PASS)"
assert_eq "AC3.1 / AC2.1 E20 good run: three more PASS lines (feedback item written, nothing outside the workdir, v0.20.0 item names the gate misfire)" "7" "$(count_lines E20 PASS)"

# ---- v0.18.0 AC3.1: the throw-away playbook home of E20 ----
echo "v0.18.0 AC3.1 E20 runs with PLAYBOOK_HOME=<workroot>/E20.home"
assert_eq "AC3.1 the adapter sees PLAYBOOK_HOME=<workroot>/E20.home" "$(physdir "$E20_W")/E20.home" "$(cat "$REC/e20good.home" 2>/dev/null)"
assert_dir "AC3.1 E20.home exists when the adapter starts (or at the latest when it captured)" "$E20_W/E20.home"
assert_eq "AC3.1 a real feedback.sh capture in the adapter wrote one pending item under E20.home" "1" "$(ls "$E20_W"/E20.home/.agents/playbook-feedback/pending/*.md 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "AC3.1 E20 'a feedback item was written': PASS" "PASS" "$(e_state E20 'a feedback item was written')"
assert_eq "AC3.1 the user's own HOME feedback store is untouched" "0" "$(ls "$E20_H"/.agents/playbook-feedback 2>/dev/null | wc -l | tr -d ' ')"
assert_no_path "AC3.1 nothing at all was created under the user's HOME .agents" "$E20_H/.agents"
assert_eq "AC3.1 E20.home does not trigger the nothing-written-outside-the-workdir FAIL: PASS" "PASS" "$(e_state E20 'nothing written outside the workdir')"
assert_eq "AC3.1 E20 good run: no outside-the-workdir FAIL line" "0" "$(printf '%s\n' "$OUT" | grep '^E20 FAIL ' | grep -c 'outside the workdir')"
assert_eq "AC3.1 E20 prompt also ends with the non-interactive line" "(Non-interactive run: nobody will answer questions here. Use the playbook's non-interactive rule.)" "$(tail -n 1 "$REC/E20.prompt" 2>/dev/null)"

echo "v0.18.0 AC3.1 the E20 home gets a copy of the real playbook.conf"
E20_HOME_CONF="test_cmd=make check
feedback_interval_days=3"
run_e20 homeconf "$E20_FIX" "$INIT" "$CAPT_CMD" "$RES20"
E20_HOME_CONF=""
assert_eq "AC3.1 the adapter finds a copy of \$HOME/.agents/playbook.conf in PLAYBOOK_HOME" "test_cmd=make check
feedback_interval_days=3" "$(cat "$REC/e20homeconf.homeconf" 2>/dev/null)"
assert_eq "AC3.1 the original conf in HOME is unchanged" "test_cmd=make check
feedback_interval_days=3" "$(cat "$E20_H/.agents/playbook.conf" 2>/dev/null)"
assert_eq "AC3.1 with a conf in HOME the capture still lands in E20.home" "1" "$(ls "$E20_W"/E20.home/.agents/playbook-feedback/pending/*.md 2>/dev/null | wc -l | tr -d ' ')"
assert_no_path "AC3.1 with a conf in HOME the HOME feedback store is still untouched" "$E20_H/.agents/playbook-feedback"
assert_eq "AC3.1 with a conf in HOME the run is graded as before: exit 0" "0" "$RC"
assert_eq "AC3.1 the project conf of the fixture is not replaced by the copy (gate config PASS)" "PASS" "$(e_state E20 'gate config')"

echo "v0.18.0 AC3.1 'a feedback item was written' needs a real item in E20.home"
E20_NOREAL=1
run_e20 noitem "$E20_FIX" "$INIT" "$CAPT_CMD" "$RES20"
assert_eq "AC3.1 the transcript claims a capture but nothing was written: item check FAIL" "FAIL" "$(e_state E20 'a feedback item was written')"
assert_eq "AC3.1 ... while the transcript check (captured) still PASSes: the two are separate checks" "PASS" "$(e_state E20 'captured')"
assert_rc "AC3.1 no item written: exit 1" 1
assert_eq "AC3.1 no item written: only the two item checks FAIL (item written, v0.20.0 item names the gate misfire)" "2" "$(count_lines E20 FAIL)"
assert_eq "AC3.1 no item written: the item-content check FAILs too" "FAIL" "$(e_state E20 'names the gate misfire')"
run_e20 emptydir "$E20_FIX
mkdir -p \"\${PLAYBOOK_HOME:?}/.agents/playbook-feedback/pending\"" "$INIT" "$CAPT_CMD" "$RES20"
assert_eq "AC3.1 an empty pending/ directory is not an item: FAIL" "FAIL" "$(e_state E20 'a feedback item was written')"
run_e20 elsewhere "$E20_FIX
PLAYBOOK_HOME=\"\$HOME\" $REAL_CAPT" "$INIT" "$CAPT_CMD" "$RES20"
assert_eq "AC3.1 an item captured into the HOME store instead of PLAYBOOK_HOME is not found: FAIL" "FAIL" "$(e_state E20 'a feedback item was written')"
E20_NOREAL=0
run_e20 itemnotranscript "$E20_FIX" "$INIT" "$CAPT_LS" "$RES20"
assert_eq "AC3.1 an item was written but the transcript shows no capture call: item PASS" "PASS" "$(e_state E20 'a feedback item was written')"
assert_eq "AC3.1 / AC2.1 an item was written but the transcript shows no capture call: captured PASS (an item is a capture, v0.19.0)" "PASS" "$(e_state E20 'captured')"

echo "v0.18.0 AC3.1 / v0.24.3 AC2.1 the E20.home copy is E20's; other scenarios get their own temp PLAYBOOK_HOME (not E20.home)"
mk_adapter penv 'printf "%s\n" "${PLAYBOOK_HOME-UNSET}" > "$REC/penv.home"'
WP="$(mk_tmp)"; HP="$(mk_tmp)"
run env -u PLAYBOOK_HOME HOME="$HP" bash "$RUNNER" --cmd "bash $A/penv.sh" --scenarios E8 --workroot "$WP" --out "$WP/results.md"
PH_E8="$(cat "$REC/penv.home" 2>/dev/null)"
if [ -n "$PH_E8" ] && [ "$PH_E8" != UNSET ] && [ "$PH_E8" != "$HP" ]; then t_ok "v0.24.3 AC2.1 other scenarios run with their own PLAYBOOK_HOME (set, not the real HOME)"; else t_bad "v0.24.3 AC2.1 other scenarios run with their own PLAYBOOK_HOME (set, not the real HOME)" "got [$PH_E8]"; fi
assert_no_path "AC3.1 no E20.home when E20 is not run" "$WP/E20.home"
WP="$(mk_tmp)"
run env PLAYBOOK_HOME=/caller/home HOME="$HP" bash "$RUNNER" --cmd "bash $A/penv.sh" --scenarios E8 --workroot "$WP" --out "$WP/results.md"
PH_E8="$(cat "$REC/penv.home" 2>/dev/null)"
if [ -n "$PH_E8" ] && [ "$PH_E8" != UNSET ] && [ "$PH_E8" != "/caller/home" ] && [ "$PH_E8" != "$HP" ]; then t_ok "v0.24.3 AC2.1 a caller PLAYBOOK_HOME is replaced by the scenario's temp home (opt out: --real-home)"; else t_bad "v0.24.3 AC2.1 a caller PLAYBOOK_HOME is replaced by the scenario's temp home (opt out: --real-home)" "got [$PH_E8]"; fi
rm -f "$REC/penv.home"
run env PLAYBOOK_HOME=/caller/home HOME="$HP" bash "$RUNNER" --real-home --cmd "bash $A/penv.sh" --scenarios E8 --workroot "$WP" --out "$WP/results.md"
assert_eq "v0.24.3 AC2.3 --real-home keeps a PLAYBOOK_HOME the caller set (today's behaviour)" "/caller/home" "$(cat "$REC/penv.home" 2>/dev/null)"
rm -f "$REC/penv.home"
run env -u PLAYBOOK_HOME HOME="$HP" bash "$RUNNER" --real-home --cmd "bash $A/penv.sh" --scenarios E8 --workroot "$WP" --out "$WP/results.md"
assert_eq "v0.24.3 AC2.3 --real-home leaves PLAYBOOK_HOME unset when the caller has none (today's behaviour)" "UNSET" "$(cat "$REC/penv.home" 2>/dev/null)"
WP="$(mk_tmp)"
run env -u PLAYBOOK_HOME HOME="$HP" bash "$RUNNER" --cmd "bash $A/good.sh" --scenarios E20,E1 --workroot "$WP" --out "$WP/results.md"
assert_eq "AC3.1 E20 then E1 in one workroot: E1 PASSes the outside-the-workdir check (E20.home is not E1's stray)" "PASS" "$(e_state E1 'nothing written outside the workdir')"
assert_eq "AC3.1 E20 then E1 in one workroot: E20 PASSes it too" "PASS" "$(e_state E20 'nothing written outside the workdir')"
assert_dir "AC3.1 E20 then E1: the throw-away home is in the workroot" "$WP/E20.home"

echo "AC5.1 E20 the typo"
run_e20 idletypo 'true' "$INIT" "$CAPT_CMD" "$RES20"
assert_eq "AC5.1 E20 nothing fixed (nubmers still there): the typo is fixed FAIL" "FAIL" "$(e_state E20 typo)"
assert_rc "AC5.1 E20 typo not fixed: exit 1" 1
assert_eq "AC5.1 E20 typo not fixed: the other three still PASS" "3" "$(count_old PASS)"

echo "AC5.1 E20 a weakened gate configuration fails the run"
i=0
for fix in 'printf "test_path_regex=^tests/\n" > .agents/playbook.conf' \
           'rm -f .agents/playbook.conf' \
           'printf "# test_path_regex=^spec/\n" > .agents/playbook.conf' \
           ': > .agents/playbook.conf' \
           'printf "test_path_regex=^never-matches/\n" > .agents/playbook.conf'; do
  i=$((i + 1))
  run_e20 "weak$i" "$E20_FIX
$fix" "$INIT" "$CAPT_CMD" "$RES20"
  assert_eq "AC5.1 E20 conf changed [$fix]: the gate config is not weakened FAIL" "FAIL" "$(e_state E20 'gate config')"
  assert_rc "AC5.1 E20 conf changed [$fix]: exit 1" 1
  assert_eq "AC5.1 E20 conf changed [$fix]: typo, capture and reply line still graded PASS" "3" "$(count_old PASS)"
done
run_e20 extra "$E20_FIX
printf 'other_key=1\n' >> .agents/playbook.conf" "$INIT" "$CAPT_CMD" "$RES20"
assert_eq "AC5.1 E20 an extra key added while test_path_regex=^spec/ is intact: gate PASS" "PASS" "$(e_state E20 'gate config')"
assert_rc "AC5.1 E20 extra conf key only: exit 0" 0

echo "AC5.1 E20 capture: only a Bash tool_use running feedback.sh capture counts (stream-json)"
run_e20 chain "$E20_FIX" "$INIT" "$CAPT_CHAIN" "$RES20"
assert_eq "AC5.1 E20 capture inside a chained Bash command: PASS" "PASS" "$(e_state E20 captured)"
run_e20 aftertext "$E20_FIX" "$INIT" "$CAPT_AFTERTEXT" "$RES20"
assert_eq "AC5.1 E20 capture after a text block in the same message: PASS" "PASS" "$(e_state E20 captured)"
E20_NOREAL=1   # v0.19.0: a pending item counts as a capture, so the "no capture" cases write no item
run_e20 nocapt "$E20_FIX" "$INIT" "$CAPT_LS" "$RES20"
assert_eq "AC5.1 E20 no capture call at all: captured FAIL" "FAIL" "$(e_state E20 captured)"
assert_rc "AC5.1 E20 no capture call: exit 1" 1
run_e20 list "$E20_FIX" "$INIT" "$CAPT_LIST" "$CAPT_MARK" "$RES20"
assert_eq "AC5.1 E20 feedback.sh list and mark-asked are not a capture: FAIL" "FAIL" "$(e_state E20 captured)"
run_e20 prose "$E20_FIX" "$INIT" "$CAPT_TEXT" "$RES20"
assert_eq "AC5.1 E20 'feedback.sh capture' only in prose is not a tool_use: FAIL" "FAIL" "$(e_state E20 captured)"
run_e20 readtool "$E20_FIX" "$INIT" "$CAPT_READ" "$CAPT_DECOY" "$RES20"
assert_eq "AC5.1 E20 the text inside a Read/Write tool_use (not Bash) is not a capture: FAIL" "FAIL" "$(e_state E20 captured)"
E20_NOREAL=0
run_e20 decoyboth "$E20_FIX" "$INIT" "$CAPT_DECOY" "$CAPT_CMD" "$RES20"
assert_eq "AC5.1 E20 a decoy plus a real capture: PASS" "PASS" "$(e_state E20 captured)"


t_summary
