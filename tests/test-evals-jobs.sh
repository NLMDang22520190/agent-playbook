#!/usr/bin/env bash
# Tests for evals/run-evals.sh --jobs N and --variant-held DIR (slice C1, spec .agents/handoff/01-spec.md AC J1-J3, decisions D6 D7):
# up to N runs at a time, a separate workdir, temp PLAYBOOK_HOME and TMPDIR per run, the md and JSON of --jobs N the same in shape and
# order as --jobs 1, one install and one restore under --variant, the held variant. Never calls a real harness: --cmd stub adapters
# that record their overlap in a dir outside the workroot, and (for --variant) the fake claude of tests/jobs-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-arms-fixture.sh"   # jget, PBH; its own fakes/home are not used here
JOBS_RUNNER="$RUNNER"; JOBS_TASKS=""
. "$(dirname "$0")/jobs-fixture.sh"

# ---- the concurrency adapter (a good adapter that also records its overlap), driven by files in $CJ (outside the workroot) ----
# $CJ/mode: seq (no waiting) or par; $CJ/barrier: labels that wait until $CJ/want runs are active (at most 5 s); E1 then also waits
# until another run has finished, so that the runs end in another order than their labels; $CJ/stray: a label that writes ../stray-<label> (then creates $CJ/strayed; the other runs wait for it, so they end after the stray exists).
CJ="$(mk_tmp)"; export CJ
mk_adapter conc "
: > \"\$CJ/active.\$e\"
ls \"\$CJ\" | grep -c '^active\\.' >> \"\$CJ/seen\"
{ printf 'wd=%s\n' \"\$wd\"; printf 'tmp=%s\n' \"\${TMPDIR-UNSET}\"; printf 'ph=%s\n' \"\${PLAYBOOK_HOME-UNSET}\"
  if [ -d \"\${PLAYBOOK_HOME:-/nonexistent}\" ]; then echo phdir=yes; else echo phdir=no; fi; } > \"\$CJ/\$e.env\"
if [ \"\$(cat \"\$CJ/mode\")\" = par ]; then
  case \" \$(cat \"\$CJ/barrier\") \" in *\" \$e \"*)
    i=0; while [ \"\$(ls \"\$CJ\" | grep -c '^active\\.')\" -lt \"\$(cat \"\$CJ/want\")\" ] && [ \"\$i\" -lt 50 ]; do sleep 0.1; i=\$((i + 1)); done
    ls \"\$CJ\" | grep -c '^active\\.' >> \"\$CJ/seen\" ;;
  esac
  if [ \"\$e\" = E1 ]; then i=0; while [ \"\$(ls \"\$CJ\" | grep -c '^fin\\.')\" -lt 1 ] && [ \"\$i\" -lt 50 ]; do sleep 0.1; i=\$((i + 1)); done; fi
fi
if [ -f \"\$CJ/stray\" ]; then
  if [ \"\$e\" = \"\$(cat \"\$CJ/stray\")\" ]; then echo x > \"../stray-\$e\"; : > \"\$CJ/strayed\"
  else i=0; while [ ! -f \"\$CJ/strayed\" ] && [ \"\$i\" -lt 50 ]; do sleep 0.1; i=\$((i + 1)); done; fi
fi
$GOOD_BODY
rm -f \"\$CJ/active.\$e\"; : > \"\$CJ/fin.\$e\""

# cj_reset MODE WANT BARRIER-LABELS... -> a clean $CJ
cj_reset() { rm -rf "${CJ:?}"/* "${CJ:?}"/.[!.]* 2>/dev/null; printf '%s\n' "$1" > "$CJ/mode"; printf '%s\n' "$2" > "$CJ/want"; shift 2; printf '%s\n' "$*" > "$CJ/barrier"; }
# peak -> the highest overlap the adapters saw
peak() { LC_ALL=C sort -n "$CJ/seen" 2>/dev/null | tail -n 1; }
# jr ARGS... -> the runner with the conc adapter into a fresh runner-owned workroot W; stdout in OUT, results in R (md) and RJ (json)
jr() {
  W="$(mk_tmp)"; : > "$W/.pb-eval-workroot"; RD="$(mk_tmp)"; R="$RD/results.md"; RJ="$RD/results.json"
  bash "$RUNNER" --cmd "bash $A/conc.sh" --workroot "$W" --out "$R" "$@" > "$RD/stdout" 2> "$RD/stderr"; RC=$?
  OUT="$(cat "$RD/stdout")"; ERR="$(cat "$RD/stderr")"
}
# norm_md FILE WORKROOT -> the headings and table rows of the md with the workroot path and the date stamps replaced
norm_md() { grep -E '^(#|\|)' "$1" | sed -e "s|$2|WORKROOT|g" -e 's/[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}/DATE/g'; }
# norm_json FILE -> the JSON without what changes between runs (stamps, paths, seconds, times, costs, commit), keys in order
norm_json() { node -e '
const j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
delete j.started; delete j.workroot; delete j.playbook_commit;
const strip=(o)=>{ if(Array.isArray(o)) return o.map(strip); if(o&&typeof o==="object"){ const n={}; for(const k of Object.keys(o)){ if(/(seconds|cost|time|started|workroot)/i.test(k)) n[k]=null; else n[k]=strip(o[k]); } return n; } return o; };
process.stdout.write(JSON.stringify(strip(j),null,1));' "$1"; }
# labels_of OUT -> the run label each output line belongs to ("== E1: running..." and "E1 PASS ..." both give E1), in order
labels_of() { printf '%s\n' "$1" | sed -n -e 's/^== \(E[0-9][0-9]*\): .*/\1/p' -e 's/^\(E[0-9][0-9]*\) [A-Z][A-Z]* .*/\1/p'; }
# contiguous LABELS -> 0 when no label comes back after another label began (each run is one block)
contiguous() { [ -z "$(printf '%s\n' "$1" | uniq | LC_ALL=C sort | uniq -d)" ]; }

# ================= option parsing =================
echo "J1 --jobs takes 1..16; 0, 17 and non-numbers exit 2"
run bash "$RUNNER" --help
assert_contains "J1 the usage text documents --jobs" "$OUT" "--jobs"
for bad in 0 17 abc -1 1.5 01x 99 ""; do
  cj_reset seq 1; rm -f "${REC:?}"/*
  W="$(mk_tmp)"; : > "$W/.pb-eval-workroot"
  run bash "$RUNNER" --cmd "bash $A/conc.sh" --scenarios E8 --workroot "$W" --out "$W/r.md" --jobs "$bad"
  assert_rc "J1 --jobs '$bad' exits 2" 2
  assert_not_contains "J1 --jobs '$bad': a value error, not an unknown option" "$OUT" "unknown option"
  assert_no_path "J1 --jobs '$bad': no adapter run" "$REC/E8.args"
  assert_no_path "J1 --jobs '$bad': no results file" "$W/r.md"
done
rm -f "${REC:?}"/*; W="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $A/conc.sh" --scenarios E8 --workroot "$W" --out "$W/r.md" --jobs
assert_rc "J1 --jobs without a value exits 2" 2
assert_not_contains "J1 --jobs without a value: a value error, not an unknown option" "$OUT" "unknown option"
for ok in 1 16; do
  cj_reset seq 1
  jr --scenarios E8 --jobs "$ok"
  assert_rc "J1 --jobs $ok (the bounds) is accepted: exit 0" 0
  assert_file "J1 --jobs $ok wrote the results" "$R"
done
# the default is --jobs 1: same results as no option
cj_reset seq 1; jr --scenarios E8,E3; A_MD="$(norm_md "$R" "$W")"; A_JS="$(norm_json "$RJ")"
cj_reset seq 1; jr --scenarios E8,E3 --jobs 1; B_MD="$(norm_md "$R" "$W")"; B_JS="$(norm_json "$RJ")"
assert_eq "J1 --jobs 1 gives the same md as no --jobs (normalised)" "$A_MD" "$B_MD"
assert_eq "J1 --jobs 1 gives the same JSON as no --jobs (normalised)" "$A_JS" "$B_JS"
assert_eq "J1 --jobs 1 runs one at a time (peak overlap 1)" "1" "$(peak)"

# ================= --jobs 1 baseline and --jobs 3 =================
echo "J1 --jobs 1: one run at a time"
cj_reset seq 1
jr --scenarios E1,E3,E8,E15 --jobs 1
assert_rc "J1 baseline --jobs 1: exit 0" 0
assert_eq "J1 --jobs 1: the peak overlap is 1" "1" "$(peak)"
S_MD="$(norm_md "$R" "$W")"; S_JS="$(norm_json "$RJ")"; S_OUT="$OUT"; S_SUMKEYS="$(jget "$RJ" 'JSON.stringify(Object.keys(j.summary||{}))')"
S_LABELS="$(jget "$RJ" 'j.runs.map(r=>r.label).join(",")')"

echo "J1 J3 --jobs 3: overlap, separate workdir/PLAYBOOK_HOME/TMPDIR, same results as --jobs 1"
cj_reset par 3 E1 E3 E8
jr --scenarios E1,E3,E8,E15 --jobs 3
assert_rc "J1 --jobs 3: exit 0 with a good adapter" 0
P="$(peak)"
if [ "${P:-0}" -gt 1 ] && [ "${P:-0}" -le 3 ]; then t_ok "J1 --jobs 3: runs really overlapped (peak $P, more than 1, at most 3)"; else t_bad "J1 --jobs 3: runs really overlapped (peak more than 1, at most 3)" "peak=[$P]"; fi
for e in E1 E3 E8 E15; do assert_file "J1 --jobs 3: $e adapter ran and recorded its environment" "$CJ/$e.env"; done
for k in wd tmp ph; do
  assert_eq "J1 --jobs 3: the $k seen by the four runs are four different values" "4" "$(for e in E1 E3 E8 E15; do sed -n "s/^$k=//p" "$CJ/$e.env"; done | LC_ALL=C sort -u | wc -l | tr -d ' ')"
done
assert_eq "J1 --jobs 3: every run had its PLAYBOOK_HOME as an existing dir" "4" "$(cat "$CJ"/E*.env | grep -c '^phdir=yes$')"
assert_eq "J1 --jobs 3: no run saw TMPDIR or PLAYBOOK_HOME unset" "0" "$(cat "$CJ"/E*.env | grep -c '=UNSET$')"
assert_eq "J1 --jobs 3: each workdir is <workroot>/<label>" "$(for e in E1 E3 E8 E15; do printf '%s\n' "$(physdir "$W")/$e"; done)" \
  "$(for e in E1 E3 E8 E15; do d="$(sed -n 's/^wd=//p' "$CJ/$e.env")"; printf '%s\n' "$(physdir "$(dirname "$d")")/$(basename "$d")"; done)"
LEFT=""; for e in E1 E3 E8 E15; do for k in ph tmp; do p="$(sed -n "s/^$k=//p" "$CJ/$e.env")"; [ -e "$p" ] && LEFT="$LEFT $p"; done; done
assert_eq "J1 --jobs 3: the temp PLAYBOOK_HOMEs and TMPDIRs are removed after the runs" "" "$LEFT"
# the runs ended in another order than their labels (E1 waited for another run), yet the results keep label order
assert_eq "J3 --jobs 3: runs[] labels in label order" "E1,E3,E8,E15" "$(jget "$RJ" 'j.runs.map(r=>r.label).join(",")')"
assert_eq "J3 --jobs 1 baseline: runs[] labels in label order" "E1,E3,E8,E15" "$S_LABELS"
assert_contains "J3 the normalised JSON holds all four runs (the comparison is not of two empty files)" "$S_JS" '"label": "E15"'
assert_eq "J3 --jobs 3: the summary has the same keys as --jobs 1" "$S_SUMKEYS" "$(jget "$RJ" 'JSON.stringify(Object.keys(j.summary||{}))')"
assert_eq "J3 --jobs 3: the JSON equals --jobs 1 after normalising times, costs, stamps and paths" "$S_JS" "$(norm_json "$RJ")"
assert_eq "J3 --jobs 3: the md equals --jobs 1 after normalising (section and row order, checks)" "$S_MD" "$(norm_md "$R" "$W")"
assert_eq "J3 --jobs 3: the md sections come in label order" "## E1
## E3
## E8
## E15" "$(grep '^## E' "$R")"
for e in E1 E3 E8 E15; do
  assert_eq "J3 --jobs 3: $e has the same check lines (name and result) as --jobs 1" \
    "$(printf '%s\n' "$S_OUT" | grep "^$e [A-Z]" | LC_ALL=C sort)" "$(printf '%s\n' "$OUT" | grep "^$e [A-Z]" | LC_ALL=C sort)"
  assert_eq "D7 --jobs 3: $e: the stray check passes (the other runs' own entries are not strays)" "PASS" "$(e_state "$e" 'nothing written outside the workdir')"
done
LB="$(labels_of "$OUT")"
if contiguous "$LB"; then t_ok "J3 --jobs 3: each run's output lines are one contiguous block"; else t_bad "J3 --jobs 3: each run's output lines are one contiguous block" "label sequence: $(printf '%s' "$LB" | tr '\n' ' ')"; fi
assert_eq "J3 --jobs 3: every run printed its lines (four blocks)" "4" "$(printf '%s\n' "$LB" | uniq | wc -l | tr -d ' ')"
assert_contains "J3 --jobs 3: the 'results:' line is printed" "$OUT" "results: $R"
assert_contains "J3 --jobs 3: the 'json:' line is printed" "$OUT" "json: $RJ"
# a self-check of the helper: an interleaved sequence is not contiguous
if contiguous "$(printf 'E1\nE3\nE1\n')"; then t_bad "J3 helper: E1 E3 E1 is detected as interleaved" "not detected"; else t_ok "J3 helper: E1 E3 E1 is detected as interleaved"; fi

echo "J1 --jobs 2: at most 2 at a time"
cj_reset par 2 E1 E3
jr --scenarios E1,E3,E8,E15 --jobs 2
assert_rc "J1 --jobs 2: exit 0" 0
P="$(peak)"
if [ "${P:-0}" = 2 ]; then t_ok "J1 --jobs 2: the peak overlap is exactly 2 (never 3 or 4)"; else t_bad "J1 --jobs 2: the peak overlap is exactly 2" "peak=[$P]; seen: $(tr '\n' ' ' < "$CJ/seen")"; fi
assert_eq "J1 --jobs 2: all four runs happened" "4" "$(ls "$CJ" | grep -c '^fin\.')"

# ================= D7 stray check =================
echo "D7 a run that writes outside its workdir is still caught under --jobs"
cj_reset par 3 E1 E3 E8; printf 'E8\n' > "$CJ/stray"
jr --scenarios E1,E3,E8,E15 --jobs 3
assert_rc "D7 --jobs 3 with a stray write: exit 1" 1
assert_eq "D7 the run that wrote ../stray-E8 FAILs the stray check" "FAIL" "$(e_state E8 'nothing written outside the workdir')"
assert_contains "D7 the FAIL line of E8 names the stray entry" "$(printf '%s\n' "$OUT" | grep '^E8 FAIL')" "stray-E8"
# E8's own section has exactly one such row; every other run ends after the stray was written and still PASSes (D20: private roots under --jobs)
assert_eq "D7 the md section of E8 records the FAIL of the stray check, naming stray-E8" "1" "$(awk '/^## /{s=$2} s=="E8"' "$R" | grep -cF 'nothing written outside the workdir (new in the workroot: stray-E8) | FAIL')"
assert_file "D7 the stray was written before the other runs ended" "$CJ/strayed"
for e in E1 E3 E15; do
  assert_eq "D20 --jobs 3: $e PASSes the stray check although E8 wrote ../stray-E8 meanwhile" "PASS" "$(e_state "$e" 'nothing written outside the workdir')"
  assert_eq "D20 --jobs 3: the md section of $e has no stray FAIL row" "0" "$(awk '/^## /{s=$2} s=="'"$e"'"' "$R" | grep -c 'nothing written outside the workdir.*| FAIL')"
done
assert_eq "D20 --jobs 3: only E8 has a stray FAIL row in the whole md" "1" "$(grep -c 'nothing written outside the workdir.*| FAIL' "$R")"

# ================= --max-cost =================
echo "D7 --max-cost with --jobs: checked before each run starts against the finished runs; later runs are still skipped"
mk_adapter c06j "$GOOD_BODY
echo '$INIT'
echo '{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"total_cost_usd\":0.6,\"result\":\"Done.\"}'"
W="$(mk_tmp)"; : > "$W/.pb-eval-workroot"; rm -f "${REC:?}"/*
run bash "$RUNNER" --cmd "bash $A/c06j.sh" --scenarios E1,E3,E8,E15 --workroot "$W" --out "$W/r.md" --max-cost 1 --jobs 2
case "$RC" in 0|1) t_ok "D7 --max-cost with --jobs: skipping never changes the exit code (exit $RC)" ;; *) t_bad "D7 --max-cost with --jobs: exit 0 or 1" "exit $RC: $OUT" ;; esac
assert_eq "D7 the first two runs (started with nothing spent) were not skipped" "0" "$(printf '%s\n' "$OUT" | grep -cE '^E(1|3) SKIPPED')"
assert_contains "D7 E8 (started after 0.6 was spent) is skipped" "$OUT" "E8 SKIPPED"
assert_contains "D7 E15 (started after 0.6 was spent) is skipped" "$OUT" "E15 SKIPPED"
assert_eq "D7 the budget stopped the later runs: their adapters never ran" "no no" "$(for e in E8 E15; do if [ -f "$REC/$e.args" ]; then printf 'yes '; else printf 'no '; fi; done | sed 's/ $//')"
assert_contains "D7 the summary has the SKIPPED row for E15" "$(cat "$W/r.md")" "| E15 | SKIPPED"

# ================= --variant =================
JOBS_OUTER_BASE="--harness claude --scenarios E8"
jobs_variant_suite --harness claude --scenarios E1,E8
t_summary
