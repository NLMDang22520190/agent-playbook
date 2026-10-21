#!/usr/bin/env bash
# Shared setup of tests/test-tdd-step.sh, tests/test-tdd-step-b.sh and tests/test-tdd-step-c.sh (split in v0.24.21 so that none of them is the floor of a CI shard):
# STEP, the temporary PLAYBOOK_HOME and the helpers (head_of, count_of, subject, fresh, lower, assert_untouched, GATE, committed, bstate, dirty, snap, can_name,
# noeol_ls, can_nl, can_exec). Source it after lib.sh. It is not a suite: run-all.sh only starts tests/test-*.sh.
STEP="$PB_ROOT/scripts/tdd-step.sh"
export PLAYBOOK_HOME="$(mk_tmp)"

head_of()  { git -C "$1" rev-parse HEAD; }
count_of() { git -C "$1" rev-list --count HEAD; }
subject()  { git -C "$1" log -1 --format=%s; }
fresh()    { local d; d="$(mk_tmp)"; mk_repo "$d"; printf '%s\n' "$d"; }
lower()    { printf '%s' "$1" | tr 'A-Z' 'a-z'; }
# assert_untouched NAME REPO HEAD COUNT -> nothing was committed
assert_untouched() {
  assert_eq "$1: HEAD unchanged" "$3" "$(head_of "$2")"
  assert_eq "$1: commit count unchanged" "$4" "$(count_of "$2")"
}
GATE="$PB_ROOT/scripts/role-gate.sh"
# committed REPO -> the paths of HEAD's commit, one per line (no rename detection: both sides of a rename show up)
committed() { git -C "$1" -c core.quotepath=off diff-tree -r --root --no-commit-id --name-only -z HEAD | tr '\0' '\n'; }
# bstate REPO -> index entries, diffs and contents of the two baseline paths (README.md src/app.js)
bstate() { ( cd "$1" && git ls-files -s -- README.md src/app.js; git diff -- README.md src/app.js; git diff --cached -- README.md src/app.js; cat README.md src/app.js ); }
# dirty REPO -> pre-existing changes: README.md staged then edited again (MM), src/app.js edited (unstaged)
dirty() {
  ( cd "$1" && printf 'staged edit\n' >> README.md && git add README.md && printf 'later edit\n' >> README.md \
    && printf 'module.exports = 9;\n' > src/app.js )
}
# snap REPO -> prints the path of a baseline manifest recorded now (outside the work tree)
snap() { local f; f="$(mk_tmp)/baseline.txt"; ( cd "$1" && bash "$GATE" snapshot --out "$f" >/dev/null 2>&1 ); printf '%s\n' "$f"; }
# can_name NAME -> 0 when the file system stores a file with that exact name AND git lists it back byte for byte (NTFS drops or maps TAB, control, newline, : and *)
can_name() { local d lf; d="$(mk_tmp)"; lf="$(mk_tmp)/lsout"; git -C "$d" init -q 2>/dev/null || return 1; { : > "$d/$1"; } 2>/dev/null || return 1; git -C "$d" ls-files --others -z > "$lf" 2>/dev/null && printf '%s\0' "$1" | cmp -s - "$lf"; }
noeol_ls() { git -C "$1" -c core.quotepath=off ls-tree -r --name-only -z HEAD | tr '\0' '\n'; }
# can_nl -> 0 when a file name holding a newline is stored and listed back unchanged
can_nl() { can_name "a"$'\n'"b"; }
# can_exec -> 0 when a file made executable here really runs (NTFS mounts refuse the mode)
can_exec() { local d f; d="$(mk_tmp)"; f="$d/h.sh"; printf '#!/bin/sh\nexit 0\n' > "$f"; chmod +x "$f" 2>/dev/null; [ -x "$f" ] && "$f" 2>/dev/null; }
