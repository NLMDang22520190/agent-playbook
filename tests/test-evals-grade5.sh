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
assert_eq "AC5.2 spec_first=0: a Bash command that only mentions (reads) the spec path is not a spec write" "0" "$(sf_of "$(tu Bash '{"command":"cat .agents/handoff/01-spec.md"}')" "$(tu Write "$SRC")")"
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

echo "v0.23.1 AC9.1 bashWritesSrc: cd into src, git mv, node writeFileSync, with read-only twins"
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  assert_eq "AC9.1 spec_first=0: a Bash write to src/ before the spec [$cmd]" "0" "$(sf_of "$(btu "$cmd")" "$(tu Write "$SFW")")"
  assert_eq "AC9.1 spec_first=1: the same write after the spec [$cmd]" "1" "$(sf_of "$(tu Write "$SFW")" "$(btu "$cmd")")"
done <<XEOF
cd src && sed $SI 's/divide/safeDivide/g' calc.js
cd src; sed $SI.bak 's/a/b/' calc.js
cd ./src && sed $SI 's/a/b/' calc.js
cd /w/E21/src && sed $SI 's/a/b/' calc.js
git mv x src/y
git mv src/a src/b
node -e "require('fs').writeFileSync('src/x','')"
node -e "require('fs').writeFileSync('./src/x.js','y')"
XEOF
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  assert_eq "AC9.1 not an src/ write [$cmd]: spec_first stays 1 when the spec comes first and src is edited later" "1" "$(sf_of "$(btu "$cmd")" "$(tu Write "$SFW")" "$(tu Write "$SRC")")"
done <<'XEOF'
cd src && cat calc.js
cd src && grep -n divide calc.js
git mv a b
git mv docs/a docs/b
node -e "require('fs').readFileSync('src/x','utf8')"
node -e "readFileSync('src/x')"
XEOF
assert_eq "AC9.1 spec_first=1: a cd into src/ and back out, then an edit elsewhere, is not an src/ write" "1" "$(sf_of "$(btu 'cd src && cat calc.js && cd .. && echo x > notes.txt')" "$(tu Write "$SFW")" "$(tu Write "$SRC")")"

echo "v0.23.1 review M3/M4 bashWritesSrc: relative cd chains, subshell cd, git -C mv"
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  assert_eq "M3/M4 spec_first=0: a Bash write to src/ before the spec [$cmd]" "0" "$(sf_of "$(btu "$cmd")" "$(tu Write "$SFW")")"
  assert_eq "M3/M4 spec_first=1: the same write after the spec [$cmd]" "1" "$(sf_of "$(tu Write "$SFW")" "$(btu "$cmd")")"
done <<XEOF
cd src && cd lib && sed $SI 's/a/b/' x.js
cd src; cd lib; sed $SI 's/a/b/' x.js
(cd src && sed $SI 's/a/b/' calc.js)
(cd src; sed $SI.bak 's/a/b/' calc.js)
git -C . mv a src/b
XEOF
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  assert_eq "M3/M4 not an src/ write [$cmd]: spec_first stays 1 when the spec comes first and src is edited later" "1" "$(sf_of "$(btu "$cmd")" "$(tu Write "$SFW")" "$(tu Write "$SRC")")"
done <<'XEOF'
git mv src/a lib/b
git -C . mv src/a lib/b
git -C . mv a b
(cd src && cat calc.js)
XEOF
assert_eq "M4 spec_first=1: a subshell cd does not leak: a write after it, outside the subshell, is not in src" "1" "$(sf_of "$(btu "(cd src && cat calc.js); echo x > notes.txt")" "$(tu Write "$SFW")" "$(tu Write "$SRC")")"

echo "v0.23.1 review: skipping 'git -C d' options in bashWritesSrc is linear"
# a transcript (a Bash command, then the spec Write) run with a watchdog: budget = a run on a tiny command + 8 s (no GNU timeout on macOS)
# The command is built inside node from a repeat count: one argv string is capped at 128 KiB (MAX_ARG_STRLEN) on Linux.
GC_BASE=-1
gc_ticks() { # PAIRS TAIL LIMIT -> GC_TICKS (tenths of a second), GC_HUNG; the command is "git" + PAIRS x " -C d" + TAIL (PAIRS 0: TAIL alone)
  node -e 'const n=+process.argv[1],t=process.argv[2];const c=n>0?"git"+" -C d".repeat(n)+t:t;console.log(JSON.stringify({type:"assistant",message:{content:[{type:"tool_use",id:"b1",name:"Bash",input:{command:c}}]}}))' "$1" "$2" > "$TR/gc.json"
  tu Write "$SFW" >> "$TR/gc.json"; echo >> "$TR/gc.json"
  node "$TS" "$TR/gc.json" > "$TR/gc.out" 2>/dev/null &
  local pid=$! i=0
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt "$3" ]; do sleep 0.1; i=$((i + 1)); done
  GC_TICKS=$i; GC_HUNG=0
  if kill -0 "$pid" 2>/dev/null; then GC_HUNG=1; kill -9 "$pid" 2>/dev/null; fi
  wait "$pid" 2>/dev/null
}
gc_timed() { # PAIRS TAIL -> the spec_first value, or SLOW
  if [ "$GC_BASE" -lt 0 ]; then gc_ticks 0 "echo x" 600; GC_BASE="$GC_TICKS"; fi
  gc_ticks "$1" "$2" $((GC_BASE + 80))
  if [ "$GC_HUNG" = 1 ]; then echo SLOW; return 0; fi
  sed -n 's/^spec_first=//p' "$TR/gc.out"
}
assert_eq "M5 200000 'git -C d' pairs then 'mv a src/b' before the spec: finishes within the baseline + 8 s and still counts as an src write (spec_first=0)" "0" "$(gc_timed 200000 " mv a src/b")"
assert_eq "M5 200000 'git -C d' pairs then a read-only 'mv a b': finishes within the baseline + 8 s, not an src write (spec_first=1)" "1" "$(gc_timed 200000 " mv a b")"


# ---- v0.23.2 AC4: bashWritesSrc reads the heredoc-stripped command; a heredoc fed to a shell is executed (D3) ----
echo "v0.23.2 AC4.1 bashWritesSrc: a heredoc body is data (opener line still counts)"
NLH='
'
SIH="-i"   # a variable, so no literal in-place sed sits in this file
# hw_of COMMAND -> spec_first when the command comes first, then the spec, then an src write:
#   1 = the command was not an src write; 0 = the command was an src write before the spec
hw_of() { sf_of "$(btu "$1")" "$(tu Write "$SFW")" "$(tu Write "$SRC")"; }
# hw_before COMMAND -> spec_first when only the command comes before the spec (0 = the command wrote under src/)
hw_before() { sf_of "$(btu "$1")" "$(tu Write "$SFW")"; }
hdw() { # KIND(no|yes) NAME COMMAND
  if [ "$1" = no ]; then assert_eq "AC4.1 not an src write: $2" "1" "$(hw_of "$3")"
  else assert_eq "AC4.1 an src write: $2" "0" "$(hw_before "$3")"; fi
}
# corpus first: these hold today and must keep holding
hdw yes "the opener line redirects into src/ (cat > src/x.js <<EOF)" "cat > src/x.js <<EOF${NLH}content${NLH}EOF"
hdw yes "the opener appends into src/ with a quoted word (cat >> src/x.js <<'EOF')" "cat >> src/x.js <<'EOF'${NLH}content${NLH}EOF"
hdw yes "a write after the heredoc has ended" "cat > notes.md <<EOF${NLH}notes${NLH}EOF${NLH}sed $SIH 's/a/b/' src/x.js"
hdw yes "a write before the heredoc" "sed $SIH 's/a/b/' src/x.js${NLH}cat > notes.md <<EOF${NLH}notes${NLH}EOF"
hdw yes "bash <<EOF with an in-place sed on src/ in the body" "bash <<EOF${NLH}sed $SIH 's/a/b/' src/x.js${NLH}EOF"
hdw no "no heredoc, a read of src/" "cat src/x.js"
# AC4.1: the body of a heredoc that no shell reads is data
hdw no "body has an in-place sed on src/ (opener cat > notes.md <<EOF)" "cat > notes.md <<EOF${NLH}sed $SIH 's/a/b/' src/x.js${NLH}EOF"
hdw no "body has an in-place sed on src/ (opener cat > notes.md <<'EOF')" "cat > notes.md <<'EOF'${NLH}sed $SIH 's/a/b/' src/x.js${NLH}EOF"
hdw no "body mentions sed -i.bak on src/ (cat <<EOF, no redirect)" "cat <<EOF${NLH}sed $SIH.bak 's/a/b/' src/x.js${NLH}EOF"
hdw no "body redirects into src/ (cat <<EOF)" "cat <<EOF${NLH}echo hi > src/x.js${NLH}EOF"
hdw no "body mentions tee into src/ (cat > notes.md <<-EOF, tab-indented)" "cat > notes.md <<-EOF${NLH}	echo x | tee src/x.js${NLH}	EOF"
hdw no "body mentions mv into src/ (git commit message in a substitution)" "git commit -m \"\$(cat <<EOF${NLH}mv a src/b${NLH}sed $SIH 's/a/b/' src/x.js${NLH}EOF${NLH})\""
hdw no "body mentions node writeFileSync into src/ (cat > notes.md <<EOF)" "cat > notes.md <<EOF${NLH}node -e \"require('fs').writeFileSync('src/x','')\"${NLH}EOF"

echo "v0.23.2 AC4.2 bashWritesSrc: a heredoc fed to a shell is executed (D3)"
hdw yes "bash <<'EOF' (quoted word)" "bash <<'EOF'${NLH}sed $SIH 's/a/b/' src/x.js${NLH}EOF"
hdw yes "sh -s <<EOF" "sh -s <<EOF${NLH}sed $SIH 's/a/b/' src/x.js${NLH}EOF"
hdw yes "zsh <<EOF" "zsh <<EOF${NLH}sed $SIH 's/a/b/' src/x.js${NLH}EOF"
hdw yes "bash -e <<EOF" "bash -e <<EOF${NLH}sed $SIH 's/a/b/' src/x.js${NLH}EOF"
hdw yes "bash -eu -o pipefail <<EOF (option with a value)" "bash -eu -o pipefail <<EOF${NLH}sed $SIH 's/a/b/' src/x.js${NLH}EOF"
hdw yes "sh -s -- <<EOF" "sh -s -- <<EOF${NLH}sed $SIH 's/a/b/' src/x.js${NLH}EOF"
hdw yes "zsh -x <<'EOF'" "zsh -x <<'EOF'${NLH}sed $SIH 's/a/b/' src/x.js${NLH}EOF"
hdw yes "/bin/bash <<EOF (path to the shell)" "/bin/bash <<EOF${NLH}sed $SIH 's/a/b/' src/x.js${NLH}EOF"
hdw yes "bash <<-EOF (tab-indented terminator)" "bash <<-EOF${NLH}	sed $SIH 's/a/b/' src/x.js${NLH}	EOF"
hdw yes "bash <<EOF with an echo redirect into src/ in the body" "bash <<EOF${NLH}echo hi > src/x.js${NLH}EOF"
hdw yes "bash <<EOF with a read first and a write second in the body" "bash <<EOF${NLH}cat src/x.js${NLH}sed $SIH 's/a/b/' src/x.js${NLH}EOF"
hdw yes "a harmless heredoc, then bash <<EOF with the write" "cat <<EOF${NLH}notes${NLH}EOF${NLH}bash <<EOF${NLH}sed $SIH 's/a/b/' src/x.js${NLH}EOF"
hdw no "bash <<EOF whose body only reads src/" "bash <<EOF${NLH}cat src/x.js${NLH}EOF"
hdw no "bash <<EOF whose body writes outside src/" "bash <<EOF${NLH}sed $SIH 's/a/b/' lib/x.js${NLH}EOF"
# assumption (see the lane report): a shell that is given a script file reads its heredoc as stdin input, not as commands
hdw no "bash build.sh <<EOF: the body is input to the script, not commands" "bash build.sh <<EOF${NLH}sed $SIH 's/a/b/' src/x.js${NLH}EOF"
hdw no "cat <<EOF followed by a pipe word: the body of cat is data" "cat <<EOF | tr a b${NLH}sed $SIH 's/a/b/' src/x.js${NLH}EOF"


echo "v0.23.2 AC4.1 real E21 transcript (v0.23.1 false FAIL): the spec written through a heredoc is not an src write"
NLX='
'
BTK='`'
SPECCMD="cd /w/E21/.agents/handoff && cat > 01-spec.md <<'EOF'${NLX}# Spec${NLX}## Understanding${NLX}  - ${BTK}grep -rn \"divide\" .${BTK} -> 4 hits: src/calc.js:5, src/report.js:1${NLX}In scope: src/calc.js definition${NLX}EOF"
SPECEDIT="$(tu Edit '{"file_path":"/w/E21/.agents/handoff/01-spec.md","old_string":"# Spec","new_string":"# Spec v2"}')"
SEDSRC="sed $SIH 's/a/b/' src/calc.js"
assert_eq "AC4.1 E21: heredoc spec call, the spec edit, then an in-place sed on src/: spec_first=1" "1" "$(sf_of "$(btu "$SPECCMD")" "$SPECEDIT" "$(btu "$SEDSRC")")"
assert_eq "AC4.1 E21: a read first, then the in-place sed on src/, then the spec edit: spec_first=0" "0" "$(sf_of "$(btu "cat src/calc.js")" "$(btu "$SEDSRC")" "$SPECEDIT")"

# the same shape with an arrow that points straight at an src path in the body (a redirect-looking token before a path)
SPECCMD2="cd /w/E21/.agents/handoff && cat > 01-spec.md <<'EOF'${NLX}## Understanding${NLX}  - the call sites -> src/calc.js:5 and src/report.js:1${NLX}EOF"
assert_eq "AC4.1 E21 arrow variant: heredoc spec call, the spec edit, then an in-place sed on src/: spec_first=1" "1" "$(sf_of "$(btu "$SPECCMD2")" "$SPECEDIT" "$(btu "$SEDSRC")")"
assert_eq "AC4.1 E21 arrow variant: the heredoc spec call alone is not an src write (spec edit, then src Write after it: spec_first=1)" "1" "$(sf_of "$(btu "$SPECCMD2")" "$SPECEDIT" "$(tu Write "$SRC")")"


# ---- v0.23.2 AC4.3 (D8): a Bash call that writes the spec file is the spec write ----
echo "v0.23.2 AC4.3 spec_first: a Bash write of .agents/handoff/01-spec.md sets the spec write"
SPB1="cd /w/E21/.agents/handoff && cat > 01-spec.md <<'EOF'${NLX}# Spec${NLX}## Understanding${NLX}  - ${BTK}grep -rn \"divide\" .${BTK} -> 4 hits: src/calc.js:5, src/report.js:1${NLX}In scope: src/calc.js definition${NLX}EOF"
SPB4="cat > .agents/handoff/01-spec.md <<EOF${NLX}## Understanding${NLX}  - the call sites -> src/calc.js:5 and src/report.js:1${NLX}EOF"
# no Write/Edit tool call of the spec anywhere in these transcripts: only Bash calls
assert_eq "AC4.3 case 1: cd .agents/handoff && cat > 01-spec.md <<'EOF', then an in-place sed on src/: spec_first=1" "1" "$(sf_of "$(btu "$SPB1")" "$(btu "$SEDSRC")")"
assert_eq "AC4.3 case 2: the in-place sed on src/ first, then the heredoc spec call: spec_first=0" "0" "$(sf_of "$(btu "$SEDSRC")" "$(btu "$SPB1")")"
assert_eq "AC4.3 case 3: echo x > notes.md is not the spec, then an src write: spec_first=0" "0" "$(sf_of "$(btu "echo x > notes.md")" "$(btu "$SEDSRC")")"
assert_eq "AC4.3 case 4: cat > .agents/handoff/01-spec.md <<EOF with '-> src/calc.js:5' in the body, then an src write: spec_first=1 (the real E21 shape)" "1" "$(sf_of "$(btu "$SPB4")" "$(btu "$SEDSRC")")"
assert_eq "AC4.3 case 4b: the same with a Write tool call of src/ after it: spec_first=1" "1" "$(sf_of "$(btu "$SPB4")" "$(tu Write "$SRC")")"
assert_eq "AC4.3 case 4c: the same but the src Write comes first: spec_first=0" "0" "$(sf_of "$(tu Write "$SRC")" "$(btu "$SPB4")")"
# other ways to write the spec, and near misses
assert_eq "AC4.3 an append (>>) to the spec counts: spec_first=1" "1" "$(sf_of "$(btu "echo x >> .agents/handoff/01-spec.md")" "$(btu "$SEDSRC")")"
assert_eq "AC4.3 an in-place sed of the spec counts: spec_first=1" "1" "$(sf_of "$(btu "sed $SIH.bak 's/a/b/' .agents/handoff/01-spec.md")" "$(btu "$SEDSRC")")"
assert_eq "AC4.3 an absolute spec path counts: spec_first=1" "1" "$(sf_of "$(btu "echo x > /w/E21/.agents/handoff/01-spec.md")" "$(btu "$SEDSRC")")"
assert_eq "AC4.3 the spec call and the src write in one command, spec first: spec_first=1" "1" "$(sf_of "$(btu "echo x > .agents/handoff/01-spec.md && $SEDSRC")")"
assert_eq "AC4.3 the same in one command, src first: spec_first=0" "0" "$(sf_of "$(btu "$SEDSRC && echo x > .agents/handoff/01-spec.md")")"
assert_eq "AC4.3 reading the spec is not writing it (cat, then an src write): spec_first=0" "0" "$(sf_of "$(btu "cat .agents/handoff/01-spec.md")" "$(btu "$SEDSRC")")"
assert_eq "AC4.3 a bare 01-spec.md without the handoff dir is not the spec: spec_first=0" "0" "$(sf_of "$(btu "echo x > 01-spec.md")" "$(btu "$SEDSRC")")"
assert_eq "AC4.3 docs/01-spec.md is not the spec: spec_first=0" "0" "$(sf_of "$(btu "echo x > docs/01-spec.md")" "$(btu "$SEDSRC")")"
assert_eq "AC4.3 a spec mentioned only in a heredoc body is not written: spec_first=0" "0" "$(sf_of "$(btu "cat > notes.md <<EOF${NLX}echo x > .agents/handoff/01-spec.md${NLX}EOF")" "$(btu "$SEDSRC")")"
assert_eq "AC4.3 cd .agents/handoff in a subshell does not leak: a bare 01-spec.md after it is not the spec: spec_first=0" "0" "$(sf_of "$(btu "(cd /w/E21/.agents/handoff && true); echo x > 01-spec.md")" "$(btu "$SEDSRC")")"



# ---- v0.23.2 lane B review (F1): heredoc stripping is linear ----
echo "v0.23.2 review F1 stripHeredocs is linear: 20000 'cat <<A ' on one line"
# one Bash call built inside node (argv is capped at 128 KiB), then the spec Write and an src Write; budget = baseline + 8 s
HL_BASE=-1
hl_ticks() { # LIMIT -> HL_TICKS, HL_HUNG
  node -e 'const c="cat <<A ".repeat(20000);console.log(JSON.stringify({type:"assistant",message:{content:[{type:"tool_use",id:"b1",name:"Bash",input:{command:c}}]}}))' > "$TR/hl.json"
  tu Write "$SFW" >> "$TR/hl.json"; echo >> "$TR/hl.json"
  tu Write "$SRC" >> "$TR/hl.json"; echo >> "$TR/hl.json"
  node "$TS" "$TR/hl.json" > "$TR/hl.out" 2>/dev/null &
  local pid=$! i=0
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt "$1" ]; do sleep 0.1; i=$((i + 1)); done
  HL_TICKS=$i; HL_HUNG=0
  if kill -0 "$pid" 2>/dev/null; then HL_HUNG=1; kill -9 "$pid" 2>/dev/null; fi
  wait "$pid" 2>/dev/null
}
hl_base() { # the time of a run on a tiny command
  printf '%s\n' "$(btu "echo x")" "$(tu Write "$SFW")" "$(tu Write "$SRC")" > "$TR/hl.json"
  node "$TS" "$TR/hl.json" > "$TR/hl.out" 2>/dev/null &
  local pid=$! i=0
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 600 ]; do sleep 0.1; i=$((i + 1)); done
  HL_BASE="$i"; wait "$pid" 2>/dev/null
}
hl_timed() {
  [ "$HL_BASE" -ge 0 ] || hl_base
  hl_ticks $((HL_BASE + 80))
  if [ "$HL_HUNG" = 1 ]; then echo SLOW; return 0; fi
  sed -n 's/^spec_first=//p' "$TR/hl.out"
}
assert_eq "F1 20000 'cat <<A ' then the spec and an src write: finishes within the baseline + 8 s, spec_first=1" "1" "$(hl_timed)"

# ---- v0.23.2 lane B review (F2): bash -c '...' <<EOF: the body is stdin of the -c script, not commands ----
echo "v0.23.2 review F2 bashWritesSrc: a heredoc after bash -c is input, not commands"
hdw no "bash -c 'cat' <<EOF" "bash -c 'cat' <<EOF${NLH}sed $SIH 's/a/b/' src/x.js${NLH}EOF"
hdw no "bash -c \"cat\" <<EOF (double quotes)" "bash -c \"cat\" <<EOF${NLH}sed $SIH 's/a/b/' src/x.js${NLH}EOF"
hdw no "bash -ec 'cat' <<EOF (option cluster)" "bash -ec 'cat' <<EOF${NLH}sed $SIH 's/a/b/' src/x.js${NLH}EOF"
hdw no "sh -c 'cat' <<'EOF'" "sh -c 'cat' <<'EOF'${NLH}sed $SIH 's/a/b/' src/x.js${NLH}EOF"
# controls: the -c script itself runs
hdw yes "bash -c with an src write as the script, heredoc body is input" "bash -c 'sed $SIH s/a/b/ src/x.js' <<EOF${NLH}input${NLH}EOF"
hdw yes "bash <<EOF still executes the body" "bash <<EOF${NLH}sed $SIH 's/a/b/' src/x.js${NLH}EOF"

# ---- v0.23.3 AC6.2 / AC6.3 / AC6.4: the same shell feeds for bashWritesSrc (the body is read when a shell reads it) ----
echo "v0.23.3 AC6.2 bashWritesSrc: options with values, -s with arguments, redirects, wrappers; the last heredoc body is the input"
SW="sed $SIH 's/a/b/' src/x.js"
hdw yes "bash --rcfile f <<EOF" "bash --rcfile f <<EOF${NLH}${SW}${NLH}EOF"
hdw yes "bash --init-file f <<EOF" "bash --init-file f <<EOF${NLH}${SW}${NLH}EOF"
hdw yes "bash -s -- a <<EOF" "bash -s -- a <<EOF${NLH}${SW}${NLH}EOF"
hdw yes "bash -s arg <<EOF" "bash -s arg <<EOF${NLH}${SW}${NLH}EOF"
hdw yes "bash 2>&1 <<EOF" "bash 2>&1 <<EOF${NLH}${SW}${NLH}EOF"
hdw yes "bash 2>/dev/null <<EOF" "bash 2>/dev/null <<EOF${NLH}${SW}${NLH}EOF"
hdw yes "bash &>f <<EOF" "bash &>f <<EOF${NLH}${SW}${NLH}EOF"
hdw yes "bash <&0 <<EOF" "bash <&0 <<EOF${NLH}${SW}${NLH}EOF"
hdw yes "bash <<A <<B with the src write only in B (bash reads the last body)" "bash <<A <<B${NLH}echo hi${NLH}A${NLH}${SW}${NLH}B"
hdw no "bash <<A <<B with the src write only in A (an earlier body is data)" "bash <<A <<B${NLH}${SW}${NLH}A${NLH}echo hi${NLH}B"
hdw no "bash <<EOF <input.txt (the file after the heredoc is the stdin: the body is data)" "bash <<EOF <input.txt${NLH}${SW}${NLH}EOF"
hdw yes "sudo -u x bash <<EOF" "sudo -u x bash <<EOF${NLH}${SW}${NLH}EOF"
hdw yes "env FOO=1 bash <<EOF" "env FOO=1 bash <<EOF${NLH}${SW}${NLH}EOF"
hdw yes "nice -n 5 bash <<EOF" "nice -n 5 bash <<EOF${NLH}${SW}${NLH}EOF"
hdw yes "exec -a n bash <<EOF" "exec -a n bash <<EOF${NLH}${SW}${NLH}EOF"
hdw yes "sudo -s <<EOF" "sudo -s <<EOF${NLH}${SW}${NLH}EOF"
hdw no "command -v bash <<EOF is a lookup" "command -v bash <<EOF${NLH}${SW}${NLH}EOF"
hdw no "bash 2>&1 build.sh <<EOF: a script file, the body is input" "bash 2>&1 build.sh <<EOF${NLH}${SW}${NLH}EOF"

echo "v0.23.3 AC6.3 bashWritesSrc: a heredoc inside the -c string of a shell is commands; a commit message stays data"
hdw yes "sh -c \"\$(cat <<'EOF' ...)\"" "sh -c \"\$(cat <<'EOF'${NLH}${SW}${NLH}EOF${NLH})\""
hdw yes "bash -c \"\$(cat <<'EOF' ...)\"" "bash -c \"\$(cat <<'EOF'${NLH}${SW}${NLH}EOF${NLH})\""
hdw yes "zsh -c \"\$(cat <<EOF ...)\"" "zsh -c \"\$(cat <<EOF${NLH}${SW}${NLH}EOF${NLH})\""
hdw no "git commit -m \"\$(cat <<EOF ...)\" stays data" "git commit -m \"\$(cat <<EOF${NLH}${SW}${NLH}EOF${NLH})\""
hdw no "echo \"\$(cat <<'EOF' ...)\" stays data" "echo \"\$(cat <<'EOF'${NLH}${SW}${NLH}EOF${NLH})\""

echo "v0.23.3 AC6.4 bashWritesSrc: a heredoc word with a dash ends at its own terminator line"
hdw yes "cat <<END-X, body, END-X, then an src write" "cat <<END-X${NLH}notes${NLH}END-X${NLH}${SW}"
hdw no "cat <<END-X with an src write in the body is data" "cat <<END-X${NLH}${SW}${NLH}END-X"
hdw yes "bash <<END-X with an src write in the body is fed to the shell" "bash <<END-X${NLH}${SW}${NLH}END-X"

# ---- v0.23.2 lane B review (F4): one command that writes the spec and src is src-first ----
echo "v0.23.2 review F4 spec_first: a single command writing both spec and src counts src first"
SPECP=".agents/handoff/01-spec.md"
assert_eq "F4 an in-place sed on src/ with a redirect into the spec: spec_first=0" "0" "$(sf_of "$(btu "sed $SIH s/a/b/ src/a.js > $SPECP")")"
assert_eq "F4 cp into src/ with a redirect into the spec: spec_first=0" "0" "$(sf_of "$(btu "cp a src/a.js > $SPECP")")"
assert_eq "F4 tee writing the spec and src/: spec_first=0" "0" "$(sf_of "$(btu "echo x | tee $SPECP src/a.js")")"
assert_eq "F4 tee writing src/ and the spec: spec_first=0" "0" "$(sf_of "$(btu "echo x | tee src/a.js $SPECP")")"
assert_eq "F4 control: spec; src gives 1" "1" "$(sf_of "$(btu "echo x > $SPECP; sed $SIH s/a/b/ src/a.js")")"
assert_eq "F4 control: src; spec gives 0" "0" "$(sf_of "$(btu "sed $SIH s/a/b/ src/a.js; echo x > $SPECP")")"
assert_eq "F4 control: tee of the spec alone, then an src write: spec_first=1" "1" "$(sf_of "$(btu "echo x | tee $SPECP")" "$(tu Write "$SRC")")"


# ---- v0.23.3 corpus: real eval transcripts keep every key ----
# The logs of real runs (v0.23.1: E16, E17, E19, E21; v0.23.2: E15, E19, E21) are not committed (they are large and CI does not
# have them). Where the directory exists on the machine that runs the suite, transcript.js must print exactly the keys it printed
# when the lane started (spec_first=1 in every one of them); where it is missing, the case is skipped and counted.
# PB_EV231_DIR / PB_EV232_DIR override the default places ($HOME/ev231-evidence, $HOME/ev232-evidence).
echo "v0.23.3 corpus: the real transcripts keep their keys (skipped when the logs are absent)"
EV231="${PB_EV231_DIR:-$HOME/ev231-evidence}"
EV232="${PB_EV232_DIR:-$HOME/ev232-evidence}"
# corpus_case DIR FILE EXPECTED-KEYS -> the keys of transcript.js on a COPY of the log (the .result file is written next to the log)
corpus_case() {
  local dir="$1" f="$2" want="$3" copy
  if [ ! -f "$dir/$f" ]; then t_skip 1 "corpus $f: $dir/$f is absent"; return 0; fi
  copy="$TR/corpus-$(basename "$dir")-$f"; cp "$dir/$f" "$copy"
  assert_eq "corpus $(basename "$dir")/$f keeps its keys" "$want" "$(node "$TS" "$copy" 2>/dev/null | tr '\n' ' ')"
}
corpus_case "$EV231" E16.log "json=1 result_ok=1 cost=2.502914 subagent=1 tdd_order=ok feedback_captured=0 full_named=1 untested_label=0 ran_tests=1 spec_first=1 asked=0 models=sonnet,sonnet,opus,sonnet "
corpus_case "$EV231" E17.log "json=1 result_ok=1 cost=0.397748 subagent=0 tdd_order=ok feedback_captured=0 full_named=0 untested_label=0 ran_tests=1 spec_first=1 asked=0 models= "
corpus_case "$EV231" E19.log "json=1 result_ok=1 cost=0.5311316 subagent=0 tdd_order=ok feedback_captured=0 full_named=0 untested_label=0 ran_tests=1 spec_first=1 asked=0 models= "
corpus_case "$EV231" E21.log "json=1 result_ok=1 cost=1.5856581 subagent=1 tdd_order=ok feedback_captured=0 full_named=1 untested_label=0 ran_tests=1 spec_first=1 asked=0 models=sonnet,sonnet,opus "
corpus_case "$EV232" E15.log "json=1 result_ok=1 cost=0.4213710000000001 subagent=0 tdd_order=ok feedback_captured=0 full_named=0 untested_label=0 ran_tests=1 spec_first=1 asked=0 models= "
corpus_case "$EV232" E19.log "json=1 result_ok=1 cost=0.5172622 subagent=0 tdd_order=ok feedback_captured=0 full_named=0 untested_label=0 ran_tests=1 spec_first=1 asked=0 models= "
corpus_case "$EV232" E21.log "json=1 result_ok=1 cost=1.6847831 subagent=1 tdd_order=ok feedback_captured=0 full_named=1 untested_label=0 ran_tests=1 spec_first=1 asked=0 models=sonnet,sonnet,opus "

echo "v0.24.18 G1 E21: a deprecated alias of the old name is not a missed call site (Run 13, v0.24.17)"
# Run 13 renamed the definition and every call site, then kept `const divide = safeDivide` and exported both names
# (a logged DECISION for outside callers); scenarios.md E21 fails only a run that "renames only the definition (or only
# some call sites)". The check now fails on a call or a definition of divide, or on any divide left in report.js.
ALIAS='printf "%s\n" "const divide = safeDivide; // DECISION[D1]: deprecated alias, kept for outside callers" >> src/calc.js
node -e "const fs=require(\"fs\");const f=\"src/calc.js\";fs.writeFileSync(f,fs.readFileSync(f,\"utf8\").replace(/module\.exports = \{ add, safeDivide \};/,\"\").trimEnd()+\"\nmodule.exports = { add, safeDivide, divide };\n\")"'
run_x E21 alias "$SPEC_OK
$REN_ALL
$ALIAS
grep -c divide src/calc.js > \"\$REC/E21.alias\"" "$INIT" "$WSPEC" "$ECALC" "$EREP" "$RES21"
assert_eq "G1 alias run: every call site is renamed PASS" "PASS" "$(e_state E21 "$K_SITES")"
assert_eq "G1 alias run: node --test passes (the alias is the same function)" "PASS" "$(e_state E21 "$K_NODE")"
if [ "$(cat "$REC/E21.alias" 2>/dev/null)" -ge 2 ] 2>/dev/null; then t_ok "G1 alias run: calc.js really keeps the word divide (alias + export)"; else t_bad "G1 alias run: calc.js really keeps the word divide (alias + export)" "count: $(cat "$REC/E21.alias" 2>/dev/null)"; fi

run_x E21 aliasrep "$SPEC_OK
$REN_CALC
$ALIAS" "$INIT" "$WSPEC" "$ECALC" "$RES21"
assert_eq "G1 alias kept but report.js still calls divide: every call site is renamed FAIL" "FAIL" "$(e_state E21 "$K_SITES")"

run_x E21 olddef "$SPEC_OK
$REN_REP
printf \"%s\n\" \"function safeDivide(a,b){return divide(a,b)}\" \"module.exports.safeDivide = safeDivide;\" >> src/calc.js" "$INIT" "$WSPEC" "$EREP" "$RES21"
assert_eq "G1 the old definition function divide( is kept (only a wrapper added): FAIL" "FAIL" "$(e_state E21 "$K_SITES")"

run_x E21 callleft "$SPEC_OK
$REN_ALL
printf \"%s\n\" \"const divide = safeDivide;\" \"function half(x) { return divide (x, 2); }\" >> src/calc.js" "$INIT" "$WSPEC" "$ECALC" "$EREP" "$RES21"
assert_eq "G1 a call divide (x, 2) left in calc.js next to the alias: FAIL" "FAIL" "$(e_state E21 "$K_SITES")"

run_x E21 reprename "$SPEC_OK
$REN_CALC
node -e \"const fs=require('fs');const f='src/report.js';fs.writeFileSync(f,fs.readFileSync(f,'utf8').replace('return divide(','return safeDivide('))\"" "$INIT" "$WSPEC" "$ECALC" "$EREP" "$RES21"
assert_eq "G1 report.js still imports the word divide (only the call renamed): FAIL" "FAIL" "$(e_state E21 "$K_SITES")"

t_summary
