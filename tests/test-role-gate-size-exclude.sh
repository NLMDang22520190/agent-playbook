#!/usr/bin/env bash
# Tests for v0.26.3 lane W slice S1 (.agents/handoff/01-spec.md AC9-AC12): `role-gate.sh size --base REF` leaves a changed lockfile
# out of the Lite count when its basename is exactly one of the AC9 table and a sibling manifest of that lockfile (same directory)
# exists as a blob in the REF commit; it then prints one note line before the `files:` line. Everything else counts as before.
# Review fix (263w-review.md finding 1): the lockfile itself must also exist at the same path in the REF commit (an update);
# a NEW lockfile-named file is counted like any code (W1).
#   AC9   all 23 lockfile/manifest pairs of the table; untracked, staged, committed and modified tracked lockfiles
#   AC10  adversarial rows a-f are counted and print the same bytes as the gate before this slice; exempt rows g-j
#   AC11  the note line (count, lines, first 5 paths, control characters shown as ?); nothing exempt: no note, same bytes as before
#   AC12  a test path is untouched; an unreadable untracked exempt lockfile is no error, a non-exempt one keeps exit 3;
#         check verdicts unchanged; the role-gate.sh header documents the exemption and its residual risk
# The "old gate" is scripts/ at 0927bde (the base of this lane), run beside the current gate on the same repo. Kinds this file
# system cannot hold (a newline or ESC in a name, symlinks, chmod 000) are skipped with the same assertion count (L-0004).
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/role-gate-fixture.sh"

OLD="$(mk_tmp)"; PRE=0927bde; REF_OK=0
if git -C "$PB_ROOT" cat-file -e "$PRE^{commit}" 2>/dev/null &&
   ( cd "$PB_ROOT" && git archive "$PRE" scripts | tar -x -C "$OLD" ) 2>/dev/null && [ -f "$OLD/scripts/role-gate.sh" ]; then REF_OK=1; fi
OLDG="$OLD/scripts/role-gate.sh"
NOTE='note: not counted (lockfile beside its manifest at the base):'
NL='
'

# gen N -> N lines of lockfile-like text; genjs N -> N lines of JavaScript
gen() { awk -v n="$1" 'BEGIN { for (i = 1; i <= n; i++) printf "  \"dep%d\": \"1.0.%d\",\n", i, i }'; }
genjs() { awk -v n="$1" 'BEGIN { for (i = 1; i <= n; i++) printf "module.exports.f%d = function () { return %d; };\n", i, i }'; }
# lrepo -> a fresh repo, cwd in it ($R); base -> B = HEAD sha; commit_all MSG
lrepo() { R="$(mk_tmp)"; mk_repo "$R"; cd "$R" || exit 3; }
base() { B="$(git rev-parse HEAD)"; }
commit_all() { git add -A && git commit -q -m "$1"; }
# man DIR NAME -> a one-line manifest DIR/NAME
man() { mkdir -p "$1"; printf '{}\n' > "$1/$2"; }
# sz [ARGS] -> current gate size --base $B (OUT = stdout+stderr, RC); SOUT = stdout only of the same run
sz() { run bash "$GATE" size --base "$B" "$@"; SOUT="$(bash "$GATE" size --base "$B" "$@" 2>/dev/null)"; }
# notes -> the not-counted note lines of $OUT
notes() { printf '%s\n' "$OUT" | grep -F "$NOTE" || true; }
# same_as_old NAME [ARGS] -> stdout, stderr and exit code of `size --base $B ARGS` equal the old gate's on this repo
same_as_old() { same_as_old_cmd "$1" size --base "$B" "${@:2}"; }
same_as_old_cmd() {
  local name="$1" d; shift
  if [ "$REF_OK" != 1 ]; then t_skip 1 "$name (no $PRE scripts in this clone)"; return; fi
  d="$(mk_tmp)"
  bash "$GATE" "$@" > "$d/n.out" 2> "$d/n.err"; echo $? > "$d/n.rc"
  bash "$OLDG" "$@" > "$d/o.out" 2> "$d/o.err"; echo $? > "$d/o.rc"
  if cmp -s "$d/n.out" "$d/o.out" && cmp -s "$d/n.err" "$d/o.err" && cmp -s "$d/n.rc" "$d/o.rc"; then t_ok "$name"
  else t_bad "$name" "new: rc $(cat "$d/n.rc") [$(cat "$d/n.out" "$d/n.err")] old: rc $(cat "$d/o.rc") [$(cat "$d/o.out" "$d/o.err")]"; fi
}
# line_before_files -> the stdout line right before the files: line
line_before_files() { printf '%s\n' "$SOUT" | awk '/^files: /{ print prev; exit } { prev = $0 }'; }

# ================= AC9 the table
echo "AC9 every lockfile of the table that exists at the base beside one of its manifests, changed after the base, adds 0 files and 0 lines"
PAIRS="package-lock.json:package.json npm-shrinkwrap.json:package.json yarn.lock:package.json pnpm-lock.yaml:package.json
bun.lock:package.json bun.lockb:package.json deno.lock:deno.json deno.lock:deno.jsonc Cargo.lock:Cargo.toml Gemfile.lock:Gemfile
poetry.lock:pyproject.toml pdm.lock:pyproject.toml uv.lock:pyproject.toml Pipfile.lock:Pipfile composer.lock:composer.json
go.sum:go.mod mix.lock:mix.exs pubspec.lock:pubspec.yaml Podfile.lock:Podfile Package.resolved:Package.swift
gradle.lockfile:build.gradle gradle.lockfile:build.gradle.kts flake.lock:flake.nix"
lrepo; i=0
for p in $PAIRS; do i=$((i + 1)); man "p$i" "${p#*:}"; printf '{\n' > "p$i/${p%%:*}"; done
commit_all manifests; base; i=0
for p in $PAIRS; do i=$((i + 1)); gen 40 >> "p$i/${p%%:*}"; done
sz
assert_rc "AC9 23 changed tracked lockfiles (920 added lines) beside their manifests: within the Lite limits, exit 0" 0
assert_contains "AC9 ... files: 0 lines: 0" "$OUT" "files: 0/3 lines: 0/100 (base=$B)"
assert_contains "AC9 ... one note names 23 file(s) and 920 line(s)" "$OUT" "$NOTE 23 file(s), 920 line(s): "

echo "W1 the same 23 lockfiles NEW (absent at the base, untracked) beside their manifests at the base are counted"
lrepo; i=0
for p in $PAIRS; do i=$((i + 1)); man "p$i" "${p#*:}"; done
commit_all manifests; base; i=0
for p in $PAIRS; do i=$((i + 1)); gen 40 > "p$i/${p%%:*}"; done
sz
assert_contains "W1 23 new lockfiles: all counted (23 files, 920 lines)" "$OUT" "files: 23/3 lines: 920/100 (base=$B)"
assert_rc "W1 23 new lockfiles: over the limit, exit 1" 1
assert_eq "W1 23 new lockfiles: no not-counted note" "" "$(notes)"
same_as_old "W1 23 new lockfiles: stdout, stderr and exit code equal the gate before this slice"

echo "AC9 a lockfile beside a manifest of another ecosystem (not one of its own) is counted"
lrepo
man x1 package.json; man x2 Cargo.toml; man x3 Pipfile; man x4 pyproject.toml; man x5 package.json; man x6 pom.xml
man x7 package.json; man x8 gemfile; man x9 go.sum
commit_all manifests; base
gen 20 > x1/Cargo.lock; gen 20 > x2/go.sum; gen 20 > x3/poetry.lock; gen 20 > x4/Pipfile.lock; gen 20 > x5/deno.lock
gen 20 > x6/gradle.lockfile; gen 20 > x7/composer.lock; gen 20 > x8/Gemfile.lock; gen 20 > x9/go.mod
sz
assert_contains "AC9 crossed pairs: all 9 counted (9 files, 180 lines)" "$OUT" "files: 9/3 lines: 180/100 (base=$B)"
assert_rc "AC9 crossed pairs: over the limit, exit 1" 1
assert_eq "AC9 crossed pairs: no not-counted note" "" "$(notes)"
same_as_old "AC9 crossed pairs: stdout, stderr and exit code equal the gate before this slice"

echo "AC9 a staged change and a committed change of a lockfile that exists at the base are exempt too"
lrepo; man . Cargo.toml; printf '{\n' > Cargo.lock; commit_all m; base
gen 130 >> Cargo.lock; git add Cargo.lock
sz
assert_rc "AC9 staged Cargo.lock change (130 lines) beside Cargo.toml: exit 0" 0
assert_contains "AC9 staged ... files: 0 lines: 0" "$OUT" "files: 0/3 lines: 0/100 (base=$B)"
assert_contains "AC9 staged ... note" "$OUT" "$NOTE 1 file(s), 130 line(s): Cargo.lock"
lrepo; man . Gemfile; printf '{\n' > Gemfile.lock; commit_all m; base
gen 110 >> Gemfile.lock; commit_all lock
sz
assert_rc "AC9 committed Gemfile.lock change (110 lines) after the base, Gemfile and Gemfile.lock at the base: exit 0" 0
assert_contains "AC9 committed ... files: 0 lines: 0" "$OUT" "files: 0/3 lines: 0/100 (base=$B)"
assert_contains "AC9 committed ... note" "$OUT" "$NOTE 1 file(s), 110 line(s): Gemfile.lock"

echo "W1 a NEW lockfile staged, or committed after the base, beside a manifest at the base is counted"
lrepo; man . Cargo.toml; commit_all m; base
gen 130 > Cargo.lock; git add Cargo.lock
sz
assert_contains "W1 staged new Cargo.lock: counted (1 file, 130 lines)" "$OUT" "files: 1/3 lines: 130/100 (base=$B)"
assert_rc "W1 staged new Cargo.lock: exit 1" 1
assert_eq "W1 staged new Cargo.lock: no note" "" "$(notes)"
lrepo; man . Gemfile; commit_all m; base
gen 110 > Gemfile.lock; commit_all lock
sz
assert_contains "W1 new Gemfile.lock committed after the base: counted (1 file, 110 lines)" "$OUT" "files: 1/3 lines: 110/100 (base=$B)"
assert_rc "W1 new Gemfile.lock committed after the base: exit 1" 1
assert_eq "W1 new Gemfile.lock committed after the base: no note" "" "$(notes)"
same_as_old "W1 new Gemfile.lock committed after the base: same bytes as before"

echo "W1 (review rv1) a new root yarn.lock holding JavaScript, required by index.js, beside package.json at the base: counted"
lrepo; printf '{"name":"x"}\n' > package.json; printf 'module.exports = 1;\n' > index.js; commit_all m; base
{ echo 'module.exports = function () {'; genjs 300; echo '  return 42; };'; } > yarn.lock
printf "module.exports = require('./yarn.lock')();\n" > index.js
commit_all work
sz
assert_contains "W1 rv1: yarn.lock and index.js both counted (2 files)" "$OUT" "files: 2/3 lines: "
assert_rc "W1 rv1: over the line limit, exit 1" 1
assert_eq "W1 rv1: no not-counted note" "" "$(notes)"
assert_not_contains "W1 rv1: the output does not report 2 lines for the work" "$OUT" "lines: 2/100"
same_as_old "W1 rv1: stdout, stderr and exit code equal the gate before this slice"

echo "W1 a lockfile at the base in another directory does not make a new one exempt (same path only)"
lrepo; man . package.json; man web package.json; printf '{\n' > yarn.lock; commit_all m; base
gen 120 > web/yarn.lock
sz
assert_contains "W1 root yarn.lock at the base, new web/yarn.lock: counted (1 file, 120 lines)" "$OUT" "files: 1/3 lines: 120/100 (base=$B)"
assert_eq "W1 ... no note" "" "$(notes)"
same_as_old "W1 ... same bytes as before"

# ================= AC10 exempt rows g-j
echo "AC10 (g) package-lock.json changed beside package.json at the base; the other production change still counts"
lrepo; man . package.json; printf '{\n' > package-lock.json; commit_all m; base
gen 150 >> package-lock.json
printf 'module.exports = 2;\nmodule.exports.x = 3;\n' > src/app.js
sz
assert_rc "AC10 (g) exit 0" 0
assert_contains "AC10 (g) src/app.js counts (1 file, 3 lines), the lockfile does not" "$OUT" "files: 1/3 lines: 3/100 (base=$B)"
assert_contains "AC11 (g) the note names the lockfile and its 150 lines" "$OUT" "$NOTE 1 file(s), 150 line(s): package-lock.json"
assert_eq "AC11 (g) the note is the stdout line right before the files: line" "$NOTE 1 file(s), 150 line(s): package-lock.json" "$(line_before_files)"
assert_eq "AC11 (g) exactly one note line" 1 "$(notes | wc -l | tr -d ' ')"

echo "W1 (h) a new go.sum beside go.mod at the base is counted (it is not at the base)"
lrepo; man . go.mod; commit_all m; base
gen 120 > go.sum
sz
assert_rc "W1 (h) new go.sum: exit 1" 1
assert_contains "W1 (h) new go.sum: counted (1 file, 120 lines)" "$OUT" "files: 1/3 lines: 120/100 (base=$B)"
assert_eq "W1 (h) new go.sum: no note" "" "$(notes)"
same_as_old "W1 (h) new go.sum: same bytes as before"
echo "AC10 (h) a go.sum that exists at the base beside go.mod, changed"
lrepo; man . go.mod; printf 'x v1 h1:a=\n' > go.sum; commit_all m; base
gen 120 >> go.sum
sz
assert_rc "AC10 (h) exit 0" 0
assert_contains "AC10 (h) files: 0 lines: 0" "$OUT" "files: 0/3 lines: 0/100 (base=$B)"
assert_contains "AC10 (h) note" "$OUT" "$NOTE 1 file(s), 120 line(s): go.sum"

echo "AC10 (i) a nested web/pnpm-lock.yaml that exists at the base beside web/package.json, changed"
lrepo; man web package.json; printf 'lockfileVersion: 9\n' > web/pnpm-lock.yaml; commit_all m; base
gen 200 >> web/pnpm-lock.yaml
sz
assert_rc "AC10 (i) exit 0" 0
assert_contains "AC10 (i) files: 0 lines: 0" "$OUT" "files: 0/3 lines: 0/100 (base=$B)"
assert_contains "AC10 (i) note" "$OUT" "$NOTE 1 file(s), 200 line(s): web/pnpm-lock.yaml"

echo "AC10 (j) under --baseline: a lockfile at the base changed after the snapshot, beside package.json at the base"
lrepo; man . package.json; printf '{\n' > yarn.lock; commit_all m; base
printf 'module.exports = 9;\n' > src/app.js
MF="$(mk_tmp)/baseline"; bash "$GATE" snapshot --out "$MF" >/dev/null 2>&1
gen 150 >> yarn.lock
sz --baseline "$MF"
assert_rc "AC10 (j) exit 0" 0
assert_contains "AC10 (j) files: 0 lines: 0 (src/app.js unchanged since the baseline, yarn.lock exempt)" "$OUT" "files: 0/3 lines: 0/100 (base=$B)"
assert_contains "AC10 (j) note" "$OUT" "$NOTE 1 file(s), 150 line(s): yarn.lock"

# ================= AC10 adversarial rows a-f (counted, same bytes as before)
echo "AC10 (a) src/yarn.lock holding JavaScript, no src/package.json at the base: counted"
lrepo; base
genjs 120 > src/yarn.lock
sz
assert_contains "AC10 (a) counted: 1 file, 120 lines" "$OUT" "files: 1/3 lines: 120/100 (base=$B)"
assert_rc "AC10 (a) exit 1" 1
assert_eq "AC10 (a) no not-counted note" "" "$(notes)"
same_as_old "AC10 (a) stdout, stderr and exit code equal the gate before this slice"

echo "AC10 (b) lib/Cargo.lock whose lib/Cargo.toml is added after the base: counted"
lrepo; base
man lib Cargo.toml; gen 120 > lib/Cargo.lock
sz
assert_contains "AC10 (b) manifest in the work tree only: lockfile and manifest counted (2 files, 121 lines)" "$OUT" "files: 2/3 lines: 121/100 (base=$B)"
assert_rc "AC10 (b) work tree: exit 1" 1
assert_eq "AC10 (b) work tree: no note" "" "$(notes)"
same_as_old "AC10 (b) work tree: same bytes as before"
lrepo; base
man lib Cargo.toml; commit_all "manifest after the base"
gen 120 > lib/Cargo.lock
sz
assert_contains "AC10 (b) manifest in a commit after the base: counted (2 files, 121 lines)" "$OUT" "files: 2/3 lines: 121/100 (base=$B)"
assert_eq "AC10 (b) later commit: no note" "" "$(notes)"
same_as_old "AC10 (b) later commit: same bytes as before"

echo "AC10 (c) the manifest exists at the base only in another directory: counted"
lrepo; man . package.json; commit_all m; base
gen 120 > src/yarn.lock
sz
assert_contains "AC10 (c) root package.json does not cover src/yarn.lock (1 file, 120 lines)" "$OUT" "files: 1/3 lines: 120/100 (base=$B)"
assert_eq "AC10 (c) no note" "" "$(notes)"
same_as_old "AC10 (c) same bytes as before"

echo "AC10 (d) not the exact basename (Yarn.lock, yarn.lock.js, xyarn.lock): counted"
lrepo; man . package.json; commit_all m; base
gen 40 > Yarn.lock; genjs 40 > yarn.lock.js; gen 40 > xyarn.lock
sz
assert_contains "AC10 (d) all three counted (3 files, 120 lines)" "$OUT" "files: 3/3 lines: 120/100 (base=$B)"
assert_eq "AC10 (d) no note" "" "$(notes)"
same_as_old "AC10 (d) same bytes as before"

echo "AC10 (e) the manifest at the base is a directory, or a symlink, not a blob: counted"
lrepo; mkdir -p pkg/package.json; printf 'x\n' > pkg/package.json/index.js; commit_all m; base
gen 120 > pkg/package-lock.json
sz
assert_contains "AC10 (e) directory named package.json: counted (1 file, 120 lines)" "$OUT" "files: 1/3 lines: 120/100 (base=$B)"
assert_eq "AC10 (e) directory: no note" "" "$(notes)"
same_as_old "AC10 (e) directory: same bytes as before"
if [ "$SYMLINKS" = 1 ]; then
  lrepo; man . package.json; mkdir lnk; ln -s ../package.json lnk/package.json; commit_all m; base
  if [ "$(git ls-files -s lnk/package.json | cut -c1-6)" = 120000 ]; then
    gen 120 > lnk/package-lock.json
    sz
    assert_contains "AC10 (e) symlink named package.json: counted (1 file, 120 lines)" "$OUT" "files: 1/3 lines: 120/100 (base=$B)"
    assert_eq "AC10 (e) symlink: no note" "" "$(notes)"
    same_as_old "AC10 (e) symlink: same bytes as before"
  else t_skip 3 "AC10 (e) symlink (git stores no 120000 entry here)"; fi
else t_skip 3 "AC10 (e) symlink (no symlinks on this file system)"; fi

# git_sees_byte HEX: an untracked path in the current repo holds the byte HEX as git reads it. Git Bash on NTFS lets
# mkdir take a newline or ESC but stores it as U+F00A / U+F01B, so the name git sees has no control byte.
git_sees_byte() { git ls-files -z --others | od -An -tx1 | tr -s ' \n' '  ' | grep -q " $1 "; }
echo "AC10 (f) a lockfile whose directory name holds a newline, manifest and lockfile beside it at the base: counted"
lrepo; NLD="n${NL}l"
if mkdir "$NLD" 2>/dev/null && printf '{}\n' > "$NLD/package.json" 2>/dev/null && git_sees_byte 0a; then
  printf '{\n' > "$NLD/package-lock.json"; commit_all m; base
  gen 120 >> "$NLD/package-lock.json"
  sz
  assert_contains "AC10 (f) counted (1 file, 120 lines)" "$OUT" "files: 1/3 lines: 120/100 (base=$B)"
  assert_eq "AC10 (f) no note" "" "$(notes)"
  same_as_old "AC10 (f) same bytes as before"
else t_skip 3 "AC10 (f) (no newline in names that git sees on this file system)"; fi

# ================= AC11 the note
echo "AC11 six exempt lockfiles: the note counts 6 and names the first 5"
lrepo; for d in a1 a2 a3 a4 a5 a6; do man "$d" package.json; printf '{\n' > "$d/yarn.lock"; done; commit_all m; base
for d in a1 a2 a3 a4 a5 a6; do gen 5 >> "$d/yarn.lock"; done
sz
assert_contains "AC11 note: 6 file(s), 30 line(s)" "$OUT" "$NOTE 6 file(s), 30 line(s): "
assert_eq "AC11 the note names exactly 5 of the 6 paths" 5 "$(notes | grep -o 'a[1-6]/yarn\.lock' | wc -l | tr -d ' ')"
assert_eq "AC11 one note line" 1 "$(notes | wc -l | tr -d ' ')"

echo "AC11 a control character in an exempt path is shown as ?"
lrepo; ESCD="e$(printf '\033')x"
if mkdir "$ESCD" 2>/dev/null && printf '{}\n' > "$ESCD/package.json" 2>/dev/null && git_sees_byte 1b; then
  printf '{\n' > "$ESCD/yarn.lock"; commit_all m; base
  gen 3 >> "$ESCD/yarn.lock"
  sz
  # W1/W11: the lockfile must now be tracked at the base, and git C-quotes a tracked path with a control character, so the gate
  # may either exempt it (the note shows ESC as ?) or count it (no note); both are sound, a raw ESC never is
  if printf '%s\n' "$OUT" | grep -qF "$NOTE"; then
    assert_contains "AC11 exempt: ESC shown as ?" "$OUT" "$NOTE 1 file(s), 3 line(s): e?x/yarn.lock"
  else
    assert_contains "AC11 not exempt: counted (1 file, 3 lines)" "$OUT" "files: 1/3 lines: 3/100 (base=$B)"
  fi
  assert_not_contains "AC11 no raw ESC byte in the output" "$OUT" "$(printf '\033')"
else t_skip 2 "AC11 control character (no ESC in names that git sees on this file system)"; fi

echo "AC11 nothing exempt: stdout, stderr and exit code equal the gate before this slice"
lrepo; base
printf 'module.exports = 5;\n' > src/app.js; genjs 30 > src/extra.js
sz
assert_eq "AC11 nothing exempt: no note" "" "$(notes)"
same_as_old "AC11 nothing exempt: plain size, same bytes as before"
same_as_old "AC11 nothing exempt: --max-lines 10, same bytes as before" --max-lines 10

# ================= AC12
echo "AC12 a test path is not counted and not named in the note (characterization: test paths were never counted)"
lrepo; man tests/fixtures package.json; commit_all m; base
gen 150 > tests/fixtures/yarn.lock
sz
assert_contains "AC12 tests/fixtures/yarn.lock: files: 0 lines: 0" "$OUT" "files: 0/3 lines: 0/100 (base=$B)"
assert_eq "AC12 test path: no note" "" "$(notes)"
same_as_old "AC12 test path: same bytes as before"

echo "AC12 W1 an unreadable untracked lockfile is never exempt (it is not at the base): exit 3 as before"
lrepo; man . go.mod; commit_all m; base
gen 120 > go.sum; chmod 000 go.sum 2>/dev/null
if [ ! -r go.sum ]; then
  sz
  assert_rc "W1 unreadable new go.sum beside go.mod: exit 3 (counted, cannot be read)" 3
  assert_contains "W1 ... the cannot-count error" "$OUT" "error: cannot count the lines of untracked file go.sum"
  same_as_old "W1 ... same bytes as before"
  chmod 644 go.sum
  lrepo; base
  gen 120 > src/yarn.lock; chmod 000 src/yarn.lock
  sz
  assert_rc "AC12 unreadable non-exempt src/yarn.lock: exit 3 (v0.24.29)" 3
  assert_contains "AC12 ... the cannot-count error" "$OUT" "error: cannot count the lines of untracked file src/yarn.lock"
  same_as_old "AC12 ... same bytes as before"
  chmod 644 src/yarn.lock
else chmod 644 go.sum 2>/dev/null; t_skip 6 "AC12 unreadable (chmod 000 does not stop reads here)"; fi

echo "AC12 check verdicts are unchanged: an exempt lockfile is still production for the tester"
lrepo; man . package.json; printf '{\n' > package-lock.json; commit_all m; base
gen 150 >> package-lock.json
run bash "$GATE" check tester --base "$B"
assert_rc "AC12 check tester with a changed package-lock.json: violation, exit 1" 1
assert_contains "AC12 ... names package-lock.json" "$OUT" "package-lock.json"
same_as_old_cmd "AC12 check tester: same bytes as before" check tester --base "$B"
same_as_old_cmd "AC12 check implementer: same bytes as before" check implementer --base "$B"

echo "AC12 the role-gate.sh header documents the exemption and its residual risk"
HDR="$(awk '/^set -u$/ { exit } { print }' "$GATE")"
assert_contains "AC12 header names the note line" "$HDR" "not counted (lockfile beside its manifest at the base)"
assert_contains "AC12 header names table entries (Package.resolved)" "$HDR" "Package.resolved"
assert_contains "AC12 header names table entries (gradle.lockfile)" "$HDR" "gradle.lockfile"
assert_contains "AC12 header names the residual risk of a manifest added in the agent's own RED commit" "$HDR" "RED commit"

t_summary
