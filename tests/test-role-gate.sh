#!/usr/bin/env bash
# Tests for scripts/role-gate.sh (enforces tester / implementer / reviewer separation)
. "$(dirname "$0")/lib.sh"
GATE="$PB_ROOT/scripts/role-gate.sh"
export PLAYBOOK_HOME="$(mk_tmp)"   # isolate from the real ~/.agents/playbook.conf

echo "classify"
for f in src/app.test.ts pkg/foo_test.go test_foo.py tests/a.js e2e/login.spec.ts \
         src/__tests__/x.ts features/login.feature conftest.py spec/models/user_spec.rb \
         src/components/Button.test.tsx; do
  run bash "$GATE" classify "$f"; assert_eq "test path: $f" "test" "$OUT"
done
for f in src/app.ts docs/latest.md contest/x.js src/protest.js README.md src/attest/index.js; do
  run bash "$GATE" classify "$f"; assert_eq "code path: $f" "code" "$OUT"
done

echo "tester role"
R="$(mk_tmp)"; mk_repo "$R"; cd "$R" || exit 3
printf 'test("new", () => {});\n' > tests/new.test.js
run bash "$GATE" check tester;                  assert_rc "tester may add a new test file" 0
printf 'module.exports = 2;\n' > src/app.js
run bash "$GATE" check tester;                  assert_rc "tester touching production code fails" 1
assert_contains "violation names the file" "$OUT" "src/app.js"
git checkout -q -- src/app.js
mkdir -p .agents/handoff && echo x > .agents/handoff/02-tests.md
run bash "$GATE" check tester;                  assert_rc "handoff dir is always allowed" 0

echo "implementer role"
R="$(mk_tmp)"; mk_repo "$R"; cd "$R" || exit 3
printf 'module.exports = 2;\n' > src/app.js
run bash "$GATE" check implementer;             assert_rc "implementer may edit production code" 0
printf 'test("weakened", () => {});\n' > tests/app.test.js
run bash "$GATE" check implementer;             assert_rc "implementer editing a test fails" 1
assert_contains "violation names the test" "$OUT" "tests/app.test.js"
git checkout -q -- tests/app.test.js
rm tests/app.test.js
run bash "$GATE" check implementer;             assert_rc "implementer deleting a test fails" 1
git checkout -q -- tests/app.test.js
printf 'x\n' > tests/sneaky.test.js
run bash "$GATE" check implementer;             assert_rc "implementer adding an untracked test fails" 1
rm tests/sneaky.test.js
git add -A
run bash "$GATE" check implementer;             assert_rc "staged production change still fine" 0

echo "--base (tests committed before implementation)"
R="$(mk_tmp)"; mk_repo "$R"; cd "$R" || exit 3
printf 'test("red", () => {});\n' > tests/red.test.js
git add -A && git commit -q -m "test(red)"
RED="$(git rev-parse HEAD)"
printf 'module.exports = 3;\n' > src/app.js
run bash "$GATE" check implementer --base "$RED"; assert_rc "implementer vs red commit passes" 0
git add -A && git commit -q -m "feat(green)"
run bash "$GATE" check implementer --base "$RED"; assert_rc "committed prod change since red still passes" 0
printf 'test("tampered", () => {});\n' > tests/red.test.js
git add -A && git commit -q -m "tamper"
run bash "$GATE" check implementer --base "$RED"; assert_rc "committed test tampering since red fails" 1

echo "reviewer role"
R="$(mk_tmp)"; mk_repo "$R"; cd "$R" || exit 3
run bash "$GATE" check reviewer;                assert_rc "reviewer with no changes passes" 0
mkdir -p .agents/handoff && echo ok > .agents/handoff/05-review.md
run bash "$GATE" check reviewer;                assert_rc "reviewer may write the handoff file" 0
printf 'module.exports = 9;\n' > src/app.js
run bash "$GATE" check reviewer;                assert_rc "reviewer editing code fails" 1
git checkout -q -- src/app.js
printf '# edited\n' >> README.md
run bash "$GATE" check reviewer;                assert_rc "reviewer editing docs fails too" 1

echo "config override"
R="$(mk_tmp)"; mk_repo "$R"; cd "$R" || exit 3
mkdir -p .agents && printf 'test_path_regex=^checks/\n' > .agents/playbook.conf
run bash "$GATE" classify checks/a.rb;          assert_eq "custom regex marks checks/ as test" "test" "$OUT"
run bash "$GATE" classify tests/a.js;           assert_eq "custom regex replaces the default" "code" "$OUT"

echo "errors"
N="$(mk_tmp)"; cd "$N" || exit 3
run bash "$GATE" check tester;                  assert_rc "non-git directory exits 3" 3
cd "$R" || exit 3
run bash "$GATE" check wizard;                  assert_rc "unknown role exits 2" 2
run bash "$GATE" check tester --base no-such-ref; assert_rc "bad --base exits 3" 3

t_summary
