#!/usr/bin/env bash
# Tests for tools/pre-commit and tools/install-hooks.sh (v0.24.30 H): the opt-in git hook that refuses a commit storing a
# script as git mode 100644 (the rule of evals/run-checks.sh --only modes), and its installer.
# Everything runs in temp repositories; the real repository's hooks are never touched.
. "$(dirname "$0")/lib.sh"
HOOK="$PB_ROOT/tools/pre-commit"
INST="$PB_ROOT/tools/install-hooks.sh"
G="git -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false -c core.autocrlf=false"

assert_file "H hook exists" "$HOOK"
assert_file "H installer exists" "$INST"
[ -x "$HOOK" ] && t_ok "H hook is executable in the work tree" || t_bad "H hook is executable in the work tree"
[ -x "$INST" ] && t_ok "H installer is executable in the work tree" || t_bad "H installer is executable in the work tree"

# mk_repo [filemode] -> sets R: repo with the real run-checks.sh, hook and installer copied in, a baseline commit, no hook installed
mk_repo() {
  R="$(mk_tmp)"
  mkdir -p "$R/evals" "$R/scripts" "$R/tools" "$R/tests" "$R/docs"
  cp "$PB_ROOT/evals/run-checks.sh" "$R/evals/run-checks.sh"
  [ -f "$HOOK" ] && cp "$HOOK" "$R/tools/pre-commit"
  [ -f "$INST" ] && cp "$INST" "$R/tools/install-hooks.sh"
  printf '#!/usr/bin/env bash\necho a\n' > "$R/scripts/a.sh"
  printf 'readme\n' > "$R/README.md"
  ( cd "$R" && $G init -q && { [ "${1:-}" = nofilemode ] && $G config core.filemode false; true; } && $G add -A ) >/dev/null 2>&1
  ( cd "$R" && $G update-index --chmod=+x evals/run-checks.sh scripts/a.sh &&
    { [ ! -f tools/pre-commit ] || $G update-index --chmod=+x tools/pre-commit; } &&
    { [ ! -f tools/install-hooks.sh ] || $G update-index --chmod=+x tools/install-hooks.sh; } &&
    $G commit -q -m base ) >/dev/null 2>&1
}
# install_hook DIR -> installs through the installer of that repo
install_hook() { run_in "$1" bash tools/install-hooks.sh; }
# stage DIR PATH CONTENT MODE -> write, add, force the index mode (+x or -x)
stage() {
  mkdir -p "$(dirname "$1/$2")"
  printf '%s\n' "$3" > "$1/$2"
  ( cd "$1" && $G add "$2" && $G update-index "--chmod=$4" "$2" ) >/dev/null 2>&1
}
commit_in() { run_in "$1" $G commit -m "$2"; }
SHEB='#!/usr/bin/env bash'

echo "refuses a script staged as 100644"
mk_repo; install_hook "$R"
assert_rc "H the installer succeeds" 0
stage "$R" scripts/new.sh "$SHEB" -x
head0="$(git -C "$R" rev-parse HEAD)"
commit_in "$R" "bad"
assert_rc "H a new #! script staged 100644: the commit is refused (exit 1)" 1
assert_contains "H the path is named" "$OUT" "scripts/new.sh"
assert_contains "H the fix with update-index is named" "$OUT" "git update-index --chmod=+x scripts/new.sh"
assert_contains "H the fix with chmod and add is named" "$OUT" "chmod +x scripts/new.sh && git add scripts/new.sh"
assert_eq "H no commit was made" "$head0" "$(git -C "$R" rev-parse HEAD)"
assert_not_contains "H the already-correct script is not named" "$OUT" "scripts/a.sh"

echo "an existing script whose mode is dropped"
mk_repo; install_hook "$R"
printf '%s\n' "$SHEB" 'echo changed' > "$R/scripts/a.sh"
( cd "$R" && $G add scripts/a.sh && $G update-index --chmod=-x scripts/a.sh ) >/dev/null 2>&1
commit_in "$R" "dropped"
assert_rc "H 100755 -> 100644 on a modified script: refused" 1
assert_contains "H the dropped script is named" "$OUT" "scripts/a.sh"

echo "passes"
mk_repo; install_hook "$R"
stage "$R" scripts/ok.sh "$SHEB" +x
commit_in "$R" "good"
assert_rc "H a script staged 100755: the commit goes through" 0
mk_repo; install_hook "$R"
printf 'more\n' >> "$R/README.md"; ( cd "$R" && $G add README.md ) >/dev/null 2>&1
commit_in "$R" "docs"
assert_rc "H a commit that touches no script passes" 0
mk_repo; install_hook "$R"
stage "$R" scripts/data.txt "plain data" -x
stage "$R" scripts/nosheb.sh "echo no shebang" -x
stage "$R" docs/free.sh "$SHEB" -x
commit_in "$R" "unguarded"
assert_rc "H files the rule does not guard (no #! under scripts/, a .sh under docs/) pass" 0

echo "core.filemode=false"
mk_repo nofilemode; install_hook "$R"
printf '%s\n' "$SHEB" > "$R/scripts/fm.sh"; chmod +x "$R/scripts/fm.sh"
( cd "$R" && $G add scripts/fm.sh && $G update-index --chmod=-x scripts/fm.sh ) >/dev/null 2>&1
commit_in "$R" "fm"
assert_rc "H filemode=false, work tree +x but index 100644: refused (the index decides)" 1
assert_contains "H filemode=false: the path is named" "$OUT" "scripts/fm.sh"
( cd "$R" && $G update-index --chmod=+x scripts/fm.sh ) >/dev/null 2>&1
commit_in "$R" "fm2"
assert_rc "H filemode=false, index 100755: passes" 0

echo "every bad path is named"
mk_repo; install_hook "$R"
stage "$R" scripts/b1.sh "$SHEB" -x
stage "$R" tools/b2.sh "$SHEB" -x
stage "$R" evals/b3.sh "$SHEB" -x
stage "$R" tests/test-b4.sh "$SHEB" -x
stage "$R" install.sh "$SHEB" -x
stage "$R" scripts/fine.sh "$SHEB" +x
commit_in "$R" "many"
assert_rc "H five bad scripts: refused" 1
for p in scripts/b1.sh tools/b2.sh evals/b3.sh tests/test-b4.sh install.sh; do
  assert_contains "H names $p" "$OUT" "git update-index --chmod=+x $p"
done
assert_not_contains "H does not name the good script" "$OUT" "scripts/fine.sh"

echo "agreement with evals/run-checks.sh --only modes"
mk_repo
stage "$R" scripts/x1.sh "$SHEB" -x
stage "$R" tools/x2.sh "$SHEB" -x
stage "$R" tests/test-x3.sh "$SHEB" -x
stage "$R" install.sh "$SHEB" -x
stage "$R" scripts/x4.txt "data" -x
stage "$R" scripts/x5.sh "no shebang" -x
stage "$R" docs/x6.sh "$SHEB" -x
stage "$R" evals/x7.sh "$SHEB" +x
run_in "$R" bash evals/run-checks.sh --only modes
rc_paths="$(printf '%s\n' "$OUT" | sed -n 's/^  FAIL .*: //p' | sort | tr '\n' ' ')"
assert_eq "H run-checks flags exactly the four guarded 100644 scripts" "install.sh scripts/x1.sh tests/test-x3.sh tools/x2.sh " "$rc_paths"
install_hook "$R"
run_in "$R" bash tools/pre-commit
assert_rc "H the hook run by hand on the same tree: exit 1" 1
hk_paths="$(printf '%s\n' "$OUT" | sed -n 's/^ *fix: git update-index --chmod=+x //p' | sort | tr '\n' ' ')"
assert_eq "H the hook names the same paths as run-checks" "$rc_paths" "$hk_paths"

echo "speed and side effects"
mk_repo; install_hook "$R"
stage "$R" scripts/s.sh "$SHEB" -x
before="$( cd "$R" && { git status --porcelain; git ls-files -s; cksum < .git/index; } 2>&1)"
t0="$(date +%s)"
run_in "$R" bash tools/pre-commit
t1="$(date +%s)"
after="$( cd "$R" && { git status --porcelain; git ls-files -s; cksum < .git/index; } 2>&1)"
assert_eq "H the hook changes nothing (status, index modes, index checksum)" "$before" "$after"
[ $((t1 - t0)) -le 3 ] && t_ok "H the hook finishes quickly ($((t1 - t0)) s, bound 3 s on a shared host)" || t_bad "H the hook finishes quickly" "$((t1 - t0)) s"

echo "a repo without evals/run-checks.sh: the hook does not block"
mk_repo; install_hook "$R"
( cd "$R" && $G rm -q -f --cached evals/run-checks.sh && rm -f evals/run-checks.sh ) >/dev/null 2>&1
stage "$R" scripts/n.sh "$SHEB" -x
commit_in "$R" "norc"
assert_rc "H no run-checks.sh: the hook warns and lets the commit through" 0

echo "installer"
mk_repo
HD="$R/.git/hooks"
run_in "$R" bash tools/install-hooks.sh
assert_rc "H install: exit 0" 0
assert_file "H install: hooks/pre-commit exists" "$HD/pre-commit"
[ -x "$HD/pre-commit" ] && t_ok "H install: the hook is executable" || t_bad "H install: the hook is executable"
assert_eq "H install: the installed hook is the tools/pre-commit text" "$(cksum < "$R/tools/pre-commit")" "$(cksum < "$HD/pre-commit")"
run_in "$R" bash tools/install-hooks.sh
assert_rc "H install twice: exit 0 (already installed)" 0
run_in "$R" bash tools/install-hooks.sh --uninstall
assert_rc "H uninstall: exit 0" 0
assert_no_path "H uninstall: the hook is gone" "$HD/pre-commit"
run_in "$R" bash tools/install-hooks.sh --uninstall
assert_rc "H uninstall when nothing is installed: exit 0" 0

mk_repo
HD="$R/.git/hooks"; mkdir -p "$HD"
printf '#!/bin/sh\necho mine\n' > "$HD/pre-commit"; chmod +x "$HD/pre-commit"
mine="$(cksum < "$HD/pre-commit")"
run_in "$R" bash tools/install-hooks.sh
assert_rc "H a different existing pre-commit: install refuses (exit 1)" 1
assert_contains "H the refusal names --force" "$OUT" "--force"
assert_eq "H the foreign hook is untouched" "$mine" "$(cksum < "$HD/pre-commit")"
run_in "$R" bash tools/install-hooks.sh --uninstall
assert_rc "H uninstall refuses a hook it did not install (exit 1)" 1
assert_eq "H uninstall left the foreign hook alone" "$mine" "$(cksum < "$HD/pre-commit")"
run_in "$R" bash tools/install-hooks.sh --force
assert_rc "H --force replaces it: exit 0" 0
assert_eq "H --force: now the playbook hook" "$(cksum < "$R/tools/pre-commit")" "$(cksum < "$HD/pre-commit")"
run_in "$R" bash tools/install-hooks.sh --bogus
assert_rc "H an unknown option: exit 2" 2

echo "coexistence with the leak-check hook (the leak guard has priority)"
LC="$PB_ROOT/scripts/leak-check.sh"
mk_repo
HD="$R/.git/hooks"
run_in "$R" bash "$LC" install-hooks --repo "$R"
assert_rc "H leak-check install-hooks first: exit 0" 0
lk="$(cksum < "$HD/pre-commit")"
run_in "$R" bash tools/install-hooks.sh
assert_rc "H install over a leak-check hook: refused (exit 1)" 1
# the path as tools/install-hooks.sh resolves it: `git rev-parse --git-path hooks` in the physical checkout root (pwd -P), made
# absolute; it differs from $HD where TMPDIR is a symlink (macOS /var -> /private/var) or a mount (Git Bash /tmp -> /c/...)
ihr="$(cd "$R" && pwd -P)"; ihh="$(cd "$R" && git rev-parse --git-path hooks)"
case "$ihh" in /* | [A-Za-z]:*) IHD="$ihh" ;; *) IHD="$ihr/$ihh" ;; esac
# the resolved path must name the hook the test made; else the expected text says so and the row fails
[ "$IHD/pre-commit" -ef "$HD/pre-commit" ] || IHD="(resolved [$IHD] is not $HD)"
assert_eq "H install message is exact" "install-hooks: $IHD/pre-commit is a leak-check hook (agent-playbook leak guard); not replaced, with or without --force. Run the exec-bit check by hand: bash evals/run-checks.sh --only modes" "$OUT"
assert_eq "H the leak-check hook is byte for byte unchanged" "$lk" "$(cksum < "$HD/pre-commit")"
run_in "$R" bash tools/install-hooks.sh --force
assert_rc "H --force over a leak-check hook: still refused (exit 1)" 1
assert_contains "H --force refusal names the leak guard" "$OUT" "is a leak-check hook"
assert_eq "H --force: the leak-check hook is byte for byte unchanged" "$lk" "$(cksum < "$HD/pre-commit")"
run_in "$R" bash tools/install-hooks.sh --uninstall
assert_rc "H --uninstall on a leak-check hook: refused (exit 1)" 1
assert_eq "H --uninstall leaves the leak-check hook untouched" "$lk" "$(cksum < "$HD/pre-commit")"
run_in "$R" bash "$LC" uninstall-hooks --repo "$R"
assert_no_path "H leak-check uninstall-hooks still removes its own hook" "$HD/pre-commit"

mk_repo
HD="$R/.git/hooks"
run_in "$R" bash tools/install-hooks.sh
ours="$(cksum < "$HD/pre-commit")"
run_in "$R" bash "$LC" install-hooks --repo "$R"
assert_rc "H ours installed first, then leak-check install-hooks: it leaves pre-commit alone (exit 1)" 1
assert_contains "H leak-check says it left pre-commit alone" "$OUT" "pre-commit already exists and is not a leak-check hook; left alone"
assert_eq "H our hook is unchanged" "$ours" "$(cksum < "$HD/pre-commit")"

echo "installer in a linked worktree"
mk_repo
WT="$(mk_tmp)/wt"
( cd "$R" && $G worktree add -q "$WT" -b wtb ) >/dev/null 2>&1
run_in "$WT" bash tools/install-hooks.sh
assert_rc "H install from a linked worktree: exit 0" 0
assert_file "H the hook lands in the shared hooks dir of the main repo" "$R/.git/hooks/pre-commit"
stage "$WT" scripts/w.sh "$SHEB" -x
commit_in "$WT" "wt"
assert_rc "H the hook also guards commits made in the worktree" 1

echo "documentation"
RD="$(cat "$PB_ROOT/README.md")"
assert_contains "H README names tools/install-hooks.sh" "$RD" "tools/install-hooks.sh"
assert_contains "H README says it is opt-in" "$RD" "opt-in"
assert_contains "H README: the leak guard takes priority" "$RD" "leak guard takes priority"
assert_contains "H README: manual mode check" "$RD" "evals/run-checks.sh --only modes"

t_summary
