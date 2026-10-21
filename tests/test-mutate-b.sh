#!/usr/bin/env bash
# Tests for scripts/mutate.sh started without a terminal (v0.24.23): the test command must really run, and a test
# command that is only an interpreter name (the calling shell dropped the quotes of --test "bash x.sh") is refused.
#   AC1 no controlling terminal: --test CMD runs in the throwaway worktree, a failing CMD kills the mutant
#   AC2 --test bash (a bare interpreter) exits 2 with a message naming "interpreter", no "mutants:" line
. "$(dirname "$0")/lib.sh"
MUT="$PB_ROOT/scripts/mutate.sh"

W="$(mk_tmp)"
mkdir -p "$W/tmp"

R="$W/repo"; mkdir -p "$R/src"
( cd "$R" && git init -q && git config user.email t@example.invalid && git config user.name tester &&
  git config commit.gpgsign false && git config core.autocrlf false &&
  printf 'base\n' > README.md && printf 'x=1\n' > src/a.sh && git add -A && git commit -q -m init && git tag base &&
  printf 'if [ "$1" = a ]; then echo yes; fi\n' >> src/a.sh && git add -A && git commit -q -m change ) || exit 3
( cd "$R" && printf 'if [ "$1" == a ]; then echo yes; fi\n' >> src/a.sh && git add -A && git commit -q -m change2 ) || exit 3

cat > "$W/stub.sh" <<'STUB'
#!/usr/bin/env bash
echo ran >> "$1"
grep -q '!=' src/a.sh && exit 1
exit 0
STUB

echo "AC1 no controlling terminal: the test command runs and its exit status is used"
MARK="$W/marker"; : > "$MARK"
if command -v setsid >/dev/null 2>&1; then
  OUT="$(cd "$R" && env TMPDIR="$W/tmp" setsid -w bash "$MUT" --base base --test "bash $W/stub.sh $MARK" </dev/null 2>&1)"; RC=$?
  assert_eq "AC1 setsid + stdin /dev/null: the baseline and the mutant both ran the command" "2" "$(wc -l < "$MARK" | tr -d ' ')"
  assert_contains "AC1 the mutant is killed" "$OUT" "killed: 1"
  assert_rc "AC1 exit 0" 0
else
  t_skip 3 "AC1 (no setsid on this system)"
fi
: > "$MARK"
OUT="$(cd "$R" && env TMPDIR="$W/tmp" bash "$MUT" --base base --test "bash $W/stub.sh $MARK" </dev/null 2>&1 | cat)"
assert_eq "AC1 stdin /dev/null, output piped: the command ran twice" "2" "$(wc -l < "$MARK" | tr -d ' ')"
assert_contains "AC1 stdin /dev/null, output piped: the mutant is killed" "$OUT" "killed: 1"

echo "AC2 a bare interpreter as the test command is refused"
for c in bash sh python3 node env; do
  OUT="$(cd "$R" && env TMPDIR="$W/tmp" bash "$MUT" --base base --test "$c" </dev/null 2>&1)"; RC=$?
  assert_rc "AC2 --test $c exits 2" 2
  assert_contains "AC2 --test $c names the interpreter" "$OUT" "interpreter"
  assert_not_contains "AC2 --test $c prints no mutants line" "$OUT" "mutants:"
done
OUT="$(cd "$R" && env TMPDIR="$W/tmp" bash "$MUT" --base base --test "bash $W/stub.sh $MARK" </dev/null 2>&1)"; RC=$?
assert_rc "AC3 an interpreter with a script is accepted" 0

t_summary
