#!/usr/bin/env bash
# Tests for scripts/mutate.sh (v0.22.4 AC1, decision D2): mutation testing on the changed lines of a diff.
#   scripts/mutate.sh --base REF --test "CMD" [--max N] [--timeout S] [--exclude GLOB]... [--fail-under PCT]
# Every case runs against a throw-away git repo. A stub CMD decides which mutants are killed:
#   kill.sh PATFILE   exits 1 when a mutant listed in PATFILE ("file<TAB>text" lines) is present in the work tree
#   slow.sh PATFILE   sleeps 30 s on such a mutant (for --timeout)
#   hang.sh PIDFILE   records its pid, then sleeps 60 s (a run to kill -9 mutate.sh in the middle of)
# `--test true` makes every mutant survive, which lists the mutants as "survived:" lines.
# Assumption (tester): <original> and <mutant> in "survived: file:line: <original> -> <mutant>" are the whole source
# line, and the fixture lines have no leading blanks, so trimming or not does not matter.
. "$(dirname "$0")/lib.sh"
MUT="$PB_ROOT/scripts/mutate.sh"

W="$(mk_tmp)"
mkdir -p "$W/tmp"
TAB="$(printf '\t')"

# ---- stubs ----
cat > "$W/kill.sh" <<'EOF'
#!/usr/bin/env bash
t="$(printf '\t')"
while IFS="$t" read -r f p; do
  [ -n "$f" ] || continue
  if grep -qF -- "$p" "$f" 2>/dev/null; then exit 1; fi
done < "$1"
exit 0
EOF
cat > "$W/slow.sh" <<'EOF'
#!/usr/bin/env bash
t="$(printf '\t')"
while IFS="$t" read -r f p; do
  [ -n "$f" ] || continue
  if grep -qF -- "$p" "$f" 2>/dev/null; then exec sleep 30; fi
done < "$1"
exit 0
EOF
cat > "$W/hang.sh" <<'EOF'
#!/usr/bin/env bash
echo "$$" > "$1"
exec sleep 60
EOF

# ---- helpers ----
mkfx() { # DIR -> a repo with README.md committed (no tag yet)
  local d="$1"; mkdir -p "$d"
  ( cd "$d" && git init -q && git config user.email t@example.invalid && git config user.name tester &&
    git config commit.gpgsign false && git config core.autocrlf false &&
    printf 'base\n' > README.md && git add -A && git commit -q -m init ) || exit 3
}
commit_all() { ( cd "$1" && git add -A && git commit -q --allow-empty -m "$2" ) || exit 3; }
set_base() { commit_all "$1" base; ( cd "$1" && git tag -f base >/dev/null ) || exit 3; }
mrun() { # DIR ARGS... -> OUT, RC (mutate.sh run in DIR, temp files kept under $W/tmp)
  local d="$1"; shift
  run_in "$d" env TMPDIR="$W/tmp" bash "$MUT" "$@"
}
surv() { printf '%s\n' "$OUT" | grep '^survived: ' || true; }
has_line() { # NAME LINE -> OUT has exactly this line
  if printf '%s\n' "$OUT" | grep -qxF -- "$2"; then t_ok "$1"; else t_bad "$1" "no line [$2] in: $OUT"; fi
}
no_text() { # NAME TEXT -> OUT does not contain TEXT
  case "$OUT" in *"$2"*) t_bad "$1" "unexpected [$2] in: $OUT" ;; *) t_ok "$1" ;; esac
}
# bg_limited LIMIT_SECS DIR ARGS... -> OUT, RC, HUNG, ELAPSED (a watchdog instead of GNU timeout, missing on macOS)
bg_limited() {
  local lim="$1" d="$2"; shift 2
  local t0 pid i=0
  t0="$(date +%s)"
  ( cd "$d" && exec env TMPDIR="$W/tmp" bash "$MUT" "$@" > "$W/bg.out" 2>&1 ) &
  pid=$!
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt $((lim * 10)) ]; do sleep 0.1; i=$((i + 1)); done
  HUNG=0
  if kill -0 "$pid" 2>/dev/null; then HUNG=1; kill -9 "$pid" 2>/dev/null; fi
  wait "$pid" 2>/dev/null; RC=$?
  ELAPSED=$(( $(date +%s) - t0 ))
  OUT="$(cat "$W/bg.out" 2>/dev/null)"
}
nwt() { ( cd "$1" && git worktree list --porcelain | grep -c '^worktree ' ); }

echo "AC1.1 the script exists"
assert_file "AC1.1 scripts/mutate.sh exists" "$MUT"

# =====================================================================================================
echo "AC1.1 changed lines: added lines, a rename, deleted and binary files, excludes, comments"
R="$W/det"; mkfx "$R"
( cd "$R" && mkdir -p src tests lib &&
  printf 'const a1 = 1;\nconst a2 = 2;\nif (u == 2) w();\nconst a4 = 4;\nconst a5 = 5;\nconst a6 = 6;\n' > src/old.js &&
  printf 'if (g == 1) h();\n' > src/gone.js &&
  printf 'const r1 = 1;\nconst r2 = 2;\nif (u == 2) keep();\nconst r4 = 4;\nconst r5 = 5;\nconst r6 = 6;\n' > src/ren.js ) || exit 3
set_base "$R"
( cd "$R" &&
  printf 'if (x == 1) y = 2;\n' >> src/old.js &&
  printf 'const n = a == b;\n// if (c == d) skip();\n   // indented comment == x\nconst m = a != b;\n' > src/new.js &&
  printf '# if [ a == b ]\nx=1\n' > src/c.sh &&
  printf 'expect(a == b);\n' > tests/new.test.js &&
  printf 'const z = a == b;\n' > lib/foo.spec.ts &&
  printf 'x := a == b\n' > lib/bar_test.go &&
  printf 'a\0b == c\n' > src/blob.js &&
  git rm -q src/gone.js &&
  git mv src/ren.js src/ren2.js && printf 'if (r == 1) q();\n' >> src/ren2.js ) || exit 3
commit_all "$R" change
mrun "$R" --base base --test true
assert_rc "AC1.1 default run exits 0 (all survive, no --fail-under)" 0
has_line "AC1.1 an added line in a modified file (src/old.js:7)" "survived: src/old.js:7: if (x == 1) y = 2; -> if (x != 1) y = 2;"
has_line "AC1.1 a new file: line 1" "survived: src/new.js:1: const n = a == b; -> const n = a != b;"
has_line "AC1.1 a new file: line 4 (!= becomes ==)" "survived: src/new.js:4: const m = a != b; -> const m = a == b;"
has_line "AC1.1 a renamed file counts only its added line (src/ren2.js:7)" "survived: src/ren2.js:7: if (r == 1) q(); -> if (r != 1) q();"
has_line "AC1.1 *.spec.ts is mutated by default (only tests/* is excluded)" "survived: lib/foo.spec.ts:1: const z = a == b; -> const z = a != b;"
has_line "AC1.1 *_test.go is mutated by default" "survived: lib/bar_test.go:1: x := a == b -> x := a != b"
no_text "AC1.1 an unchanged line of a modified file is not mutated" "u == 2"
no_text "AC1.1 an unchanged line of a renamed file is not mutated" "keep()"
no_text "AC1.1 a deleted file is ignored" "gone.js"
no_text "AC1.1 a binary file is ignored" "blob.js"
no_text "AC1.1 tests/* is excluded by default" "tests/new.test.js"
no_text "AC1.1 a // comment line is skipped" "skip()"
no_text "AC1.1 an indented // comment line is skipped" "indented comment"
no_text "AC1.1 a # comment line is skipped" "src/c.sh"
has_line "AC1.5 the total line counts exactly the six mutants" "mutants: 6, killed: 0, survived: 6"

mrun "$R" --base base --test true --exclude '*.spec.ts' --exclude '*_test.go'
assert_rc "AC1.1 --exclude (repeated) run exits 0" 0
no_text "AC1.1 --exclude '*.spec.ts' removes that file" "foo.spec.ts"
no_text "AC1.1 the second --exclude '*_test.go' also applies" "bar_test.go"
has_line "AC1.1 the other files are still mutated after --exclude" "survived: src/new.js:1: const n = a == b; -> const n = a != b;"
has_line "AC1.5 the total drops to four" "mutants: 4, killed: 0, survived: 4"

# =====================================================================================================
echo "AC1.2 whole tokens only; nothing mutable gives mutants: 0"
R="$W/tok"; mkfx "$R"; set_base "$R"
( cd "$R" && mkdir -p src &&
  printf 'const s = a === b;\nconst s2 = a !== b;\nconst untrue = is_true(x);\nreturn 10;\n' > src/t.js &&
  printf 'cat in > out\nread a < in\necho hi >> log\nexec 2>&1\n' > src/t.sh ) || exit 3
commit_all "$R" change
mrun "$R" --base base --test true
assert_rc "AC1.5 nothing mutable: exit 0" 0
has_line "AC1.5 nothing mutable: mutants: 0, killed: 0, survived: 0" "mutants: 0, killed: 0, survived: 0"
assert_eq "AC1.2 === !== untrue is_true 'return 10' and shell redirections give no mutant" "" "$(surv)"

# =====================================================================================================
echo "AC1.2 operators, order, --max"
R="$W/ord"; mkfx "$R"; set_base "$R"
( cd "$R" && mkdir -p src &&
  printf '%s\n' 'if (n < 3 && m > 2) go();' 'const flag = true;' 'return 0;' > src/a.js &&
  printf '%s\n' 'if [ "$a" -eq 1 ] && [ "$b" -lt 2 ]; then' 'cat in > out' 'ok=true' > src/b.sh &&
  printf '%s\n' 'if a > b: pass' > src/c.py ) || exit 3
commit_all "$R" change
L1='survived: src/a.js:1: if (n < 3 && m > 2) go(); -> if (n < 3 || m > 2) go();'
L2='survived: src/a.js:1: if (n < 3 && m > 2) go(); -> if (n >= 3 && m > 2) go();'
L3='survived: src/a.js:1: if (n < 3 && m > 2) go(); -> if (n < 3 && m <= 2) go();'
L4='survived: src/a.js:2: const flag = true; -> const flag = false;'
L5='survived: src/a.js:3: return 0; -> return 1;'
L6='survived: src/b.sh:1: if [ "$a" -eq 1 ] && [ "$b" -lt 2 ]; then -> if [ "$a" -ne 1 ] && [ "$b" -lt 2 ]; then'
L7='survived: src/b.sh:1: if [ "$a" -eq 1 ] && [ "$b" -lt 2 ]; then -> if [ "$a" -eq 1 ] && [ "$b" -ge 2 ]; then'
L8='survived: src/b.sh:1: if [ "$a" -eq 1 ] && [ "$b" -lt 2 ]; then -> if [ "$a" -eq 1 ] || [ "$b" -lt 2 ]; then'
L9='survived: src/b.sh:3: ok=true -> ok=false'
L10='survived: src/c.py:1: if a > b: pass -> if a <= b: pass'
ALL="$(printf '%s\n' "$L1" "$L2" "$L3" "$L4" "$L5" "$L6" "$L7" "$L8" "$L9" "$L10")"
mrun "$R" --base base --test true
assert_rc "AC1.2 run exits 0" 0
assert_eq "AC1.2 one mutant per (line, operator), ordered by file, line, then operator list (&&, <, > on one line; -eq, -lt, && in shell; < > only outside shell)" "$ALL" "$(surv)"
has_line "AC1.5 the total line" "mutants: 10, killed: 0, survived: 10"
no_text "AC1.2 'cat in > out' in a shell file is not mutated" "src/b.sh:2:"

mrun "$R" --base base --test true --max 4
assert_rc "AC1.1 --max 4 exits 0" 0
assert_eq "AC1.1 --max 4 keeps the first four mutants in order" "$(printf '%s\n' "$L1" "$L2" "$L3" "$L4")" "$(surv)"
has_line "AC1.5 --max 4 total line" "mutants: 4, killed: 0, survived: 4"

mrun "$R" --base HEAD --test true
assert_rc "AC1.5 no changed line at all: exit 0" 0
has_line "AC1.5 no changed line at all: mutants: 0" "mutants: 0, killed: 0, survived: 0"

echo "AC1.2 the default for --max is 20"
R="$W/many"; mkfx "$R"; set_base "$R"
( cd "$R" && mkdir -p src && i=1 && : > src/many.js && while [ "$i" -le 25 ]; do printf 'const v%d = a == b;\n' "$i" >> src/many.js; i=$((i + 1)); done ) || exit 3
commit_all "$R" change
mrun "$R" --base base --test true
has_line "AC1.2 25 mutable lines, default --max: mutants: 20" "mutants: 20, killed: 0, survived: 20"
has_line "AC1.2 line 20 is the last mutated" "survived: src/many.js:20: const v20 = a == b; -> const v20 = a != b;"
no_text "AC1.2 line 21 is not mutated" "src/many.js:21:"

# =====================================================================================================
echo "AC1.5 killed and survived mutants, --fail-under"
R="$W/ord"
printf 'src/a.js%sconst flag = false;\nsrc/a.js%sreturn 1;\nsrc/b.sh%sok=false\n' "$TAB" "$TAB" "$TAB" > "$W/kill.pats"
CMDK="bash $W/kill.sh $W/kill.pats"
mrun "$R" --base base --test "$CMDK"
assert_rc "AC1.5 killed and survived mutants, no --fail-under: exit 0" 0
has_line "AC1.5 3 killed of 10" "mutants: 10, killed: 3, survived: 7"
assert_eq "AC1.5 only the survivors are listed, in order" "$(printf '%s\n' "$L1" "$L2" "$L3" "$L6" "$L7" "$L8" "$L10")" "$(surv)"
mrun "$R" --base base --test "$CMDK" --fail-under 30
assert_rc "AC1.5 --fail-under 30 with 3*100/10 = 30: not below, exit 0" 0
mrun "$R" --base base --test "$CMDK" --fail-under 31
assert_rc "AC1.5 --fail-under 31: 30 is below, exit 1" 1
has_line "AC1.5 --fail-under 31 still prints the total line" "mutants: 10, killed: 3, survived: 7"
mrun "$R" --base base --test true --fail-under 1
assert_rc "AC1.5 nothing killed, --fail-under 1: exit 1" 1
mrun "$R" --base base --test "$CMDK" --fail-under 0
assert_rc "AC1.5 --fail-under 0 never fails" 0

# =====================================================================================================
echo "AC1.3b baseline: the tests must pass in the throw-away worktree"
R="$W/b4"; mkfx "$R"
( cd "$R" && mkdir -p src && printf 'secret.cfg\n' > .gitignore && printf 'const k = 1;\n' > src/a.js ) || exit 3
set_base "$R"
( cd "$R" && printf 'const q = a == b;\n' >> src/a.js && printf 'x\n' > secret.cfg ) || exit 3
commit_all "$R" change
run_in "$R" test -f secret.cfg
assert_rc "AC1.3b control: the test command passes in the user's tree (the ignored file is there)" 0
mrun "$R" --base base --test "test -f secret.cfg"
assert_rc "AC1.3b a baseline that fails in the worktree: exit 4" 4
assert_contains "AC1.3b the message names the cause" "$OUT" "tests fail without mutation in the throwaway worktree"
case "$OUT" in *"mutants:"*) t_bad "AC1.3b no mutants line after a failed baseline" "$OUT" ;; *) t_ok "AC1.3b no mutants line after a failed baseline" ;; esac
assert_eq "AC1.3b no survivor lines either" "" "$(surv)"
assert_eq "AC1.3 no worktree is left behind after exit 4" "1" "$(nwt "$R")"

# =====================================================================================================
echo "AC1.4 timeout: a mutant that hangs is killed, reported, and counted as killed"
R="$W/to"; mkfx "$R"; set_base "$R"
( cd "$R" && mkdir -p src && printf 'const q = a == b;\n' > src/a.js ) || exit 3
commit_all "$R" change
printf 'src/a.js%sa != b\n' "$TAB" > "$W/slow.pats"
bg_limited 25 "$R" --base base --test "bash $W/slow.sh $W/slow.pats" --timeout 2
assert_eq "AC1.4 mutate.sh finishes by itself (the CMD sleeps 30 s, --timeout 2)" "0" "$HUNG"
if [ "$ELAPSED" -lt 25 ]; then t_ok "AC1.4 the run took less than 25 s ($ELAPSED s)"; else t_bad "AC1.4 the run took less than 25 s" "elapsed $ELAPSED s"; fi
assert_rc "AC1.4 timeout run exits 0" 0
assert_contains "AC1.4 the line 'killed (timeout): file:line'" "$OUT" "killed (timeout): src/a.js:1"
has_line "AC1.4 a timeout counts as killed" "mutants: 1, killed: 1, survived: 0"
assert_eq "AC1.4 no survivor line" "" "$(surv)"

# =====================================================================================================
echo "AC1.3 safety: the user's work tree is never written, the worktree is removed"
R="$W/safe"; mkfx "$R"
( cd "$R" && mkdir -p src && printf 'const k = 1;\n' > src/a.js ) || exit 3
set_base "$R"
( cd "$R" && printf 'const flag = true;\n' >> src/a.js ) || exit 3
commit_all "$R" change
( cd "$R" && printf 'const u = p == q;\n' >> src/a.js && printf 'staged\n' >> README.md && git add README.md &&
  printf 'mine\n' > notes.txt ) || exit 3
BEFORE="$(cd "$R" && git status --porcelain)"
SUMS="$(cd "$R" && cksum src/a.js README.md notes.txt)"
rm -f "$W/cwd.log"
mrun "$R" --base base --test "pwd >> $W/cwd.log"
assert_rc "AC1.3 run with uncommitted user changes exits 0" 0
has_line "AC1.3 the committed line is mutated" "survived: src/a.js:2: const flag = true; -> const flag = false;"
no_text "AC1.3 an uncommitted line of the user is not part of the run (only HEAD is mutated)" "p == q"
assert_eq "AC1.3 git status --porcelain is unchanged (uncommitted, staged and untracked work stay as they were)" "$BEFORE" "$(cd "$R" && git status --porcelain)"
assert_eq "AC1.3 the user's files are byte-identical" "$SUMS" "$(cd "$R" && cksum src/a.js README.md notes.txt)"
USERDIR="$(cd "$R" && pwd -P)"
FIRSTCWD="$(sed -n 1p "$W/cwd.log" 2>/dev/null)"
if [ -n "$FIRSTCWD" ] && [ "$(cd "$FIRSTCWD" 2>/dev/null && pwd -P)" != "$USERDIR" ]; then t_ok "AC1.3 CMD runs in a throw-away directory, not in the user's tree"; else t_bad "AC1.3 CMD runs in a throw-away directory, not in the user's tree" "cwd [$FIRSTCWD] user [$USERDIR]"; fi
assert_eq "AC1.3 the worktree is removed on exit (one worktree left)" "1" "$(nwt "$R")"
assert_eq "AC1.3 nothing is left in the temp dir" "" "$(ls -A "$W/tmp")"

echo "AC1.3 kill -9 in the middle of a run, then the next run cleans up"
R="$W/k9"; mkfx "$R"
( cd "$R" && mkdir -p src && printf 'const k = 1;\n' > src/a.js ) || exit 3
set_base "$R"
( cd "$R" && printf 'const flag = true;\n' >> src/a.js ) || exit 3
commit_all "$R" change
( cd "$R" && printf 'const u = p == q;\n' >> src/a.js && printf 'mine\n' > notes.txt ) || exit 3
BEFORE="$(cd "$R" && git status --porcelain)"
SUMS="$(cd "$R" && cksum src/a.js notes.txt)"
rm -f "$W/hang.pid"
( cd "$R" && exec env TMPDIR="$W/tmp" bash "$MUT" --base base --test "bash $W/hang.sh $W/hang.pid" > "$W/k9.out" 2>&1 ) &
MPID=$!
i=0; while [ ! -s "$W/hang.pid" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i + 1)); done
if [ -s "$W/hang.pid" ]; then t_ok "AC1.3 mutate.sh reached the test command"; else t_bad "AC1.3 mutate.sh reached the test command" "no pid file after 20 s"; fi
kill -9 "$MPID" 2>/dev/null; wait "$MPID" 2>/dev/null
[ -s "$W/hang.pid" ] && kill -9 "$(cat "$W/hang.pid")" 2>/dev/null
assert_eq "AC1.3b after kill -9 the user's git status --porcelain is unchanged" "$BEFORE" "$(cd "$R" && git status --porcelain)"
assert_eq "AC1.3b after kill -9 the user's files are byte-identical" "$SUMS" "$(cd "$R" && cksum src/a.js notes.txt)"
assert_eq "AC1.3 the killed run left its worktree registered (a stale one)" "2" "$(nwt "$R")"
mrun "$R" --base base --test true
assert_rc "AC1.3 the next run exits 0" 0
assert_eq "AC1.3 the next run removed the stale worktree under its prefix" "1" "$(nwt "$R")"
assert_eq "AC1.3 the stale directory is gone from the temp dir" "" "$(ls -A "$W/tmp")"
has_line "AC1.3 the next run still mutates the committed line" "survived: src/a.js:2: const flag = true; -> const flag = false;"

# =====================================================================================================
echo "AC1.5 exit codes: usage 2, not a repository 3"
R="$W/tok"
mrun "$R" --base base
assert_rc "AC1.5 missing --test: exit 2" 2
mrun "$R" --test true
assert_rc "AC1.5 missing --base: exit 2" 2
mrun "$R" --base base --test true --bogus
assert_rc "AC1.5 unknown option: exit 2" 2
mrun "$R" --base base --test true --max abc
assert_rc "AC1.5 non-numeric --max: exit 2" 2
mrun "$R" --base base --test true --timeout abc
assert_rc "AC1.5 non-numeric --timeout: exit 2" 2
mrun "$R" --base base --test true --fail-under abc
assert_rc "AC1.5 non-numeric --fail-under: exit 2" 2
N="$(mk_tmp)"
mrun "$N" --base base --test true
assert_rc "AC1.5 not a git repository: exit 3" 3

# =====================================================================================================
# v0.22.4 review findings (round 2)
# =====================================================================================================
cat > "$W/snap.sh" <<'EOF'
#!/usr/bin/env bash
# snap.sh LOG TARGET: record the target's checksum before and after a one-second pause (a slow CMD)
echo "$(cksum < "$2")" >> "$1"
sleep 1
echo "$(cksum < "$2")" >> "$1"
exit 0
EOF
cat > "$W/seen.sh" <<'EOF'
#!/usr/bin/env bash
# seen.sh LOG SECS: record which mutant of src/m.js this run really sees, then pause SECS seconds
printf 'seen:%s\n' "$(grep -n '!=' src/m.js)" >> "$1"
sleep "$2"
exit 0
EOF
cat > "$W/gc.sh" <<'EOF'
#!/usr/bin/env bash
# gc.sh PIDDIR MODE: start a grandchild (sleep 300) and wait for it. MODE mutant: only when src/a.js is mutated.
if [ "$2" = mutant ] && ! grep -q '!=' src/a.js; then exit 0; fi
echo "$$" > "$1/cmd.pid"
sleep 300 &
echo "$!" > "$1/gc.pid"
wait
EOF
alive() { kill -0 "$1" 2>/dev/null; }
# gone_within SECS PID -> 0 when PID is dead within SECS seconds (polled)
gone_within() {
  local i=0
  while alive "$2" && [ "$i" -lt $(($1 * 10)) ]; do sleep 0.1; i=$((i + 1)); done
  ! alive "$2"
}

echo "AC1.3 symlinks (absolute or relative) are skipped; their target is never written"
if [ "$SYMLINKS" = 1 ]; then
  R="$W/sym"; mkfx "$R"
  OUTSIDE="$W/outside/true"; mkdir -p "$OUTSIDE"
  printf 'const t = a == b;\nconst u = 1;\n' > "$OUTSIDE/t.js"
  ( cd "$R" && mkdir -p src && printf 'const k = 1;\n' > src/a.js ) || exit 3
  set_base "$R"
  # the blob text of each link is its target path, which holds the whole token "true" (".../true/t.js")
  ( cd "$R" && printf 'const f = true;\n' >> src/a.js && ln -s "$OUTSIDE/t.js" src/abs.js && ln -s "../../outside/true/t.js" src/rel.js ) || exit 3
  commit_all "$R" change
  assert_eq "AC1.3 precondition: both links are committed as symlinks (mode 120000)" "2" "$(cd "$R" && git ls-files -s src/abs.js src/rel.js | grep -c '^120000 ')"
  TSUM="$(cksum < "$OUTSIDE/t.js")"
  rm -f "$W/snap.log"
  mrun "$R" --base base --test "bash $W/snap.sh $W/snap.log $OUTSIDE/t.js"
  assert_rc "AC1.3 a repo with symlinks: exit 0" 0
  has_line "AC1.3 the regular file is still mutated" "survived: src/a.js:2: const f = true; -> const f = false;"
  no_text "AC1.3 the absolute symlink never becomes a mutant" "src/abs.js"
  no_text "AC1.3 the relative symlink never becomes a mutant" "src/rel.js"
  has_line "AC1.3 only the regular file is counted" "mutants: 1, killed: 0, survived: 1"
  assert_eq "AC1.3 the target outside the repo is unchanged after the run" "$TSUM" "$(cksum < "$OUTSIDE/t.js")"
  assert_eq "AC1.3 the target was unchanged at every snapshot taken during the run (2 per CMD run)" "$(printf '%s\n%s\n%s\n%s\n' "$TSUM" "$TSUM" "$TSUM" "$TSUM")" "$(cat "$W/snap.log")"
  assert_eq "AC1.3 the symlinks in the user's tree are untouched" "2" "$(cd "$R" && find src -type l | wc -l | tr -d ' ')"
else
  t_skip 10 "AC1.3 symlinks (this system cannot create them)"
fi

echo "AC1.3 concurrent runs: a live run's worktree is never removed, only a dead owner's is"
R="$W/conc"; mkfx "$R"
( cd "$R" && mkdir -p src && printf 'const v0 = 0;\n' > src/m.js ) || exit 3
set_base "$R"
( cd "$R" && printf 'const v1 = a == b;\nconst v2 = a == b;\nconst v3 = a == b;\n' >> src/m.js ) || exit 3
commit_all "$R" change
# K: a run killed with kill -9 leaves a stale worktree behind (its owner is dead)
rm -f "$W/hang.pid"
( cd "$R" && exec env TMPDIR="$W/tmp" bash "$MUT" --base base --test "bash $W/hang.sh $W/hang.pid" > "$W/kc.out" 2>&1 ) &
KPID=$!
i=0; while [ ! -s "$W/hang.pid" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i + 1)); done
kill -9 "$KPID" 2>/dev/null; wait "$KPID" 2>/dev/null
[ -s "$W/hang.pid" ] && kill -9 "$(cat "$W/hang.pid")" 2>/dev/null
assert_eq "AC1.3 precondition: the killed run left its worktree registered" "2" "$(nwt "$R")"
# A: a slow run (3 s per CMD run, baseline + 3 mutants)
rm -f "$W/seen.A.log"
( cd "$R" && exec env TMPDIR="$W/tmp" bash "$MUT" --base base --test "bash $W/seen.sh $W/seen.A.log 3" > "$W/A.out" 2>&1 ) &
APID=$!
i=0; while [ ! -s "$W/seen.A.log" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i + 1)); done
if [ -s "$W/seen.A.log" ]; then t_ok "AC1.3 run A reached its test command"; else t_bad "AC1.3 run A reached its test command" "no log after 20 s"; fi
assert_eq "AC1.3 A's start removed the dead owner's worktree and made its own (two registered: the repo and A)" "2" "$(nwt "$R")"
assert_eq "AC1.3 only A's temp directory is left (the stale one is gone)" "1" "$(ls -A "$W/tmp" | wc -l | tr -d ' ')"
# B: starts while A is still running
mrun "$R" --base base --test true
assert_rc "AC1.3 run B, started while A runs, completes with exit 0" 0
has_line "AC1.3 run B's own result is complete" "mutants: 3, killed: 0, survived: 3"
if alive "$APID"; then t_ok "AC1.3 run A is still running after B finished"; else t_bad "AC1.3 run A is still running after B finished" "A ended early"; fi
assert_eq "AC1.3 B did not remove A's worktree (the repo and A are still registered)" "2" "$(nwt "$R")"
assert_eq "AC1.3 B removed only its own temp directory (A's is still there)" "1" "$(ls -A "$W/tmp" | wc -l | tr -d ' ')"
i=0; while alive "$APID" && [ "$i" -lt 900 ]; do sleep 0.1; i=$((i + 1)); done
if alive "$APID"; then kill -9 "$APID" 2>/dev/null; t_bad "AC1.3 run A finished within 90 s" "still running"; else t_ok "AC1.3 run A finished within 90 s"; fi
wait "$APID" 2>/dev/null; ARC=$?
AOUT="$(cat "$W/A.out" 2>/dev/null)"
assert_eq "AC1.3 run A exits 0" "0" "$ARC"
assert_contains "AC1.3 run A's result is correct (three mutants, none killed)" "$AOUT" "mutants: 3, killed: 0, survived: 3"
assert_eq "AC1.3 run A saw each of its mutants in its own worktree, once, in order (the baseline sees none)" "$(printf 'seen:\nseen:2:const v1 = a != b;\nseen:3:const v2 = a != b;\nseen:4:const v3 = a != b;')" "$(cat "$W/seen.A.log")"
assert_eq "AC1.3 after both runs only the repo's worktree is left" "1" "$(nwt "$R")"
assert_eq "AC1.3 after both runs the temp dir is empty" "" "$(ls -A "$W/tmp")"

echo "AC1.3 a mutant that cannot be applied is an error line, not a kill"
RO_OK=1
[ "$(id -u)" = 0 ] && RO_OK=0
printf 'x\n' > "$W/probe.txt"; chmod a-w "$W/probe.txt"
if ( : >> "$W/probe.txt" ) 2>/dev/null; then RO_OK=0; fi
chmod u+w "$W/probe.txt"
if [ "$RO_OK" = 1 ]; then
  R="$W/ro"; mkfx "$R"; ( cd "$R" && mkdir -p src && printf 'const k = 1;\n' > src/a.js ) || exit 3
  set_base "$R"
  ( cd "$R" && printf 'const q = a == b;\n' >> src/a.js ) || exit 3
  commit_all "$R" change
  # the test command makes the file read-only in the throw-away copy, so the write of the mutant fails
  mrun "$R" --base base --test "chmod a-w src/a.js"
  if printf '%s\n' "$OUT" | grep -qiE '^error.*src/a\.js:2'; then t_ok "AC1.3 an error line names src/a.js:2"; else t_bad "AC1.3 an error line names src/a.js:2" "output: $OUT"; fi
  no_text "AC1.3 an unapplied mutant is not reported as a survivor" "survived: src/a.js"
  no_text "AC1.3 an unapplied mutant is not a timeout kill" "killed (timeout)"
  ML="$(printf '%s\n' "$OUT" | grep '^mutants: ')"
  case "$ML" in
    "") t_ok "AC1.3 (no mutants line: the run stopped on the error)" ;;
    *"killed: 0,"*) t_ok "AC1.3 an unapplied mutant is not counted as killed" ;;
    *) t_bad "AC1.3 an unapplied mutant is not counted as killed" "line: $ML" ;;
  esac
  assert_eq "AC1.3 the worktree is removed even with a read-only file" "1" "$(nwt "$R")"
else
  t_skip 5 "AC1.3 unapplied mutant (running as root, or this file system ignores read-only files)"
fi

echo "AC1.4 process group: no grandchild survives a timeout or a kill -9 of mutate.sh"
R="$W/pg"; mkfx "$R"; ( cd "$R" && mkdir -p src && printf 'const k = 1;\n' > src/a.js ) || exit 3
set_base "$R"
( cd "$R" && printf 'const q = a == b;\n' >> src/a.js ) || exit 3
commit_all "$R" change
PD="$W/pd1"; mkdir -p "$PD"
bg_limited 30 "$R" --base base --test "bash $W/gc.sh $PD mutant" --timeout 2
assert_eq "AC1.4 the timeout run finishes by itself" "0" "$HUNG"
assert_contains "AC1.4 the timeout run reports the timeout" "$OUT" "killed (timeout): src/a.js:2"
GC="$(cat "$PD/gc.pid" 2>/dev/null)"; CP="$(cat "$PD/cmd.pid" 2>/dev/null)"
if [ -n "$GC" ]; then
  if gone_within 10 "$GC"; then t_ok "AC1.4 the grandchild (sleep 300 &) is gone after a timeout"; else kill -9 "$GC" 2>/dev/null; t_bad "AC1.4 the grandchild (sleep 300 &) is gone after a timeout" "pid $GC still alive"; fi
  if gone_within 5 "$CP"; then t_ok "AC1.4 the test command itself is gone after a timeout"; else kill -9 "$CP" 2>/dev/null; t_bad "AC1.4 the test command itself is gone after a timeout" "pid $CP still alive"; fi
else
  t_bad "AC1.4 the grandchild was started" "no pid file"
fi
PD="$W/pd2"; mkdir -p "$PD"
( cd "$R" && exec env TMPDIR="$W/tmp" bash "$MUT" --base base --test "bash $W/gc.sh $PD always" > "$W/pg.out" 2>&1 ) &
MPID=$!
i=0; while [ ! -s "$PD/gc.pid" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i + 1)); done
sleep 0.3
GC="$(cat "$PD/gc.pid" 2>/dev/null)"; CP="$(cat "$PD/cmd.pid" 2>/dev/null)"
kill -9 "$MPID" 2>/dev/null; wait "$MPID" 2>/dev/null
if [ -n "$GC" ]; then
  if gone_within 15 "$GC"; then t_ok "AC1.4 the grandchild is gone after a kill -9 of mutate.sh"; else kill -9 "$GC" 2>/dev/null; t_bad "AC1.4 the grandchild is gone after a kill -9 of mutate.sh" "pid $GC still alive after 15 s"; fi
  if gone_within 5 "$CP"; then t_ok "AC1.4 the test command itself is gone after a kill -9 of mutate.sh"; else kill -9 "$CP" 2>/dev/null; t_bad "AC1.4 the test command itself is gone after a kill -9 of mutate.sh" "pid $CP still alive"; fi
else
  t_bad "AC1.4 the grandchild was started (kill -9 case)" "no pid file"
fi
mrun "$R" --base base --test true
assert_eq "AC1.4 the next run cleans up the killed run's worktree" "1" "$(nwt "$R")"

echo "AC1.1 *.md is excluded by default (D4); --include-docs brings it back"
R="$W/md"; mkfx "$R"; ( cd "$R" && mkdir -p src docs ) || exit 3
printf 'const k = 1;\n' > "$R/src/a.js"
set_base "$R"
( cd "$R" && printf 'const f = true;\n' >> src/a.js &&
  printf 'Set the flag to true and check a == b.\n' > docs/g.md && printf 'x == y\n' > NOTES.md ) || exit 3
commit_all "$R" change
mrun "$R" --base base --test true
assert_rc "AC1.1 default run exits 0" 0
has_line "AC1.1 the code line is mutated" "survived: src/a.js:2: const f = true; -> const f = false;"
no_text "AC1.1 a .md file in a directory is not mutated by default" "docs/g.md"
no_text "AC1.1 a .md file at the root is not mutated by default" "NOTES.md"
has_line "AC1.5 only the code mutant is counted by default" "mutants: 1, killed: 0, survived: 1"
mrun "$R" --base base --test true --include-docs
assert_rc "AC1.1 --include-docs run exits 0" 0
has_line "AC1.1 --include-docs: the == in a .md file is mutated" "survived: docs/g.md:1: Set the flag to true and check a == b. -> Set the flag to true and check a != b."
has_line "AC1.1 --include-docs: the word true in a .md file is mutated" "survived: docs/g.md:1: Set the flag to true and check a == b. -> Set the flag to false and check a == b."
has_line "AC1.1 --include-docs: a root .md file is mutated" "survived: NOTES.md:1: x == y -> x != y"
has_line "AC1.5 --include-docs counts all four mutants" "mutants: 4, killed: 0, survived: 4"
mrun "$R" --base base --test true --include-docs --exclude 'docs/*'
no_text "AC1.1 --exclude still applies next to --include-docs" "docs/g.md"
has_line "AC1.1 --exclude next to --include-docs keeps the other .md file" "survived: NOTES.md:1: x == y -> x != y"

echo "v0.23.1 AC8.1 pid reuse: an owner is reaped when its pid is dead or its start string differs; a failing ps never reaps"
# Assumed owner file format (tester): line 1 = pid, line 2 = the trimmed start string (a v0.22.4 file has line 1 only, N4).
# A fake ps on PATH decides the start string. FPS_MODE: out (print FPS_OUT) | empty (print nothing, exit 0) | fail (exit 1).
FB="$W/fakebin"; mkdir -p "$FB"
cat > "$FB/ps" <<'EOF'
#!/bin/sh
printf 'LC_ALL=%s TZ=%s ARGS=%s\n' "${LC_ALL:-}" "${TZ:-}" "$*" >> "${FPS_LOG:-/dev/null}"
case "${FPS_MODE:-out}" in
  empty) exit 0 ;;
  fail) exit 1 ;;
  *) printf '%s\n' "${FPS_OUT:-}" ;;
esac
EOF
chmod +x "$FB/ps"
R="$W/reuse"; mkfx "$R"
( cd "$R" && mkdir -p src && printf 'const k = 1;\n' > src/a.js ) || exit 3
set_base "$R"
( cd "$R" && printf 'const q = a == b;\n' >> src/a.js ) || exit 3
commit_all "$R" change
RT_START='Mon Oct 12 10:00:00 2026'
# stale_case NAME OWNER_CONTENT MODE PSOUT -> a registered worktree under its own TMPDIR with that owner file; runs
# mutate.sh with the fake ps; sets REAPED=1|0 (the stale dir is gone) and OUT, RC
stale_case() {
  local name="$1" content="$2" mode="$3" psout="$4" tb rb
  tb="$W/rt-$name"; mkdir -p "$tb"; rb="$(cd "$tb" && pwd -P)"
  mkdir -p "$rb/pbmutate.stale"
  ( cd "$R" && git worktree add -q --detach "$rb/pbmutate.stale/wt" HEAD >/dev/null 2>&1 ) || { t_bad "AC8.1 fixture [$name]: worktree add" "failed"; }
  printf '%s' "$content" > "$rb/pbmutate.stale/owner"
  OUT="$(cd "$R" && env TMPDIR="$tb" PATH="$FB:$PATH" FPS_MODE="$mode" FPS_OUT="$psout" bash "$MUT" --base base --test true 2>&1)"; RC=$?
  if [ -d "$rb/pbmutate.stale" ]; then REAPED=0; else REAPED=1; fi
  ( cd "$R" && git worktree remove --force "$rb/pbmutate.stale/wt" >/dev/null 2>&1; git worktree prune >/dev/null 2>&1 ) || true
  rm -rf "$rb/pbmutate.stale"
}
sleep 300 & LIVE=$!
sleep 300 & LIVE2=$!
DEADP=999999; while kill -0 "$DEADP" 2>/dev/null; do DEADP=$((DEADP + 1)); done

stale_case live-match "$LIVE
$RT_START
" out "$RT_START"
assert_rc "AC8.1 live pid + matching start string: the run itself exits 0" 0
assert_eq "AC8.1 live pid + matching start string: never reaped" "0" "$REAPED"
stale_case live-match-sp "$LIVE
$RT_START
" out "  $RT_START  "
assert_eq "AC8.1 the current start string is trimmed before comparing: never reaped" "0" "$REAPED"
stale_case live-diff "$LIVE
$RT_START
" out "Tue Oct 13 11:11:11 2026"
assert_rc "AC8.1 live pid + differing start string: the run exits 0" 0
assert_eq "AC8.1 live pid + a differing non-empty start string counts as reused: reaped" "1" "$REAPED"
stale_case live-cur-empty "$LIVE
$RT_START
" empty ""
assert_eq "AC8.1 live pid, stored string set, ps prints nothing now: never reaped" "0" "$REAPED"
stale_case live-cur-fail "$LIVE
$RT_START
" fail ""
assert_eq "AC8.1 live pid, stored string set, ps fails now: never reaped" "0" "$REAPED"
stale_case live-stored-empty "$LIVE

" out "$RT_START"
assert_eq "AC8.1 live pid, empty stored string, ps works now: never reaped" "0" "$REAPED"
stale_case live-both-empty "$LIVE

" empty ""
assert_eq "AC8.1 live pid, ps empty on both sides: never reaped" "0" "$REAPED"
stale_case live-oneline-out "$LIVE
" out "$RT_START"
assert_eq "AC8.1 a one-line owner (v0.22.4: pid only) of a live pid, ps works: kill -0 says alive, never reaped (N4)" "0" "$REAPED"
stale_case live-oneline-empty "$LIVE
" empty ""
assert_eq "AC8.1 a one-line owner of a live pid, ps empty: never reaped (N4)" "0" "$REAPED"
stale_case dead-oneline "$DEADP
" out "$RT_START"
assert_rc "AC8.1 a one-line owner of a dead pid: the run exits 0" 0
assert_eq "AC8.1 a one-line owner of a dead pid is reaped by kill -0 (N4)" "1" "$REAPED"
stale_case dead-match "$DEADP
$RT_START
" out "$RT_START"
assert_eq "AC8.1 a dead pid is reaped even when the start strings match" "1" "$REAPED"
stale_case dead-ps-empty "$DEADP
$RT_START
" empty ""
assert_eq "AC8.1 a dead pid is reaped when ps prints nothing" "1" "$REAPED"
kill -9 "$LIVE" "$LIVE2" 2>/dev/null; wait "$LIVE" "$LIVE2" 2>/dev/null

echo "v0.23.1 AC8.1 the owner file stores the pid and the trimmed start string from LC_ALL=C TZ=UTC0 ps -o lstart= -p PID"
R="$W/own"; mkfx "$R"
( cd "$R" && mkdir -p src && printf 'const k = 1;\n' > src/a.js ) || exit 3
set_base "$R"
( cd "$R" && printf 'const q = a == b;\n' >> src/a.js ) || exit 3
commit_all "$R" change
rm -f "$W/own.copy" "$W/fps.log"
OUT="$(cd "$R" && env TMPDIR="$W/tmp" PATH="$FB:$PATH" FPS_MODE=out FPS_OUT="  $RT_START  " FPS_LOG="$W/fps.log" LC_ALL=de_DE.UTF-8 TZ=Asia/Tokyo bash "$MUT" --base base --test "cat ../owner > $W/own.copy" 2>&1)"; RC=$?
assert_rc "AC8.1 the run with a fake ps exits 0" 0
OWN1="$(sed -n 1p "$W/own.copy" 2>/dev/null)"; OWN2="$(sed -n 2p "$W/own.copy" 2>/dev/null)"
case "$OWN1" in "" | *[!0-9]*) t_bad "AC8.1 owner line 1 is the pid" "got [$OWN1]" ;; *) t_ok "AC8.1 owner line 1 is the pid" ;; esac
assert_eq "AC8.1 owner line 2 is the trimmed start string" "$RT_START" "$OWN2"
FLOG="$(cat "$W/fps.log" 2>/dev/null)"
assert_contains "AC8.1 ps was called as ps -o lstart= -p <pid of the run>" "$FLOG" "-o lstart= -p $OWN1"
if printf '%s\n' "$FLOG" | grep -F -- "-p $OWN1" | grep -qF 'LC_ALL=C TZ=UTC0 '; then t_ok "AC8.1 that ps call ran with LC_ALL=C and TZ=UTC0 (whatever the caller's locale and zone)"; else t_bad "AC8.1 that ps call ran with LC_ALL=C and TZ=UTC0" "log: $FLOG"; fi
# an empty ps: the owner still names the pid, with an empty start string
rm -f "$W/own.copy"
OUT="$(cd "$R" && env TMPDIR="$W/tmp" PATH="$FB:$PATH" FPS_MODE=empty bash "$MUT" --base base --test "cat ../owner > $W/own.copy" 2>&1)"; RC=$?
assert_rc "AC8.1 a run whose ps prints nothing still exits 0" 0
OWN1="$(sed -n 1p "$W/own.copy" 2>/dev/null)"; OWN2="$(sed -n 2p "$W/own.copy" 2>/dev/null)"
case "$OWN1" in "" | *[!0-9]*) t_bad "AC8.1 empty ps: owner line 1 is still the pid" "got [$OWN1]" ;; *) t_ok "AC8.1 empty ps: owner line 1 is still the pid" ;; esac
assert_eq "AC8.1 empty ps: owner line 2 is empty" "" "$OWN2"

t_summary
