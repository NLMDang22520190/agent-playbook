#!/usr/bin/env bash
# Tests for tools/eval-delta.sh (v0.26.0 lane E, spec .agents/handoff/01-spec.md slice S6, AC6.1-AC6.4) and the help texts of
# slice S7 (AC7.2): the Δ table per check from pb-evals/1 results (one file with both arms, or one file per arm), the
# non-discriminating flag (DECISION[D4]: both arms passes*3 >= n*2, or both 0 passes), the refusals (exit 2), the isolation
# verdict (exit 1) and the missing node (exit 3). Inputs are hand-written JSON; two cases feed it a fake-adapter runner result.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-arms-fixture.sh"
DL="$PB_ROOT/tools/eval-delta.sh"
ISO='without arm: no playbook file read and no playbook Skill call'
D="$(mk_tmp)"

# rn SCENARIO ARM K STATUS "NAME=RESULT ..." [DROPPED] [FIXTURE_TREE] [PROMPT_SHA] -> one run object (ISO=... is the isolation check)
rn() {
  local cks="" c n r sep="" err=null
  for c in $5; do
    n="${c%%=*}"; r="${c#*=}"; [ "$n" = ISO ] && n="$ISO"
    cks="$cks$sep{\"name\":\"$n\",\"key\":\"$n\",\"result\":\"$r\"}"; sep=","
  done
  [ "$4" = error ] && err='"adapter exited 7"'
  printf '{"scenario":"%s","arm":"%s","k":%s,"label":"%s.%s.%s","status":"%s","error":%s,"isolation":"adapter","fixture_tree":"%s","prompt_sha":"%s","cost_usd":0.1,"seconds":5,"notes":[],"dropped_user_lines":%s,"checks":[%s]}' \
    "$1" "$2" "$3" "$1" "$2" "$3" "$4" "$err" "${7:-tree-$1}" "${8:-sha-$1}" "${6:-0}" "$cks"
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

# table_rows -> the Δ table rows of $OUT (lines "| E..." before "## One arm only"), spaces squeezed
table_rows() { printf '%s\n' "$OUT" | awk '/^## One arm only/ { exit } /^\| *E[0-9]/' | tr -s ' '; }
after_one_arm() { printf '%s\n' "$OUT" | awk 'f { print } /^## One arm only/ { f = 1 }'; }
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

t_summary
