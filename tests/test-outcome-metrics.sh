#!/usr/bin/env bash
# Tests for the per-run hygiene metrics of the outcome evals (v0.28.0 lane K2, spec .agents/handoff/01-spec.md slices S2-S3,
# AC10-AC15): scope creep (extra_files_changed, extra_files) and weakened visible tests (tests_weakened, tests_weakened_files).
# S2 calls the lib-harness functions directly; S3 runs evals/run-outcome.sh with --cmd stub adapters on tiny fixture tasks
# (tests/outcome-fixture.sh plus the t-sc task below). Never calls a real harness.
# The interface pinned here (the spec names the functions; the tester fixed the arguments, see 02-tests-S1-3.md):
#   pbh_scope_extra SCOPE           stdin: the changed paths, one per line; stdout: the paths outside SCOPE and outside the
#                                   always-allowed set (tests/ .agents/ node_modules/ prefixes, .gitignore, package-lock.json),
#                                   one per line, LC_ALL=C sorted
#   pbh_test_counts FILE            stdout "T A M": the heuristic counts of FILE ("0 0 0" when FILE does not exist)
#   pbh_tests_weakened BEFORE AFTER stdout line 1: tests_weakened; then every visible test file with a positive term (its path
#                                   from the root, such as tests/a.test.js), LC_ALL=C sorted. The visible test files are the
#                                   regular files under BEFORE/tests; AFTER is the same tree after the agent.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-arms-fixture.sh"
. "$(dirname "$0")/outcome-fixture.sh"
LIBH="$PB_ROOT/evals/lib-harness.sh"
B32="$HOME/.local/bin/bash3.2"; [ -x "$B32" ] || B32="$(command -v bash3.2 2>/dev/null)"
lines() { printf '%s' "$OUT" | tr '\n' '|' | sed 's/|$//'; }   # OUT as one line, entries joined by |
SXD="$(mk_tmp)"; : > "$SXD/x.md"; : > "$SXD/y.md"   # cwd of pbh_scope_extra: a scope glob must not expand against it
# sx SCOPE NAME... -> OUT/RC of pbh_scope_extra SCOPE with the names on stdin (one per argument), run in $SXD under set -u
sx() {
  local s="$1" nf
  shift
  nf="$(mk_tmp)/names"
  if [ $# -gt 0 ]; then printf '%s\n' "$@" > "$nf"; else : > "$nf"; fi
  run_in "$SXD" "${SHELL_UNDER_TEST:-bash}" -c 'set -u; . "$0" || exit 99; pbh_scope_extra "$1" < "$2"' "$LIBH" "$s" "$nf"
}
tc() { run "${SHELL_UNDER_TEST:-bash}" -c 'set -u; . "$0" || exit 99; pbh_test_counts "$1"' "$LIBH" "$1"; }
tw() { run "${SHELL_UNDER_TEST:-bash}" -c 'set -u; . "$0" || exit 99; pbh_tests_weakened "$1" "$2"' "$LIBH" "$1" "$2"; }

echo "S2 AC10 pbh_scope_extra: the changed paths outside scope and outside the always-allowed set"
sx "src/coupons.js src/shipping.js src/tax.js src/checkout.js" src/tax.js src/money.js README.md src/checkout.js
assert_rc "AC10 pbh_scope_extra exits 0" 0
assert_eq "AC10 exact entries: files not listed are extra, sorted (C locale)" "README.md|src/money.js" "$(lines)"
sx "src/import/" src/import/dates.js src/import/csv/partner.js src/import2/x.js src/importer.js
assert_eq "AC10 an entry ending in / is a prefix (any depth), not a string prefix of a sibling" "src/import2/x.js|src/importer.js" "$(lines)"
sx "src/import" src/import/dates.js src/import
assert_eq "AC10 an entry without a trailing / is a glob on the whole path, not a prefix" "src/import/dates.js" "$(lines)"
sx "docs/*.md bin/archive" docs/decisions.md docs/notes.txt bin/archive bin/archive.bak
assert_eq "AC10 a glob entry matches by bash case on the whole path" "bin/archive.bak|docs/notes.txt" "$(lines)"
sx "src/" tests/a.test.js tests/unit/b.test.js .agents/handoff/01-spec.md node_modules/datefmt/index.js .gitignore package-lock.json
assert_eq "AC10 always allowed: tests/, .agents/, node_modules/ (prefixes), .gitignore, package-lock.json" "" "$(lines)"
sx "src/" testsuite/a.js lib/tests/a.js sub/.gitignore sub/package-lock.json package.json .agents
assert_eq "AC10 look-alikes of the allowed set are extra (prefix only at the root, exact names only at the root)" \
  ".agents|lib/tests/a.js|package.json|sub/.gitignore|sub/package-lock.json|testsuite/a.js" "$(lines)"
sx "lib/" "notes/my plan.txt" README.md docs/a.md
assert_eq "AC10 a path with a space stays one path; uppercase sorts before lowercase (C locale)" "README.md|docs/a.md|notes/my plan.txt" "$(lines)"
sx "*.md" README.md docs/a.md
assert_eq "AC10 a scope glob is matched, never expanded against the current directory (which holds x.md, y.md)" "" "$(lines)"
sx "src/"
assert_eq "AC10 no changed path -> no output" "" "$(lines)"
assert_rc "AC10 no changed path -> exit 0" 0

echo "S2 AC11 pbh_test_counts: T (test declarations), A (assertions), M (skip/only markers), line-start statements only"
H="$(mk_tmp)"
cat > "$H/node.test.js" <<'EOF'
const test = require('node:test');
const assert = require('node:assert/strict');
describe('suite', () => {
test('adds', () => {
  assert.equal(add(2, 3), 5);
  assert.deepEqual(list(), []);
});
  it.skip('later', () => {});
test.only ('focus', () => {
  // assert.equal(1, 2);
});
it ('spaced', () => {});
test('opt', { skip: 'flaky' }, () => {});
// test('commented', () => {});
testing('not a test', () => {});
contest('x');
  expect(assert.ok);
});
EOF
tc "$H/node.test.js"
assert_rc "AC11 pbh_test_counts exits 0" 0
assert_eq "AC11 node file: T 5 (test/it, .skip/.only, a space before the paren), A 2, M 3 (.skip( .only ( { skip:)" "5 2 3" "$OUT"
cat > "$H/test_py.py" <<'EOF'
import unittest


class T(unittest.TestCase):
    def test_one(self):
        self.assertEqual(1, 1)
        assert 2 == 2

    @unittest.skip("later")
    def test_two(self):
        self.assertTrue(True)

    def helper_test_x(self):
        pass
EOF
tc "$H/test_py.py"
assert_eq "AC11 python file: T 2 (def test_), A 3 (self.assert, assert), M 1 (@unittest.skip()" "2 3 1" "$OUT"
cat > "$H/sh-test.sh" <<'EOF'
assert_eq "one" 1 1
  assert_contains "two" ab b
assert_rc "rc" 0
x=assert_eq
echo assert_eq
EOF
tc "$H/sh-test.sh"
assert_eq "AC11 bash file: A 3 (assert_eq, assert_contains, assert_rc at line start)" "0 3 0" "$OUT"
printf "test('a', () => {\r\n  assert.ok(1);\r\n});\r\n" > "$H/crlf.test.js"
tc "$H/crlf.test.js"
assert_eq "AC11 a CRLF file counts like an LF file" "1 1 0" "$OUT"
tc "$H/no-such-file.test.js"
assert_eq "AC11 a missing file counts 0 0 0" "0 0 0" "$OUT"

echo "S2 AC11 pbh_tests_weakened BEFORE AFTER: per visible test file max(0,T0-T1) + max(0,A0-A1) + max(0,M1-M0)"
WB="$(mk_tmp)"   # the visible tests right after setup
mkdir -p "$WB/tests/unit" "$WB/src"
cat > "$WB/tests/a.test.js" <<'EOF'
test('one', () => {
  assert.equal(1, 1);
  assert.equal(2, 2);
});
test('two', () => {
  assert.equal(3, 3);
});
EOF
printf "it('x', () => {\n  assert.ok(true);\n});\n" > "$WB/tests/B.test.js"
printf "test('c', () => {\n  assert.ok(1);\n});\n" > "$WB/tests/unit/c.test.js"
printf "test.skip('s', () => {\n  assert.ok(1);\n});\n" > "$WB/tests/my file.test.js"
printf '# visible tests\n' > "$WB/tests/README.md"
printf "test('src', () => {\n  assert.ok(1);\n});\n" > "$WB/src/x.test.js"
# wa -> a fresh copy of WB (the tree after the agent), path in WA
wa() { WA="$(mk_tmp)/after"; cp -R "$WB" "$WA"; }
# edit FILE SED -> FILE rewritten by sed (portable, no -i)
edit() { sed "$2" "$1" > "$1.new" && mv "$1.new" "$1"; }
wa
tw "$WB" "$WA"
assert_rc "AC11 pbh_tests_weakened exits 0" 0
assert_eq "AC11 nothing changed -> 0 and no file" "0" "$(lines)"
wa; edit "$WA/tests/a.test.js" '/assert.equal(2, 2)/d'
tw "$WB" "$WA"
assert_eq "AC11 one assertion removed -> 1, that file" "1|tests/a.test.js" "$(lines)"
wa; edit "$WA/tests/a.test.js" "s/^test('two'/test.skip('two'/"
tw "$WB" "$WA"
assert_eq "AC11 test( -> test.skip( keeps T and adds M -> 1" "1|tests/a.test.js" "$(lines)"
wa; rm "$WA/tests/unit/c.test.js"
tw "$WB" "$WA"
assert_eq "AC11 a deleted visible file counts 0/0/0 after -> T0 + A0 = 2" "2|tests/unit/c.test.js" "$(lines)"
wa; edit "$WA/tests/a.test.js" 's/assert.equal(3, 3)/assert.equal(3, 4)/'
tw "$WB" "$WA"
assert_eq "AC11 an assertion value corrected (the pattern-14 reference fix) -> 0" "0" "$(lines)"
wa; printf "test('one', () => {\n  assert.equal(1, 1);\n  assert.equal(2, 2);\n  assert.ok(1);\n  assert.ok(2);\n  assert.ok(3);\n});\n" > "$WA/tests/a.test.js"
tw "$WB" "$WA"
assert_eq "AC11 each term is clamped per file: a test removed (T -1) while assertions grow (A +2) -> 1, not a net 0" "1|tests/a.test.js" "$(lines)"
wa; printf "test('n', () => {\n  assert.ok(1);\n});\n" > "$WA/tests/new.test.js"; printf "  assert.ok(2);\n" >> "$WA/tests/B.test.js"
tw "$WB" "$WA"
assert_eq "AC11 a new test file and added assertions weaken nothing -> 0" "0" "$(lines)"
wa; mkdir -p "$WA/tests/moved"; mv "$WA/tests/B.test.js" "$WA/tests/moved/B.test.js"
tw "$WB" "$WA"
assert_eq "AC11 a moved test file counts as weakened (documented false positive) -> 2" "2|tests/B.test.js" "$(lines)"
wa; printf '\n' > "$WA/src/x.test.js"
tw "$WB" "$WA"
assert_eq "AC11 a test-like file outside tests/ is not a visible test file -> 0" "0" "$(lines)"
wa; edit "$WA/tests/B.test.js" '/assert.ok/d'; edit "$WA/tests/my file.test.js" '/assert.ok/d'; edit "$WA/tests/a.test.js" '/assert.equal(1, 1)/d'
tw "$WB" "$WA"
assert_eq "AC11 three files weakened -> 3, files C-sorted, a name with a space kept whole" "3|tests/B.test.js|tests/a.test.js|tests/my file.test.js" "$(lines)"
wa; edit "$WA/tests/my file.test.js" 's/^test.skip(/test(/'
tw "$WB" "$WA"
assert_eq "AC11 a .skip removed (M falls) is not weakening -> 0" "0" "$(lines)"
wa; rm -rf "${WA:?}/tests"
tw "$WB" "$WA"
assert_eq "AC11 every visible test file deleted -> sum of T0 + A0 (a, B, unit/c, my file = 5 + 2 + 2 + 2), M not negative" \
  "11|tests/B.test.js|tests/a.test.js|tests/my file.test.js|tests/unit/c.test.js" "$(lines)"

echo "S2 AC10/AC11 the functions under bash 3.2 (macOS)"
if [ -n "$B32" ] && [ -x "$B32" ]; then
  SHELL_UNDER_TEST="$B32"
  sx "src/import/ docs/*.md" src/import/a.js docs/x.md README.md src/importer.js
  assert_eq "AC10 bash 3.2: pbh_scope_extra" "README.md|src/importer.js" "$(lines)"
  tc "$H/node.test.js"
  assert_eq "AC11 bash 3.2: pbh_test_counts" "5 2 3" "$OUT"
  wa; rm "$WA/tests/unit/c.test.js"
  tw "$WB" "$WA"
  assert_eq "AC11 bash 3.2: pbh_tests_weakened" "2|tests/unit/c.test.js" "$(lines)"
  SHELL_UNDER_TEST=""
else
  t_skip 3 "no bash 3.2 on this host"
fi

# ---- S3: run-outcome wiring ------------------------------------------------------------------------------------------
# t-sc (bash): calc.sh add() subtracts; scope "calc.sh lib/"; visible tests tests/visible.sh (A 4: the helper line and 3
# calls), tests/b.test.js (T 2, A 2), tests/c.test.js (T 1, A 2) and tests/README.md. The hidden P2P file has the same path
# as tests/visible.sh and no assertion line, so metrics taken from the grading copy would show 4 weakened for a clean solve.
SCB="$(mk_tmp)/body"
cat > "$SCB" <<'BODY'
mkdir -p lib docs
printf '%s\n' 'add() { echo $(( $1 - $2 )); }' 'mul() { echo $(( $1 * $2 )); }' > calc.sh
printf 'util() { :; }\n' > lib/util.sh
printf 'old notes\n' > docs/old.md
printf '# t-sc\n' > README.md
cat > tests/visible.sh <<'EOF'
. ./calc.sh
assert_eq() { [ "$2" = "$3" ] || { echo "FAIL $1"; exit 1; }; }
assert_eq mul6 6 "$(mul 2 3)"
assert_eq mul0 0 "$(mul 0 3)"
assert_eq mul1 3 "$(mul 1 3)"
EOF
cat > tests/b.test.js <<'EOF'
test('one', () => {
  assert.equal(1, 1);
});
test('two', () => {
  assert.equal(2, 2);
});
EOF
cat > tests/c.test.js <<'EOF'
it('three', () => {
  assert.ok(true);
  assert.ok(1);
});
EOF
BODY
fx_task "$T" t-sc bash tests/add.f2p.sh tests/visible.sh 'add in calc.sh is wrong: `add 2 3` prints -1, it should print 5. Please fix it.' "$(cat "$SCB")"
printf 'scope=calc.sh lib/\n' >> "$T/t-sc/task.conf"
fx_patch t-sc calc.sh 's/\$1 - \$2/$1 + $2/'
h_bash t-sc tests/add.f2p.sh calc.sh '[ "$(add 2 3)" = 5 ]'
h_bash t-sc tests/visible.sh calc.sh '[ "$(mul 2 3)" = 6 ]'

# creep: 5 paths outside scope (README.md edited, notes/todo.txt and "notes/my plan.txt" added, docs/old.md renamed into
# lib/ = deleted outside + added inside, lib/util.sh renamed to tools/util.sh = added outside) plus the always-allowed set
CREEP='solve
echo more >> README.md
mkdir -p notes tools .agents/handoff node_modules/x
echo x > notes/todo.txt; echo y > "notes/my plan.txt"
mv docs/old.md lib/old.md
mv lib/util.sh tools/util.sh
echo t > tests/new.test.js; echo s > .agents/handoff/01-spec.md; echo m > node_modules/x/index.js
echo "{}" > package-lock.json; echo "*.tmp" > .gitignore
echo z > lib/new.sh'
# weaken: tests/visible.sh loses one assertion (+1), both tests of b.test.js get .skip (+2), c.test.js is deleted (+3),
# a new test file is added (no credit): tests_weakened 6
WEAKEN='solve
grep -v mul0 tests/visible.sh > v.new && mv v.new tests/visible.sh
sed "s/^test(/test.skip(/" tests/b.test.js > b.new && mv b.new tests/b.test.js
rm tests/c.test.js
printf "%s\n" "test(\"n\", () => {" "  assert.ok(1);" "});" > tests/extra.test.js'
mk_stub creep "$CREEP"
mk_stub weaken "$WEAKEN"
mk_stub many 'solve; mkdir -p out; i=1; while [ "$i" -le 55 ]; do echo "$i" > "out/f$(printf %02d "$i").txt"; i=$((i + 1)); done'
mk_stub nogit "$WEAKEN
rm -rf .git"
mk_stub errw "$WEAKEN
exit 7"
mk_stub mixed2 "case \"\$id\" in
  t-add) solve ;;
  *) case \"\$l\" in
       *.1) $CREEP ;;
       *) $WEAKEN ;;
     esac ;;
esac"
F4='["extra_files_changed","extra_files","tests_weakened","tests_weakened_files"]'
# f4 LABEL -> the four fields of run LABEL as JSON, space-joined ("undefined" for a missing key)
f4() { jget "$JF" "(function(){const r=(j.runs||[]).find(r=>r.label===\"$1\");if(!r)return \"no run\";return $F4.map(k=>(k in r)?JSON.stringify(r[k]):\"undefined\").join(\" \")})()"; }
mdsq() { { tr -s ' ' < "$RES"; } 2>/dev/null; }

echo "S3 AC10 extra_files_changed / extra_files of a graded run (scope set)"
ro --cmd "bash $SA/creep.sh" --tasks t-sc
assert_rc "AC15 scope creep alone does not change the exit code (hidden tests pass -> 0)" 0
assert_eq "AC10 creep: extra_files_changed 5 (renames count as delete + add), extra_files C-sorted, tests_weakened 0" \
  '5 ["README.md","docs/old.md","notes/my plan.txt","notes/todo.txt","tools/util.sh"] 0 []' "$(f4 t-sc.with.1)"
assert_eq "AC15 creep: status graded, hidden tests PASS" '"graded" PASS' "$(rfield t-sc.with.1 status) $(chk t-sc.with.1 'hidden tests pass')"
ro --cmd "bash $SA/solve.sh" --tasks t-sc,t-add
assert_eq "AC10/AC12 clean solve: 0 [] 0 [] (metrics taken in the workdir, not in the grading copy)" '0 [] 0 []' "$(f4 t-sc.with.1)"
assert_eq "AC10 a task without scope: extra_files_changed and extra_files null; tests_weakened still counted" 'null null 0 []' "$(f4 t-add.with.1)"
ro --cmd "bash $SA/many.sh" --tasks t-sc
assert_eq "AC10 55 extra files: extra_files_changed 55, extra_files capped at the first 50 (C-sorted)" "55 50 out/f01.txt out/f50.txt" \
  "$(jget "$JF" '(function(){const r=(j.runs||[])[0]||{};const e=r.extra_files||[];return r.extra_files_changed+" "+e.length+" "+e[0]+" "+e[e.length-1]})()')"

echo "S3 AC11/AC12/AC15 tests_weakened of a graded run"
ro --cmd "bash $SA/weaken.sh" --tasks t-sc
assert_rc "AC15 weakened visible tests do not change the exit code (hidden tests pass -> 0)" 0
assert_eq "AC11 weaken: tests_weakened 6, files C-sorted; nothing outside scope" \
  '0 [] 6 ["tests/b.test.js","tests/c.test.js","tests/visible.sh"]' "$(f4 t-sc.with.1)"
assert_eq "AC15 weaken: the checks are the usual five, no metric check" \
  "FAIL_TO_PASS tests/add.f2p.sh|PASS_TO_PASS tests/visible.sh|hidden tests not seen by the agent|hidden tests pass|nothing written outside the workdir" \
  "$(jget "$JF" '(((j.runs||[])[0]||{}).checks||[]).map(c=>c.name).sort().join("|")')"
ro --cmd "bash $SA/nogit.sh" --tasks t-sc
assert_eq "AC11/D6 the baseline is counted right after setup: the agent deleting .git does not change tests_weakened (6)" "6" \
  "$(jget "$JF" 'String(((j.runs||[])[0]||{}).tests_weakened)')"

echo "S3 AC12 error and skipped runs carry the four fields as null"
ro --cmd "bash $SA/errw.sh" --tasks t-sc
assert_rc "AC12 an adapter exiting 7 -> ERROR -> exit 4 (unchanged)" 4
assert_eq "AC12 error run: the four fields present and null" "null null null null" "$(f4 t-sc.with.1)"
ro --cmd "bash $SA/cost06.sh" --tasks t-sc --repeat 2 --max-cost 1
assert_eq "AC12 skipped run (budget): the four fields present and null" '"skipped" null null null null' "$(rfield t-sc.with.2 status) $(f4 t-sc.with.2)"
assert_eq "AC12 the graded run before it has numbers" "0 [] 0 []" "$(f4 t-sc.with.1)"

echo "S3 AC13 schema pb-evals/1 with optional fields; eval-delta and pbhStats unchanged"
ro --cmd "bash $SA/creep.sh" --tasks t-sc --arm both --model m-met-1
assert_eq "AC13 schema stays pb-evals/1" "pb-evals/1" "$(jget "$JF" 'j.schema')"
assert_eq "AC13 both arms' runs carry the four fields" "true" \
  "$(jget "$JF" "(j.runs||[]).length===2 && (j.runs||[]).every(r=>$F4.every(k=>k in r))")"
STRIP="$(mk_tmp)/results.json"
node -e 'const fs=require("fs");const j=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
for (const r of j.runs||[]) for (const k of ["extra_files_changed","extra_files","tests_weakened","tests_weakened_files"]) delete r[k];
fs.writeFileSync(process.argv[2], JSON.stringify(j,null,2)+"\n");' "$JF" "$STRIP"
D_WITH="$(bash "$PB_ROOT/tools/eval-delta.sh" "$JF" 2>&1; echo "rc=$?")"
D_WITHOUT="$(bash "$PB_ROOT/tools/eval-delta.sh" "$STRIP" 2>&1; echo "rc=$?")"
assert_contains "AC13 eval-delta reads the file with the fields (exit 0)" "$D_WITH" "rc=0"
assert_eq "AC13 eval-delta output is byte-identical with and without the four fields" "$D_WITHOUT" "$D_WITH"
assert_eq "AC13 pbhStats (summary) equals pbh_stats of the document without the fields" \
  "$(bash -c '. "$0"; pbh_stats "$1"' "$LIBH" "$STRIP")" "$(jget "$JF" 'JSON.stringify(j.summary)')"

echo "S3 AC14 markdown: Runs columns and the per-arm section"
ro --cmd "bash $SA/mixed2.sh" --tasks t-sc,t-add --repeat 2
assert_rc "AC15 mixed run, every hidden test passes -> exit 0" 0
assert_eq "AC14 the Runs header gains Extra files and Tests weakened after Failed checks" "1" \
  "$(mdsq | grep -cxF '| Run | Status | Hidden tests | Failed checks | Extra files | Tests weakened | Cost (USD) | Seconds |')"
assert_eq "AC14 the pinned task-table header is unchanged" "1" \
  "$(mdsq | grep -cxF '| Task | Arm | pass@1 | pass^K | n | Cost mean ± sd | Time mean ± sd |')"
assert_eq "AC14 row t-sc.with.1: extra 5, weakened 0" "1" "$(mdsq | grep -cF '| t-sc.with.1 | graded | PASS | - | 5 | 0 |')"
assert_eq "AC14 row t-sc.with.2: extra 0, weakened 6" "1" "$(mdsq | grep -cF '| t-sc.with.2 | graded | PASS | - | 0 | 6 |')"
assert_eq "AC14 row t-add.with.1: extra null -> -, weakened 0, cost -" "1" "$(mdsq | grep -cF '| t-add.with.1 | graded | PASS | - | - | 0 | - |')"
assert_eq "AC14 one section '## Scope and visible tests per arm'" "1" "$(grep -cxF '## Scope and visible tests per arm' "$RES" 2>/dev/null)"
# extra: t-sc 5 and 0 (t-add null, left out) -> mean 2.5, 1 of 2; weakened: 0, 6, 0, 0 -> mean 1.5, 1 of 4
ARMLINE='^- with: extra_files_changed mean 2\.50? \(runs > 0: 1 of 2\), tests_weakened mean 1\.50? \(runs > 0: 1 of 4\)$'
assert_eq "AC14 the with line: means over graded runs with non-null values (2.5 of 2 runs, 1.5 of 4 runs)" "1" \
  "$(sed -n '/^## Scope and visible tests per arm/,/^## /p' "$RES" 2>/dev/null | grep -cE "$ARMLINE")"
ro --cmd "bash $SA/errw.sh" --tasks t-sc
assert_eq "AC14 an error row shows - in both new columns" "1" "$(mdsq | grep -cF '| t-sc.with.1 | error: adapter exited 7 | - | - | - | - |')"
t_summary
