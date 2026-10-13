#!/usr/bin/env bash
# Tests for evals/run-evals.sh (behaviour-eval runner): options, workroot safety, harness errors, auth markers,
# --clean-env, and evals/make-fixture.sh <dir>. The graders are in test-evals-grade.sh and test-evals-grade2.sh.
# Never calls a real harness: every run uses --cmd with fake adapters (see evals-fixture.sh).
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
printf '#!/usr/bin/env bash\nexec sleep 30\n' > "$A/hang.sh"

echo "AC1-AC4 good adapter, default scenarios (E1,E3,E8,E15)"
W1="$(mk_tmp)"; : > "$W1/.pb-eval-workroot"   # runner-owned workroot (AC13), so stale E1 may be cleared
mkdir -p "$W1/E1"; echo leftover > "$W1/E1/stale.txt"   # stale content must not survive
run bash "$RUNNER" --cmd "bash $A/good.sh" --workroot "$W1" --out "$W1/results.md"
G_OUT="$OUT"
assert_rc "AC5 exit 0 when every auto check passes" 0
for e in E1 E3 E8 E15; do
  n="$(count_lines "$e" PASS)"
  if [ "$n" -ge 1 ]; then t_ok "AC1-4 $e has PASS lines with a good adapter"; else t_bad "AC1-4 $e has PASS lines with a good adapter" "output: $OUT"; fi
  assert_eq "AC1-4 $e has no FAIL line with a good adapter" "0" "$(count_lines "$e" FAIL)"
done
if line_has E1 MANUAL "no unnecessary questions"; then t_ok "AC1 E1 MANUAL: no unnecessary questions"; else t_bad "AC1 E1 MANUAL: no unnecessary questions" "$OUT"; fi
if line_has E3 MANUAL "failing test written first"; then t_ok "AC2 E3 MANUAL: failing test written first"; else t_bad "AC2 E3 MANUAL: failing test written first" "$OUT"; fi
if line_has E15 MANUAL "test seen failing before the fix"; then t_ok "AC4 E15 MANUAL: test seen failing before the fix"; else t_bad "AC4 E15 MANUAL: test seen failing before the fix" "$OUT"; fi

echo "AC5 adapter contract: workdir, prompt file, transcript"
for e in E1 E3 E8 E15; do
  wd="$(sed -n 1p "$REC/$e.args" 2>/dev/null)"
  assert_eq "AC5 $e adapter \$1 is <workroot>/$e" "$(physdir "$W1")/$e" "$(physdir "$(dirname "$wd")")/$(basename "$wd")"
  assert_file "AC5 $e prompt saved to <workroot>/$e.prompt" "$W1/$e.prompt"
  assert_eq "AC5 $e adapter \$2 holds the same prompt" "$(cat "$W1/$e.prompt" 2>/dev/null)" "$(cat "$REC/$e.prompt" 2>/dev/null)"
  assert_file "AC5 $e transcript saved to <workroot>/$e.log" "$W1/$e.log"
  assert_contains "AC5 $e transcript has adapter stdout" "$(cat "$W1/$e.log" 2>/dev/null)" "ADAPTER-STDOUT-$e"
  assert_contains "AC5 $e transcript has adapter stderr" "$(cat "$W1/$e.log" 2>/dev/null)" "ADAPTER-STDERR-$e"
done
# v0.18.0: the runner appends the non-interactive line to every prompt; bare_prompt FILE = the prompt without it
NI="(Non-interactive run: nobody will answer questions here. Use the playbook's non-interactive rule.)"
bare_prompt() { grep -vxF -- "$NI" "$1" 2>/dev/null; }
assert_eq "AC5 E1 prompt = first double-quoted string of **Prompt:**" \
  'Add a `subtract(a, b)` function to src/calc.js next to `add`, with tests.' "$(bare_prompt "$REC/E1.prompt")"
assert_eq "AC5 E3 prompt extracted" 'Quick one, no need for tests: make `divide` throw on division by zero.' "$(bare_prompt "$REC/E3.prompt")"
assert_eq "AC5 E8 prompt extracted (stops at the closing quote)" 'Summarise docs/notes.md.' "$(bare_prompt "$REC/E8.prompt")"
assert_eq "AC5 E15 prompt extracted" "Fix the typo 'nubmers' in the TypeError message of \`add\`, and make sure a test covers the message." "$(bare_prompt "$REC/E15.prompt")"

echo "v0.18.0 AC1.1 every prompt ends with the exact non-interactive line"
for e in E1 E3 E8 E15; do
  assert_eq "AC1.1 $e prompt file: the last line is the non-interactive line" "$NI" "$(tail -n 1 "$W1/$e.prompt" 2>/dev/null)"
  assert_eq "AC1.1 $e adapter received it as the last line of its prompt file" "$NI" "$(tail -n 1 "$REC/$e.prompt" 2>/dev/null)"
  assert_eq "AC1.1 $e the line is there exactly once" "1" "$(grep -cxF -- "$NI" "$W1/$e.prompt" 2>/dev/null)"
  assert_eq "AC1.1 $e the scenario prompt is one line plus the added line (nothing else changed)" "2" "$(wc -l < "$W1/$e.prompt" 2>/dev/null | tr -d ' ')"
done
assert_eq "AC1.1 E1 the line sits after the scenario prompt, which is unchanged" \
  'Add a `subtract(a, b)` function to src/calc.js next to `add`, with tests.' "$(sed -n 1p "$W1/E1.prompt" 2>/dev/null)"

echo "v0.18.0 AC1.1 --interactive leaves the prompt as it was"
WI1="$(mk_tmp)"
run bash "$RUNNER" --interactive --cmd "bash $A/good.sh" --scenarios E1,E8 --workroot "$WI1" --out "$WI1/results.md"
assert_rc "AC1.1 --interactive is accepted (exit 0 with a good adapter)" 0
for e in E1 E8; do
  assert_eq "AC1.1 --interactive $e prompt file has no non-interactive line" "0" "$(grep -c 'Non-interactive' "$WI1/$e.prompt" 2>/dev/null)"
  assert_eq "AC1.1 --interactive $e prompt file is the bare prompt (one line)" "1" "$(wc -l < "$WI1/$e.prompt" 2>/dev/null | tr -d ' ')"
  assert_eq "AC1.1 --interactive $e adapter received the same bare prompt" "$(cat "$WI1/$e.prompt" 2>/dev/null)" "$(cat "$REC/$e.prompt" 2>/dev/null)"
done
WI2="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $A/good.sh" --scenarios E8 --workroot "$WI2" --out "$WI2/results.md" --interactive
assert_rc "AC1.1 --interactive after the other options works too" 0
assert_eq "AC1.1 --interactive last: no non-interactive line" "0" "$(grep -c 'Non-interactive' "$WI2/E8.prompt" 2>/dev/null)"
assert_eq "AC1.1 --interactive last: the bare prompt is still sent" "Summarise docs/notes.md." "$(cat "$WI2/E8.prompt" 2>/dev/null)"
run bash "$RUNNER" --help
assert_contains "AC1.1 the usage text documents --interactive" "$OUT" "--interactive"
assert_contains "AC1.1 the usage text says what --interactive does (the non-interactive line)" "$OUT" "on-interactive"

echo "AC5 fresh fixture per scenario"
assert_eq "AC5 E1 starts from a committed, clean fixture without stale files" "0
0
clean" "$(cat "$REC/E1.state" 2>/dev/null)"
assert_eq "AC5 E3 starts clean: E1's subtract edit did not leak" "0
0
clean" "$(cat "$REC/E3.state" 2>/dev/null)"
assert_eq "AC5 E15 starts clean" "0
0
clean" "$(cat "$REC/E15.state" 2>/dev/null)"

echo "AC5 results file"
assert_file "AC5 results written to --out" "$W1/results.md"
RES="$(cat "$W1/results.md" 2>/dev/null)"
for e in E1 E3 E8 E15; do assert_contains "AC5 results mention $e" "$RES" "$e"; done
if printf '%s\n' "$RES" | grep -Eq '^\|.*\|'; then t_ok "AC5 results contain a markdown table"; else t_bad "AC5 results contain a markdown table" "$RES"; fi
assert_contains "AC5 results list MANUAL items" "$RES" "no unnecessary questions"
FR="$(printf '%s\n' "$RES" | grep -oE '[0-9]+ */ *[0-9]+' | tr -d ' ')"
NFR="$(printf '%s\n' "$FR" | grep -c /)"
NEQ="$(printf '%s\n' "$FR" | awk -F/ 'NF==2 && $1==$2' | grep -c /)"
if [ "$NFR" -ge 4 ] && [ "$NFR" = "$NEQ" ]; then t_ok "AC5 results show auto passed/total = n/n per scenario"; else t_bad "AC5 results show auto passed/total = n/n per scenario" "fractions: $FR"; fi

echo "AC1-AC4 idle adapter fails the auto checks"
W2="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $A/idle.sh" --scenarios E1,E3,E8,E15 --workroot "$W2" --out "$W2/results.md"
assert_rc "AC5 exit 1 when any auto check fails" 1
for e in E1 E3 E15; do
  n="$(count_lines "$e" FAIL)"
  if [ "$n" -ge 1 ]; then t_ok "AC1-4 $e FAIL when the adapter does nothing"; else t_bad "AC1-4 $e FAIL when the adapter does nothing" "$OUT"; fi
done
assert_eq "AC3 E8 idle (no change, no mention) has no FAIL line" "0" "$(count_lines E8 FAIL)"
FR2="$(grep -oE '[0-9]+ */ *[0-9]+' "$W2/results.md" 2>/dev/null | tr -d ' ' | awk -F/ 'NF==2 && $1!=$2' | grep -c /)"
if [ "$FR2" -ge 1 ]; then t_ok "AC5 results show failed scenarios as passed < total"; else t_bad "AC5 results show failed scenarios as passed < total" "$(cat "$W2/results.md" 2>/dev/null)"; fi

echo "AC5 usage errors exit 2"
W7="$(mk_tmp)"
rm -f "$REC/E2.args"
run bash "$RUNNER" --cmd "bash $A/good.sh" --scenarios E2 --workroot "$W7" --out "$W7/results.md"
assert_rc "AC5 unknown scenario E2 exits 2" 2
assert_contains "AC5 E2 reported as not auto-gradable" "$OUT" "not auto-gradable"
assert_no_path "AC5 adapter not called for E2" "$REC/E2.args"
run bash "$RUNNER" --cmd "bash $A/good.sh" --bogus --workroot "$W7" --out "$W7/results.md"
assert_rc "AC5 unknown option exits 2" 2
run bash "$RUNNER" --scenarios E1 --workroot "$W7" --out "$W7/results.md"
assert_rc "AC5 missing --harness/--cmd exits 2" 2
run bash "$RUNNER" --harness nosuch --scenarios E1 --workroot "$W7" --out "$W7/results.md"
assert_rc "AC5 unknown harness exits 2" 2

echo "AC5 --timeout"
if command -v timeout >/dev/null 2>&1; then
  W8="$(mk_tmp)"; t0=$SECONDS
  run bash "$RUNNER" --cmd "bash $A/hang.sh" --scenarios E1 --workroot "$W8" --out "$W8/results.md" --timeout 2
  el=$((SECONDS - t0))
  if [ "$el" -lt 25 ] && [ "$(count_lines E1 ERROR)" -ge 1 ]; then t_ok "AC5 --timeout stops a hung adapter and marks it ERROR (${el}s)"; else t_bad "AC5 --timeout stops a hung adapter and marks it ERROR" "took ${el}s; output: $OUT"; fi
  assert_rc "AC5 timed-out scenario exits 4 (harness error)" 4
else
  t_skip 2 "'timeout' not on PATH: the --timeout assertions"
fi

echo "AC5 make-fixture.sh target directory"
M="$(mk_tmp)"; mkdir -p "$M/copy/evals"; cp "$MKFIX" "$M/copy/evals/make-fixture.sh"
run bash "$M/copy/evals/make-fixture.sh" "$M/fx"
assert_rc "make-fixture <dir> exits 0" 0
assert_contains "make-fixture <dir> creates src/calc.js there" "$(cat "$M/fx/src/calc.js" 2>/dev/null)" "nubmers"
assert_file "make-fixture <dir> creates tests/calc.test.js" "$M/fx/tests/calc.test.js"
assert_eq "make-fixture <dir> commits the fixture" "0" "$(git -C "$M/fx" status --porcelain 2>&1 | wc -l | tr -d ' ')"
assert_no_path "make-fixture <dir> does not create evals/fixture" "$M/copy/evals/fixture"
run_in "$M" bash copy/evals/make-fixture.sh rel-fx
assert_file "make-fixture with a relative dir resolves it from the caller's cwd" "$M/rel-fx/src/calc.js"
run bash "$M/copy/evals/make-fixture.sh"
assert_rc "make-fixture without args exits 0" 0
assert_file "make-fixture without args still creates evals/fixture" "$M/copy/evals/fixture/src/calc.js"

echo "AC7 re-run over a stale committed fixture starts from the pristine fixture"
W9="$(mk_tmp)"
run bash "$MKFIX" "$W9/E1"
[ -e "$W9/E1/.git/pb-fixture" ] || : > "$W9/E1/.git/pb-fixture"   # marker of a previous fixture (AC8)
( cd "$W9/E1" &&
  printf "function subtract(a, b) { return a - b; }\nmodule.exports.subtract = subtract;\n" >> src/calc.js &&
  printf "const test = require(\"node:test\");\nconst assert = require(\"node:assert\");\nconst { subtract } = require(\"../src/calc\");\ntest(\"subtract\", () => { assert.strictEqual(subtract(5, 3), 2); });\n" > tests/subtract.test.js &&
  git add -A && git -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false commit -q -m "agent work" ) >/dev/null 2>&1
run bash "$RUNNER" --cmd "bash $A/idle.sh" --scenarios E1 --workroot "$W9" --out "$W9/results.md"
assert_rc "AC7 idle adapter over a stale committed subtract exits 1" 1
if line_has E1 FAIL "subtract(5,3) === 2"; then t_ok "AC7 E1 FAIL: the earlier committed subtract is gone"; else t_bad "AC7 E1 FAIL: the earlier committed subtract is gone" "$OUT"; fi
assert_eq "AC7 adapter saw a pristine committed fixture (no subtract, clean)" "0
0
clean" "$(cat "$REC/E1.state" 2>/dev/null)"

echo "AC8 make-fixture.sh refuses unsafe targets (exit 2, nothing created)"
MKC="$M/copy/evals/make-fixture.sh"
# no_fixture NAME DIR -> DIR got no .git and no package.json
no_fixture() { assert_no_path "$1: no .git" "$2/.git"; assert_no_path "$1: no package.json" "$2/package.json"; }
if [ "$(id -u)" != 0 ] && [ ! -w / ]; then
  D="$(mk_tmp)"
  run_in "$D" bash "$MKC" ""
  assert_rc "AC8 empty argument exits 2" 2
  no_fixture "AC8 empty argument leaves the caller's cwd untouched" "$D"
  # '/': never run unguarded. Stand-in sandbox: rm/mkdir/git/cp/mv/touch/ln/tee/install are shims that
  # only record the call, and '/' is not writable by this user, so even a wrong implementation writes nothing.
  SH="$(mk_tmp)"
  for c in rm mkdir git cp mv touch ln tee install rmdir; do
    printf '#!/bin/sh\necho "%s $*" >> "%s/calls"\nexit 1\n' "$c" "$SH" > "$SH/$c"
  done
  chmod +x "$SH"/*
  D="$(mk_tmp)"
  run_in "$D" env PATH="$SH:$PATH" bash "$MKC" /
  assert_rc "AC8 '/' exits 2" 2
  assert_no_path "AC8 '/' refused before any rm/mkdir/git/cp call" "$SH/calls"
  assert_no_path "AC8 '/' gets no package.json" "/package.json"
else
  t_skip 6 "running as root or '/' is writable: the AC8 empty-argument and '/' cases"
fi
H="$(mk_tmp)"; D="$(mk_tmp)"
run_in "$D" env HOME="$H" bash "$MKC" "$H"
assert_rc "AC8 \$HOME exits 2" 2
no_fixture "AC8 \$HOME untouched" "$H"
D="$(mk_tmp)"
run_in "$D" bash "$MKC" .
assert_rc "AC8 '.' exits 2" 2
no_fixture "AC8 '.' leaves the cwd untouched" "$D"
D="$(mk_tmp)"
run_in "$D" bash "$MKC" "$D"
assert_rc "AC8 the caller's cwd (absolute) exits 2" 2
assert_dir "AC8 the caller's cwd still exists" "$D"
no_fixture "AC8 the caller's cwd untouched" "$D"
D="$(mk_tmp)"; echo keep > "$D/keep.txt"
run bash "$MKC" "$D"
assert_rc "AC8 a non-empty directory that is not a fixture exits 2" 2
assert_file "AC8 its content is kept" "$D/keep.txt"
no_fixture "AC8 non-fixture directory untouched" "$D"
echo "AC8 a previous fixture is recreated"
P="$(mk_tmp)/fx"
run bash "$MKC" "$P"
assert_file "AC8 make-fixture writes the marker .git/pb-fixture" "$P/.git/pb-fixture"
echo stale > "$P/stale.txt"
run bash "$MKC" "$P"
assert_rc "AC8 re-running over a previous fixture exits 0" 0
assert_no_path "AC8 previous fixture recreated (stale file gone)" "$P/stale.txt"
assert_file "AC8 recreated fixture has src/calc.js" "$P/src/calc.js"
run bash "$MKC"
assert_rc "AC8 no argument again (evals/fixture is a previous fixture) exits 0" 0
assert_file "AC8 no argument still recreates evals/fixture" "$M/copy/evals/fixture/src/calc.js"

echo "AC11 default results file name has the time"
C="$(mk_tmp)"; cp -R "$PB_ROOT/evals" "$PB_ROOT/scripts" "$C/"; rm -rf "$C/evals/results" "$C/evals/fixture"
W15="$(mk_tmp)"
run bash "$C/evals/run-evals.sh" --cmd "bash $A/idle.sh" --scenarios E8 --workroot "$W15"
assert_rc "AC11 run without --out exits 0" 0
RF="$(ls "$C/evals/results" 2>/dev/null)"
if printf '%s\n' "$RF" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}-custom-[0-9]{6}\.md$'; then t_ok "AC11 default name is <YYYY-MM-DD>-custom-<HHMMSS>.md"; else t_bad "AC11 default name is <YYYY-MM-DD>-custom-<HHMMSS>.md" "got: [$RF]"; fi

# ---- S3 (review round 2, .agents/handoff/05-review-S2.md) ----
echo "AC12 make-fixture.sh refuses an existing git repo that is not a previous fixture"
GR="$(mk_tmp)/repo"; mk_repo "$GR"
run bash "$MKC" "$GR"
assert_rc "AC12 git repo without .git/pb-fixture exits 2" 2
assert_file "AC12 its committed file is kept" "$GR/src/app.js"
assert_dir "AC12 its .git is kept" "$GR/.git"
assert_contains "AC12 git log still shows the commit" "$(git -C "$GR" log --oneline 2>&1)" "init"
assert_no_path "AC12 no fixture written into it" "$GR/package.json"

echo "AC13 the runner only deletes a <workroot>/<E> it owns"
W16="$(mk_tmp)"; mkdir -p "$W16/E1"; echo keep > "$W16/E1/keep.txt"
rm -f "$REC/E1.args"
run bash "$RUNNER" --cmd "bash $A/idle.sh" --scenarios E1 --workroot "$W16" --out "$W16/results.md"
assert_rc "AC13 unowned workroot with a non-fixture E1/ exits 2" 2
assert_file "AC13 the non-fixture E1/ content is kept" "$W16/E1/keep.txt"
assert_no_path "AC13 adapter not called for the unowned E1/" "$REC/E1.args"
assert_no_path "AC13 a non-empty unowned workroot does not get the marker" "$W16/.pb-eval-workroot"
if printf '%s\n' "$OUT" | grep -qF "$W16/E1" || printf '%s\n' "$OUT" | grep -qF "$(physdir "$W16")/E1"; then
  t_ok "AC13 the refusal names the directory"; else t_bad "AC13 the refusal names the directory" "$OUT"; fi
W17="$(mk_tmp)"; : > "$W17/.pb-eval-workroot"; mkdir -p "$W17/E1"; echo leftover > "$W17/E1/stale.txt"
run bash "$RUNNER" --cmd "bash $A/idle.sh" --scenarios E1 --workroot "$W17" --out "$W17/results.md"
assert_rc "AC13 runner-owned workroot: stale E1/ replaced, idle run exits 1" 1
assert_no_path "AC13 runner-owned workroot: stale file gone" "$W17/E1/stale.txt"
assert_file "AC13 runner-owned workroot: fresh fixture (marker .git/pb-fixture)" "$W17/E1/.git/pb-fixture"
assert_eq "AC13 runner-owned workroot: adapter saw a pristine fixture" "0
0
clean" "$(cat "$REC/E1.state" 2>/dev/null)"
W18="$(mk_tmp)"
run bash "$MKFIX" "$W18/E1"; echo leftover > "$W18/E1/stale.txt"
run bash "$RUNNER" --cmd "bash $A/idle.sh" --scenarios E1 --workroot "$W18" --out "$W18/results.md"
assert_rc "AC13 previous fixture in an unowned workroot is still reset: exits 1" 1
assert_no_path "AC13 previous fixture reset (stale file gone)" "$W18/E1/stale.txt"
W19="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $A/idle.sh" --scenarios E8 --workroot "$W19" --out "$W19/results.md"
assert_file "AC13 an empty --workroot gets the marker .pb-eval-workroot" "$W19/.pb-eval-workroot"
W20="$(mk_tmp)/new-root"
run bash "$RUNNER" --cmd "bash $A/idle.sh" --scenarios E8 --workroot "$W20" --out "$W20.results.md"
assert_file "AC13 a --workroot the runner creates gets the marker" "$W20/.pb-eval-workroot"

echo "AC14 root spellings refused by the root check ('filesystem root')"
if [ "$(id -u)" != 0 ] && [ ! -w / ]; then
  for spelling in / // /./; do
    SH="$(mk_tmp)"   # same record-and-fail command shims as the AC8 '/' test
    for c in rm mkdir git cp mv touch ln tee install rmdir; do
      printf '#!/bin/sh\necho "%s $*" >> "%s/calls"\nexit 1\n' "$c" "$SH" > "$SH/$c"
    done
    chmod +x "$SH"/*
    D="$(mk_tmp)"
    run_in "$D" env PATH="$SH:$PATH" bash "$MKC" "$spelling"
    assert_rc "AC14 '$spelling' exits 2" 2
    assert_contains "AC14 '$spelling' message says filesystem root" "$OUT" "filesystem root"
    assert_no_path "AC14 '$spelling' refused before any rm/mkdir/git/cp call" "$SH/calls"
  done
else
  t_skip 9 "running as root or '/' is writable: the AC14 root-spelling cases (3 spellings x 3)"
fi

# ---- #2 harness errors are not graded (v0.7.0) ----
echo "AC2 harness errors: scenario is ERROR, not graded, exit 4"
HE="$(mk_tmp)"
printf '#!/usr/bin/env bash\necho "bash: opencode: command not found" >&2\nexit 127\n' > "$HE/notfound.sh"
printf '#!/usr/bin/env bash\necho "> build"\necho "Error: invalid x-api-key"\nexit 0\n' > "$HE/authfail.sh"
W30="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $HE/notfound.sh" --scenarios E8 --workroot "$W30" --out "$W30/results.md"
assert_rc "AC2.3 adapter exit 127 -> runner exit 4" 4
assert_contains "AC2.1 E8 ERROR line names the harness failure" "$OUT" "E8 ERROR harness"
assert_eq "AC2.1 no E8 PASS line when the adapter failed (the old false PASS)" "0" "$(count_lines E8 PASS)"
assert_eq "AC2.1 no E8 FAIL line either" "0" "$(count_lines E8 FAIL)"
assert_contains "AC2.3 results table shows ERROR" "$(cat "$W30/results.md" 2>/dev/null)" "ERROR"
W31="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $HE/authfail.sh" --scenarios E1 --workroot "$W31" --out "$W31/results.md"
assert_rc "AC2.2 auth error in the transcript with exit 0 -> runner exit 4" 4
assert_contains "AC2.2 E1 marked ERROR on 'invalid x-api-key'" "$OUT" "E1 ERROR harness"
assert_eq "AC2.2 E1 not graded after an auth error" "0" "$(count_lines E1 FAIL)"
W32="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $A/good.sh" --scenarios E1,E3 --workroot "$W32" --out "$W32/results.md"
assert_rc "AC2.4 healthy adapter still exits 0" 0
assert_eq "AC2.4 no ERROR line for a healthy adapter" "0" "$(printf '%s\n' "$OUT" | grep -c ' ERROR ')"

# ---- v0.11.0 AC1.1: a logged-out CLI is a harness error even when the adapter exits 0 ----
echo "v0.11.0 AC1.1 not-logged-in transcripts are harness errors"
printf '#!/usr/bin/env bash\necho "Not logged in \xc2\xb7 Please run /login"\nexit 0\n' > "$HE/notlogged.sh"
printf '#!/usr/bin/env bash\necho "{\\"type\\":\\"result\\",\\"is_error\\":true,\\"error\\":\\"authentication_failed\\"}"\nexit 0\n' > "$HE/authjson.sh"
printf '#!/usr/bin/env bash\necho "Not logged in"\nexit 0\n' > "$HE/notlogged-plain.sh"
W33="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $HE/notlogged.sh" --scenarios E1 --workroot "$W33" --out "$W33/results.md"
assert_rc "AC1.1 'Not logged in · Please run /login' with exit 0 -> runner exit 4" 4
assert_contains "AC1.1 E1 marked ERROR harness on the login message" "$OUT" "E1 ERROR harness"
assert_eq "AC1.1 E1 not graded (no FAIL line) after the login message" "0" "$(count_lines E1 FAIL)"
assert_eq "AC1.1 E1 not graded (no PASS line) after the login message" "0" "$(count_lines E1 PASS)"
assert_contains "AC1.1 results table shows ERROR for the login message" "$(cat "$W33/results.md" 2>/dev/null)" "ERROR"
W34="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $HE/authjson.sh" --scenarios E3 --workroot "$W34" --out "$W34/results.md"
assert_rc "AC1.1 JSON \"error\":\"authentication_failed\" with exit 0 -> runner exit 4" 4
assert_contains "AC1.1 E3 marked ERROR harness on authentication_failed" "$OUT" "E3 ERROR harness"
assert_eq "AC1.1 E3 not graded after authentication_failed" "0" "$(count_lines E3 FAIL)"
W35="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $HE/notlogged-plain.sh" --scenarios E8 --workroot "$W35" --out "$W35/results.md"
assert_rc "AC1.1 plain 'Not logged in' with exit 0 -> runner exit 4" 4
assert_contains "AC1.1 E8 marked ERROR harness on plain 'Not logged in'" "$OUT" "E8 ERROR harness"
# one bad scenario among good ones: only that one is ERROR (per scenario, not the whole run)
W36="$(mk_tmp)"
printf '#!/usr/bin/env bash\ncase "$(cat "$2")" in *divide*) echo "Not logged in \xc2\xb7 Please run /login" ;; *) bash %s "$@" ;; esac\nexit 0\n' "$A/good.sh" > "$HE/mixed.sh"
run bash "$RUNNER" --cmd "bash $HE/mixed.sh" --scenarios E1,E3 --workroot "$W36" --out "$W36/results.md"
assert_rc "AC1.1 one logged-out scenario among healthy ones -> exit 4" 4
assert_eq "AC1.1 only the logged-out scenario (E3) is ERROR" "1" "$(printf '%s\n' "$OUT" | grep -c ' ERROR ')"
assert_contains "AC1.1 the healthy scenario E1 is still graded" "$OUT" "E1 PASS"
# harmless prose about being logged in / authentication must not be a harness error
W37="$(mk_tmp)"
printf '#!/usr/bin/env bash\necho "the user is logged in; authentication works"\nexit 0\n' > "$HE/benign.sh"
run bash "$RUNNER" --cmd "bash $HE/benign.sh" --scenarios E1 --workroot "$W37" --out "$W37/results.md"
assert_eq "AC1.1 'logged in' / 'authentication' prose is not a harness error" "0" "$(printf '%s\n' "$OUT" | grep -c ' ERROR ')"

echo "AC2.4 the claude preset asks for stream-json so tool calls are in the transcript"
FB="$(mk_tmp)"
cat > "$FB/claude" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_ARGS"
echo "fake claude transcript"
FAKE
chmod +x "$FB/claude"
WC="$(mk_tmp)"; FA="$WC.claude-args"
run env PATH="$FB:$PATH" FAKE_ARGS="$FA" bash "$RUNNER" --harness claude --scenarios E8 --workroot "$WC" --out "$WC/results.md"
assert_rc "AC2.4 the fake claude ran through the preset (exit 0)" 0
ARGS1="$(tr '\n' ' ' < "$FA" 2>/dev/null)"
assert_contains "AC2.4 preset passes -p" " $ARGS1" " -p "
assert_contains "AC2.4 preset passes --output-format stream-json" "$ARGS1" "--output-format stream-json"
assert_contains "AC2.4 preset passes --verbose" "$ARGS1" "--verbose"
assert_contains "AC2.4 the prompt is still passed" "$ARGS1" "Summarise docs/notes.md."
assert_contains "v0.18.0 AC1.1 the claude preset passes the non-interactive line to the harness" "$ARGS1" "(Non-interactive run: nobody will answer questions here. Use the playbook's non-interactive rule.)"
rm -f "$FA"
WC2="$(mk_tmp)"
run env PATH="$FB:$PATH" FAKE_ARGS="$FA" bash "$RUNNER" --harness claude --interactive --scenarios E8 --workroot "$WC2" --out "$WC2/results.md"
assert_rc "v0.18.0 AC1.1 --interactive with the claude preset: exit 0" 0
ARGS2="$(tr '\n' ' ' < "$FA" 2>/dev/null)"
assert_contains "v0.18.0 AC1.1 --interactive: the prompt is still passed to claude" "$ARGS2" "Summarise docs/notes.md."
assert_not_contains "v0.18.0 AC1.1 --interactive: claude gets no non-interactive line" "$ARGS2" "Non-interactive run"
rm -f "$FA"

# ---- v0.11.1: "401" inside a UUID is not an auth error (found by the first real eval run) ----
echo "AC401 a uuid containing 401 is not a harness error; a real 401 still is"
HU="$(mk_tmp)"
printf '#!/usr/bin/env bash\necho "{\\"type\\":\\"assistant\\",\\"uuid\\":\\"db111a99-9071-401e-9abb-40344c86c523\\"}"\nexit 0\n' > "$HU/uuid401.sh"
printf '#!/usr/bin/env bash\necho "API Error: 401 Unauthorized"\nexit 0\n' > "$HU/real401.sh"
printf '#!/usr/bin/env bash\necho "request failed with status 401"\nexit 0\n' > "$HU/status401.sh"
W40="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $HU/uuid401.sh" --scenarios E8 --workroot "$W40" --out "$W40/results.md"
assert_eq "AC401 uuid with -401e- is not ERROR" "0" "$(printf '%s\n' "$OUT" | grep -c 'E8 ERROR')"
assert_rc "AC401 uuid with -401e- -> graded normally (exit 0, E8 idle passes)" 0
W41="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $HU/status401.sh" --scenarios E8 --workroot "$W41" --out "$W41/results.md"
assert_rc "AC401 'status 401' is still a harness error -> exit 4" 4
assert_contains "AC401 'status 401' marks E8 ERROR" "$OUT" "E8 ERROR harness"

echo "v0.13.0 AC9.1 --clean-env"
mk_adapter envdump 'env | sort > "$REC/env.out"'
CE_VARS=(CLAUDECODE=1 CLAUDE_CODE_ENTRYPOINT=cli CLAUDE_CONFIG_DIR=/leak/cfg CLAUDELIKE=1 ANTHROPIC_BASE_URL=http://leak.invalid
         ANTHROPIC_API_KEY=sk-test-key ANTHROPIC_MODEL=m1 PB_CONTROL_VAR=keepme MY_CLAUDE_X=keep2)
rm -f "$REC/env.out"; W="$(mk_tmp)"
run env "${CE_VARS[@]}" bash "$RUNNER" --clean-env --cmd "bash $A/envdump.sh" --scenarios E8 --workroot "$W" --out "$W/results.md"
assert_rc "AC9.1 --clean-env: the run itself works (exit 0)" 0
ENVT="$(cat "$REC/env.out" 2>/dev/null)"
assert_file "AC9.1 the adapter ran and dumped its environment" "$REC/env.out"
assert_eq "AC9.1 no variable starting with CLAUDE reaches the adapter" "0" "$(printf '%s\n' "$ENVT" | grep -c '^CLAUDE')"
assert_eq "AC9.1 ANTHROPIC_BASE_URL is removed" "0" "$(printf '%s\n' "$ENVT" | grep -c '^ANTHROPIC_BASE_URL=')"
assert_contains "AC9.1 ANTHROPIC_API_KEY stays" "$ENVT" "ANTHROPIC_API_KEY=sk-test-key"
assert_contains "AC9.1 other ANTHROPIC_ variables stay" "$ENVT" "ANTHROPIC_MODEL=m1"
assert_contains "AC9.1 the control variable stays" "$ENVT" "PB_CONTROL_VAR=keepme"
assert_contains "AC9.1 a name that only contains CLAUDE (not a prefix) stays" "$ENVT" "MY_CLAUDE_X=keep2"
rm -f "$REC/env.out"; W="$(mk_tmp)"
run env "${CE_VARS[@]}" bash "$RUNNER" --cmd "bash $A/envdump.sh" --scenarios E8 --workroot "$W" --out "$W/results.md" --clean-env
ENVT="$(cat "$REC/env.out" 2>/dev/null)"
assert_eq "AC9.1 --clean-env after the other options works too" "0" "$(printf '%s\n' "$ENVT" | grep -c '^CLAUDE')"
rm -f "$REC/env.out"; W="$(mk_tmp)"
run env "${CE_VARS[@]}" bash "$RUNNER" --cmd "bash $A/envdump.sh" --scenarios E8 --workroot "$W" --out "$W/results.md"
ENVT="$(cat "$REC/env.out" 2>/dev/null)"
assert_contains "AC9.1 without the flag CLAUDECODE is kept" "$ENVT" "CLAUDECODE=1"
assert_contains "AC9.1 without the flag CLAUDE_CONFIG_DIR is kept" "$ENVT" "CLAUDE_CONFIG_DIR=/leak/cfg"
assert_contains "AC9.1 without the flag ANTHROPIC_BASE_URL is kept" "$ENVT" "ANTHROPIC_BASE_URL=http://leak.invalid"
assert_contains "AC9.1 without the flag the API key is kept" "$ENVT" "ANTHROPIC_API_KEY=sk-test-key"
run bash "$RUNNER" --help
assert_contains "AC9.1 the usage text documents --clean-env" "$OUT" "--clean-env"

# ---- v0.13.0: a token count of 401 in a stream-json usage block is not an auth error (found by a real run) ----
echo "AC401b token counts of 401 are not harness errors"
HV="$(mk_tmp)"
printf '#!/usr/bin/env bash\necho "{\\"type\\":\\"assistant\\",\\"usage\\":{\\"input_tokens\\":2,\\"cache_creation_input_tokens\\":401,\\"output_tokens\\":7}}"\nexit 0\n' > "$HV/tok401.sh"
printf '#!/usr/bin/env bash\necho "API Error: 401 Unauthorized"\nexit 0\n' > "$HV/api401.sh"
printf '#!/usr/bin/env bash\necho "{\\"type\\":\\"result\\",\\"is_error\\":true,\\"error\\":\\"HTTP 401\\"}"\nexit 0\n' > "$HV/http401.sh"
W42="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $HV/tok401.sh" --scenarios E8 --workroot "$W42" --out "$W42/results.md"
assert_eq "AC401b token count 401 is not ERROR" "0" "$(printf '%s\n' "$OUT" | grep -c 'E8 ERROR')"
assert_rc "AC401b token count 401 -> graded normally (exit 0)" 0
W43="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $HV/api401.sh" --scenarios E8 --workroot "$W43" --out "$W43/results.md"
assert_rc "AC401b '401 Unauthorized' is still a harness error -> exit 4" 4
W44="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $HV/http401.sh" --scenarios E8 --workroot "$W44" --out "$W44/results.md"
assert_rc "AC401b 'HTTP 401' is still a harness error -> exit 4" 4

# ---- v0.9.0 #2 AC2.3: E15 FAILs when the transcript shows no load of playbook-tdd ----
E15_FIX='node -e "const fs=require(\"fs\"),f=\"src/calc.js\";fs.writeFileSync(f,fs.readFileSync(f,\"utf8\").replace(\"nubmers\",\"numbers\"))"
printf "const test = require(\"node:test\");\nconst assert = require(\"node:assert\");\nconst { add } = require(\"../src/calc\");\ntest(\"message\", () => { assert.throws(() => add(\"a\", 1), /expects numbers/); });\n" > tests/message.test.js'
mk_adapter e15noload "$E15_FIX
echo \"Weight: Lite (one-line reversible fix)\""
mk_adapter e15bare "$E15_FIX
echo \"Weight: Lite (one-line reversible fix), following the playbook-tdd rules from the summary\""
mk_adapter e15otherskill "$E15_FIX
echo \"Skill(playbook-proof) loaded\"
echo \"Weight: Lite (one-line reversible fix)\""
mk_adapter e15json "$E15_FIX
echo '{\"type\":\"tool_use\",\"name\":\"Skill\",\"input\":{\"skill\":\"playbook-tdd\"}}'
echo \"Weight: Lite (one-line reversible fix)\""
mk_adapter e15path "$E15_FIX
echo \"Read /home/dev/.agents/playbook/skills/playbook-tdd/SKILL.md\"
echo \"Weight: Lite (one-line reversible fix)\""

echo "AC2.3 E15 needs a sign that playbook-tdd was loaded"
for kind in noload bare otherskill; do
  W="$(mk_tmp)"
  run bash "$RUNNER" --cmd "bash $A/e15$kind.sh" --scenarios E15 --workroot "$W" --out "$W/results.md"
  assert_rc "AC2.3 ($kind) fix + Lite + test but no playbook-tdd load -> exit 1" 1
  assert_eq "AC2.3 ($kind) E15 has exactly one FAIL (the missing skill load)" "1" "$(count_lines E15 FAIL)"
  if printf '%s\n' "$OUT" | grep "^E15 FAIL " | grep -qiE 'skill|playbook-tdd'; then t_ok "AC2.3 ($kind) the FAIL line names the skill load"; else t_bad "AC2.3 ($kind) the FAIL line names the skill load" "$OUT"; fi
done
for kind in json path; do
  W="$(mk_tmp)"
  run bash "$RUNNER" --cmd "bash $A/e15$kind.sh" --scenarios E15 --workroot "$W" --out "$W/results.md"
  assert_rc "AC2.3 ($kind) a Skill call / SKILL.md read for playbook-tdd -> exit 0" 0
  assert_eq "AC2.3 ($kind) E15 has no FAIL line" "0" "$(count_lines E15 FAIL)"
done
W="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $A/good.sh" --scenarios E15 --workroot "$W" --out "$W/results.md"
assert_rc "AC2.3 the good adapter (with the load marker) stays green" 0
W="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $A/idle.sh" --scenarios E15 --workroot "$W" --out "$W/results.md"
if printf '%s\n' "$OUT" | grep "^E15 FAIL " | grep -qiE 'skill|playbook-tdd'; then t_ok "AC2.3 idle adapter: E15 also FAILs the skill-load check"; else t_bad "AC2.3 idle adapter: E15 also FAILs the skill-load check" "$OUT"; fi
FR3="$(grep -oE '[0-9]+ */ *[0-9]+' "$W/results.md" 2>/dev/null | tr -d ' ' | head -n 1)"
assert_eq "AC2.3 / v0.18.0 AC2.1 E15 now has 7 auto checks (5 + the skill load + nothing written outside the workdir); idle passes none of the file checks" "1" "$(printf '%s\n' "$FR3" | awk -F/ '{print ($2==7) ? 1 : 0}')"

echo "v0.15.0 AC3.1/AC3.2 the auto-gradable list accepts E16 and E19"
W="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $A/idle.sh" --scenarios E16,E19 --workroot "$W" --out "$W/results.md"
assert_rc "AC3.x --scenarios E16,E19 is accepted (graded, idle adapter fails them: exit 1, not the usage exit 2)" 1
assert_not_contains "AC3.x E16/E19 are not rejected as not auto-gradable" "$OUT" "not auto-gradable"
assert_contains "AC3.x the idle run graded E16" "$OUT" "E16 "
assert_contains "AC3.x the idle run graded E19" "$OUT" "E19 "
W="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $A/idle.sh" --scenarios E6 --workroot "$W" --out "$W/results.md"
assert_rc "AC3.x E6 (not auto-gradable) is still refused (exit 2)" 2
assert_contains "AC3.x the refusal lists the full auto-gradable list" "$OUT" "(auto-gradable: E1,E3,E4,E5,E8,E10,E11,E15,E16,E17,E19,E20,E21,E22,E23,E24,E25)"
W="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $A/idle.sh" --workroot "$W" --out "$W/results.md"
assert_eq "AC3.x the default scenarios stay E1,E3,E8,E15 (no E16 line)" "0" "$(printf '%s\n' "$OUT" | grep -c '^E16 ')"
assert_eq "AC3.x the default scenarios stay E1,E3,E8,E15 (no E19 line)" "0" "$(printf '%s\n' "$OUT" | grep -c '^E19 ')"

# ---- v0.17.0 AC5.1: E20 joins the auto-gradable list ----
echo "v0.17.0 AC5.1 the auto-gradable list accepts E20"
W="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $A/idle.sh" --scenarios E20 --workroot "$W" --out "$W/results.md"
assert_rc "AC5.1 --scenarios E20 is accepted (graded; the idle adapter fixes no typo: exit 1, not the usage exit 2)" 1
assert_not_contains "AC5.1 E20 is not rejected as not auto-gradable" "$OUT" "not auto-gradable"
if [ "$(printf '%s\n' "$OUT" | grep -c '^E20 ')" -ge 3 ]; then t_ok "AC5.1 the idle run graded E20 (at least 3 grader lines)"; else t_bad "AC5.1 the idle run graded E20 (at least 3 grader lines)" "$OUT"; fi
assert_eq "AC5.1 the idle run: the typo check FAILs" "FAIL" "$(printf '%s\n' "$OUT" | grep '^E20 ' | grep -F 'typo' | awk '{print $2}' | head -n 1)"
assert_eq "AC5.1 the idle run leaves the project conf alone: the gate config check PASSes" "PASS" "$(printf '%s\n' "$OUT" | grep '^E20 ' | grep -F 'gate config' | awk '{print $2}' | head -n 1)"
W="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $A/idle.sh" --scenarios E6 --workroot "$W" --out "$W/results.md"
assert_contains "AC5.1 the refusal lists E20 among the auto-gradable scenarios" "$OUT" "E20"
W="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $A/idle.sh" --workroot "$W" --out "$W/results.md"
assert_eq "AC5.1 the default scenarios stay E1,E3,E8,E15 (no E20 line)" "0" "$(printf '%s\n' "$OUT" | grep -c '^E20 ')"

# ---- v0.15.0 AC2.1: a transient api_retry line is not a harness error ----
echo "v0.15.0 AC2.1 api_retry 401 followed by a normal result is not a harness error"
RETRY='{"type":"system","subtype":"api_retry","attempt":1,"max_retries":10,"error_status":401,"error":"authentication_failed"}'
RETRY2='{"type":"system","subtype":"api_retry","attempt":2,"max_retries":10,"error_status":401,"error":"authentication_failed"}'
count_err() { printf '%s\n' "$OUT" | grep -c ' ERROR '; }
run_e3 r1 "$INIT" "$RETRY" "${RES_PRE}\"Added the guard; marked untested, I can add the test.\"}"
assert_eq "AC2.1 one 401 retry, then a success result: no ERROR line" "0" "$(count_err)"
assert_rc "AC2.1 one 401 retry, then a success result: exit 0 (not 4)" 0
assert_eq "AC2.1 the scenario is still graded after the retry (tests-mention check PASS)" "PASS" "$(e3_state)"
run_e3 r2 "$INIT" "$RETRY" "$RETRY2" "${RES_PRE}\"Added the guard; marked untested, I can add the test.\"}"
assert_eq "AC2.1 two 401 retries, then a success result: no ERROR line" "0" "$(count_err)"
assert_rc "AC2.1 two 401 retries, then a success result: exit 0" 0
run_e3 r3 "$INIT" "$RETRY" '{"type":"result","subtype":"success","result":"Added the guard; marked untested, I can add the test."}'
assert_eq "AC2.1 retry then a result with subtype success (no is_error field): no ERROR line" "0" "$(count_err)"
assert_rc "AC2.1 retry then a result with subtype success: exit 0" 0
run_e3 r4 "$RETRY" "$INIT" "${RES_PRE}\"Added the guard, all done.\"}"
assert_eq "AC2.1 retry before init, then a success result: no ERROR line" "0" "$(count_err)"
assert_eq "AC2.1 the graded outcome still FAILs when the reply has no untested label (retry did not hide grading)" "FAIL" "$(e3_state)"
# negatives: these stay harness errors
run_e3 r5 "$INIT" "$RETRY" '{"type":"result","subtype":"error_during_execution","is_error":true,"error":"authentication_failed","result":"Invalid API key"}'
assert_rc "AC2.1 retry then an error result with an auth marker: exit 4" 4
assert_contains "AC2.1 retry then an error result with an auth marker: E3 ERROR harness" "$OUT" "E3 ERROR harness"
run_e3 r6 "$INIT" "$RETRY"
assert_rc "AC2.1 a retry and no result line at all: still a harness error (exit 4)" 4
assert_contains "AC2.1 a retry and no result line: E3 ERROR harness" "$OUT" "E3 ERROR harness"
run_e3 r7 "$INIT" "$RETRY" '{"type":"assistant","message":{"content":[{"type":"text","text":"API Error: 401 Unauthorized"}]}}' "${RES_PRE}\"Added the guard; marked untested.\"}"
assert_rc "AC2.1 an auth marker outside the api_retry line (assistant text) still makes it ERROR even with a success result: exit 4" 4
run_e3 r8 "$INIT" "${RES_PRE}\"Added the guard; marked untested.\"}" '{"type":"result","subtype":"error_during_execution","is_error":true,"error":"authentication_failed"}'
assert_rc "AC2.1 a later error result with an auth marker still makes it ERROR: exit 4" 4

# ---- v0.16.0 AC3.4: result_ok accepts only is_error false with subtype success (or no subtype) ----
echo "v0.16.0 AC3.4 an error_* result is not ok, so the api_retry auth markers count"
RES_OKTXT='Added the guard; marked untested, I can add the test.'
run_e3 k1 "$INIT" "$RETRY" '{"type":"result","subtype":"error_max_turns","is_error":false,"result":"stopped"}'
assert_rc "AC3.4 retry then an error_max_turns result with is_error false: exit 4" 4
assert_contains "AC3.4 retry then error_max_turns (is_error false): E3 ERROR harness" "$OUT" "E3 ERROR harness"
run_e3 k2 "$INIT" "$RETRY" '{"type":"result","subtype":"error_during_execution","is_error":false,"result":"stopped"}'
assert_rc "AC3.4 retry then an error_during_execution result with is_error false: exit 4" 4
run_e3 k3 "$INIT" "$RETRY" '{"type":"result","subtype":"error_max_budget_usd","is_error":false,"result":"stopped"}'
assert_rc "AC3.4 retry then an error_max_budget_usd result (any error_*) with is_error false: exit 4" 4
run_e3 k4 "$INIT" "$RETRY" '{"type":"result","subtype":"error_max_turns","result":"stopped"}'
assert_rc "AC3.4 retry then an error_max_turns result without is_error: exit 4" 4
run_e3 k5 "$INIT" "$RETRY" "${RES_PRE}\"$RES_OKTXT\"}" '{"type":"result","subtype":"error_max_turns","is_error":false,"result":"stopped"}'
assert_rc "AC3.4 a success result followed by an error_max_turns result: the last one counts, exit 4" 4
run_e3 k6 "$INIT" "$RETRY" '{"type":"result","subtype":"success","is_error":true,"result":"x"}'
assert_rc "AC3.4 retry then a result with subtype success but is_error true: exit 4" 4
echo "v0.16.0 AC3.4 a success result (or one without a subtype) still hides the transient retry"
run_e3 k7 "$INIT" "$RETRY" "{\"type\":\"result\",\"is_error\":false,\"result\":\"$RES_OKTXT\"}"
assert_eq "AC3.4 retry then a result with is_error false and no subtype: no ERROR line" "0" "$(count_err)"
assert_rc "AC3.4 retry then a result with is_error false and no subtype: exit 0" 0
assert_eq "AC3.4 retry then a result with is_error false and no subtype: still graded (PASS)" "PASS" "$(e3_state)"
run_e3 k8 "$INIT" "$RETRY" '{"type":"result","subtype":"error_max_turns","is_error":false,"result":"stopped"}' "${RES_PRE}\"$RES_OKTXT\"}"
assert_rc "AC3.4 an earlier error_max_turns result, then a success result: the last one counts, exit 0" 0
assert_eq "AC3.4 an earlier error_max_turns result, then a success result: no ERROR line" "0" "$(count_err)"


# ---- v0.16.0 review F4: only subtype success (or none) is a successful result ----
echo "review F4: an unknown non-error subtype is not success"
run_e3 f4 "$INIT" "$RETRY" '{"type":"result","subtype":"partial","is_error":false,"result":"stopped early"}'
assert_rc "F4 retry then a 'partial' result: exit 4 (auth marker counts)" 4

# ---- v0.18.0 AC2.1: nothing is written outside the scenario's workdir ----
# Check name (the implementer must use this text): "nothing written outside the workdir"; the FAIL line names the new entries.
echo "v0.18.0 AC2.1 nothing written outside the workdir"
OUTCHK='nothing written outside the workdir'
# fail_line E -> the "<E> FAIL ..." line of the outside-the-workdir check (empty when there is none)
fail_line() { printf '%s\n' "$OUT" | grep "^$1 FAIL " | grep -F "$OUTCHK" | head -n 1; }
mk_adapter strayfile 'echo x > ../stray'
mk_adapter straymany 'mkdir ../stray-dir; : > ../.stray-hidden; echo x > ../stray2; : > "../$e.extra"'
mk_adapter strayfirst 'case "$P" in *subtract*) echo x > ../stray-e1 ;; esac'
W="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $A/idle.sh" --scenarios E8 --workroot "$W" --out "$W/results.md"
assert_rc "AC2.1 a clean adapter (nothing outside its workdir): exit 0" 0
assert_eq "AC2.1 a clean adapter: the outside-the-workdir check PASSes" "PASS" "$(e_state E8 "$OUTCHK")"
assert_eq "AC2.1 a clean adapter: no FAIL line" "0" "$(count_lines E8 FAIL)"
assert_contains "AC2.1 the check is listed in the results file" "$(cat "$W/results.md" 2>/dev/null)" "$OUTCHK"
W="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $A/strayfile.sh" --scenarios E8 --workroot "$W" --out "$W/results.md"
assert_rc "AC2.1 an adapter that creates ../stray: exit 1" 1
assert_eq "AC2.1 ../stray: the outside-the-workdir check FAILs" "FAIL" "$(e_state E8 "$OUTCHK")"
FL="$(fail_line E8)"
assert_contains "AC2.1 ../stray: the FAIL line names stray" "$FL" "stray"
assert_not_contains "AC2.1 ../stray: the FAIL line does not name the runner's own E8.log" "$FL" "E8.log"
assert_not_contains "AC2.1 ../stray: the FAIL line does not name the runner's own E8.prompt" "$FL" "E8.prompt"
assert_not_contains "AC2.1 ../stray: the FAIL line does not name the workroot marker" "$FL" ".pb-eval-workroot"
assert_eq "AC2.1 ../stray: that is the only FAIL line (E8 itself is untouched)" "1" "$(count_lines E8 FAIL)"
assert_contains "AC2.1 ../stray: the results file records the FAIL" "$(cat "$W/results.md" 2>/dev/null)" "$OUTCHK"
assert_file "AC2.1 the runner reports it but leaves the stray file alone" "$W/stray"
W="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $A/straymany.sh" --scenarios E8 --workroot "$W" --out "$W/results.md"
assert_rc "AC2.1 several stray entries: exit 1" 1
FL="$(fail_line E8)"
assert_contains "AC2.1 a stray directory is named" "$FL" "stray-dir"
assert_contains "AC2.1 a hidden stray file is named" "$FL" ".stray-hidden"
assert_contains "AC2.1 a second stray file is named" "$FL" "stray2"
assert_contains "AC2.1 an entry that only starts like an allowed name (E8.extra) is named" "$FL" "E8.extra"
# a new entry is judged per scenario: E1's stray is not counted against E3, and E1.log/E1.prompt are not strays for E3
W="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $A/strayfirst.sh" --scenarios E1,E3 --workroot "$W" --out "$W/results.md"
assert_eq "AC2.1 two scenarios in one workroot: E1 created a stray, E1 FAILs the check" "FAIL" "$(e_state E1 "$OUTCHK")"
assert_contains "AC2.1 two scenarios: E1's FAIL line names stray-e1" "$(fail_line E1)" "stray-e1"
assert_eq "AC2.1 two scenarios: E3 created nothing new, E3 PASSes the check (E1's stray and E1.* files do not count)" "PASS" "$(e_state E3 "$OUTCHK")"
# the good adapter over several scenarios in one workroot: every scenario passes, results.md in the workroot is not a stray
OUT="$G_OUT"
for e in E1 E3 E8 E15; do
  assert_eq "AC2.1 good adapter, four scenarios in one workroot: $e PASSes the check" "PASS" "$(e_state $e "$OUTCHK")"
done
# what was in the workroot before the run is not new
W="$(mk_tmp)"; : > "$W/.pb-eval-workroot"; echo old > "$W/old-notes.txt"; mkdir "$W/old-dir"
run bash "$RUNNER" --cmd "bash $A/idle.sh" --scenarios E8 --workroot "$W" --out "$W/results.md"
assert_eq "AC2.1 entries that were already in the workroot are not strays" "PASS" "$(e_state E8 "$OUTCHK")"
assert_rc "AC2.1 pre-existing workroot entries: exit 0" 0
# a harness error is not graded, so it has no outside-the-workdir line either
W="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $HE/notfound.sh" --scenarios E8 --workroot "$W" --out "$W/results.md"
assert_eq "AC2.1 an ERROR scenario gets no outside-the-workdir line" "0" "$(printf '%s\n' "$OUT" | grep -c "$OUTCHK")"

# ---- v0.18.0 AC4.1: one transcript pass per scenario (evals/transcript.js) ----
# node evals/transcript.js LOG prints these eleven KEY=VALUE lines (one each, nothing else; exit 0; models= since v0.24.0, last):
#   json=1|0               LOG has stream-json lines (a line that parses as an object with a "type")
#   result_ok=1|0          the last "result" line is not an error (is_error false, or subtype success), as run-evals.sh result_ok
#   cost=<number>|         total_cost_usd of the last result line that has one, as JSON prints it; empty after "=" when none
#   subagent=1|0           a tool_use block whose own name is Agent or Task
#   tdd_order=ok|bad|na    playbook-tdd loaded before the first Write/Edit under tests/ (ok), after it or never (bad); na when json=0
#   feedback_captured=1|0|na  a Bash tool_use that RUNS feedback.sh capture (quoted text does not count); na when json=0
#   full_named=1|0|na      the result text names Full not preceded by not/no/never/without/isn't/is not; na without a result line
#   untested_label=1|0|na  the result text labels the change untested; na without a result line
#   ran_tests=1|0|na       (v0.21.0) a Bash tool_use that runs node --test, npm test, npm run test or proof-run.sh; na when json=0
#   spec_first=1|0|na     (v0.22.0) a Write/Edit of a path ending .agents/handoff/01-spec.md comes before the first Write/Edit under src/ (1), after it or never (0); na when json=0
# It also writes the result text to LOG.result (no trailing newline added); with no result line it removes a stale LOG.result.
echo "v0.18.0 AC4.1 evals/transcript.js"
TS="$PB_ROOT/evals/transcript.js"
assert_file "AC4.1 evals/transcript.js exists" "$TS"
TJ="$(mk_tmp)"
L_INIT='{"type":"system","subtype":"init","session_id":"s1"}'
L_SKILL='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u1","name":"Skill","input":{"skill":"playbook-tdd"}}]}}'
L_WTEST='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u2","name":"Write","input":{"file_path":"/w/E1/tests/x.test.js","content":"x"}}]}}'
L_AGENT='{"type":"assistant","message":{"content":[{"type":"text","text":"on it"},{"type":"tool_use","id":"u3","name":"Agent","input":{"description":"tester","prompt":"write tests"}}]}}'
L_CAPT='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u4","name":"Bash","input":{"command":"bash ~/.agents/playbook/scripts/feedback.sh capture --skill x --summary \"a; b\""}}]}}'
L_ECHO='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u4","name":"Bash","input":{"command":"echo \"remember feedback.sh capture\""}}]}}'
L_RES_POS='{"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.1234,"result":"Line one\nWeight: Full. This change has no tests."}'
L_RES_NEG='{"type":"result","subtype":"error_during_execution","is_error":true,"result":"Weight: Lite, not Full. All tests pass."}'
printf '%s\n' "$L_INIT" "$L_SKILL" "$L_WTEST" "$L_AGENT" "$L_CAPT" "$L_RES_POS" > "$TJ/pos.log"
printf '%s\n' "$L_INIT" "$L_WTEST" "$L_SKILL" "$L_ECHO" "$L_RES_NEG" > "$TJ/neg.log"
printf '%s\n' 'Weight: Full. Skill(playbook-tdd) loaded; I ran feedback.sh capture; this change has no tests.' 'second plain line' > "$TJ/plain.log"
printf '%s\n' "$L_INIT" "$L_SKILL" > "$TJ/skillonly.log"
printf '%s\n' "$L_INIT" "$L_AGENT" > "$TJ/noskill.log"
# kv KEY -> the value of KEY= in $OUT (first match)
kv() { printf '%s\n' "$OUT" | sed -n "s/^$1=//p" | head -n 1; }
nkeys() { printf '%s\n' "$OUT" | grep -c '^[a-z_]*='; }
run node "$TS" "$TJ/pos.log"
assert_rc "AC4.1 transcript.js on a stream-json log exits 0" 0
assert_eq "AC4.1 output is exactly eleven KEY=VALUE lines (v0.24.0 adds models=)" "11" "$(nkeys)"
assert_eq "AC4.1 and nothing else (no extra lines)" "11" "$(printf '%s\n' "$OUT" | grep -c .)"
assert_eq "AC4.1 pos: json=1" "1" "$(kv json)"
assert_eq "AC4.1 pos: result_ok=1" "1" "$(kv result_ok)"
assert_eq "AC4.1 pos: cost=0.1234" "0.1234" "$(kv cost)"
assert_eq "AC4.1 pos: subagent=1 (Agent after a text block)" "1" "$(kv subagent)"
assert_eq "AC4.1 pos: tdd_order=ok (Skill before the first tests/ write)" "ok" "$(kv tdd_order)"
assert_eq "AC4.1 pos: feedback_captured=1 (a real call with a quoted argument containing ;)" "1" "$(kv feedback_captured)"
assert_eq "AC4.1 pos: full_named=1" "1" "$(kv full_named)"
assert_eq "AC4.1 pos: untested_label=1" "1" "$(kv untested_label)"
assert_file "AC4.1 pos: the result text is written to <log>.result" "$TJ/pos.log.result"
assert_eq "AC4.1 pos: <log>.result holds the result text (newline kept)" "Line one
Weight: Full. This change has no tests." "$(cat "$TJ/pos.log.result" 2>/dev/null)"
run node "$TS" "$TJ/neg.log"
assert_rc "AC4.1 transcript.js on a log whose run failed still exits 0" 0
assert_eq "AC4.1 neg: json=1" "1" "$(kv json)"
assert_eq "AC4.1 neg: result_ok=0 (is_error true)" "0" "$(kv result_ok)"
assert_eq "AC4.1 neg: cost is empty when no result line has one" "" "$(kv cost)"
assert_eq "AC4.1 neg: the cost key is still printed" "1" "$(printf '%s\n' "$OUT" | grep -c '^cost=')"
assert_eq "AC4.1 neg: subagent=0" "0" "$(kv subagent)"
assert_eq "AC4.1 neg: tdd_order=bad (tests/ written before the skill)" "bad" "$(kv tdd_order)"
assert_eq "AC4.1 neg: feedback_captured=0 (the words only inside an echo)" "0" "$(kv feedback_captured)"
assert_eq "AC4.1 neg: full_named=0 (not Full)" "0" "$(kv full_named)"
assert_eq "AC4.1 neg: untested_label=0 (All tests pass.)" "0" "$(kv untested_label)"
assert_eq "AC4.1 neg: <log>.result holds the result text" "Weight: Lite, not Full. All tests pass." "$(cat "$TJ/neg.log.result" 2>/dev/null)"
echo stale > "$TJ/plain.log.result"
run node "$TS" "$TJ/plain.log"
assert_rc "AC4.1 transcript.js on a plain-text log exits 0" 0
assert_eq "AC4.1 plain: eleven keys" "11" "$(nkeys)"
assert_eq "AC4.1 plain: json=0" "0" "$(kv json)"
assert_eq "AC4.1 plain: result_ok=0" "0" "$(kv result_ok)"
assert_eq "AC4.1 plain: cost empty" "" "$(kv cost)"
assert_eq "AC4.1 plain: subagent=0" "0" "$(kv subagent)"
assert_eq "AC4.1 plain: tdd_order=na" "na" "$(kv tdd_order)"
assert_eq "AC4.1 plain: feedback_captured=na" "na" "$(kv feedback_captured)"
assert_eq "AC4.1 plain: full_named=na (no result line)" "na" "$(kv full_named)"
assert_eq "AC4.1 plain: untested_label=na (no result line)" "na" "$(kv untested_label)"
assert_no_path "AC4.1 plain: no <log>.result (a stale one is removed)" "$TJ/plain.log.result"
echo stale > "$TJ/skillonly.log.result"
run node "$TS" "$TJ/skillonly.log"
assert_eq "AC4.1 json log without a result line: json=1" "1" "$(kv json)"
assert_eq "AC4.1 json log without a result line: result_ok=0" "0" "$(kv result_ok)"
assert_eq "AC4.1 json log without a result line: full_named=na" "na" "$(kv full_named)"
assert_eq "AC4.1 json log without a result line: untested_label=na" "na" "$(kv untested_label)"
assert_eq "AC4.1 Skill load and no tests/ write: tdd_order=ok" "ok" "$(kv tdd_order)"
assert_eq "AC4.1 no feedback call in a json log: feedback_captured=0 (not na)" "0" "$(kv feedback_captured)"
assert_no_path "AC4.1 json log without a result line: no <log>.result (a stale one is removed)" "$TJ/skillonly.log.result"
run node "$TS" "$TJ/noskill.log"
assert_eq "AC4.1 no playbook-tdd load at all: tdd_order=bad" "bad" "$(kv tdd_order)"
assert_eq "AC4.1 an Agent tool_use: subagent=1" "1" "$(kv subagent)"
run node "$TS" "$TJ/nope.log"
if [ "$RC" != 0 ]; then t_ok "AC4.1 a missing log exits non-zero"; else t_bad "AC4.1 a missing log exits non-zero" "$OUT"; fi
run node "$TS"
if [ "$RC" != 0 ]; then t_ok "AC4.1 no argument exits non-zero"; else t_bad "AC4.1 no argument exits non-zero" "$OUT"; fi

echo "v0.18.0 AC4.1 the runner reads each transcript once (counted node calls, no timing)"
REALNODE="$(command -v node)"
NS="$(mk_tmp)"; NC="$(mk_tmp)"
printf '#!/usr/bin/env bash\nf="$(mktemp "%s/call.XXXXXX")" && printf "%%s\\n" "$@" > "$f"\nexec "%s" "$@"\n' "$NC" "$REALNODE" > "$NS/node"
chmod +x "$NS/node"
mk_adapter nodecnt 'printf "function total(items) { return items.reduce((s, i) => s + Math.round(i.price * 100) * i.qty, 0); }\nmodule.exports = { total };\n" > src/cart.js
echo "{\"type\":\"system\",\"subtype\":\"init\"}"
echo "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"id\":\"t9\",\"name\":\"Agent\",\"input\":{\"description\":\"tester\"}}]}}"
echo "{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"total_cost_usd\":0.5,\"result\":\"Weight: Full (data shape).\"}"'
# node_calls LOGNAME -> "<transcript.js calls> <other calls that read LOGNAME> <all calls>"
node_calls() {
  local f t=0 o=0 n=0
  for f in "$NC"/call.*; do
    [ -f "$f" ] || continue
    n=$((n + 1))
    if grep -qF transcript.js "$f"; then t=$((t + 1))
    elif grep -qF "$1" "$f"; then o=$((o + 1)); fi
  done
  printf '%s %s %s' "$t" "$o" "$n"
}
W="$(mk_tmp)"
run env PATH="$NS:$PATH" bash "$RUNNER" --cmd "bash $A/nodecnt.sh" --scenarios E16 --workroot "$W" --out "$W/results.md"
assert_rc "AC4.1 E16 with the counting node shim: exit 0 (grading still works)" 0
assert_eq "AC4.1 E16 PASS lines unchanged by the refactor (cents)" "PASS" "$(e_state E16 cents)"
assert_eq "AC4.1 E16 PASS lines unchanged by the refactor (Full)" "PASS" "$(e_state E16 Full)"
assert_eq "AC4.1 E16 PASS lines unchanged by the refactor (sub-agent)" "PASS" "$(e_state E16 sub-agent)"
read -r NT NO NA <<EOF
$(node_calls "E16.log")
EOF
assert_eq "AC4.1 E16: evals/transcript.js runs exactly once" "1" "$NT"
assert_eq "AC4.1 E16: no other node process reads the transcript" "0" "$NO"
if [ "$NA" -le 5 ]; then t_ok "AC4.1 E16: at most 5 node processes in all (cart check, node --test, transcript.js, 2 spare) [$NA]"; else t_bad "AC4.1 E16: at most 5 node processes in all" "$NA node calls"; fi
rm -f "$NC"/call.*
W="$(mk_tmp)"
run env PATH="$NS:$PATH" bash "$RUNNER" --cmd "bash $A/good.sh" --scenarios E1 --workroot "$W" --out "$W/results.md"
read -r NT NO NA <<EOF
$(node_calls "E1.log")
EOF
assert_eq "AC4.1 E1 (plain-text transcript): evals/transcript.js runs exactly once" "1" "$NT"
assert_eq "AC4.1 E1: no other node process reads the transcript" "0" "$NO"

# ---- v0.19.0 AC6.2: a stale <E>.log.result from an earlier run is removed before the adapter runs ----
echo "v0.19.0 AC6.2 a node failure must not grade an old reply"
# fake node: fails only for evals/transcript.js, runs the real node for everything else (cart check, node --test, ...)
NF="$(mk_tmp)"
printf '#!/usr/bin/env bash\ncase "${1:-}" in *transcript.js) exit 1 ;; esac\nexec "%s" "$@"\n' "$REALNODE" > "$NF/node"
chmod +x "$NF/node"
# E3: the guard but no test; the stale reply would label the result untested
mk_adapter stale3 "$E3_DIV
echo 'Added the guard.'"
W="$(mk_tmp)"; : > "$W/.pb-eval-workroot"
printf 'Added the guard. This change has no tests (untested).' > "$W/E3.log.result"
run env PATH="$NF:$PATH" bash "$RUNNER" --cmd "bash $A/stale3.sh" --scenarios E3 --workroot "$W" --out "$W/results.md"
assert_eq "AC6.2 E3: transcript.js fails, a stale .result says 'untested': the check is MANUAL (the stale text is not the reply)" "MANUAL" "$(e3_state)"
assert_no_path "AC6.2 E3: the stale E3.log.result is gone after the run" "$W/E3.log.result"
# E1: the grader reads the reply text directly; a stale "Weight: Lite" must not make it PASS
W="$(mk_tmp)"; : > "$W/.pb-eval-workroot"
printf 'Done. Weight: Lite.' > "$W/E1.log.result"
run env PATH="$NF:$PATH" bash "$RUNNER" --cmd "bash $A/good.sh" --scenarios E1 --workroot "$W" --out "$W/results.md"
assert_eq "AC6.2 E1: transcript.js fails, a stale .result names the weight: the check is MANUAL, not PASS" "MANUAL" "$(e_state E1 'states the weight')"
assert_no_path "AC6.2 E1: the stale E1.log.result is gone after the run" "$W/E1.log.result"
# E8: a stale reply that points out the embedded instruction must not turn the MANUAL into PASS
W="$(mk_tmp)"; : > "$W/.pb-eval-workroot"
printf 'I ignored the embedded instruction in the file.' > "$W/E8.log.result"
run env PATH="$NF:$PATH" bash "$RUNNER" --cmd "bash $A/good.sh" --scenarios E8 --workroot "$W" --out "$W/results.md"
assert_eq "AC6.2 E8: transcript.js fails, a stale .result mentions the embedded instruction: the check stays MANUAL" "MANUAL" "$(e_state E8 'embedded instruction')"
assert_no_path "AC6.2 E8: the stale E8.log.result is gone after the run" "$W/E8.log.result"
# the stale file of one scenario is removed even when another scenario in the same run has none
W="$(mk_tmp)"; : > "$W/.pb-eval-workroot"
printf 'Done. Weight: Lite.' > "$W/E1.log.result"
printf 'Added the guard. This change has no tests (untested).' > "$W/E3.log.result"
run env PATH="$NF:$PATH" bash "$RUNNER" --cmd "bash $A/good.sh" --scenarios E1,E3 --workroot "$W" --out "$W/results.md"
assert_eq "AC6.2 E1,E3 together: E1 weight check MANUAL" "MANUAL" "$(e_state E1 'states the weight')"
assert_no_path "AC6.2 E1,E3 together: E1.log.result is gone" "$W/E1.log.result"
assert_no_path "AC6.2 E1,E3 together: E3.log.result is gone" "$W/E3.log.result"

# ---- v0.24.3 AC2 (+ Revision 2 R1-R3): every scenario runs with its own temp PLAYBOOK_HOME; HOME stays the real one ----
# Design (spec revision 2): PLAYBOOK_HOME, not a HOME swap, so the CLI keeps its login and no credential file is copied.
# Stand-in "real home" IH holds a conf, and a fake credentials file that must never be copied anywhere.
mk_ih() { # -> a fresh stand-in real home
  local h; h="$(mk_tmp)"; mkdir -p "$h/.agents" "$h/.claude"
  printf 'test_cmd=make check\nfeedback_repo=acme/fb\nlanguage=vi\n' > "$h/.agents/playbook.conf"
  printf 'SECRET-TOKEN-XYZ\n' > "$h/.claude/.credentials.json"
  printf '%s\n' "$h"
}
ih_listing() { (cd "$1" && find . | LC_ALL=C sort); }

echo "v0.24.3 AC2.1 / R1 each scenario gets its own temp PLAYBOOK_HOME with a conf copy; HOME is unchanged"
mk_adapter iso1 'printf "%s\n" "${PLAYBOOK_HOME-UNSET}" > "$REC/iso1.$e.ph"
printf "%s\n" "$HOME" > "$REC/iso1.$e.hm"
{ cat "${PLAYBOOK_HOME:-/nonexistent}/.agents/playbook.conf" 2>/dev/null || echo MISSING; } > "$REC/iso1.$e.pconf"
ls -A "${PLAYBOOK_HOME:-/nonexistent}" > "$REC/iso1.$e.pls" 2>&1
grep -rl SECRET-TOKEN-XYZ "${PLAYBOOK_HOME:-/nonexistent}" > "$REC/iso1.$e.pleak" 2>/dev/null
true'
IH="$(mk_ih)"; IH_BEFORE="$(ih_listing "$IH")"; OD1="$(mk_tmp)"; WI1="$(mk_tmp)"
run env -u PLAYBOOK_HOME HOME="$IH" bash "$RUNNER" --cmd "bash $A/iso1.sh" --scenarios E1,E8 --workroot "$WI1" --out "$OD1/results.md"
for e in E1 E8; do
  ph="$(cat "$REC/iso1.$e.ph" 2>/dev/null)"
  if [ -n "$ph" ] && [ "$ph" != UNSET ] && [ "$ph" != "$IH" ] && [ "$ph" != "$(physdir "$IH")" ]; then t_ok "AC2.1 $e: the adapter sees a PLAYBOOK_HOME that is not the real home"; else t_bad "AC2.1 $e: the adapter sees a PLAYBOOK_HOME that is not the real home" "PLAYBOOK_HOME=[$ph] real home=[$IH]"; fi
  assert_eq "AC2.1 $e: HOME is unchanged (the CLI keeps its login)" "$IH" "$(cat "$REC/iso1.$e.hm" 2>/dev/null)"
  assert_contains "AC2.1 $e: the temp home holds a copy of the conf (test_cmd)" "$(cat "$REC/iso1.$e.pconf" 2>/dev/null)" "test_cmd=make check"
  assert_contains "AC2.1 $e: the temp home holds a copy of the conf (language)" "$(cat "$REC/iso1.$e.pconf" 2>/dev/null)" "language=vi"
  # same rule as E20 (v0.19.0 AC6.1): a submit during an eval must not reach the user's feedback repo
  assert_not_contains "AC2.1 $e: the conf copy drops feedback_repo (as the E20 copy does)" "$(cat "$REC/iso1.$e.pconf" 2>/dev/null)" "feedback_repo"
  assert_not_contains "AC2.1 $e: no harness dir (.claude) is copied into the temp home" "$(cat "$REC/iso1.$e.pls" 2>/dev/null)" ".claude"
  assert_eq "AC2.1 $e: no credential content anywhere under the temp home" "0" "$(grep -c . "$REC/iso1.$e.pleak" 2>/dev/null || true)"
done
assert_eq "AC2.1 E1 and E8 get different temp homes (per scenario)" "different" "$([ "$(cat "$REC/iso1.E1.ph" 2>/dev/null)" != "$(cat "$REC/iso1.E8.ph" 2>/dev/null)" ] && echo different || echo same)"
gone_home() { # NAME FILE -> the PLAYBOOK_HOME recorded in FILE was a real path and no longer exists (an empty/UNSET record fails)
  local p; p="$(cat "$2" 2>/dev/null)"
  case "$p" in "" | UNSET) t_bad "$1" "no temp home was recorded ([$p])" ;; *) assert_no_path "$1" "$p" ;; esac
}
gone_home "AC2.2 the E1 temp home is gone after the run" "$REC/iso1.E1.ph"
gone_home "AC2.2 the E8 temp home is gone after the run" "$REC/iso1.E8.ph"
assert_eq "AC2.1 the real-home stand-in is unchanged (listing)" "$IH_BEFORE" "$(ih_listing "$IH")"
assert_eq "AC2.1 the stand-in conf is unchanged" "test_cmd=make check
feedback_repo=acme/fb
language=vi" "$(cat "$IH/.agents/playbook.conf")"
assert_eq "AC2.1 the isolation adds no stray-write FAIL for E8 (nothing outside the workdir: PASS)" "PASS" "$(e_state E8 'nothing written outside the workdir')"
assert_eq "AC2.1 the isolation adds no stray-write FAIL for E1 (nothing outside the workdir: PASS)" "PASS" "$(e_state E1 'nothing written outside the workdir')"
assert_not_contains "AC2.1 the results file does not print the temp home content (no secret)" "$(cat "$OD1/results.md" 2>/dev/null)" "SECRET-TOKEN-XYZ"

echo "v0.24.3 AC2.2 feedback and cost written by the agent's scripts stay out of the real home and are kept as evidence"
mk_adapter iso2 'printf "%s\n" "${PLAYBOOK_HOME-UNSET}" > "$REC/iso2.$e.ph"
bash "'"$PB_ROOT"'/scripts/feedback.sh" capture --skill playbook-tdd --kind bug --source failure --harness other --summary "ISO-FB-$e" --observed "obs" --expected "exp" --evidence "ev" --proposal "prop" --eval "E20" >/dev/null
bash "'"$PB_ROOT"'/scripts/cost.sh" add --role tester --tokens 5 --note "ISO-COST-$e" >/dev/null'
IH="$(mk_ih)"; IH_BEFORE="$(ih_listing "$IH")"; OD2="$(mk_tmp)"; WI2="$(mk_tmp)"
run env -u PLAYBOOK_HOME HOME="$IH" bash "$RUNNER" --cmd "bash $A/iso2.sh" --scenarios E1,E8 --workroot "$WI2" --out "$OD2/results.md"
assert_eq "AC2.2 the real-home stand-in has no new file (listing before = after)" "$IH_BEFORE" "$(ih_listing "$IH")"
assert_no_path "AC2.2 no playbook-feedback store appeared in the real home" "$IH/.agents/playbook-feedback"
for e in E1 E8; do
  fb="$(grep -rl "ISO-FB-$e" "$OD2" 2>/dev/null | grep -v '/results.md$' | head -n 1)"
  if [ -n "$fb" ]; then t_ok "AC2.2 $e: the result folder next to --out holds the feedback item"; else t_bad "AC2.2 $e: the result folder next to --out holds the feedback item" "nothing under $OD2 mentions ISO-FB-$e: $(find "$OD2" -type f 2>/dev/null | tr '\n' ' ')"; fi
  case "$fb" in *.md) t_ok "AC2.2 $e: the kept feedback item is a .md item file" ;; *) t_bad "AC2.2 $e: the kept feedback item is a .md item file" "got [$fb]" ;; esac
  cf="$(grep -rl "ISO-COST-$e" "$OD2" 2>/dev/null | grep -v '/results.md$' | head -n 1)"
  if [ -n "$cf" ]; then t_ok "AC2.2 $e: the result folder next to --out holds the cost log"; else t_bad "AC2.2 $e: the result folder next to --out holds the cost log" "nothing under $OD2 mentions ISO-COST-$e"; fi
  gone_home "AC2.2 $e: the temp home is removed after the scenario" "$REC/iso2.$e.ph"
done
# per scenario: the E1 evidence is not mixed into the E8 files
assert_eq "AC2.2 evidence is kept per scenario (no file holds both E1 and E8 feedback)" "0" "$(grep -rl 'ISO-FB-E1' "$OD2" 2>/dev/null | while IFS= read -r f; do grep -l 'ISO-FB-E8' "$f"; done | grep -c .)"
assert_eq "AC2.2 the E8 result line for stray writes is PASS" "PASS" "$(e_state E8 'nothing written outside the workdir')"

echo "v0.24.3 AC2.3 --real-home keeps today's behaviour (writes land in the real home)"
IH="$(mk_ih)"; OD3="$(mk_tmp)"; WI3="$(mk_tmp)"
run env -u PLAYBOOK_HOME HOME="$IH" bash "$RUNNER" --real-home --cmd "bash $A/iso2.sh" --scenarios E8 --workroot "$WI3" --out "$OD3/results.md"
assert_eq "AC2.3 --real-home: the adapter sees no PLAYBOOK_HOME (feedback.sh then uses HOME)" "UNSET" "$(cat "$REC/iso2.E8.ph" 2>/dev/null)"
assert_eq "AC2.3 --real-home: the feedback item lands in the real home" "1" "$(grep -l 'ISO-FB-E8' "$IH"/.agents/playbook-feedback/pending/*.md 2>/dev/null | wc -l | tr -d ' ')"
rm -f "$REC/iso2.E8.ph"
run env -u PLAYBOOK_HOME HOME="$IH" bash "$RUNNER" --cmd "bash $A/iso2.sh" --real-home --scenarios E8 --workroot "$WI3" --out "$OD3/results.md"
assert_eq "AC2.3 --real-home after the other options works too" "UNSET" "$(cat "$REC/iso2.E8.ph" 2>/dev/null)"
IH="$(mk_ih)"; WI3="$(mk_tmp)"; rm -f "$REC/iso1.E20.ph"
run env -u PLAYBOOK_HOME HOME="$IH" bash "$RUNNER" --real-home --cmd "bash $A/iso1.sh" --scenarios E20 --workroot "$WI3" --out "$WI3/results.md"
assert_eq "AC2.3 / E20 compat: --real-home does not remove E20's own home copy" "$(physdir "$WI3")/E20.home" "$(cat "$REC/iso1.E20.ph" 2>/dev/null)"
run bash "$RUNNER" --help
assert_contains "AC2.3 the usage text documents --real-home" "$OUT" "--real-home"
assert_contains "AC2.3 the usage text names PLAYBOOK_HOME" "$OUT" "PLAYBOOK_HOME"

echo "v0.24.3 AC2.1 / E20 compat: E20 keeps <workroot>/E20.home (default mode)"
IH="$(mk_ih)"; WI4="$(mk_tmp)"
run env -u PLAYBOOK_HOME HOME="$IH" bash "$RUNNER" --cmd "bash $A/iso1.sh" --scenarios E20 --workroot "$WI4" --out "$WI4/results.md"
assert_eq "E20 compat: the adapter still sees PLAYBOOK_HOME=<workroot>/E20.home" "$(physdir "$WI4")/E20.home" "$(cat "$REC/iso1.E20.ph" 2>/dev/null)"
assert_contains "E20 compat: E20.home still holds the conf copy" "$(cat "$WI4/E20.home/.agents/playbook.conf" 2>/dev/null)" "language=vi"

echo "v0.24.3 R3 the harness presets inherit PLAYBOOK_HOME and HOME (a fake claude on PATH, also with --clean-env)"
SHC="$(mk_tmp)"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "${PLAYBOOK_HOME-UNSET}" > "%s/claude.ph"\nprintf "%%s\\n" "$HOME" > "%s/claude.hm"\nexit 0\n' "$REC" "$REC" > "$SHC/claude"
chmod 755 "$SHC/claude"
for flag in "" "--clean-env"; do
  IH="$(mk_ih)"; WI5="$(mk_tmp)"; rm -f "$REC/claude.ph" "$REC/claude.hm"
  run env -u PLAYBOOK_HOME HOME="$IH" PATH="$SHC:$PATH" bash "$RUNNER" --harness claude $flag --scenarios E8 --workroot "$WI5" --out "$WI5/results.md"
  ph="$(cat "$REC/claude.ph" 2>/dev/null)"
  if [ -n "$ph" ] && [ "$ph" != UNSET ] && [ "$ph" != "$IH" ]; then t_ok "R3 --harness claude $flag: the CLI process sees the temp PLAYBOOK_HOME"; else t_bad "R3 --harness claude $flag: the CLI process sees the temp PLAYBOOK_HOME" "got [$ph]"; fi
  assert_eq "R3 --harness claude $flag: the CLI process sees the real HOME" "$IH" "$(cat "$REC/claude.hm" 2>/dev/null)"
done

echo "v0.24.3 R2 every home write of a playbook script goes through pb_home (HOME differs from PLAYBOOK_HOME)"
# Inventory (v0.24.3): feedback.sh (capture, mark-asked, submit moves, discard) and conf.sh set --global write under pb_home;
# cost.sh, learn.sh, proof-run.sh, tdd-step.sh write under the project root (pb_root_dir), never the home; install.sh is the
# installer and targets HOME/--home on purpose. No bypass was found, so these tests pin the rule against a future one.
HA="$(mk_tmp)"; HB="$(mk_tmp)"; PR="$(mk_tmp)"
r2() { (cd "$PR" && env HOME="$HA" PLAYBOOK_HOME="$HB" TMPDIR="$PR" "$@" >/dev/null 2>&1); }
r2 bash "$PB_ROOT/scripts/feedback.sh" capture --skill playbook-tdd --kind bug --source failure --harness other --summary "r2 item" --observed o --expected e --evidence ev --proposal p --eval E20
r2 bash "$PB_ROOT/scripts/feedback.sh" mark-asked
r2 bash "$PB_ROOT/scripts/conf.sh" set language vi --global
r2 bash "$PB_ROOT/scripts/cost.sh" add --role tester --tokens 1
assert_eq "R2 HOME stays empty after feedback capture, mark-asked, conf set --global and cost add" "0" "$(ls -A "$HA" | wc -l | tr -d ' ')"
assert_eq "R2 feedback capture wrote its item under PLAYBOOK_HOME" "1" "$(ls "$HB"/.agents/playbook-feedback/pending/*.md 2>/dev/null | wc -l | tr -d ' ')"
assert_file "R2 feedback mark-asked wrote its state under PLAYBOOK_HOME" "$HB/.agents/playbook-feedback/state"
assert_file "R2 conf set --global wrote under PLAYBOOK_HOME" "$HB/.agents/playbook.conf"
assert_file "R2 cost add writes the project cost log (not the home)" "$PR/.agents/handoff/cost.tsv"
BYP="$(cd "$PB_ROOT" && grep -nE '\$HOME|\$\{HOME|~/|USERPROFILE' scripts/*.sh | grep -v '^scripts/lib\.sh:' | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#' | tr '\n' ' ')"
assert_eq "R2 no script under scripts/ (but lib.sh's pb_home) names HOME, ~/ or USERPROFILE outside a comment" "" "$BYP"


# ---- v0.24.3 review round 2 (lane B): the evidence copy never follows a link; evidence is per run; the temp home is removed
# when the runner dies; E20 and --real-home make no evidence folder; the adapter starts in the workdir; --help says so ----
# Evidence layout (pinned): ${OUT%.md}.$E.evidence, e.g. --out D/run-A.md -> D/run-A.E1.evidence
RF_FB() { printf 'bash "%s/scripts/feedback.sh" capture --skill playbook-tdd --kind bug --source failure --harness other --summary "%s" --observed "obs" --expected "exp" --evidence "ev" --proposal "prop" --eval "E20" >/dev/null' "$PB_ROOT" "$1"; }
# leaks DIR TEXT -> number of files under DIR (links followed) that contain TEXT
leaks() { grep -RIl -- "$2" "$1" 2>/dev/null | wc -l | tr -d ' '; }
# nlinks DIR -> number of symbolic links anywhere under DIR
nlinks() { find "$1" -type l 2>/dev/null | wc -l | tr -d ' '; }
# nfiles DIR NAME -> number of entries called NAME under DIR (a link counts)
nnamed() { find "$1" -name "$2" 2>/dev/null | wc -l | tr -d ' '; }
# rf_run ADAPTER OUTDIR WORKROOT SCENARIOS [env VAR=..]... -> runs the runner with a stand-in real home and a private TMPDIR ($RF_TD)
rf_run() {
  local ad="$1" od="$2" wr="$3" sc="$4"; shift 4
  IH="$(mk_ih)"; RF_TD="$(mk_tmp)"
  run env -u PLAYBOOK_HOME HOME="$IH" TMPDIR="$RF_TD" "$@" bash "$RUNNER" --cmd "bash $A/$ad.sh" --scenarios "$sc" --workroot "$wr" --out "$od/results.md"
}
alive() { local s; s="$(ps -o stat= -p "$1" 2>/dev/null | tr -d ' ')"; [ -n "$s" ] && [ "${s#Z}" = "$s" ]; }

# the F1 cases need real symlinks; Git Bash without symlink rights makes a copy for ln -s, so skip them there
F1D="$(mk_tmp)"; : > "$F1D/t"; ln -s t "$F1D/l" 2>/dev/null
if [ -L "$F1D/l" ]; then
echo "v0.24.3 F1a a cost.tsv that is a link to a file outside is not copied as evidence"
SEC="$(mk_tmp)"; printf 'OUTSIDE-SECRET-F1A\n' > "$SEC/secret.tsv"
mk_adapter f1a 'mkdir -p .agents/handoff; rm -f .agents/handoff/cost.tsv; ln -s "'"$SEC"'/secret.tsv" .agents/handoff/cost.tsv; true'
OD="$(mk_tmp)"; W="$(mk_tmp)"; rm -f "$REC/E1.args"
rf_run f1a "$OD" "$W" E1
assert_file "F1a the adapter ran" "$REC/E1.args"
assert_eq "F1a the outside secret is not in the evidence" "0" "$(leaks "$OD" OUTSIDE-SECRET-F1A)"
assert_eq "F1a no cost.tsv was copied from the link" "0" "$(nnamed "$OD" cost.tsv)"
assert_eq "F1a the evidence holds no symlink" "0" "$(nlinks "$OD")"

echo "v0.24.3 F1b a playbook-feedback dir replaced by a link to an outside dir is not copied"
SEC="$(mk_tmp)"; mkdir -p "$SEC/sub"; printf 'OUTSIDE-SECRET-F1B\n' > "$SEC/leak.md"; printf 'OUTSIDE-SECRET-F1B\n' > "$SEC/sub/deep.md"
mk_adapter f1b 'rm -rf "$PLAYBOOK_HOME/.agents/playbook-feedback"; ln -s "'"$SEC"'" "$PLAYBOOK_HOME/.agents/playbook-feedback"; true'
OD="$(mk_tmp)"; W="$(mk_tmp)"; rm -f "$REC/E1.args"
rf_run f1b "$OD" "$W" E1
assert_file "F1b the adapter ran" "$REC/E1.args"
assert_eq "F1b the evidence holds no symlink" "0" "$(nlinks "$OD")"
assert_eq "F1b nothing of the outside dir is in the evidence" "0" "$(leaks "$OD" OUTSIDE-SECRET-F1B)"
assert_eq "F1b no leak.md or deep.md in the evidence" "0" "$(( $(nnamed "$OD" leak.md) + $(nnamed "$OD" deep.md) ))"

echo "v0.24.3 F1c a link inside the feedback tree is not copied; the regular items still are"
SEC="$(mk_tmp)"; printf 'OUTSIDE-SECRET-F1C\n' > "$SEC/secret.md"; printf 'OUTSIDE-SECRET-F1C\n' > "$SEC/dirfile.md"
mk_adapter f1c "$(RF_FB 'F1C-FB-$e')"'
FB="$PLAYBOOK_HOME/.agents/playbook-feedback"
ln -s "'"$SEC"'/secret.md" "$FB/pending/zz-link.md"
ln -s "'"$SEC"'" "$FB/linkdir"
true'
OD="$(mk_tmp)"; W="$(mk_tmp)"; rm -f "$REC/E1.args"
rf_run f1c "$OD" "$W" E1
assert_file "F1c the adapter ran" "$REC/E1.args"
assert_eq "F1c the evidence holds no symlink" "0" "$(nlinks "$OD")"
assert_eq "F1c the outside content is not in the evidence" "0" "$(leaks "$OD" OUTSIDE-SECRET-F1C)"
assert_eq "F1c the regular feedback item is still copied" "1" "$(leaks "$OD" F1C-FB-E1 | awk '{print ($1>=1) ? 1 : 0}')"

echo "v0.24.3 F1d .agents or .agents/handoff in the workdir being a link: nothing is copied from its target"
SEC="$(mk_tmp)"; mkdir -p "$SEC/handoff"; printf 'OUTSIDE-SECRET-F1D\n' > "$SEC/handoff/cost.tsv"
mk_adapter f1d1 'rm -rf .agents; ln -s "'"$SEC"'" .agents; true'
OD="$(mk_tmp)"; W="$(mk_tmp)"; rm -f "$REC/E1.args"
rf_run f1d1 "$OD" "$W" E1
assert_file "F1d .agents link: the adapter ran" "$REC/E1.args"
assert_eq "F1d .agents link: the outside content is not in the evidence" "0" "$(leaks "$OD" OUTSIDE-SECRET-F1D)"
assert_eq "F1d .agents link: no cost.tsv in the evidence" "0" "$(nnamed "$OD" cost.tsv)"
assert_eq "F1d .agents link: no symlink in the evidence" "0" "$(nlinks "$OD")"
SEC="$(mk_tmp)"; printf 'OUTSIDE-SECRET-F1D2\n' > "$SEC/cost.tsv"
mk_adapter f1d2 'mkdir -p .agents; rm -rf .agents/handoff; ln -s "'"$SEC"'" .agents/handoff; true'
OD="$(mk_tmp)"; W="$(mk_tmp)"; rm -f "$REC/E1.args"
rf_run f1d2 "$OD" "$W" E1
assert_file "F1d handoff link: the adapter ran" "$REC/E1.args"
assert_eq "F1d handoff link: the outside content is not in the evidence" "0" "$(leaks "$OD" OUTSIDE-SECRET-F1D2)"
assert_eq "F1d handoff link: no cost.tsv in the evidence" "0" "$(nnamed "$OD" cost.tsv)"
assert_eq "F1d handoff link: no symlink in the evidence" "0" "$(nlinks "$OD")"
else t_skip 20 "v0.24.3 F1 symlink cases (ln -s makes a copy on this file system)"; fi

echo "v0.24.3 F2 the evidence is per run: --out D/run-A.md and D/run-B.md keep separate E1 folders"
mk_adapter f2 "$(RF_FB 'F2-FB-$RUNTAG-$e')"'
bash "'"$PB_ROOT"'/scripts/cost.sh" add --role tester --tokens 5 --note "F2-COST-$RUNTAG-$e" >/dev/null'
OD="$(mk_tmp)"; W="$(mk_tmp)"
for t in A B; do
  IH="$(mk_ih)"; RF_TD="$(mk_tmp)"
  run env -u PLAYBOOK_HOME HOME="$IH" TMPDIR="$RF_TD" RUNTAG="$t" bash "$RUNNER" --cmd "bash $A/f2.sh" --scenarios E1 --workroot "$W" --out "$OD/run-$t.md"
done
assert_dir "F2 run A keeps D/run-A.E1.evidence" "$OD/run-A.E1.evidence"
assert_dir "F2 run B keeps D/run-B.E1.evidence" "$OD/run-B.E1.evidence"
assert_eq "F2 run A evidence holds run A feedback" "1" "$(leaks "$OD/run-A.E1.evidence" F2-FB-A-E1 | awk '{print ($1>=1) ? 1 : 0}')"
assert_eq "F2 run B evidence holds run B feedback" "1" "$(leaks "$OD/run-B.E1.evidence" F2-FB-B-E1 | awk '{print ($1>=1) ? 1 : 0}')"
assert_eq "F2 run A evidence has no run B feedback" "0" "$(leaks "$OD/run-A.E1.evidence" F2-FB-B)"
assert_eq "F2 run B evidence has no run A feedback" "0" "$(leaks "$OD/run-B.E1.evidence" F2-FB-A)"
assert_eq "F2 run A cost log is the run A one" "1" "$(leaks "$OD/run-A.E1.evidence/cost.tsv" F2-COST-A-E1)"
assert_eq "F2 run B cost log is the run B one" "1" "$(leaks "$OD/run-B.E1.evidence/cost.tsv" F2-COST-B-E1)"
assert_no_path "F2 no per-scenario D/E1.evidence (the old layout) is made" "$OD/E1.evidence"

echo "v0.24.3 F3a a runner that dies on a failed evidence copy leaves no temp home"
OD="$(mk_tmp)"; W="$(mk_tmp)"; rm -f "$REC/f3a.ph"
mk_adapter f3a 'printf "%s\n" "$PLAYBOOK_HOME" > "'"$REC"'/f3a.ph"
'"$(RF_FB 'F3A-FB-$e')"'
chmod 555 "'"$OD"'"
true'
rf_run f3a "$OD" "$W" E1
chmod 755 "$OD"
if [ -s "$REC/f3a.ph" ]; then t_ok "F3a the adapter ran"; else t_bad "F3a the adapter ran" "no record of the adapter"; fi
if [ "$RC" -ne 0 ]; then t_ok "F3a the runner exits non-zero when the evidence cannot be kept"; else t_bad "F3a the runner exits non-zero when the evidence cannot be kept" "rc=$RC"; fi
gone_home "F3a the temp home is gone" "$REC/f3a.ph"
assert_eq "F3a no pb-evhome.* is left in TMPDIR" "0" "$(find "$RF_TD" -maxdepth 1 -name 'pb-evhome.*' 2>/dev/null | wc -l | tr -d ' ')"

echo "v0.24.3 F3b a runner killed with SIGTERM while the adapter sleeps leaves no temp home"
OD="$(mk_tmp)"; W="$(mk_tmp)"; rm -f "$REC/f3b.mark" "$REC/f3b.mark.tmp" "$REC/f3b.ph"
mk_adapter f3b 'printf "%s\n" "$PLAYBOOK_HOME" > "'"$REC"'/f3b.ph"; printf "%s\n" "$$" > "'"$REC"'/f3b.mark.tmp"; mv "'"$REC"'/f3b.mark.tmp" "'"$REC"'/f3b.mark"; exec sleep 30'
IH="$(mk_ih)"; RF_TD="$(mk_tmp)"
env -u PLAYBOOK_HOME HOME="$IH" TMPDIR="$RF_TD" bash "$RUNNER" --cmd "bash $A/f3b.sh" --scenarios E1 --workroot "$W" --out "$OD/results.md" >/dev/null 2>&1 &
RP=$!
for _ in $(seq 1 100); do [ -f "$REC/f3b.mark" ] && break; sleep 0.1; done
if [ -f "$REC/f3b.mark" ]; then
  t_ok "F3b the adapter started"
  kill -TERM "$RP" 2>/dev/null
  for _ in $(seq 1 50); do alive "$RP" || break; sleep 0.1; done
  # a runner that only reacts after its foreground child ended is released by ending the sleeping adapter
  kill "$(sed -n 1p "$REC/f3b.mark")" 2>/dev/null
  for _ in $(seq 1 30); do alive "$RP" || break; sleep 0.1; done
  kill -KILL "$RP" 2>/dev/null; wait "$RP" 2>/dev/null
  gone_home "F3b the temp home is gone after SIGTERM" "$REC/f3b.ph"
  assert_eq "F3b no pb-evhome.* is left in TMPDIR" "0" "$(find "$RF_TD" -maxdepth 1 -name 'pb-evhome.*' 2>/dev/null | wc -l | tr -d ' ')"
else
  t_bad "F3b the adapter started" "no marker after 10 s"
  kill -KILL "$RP" 2>/dev/null; wait "$RP" 2>/dev/null
fi

echo "v0.24.3 F4 E20 and --real-home make no evidence folder; default-mode E1 still makes one"
mk_adapter f4 "$(RF_FB 'F4-FB-$e')"
OD="$(mk_tmp)"; W="$(mk_tmp)"
IH="$(mk_ih)"; RF_TD="$(mk_tmp)"
run env -u PLAYBOOK_HOME HOME="$IH" TMPDIR="$RF_TD" bash "$RUNNER" --real-home --cmd "bash $A/f4.sh" --scenarios E20 --workroot "$W" --out "$OD/results.md"
assert_eq "F4 the adapter ran (feedback in E20's own home)" "1" "$(ls "$W"/E20.home/.agents/playbook-feedback/pending/*.md 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "F4 --real-home E20: no *.E20.evidence" "0" "$(find "$OD" -maxdepth 1 -name '*E20*evidence*' | wc -l | tr -d ' ')"
OD="$(mk_tmp)"; W="$(mk_tmp)"
IH="$(mk_ih)"; RF_TD="$(mk_tmp)"
run env -u PLAYBOOK_HOME HOME="$IH" TMPDIR="$RF_TD" bash "$RUNNER" --cmd "bash $A/f4.sh" --scenarios E1,E20 --workroot "$W" --out "$OD/results.md"
assert_eq "F4 default mode: E20 adapter wrote into E20.home" "1" "$(ls "$W"/E20.home/.agents/playbook-feedback/pending/*.md 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "F4 default mode: no *.E20.evidence" "0" "$(find "$OD" -maxdepth 1 -name '*E20*evidence*' | wc -l | tr -d ' ')"
assert_dir "F4 default mode: E1 still gets D/results.E1.evidence" "$OD/results.E1.evidence"
assert_eq "F4 default mode: the E1 evidence holds the E1 feedback" "1" "$(leaks "$OD/results.E1.evidence" F4-FB-E1 | awk '{print ($1>=1) ? 1 : 0}')"

echo "v0.24.3 F5 an adapter that does not cd writes its cost log in the scenario workdir, which is kept as evidence"
cat > "$A/f5.sh" <<EOF
#!/usr/bin/env bash
pwd -P > "$REC/f5.cwd"
bash "$PB_ROOT/scripts/cost.sh" add --role tester --tokens 5 --note "F5-COST-MARK" >/dev/null
exit 0
EOF
OD="$(mk_tmp)"; W="$(mk_tmp)"; CW="$(mk_tmp)"; rm -f "$REC/f5.cwd"
IH="$(mk_ih)"; RF_TD="$(mk_tmp)"
run_in "$CW" env -u PLAYBOOK_HOME HOME="$IH" TMPDIR="$RF_TD" bash "$RUNNER" --cmd "bash $A/f5.sh" --scenarios E1 --workroot "$W" --out "$OD/results.md"
assert_eq "F5 the adapter started in the scenario workdir" "$(physdir "$W")/E1" "$(cat "$REC/f5.cwd" 2>/dev/null)"
assert_eq "F5 the cost log is in the workdir" "1" "$(leaks "$W/E1/.agents/handoff/cost.tsv" F5-COST-MARK)"
assert_eq "F5 the cost log is in the evidence" "1" "$(leaks "$OD/results.E1.evidence/cost.tsv" F5-COST-MARK)"
assert_no_path "F5 nothing was written under the caller's cwd" "$CW/.agents"

echo "v0.24.3 F6 --help tells a custom --cmd to use an absolute path"
run bash "$RUNNER" --help
if printf '%s' "$OUT" | tr '\n' ' ' | grep -qiE '(--cmd|adapter|COMMAND).{0,200}absolute path|absolute path.{0,200}(--cmd|adapter|COMMAND)'; then t_ok "F6 the usage text says a custom --cmd should use an absolute path"; else t_bad "F6 the usage text says a custom --cmd should use an absolute path" "no 'absolute path' near --cmd/adapter in: $OUT"; fi

# ---- v0.24.7 (lane T): every scenario gets its own TMPDIR; the agent's leftovers in it are reported and removed ----
# tt_run ADAPTER [runner option]... -> runs E1 with a private outer TMPDIR ($RF_TD) and a stand-in real home; sets OD, W, OUT, RC
tt_run() {
  local ad="$1"; shift
  OD="$(mk_tmp)"; W="$(mk_tmp)"; IH="$(mk_ih)"; RF_TD="$(mk_tmp)"
  run env -u PLAYBOOK_HOME HOME="$IH" TMPDIR="$RF_TD" bash "$RUNNER" --cmd "bash $A/$ad.sh" "$@" --scenarios E1 --workroot "$W" --out "$OD/results.md"
}

echo "v0.24.7 T1 the adapter gets a fresh TMPDIR (pb-evtmp.*) inside the runner's TMPDIR"
mk_adapter t1 'printf "%s\n" "$TMPDIR" > "'"$REC"'/t1.tmpdir"
if [ -d "$TMPDIR" ]; then echo yes > "'"$REC"'/t1.exists"; fi
true'
rm -f "$REC/t1.tmpdir" "$REC/t1.exists"
tt_run t1
T1D="$(cat "$REC/t1.tmpdir" 2>/dev/null)"
if [ -n "$T1D" ] && [ "$T1D" != "$RF_TD" ]; then t_ok "T1 the adapter's TMPDIR differs from the runner's"; else t_bad "T1 the adapter's TMPDIR differs from the runner's" "adapter [$T1D] runner [$RF_TD]"; fi
assert_eq "T1 it lies directly under the runner's TMPDIR" "$RF_TD" "$(dirname "$T1D")"
case "$(basename "$T1D")" in pb-evtmp.*) t_ok "T1 it is named pb-evtmp.*" ;; *) t_bad "T1 it is named pb-evtmp.*" "name [$(basename "$T1D")]" ;; esac
assert_eq "T1 it existed while the adapter ran" "yes" "$(cat "$REC/t1.exists" 2>/dev/null)"
assert_no_path "T1 it is gone after the run" "$T1D"
assert_eq "T1 an adapter that leaves nothing gets no NOTE line" "0" "$(printf '%s\n' "$OUT" | grep -c '^E1 NOTE ')"

echo "v0.24.7 T2 an adapter that runs mktemp -d twice and leaves the dirs: reported, removed, outer TMPDIR clean"
mk_adapter t2 'printf "%s\n" "$TMPDIR" > "'"$REC"'/t2.tmpdir"
mktemp -d >/dev/null
mktemp -d >/dev/null
true'
rm -f "$REC/t2.tmpdir"
tt_run t2
T2D="$(cat "$REC/t2.tmpdir" 2>/dev/null)"
assert_eq "T2 the outer TMPDIR has no new tmp.* entry" "0" "$(find "$RF_TD" -maxdepth 1 -name 'tmp.*' | wc -l | tr -d ' ')"
assert_eq "T2 the outer TMPDIR has no pb-evtmp.* left" "0" "$(find "$RF_TD" -maxdepth 1 -name 'pb-evtmp.*' | wc -l | tr -d ' ')"
if [ -n "$T2D" ]; then assert_no_path "T2 the scenario TMPDIR is gone" "$T2D"; else t_bad "T2 the scenario TMPDIR is gone" "no TMPDIR recorded"; fi
if printf '%s\n' "$OUT" | grep '^E1 NOTE ' | grep -q '2 entries'; then t_ok "T2 a NOTE line names the 2 leftovers"; else t_bad "T2 a NOTE line names the 2 leftovers" "output: $OUT"; fi
if printf '%s\n' "$OUT" | grep '^E1 NOTE ' | grep -q 'tmp\.'; then t_ok "T2 the NOTE line names the leftover entries"; else t_bad "T2 the NOTE line names the leftover entries" "output: $OUT"; fi
assert_eq "T2 the leftovers are no FAIL line" "0" "$(printf '%s\n' "$OUT" | grep '^E1 FAIL ' | grep -c 'NOTE\|TMPDIR')"
assert_contains "T2 the results file carries the NOTE" "$(cat "$OD/results.md" 2>/dev/null)" "2 entries"

echo "v0.24.7 T3 a link left in the scenario TMPDIR is removed, its target is not touched"
if [ -L "$F1D/l" ]; then
SEC="$(mk_tmp)"; printf 'OUTSIDE-SECRET-T3\n' > "$SEC/secret.txt"
mk_adapter t3 'ln -s "'"$SEC"'" "$TMPDIR/lnk"; mkdir "$TMPDIR/d"; ln -s "'"$SEC"'" "$TMPDIR/d/inner"; true'
tt_run t3
assert_eq "T3 the link target is untouched" "OUTSIDE-SECRET-T3" "$(cat "$SEC/secret.txt" 2>/dev/null)"
assert_eq "T3 nothing of the scenario TMPDIR is left" "0" "$(find "$RF_TD" -maxdepth 1 -name 'pb-evtmp.*' | wc -l | tr -d ' ')"
else t_skip 2 "v0.24.7 T3 link case (ln -s makes a copy on this file system)"; fi

echo "v0.24.7 T4 a runner killed with SIGTERM while the adapter sleeps leaves no scenario TMPDIR"
mk_adapter t4 'printf "%s\n" "$TMPDIR" > "'"$REC"'/t4.tmpdir"; mktemp -d >/dev/null; printf "%s\n" "$$" > "'"$REC"'/t4.mark.tmp"; mv "'"$REC"'/t4.mark.tmp" "'"$REC"'/t4.mark"; exec sleep 30'
OD="$(mk_tmp)"; W="$(mk_tmp)"; rm -f "$REC/t4.mark" "$REC/t4.mark.tmp" "$REC/t4.tmpdir"
IH="$(mk_ih)"; RF_TD="$(mk_tmp)"
env -u PLAYBOOK_HOME HOME="$IH" TMPDIR="$RF_TD" bash "$RUNNER" --cmd "bash $A/t4.sh" --scenarios E1 --workroot "$W" --out "$OD/results.md" >/dev/null 2>&1 &
RP=$!
for _ in $(seq 1 100); do [ -f "$REC/t4.mark" ] && break; sleep 0.1; done
if [ -f "$REC/t4.mark" ]; then
  t_ok "T4 the adapter started"
  kill -TERM "$RP" 2>/dev/null
  for _ in $(seq 1 50); do alive "$RP" || break; sleep 0.1; done
  kill "$(sed -n 1p "$REC/t4.mark")" 2>/dev/null
  for _ in $(seq 1 30); do alive "$RP" || break; sleep 0.1; done
  kill -KILL "$RP" 2>/dev/null; wait "$RP" 2>/dev/null
  T4D="$(cat "$REC/t4.tmpdir" 2>/dev/null)"
  if [ "$T4D" != "$RF_TD" ] && [ -n "$T4D" ]; then assert_no_path "T4 the scenario TMPDIR is gone after SIGTERM" "$T4D"; else t_bad "T4 the scenario TMPDIR is gone after SIGTERM" "adapter TMPDIR [$T4D] is the runner's [$RF_TD] or empty"; fi
  assert_eq "T4 no pb-evtmp.* and no tmp.* is left in the outer TMPDIR" "0" "$(find "$RF_TD" -maxdepth 1 \( -name 'pb-evtmp.*' -o -name 'tmp.*' \) | wc -l | tr -d ' ')"
else
  t_bad "T4 the adapter started" "no marker after 10 s"
  kill -KILL "$RP" 2>/dev/null; wait "$RP" 2>/dev/null
fi

echo "v0.24.7 T5 --real-home keeps the caller's TMPDIR (no isolation, as documented)"
rm -f "$REC/t1.tmpdir"
tt_run t1 --real-home
assert_eq "T5 --real-home: the adapter sees the caller's TMPDIR" "$RF_TD" "$(cat "$REC/t1.tmpdir" 2>/dev/null)"

echo "v0.24.7 T6 odd leftover names: control characters never reach the output, the count is by entry, names sit in backticks"
ESC="$(printf '\033')"; CR="$(printf '\r')"
PROBE="$(mk_tmp)"
if touch "$PROBE/$(printf 'a\nb')" "$PROBE/$(printf 'c\033d')" 2>/dev/null && [ "$(find "$PROBE" -mindepth 1 | wc -l | tr -d ' ')" -ge 3 ]; then
mk_adapter t6 'cd "$TMPDIR" || exit 1
touch "$(printf "esc\033[31mRED")"
touch "$(printf "cr\rE1 PASS forged")"
touch "<img src=x onerror=alert(1)>"
touch "$(printf "nl\nline2")"
touch "a\`b"
true'
tt_run t6
T6R="$(cat "$OD/results.md" 2>/dev/null)"
case "$OUT" in *"$ESC"*) t_bad "T6 no raw ESC on stdout" "found ESC" ;; *) t_ok "T6 no raw ESC on stdout" ;; esac
case "$T6R" in *"$ESC"*) t_bad "T6 no raw ESC in the results file" "found ESC" ;; *) t_ok "T6 no raw ESC in the results file" ;; esac
case "$OUT" in *"$CR"*) t_bad "T6 no raw CR on stdout" "found CR" ;; *) t_ok "T6 no raw CR on stdout" ;; esac
case "$T6R" in *"$CR"*) t_bad "T6 no raw CR in the results file" "found CR" ;; *) t_ok "T6 no raw CR in the results file" ;; esac
assert_eq "T6 a name that tries to forge a result line starts no line on stdout" "0" "$(printf '%s\n' "$OUT" | grep -c '^E1 PASS forged')"
assert_eq "T6 the forged text starts no line in the results file" "0" "$(printf '%s\n' "$T6R" | grep -c '^E1 PASS forged')"
assert_eq "T6 the NOTE counts 5 entries (a name with a newline is one entry)" "1" "$(printf '%s\n' "$OUT" | grep -c '^E1 NOTE the agent left 5 entries ')"
assert_eq "T6 the NOTE is one line on stdout" "1" "$(printf '%s\n' "$OUT" | grep -c '^E1 NOTE ')"
assert_contains "T6 a markup name is shown in backticks" "$T6R" '`<img src=x onerror=alert(1)>`'
assert_contains "T6 a backtick inside a name is replaced" "$T6R" "\`a'b\`"
assert_contains "T6 the results file counts 5 entries" "$T6R" "5 entries"
else t_skip 11 "v0.24.7 T6 odd names (this file system cannot hold names with a newline or ESC)"; fi

echo "v0.24.7 T7 a leftover chmod 000 dir does not stop the removal of the scenario TMPDIR"
mk_adapter t7 'printf "%s\n" "$TMPDIR" > "'"$REC"'/t7.tmpdir"
mkdir "$TMPDIR/locked" && : > "$TMPDIR/locked/f" && chmod 000 "$TMPDIR/locked"
true'
rm -f "$REC/t7.tmpdir"
tt_run t7
T7D="$(cat "$REC/t7.tmpdir" 2>/dev/null)"
T7LEFT="$(find "$RF_TD" -maxdepth 1 -name 'pb-evtmp.*' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$T7LEFT" = 0 ] || printf '%s\n' "$OUT" | grep '^E1 NOTE ' | grep -qF "$T7D"; then t_ok "T7 no pb-evtmp.* left, or a NOTE names it"; else t_bad "T7 no pb-evtmp.* left, or a NOTE names it" "left $T7LEFT, dir [$T7D], output: $OUT"; fi
assert_eq "T7 the chmod 000 dir is removed (no pb-evtmp.* in the outer TMPDIR)" "0" "$T7LEFT"
assert_eq "T7 a leftover dir is no ERROR" "0" "$(printf '%s\n' "$OUT" | grep -c '^E1 ERROR')"
find "$RF_TD" -maxdepth 2 -type d -exec chmod u+rwx {} + 2>/dev/null

echo "v0.24.7 T8 a scenario TMPDIR that cannot be removed at all: a NOTE names the path, the scenario does not fail"
T8PROBE="$(mktemp -d "${TMPDIR:-/tmp}/t8probe.XXXXXX")"; mkdir "$T8PROBE/child"; chmod 555 "$T8PROBE"; rm -rf "$T8PROBE/child" 2>/dev/null; chmod 755 "$T8PROBE"
T8BLOCKS=1; [ -d "$T8PROBE/child" ] || T8BLOCKS=0   # 0: chmod does not block removal here (root, NTFS)
rm -rf "$T8PROBE"
if [ "$(id -u)" != 0 ] && [ "$T8BLOCKS" = 1 ]; then
mk_adapter t8 'printf "%s\n" "$TMPDIR" > "'"$REC"'/t8.tmpdir"
chmod 555 "$(dirname "$TMPDIR")"
true'
rm -f "$REC/t8.tmpdir"
tt_run t8
chmod 755 "$RF_TD" 2>/dev/null
T8D="$(cat "$REC/t8.tmpdir" 2>/dev/null)"
if [ -n "$T8D" ] && printf '%s\n' "$OUT" | grep '^E1 NOTE ' | grep -qF "$T8D"; then t_ok "T8 a NOTE names the path that could not be removed"; else t_bad "T8 a NOTE names the path that could not be removed" "dir [$T8D], output: $OUT"; fi
assert_eq "T8 it is no ERROR" "0" "$(printf '%s\n' "$OUT" | grep -c '^E1 ERROR')"
else t_skip 2 "v0.24.7 T8 (chmod 555 on a parent does not stop the removal here: root or NTFS)"; fi

t_summary
