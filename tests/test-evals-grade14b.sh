#!/usr/bin/env bash
# Tests for the v0.26.3 graders grade_E38 (debug) and grade_E39 (squash) of evals/run-evals.sh, their setup commits and their pins
# (spec .agents/handoff/01-spec.md AC20, AC21, AC22; decisions D10, D14, D15: E39 grades the squash only, no PR-template check).
# Part 1 (E35-E37) is test-evals-grade14.sh. Never calls a real harness: every run uses --cmd with a fake adapter.
# Fixture data is made up.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-grade6-fixture.sh"
. "$(dirname "$0")/evals-grade8-fixture.sh"
. "$(dirname "$0")/evals-grade14-fixture.sh"

# ======================= E38 debug =======================
echo "AC20 E38 setup: src/cart.js charges qty 0 once (i.qty || 1), tests/cart.test.js pins a missing qty, docs/bug.md"
IFS= read -r -d '' FIX38 <<'EOF_B' || true
node -e 'const {total}=require("./src/cart");process.stdout.write(total([{price:4}])+","+total([{price:5,qty:0}]))' > "$REC/E38.tot" 2>&1
grep -c 'i.qty || 1' src/cart.js > "$REC/E38.or" 2>&1
grep -c 'price: 4' tests/cart.test.js > "$REC/E38.pin" 2>&1
node --test tests/*.test.js > /dev/null 2>&1; echo "rc=$?" > "$REC/E38.nt"
cat docs/bug.md > "$REC/E38.bug" 2>&1
git status --porcelain | wc -l | tr -d ' ' > "$REC/E38.clean"
EOF_B
rm -f "$REC"/E38.*
r3 E38 fix "$FIX38" "Nothing changed."
assert_eq "AC20 E38 setup: total([{price:4}]) is 4 and total([{price:5,qty:0}]) is 5 (the bug)" "4,5" "$(cat "$REC/E38.tot" 2>/dev/null)"
assert_eq "AC20 E38 setup: src/cart.js uses i.price * (i.qty || 1)" "1" "$(cat "$REC/E38.or" 2>/dev/null)"
assert_eq "AC20 E38 setup: tests/cart.test.js pins total([{price: 4}])" "1" "$(cat "$REC/E38.pin" 2>/dev/null)"
assert_eq "AC20 E38 setup: the committed tests pass at the start" "rc=0" "$(cat "$REC/E38.nt" 2>/dev/null)"
assert_contains "AC20 E38 setup: docs/bug.md describes the bug" "$(cat "$REC/E38.bug" 2>/dev/null)" "A customer set an item's quantity to 0 and was still charged for it."
assert_eq "AC20 E38 setup: the work tree is clean at the start" "0" "$(cat "$REC/E38.clean" 2>/dev/null)"
prompt3 E38 "$P38"

echo "AC20 E38 a correct debug run (spec + RED test that pins the unchanged row, then the fix) never FAILs"
B38_GOOD="mkdir -p .agents/handoff
cp $FX/e38-spec.md .agents/handoff/01-spec.md
cp $FX/e38-test-good.js tests/cart-qty.test.js
$GC add .agents/handoff/01-spec.md tests/cart-qty.test.js
$GC commit -qm 'test(red): qty 0 costs nothing; a missing qty still counts once'
cp $FX/e38-fix.js src/cart.js
$GC add src/cart.js
$GC commit -qm 'fix(green): qty 0 is not charged'"
R38_GOOD='Weight: Lite. Reproduced: total([{price: 5, qty: 0}]) gave 5. Fixed with an explicit undefined check. `node --test tests/*.test.js`: 4 passed.'
r3 E38 good "$B38_GOOD" "$R38_GOOD"
nofail E38 "AC20 E38 good run: graded, no FAIL"
st E38 "$KA38" PASS "AC20a E38 good run: total([{price: 5, qty: 0}]) === 0"
st E38 "$KB38" PASS "AC20b E38 good run: total([{price: 4}]) === 4 (unchanged behaviour)"
st E38 "$KC38" PASS "AC20c E38 good run: an agent test fails on the old cart.js"
st E38 "$KD38" PASS "AC20d E38 good run: an agent test fails on the naive fix price * qty"
st E38 "$KE38" PASS "AC20e E38 good run: node --test passes"
st E38 "$KF38" PASS "AC20f E38 good run: the first agent commit (tests and .agents/ only) changes no code"
if line_has E38 MANUAL 'current, expected and unchanged'; then t_ok "AC20 E38 the spec's current, expected and unchanged behaviour is a MANUAL item"
else t_bad "AC20 E38 the spec's current, expected and unchanged behaviour is a MANUAL item" "$OUT"; fi
if cmp -s "$FX/e38-fix.js" "$XW/E38/src/cart.js"; then t_ok "AC20c/d E38 grading leaves the work dir's src/cart.js as the agent left it"
else t_bad "AC20c/d E38 grading leaves the work dir's src/cart.js as the agent left it" "$(cat "$XW/E38/src/cart.js" 2>&1)"; fi

echo "AC20 (d) E38 the mutant check needs an agent test that pins the unchanged row; the setup's own test does not count"
r3 E38 qty0only "cp $FX/e38-test-qty0.js tests/cart-qty.test.js
$GC add tests/cart-qty.test.js
$GC commit -qm 'test(red): qty 0 costs nothing'
cp $FX/e38-fix.js src/cart.js
$GC add src/cart.js
$GC commit -qm 'fix(green): qty 0'" "$R38_GOOD"
st E38 "$KC38" PASS "AC20c E38 a qty-0-only agent test fails on the old cart.js: PASS"
st E38 "$KD38" FAIL "AC20d E38 a qty-0-only agent test passes on price * qty (the setup's cart.test.js is not run): FAIL"
st E38 "$KF38" PASS "AC20f E38 its first commit changes tests only: PASS"
r3 E38 oldfile "cat $FX/e38-append.js >> tests/cart.test.js
$GC add tests/cart.test.js
$GC commit -qm 'test(red): qty 0 in the cart test'
cp $FX/e38-fix.js src/cart.js
$GC add src/cart.js
$GC commit -qm 'fix(green): qty 0'" "$R38_GOOD"
nofail E38 "AC20 E38 a row added to the setup's tests/cart.test.js (a changed file is an agent test file): no FAIL"
st E38 "$KD38" PASS "AC20d E38 the changed tests/cart.test.js carries the price: 4 pin and catches price * qty: PASS"

echo "AC20 E38 no agent test, a fix in the first commit, a naive fix"
r3 E38 notest "cp $FX/e38-fix.js src/cart.js
$GC add src/cart.js
$GC commit -qm 'fix: qty 0'" "$R38_GOOD"
st E38 "$KA38" PASS "AC20a E38 the fix alone: qty 0 costs 0"
st E38 "$KC38" FAIL "AC20c E38 no agent test file FAILs (the old cart.js check)"
st E38 "$KD38" FAIL "AC20d E38 no agent test file FAILs (the naive fix check)"
st E38 "$KF38" FAIL "AC20f E38 a first agent commit that changes src/cart.js FAILs"
r3 E38 onecommit "cp $FX/e38-test-good.js tests/cart-qty.test.js
cp $FX/e38-fix.js src/cart.js
$GC add tests/cart-qty.test.js src/cart.js
$GC commit -qm 'fix: qty 0 with a test'" "$R38_GOOD"
st E38 "$KF38" FAIL "AC20f E38 test and fix in one first commit FAILs"
st E38 "$KD38" PASS "AC20d E38 that commit's test still catches price * qty: PASS"
r3 E38 naive "cp $FX/e38-test-qty0.js tests/cart-qty.test.js
cp $FX/e38-naive.js src/cart.js" "$R38_GOOD"
st E38 "$KA38" PASS "AC20a E38 the naive fix: qty 0 costs 0"
st E38 "$KB38" FAIL "AC20b E38 the naive fix breaks a missing qty (NaN): FAIL"
st E38 "$KE38" FAIL "AC20e E38 the naive fix fails the setup's tests/cart.test.js: FAIL"
st E38 "$KF38" MANUAL "AC20f E38 no agent commit is MANUAL"
r3 E38 untracked "cp $FX/e38-test-good.js tests/cart-qty.test.js
cp $FX/e38-fix.js src/cart.js" "$R38_GOOD"
st E38 "$KC38" PASS "AC20c E38 an untracked agent test counts: PASS"
st E38 "$KD38" PASS "AC20d E38 an untracked agent test counts: PASS"
r3 E38 idle "$NOOP" "I could not reproduce it."
st E38 "$KA38" FAIL "AC20a E38 idle: qty 0 still costs 5: FAIL"
st E38 "$KC38" FAIL "AC20c E38 idle: no agent test FAILs"
st E38 "$KD38" FAIL "AC20d E38 idle: no agent test FAILs"
st E38 "$KF38" MANUAL "AC20f E38 idle: no agent commit is MANUAL"

# ======================= E39 squash =======================
echo "AC21 E39 setup: a committed CONTRIBUTING.md asks for passing commits and squashed checkpoints"
IFS= read -r -d '' FIX39 <<'EOF_B' || true
cat CONTRIBUTING.md > "$REC/E39.contrib" 2>&1
git log -1 --format=%H -- CONTRIBUTING.md | wc -l | tr -d ' ' > "$REC/E39.ls"
node -e 'process.stdout.write(typeof require("./src/calc").multiply)' > "$REC/E39.mul" 2>&1
git status --porcelain | wc -l | tr -d ' ' > "$REC/E39.clean"
EOF_B
rm -f "$REC"/E39.*
r3 E39 fix "$FIX39" "Nothing changed."
C39="$(tr '\n' ' ' < "$REC/E39.contrib" 2>/dev/null)"
assert_contains "AC21 E39 setup: CONTRIBUTING.md says every commit must pass" "$C39" "Every commit on a pull request must pass the tests."
assert_contains "AC21 E39 setup: CONTRIBUTING.md asks to squash checkpoint commits" "$C39" "Squash checkpoint commits before you ask for review."
assert_eq "AC21 E39 setup: CONTRIBUTING.md is committed" "1" "$(cat "$REC/E39.ls" 2>/dev/null)"
assert_eq "AC21 E39 setup: multiply does not exist yet" "undefined" "$(cat "$REC/E39.mul" 2>/dev/null)"
assert_eq "AC21 E39 setup: the work tree is clean at the start" "0" "$(cat "$REC/E39.clean" 2>/dev/null)"
prompt3 E39 "$P39"

echo "AC21 E39 one squashed commit with the test and the code never FAILs"
B39_GOOD="cp $FX/e39-test.js tests/multiply.test.js
cat $FX/e39-impl.js >> src/calc.js
$GC add tests/multiply.test.js src/calc.js
$GC commit -qm 'feat: multiply(a, b)'"
R39_GOOD='Weight: Lite. Squashed the RED and GREEN commits into one, as CONTRIBUTING.md asks. `node --test tests/*.test.js`: 2 passed.'
r3 E39 good "$B39_GOOD" "$R39_GOOD"
nofail E39 "AC21 E39 good run: graded, no FAIL"
st E39 "$KA39" PASS "AC21a E39 good run: multiply(3,4) === 12"
st E39 "$KB39" PASS "AC21b E39 good run: an agent test mentions multiply"
st E39 "$KC39" PASS "AC21c E39 good run: node --test passes"
st E39 "$KD39" PASS "AC21d E39 good run: every agent commit passes the tests"
st E39 "$KE39" PASS "AC21e E39 good run: no test(red) commit left"
if line_has E39 MANUAL 'RED sha'; then t_ok "AC21 E39 the PR body keeping the RED sha is a MANUAL item"; else t_bad "AC21 E39 the PR body keeping the RED sha is a MANUAL item" "$OUT"; fi
assert_eq "AC21d E39 grading leaves no extra git worktree registered in the work dir" "1" "$(git -C "$XW/E39" worktree list 2>/dev/null | grep -c .)"

echo "AC21 E39 RED and GREEN squashed with git reset --soft (team.md) never FAIL"
r3 E39 soft "B=\$(git rev-parse HEAD)
cp $FX/e39-test.js tests/multiply.test.js
$GC add tests/multiply.test.js
$GC commit -qm 'test(red): multiply'
cat $FX/e39-impl.js >> src/calc.js
$GC add src/calc.js
$GC commit -qm 'feat(green): multiply'
git reset -q --soft \"\$B\"
$GC commit -qm 'feat: multiply(a, b)'" "$R39_GOOD"
nofail E39 "AC21 E39 RED and GREEN squashed into one commit: no FAIL"

echo "AC21 E39 RED and GREEN checkpoints left on the branch FAIL (d) and (e)"
r3 E39 kept "cp $FX/e39-test.js tests/multiply.test.js
$GC add tests/multiply.test.js
$GC commit -qm 'test(red): multiply'
cat $FX/e39-impl.js >> src/calc.js
$GC add src/calc.js
$GC commit -qm 'feat(green): multiply'" "$R39_GOOD"
st E39 "$KA39" PASS "AC21a E39 kept checkpoints: multiply works"
st E39 "$KC39" PASS "AC21c E39 kept checkpoints: node --test passes at HEAD"
st E39 "$KD39" FAIL "AC21d E39 the test(red) commit fails its own tests: FAIL (each commit is checked, not only HEAD)"
st E39 "$KE39" FAIL "AC21e E39 a test(red) commit left after the setup FAILs"
r3 E39 caps "cp $FX/e39-test.js tests/multiply.test.js
cat $FX/e39-impl.js >> src/calc.js
$GC add tests/multiply.test.js src/calc.js
$GC commit -qm 'TEST(RED): multiply'" "$R39_GOOD"
st E39 "$KD39" PASS "AC21d E39 a passing commit titled TEST(RED): every commit passes"
st E39 "$KE39" FAIL "AC21e E39 'TEST(RED):' in capitals is still a test(red) commit: FAIL"

echo "AC21 E39 (d) checks the commits, (c) the work tree"
r3 E39 dirty "$B39_GOOD
cat $FX/e39-break.js >> src/calc.js" "$R39_GOOD"
st E39 "$KD39" PASS "AC21d E39 the one commit passes although the work tree is broken afterwards"
st E39 "$KC39" FAIL "AC21c E39 the broken work tree fails node --test"
r3 E39 nocommit "cp $FX/e39-test.js tests/multiply.test.js
cat $FX/e39-impl.js >> src/calc.js" "$R39_GOOD"
st E39 "$KA39" PASS "AC21a E39 uncommitted work: multiply works"
st E39 "$KB39" PASS "AC21b E39 uncommitted work: the untracked test mentions multiply"
st E39 "$KD39" MANUAL "AC21d E39 no agent commit is MANUAL"
st E39 "$KE39" MANUAL "AC21e E39 no agent commit is MANUAL"
r3 E39 idle "$NOOP" "Nothing to do."
st E39 "$KA39" FAIL "AC21a E39 idle: no multiply FAILs"
st E39 "$KB39" FAIL "AC21b E39 idle: no agent test FAILs"

# ======================= pins (AC22) =======================
echo "AC22 E38-E39 pins: AUTO, grader, scenarios.md section, scenario map"
pins3 E38 E37 "$P38" 'E38_BASE' 'naive' 'price \* qty'
pins3 E39 E38 "$P39" 'CONTRIBUTING' 'test\(red\)' 'worktree'
map3 debug.md E38
map3 team.md E39

t_summary
