#!/usr/bin/env bash
# Tests for the v0.22.0 eval E21 ("the whole request is found before editing") of evals/run-evals.sh and
# evals/transcript.js (spec AC5.1, AC5.2):
#   Setup: the runner commits src/report.js, a second call site of divide, on top of the fixture; the prompt is
#   "Rename the function divide to safeDivide." Auto-graded; --scenarios E21 is accepted; the default list is unchanged.
# Never calls a real harness: every run uses --cmd with fake adapters (see evals-fixture.sh). Check lines are found by a
# keyword of their text (e_state); the implementer must use these exact check texts:
#   E21  "every call site is renamed" (key: every call site)
#        "node --test tests/*.test.js passes" (key: node --test)
#        "the spec has an Understanding section" (key: Understanding section)
#        "the spec names report.js" (key: names report.js)
#        "the spec is written before the first src/ edit" (key: written before the first src)
# Meaning of the checks:
#   every call site: no word `divide` is left in src/*.js (safeDivide does not count) and src/report.js calls safeDivide.
#   the spec checks read .agents/handoff/01-spec.md of the workdir: it contains "## Understanding" / it mentions report.js.
#   spec first: transcript.js prints a new key spec_first=1|0|na: 1 when a Write or Edit of a path ending
#   .agents/handoff/01-spec.md comes before the first Write or Edit of a path under src/, 0 when it comes after or
#   never (with an src edit), na when the log is not stream-json. MANUAL (not FAIL) when spec_first is na.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"

# run_x E NAME BODY TRANSCRIPT-LINES... -> runs scenario E with an adapter that runs BODY, then prints the lines
# (BODY runs in the workdir; $REC/<E>.* files are overwritten by every run of the same E); sets OUT, RC, XW
run_x() { local e="$1" n="$2" body="$3"; shift 3
  jl "x$e$n" "$@"
  mk_adapter "$e$n" "$body
cat $J/x$e$n.json"
  XW="$(mk_tmp)"
  run bash "$RUNNER" --cmd "bash $A/$e$n.sh" --scenarios "$e" --workroot "$XW" --out "$XW/results.md"; }
res() { printf '%s"%s"}' "$RES_PRE" "$1"; }   # a stream-json result line with that reply
tu() { printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u1","name":"%s","input":%s}]}}' "$1" "$2"; }

K_SITES='every call site'; K_NODE='node --test'; K_UND='Understanding section'; K_REP='names report.js'; K_FIRST='written before the first src'
WSPEC="$(tu Write '{"file_path":"/work/E21/.agents/handoff/01-spec.md","content":"# Spec"}')"
ESPEC="$(tu Edit '{"file_path":"/work/E21/.agents/handoff/01-spec.md","old_string":"a","new_string":"b"}')"
ECALC="$(tu Edit '{"file_path":"/work/E21/src/calc.js","old_string":"divide","new_string":"safeDivide"}')"
EREP="$(tu Edit '{"file_path":"/work/E21/src/report.js","old_string":"divide","new_string":"safeDivide"}')"
RES21="$(res 'Renamed divide to safeDivide in calc.js and report.js; tests pass.')"

# adapter bodies (they run in the workdir)
E21_SEE='{ [ -f src/report.js ] && echo report-present
  grep -qw divide src/report.js && echo report-calls-divide
  grep -qw divide src/calc.js && echo calc-has-divide
  echo "tracked=$(git ls-files src/report.js)"
  echo "dirty=$(git status --porcelain | wc -l | tr -d " ")"
  echo "commits=$(git rev-list --count HEAD)"
  true; } > "$REC/E21.fix"'
SPEC_OK='mkdir -p .agents/handoff
printf "# Spec\n\n## Understanding\nRename divide to safeDivide in src/calc.js and at its call site in src/report.js (grep -rn divide src: 3 hits).\n" > .agents/handoff/01-spec.md'
SPEC_NO_UND='mkdir -p .agents/handoff
printf "# Spec\n\nRename divide to safeDivide in src/calc.js and in src/report.js.\n" > .agents/handoff/01-spec.md'
SPEC_NO_REP='mkdir -p .agents/handoff
printf "# Spec\n\n## Understanding\nRename divide to safeDivide in src/calc.js.\n" > .agents/handoff/01-spec.md'
REN_ALL='node -e "const fs=require(\"fs\");for(const f of process.argv.slice(1)){fs.writeFileSync(f,fs.readFileSync(f,\"utf8\").replace(/\\bdivide\\b/g,\"safeDivide\"))}" src/calc.js src/report.js'
REN_CALC='node -e "const fs=require(\"fs\");for(const f of process.argv.slice(1)){fs.writeFileSync(f,fs.readFileSync(f,\"utf8\").replace(/\\bdivide\\b/g,\"safeDivide\"))}" src/calc.js'
REN_REP='node -e "const fs=require(\"fs\");for(const f of process.argv.slice(1)){fs.writeFileSync(f,fs.readFileSync(f,\"utf8\").replace(/\\bdivide\\b/g,\"safeDivide\"))}" src/report.js'
GOOD21="$E21_SEE
$SPEC_OK
$REN_ALL"

echo "v0.22.0 AC5.1 E21 good run and its fixture"
run_x E21 good "$GOOD21" "$INIT" "$WSPEC" "$ECALC" "$EREP" "$RES21"
assert_eq "AC5.2 E21 good run: every call site is renamed PASS" "PASS" "$(e_state E21 "$K_SITES")"
assert_eq "AC5.2 E21 good run: node --test tests/*.test.js passes PASS" "PASS" "$(e_state E21 "$K_NODE")"
assert_eq "AC5.2 E21 good run: the spec has an Understanding section PASS" "PASS" "$(e_state E21 "$K_UND")"
assert_eq "AC5.2 E21 good run: the spec names report.js PASS" "PASS" "$(e_state E21 "$K_REP")"
assert_eq "AC5.2 E21 good run: the spec is written before the first src/ edit PASS" "PASS" "$(e_state E21 "$K_FIRST")"
assert_eq "AC5.2 E21 good run has no FAIL line" "0" "$(count_lines E21 FAIL)"
assert_eq "AC5.2 E21 good run has no ERROR line" "0" "$(count_err)"
assert_rc "AC5.2 E21 good run: exit 0" 0
assert_contains "AC5.2 E21 good run: nothing written outside the workdir PASS" "$OUT" "E21 PASS nothing written outside the workdir"
assert_contains "AC5.1 E21 the fixture has src/report.js" "$(cat "$REC/E21.fix" 2>/dev/null)" "report-present"
assert_contains "AC5.1 E21 src/report.js calls divide (the second call site)" "$(cat "$REC/E21.fix" 2>/dev/null)" "report-calls-divide"
assert_contains "AC5.1 E21 src/calc.js defines divide when the adapter starts" "$(cat "$REC/E21.fix" 2>/dev/null)" "calc-has-divide"
assert_contains "AC5.1 E21 src/report.js is committed (tracked)" "$(cat "$REC/E21.fix" 2>/dev/null)" "tracked=src/report.js"
assert_contains "AC5.1 E21 the tree is clean when the adapter starts" "$(cat "$REC/E21.fix" 2>/dev/null)" "dirty=0"
assert_eq "AC5.1 E21 report.js is its own commit on top of the fixture (2 commits)" "commits=2" "$(grep '^commits=' "$REC/E21.fix" 2>/dev/null)"
E21_P="$(cat "$REC/E21.prompt" 2>/dev/null)"
assert_contains "AC5.1 E21 the prompt is the rename request" "$E21_P" "Rename the function divide to safeDivide."
assert_eq "AC5.1 E21 the prompt ends with the non-interactive line" "(Non-interactive run: nobody will answer questions here. Use the playbook's non-interactive rule.)" "$(tail -n 1 "$REC/E21.prompt" 2>/dev/null)"
assert_eq "AC5.1 E21 the prompt does not mention report.js (the agent has to find it)" "0" "$(printf '%s' "$E21_P" | grep -c 'report')"

echo "v0.22.0 AC5.1 --scenarios E21 is accepted, the default list is unchanged"
run_x E21 accept "true" "$INIT" "$RES21"
assert_eq "AC5.1 --scenarios E21 is accepted (auto-gradable): not a usage error" "0" "$(printf '%s\n' "$OUT" | grep -c 'not auto-gradable')"
if [ "$RC" = 1 ]; then t_ok "AC5.1 an idle adapter fails E21: exit 1 (not the usage exit 2)"; else t_bad "AC5.1 an idle adapter fails E21: exit 1" "exit $RC; output: $OUT"; fi
assert_eq "AC5.2 E21 idle run: every call site is renamed FAIL" "FAIL" "$(e_state E21 "$K_SITES")"
assert_eq "AC5.2 E21 idle run: the spec has an Understanding section FAIL" "FAIL" "$(e_state E21 "$K_UND")"
assert_eq "AC5.2 E21 idle run: the spec names report.js FAIL" "FAIL" "$(e_state E21 "$K_REP")"
W="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $A/idle.sh" --workroot "$W" --out "$W/results.md"
assert_eq "AC5.1 the default scenarios stay E1,E3,E8,E15 (no E21 line)" "0" "$(printf '%s\n' "$OUT" | grep -c '^E21 ')"
SCEN="$PB_ROOT/evals/scenarios.md"
if grep -qxF '## E21 The whole request is found before editing' "$SCEN" 2>/dev/null; then t_ok "AC5.1 scenarios.md has the exact heading ## E21 The whole request is found before editing"; else t_bad "AC5.1 scenarios.md has the exact heading ## E21 The whole request is found before editing" "no such line in $SCEN"; fi
E21_SC="$(awk 'index($0, "## E21 ") == 1 { f = 1; print; next } f && /^## / { exit } f { print }' "$SCEN" 2>/dev/null)"
assert_contains "AC5.1 scenarios.md E21 has the quoted prompt" "$E21_SC" '"Rename the function divide to safeDivide."'
assert_contains "AC5.1 scenarios.md E21 has a Pass if line" "$E21_SC" '**Pass if:**'
assert_contains "AC5.1 scenarios.md E21 has a Fail if line" "$E21_SC" '**Fail if:**'
assert_contains "AC5.1 scenarios.md E21 names report.js" "$E21_SC" 'report.js'

echo "v0.22.0 AC5.2 E21 every call site is renamed"
run_x E21 calconly "$E21_SEE
$SPEC_OK
$REN_CALC" "$INIT" "$WSPEC" "$ECALC" "$RES21"
assert_eq "AC5.2 E21 report.js still calls divide: every call site is renamed FAIL" "FAIL" "$(e_state E21 "$K_SITES")"
assert_eq "AC5.2 E21 calc.js only: the spec checks still PASS (Understanding)" "PASS" "$(e_state E21 "$K_UND")"
assert_eq "AC5.2 E21 calc.js only: the spec checks still PASS (names report.js)" "PASS" "$(e_state E21 "$K_REP")"
assert_eq "AC5.2 E21 calc.js only: spec first still PASS" "PASS" "$(e_state E21 "$K_FIRST")"
assert_eq "AC5.2 E21 calc.js only: it is the only FAIL line" "1" "$(count_lines E21 FAIL)"
assert_rc "AC5.2 E21 calc.js only: exit 1" 1
run_x E21 reponly "$E21_SEE
$SPEC_OK
$REN_REP" "$INIT" "$WSPEC" "$EREP" "$RES21"
assert_eq "AC5.2 E21 only report.js renamed (calc.js still has divide): every call site is renamed FAIL" "FAIL" "$(e_state E21 "$K_SITES")"
run_x E21 comment "$GOOD21
printf '// divide by zero is not handled\n' >> src/calc.js" "$INIT" "$WSPEC" "$ECALC" "$EREP" "$RES21"
assert_eq "AC5.2 E21 a leftover word divide in src/calc.js (a comment): every call site is renamed FAIL" "FAIL" "$(e_state E21 "$K_SITES")"
run_x E21 safeonly "$GOOD21
printf '// safeDivide by zero is not handled\n' >> src/calc.js" "$INIT" "$WSPEC" "$ECALC" "$EREP" "$RES21"
assert_eq "AC5.2 E21 the word safeDivide in a comment is not a leftover: every call site is renamed PASS" "PASS" "$(e_state E21 "$K_SITES")"

echo "v0.22.0 AC5.2 E21 the spec checks"
run_x E21 noundersec "$E21_SEE
$SPEC_NO_UND
$REN_ALL" "$INIT" "$WSPEC" "$ECALC" "$EREP" "$RES21"
assert_eq "AC5.2 E21 spec without an Understanding section: the spec has an Understanding section FAIL" "FAIL" "$(e_state E21 "$K_UND")"
assert_eq "AC5.2 E21 spec without Understanding but naming report.js: the spec names report.js PASS" "PASS" "$(e_state E21 "$K_REP")"
assert_eq "AC5.2 E21 spec without Understanding: every call site is renamed PASS" "PASS" "$(e_state E21 "$K_SITES")"
assert_eq "AC5.2 E21 spec without Understanding: it is the only FAIL line" "1" "$(count_lines E21 FAIL)"
assert_rc "AC5.2 E21 spec without Understanding: exit 1" 1
run_x E21 norep "$E21_SEE
$SPEC_NO_REP
$REN_ALL" "$INIT" "$WSPEC" "$ECALC" "$EREP" "$RES21"
assert_eq "AC5.2 E21 spec that does not name report.js: the spec names report.js FAIL" "FAIL" "$(e_state E21 "$K_REP")"
assert_eq "AC5.2 E21 spec with Understanding but without report.js: the spec has an Understanding section PASS" "PASS" "$(e_state E21 "$K_UND")"
assert_eq "AC5.2 E21 spec without report.js: it is the only FAIL line" "1" "$(count_lines E21 FAIL)"
assert_rc "AC5.2 E21 spec without report.js: exit 1" 1
run_x E21 nospec "$E21_SEE
$REN_ALL" "$INIT" "$ECALC" "$EREP" "$RES21"
assert_eq "AC5.2 E21 no spec file at all: the spec has an Understanding section FAIL" "FAIL" "$(e_state E21 "$K_UND")"
assert_eq "AC5.2 E21 no spec file at all: the spec names report.js FAIL" "FAIL" "$(e_state E21 "$K_REP")"
assert_eq "AC5.2 E21 no spec file at all: the spec is written before the first src/ edit FAIL" "FAIL" "$(e_state E21 "$K_FIRST")"
assert_eq "AC5.2 E21 no spec file at all: the code checks still PASS (every call site)" "PASS" "$(e_state E21 "$K_SITES")"
assert_rc "AC5.2 E21 no spec file at all: exit 1" 1
run_x E21 specelsewhere "$E21_SEE
mkdir -p docs
printf '# Spec\n\n## Understanding\nRename divide in src/calc.js and src/report.js.\n' > docs/01-spec.md
$REN_ALL" "$INIT" "$ECALC" "$EREP" "$RES21"
assert_eq "AC5.2 E21 an Understanding section in docs/01-spec.md is not the spec: FAIL" "FAIL" "$(e_state E21 "$K_UND")"

echo "v0.22.0 AC5.2 E21 the spec is written before the first src/ edit (transcript order)"
run_x E21 late "$GOOD21" "$INIT" "$ECALC" "$EREP" "$WSPEC" "$RES21"
assert_eq "AC5.2 E21 spec Written after the src edit: the spec is written before the first src/ edit FAIL" "FAIL" "$(e_state E21 "$K_FIRST")"
assert_eq "AC5.2 E21 late spec: the content checks still PASS (Understanding)" "PASS" "$(e_state E21 "$K_UND")"
assert_eq "AC5.2 E21 late spec: the content checks still PASS (names report.js)" "PASS" "$(e_state E21 "$K_REP")"
assert_eq "AC5.2 E21 late spec: it is the only FAIL line" "1" "$(count_lines E21 FAIL)"
assert_rc "AC5.2 E21 late spec: exit 1" 1
run_x E21 interleaved "$GOOD21" "$INIT" "$WSPEC" "$ECALC" "$ESPEC" "$EREP" "$RES21"
assert_eq "AC5.2 E21 spec first, then a src edit, then a spec edit: the first spec write counts: PASS" "PASS" "$(e_state E21 "$K_FIRST")"
run_x E21 editspec "$GOOD21" "$INIT" "$ESPEC" "$ECALC" "$EREP" "$RES21"
assert_eq "AC5.2 E21 an Edit of the spec before the src edit counts as written first: PASS" "PASS" "$(e_state E21 "$K_FIRST")"
run_x E21 viabash "$GOOD21" "$INIT" "$(tu Bash '{"command":"cat src/report.js"}')" "$WSPEC" "$ECALC" "$EREP" "$RES21"
assert_eq "AC5.2 E21 reading files with Bash before the spec is fine: PASS" "PASS" "$(e_state E21 "$K_FIRST")"
run_x E21 testsfirst "$GOOD21" "$INIT" "$(tu Write '{"file_path":"/work/E21/tests/divide.test.js","content":"x"}')" "$WSPEC" "$ECALC" "$EREP" "$RES21"
assert_eq "AC5.2 E21 a Write under tests/ before the spec is not an src/ edit: PASS" "PASS" "$(e_state E21 "$K_FIRST")"

echo "v0.22.0 AC5.2 E21 plain-text transcript: the order check needs a human"
run_x E21 plain "$GOOD21
echo 'Spec written first, then the rename.'"
assert_eq "AC5.2 E21 plain-text transcript: the spec is written before the first src/ edit is MANUAL" "MANUAL" "$(e_state E21 "$K_FIRST")"
assert_eq "AC5.2 E21 plain-text transcript: every call site is renamed is still graded (PASS)" "PASS" "$(e_state E21 "$K_SITES")"
assert_eq "AC5.2 E21 plain-text transcript: the spec has an Understanding section is still graded (PASS)" "PASS" "$(e_state E21 "$K_UND")"
assert_eq "AC5.2 E21 plain-text transcript: the spec names report.js is still graded (PASS)" "PASS" "$(e_state E21 "$K_REP")"
assert_eq "AC5.2 E21 plain-text transcript: no FAIL line" "0" "$(count_lines E21 FAIL)"
assert_rc "AC5.2 E21 plain-text transcript: exit 0" 0

echo "v0.22.0 AC5.2 transcript.js spec_first"
TS="$PB_ROOT/evals/transcript.js"
TR="$(mk_tmp)"
SFW='{"file_path":"/w/E21/.agents/handoff/01-spec.md","content":"# Spec"}'
SRC='{"file_path":"/w/E21/src/calc.js","content":"x"}'
# sf_of LINE... -> the spec_first value of a transcript with those lines
sf_of() { printf '%s\n' "$@" > "$TR/t.json"; node "$TS" "$TR/t.json" 2>/dev/null | sed -n 's/^spec_first=//p'; }
assert_eq "AC5.2 spec_first=1: Write spec, then Write src" "1" "$(sf_of "$(tu Write "$SFW")" "$(tu Write "$SRC")")"
assert_eq "AC5.2 spec_first=0: Write src, then Write spec" "0" "$(sf_of "$(tu Write "$SRC")" "$(tu Write "$SFW")")"
assert_eq "AC5.2 spec_first=1: Edit spec, then Edit src" "1" "$(sf_of "$(tu Edit "$SFW")" "$(tu Edit "$SRC")")"
assert_eq "AC5.2 spec_first=0: Edit src, then Edit spec" "0" "$(sf_of "$(tu Edit "$SRC")" "$(tu Edit "$SFW")")"
assert_eq "AC5.2 spec_first=0: an src edit and no spec at all" "0" "$(sf_of "$(tu Write "$SRC")")"
assert_eq "AC5.2 spec_first=1: Write spec, then a Write under tests/, then Write src" "1" "$(sf_of "$(tu Write "$SFW")" "$(tu Write '{"file_path":"/w/E21/tests/a.test.js","content":"x"}')" "$(tu Write "$SRC")")"
assert_eq "AC5.2 spec_first=1: a tests/ write before the spec does not count as an src edit" "1" "$(sf_of "$(tu Write '{"file_path":"/w/E21/tests/a.test.js","content":"x"}')" "$(tu Write "$SFW")" "$(tu Write "$SRC")")"
assert_eq "AC5.2 spec_first=1: the first spec write counts even if the spec is edited again after src" "1" "$(sf_of "$(tu Write "$SFW")" "$(tu Write "$SRC")" "$(tu Edit "$SFW")")"
assert_eq "AC5.2 spec_first=1: Windows-style paths (backslashes)" "1" "$(sf_of "$(tu Write '{"file_path":"C:\\w\\E21\\.agents\\handoff\\01-spec.md","content":"x"}')" "$(tu Write '{"file_path":"C:\\w\\E21\\src\\calc.js","content":"x"}')")"
assert_eq "AC5.2 spec_first=0: a spec-like file in another directory is not the spec" "0" "$(sf_of "$(tu Write '{"file_path":"/w/E21/docs/01-spec.md","content":"x"}')" "$(tu Write "$SRC")")"
assert_eq "AC5.2 spec_first=0: a different file name in .agents/handoff is not the spec" "0" "$(sf_of "$(tu Write '{"file_path":"/w/E21/.agents/handoff/notes.md","content":"x"}')" "$(tu Write "$SRC")")"
assert_eq "AC5.2 spec_first=0: a Bash command that mentions the spec path is not a Write or Edit" "0" "$(sf_of "$(tu Bash '{"command":"echo x > .agents/handoff/01-spec.md"}')" "$(tu Write "$SRC")")"
assert_eq "AC5.2 spec_first=0: a Bash read of the spec between an src Write and the spec Write changes nothing" "0" "$(sf_of "$(tu Write "$SRC")" "$(tu Bash '{"command":"cat .agents/handoff/01-spec.md"}')" "$(tu Write "$SFW")")"
printf 'wrote the spec, then edited src/calc.js\nsecond line\n' > "$TR/p.txt"
assert_eq "AC5.2 spec_first=na for a plain-text transcript" "na" "$(node "$TS" "$TR/p.txt" 2>/dev/null | sed -n 's/^spec_first=//p')"
assert_eq "AC5.2 transcript.js prints the spec_first key exactly once" "1" "$(printf '%s\n' "$(tu Write "$SFW")" > "$TR/o.json"; node "$TS" "$TR/o.json" 2>/dev/null | grep -c '^spec_first=')"


echo "review: spec_first with no src write at all, MultiEdit, NotebookEdit, Bash edits of src/"
assert_eq "RV8 spec_first=1: a spec Write and no src/ write at all" "1" "$(sf_of "$(tu Write "$SFW")")"
assert_eq "RV8 spec_first=1: a spec Edit and no src/ write at all" "1" "$(sf_of "$(tu Edit "$SFW")")"
assert_eq "RV9 spec_first=0: MultiEdit of an src/ file before the spec" "0" "$(sf_of "$(tu MultiEdit '{"file_path":"/w/E21/src/calc.js","edits":[{"old_string":"a","new_string":"b"}]}')" "$(tu Write "$SFW")")"
assert_eq "RV9 spec_first=1: the spec, then a MultiEdit of src/" "1" "$(sf_of "$(tu Write "$SFW")" "$(tu MultiEdit '{"file_path":"/w/E21/src/calc.js","edits":[]}')")"
assert_eq "RV9 spec_first=0: NotebookEdit of an src/ notebook before the spec" "0" "$(sf_of "$(tu NotebookEdit '{"notebook_path":"/w/E21/src/n.ipynb","new_source":"x"}')" "$(tu Write "$SFW")")"
# btu COMMAND -> a Bash tool_use line (JSON-escaped by node)
btu() { node -e 'console.log(JSON.stringify({type:"assistant",message:{content:[{type:"tool_use",id:"b1",name:"Bash",input:{command:process.argv[1]}}]}}))' "$1"; }
SI="-i"   # built from a variable so that no literal in-place sed sits in this file
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  assert_eq "RV9 spec_first=0: a Bash edit of src/ before the spec [$cmd]" "0" "$(sf_of "$(btu "$cmd")" "$(tu Write "$SFW")")"
  assert_eq "RV9 spec_first=1: the same Bash edit after the spec [$cmd]" "1" "$(sf_of "$(tu Write "$SFW")" "$(btu "$cmd")")"
done <<XEOF
sed $SI 's/divide/safeDivide/g' src/calc.js
sed $SI.bak 's/a/b/' src/x.js
sed -e 's/a/b/' $SI src/x.js
perl -pi -e 's/a/b/' src/x.js
perl -i -pe 's/a/b/' src/x.js
echo hi > src/x.js
cat /tmp/new.js > src/x.js
printf 'x' > ./src/x.js
echo x | tee src/x.js
echo x | tee -a src/x.js
mv /tmp/a.js src/x.js
cd /w/E21 && sed $SI 's/a/b/' src/calc.js
XEOF
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  assert_eq "RV9 not an src/ write [$cmd]: spec_first stays 1 when the spec comes first and src is edited later" "1" "$(sf_of "$(btu "$cmd")" "$(tu Write "$SFW")" "$(tu Write "$SRC")")"
done <<'XEOF'
cat src/calc.js
grep -rn divide src
sed -n 1,5p src/calc.js
ls src > /tmp/listing.txt
cat src/calc.js > /tmp/copy.js
cp src/calc.js /tmp/copy.js
echo hi > srcnotes.txt
XEOF
assert_eq "RV9 spec_first=1: a Write under node_modules/x/src/ is not an src/ write" "1" "$(sf_of "$(tu Write '{"file_path":"/w/E21/node_modules/x/src/a.js","content":"x"}')" "$(tu Write "$SFW")")"
assert_eq "RV9 spec_first=1: a Bash write under node_modules/x/src/ is not an src/ write" "1" "$(sf_of "$(btu 'echo x > node_modules/x/src/a.js')" "$(tu Write "$SFW")")"
assert_eq "RV9 spec_first=1: a Bash sed edit under node_modules/x/src/ is not an src/ write" "1" "$(sf_of "$(btu "sed $SI 's/a/b/' node_modules/x/src/a.js")" "$(tu Write "$SFW")")"
assert_eq "RV9 spec_first=0: a real src/ write after a node_modules one and before the spec" "0" "$(sf_of "$(tu Write '{"file_path":"/w/E21/node_modules/x/src/a.js","content":"x"}')" "$(tu Write "$SRC")" "$(tu Write "$SFW")")"

t_summary
