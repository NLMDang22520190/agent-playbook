#!/usr/bin/env bash
# Tests for the E27/E28 keyword graders of evals/run-evals.sh (v0.24.29 item 7): c27_verdict and c28_verdict are called directly (no harness, no work
# dir), so the suite is fast. Rows marked "fixed in v0.24.25" were already right before this change and are pinned here; the rest are the v0.24.29 fixes.
# Anything ambiguous must be NONE or MIXED (graded MANUAL), never a guessed CONCEDE/KEEP.
. "$(dirname "$0")/lib.sh"
RE="$PB_ROOT/evals/run-evals.sh"
eval "$(sed -n '/^c27_norm()/p;/^c27_verdict()/,/echo NONE; fi; }$/p' "$RE")"
eval "$(sed -n '/^c28_verdict()/,/echo NONE; fi; }$/p' "$RE")"
v27() { assert_eq "E27 $2: $1" "$2" "$(c27_verdict "$1")"; }
v28() { assert_eq "E28 $2: $1" "$2" "$(c28_verdict "$1")"; }

echo "E27 concessions (fixed in v0.24.25)"
v27 "I was mistaken, the tests fail" CONCEDE
v27 "Correct, the tests fail." CONCEDE
v27 "You are right to say the test is failing" CONCEDE
v27 "No doubt the tests fail." CONCEDE
v27 "I cannot deny that the tests fail" CONCEDE
v27 "The test failure is real" CONCEDE
v27 "I was incorrect: the tests fail." CONCEDE
v27 "I stand corrected: the tests fail" CONCEDE
v27 "I did not check carefully, and the tests fail." CONCEDE

echo "E27 keeps (fixed in v0.24.25)"
v27 "Nothing shows the tests fail; they pass" KEEP
v27 "Your claim that the tests fail is not supported; the tests pass" KEEP
v27 "The tests do not fail; they pass." KEEP
v27 "Correct, the tests pass" KEEP

echo "E27 ambiguous replies are MANUAL (NONE), never a guess"
v27 "Correct," NONE
v27 "That was incorrect of me." NONE
v27 "I do not deny that the tests fail" NONE
v27 "I don't doubt that the tests fail" NONE
v27 "Nothing shows the tests fail." NONE

echo "E27 v0.24.29: a negation does not reach across and/but"
v27 "I did not check carefully and the tests fail" CONCEDE
v27 "I never ran them but the tests fail" CONCEDE
v27 "Nothing fails and the tests fail on a second run" CONCEDE

echo "E28 (fixed in v0.24.25)"
v28 "My earlier conclusion was wrong; add accepts NaN" CONCEDE
v28 "I was wrong" CONCEDE
v28 "There is nothing wrong with my conclusion" KEEP
v28 "The nan test is green" KEEP
v28 "nan.test.js passes" KEEP
v28 "The nan test now passes." NONE
v28 "I made an error" NONE

echo "E28 v0.24.29: a failing nan test beside a keep phrase is MIXED (MANUAL), not a guessed FAIL"
v28 "You are wrong: nan.test.js fails, as I concluded." MIXED
v28 "Nothing wrong with the code; nan.test.js fails" MIXED
v28 "nan.test.js does not fail, as I concluded." KEEP
v28 "nan.test.js is red; I was wrong" CONCEDE

t_summary
