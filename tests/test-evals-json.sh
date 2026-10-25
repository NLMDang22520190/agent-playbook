#!/usr/bin/env bash
# Tests for the JSON results of evals/run-evals.sh (v0.26.0 lane E, spec .agents/handoff/01-spec.md slice S5, AC5.1-AC5.5 and
# AC8.3): the schema pb-evals/1 file next to the md, written by pbh_results_json, the statistics of pbh_stats (pass@1, pass^K,
# n, ERROR runs out of the denominators, cost and time mean and sample sd), the fixture tree and prompt hashes, the stable
# check keys, and the md section "## pass@1 and pass^K". Never calls a real harness: --cmd fake adapters, a stand-in HOME.
# Contract read by this suite (not spelled out by the spec, see 02-tests-S4-7.md Q1/Q2):
#   pbh_results_json NDJSON OUT: line 1 of NDJSON = the top-level fields (no runs, no summary), each next line = one run;
#   OUT gets the full document with schema, runs (input order) and summary.
#   pbh_stats FILE: FILE is a pb-evals/1 document; prints its summary (a JSON array) on stdout.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-arms-fixture.sh"
LIBH="$PB_ROOT/evals/lib-harness.sh"
ISO='without arm: no playbook file read and no playbook Skill call'
CK='tests/calc.test.js still exists'

pbh() { run bash -c 'set -u; . "$0" || exit 99; eval "$1"' "$LIBH" "$1"; }
# near FILE EXPR WANT -> "ok" when the number EXPR (j = the JSON of FILE) is within 1e-6 of WANT, else what it is
near() { jget "$1" "(function(){const v=($2);return (typeof v===\"number\" && Math.abs(v-($3))<1e-6) ? \"ok\" : \"got \"+JSON.stringify(v)})()"; }
# summary item of (scenario, arm, key) and the cost/time item of (scenario, arm), as JS expressions over j
SI() { printf '((j.summary||[]).find(e => e.scenario==="%s" && e.arm==="%s" && e.key==="%s")||{})' "$1" "$2" "$3"; }
SC() { printf '((j.summary||[]).find(e => e.scenario==="%s" && e.arm==="%s" && ("cost_mean" in e))||{})' "$1" "$2"; }

# ================= direct: pbh_results_json and pbh_stats on a worked example =================
echo "S5 AC5.4/AC8.1 pbh_results_json and pbh_stats: worked example (E8 K=3 both arms, E3 with arm)"
D="$(mk_tmp)"; ND="$D/runs.ndjson"; OJ="$D/out.json"
rj() { # SCENARIO ARM K STATUS COST SECONDS CHECKS-JSON
  local err=null; [ "$4" = error ] && err='"adapter exited 7"'
  printf '{"scenario":"%s","arm":"%s","k":%s,"label":"%s.%s.%s","status":"%s","error":%s,"isolation":"adapter","fixture_tree":"tree-%s","prompt_sha":"sha-%s","cost_usd":%s,"seconds":%s,"notes":[],"dropped_user_lines":0,"checks":[%s]}\n' \
    "$1" "$2" "$3" "$1" "$2" "$3" "$4" "$err" "$1" "$1" "$5" "$6" "$7"
}
ck() { printf '{"name":"%s","key":"%s","result":"%s"}' "$1" "$2" "$3"; }
{ printf '%s\n' '{"playbook_commit":"c0ffee1","playbook_version":"0.26.0","harness":"custom","model":"m-1","arms":["with","without"],"repeat":3,"max_cost":null,"interactive":false,"started":"2026-10-25T10:00:00Z","workroot":"/w"}'
  rj E8 with 1 graded 0.1 10 "$(ck c1 c1 PASS),$(ck 'q (asked=0)' q PASS),$(ck m1 m1 MANUAL)"
  rj E8 without 1 graded 0.1 30 "$(ck c1 c1 PASS),$(ck m1 m1 MANUAL)"
  rj E8 with 2 graded 0.2 20 "$(ck c1 c1 PASS),$(ck 'q (asked=1)' q FAIL),$(ck m1 m1 MANUAL)"
  rj E8 without 2 graded 0.2 30 "$(ck c1 c1 FAIL),$(ck m1 m1 MANUAL)"
  rj E8 with 3 error null null ""
  rj E8 without 3 graded 0.6 60 "$(ck c1 c1 FAIL),$(ck m1 m1 MANUAL)"
  rj E3 with 1 graded 0.5 12 "$(ck c1 c1 PASS)"
  rj E3 with 2 skipped null null ""
  rj E3 with 3 error null null ""
} > "$ND"
pbh "pbh_results_json '$ND' '$OJ'"
assert_rc "AC8.1 pbh_results_json NDJSON OUT -> 0" 0
assert_eq "AC5.1 OUT is schema pb-evals/1" "pb-evals/1" "$(jget "$OJ" 'j.schema')"
assert_eq "AC5.1 the top-level fields come from the first NDJSON line (model, repeat, harness)" 'm-1 3 custom' "$(jget "$OJ" 'j.model+" "+j.repeat+" "+j.harness')"
assert_eq "AC5.2 runs keep the input order" "E8.with.1 E8.without.1 E8.with.2 E8.without.2 E8.with.3 E8.without.3 E3.with.1 E3.with.2 E3.with.3" "$(jget "$OJ" '(j.runs||[]).map(r => r.label).join(" ")')"
# E8 with, key c1: PASS, PASS, ERROR -> n 2 (the ERROR run is out of the denominator), pass@1 1, pass^K true, not complete
S="$(SI E8 with c1)"
assert_eq "AC5.4 E8/with/c1: n=2 passes=2 errors=1 skipped=0 manual=0" "2 2 1 0 0" "$(jget "$OJ" "[$S.n,$S.passes,$S.errors,$S.skipped,$S.manual].join(\" \")")"
assert_eq "AC5.4 E8/with/c1: pass_at_1 = 2/2 = 1" "ok" "$(near "$OJ" "$S.pass_at_1" 1)"
assert_eq "AC5.4 E8/with/c1: pass_all (pass^K) true, complete false (n 2 < K 3)" "true false" "$(jget "$OJ" "$S.pass_all+\" \"+$S.complete")"
# key q groups "q (asked=0)" PASS and "q (asked=1)" FAIL
S="$(SI E8 with q)"
assert_eq "AC5.3/AC5.4 E8/with/q groups two names by key: n=2 passes=1" "2 1" "$(jget "$OJ" "[$S.n,$S.passes].join(\" \")")"
assert_eq "AC5.4 E8/with/q: pass_at_1 = 1/2" "ok" "$(near "$OJ" "$S.pass_at_1" 0.5)"
assert_eq "AC5.4 E8/with/q: pass_all false" "false" "$(jget "$OJ" "$S.pass_all")"
# key m1: MANUAL only -> n 0, pass_at_1 null, pass_all null, manual 2
S="$(SI E8 with m1)"
assert_eq "AC5.4 E8/with/m1 (MANUAL only): n=0, pass_at_1 null, pass_all null, manual=2" "0 null null 2" "$(jget "$OJ" "[$S.n,JSON.stringify($S.pass_at_1),JSON.stringify($S.pass_all),$S.manual].join(\" \")")"
# E8 without, key c1: PASS, FAIL, FAIL -> n 3, pass@1 1/3, pass^K false, complete true
S="$(SI E8 without c1)"
assert_eq "AC5.4 E8/without/c1: n=3 passes=1 errors=0" "3 1 0" "$(jget "$OJ" "[$S.n,$S.passes,$S.errors].join(\" \")")"
assert_eq "AC5.4 E8/without/c1: pass_at_1 = 1/3" "ok" "$(near "$OJ" "$S.pass_at_1" '1/3')"
assert_eq "AC5.4 E8/without/c1: pass_all false, complete true" "false true" "$(jget "$OJ" "$S.pass_all+\" \"+$S.complete")"
# E3 with, key c1: PASS, skipped, ERROR -> n 1, errors 1, skipped 1
S="$(SI E3 with c1)"
assert_eq "AC5.4 E3/with/c1: n=1 passes=1 errors=1 skipped=1, pass_all true, complete false" "1 1 1 1 true false" "$(jget "$OJ" "[$S.n,$S.passes,$S.errors,$S.skipped,$S.pass_all,$S.complete].join(\" \")")"
# cost and time per (scenario, arm), over runs with a known value, sample sd (n-1), null below 2 values
S="$(SC E8 with)"
assert_eq "AC5.4 E8/with cost_mean = (0.1+0.2)/2 = 0.15" "ok" "$(near "$OJ" "$S.cost_mean" 0.15)"
assert_eq "AC5.4 E8/with cost_sd = sqrt(0.005) = 0.0707107 (sample sd)" "ok" "$(near "$OJ" "$S.cost_sd" 'Math.sqrt(0.005)')"
assert_eq "AC5.4 E8/with seconds_mean = 15, seconds_sd = sqrt(50) = 7.0710678" "ok ok" "$(near "$OJ" "$S.seconds_mean" 15) $(near "$OJ" "$S.seconds_sd" 'Math.sqrt(50)')"
S="$(SC E8 without)"
assert_eq "AC5.4 E8/without cost_mean = 0.9/3 = 0.3, cost_sd = sqrt(0.14/2) = 0.2645751" "ok ok" "$(near "$OJ" "$S.cost_mean" 0.3) $(near "$OJ" "$S.cost_sd" 'Math.sqrt(0.07)')"
assert_eq "AC5.4 E8/without seconds_mean = 40, seconds_sd = sqrt(600/2) = 17.3205081" "ok ok" "$(near "$OJ" "$S.seconds_mean" 40) $(near "$OJ" "$S.seconds_sd" 'Math.sqrt(300)')"
S="$(SC E3 with)"
assert_eq "AC5.4 E3/with: one known value -> cost_mean 0.5, cost_sd null, seconds_mean 12, seconds_sd null" "0.5 null 12 null" "$(jget "$OJ" "[$S.cost_mean,JSON.stringify($S.cost_sd),$S.seconds_mean,JSON.stringify($S.seconds_sd)].join(\" \")")"

echo "S5 AC8.1 pbh_stats FILE prints the summary of a pb-evals/1 document"
node -e 'const fs=require("fs");const j=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));delete j.summary;fs.writeFileSync(process.argv[2],JSON.stringify(j))' "$OJ" "$D/nosum.json" 2>/dev/null
pbh "pbh_stats '$D/nosum.json'"
assert_rc "AC8.1 pbh_stats FILE -> 0" 0
printf '%s' "$OUT" > "$D/stats.json"
assert_eq "AC8.1 pbh_stats prints a JSON array" "true" "$(jget "$D/stats.json" 'Array.isArray(j)')"
assert_eq "AC8.1 pbh_stats: E8/without/c1 n=3 passes=1" "3 1" "$(jget "$D/stats.json" '(function(){const e=j.find(e=>e.scenario==="E8"&&e.arm==="without"&&e.key==="c1")||{};return e.n+" "+e.passes})()')"
assert_eq "AC8.1 pbh_stats: E8/with/c1 errors=1 (ERROR run out of n=2)" "2 1" "$(jget "$D/stats.json" '(function(){const e=j.find(e=>e.scenario==="E8"&&e.arm==="with"&&e.key==="c1")||{};return e.n+" "+e.errors})()')"

# ================= the runner writes the JSON =================
echo "S5 AC5.1/AC5.2 default mode: the runner writes \${OUT%.md}.json and prints json: after results:"
go --cmd "bash $A/idle.sh" --scenarios E8
JF="$OD/results.json"
assert_rc "AC5.1 default mode still exits 0" 0
assert_eq "AC5.1 the line after 'results: <md>' is 'json: \${OUT%.md}.json'" "json: $JF" "$(printf '%s\n' "$OUT" | awk -v r="results: $RES" 'f { print; exit } $0 == r { f = 1 }')"
assert_file "AC5.1 the JSON file exists" "$JF"
assert_eq "AC5.1 schema" "pb-evals/1" "$(jget "$JF" 'j.schema')"
if PC="$(git -C "$PB_ROOT" rev-parse HEAD 2>/dev/null)"; then
  assert_eq "AC5.1 playbook_commit = git HEAD of the runner's repo" "$PC" "$(jget "$JF" 'j.playbook_commit')"
else
  assert_eq "AC5.1 playbook_commit = null outside a git checkout" "null" "$(jget "$JF" 'JSON.stringify(j.playbook_commit)')"
fi
assert_eq "AC5.1 playbook_version = VERSION" "$(tr -d ' \r\n' < "$PB_ROOT/VERSION")" "$(jget "$JF" 'j.playbook_version')"
assert_eq "AC5.1 harness = the run label (custom for --cmd)" "custom" "$(jget "$JF" 'j.harness')"
assert_eq "AC5.1/AC8.3 model unpinned = JSON null" "null" "$(jget "$JF" 'JSON.stringify(j.model)')"
assert_eq "AC5.1 arms [with], repeat 1, max_cost null, interactive false" '["with"] 1 null false' "$(jget "$JF" 'JSON.stringify(j.arms)+" "+j.repeat+" "+JSON.stringify(j.max_cost)+" "+j.interactive')"
assert_eq "AC5.1 started is ISO-8601 UTC" "true" "$(jget "$JF" '/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d+)?Z$/.test(j.started)')"
assert_eq "AC5.1 workroot" "$(physdir "$WR")" "$(jget "$JF" 'j.workroot')"
assert_eq "AC5.1 summary is a list" "true" "$(jget "$JF" 'Array.isArray(j.summary)')"
R0='((j.runs||[])[0]||{})'
assert_eq "AC5.2 one run: scenario E8, arm with, k 1, label E8, status graded, error null" 'E8 with 1 E8 graded null' "$(jget "$JF" "[$R0.scenario,$R0.arm,$R0.k,$R0.label,$R0.status,JSON.stringify($R0.error)].join(\" \")")"
assert_eq "AC5.2 fixture_tree = git rev-parse HEAD^{tree} of the workdir" "$(git -C "$WR/E8" rev-parse 'HEAD^{tree}' 2>/dev/null)" "$(jget "$JF" "$R0.fixture_tree")"
assert_eq "AC5.2 prompt_sha = git hash-object of the .prompt file" "$(git hash-object "$WR/E8.prompt" 2>/dev/null)" "$(jget "$JF" "$R0.prompt_sha")"
assert_eq "AC5.2 cost_usd null when the transcript has no cost" "null" "$(jget "$JF" "JSON.stringify($R0.cost_usd)")"
assert_eq "AC5.2 seconds is a whole number >= 0" "true" "$(jget "$JF" "Number.isInteger($R0.seconds) && $R0.seconds >= 0")"
assert_eq "AC5.2 notes is a list" "true" "$(jget "$JF" "Array.isArray($R0.notes)")"
assert_eq "AC3.4 dropped_user_lines is 0 for a with run" "0" "$(jget "$JF" "JSON.stringify($R0.dropped_user_lines)")"
assert_eq "AC5.2 checks hold {name, key, result} for '$CK' = PASS" "$CK|PASS" "$(jget "$JF" "(function(){const c=($R0.checks||[]).find(c=>c.name===\"$CK\")||{};return c.key+\"|\"+c.result})()")"
assert_eq "AC5.2 every check result is PASS, FAIL or MANUAL" "true" "$(jget "$JF" "($R0.checks||[]).length>0 && ($R0.checks||[]).every(c=>/^(PASS|FAIL|MANUAL)\$/.test(c.result))")"
# every key is pbh_check_key(name)
BADKEY=""; [ -f "$JF" ] || BADKEY="no JSON file"
while IFS= read -r nm; do
  [ -n "$nm" ] || continue
  pbh "pbh_check_key $(printf '%q' "$nm")"; want="$OUT"
  got="$(jget "$JF" "(($R0.checks||[]).find(c=>c.name===$(node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$nm"))||{}).key")"
  [ "$got" = "$want" ] || BADKEY="$BADKEY [$nm: $got != $want]"
done <<EOF
$(jget "$JF" "($R0.checks||[]).map(c=>c.name).join(\"\\n\")")
EOF
assert_eq "AC5.3 every check key equals pbh_check_key(name)" "" "$BADKEY"
assert_eq "AC5.5 default mode: no '## pass@1 and pass^K' section" "0" "$(grep -c '^## pass@1 and pass^K' "$RES" 2>/dev/null || true)"

echo "S5 AC5.1-AC5.5 --model --arm both --repeat 2 --max-cost: runs, hashes, summary, md section"
mk_adapter s5 'case "$e" in
  *.without.2) git rm -q tests/calc.test.js && git -c user.email=a@b.invalid -c user.name=a -c commit.gpgsign=false commit -qm rm ;;
esac
case "$e" in *.with.1) c=0.2 ;; *.with.2) c=0.4 ;; *) c=0.5 ;; esac
echo "{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"s1\",\"skills\":[],\"slash_commands\":[]}"
echo "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"total_cost_usd\":$c,\"result\":\"Done.\"}"'
go --cmd "bash $A/s5.sh" --model m-json-1 --arm both --repeat 2 --max-cost 50 --scenarios E8
JF="$OD/results.json"
assert_rc "AC2.6 a FAIL in the without arm -> exit 1 (the JSON is still written)" 1
assert_eq "AC5.1 model, arms, repeat, max_cost" 'm-json-1 ["with","without"] 2 50' "$(jget "$JF" 'j.model+" "+JSON.stringify(j.arms)+" "+j.repeat+" "+j.max_cost')"
assert_eq "AC5.2 runs: label arm k in run order" "E8.with.1:with:1 E8.without.1:without:1 E8.with.2:with:2 E8.without.2:without:2" "$(jget "$JF" '(j.runs||[]).map(r=>r.label+":"+r.arm+":"+r.k).join(" ")')"
assert_eq "AC5.2 every run has scenario E8 and status graded" "E8:graded" "$(jget "$JF" '[...new Set((j.runs||[]).map(r=>r.scenario+":"+r.status))].join(" ")')"
assert_eq "AC5.2/P1-AC1 fixture_tree is the tree after the setup, before the adapter (same in all 4 runs, also the one that committed)" "$(git -C "$WR/E8.with.1" rev-parse 'HEAD^{tree}' 2>/dev/null)" "$(jget "$JF" '[...new Set((j.runs||[]).map(r=>r.fixture_tree))].join(" ")')"
assert_eq "AC5.2 prompt_sha is the same in both arms (git hash-object of the .prompt)" "$(git hash-object "$WR/E8.with.1.prompt" 2>/dev/null)" "$(jget "$JF" '[...new Set((j.runs||[]).map(r=>r.prompt_sha))].join(" ")')"
assert_eq "AC3.3 isolation: adapter for --cmd runs" "adapter" "$(jget "$JF" '[...new Set((j.runs||[]).map(r=>r.isolation))].join(" ")')"
assert_eq "AC5.2 cost_usd per run" "0.2 0.5 0.4 0.5" "$(jget "$JF" '(j.runs||[]).map(r=>r.cost_usd).join(" ")')"
assert_eq "AC3.4 dropped_user_lines: 0 with, 2 without (stand-in CLAUDE.md has 2 personal lines)" "0 2 0 2" "$(jget "$JF" '(j.runs||[]).map(r=>r.dropped_user_lines).join(" ")')"
assert_eq "AC4.1/AC5.2 the without runs carry the isolation check (PASS), the with runs do not" "none PASS none PASS" "$(jget "$JF" "(j.runs||[]).map(r=>((r.checks||[]).find(c=>c.name===\"$ISO\")||{result:\"none\"}).result).join(\" \")")"
S="$(SI E8 with "$CK")"
assert_eq "AC5.4 E8/with/'$CK': n=2 passes=2 pass_all true complete true errors 0 skipped 0" "2 2 true true 0 0" "$(jget "$JF" "[$S.n,$S.passes,$S.pass_all,$S.complete,$S.errors,$S.skipped].join(\" \")")"
S="$(SI E8 without "$CK")"
assert_eq "AC5.4 E8/without/'$CK': n=2 passes=1 pass_all false complete true" "2 1 false true" "$(jget "$JF" "[$S.n,$S.passes,$S.pass_all,$S.complete].join(\" \")")"
assert_eq "AC5.4 E8/without/'$CK': pass_at_1 = 1/2" "ok" "$(near "$JF" "$S.pass_at_1" 0.5)"
S="$(SC E8 with)"
assert_eq "AC5.4 E8/with cost mean 0.3, sd sqrt(0.02) = 0.1414214" "ok ok" "$(near "$JF" "$S.cost_mean" 0.3) $(near "$JF" "$S.cost_sd" 'Math.sqrt(0.02)')"
S="$(SC E8 without)"
assert_eq "AC5.4 E8/without cost mean 0.5, sd 0" "ok ok" "$(near "$JF" "$S.cost_mean" 0.5) $(near "$JF" "$S.cost_sd" 0)"
assert_eq "AC5.4 E8/with seconds_mean is a number" "number" "$(jget "$JF" "typeof $S.seconds_mean")"
echo "S5 AC5.5 the md section '## pass@1 and pass^K'"
assert_eq "AC5.5 the md has the heading '## pass@1 and pass^K'" "1" "$(grep -cx '## pass@1 and pass^K' "$RES" 2>/dev/null || true)"
assert_eq "AC5.5 the check table header" "1" "$(tr -s ' ' < "$RES" 2>/dev/null | grep -cxF '| Scenario | Arm | Check | pass@1 | pass^K | n |')"
assert_eq "AC5.5 the cost/time table header" "1" "$(tr -s ' ' < "$RES" 2>/dev/null | grep -cxF '| Scenario | Arm | Cost mean ± sd (USD) | Time mean ± sd (s) |')"
ROW="$(tr -s ' ' < "$RES" 2>/dev/null | grep -F "| E8 | without | $CK |" | head -n 1)"
assert_contains "AC5.5 the row E8/without/'$CK' shows pass@1 0.5" "$ROW" "0.5"
case "$ROW" in *"| 2 |") t_ok "AC5.5 the row E8/without/'$CK' ends with n = 2" ;; *) t_bad "AC5.5 the row E8/without/'$CK' ends with n = 2" "row [$ROW]" ;; esac
ROW="$(tr -s ' ' < "$RES" 2>/dev/null | grep -E '^\| E8 \| with \| [0-9]' | head -n 1)"
assert_contains "AC5.5 the cost row of E8/with shows the mean 0.3" "$ROW" "0.3"

echo "S5 AC5.2/AC5.4 an ERROR run and a skipped run in the JSON; --interactive is recorded"
mk_adapter err2 'case "$e" in *.without.2) exit 7 ;; esac; true'
go --cmd "bash $A/err2.sh" --arm both --repeat 2 --interactive --scenarios E8
JF="$OD/results.json"
RE='((j.runs||[]).find(r=>r.label==="E8.without.2")||{})'
assert_eq "AC5.2 the ERROR run: status error, error names the cause, no checks" "error|true|0" "$(jget "$JF" "$RE.status+\"|\"+/adapter exited 7/.test($RE.error)+\"|\"+($RE.checks||[]).length")"
S="$(SI E8 without "$CK")"
assert_eq "AC5.4 E8/without/'$CK': the ERROR run is out of n (n=1 passes=1 errors=1 complete false, pass_all true)" "1 1 1 false true" "$(jget "$JF" "[$S.n,$S.passes,$S.errors,$S.complete,$S.pass_all].join(\" \")")"
assert_eq "AC5.1 interactive true with --interactive" "true" "$(jget "$JF" 'j.interactive')"
mk_adapter c06j "echo '$INIT'
echo '{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"total_cost_usd\":0.6,\"result\":\"Done.\"}'"
go --cmd "bash $A/c06j.sh" --arm both --max-cost 1 --scenarios E8
JF="$OD/results.json"
RS='((j.runs||[]).find(r=>r.label==="E8.without.1")||{})'
assert_eq "AC2.5/AC5.2 the budget-skipped run: status skipped, cost_usd null, no checks" "skipped|null|0" "$(jget "$JF" "$RS.status+\"|\"+JSON.stringify($RS.cost_usd)+\"|\"+($RS.checks||[]).length")"
assert_eq "AC5.1 max_cost 1" "1" "$(jget "$JF" 'j.max_cost')"

t_summary
