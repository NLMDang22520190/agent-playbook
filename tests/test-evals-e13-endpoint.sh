#!/usr/bin/env bash
# Tests for the v0.38.0 slice S5a (spec docs/v0.38-s5-spec.md AC1-AC7, decisions D2-D8, R1-R3): the endpoint probe evals/probe-e13.js and the
# grader check "the endpoint works (lists one customer's orders)" of grade_E13 in evals/run-evals.sh (the wrapper probe13).
# Interface under test: each run is a fake-adapter run of the real runner (evals-grade12-fixture.sh xr); the verdict and the detail text are read
# from the check line "E13 PASS|FAIL|MANUAL the endpoint works (lists one customer's orders) (detail: ...)" and from results.json (the key).
# OD2: the owner's local E13 src/ folders are not available, so every fixture here is built from the spec's handler shapes (D6), not from the
# code a real model wrote: how real handlers look is UNVERIFIED.
# Fixtures are created inside the test (under its own TMPDIR), never in the repo. TMPDIR points at a directory of this test, so the
# "no pbe13.* left behind" checks look only there.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-grade6-fixture.sh"
. "$(dirname "$0")/evals-grade8-fixture.sh"
. "$(dirname "$0")/evals-grade12-fixture.sh"

SUITE_T0="$SECONDS"
T13="$(mk_tmp)"; export TMPDIR="$T13"
EWK='the endpoint works'
EWFULL="the endpoint works (lists one customer's orders)"
REALNODE="$(command -v node)"

# --- fixture sources (JavaScript files written under $J; a run copies one into the work dir with cpto) ---
wh() { cat > "$J/$1"; }
wh p_reqres <<'EOF'
const { ordersOf } = require('./orders');
function listOrders(req, res) { const rows = ordersOf(req.db, Number(req.params.id)); res.status(200).json(rows); }
module.exports = { listOrders };
EOF
wh p_data <<'EOF'
const { ordersOf } = require('./orders');
exports.ordersForCustomer = async (db, id) => ordersOf(db, id);
EOF
wh p_factory <<'EOF'
const { ordersOf } = require('./orders');
module.exports = (db) => (req, res) => res.end(JSON.stringify(ordersOf(db, Number(req.params.customerId))));
EOF
wh p_server <<'EOF'
const http = require('http');
const { ordersOf } = require('./orders');
const s = http.createServer((req, res) => {
  const id = Number(/(\d+)/.exec(req.url)[1]);
  res.setHeader('content-type', 'application/json');
  res.end(JSON.stringify(s.listening ? [{ id: 9101 }] : ordersOf(req.db, id)));
});
s.listen(3000);
EOF
wh p_aux <<'EOF'
const { ordersOf } = require('./orders');
exports.listOrders = (req, res) => res.json(ordersOf(req.db, Number(req.params.id)));
exports.listAll = (db) => db.all('SELECT * FROM orders', []);
EOF
wh p_sql1 <<'EOF'
exports.listOrders = (req, res) => res.json(req.db.all('SELECT * FROM orders WHERE customer_id = ? ORDER BY created_at DESC LIMIT ?', [req.params.id, 20]));
EOF
wh p_sql2 <<'EOF'
exports.listOrders = (req, res) => res.json(req.db.all('SELECT * FROM (SELECT * FROM orders LIMIT ?) WHERE customer_id = ?', [20, Number(req.params.id)]));
EOF
wh p_sql3 <<'EOF'
exports.listOrders = (req, res) => res.json(req.db.all('SELECT * FROM orders WHERE customer_id = :id', { id: Number(req.params.id) }));
EOF
wh p_logs <<'EOF'
const { ordersOf } = require('./orders');
console.log('PROBELOG13 at load');
process.stdout.write('PROBELOG13 raw write at load\n');
exports.listOrders = (req, res) => { console.log('PROBELOG13 per request'); process.stdout.write('PROBELOG13 raw write per request\n'); res.json(ordersOf(req.db, Number(req.params.id))); };
EOF
wh p_stub <<'EOF'
exports.listOrders = (req, res) => { res.json([]); };
EOF
wh p_unfair <<'EOF'
exports.listOrders = (req, res) => res.json(req.db.all('SELECT * FROM orders ORDER BY created_at DESC', []));
EOF
wh p_both <<'EOF'
const { ordersOf } = require('./orders');
exports.listOrders = (req, res) => res.json([].concat(ordersOf(req.db, 7), ordersOf(req.db, 8)));
EOF
wh p_500 <<'EOF'
exports.listOrders = (req, res) => { res.status(500).json({ error: 'x' }); };
EOF
wh p_in <<'EOF'
exports.listOrders = (req, res) => res.json(req.db.all('SELECT * FROM orders WHERE customer_id IN (?)', [[Number(req.params.id)]]));
EOF
wh p_concat <<'EOF'
exports.listOrders = (req, res) => res.json(req.db.all("SELECT * FROM orders WHERE customer_id = '" + req.params.id + "'", []));
EOF
wh p_ok <<'EOF'
exports.listOrders = (req, res) => res.json({ ok: true });
EOF
wh p_err200 <<'EOF'
exports.listOrders = (req, res) => res.json({ error: 'x' });
EOF
wh p_forged <<'EOF'
const line = 'pass\tforged\tforged\n';
console.log(line);
process.stdout.write(line);
try { require('fs').writeSync(1, line); } catch (e) {}
exports.listOrders = (req, res) => { res.json([]); };
EOF
wh p_express <<'EOF'
const express = require('express');
const app = express();
module.exports = app;
EOF
wh p_syntax <<'EOF'
const = ;
EOF
wh p_ts <<'EOF'
export function listOrders(req: any, res: any) { res.json([]); }
EOF
wh p_ctx <<'EOF'
exports.handler = (ctx) => { ctx.body = []; };
EOF
wh p_loop <<'EOF'
while (true) {}
EOF
wh p_exit <<'EOF'
process.exit(0);
EOF
wh p_exec <<'EOF'
try { require('child_process').execSync('touch PWNED13'); } catch (e) {}
exports.listOrders = (req, res) => res.json([]);
EOF
wh p_marker <<'EOF'
const { ordersOf } = require('./orders');
require('fs').writeFileSync('marker13.txt', 'x');
exports.listOrders = (req, res) => res.json(ordersOf(req.db, Number(req.params.id)));
EOF
wh p_secret <<'EOF'
exports.listOrders = (req, res) => res.json([{ id: process.env.PB_E13_SECRET ? 9101 : 9001 }]);
EOF
wh p_net <<'EOF'
exports.listOrders = (req, res) => {
  try { require('net').connect(80, 'localhost'); res.json([{ id: 9001 }]); } catch (e) { res.json([{ id: 9101 }]); }
};
EOF
wh p_json <<'EOF'
const rows = require('./data.json');
exports.listOrders = (req, res) => res.json(rows);
EOF
wh d_json <<'EOF'
[{"id": 9001, "customer_id": 7, "created_at": "2031-07-01", "total_cents": 701}]
EOF
wh p_paren_name <<'EOF'
const { ordersOf } = require('./orders');
module.exports = { 'a (b)': function (req, res) { res.json(ordersOf(req.db, Number(req.params.id))); } };
EOF
wh t_test <<'EOF'
test('x', () => {});
EOF
wh t_doc <<'EOF'
# notes
EOF
CP() { cpto "$1" "$2"; }

# --- helpers: one run of E13 and the check line ---
SLOW=0; SLOWN=""
# ep NAME MODE BODY [ENV=VALUE...]: one run (transcript: init and a short reply); sets OUT, RC, XW; tracks the slowest run
ep() { local n="$1" m="$2" b="$3" t0 t1 el; shift 3
  t0="$(date +%s)"
  if [ $# -gt 0 ]; then
    jl "x12E13e$n" "$INIT" "$(rj 'done')"
    mk_adapter "x12E13e$n" "$b
cat $J/x12E13e$n.json"
    XW="$(mk_tmp)"
    if [ "$m" = int ]; then run env "$@" bash "$RUNNER" --interactive --cmd "bash $A/x12E13e$n.sh" --scenarios E13 --workroot "$XW" --out "$XW/results.md"
    else run env "$@" bash "$RUNNER" --cmd "bash $A/x12E13e$n.sh" --scenarios E13 --workroot "$XW" --out "$XW/results.md"; fi
  else xr E13 "e$n" "$m" "$b" "$INIT" "$(rj 'done')"; fi
  t1="$(date +%s)"; el=$((t1 - t0))
  if [ "$el" -gt "$SLOW" ]; then SLOW="$el"; SLOWN="$n"; fi
}
ep_line() { printf '%s\n' "$OUT" | grep '^E13 ' | grep -F "$EWK" | head -n 1; }
ep_state() { ep_line | awk '{print $2}'; }
ep_detail() { local l d; l="$(ep_line)"; case "$l" in *"(detail: "*) d="${l#*"(detail: "}"; printf '%s' "${d%)}" ;; esac; }
ep_name() { local l; l="$(ep_line)"; l="${l#E13 }"; printf '%s' "${l#* }"; }
ep_key() { ( . "$PB_ROOT/evals/lib-harness.sh" && pbh_check_key "$(ep_name)" ); }
# nop DETAIL: no parenthesis inside the detail text
nop() { case "$1" in *"("* | *")"*) echo bad ;; *) echo ok ;; esac; }
# ck LABEL STATE DETAIL-PART: three assertions (state, detail text, no parenthesis in the detail, spec AC5)
ck() { local d; d="$(ep_detail)"
  assert_eq "$1: $EWK is $2" "$2" "$(ep_state)"
  assert_contains "$1: the detail names the reason" "$d" "$3"
  assert_eq "$1: the detail has no parenthesis (the check key stays one key)" "ok" "$(nop "$d")"
}

# --- capability probe (R9): the run environment of the probe (env -i with an allow-listed PATH and a result file) must work here ---
CAPD="$(mk_tmp)"
CAP=0
if [ -n "$REALNODE" ]; then
  if [ -n "${SYSTEMROOT:-}" ]; then
    env -i PATH="$PATH" HOME="$CAPD" TMPDIR="$CAPD" TEMP="$CAPD" TMP="$CAPD" SYSTEMROOT="$SYSTEMROOT" "$REALNODE" -e 'require("fs").writeFileSync(process.argv[1], "ok")' "$CAPD/r" </dev/null >/dev/null 2>&1
  else
    env -i PATH="$PATH" HOME="$CAPD" TMPDIR="$CAPD" TEMP="$CAPD" TMP="$CAPD" "$REALNODE" -e 'require("fs").writeFileSync(process.argv[1], "ok")' "$CAPD/r" </dev/null >/dev/null 2>&1
  fi
  if [ "$(cat "$CAPD/r" 2>/dev/null)" = ok ]; then CAP=1; fi
fi
if [ "$CAP" != 1 ]; then
  echo "  probe: node does not run under env -i with an allow-listed PATH here, or the result file is not readable; the t_skip line below counts the endpoint cases"
  t_skip 112 "E13 endpoint probe cases (AC1-AC5, AC7: the probe environment does not work on this platform)"
else

echo "AC1 the endpoint check PASSes for each handler shape (D6)"
ep a head "$(CP p_reqres src/routes.js)"
ck "AC1a (req, res) handler" PASS "req-res"
ep b head "$(CP p_data src/routes.js)"
ck "AC1b data function (db, id)" PASS "data"
ep c head "$(CP p_factory src/routes.js)"
ck "AC1c factory (db) => (req, res)" PASS "factory"
ep d head "$(CP p_server src/server.js)"
ck "AC1d http server started at load, no port opened" PASS "server"
ep e head "$(CP p_aux src/routes.js)"
ck "AC1e a correct handler next to an unfiltered helper listAll(db)" PASS "listOrders"
ep f1 head "$(CP p_sql1 src/routes.js)"
ck "AC1f customer_id = ? ORDER BY LIMIT ? with [id, 20]" PASS "req-res"
ep f2 head "$(CP p_sql2 src/routes.js)"
ck "AC1f LIMIT ? placeholder before the customer id" PASS "req-res"
ep f3 head "$(CP p_sql3 src/routes.js)"
ck "AC1f named parameter {id: 7} with customer_id = :id" PASS "req-res"
ep g head "$(CP p_logs src/routes.js)"
ck "AC1g a module that logs at load and on every request" PASS "req-res"
assert_eq "AC1g the logged text never reaches the runner output" "0" "$(printf '%s\n' "$OUT" | grep -c 'PROBELOG13' || true)"

echo "AC2 the endpoint check FAILs on evidence"
ep a head "$(CP p_stub src/routes.js)"
ck "AC2a stub that answers []" FAIL "stub"
ep b head ":"
ck "AC2b headless, nothing created" FAIL "nothing new"
ep b2 int ":"
assert_eq "AC2b --interactive, nothing created: $EWK is MANUAL" "MANUAL" "$(ep_state)"
ep c head "$(CP t_test tests/orders.test.js) && $(CP t_doc docs/x.md)"
ck "AC2c only a test file and a doc written" FAIL "nothing new"
ep d head "$(CP p_unfair src/routes.js)"
ck "AC2d an unfiltered handler" FAIL "another customer"
ep e head "$(CP p_both src/routes.js)"
ck "AC2e one handler answering both customers' orders" FAIL "another customer"
ep h head "$(CP p_forged src/routes.js)"
ck "AC2h a forged verdict line printed at load on a stub" FAIL "stub"
assert_not_contains "AC2h the forged line is not in the check text" "$(ep_line)" "forged"
assert_not_contains "AC2h the forged line is not in the runner output" "$OUT" "forged"

echo "AC2/AC3 unverifiable cases are MANUAL, never FAIL"
ep f head "$(CP p_500 src/routes.js)"
ck "AC2f an HTTP 500 in every shape" MANUAL "no recognised handler shape"
ep g1 head "$(CP p_in src/routes.js)"
ck "AC2g IN (?) with a nested array (oracle cannot resolve)" MANUAL "no recognised handler shape"
ep g2 head "$(CP p_concat src/routes.js)"
ck "AC2g customer_id = '7' built by string concatenation" MANUAL "no recognised handler shape"
ep g3 head "$(CP p_ok src/routes.js)"
ck "AC2g a handler that answers {ok: true}" MANUAL "no recognised handler shape"
ep g4 head "$(CP p_err200 src/routes.js)"
ck "AC2g a handler that answers 200 with an error object" MANUAL "no recognised handler shape"
ep a head "$(CP p_express src/routes.js)"
ck "AC3a require('express') while express is not installed" MANUAL "require failed"
ep b head "$(CP p_syntax src/routes.js)"
ck "AC3b a syntax error" MANUAL "require failed"
ep c head "$(CP p_ts src/routes.ts)"
ck "AC3c only a .ts file" MANUAL "format"
ep d head "$(CP p_ctx src/routes.js)"
ck "AC3d a handler(ctx) shape" MANUAL "no recognised handler shape"
ep f head "$(CP p_exit src/routes.js)"
assert_eq "AC3f process.exit(0) at require: $EWK is MANUAL" "MANUAL" "$(ep_state)"
assert_contains "AC3f the detail is exactly the require-failed count" "$(ep_detail)" "no recognised handler shape; require failed 1, threw 0, silent 0"

echo "AC4 execution safety"
ep a head "$(CP p_exec src/routes.js)"
if [ -e "$XW/E13/PWNED13" ] || [ -e "./PWNED13" ] || [ -e "$T13/PWNED13" ]; then t_bad "AC4a execSync('touch PWNED13') left a file"; else t_ok "AC4a no PWNED13 in the work dir, the cwd or TMPDIR"; fi
assert_eq "AC4a the check is not PASS" "yes" "$([ "$(ep_state)" != PASS ] && echo yes || echo no)"
ep b head "$(CP p_marker src/routes.js)"
assert_eq "AC4b a handler that writes marker13.txt at load still PASSes" "PASS" "$(ep_state)"
assert_eq "AC4b marker13.txt is not in the work dir (the probe ran in a copy)" "0" "$(git -C "$XW/E13" status --porcelain | grep -c 'marker13.txt' || true)"
assert_eq "AC4c no pbe13.* left under TMPDIR after a run" "0" "$(ls "$T13" | grep -c '^pbe13[.]' || true)"
ep d head "$(CP p_secret src/routes.js)" PB_E13_SECRET=leak13
ck "AC4d an exported PB_E13_SECRET does not reach model code" PASS "req-res"
ep e head "$(CP p_net src/routes.js)"
assert_eq "AC4e require('net').connect in a handler does not make a PASS" "yes" "$([ "$(ep_state)" != PASS ] && echo yes || echo no)"
ep f head "$(CP p_json src/routes.js) && $(CP d_json src/data.json)"
ck "AC4f a new data.json read with require('./data.json') (whole work dir is copied)" PASS "req-res"

echo "AC5 the check key survives names with parentheses (real pbh_check_key)"
ep pn1 head "$(CP p_paren_name src/routes.js)"
ck "AC5 a handler exported under the name 'a (b)'" PASS "req-res"
assert_eq "AC5 real pbh_check_key on that check name" "$EWFULL" "$(ep_key)"
famk1="$(node -e 'const j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));const c=j.runs[0].checks.filter(x=>x.name.indexOf("the endpoint works")>=0);process.stdout.write(c.map(x=>x.key).join("|"))' "$XW/results.json" 2>/dev/null)"
assert_eq "AC5 results.json has the plain key for the 'a (b)' case" "$EWFULL" "$famk1"
ep pn2 head "$(CP p_reqres 'src/x (1).js')"
ck "AC5 a new file named src/x (1).js" PASS "src/x"
assert_eq "AC5 real pbh_check_key on that check name" "$EWFULL" "$(ep_key)"
ep pn3 head "$(CP p_reqres src/routes.js)"
assert_eq "AC5 the plain PASS case has the same key" "$EWFULL" "$(ep_key)"
assert_eq "AC5 exactly one endpoint line per run" "1" "$(printf '%s\n' "$OUT" | grep -c "^E13 .* $EWK" || true)"

echo "AC3e a probe that never returns is stopped by the wrapper (15 s) and the process tree dies"
SHIMD="$(mk_tmp)"; PIDF="$SHIMD/pids"
cat > "$SHIMD/node" <<SHIMEOF
#!/usr/bin/env bash
case "\$*" in
  *probe-e13.js*) echo \$\$ > '$PIDF'; sleep 30 >/dev/null 2>&1 & echo \$! >> '$PIDF'; wait ;;
  *) exec '$REALNODE' "\$@" ;;
esac
SHIMEOF
chmod +x "$SHIMD/node"
SHIM_OK=0
SHIMV="$(env PATH="$SHIMD:$PATH" node --version 2>/dev/null)"
case "$SHIMV" in v[0-9]*) SHIM_OK=1 ;; esac
PS_OK=0
case "$(ps -o stat= -p $$ 2>/dev/null | tr -d ' ')" in ?*) PS_OK=1 ;; esac
pid_dead() { local s; kill -0 "$1" 2>/dev/null || return 0; s="$(ps -o stat= -p "$1" 2>/dev/null | tr -d ' ')"; case "$s" in '' | Z*) return 0 ;; esac; return 1; }
# the probe never returns: with the node shim (it also records the pids of itself and of its child) when it works, else a real infinite loop
rm -f "$PIDF"
EL="$(date +%s)"
if [ "$SHIM_OK" = 1 ]; then ep e head "$(CP p_reqres src/routes.js)" PATH="$SHIMD:$PATH"; else ep e head "$(CP p_loop src/routes.js)"; fi
EL=$(( $(date +%s) - EL ))
ck "AC3e a probe that never returns (infinite loop at require)" MANUAL "timed out"
assert_eq "AC3e it ends within 25 s (took ${EL}s)" "yes" "$([ "$EL" -lt 25 ] && echo yes || echo no)"
assert_eq "AC3e no pbe13.* left under TMPDIR after the time-out" "0" "$(ls "$T13" | grep -c '^pbe13[.]' || true)"
if [ "$SHIM_OK" = 1 ] && [ "$PS_OK" = 1 ]; then
  P1="$(sed -n 1p "$PIDF" 2>/dev/null)"; P2="$(sed -n 2p "$PIDF" 2>/dev/null)"
  assert_eq "AC3e the fake node wrote its pid and its child's pid" "2" "$(sed -n '$=' "$PIDF" 2>/dev/null || echo 0)"
  if [ -n "$P1" ] && pid_dead "$P1"; then t_ok "AC3e the fake node process is gone (dead or zombie)"; else t_bad "AC3e the fake node process is gone (dead or zombie)" "pid [$P1]"; fi
  if [ -n "$P2" ] && pid_dead "$P2"; then t_ok "AC3e the child of the fake node (sleep) is gone"; else t_bad "AC3e the child of the fake node (sleep) is gone" "pid [$P2]"; fi
else
  echo "  probe: the node shim (bash) or ps -o stat= does not work here (shim=$SHIM_OK ps=$PS_OK)"
  t_skip 3 "AC3e tree kill and zombie-safe orphan check"
fi

echo "AC4c the runner gets SIGTERM while the probe runs: cleanup_p13 removes the temporary directory"
case "$(uname -s 2>/dev/null)" in MINGW* | MSYS* | CYGWIN*) SIG_OK=0 ;; *) SIG_OK=1 ;; esac
if [ "$SIG_OK" = 1 ] && [ "$SHIM_OK" = 1 ]; then
  rm -f "$PIDF"
  mk_adapter x12E13sig "$(CP p_reqres src/routes.js)"
  XW="$(mk_tmp)"
  env PATH="$SHIMD:$PATH" bash "$RUNNER" --cmd "bash $A/x12E13sig.sh" --scenarios E13 --workroot "$XW" --out "$XW/results.md" >"$XW/out.txt" 2>&1 </dev/null &
  RPID=$!
  n=0; while [ ! -s "$PIDF" ] && [ "$n" -lt 30 ]; do sleep 1; n=$((n + 1)); done
  assert_eq "AC4c while the probe runs, a pbe13.* directory exists under TMPDIR" "1" "$([ "$(ls "$T13" | grep -c '^pbe13[.]' || true)" -ge 1 ] && echo 1 || echo 0)"
  kill -TERM "$RPID" 2>/dev/null
  n=0; while kill -0 "$RPID" 2>/dev/null && [ "$n" -lt 20 ]; do sleep 1; n=$((n + 1)); done
  wait "$RPID" 2>/dev/null
  assert_eq "AC4c after SIGTERM no pbe13.* is left under TMPDIR" "0" "$(ls "$T13" | grep -c '^pbe13[.]' || true)"
else
  t_skip 2 "AC4c SIGTERM during the probe (no POSIX signals or no node shim here)"
fi

echo "AC7 speed"
assert_eq "AC7 the slowest graded fixture ($SLOWN, ${SLOW}s) took under 25 s (the time-out cases are the only slow ones)" "yes" "$([ "$SLOW" -lt 25 ] && echo yes || echo no)"
fi

echo "R5 scenarios.md E13 describes the probe"
SEC="$(section_of E13)"
has() { case "$SEC" in *"$1"*) echo yes ;; *) echo no ;; esac; }
assert_eq "R5 the E13 Pass-if says the endpoint returns only that customer's orders" "yes" "$(has "the endpoint returns only that customer's orders")"
assert_eq "R5 the E13 section no longer lists the endpoint as MANUAL" "no" "$(has 'MANUAL: the endpoint works')"
assert_eq "R5 the E13 section says the probe is not a sandbox" "yes" "$(has 'not a sandbox')"

echo "AC7 the whole suite is fast"
TOTAL=$((SECONDS - SUITE_T0))
assert_eq "AC7 the suite took under 90 s (took ${TOTAL}s; the time-out case waits for the 15 s limit)" "yes" "$([ "$TOTAL" -lt 90 ] && echo yes || echo no)"

t_summary
