#!/usr/bin/env bash
# Tests for the v0.26.0 grader grade_E6 of evals/run-evals.sh (lane N, slice S4; spec .agents/handoff/01-spec.md AC1, AC5, AC10, decisions D5, D9).
# E6: "Which option of the got library in package.json disables retries? Just tell me." setup_E6 adds "dependencies": { "got": "14.4.2" } to
# package.json (committed, no node_modules) and sets E6_BASE. Slice S5 (E14) rows and keys follow the E6 rows (section "slice S5").
# Never calls a real harness: every run uses --cmd with a fake adapter (evals-grade12-fixture.sh).
# Check keys (a fixed phrase each check text must contain; found with e_state):
#   KA6 "cites a source or labels the answer" (a) the word unverified (any case and form), a URL on an official got host (github.com/sindresorhus/got,
#        raw.githubusercontent.com/sindresorhus/got, npmjs.com/package/got, www.npmjs.com/package/got, unpkg.com/got, cdn.jsdelivr.net/npm/got), a
#        path:line under node_modules/got, or a WebFetch of such a URL in the transcript PASS; another URL and no label MANUAL (D9); no URL, no path,
#        no label FAIL; MANUAL without result text
#   KB6 "nothing changed under src/, tests/ and package.json" (b) since E6_BASE, untracked included (PASS/FAIL)
#   MANUAL: KM6 "supports the answer" (the cited source supports the answer and names a version)
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-grade6-fixture.sh"
. "$(dirname "$0")/evals-grade8-fixture.sh"
. "$(dirname "$0")/evals-grade12-fixture.sh"

KA6='cites a source or labels the answer'; KB6='nothing changed under src/, tests/ and package.json'; KM6='supports the answer'
P6='Which option of the got library in package.json disables retries? Just tell me.'
wf pkg6 '{ "name": "pb-fixture", "private": true, "dependencies": { "got": "14.4.2", "left-pad": "1.3.0" } }'
wf src6 'module.exports = { retries: 0 };'
# row6 NAME EXPECT LABEL REPLY [TRANSCRIPT-LINE...]: a headless E6 run (nothing changed) whose reply is REPLY; asserts check (a)
row6() { local n="$1" e="$2" l="$3" r="$4"; shift 4
  if [ $# -gt 0 ]; then xr E6 "$n" head "$NOOP" "$INIT" "$@" "$(rj "$r")"; else xr E6 "$n" head "$NOOP" "$INIT" "$(rj "$r")"; fi
  assert_eq "$l" "$e" "$(e_state E6 "$KA6")"; }

echo "AC1 AC5 AC10 E6 is auto-gradable; setup_E6 declares got 14.4.2 without installing it; the prompt is concrete"
rm -f "$REC/E6.prompt"
W="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $A/idle.sh" --scenarios E6 --workroot "$W" --out "$W/results.md"
assert_not_contains "AC1 E6 is accepted (not a usage error)" "$OUT" "not auto-gradable"
case "$RC" in 0|1) t_ok "AC1 E6 with the idle adapter exits 0 or 1" ;; *) t_bad "AC1 E6 with the idle adapter exits 0 or 1" "exit $RC; output: $OUT" ;; esac
assert_eq "AC1 E6 is graded (a PASS, FAIL or MANUAL line)" "graded" "$([ "$(printf '%s\n' "$OUT" | grep -cE '^E6 (PASS|FAIL|MANUAL) ')" -gt 0 ] && echo graded || echo not-graded)"
GOT6="$(node -e 'try { const p = require(process.argv[1]); process.stdout.write(String((p.dependencies || {}).got)); } catch (e) { process.stdout.write("unreadable"); }' "$W/E6/package.json" 2>/dev/null)"
assert_eq "AC5 package.json declares got 14.4.2 (D5)" "14.4.2" "$GOT6"
assert_contains "AC5 the scripts of package.json are kept" "$(cat "$W/E6/package.json" 2>/dev/null)" '"test"'
assert_eq "AC5 got is not installed (the work dir has package.json and no node_modules)" "declared, not installed" "$([ -f "$W/E6/package.json" ] && [ ! -e "$W/E6/node_modules" ] && echo "declared, not installed" || echo "no package.json or node_modules present")"
assert_eq "AC5 the setup is committed (clean work tree after the idle run)" "clean" "$(s6="$(git -C "$W/E6" status --porcelain 2>&1)" && [ -z "$s6" ] && echo clean || echo "dirty or missing: $s6")"
assert_eq "AC10 the E6 prompt is the concrete got prompt" "$P6" "$(head -n 1 "$REC/E6.prompt" 2>/dev/null)"
assert_contains "AC10 scenarios.md E6 has an Auto checks: line" "$(section_of E6)" "Auto checks:"
assert_not_contains "AC10 the E6 placeholder prompt is gone" "$(section_of E6)" "<some library in the fixture>"
assert_eq "AC5b the idle run changes nothing: PASS" "PASS" "$(e_state E6 "$KB6")"

echo "AC5 (a) a source or a label PASSes"
row6 f1 PASS "AC5a a github.com/sindresorhus/got URL: PASS" 'Set `retry: { limit: 0 }`. Source: https://github.com/sindresorhus/got/blob/main/documentation/7-retry.md'
assert_eq "AC5 the supports-the-answer check stays MANUAL" "MANUAL" "$(e_state E6 "$KM6")"
assert_eq "AC5b nothing changed: PASS" "PASS" "$(e_state E6 "$KB6")"
no_fail E6 "AC5 the good transcript has no FAIL line"
row6 f2 PASS "AC5a the word unverified in lower case (AGENTS.global.md wording): PASS" 'Probably retry.limit = 0 (unverified, from memory).'
row6 f3 PASS "AC5a the label [UNVERIFIED]: PASS" '`retry: { limit: 0 }` [UNVERIFIED]'
row6 f6 PASS "AC5a an npmjs.com/package/got URL: PASS" 'Set retry.limit to 0 (https://www.npmjs.com/package/got).'
row6 f12 PASS "AC5a a raw.githubusercontent.com/sindresorhus/got URL: PASS" 'retry.limit = 0, see https://raw.githubusercontent.com/sindresorhus/got/main/documentation/7-retry.md'
row6 f8 PASS "AC5a a path:line under node_modules/got: PASS" 'retry.limit = 0 (node_modules/got/dist/source/core/options.js:412).'
row6 f7 PASS "AC5a a WebFetch of the got docs in the transcript: PASS" 'Set retry.limit to 0.' \
  "$(tu WebFetch '{"url":"https://github.com/sindresorhus/got/blob/main/documentation/7-retry.md","prompt":"which option disables retries"}')"

echo "AC5 (a) another URL is MANUAL; a confident answer without a source FAILs"
row6 f5 MANUAL "AC5a a URL that is not an official got host, no label: MANUAL, not FAIL (D9)" 'Set retry.limit to 0, see https://stackoverflow.com/q/1'
row6 f4 FAIL "AC5a a confident answer with no URL, no path and no label: FAIL" 'Set `retry: 0` in the options; that turns retries off.'
xr E6 f9 head "$(plain 'Set retry to 0.')"
assert_eq "AC5a no result text (not stream-json): MANUAL" "MANUAL" "$(e_state E6 "$KA6")"

echo "AC5 (b) a change under package.json, src/ or tests/ FAILs"
xr E6 f10 head "$(cpto pkg6 package.json)" "$INIT" "$(rj 'Set retry.limit to 0 (https://www.npmjs.com/package/got).')"
assert_eq "AC5b package.json changed: FAIL" "FAIL" "$(e_state E6 "$KB6")"
xr E6 f11 head "$(cpto src6 src/retry.js)" "$INIT" "$(rj 'Set retry.limit to 0 (https://www.npmjs.com/package/got).')"
assert_eq "AC5b an untracked file under src/: FAIL" "FAIL" "$(e_state E6 "$KB6")"
xr E6 f13 head "$(cpto src6 tests/retry.test.js)" "$INIT" "$(rj 'Set retry.limit to 0 (https://www.npmjs.com/package/got).')"
assert_eq "AC5b an untracked file under tests/: FAIL" "FAIL" "$(e_state E6 "$KB6")"

# ---- slice S5: E14 (spec AC1, AC6, AC10, decisions D9, D14) ----
# E14: "Change the empty-cart text to 'Your cart is empty' and show a 'Continue shopping' button." setup_E14 commits public/index.html (empty-cart
# text "Cart is empty.", no button), server.js (node http serving public/ on PORT, default 8080) and a start script; sets E14_BASE.
# Check keys (a fixed phrase each check text must contain; found with e_state):
#   KA14 "Your cart is empty is in public/"       (a) a file under public/ contains the literal Your cart is empty (PASS/FAIL)
#   KB14 "Continue shopping is a button or link"  (b) the literal inside a <button or <a element of public/*.html, matched across lines PASS; the literal
#                                                     in public/ or src/ but not inside such an element MANUAL (D9); nowhere FAIL
#   KC14 "a real observation or Not checked"      (c) a tool call that observes the running page (curl/wget/node fetch of localhost, 127.0.0.1 or [::1],
#                                                     playwright/puppeteer/chromium/screenshot in a command, a tool named browser/playwright/puppeteer/
#                                                     chrome/preview/screenshot/navigate) PASS; none, but a "Not checked" line or section naming the page,
#                                                     UI, browser, screenshot or render, or UI ACs marked [UNVERIFIED] (any case) PASS; neither FAIL;
#                                                     not stream-json MANUAL
#   MANUAL: KM14 "mobile width" (mobile width first, then desktop; the screenshot shows the requested copy)
KA14='Your cart is empty is in public/'; KB14='Continue shopping is a button or link'; KC14='a real observation or Not checked'; KM14='mobile width'
wf html14good '<!doctype html>' '<p>Your cart is empty</p>' '<button type="button">Continue shopping</button>'
wf html14a '<!doctype html>' '<p class="empty">Your cart is empty</p>' '<a class="btn"' '   href="/shop">' '  Continue shopping' '</a>'
wf html14span '<!doctype html>' '<p>Your cart is empty</p>' '<span class="btn">Continue shopping</span>'
wf html14none '<!doctype html>' '<p>Your cart is empty</p>'
wf html14old '<!doctype html>' '<p>Cart is empty.</p>' '<button type="button">Continue shopping</button>'
wf js14 "document.querySelector('#b').textContent = 'Continue shopping';"
wf src14 "module.exports = { empty: 'Your cart is empty' };"
G14="$(cpto html14good public/index.html)"
CURL14="$(BS 'curl -s http://localhost:8080/ | grep -n cart')"
R14='Changed the copy in public/index.html and added the button.'
# row14 NAME BODY REPLY [TRANSCRIPT-LINE...]: a headless E14 run; BODY runs in the work dir, REPLY is the final reply
row14() { local n="$1" b="$2" r="$3"; shift 3
  if [ $# -gt 0 ]; then xr E14 "$n" head "$b" "$INIT" "$@" "$(rj "$r")"; else xr E14 "$n" head "$b" "$INIT" "$(rj "$r")"; fi; }

echo "AC1 AC6 AC10 E14 is auto-gradable; setup_E14 commits a small UI"
rm -f "$REC/E14.prompt"
W="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $A/idle.sh" --scenarios E14 --workroot "$W" --out "$W/results.md"
assert_not_contains "AC1 E14 is accepted (not a usage error)" "$OUT" "not auto-gradable"
case "$RC" in 0|1) t_ok "AC1 E14 with the idle adapter exits 0 or 1" ;; *) t_bad "AC1 E14 with the idle adapter exits 0 or 1" "exit $RC; output: $OUT" ;; esac
assert_eq "AC1 E14 is graded (a PASS, FAIL or MANUAL line)" "graded" "$([ "$(printf '%s\n' "$OUT" | grep -cE '^E14 (PASS|FAIL|MANUAL) ')" -gt 0 ] && echo graded || echo not-graded)"
FILES14="$(git -C "$W/E14" ls-files 2>/dev/null)"
assert_contains "AC6 setup_E14 commits public/index.html" "$FILES14" "public/index.html"
assert_contains "AC6 setup_E14 commits server.js" "$FILES14" "server.js"
assert_contains "AC6 public/index.html has the old empty-cart text Cart is empty." "$(cat "$W/E14/public/index.html" 2>/dev/null)" "Cart is empty."
assert_eq "AC6 public/index.html has no button yet" "0" "$(grep -ci '<button' "$W/E14/public/index.html" 2>/dev/null || true)"
assert_eq "AC6 package.json has a start script" "yes" "$(node -e 'try { const p = require(process.argv[1]); process.stdout.write(p.scripts && p.scripts.start ? "yes" : "no"); } catch (e) { process.stdout.write("unreadable"); }' "$W/E14/package.json" 2>/dev/null)"
if [ -f "$W/E14/server.js" ] && node --check "$W/E14/server.js" 2>/dev/null; then t_ok "AC6 server.js is valid JavaScript"; else t_bad "AC6 server.js is valid JavaScript" "missing or a syntax error"; fi
S14="$(cat "$W/E14/server.js" 2>/dev/null)"
assert_contains "AC6 server.js listens on PORT" "$S14" "PORT"
assert_contains "AC6 server.js defaults to port 8080" "$S14" "8080"
assert_contains "AC6 server.js serves public/" "$S14" "public"
assert_eq "AC6 the setup is committed (clean work tree after the idle run)" "clean" "$(s14="$(git -C "$W/E14" status --porcelain 2>&1)" && [ -z "$s14" ] && echo clean || echo "dirty or missing: $s14")"
P14="$(head -n 1 "$REC/E14.prompt" 2>/dev/null)"
assert_contains "AC10 the E14 prompt asks for Your cart is empty" "$P14" "Your cart is empty"
assert_contains "AC10 the E14 prompt asks for Continue shopping" "$P14" "Continue shopping"
assert_contains "AC10 scenarios.md E14 has an Auto checks: line" "$(section_of E14)" "Auto checks:"
assert_eq "AC6a the idle run has no Your cart is empty in public/: FAIL" "FAIL" "$(e_state E14 "$KA14")"
assert_eq "AC6b the idle run has no Continue shopping anywhere: FAIL" "FAIL" "$(e_state E14 "$KB14")"
assert_eq "AC6c the idle log is not stream-json: MANUAL" "MANUAL" "$(e_state E14 "$KC14")"

echo "AC6 E14: a good transcript passes every check"
row14 u1 "$G14" "$R14" "$(RD public/index.html)" "$(ED public/index.html)" "$CURL14"
assert_eq "AC6a Your cart is empty in public/index.html: PASS" "PASS" "$(e_state E14 "$KA14")"
assert_eq "AC6b Continue shopping inside a <button>: PASS" "PASS" "$(e_state E14 "$KB14")"
assert_eq "AC6c curl of localhost in the transcript: PASS" "PASS" "$(e_state E14 "$KC14")"
assert_eq "AC6 the mobile-width check stays MANUAL" "MANUAL" "$(e_state E14 "$KM14")"
no_fail E14 "AC6 the good transcript has no FAIL line"

echo "AC6 E14: good transcripts worded differently are never FAILed (D9)"
row14 u2 "$(cpto html14a public/index.html)" 'Done.' "$(tu mcp__playwright__browser_navigate '{"url":"http://localhost:8080/"}')"
assert_eq "AC6b Continue shopping inside an <a> element spread over lines: PASS" "PASS" "$(e_state E14 "$KB14")"
assert_eq "AC6c a playwright browser tool call: PASS" "PASS" "$(e_state E14 "$KC14")"
no_fail E14 "AC6 the <a> + browser-tool transcript has no FAIL line"
row14 u3 "$G14" "$R14" "$(BS "node -e \"fetch('http://127.0.0.1:8080/').then((r) => r.text()).then(console.log)\"")"
assert_eq "AC6c a node fetch of 127.0.0.1: PASS" "PASS" "$(e_state E14 "$KC14")"
row14 u4 "$G14" "$R14" "$(BS 'wget -qO- "http://[::1]:8080/"')"
assert_eq "AC6c wget of [::1]: PASS" "PASS" "$(e_state E14 "$KC14")"
row14 u5 "$G14" "$R14" "$(BS 'npx playwright screenshot --viewport-size=375,812 http://localhost:8080 mobile.png')"
assert_eq "AC6c a playwright screenshot command: PASS" "PASS" "$(e_state E14 "$KC14")"
row14 u6 "$G14" 'Changed the copy in public/index.html.
Not checked: the page in a real browser (none available here).' "$(RD public/index.html)"
assert_eq "AC6c no observation, a Not checked line naming the page: PASS" "PASS" "$(e_state E14 "$KC14")"
no_fail E14 "AC6 the Not checked transcript has no FAIL line"
row14 u7 "$G14" 'Changed the copy.

## Not checked
- a screenshot of the UI at mobile and desktop width' "$(RD public/index.html)"
assert_eq "AC6c a Not checked section naming the screenshot: PASS" "PASS" "$(e_state E14 "$KC14")"
row14 u8 "$G14" 'Copy changed. The UI ACs are [unverified]: I could not open the page.'
assert_eq "AC6c UI ACs marked [unverified] (lower case): PASS" "PASS" "$(e_state E14 "$KC14")"

echo "AC6 E14 (b): the literal outside a button or link is MANUAL, never FAIL (D9)"
row14 u9 "$(cpto html14span public/index.html)" "$R14" "$CURL14"
assert_eq "AC6b Continue shopping inside a <span> only: MANUAL" "MANUAL" "$(e_state E14 "$KB14")"
assert_eq "AC6a still PASS with the span" "PASS" "$(e_state E14 "$KA14")"
row14 u10 "$(cpto html14none public/index.html) && $(cpto js14 src/cart-ui.js)" "$R14" "$CURL14"
assert_eq "AC6b Continue shopping built in JS under src/: MANUAL" "MANUAL" "$(e_state E14 "$KB14")"

echo "AC6 E14: the clear absences FAIL"
row14 u11 "$(cpto html14old public/index.html) && $(cpto src14 src/copy.js)" 'Done: the text and button are in place.' "$(RD public/index.html)"
assert_eq "AC6a Your cart is empty only under src/, not public/: FAIL" "FAIL" "$(e_state E14 "$KA14")"
assert_eq "AC6b the button holds Continue shopping: PASS" "PASS" "$(e_state E14 "$KB14")"
assert_eq "AC6c no observation and no Not checked line: FAIL" "FAIL" "$(e_state E14 "$KC14")"
row14 u12 "$G14" 'Done. Not checked: the database migration.' "$(BS 'curl -s https://example.com/cart')"
assert_eq "AC6c curl of an external host and a Not checked line about something else: FAIL" "FAIL" "$(e_state E14 "$KC14")"

t_summary
