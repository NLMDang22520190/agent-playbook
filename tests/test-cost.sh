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

t_summary
