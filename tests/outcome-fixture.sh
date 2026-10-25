#!/usr/bin/env bash
# Shared setup of tests/test-outcome-runner.sh, test-outcome-isolation.sh and test-outcome-report.sh (v0.27.0 lane O,
# slices S1-S3 of evals/run-outcome.sh). Source it after lib.sh, evals-fixture.sh and evals-arms-fixture.sh (lane E's fake
# claude/codex/opencode in $FK, the stand-in HOME $GH, jget, physdir). It is not a suite: run-all.sh only starts tests/test-*.sh.
# Never calls a real harness: every run uses a --cmd stub adapter, or --harness with $FK first on PATH.
# Three tiny fixture tasks in $T (not the real corpus, to keep the suites fast):
#   t-add  bash: calc.sh add() subtracts; F2P tests/add.f2p.sh, P2P tests/mul.p2p.sh
#   t-two  bash: lib.sh inc() adds 2; F2P tests/a.f2p.sh tests/b.f2p.sh, P2P tests/c.p2p.sh
#   t-node node: src/m.js add() subtracts; F2P tests/add.f2p.test.js, P2P tests/mul.p2p.test.js
# and one broken task in $TB (t-bad: setup.sh exits 1). Every hidden test appends `pwd -P` (the dir it runs in, i.e. the
# grading copy) to $GR/<id>.<name>, so a suite can see where grading happened and that it no longer exists.
OUTCOME="$PB_ROOT/evals/run-outcome.sh"
CAN="PB-HIDDEN-""CANARY"   # split so this file is not itself a canary hit for greps over the repo
# shellcheck disable=SC2034   # NONINT, ISO and HAS_TIMEOUT are read by the suites
NONINT="(Non-interactive run: nobody will answer questions here. Use the playbook's non-interactive rule.)"
# shellcheck disable=SC2034
ISO='without arm: no playbook file read and no playbook Skill call'
T="$(mk_tmp)"    # fixture tasks dir
TB="$(mk_tmp)"   # tasks dir with a task whose setup fails
GR="$(mk_tmp)"   # where hidden tests record the dir they ran in
# GRN: $GR as a native program reads it from a file (node/python sources). Git Bash converts /tmp paths only in
# arguments and env, never in file contents, so on Windows use the mixed C:/... form; elsewhere GRN = GR.
GRN="$GR"; if command -v cygpath >/dev/null 2>&1; then GRN="$(cygpath -m "$GR")"; fi
SA="$(mk_tmp)"   # stub adapters
SR="$(mk_tmp)"   # what the stubs recorded: $SR/<label>.<what>
FS="$(mk_tmp)"   # scratch: base repos for the patches

# fx_setup FILE BODY -> a setup.sh that refuses a non-empty target, writes BODY's files in $1 and commits them with a fixed date
fx_setup() {
  { printf '%s\n' '#!/usr/bin/env bash' 'set -eu' 'dest="$1"' \
      'if [ -d "$dest" ] && [ -n "$(ls -A "$dest")" ]; then echo "setup: refusing non-empty $dest" >&2; exit 2; fi' \
      'mkdir -p "$dest/tests"' 'cd "$dest"' 'printf "visible tests live here\n" > tests/README.md'
    printf '%s\n' "$2"
    printf '%s\n' 'git init -q' 'git config user.name fixture' 'git config user.email fixture@example.invalid' \
      'git config commit.gpgsign false' 'git config core.autocrlf false' 'git add -A' \
      "GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z' git commit -q -m init"
  } > "$1"
  chmod +x "$1" 2>/dev/null
}
# fx_task DIR ID LANGUAGE F2P P2P PROMPT SETUP-BODY -> task dir DIR/ID with task.conf, prompt.md, setup.sh
fx_task() {
  mkdir -p "$1/$2/hidden/tests"
  printf 'id=%s\nlanguage=%s\nsource=oss:fixture\nexpected_weight=Lite\nfail_to_pass=%s\npass_to_pass=%s\n' "$2" "$3" "$4" "$5" > "$1/$2/task.conf"
  printf '%s\n' "$6" > "$1/$2/prompt.md"
  fx_setup "$1/$2/setup.sh" "$7"
}
# fx_patch ID FILE SED -> solution.patch of ID: SED applied to FILE of a fresh setup repo
fx_patch() {
  local r="$FS/$1"
  bash "$T/$1/setup.sh" "$r" >/dev/null 2>&1 || { echo "fixture: setup of $1 failed" >&2; return 1; }
  sed "$3" "$r/$2" > "$r/$2.new" && mv "$r/$2.new" "$r/$2"
  git -C "$r" diff > "$T/$1/solution.patch"
}
# hidden tests: a bash file sources the repo's script; every file records where it ran
h_bash() { # ID FILE SCRIPT ASSERTION
  printf '#!/usr/bin/env bash\n# %s:%s\npwd -P >> %s\n. ./%s\n%s\n' "$CAN" "$1" "'$GR/$1.${2##*/}'" "$3" "$4" > "$T/$1/hidden/$2"
}
h_node() { # ID FILE ASSERTION
  printf "// %s:%s\nrequire('fs').appendFileSync(%s, process.cwd() + '\\\\n');\nconst test = require('node:test');\nconst assert = require('node:assert/strict');\nconst m = require('../src/m');\ntest('t', () => { %s; });\n" \
    "$CAN" "$1" "'$GRN/$1.${2##*/}'" "$3" > "$T/$1/hidden/$2"
}

fx_task "$T" t-add bash tests/add.f2p.sh tests/mul.p2p.sh \
  'add in calc.sh is wrong: `add 2 3` prints -1, it should print 5. Please fix it.' \
  "printf '%s\n' 'add() { echo \$(( \$1 - \$2 )); }' 'mul() { echo \$(( \$1 * \$2 )); }' > calc.sh"
fx_patch t-add calc.sh 's/\$1 - \$2/$1 + $2/'
h_bash t-add tests/add.f2p.sh calc.sh '[ "$(add 2 3)" = 5 ]'
h_bash t-add tests/mul.p2p.sh calc.sh '[ "$(mul 2 3)" = 6 ]'

fx_task "$T" t-two bash "tests/a.f2p.sh tests/b.f2p.sh" tests/c.p2p.sh \
  'inc in lib.sh should add one, it adds two. Please fix it.' \
  "printf '%s\n' 'inc() { echo \$(( \$1 + 2 )); }' 'dbl() { echo \$(( \$1 * 2 )); }' > lib.sh"
fx_patch t-two lib.sh 's/+ 2/+ 1/'
h_bash t-two tests/a.f2p.sh lib.sh '[ "$(inc 1)" = 2 ]'
h_bash t-two tests/b.f2p.sh lib.sh '[ "$(inc 41)" = 42 ]'
h_bash t-two tests/c.p2p.sh lib.sh '[ "$(dbl 4)" = 8 ]'

fx_task "$T" t-node node tests/add.f2p.test.js tests/mul.p2p.test.js \
  'add in src/m.js subtracts. Please fix it.' \
  "mkdir -p src; printf '%s\n' 'exports.add = (a, b) => a - b;' 'exports.mul = (a, b) => a * b;' > src/m.js"
fx_patch t-node src/m.js 's/a - b/a + b/'
h_node t-node tests/add.f2p.test.js 'assert.equal(m.add(2, 3), 5)'
h_node t-node tests/mul.p2p.test.js 'assert.equal(m.mul(2, 3), 6)'

mkdir -p "$TB/t-bad/hidden/tests"
printf 'id=t-bad\nlanguage=bash\nsource=oss:fixture\nexpected_weight=Lite\nfail_to_pass=tests/x.f2p.sh\npass_to_pass=\n' > "$TB/t-bad/task.conf"
printf 'Fix it.\n' > "$TB/t-bad/prompt.md"
printf '#!/usr/bin/env bash\necho "setup: cannot build" >&2\nexit 1\n' > "$TB/t-bad/setup.sh"
printf '#!/usr/bin/env bash\n# %s:t-bad\nexit 1\n' "$CAN" > "$TB/t-bad/hidden/tests/x.f2p.sh"

# mk_stub NAME BODY -> $SA/NAME.sh, run as `bash $SA/NAME.sh <workdir> <prompt-file>`. The prelude records the arguments, the
# hidden destination paths that exist in the workdir at start ($SR/<label>.hidden, empty = none), a copy of the prompt file
# ($SR/<label>.prompt), the workdir's HEAD at start ($SR/<label>.head), TMPDIR, PLAYBOOK_HOME (and
# its files and conf), HOME and the PB_EVAL_* variables, prints STUB-OUT-<label> / STUB-ERR-<label>, then cds into the
# workdir. `solve` applies the task's solution.patch. l = label, id = task id.
mk_stub() {
  { printf '#!/usr/bin/env bash\nSR=%s\nTASKS=%s\n' "'$SR'" "'$T'"
    cat <<'EOF'
wd="$1"; pf="$2"; l="$(basename "$wd")"; id="${l%%.*}"
printf '%s\n%s\n' "$wd" "$pf" > "$SR/$l.args"
cp "$pf" "$SR/$l.prompt" 2>/dev/null
git -C "$wd" rev-parse HEAD > "$SR/$l.head" 2>/dev/null
for f in $(sed -n 's/^fail_to_pass=//p; s/^pass_to_pass=//p' "$TASKS/$id/task.conf" 2>/dev/null); do
  if [ -e "$wd/$f" ]; then printf '%s\n' "$f"; fi
done > "$SR/$l.hidden"
printf '%s\n' "${TMPDIR-UNSET}" > "$SR/$l.tmp"
printf '%s\n' "${PLAYBOOK_HOME-UNSET}" > "$SR/$l.ph"
if [ -n "${PLAYBOOK_HOME:-}" ] && [ -d "$PLAYBOOK_HOME" ]; then
  (cd "$PLAYBOOK_HOME" && find . -type f | LC_ALL=C sort) > "$SR/$l.phfiles"
  cat "$PLAYBOOK_HOME/.agents/playbook.conf" > "$SR/$l.conf" 2>/dev/null
fi
printf '%s\n' "$HOME" > "$SR/$l.home"
env | grep '^PB_EVAL_' | LC_ALL=C sort > "$SR/$l.env"
if [ -n "${PB_EVAL_SETTINGS:-}" ] && [ -f "$PB_EVAL_SETTINGS" ]; then cp "$PB_EVAL_SETTINGS" "$SR/$l.settings"; fi
echo "STUB-OUT-$l"
echo "STUB-ERR-$l" >&2
cd "$wd" || exit 3
solve() { git apply "$TASKS/$id/solution.patch"; }
tu() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"%s","input":%s}]}}\n' "$1" "$2"; }
init() { echo '{"type":"system","subtype":"init","session_id":"s1","skills":[],"slash_commands":[]}'; }
result() { printf '{"type":"result","subtype":"success","is_error":false,"total_cost_usd":%s,"result":"Done."}\n' "$1"; }
EOF
    printf '%s\n' "$2"
  } > "$SA/$1.sh"
}
mk_stub solve 'solve'
mk_stub idle ':'
mk_stub breakp2p 'solve; printf "%s\n" "mul() { echo 0; }" >> calc.sh'
mk_stub cheat 'printf "exit 0\n" > tests/add.f2p.sh; printf "exit 0\n" > tests/a.f2p.sh'
mk_stub exit7 'exit 7'
mk_stub auth 'solve; echo "Error: Invalid API key. Please run /login"'
mk_stub slow 'sleep 5; solve'
mk_stub canary 'solve; cat "$TASKS/$id/hidden/tests/"*'
mk_stub stray 'solve; echo x > "$(dirname "$wd")/stray-$l.txt"'
mk_stub oracle 'case "$l" in t-add.with.3) ;; *) solve ;; esac'
mk_stub errk2 'case "$l" in t-add.with.2) exit 7 ;; esac; solve'
mk_stub cost 'solve; init; case "$l" in *.1) result 0.2 ;; *) result 0.4 ;; esac'
mk_stub cost06 'solve; init; result 0.6'
mk_stub skill 'solve; init; case "$l" in *.without.*) tu Skill "{\"skill\":\"playbook-tdd\"}" ;; esac; result 0.01'
# snoop: during its run it lists and greps for the canary its workdir, the whole workroot (earlier repeats and the other arm),
# the regular files of the workroot's parent (depth 1), the workdir's git history (all refs, with patches), its TMPDIR and
# PLAYBOOK_HOME, and env. It prints nothing (its transcript must stay clean): $SR/<label>.snoop gets CLEAN or HIT, plus
# ENVHIT when an env value holds the tasks dir path. Then it solves the task.
mk_stub snoop 'c="PB-HIDDEN-"; c="${c}CANARY:"
wr="$(dirname "$wd")"; par="$(dirname "$wr")"
{ ls -laR "$wd"; grep -rs -- "$c" "$wd"
  ls -laR "$wr"; grep -rs -- "$c" "$wr"
  ls -la "$par"; for f in "$par"/* "$par"/.[!.]*; do if [ -f "$f" ]; then grep -s -- "$c" "$f"; fi; done
  git -C "$wd" log --all -p
  if [ -n "${TMPDIR:-}" ]; then ls -laR "$TMPDIR"; grep -rs -- "$c" "$TMPDIR"; fi
  if [ -n "${PLAYBOOK_HOME:-}" ]; then ls -laR "$PLAYBOOK_HOME"; grep -rs -- "$c" "$PLAYBOOK_HOME"; fi
  env
} > "$SR/$l.dump" 2>&1
if grep -q -- "$c" "$SR/$l.dump"; then echo HIT > "$SR/$l.snoop"; else echo CLEAN > "$SR/$l.snoop"; fi
if env | grep -qF -- "$TASKS"; then echo ENVHIT >> "$SR/$l.snoop"; fi
solve'

# peek (review fix 4: no leak between runs): before it solves, it records what of OTHER runs it can reach from its workdir:
# $SR/<label>.sib = workroot entries besides its own <label>, <label>.log, <label>.prompt and the marker (sibling workdirs,
# earlier transcripts or prompts), $SR/<label>.tr = STUB-OUT-<other label> lines found under the workroot's parent (an
# earlier run's transcript), $SR/<label>.fix = files under the workroot's parent holding t-add's fix (an earlier run's
# solution). Empty files = nothing reachable.
mk_stub peek 'wr="$(dirname "$wd")"; par="$(dirname "$wr")"
(cd "$wr" && ls -A) | grep -vxF -e "$l" -e "$l.log" -e "$l.prompt" -e .pb-eval-workroot > "$SR/$l.sib"
grep -rhos -- "STUB-OUT-[A-Za-z0-9.-]*" "$par" | grep -vxF "STUB-OUT-$l" | LC_ALL=C sort -u > "$SR/$l.tr"
grep -rlsF -- "\$1 + \$2" "$par" > "$SR/$l.fix"
solve'
# python3 stubs for the t-py task of test-outcome-isolation.sh (review fix 5): pysolve fixes m.py; pyshadow and pyshadowmod
# do not fix anything but leave a stdlib shadow in the repo root (a unittest/ package, a unittest.py module) whose
# entry point exits 0, so `python3 -m unittest F` run from the repo root would "pass" every hidden test.
mk_stub pysolve 'sed "s/a - b/a + b/" m.py > m.py.new && mv m.py.new m.py'
mk_stub pyshadow 'mkdir -p unittest; : > unittest/__init__.py; printf "%s\n" "import sys" "sys.exit(0)" > unittest/__main__.py'
mk_stub pyshadowmod 'printf "%s\n" "import sys" "sys.exit(0)" > unittest.py'

# ro [ARGS...] -> run evals/run-outcome.sh on the tasks dir $T with HOME=$GH, $FK first on PATH, TMPDIR=$RT (a fresh dir, so a
# suite can see what the runner leaves there) and a fresh runner-owned workroot WR = $WP/wr (its parent WP is a dir of the
# suite, so a depth-1 snoop of the parent stays inside it). Results in OD: RES (md) and JF (json); EV = ${RES%.md}.runs, the
# evidence dir next to --out where each run's transcript (<label>.log) and diff (<label>.diff) are kept outside the workroot
# (review fix 4, DECISION in .agents/handoff/decisions.md). Clears $SR, $GR and $FR.
ro() {
  WP="$(mk_tmp)"; WR="$WP/wr"; mkdir -p "$WR"; : > "$WR/.pb-eval-workroot"
  OD="$(mk_tmp)"; RES="$OD/results.md"; JF="$OD/results.json"; EV="$OD/results.runs"; RT="$(mk_tmp)"
  rm -f "$SR"/* "$GR"/* "$FR"/*
  run env -u PLAYBOOK_HOME -u PB_EVAL_ARM -u PB_EVAL_MODEL -u PB_EVAL_SETTINGS HOME="$GH" PATH="$FK:$PATH" TMPDIR="$RT" \
    bash "$OUTCOME" --tasks-dir "$T" --workroot "$WR" --out "$RES" "$@"
}
# chk LABEL NAME -> the result(s) of check NAME in run LABEL of $JF (comma-joined), "none" when absent
chk() { jget "$JF" "((((j.runs||[]).find(r=>r.label===\"$1\")||{}).checks||[]).filter(c=>c.name===\"$2\").map(c=>c.result).join(\",\"))||\"none\""; }
# rfield LABEL FIELD -> FIELD of run LABEL as JSON ("none" when there is no such run)
rfield() { jget "$JF" "(function(){const r=(j.runs||[]).find(r=>r.label===\"$1\");return r?JSON.stringify(r[\"$2\"]):\"none\"})()"; }
# sitem TASK ARM KEY FIELDS... -> the FIELDS of the summary item (TASK, ARM, KEY), space-joined
sitem() { local t="$1" a="$2" k="$3"; shift 3
  jget "$JF" "(function(){const e=(j.summary||[]).find(e=>e.scenario===\"$t\"&&e.arm===\"$a\"&&e.key===\"$k\");if(!e)return \"none\";return [$(printf '"%s",' "$@")].map(f=>JSON.stringify(e[f])).join(\" \")})()"; }
# leftovers DIR -> the entries of DIR, space-joined ("" when empty)
leftovers() { (cd "$1" 2>/dev/null && ls -A | tr '\n' ' '); }
# under PATH DIR -> 0 when PATH is DIR or below it (string prefix, both as given)
under() { case "$1" in "$2" | "$2"/*) return 0 ;; esac; return 1; }
HAS_TIMEOUT=0
# shellcheck disable=SC2034
if command -v timeout >/dev/null 2>&1 && timeout 5 true 2>/dev/null; then HAS_TIMEOUT=1; fi
