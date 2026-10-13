#!/usr/bin/env bash
# Shared setup of tests/test-run-checks.sh and its split parts (test-run-checks-gnu.sh, test-run-checks-gnu9.sh, test-run-checks-sections.sh): the copy of the
# working tree that every case mutates, and the helpers that run evals/run-checks.sh inside such a copy.
# Source it after lib.sh. It is not a suite: run-all.sh only starts tests/test-*.sh.
SKILL=skills/playbook-proof/SKILL.md

# The tree is read once into MASTER (tracked + untracked, non-ignored files); every mk_copy is a plain
# `cp -a` of it, so the file list and the tar pipeline are not repeated for each of the ~50 cases.
MASTER="$(mk_tmp)"
( cd "$PB_ROOT" &&
  git ls-files -co --exclude-standard | while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done |
  tar -cf - -T - ) | ( cd "$MASTER" && tar -xf - )
# mk_copy -> prints a temp dir holding a copy of the working tree
mk_copy() {
  local d; d="$(mk_tmp)"
  cp -a "$MASTER/." "$d/"
  printf '%s\n' "$d"
}
# mk_min_copy -> prints a temp dir for the cases whose findings come only from their own fixture file and that run a section
# reading nothing but the shell-script globs (dupmax, sed, gnu, soh: tests/*.sh evals/*.sh scripts/*.sh tools/*.sh install.sh).
# It holds evals/run-checks.sh (the working-tree copy) and one stub .sh file per glob, so every glob matches (the nofiles
# checks stay quiet) and the stubs carry no findings. The scanners reset their state per file (FNR == 1), so a finding does not
# depend on the other files: scanning the 80 files of the whole tree for each case was 98% of a case's time. A case that
# asserts something about the real tree (the real tree passes, equivalence over every *.sh, a section that reads skills/ or
# evals/scenarios.md) keeps mk_copy. A new glob in a scanned section needs a stub here.
MINMASTER="$(mk_tmp)"
mkdir -p "$MINMASTER/evals" "$MINMASTER/tests" "$MINMASTER/scripts" "$MINMASTER/tools"
cp "$MASTER/evals/run-checks.sh" "$MINMASTER/evals/run-checks.sh"
for stub in tests/stub.sh scripts/stub.sh tools/stub.sh install.sh; do
  printf '#!/usr/bin/env bash\n# stub: keeps its glob non-empty, holds no finding\n' > "$MINMASTER/$stub"
  chmod +x "$MINMASTER/$stub"
done
mk_min_copy() {
  local d; d="$(mk_tmp)"
  cp -a "$MINMASTER/." "$d/"
  printf '%s\n' "$d"
}
# set_line DIR KEY LINE -> replace the first "KEY:" line of the frontmatter of $SKILL with LINE
set_line() {
  awk -v k="$2:" -v l="$3" 'NR<=10 && !done && index($0, k) == 1 { print l; done = 1; next } { print }' \
    "$1/$SKILL" > "$1/$SKILL.new" && mv "$1/$SKILL.new" "$1/$SKILL"
}
# add_line DIR LINE -> insert LINE as the second frontmatter line of $SKILL
add_line() {
  awk -v l="$2" 'NR == 2 { print l } { print }' "$1/$SKILL" > "$1/$SKILL.new" && mv "$1/$SKILL.new" "$1/$SKILL"
}
# checks DIR -> run run-checks.sh in DIR; OUT keeps only non-"ok" lines (FAIL, skip, summary) to keep failures readable
only_problems() { OUT="$(printf '%s\n' "$OUT" | grep -v '^  ok ')"; }
# checks DIR [SECTION] -> with SECTION only that check group runs (run-checks.sh --only SECTION): a sandbox case for one
# rule does not need the other groups (shellcheck, frontmatter, ...), which dominate the time on Windows
checks() { if [ -n "${2:-}" ]; then run bash "$1/evals/run-checks.sh" --only "$2"; else run bash "$1/evals/run-checks.sh"; fi; only_problems; }
# mk_gmaster -> builds GMASTER: a copy of the working tree committed into a fresh git repo with LF in the index (with .git).
# Only the suites that call mk_git_copy call it (it costs a git init and a commit of the whole tree).
mk_gmaster() {
  GMASTER="$(mk_tmp)"
  cp -a "$MASTER/." "$GMASTER/"
  ( cd "$GMASTER" && git init -q && git config core.autocrlf false && git config user.email t@example.invalid &&
    git config user.name tester && git config commit.gpgsign false && git add -A && git commit -q -m copy ) >/dev/null 2>&1
}
# mk_git_copy -> a copy of GMASTER (after mk_gmaster) committed into a fresh git repo with LF in the index
mk_git_copy() {
  local d; d="$(mk_tmp)"
  cp -a "$GMASTER/." "$d/"
  printf '%s\n' "$d"
}
to_crlf() { sed 's/$/\r/' "$1" > "$1.crlf" && mv "$1.crlf" "$1"; }
