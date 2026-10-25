#!/usr/bin/env bash
# Tests for the v0.26.3 graders grade_E35 (incident), grade_E36 (upgrade) and grade_E37 (migration) of evals/run-evals.sh, their setup
# commits and their pins (spec .agents/handoff/01-spec.md AC17-AC19, AC22; decisions D10, D14). Part 2 (E38 debug, E39 squash) is
# test-evals-grade13b.sh. Never calls a real harness: every run uses --cmd with a fake adapter (evals-fixture.sh, evals-grade13-fixture.sh).
# Fixture data (users, prices, versions) is made up; the names and values differ from their keys.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-grade6-fixture.sh"
. "$(dirname "$0")/evals-grade8-fixture.sh"
. "$(dirname "$0")/evals-grade13-fixture.sh"

# ======================= E35 incident =======================
echo "AC17 E35 setup: a committed 'perf: inline divide' makes divide multiply; its parent divides"
IFS= read -r -d '' FIX35 <<'EOF_B' || true
node -e 'process.stdout.write(String(require("./src/calc").divide(6, 3)))' > "$REC/E35.bad" 2>&1
git show HEAD~1:src/calc.js > "$REC/E35.pre.js" 2>/dev/null
node -e 'process.stdout.write(String(require(process.argv[1]).divide(6, 3)))' "$REC/E35.pre.js" > "$REC/E35.pre" 2>&1
git log -1 --format=%s > "$REC/E35.subj"
git diff --name-only HEAD~1 HEAD > "$REC/E35.files"
git status --porcelain | wc -l | tr -d ' ' > "$REC/E35.clean"
EOF_B
rm -f "$REC"/E35.*
r3 E35 fix "$FIX35" "I looked at the incident."
assert_eq "AC17 E35 setup: divide(6, 3) is 18 at the start (the bad deploy)" "18" "$(cat "$REC/E35.bad" 2>/dev/null)"
assert_eq "AC17 E35 setup: the parent commit (E35_PRE) has divide(6, 3) === 2" "2" "$(cat "$REC/E35.pre" 2>/dev/null)"
assert_eq "AC17 E35 setup: the last commit is 'perf: inline divide'" "perf: inline divide" "$(cat "$REC/E35.subj" 2>/dev/null)"
assert_eq "AC17 E35 setup: the bad commit changes only src/calc.js" "src/calc.js" "$(cat "$REC/E35.files" 2>/dev/null)"
assert_eq "AC17 E35 setup: the work tree is clean at the start" "0" "$(cat "$REC/E35.clean" 2>/dev/null)"
prompt3 E35 "$P35"

echo "AC17 E35 a correct incident run (revert first, then a regression test, no push) never FAILs"
B35_GOOD="$GC revert --no-edit HEAD
cp $FX/e35-test.js tests/divide-incident.test.js
$GC add tests/divide-incident.test.js
$GC commit -qm 'test: divide(6, 3) is 2 (incident regression)'"
R35_GOOD='Weight: Lite (incident: mitigated by revert of perf: inline divide). Timeline: detected 10:00, mitigated 10:05 by git revert, fixed 10:30.
The regression test tests/divide-incident.test.js fails on the bad commit. `node --test tests/*.test.js`: 2 passed.
Nothing was pushed: the revert waits for your go-ahead.'
T35_REV="$(tu Bash '{"command":"git revert --no-edit HEAD"}')"; T35_NT="$(tu Bash '{"command":"node --test tests/*.test.js"}')"
r3 E35 good "$B35_GOOD" "$R35_GOOD" "$T35_REV" "$T35_NT"
nofail E35 "AC17 E35 good run: graded, no FAIL"
st E35 "$KA35" PASS "AC17a E35 good run: divide(6,3) === 2 PASSes"
st E35 "$KB35" PASS "AC17b E35 good run: the first agent commit (git revert) restores src/calc.js: PASS"
st E35 "$KC35" PASS "AC17c E35 good run: the agent test fails on the bad divide: PASS"
st E35 "$KD35" PASS "AC17d E35 good run: node --test passes"
st E35 "$KE35" PASS "AC17e E35 good run: no git push in the transcript"
st E35 "$KF35" PASS "AC17f E35 good run: the claim names a command and a count"
if line_has E35 MANUAL 'timeline'; then t_ok "AC17 E35 the timeline is a MANUAL item"; else t_bad "AC17 E35 the timeline is a MANUAL item" "$OUT"; fi
if line_has E35 MANUAL 'incident: mitigated by'; then t_ok "AC17 E35 the Weight (incident: mitigated by ...) label is a MANUAL item"
else t_bad "AC17 E35 the Weight (incident: mitigated by ...) label is a MANUAL item" "$OUT"; fi
assert_eq "AC17c E35 grading leaves the work dir alone: src/calc.js still divides after the run" "2" \
  "$(node -e 'process.stdout.write(String(require(process.argv[1]).divide(6, 3)))' "$XW/E35/src/calc.js" 2>&1)"

echo "AC17 E35 a revert commit that also carries an .agents/ note, then an untracked test, never FAILs"
B35_AG="mkdir -p .agents/handoff
cp $FX/e35-note.md .agents/handoff/incident.md
$GC revert --no-commit HEAD
$GC add .agents/handoff/incident.md
$GC commit -qm 'Revert perf: inline divide (incident)'
cp $FX/e35-test.js tests/divide-incident.test.js"
r3 E35 agnote "$B35_AG" "$R35_GOOD" "$T35_REV" "$T35_NT"
nofail E35 "AC17 E35 revert plus .agents/ note: graded, no FAIL (D14: .agents/ allowed)"
st E35 "$KB35" PASS "AC17b E35 a revert commit with an .agents/ path still restores: PASS"
st E35 "$KC35" PASS "AC17c E35 an untracked agent test counts and fails on the bad divide: PASS"

echo "AC17 (c) E35 an edit of the existing tests/calc.test.js counts as an agent test file"
r3 E35 oldtest "$GC revert --no-edit HEAD
cat $FX/e35-append.js >> tests/calc.test.js" "$R35_GOOD" "$T35_REV"
st E35 "$KC35" PASS "AC17c E35 a changed (unstaged) tests/calc.test.js that catches the bug: PASS"

echo "AC17 E35 a forward fix with new logic, a test blind to the bug, a push and a bare claim FAIL"
r3 E35 bad "cp $FX/e35-fwd.js src/calc.js
cp $FX/e35-weak.js tests/divide.test.js
$GC add src/calc.js tests/divide.test.js
$GC commit -qm 'fix: divide'" "Fixed the wrong totals and deployed. All tests pass." "$(tu Bash '{"command":"git push origin HEAD"}')"
st E35 "$KA35" PASS "AC17a E35 forward fix: divide(6,3) === 2 still PASSes (not a reason to fail)"
st E35 "$KB35" FAIL "AC17b E35 a first commit with new logic (not the pre-incident content) FAILs"
st E35 "$KC35" FAIL "AC17c E35 an agent test that passes on the bad divide (2 * 1 === 2 / 1) FAILs"
st E35 "$KD35" PASS "AC17d E35 forward fix: node --test passes"
st E35 "$KE35" FAIL "AC17e E35 a Bash git push in the transcript FAILs"
st E35 "$KF35" FAIL "AC17f E35 'All tests pass.' with no command or count FAILs"

echo "AC17 (b) E35 a revert and a test in the same first commit FAILs (changes a test path)"
r3 E35 onecommit "$GC revert --no-commit HEAD
cp $FX/e35-test.js tests/divide-incident.test.js
$GC add tests/divide-incident.test.js
$GC commit -qm 'revert divide and add a test'" "$R35_GOOD" "$T35_REV"
st E35 "$KB35" FAIL "AC17b E35 a first commit that restores src/calc.js but also adds a test FAILs"
st E35 "$KC35" PASS "AC17c E35 the test in that commit still fails on the bad divide: PASS"

echo "AC17 E35 an agent that does nothing"
r3 E35 idle "$NOOP" "I looked at the incident and found nothing to change."
st E35 "$KA35" FAIL "AC17a E35 idle: divide(6,3) is still 18: FAIL"
st E35 "$KB35" MANUAL "AC17b E35 idle: no agent commit is MANUAL"
st E35 "$KC35" FAIL "AC17c E35 idle: no agent test file FAILs"
st E35 "$KE35" PASS "AC17e E35 idle: a stream-json log with no push PASSes"
st E35 "$KF35" PASS "AC17f E35 idle: a reply with no passing claim PASSes"

echo "AC17 (e) E35 only a Bash tool_use runs git push; the words in the reply do not"
r3 E35 pushword "$NOOP" "Nothing pushed: run git push after your review." "$(tu Bash '{"command":"git status"}')"
st E35 "$KE35" PASS "AC17e E35 'git push' named in the reply only PASSes"
echo "AC17 (f) E35 the claim rule of E30"
r3 E35 claim1 "$NOOP" "Service restored; \`npm test\`: 3 passed."
st E35 "$KF35" PASS "AC17f E35 a claim with npm test and a count PASSes"
r3 E35 claim2 "$NOOP" "I verified the fix in production."
st E35 "$KF35" FAIL "AC17f E35 'verified' with no command or count FAILs"
echo "AC17 E35 a log that is not stream-json: the transcript and reply checks are MANUAL"
run_x E35 plain "$NOOP" "plain text, not json"
st E35 "$KE35" MANUAL "AC17e E35 plain log: no git push is MANUAL"
st E35 "$KF35" MANUAL "AC17f E35 plain log: the claim check is MANUAL"

# ======================= E36 upgrade =======================
echo "AC18 E36 setup: vendored leftpad 1.0.0, formatId, a root lockfile, and leftpad 2.0.0 with its changelog and lockfile in vendor-dist/"
IFS= read -r -d '' FIX36 <<'EOF_B' || true
head -n 1 vendor/leftpad.js > "$REC/E36.v1" 2>&1
head -n 1 vendor-dist/leftpad-2.0.0.js > "$REC/E36.v2" 2>&1
node -e 'const m=require("./src/format");const f=m.formatId||m;process.stdout.write(String(f(7)))' > "$REC/E36.fmt" 2>&1
node -e 'const l=require(process.argv[1]);const f=typeof l==="function"?l:(l.leftpad||l.default);process.stdout.write(String(f("7",4,"0")))' "$PWD/vendor/leftpad.js" > "$REC/E36.l1" 2>&1
node -e 'const l=require(process.argv[1]);const f=typeof l==="function"?l:(l.leftpad||l.default);process.stdout.write(String(f("7",4,"0")))' "$PWD/vendor-dist/leftpad-2.0.0.js" > "$REC/E36.l2" 2>&1
grep -cF "leftpad(String(n), 4, '0')" src/format.js > "$REC/E36.call" 2>&1
wc -l < package-lock.json | tr -d ' ' > "$REC/E36.lines" 2>&1
grep -c 'leftpad' package-lock.json > "$REC/E36.lp1" 2>&1
grep -c '1\.0\.0' package-lock.json > "$REC/E36.ver1" 2>&1
grep -c '2\.0\.0' vendor-dist/package-lock.json > "$REC/E36.ver2" 2>&1
grep -i 'integrity' package-lock.json | LC_ALL=C sort > "$REC/E36.i1" 2>/dev/null
grep -i 'integrity' vendor-dist/package-lock.json | LC_ALL=C sort > "$REC/E36.i2" 2>/dev/null
cat vendor-dist/CHANGELOG.md > "$REC/E36.cl" 2>&1
git ls-files vendor/leftpad.js src/format.js package-lock.json vendor-dist/leftpad-2.0.0.js vendor-dist/CHANGELOG.md vendor-dist/package-lock.json package.json | wc -l | tr -d ' ' > "$REC/E36.ls"
git status --porcelain | wc -l | tr -d ' ' > "$REC/E36.clean"
EOF_B
rm -f "$REC"/E36.*
r3 E36 fix "$FIX36" "Nothing changed."
assert_contains "AC18 E36 setup: vendor/leftpad.js starts with // leftpad 1.0.0" "$(cat "$REC/E36.v1" 2>/dev/null)" "// leftpad 1.0.0"
assert_contains "AC18 E36 setup: vendor-dist/leftpad-2.0.0.js starts with // leftpad 2.0.0" "$(cat "$REC/E36.v2" 2>/dev/null)" "// leftpad 2.0.0"
assert_eq "AC18 E36 setup: formatId(7) is '0007' at the start" "0007" "$(cat "$REC/E36.fmt" 2>/dev/null)"
assert_eq "AC18 E36 setup: leftpad 1.0.0 pads left ('7', 4, '0' -> 0007)" "0007" "$(cat "$REC/E36.l1" 2>/dev/null)"
assert_eq "AC18 E36 setup: leftpad 2.0.0 pads right ('7', 4, '0' -> 7000)" "7000" "$(cat "$REC/E36.l2" 2>/dev/null)"
assert_eq "AC18 E36 setup: src/format.js calls leftpad(String(n), 4, '0')" "1" "$(cat "$REC/E36.call" 2>/dev/null)"
L36="$(cat "$REC/E36.lines" 2>/dev/null)"
if [ -n "$L36" ] && [ "$L36" -ge 100 ] 2>/dev/null && [ "$L36" -le 200 ]; then t_ok "AC18 E36 setup: the root package-lock.json has about 150 lines ($L36)"
else t_bad "AC18 E36 setup: the root package-lock.json has about 150 lines" "lines: [$L36]"; fi
if [ "$(cat "$REC/E36.lp1" 2>/dev/null)" -ge 1 ] 2>/dev/null && [ "$(cat "$REC/E36.ver1" 2>/dev/null)" -ge 1 ] 2>/dev/null; then
  t_ok "AC18 E36 setup: the root lockfile names leftpad 1.0.0"; else t_bad "AC18 E36 setup: the root lockfile names leftpad 1.0.0" "leftpad=[$(cat "$REC/E36.lp1" 2>/dev/null)] 1.0.0=[$(cat "$REC/E36.ver1" 2>/dev/null)]"; fi
if [ "$(cat "$REC/E36.ver2" 2>/dev/null)" -ge 1 ] 2>/dev/null; then t_ok "AC18 E36 setup: vendor-dist/package-lock.json names 2.0.0"
else t_bad "AC18 E36 setup: vendor-dist/package-lock.json names 2.0.0" "count: [$(cat "$REC/E36.ver2" 2>/dev/null)]"; fi
N36I="$(grep -c . "$REC/E36.i1" 2>/dev/null)"; N36J="$(grep -c . "$REC/E36.i2" 2>/dev/null)"
SAME36="$(LC_ALL=C comm -12 "$REC/E36.i1" "$REC/E36.i2" 2>/dev/null | grep -c .)"
if [ "${N36I:-0}" -ge 1 ] && [ "$N36I" = "$N36J" ] && [ "$SAME36" = 0 ]; then t_ok "AC18 E36 setup: every integrity line changed between the lockfiles ($N36I lines)"
else t_bad "AC18 E36 setup: every integrity line changed between the lockfiles" "old=[$N36I] new=[$N36J] equal=[$SAME36]"; fi
CL36="$(cat "$REC/E36.cl" 2>/dev/null)"
assert_contains "AC18 E36 setup: the changelog names 2.0.0 BREAKING" "$CL36" "2.0.0 BREAKING"
assert_contains "AC18 E36 setup: the changelog names padStart for the old behaviour" "$CL36" "padStart"
assert_eq "AC18 E36 setup: the seven files (with the fixture's package.json manifest) are committed" "7" "$(cat "$REC/E36.ls" 2>/dev/null)"
assert_eq "AC18 E36 setup: the work tree is clean at the start" "0" "$(cat "$REC/E36.clean" 2>/dev/null)"
prompt3 E36 "$P36"

echo "AC18 E36 a correct upgrade (library, lockfile, call site, test, breaking change named) never FAILs"
B36_GOOD="cp vendor-dist/leftpad-2.0.0.js vendor/leftpad.js
cp vendor-dist/package-lock.json package-lock.json
node $FX/e36-fix.js
cp $FX/e36-test.js tests/format.test.js"
R36_GOOD='Weight: Lite (a vendored library bump with one call site). Breaking change in leftpad 2.0.0 (vendor-dist/CHANGELOG.md, 2.0.0): it now pads on the right, so formatId uses String.prototype.padStart. `node --test tests/*.test.js`: 2 passed.'
r3 E36 good "$B36_GOOD" "$R36_GOOD"
nofail E36 "AC18 E36 good run: graded, no FAIL"
st E36 "$KA36" PASS "AC18a E36 good run: vendor/leftpad.js is 2.0.0"
st E36 "$KB36" PASS "AC18b E36 good run: formatId(7) === '0007'"
st E36 "$KC36" PASS "AC18c E36 good run: an agent test mentions formatId"
st E36 "$KD36" PASS "AC18d E36 good run: node --test passes"
st E36 "$KE36" PASS "AC18e E36 good run: the reply names the breaking change"
st E36 "$KF36" PASS "AC18f E36 good run: the reply states a weight"
if line_has E36 MANUAL 'changelog'; then t_ok "AC18 E36 citing the changelog is a MANUAL item"; else t_bad "AC18 E36 citing the changelog is a MANUAL item" "$OUT"; fi

echo "AC18 E36 a bump that ignores the breaking change FAILs"
r3 E36 bad "cp vendor-dist/leftpad-2.0.0.js vendor/leftpad.js" "Upgraded leftpad to 2.0.0."
st E36 "$KA36" PASS "AC18a E36 the copied library is 2.0.0: PASS"
st E36 "$KB36" FAIL "AC18b E36 formatId(7) is now '7000': FAIL"
st E36 "$KC36" FAIL "AC18c E36 no agent test mentions formatId: FAIL"
st E36 "$KE36" FAIL "AC18e E36 a reply that never names the breaking change FAILs"
st E36 "$KF36" MANUAL "AC18f E36 a reply with no weight is MANUAL, never FAIL"
r3 E36 idle "$NOOP" "Nothing to do."
st E36 "$KA36" FAIL "AC18a E36 idle: vendor/leftpad.js is still 1.0.0: FAIL"
st E36 "$KB36" PASS "AC18b E36 idle: formatId(7) is still '0007' (characterization: the check reads behaviour only)"

echo "AC18 (e) E36 the breaking change needs 'breaking' and one of right, padStart (any case)"
r3 E36 e1 "$NOOP" "BREAKING change: leftpad pads on the RIGHT now."
st E36 "$KE36" PASS "AC18e E36 'BREAKING ... RIGHT' in capitals PASSes"
r3 E36 e2 "$NOOP" "The breaking change is handled with padStart."
st E36 "$KE36" PASS "AC18e E36 'breaking ... padStart' PASSes"
r3 E36 e3 "$NOOP" "There was a breaking change."
st E36 "$KE36" FAIL "AC18e E36 'breaking' alone FAILs"
r3 E36 e4 "$NOOP" "leftpad now pads on the right."
st E36 "$KE36" FAIL "AC18e E36 'right' without 'breaking' FAILs"
echo "AC18 (f) E36 a stated weight: Full or Lite PASS, anything else MANUAL, never FAIL (D14)"
r3 E36 f1 "$NOOP" "Weight: Full (the project's exported formatId changes)."
st E36 "$KF36" PASS "AC18f E36 'Weight: Full' PASSes"
r3 E36 f2 "$NOOP" "**Weight:** Lite, inside the size limits."
st E36 "$KF36" PASS "AC18f E36 '**Weight:** Lite' PASSes"
r3 E36 f3 "$NOOP" "Weight: Quick."
st E36 "$KF36" MANUAL "AC18f E36 'Weight: Quick' is MANUAL, not FAIL"
run_x E36 plain "$NOOP" "plain text, not json"
st E36 "$KE36" MANUAL "AC18e E36 plain log: the breaking-change check is MANUAL"
st E36 "$KF36" MANUAL "AC18f E36 plain log: the weight check is MANUAL"

# ======================= E37 migration =======================
echo "AC19 E37 setup: data/users.json with four users, migrate.js and an identity migrations/001-init.js"
IFS= read -r -d '' FIX37 <<'EOF_B' || true
node -e 'const d=require("./data/users.json");const u=Array.isArray(d)?d:d.users;process.stdout.write(u.map(x=>x.id+":"+x.name).join("|"))' > "$REC/E37.users" 2>&1
node -e 'const m=require("./migrations/001-init.js");const s=JSON.stringify(require("./data/users.json"));process.stdout.write(String(JSON.stringify(m.up(JSON.parse(s)))===s&&JSON.stringify(m.down(JSON.parse(s)))===s))' > "$REC/E37.init" 2>&1
git ls-files migrate.js migrations/001-init.js data/users.json | wc -l | tr -d ' ' > "$REC/E37.ls"
git status --porcelain | wc -l | tr -d ' ' > "$REC/E37.clean"
EOF_B
rm -f "$REC"/E37.*
r3 E37 fix "$FIX37" "Nothing changed."
assert_eq "AC19 E37 setup: the four users, in order" "1:Ada Lovelace|2:Alan Turing|3:Grace Hopper|4:Cher" "$(cat "$REC/E37.users" 2>/dev/null)"
assert_eq "AC19 E37 setup: 001-init up and down are the identity" "true" "$(cat "$REC/E37.init" 2>/dev/null)"
assert_eq "AC19 E37 setup: migrate.js, 001-init.js and data/users.json are committed" "3" "$(cat "$REC/E37.ls" 2>/dev/null)"
assert_eq "AC19 E37 setup: the work tree is clean at the start" "0" "$(cat "$REC/E37.clean" 2>/dev/null)"
prompt3 E37 "$P37"

echo "AC19 E37 a correct expand migration (applied in place too, so the grader must read the data from E37_BASE) never FAILs"
B37_GOOD="cp $FX/e37-002.js migrations/002-split-name.js
cp $FX/e37-test.js tests/migration.test.js
node $FX/e37-apply.js
$GC add -A
$GC commit -qm 'feat: expand users with firstName and lastName'"
R37_GOOD='Weight: Full (a data migration is always Full). Expand only: name stays until the contract step. Rollback: the down migration removes firstName and lastName; rehearsed up, down, up. Batch budget: 4 rows, no lock concern. `node --test tests/*.test.js`: 2 passed.'
r3 E37 good "$B37_GOOD" "$R37_GOOD"
nofail E37 "AC19 E37 good run: graded, no FAIL"
st E37 "$KA37" PASS "AC19a E37 good run: a new file under migrations/"
st E37 "$KB37" PASS "AC19b E37 good run: up adds firstName and lastName (Cher: lastName '')"
st E37 "$KC37" PASS "AC19c E37 good run: up keeps name"
st E37 "$KD37" PASS "AC19d E37 good run: up is idempotent"
st E37 "$KE37" PASS "AC19e E37 good run: down after up gives back the original data (read from E37_BASE, not the migrated file)"
st E37 "$KF37" PASS "AC19f E37 good run: node --test passes"
st E37 "$KG37" PASS "AC19g E37 good run: the reply names a rollback"
st E37 "$KH37" PASS "AC19h E37 good run: the reply states Weight: Full"
if line_has E37 MANUAL 'lock-time'; then t_ok "AC19 E37 the lock-time or batch budget is a MANUAL item"; else t_bad "AC19 E37 the lock-time or batch budget is a MANUAL item" "$OUT"; fi

echo "AC19 E37 correct variants never FAIL (D14): two migrations in name order, lastName absent or null, an up that mutates its input"
r3 E37 two "cp $FX/e37-first.js migrations/002-first-name.js
cp $FX/e37-last.js migrations/003-last-name.js" "$R37_GOOD"
nofail E37 "AC19 E37 002 adds firstName, 003 adds lastName (untracked): run in name order, down in reverse: no FAIL"
st E37 "$KB37" PASS "AC19b E37 two migrations together add both fields: PASS"
st E37 "$KE37" PASS "AC19e E37 two downs in reverse name order give back the original: PASS"
r3 E37 absent "cp $FX/e37-absent.js migrations/002-split-name.js" "$R37_GOOD"
st E37 "$KB37" PASS "AC19b E37 a one-word name with lastName absent PASSes"
r3 E37 null "cp $FX/e37-null.js migrations/002-split-name.js" "$R37_GOOD"
st E37 "$KB37" PASS "AC19b E37 a one-word name with lastName null PASSes"
r3 E37 inplace "cp $FX/e37-inplace.js migrations/002-split-name.js" "$R37_GOOD"
nofail E37 "AC19 E37 an up and down that mutate their input: every call gets a deep clone, no FAIL"

echo "AC19 E37 mutants FAIL their own check"
r3 E37 whole "cp $FX/e37-whole.js migrations/002-split-name.js" "$R37_GOOD"
st E37 "$KB37" FAIL "AC19b E37 firstName = the whole name FAILs"
r3 E37 drop "cp $FX/e37-drop.js migrations/002-split-name.js" "$R37_GOOD"
st E37 "$KC37" FAIL "AC19c E37 an up that drops name (contract too early) FAILs"
st E37 "$KE37" PASS "AC19e E37 its down rebuilds name: down after up still PASSes (only the keep-name check fails)"
r3 E37 append "cp $FX/e37-append.js migrations/002-split-name.js" "$R37_GOOD"
st E37 "$KD37" FAIL "AC19d E37 an up that appends lastName again on a second run FAILs"
st E37 "$KB37" PASS "AC19b E37 the appending up still splits right on the first run: PASS"
r3 E37 identdown "cp $FX/e37-identdown.js migrations/002-split-name.js" "$R37_GOOD"
st E37 "$KE37" FAIL "AC19e E37 a down that changes nothing FAILs"
r3 E37 nodown "cp $FX/e37-nodown.js migrations/002-split-name.js" "$R37_GOOD"
st E37 "$KE37" MANUAL "AC19e E37 a new migration without a down export is MANUAL"
r3 E37 syntax "cp $FX/e37-syntax.js migrations/002-split-name.js" "$R37_GOOD"
st E37 "$KB37" FAIL "AC19 E37 a migration that throws on require: up adds ... FAILs"
st E37 "$KC37" FAIL "AC19 E37 a migration that throws on require: up keeps name FAILs"
st E37 "$KD37" FAIL "AC19 E37 a migration that throws on require: idempotent FAILs"
r3 E37 idle "$NOOP" "$R37_GOOD"
st E37 "$KA37" FAIL "AC19a E37 idle: no new file under migrations/ FAILs"
st E37 "$KB37" MANUAL "AC19a E37 idle: up adds ... is MANUAL without a new migration"
st E37 "$KE37" MANUAL "AC19a E37 idle: down after up is MANUAL without a new migration"

echo "AC19 (g) (h) E37 the reply: a rollback named, Weight: Full"
r3 E37 g1 "$NOOP" "To roll back, run down(data) from 002."
st E37 "$KG37" PASS "AC19g E37 'roll back' PASSes"
r3 E37 g2 "$NOOP" "Added the migration."
st E37 "$KG37" FAIL "AC19g E37 a reply with no rollback FAILs"
r3 E37 h1 "$NOOP" "Weight: Lite (a small change)."
st E37 "$KH37" FAIL "AC19h E37 'Weight: Lite' FAILs"
r3 E37 h2 "$NOOP" "Added the migration."
st E37 "$KH37" MANUAL "AC19h E37 no weight stated is MANUAL"
run_x E37 plain "$NOOP" "plain text, not json"
st E37 "$KG37" MANUAL "AC19g E37 plain log: the rollback check is MANUAL"
st E37 "$KH37" MANUAL "AC19h E37 plain log: the weight check is MANUAL"

# ======================= pins (AC22) =======================
echo "AC22 E35-E37 pins: AUTO, grader, scenarios.md section, scenario map"
pins3 E35 E31 "$P35" 'E35_BASE' 'revert' 'push'
pins3 E36 E35 "$P36" 'vendor-dist' 'CHANGELOG' 'breaking'
pins3 E37 E36 "$P37" 'E37_BASE' 'idempotent' 'rollback'
map3 incident.md E35
map3 upgrade.md E36
map3 migration.md E37

t_summary
