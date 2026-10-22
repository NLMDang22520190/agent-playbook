#!/usr/bin/env bash
# Tests for scripts/tdd-step.sh (v0.24.23 lane A, Full, code review round 1 fixes), part 9 of 10 (the new parts: test-tdd-step-n.sh, -o.sh, -p.sh; spec 01-spec.md):
#   F2  print mode (--baseline without --commit) is byte-identical to v0.24.22 (aeeb809, from git archive) in output and exit code, and leaves the object store unchanged:
#       a plain repo; core.autocrlf=true (no extra warning line; the warnings are NOT dropped from the comparison); core.autocrlf=true with core.safecrlf=true (v0.24.22
#       exits 0, no "git add failed"); an untracked nested repository (no "embedded git repository" hint)
# Shared setup: tdd-step-fixture.sh, tdd-step-d-fixture.sh, tdd-step-g-fixture.sh and tdd-step-n-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/tdd-step-fixture.sh"
. "$(dirname "$0")/tdd-step-d-fixture.sh"
. "$(dirname "$0")/tdd-step-g-fixture.sh"
. "$(dirname "$0")/tdd-step-n-fixture.sh"

# OLDDIR -> a dir holding scripts/ of v0.24.22 (aeeb809); empty when that commit is not in this clone (a shallow clone, or no git archive)
OLDDIR=""; _o="$(mk_tmp)"
if git -C "$PB_ROOT" cat-file -e aeeb809 2>/dev/null && git -C "$PB_ROOT" archive aeeb809 scripts 2>/dev/null | tar -x -C "$_o" 2>/dev/null && [ -f "$_o/scripts/tdd-step.sh" ]; then OLDDIR="$_o"; fi

# ---------------------------------------------------------------------------------------------------------------
echo "F2 print mode (--baseline without --commit) is what v0.24.22 printed, and writes no object (old scripts from git archive aeeb809)"
if [ -n "$OLDDIR" ]; then
  norm() { printf '%s' "$1" | sed -E "s/[0-9]{8}T[0-9]{6}Z/<ts>/g; s/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z/<time>/g"; }
  # objl REPO -> every loose object file, sorted (the object store as a list)
  objl() { ( cd "$1" && find .git/objects -type f | LC_ALL=C sort ); }
  # pm_case LABEL KIND -> 10 assertions. KIND plain | crlf | safecrlf | nested. Repo a runs the v0.24.22 script, repo b this one, both in print mode with a baseline
  # (README.md staged then edited again, src/app.js edited, tests/n.test.js new); fixed commit dates make equal runs give equal shas. The output is compared whole (the git
  # LF/CRLF warning lines are NOT dropped), after the temp paths and the times are replaced.
  pm_case() {
    local label="$1" kind="$2" a b ba bb oa ob ra rb r a0 b0
    export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"
    a="$(fresh)"; b="$(fresh)"
    for r in "$a" "$b"; do dirty "$r"; done
    ba="$(snap "$a")"; bb="$(snap "$b")"
    for r in "$a" "$b"; do
      printf 'test("n", () => {});\n' > "$r/tests/n.test.js"
      case "$kind" in
        crlf)     ( cd "$r" && git config core.autocrlf true ) ;;
        safecrlf) ( cd "$r" && git config core.autocrlf true && git config core.safecrlf true ) ;;
        nested)   mkdir -p "$r/tests/sub" && ( cd "$r/tests/sub" && git init -q && git config user.email t@example.invalid && git config user.name tester \
                    && git config commit.gpgsign false && printf 'a\n' > a && git add a && git commit -q -m s ) ;;
      esac
      # settle the fixture: every mtime clearly in the past, then refresh the index, so that no entry is racy (git would warn again about a racy entry)
      ( cd "$r" && find . -path ./.git -prune -o -path ./tests/sub -prune -o -type f -exec touch -t 202001010000 {} + && { git update-index --refresh >/dev/null 2>&1 || true; } )
    done
    a0="$(objl "$a")"; b0="$(objl "$b")"
    run_in "$a" bash "$OLDDIR/scripts/tdd-step.sh" red --message "m" --baseline "$ba" -- sh -c "exit 1"; oa="$OUT"; ra="$RC"
    run_in "$b" bash "$STEP" red --message "m" --baseline "$bb" -- sh -c "exit 1"; ob="$OUT"; rb="$RC"
    unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE
    oa="$(repl_path "$oa" "<R>" "$a")"; ob="$(repl_path "$ob" "<R>" "$b")"
    oa="$(repl_path "$oa" "<BL>" "$ba")"; ob="$(repl_path "$ob" "<BL>" "$bb")"
    assert_eq "$label: the old script passes (exit 0; the fixture works)" "0" "$ra"
    assert_eq "$label: the old script leaves the object store as it was (the check measures something)" "$a0" "$(objl "$a")"
    assert_eq "$label: same exit code" "$ra" "$rb"
    assert_eq "$label: byte-identical output (warnings included)" "$(norm "$oa")" "$(norm "$ob")"
    assert_eq "$label: the object store is unchanged (no blob is written)" "$b0" "$(objl "$b")"
    assert_contains "$label: prints the commit commands" "$ob" "not committing (no --commit)"
    assert_not_contains "$label: no git add failure" "$ob" "git add failed"
    assert_eq "$label: HEAD unchanged" "$(head_of "$a")" "$(head_of "$b")"
    case "$kind" in
      crlf)   assert_not_contains "$label: no warning about tests/n.test.js (the new file the scratch git add would touch)" "$ob" "working copy of 'tests/n.test.js'" ;;
      nested) assert_not_contains "$label: no embedded git repository hint" "$ob" "embedded git repository" ;;
      *)      assert_not_contains "$label: no fatal line" "$ob" "fatal:" ;;
    esac
    assert_eq "$label: the number of warning and hint lines is the old script's" "$(printf '%s\n' "$oa" | grep -c -E '^(warning|hint|fatal):')" "$(printf '%s\n' "$ob" | grep -c -E '^(warning|hint|fatal):')"
  }
  pm_case "F2 plain repo" plain
  pm_case "F2 core.autocrlf=true" crlf
  pm_case "F2 core.autocrlf=true and core.safecrlf=true" safecrlf
  # AC6 (v0.24.24 lane A, slice S2, spec 01-spec.md AC5): the untracked nested repository case was byte-identical to v0.24.22; since v0.24.24 it is REFUSED (exit 1) before the
  # test command, on --baseline in print mode too. The old script (exit 0) shows the fixture works. Changed on purpose, AC6 names this row.
  pm_refuse() {
    local label="$1" a b ba bb oa ra ob rb r b0 lo bh0
    a="$(fresh)"; b="$(fresh)"
    for r in "$a" "$b"; do dirty "$r"; done
    ba="$(snap "$a")"; bb="$(snap "$b")"
    for r in "$a" "$b"; do
      printf 'test("n", () => {});
' > "$r/tests/n.test.js"
      mkdir -p "$r/tests/sub" && ( cd "$r/tests/sub" && git init -q && git config user.email t@example.invalid && git config user.name tester         && git config commit.gpgsign false && printf 'a
' > a && git add a && git commit -q -m s )
    done
    # HEAD is compared with the same repo before the run, not with the other repo: two fresh repos get commit times a second apart under load, so their shas differ.
    bh0="$(head_of "$b")"
    b0="$(objl "$b")"
    run_in "$a" bash "$OLDDIR/scripts/tdd-step.sh" red --message "m" --baseline "$ba" -- sh -c "exit 1"; oa="$OUT"; ra="$RC"
    run_in "$b" bash "$STEP" red --message "m" --baseline "$bb" -- sh -c "exit 1"; ob="$OUT"; rb="$RC"
    lo="$(lower "$ob")"
    assert_eq "$label: the old script passes (exit 0; the fixture works)" "0" "$ra"
    assert_eq "$label: refused (exit 1)" "1" "$rb"
    assert_contains "$label: says nested repository" "$lo" "nested repository"
    assert_contains "$label: names tests/sub" "$lo" "tests/sub"
    assert_contains "$label: hints at .git/info/exclude" "$lo" ".git/info/exclude"
    assert_contains "$label: says nothing committed" "$lo" "nothing committed"
    assert_not_contains "$label: does not print the commit commands" "$lo" "not committing (no --commit)"
    assert_eq "$label: the object store is unchanged" "$b0" "$(objl "$b")"
    assert_eq "$label: HEAD unchanged" "$bh0" "$(head_of "$b")"
  }
  pm_refuse "F2 untracked nested repository (tests/sub) is refused (AC6)"
else
  t_skip 40 "F2 print mode against v0.24.22 (commit aeeb809 is not in this clone, or git archive is not available)"
fi

t_summary
