#!/usr/bin/env bash
# Tests for scripts/cost.sh (slice S1, AC2; default D3)
. "$(dirname "$0")/lib.sh"
COST="$PB_ROOT/scripts/cost.sh"

H="$(mk_tmp)"
export PLAYBOOK_HOME="$H"
unset PLAYBOOK_HARNESS

# fresh project dir (not inside any repo); cost.tsv location per D3
newp() { P="$(mk_tmp)"; F="$P/.agents/handoff/cost.tsv"; }
cost() { run_in "$P" bash "$COST" "$@"; }
lines() { if [ -f "$F" ]; then wc -l < "$F" | tr -d ' '; else echo 0; fi; }
# cells ROLE_OR_TOTAL_REGEX -> trimmed cells of the first markdown table row whose first cell matches, joined by '|'
cells() {
  printf '%s\n' "$OUT" | awk -F'|' -v pat="$1" '
    { c = $2; gsub(/^[ \t*]+|[ \t*]+$/, "", c) }
    tolower(c) ~ pat && !done {
      s = ""; for (i = 2; i < NF; i++) { x = $i; gsub(/^[ \t*]+|[ \t*]+$/, "", x); s = s (i > 2 ? "|" : "") x }
      print s; done = 1 }'
}
has_cell() { # name "a|b|c" cell
  case "|$2|" in *"|$3|"*) t_ok "$1" ;; *) t_bad "$1" "cell [$3] not in row [$2]" ;; esac
}

echo "cost.sh add"

newp
cost add --role tester --tokens 100 --seconds 10 --model m1 --weight Full --note "first run"
assert_rc "AC2 add valid exits 0" 0
assert_file "AC2 cost.tsv created at .agents/handoff/ (D3)" "$F"
assert_eq "AC2 header + 1 row" "2" "$(lines)"
assert_contains "AC2 header names tokens column" "$(head -n 1 "$F")" "tokens"
assert_contains "AC2 header names role column" "$(head -n 1 "$F")" "role"
ROW="$(tail -n 1 "$F")"
assert_contains "AC2 row has role" "$ROW" "tester"
assert_contains "AC2 row has model" "$ROW" "m1"
assert_contains "AC2 row has note" "$ROW" "first run"
assert_contains "AC2 row has weight" "$ROW" "Full"
# tab-separated, same number of fields as header
HF="$(head -n 1 "$F" | awk -F'\t' '{print NF}')"; RF="$(printf '%s\n' "$ROW" | awk -F'\t' '{print NF}')"
assert_eq "AC2 row has same field count as header (tab-separated)" "$HF" "$RF"
case "$HF" in 1|0|"") t_bad "AC2 file is tab-separated (header has >1 field)" "fields=$HF" ;; *) t_ok "AC2 file is tab-separated (header has >1 field)" ;; esac
# tokens and seconds are whole fields of the row
if printf '%s\n' "$ROW" | awk -F'\t' '{f=0; for(i=1;i<=NF;i++) if($i=="100") f=1; exit !f}'; then t_ok "AC2 tokens stored as own field"; else t_bad "AC2 tokens stored as own field" "$ROW"; fi

cost add --role reviewer --tokens 1000
assert_rc "AC2 add with only required fields (optional missing) exits 0" 0
assert_eq "AC2 second add appends one row" "3" "$(lines)"
assert_eq "AC2 header appears exactly once" "1" "$(grep -c 'tokens' "$F" | head -n 1)"
assert_eq "AC2 no duplicate lines (header not rewritten)" "" "$(sort "$F" | uniq -d)"
assert_eq "AC2 first row preserved after append" "$ROW" "$(sed -n 2p "$F")"
assert_eq "AC2 row without optional fields keeps field count" "$HF" "$(tail -n 1 "$F" | awk -F'\t' '{print NF}')"

newp
cost add --role orchestrator --tokens 0 --seconds 0
assert_rc "AC2 zero tokens and zero seconds accepted" 0
assert_eq "AC2 zero-token row written" "2" "$(lines)"
cost add --role implementer --tokens 5 --weight Lite
assert_rc "AC2 weight Lite accepted" 0
cost add --role implementer --tokens 5 --weight Full
assert_rc "AC2 weight Full accepted" 0
assert_eq "AC2 three valid rows + header" "4" "$(lines)"

echo "cost.sh add: invalid input writes nothing"
newp
bad() { # name args...   -> exit 2 and no file
  local n="$1"; shift
  cost add "$@"
  assert_rc "AC2 $n exits 2" 2
  assert_no_path "AC2 $n writes nothing (no file)" "$F"
}
bad "bad role"               --role janitor --tokens 5
bad "role case-sensitive"    --role Tester --tokens 5
bad "missing role"           --tokens 5
bad "missing tokens"         --role tester
bad "negative tokens"        --role tester --tokens -5
bad "non-integer tokens"     --role tester --tokens 1.5
bad "alpha tokens"           --role tester --tokens abc
bad "empty tokens"           --role tester --tokens ""
bad "negative seconds"       --role tester --tokens 5 --seconds -1
bad "non-integer seconds"    --role tester --tokens 5 --seconds 2.5
bad "bad weight"             --role tester --tokens 5 --weight Heavy
bad "lowercase weight"       --role tester --tokens 5 --weight full
bad "unknown option"         --role tester --tokens 5 --bogus x
bad "note with tab"          --role tester --tokens 5 --note "a	b"
bad "note with newline"      --role tester --tokens 5 --note "a
b"
bad "model with tab"         --role tester --tokens 5 --model "a	b"
bad "model with newline"     --role tester --tokens 5 --model "a
b"

# invalid input after valid data: row count unchanged, existing rows intact
cost add --role tester --tokens 7 --model keep
BEFORE="$(cat "$F")"
cost add --role tester --tokens nope
assert_rc "AC2 invalid add on existing file exits 2" 2
assert_eq "AC2 invalid add leaves existing file byte-identical" "$BEFORE" "$(cat "$F")"
cost add --role tester --tokens 5 --note "x
y"
assert_rc "AC2 newline note on existing file exits 2" 2
assert_eq "AC2 newline note leaves file unchanged" "$BEFORE" "$(cat "$F")"
cost add --role tester --tokens 5 --note "x	y"
assert_eq "AC2 tab note leaves file unchanged" "$BEFORE" "$(cat "$F")"

cost bogus
assert_rc "AC2 unknown subcommand exits 2" 2
cost
assert_rc "AC2 no subcommand exits 2" 2

echo "cost.sh summary"
newp
cost summary
assert_rc "AC2 summary with no data exits 0" 0
assert_contains "AC2 summary with no data prints 'no cost data'" "$OUT" "no cost data"
assert_no_path "AC2 summary does not create the file" "$F"

# header-only file counts as no data
mkdir -p "$P/.agents/handoff"
cost add --role tester --tokens 1
head -n 1 "$F" > "$F.hdr" && mv "$F.hdr" "$F"
cost summary
assert_rc "AC2 summary of header-only file exits 0" 0
assert_contains "AC2 header-only file -> 'no cost data'" "$OUT" "no cost data"

newp
cost add --role tester --tokens 100 --seconds 10 --model m1
cost add --role tester --tokens 250 --seconds 5  --model m2
cost add --role reviewer --tokens 1000 --seconds 60 --model big
cost add --role implementer --tokens 0
cost summary
assert_rc "AC2 summary exits 0" 0
assert_contains "AC2 summary is a markdown table" "$OUT" "|"
assert_contains "AC2 summary has separator row" "$OUT" "---"
T="$(cells '^tester$')"
has_cell "AC2 tester runs = 2"        "$T" "2"
has_cell "AC2 tester tokens = 350"    "$T" "350"
has_cell "AC2 tester seconds = 15"    "$T" "15"
assert_contains "AC2 tester models include m1" "$T" "m1"
assert_contains "AC2 tester models include m2" "$T" "m2"
R="$(cells '^reviewer$')"
has_cell "AC2 reviewer runs = 1"      "$R" "1"
has_cell "AC2 reviewer tokens = 1000" "$R" "1000"
has_cell "AC2 reviewer seconds = 60"  "$R" "60"
assert_contains "AC2 reviewer model" "$R" "big"
assert_not_contains "AC2 reviewer row has no tester model" "$R" "m1"
I="$(cells '^implementer$')"
has_cell "AC2 zero-token role still counted as a run" "$I" "1"
has_cell "AC2 missing seconds counted as 0" "$I" "0"
TOT="$(cells 'total')"
[ -n "$TOT" ] && t_ok "AC2 total row present" || t_bad "AC2 total row present" "$OUT"
has_cell "AC2 total runs = 4"          "$TOT" "4"
has_cell "AC2 total tokens = 1350"     "$TOT" "1350"
has_cell "AC2 total seconds = 75"      "$TOT" "75"
assert_eq "AC2 one row per role present (tester appears once)" "1" "$(printf '%s\n' "$OUT" | grep -c '^| *tester *|')"

# summary is read-only and ignores other projects
BEFORE="$(cat "$F")"
cost summary
assert_eq "AC2 summary does not modify the file" "$BEFORE" "$(cat "$F")"
NEWOLD="$P"; newp
cost summary
assert_contains "AC2 summary is per project (other project has no data)" "$OUT" "no cost data"
P="$NEWOLD"


# --- v0.22.3 AC1: phase, rework and majors (the old cases above stay as they are)
echo "cost.sh v0.22.3 AC1.1: new columns appended at the end"
OLDHDR="$(printf 'date\trole\ttokens\tseconds\tmodel\tweight\tnote')"
OLDHDR10="$(printf 'date\trole\ttokens\tseconds\tmodel\tweight\tnote\tphase\trework\tmajors')"
field() { # N LINE -> tab field N
  printf '%s\n' "$2" | awk -F'\t' -v n="$1" '{ print $n }'
}
newp
cost add --role tester --tokens 100 --seconds 10 --model m1 --weight Full --note "n1" --phase red --rework 2 --majors 3
assert_rc "AC1.1 add with --phase --rework --majors exits 0" 0
HDR="$(head -n 1 "$F")"
assert_eq "AC1.1 the old seven header columns stay first and unchanged" "$OLDHDR" "$(printf '%s\n' "$HDR" | cut -f1-7)"
assert_eq "AC1.1 header column 8 is phase" "phase" "$(field 8 "$HDR")"
assert_eq "AC1.1 header column 9 is rework" "rework" "$(field 9 "$HDR")"
assert_eq "AC1.1 header column 10 is majors" "majors" "$(field 10 "$HDR")"
assert_eq "AC1.1 the header has exactly eleven columns (v0.22.4 adds task)" "11" "$(printf '%s\n' "$HDR" | awk -F'\t' '{print NF}')"
ROW="$(tail -n 1 "$F")"
assert_eq "AC1.1 the row has the same field count as the header (eleven since v0.22.4)" "11" "$(printf '%s\n' "$ROW" | awk -F'\t' '{print NF}')"
assert_eq "AC1.1 the old fields keep their place (role)" "tester" "$(field 2 "$ROW")"
assert_eq "AC1.1 the old fields keep their place (tokens)" "100" "$(field 3 "$ROW")"
assert_eq "AC1.1 the old fields keep their place (note)" "n1" "$(field 7 "$ROW")"
assert_eq "AC1.1 --phase is recorded in column 8" "red" "$(field 8 "$ROW")"
assert_eq "AC1.1 --rework is recorded in column 9" "2" "$(field 9 "$ROW")"
assert_eq "AC1.1 --majors is recorded in column 10" "3" "$(field 10 "$ROW")"
assert_not_contains "AC1.1 a new-format file prints no old-format note" "$OUT" "old cost.tsv format"

for ph in spec red green review fix release; do
  newp
  cost add --role implementer --tokens 5 --phase "$ph"
  assert_rc "AC1.1 --phase $ph accepted" 0
  assert_eq "AC1.1 --phase $ph recorded" "$ph" "$(field 8 "$(tail -n 1 "$F")")"
done
newp
cost add --role tester --tokens 1 --rework 0 --majors 0
assert_rc "AC1.1 --rework 0 and --majors 0 accepted (0 = first pass)" 0
assert_eq "AC1.1 --rework 0 recorded" "0" "$(field 9 "$(tail -n 1 "$F")")"
assert_eq "AC1.1 --majors 0 recorded" "0" "$(field 10 "$(tail -n 1 "$F")")"
newp
cost add --role tester --tokens 1
assert_rc "AC1.1 add without the new options still exits 0" 0
assert_eq "AC1.1 add without the new options keeps the header field count (eleven since v0.22.4)" "11" "$(tail -n 1 "$F" | awk -F'\t' '{print NF}')"
assert_eq "AC1.1 add without --phase leaves the phase empty" "" "$(field 8 "$(tail -n 1 "$F")")"

echo "cost.sh v0.22.3 AC1.1: invalid values exit 2 and write nothing"
newp
badn() { # name args...  -> exit 2, no file
  local n="$1"; shift
  cost add --role tester --tokens 5 "$@"
  assert_rc "AC1.1 $n exits 2" 2
  assert_no_path "AC1.1 $n writes nothing (no file)" "$F"
}
badn "phase plan"            --phase plan
badn "phase Red (case)"      --phase Red
badn "phase empty"           --phase ""
badn "phase with a space"    --phase "red green"
badn "negative rework"       --rework -1
badn "non-integer rework"    --rework 1.5
badn "alpha rework"          --rework abc
badn "empty rework"          --rework ""
badn "negative majors"       --majors -2
badn "non-integer majors"    --majors 0.5
badn "alpha majors"          --majors many
badn "empty majors"          --majors ""
badn "one bad value among good ones" --phase red --rework 1 --majors x
cost add --role tester --tokens 7 --phase red --rework 1 --majors 1
BEFORE="$(cat "$F")"
cost add --role tester --tokens 7 --phase nope
assert_rc "AC1.1 invalid phase on an existing file exits 2" 2
assert_eq "AC1.1 invalid phase leaves the file byte-identical" "$BEFORE" "$(cat "$F")"
cost add --role tester --tokens 7 --rework -3
assert_eq "AC1.1 invalid rework leaves the file byte-identical" "$BEFORE" "$(cat "$F")"
cost add --role tester --tokens 7 --majors z
assert_eq "AC1.1 invalid majors leaves the file byte-identical" "$BEFORE" "$(cat "$F")"

echo "cost.sh v0.22.3 AC1.1: an old-header file keeps its header and its field count"
oldp() { # -> project whose cost.tsv has the old header and one old row
  newp
  mkdir -p "$(dirname "$F")"
  printf '%s\n' "$OLDHDR" > "$F"
  printf '2026-01-01T00:00:00Z\ttester\t40\t4\tm0\tLite\told note\n' >> "$F"
}
NOTE="old cost.tsv format: phase/rework/majors not recorded"
oldp
cost add --role reviewer --tokens 60 --seconds 6 --phase review --rework 1 --majors 2
assert_rc "AC1.1 add to an old-header file exits 0" 0
assert_eq "AC1.1 the old header is untouched" "$OLDHDR" "$(head -n 1 "$F")"
assert_eq "AC1.1 the old row is untouched" "$(printf '2026-01-01T00:00:00Z\ttester\t40\t4\tm0\tLite\told note')" "$(sed -n 2p "$F")"
assert_eq "AC1.1 one row was appended" "3" "$(lines)"
assert_eq "AC1.1 the new row keeps the old field count (7)" "7" "$(tail -n 1 "$F" | awk -F'\t' '{print NF}')"
assert_eq "AC1.1 the new row still has its role" "reviewer" "$(field 2 "$(tail -n 1 "$F")")"
assert_eq "AC1.1 the new row still has its tokens" "60" "$(field 3 "$(tail -n 1 "$F")")"
assert_contains "AC1.1 add prints the old-format note" "$OUT" "$NOTE"
assert_eq "AC1.1 the old-format note is printed once per add call" "1" "$(printf '%s\n' "$OUT" | grep -cF "$NOTE")"
cost add --role tester --tokens 1
assert_rc "AC1.1 a second add to the old-header file exits 0" 0
assert_contains "AC1.1 the note is printed again by each add call" "$OUT" "$NOTE"
assert_eq "AC1.1 the second add also keeps 7 fields" "7" "$(tail -n 1 "$F" | awk -F'\t' '{print NF}')"
assert_eq "AC1.1 the header is still the old one after two adds" "$OLDHDR" "$(head -n 1 "$F")"
oldp
BEFORE="$(cat "$F")"
cost add --role tester --tokens 5 --phase bogus
assert_rc "AC1.1 an invalid phase on an old-header file exits 2" 2
assert_eq "AC1.1 an invalid phase leaves the old-header file unchanged" "$BEFORE" "$(cat "$F")"

echo "cost.sh v0.22.3 AC1.2: summary per phase, rework rounds, review majors"
newp
cost add --role tester      --tokens 100 --seconds 10 --phase red     --rework 0 --majors 0
cost add --role tester      --tokens 50  --seconds 5  --phase red     --rework 1 --majors 0
cost add --role implementer --tokens 200 --seconds 20 --phase green   --rework 0 --majors 0
cost add --role reviewer    --tokens 300 --seconds 30 --phase review  --rework 0 --majors 2
cost add --role orchestrator --tokens 25 --seconds 7
cost summary
assert_rc "AC1.2 summary exits 0" 0
PR="$(cells '^red$')"
[ -n "$PR" ] && t_ok "AC1.2 a per-phase row for red" || t_bad "AC1.2 a per-phase row for red" "$OUT"
has_cell "AC1.2 red tokens = 150" "$PR" "150"
has_cell "AC1.2 red seconds = 15" "$PR" "15"
PG="$(cells '^green$')"
has_cell "AC1.2 green tokens = 200" "$PG" "200"
has_cell "AC1.2 green seconds = 20" "$PG" "20"
PV="$(cells '^review$')"
has_cell "AC1.2 review tokens = 300" "$PV" "300"
has_cell "AC1.2 review seconds = 30" "$PV" "30"
assert_contains "AC1.2 summary has a phase column heading" "$(printf '%s\n' "$OUT" | grep -i 'phase' | head -n 1)" "|"
assert_eq "AC1.2 the line 'rework rounds: 1, review majors: 2'" "1" "$(printf '%s\n' "$OUT" | grep -cx 'rework rounds: 1, review majors: 2')"
T="$(cells '^tester$')"
has_cell "AC1.2 the per-role table is still there (tester tokens = 150)" "$T" "150"
before="$(cat "$F")"
cost summary
assert_eq "AC1.2 summary does not modify the file" "$before" "$(cat "$F")"

echo "cost.sh v0.22.3 AC1.2: summary --json"
cost summary --json
assert_rc "AC1.2 summary --json exits 0" 0
assert_not_contains "AC1.2 summary --json is not the markdown table" "$OUT" "|---"
printf '%s' "$OUT" > "$P/summary.json"
JCHK='const fs = require("fs"); const t = fs.readFileSync(process.argv[1], "utf8"); let o; try { o = JSON.parse(t); } catch (e) { console.log("notjson"); process.exit(0); }
if (o === null || typeof o !== "object" || Array.isArray(o)) { console.log("notobject"); process.exit(0); }
const nums = [], keys = [], strs = [];
(function walk(v, k) { if (k !== undefined) keys.push(String(k)); if (typeof v === "number") nums.push(v); else if (typeof v === "string") strs.push(v); else if (v && typeof v === "object") for (const x of Object.keys(v)) walk(v[x], x); })(o);
const has = (re, a) => a.some(x => re.test(String(x)));
const out = [];
out.push("object");
out.push(nums.includes(675) ? "tokens675" : "no-tokens675");
out.push(nums.includes(72) ? "seconds72" : "no-seconds72");
out.push(has(/rework/i, keys) ? "rework-key" : "no-rework-key");
out.push(has(/major/i, keys) ? "majors-key" : "no-majors-key");
out.push(has(/phase/i, keys) ? "phase-key" : "no-phase-key");
out.push(has(/^red$/, keys.concat(strs)) ? "red-present" : "no-red");
console.log(out.join(" "));'
JR="$(node -e "$JCHK" "$P/summary.json" 2>&1)"
assert_eq "AC1.2 --json is one JSON object carrying the totals (tokens 675, seconds 72), rework, majors and phases" "object tokens675 seconds72 rework-key majors-key phase-key red-present" "$JR"
assert_eq "AC1.2 --json prints a single JSON document (one object, no markdown around it)" "1" "$(node -e 'const t=require("fs").readFileSync(process.argv[1],"utf8"); try { JSON.parse(t); console.log(1) } catch (e) { console.log(0) }' "$P/summary.json")"

echo "cost.sh v0.22.3 AC1.2: missing fields read as empty or 0"
oldp
cost summary
assert_rc "AC1.2 summary of an old-header file exits 0" 0
assert_eq "AC1.2 an old-header file: rework rounds: 0, review majors: 0" "1" "$(printf '%s\n' "$OUT" | grep -cx 'rework rounds: 0, review majors: 0')"
T="$(cells '^tester$')"
has_cell "AC1.2 an old-header file: the role table still counts tokens (40)" "$T" "40"
cost summary --json
assert_rc "AC1.2 summary --json of an old-header file exits 0" 0
printf '%s' "$OUT" > "$P/old.json"
assert_eq "AC1.2 summary --json of an old-header file is valid JSON" "1" "$(node -e 'try { const o = JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); console.log(o && typeof o === "object" && !Array.isArray(o) ? 1 : 0) } catch (e) { console.log(0) }' "$P/old.json")"
# a new-header file holding a short (7-field) row next to a full row
newp
mkdir -p "$(dirname "$F")"
printf 'date\trole\ttokens\tseconds\tmodel\tweight\tnote\tphase\trework\tmajors\n' > "$F"
printf '2026-01-01T00:00:00Z\ttester\t40\t4\tm0\tLite\tshort row\n' >> "$F"
printf '2026-01-02T00:00:00Z\treviewer\t60\t6\tm1\tFull\tfull row\treview\t3\t4\n' >> "$F"
cost summary
assert_rc "AC1.2 a short row under a new header: summary exits 0" 0
assert_eq "AC1.2 the short row counts 0 rework and 0 majors; the full row adds 3 and 4" "1" "$(printf '%s\n' "$OUT" | grep -cx 'rework rounds: 3, review majors: 4')"
has_cell "AC1.2 the short row still counts its tokens (total 100)" "$(cells 'total')" "100"
PV="$(cells '^review$')"
has_cell "AC1.2 only the full row is in the review phase (tokens 60)" "$PV" "60"
# --- v0.22.4 AC3: --task column and calibrate (advisory)
echo "cost.sh v0.22.4 AC3.1: --task is appended after majors (new files have eleven columns)"
newp
cost add --role tester --tokens 5 --phase red --rework 0 --majors 0 --task T-1.a_b
assert_rc "AC3.1 add with --task exits 0" 0
HDR="$(head -n 1 "$F")"; ROW="$(tail -n 1 "$F")"
assert_eq "AC3.1 the first ten header columns are unchanged" "$OLDHDR10" "$(printf '%s\n' "$HDR" | cut -f1-10)"
assert_eq "AC3.1 header column 11 is task" "task" "$(field 11 "$HDR")"
assert_eq "AC3.1 the header has eleven columns" "11" "$(printf '%s\n' "$HDR" | awk -F'\t' '{print NF}')"
assert_eq "AC3.1 the row has eleven fields" "11" "$(printf '%s\n' "$ROW" | awk -F'\t' '{print NF}')"
assert_eq "AC3.1 --task is recorded in column 11" "T-1.a_b" "$(field 11 "$ROW")"
assert_eq "AC3.1 column 10 (majors) keeps its place" "0" "$(field 10 "$ROW")"
cost add --role tester --tokens 5
assert_rc "AC3.1 add without --task exits 0" 0
assert_eq "AC3.1 add without --task keeps eleven fields" "11" "$(tail -n 1 "$F" | awk -F'\t' '{print NF}')"
assert_eq "AC3.1 add without --task leaves the task empty" "" "$(field 11 "$(tail -n 1 "$F")")"
assert_not_contains "AC3.1 a new-format file prints no old-format note" "$OUT" "old cost.tsv format"
cost add --role tester --tokens 5 --task A9
assert_eq "AC3.1 IDs of letters and digits are accepted" "A9" "$(field 11 "$(tail -n 1 "$F")")"

echo "cost.sh v0.22.4 AC3.1: an invalid task ID exits 2 and writes nothing"
newp
badn "task with a space"       --task "a b"
badn "task with a slash"       --task "a/b"
badn "task with a semicolon"   --task "a;b"
badn "task empty"              --task ""
badn "task with a tab"         --task "a	b"
badn "task with a newline"     --task "a
b"
cost add --role tester --tokens 7 --task ok1
BEFORE="$(cat "$F")"
cost add --role tester --tokens 7 --task "bad id"
assert_rc "AC3.1 an invalid task on an existing file exits 2" 2
assert_eq "AC3.1 an invalid task leaves the file byte-identical" "$BEFORE" "$(cat "$F")"

echo "cost.sh v0.22.4 AC3.1: old files (seven or v0.22.3 ten columns) keep their header, the note mentions task"
oldp10() { newp; mkdir -p "$(dirname "$F")"; printf '%s\n' "$OLDHDR10" > "$F"; printf '2026-01-01T00:00:00Z\ttester\t40\t4\tm0\tLite\told\tred\t0\t0\n' >> "$F"; }
oldp10
cost add --role reviewer --tokens 60 --phase review --majors 1 --task T9
assert_rc "AC3.1 add --task to a v0.22.3 ten-column file exits 0" 0
assert_eq "AC3.1 the ten-column header is untouched" "$OLDHDR10" "$(head -n 1 "$F")"
assert_eq "AC3.1 the new row keeps ten fields (no task recorded)" "10" "$(tail -n 1 "$F" | awk -F'\t' '{print NF}')"
assert_eq "AC3.1 the new row keeps its majors in column 10" "1" "$(field 10 "$(tail -n 1 "$F")")"
assert_contains "AC3.1 the note says it is the old format" "$OUT" "old cost.tsv format"
assert_contains "AC3.1 the note mentions task" "$OUT" "task"
cost add --role tester --tokens 1
assert_contains "AC3.1 the note is printed without --task too" "$OUT" "old cost.tsv format"
assert_eq "AC3.1 still ten fields after a second add" "10" "$(tail -n 1 "$F" | awk -F'\t' '{print NF}')"
oldp
cost add --role reviewer --tokens 60 --task T9
assert_rc "AC3.1 add --task to a seven-column file exits 0" 0
assert_eq "AC3.1 the seven-column header is untouched" "$OLDHDR" "$(head -n 1 "$F")"
assert_eq "AC3.1 the new row keeps seven fields" "7" "$(tail -n 1 "$F" | awk -F'\t' '{print NF}')"
assert_contains "AC3.1 the seven-column note mentions task" "$OUT" "task"
oldp10
BEFORE="$(cat "$F")"
cost add --role tester --tokens 5 --task "bad id"
assert_rc "AC3.1 an invalid task on an old file exits 2" 2
assert_eq "AC3.1 an invalid task leaves the old file unchanged" "$BEFORE" "$(cat "$F")"

echo "cost.sh v0.22.4 AC3.2: calibrate per weight"
CH="$(printf 'date\trole\ttokens\tseconds\tmodel\tweight\tnote\tphase\trework\tmajors\ttask')"
crow() { # ROLE TOKENS PHASE REWORK MAJORS TASK WEIGHT -> one eleven-field row on stdout
  printf '2026-01-01T00:00:00Z\t%s\t%s\t1\tm\t%s\t\t%s\t%s\t%s\t%s\n' "$1" "$2" "$7" "$3" "$4" "$5" "$6"
}
mkcal() { newp; mkdir -p "$(dirname "$F")"; printf '%s\n' "$CH" > "$F"; }
# line_of_weight WEIGHT -> the calibrate output line that starts with that weight (after table or list marks)
line_of_weight() { printf '%s\n' "$OUT" | grep -E "^[-*| ]*$1([^A-Za-z]|\$)" | head -n 1; }
# has_metric NAME LINE LABEL VALUE: LABEL comes first, then the number; an average may be written with one decimal (1500 or 1500.0)
has_metric() {
  if printf '%s\n' "$2" | grep -qiE "$3[^0-9]{0,20}$4(\\.0)?([^0-9.]|\$)"; then t_ok "$1"; else t_bad "$1" "no [$3 ... $4] in line [$2]"; fi
}
mkcal
{
  crow tester 400 red 0 0 F1 Full; crow implementer 300 green 2 0 F1 Full; crow reviewer 300 review 0 2 F1 Full
  crow tester 1500 red 2 0 F2 Full; crow reviewer 300 review 0 1 F2 Full; crow reviewer 200 review 0 3 F2 Full
  crow implementer 500 green 1 0 L1 Lite; crow reviewer 100 review 0 0 L1 Lite
  crow tester 900 red 3 0 L2 Lite; crow reviewer 100 review 0 0 L2 Lite
  crow implementer 99999 green 9 0 S1 Full
  crow reviewer 88888 review 0 "" S2 Lite
  crow reviewer 77777 review 9 9 "" Full
} >> "$F"
CALSUM="$(cksum "$F")"
FILES_BEFORE="$(find "$P" "$PLAYBOOK_HOME" -type f 2>/dev/null | sort)"
cost calibrate
assert_rc "AC3.2 calibrate exits 0" 0
FL="$(line_of_weight Full)"
LL="$(line_of_weight Lite)"
[ -n "$FL" ] && t_ok "AC3.2 a line for the weight Full" || t_bad "AC3.2 a line for the weight Full" "$OUT"
[ -n "$LL" ] && t_ok "AC3.2 a line for the weight Lite" || t_bad "AC3.2 a line for the weight Lite" "$OUT"
has_metric "AC3.2 Full: 2 tasks (rows without review data or task id are not counted)" "$FL" "tasks" "2"
has_metric "AC3.2 Full: average tokens 1500 per task" "$FL" "tokens" "1500"
has_metric "AC3.2 Full: review majors per task 3 (sum over the review rows: 2 and 4)" "$FL" "major" "3"
has_metric "AC3.2 Full: rework per task 2 (max rework in the task)" "$FL" "rework" "2"
has_metric "AC3.2 Lite: 2 tasks" "$LL" "tasks" "2"
has_metric "AC3.2 Lite: average tokens 800 per task" "$LL" "tokens" "800"
has_metric "AC3.2 Lite: review majors per task 0" "$LL" "major" "0"
has_metric "AC3.2 Lite: rework per task 2 (1 and 3)" "$LL" "rework" "2"
assert_contains "AC3.2 two tasks lack review data (no review row, review row without majors)" "$OUT" "skipped 2 task(s) without review data"
assert_not_contains "AC3.2 fewer than five Full tasks: no advice" "$OUT" "advice:"
assert_eq "AC3.2 calibrate does not modify the cost file" "$CALSUM" "$(cksum "$F")"
assert_eq "AC3.2 calibrate writes no file anywhere (project or playbook home)" "$FILES_BEFORE" "$(find "$P" "$PLAYBOOK_HOME" -type f 2>/dev/null | sort)"

echo "cost.sh v0.22.4 AC3.2: the advice line"
ADV="advice: Full reviews found no majors in 5 tasks; similar changes may be Lite"
fulls() { # N [LAST_MAJORS] -> N Full tasks FA1..FAN, one review row each (majors 0, the last one LAST_MAJORS)
  local n="$1" last="${2:-0}" i=1
  while [ "$i" -le "$n" ]; do
    crow implementer 100 green 0 0 "FA$i" Full
    if [ "$i" -eq "$n" ]; then crow reviewer 50 review 0 "$last" "FA$i" Full; else crow reviewer 50 review 0 0 "FA$i" Full; fi
    i=$((i + 1))
  done
}
mkcal; fulls 5 >> "$F"
cost calibrate
assert_rc "AC3.2 five Full tasks, no majors: exit 0" 0
assert_eq "AC3.2 five Full tasks with 0 majors: the advice line, once" "1" "$(printf '%s\n' "$OUT" | grep -cxF "$ADV")"
mkcal; fulls 6 >> "$F"
cost calibrate
assert_eq "AC3.2 six Full tasks with 0 majors: the line names 6" "1" "$(printf '%s\n' "$OUT" | grep -cxF "advice: Full reviews found no majors in 6 tasks; similar changes may be Lite")"
mkcal; fulls 4 >> "$F"
cost calibrate
assert_not_contains "AC3.2 four Full tasks: no advice" "$OUT" "advice:"
mkcal; fulls 5 1 >> "$F"
cost calibrate
assert_not_contains "AC3.2 five Full tasks, one found a major: no advice" "$OUT" "advice:"
mkcal; { fulls 4; crow implementer 100 green 0 0 SK Full; } >> "$F"
cost calibrate
assert_not_contains "AC3.2 four counted Full tasks plus one without review data: no advice" "$OUT" "advice:"
assert_contains "AC3.2 ... and that task is reported as skipped" "$OUT" "skipped 1 task(s) without review data"
mkcal; { fulls 5; crow reviewer 50 review 0 2 L1 Lite; } >> "$F"
cost calibrate
assert_eq "AC3.2 majors found in Lite tasks do not cancel the Full advice" "1" "$(printf '%s\n' "$OUT" | grep -cxF "$ADV")"

echo "cost.sh v0.22.4 AC3.2: calibrate on old or empty data"
oldp
cost calibrate
assert_rc "AC3.2 calibrate on a seven-column file exits 0" 0
assert_not_contains "AC3.2 no tasks recorded, no advice" "$OUT" "advice:"
oldp10
cost calibrate
assert_rc "AC3.2 calibrate on a v0.22.3 ten-column file exits 0 (no task recorded: starts from new data)" 0
newp
cost calibrate
assert_rc "AC3.2 calibrate with no file exits 0" 0
assert_no_path "AC3.2 calibrate does not create the file" "$F"

echo "cost.sh v0.22.4 review: per-task averages show one decimal place (D5)"
mkcal
{
  crow reviewer 100 review 1 1 D1 Full
  crow reviewer 100 review 0 0 D2 Full
  crow reviewer 101 review 0 0 D3 Full
} >> "$F"
cost calibrate
assert_rc "D5 calibrate with three Full tasks exits 0" 0
DL="$(line_of_weight Full)"
assert_contains "D5 three Full tasks with one major in total print 'review majors 0.3'" "$DL" "review majors 0.3"
has_metric "D5 tasks stay a whole count (3)" "$DL" "tasks" "3"
if printf '%s\n' "$DL" | grep -qiE 'tokens[^0-9]{0,20}100\.3([^0-9]|$)'; then t_ok "D5 the average tokens (300.33 / 3 = 100.33) print as 100.3"; else t_bad "D5 the average tokens print as 100.3" "line: $DL"; fi
if printf '%s\n' "$DL" | grep -qiE 'rework[^0-9]{0,20}0\.3([^0-9]|$)'; then t_ok "D5 the rework per task (1, 0, 0) prints as 0.3"; else t_bad "D5 the rework per task prints as 0.3" "line: $DL"; fi

echo "v0.24.5: cost.sh accepts the spec_reviewer role and reports it after the reviewer"
newp
cost add --role spec_reviewer --tokens 70 --seconds 5 --model sm --weight Full
assert_rc "v0.24.5 add --role spec_reviewer exits 0" 0
assert_eq "v0.24.5 the spec_reviewer row is logged" "2" "$(lines)"
cost add --role reviewer --tokens 30 --seconds 3 --model rm --weight Full
cost add --role tester --tokens 10 --seconds 1 --weight Full
cost summary
assert_rc "v0.24.5 summary with a spec_reviewer row exits 0" 0
ROWS="$(printf '%s\n' "$OUT" | grep -E '^\| (tester|implementer|reviewer|spec_reviewer|orchestrator) ' | awk -F'|' '{ gsub(/ /, "", $2); printf "%s ", $2 }')"
assert_eq "v0.24.5 the report orders spec_reviewer after the reviewer" "tester reviewer spec_reviewer " "$ROWS"
has_cell "v0.24.5 the spec_reviewer row sums its tokens" "$(cells '^spec_reviewer$')" "70"
cost summary --json
assert_contains "v0.24.5 the json report has a spec_reviewer entry" "$OUT" "\"spec_reviewer\":{\"runs\":1,\"tokens\":70,\"seconds\":5}"
cost add --role spec-reviewer --tokens 1
assert_rc "v0.24.5 a misspelt role is still rejected" 2
t_summary
