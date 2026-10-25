#!/usr/bin/env bash
# Tests for evals/check-tasks.sh (v0.27.0 lane O, slice S0a, AC19-AC20): the offline self-check of outcome-eval tasks.
# Every task here is a fixture made in a temp tasks dir; the real corpus is tested in test-outcome-corpus.sh.
# A fixture task: task.conf, prompt.md, setup.sh (builds a tiny git repo in $1), solution.patch, hidden/tests/*.
# The fixture repo holds a visible tests/f2p.sh that always passes, so a self-check that ran the repo's own file
# instead of copying the hidden one over it (same relative path) would see F2P pass before the fix.
. "$(dirname "$0")/lib.sh"
CHECK="$PB_ROOT/evals/check-tasks.sh"
T="$(mk_tmp)"      # the fixture tasks dir
S="$(mk_tmp)"      # scratch: base repos for making patches, fake python3
CAN="PB-HIDDEN-""CANARY"   # split so this file is not itself a canary hit for greps over the repo

# ---- fixture builders -------------------------------------------------------------------------------------------
# A bash setup that refuses a non-empty target and builds calc.sh (add is wrong: it subtracts) with a fixed date.
cat > "$S/setup-bash.sh" <<'SETUP'
#!/usr/bin/env bash
set -eu
dest="$1"
if [ -d "$dest" ] && [ -n "$(ls -A "$dest")" ]; then echo "setup: refusing non-empty $dest" >&2; exit 2; fi
mkdir -p "$dest/tests"
cd "$dest"
printf '%s\n' 'add() { echo $(( $1 - $2 )); }' 'mul() { echo $(( $1 * $2 )); }' > calc.sh
printf 'exit 0\n' > tests/f2p.sh
git init -q
git config user.name fixture
git config user.email fixture@example.invalid
git config commit.gpgsign false
git add -A
GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z' git commit -q -m init
SETUP
# The node twin: src/m.js with the same wrong add.
cat > "$S/setup-node.sh" <<'SETUP'
#!/usr/bin/env bash
set -eu
dest="$1"
if [ -d "$dest" ] && [ -n "$(ls -A "$dest")" ]; then echo "setup: refusing non-empty $dest" >&2; exit 2; fi
mkdir -p "$dest/src" "$dest/tests"
cd "$dest"
printf '%s\n' 'exports.add = (a, b) => a - b;' 'exports.mul = (a, b) => a * b;' > src/m.js
git init -q
git config user.name fixture
git config user.email fixture@example.invalid
git config commit.gpgsign false
git add -A
GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z' git commit -q -m init
SETUP
# The python3 twin: src/m.py (src is a package) with the same wrong add.
cat > "$S/setup-py.sh" <<'SETUP'
#!/usr/bin/env bash
set -eu
dest="$1"
if [ -d "$dest" ] && [ -n "$(ls -A "$dest")" ]; then echo "setup: refusing non-empty $dest" >&2; exit 2; fi
mkdir -p "$dest/src" "$dest/tests"
cd "$dest"
: > src/__init__.py
printf '%s\n' 'def add(a, b):' '    return a - b' '' '' 'def mul(a, b):' '    return a * b' > src/m.py
printf '# visible tests live here\n' > tests/README.md
git init -q
git config user.name fixture
git config user.email fixture@example.invalid
git config commit.gpgsign false
git add -A
GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z' git commit -q -m init
SETUP

# mk_patch KIND FILE SED... -> a unified diff against the base repo of KIND made by applying the sed expressions to FILE
mk_patch() {
  local kind="$1" file="$2" r
  shift 2
  r="$S/base-$kind-$RANDOM$RANDOM"
  bash "$S/setup-$kind.sh" "$r" >/dev/null 2>&1 || { echo "fixture: base repo $kind failed" >&2; return 1; }
  for e in "$@"; do sed "$e" "$r/$file" > "$r/$file.new" && mv "$r/$file.new" "$r/$file"; done
  git -C "$r" diff
}
P_FIX_BASH="$(mk_patch bash calc.sh 's/\$1 - \$2/$1 + $2/')"
P_NOFIX_BASH="$(mk_patch bash calc.sh '1i\
# reviewed')"
P_BREAK_BASH="$(mk_patch bash calc.sh 's/\$1 - \$2/$1 + $2/' 's/\$1 \* \$2/$1 + $2/')"
P_FIX_NODE="$(mk_patch node src/m.js 's/a - b/a + b/')"
P_NOFIX_NODE="$(mk_patch node src/m.js '1i\
// reviewed')"
P_FIX_PY="$(mk_patch py src/m.py 's/a - b/a + b/')"

# mk_task ID KIND LANGUAGE F2P P2P PATCH(-|none|empty|text)  -> task dir $T/ID with the base setup of KIND
mk_task() {
  local id="$1" kind="$2" lang="$3" f2p="$4" p2p="$5" patch="$6" d="$T/$1"
  mkdir -p "$d/hidden/tests"
  cp "$S/setup-$kind.sh" "$d/setup.sh"
  printf 'id=%s\nlanguage=%s\nsource=oss:fixture\nexpected_weight=Lite\nfail_to_pass=%s\npass_to_pass=%s\n' \
    "$id" "$lang" "$f2p" "$p2p" > "$d/task.conf"
  printf 'Fix the add function of this fixture repo.\n' > "$d/prompt.md"
  case "$patch" in
    none) ;;
    empty) : > "$d/solution.patch" ;;
    *) printf '%s\n' "$patch" > "$d/solution.patch" ;;
  esac
}
# hidden bash tests (run from the repo root as `bash tests/x.sh`)
h_bash() { # ID NAME BODY
  printf '#!/usr/bin/env bash\n# %s:%s\n. ./calc.sh\n%s\n' "$CAN" "$1" "$3" > "$T/$1/hidden/tests/$2"
}
h_node() { # ID NAME EXPR
  printf "// %s:%s\nconst test = require('node:test');\nconst assert = require('node:assert/strict');\nconst m = require('../src/m');\ntest('t', () => { assert.equal(%s); });\n" \
    "$CAN" "$1" "$3" > "$T/$1/hidden/tests/$2"
}
h_py() { # ID NAME EXPR
  printf '# %s:%s\nimport unittest\n\nfrom src.m import add, mul\n\n\nclass T(unittest.TestCase):\n    def test_it(self):\n        self.assertEqual(%s)\n' \
    "$CAN" "$1" "$3" > "$T/$1/hidden/tests/$2"
}
F2P_BODY='[ "$(add 2 3)" = 5 ]'
P2P_BODY='[ "$(mul 2 3)" = 6 ]'

# good: F2P fails before, passes after the patch; P2P passes before and after
mk_task good bash bash tests/f2p.sh tests/p2p.sh "$P_FIX_BASH"
h_bash good f2p.sh "$F2P_BODY"; h_bash good p2p.sh "$P2P_BODY"
# one of two F2P files already passes on the unfixed repo
mk_task f2p-passing bash bash "tests/f2p.sh tests/f2p-b.sh" tests/p2p.sh "$P_FIX_BASH"
h_bash f2p-passing f2p.sh "$F2P_BODY"; h_bash f2p-passing f2p-b.sh '[ "$(mul 3 3)" = 9 ]'; h_bash f2p-passing p2p.sh "$P2P_BODY"
# one of two P2P files fails on the unfixed repo (the patch would make it pass)
mk_task p2p-failing bash bash tests/f2p.sh "tests/p2p.sh tests/p2p-b.sh" "$P_FIX_BASH"
h_bash p2p-failing f2p.sh "$F2P_BODY"; h_bash p2p-failing p2p.sh "$P2P_BODY"; h_bash p2p-failing p2p-b.sh '[ "$(add 1 1)" = 2 ]'
# solution.patch does not apply
mk_task patch-bad bash bash tests/f2p.sh tests/p2p.sh "$(printf '%s\n' '--- a/calc.sh' '+++ b/calc.sh' '@@ -1,2 +1,2 @@' '-add() { echo nothing-like-this; }' '+add() { echo $(( $1 + $2 )); }' ' mul() { echo $(( $1 * $2 )); }')"
h_bash patch-bad f2p.sh "$F2P_BODY"; h_bash patch-bad p2p.sh "$P2P_BODY"
# solution.patch applies but does not fix F2P
mk_task patch-nofix bash bash tests/f2p.sh tests/p2p.sh "$P_NOFIX_BASH"
h_bash patch-nofix f2p.sh "$F2P_BODY"; h_bash patch-nofix p2p.sh "$P2P_BODY"
# solution.patch fixes F2P but breaks P2P
mk_task patch-breaks bash bash tests/f2p.sh tests/p2p.sh "$P_BREAK_BASH"
h_bash patch-breaks f2p.sh "$F2P_BODY"; h_bash patch-breaks p2p.sh "$P2P_BODY"
# no F2P and an empty solution.patch file
mk_task empty-patch bash bash "" tests/p2p.sh empty
h_bash empty-patch p2p.sh "$P2P_BODY"
# no F2P and no solution.patch file (a should-not-change task)
mk_task no-patch bash bash "" tests/p2p.sh none
h_bash no-patch p2p.sh "$P2P_BODY"
# setup is not deterministic: two runs give different HEADs
mk_task nondet bash bash tests/f2p.sh tests/p2p.sh "$P_FIX_BASH"
h_bash nondet f2p.sh "$F2P_BODY"; h_bash nondet p2p.sh "$P2P_BODY"
cat >> "$T/nondet/setup.sh" <<'EXTRA'
printf '%s %s\n' "$$" "$RANDOM" > run-id.txt
git add run-id.txt
GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z' git commit -q -m run-id
EXTRA
# setup has a syntax error after an early exit: it runs fine, only `bash -n` sees it
mk_task syntax bash bash tests/f2p.sh tests/p2p.sh "$P_FIX_BASH"
h_bash syntax f2p.sh "$F2P_BODY"; h_bash syntax p2p.sh "$P2P_BODY"
printf 'exit 0\nif then fi\n' >> "$T/syntax/setup.sh"
# setup.sh holds the hidden-test canary
mk_task canary-setup bash bash tests/f2p.sh tests/p2p.sh "$P_FIX_BASH"
h_bash canary-setup f2p.sh "$F2P_BODY"; h_bash canary-setup p2p.sh "$P2P_BODY"
printf '# %s:canary-setup\n' "$CAN" >> "$T/canary-setup/setup.sh"
# setup exits non-zero
mk_task setup-fails bash bash tests/f2p.sh tests/p2p.sh "$P_FIX_BASH"
h_bash setup-fails f2p.sh "$F2P_BODY"; h_bash setup-fails p2p.sh "$P2P_BODY"
printf 'exit 1\n' >> "$T/setup-fails/setup.sh"
# node: language command is `node --test FILE`
mk_task node-good node node tests/add.f2p.test.js tests/mul.p2p.test.js "$P_FIX_NODE"
h_node node-good add.f2p.test.js 'm.add(2, 3), 5'; h_node node-good mul.p2p.test.js 'm.mul(2, 3), 6'
mk_task node-nofix node node tests/add.f2p.test.js tests/mul.p2p.test.js "$P_NOFIX_NODE"
h_node node-nofix add.f2p.test.js 'm.add(2, 3), 5'; h_node node-nofix mul.p2p.test.js 'm.mul(2, 3), 6'
# python3: language command is `python3 -m unittest FILE`
mk_task py-good py python3 tests/test_add_f2p.py tests/test_mul_p2p.py "$P_FIX_PY"
h_py py-good test_add_f2p.py 'add(2, 3), 5'; h_py py-good test_mul_p2p.py 'mul(2, 3), 6'

# a real python3 is one where `python3 -c 'import sys'` works (the Windows Store stub fails it)
HAVE_PY=0
if python3 -c 'import sys' >/dev/null 2>&1; then HAVE_PY=1; fi
# snapshot of the fixture tasks dir: the self-check must not write into it
snap() { (cd "$T" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(cksum < "$f")"; done) }
SNAP0="$(snap)"

# line_ok NAME REGEX -> assert that one output line matches the ERE
line_ok() {
  if printf '%s\n' "$OUT" | grep -Eq -- "$2"; then t_ok "$1"; else t_bad "$1" "no line matching [$2] in: $OUT"; fi
}
line_none() {
  if printf '%s\n' "$OUT" | grep -Eq -- "$2"; then t_bad "$1" "unexpected line matching [$2] in: $OUT"; else t_ok "$1"; fi
}

echo "AC20 self-check over every fixture task"
assert_file "AC20 evals/check-tasks.sh exists" "$CHECK"
run bash "$CHECK" --tasks-dir "$T"
ALL_OUT="$OUT"
assert_rc "AC20 exit 1 when any task is BROKEN" 1
line_ok "AC20 good: F2P fails before, all pass after the patch -> SELF-CHECK OK" '^good SELF-CHECK OK( |$)'
line_ok "AC20 an F2P file that already passes on the unfixed repo -> BROKEN with a reason" '^f2p-passing SELF-CHECK BROKEN .'
line_ok "AC20 a P2P file that fails on the unfixed repo -> BROKEN with a reason" '^p2p-failing SELF-CHECK BROKEN .'
line_ok "AC20 a solution.patch that does not apply -> BROKEN" '^patch-bad SELF-CHECK BROKEN .'
line_ok "AC20 a solution.patch that leaves F2P failing -> BROKEN" '^patch-nofix SELF-CHECK BROKEN .'
line_ok "AC20 a solution.patch that breaks a P2P file -> BROKEN" '^patch-breaks SELF-CHECK BROKEN .'
line_ok "AC20 an empty solution.patch file -> BROKEN" '^empty-patch SELF-CHECK BROKEN .'
line_ok "AC19/AC20 no F2P and no solution.patch file -> apply skipped, SELF-CHECK OK" '^no-patch SELF-CHECK OK( |$)'
line_ok "AC20 setup giving a different HEAD on its second run -> BROKEN" '^nondet SELF-CHECK BROKEN .'
line_ok "AC20 setup.sh failing bash -n (even when it runs) -> BROKEN" '^syntax SELF-CHECK BROKEN .'
line_ok "AC20 setup.sh containing the hidden-test canary -> BROKEN" '^canary-setup SELF-CHECK BROKEN .'
line_ok "AC20 setup.sh exiting non-zero -> BROKEN" '^setup-fails SELF-CHECK BROKEN .'
line_ok "AC20 node task graded with node --test -> SELF-CHECK OK" '^node-good SELF-CHECK OK( |$)'
line_ok "AC20 node task whose patch leaves F2P failing -> BROKEN" '^node-nofix SELF-CHECK BROKEN .'
if [ "$HAVE_PY" = 1 ]; then
  line_ok "AC20 python3 task graded with python3 -m unittest -> SELF-CHECK OK" '^py-good SELF-CHECK OK( |$)'
else
  line_ok "AC20 python3 task SKIPPED where python3 cannot run (this host)" '^py-good .*SKIPPED \(no python3\)'
fi
assert_eq "AC20 the self-check leaves the tasks dir unchanged" "$SNAP0" "$(snap)"

echo "AC20 --tasks selects tasks; only BROKEN fails the run"
run bash "$CHECK" --tasks-dir "$T" --tasks good,no-patch,node-good
assert_rc "AC20 exit 0 when every selected task is OK" 0
line_ok "AC20 --tasks: good checked" '^good SELF-CHECK OK( |$)'
line_ok "AC20 --tasks: no-patch checked" '^no-patch SELF-CHECK OK( |$)'
line_ok "AC20 --tasks: node-good checked" '^node-good SELF-CHECK OK( |$)'
line_none "AC20 --tasks: an unselected task is not checked" '^(f2p-passing|patch-bad|nondet|py-good) '

echo "AC20 python3 counts as present only if python3 -c 'import sys' works"
FB="$(mk_tmp)"
printf '#!/usr/bin/env bash\necho "Python was not found; run without arguments to install from the Microsoft Store" >&2\nexit 9009\n' > "$FB/python3"
chmod +x "$FB/python3" 2>/dev/null
if [ -x "$FB/python3" ] && ! PATH="$FB:$PATH" python3 -c 'import sys' >/dev/null 2>&1; then
  OUT="$(PATH="$FB:$PATH" bash "$CHECK" --tasks-dir "$T" --tasks py-good 2>&1)"; RC=$?
  line_ok "AC20 a python3 that fails import sys -> SKIPPED (no python3)" '^py-good .*SKIPPED \(no python3\)'
  line_none "AC20 a skipped python task is not BROKEN" '^py-good SELF-CHECK BROKEN'
  assert_rc "AC20 a skipped task alone exits 0 (exit 1 only for BROKEN)" 0
else
  t_skip 3 "a fake python3 cannot shadow the real one on this host (chmod or PATH)"
fi

echo "AC20 check-tasks.sh is standalone (sources only scripts/lib.sh)"
if [ -f "$CHECK" ]; then
  srcs="$(grep -E '^[[:space:]]*(\.|source)[[:space:]]' "$CHECK" | grep -v 'scripts/lib\.sh' || true)"
  assert_eq "AC20 no source line other than scripts/lib.sh" "" "$srcs"
else
  t_bad "AC20 no source line other than scripts/lib.sh" "missing $CHECK"
fi
: "$ALL_OUT"
t_summary
