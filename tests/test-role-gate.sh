#!/usr/bin/env bash
# Tests for scripts/role-gate.sh (enforces tester / implementer / reviewer separation)
. "$(dirname "$0")/lib.sh"
GATE="$PB_ROOT/scripts/role-gate.sh"
export PLAYBOOK_HOME="$(mk_tmp)"   # isolate from the real ~/.agents/playbook.conf
# Git on Windows defaults to core.autocrlf=true and then prints "LF will be replaced by CRLF" warnings on
# stderr, which would break the byte-identical output checks. Force it off for every git call in this suite
# (command-line style config, git >= 2.31; it beats repository and global config).
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.autocrlf GIT_CONFIG_VALUE_0=false

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
N="$(mk_tmp)"; cd "$N" || exit 3   # leave $R: its .agents/playbook.conf overrides the default regex
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


# ---- v0.9.0 #4: test infrastructure has its own role (test_infra_regex) ----
INFRA_RE='^(tests/(lib|run-all)\.sh$|ci/)'
# mk_infra_repo [CONF_LINE] -> temp repo with tests/lib.sh, tests/run-all.sh, ci/build.sh committed (and the conf, committed, when given)
mk_infra_repo() {
  local d; d="$(mk_tmp)"; mk_repo "$d"
  ( cd "$d" && mkdir -p ci &&
    printf 'helper() { :; }\n' > tests/lib.sh &&
    printf '#!/usr/bin/env bash\nexit 0\n' > tests/run-all.sh &&
    printf '#!/usr/bin/env bash\nexit 0\n' > ci/build.sh &&
    if [ -n "${1:-}" ]; then mkdir -p .agents && printf '%s\n' "$1" > .agents/playbook.conf; fi &&
    git add -A && git commit -q -m "infra files" )
  printf '%s\n' "$d"
}

echo "AC4.1 classify: infra before test"
R="$(mk_infra_repo "test_infra_regex=$INFRA_RE")"; cd "$R" || exit 3
run bash "$GATE" classify tests/lib.sh;        assert_eq "AC4.1 infra path that is also a test path -> infra (infra wins)" "infra" "$OUT"
run bash "$GATE" classify tests/run-all.sh;    assert_eq "AC4.1 tests/run-all.sh -> infra" "infra" "$OUT"
run bash "$GATE" classify ci/build.sh;         assert_eq "AC4.1 ci/build.sh (would be code) -> infra" "infra" "$OUT"
run bash "$GATE" classify tests/app.test.js;   assert_eq "AC4.1 an ordinary test stays test" "test" "$OUT"
run bash "$GATE" classify src/app.js;          assert_eq "AC4.1 an ordinary source file stays code" "code" "$OUT"
run bash "$GATE" classify src/ci/x.js;         assert_eq "AC4.1 the regex is anchored as written (src/ci/x.js is code)" "code" "$OUT"
run bash "$GATE" classify tests/lib.shx;       assert_eq "AC4.1 near-miss tests/lib.shx is not infra (test)" "test" "$OUT"
cd "$R" && printf 'test_path_regex=^checks/\ntest_infra_regex=^ci/\n' > .agents/playbook.conf
run bash "$GATE" classify ci/build.sh;         assert_eq "AC4.1 infra works together with a custom test_path_regex" "infra" "$OUT"
run bash "$GATE" classify checks/a.rb;         assert_eq "AC4.1 custom test_path_regex still gives test" "test" "$OUT"
run bash "$GATE" classify tests/lib.sh;        assert_eq "AC4.1 with custom regexes tests/lib.sh is code (neither matches)" "code" "$OUT"
# global conf also works
N="$(mk_tmp)"; mk_repo "$N"; cd "$N" || exit 3
G_HOME="$(mk_tmp)"; mkdir -p "$G_HOME/.agents"; printf 'test_infra_regex=^tools/ci/\n' > "$G_HOME/.agents/playbook.conf"
run env PLAYBOOK_HOME="$G_HOME" bash "$GATE" classify tools/ci/run.sh; assert_eq "AC4.1 test_infra_regex is read from the global conf too" "infra" "$OUT"

echo "AC4.2 check infra"
R="$(mk_infra_repo "test_infra_regex=$INFRA_RE")"; cd "$R" || exit 3
run bash "$GATE" check infra;                   assert_rc "AC4.2 no changes -> exit 0" 0
printf '#!/usr/bin/env bash\nexit 1\n' > tests/run-all.sh
run bash "$GATE" check infra;                   assert_rc "AC4.2 changing only an infra path is allowed" 0
assert_contains "AC4.2 success line names the role" "$OUT" "role gate passed for infra"
printf 'echo hi\n' >> ci/build.sh; printf 'helper2() { :; }\n' >> tests/lib.sh
mkdir -p .agents/handoff && echo x > .agents/handoff/03-infra.md
run bash "$GATE" check infra;                   assert_rc "AC4.2 several infra paths plus the handoff dir are allowed" 0
printf 'module.exports = 2;\n' > src/app.js
run bash "$GATE" check infra;                   assert_rc "AC4.2 a production code change fails" 1
assert_contains "AC4.2 violation names the code file" "$OUT" "src/app.js"
assert_contains "AC4.2 violation line names the infra role" "$OUT" "VIOLATION (infra)"
git checkout -q -- src/app.js
printf 'test("weakened", () => {});\n' > tests/app.test.js
run bash "$GATE" check infra;                   assert_rc "AC4.2 a (non-infra) test change fails" 1
assert_contains "AC4.2 violation names the test file" "$OUT" "tests/app.test.js"
git checkout -q -- tests/app.test.js
printf 'x\n' > tests/new.test.js
run bash "$GATE" check infra;                   assert_rc "AC4.2 an untracked new test fails" 1
rm tests/new.test.js
printf 'y\n' > src/new.js
run bash "$GATE" check infra;                   assert_rc "AC4.2 an untracked new code file fails" 1
rm src/new.js
git rm -q --cached ci/build.sh >/dev/null 2>&1; rm -f ci/build.sh
run bash "$GATE" check infra;                   assert_rc "AC4.2 deleting an infra path is still an infra change" 0
git checkout -q HEAD -- ci/build.sh 2>/dev/null
run bash "$GATE" check infra --base no-such-ref; assert_rc "AC4.2 bad --base exits 3" 3
N="$(mk_tmp)"; cd "$N" || exit 3
run bash "$GATE" check infra;                   assert_rc "AC4.2 non-git directory exits 3" 3

echo "AC4.2 check infra --base (tests first, then the infra change)"
R="$(mk_infra_repo "test_infra_regex=$INFRA_RE")"; cd "$R" || exit 3
INIT="$(git rev-parse HEAD)"
printf 'test("for the new runner", () => {});\n' > tests/runner.test.js
git add -A && git commit -q -m "test(red)"
RED="$(git rev-parse HEAD)"
printf '#!/usr/bin/env bash\nexit 7\n' > tests/run-all.sh
git add -A && git commit -q -m "infra change"
run bash "$GATE" check infra --base "$RED";     assert_rc "AC4.2 infra commit since RED passes" 0
run bash "$GATE" check infra --base "$INIT";    assert_rc "AC4.2 against the older base the tester's test shows up -> fails" 1
assert_contains "AC4.2 the tester's test file is named" "$OUT" "tests/runner.test.js"
run bash "$GATE" check tester --base "$RED";    assert_rc "AC4.3 tester role: the committed infra change since RED fails" 1
assert_contains "AC4.3 tester violation names the infra file" "$OUT" "tests/run-all.sh"

echo "AC4.3 tester and implementer must not touch infra"
R="$(mk_infra_repo "test_infra_regex=$INFRA_RE")"; cd "$R" || exit 3
printf 'test("new", () => {});\n' > tests/new.test.js
run bash "$GATE" check tester;                  assert_rc "AC4.3 tester may still add a test" 0
printf 'helper2() { :; }\n' >> tests/lib.sh
run bash "$GATE" check tester;                  assert_rc "AC4.3 tester changing tests/lib.sh (infra) fails" 1
assert_contains "AC4.3 violation names tests/lib.sh" "$OUT" "tests/lib.sh"
assert_contains "AC4.3 violation says infra" "$OUT" "infra"
git checkout -q -- tests/lib.sh
printf 'echo hi\n' >> ci/build.sh
run bash "$GATE" check tester;                  assert_rc "AC4.3 tester changing ci/build.sh (infra, would be code) fails" 1
git checkout -q -- ci/build.sh; rm tests/new.test.js
printf 'module.exports = 2;\n' > src/app.js
run bash "$GATE" check implementer;             assert_rc "AC4.3 implementer may still edit production code" 0
printf '#!/usr/bin/env bash\nexit 1\n' > tests/run-all.sh
run bash "$GATE" check implementer;             assert_rc "AC4.3 implementer editing the runner (infra) fails" 1
assert_contains "AC4.3 violation names tests/run-all.sh" "$OUT" "tests/run-all.sh"
git checkout -q -- tests/run-all.sh
rm ci/build.sh
run bash "$GATE" check implementer;             assert_rc "AC4.3 implementer deleting an infra file fails" 1
git checkout -q -- ci/build.sh
printf 'x\n' > ci/extra.sh
run bash "$GATE" check implementer;             assert_rc "AC4.3 implementer adding an untracked infra file fails" 1
rm ci/extra.sh
git checkout -q -- src/app.js
run bash "$GATE" check reviewer;                assert_rc "AC4.3 reviewer with no changes passes" 0
printf 'echo hi\n' >> ci/build.sh
run bash "$GATE" check reviewer;                assert_rc "AC4.3 reviewer: any change (infra) is still a violation" 1
git checkout -q -- ci/build.sh
printf 'module.exports = 9;\n' > src/app.js
run bash "$GATE" check reviewer;                assert_rc "AC4.3 reviewer unchanged: code change is a violation" 1
git checkout -q -- src/app.js

echo "AC4.4 size counts infra like production"
R="$(mk_infra_repo "test_infra_regex=$INFRA_RE")"; cd "$R" || exit 3
seq 1 120 > ci/build.sh
run bash "$GATE" size;                          assert_rc "AC4.4 a 120-line infra change is over the Lite limit -> exit 1" 1
assert_contains "AC4.4 infra file and lines are counted" "$OUT" "files: 1/3 lines: 122/100"
assert_contains "AC4.4 says escalate to Full" "$OUT" "escalate to Full"
git checkout -q -- ci/build.sh
seq 1 4 >> tests/lib.sh; printf 'one\n' > src/new.js
run bash "$GATE" size;                          assert_rc "AC4.4 small infra + code change within limits -> exit 0" 0
assert_contains "AC4.4 infra (tests/lib.sh, +4) and code (+1) both counted" "$OUT" "files: 2/3 lines: 5/100"
rm src/new.js; git checkout -q -- tests/lib.sh
seq 1 300 > tests/big.test.js
run bash "$GATE" size;                          assert_contains "AC4.4 ordinary tests are still not counted" "$OUT" "files: 0/3 lines: 0/100"
rm tests/big.test.js

echo "AC4.5 key unset or empty: behaviour and output are unchanged"
for MODE in unset empty; do
  if [ "$MODE" = unset ]; then CONF=""; else CONF="test_infra_regex="; fi
  R="$(mk_infra_repo "$CONF")"; cd "$R" || exit 3
  run bash "$GATE" classify tests/lib.sh;       assert_eq "AC4.5 ($MODE) tests/lib.sh is test" "test" "$OUT"
  run bash "$GATE" classify tests/run-all.sh;   assert_eq "AC4.5 ($MODE) tests/run-all.sh is test" "test" "$OUT"
  run bash "$GATE" classify ci/build.sh;        assert_eq "AC4.5 ($MODE) ci/build.sh is code" "code" "$OUT"
  run bash "$GATE" classify src/app.js;         assert_eq "AC4.5 ($MODE) src/app.js is code" "code" "$OUT"
  run bash "$GATE" classify README.md;          assert_eq "AC4.5 ($MODE) README.md is code (empty regex must not match everything)" "code" "$OUT"
  printf 'helper2() { :; }\n' >> tests/lib.sh
  run bash "$GATE" check tester;                assert_rc "AC4.5 ($MODE) tester may change tests/lib.sh" 0
  assert_eq "AC4.5 ($MODE) tester output byte-identical" "OK: role gate passed for tester (1 file(s) checked, base=HEAD)" "$OUT"
  run bash "$GATE" check implementer;           assert_rc "AC4.5 ($MODE) implementer changing tests/lib.sh fails" 1
  assert_eq "AC4.5 ($MODE) implementer output byte-identical" "VIOLATION (implementer): tests/lib.sh [test]
role gate FAILED for implementer: 1 violation(s), base=HEAD" "$OUT"
  run bash "$GATE" size;                        assert_rc "AC4.5 ($MODE) size ignores the test-like tests/lib.sh" 0
  assert_eq "AC4.5 ($MODE) size output byte-identical" "files: 0/3 lines: 0/100 (base=HEAD)" "$OUT"
  git checkout -q -- tests/lib.sh
  printf 'module.exports = 2;\n' > src/app.js
  run bash "$GATE" check tester;                assert_rc "AC4.5 ($MODE) tester changing code fails" 1
  assert_eq "AC4.5 ($MODE) tester violation output byte-identical" "VIOLATION (tester): src/app.js [code]
role gate FAILED for tester: 1 violation(s), base=HEAD" "$OUT"
  run bash "$GATE" check implementer;           assert_rc "AC4.5 ($MODE) implementer changing code passes" 0
  assert_eq "AC4.5 ($MODE) implementer output byte-identical" "OK: role gate passed for implementer (1 file(s) checked, base=HEAD)" "$OUT"
  run bash "$GATE" size;                        assert_eq "AC4.5 ($MODE) size with one code line changed" "files: 1/3 lines: 2/100 (base=HEAD)" "$OUT"
  run bash "$GATE" check reviewer;              assert_rc "AC4.5 ($MODE) reviewer changing code fails" 1
  assert_eq "AC4.5 ($MODE) reviewer output byte-identical" "VIOLATION (reviewer): src/app.js [code]
role gate FAILED for reviewer: 1 violation(s), base=HEAD" "$OUT"
  git checkout -q -- src/app.js
done

echo "AC4.7 an invalid regex fails closed (exit 3, names the key, never OK)"
# bad_regex_repo KEY VALUE -> temp repo with tests/lib.sh changed and the (committed) conf KEY=VALUE
bad_regex_repo() {
  local d; d="$(mk_infra_repo "$1=$2")"
  ( cd "$d" && printf 'helper2() { :; }\n' >> tests/lib.sh && printf 'module.exports = 2;\n' > src/app.js )
  printf '%s\n' "$d"
}
for KV in 'test_infra_regex=^tests/(lib' 'test_path_regex=^(checks' 'test_infra_regex=['; do
  KEY="${KV%%=*}"; VAL="${KV#*=}"
  R="$(bad_regex_repo "$KEY" "$VAL")"; cd "$R" || exit 3
  for cmdline in "classify tests/lib.sh" "check tester" "check implementer" "size"; do
    run bash "$GATE" $cmdline
    assert_rc "AC4.7 [$VAL] $cmdline exits 3" 3
    assert_contains "AC4.7 [$VAL] $cmdline names $KEY" "$OUT" "$KEY"
    assert_not_contains "AC4.7 [$VAL] $cmdline never prints OK" "$OUT" "OK:"
  done
done
R="$(mk_infra_repo "test_infra_regex=$INFRA_RE")"; cd "$R" || exit 3
printf 'helper2() { :; }\n' >> tests/lib.sh
run bash "$GATE" check tester;                  assert_rc "AC4.7 control: a valid regex still works (tester on infra -> 1)" 1
G_HOME="$(mk_tmp)"; mkdir -p "$G_HOME/.agents"; printf 'test_infra_regex=^tests/(lib\n' > "$G_HOME/.agents/playbook.conf"
N="$(mk_tmp)"; mk_repo "$N"; cd "$N" || exit 3
run env PLAYBOOK_HOME="$G_HOME" bash "$GATE" classify tests/lib.sh
assert_rc "AC4.7 an invalid regex in the global conf also exits 3" 3
assert_contains "AC4.7 global-conf failure names the key" "$OUT" "test_infra_regex"


# ---- v0.10.0 AC1.2: the gate shows where a moved regex comes from ----
# conf_repo CONFTEXT -> repo with src/app.js changed (a code change), conf committed (so it is no change itself)
conf_repo() {
  local d; d="$(mk_tmp)"; mk_repo "$d"
  ( cd "$d" && mkdir -p .agents && printf '%b' "$1" > .agents/playbook.conf && git add -A && git commit -q -m conf &&
    printf 'module.exports = 2;\n' > src/app.js )
  printf '%s\n' "$d"
}
# notes_of -> the note: lines of $OUT
notes_of() { printf '%s\n' "$OUT" | grep '^note:' || true; }

echo "AC1.2 note lines for config-file regexes"
R="$(conf_repo 'test_path_regex=^checks/\n')"; cd "$R" || exit 3
run bash "$GATE" check implementer
assert_rc "AC1.2 implementer on code with a project test_path_regex passes" 0
N1="$(notes_of)"
assert_contains "AC1.2 note names the key" "$N1" "test_path_regex"
assert_contains "AC1.2 note names the project scope" "$N1" "project"
assert_contains "AC1.2 note shows the value" "$N1" "^checks/"
assert_not_contains "AC1.2 no note for the key that is not set" "$N1" "test_infra_regex"
assert_eq "AC1.2 exactly one note line" "1" "$(printf '%s\n' "$N1" | grep -c '^note:')"
assert_eq "AC1.2 the note is the first line, before the verdict" "note:" "$(printf '%s\n' "$OUT" | head -n 1 | cut -c1-5)"
assert_eq "AC1.2 the verdict line follows unchanged" "OK: role gate passed for implementer (1 file(s) checked, base=HEAD)" "$(printf '%s\n' "$OUT" | tail -n 1)"

R="$(conf_repo 'test_infra_regex=^ci/\n')"; cd "$R" || exit 3
run bash "$GATE" check implementer
N1="$(notes_of)"
assert_contains "AC1.2 infra note names the key" "$N1" "test_infra_regex"
assert_contains "AC1.2 infra note names the project scope" "$N1" "project"
assert_contains "AC1.2 infra note shows the value" "$N1" "^ci/"
assert_not_contains "AC1.2 infra only: no test_path_regex note" "$N1" "test_path_regex"

R="$(conf_repo 'test_path_regex=^checks/\ntest_infra_regex=^ci/\n')"; cd "$R" || exit 3
run bash "$GATE" check tester
assert_rc "AC1.2 tester changing code still fails" 1
assert_eq "AC1.2 both keys: two note lines" "2" "$(notes_of | grep -c '^note:')"
assert_contains "AC1.2 both keys: path note present" "$(notes_of)" "test_path_regex"
assert_contains "AC1.2 both keys: infra note present" "$(notes_of)" "test_infra_regex"
FIRSTV="$(printf '%s\n' "$OUT" | grep -n '^VIOLATION' | head -n 1 | cut -d: -f1)"
LASTN="$(printf '%s\n' "$OUT" | grep -n '^note:' | tail -n 1 | cut -d: -f1)"
if [ -n "$FIRSTV" ] && [ -n "$LASTN" ] && [ "$LASTN" -lt "$FIRSTV" ]; then t_ok "AC1.2 notes come before the VIOLATION lines"; else t_bad "AC1.2 notes come before the VIOLATION lines" "notes at $LASTN, violation at $FIRSTV in [$OUT]"; fi
assert_contains "AC1.2 the violation itself is still reported" "$OUT" "VIOLATION (tester): src/app.js [code]"
run bash "$GATE" check reviewer
assert_contains "AC1.2 reviewer also shows the notes" "$OUT" "note:"

echo "AC1.2 global scope and precedence"
G_HOME="$(mk_tmp)"; mkdir -p "$G_HOME/.agents"; printf 'test_path_regex=^gchecks/\ntest_infra_regex=^gci/\n' > "$G_HOME/.agents/playbook.conf"
N="$(mk_tmp)"; mk_repo "$N"; cd "$N" || exit 3; printf 'module.exports = 2;\n' > src/app.js
run env PLAYBOOK_HOME="$G_HOME" bash "$GATE" check implementer
assert_rc "AC1.2 global regexes: implementer on code passes" 0
GN="$(notes_of)"
assert_eq "AC1.2 global: two note lines" "2" "$(printf '%s\n' "$GN" | grep -c '^note:')"
assert_contains "AC1.2 global note shows the global scope" "$GN" "global"
assert_not_contains "AC1.2 global note is not labelled project" "$GN" "project"
assert_contains "AC1.2 global note shows the path value" "$GN" "^gchecks/"
assert_contains "AC1.2 global note shows the infra value" "$GN" "^gci/"
# project value wins over the global one: the note shows the effective source
R="$(conf_repo 'test_path_regex=^pchecks/\n')"; cd "$R" || exit 3
run env PLAYBOOK_HOME="$G_HOME" bash "$GATE" check implementer
PN="$(notes_of | grep test_path_regex)"
assert_contains "AC1.2 project value wins: project scope shown" "$PN" "project"
assert_contains "AC1.2 project value wins: its value shown" "$PN" "^pchecks/"
assert_not_contains "AC1.2 project value wins: the shadowed global value is not shown" "$PN" "^gchecks/"
assert_contains "AC1.2 the global-only infra key is still noted as global" "$(notes_of | grep test_infra_regex)" "global"

echo "AC1.2 no note, output unchanged"
R="$(conf_repo 'language=vi\nmodel_tester_claude=x\n')"; cd "$R" || exit 3
run bash "$GATE" check implementer
assert_eq "AC1.2 other keys only: implementer output byte-identical to v0.9.0" "OK: role gate passed for implementer (1 file(s) checked, base=HEAD)" "$OUT"
run bash "$GATE" check tester
assert_eq "AC1.2 other keys only: tester output byte-identical to v0.9.0" "VIOLATION (tester): src/app.js [code]
role gate FAILED for tester: 1 violation(s), base=HEAD" "$OUT"
R="$(conf_repo 'test_path_regex=^checks/\ntest_infra_regex=^ci/\n')"; cd "$R" || exit 3
run bash "$GATE" classify checks/a.rb
assert_eq "AC1.2 classify prints only the class, even with notes-worthy keys" "test" "$OUT"
run bash "$GATE" classify ci/x.sh
assert_eq "AC1.2 classify infra prints only the class" "infra" "$OUT"
run bash "$GATE" size
assert_eq "AC1.2 size output unchanged with the keys set" "files: 1/3 lines: 2/100 (base=HEAD)" "$OUT"

# ---- v0.10.0 AC5.1: an empty test_path_regex fails closed ----
echo "AC5.1 empty test_path_regex"
# empty_repo CONFTEXT -> repo with a code change and a test change, conf committed
empty_repo() {
  local d; d="$(conf_repo "$1")"
  ( cd "$d" && printf 'test("x", () => { /* edited */ });\n' > tests/app.test.js )
  printf '%s\n' "$d"
}
check_empty() { # label  -> run the three commands in the current dir with the current env prefix in "$@"
  local label="$1"; shift
  for cmdline in "classify src/app.js" "classify tests/app.test.js" "check tester" "check implementer" "check reviewer" "size"; do
    run "$@" bash "$GATE" $cmdline
    assert_rc "AC5.1 [$label] $cmdline exits 3" 3
    assert_contains "AC5.1 [$label] $cmdline names the key" "$OUT" "test_path_regex"
    assert_contains "AC5.1 [$label] $cmdline says it is empty" "$OUT" "empty"
    assert_contains "AC5.1 [$label] $cmdline says to unset it" "$OUT" "unset"
    assert_not_contains "AC5.1 [$label] $cmdline never prints OK" "$OUT" "OK:"
  done
}
R="$(empty_repo 'test_path_regex=\n')"; cd "$R" || exit 3
check_empty "project" env
R="$(mk_tmp)"; mk_repo "$R"; cd "$R" || exit 3; printf 'module.exports = 2;\n' > src/app.js
G_HOME="$(mk_tmp)"; mkdir -p "$G_HOME/.agents"; printf 'test_path_regex=\n' > "$G_HOME/.agents/playbook.conf"
check_empty "global" env PLAYBOOK_HOME="$G_HOME"
# an empty project value shadows a non-empty global one: still fails closed
R="$(empty_repo 'test_path_regex=\n')"; cd "$R" || exit 3
G2="$(mk_tmp)"; mkdir -p "$G2/.agents"; printf 'test_path_regex=^checks/\n' > "$G2/.agents/playbook.conf"
run env PLAYBOOK_HOME="$G2" bash "$GATE" classify src/app.js
assert_rc "AC5.1 empty project value wins over a non-empty global one: exit 3" 3
# a non-empty project value wins over an empty global one: works
R="$(conf_repo 'test_path_regex=^checks/\n')"; cd "$R" || exit 3
run env PLAYBOOK_HOME="$G_HOME" bash "$GATE" classify checks/a.rb
assert_eq "AC5.1 non-empty project value beats an empty global one" "test" "$OUT"
# unset key stays the default; an empty infra regex stays off
R="$(conf_repo 'language=vi\n')"; cd "$R" || exit 3
run bash "$GATE" classify tests/app.test.js; assert_eq "AC5.1 unset key: default regex still applies" "test" "$OUT"
R="$(conf_repo 'test_infra_regex=\n')"; cd "$R" || exit 3
run bash "$GATE" classify tests/app.test.js; assert_eq "AC5.1 empty test_infra_regex stays off (classify)" "test" "$OUT"
assert_rc "AC5.1 empty test_infra_regex stays off (exit 0)" 0
run bash "$GATE" check implementer;          assert_rc "AC5.1 empty test_infra_regex stays off (check works)" 0

# ---- v0.10.0 round 2: shadowing empty infra regex, notes on stdout ----
echo "AC1.2 an empty project test_infra_regex shadowing a global one is noted"
R="$(conf_repo 'test_infra_regex=\n')"; cd "$R" || exit 3
( mkdir -p tests && printf 'helper() { :; }\n' > tests/lib.sh && git add -A && git commit -q -m lib ) >/dev/null
printf 'helper2() { :; }\n' >> tests/lib.sh
G3="$(mk_tmp)"; mkdir -p "$G3/.agents"; printf 'test_infra_regex=^tests/lib\\.sh$\n' > "$G3/.agents/playbook.conf"
run env PLAYBOOK_HOME="$G3" bash "$GATE" check tester
assert_rc "AC1.2 shadowed: tester editing tests/lib.sh passes (infra is off)" 0
SN="$(notes_of | grep test_infra_regex)"
assert_contains "AC1.2 shadowed: a note names test_infra_regex" "$SN" "test_infra_regex"
assert_contains "AC1.2 shadowed: the note says it is empty" "$SN" "empty"
assert_contains "AC1.2 shadowed: the note says it is the project conf" "$SN" "project"
case "$SN" in *override*|*shadow*|*off*) t_ok "AC1.2 shadowed: the note says it overrides / switches off the global value" ;; *) t_bad "AC1.2 shadowed: the note says it overrides / switches off the global value" "note: [$SN]" ;; esac
assert_contains "AC1.2 shadowed: the note mentions the global value" "$SN" "global"
assert_eq "AC1.2 shadowed: the note is first, before the verdict" "note:" "$(printf '%s\n' "$OUT" | head -n 1 | cut -c1-5)"
# no global value: the v0.9 byte-identical behaviour (empty infra regex is silent)
run bash "$GATE" check tester
assert_eq "AC1.2 empty project value with no global value stays silent" "OK: role gate passed for tester (1 file(s) checked, base=HEAD)" "$OUT"
# empty global value and empty project value: nothing to shadow
G4="$(mk_tmp)"; mkdir -p "$G4/.agents"; printf 'test_infra_regex=\n' > "$G4/.agents/playbook.conf"
run env PLAYBOOK_HOME="$G4" bash "$GATE" check tester
assert_eq "AC1.2 empty project over empty global stays silent" "OK: role gate passed for tester (1 file(s) checked, base=HEAD)" "$OUT"

echo "AC1.2 notes go to stdout, not stderr"
R="$(conf_repo 'test_path_regex=^checks/\ntest_infra_regex=^ci/\n')"; cd "$R" || exit 3
SO="$(bash "$GATE" check implementer 2>/dev/null)"
SE="$(bash "$GATE" check implementer 2>&1 >/dev/null)"
assert_contains "AC1.2 stdout carries the test_path_regex note" "$SO" "note:"
assert_eq "AC1.2 stdout carries both notes" "2" "$(printf '%s\n' "$SO" | grep -c '^note:')"
assert_eq "AC1.2 stderr is empty on a passing check" "" "$SE"
SE="$(bash "$GATE" check tester 2>&1 >/dev/null)"
assert_not_contains "AC1.2 stderr has no note on a failing check" "$SE" "note:"

t_summary
