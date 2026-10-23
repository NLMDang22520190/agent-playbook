#!/usr/bin/env bash
# Tests for scripts/tdd-step.sh --scope FILE (v0.24.29 lane C, slice S3; .agents/handoff/01-spec.md AC10, AC11, AC14; the exact strings E10-E18 are used verbatim):
#   A  AC10  --commit commits ONLY the changed own paths (a foreign untracked path, a foreign tracked edit and a foreign STAGED edit stay as they were); with --baseline too
#   B  AC10  without --commit the printed commands name only the own paths; no own path to commit gives E11 (also with --baseline)
#   C  AC14  a rule-4 path that passed the gate (unknown, allowed kind): E16 on stderr in both modes, E17 on stdout after the printed commands (print mode only), never committed
#   D  AC11  --scope reaches BOTH gate runs; a not-own path changing while CMD runs: E13, then the second gate judges it; the notes comparison covers own paths only
#   E  AC11  an own path changed while CMD runs, or HEAD moved: E12 refusal
#   F  AC14  E14 (--scope without --base), E10 (usage lines, twice, no value), E15 (scope file digest), E18 (baseline manifest digest, E15 first)
#   G  AC14  the control-character refusal also applies on the --scope path, without --baseline
#   H  a scope file path relative to the caller's directory is resolved before the step enters the project root
# The step is run with stdout and stderr captured separately (E11-E16 go to stderr, E17 to stdout). Shared setup: tdd-step-fixture.sh. ASCII paths (E17 uses the shell's own printf %q).
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/tdd-step-fixture.sh"
T="$(printf '\t')"
TD="$(mk_tmp)"

dig() { git hash-object -- "$1" 2>/dev/null || printf 'NODIGEST'; }
# sf FILE KIND:PATH...: a valid scope file (header, then one "kind TAB path" line per argument; the path is everything after the first colon)
sf() { local f="$1" e; shift; { printf '# role-gate scope v1\n'; for e in "$@"; do printf '%s\t%s\n' "${e%%:*}" "${e#*:}"; done; } > "$f"; }
# new_s: a fresh repo R (src/app.js, tests/app.test.js, README.md), BASE (the sha before the role), SF (a scope file outside the repo), no baseline
new_s() { R="$(fresh)"; BASE="$(head_of "$R")"; SF="$(mk_tmp)/scope"; BL=""; N0="$(count_of "$R")"; H0="$BASE"; }
# stp ARGS...: run tdd-step in SD (default R); sets RC, SO (stdout), SE (stderr), OUT (both)
stp() {
  ( cd "${SD:-$R}" && bash "$STEP" "$@" ) > "$TD/so" 2> "$TD/se"; RC=$?
  SO="$(cat "$TD/so")"; SE="$(cat "$TD/se")"; OUT="$SO
$SE"
}
# red / green: the step with --base BASE --scope SF (and --baseline BL when BL is set), --message m, then the flag and the command
red()   { local fl="$1"; shift; stp red   --base "$BASE" --scope "$SF" ${BL:+--baseline "$BL"} --message m $fl -- "$@"; }
green() { local fl="$1"; shift; stp green --base "$BASE" --scope "$SF" ${BL:+--baseline "$BL"} --message m $fl -- "$@"; }
# has_err NAME LINE / no_err NAME LINE: stderr has / has not exactly this line; has_out / no_out: the same for stdout
has_err() { if printf '%s\n' "$SE" | grep -Fx -- "$2" >/dev/null 2>&1; then t_ok "$1"; else t_bad "$1" "no stderr line [$2]; stderr: $SE"; fi; }
no_err()  { if printf '%s\n' "$SE" | grep -Fx -- "$2" >/dev/null 2>&1; then t_bad "$1" "unexpected stderr line [$2]"; else t_ok "$1"; fi; }
has_out() { if printf '%s\n' "$SO" | grep -Fx -- "$2" >/dev/null 2>&1; then t_ok "$1"; else t_bad "$1" "no stdout line [$2]; stdout: $SO"; fi; }
no_out()  { if printf '%s\n' "$SO" | grep -Fx -- "$2" >/dev/null 2>&1; then t_bad "$1" "unexpected stdout line [$2]"; else t_ok "$1"; fi; }
# lno TEXT LINE: the first line number of exactly this line in TEXT (0 when absent)
lno() { printf '%s\n' "$1" | WANT="$2" awk 'BEGIN { want = ENVIRON["WANT"] } $0 == want { print NR; found = 1; exit } END { if (!found) print 0 }'; }
untouched() { assert_untouched "$1" "$R" "$H0" "$N0"; }
status_of() { git -C "$R" status --porcelain --untracked-files=all -- "$1"; }
E11="error: nothing of the role's to commit (no changed path in the task scope)"
E12W="error: the test command changed the work tree (a file was written, edited or committed) - nothing committed"
E12H="error: HEAD moved while the test command ran - nothing committed"
e13() { printf 'note: outside the task scope, changed while the test command ran: %s' "$1"; }
e16() { printf 'note: outside the task scope, not committed: %s' "$1"; }
e17() { printf '# not in the task scope, not included above: %q' "$1"; }
E14="--scope needs --base REF (the sha recorded before the role)"
MINE="$(printf 'test("m", () => {});\n')"

# ================= A  AC10  commit only the own paths =================
echo "A AC10 red --commit with a scope: only the changed own path is committed; a foreign untracked path, a foreign tracked edit and a foreign STAGED edit stay as they were"
new_s
sf "$SF" own:tests/mine.test.js other:tests/other.test.js other:README.md other:src/app.js
printf '%s\n' "$MINE" > "$R/tests/mine.test.js"
printf 'test("o", () => {});\n' > "$R/tests/other.test.js"
printf 'foreign staged\n' >> "$R/README.md"; git -C "$R" add README.md
printf 'module.exports = 5;\n' > "$R/src/app.js"
red --commit sh -c 'exit 1'
assert_rc "A red --commit with a scope: exit 0 (the first gate got --scope: foreign code paths are not a tester violation)" 0
assert_contains "A red --commit with a scope: prints RED=" "$OUT" "RED="
assert_eq "A the commit holds only the own path" "tests/mine.test.js" "$(committed "$R")"
assert_eq "A one commit was added" "$((N0 + 1))" "$(count_of "$R")"
assert_eq "A the foreign untracked test stays untracked" "?? tests/other.test.js" "$(status_of tests/other.test.js)"
assert_eq "A the foreign STAGED edit stays staged and is not committed" "M  README.md" "$(status_of README.md)"
assert_eq "A the foreign unstaged edit stays unstaged and is not committed" " M src/app.js" "$(status_of src/app.js)"
assert_eq "A the foreign edit is intact" "module.exports = 5;" "$(cat "$R/src/app.js")"

echo "A AC10 green --commit with a scope: a tracked own path is committed alone; the foreign test edit stays in the work tree"
new_s
sf "$SF" own:src/ other:tests/app.test.js
printf 'module.exports = 2;\n' > "$R/src/app.js"; printf 'n\n' > "$R/src/new.js"
printf 'test("y", () => {});\n' > "$R/tests/app.test.js"
green --commit true
assert_rc "A green --commit with a scope: exit 0 (a foreign test edit is not an implementer violation)" 0
assert_contains "A green --commit with a scope: prints committed:" "$OUT" "committed:"
assert_eq "A green: the commit holds the own paths only" "src/app.js
src/new.js" "$(committed "$R")"
assert_eq "A green: the foreign test edit is still unstaged" " M tests/app.test.js" "$(status_of tests/app.test.js)"

echo "A AC10 --baseline with a scope: only the changed own path is committed; the baseline paths keep their state"
new_s
dirty "$R"; BL="$(snap "$R")"
sf "$SF" own:tests/mine.test.js other:tests/other.test.js
printf '%s\n' "$MINE" > "$R/tests/mine.test.js"; printf 'test("o", () => {});\n' > "$R/tests/other.test.js"
BS0="$(bstate "$R")"
red --commit sh -c 'exit 1'
assert_rc "A baseline: exit 0" 0
assert_eq "A baseline: only the own path is committed" "tests/mine.test.js" "$(committed "$R")"
assert_eq "A baseline: the baseline paths are untouched" "$BS0" "$(bstate "$R")"
assert_eq "A baseline: the foreign test stays untracked" "?? tests/other.test.js" "$(status_of tests/other.test.js)"

# ================= B  AC10  print mode, E11 =================
echo "B AC10 without --commit the printed commands name only the own path (the foreign paths are not in them)"
new_s
sf "$SF" own:tests/mine.test.js other:tests/other.test.js other:README.md
printf '%s\n' "$MINE" > "$R/tests/mine.test.js"; printf 'test("o", () => {});\n' > "$R/tests/other.test.js"; printf 'foreign\n' >> "$R/README.md"
red "" sh -c 'exit 1'
assert_rc "B print mode: exit 0" 0
assert_contains "B print mode says it did not commit" "$SO" "not committing (no --commit)"
has_out "B print mode: the add command names only the own untracked path" "GIT_LITERAL_PATHSPECS=1 git add -- tests/mine.test.js"
has_out "B print mode: the commit command names only the own path" "$(printf 'GIT_LITERAL_PATHSPECS=1 git commit -m %q -- tests/mine.test.js' 'test(red): m')"
assert_eq "B print mode: no printed GIT_LITERAL command mentions a foreign path" "0" "$(printf '%s\n' "$SO" | grep '^GIT_LITERAL' | grep -c -e 'other\.test\.js' -e 'README\.md' || true)"
has_out "B print mode: the gate E2 note names the foreign test path" "note: another task's path, not checked: tests/other.test.js [test]"
has_out "B print mode: the gate E2 note names the foreign README path" "note: another task's path, not checked: README.md [code]"
untouched "B print mode"

echo "B AC10 E11: nothing of the task's changed (only a foreign path): exit 1, nothing committed"
new_s
sf "$SF" own:tests/mine.test.js other:tests/other.test.js
printf 'test("o", () => {});\n' > "$R/tests/other.test.js"
red --commit sh -c 'exit 1'
assert_rc "B E11 default path: exit 1" 1
has_err "B E11 default path: the exact message" "$E11"
untouched "B E11 default path"
red "" sh -c 'exit 1'
assert_rc "B E11 print mode: exit 1" 1
has_err "B E11 print mode: the exact message" "$E11"
new_s
dirty "$R"; BL="$(snap "$R")"
sf "$SF" own:tests/mine.test.js other:tests/other.test.js
printf 'test("o", () => {});\n' > "$R/tests/other.test.js"
red --commit sh -c 'exit 1'
assert_rc "B E11 with --baseline: exit 1" 1
has_err "B E11 with --baseline: the exact message" "$E11"
untouched "B E11 with --baseline"

# ================= C  AC14  rule-4 paths: E16, E17 =================
echo "C AC14 --commit: a rule-4 path that passed the gate (unknown test path for the tester) is named with E16 on stderr and is not committed"
new_s
sf "$SF" own:tests/mine.test.js
printf '%s\n' "$MINE" > "$R/tests/mine.test.js"; printf 'test("s", () => {});\n' > "$R/tests/stray.test.js"
red --commit sh -c 'exit 1'
assert_rc "C --commit: exit 0 (an allowed-kind rule-4 path passes the gate)" 0
has_err "C --commit: E16 names the stray path" "$(e16 tests/stray.test.js)"
no_err "C --commit: the own path is not named by E16" "$(e16 tests/mine.test.js)"
assert_eq "C --commit: only the own path is committed" "tests/mine.test.js" "$(committed "$R")"
assert_eq "C --commit: the stray path stays untracked" "?? tests/stray.test.js" "$(status_of tests/stray.test.js)"
assert_eq "C --commit: E17 is print mode only (no '# not in the task scope' line on stdout)" "0" "$(printf '%s\n' "$SO" | grep -c -F '# not in the task scope' || true)"

echo "C AC14 print mode: E16 on stderr and E17 on stdout after the printed commands; the commands do not name the stray paths (also a path with a space, via printf %q)"
new_s
sf "$SF" own:tests/mine.test.js
printf '%s\n' "$MINE" > "$R/tests/mine.test.js"; printf 'test("s", () => {});\n' > "$R/tests/stray.test.js"; printf 'test("s", () => {});\n' > "$R/tests/a b.test.js"
red "" sh -c 'exit 1'
assert_rc "C print mode: exit 0" 0
has_err "C print mode: E16 names tests/stray.test.js" "$(e16 tests/stray.test.js)"
has_err "C print mode: E16 names the path with a space" "$(e16 'tests/a b.test.js')"
has_out "C print mode: E17 for tests/stray.test.js" "$(e17 tests/stray.test.js)"
has_out "C print mode: E17 for the path with a space, shell-quoted" "$(e17 'tests/a b.test.js')"
CL="$(lno "$SO" "$(printf 'GIT_LITERAL_PATHSPECS=1 git commit -m %q -- tests/mine.test.js' 'test(red): m')")"
EL="$(lno "$SO" "$(e17 tests/stray.test.js)")"
if [ "$CL" -gt 0 ] && [ "$EL" -gt "$CL" ]; then t_ok "C print mode: E17 comes after the printed commands"; else t_bad "C print mode: E17 comes after the printed commands" "commit command at line $CL, E17 at line $EL; stdout: $SO"; fi
assert_eq "C print mode: no printed GIT_LITERAL command names a stray path" "0" "$(printf '%s\n' "$SO" | grep '^GIT_LITERAL' | grep -c -e stray -e 'a b' || true)"
untouched "C print mode"

echo "C AC14 --baseline: a rule-4 path gets E16; a baseline-recorded path that changed after the snapshot is rule 3 and gets no E16"
new_s
dirty "$R"; BL="$(snap "$R")"
sf "$SF" own:tests/mine.test.js
printf '%s\n' "$MINE" > "$R/tests/mine.test.js"; printf 'test("s", () => {});\n' > "$R/tests/stray.test.js"
printf 'edited by the other task\n' >> "$R/README.md"
red --commit sh -c 'exit 1'
assert_rc "C baseline: exit 0" 0
has_err "C baseline: E16 names the rule-4 stray path" "$(e16 tests/stray.test.js)"
no_err "C baseline: no E16 for the recorded (rule 3) path" "$(e16 README.md)"
assert_eq "C baseline: only the own path is committed" "tests/mine.test.js" "$(committed "$R")"

# ================= D  AC11  CMD-time changes outside the scope =================
echo "D AC11 a declared foreign path changes while CMD runs: E13 names it, the second gate (which also got --scope) passes, only the own path is committed"
new_s
sf "$SF" own:src/mine.js other:src/theirs.js
printf 'module.exports = 3;\n' > "$R/src/mine.js"
green --commit sh -c "printf 'z\n' > src/theirs.js"
assert_rc "D foreign path written by CMD: exit 0" 0
has_err "D foreign path written by CMD: E13 names it" "$(e13 src/theirs.js)"
assert_eq "D foreign path written by CMD: only the own path is committed" "src/mine.js" "$(committed "$R")"
assert_eq "D foreign path written by CMD: it stays untracked" "?? src/theirs.js" "$(status_of src/theirs.js)"

echo "D AC11 an unknown test path written by CMD in a green step: E13, then the second gate judges it (rule 4, forbidden kind) and the step fails"
new_s
sf "$SF" own:src/mine.js
printf 'module.exports = 3;\n' > "$R/src/mine.js"
green --commit sh -c "printf 'test(1)\n' > tests/stray.test.js"
assert_rc "D forbidden rule-4 path written by CMD: exit 1" 1
has_err "D forbidden rule-4 path written by CMD: E13 names it" "$(e13 tests/stray.test.js)"
assert_contains "D forbidden rule-4 path written by CMD: the second gate fails the step" "$OUT" "error: the role gate fails after the test command - nothing committed"
untouched "D forbidden rule-4 path written by CMD"

echo "D AC11 --baseline: a recorded (rule 3) path edited while CMD runs is E13, not a refusal: the notes comparison covers own paths only"
new_s
dirty "$R"; BL="$(snap "$R")"
sf "$SF" own:src/mine.js
printf 'module.exports = 3;\n' > "$R/src/mine.js"
green --commit sh -c "printf 'more\n' >> README.md"
assert_rc "D recorded path edited by CMD: exit 0" 0
has_err "D recorded path edited by CMD: E13 names it" "$(e13 README.md)"
assert_not_contains "D recorded path edited by CMD: not refused for differing baseline notes" "$OUT" "differ after the test command"
assert_eq "D recorded path edited by CMD: only the own path is committed" "src/mine.js" "$(committed "$R")"
assert_contains "D recorded path edited by CMD: the edit is still in the work tree" "$(cat "$R/README.md")" "more"

# ================= E  AC11  own change / HEAD moved =================
echo "E AC11 an own path written while CMD runs: E12 refusal, nothing committed"
new_s
sf "$SF" own:src/mine.js other:src/theirs.js
printf 'module.exports = 3;\n' > "$R/src/mine.js"
green --commit sh -c "printf 'q\n' >> src/mine.js"
assert_rc "E own path written by CMD: exit 1" 1
has_err "E own path written by CMD: E12 (work tree changed)" "$E12W"
untouched "E own path written by CMD"

echo "E AC11 --baseline: a recorded own path edited while CMD runs is refused too"
new_s
dirty "$R"; BL="$(snap "$R")"
sf "$SF" own:src/app.js own:src/mine.js
printf 'module.exports = 3;\n' > "$R/src/mine.js"
green --commit sh -c "printf 'q\n' >> src/app.js"
assert_rc "E recorded own path edited by CMD: exit 1" 1
assert_contains "E recorded own path edited by CMD: nothing committed" "$SE" "nothing committed"
untouched "E recorded own path edited by CMD"

echo "E AC11 HEAD moved while CMD runs (N3): E12 refusal, the step commits nothing of its own"
new_s
sf "$SF" own:src/mine.js
printf 'module.exports = 3;\n' > "$R/src/mine.js"
green --commit sh -c "git commit -q --allow-empty -m moved-by-cmd"
assert_rc "E HEAD moved: exit 1" 1
has_err "E HEAD moved: E12 (HEAD moved)" "$E12H"
assert_eq "E HEAD moved: only the command's own commit was added" "$((N0 + 1))" "$(count_of "$R")"
assert_eq "E HEAD moved: the step did not commit" "moved-by-cmd" "$(subject "$R")"

# ================= F  AC14  usage and digests =================
echo "F AC14 E14: --scope without --base (red) is a usage error, exit 2, nothing run"
new_s
sf "$SF" own:tests/mine.test.js
printf '%s\n' "$MINE" > "$R/tests/mine.test.js"
stp red --scope "$SF" --message m --commit -- sh -c 'exit 1'
assert_rc "F E14: exit 2" 2
assert_contains "F E14: the exact message" "$SE" "$E14"
untouched "F E14"

echo "F AC14 E10: the usage lines gain [--scope FILE] after [--baseline FILE]; --scope twice; --scope without a value"
new_s
stp red --base "$BASE" --scope "$SF" --scope "$SF" --message m -- sh -c 'exit 1'
assert_rc "F E10 twice: exit 2" 2
assert_contains "F E10 twice: '--scope given twice'" "$SE" "--scope given twice"
stp red --base "$BASE" --message m --scope ""
assert_rc "F E10 no value: exit 2" 2
has_err "F E10 no value: the red usage line gains [--scope FILE] after [--baseline FILE]" "usage: tdd-step.sh red [--base REF] [--baseline FILE] [--scope FILE] --message M [--commit] -- CMD..."
has_err "F E10 no value: the green usage line gains [--scope FILE] after [--baseline FILE]" "       tdd-step.sh green --base REF [--baseline FILE] [--scope FILE] --message M [--commit] -- CMD..."
stp red --base "$BASE" --message m --scope
assert_rc "F E10 --scope as the last argument: exit 2" 2
assert_contains "F E10 --scope as the last argument: the usage names [--scope FILE]" "$SE" "[--scope FILE]"
untouched "F E10"

echo "F AC14 E15: the scope file changes between the two gate runs: refused with both digests, nothing committed"
new_s
sf "$SF" own:src/mine.js
printf 'module.exports = 3;\n' > "$R/src/mine.js"
D1="$(dig "$SF")"
green --commit sh -c "printf 'other\tdocs/x.md\n' >> '$SF'"
D2="$(dig "$SF")"
assert_rc "F E15: exit 1" 1
has_err "F E15: the exact message with D1 (before) and D2 (now)" "error: the scope file changed between the two gate runs (digest $D1, now $D2) - nothing committed"
untouched "F E15"

echo "F AC14 E18: with --baseline the manifest changes between the two gate runs: refused with both digests; E15 is checked first"
new_s
dirty "$R"; BL="$(snap "$R")"
sf "$SF" own:src/mine.js
printf 'module.exports = 3;\n' > "$R/src/mine.js"
B1="$(dig "$BL")"
green --commit sh -c "printf 'absent\tnone\tzz-ghost.txt\n' >> '$BL'"
B2="$(dig "$BL")"
assert_rc "F E18: exit 1" 1
has_err "F E18: the exact message with both manifest digests" "error: the baseline manifest changed between the two gate runs (digest $B1, now $B2) - nothing committed"
untouched "F E18"
new_s
dirty "$R"; BL="$(snap "$R")"
sf "$SF" own:src/mine.js
printf 'module.exports = 3;\n' > "$R/src/mine.js"
D1="$(dig "$SF")"
green --commit sh -c "printf 'other\tdocs/x.md\n' >> '$SF'; printf 'absent\tnone\tzz-ghost.txt\n' >> '$BL'"
D2="$(dig "$SF")"
assert_rc "F E15 before E18: exit 1" 1
has_err "F E15 before E18: both files changed, E15 is reported" "error: the scope file changed between the two gate runs (digest $D1, now $D2) - nothing committed"
assert_not_contains "F E15 before E18: E18 is not reported" "$SE" "the baseline manifest changed between the two gate runs"
untouched "F E15 before E18"

# ================= G  AC14  control characters =================
echo "G AC14 a changed path with a control character is refused on the --scope path, without --baseline: own path and a foreign path alike"
CTL="c"$'\003'"d.test.js"
if can_name "$CTL"; then
  new_s
  sf "$SF" own:tests/
  printf '%s\n' "$MINE" > "$R/tests/$CTL"
  red --commit sh -c 'exit 1'
  assert_rc "G own control-character path, no baseline: exit 1" 1
  has_err "G own control-character path, no baseline: refused as today" "error: a changed path contains a control character: commit the role's paths by hand - nothing committed"
  untouched "G own control-character path, no baseline"
  new_s
  sf "$SF" own:tests/mine.test.js other:docs/
  printf '%s\n' "$MINE" > "$R/tests/mine.test.js"; mkdir -p "$R/docs"; printf 'x\n' > "$R/docs/$CTL"
  red --commit sh -c 'exit 1'
  assert_rc "G foreign control-character path (other entry), no baseline: exit 1" 1
  has_err "G foreign control-character path, no baseline: refused as today" "error: a changed path contains a control character: commit the role's paths by hand - nothing committed"
  untouched "G foreign control-character path, no baseline"
  new_s
  dirty "$R"; BL="$(snap "$R")"
  sf "$SF" own:tests/
  printf '%s\n' "$MINE" > "$R/tests/$CTL"
  red --commit sh -c 'exit 1'
  assert_rc "G own control-character path with --baseline: exit 1" 1
  has_err "G own control-character path with --baseline: refused as today" "error: a changed path contains a control character: commit the role's paths by hand - nothing committed"
  untouched "G own control-character path with --baseline"
else
  t_skip 9 "G control-character path (the file system cannot store a name with a control character)"
fi

# ================= H  relative scope file =================
echo "H a relative --scope path is the caller's, not the project root's (the step resolves it before it enters the root)"
new_s
mkdir -p "$R/tests/sub"
SF="$R/.git/pb-scope-t"
sf "$SF" own:tests/mine.test.js
printf '%s\n' "$MINE" > "$R/tests/mine.test.js"
SD="$R/tests/sub"
stp red --base "$BASE" --scope ../../.git/pb-scope-t --message m --commit -- sh -c 'exit 1'
SD=""
assert_rc "H relative scope file from a subdirectory: exit 0" 0
assert_eq "H relative scope file: the own path is committed" "tests/mine.test.js" "$(committed "$R")"

# ================= I  AC6.2 / AC6.5  the fallbacks of own_notes and scope_cmd_diff (characterization tests: the guards exist today; mutants N4 and M11 make these fail) =================
# shims: a PATH dir with a counting mktemp (fails templates holding pb-scope. from call PB_FAIL_FROM on) and a cmp (exits 2 on tdd-step's before/after compare)
SH_RM="$(command -v mktemp)"; SH_CMP="$(command -v cmp)"
SHD="$(mk_tmp)"; SHLOG="$(mk_tmp)"
cat > "$SHD/mktemp" <<EOF
#!/usr/bin/env bash
case "\$*" in *pb-scope.*) n=\$(cat "$SHLOG/cnt" 2>/dev/null); n=\$((\${n:-0} + 1)); echo "\$n" > "$SHLOG/cnt"; echo "pb-scope call \$n" >> "$SHLOG/mlog"
  if [ -n "\${PB_FAIL_FROM:-}" ] && [ "\$n" -ge "\$PB_FAIL_FROM" ]; then exit 1; fi ;; esac
exec "$SH_RM" "\$@"
EOF
cat > "$SHD/cmp" <<EOF
#!/usr/bin/env bash
if [ -n "\${PB_CMP_FAIL:-}" ]; then
  prev=""; last=""
  for a in "\$@"; do prev="\$last"; last="\$a"; done
  case "\$prev:\$last" in */before:*/after) echo "cmp shim fired" >> "$SHLOG/clog"; exit 2 ;; esac
fi
exec "$SH_CMP" "\$@"
EOF
chmod +x "$SHD/mktemp" "$SHD/cmp"
if [ -x "$SHD/mktemp" ] && [ -x "$SHD/cmp" ]; then
echo "I AC6.2 [characterization, N4] --scope --baseline: pb_scope_classify failing from its 4th call (own_notes) keeps the note in the comparison: the step exits 1 with ND, never 3"
new_s
printf 'dirty\n' >> "$R/README.md"; BL="$(snap "$R")"
sf "$SF" own:src/mine.js
printf 'module.exports = 3;\n' > "$R/src/mine.js"
: > "$SHLOG/cnt"; : > "$SHLOG/mlog"
OLDP="$PATH"; PATH="$SHD:$PATH"; export PB_FAIL_FROM=4
green --commit sh -c "printf 'more\n' >> README.md"
unset PB_FAIL_FROM; PATH="$OLDP"
assert_eq "I AC6.2 the mktemp shim saw exactly 4 pb-scope. calls (gate 1, scope_cmd_diff, gate 2, own_notes): the order is as assumed" "4" "$(grep -c '^pb-scope call' "$SHLOG/mlog" 2>/dev/null || true)"
has_err "I AC6.2 the edit of the recorded path reached the own_notes call (E13 names README.md)" "$(e13 README.md)"
assert_rc "I AC6.2 own_notes fallback (classify fails): exit 1, not 3" 1
has_err "I AC6.2 own_notes fallback: ND, the unchanged-notes comparison refuses the step" "error: the paths unchanged since the baseline differ after the test command - nothing committed"
assert_not_contains "I AC6.2 own_notes fallback: no cannot-classify error (exit 3 is the mutant)" "$OUT" "cannot classify the changed paths"
untouched "I AC6.2 own_notes fallback"
echo "I AC6.5 [characterization, M11] --scope, CMD changes nothing, tdd-step's before/after cmp exits 2 (an error, not a difference): the any-eq-0 guard refuses, as without --scope"
new_s
sf "$SF" own:src/mine.js
printf 'module.exports = 3;\n' > "$R/src/mine.js"
: > "$SHLOG/clog"
OLDP="$PATH"; PATH="$SHD:$PATH"; export PB_CMP_FAIL=1
green --commit true
PATH="$OLDP"
assert_eq "I AC6.5 the cmp shim fired on the before/after compare (control)" "1" "$(grep -c 'cmp shim fired' "$SHLOG/clog" 2>/dev/null || true)"
assert_rc "I AC6.5 --scope, equal manifests, cmp error: exit 1" 1
has_err "I AC6.5 --scope, equal manifests, cmp error: E12W" "$E12W"
untouched "I AC6.5 --scope"
: > "$SHLOG/clog"
OLDP="$PATH"; PATH="$SHD:$PATH"
stp green --base "$BASE" --message m --commit -- true
PATH="$OLDP"; unset PB_CMP_FAIL
assert_eq "I AC6.5 without --scope the cmp shim fired too (control)" "1" "$(grep -c 'cmp shim fired' "$SHLOG/clog" 2>/dev/null || true)"
assert_rc "I AC6.5 without --scope the same input: exit 1" 1
has_err "I AC6.5 without --scope the same input: E12W" "$E12W"
else
  t_skip 15 "I AC6.2 / AC6.5 PATH shims (cannot make an executable shim here)"
fi

t_summary
