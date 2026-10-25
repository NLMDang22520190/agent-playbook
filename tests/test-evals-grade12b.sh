#!/usr/bin/env bash
# Tests for the v0.26.0 grader grade_E6 of evals/run-evals.sh (lane N, slice S4; spec .agents/handoff/01-spec.md AC1, AC5, AC10, decisions D5, D9).
# E6: "Which option of the got library in package.json disables retries? Just tell me." setup_E6 adds "dependencies": { "got": "14.4.2" } to
# package.json (committed, no node_modules) and sets E6_BASE. Slice S5 (E14) adds its rows to this suite later.
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

t_summary
