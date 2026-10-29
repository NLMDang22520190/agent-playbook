#!/usr/bin/env bash
# Tests for `tools/release-gate.sh --check [REV]` (v0.32.0 slice S2: AC3, AC3', m-b, m-c; D1, D6). The mode reads only the
# COMMITTED tree at REV: it finds the pb-evals/1 files of every evals/results/gate-*/ dir, groups them by (playbook_commit,
# harness, model), recomputes the AC2 verdict, and accepts a group when its commit C is REV or an ancestor of REV and nothing
# outside evals/results/ changed between C and REV. It spends nothing and never calls a runner. The tool is copied into
# throw-away repos whose run-evals.sh / run-outcome.sh are RECORDING fakes (any call is a failure); the gate dirs are synthetic
# pb-evals/1 files (a variant object with sha = the gate commit, 5 graded runs per arm) pooled by the real
# `release-gate.sh --pool-only` so gate.json is the real one. Never calls a real harness. Needs node.
. "$(dirname "$0")/lib.sh"
GATE="$PB_ROOT/tools/release-gate.sh"
command -v node >/dev/null 2>&1 || { t_skip 1 "node missing"; t_summary; exit $?; }
command -v git >/dev/null 2>&1 || { t_skip 1 "git missing"; t_summary; exit $?; }

W="$(mk_tmp)"
mkdir -p "$W/home" "$W/tmp" "$W/ctmp"
CALLS="$W/calls.log"; : > "$CALLS"
TASKS="pattern-15-erase-account-ambiguous,pattern-24-merge-duplicate-customers,pattern-26-consistent-price-rounding"

# mk_runner FILE AUTO-or-empty: a fake runner that only records that it was called
mk_runner() {
  { printf '#!/usr/bin/env bash\n'
    [ -z "$2" ] || printf 'AUTO="%s"\n' "$2"
    printf 'printf "%%s %%s\\n" "$0" "$*" >> '"'%s'"'\nexit 0\n' "$CALLS"; } > "$1"
  chmod 755 "$1"
}
# new_repo NAME AUTO -> $W/NAME: tools, fake runners (AUTO line), task dirs, one base commit
new_repo() {
  local r="$W/$1"
  mkdir -p "$r/tools" "$r/evals/tasks" "$r/skills"
  cp -p "$GATE" "$r/tools/release-gate.sh"
  cp -p "$PB_ROOT/tools/eval-delta.sh" "$r/tools/eval-delta.sh"
  local t
  for t in $(printf '%s' "$TASKS" | tr ',' ' '); do mkdir -p "$r/evals/tasks/$t"; printf 'x\n' > "$r/evals/tasks/$t/prompt.md"; done
  mk_runner "$r/evals/run-evals.sh" "$2"
  mk_runner "$r/evals/run-outcome.sh" ""
  printf '# fixture\n' > "$r/README.md"
  ( cd "$r" && git init -q && git config user.email t@example.invalid && git config user.name tester &&
    git config commit.gpgsign false && git config core.autocrlf false && git add -A && git commit -qm base ) || t_bad "fixture $1" "git init failed"
}
hd() { git -C "$1" rev-parse HEAD; }
# gcommit REPO MSG FILE CONTENT : write a file (relative to REPO) and commit it
gcommit() { mkdir -p "$(dirname "$1/$3")"; printf '%s\n' "$4" > "$1/$3"; git -C "$1" add -A && git -C "$1" commit -qm "$2"; }
# gadd REPO PATH MSG : commit only PATH (a results dir)
gadd() { git -C "$1" add -- "$2" && git -C "$1" commit -qm "$3"; }
# jfile OUT COMMIT MODEL ITEMS INVERT : a pb-evals/1 file, 5 graded runs per arm and item; with passes, without fails
# (items in INVERT: with fails, without passes); the variant object names COMMIT.
jfile() {
  local out="$1" commit="$2" model="$3" list="$4" inv="${5:-}" runs="" sep="" s i arm r
  for s in $(printf '%s' "$list" | tr ',' ' '); do
    i=1
    while [ "$i" -le 5 ]; do
      for arm in with without; do
        r=PASS; [ "$arm" = without ] && r=FAIL
        case ",$inv," in *",$s,"*) if [ "$r" = PASS ]; then r=FAIL; else r=PASS; fi ;; esac
        runs="$runs$sep{\"scenario\":\"$s\",\"arm\":\"$arm\",\"k\":$i,\"label\":\"$s.$arm.$i\",\"status\":\"graded\",\"error\":null,\"isolation\":\"adapter\",\"fixture_tree\":\"t-$s\",\"prompt_sha\":\"p-$s\",\"cost_usd\":0.1,\"seconds\":5,\"notes\":[],\"dropped_user_lines\":0,\"checks\":[{\"name\":\"x\",\"key\":\"x\",\"result\":\"$r\"}]}"
        sep=","
      done
      i=$((i + 1))
    done
  done
  printf '{"schema":"pb-evals/1","playbook_commit":"%s","playbook_version":"0.30.0","harness":"claude","model":"%s","arms":["with","without"],"repeat":5,"max_cost":null,"interactive":false,"started":"2026-10-27T10:00:00Z","workroot":"<tmp>/w","out":"x.md","variant":{"tree":"<variant>","version":"0.30.0","sha":"%s","end_check":"ok"},"runs":[%s],"summary":[]}\n' \
    "$commit" "$model" "$commit" "$runs" > "$out"
}
auto_of() { sed -n 's/^AUTO="\(.*\)"$/\1/p' "$1/evals/run-evals.sh" | head -n 1 | tr -s ' ' ','; }
# mkgate REPO NAME MODEL [INVERT] [ITEMS] : gate dir NAME (not committed) for the commit at HEAD of REPO: a behaviour file over
# AUTO (or ITEMS), an outcome file over the three tasks, then the real `--pool-only` writes gate.json and .gitignore
mkgate() {
  local r="$1" n="$2" m="$3" inv="${4:-}" items="${5:-}" c d
  c="$(hd "$r")"; d="$r/evals/results/$n"; mkdir -p "$d"
  [ -n "$items" ] || items="$(auto_of "$r")"
  jfile "$d/behaviour-$m.json" "$c" "$m" "$items" "$inv"
  jfile "$d/outcome-$m.json" "$c" "$m" "$TASKS" "$inv"
  ( cd "$r" && env HOME="$W/home" TMPDIR="$W/tmp" bash tools/release-gate.sh --harness claude --model "$m" --pool-only --out-dir "evals/results/$n" >/dev/null 2>&1 )
}
# chk REPO ARGS... -> OUT, RC: the tool of that repo with --check, HOME and TMPDIR fenced
chk() {
  local r="$1"; shift
  RC=0; OUT="$(cd "$r" && env HOME="$W/home" TMPDIR="$W/ctmp" bash tools/release-gate.sh --check "$@" 2>&1)" || RC=$?
}
nopass() { case "$2" in *"release gate: pass"*) t_bad "$1" "output has a pass line: [$2]" ;; *) t_ok "$1" ;; esac; }

# ---------------------------------------------------------------------------------------------------------------------------
echo "AC3 pass: a gate dir committed at C, REV = the results commit"
new_repo a "E1 E2 E3"
gcommit "$W/a" "c1" README.md "# c1"
CA="$(hd "$W/a")"; CA12="$(printf '%s' "$CA" | cut -c1-12)"
mkgate "$W/a" gate-a m1
gadd "$W/a" evals/results/gate-a "results a"
RA="$(hd "$W/a")"; BA="$(git -C "$W/a" rev-parse --abbrev-ref HEAD)"
assert_file "AC3 fixture: gate.json was written by the real --pool-only" "$W/a/evals/results/gate-a/gate.json"
assert_eq "AC3 fixture: the real pool-only says pass for the good run" "pass" "$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).verdict)' "$W/a/evals/results/gate-a/gate.json")"
BEFORE="$(ls -A "$W/ctmp")"
chk "$W/a" "$RA"
assert_rc "AC3 --check <results commit> -> exit 0" 0
assert_contains "AC3 the pass line names the commit" "$OUT" "release gate: pass (commit $CA12"
assert_contains "AC3 the pass line names harness, model, min graded and the dir" "$OUT" ", harness claude, model m1, min graded 5 per arm, evals/results/gate-a)"
assert_eq "AC3 the extraction temp dir is removed (TMPDIR listing unchanged, pass)" "$BEFORE" "$(ls -A "$W/ctmp")"
chk "$W/a"
assert_rc "AC3 REV defaults to HEAD -> exit 0" 0
assert_contains "AC3 the default-REV run prints the pass line" "$OUT" "release gate: pass (commit $CA12"

echo "AC3 reads only the committed tree"
printf 'garbage\n' > "$W/a/evals/results/gate-a/behaviour-m1.json"
printf '{"verdict":"fail"}\n' > "$W/a/evals/results/gate-a/gate.json"
chk "$W/a" "$RA"
assert_rc "AC3 a work-tree edit that breaks committed files does not change the result -> exit 0" 0
git -C "$W/a" checkout -q -- .
new_repo z "E1 E2 E3"
gcommit "$W/z" "c1" README.md "# c1"
mkgate "$W/z" gate-z m1
chk "$W/z"
assert_rc "AC3 gate files only in the work tree (uncommitted) -> exit 1" 1
assert_contains "AC3 ... with the no-result line" "$OUT" "no gate result under evals/results/gate-*/ at REV"
nopass "AC3 ... and no pass line" "$OUT"
chk "$W/a" "$CA"
assert_rc "AC3 an explicit REV without results (the gate commit itself) -> exit 1" 1
assert_contains "AC3 ... with the no-result line" "$OUT" "no gate result under evals/results/gate-*/ at REV"
git -C "$W/a" checkout -q "$CA"
chk "$W/a"
assert_rc "AC3 REV defaults to HEAD, not to a branch: HEAD at the gate commit -> exit 1" 1
git -C "$W/a" checkout -q "$BA"

echo "AC3'/m-b the AUTO list and the default tasks come from C, not from the work tree"
sed 's/^AUTO="E1 E2 E3"$/AUTO="E1 E2 E3 E4"/' "$W/a/evals/run-evals.sh" > "$W/auto.tmp" && cat "$W/auto.tmp" > "$W/a/evals/run-evals.sh"
chk "$W/a" "$RA"
assert_rc "AC3' an uncommitted AUTO edit in the work tree does not change the result -> exit 0" 0
assert_contains "AC3' ... the pass line is the same" "$OUT" "release gate: pass (commit $CA12"
git -C "$W/a" checkout -q -- .
sed 's/^DEFAULT_TASKS="\(.*\)"$/DEFAULT_TASKS="\1,pattern-01-option-value-label"/' "$W/a/tools/release-gate.sh" > "$W/dt.tmp" && cat "$W/dt.tmp" > "$W/a/tools/release-gate.sh"
chk "$W/a" "$RA"
assert_rc "m-b an uncommitted DEFAULT_TASKS edit in the work tree does not change the result -> exit 0" 0
git -C "$W/a" checkout -q -- .
new_repo l "E1 E2 E3 E4"
gcommit "$W/l" "c1" README.md "# c1"
mkgate "$W/l" gate-l m1 "" "E1,E2,E3"
gadd "$W/l" evals/results/gate-l "results l"
chk "$W/l"
assert_rc "AC3' AUTO at C has E4 but the files do not -> exit 1" 1
assert_contains "AC3' ... the reason names E4" "$OUT" "E4"

echo "D1 nothing outside evals/results may change between C and REV"
git -C "$W/a" checkout -q -b okres "$RA"
gcommit "$W/a" "notes under results" evals/results/notes/note.md "note"
chk "$W/a"
assert_rc "D1 a later commit that touches only evals/results -> still exit 0" 0
git -C "$W/a" checkout -q "$BA"
gcommit "$W/a" "outside" b1.txt "b"
printf 'a\n' > "$W/a/a1.txt"; git -C "$W/a" add -A && git -C "$W/a" commit -qm "outside 2"
chk "$W/a"
assert_rc "D1 a later commit that changes a path outside evals/results -> exit 1" 1
L="$(printf '%s\n' "$OUT" | grep 'changes outside evals/results since')"
assert_contains "D1 the line says changes outside evals/results since C" "$L" "changes outside evals/results since "
assert_contains "D1 ... and names the first path (git diff --name-only order)" "$L" "a1.txt"
assert_not_contains "D1 ... only the first path" "$L" "b1.txt"
nopass "D1 no pass line" "$OUT"
chk "$W/a" "$RA"
assert_rc "AC3 an explicit older REV (before the outside change) still passes -> exit 0" 0

echo "AC3 C must be an ancestor of REV"
git -C "$W/a" checkout -q -b other "$(git -C "$W/a" rev-list --max-parents=0 HEAD | head -n 1)"
gcommit "$W/a" "other work" other.txt "o"
git -C "$W/a" cherry-pick "$RA" >/dev/null 2>&1 || t_bad "fixture a" "cherry-pick failed"
chk "$W/a"
assert_rc "AC3 results cherry-picked onto a branch that does not contain C -> exit 1" 1
nopass "AC3 ... no pass line" "$OUT"
git -C "$W/a" checkout -q "$BA"

echo "AC2/AC3 the verdict is recomputed from the committed pb-evals files"
new_repo f "E1 E2 E3"
gcommit "$W/f" "c1" README.md "# c1"
mkgate "$W/f" gate-f m1 E2
assert_eq "AC3 fixture: the real pool-only says fail for the inverted item" "fail" "$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).verdict)' "$W/f/evals/results/gate-f/gate.json")"
gadd "$W/f" evals/results/gate-f "results f (fail)"
chk "$W/f"
assert_rc "AC3 a failing run -> exit 1" 1
assert_contains "AC3 the verdict reason is printed (the failing item)" "$OUT" "E2"
assert_not_contains "AC3 an honest fail does not claim gate.json says pass" "$OUT" "gate.json says pass"
node -e 'const fs=require("fs"),f=process.argv[1],j=JSON.parse(fs.readFileSync(f,"utf8"));j.verdict="pass";j.verdict_reasons=[];fs.writeFileSync(f,JSON.stringify(j,null,2)+"\n")' "$W/f/evals/results/gate-f/gate.json"
gadd "$W/f" evals/results/gate-f "hand-edited gate.json"
chk "$W/f"
assert_rc "AC3 gate.json hand-edited to pass over failing files -> exit 1" 1
assert_contains "AC3 ... reported as a disagreement" "$OUT" "gate.json says pass, the recomputed verdict is fail"
nopass "AC3 ... no pass line" "$OUT"
new_repo h "E1 E2 E3"
gcommit "$W/h" "c1" README.md "# c1"
mkdir -p "$W/h/evals/results/gate-h"
printf '{"schema":"pb-gate/1","verdict":"pass","verdict_reasons":[]}\n' > "$W/h/evals/results/gate-h/gate.json"
gadd "$W/h" evals/results/gate-h "hand-written gate.json"
chk "$W/h"
assert_rc "AC3 a hand-written gate.json with no pb-evals files -> exit 1" 1
nopass "AC3 ... no pass line" "$OUT"

echo "AC3' groups by (playbook_commit, harness, model); several gate dirs"
new_repo g "E1 E2 E3"
gcommit "$W/g" "c1" README.md "# c1"
CG="$(hd "$W/g")"
mkgate "$W/g" gate-g m1
jfile "$W/g/evals/results/gate-g/behaviour-m2.json" "$CG" m2 "E1"
jfile "$W/g/evals/results/gate-g/behaviour-old.json" "0000000000000000000000000000000000000000" m1 "E1,E2,E3"
gadd "$W/g" evals/results/gate-g "results g (extra groups)"
chk "$W/g"
assert_rc "AC3' a dir with a passing group plus files of another model and commit -> exit 0" 0
assert_contains "AC3' ... the passing group counts (model m1)" "$OUT" ", harness claude, model m1, min graded 5 per arm, evals/results/gate-g)"
# build_multi NAME NEWINV : an old gate dir at C_old, a commit outside evals/results, a new gate dir at C_new
build_multi() {
  new_repo "$1" "E1 E2 E3"
  gcommit "$W/$1" "c1" README.md "# c1"
  mkgate "$W/$1" gate-old m1; gadd "$W/$1" evals/results/gate-old "results old"
  gcommit "$W/$1" "c2 outside results" README.md "# c2"
  mkgate "$W/$1" gate-new m1 "$2"; gadd "$W/$1" evals/results/gate-new "results new"
}
build_multi m ""
chk "$W/m"
assert_rc "AC3' an old dir failing on D1 and a new passing dir -> exit 0" 0
assert_contains "AC3' ... the new dir is the one named" "$OUT" "evals/results/gate-new)"
assert_not_contains "AC3' ... the old dir's reason is not listed when one passes" "$OUT" "changes outside evals/results"
build_multi n E2
chk "$W/n"
assert_rc "AC3' nothing passes (old fails D1, new fails the verdict) -> exit 1" 1
assert_contains "AC3' ... the old dir's reason is listed" "$OUT" "changes outside evals/results since "
assert_contains "AC3' ... the old dir is named" "$OUT" "gate-old"
assert_contains "AC3' ... the new dir is named" "$OUT" "gate-new"
assert_contains "AC3' ... the new dir's verdict reason is listed (E2)" "$OUT" "E2"
BEFORE="$(ls -A "$W/ctmp")"
chk "$W/n"
assert_eq "AC3 the extraction temp dir is removed (TMPDIR listing unchanged, fail)" "$BEFORE" "$(ls -A "$W/ctmp")"

echo "usage (exit 2) and environment (exit 3)"
chk "$W/a" --bogus
assert_rc "AC3 --check with an unknown option -> exit 2" 2
assert_not_contains "AC3 ... --check itself is known" "$OUT" "unknown option: --check"
chk "$W/a" "$RA" extra
assert_rc "AC3 --check with extra arguments -> exit 2" 2
assert_not_contains "AC3 ... --check itself is known (extra args)" "$OUT" "unknown option: --check"
chk "$W/a" nosuchrev-xyz
assert_rc "AC3 REV that is not a commit -> exit 3" 3
assert_not_contains "AC3 ... --check itself is known (bad REV)" "$OUT" "unknown option: --check"
chk "$W/a" "$(git -C "$W/a" rev-parse "$RA^{tree}")"
assert_rc "AC3 REV that is a tree, not a commit -> exit 3" 3
mkdir -p "$W/nogit/tools"; cp -p "$GATE" "$W/nogit/tools/release-gate.sh"; cp -p "$PB_ROOT/tools/eval-delta.sh" "$W/nogit/tools/eval-delta.sh"
chk "$W/nogit"
assert_rc "AC3 not a git repository -> exit 3" 3
assert_not_contains "AC3 ... --check itself is known (no repo)" "$OUT" "unknown option: --check"

echo "AC3 spends nothing"
assert_eq "AC3 --check never called a runner (all the runs above)" "0" "$(wc -l < "$CALLS" | tr -d ' ')"

t_summary
