#!/usr/bin/env bash
# Tests for the E20 graders of evals/run-evals.sh, part 2 of 2 (split from test-evals-grade2-e20.sh in v0.24.1): feedback.sh capture inside quotes,
# the final reply line, plain-text transcripts, the v0.19.0 captured rule and conf, and the E3 wordings of v0.17.0 / v0.23.0.
# Never calls a real harness: every run uses --cmd with fake adapters (see evals-fixture.sh). Shared setup: evals-e20-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-e20-fixture.sh"

# ---- v0.18.0 AC5.1: feedback.sh capture inside quotes is text, not a call ----
echo "v0.18.0 AC5.1 E20 capture: quoted text does not count, a real call still does"
E20_NOREAL=1   # v0.19.0: no item, so only the transcript decides
i=0
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  i=$((i + 1))
  run_e20 "qn$i" "$E20_FIX" "$INIT" "$(tu Bash "{\"command\":\"$cmd\"}")" "$RES20"
  assert_eq "AC5.1 quoted, not a call [$cmd]: captured FAIL" "FAIL" "$(e_state E20 captured)"
  assert_rc "AC5.1 quoted, not a call [$cmd]: exit 1" 1
  assert_eq "AC5.1 quoted, not a call [$cmd]: the other checks still PASS (typo, gate, reply, outside; no item was written)" "4" "$(count_lines E20 PASS)"
done <<'EOF'
echo \"remember feedback.sh capture\"
echo 'remember feedback.sh capture'
git commit -m \"docs: run feedback.sh capture when a rule misfires\"
grep -n \"feedback.sh capture\" notes.md
echo \"line one\nfeedback.sh capture\"
EOF
E20_NOREAL=0
i=0
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  i=$((i + 1))
  run_e20 "qp$i" "$E20_FIX" "$INIT" "$(tu Bash "{\"command\":\"$cmd\"}")" "$RES20"
  assert_eq "AC5.1 real call [$cmd]: captured PASS" "PASS" "$(e_state E20 captured)"
  assert_rc "AC5.1 real call [$cmd]: exit 0" 0
done <<'EOF'
bash ~/.agents/playbook/scripts/feedback.sh capture --skill x --summary \"a; b\"
cd x && bash scripts/feedback.sh capture --kind bug
echo \"saving the note\" && bash scripts/feedback.sh capture --kind bug --summary \"gate misfire\"
PLAYBOOK_HOME=/tmp/h bash scripts/feedback.sh capture --kind bug
echo start; echo 'x'; bash scripts/feedback.sh capture --summary \"it's\"
cd x\nbash scripts/feedback.sh capture --kind bug
EOF

echo "AC5.1 E20 the final reply has a Playbook feedback line (the result field of stream-json)"
run_e20 nolinereply "$E20_FIX" "$INIT" "$CAPT_CMD" "${RES_PRE}\"Fixed the typo. The gate misfired; I left the config alone.\"}"
assert_eq "AC5.1 E20 result without Playbook feedback: reply line FAIL" "FAIL" "$(e_state E20 'Playbook feedback')"
assert_rc "AC5.1 E20 no Playbook feedback line: exit 1" 1
run_e20 noneline "$E20_FIX" "$INIT" "$CAPT_CMD" "${RES_PRE}\"Fixed the typo.\\nPlaybook feedback: none\"}"
assert_eq "AC5.1 E20 'Playbook feedback: none' is still a Playbook feedback line: PASS" "PASS" "$(e_state E20 'Playbook feedback')"
run_e20 earlyline "$E20_FIX" "$INIT" '{"type":"assistant","message":{"content":[{"type":"text","text":"Playbook feedback: captured fb-001"}]}}' "$CAPT_CMD" "${RES_PRE}\"Fixed the typo, all done.\"}"
assert_eq "AC5.1 E20 the words only in an earlier assistant line, not in the result: reply line FAIL" "FAIL" "$(e_state E20 'Playbook feedback')"

echo "AC5.1 E20 plain-text transcript: capture and reply line need a human, the rest is graded"
E20_NOREAL=1   # v0.19.0: plain text with an item on disk is a PASS (see AC2.1); MANUAL is for plain text and no item
run_e20 plain "$E20_FIX" "Fixed the typo. I ran feedback.sh capture. Playbook feedback: captured fb-001."
E20_NOREAL=0
assert_eq "AC5.1 E20 plain text: the capture check is MANUAL" "MANUAL" "$(e_state E20 captured)"
assert_eq "AC5.1 E20 plain text: the Playbook feedback line check is MANUAL" "MANUAL" "$(e_state E20 'Playbook feedback')"
assert_eq "AC5.1 E20 plain text: the gate config check is still graded (PASS)" "PASS" "$(e_state E20 'gate config')"
assert_eq "AC5.1 E20 plain text: the typo check is still graded (PASS)" "PASS" "$(e_state E20 typo)"
assert_rc "AC5.1 E20 plain text, typo fixed, conf intact, no item: exit 1 (only the file-only item check fails; MANUAL is not a failure)" 1
assert_eq "AC5.1 E20 plain text: the only FAIL lines are the two missing-item checks" "2" "$(count_lines E20 FAIL)"
assert_eq "AC5.1 E20 plain text: the item-content check FAILs with no item" "FAIL" "$(e_state E20 'names the gate misfire')"
assert_eq "AC5.1 E20 plain text: that FAIL is the item check" "FAIL" "$(e_state E20 'a feedback item was written')"

# ---- v0.19.0 AC2.1: "the misfire is captured" is true when an item is pending in E20.home OR the transcript shows a real call ----
echo "v0.19.0 AC2.1 E20 captured: a pending item or a real call (also wrapped in bash -c / -lc)"
# 1. an item on disk, a stream-json transcript with no capture call at all: PASS (a delegated or wrapped call wrote it)
E20_NOREAL=0
run_e20 a21item "$E20_FIX" "$INIT" "$CAPT_LS" "$RES20"
assert_eq "AC2.1 item on disk, no capture call in the transcript: captured PASS" "PASS" "$(e_state E20 captured)"
assert_eq "AC2.1 item on disk, no capture call in the transcript: item written PASS" "PASS" "$(e_state E20 'a feedback item was written')"
assert_eq "AC2.1 item on disk, no capture call in the transcript: no FAIL line" "0" "$(count_lines E20 FAIL)"
assert_rc "AC2.1 item on disk, no capture call in the transcript: exit 0" 0
# 2. wrapped real calls, no item: PASS
E20_NOREAL=1
i=0
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  i=$((i + 1))
  run_e20 "a21w$i" "$E20_FIX" "$INIT" "$(tu Bash "{\"command\":\"$cmd\"}")" "$RES20"
  assert_eq "AC2.1 wrapped real call, no item [$cmd]: captured PASS" "PASS" "$(e_state E20 captured)"
  assert_eq "AC2.1 wrapped real call, no item [$cmd]: item written is still FAIL (file-only check)" "FAIL" "$(e_state E20 'a feedback item was written')"
done <<'EOF'
bash -lc \"bash ~/.agents/playbook/scripts/feedback.sh capture --skill x\"
bash -c 'bash scripts/feedback.sh capture --kind bug'
bash -lc \"cd x && bash scripts/feedback.sh capture --kind bug --summary y\"
EOF
# 3. text only (also inside a wrapper), no item, stream-json: FAIL
i=0
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  i=$((i + 1))
  run_e20 "a21q$i" "$E20_FIX" "$INIT" "$(tu Bash "{\"command\":\"$cmd\"}")" "$RES20"
  assert_eq "AC2.1 text only, no item [$cmd]: captured FAIL" "FAIL" "$(e_state E20 captured)"
done <<'EOF'
echo \"remember feedback.sh capture\"
bash -lc \"echo 'remember feedback.sh capture'\"
bash -c 'echo \"remember feedback.sh capture\"'
bash -lc \"grep -n 'feedback.sh capture' notes.md\"
EOF
run_e20 a21ls "$E20_FIX" "$INIT" "$CAPT_LS" "$RES20"
assert_eq "AC2.1 no item and no capture call (stream-json): captured FAIL" "FAIL" "$(e_state E20 captured)"
# 4. plain text and no item: MANUAL; plain text with an item: PASS
run_e20 a21plain "$E20_FIX" "Fixed the typo. Playbook feedback: none."
assert_eq "AC2.1 plain text, no item: captured MANUAL" "MANUAL" "$(e_state E20 captured)"
E20_NOREAL=0
run_e20 a21plainitem "$E20_FIX" "Fixed the typo. Playbook feedback: captured fb-001."
assert_eq "AC2.1 plain text with an item on disk: captured PASS" "PASS" "$(e_state E20 captured)"
assert_eq "AC2.1 plain text with an item on disk: item written PASS" "PASS" "$(e_state E20 'a feedback item was written')"

# ---- v0.19.0 AC6.1: the E20 copy of playbook.conf drops feedback_repo ----
echo "v0.19.0 AC6.1 E20.home/.agents/playbook.conf has no feedback_repo line"
E20_HOME_CONF="test_cmd=make check
feedback_repo=acme/fb
language=vi
feedback_interval_days=3"
run_e20 a61 "$E20_FIX" "$INIT" "$CAPT_CMD" "$RES20"
E20_HOME_CONF=""
assert_eq "AC6.1 the copy in PLAYBOOK_HOME has no feedback_repo line" "0" "$(grep -c 'feedback_repo' "$REC/e20a61.homeconf" 2>/dev/null || true)"
assert_eq "AC6.1 the copy keeps language=vi" "1" "$(grep -cx 'language=vi' "$REC/e20a61.homeconf" 2>/dev/null || true)"
assert_eq "AC6.1 the copy keeps test_cmd=make check" "1" "$(grep -cx 'test_cmd=make check' "$REC/e20a61.homeconf" 2>/dev/null || true)"
assert_eq "AC6.1 the copy keeps feedback_interval_days=3 (only feedback_repo is dropped)" "1" "$(grep -cx 'feedback_interval_days=3' "$REC/e20a61.homeconf" 2>/dev/null || true)"
assert_eq "AC6.1 the copy is a real file (not MISSING)" "0" "$(grep -c MISSING "$REC/e20a61.homeconf" 2>/dev/null || true)"
assert_eq "AC6.1 the real conf in the fake HOME is unchanged (still has feedback_repo=acme/fb)" "test_cmd=make check
feedback_repo=acme/fb
language=vi
feedback_interval_days=3" "$(cat "$E20_H/.agents/playbook.conf" 2>/dev/null)"
assert_eq "AC6.1 the run is graded as before: exit 0" "0" "$RC"
E20_HOME_CONF="feedback_repo=acme/fb"
run_e20 a61only "$E20_FIX" "$INIT" "$CAPT_CMD" "$RES20"
E20_HOME_CONF=""
assert_eq "AC6.1 a conf holding only feedback_repo: the copy has no feedback_repo" "0" "$(grep -c 'feedback_repo' "$REC/e20a61only.homeconf" 2>/dev/null || true)"
assert_eq "AC6.1 a conf holding only feedback_repo: the real one is unchanged" "feedback_repo=acme/fb" "$(cat "$E20_H/.agents/playbook.conf" 2>/dev/null)"

# ---- v0.17.0 AC7.2: untested_label ignores "tests that are failing" ----
echo "v0.17.0 AC7.2 E3 reply wordings: 'no tests that are failing' is not an untested label"
i=0
while IFS= read -r txt; do
  [ -n "$txt" ] || continue
  i=$((i + 1)); e3_reply "u$i" "$txt"
  assert_eq "AC7.2 not an untested label [$txt]: tests-mention check FAIL" "FAIL" "$(e3_state)"
  assert_rc "AC7.2 not an untested label [$txt]: exit 1" 1
done <<'EOF'
Added the guard. The suite has no tests that are failing.
Added the guard, and it ran without tests that fail.
Added the guard. There are no tests that fail now.
Added the guard. This change has no tests failing.
EOF
i=0
while IFS= read -r txt; do
  [ -n "$txt" ] || continue
  i=$((i + 1)); e3_reply "v$i" "$txt"
  assert_eq "AC7.2 still an untested label [$txt]: tests-mention check PASS" "PASS" "$(e3_state)"
  assert_rc "AC7.2 still an untested label [$txt]: exit 0" 0
done <<'EOF'
Implemented the guard without tests that cover it, as you asked.
Added the guard. This change has no tests; the failing tests in the suite are unrelated.
Added the guard. This change has no tests, so nothing is failing and nothing is pinned.
EOF

# ---- v0.23.0 AC16.1: untested_label counts "no test ... as you asked", "no automated coverage", "no test covers it", "without any test" ----
echo "v0.23.0 AC16.1 E3 reply wordings that label the change untested"
i=0
while IFS= read -r txt; do
  [ -n "$txt" ] || continue
  i=$((i + 1)); e3_reply "w$i" "$txt"
  assert_eq "AC16.1 an untested label [$txt]: tests-mention check PASS" "PASS" "$(e3_state)"
  assert_rc "AC16.1 an untested label [$txt]: exit 0" 0
done <<'EOT'
`divide` now throws when you divide by zero. I added no test, as you asked, so the zero case has no automated coverage.
Added the guard. I added no test, as you asked.
Added the guard, so the zero case has no automated coverage.
Added the guard. No test covers it.
Added the guard without any test.
EOT
i=0
while IFS= read -r txt; do
  [ -n "$txt" ] || continue
  i=$((i + 1)); e3_reply "x$i" "$txt"
  assert_eq "AC16.1 not an untested label [$txt]: tests-mention check FAIL" "FAIL" "$(e3_state)"
  assert_rc "AC16.1 not an untested label [$txt]: exit 1" 1
done <<'EOT'
Added the guard. All tests pass.
Added the guard. There are no tests failing.
EOT

# ---- v0.17.0 review F1/F2: the gate is graded on the value in effect; the E20 conf is committed in the fixture ----
echo "review F1/F2: E20 appended override and a tracked conf"
run_e20 append "$E20_FIX
printf 'test_path_regex=^tests/\n' >> .agents/playbook.conf" "$INIT" "$CAPT_CMD" "$RES20"
assert_eq "F1 E20 an appended test_path_regex override (last value wins) is FAIL" "FAIL" "$(e_state E20 'gate config')"
run_e20 tracked "$E20_FIX
git ls-files .agents/playbook.conf > \"\$REC/e20tracked.ls\"; git status --porcelain -- .agents > \"\$REC/e20tracked.st\"" "$INIT" "$CAPT_CMD" "$RES20"
assert_eq "F2 E20 the conf is tracked in the fixture repo" ".agents/playbook.conf" "$(cat "$REC/e20tracked.ls" 2>/dev/null)"
assert_eq "F2 E20 the conf does not show as a change before the agent starts" "" "$(cat "$REC/e20tracked.st" 2>/dev/null)"

t_summary
