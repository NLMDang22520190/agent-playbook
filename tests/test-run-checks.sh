#!/usr/bin/env bash
# Tests for the SKILL.md frontmatter checks in evals/run-checks.sh (AC5).
# Each test runs run-checks.sh inside a fresh copy of the repository (tracked + untracked,
# non-ignored files), so mutations never touch the real skills.
# (v0.23.3: test-run-checks.sh was split by section so that no part is the floor of a CI shard: this file holds the SKILL.md
# frontmatter, CRLF and executable-bit cases; the GNU scanner cases are in test-run-checks-gnu.sh and
# test-run-checks-gnu9.sh, the dupmax, sed, --only, soh and empty-glob cases in test-run-checks-sections.sh. Shared setup: run-checks-fixture.sh.)
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/run-checks-fixture.sh"
# (the CRLF cases copy a committed git repo of a minimal tree, FMING below; no full-tree mk_gmaster here)

# Minimal trees (v0.24.8). A full-tree copy makes `run-checks --only files` spawn `bash -n` for every script (89 spawns,
# ~68 ms each on Git Bash) and `--only skills` walk every skill; the cases below only need what their group reads.
# files group reads: install.sh, scripts|tests|evals|tools/*.sh (globs must match), the six scripts whose exec bit it checks,
# and git's view of the tree for the CRLF check. skills group reads skills/*/ (one skill is enough for a mutated-line case;
# the real tree is still run once by the AC5 "current skills pass" and AC4 "real tree" cases).
FMIN="$(mk_tmp)"
mkdir -p "$FMIN/evals" "$FMIN/scripts" "$FMIN/tests" "$FMIN/tools" "$FMIN/docs" "$FMIN/skills"
cp "$MASTER/evals/run-checks.sh" "$FMIN/evals/run-checks.sh"
for stub in tests/stub.sh tools/stub.sh install.sh scripts/conf.sh scripts/role-gate.sh scripts/proof-run.sh scripts/learn.sh scripts/feedback.sh; do
  printf '#!/usr/bin/env bash\n# stub: keeps its glob non-empty, holds no finding\n' > "$FMIN/$stub"
  chmod +x "$FMIN/$stub"
done
cp "$MASTER/README.md" "$MASTER/.gitattributes" "$FMIN/"
printf 'plain note\n' > "$FMIN/docs/note.md"
cp -a "$MASTER/skills/playbook-proof" "$FMIN/skills/playbook-proof"
# mk_fmin_copy -> temp dir, not a git repo; mk_fmin_git_copy -> the same, committed into a fresh repo with LF in the index
mk_fmin_copy() { local d; d="$(mk_tmp)"; cp -a "$FMIN/." "$d/"; printf '%s\n' "$d"; }
FMING="$(mk_tmp)"
cp -a "$FMIN/." "$FMING/"
( cd "$FMING" && git init -q && git config core.autocrlf false && git config user.email t@example.invalid &&
  git config user.name tester && git config commit.gpgsign false && git add -A && git commit -q -m copy ) >/dev/null 2>&1
mk_fmin_git_copy() { local d; d="$(mk_tmp)"; cp -a "$FMING/." "$d/"; printf '%s\n' "$d"; }

echo "frontmatter checks (AC5)"
C="$(mk_copy)"
checks "$C" skills
assert_rc "AC5 current skills pass run-checks (exit 0)" 0

C="$(mk_fmin_copy)"
set_line "$C" description 'description: Use when stating results. Note: keep it short.'
checks "$C" skills
assert_rc "AC5 unquoted description containing ': ' fails (exit 1)" 1
assert_contains "AC5 failure names the SKILL.md" "$OUT" "$SKILL"

C="$(mk_fmin_copy)"
set_line "$C" description 'description: "Use when stating results. Note: keep it short."'
checks "$C" skills
assert_rc "AC5 double-quoted description containing ': ' passes" 0

C="$(mk_fmin_copy)"
set_line "$C" description "description: 'Use when stating results. Note: keep it short.'"
checks "$C" skills
assert_rc "AC5 single-quoted description containing ': ' passes" 0

C="$(mk_fmin_copy)"
set_line "$C" description 'description: Use when stating results at a 1:2 ratio or more.'
checks "$C" skills
assert_rc "AC5 unquoted description with ':' not followed by a space passes" 0

if python3 -c 'import yaml' >/dev/null 2>&1; then
  C="$(mk_fmin_copy)"
  add_line "$C" 'metadata: [unclosed'
  checks "$C" skills
  assert_rc "AC5 frontmatter that PyYAML cannot parse fails (exit 1)" 1
  assert_contains "AC5 parse failure names the SKILL.md" "$OUT" "$SKILL"
else
  t_skip 2 "AC5 PyYAML parse test: python3 -c 'import yaml' failed"
fi

# Without PyYAML the parse check is skipped with a printed note, the rest still runs.
C="$(mk_fmin_copy)"
add_line "$C" 'metadata: [unclosed'
FAKE="$(mk_tmp)"
printf '#!/bin/sh\nexit 1\n' > "$FAKE/python3"; chmod +x "$FAKE/python3"
OUT="$(PATH="$FAKE:$PATH" bash "$C/evals/run-checks.sh" --only skills 2>&1)"; RC=$?; only_problems
assert_rc "AC5 without PyYAML the parse check does not fail the run" 0
SKIPLINE="$(printf '%s\n' "$OUT" | grep -i 'skip' | grep -i 'yaml')"
assert_contains "AC5 without PyYAML a skip note mentioning yaml is printed" "$(printf '%s' "$SKIPLINE" | tr 'A-Z' 'a-z')" "yaml"

# Without PyYAML the explicit unquoted ': ' check alone must still catch the bad description.
C="$(mk_fmin_copy)"
set_line "$C" description 'description: Use when stating results. Note: keep it short.'
OUT="$(PATH="$FAKE:$PATH" bash "$C/evals/run-checks.sh" --only skills 2>&1)"; RC=$?; only_problems
assert_rc "AC5 without PyYAML an unquoted description containing ': ' still fails (exit 1)" 1
assert_contains "AC5 without PyYAML the failure says unquoted" "$OUT" "unquoted"
assert_contains "AC5 without PyYAML the failure names the SKILL.md" "$OUT" "$SKILL"

echo "CRLF check judges what git stores (Windows checkouts convert to CRLF)"
C="$(mk_fmin_git_copy)"
to_crlf "$C/README.md"; to_crlf "$C/.gitattributes"
checks "$C" files
assert_not_contains "CRLF only in the working tree of a tracked LF file is not a failure" "$OUT" "CRLF found"
# "* text=auto eol=lf" would normalise CRLF to LF on add, so override it for this file
# (-text) to really store CRLF in the index.
C="$(mk_fmin_git_copy)"
printf 'docs/crlf-note.md -text\n' >> "$C/.gitattributes"
printf 'line one\r\nline two\r\n' > "$C/docs/crlf-note.md"
( cd "$C" && git add .gitattributes docs/crlf-note.md && git commit -q -m crlf ) >/dev/null 2>&1
checks "$C" files
assert_rc "CRLF stored in the git index fails" 1
assert_contains "the failure names the CRLF file" "$OUT" "docs/crlf-note.md"
C="$(mk_fmin_git_copy)"
printf 'untracked\r\n' > "$C/docs/untracked-crlf.md"
checks "$C" files
assert_contains "an untracked CRLF file still fails" "$OUT" "docs/untracked-crlf.md"
C="$(mk_fmin_copy)"
printf 'no git here\r\n' > "$C/docs/plain-crlf.md"
checks "$C" files
assert_contains "outside git, working-tree CRLF still fails" "$OUT" "docs/plain-crlf.md"

# when `cat` fails, the one-pass CR scan must fall back to the per-file check, not report "no CR"
C="$(mk_fmin_copy)"
printf 'no git here\r\n' > "$C/docs/catfail-crlf.md"
FB="$(mk_tmp)"; printf '#!/bin/sh\nexit 1\n' > "$FB/cat"; chmod +x "$FB/cat"
run env PATH="$FB:$PATH" bash "$C/evals/run-checks.sh" --only files
assert_contains "CRLF file still reported when cat fails" "$(printf '%s\n' "$OUT" | grep 'CRLF found in:')" "docs/catfail-crlf.md"


echo "#12b quoted name matches its directory"
C="$(mk_fmin_copy)"
set_line "$C" name 'name: "playbook-proof"'
checks "$C" skills
assert_rc "AC12b.2 quoted name passes run-checks" 0
assert_not_contains "AC12b.2 no name-mismatch failure for a quoted name" "$OUT" "name '"

# ---- v0.24.6 AC4: run-checks.sh --only files ----
echo "v0.24.6 AC4 run-checks.sh --only files runs the files group and no other group"
C="$(mk_copy)"
run bash "$C/evals/run-checks.sh" --only files
assert_rc "AC4 --only files on the real tree: exit 0" 0
assert_contains "AC4 --only files prints the CRLF line" "$OUT" "  ok   no CRLF line endings"
assert_contains "AC4 --only files prints a syntax line" "$OUT" "  ok   syntax: install.sh"
assert_contains "AC4 --only files prints an executable-bit line" "$OUT" "  ok   executable: scripts/conf.sh"
assert_contains "AC4 --only files ends with the summary" "$OUT" "run-checks: all ok"
for other in "always-on block" "v0.3 rules" "v0.4 weights" "contains the verbatim clarify sentence" "name matches directory" \
  "chars (<=450)" "scenarios each have" "regex repeat bounds" "has a suffix (BSD sed)" "GNU-only options" "no SOH byte" \
  "shellcheck (warning level)" "skip shellcheck" "every script is stored with git mode 100755"; do
  assert_not_contains "AC4 --only files prints no line of another group [$other]" "$OUT" "$other"
done

echo "v0.24.6 AC4 the files checks still fail under --only files"
C="$(mk_fmin_copy)"
printf 'plain file, crlf\r\n' > "$C/docs/files-only-crlf.md"
run bash "$C/evals/run-checks.sh" --only files
assert_rc "AC4 a CRLF fixture fails under --only files (exit 1)" 1
assert_contains "AC4 the CRLF failure under --only files says CRLF found" "$OUT" "CRLF found in:"
assert_contains "AC4 the CRLF failure under --only files names the file" "$OUT" "docs/files-only-crlf.md"
C="$(mk_fmin_copy)"
chmod -x "$C/scripts/conf.sh"
if [ -x "$C/scripts/conf.sh" ]; then t_skip 2 "AC4 exec-bit failure under --only files (chmod -x has no effect on this file system)"; else
run bash "$C/evals/run-checks.sh" --only files
assert_rc "AC4 a script without its exec bit fails under --only files (exit 1)" 1
assert_contains "AC4 the exec-bit failure under --only files names the script" "$OUT" "not executable: scripts/conf.sh"
fi
C="$(mk_fmin_copy)"
printf 'if then\n' >> "$C/scripts/conf.sh"
run bash "$C/evals/run-checks.sh" --only files
assert_rc "AC4 a script with a syntax error fails under --only files (exit 1)" 1
assert_contains "AC4 the syntax failure under --only files names the script" "$OUT" "bash -n failed: scripts/conf.sh"
echo "v0.24.6 AC4 --only files runs only the files group: another group's problem is not reported"
C="$(mk_fmin_copy)"
set_line "$C" description 'description: Use when stating results. Note: keep it short.'
run bash "$C/evals/run-checks.sh" --only files
assert_rc "AC4 --only files ignores a skills problem (a bad description): exit 0" 0

echo "v0.24.6 AC4 --only takes exactly one name; the messages name files"
C="$(mk_min_copy)"
run bash "$C/evals/run-checks.sh" --only files skills
assert_rc "AC4 --only files skills (two names) still exits 2" 2
assert_not_contains "AC4 --only files skills: no check ran" "$OUT" "  ok   "
run bash "$C/evals/run-checks.sh" --only nosuchgroup
assert_rc "AC4 --only nosuchgroup still exits 2" 2
assert_contains "AC4 the unknown-section message names the files group" "$OUT" "files"
run bash "$C/evals/run-checks.sh" --only
assert_rc "AC4 --only without a name exits 2" 2
assert_contains "AC4 the usage text names the files group" "$OUT" "files"

echo "v0.23.0 review: executable bits (git mode 100755) of every script"
# Guard: every tracked file under scripts/, tools/ and evals/ whose first line is a #! line, plus tests/*.sh and install.sh,
# is stored with mode 100755. A commit that rewrites a script as 100644 breaks `bash x` nowhere but `./x` and the CI wrappers.
if git -C "$PB_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  BADMODE=""
  LSF="$(git -C "$PB_ROOT" ls-files -s -- scripts tools evals tests install.sh)"
  while read -r mode _ _ path; do
    case "$path" in
      scripts/*|tools/*|evals/*) first=""; IFS= read -r first < "$PB_ROOT/$path" 2>/dev/null; case "$first" in "#!"*) ;; *) continue ;; esac ;;
      tests/*.sh|install.sh) ;;
      *) continue ;;
    esac
    [ "$mode" = 100755 ] || BADMODE="$BADMODE $path($mode)"
  done <<EOF
$LSF
EOF
  assert_eq "every script is stored with git mode 100755" "" "$BADMODE"
else
  t_skip 1 "executable-bit guard needs a git checkout"
fi


# ---- v0.23.2 AC6: the exec-bit guard has its own fixture test ----
# Interface chosen for the guard: `evals/run-checks.sh --only modes`. It runs inside the repository that holds the script
# (run-checks.sh already does cd to its own repo root), reads the INDEX modes with `git ls-files -s` (never [ -x ]), and
# prints "FAIL ... <path>" lines plus exit 1 for every tracked script stored with a mode other than 100755: a file under
# scripts/, tools/ or evals/ whose first line is a #! line, or tests/*.sh, or install.sh. Nothing else is read, so the
# fixture repositories below hold only run-checks.sh and a few scripts.
echo "v0.23.2 AC6.1 exec guard: evals/run-checks.sh --only modes on fixture repositories"
G3="git -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false -c core.autocrlf=false"
# mk_modes_repo -> sets MR: a repo with run-checks.sh and one script per guarded place, all stored at 100755
mk_modes_repo() {
  MR="$(mk_tmp)"
  mkdir -p "$MR/evals" "$MR/scripts" "$MR/tools" "$MR/tests"
  cp "$PB_ROOT/evals/run-checks.sh" "$MR/evals/run-checks.sh"
  printf '#!/usr/bin/env bash\necho a\n' > "$MR/scripts/a.sh"
  printf '#!/usr/bin/env bash\necho b\n' > "$MR/tools/b.sh"
  printf '#!/usr/bin/env bash\necho c\n' > "$MR/evals/c.sh"
  printf '#!/usr/bin/env bash\necho t\n' > "$MR/tests/t.sh"
  printf '#!/usr/bin/env bash\necho i\n' > "$MR/install.sh"
  printf 'plain data, no shebang\n' > "$MR/scripts/data.txt"
  ( cd "$MR" && $G3 init -q && $G3 add -A && $G3 update-index --chmod=+x evals/run-checks.sh scripts/a.sh tools/b.sh evals/c.sh tests/t.sh install.sh &&
    $G3 commit -q -m base ) >/dev/null 2>&1
}
# modes_run DIR -> OUT, RC of the guard in that repository
modes_run() { run_in "$1" bash evals/run-checks.sh --only modes; }
# stage_mode DIR MODE PATH -> change the INDEX mode of a path (+x or -x) and commit nothing
stage_mode() { ( cd "$1" && $G3 update-index "--chmod=$2" "$3" ) >/dev/null 2>&1; }

# corpus first: the all-100755 repository passes
mk_modes_repo
modes_run "$MR"
assert_rc "AC6.1 all scripts at 100755: the guard exits 0" 0
assert_not_contains "AC6.1 all scripts at 100755: no FAIL line" "$OUT" "FAIL"
assert_eq "AC6.1 precondition: the fixture really stores run-checks.sh at 100755" "100755" "$(cd "$MR" && git ls-files -s evals/run-checks.sh | cut -d' ' -f1)"

# a 100644 #! script is reported by path
mk_modes_repo; stage_mode "$MR" -x scripts/a.sh
assert_eq "AC6.1 precondition: scripts/a.sh is staged at 100644" "100644" "$(cd "$MR" && git ls-files -s scripts/a.sh | cut -d' ' -f1)"
modes_run "$MR"
assert_rc "AC6.1 a 100644 #! script under scripts/: exit 1" 1
assert_contains "AC6.1 a 100644 #! script under scripts/: the path is reported" "$OUT" "scripts/a.sh"
assert_not_contains "AC6.1 only the offending path is reported (tools/b.sh is fine)" "$OUT" "tools/b.sh"
assert_contains "AC6.1 the output says FAIL" "$OUT" "FAIL"
for p in tools/b.sh evals/c.sh tests/t.sh install.sh; do
  mk_modes_repo; stage_mode "$MR" -x "$p"; modes_run "$MR"
  assert_rc "AC6.1 [$p] at 100644: exit 1" 1
  assert_contains "AC6.1 [$p] at 100644: the path is reported" "$OUT" "$p"
done
mk_modes_repo; stage_mode "$MR" -x scripts/a.sh; stage_mode "$MR" -x tools/b.sh; modes_run "$MR"
assert_rc "AC6.1 two files at 100644: exit 1" 1
assert_contains "AC6.1 two files at 100644: the first path is reported" "$OUT" "scripts/a.sh"
assert_contains "AC6.1 two files at 100644: the second path is reported" "$OUT" "tools/b.sh"

# a new file added at 100644 (committed, not just staged) is reported too
mk_modes_repo
printf '#!/usr/bin/env bash\necho new\n' > "$MR/scripts/new.sh"
( cd "$MR" && $G3 add scripts/new.sh && $G3 update-index --chmod=-x scripts/new.sh && $G3 commit -q -m new ) >/dev/null 2>&1
modes_run "$MR"
assert_rc "AC6.1 a committed new #! script at 100644: exit 1" 1
assert_contains "AC6.1 a committed new #! script at 100644: the path is reported" "$OUT" "scripts/new.sh"

# a file under scripts/ without a #! first line is data, not a script: not reported
mk_modes_repo
( cd "$MR" && $G3 update-index --chmod=-x scripts/data.txt ) >/dev/null 2>&1
modes_run "$MR"
assert_rc "AC6.1 scripts/data.txt (no #!) at 100644 is not a script: exit 0" 0

# the INDEX mode decides, never the work-tree executable bit
mk_modes_repo; stage_mode "$MR" -x scripts/a.sh; chmod +x "$MR/scripts/a.sh"
modes_run "$MR"
assert_rc "AC6.1 index 100644 but the work tree file is chmod +x: still exit 1" 1
assert_contains "AC6.1 index 100644 but the work tree file is chmod +x: the path is reported" "$OUT" "scripts/a.sh"
mk_modes_repo; chmod -x "$MR/scripts/a.sh" "$MR/tools/b.sh"
modes_run "$MR"
assert_rc "AC6.1 index 100755 but the work tree file lost +x (not staged): exit 0 (the index is what is committed)" 0
assert_not_contains "AC6.1 index 100755 but the work tree file lost +x (not staged): no FAIL line" "$OUT" "FAIL"

# the section name is part of the usage text
run bash "$PB_ROOT/evals/run-checks.sh" --only nosuchgroup
assert_rc "AC6.1 an unknown section still exits 2" 2
assert_contains "AC6.1 the usage text lists the modes group" "$OUT" "modes"

# mutant: a guard that accepts 100644. A `git` shim rewrites the mode column of `git ls-files -s` (100644 -> 100755), which is
# exactly what a guard that accepts 100644 would see. The fixture that must FAIL then passes, so the assertions above (exit 1,
# path reported) are able to tell the mutant from the real guard.
REALGIT="$(command -v git)"
SHIM="$(mk_tmp)"
printf '#!/bin/sh\ncase " $* " in\n  *" ls-files "*) "%s" "$@" | sed "s/^100644/100755/" ;;\n  *) exec "%s" "$@" ;;\nesac\n' "$REALGIT" "$REALGIT" > "$SHIM/git"
chmod +x "$SHIM/git"
mk_modes_repo; stage_mode "$MR" -x scripts/a.sh
OUT="$(cd "$MR" && PATH="$SHIM:$PATH" bash evals/run-checks.sh --only modes 2>&1)"; RC=$?
assert_eq "AC6.1 mutant (accepts 100644): the 100644 fixture is NOT reported, so the exit-1 assertion above kills it" "0" "$RC"
assert_not_contains "AC6.1 mutant (accepts 100644): the offending path is not reported, so the path assertion above kills it" "$OUT" "scripts/a.sh"

# the real checkout passes the guard (modes are read from its index; the work tree is not looked at)
if git -C "$PB_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  run bash "$PB_ROOT/evals/run-checks.sh" --only modes
  assert_rc "AC6.1 the real checkout passes evals/run-checks.sh --only modes" 0
else
  t_skip 1 "AC6.1 the real-checkout guard run needs a git checkout"
fi

t_summary
