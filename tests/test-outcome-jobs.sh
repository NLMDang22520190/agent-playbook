#!/usr/bin/env bash
# Tests for evals/run-outcome.sh --jobs N and --variant-held DIR (slice C1, spec .agents/handoff/01-spec.md AC J1-J3, decisions D6 D7):
# up to N runs at a time, a separate workdir, temp PLAYBOOK_HOME and TMPDIR per run, the md and JSON of --jobs N the same in shape and
# order as --jobs 1, one install and one restore under --variant, the held variant. Never calls a real harness: --cmd stub adapters
# that record their overlap in a dir outside the workroot, and (for --variant) the fake claude of tests/jobs-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-arms-fixture.sh"   # jget, PBH; its own fakes/home are not used here
. "$(dirname "$0")/outcome-fixture.sh"      # OUTCOME, T (fixture tasks t-add t-two t-node), SA, SR, ro, chk
JOBS_RUNNER="$OUTCOME"; JOBS_TASKS="$T"
. "$(dirname "$0")/jobs-fixture.sh"

# ---- the concurrency stub (solves the task, and records its overlap), driven by files in $CJ (outside the workroot) ----
# $CJ/mode: seq (no waiting) or par; $CJ/barrier: labels that wait until $CJ/want runs are active (at most 5 s); t-add then also waits
# until another run has finished, so that the runs end in another order than their labels; $CJ/stray: a label that writes ../stray-<label>.txt (then creates $CJ/strayed; the other runs wait for it, so they end after the stray exists).
CJ="$(mk_tmp)"; export CJ
mk_stub conc ': > "$CJ/active.$l"
ls "$CJ" | grep -c "^active\." >> "$CJ/seen"
if [ "$(cat "$CJ/mode")" = par ]; then
  case " $(cat "$CJ/barrier") " in *" $l "*)
    i=0; while [ "$(ls "$CJ" | grep -c "^active\.")" -lt "$(cat "$CJ/want")" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
    ls "$CJ" | grep -c "^active\." >> "$CJ/seen" ;;
  esac
  if [ "$l" = t-add.with.1 ]; then i=0; while [ "$(ls "$CJ" | grep -c "^fin\.")" -lt 1 ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done; fi
fi
if [ -f "$CJ/stray" ]; then
  if [ "$l" = "$(cat "$CJ/stray")" ]; then echo x > "$(dirname "$wd")/stray-$l.txt"; : > "$CJ/strayed"
  else i=0; while [ ! -f "$CJ/strayed" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done; fi
fi
solve
rm -f "$CJ/active.$l"; : > "$CJ/fin.$l"'

cj_reset() { rm -rf "${CJ:?}"/* "${CJ:?}"/.[!.]* 2>/dev/null; printf '%s\n' "$1" > "$CJ/mode"; printf '%s\n' "$2" > "$CJ/want"; shift 2; printf '%s\n' "$*" > "$CJ/barrier"; }
peak() { LC_ALL=C sort -n "$CJ/seen" 2>/dev/null | tail -n 1; }
# norm_md FILE WORKROOT -> the headings and table rows of the md with the workroot path, date stamps and the time cells replaced
norm_md() { grep -E '^(#|\|)' "$1" | sed -e "s|$2|WORKROOT|g" -e 's/[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}/DATE/g' \
  -e 's/| [0-9][0-9.]* ± [^|]*|$/| T |/' -e 's/| [0-9][0-9]* |$/| N |/'; }
# norm_json FILE -> the JSON without what changes between runs (stamps, paths, seconds, times, costs, commit), keys in order
norm_json() { node -e '
const j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
delete j.started; delete j.workroot; delete j.playbook_commit;
const strip=(o)=>{ if(Array.isArray(o)) return o.map(strip); if(o&&typeof o==="object"){ const n={}; for(const k of Object.keys(o)){ if(/(seconds|cost|time|started|workroot)/i.test(k)) n[k]=null; else n[k]=strip(o[k]); } return n; } return o; };
process.stdout.write(JSON.stringify(strip(j),null,1));' "$1"; }
# labels_of OUT -> the run label each output line belongs to, in order
labels_of() { printf '%s\n' "$1" | sed -n -e 's/^== \(t-[a-z]*\.[a-z]*\.[0-9]*\): .*/\1/p' -e 's/^\(t-[a-z]*\.[a-z]*\.[0-9]*\) [A-Z][A-Z]* .*/\1/p'; }
contiguous() { [ -z "$(printf '%s\n' "$1" | uniq | LC_ALL=C sort | uniq -d)" ]; }
LABELS="t-add.with.1,t-two.with.1,t-node.with.1"

# ================= option parsing =================
echo "J1 --jobs takes 1..16; 0, 17 and non-numbers exit 2"
run bash "$OUTCOME" --help
assert_contains "J1 the usage text documents --jobs" "$OUT" "--jobs"
for bad in 0 17 abc -1 1.5 01x 99 ""; do
  cj_reset seq 1
  ro --cmd "bash $SA/conc.sh" --tasks t-add --jobs "$bad"
  assert_rc "J1 --jobs '$bad' exits 2" 2
  assert_not_contains "J1 --jobs '$bad': a value error, not an unknown option" "$OUT" "unknown option"
  assert_no_path "J1 --jobs '$bad': no adapter run" "$SR/t-add.with.1.args"
  assert_no_path "J1 --jobs '$bad': no results file" "$RES"
done
ro --cmd "bash $SA/conc.sh" --tasks t-add --jobs
assert_rc "J1 --jobs without a value exits 2" 2
assert_not_contains "J1 --jobs without a value: a value error, not an unknown option" "$OUT" "unknown option"
for ok in 1 16; do
  cj_reset seq 1
  ro --cmd "bash $SA/conc.sh" --tasks t-add --jobs "$ok"
  assert_rc "J1 --jobs $ok (the bounds) is accepted: exit 0" 0
  assert_file "J1 --jobs $ok wrote the results" "$RES"
done
cj_reset seq 1; ro --cmd "bash $SA/conc.sh" --tasks t-add,t-two; A_MD="$(norm_md "$RES" "$WR")"; A_JS="$(norm_json "$JF")"
cj_reset seq 1; ro --cmd "bash $SA/conc.sh" --tasks t-add,t-two --jobs 1; B_MD="$(norm_md "$RES" "$WR")"; B_JS="$(norm_json "$JF")"
assert_eq "J1 --jobs 1 gives the same md as no --jobs (normalised)" "$A_MD" "$B_MD"
assert_eq "J1 --jobs 1 gives the same JSON as no --jobs (normalised)" "$A_JS" "$B_JS"
assert_eq "J1 --jobs 1 runs one at a time (peak overlap 1)" "1" "$(peak)"

# ================= --jobs 1 baseline and --jobs 3 =================
echo "J1 --jobs 1: one run at a time"
cj_reset seq 1
ro --cmd "bash $SA/conc.sh" --tasks t-add,t-two,t-node --jobs 1
assert_rc "J1 baseline --jobs 1: exit 0" 0
assert_eq "J1 --jobs 1: the peak overlap is 1" "1" "$(peak)"
S_MD="$(norm_md "$RES" "$WR")"; S_JS="$(norm_json "$JF")"; S_OUT="$OUT"; S_SUMKEYS="$(jget "$JF" 'JSON.stringify((j.summary||[]).map(e=>e.scenario+"/"+e.arm+"/"+e.key))')"
S_LABELS="$(jget "$JF" 'j.runs.map(r=>r.label).join(",")')"

echo "J1 J3 --jobs 3: overlap, separate workdir/PLAYBOOK_HOME/TMPDIR, same results as --jobs 1"
cj_reset par 3 t-add.with.1 t-two.with.1 t-node.with.1
ro --cmd "bash $SA/conc.sh" --tasks t-add,t-two,t-node --jobs 3
assert_rc "J1 --jobs 3: exit 0 with a solving stub" 0
P="$(peak)"
if [ "${P:-0}" -gt 1 ] && [ "${P:-0}" -le 3 ]; then t_ok "J1 --jobs 3: runs really overlapped (peak $P, more than 1, at most 3)"; else t_bad "J1 --jobs 3: runs really overlapped (peak more than 1, at most 3)" "peak=[$P]"; fi
for k in args tmp ph home; do
  assert_eq "J1 --jobs 3: the $k seen by the three runs are three different values (home is shared by design: 1)" "$([ "$k" = home ] && echo 1 || echo 3)" \
    "$(for l in t-add.with.1 t-two.with.1 t-node.with.1; do if [ "$k" = args ]; then sed -n 1p "$SR/$l.args"; else cat "$SR/$l.$k"; fi; done | LC_ALL=C sort -u | wc -l | tr -d ' ')"
done
for l in t-add.with.1 t-two.with.1 t-node.with.1; do
  assert_file "J1 --jobs 3: $l had its PLAYBOOK_HOME as an existing dir (its files were listed)" "$SR/$l.phfiles"
  assert_eq "J1 --jobs 3: $l: its workdir is <workroot>/$l" "$(physdir "$WR")/$l" "$(a="$(sed -n 1p "$SR/$l.args" 2>/dev/null)"; printf '%s/%s' "$(physdir "$(dirname "$a")")" "$(basename "$a")")"
  assert_eq "J1 --jobs 3: $l: TMPDIR and PLAYBOOK_HOME are set" "0" "$(cat "$SR/$l.tmp" "$SR/$l.ph" | grep -c '^UNSET$')"
  assert_eq "J1 --jobs 3: $l: the log is kept in <out>.runs" "1" "$(grep -c "STUB-OUT-$l" "$EV/$l.log" 2>/dev/null)"
  assert_file "J1 --jobs 3: $l: the diff is kept in <out>.runs" "$EV/$l.diff"
done
LEFT=""; for l in t-add.with.1 t-two.with.1 t-node.with.1; do for k in ph tmp; do p="$(cat "$SR/$l.$k")"; [ -e "$p" ] && LEFT="$LEFT $p"; done; done
assert_eq "J1 --jobs 3: the temp PLAYBOOK_HOMEs and TMPDIRs are removed after the runs" "" "$LEFT"
assert_eq "J1 --jobs 3: nothing is left in the runner's TMPDIR" "" "$(leftovers "$RT")"
# the runs ended in another order than their labels (t-add waited for another run), yet the results keep label order
assert_eq "J3 --jobs 3: runs[] labels in label order" "$LABELS" "$(jget "$JF" 'j.runs.map(r=>r.label).join(",")')"
assert_eq "J3 --jobs 1 baseline: runs[] labels in label order" "$LABELS" "$S_LABELS"
assert_eq "J3 --jobs 3: the summary has the same items, in the same order, as --jobs 1" "$S_SUMKEYS" "$(jget "$JF" 'JSON.stringify((j.summary||[]).map(e=>e.scenario+"/"+e.arm+"/"+e.key))')"
assert_contains "J3 the normalised JSON holds all three runs (the comparison is not of two empty files)" "$S_JS" '"label": "t-node.with.1"'
assert_eq "J3 --jobs 3: the JSON equals --jobs 1 after normalising times, costs, stamps and paths" "$S_JS" "$(norm_json "$JF")"
assert_eq "J3 --jobs 3: the md equals --jobs 1 after normalising (section and row order, checks)" "$S_MD" "$(norm_md "$RES" "$WR")"
assert_eq "J3 --jobs 3: the Runs table keeps label order" "t-add.with.1
t-two.with.1
t-node.with.1" "$(grep -oE '^\| t-[a-z]+\.with\.1 \| graded' "$RES" | sed 's/^| //; s/ | graded//')"
for l in t-add.with.1 t-two.with.1 t-node.with.1; do
  assert_eq "J3 --jobs 3: $l has the same check lines (name and result) as --jobs 1" \
    "$(printf '%s\n' "$S_OUT" | grep "^$l [A-Z]" | LC_ALL=C sort)" "$(printf '%s\n' "$OUT" | grep "^$l [A-Z]" | LC_ALL=C sort)"
  assert_eq "D7 --jobs 3: $l: the stray check passes (the other runs' own entries are not strays)" "PASS" "$(chk "$l" 'nothing written outside the workdir')"
done
LB="$(labels_of "$OUT")"
if contiguous "$LB"; then t_ok "J3 --jobs 3: each run's output lines are one contiguous block"; else t_bad "J3 --jobs 3: each run's output lines are one contiguous block" "label sequence: $(printf '%s' "$LB" | tr '\n' ' ')"; fi
assert_eq "J3 --jobs 3: every run printed its lines (three blocks)" "3" "$(printf '%s\n' "$LB" | uniq | wc -l | tr -d ' ')"
assert_contains "J3 --jobs 3: the 'results:' line is printed" "$OUT" "results: $RES"
assert_contains "J3 --jobs 3: the 'json:' line is printed" "$OUT" "json: $JF"
if contiguous "$(printf 'a\nb\na\n')"; then t_bad "J3 helper: a b a is detected as interleaved" "not detected"; else t_ok "J3 helper: a b a is detected as interleaved"; fi

echo "J1 --jobs 2: at most 2 at a time"
cj_reset par 2 t-add.with.1 t-two.with.1
ro --cmd "bash $SA/conc.sh" --tasks t-add,t-two,t-node --jobs 2
assert_rc "J1 --jobs 2: exit 0" 0
P="$(peak)"
if [ "${P:-0}" = 2 ]; then t_ok "J1 --jobs 2: the peak overlap is exactly 2 (never 3)"; else t_bad "J1 --jobs 2: the peak overlap is exactly 2" "peak=[$P]; seen: $(tr '\n' ' ' < "$CJ/seen")"; fi
assert_eq "J1 --jobs 2: all three runs happened" "3" "$(ls "$CJ" | grep -c '^fin\.')"

# ================= D7 stray check =================
echo "D7 a run that writes outside its workroot entry is still caught under --jobs"
cj_reset par 3 t-add.with.1 t-two.with.1 t-node.with.1; printf 't-two.with.1\n' > "$CJ/stray"
ro --cmd "bash $SA/conc.sh" --tasks t-add,t-two,t-node --jobs 3
assert_rc "D7 --jobs 3 with a stray write: exit 1" 1
assert_eq "D7 the run that wrote stray-t-two.with.1.txt FAILs the stray check" "FAIL" "$(chk t-two.with.1 'nothing written outside the workdir')"
assert_contains "D7 the NOTE of that run names the stray entry" "$(printf '%s\n' "$OUT" | grep '^t-two.with.1 ')" "stray-t-two.with.1.txt"
assert_file "D7 the stray was written before the other runs ended" "$CJ/strayed"
for l in t-add.with.1 t-node.with.1; do
  assert_eq "D20 --jobs 3: $l PASSes the stray check although t-two wrote a stray meanwhile" "PASS" "$(chk "$l" 'nothing written outside the workdir')"
done
assert_eq "D20 --jobs 3: exactly one stray FAIL in the JSON checks (t-two's)" "1" "$(jget "$JF" '(j.runs||[]).reduce((n,r)=>n+(r.checks||[]).filter(c=>c.name==="nothing written outside the workdir"&&c.result==="FAIL").length,0)')"

# ================= --max-cost =================
echo "D7 --max-cost with --jobs: checked before each run starts against the finished runs; later runs are still skipped"
ro --cmd "bash $SA/cost06.sh" --tasks t-add,t-two,t-node --max-cost 1 --jobs 2
case "$RC" in 0|1) t_ok "D7 --max-cost with --jobs: skipping never changes the exit code (exit $RC)" ;; *) t_bad "D7 --max-cost with --jobs: exit 0 or 1" "exit $RC: $OUT" ;; esac
assert_eq "D7 the first two runs (started with nothing spent) were not skipped" "0" "$(printf '%s\n' "$OUT" | grep -cE '^t-(add|two)\.with\.1 SKIPPED')"
assert_contains "D7 t-node (started after 0.6 was spent) is skipped" "$OUT" "t-node.with.1 SKIPPED"
assert_no_path "D7 the budget stopped the later run: its adapter never ran" "$SR/t-node.with.1.args"
assert_file "D7 the first run's adapter ran" "$SR/t-add.with.1.args"

# ================= --variant =================
JOBS_OUTER_BASE="--harness claude --tasks-dir $T --tasks t-add"
jobs_variant_suite --harness claude --tasks-dir "$T" --tasks t-add,t-two
t_summary
