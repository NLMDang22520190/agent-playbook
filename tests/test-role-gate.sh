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

echo "AC1 test configuration counts as test"
for f in jest.config.js jest.config.ts vitest.config.mts playwright.config.ts cypress.config.js \
         karma.conf.js .mocharc.yml pytest.ini src/__snapshots__/a.test.js.snap x/y.snap \
         phpunit.xml phpunit.xml.dist; do
  run bash "$GATE" classify "$f"; assert_eq "AC1 test config path: $f" "test" "$OUT"
done
for f in src/config.ts jest.js docs/playwright.md snapshot.js tox.ini setup.cfg; do
  run bash "$GATE" classify "$f"; assert_eq "AC1 still code: $f" "code" "$OUT"
done
R="$(mk_tmp)"; mk_repo "$R"; cd "$R" || exit 3
printf 'module.exports = { testTimeout: 5000 };\n' > jest.config.js
git add -A && git commit -q -m "jest config"
printf 'module.exports = { testPathIgnorePatterns: ["tests"] };\n' > jest.config.js
run bash "$GATE" check implementer;             assert_rc "AC1 implementer changing jest.config.js fails" 1
assert_contains "AC1 violation names jest.config.js" "$OUT" "jest.config.js"

echo "AC2 size: within limits (boundary 3 files / 100 lines)"
R="$(mk_tmp)"; mk_repo "$R"; cd "$R" || exit 3
seq 1 98 > src/a.js; printf 'b\n' > src/b.js; printf 'c\n' > src/c.js
run bash "$GATE" size;                          assert_rc "AC2 exactly 3 files / 100 lines exits 0" 0
assert_contains "AC2 prints files/lines summary" "$OUT" "files: 3/3 lines: 100/100"
assert_not_contains "AC2 no escalation within limits" "$OUT" "escalate to Full"

echo "AC2 size: over limits"
printf 'd\n' >> src/c.js
run bash "$GATE" size;                          assert_rc "AC2 101 lines exits 1" 1
assert_contains "AC2 over lines summary" "$OUT" "files: 3/3 lines: 101/100"
assert_contains "AC2 over lines says escalate to Full" "$OUT" "escalate to Full"
rm src/a.js src/b.js src/c.js
for n in 1 2 3 4; do printf 'x\n' > "src/f$n.js"; done
run bash "$GATE" size;                          assert_rc "AC2 4 files exits 1" 1
assert_contains "AC2 over files summary" "$OUT" "files: 4/3 lines: 4/100"
assert_contains "AC2 over files says escalate to Full" "$OUT" "escalate to Full"

echo "AC2 size: custom limits"
run bash "$GATE" size --max-files 5 --max-lines 200; assert_rc "AC2 raised limits pass" 0
assert_contains "AC2 custom limits shown" "$OUT" "files: 4/5 lines: 4/200"
run bash "$GATE" size --max-files 10 --max-lines 3; assert_rc "AC2 custom --max-lines enforced" 1
assert_contains "AC2 custom max-lines shown" "$OUT" "files: 4/10 lines: 4/3"

echo "AC2 size: what is not counted / what is"
R="$(mk_tmp)"; mk_repo "$R"; cd "$R" || exit 3
seq 1 500 > tests/big.test.js; seq 1 500 >> tests/app.test.js
seq 1 500 > jest.config.js
mkdir -p .agents/handoff && seq 1 500 > .agents/handoff/02-tests.md
run bash "$GATE" size;                          assert_rc "AC2 test files and handoff not counted" 0
assert_contains "AC2 zero production change" "$OUT" "files: 0/3 lines: 0/100"
printf '1\n2\n3\n4\n5\n' > src/new.js
run bash "$GATE" size;                          assert_contains "AC2 untracked file counts all its lines" "$OUT" "files: 1/3 lines: 5/100"
rm src/new.js
rm src/app.js
run bash "$GATE" size;                          assert_contains "AC2 deleted lines count" "$OUT" "files: 1/3 lines: 1/100"
git checkout -q -- src/app.js
printf 'a\0b\0c' > src/logo.bin
run bash "$GATE" size;                          assert_contains "AC2 binary file counts as 1 line (D2)" "$OUT" "files: 1/3 lines: 1/100"
rm src/logo.bin

echo "AC2 size: --base counts committed and staged changes"
R="$(mk_tmp)"; mk_repo "$R"; cd "$R" || exit 3
RED="$(git rev-parse HEAD)"
printf 'a\nb\nc\n' > src/app.js
git add -A && git commit -q -m "feat"
printf 'x\ny\n' > src/b.js; git add src/b.js
run bash "$GATE" size --base "$RED";            assert_rc "AC2 committed+staged within limits" 0
assert_contains "AC2 committed (+3 -1) and staged (+2) counted" "$OUT" "files: 2/3 lines: 6/100"

echo "AC2 size: errors"
run bash "$GATE" size --max-files;              assert_rc "AC2 --max-files without value exits 2" 2
run bash "$GATE" size --max-lines abc;          assert_rc "AC2 non-numeric --max-lines exits 2" 2
run bash "$GATE" size --bogus;                  assert_rc "AC2 unknown option exits 2" 2
run bash "$GATE" size --base no-such-ref;       assert_rc "AC2 bad --base exits 3" 3
N="$(mk_tmp)"; cd "$N" || exit 3
run bash "$GATE" size;                          assert_rc "AC2 outside git exits 3" 3

t_summary
