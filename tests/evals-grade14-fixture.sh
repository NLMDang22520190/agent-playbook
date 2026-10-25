#!/usr/bin/env bash
# Shared setup of tests/test-evals-grade14.sh (E35 incident, E36 upgrade, E37 migration) and tests/test-evals-grade14b.sh (E38 debug,
# E39 squash), v0.26.3 lane W (spec .agents/handoff/01-spec.md AC17-AC22, decisions D10, D14, D15). Source it after lib.sh,
# evals-fixture.sh, evals-grade6-fixture.sh and evals-grade8-fixture.sh. It is not a suite: run-all.sh only starts tests/test-*.sh.
# Never calls a real harness: every run uses --cmd with a fake adapter that plays the agent and prints a stream-json transcript.
# The check keys are fixed phrases of the spec's check texts (found by e_state); the implementer must keep them in the check names.
KA35='divide(6,3) === 2'; KB35='first agent commit restores'; KC35='fails on the bad divide'; KD35='node --test'; KE35='no git push'
KF35='names a command or a count'
KA36='is version 2.0.0'; KB36="formatId(7) === '0007'"; KC36='mentions formatId'; KD36='node --test'; KE36='names the breaking change'
KF36='states a weight'
KA37='new file under migrations/'; KB37='up adds firstName and lastName'; KC37='up keeps name'; KD37='up is idempotent'
KE37='down after up'; KF37='node --test'; KG37='names a rollback'; KH37='Weight: Full'
KA38='qty: 0'; KB38='=== 4 (unchanged'; KC38='fails on the old cart.js'; KD38='fails on the naive fix'; KE38='node --test'
KF38='first agent commit changes no code'
KA39='multiply(3,4) === 12'; KB39='mentions multiply'; KC39='node --test'; KD39='every agent commit passes'; KE39='no test(red) commit'
# the prompts of the spec, verbatim
P35='Production incident: since the last deploy, invoices show wrong totals and customers are being charged wrong amounts. Restore service now, then fix it properly.'
P36='Upgrade the vendored leftpad library to 2.0.0. The new version and its changelog are in vendor-dist/; update package-lock.json from vendor-dist/package-lock.json too.'
P37="Split the users' name field into firstName and lastName with a migration. The app still reads name today."
P38='Fix the bug in docs/bug.md.'
P39='Add multiply(a, b) to src/calc.js and get the branch ready for review.'
SCEN3="$PB_ROOT/evals/scenarios.md"

# resj REPLY -> the stream-json result line carrying REPLY (JSON-escaped by node)
resj() { R3TXT="$1" node -e 'process.stdout.write(JSON.stringify({type:"result",subtype:"success",is_error:false,result:process.env.R3TXT}))'; }
# r3 E NAME BODY REPLY [TRANSCRIPT-LINE...]: one headless run of E whose fake agent runs BODY in the work dir and ends with REPLY; sets OUT, RC, XW
r3() { local e="$1" n="$2" b="$3" r="$4"; shift 4
  if [ $# -gt 0 ]; then run_x "$e" "$n" "$b" "$INIT" "$@" "$(resj "$r")"; else run_x "$e" "$n" "$b" "$INIT" "$(resj "$r")"; fi; }
# nofail E LABEL: the run was graded (at least one PASS) and no check of E FAILed (a correct agent never FAILs, D14)
nofail() { assert_eq "$2" "0/graded" "$(fail_graded "$1")"; }
# st E KEY EXPECT LABEL: the state of the check KEY of E
st() { assert_eq "$4" "$3" "$(e_state "$1" "$2")"; }
# sec3 E -> the "## E ..." section of evals/scenarios.md on one line
sec3() { awk -v h="## $1 " 'index($0, h) == 1 { f = 1; next } f && /^## / { exit } f { print }' "$SCEN3" | tr '\n' ' '; }
# pins3 E PREV PROMPT PATTERN...: the AC22 pins of one scenario: E is in AUTO, grade_E is defined, scenarios.md has a "## E" section
# after "## PREV" (appended) with the fields of the existing format, the spec prompt verbatim in double quotes, and each PATTERN (ERE, any case)
pins3() { local e="$1" prev="$2" p="$3" s k lp le auto; shift 3
  auto="$(sed -n 's/^AUTO="\(.*\)"$/\1/p' "$PB_ROOT/evals/run-evals.sh" | head -n 1)"
  case " $auto " in *" $e "*) t_ok "AC22 $e is in the AUTO list" ;; *) t_bad "AC22 $e is in the AUTO list" "AUTO: [$auto]" ;; esac
  if grep -qE "^grade_${e}\(\)" "$PB_ROOT/evals/run-evals.sh"; then t_ok "AC22 run-evals.sh defines grade_$e"
  else t_bad "AC22 run-evals.sh defines grade_$e" "no grade_$e() in evals/run-evals.sh"; fi
  lp="$(grep -n -m1 "^## $prev " "$SCEN3" | cut -d: -f1)"; le="$(grep -n -m1 "^## $e [A-Za-z]" "$SCEN3" | cut -d: -f1)"
  if [ -n "$lp" ] && [ -n "$le" ] && [ "$lp" -lt "$le" ]; then t_ok "AC22 scenarios.md has a ## $e section after ## $prev"
  else t_bad "AC22 scenarios.md has a ## $e section after ## $prev" "$prev=[$lp] $e=[$le]"; fi
  s="$(sec3 "$e")"
  for k in '\*\*Prompt:\*\*' '\*\*Pass if:\*\*' '\*\*Fail if:\*\*' 'Auto checks:' 'MANUAL' "$@"; do
    if printf '%s' "$s" | grep -qiE -- "$k"; then t_ok "AC22 the $e section has [$k]"; else t_bad "AC22 the $e section has [$k]" "not found in the ## $e section"; fi
  done
  assert_contains "AC22 the $e section holds the spec prompt verbatim in double quotes" "$s" "\"$p\""
}
# map3 FILE E: evals/scenario-map has the line "skills/playbook-tdd/references/FILE ..." naming E (AC22: one line per reference file)
map3() { local l
  l="$(grep -E "^skills/playbook-tdd/references/$1( |$)" "$PB_ROOT/evals/scenario-map" | head -n 1)"
  if printf '%s' "$l" | grep -qE "(^| )$2( |$)"; then t_ok "AC22 scenario-map maps references/$1 to $2"
  else t_bad "AC22 scenario-map maps references/$1 to $2" "line: [$l]"; fi; }
# prompt3 E PROMPT: the prompt the adapter received (written by the runner from scenarios.md) starts with the spec prompt
prompt3() { local got; got="$(head -n 1 "$REC/$1.prompt" 2>/dev/null)"
  assert_eq "AC22 the $1 adapter receives the spec prompt" "$2" "$got"; }

# ---- files the fake agents copy into their work dir (made-up samples; every name differs from its value) ----
FX="$(mk_tmp)"
# E35: the regression test, a test that cannot see the bug (2 * 1 === 2 / 1), a forward fix with new logic, a line for the old test file
cat > "$FX/e35-test.js" <<'EOF'
const test = require('node:test');
const assert = require('node:assert');
const { divide } = require('../src/calc');
test('divide(6, 3) is 2 (incident regression)', () => { assert.strictEqual(divide(6, 3), 2); });
EOF
cat > "$FX/e35-weak.js" <<'EOF'
const test = require('node:test');
const assert = require('node:assert');
const { divide } = require('../src/calc');
test('divide(2, 1) is 2', () => { assert.strictEqual(divide(2, 1), 2); });
EOF
cat > "$FX/e35-fwd.js" <<'EOF'
function add(a, b) {
  if (typeof a !== 'number' || typeof b !== 'number') throw new TypeError('add expects nubmers');
  return a + b;
}
function divide(a, b) { if (b === 0) return 0; return a / b; }
module.exports = { add, divide };
EOF
cat > "$FX/e35-append.js" <<'EOF'
test('divide(6, 3) is 2', () => { assert.strictEqual(require('../src/calc').divide(6, 3), 2); });
EOF
printf '# Incident\ndetected 10:00, mitigated 10:05 by revert\n' > "$FX/e35-note.md"
# E36: the call-site fix (padStart instead of leftpad) and the test of formatId
cat > "$FX/e36-fix.js" <<'EOF'
const fs = require('fs');
const f = 'src/format.js';
const s = fs.readFileSync(f, 'utf8');
const t = s.replace(/leftpad\(\s*String\(n\)\s*,\s*4\s*,\s*(['"])0\1\s*\)/, "String(n).padStart(4, '0')");
if (t === s) { console.error('e36-fix: the leftpad call was not found'); process.exit(1); }
fs.writeFileSync(f, t);
EOF
cat > "$FX/e36-test.js" <<'EOF'
const test = require('node:test');
const assert = require('node:assert');
const m = require('../src/format');
const formatId = m.formatId || m;
test('formatId pads on the left after the leftpad 2.0.0 upgrade', () => { assert.strictEqual(formatId(7), '0007'); });
EOF
# E37: migrations. each() keeps the container of data/users.json (an array, or an object with a users array)
E37_EACH='const each = (d, f) => (Array.isArray(d) ? d.map(f) : Object.assign({}, d, { users: d.users.map(f) }));'
E37_DOWN='exports.down = (d) => each(d, (u) => { const c = Object.assign({}, u); delete c.firstName; delete c.lastName; return c; });'
printf '%s\n%s\n%s\n' "$E37_EACH" \
  "exports.up = (d) => each(d, (u) => { const w = String(u.name).split(' '); return Object.assign({}, u, { firstName: w[0], lastName: w.slice(1).join(' ') }); });" \
  "$E37_DOWN" > "$FX/e37-002.js"
printf '%s\n%s\n%s\n' "$E37_EACH" \
  "exports.up = (d) => each(d, (u) => Object.assign({}, u, { firstName: String(u.name).split(' ')[0] }));" \
  "exports.down = (d) => each(d, (u) => { const c = Object.assign({}, u); delete c.firstName; return c; });" > "$FX/e37-first.js"
printf '%s\n%s\n%s\n' "$E37_EACH" \
  "exports.up = (d) => each(d, (u) => Object.assign({}, u, { lastName: String(u.name).split(' ').slice(1).join(' ') }));" \
  "exports.down = (d) => each(d, (u) => { const c = Object.assign({}, u); delete c.lastName; return c; });" > "$FX/e37-last.js"
printf '%s\n%s\n%s\n' "$E37_EACH" \
  "exports.up = (d) => each(d, (u) => { const w = String(u.name).split(' '); const o = Object.assign({}, u, { firstName: w[0] }); if (w.length > 1) o.lastName = w.slice(1).join(' '); return o; });" \
  "$E37_DOWN" > "$FX/e37-absent.js"
printf '%s\n%s\n%s\n' "$E37_EACH" \
  "exports.up = (d) => each(d, (u) => { const w = String(u.name).split(' '); return Object.assign({}, u, { firstName: w[0], lastName: w.length > 1 ? w.slice(1).join(' ') : null }); });" \
  "$E37_DOWN" > "$FX/e37-null.js"
cat > "$FX/e37-inplace.js" <<'EOF'
const list = (d) => (Array.isArray(d) ? d : d.users);
exports.up = (d) => { for (const u of list(d)) { const w = u.name.split(' '); u.firstName = w[0]; u.lastName = w.slice(1).join(' '); } return d; };
exports.down = (d) => { for (const u of list(d)) { delete u.firstName; delete u.lastName; } return d; };
EOF
# mutants: the whole name as firstName; name dropped (contract too early, down rebuilds it); lastName appended (not idempotent);
# a down that changes nothing; no down export; a file that does not load
printf '%s\n%s\n%s\n' "$E37_EACH" \
  "exports.up = (d) => each(d, (u) => Object.assign({}, u, { firstName: u.name, lastName: '' }));" "$E37_DOWN" > "$FX/e37-whole.js"
printf '%s\n%s\n%s\n' "$E37_EACH" \
  "exports.up = (d) => each(d, (u) => { const w = String(u.name).split(' '); return { id: u.id, firstName: w[0], lastName: w.slice(1).join(' ') }; });" \
  "exports.down = (d) => each(d, (u) => ({ id: u.id, name: [u.firstName, u.lastName].filter(Boolean).join(' ') }));" > "$FX/e37-drop.js"
printf '%s\n%s\n%s\n' "$E37_EACH" \
  "exports.up = (d) => each(d, (u) => { const w = String(u.name).split(' '); const r = w.slice(1).join(' '); return Object.assign({}, u, { firstName: w[0], lastName: (u.lastName ? u.lastName + ' ' : '') + r }); });" \
  "$E37_DOWN" > "$FX/e37-append.js"
printf '%s\n%s\n%s\n' "$E37_EACH" \
  "exports.up = (d) => each(d, (u) => { const w = String(u.name).split(' '); return Object.assign({}, u, { firstName: w[0], lastName: w.slice(1).join(' ') }); });" \
  "exports.down = (d) => d;" > "$FX/e37-identdown.js"
printf '%s\n%s\n' "$E37_EACH" \
  "exports.up = (d) => each(d, (u) => { const w = String(u.name).split(' '); return Object.assign({}, u, { firstName: w[0], lastName: w.slice(1).join(' ') }); });" > "$FX/e37-nodown.js"
printf '%s\n' 'exports.up = (d) => { return d.map((u) => ({ ...u, firstName: ' > "$FX/e37-syntax.js"
cat > "$FX/e37-test.js" <<'EOF'
const test = require('node:test');
const assert = require('node:assert');
const m = require('../migrations/002-split-name');
test('002 adds firstName and lastName and keeps name', () => {
  const out = m.up([{ id: 9, name: 'Edsger Wybe Dijkstra' }]);
  assert.strictEqual(out[0].firstName, 'Edsger');
  assert.strictEqual(out[0].lastName, 'Wybe Dijkstra');
  assert.strictEqual(out[0].name, 'Edsger Wybe Dijkstra');
});
EOF
cat > "$FX/e37-apply.js" <<'EOF'
const fs = require('fs');
const path = require('path');
const f = path.resolve('data/users.json');
const m = require(path.resolve('migrations/002-split-name.js'));
fs.writeFileSync(f, JSON.stringify(m.up(JSON.parse(fs.readFileSync(f, 'utf8'))), null, 2) + '\n');
EOF
# E38: the fix, the naive fix, a test of the bug and the unchanged behaviour, a test of the bug only, a row for the old test file
cat > "$FX/e38-fix.js" <<'EOF'
function total(items) { return items.reduce((s, i) => s + i.price * (i.qty === undefined ? 1 : i.qty), 0); }
module.exports = { total };
EOF
cat > "$FX/e38-naive.js" <<'EOF'
function total(items) { return items.reduce((s, i) => s + i.price * i.qty, 0); }
module.exports = { total };
EOF
cat > "$FX/e38-test-good.js" <<'EOF'
const test = require('node:test');
const assert = require('node:assert');
const { total } = require('../src/cart');
test('an item with qty 0 costs nothing', () => { assert.strictEqual(total([{ price: 5, qty: 0 }]), 0); });
test('unchanged: an item without qty counts once', () => { assert.strictEqual(total([{ price: 4 }]), 4); });
EOF
cat > "$FX/e38-test-qty0.js" <<'EOF'
const test = require('node:test');
const assert = require('node:assert');
const { total } = require('../src/cart');
test('an item with qty 0 costs nothing', () => { assert.strictEqual(total([{ price: 5, qty: 0 }]), 0); });
EOF
cat > "$FX/e38-append.js" <<'EOF'
test('an item with qty 0 costs nothing', () => { assert.strictEqual(require('../src/cart').total([{ price: 5, qty: 0 }]), 0); });
EOF
printf '# Spec: qty 0\nCurrent: an item with qty 0 is charged once. Expected: 0. Unchanged: an item without qty counts once.\n' > "$FX/e38-spec.md"
# E39: multiply and its test
printf '%s\n' 'function multiply(a, b) { return a * b; }' 'module.exports.multiply = multiply;' > "$FX/e39-impl.js"
printf '%s\n' 'module.exports.multiply = function () { throw new Error("broken"); };' > "$FX/e39-break.js"
cat > "$FX/e39-test.js" <<'EOF'
const test = require('node:test');
const assert = require('node:assert');
const { multiply } = require('../src/calc');
test('multiply(3, 4) is 12', () => { assert.strictEqual(multiply(3, 4), 12); });
EOF
