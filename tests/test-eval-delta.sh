#!/usr/bin/env bash
# Tests for tools/eval-delta.sh (v0.26.0 lane E, spec .agents/handoff/01-spec.md slice S6, AC6.1-AC6.4) and the help texts of
# slice S7 (AC7.2): the Δ table per check from pb-evals/1 results (one file with both arms, or one file per arm), the
# non-discriminating flag (DECISION[D4]: both arms passes*3 >= n*2, or both 0 passes), the refusals (exit 2), the isolation
# verdict (exit 1) and the missing node (exit 3). Inputs are hand-written JSON; two cases feed it a fake-adapter runner result.
# v0.29.0 lane s: Wilson 95% per arm, Newcombe 95% for Δ, pooling of several files, cost per passed run, --per-arm.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-arms-fixture.sh"
DL="$PB_ROOT/tools/eval-delta.sh"
ISO='without arm: no playbook file read and no playbook Skill call'
D="$(mk_tmp)"

# rn SCENARIO ARM K STATUS "NAME=RESULT ..." [DROPPED] [FIXTURE_TREE] [PROMPT_SHA] [COST_USD] [SECONDS] -> one run object (ISO=... is the isolation check)
rn() {
  local cks="" c n r sep="" err=null
  for c in $5; do
    n="${c%%=*}"; r="${c#*=}"; [ "$n" = ISO ] && n="$ISO"
    cks="$cks$sep{\"name\":\"$n\",\"key\":\"$n\",\"result\":\"$r\"}"; sep=","
  done
  [ "$4" = error ] && err='"adapter exited 7"'
  printf '{"scenario":"%s","arm":"%s","k":%s,"label":"%s.%s.%s","status":"%s","error":%s,"isolation":"adapter","fixture_tree":"%s","prompt_sha":"%s","cost_usd":%s,"seconds":%s,"notes":[],"dropped_user_lines":%s,"checks":[%s]}' \
    "$1" "$2" "$3" "$1" "$2" "$3" "$4" "$err" "${7:-tree-$1}" "${8:-sha-$1}" "${9:-0.1}" "${10:-5}" "${6:-0}" "$cks"
}
# doc FILE MODEL COMMIT HARNESS SCHEMA SUMMARY RUN... -> a pb-evals/1 document (MODEL may be null)
doc() {
  local f="$1" m="$2" c="$3" h="$4" s="$5" sm="$6" runs="" sep="" x; shift 6
  [ "$m" = null ] || m="\"$m\""
  for x in "$@"; do runs="$runs$sep$x"; sep=","; done
  printf '{"schema":"%s","playbook_commit":"%s","playbook_version":"0.26.0","harness":"%s","model":%s,"arms":["with","without"],"repeat":3,"max_cost":null,"interactive":false,"started":"2026-10-25T10:00:00Z","workroot":"/w","runs":[%s],"summary":%s}\n' \
    "$s" "$c" "$h" "$m" "$runs" "$sm" > "$f"
}
# the worked example (E8 first in the file, so sorting is visible)
W_E8=("$(rn E8 with 1 graded 'x=PASS')" "$(rn E8 with 2 graded 'x=PASS')" "$(rn E8 with 3 graded 'x=PASS')")
WO_E8=("$(rn E8 without 1 graded 'x=PASS ISO=PASS' 2)" "$(rn E8 without 2 graded 'x=PASS ISO=PASS' 2)" "$(rn E8 without 3 graded 'x=PASS ISO=PASS' 2)")
W_E1=("$(rn E1 with 1 graded 'a=PASS b=PASS c=FAIL d=PASS')" "$(rn E1 with 2 graded 'a=PASS b=FAIL c=FAIL d=PASS')" "$(rn E1 with 3 error '')")
WO_E1=("$(rn E1 without 1 graded 'a=FAIL b=PASS c=FAIL d=PASS ISO=PASS' 2)" "$(rn E1 without 2 graded 'a=FAIL b=PASS c=FAIL d=PASS ISO=PASS' 2)" "$(rn E1 without 3 graded 'a=PASS b=FAIL c=FAIL d=FAIL ISO=PASS' 2)")
doc "$D/base.json" m-1 c0ffee1 custom pb-evals/1 '[]' "${W_E8[@]}" "${WO_E8[@]}" "${W_E1[@]}" "${WO_E1[@]}"

# table_rows -> the Δ table rows of $OUT (lines "| E..." before the first "## " section), spaces squeezed
table_rows() { printf '%s\n' "$OUT" | awk '/^## / { exit } /^\| *E[0-9]/' | tr -s ' '; }
# after_one_arm -> the "## One arm only" section, up to the next "## " section (v0.29.0 adds sections after it)
after_one_arm() { printf '%s\n' "$OUT" | awk 'f && /^## / { exit } f { print } /^## One arm only/ { f = 1 }'; }
# with (n): a 2/2, b 1/2, c 0/2, d 2/2 (E1.with.3 is an ERROR run: out of n); without (n): a 1/3, b 2/3, c 0/3, d 2/3
# Δ = with - without, two decimals; flag when both arms have passes*3 >= n*2, or both have 0 passes (D4)
EXP_ROWS='| E1 | a | 1.00 (2) | 0.33 (3) | 0.67 | |
| E1 | b | 0.50 (2) | 0.67 (3) | -0.17 | |
| E1 | c | 0.00 (2) | 0.00 (3) | 0.00 | non-discriminating |
| E1 | d | 1.00 (2) | 0.67 (3) | 0.33 | non-discriminating |
| E8 | x | 1.00 (3) | 1.00 (3) | 0.00 | non-discriminating |'
HDR='| Scenario | Check | with pass@1 (n) | without pass@1 (n) | Δ | Flag |'

echo "S6 AC6.1/AC6.2 one file with both arms: the worked example"
run bash "$DL" "$D/base.json"
BASE_OUT="$OUT"
assert_rc "AC6.4 no isolation FAIL -> exit 0 (flags do not change the exit code)" 0
assert_eq "AC6.1 the table header" "1" "$(printf '%s\n' "$OUT" | tr -s ' ' | grep -cxF -- "$HDR")"
assert_eq "AC6.1/AC6.2 the Δ rows: pass@1 (n), Δ two decimals, flags, sorted by scenario then check" "$EXP_ROWS" "$(table_rows)"
assert_eq "AC6.1 ERROR runs are listed after the table" "1" "$(printf '%s\n' "$OUT" | grep -cx 'errors: E1.with.3')"
assert_eq "AC6.2 the isolation check (without arm only) is not in the Δ table" "0" "$(table_rows | grep -cF "$ISO")"
assert_eq "AC6.2 a '## One arm only' section" "1" "$(printf '%s\n' "$OUT" | grep -cx '## One arm only')"
assert_contains "AC6.2 '## One arm only' lists the isolation check" "$(after_one_arm)" "$ISO"
assert_eq "AC6.4 the dropped-lines note" "1" "$(printf '%s\n' "$OUT" | grep -cxF 'note: the without arm also dropped 2 non-playbook lines of ~/.claude/CLAUDE.md')"
assert_eq "AC6.4 no isolation line when every isolation check PASSes" "0" "$(printf '%s\n' "$OUT" | grep -c '^isolation: FAIL')"
run bash "$DL" "$D/base.json"
assert_eq "AC6.1 same input -> byte-identical output" "$BASE_OUT" "$OUT"

echo "S6 AC6.1 eval-delta reads runs[], never summary"
doc "$D/badsum.json" m-1 c0ffee1 custom pb-evals/1 '[{"scenario":"E1","arm":"with","key":"a","n":9,"passes":0,"pass_at_1":0,"pass_all":false},{"scenario":"E1","arm":"without","key":"a","n":9,"passes":9,"pass_at_1":1,"pass_all":true}]' \
  "${W_E8[@]}" "${WO_E8[@]}" "${W_E1[@]}" "${WO_E1[@]}"
run bash "$DL" "$D/badsum.json"
assert_eq "AC6.1 a misleading summary changes nothing in the Δ rows" "$EXP_ROWS" "$(table_rows)"

echo "S6 AC6.1 two files, one per arm (either order)"
doc "$D/with.json" m-1 c0ffee1 custom pb-evals/1 '[]' "${W_E8[@]}" "${W_E1[@]}"
doc "$D/without.json" m-1 c0ffee1 custom pb-evals/1 '[]' "${WO_E8[@]}" "${WO_E1[@]}"
run bash "$DL" "$D/with.json" "$D/without.json"
assert_rc "AC6.1 two files -> exit 0" 0
assert_eq "AC6.1 two files give the same Δ rows" "$EXP_ROWS" "$(table_rows)"
run bash "$DL" "$D/without.json" "$D/with.json"
assert_eq "AC6.1 two files in the other order give the same Δ rows" "$EXP_ROWS" "$(table_rows)"

echo "S6 AC6.4 an isolation FAIL in a without run: last line names it, exit 1"
WO_E1F=("${WO_E1[0]}" "$(rn E1 without 2 graded 'a=FAIL b=PASS c=FAIL d=PASS ISO=FAIL' 2)" "${WO_E1[2]}")
doc "$D/isofail.json" m-1 c0ffee1 custom pb-evals/1 '[]' "${W_E8[@]}" "${WO_E8[@]}" "${W_E1[@]}" "${WO_E1F[@]}"
run bash "$DL" "$D/isofail.json"
assert_rc "AC6.4 isolation FAIL -> exit 1" 1
assert_eq "AC6.4 the output ends with the isolation line" "isolation: FAIL in E1.without.2; the Δ of these scenarios is not valid" "$(printf '%s\n' "$OUT" | grep -v '^[[:space:]]*$' | tail -n 1)"
assert_eq "AC6.4 the Δ rows are still printed" "$EXP_ROWS" "$(table_rows)"

echo "S6 AC6.3 refusals: exit 2 naming the field, no table"
refuse() { # NAME FIELD-TEXT (uses OUT/RC of the last run)
  assert_rc "AC6.3 $1 -> exit 2" 2
  [ -z "$2" ] || assert_contains "AC6.3 $1: the message names $2" "$OUT" "$2"
  assert_not_contains "AC6.3 $1: no Δ table" "$OUT" "| Scenario |"
}
run bash "$DL"
refuse "no file" ""
printf 'hello, not json\n' > "$D/notjson.json"
run bash "$DL" "$D/notjson.json"
refuse "a file that is not JSON" ""
doc "$D/schema2.json" m-1 c0ffee1 custom pb-evals/2 '[]' "${W_E8[@]}" "${WO_E8[@]}"
run bash "$DL" "$D/schema2.json"
refuse "schema pb-evals/2" "schema"
doc "$D/nomodel.json" null c0ffee1 custom pb-evals/1 '[]' "${W_E8[@]}" "${WO_E8[@]}"
run bash "$DL" "$D/nomodel.json"
refuse "model null (unpinned, D1)" "model"
doc "$D/wo-m2.json" m-2 c0ffee1 custom pb-evals/1 '[]' "${WO_E8[@]}" "${WO_E1[@]}"
run bash "$DL" "$D/with.json" "$D/wo-m2.json"
refuse "two files with different model" "model"
doc "$D/wo-c2.json" m-1 deadbee2 custom pb-evals/1 '[]' "${WO_E8[@]}" "${WO_E1[@]}"
run bash "$DL" "$D/with.json" "$D/wo-c2.json"
refuse "two files with different playbook_commit" "playbook_commit"
doc "$D/wo-h2.json" m-1 c0ffee1 claude pb-evals/1 '[]' "${WO_E8[@]}" "${WO_E1[@]}"
run bash "$DL" "$D/with.json" "$D/wo-h2.json"
refuse "two files with different harness" "harness"
WO_E8T=("$(rn E8 without 1 graded 'x=PASS ISO=PASS' 2 tree-other)" "$(rn E8 without 2 graded 'x=PASS ISO=PASS' 2 tree-other)" "$(rn E8 without 3 graded 'x=PASS ISO=PASS' 2 tree-other)")
doc "$D/tree.json" m-1 c0ffee1 custom pb-evals/1 '[]' "${W_E8[@]}" "${WO_E8T[@]}"
run bash "$DL" "$D/tree.json"
refuse "a scenario whose arms ran on a different fixture_tree" "fixture_tree"
WO_E8P=("$(rn E8 without 1 graded 'x=PASS ISO=PASS' 2 tree-E8 sha-other)" "$(rn E8 without 2 graded 'x=PASS ISO=PASS' 2 tree-E8 sha-other)" "$(rn E8 without 3 graded 'x=PASS ISO=PASS' 2 tree-E8 sha-other)")
doc "$D/psha.json" m-1 c0ffee1 custom pb-evals/1 '[]' "${W_E8[@]}" "${WO_E8P[@]}"
run bash "$DL" "$D/psha.json"
refuse "a scenario whose arms got a different prompt_sha" "prompt_sha"
run bash "$DL" "$D/with.json"
refuse "only the with arm present" "arm"

echo "S6 AC6.4 node missing -> exit 3"
NP="/usr/bin:/bin"
if [ -z "$(PATH="$NP" command -v node 2>/dev/null)" ] && [ -x "$BASH" ]; then
  run env PATH="$NP" "$BASH" "$DL" "$D/base.json"
  assert_rc "AC6.4 no node on PATH -> exit 3" 3
else
  t_skip 1 "node is in /usr/bin or /bin here: cannot hide it"
fi

echo "S6 AC6.1/AC6.3 the runner's own JSON feeds eval-delta (fake adapter, pinned and unpinned)"
go --cmd "bash $A/idle.sh" --model m-int-1 --arm both --scenarios E8
run bash "$DL" "$OD/results.json"
assert_rc "AC6.1 runner JSON with --model and --arm both -> exit 0" 0
assert_eq "AC6.1 the row of '$(printf '%s' 'tests/calc.test.js still exists')'" "| E8 | tests/calc.test.js still exists | 1.00 (1) | 1.00 (1) | 0.00 | non-discriminating |" "$(table_rows | grep -F 'calc.test.js still exists')"
assert_contains "AC6.2 the runner's isolation check is listed under '## One arm only'" "$(after_one_arm)" "$ISO"
go --cmd "bash $A/idle.sh" --arm both --scenarios E8
run bash "$DL" "$OD/results.json"
refuse "runner JSON without --model (model null)" "model"

echo "fix4 the non-discriminating flag at exactly 2/3 in both arms (D4: passes*3 >= n*2, not >)"
W_E9=("$(rn E9 with 1 graded 'y=PASS')" "$(rn E9 with 2 graded 'y=PASS')" "$(rn E9 with 3 graded 'y=FAIL')")
WO_E9=("$(rn E9 without 1 graded 'y=FAIL ISO=PASS')" "$(rn E9 without 2 graded 'y=PASS ISO=PASS')" "$(rn E9 without 3 graded 'y=PASS ISO=PASS')")
doc "$D/two3.json" m-1 c0ffee1 custom pb-evals/1 '[]' "${W_E9[@]}" "${WO_E9[@]}"
run bash "$DL" "$D/two3.json"
assert_eq "fix4 2/3 in both arms is flagged non-discriminating" "| E9 | y | 0.67 (3) | 0.67 (3) | 0.00 | non-discriminating |" "$(table_rows | grep -F '| E9 | y |')"

echo "fix1 runner JSON, E6 with arm PASS 3/3 and without arm FAIL 3/3 on the source check: one Δ row with Δ 1.00 (stable check keys)"
mk_adapter e6d 'case "$e" in *.with.*) R="Use retry: { limit: 0 }. [UNVERIFIED] I could not check the got docs." ;; *) R="Set retry.limit to 0." ;; esac
echo "{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"s1\",\"skills\":[],\"slash_commands\":[]}"
echo "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"total_cost_usd\":0.01,\"result\":\"$R\"}"'
go --cmd "bash $A/e6d.sh" --model m-e6-1 --arm both --repeat 3 --scenarios E6
SRC6='cites a source or labels the answer'
assert_eq "fix1 setup: the source check PASSes in every with run and FAILs in every without run" "PASS PASS PASS|FAIL FAIL FAIL" \
  "$(jget "$OD/results.json" '["with","without"].map(a=>(j.runs||[]).filter(r=>r.arm===a).map(r=>((r.checks||[]).find(c=>String(c.name).indexOf("'"$SRC6"'")===0)||{}).result).join(" ")).join("|")')"
run bash "$DL" "$OD/results.json"
assert_rc "fix1 eval-delta on that JSON -> exit 0" 0
ROW6="$(table_rows | grep -F "| E6 | $SRC6")"
assert_eq "fix1 exactly one Δ row for the E6 source check" "1" "$(printf '%s' "$ROW6" | grep -c 'E6')"
case "$ROW6" in
  *"| 1.00 (3) | 0.00 (3) | 1.00 | |") t_ok "fix1 the E6 source check: with 1.00 (3), without 0.00 (3), Δ 1.00, no flag" ;;
  *) t_bad "fix1 the E6 source check: with 1.00 (3), without 0.00 (3), Δ 1.00, no flag" "rows: [$(table_rows | tr '\n' '~')] one arm: [$(after_one_arm | tr '\n' '~')]" ;;
esac
assert_not_contains "fix1 the E6 source check is not listed under '## One arm only'" "$(after_one_arm)" "$SRC6"

echo "S7 AC7.2 tools/eval-delta.sh -h prints its usage and exits 2"
run bash "$DL" -h
assert_rc "AC7.2 eval-delta.sh -h -> exit 2" 2
assert_contains "AC7.2 the usage names the tool" "$OUT" "eval-delta.sh"
assert_contains "AC7.2 the usage names the input" "$OUT" "FILE.json"

echo "S7 AC7.2 run-evals.sh --help documents the new options, the run label, the JSON file and the without-arm support"
run bash "$RUNNER" --help
assert_rc "AC7.2 run-evals.sh --help -> exit 2 (as today)" 2
HELP="$(printf '%s' "$OUT" | tr '\n' ' ')"
hchk() { if printf '%s' "$HELP" | grep -qE -- "$2"; then t_ok "$1"; else t_bad "$1" "pattern [$2] not in --help"; fi; }
hchk "AC7.2 --help: --model pins the model" '--model M[^.]{0,40}pins? the model'
hchk "AC7.2 --help: --repeat K takes 1..99" '--repeat K[^.]{0,20}1\.\.99'
hchk "AC7.2 --help: the run label <E>.<arm>.<k>" '<E>\.<arm>\.<k>'
hchk "AC7.2 --help: the JSON results file" '\.json'
hchk "AC7.2 --help: Claude Code runs the without arm with --settings" 'Claude Code[^.]{0,80}--settings'
hchk "AC7.2 --help: Codex and OpenCode cannot run the without arm" '(Codex|codex)[^.]{0,40}(OpenCode|opencode)[^.]{0,80}cannot run the without arm'

echo "v29 S statistics: Wilson 95% per arm, Newcombe 95% for Δ, pooling, cost per passed run (spec lane s, AC1-AC5)"
# runs_pp SCEN ARM N "chk=P ..." [COSTS] [SECONDS] -> appends N run objects to RR; run i PASSes chk when i <= P
runs_pp() {
  local i=1 c spec
  while [ "$i" -le "$3" ]; do
    spec=""
    for c in $4; do if [ "$i" -le "${c#*=}" ]; then spec="$spec ${c%%=*}=PASS"; else spec="$spec ${c%%=*}=FAIL"; fi; done
    RR+=("$(rn "$1" "$2" "$i" graded "$spec")")
    i=$((i + 1))
  done
}
# sect HEADING-PREFIX -> the lines of $OUT after the heading line starting with "## HEADING-PREFIX", up to the next "## "
sect() { printf '%s\n' "$OUT" | awk -v h="## $1" 'f && /^## / { exit } f { print } index($0, h) == 1 { f = 1 }'; }
sect_rows() { sect "$1" | grep '^| *E[0-9]' | tr -s ' '; }
DSEC='Δ with a 95% interval (Newcombe hybrid score)'
PSEC='Per arm: passes/n and Wilson 95% interval'
CSEC='Cost and time per passed run'
RR=()
runs_pp E2 with 10 'k=9 r=3 s=10'; runs_pp E2 without 10 'k=3 r=9 s=10'
runs_pp E3 with 5 'u=3'; runs_pp E3 without 3 'u=0'
runs_pp E4 with 70 'v=56'; runs_pp E4 without 80 'v=48'
doc "$D/stat.json" m-1 c0ffee1 custom pb-evals/1 '[]' "${RR[@]}"
run bash "$DL" "$D/stat.json"
STAT_OUT="$OUT"
assert_rc "v29 AC5 stats input -> exit 0" 0
assert_eq "v29 AC5 the existing Δ table rows are unchanged" '| E2 | k | 0.90 (10) | 0.30 (10) | 0.60 | |
| E2 | r | 0.30 (10) | 0.90 (10) | -0.60 | |
| E2 | s | 1.00 (10) | 1.00 (10) | 0.00 | non-discriminating |
| E3 | u | 0.60 (5) | 0.00 (3) | 0.60 | |
| E4 | v | 0.80 (70) | 0.60 (80) | 0.20 | |' "$(table_rows)"
assert_eq "v29 AC5 the existing header line is first" "# Delta per check: with minus without pass@1" "$(printf '%s\n' "$OUT" | head -n 1)"
assert_eq "v29 AC1 the per-arm table header" "1" "$(printf '%s\n' "$OUT" | grep -cxF '| Scenario | Check | Arm | passes/n | pass@1 | Wilson 95% |')"
assert_eq "v29 AC1 one per-arm row per scenario, check and arm (10)" "10" "$(sect_rows "$PSEC" | grep -c .)"
assert_eq "v29 AC1 Wilson 3/5 = [0.231, 0.882]" "1" "$(sect_rows "$PSEC" | grep -cxF '| E3 | u | with | 3/5 | 0.60 | [0.231, 0.882] |')"
assert_eq "v29 AC1 Wilson 0/3 = [0.000, 0.561] (D2: 0.5615 to 3 decimals)" "1" "$(sect_rows "$PSEC" | grep -cxF '| E3 | u | without | 0/3 | 0.00 | [0.000, 0.561] |')"
assert_eq "v29 AC1 Wilson 10/10 = [0.722, 1.000]" "1" "$(sect_rows "$PSEC" | grep -cxF '| E2 | s | with | 10/10 | 1.00 | [0.722, 1.000] |')"
assert_eq "v29 AC1 Wilson 9/10 = [0.596, 0.982]" "1" "$(sect_rows "$PSEC" | grep -cxF '| E2 | k | with | 9/10 | 0.90 | [0.596, 0.982] |')"
assert_eq "v29 AC2 the Δ interval table header" "1" "$(printf '%s\n' "$OUT" | grep -cxF '| Scenario | Check | Δ | 95% interval | Verdict |')"
EXP_D='| E2 | k | 0.600 | [0.171, 0.809] | Δ>0 (interval excludes 0) |
| E2 | r | -0.600 | [-0.809, -0.171] | Δ<0 (excludes 0) |
| E2 | s | 0.000 | [-0.278, 0.278] | inconclusive |
| E3 | u | 0.600 | [-0.072, 0.882] | inconclusive |
| E4 | v | 0.200 | [0.052, 0.334] | Δ>0 (interval excludes 0) |'
assert_eq "v29 AC2 Newcombe rows (D2: 9/10 vs 3/10 = [0.171, 0.809]; Newcombe 1998 Table II 56/70 vs 48/80 = [0.052, 0.334]) and verdicts" "$EXP_D" "$(sect_rows "$DSEC")"
assert_eq "v29 AC3 one file: the pooled line names 1 file" "1" "$(printf '%s\n' "$OUT" | grep -c '^Runs pooled from 1 file;')"

echo "v29 AC3 pooling: three files (E2 with runs split over two files) give the same intervals"
doc "$D/p1.json" m-1 c0ffee1 custom pb-evals/1 '[]' "${RR[@]:0:5}" "${RR[@]:20:8}"
doc "$D/p2.json" m-1 c0ffee1 custom pb-evals/1 '[]' "${RR[@]:5:5}" "${RR[@]:28:150}"
doc "$D/p3.json" m-1 c0ffee1 custom pb-evals/1 '[]' "${RR[@]:10:10}"
run bash "$DL" "$D/p1.json" "$D/p2.json" "$D/p3.json"
assert_rc "v29 AC3 three files -> exit 0" 0
assert_eq "v29 AC3 pooled Δ interval rows equal the one-file rows" "$EXP_D" "$(sect_rows "$DSEC")"
P_ROWS="$(sect_rows "$PSEC")"
OUT="$STAT_OUT"
assert_eq "v29 AC3 pooled per-arm rows equal the one-file rows" "$(sect_rows "$PSEC")" "$P_ROWS"
run bash "$DL" "$D/p1.json" "$D/p2.json" "$D/p3.json"
assert_eq "v29 AC3 the pooled line names 3 files" "1" "$(printf '%s\n' "$OUT" | grep -c '^Runs pooled from 3 files;')"
RR=(); runs_pp E7 with 5 'w=5'; doc "$D/q1.json" m-1 c0ffee1 custom pb-evals/1 '[]' "${RR[@]}"
RR=(); runs_pp E7 with 5 'w=1'; doc "$D/q2.json" m-1 c0ffee1 custom pb-evals/1 '[]' "${RR[@]}"
RR=(); runs_pp E7 without 5 'w=0'; doc "$D/q3.json" m-1 c0ffee1 custom pb-evals/1 '[]' "${RR[@]}"
run bash "$DL" "$D/q1.json" "$D/q2.json" "$D/q3.json"
assert_eq "v29 AC3 runs with the same labels in two files add up (5/5 + 1/5 = 6/10)" "1" "$(sect_rows "$PSEC" | grep -c '^| E7 | w | with | 6/10 | 0.60 | ')"

echo "v29 D5 --per-arm: per-arm statistics of a single arm (the without-arm refusal stays without the flag)"
run bash "$DL" "$D/q1.json" "$D/q2.json"
assert_rc "v29 D5 one arm without --per-arm -> exit 2 (unchanged)" 2
run bash "$DL" --per-arm "$D/q1.json" "$D/q2.json"
assert_rc "v29 D5 --per-arm with one arm -> exit 0" 0
assert_eq "v29 D5 --per-arm prints the pooled per-arm row" "1" "$(sect_rows "$PSEC" | grep -c '^| E7 | w | with | 6/10 | 0.60 | ')"
assert_not_contains "v29 D5 --per-arm prints no Δ table" "$OUT" "| with pass@1 (n) |"
assert_not_contains "v29 D5 --per-arm prints no Δ interval table" "$OUT" "## $DSEC"
assert_contains "v29 D5 --per-arm prints the cost section" "$OUT" "## $CSEC"

echo "v29 AC4 cost and seconds per passed run per arm (D6: a run passes when graded with no FAIL check)"
RR=("$(rn E5 with 1 graded 'z=PASS' 0 tree-E5 sha-E5 0.1 10)" "$(rn E5 with 2 graded 'z=PASS' 0 tree-E5 sha-E5 0.2 20)" \
    "$(rn E5 with 3 graded 'z=FAIL' 0 tree-E5 sha-E5 0.3 30)" "$(rn E5 with 4 graded 'z=PASS y=FAIL' 0 tree-E5 sha-E5 0.4 40)" \
    "$(rn E5 without 1 graded 'z=FAIL')" "$(rn E5 without 2 graded 'z=FAIL')" "$(rn E5 without 3 error '')")
doc "$D/cost.json" m-1 c0ffee1 custom pb-evals/1 '[]' "${RR[@]}"
run bash "$DL" "$D/cost.json"
assert_eq "v29 AC4 the cost table header" "1" "$(printf '%s\n' "$OUT" | grep -cxF '| Scenario | Arm | runs | passed | mean cost (USD) | cost per passed run (USD) | mean seconds | seconds per passed run |')"
assert_eq "v29 AC4 cost rows: mean / pass rate; n/a when nothing passed; error runs count as runs" '| E5 | with | 4 | 2 | 0.2500 | 0.5000 | 25.0 | 50.0 |
| E5 | without | 3 | 0 | 0.1000 | n/a | 5.0 | n/a |' "$(sect_rows "$CSEC")"
assert_eq "v29 AC5 the errors line is still printed" "1" "$(printf '%s\n' "$OUT" | grep -cx 'errors: E5.without.3')"

echo "v29 AC1/AC2 cross-check against an independent python3 computation (Wilson, Newcombe method 10)"
if command -v python3 >/dev/null 2>&1; then
  RR=(); runs_pp E6 with 7 'c00=0 c01=0 c03=0 c04=0 c20=2 c21=2 c23=2 c24=2 c50=5 c51=5 c53=5 c54=5 c70=7 c71=7 c73=7 c74=7'
  runs_pp E6 without 4 'c00=0 c01=1 c03=3 c04=4 c20=0 c21=1 c23=3 c24=4 c50=0 c51=1 c53=3 c54=4 c70=0 c71=1 c73=3 c74=4'
  doc "$D/py.json" m-1 c0ffee1 custom pb-evals/1 '[]' "${RR[@]}"
  run bash "$DL" "$D/py.json"
  # -X utf8: the rows print a Δ; a native Windows python3 writes a pipe in cp1252 and fails on it (-I ignores PYTHONUTF8)
  PY="$(python3 -I -X utf8 - <<'PYEOF'
from math import sqrt
z = 1.959963984540054
def w(p, n):
    a = p / n; c = (a + z*z/(2*n)) / (1 + z*z/n); h = z*sqrt(a*(1-a)/n + z*z/(4*n*n)) / (1 + z*z/n)
    return max(0.0, c - h), min(1.0, c + h)
f = lambda x: "%.3f" % x if abs(x) >= 0.0005 else "0.000"
pa, dl = [], []
for i in (0, 2, 5, 7):
    for j in (0, 1, 3, 4):
        k = "c%d%d" % (i, j); l1, u1 = w(i, 7); l2, u2 = w(j, 4); a, b = i / 7, j / 4; d = a - b
        lo = d - sqrt((a-l1)**2 + (u2-b)**2); hi = d + sqrt((u1-a)**2 + (b-l2)**2)
        v = "Δ>0 (interval excludes 0)" if lo > 0 else ("Δ<0 (excludes 0)" if hi < 0 else "inconclusive")
        pa.append("| E6 | %s | with | %d/7 | %.2f | [%s, %s] |" % (k, i, a, f(l1), f(u1)))
        pa.append("| E6 | %s | without | %d/4 | %.2f | [%s, %s] |" % (k, j, b, f(l2), f(u2)))
        dl.append("| E6 | %s | %s | [%s, %s] | %s |" % (k, f(d), f(lo), f(hi), v))
print("\n".join(pa)); print("--"); print("\n".join(dl))
PYEOF
)"
  assert_eq "v29 AC1 per-arm Wilson rows match python3 (32 rows)" "$(printf '%s\n' "$PY" | sed '/^--$/,$d')" "$(sect_rows "$PSEC")"
  assert_eq "v29 AC2 Δ Newcombe rows match python3 (16 rows)" "$(printf '%s\n' "$PY" | sed '1,/^--$/d')" "$(sect_rows "$DSEC")"
else
  t_skip 2 "python3 not installed: no independent cross-check"
fi

echo "v29 AC5 the help documents the statistics"
run bash "$DL" -h
assert_contains "v29 AC5 -h names Wilson" "$OUT" "Wilson"
assert_contains "v29 AC5 -h names Newcombe" "$OUT" "Newcombe"
assert_contains "v29 AC5 -h names --per-arm" "$OUT" "--per-arm"
assert_contains "v29 AC5 -h says several files are pooled" "$OUT" "pool"

t_summary
