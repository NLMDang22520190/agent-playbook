#!/usr/bin/env bash
# Tests for evals/run-evals.sh (behaviour-eval runner): options, workroot safety, harness errors, auth markers,
# --clean-env, and evals/make-fixture.sh <dir>. The graders are in test-evals-grade.sh and test-evals-grade2.sh.
# Never calls a real harness: every run uses --cmd with fake adapters (see evals-fixture.sh).
# Split in v0.24.19 so that it is not the floor of a CI shard: this is the first half, up to the v0.15.0 AC2.1 api_retry section; the rest is in test-evals-runner-b.sh.
# Shared setup: evals-fixture.sh, evals-runner-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-runner-fixture.sh"
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
rm -f "$REC/E7.args"
run bash "$RUNNER" --cmd "bash $A/good.sh" --scenarios E7 --workroot "$W7" --out "$W7/results.md"
assert_rc "AC5 unknown scenario E7 exits 2" 2
assert_contains "AC5 E7 reported as not auto-gradable" "$OUT" "not auto-gradable"
assert_no_path "AC5 adapter not called for E7" "$REC/E7.args"
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
run bash "$RUNNER" --cmd "bash $A/idle.sh" --scenarios E9 --workroot "$W" --out "$W/results.md"
assert_rc "AC3.x E9 (not auto-gradable) is still refused (exit 2)" 2
assert_contains "AC3.x the refusal lists the full auto-gradable list (v0.26.0 lane N S2-S4: E2, E6, E13 added)" "$OUT" "(auto-gradable: E1,E2,E3,E4,E5,E6,E8,E10,E11,E13,E15,E16,E17,E19,E20,E21,E22,E23,E24,E25,E26,E27,E28,E29,E30,E31)"
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
run bash "$RUNNER" --cmd "bash $A/idle.sh" --scenarios E9 --workroot "$W" --out "$W/results.md"
assert_contains "AC5.1 the refusal lists E20 among the auto-gradable scenarios" "$OUT" "E20"
W="$(mk_tmp)"
run bash "$RUNNER" --cmd "bash $A/idle.sh" --workroot "$W" --out "$W/results.md"
assert_eq "AC5.1 the default scenarios stay E1,E3,E8,E15 (no E20 line)" "0" "$(printf '%s\n' "$OUT" | grep -c '^E20 ')"

# ---- v0.15.0 AC2.1: a transient api_retry line is not a harness error ----
echo "v0.15.0 AC2.1 api_retry 401 followed by a normal result is not a harness error"
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

t_summary
