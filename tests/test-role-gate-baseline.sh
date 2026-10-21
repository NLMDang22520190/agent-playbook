#!/usr/bin/env bash
# Tests for scripts/role-gate.sh baselines (v0.24.17 item 1, slice S1): `snapshot` and `check ROLE --baseline FILE`
# (AC1-AC5, AC7, AC8, AC10 of .agents/handoff/01-spec.md) and, slice S2, `size --baseline FILE` (AC6). A baseline records the
# work-tree and index state of every changed path before a role starts; the gate then skips only the paths whose state is
# unchanged. Shared setup: role-gate-fixture.sh. Platform probes (symlinks, exec bit, odd names) skip with exact counts.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/role-gate-fixture.sh"
unset PB_ALLOW_MODE_CHANGE
T="$(printf '\t')"

gate() { run env PLAYBOOK_HOME="$IH" bash "$GATE" "$@"; }
hsh() { git hash-object --no-filters -- "$1"; }
idx() { git ls-files -s -- ":(literal)$1" | awk '{print $1 " " $2}'; }
dig() { git hash-object -- "$1" 2>/dev/null || printf 'NODIGEST'; }
# assert_mline NAME MANIFEST EXPECTED-LINE: the manifest has exactly this line (fixed string, whole line)
assert_mline() {
  if grep -Fx -- "$3" "$2" >/dev/null 2>&1; then t_ok "$1"; else t_bad "$1" "no line [$3] in manifest: $(cat "$2" 2>/dev/null | tr '\t' '>')"; fi
}
# blk_check NAME DECLARED DELTA: a skipped block declares how many assertions it holds; a drift is a failure here
blk_check() { if [ "$2" != "$3" ]; then t_bad "$1: the declared skip count ($2) matches the assertions run ($3)" ""; fi; }

# stores_name NAME: 0 when the cwd (a fresh repo plus this one file) lists exactly NAME as its only untracked entry, byte for
# byte (git ls-files --others -z). A file system that maps a TAB or a newline to a substitute character (NTFS) fails this.
stores_name() {
  local lf; lf="$(mk_tmp)/lsout"
  git ls-files --others -z > "$lf" 2>/dev/null || return 1
  printf '%s\0' "$1" | cmp -s - "$lf"
}
# Fixture repos are built once, on the first call, and copied (cp -a) for every case: a case starts from the same bytes without
# running git add/commit (base_repo), the snapshot gate (dirty_*, size_dirty) or the 120-line loop (size_dirty) again.
BASE_TPL=""; DR_TPL=""; DI_TPL=""; SD_TPL=""
# base_repo: cd into a repo with src/mod.js, src/gone.js, src/staged.js, tests/t.test.js and a .gitignore committed (sets R)
base_repo() {
  if [ -z "$BASE_TPL" ]; then
    BASE_TPL="$(mk_tmp)"; mk_repo "$BASE_TPL"
    ( cd "$BASE_TPL" && printf 'one\n' > src/mod.js && printf 'gone\n' > src/gone.js && printf 'st\n' > src/staged.js &&
      printf 'tt\n' > tests/t.test.js && printf 'ignored.log\n' > .gitignore && git add -A && git commit -q -m base ) || exit 3
  fi
  R="$(mk_tmp)"; cp -a "$BASE_TPL/." "$R/"; cd "$R" || exit 3
}
# dirty_reviewer: a modified tracked file, an untracked production file and an untracked notes file, then a snapshot (sets MF, D)
dirty_reviewer() {
  if [ -z "$DR_TPL" ]; then
    base_repo
    printf 'two\n' > src/mod.js; printf 'n\n' > src/new.js; mkdir -p notes; printf 'x\n' > notes/NOTES.md
    DR_MF="$(mk_tmp)/m"; gate snapshot --out "$DR_MF"; DR_D="$(dig "$DR_MF")"; DR_TPL="$R"
  fi
  R="$(mk_tmp)"; cp -a "$DR_TPL/." "$R/"; cd "$R" || exit 3
  MF="$(mk_tmp)/m"; cp "$DR_MF" "$MF"; D="$DR_D"
  NOTE="note: baseline $MF (3 path(s), digest $D): 3 path(s) unchanged, not checked"
}
# dirty_impl: a modified tracked production file and a modified tracked test file, then a snapshot (sets MF, D)
dirty_impl() {
  if [ -z "$DI_TPL" ]; then
    base_repo
    printf 'two\n' > src/mod.js; printf 'tt2\n' > tests/t.test.js
    DI_MF="$(mk_tmp)/m"; gate snapshot --out "$DI_MF"; DI_D="$(dig "$DI_MF")"; DI_TPL="$R"
  fi
  R="$(mk_tmp)"; cp -a "$DI_TPL/." "$R/"; cd "$R" || exit 3
  MF="$(mk_tmp)/m"; cp "$DI_MF" "$MF"; D="$DI_D"
}
cb() { gate check "$@" --baseline "$MF"; }

# ================= AC1 snapshot =================
echo "AC1 snapshot records every path that differs from HEAD (tracked, deleted, staged-only, untracked), not .agents/handoff/ or ignored files"
base_repo
printf 'two\n' > src/mod.js
rm -f src/gone.js
printf 'st2\n' > src/staged.js; git add src/staged.js
printf 'n\n' > src/new.js; mkdir -p notes; printf 'x\n' > notes/n.md
mkdir -p .agents/handoff; printf 'h\n' > .agents/handoff/x.md; printf 'log\n' > ignored.log
SR="$R"
MF="$(mk_tmp)/snap"
gate snapshot --out "$MF"; SRC="$RC"; SOUT="$OUT"
D="$(dig "$MF")"
assert_eq "AC1 snapshot --out exits 0" "0" "$SRC"
assert_eq "AC1 the printed line is exactly: baseline: N path(s) recorded in FILE (digest D)" "baseline: 5 path(s) recorded in $MF (digest $D)" "$SOUT"
assert_eq "AC1 the first manifest line is exactly the header" "# role-gate baseline v1" "$(sed -n 1p "$MF" 2>/dev/null)"
assert_eq "AC1 the manifest is a header plus one line per recorded path (5)" "6" "$(cat "$MF" 2>/dev/null | wc -l | tr -d " ")"
assert_mline "AC1 a modified tracked file: work-tree state, index state (HEAD blob), path" "$MF" "100644 $(hsh src/mod.js)${T}$(idx src/mod.js)${T}src/mod.js"
assert_mline "AC1 a deleted tracked file: absent work-tree state, index state kept" "$MF" "absent${T}$(idx src/gone.js)${T}src/gone.js"
assert_mline "AC1 a staged-only change: work tree and index state both the new blob" "$MF" "100644 $(hsh src/staged.js)${T}$(idx src/staged.js)${T}src/staged.js"
assert_mline "AC1 an untracked file: index state none" "$MF" "100644 $(hsh src/new.js)${T}none${T}src/new.js"
assert_mline "AC1 an untracked file in a new directory is recorded by its path" "$MF" "100644 $(hsh notes/n.md)${T}none${T}notes/n.md"
assert_eq "AC1 nothing under .agents/handoff/ is recorded" "0" "$(grep -c 'agents/handoff' "$MF" 2>/dev/null)"
assert_eq "AC1 an ignored file is not recorded" "0" "$(grep -c 'ignored.log' "$MF" 2>/dev/null)"
# the same state from a subdirectory: paths are relative to the work-tree top
cd "$SR/src" || exit 3
MF2="$(mk_tmp)/snap2"
gate snapshot --out "$MF2"
assert_rc "AC1 snapshot from a subdirectory exits 0" 0
if cmp -s "$MF" "$MF2"; then t_ok "AC1 a snapshot from a subdirectory records the same manifest (top-relative paths)"; else t_bad "AC1 a snapshot from a subdirectory records the same manifest (top-relative paths)" "$(cat "$MF2" 2>/dev/null | tr '\t' '>')"; fi
# default FILE: inside the git dir, per work tree
gate snapshot
DEF="$(git rev-parse --git-path pb-gate-baseline)"
assert_rc "AC1 snapshot with no --out exits 0" 0
PF="${OUT#*recorded in }"; PF="${PF% (digest *}"
case "$PF" in /*|[A-Za-z]:[/\\]*) t_ok "AC1 the printed default FILE is an absolute path" ;; *) t_bad "AC1 the printed default FILE is an absolute path" "[$PF] in [$OUT]" ;; esac
if [ -f "$DEF" ] && [ "$PF" -ef "$DEF" ]; then t_ok "AC1 the default FILE is git rev-parse --git-path pb-gate-baseline (inside the git dir)"; else t_bad "AC1 the default FILE is git rev-parse --git-path pb-gate-baseline (inside the git dir)" "printed [$PF], git says [$DEF]"; fi
assert_eq "AC1 the default manifest digest is printed" "baseline: 5 path(s) recorded in $PF (digest $(dig "$DEF"))" "$OUT"
cd "$SR" || exit 3
# a relative --out is resolved against the caller's directory
cd "$SR/src" || exit 3
gate snapshot --out ../.git/rel-manifest
assert_rc "AC1 a relative --out from a subdirectory exits 0" 0
assert_file "AC1 a relative --out is written relative to the caller's cwd" "$SR/.git/rel-manifest"
cd "$SR" || exit 3

echo "AC1 snapshot: symlink state is the hash of the link text, a dangling link is recorded"
R="$(mk_tmp)"; mk_repo "$R"; cd "$R" || exit 3
if ln -s README.md lnk-ok 2>/dev/null && ln -s no-such-target lnk-dead 2>/dev/null && [ -L lnk-ok ] && [ -L lnk-dead ]; then
  B0=$((T_PASS + T_FAIL))
  MF="$(mk_tmp)/m"; gate snapshot --out "$MF"
  assert_mline "AC1 a symlink: 120000 plus the hash of its link text" "$MF" "120000 $(printf '%s' README.md | git hash-object --stdin)${T}none${T}lnk-ok"
  assert_mline "AC1 a dangling symlink is recorded too" "$MF" "120000 $(printf '%s' no-such-target | git hash-object --stdin)${T}none${T}lnk-dead"
  cb reviewer
  assert_contains "AC1 an untouched symlink counts as unchanged since the baseline" "$OUT" "note: unchanged since the baseline: lnk-dead"
  ln -sf other-target lnk-dead
  cb reviewer
  assert_rc "AC1 a retargeted symlink is a change: the reviewer fails" 1
  assert_contains "AC1 ... and it is named" "$OUT" "VIOLATION (reviewer): lnk-dead [code]"
  blk_check "AC1 symlink block" 5 $((T_PASS + T_FAIL - B0))
else rm -f lnk-ok lnk-dead; t_skip 5 "AC1 symlink block (this file system or git setup cannot create symlinks)"; fi

echo "AC1 snapshot: a gitlink (a submodule that moved) is recorded as unhashable with a note, and is never skipped"
R="$(mk_tmp)"; mk_repo "$R"; cd "$R" || exit 3
mkdir sub
( cd sub && git init -q && git config user.email t@example.invalid && git config user.name tester && git config commit.gpgsign false &&
  git commit -q --allow-empty -m one ) >/dev/null 2>&1
git add sub >/dev/null 2>&1; git commit -q -m "add gitlink"
( cd sub && git commit -q --allow-empty -m two ) >/dev/null 2>&1
MF="$(mk_tmp)/m"; gate snapshot --out "$MF"
assert_rc "AC1 a gitlink path does not stop the snapshot: exit 0" 0
assert_contains "AC1 a note: line explains the unhashable path" "$OUT" "note:"
assert_eq "AC1 the gitlink is recorded with an unhashable work-tree state" "1" "$(awk -F'\t' '$1 == "unhashable" && $3 == "sub"' "$MF" 2>/dev/null | wc -l | tr -d ' ')"
cb reviewer
assert_rc "AC1/AC2 an unhashable baseline path is never unchanged: the reviewer fails (fail closed)" 1
assert_contains "AC1/AC2 ... and names the gitlink" "$OUT" "VIOLATION (reviewer): sub [code]"

echo "AC1 snapshot: a path with a TAB parses (the path is everything after the second TAB)"
R="$(mk_tmp)"; mk_repo "$R"; cd "$R" || exit 3
TABP="src/ta${T}b.js"
if printf 'x\n' > "$TABP" 2>/dev/null && [ -f "$TABP" ] && stores_name "$TABP"; then
  B0=$((T_PASS + T_FAIL))
  MF="$(mk_tmp)/m"; gate snapshot --out "$MF"
  assert_rc "AC1 a TAB path: snapshot exits 0" 0
  assert_mline "AC1 a TAB path: the line keeps the TAB inside the path" "$MF" "100644 $(hsh "$TABP")${T}none${T}$TABP"
  cb reviewer
  assert_rc "AC1 a TAB path unchanged since the baseline: the reviewer passes" 0
  assert_contains "AC1 ... the note names the full path" "$OUT" "note: unchanged since the baseline: $TABP"
  printf 'y\n' >> "$TABP"
  cb reviewer
  assert_rc "AC1 a TAB path edited after the snapshot: the reviewer fails" 1
  assert_contains "AC1 ... and the full path is named" "$OUT" "VIOLATION (reviewer): $TABP [code]"
  blk_check "AC1 TAB block" 6 $((T_PASS + T_FAIL - B0))
else rm -f -- "$TABP" 2>/dev/null; t_skip 6 "AC1 TAB path (this file system cannot store a TAB in a name, or git does not list it back unchanged)"; fi

echo "AC1 snapshot: a path with a newline cannot be recorded: exit 3 and no manifest"
R="$(mk_tmp)"; mk_repo "$R"; cd "$R" || exit 3
NLP="src/new
line.js"
if printf 'x\n' > "$NLP" 2>/dev/null && [ -f "$NLP" ] && stores_name "$NLP"; then
  B0=$((T_PASS + T_FAIL))
  MF="$(mk_tmp)/m"; gate snapshot --out "$MF"
  assert_rc "AC1 a newline path: snapshot exits 3" 3
  assert_no_path "AC1 ... and writes no manifest" "$MF"
  assert_not_contains "AC1 ... and prints no baseline: line" "$OUT" "baseline:"
  blk_check "AC1 newline block" 3 $((T_PASS + T_FAIL - B0))
else rm -f -- "$NLP" 2>/dev/null; t_skip 3 "AC1 newline path (this file system cannot store a newline in a name, or git does not list it back unchanged)"; fi

echo "AC1 snapshot: errors"
N="$(mk_tmp)"; cd "$N" || exit 3
gate snapshot;                                   assert_rc "AC1 snapshot outside a git work tree exits 3" 3
R="$(mk_tmp)"; mk_repo "$R"; cd "$R" || exit 3
gate snapshot --bogus;                           assert_rc "AC1 snapshot with an unknown option exits 2" 2
gate snapshot --out;                             assert_rc "AC1 snapshot --out without a value exits 2" 2
gate snapshot --out "$R/README.md/m";            assert_rc "AC1 a FILE that cannot be written exits 3" 3
gate;                                            assert_rc "AC8 no command exits 2" 2
assert_contains "AC8 the usage text still says: usage: role-gate.sh" "$OUT" "usage: role-gate.sh"

# ================= AC2 / AC3 / AC7 reviewer on a dirty start =================
echo "AC7 regression fb-20261017-001: a read-only reviewer on a repo with pre-existing dirty and untracked files"
dirty_reviewer
cb reviewer
assert_rc "AC7 the reviewer changed nothing: check --baseline exits 0" 0
assert_contains "AC3 the OK line keeps its format; C counts judged paths only (0)" "$OUT" "OK: role gate passed for reviewer (0 file(s) checked, base=HEAD)"
assert_contains "AC3 the baseline line shows N, the digest and K unchanged" "$OUT" "$NOTE"
assert_contains "AC3 a skipped modified tracked file is named" "$OUT" "note: unchanged since the baseline: src/mod.js"
assert_contains "AC3 a skipped untracked production file is named" "$OUT" "note: unchanged since the baseline: src/new.js"
assert_contains "AC3 a skipped untracked notes file is named" "$OUT" "note: unchanged since the baseline: notes/NOTES.md"
assert_not_contains "AC7 no violation" "$OUT" "VIOLATION"
gate check reviewer
assert_rc "AC7 the same repo without --baseline still fails (3 changed paths)" 1
assert_contains "AC7 ... with the summary line as today" "$OUT" "role gate FAILED for reviewer: 3 violation(s), base=HEAD"

echo "AC7/AC2 the reviewer edits a pre-dirty file: the file is checked and named, the others stay skipped"
dirty_reviewer
printf 'more\n' >> src/mod.js
cb reviewer
assert_rc "AC7 an edit of a pre-dirty tracked file: exit 1" 1
assert_contains "AC7 ... the edited file is named" "$OUT" "VIOLATION (reviewer): src/mod.js [code]"
assert_not_contains "AC7 ... and is no longer reported as unchanged" "$OUT" "unchanged since the baseline: src/mod.js"
assert_contains "AC3 ... the other two stay skipped (K=2)" "$OUT" "note: baseline $MF (3 path(s), digest $D): 2 path(s) unchanged, not checked"
assert_contains "AC7 ... exactly one violation" "$OUT" "role gate FAILED for reviewer: 1 violation(s), base=HEAD"
dirty_reviewer
printf 'more\n' >> src/new.js
cb reviewer
assert_rc "AC7 an edit of a pre-existing untracked file: exit 1" 1
assert_contains "AC7 ... the edited file is named" "$OUT" "VIOLATION (reviewer): src/new.js [code]"

echo "AC2 the reviewer reverts a pre-dirty file to HEAD or deletes the pre-existing untracked file: the change is judged"
dirty_reviewer
git checkout -q -- src/mod.js
cb reviewer
assert_rc "AC2 a pre-dirty file reverted to HEAD: exit 1" 1
assert_contains "AC2 ... the reverted file (no longer in the changed list) is named" "$OUT" "VIOLATION (reviewer): src/mod.js [code]"
assert_contains "AC2 ... the other two stay skipped" "$OUT" "note: unchanged since the baseline: src/new.js"
dirty_reviewer
rm -f src/new.js
cb reviewer
assert_rc "AC2 a pre-existing untracked file deleted: exit 1" 1
assert_contains "AC2 ... the deleted file is named" "$OUT" "VIOLATION (reviewer): src/new.js [code]"
dirty_reviewer
rm -f notes/NOTES.md
cb reviewer
assert_rc "AC2 a pre-existing untracked notes file deleted: exit 1" 1
assert_contains "AC2 ... the deleted notes file is named" "$OUT" "VIOLATION (reviewer): notes/NOTES.md [code]"

echo "AC2 a pre-deleted tracked file that comes back is judged; one that stays deleted is skipped"
base_repo
rm -f src/gone.js
MF="$(mk_tmp)/m"; gate snapshot --out "$MF"
cb reviewer
assert_rc "AC2 a tracked file deleted before the snapshot and still deleted: exit 0" 0
assert_contains "AC3 ... it is named as unchanged" "$OUT" "note: unchanged since the baseline: src/gone.js"
git checkout -q -- src/gone.js
cb reviewer
assert_rc "AC2 the deleted file restored to HEAD after the snapshot: exit 1" 1
assert_contains "AC2 ... the restored file is named" "$OUT" "VIOLATION (reviewer): src/gone.js [code]"

echo "AC2 a new file after the snapshot is checked as today, next to the skipped ones"
dirty_reviewer
printf 'e\n' > src/extra.js
cb reviewer
assert_rc "AC2 a new file after the snapshot: exit 1" 1
assert_contains "AC2 ... the new file is named" "$OUT" "VIOLATION (reviewer): src/extra.js [code]"
assert_contains "AC2 ... exactly one violation" "$OUT" "role gate FAILED for reviewer: 1 violation(s), base=HEAD"
assert_contains "AC3 ... the pre-existing three stay skipped" "$OUT" "digest $D): 3 path(s) unchanged, not checked"

echo "AC2 same content but a different index state is not skipped (staging is a change)"
dirty_reviewer
git add src/mod.js
cb reviewer
assert_rc "AC2 a pre-dirty file staged after the snapshot (same bytes): exit 1" 1
assert_contains "AC2 ... the staged file is named" "$OUT" "VIOLATION (reviewer): src/mod.js [code]"
assert_not_contains "AC2 ... and is not reported as unchanged" "$OUT" "unchanged since the baseline: src/mod.js"
dirty_reviewer
git add -N src/new.js 2>/dev/null
cb reviewer
assert_rc "AC2 a pre-existing untracked file added as intent-to-add: exit 1" 1
assert_contains "AC2 ... the path is named" "$OUT" "VIOLATION (reviewer): src/new.js [code]"

echo "AC2 the baseline decides by exact state, not by path: a rewrite to the same bytes is unchanged"
dirty_reviewer
printf 'two\n' > src/mod.js
cb reviewer
assert_rc "AC2 a file rewritten with identical bytes is still unchanged: exit 0" 0

echo "AC3 a manifest changed after the snapshot shows a different digest"
dirty_reviewer
printf 'absent%snone%szz-extra.txt\n' "$T" "$T" >> "$MF"
D2="$(dig "$MF")"
cb reviewer
assert_rc "AC3 an appended manifest line for an untouched path: exit 0" 0
assert_contains "AC3 the baseline line shows the digest of the manifest as it is now" "$OUT" "digest $D2)"
assert_not_contains "AC3 ... which is not the digest the snapshot printed" "$OUT" "digest $D)"
if [ "$D" != "$D2" ]; then t_ok "AC3 fixture: the two digests differ"; else t_bad "AC3 fixture: the two digests differ" "$D"; fi

echo "AC3 a relative --baseline is resolved against the caller's directory"
dirty_reviewer
cd "$R/src" || exit 3
gate snapshot --out ../.git/rel-m
gate check reviewer --baseline ../.git/rel-m
assert_rc "AC2 a relative --baseline from a subdirectory: exit 0" 0
assert_contains "AC3 ... with the skipped paths named (top-relative)" "$OUT" "note: unchanged since the baseline: src/mod.js"
cd "$R" || exit 3

echo "AC2 usage: --baseline needs a value"
gate check reviewer --baseline
assert_rc "AC2 check --baseline without a file exits 2" 2

# ================= AC4 fail closed =================
echo "AC4 a missing, empty or malformed manifest exits 3 before any verdict"
dirty_reviewer
BD="$(mk_tmp)"
S40="$(printf 'x' | git hash-object --stdin)"
HDR1="# role-gate baseline v1"
bad_case() { # NAME FILE (content already in FILE; a missing FILE is passed as is)
  gate check reviewer --baseline "$2"
  assert_rc "AC4 $1: exit 3" 3
  assert_not_contains "AC4 $1: no OK line" "$OUT" "OK:"
  assert_not_contains "AC4 $1: no FAILED line" "$OUT" "FAILED"
}
bad_case "a missing manifest" "$BD/does-not-exist"
: > "$BD/empty"; bad_case "an empty manifest (no header)" "$BD/empty"
printf '# role-gate baseline v2\nabsent\tnone\tsrc/x\n' > "$BD/v2"; bad_case "a wrong header version" "$BD/v2"
printf '%s \nabsent\tnone\tsrc/x\n' "$HDR1" > "$BD/hsp"; bad_case "a header with a trailing space" "$BD/hsp"
printf 'absent\tnone\tsrc/x\n' > "$BD/nohdr"; bad_case "no header line" "$BD/nohdr"
printf '%s\nabsent\tsrc/x\n' "$HDR1" > "$BD/onetab"; bad_case "a line with only one TAB" "$BD/onetab"
printf '%s\ngarbage\n' "$HDR1" > "$BD/notab"; bad_case "a line without TABs" "$BD/notab"
printf '%s\n100666 %s\tnone\tsrc/x\n' "$HDR1" "$S40" > "$BD/badmode"; bad_case "a work-tree mode that is not allowed (100666)" "$BD/badmode"
printf '%s\n100644 abc\tbogus\tsrc/x\n' "$HDR1" > "$BD/badidx"; bad_case "an index state that is not a state" "$BD/badidx"
printf '%s\n100644\tnone\tsrc/x\n' "$HDR1" > "$BD/nosha"; bad_case "a work-tree state with a mode but no hash" "$BD/nosha"
printf '%s\nabsent\tnone\tsrc/x\n100644 %s\tnone\tsrc/x\n' "$HDR1" "$S40" > "$BD/dupstale"; bad_case "two lines for the same path (a stale one and a current one)" "$BD/dupstale"
printf '%s\nabsent\tnone\tsrc/x\nabsent\tnone\tsrc/x\n' "$HDR1" > "$BD/dupsame"; bad_case "the same line twice" "$BD/dupsame"
printf '%s\n100644 %s\t100644 %s\tsrc/mod.js\n100644 %s\tnone\tsrc/mod.js\n' "$HDR1" "$S40" "$S40" "$S40" > "$BD/dupreal"; bad_case "two lines for a path that is really dirty" "$BD/dupreal"
gate size --baseline "$BD/dupstale"
assert_rc "AC4 size --baseline: a manifest with two lines for the same path: exit 3" 3
assert_not_contains "AC4 ... size prints no files: line (no fail-open)" "$OUT" "files:"
printf '%s\nabsent\tnone\tsrc/x\n' "$HDR1" > "$BD/valid"
gate check reviewer --baseline "$BD/valid"
assert_rc "AC4 control: a well-formed manifest is accepted (the dirty files are then judged: exit 1, not 3)" 1

# ================= AC2 tester / implementer on a dirty start =================
echo "AC2 implementer with a pre-dirty test file: untouched passes, touched is a violation"
dirty_impl
cb implementer
assert_rc "AC2 implementer: pre-dirty production and test files untouched: exit 0" 0
assert_contains "AC3 ... the OK line counts judged paths only (0)" "$OUT" "OK: role gate passed for implementer (0 file(s) checked, base=HEAD)"
assert_contains "AC3 ... the pre-dirty test file is named as unchanged" "$OUT" "note: unchanged since the baseline: tests/t.test.js"
dirty_impl
printf 'extra\n' >> tests/t.test.js
cb implementer
assert_rc "AC2 implementer touching the pre-dirty test file: exit 1" 1
assert_contains "AC2 ... it is a test violation" "$OUT" "VIOLATION (implementer): tests/t.test.js [test]"
dirty_impl
git checkout -q -- tests/t.test.js
cb implementer
assert_rc "AC2 implementer reverting the pre-dirty test file to HEAD: exit 1" 1
assert_contains "AC2 ... it is a test violation" "$OUT" "VIOLATION (implementer): tests/t.test.js [test]"
dirty_impl
git add tests/t.test.js
cb implementer
assert_rc "AC2 implementer staging the pre-dirty test file (same bytes): exit 1 (index state changed)" 1
assert_contains "AC2 ... it is named" "$OUT" "VIOLATION (implementer): tests/t.test.js [test]"
dirty_impl
printf 'n\n' > src/extra.js
cb implementer
assert_rc "AC2 implementer adding a production file next to the baseline: exit 0" 0
assert_contains "AC3 ... C counts the new file only (1)" "$OUT" "OK: role gate passed for implementer (1 file(s) checked, base=HEAD)"
assert_contains "AC3 ... two paths stay unchanged" "$OUT" "digest $D): 2 path(s) unchanged, not checked"

echo "AC2 tester: a pre-dirty production file untouched passes; reverting it is judged by kind"
dirty_impl
cb tester
assert_rc "AC2 tester: pre-dirty files untouched: exit 0" 0
assert_contains "AC3 ... the OK line (0 judged)" "$OUT" "OK: role gate passed for tester (0 file(s) checked, base=HEAD)"
dirty_impl
git checkout -q -- src/mod.js
cb tester
assert_rc "AC2 tester reverting a pre-dirty production file: exit 1" 1
assert_contains "AC2 ... it is a production violation for the tester" "$OUT" "VIOLATION (tester): src/mod.js [code]"
dirty_impl
git checkout -q -- tests/t.test.js
cb tester
assert_rc "AC2 tester reverting a pre-dirty test file: allowed, exit 0" 0
assert_contains "AC3 ... the reverted path was judged (1 file checked)" "$OUT" "OK: role gate passed for tester (1 file(s) checked, base=HEAD)"

# ================= AC5 mode drops =================
echo "AC5 a 100755 -> 100644 drop recorded in the baseline is not reported; a later drop is"
R="$(mk_tmp)"; mk_mode_repo "$R"; cd "$R" || exit 3
if ! fm_true_ok; then t_skip 12 "AC5 (this file system does not keep executable bits)"
else
  chmod -x src/run.sh 2>/dev/null
  if [ -x src/run.sh ]; then t_skip 12 "AC5 (chmod -x has no effect here)"
  else
    B0=$((T_PASS + T_FAIL))
    MF="$(mk_tmp)/m"; gate snapshot --out "$MF"
    cb implementer
    assert_rc "AC5 a drop that exists at the snapshot: exit 0" 0
    assert_not_contains "AC5 ... no mode violation" "$OUT" "(mode)"
    chmod -x src/second.sh 2>/dev/null
    cb implementer
    assert_rc "AC5 a second drop after the snapshot: exit 1" 1
    assert_contains "AC5 ... the new drop is reported" "$OUT" "VIOLATION (mode): src/second.sh lost its executable bit (100755 -> 100644)"
    assert_not_contains "AC5 ... the baseline drop stays unreported" "$OUT" "VIOLATION (mode): src/run.sh"
    printf '# edited\n' >> src/run.sh
    cb implementer
    assert_rc "AC5 a baseline path whose content changed: exit 1" 1
    assert_contains "AC5 ... its drop is reported again (the state changed)" "$OUT" "VIOLATION (mode): src/run.sh lost its executable bit (100755 -> 100644)"
    blk_check "AC5 work-tree block" 7 $((T_PASS + T_FAIL - B0))
    # a drop that is only staged
    R="$(mk_tmp)"; mk_mode_repo "$R"; cd "$R" || exit 3; git config core.fileMode true
    B0=$((T_PASS + T_FAIL))
    git update-index --chmod=-x -- src/run.sh
    MF="$(mk_tmp)/m"; gate snapshot --out "$MF"
    cb implementer
    assert_rc "AC5 a staged-only drop at the snapshot: exit 0" 0
    assert_not_contains "AC5 ... no mode violation" "$OUT" "(mode)"
    git update-index --chmod=-x -- src/second.sh
    cb implementer
    assert_rc "AC5 a second staged-only drop after the snapshot: exit 1" 1
    assert_contains "AC5 ... the new drop is reported" "$OUT" "VIOLATION (mode): src/second.sh lost its executable bit (100755 -> 100644)"
    assert_not_contains "AC5 ... the baseline drop stays unreported" "$OUT" "VIOLATION (mode): src/run.sh"
    blk_check "AC5 staged block" 5 $((T_PASS + T_FAIL - B0))
  fi
fi

# ================= AC2/AC5 a mode change after the snapshot on a path that was already dirty =================
echo "AC2/AC5 a tracked path dirty at the snapshot whose mode flips afterwards is judged (100755 -> 100644 and 100644 -> 100755)"
R="$(mk_tmp)"; mk_mode_repo "$R"; cd "$R" || exit 3
PRB=probe-x; : > "$PRB"; chmod 755 "$PRB" 2>/dev/null
if fm_true_ok && [ -x "$PRB" ] && chmod 644 "$PRB" 2>/dev/null && [ ! -x "$PRB" ]; then
  rm -f "$PRB"
  B0=$((T_PASS + T_FAIL))
  printf '# edit\n' >> src/run.sh; printf 'edit\n' >> src/plain.js
  MF="$(mk_tmp)/m"; gate snapshot --out "$MF"
  assert_mline "AC2 a dirty tracked 100755 file: both states 100755" "$MF" "100755 $(hsh src/run.sh)${T}$(idx src/run.sh)${T}src/run.sh"
  assert_mline "AC2 a dirty tracked 100644 file: both states 100644" "$MF" "100644 $(hsh src/plain.js)${T}$(idx src/plain.js)${T}src/plain.js"
  cb implementer
  assert_rc "AC2 control: nothing changed since the snapshot: exit 0" 0
  assert_contains "AC2 control: the dirty 100755 file is named as unchanged" "$OUT" "note: unchanged since the baseline: src/run.sh"
  chmod -x src/run.sh
  cb implementer
  assert_rc "AC5 a dirty 100755 file loses its exec bit after the snapshot (same bytes): exit 1" 1
  assert_contains "AC5 ... the mode violation is reported" "$OUT" "VIOLATION (mode): src/run.sh lost its executable bit (100755 -> 100644)"
  assert_not_contains "AC5 ... and the path is not listed as unchanged since the baseline" "$OUT" "unchanged since the baseline: src/run.sh"
  cb reviewer
  assert_rc "AC2 the same drop for a reviewer: exit 1" 1
  assert_contains "AC2 ... the path is judged and named" "$OUT" "VIOLATION (reviewer): src/run.sh [code]"
  chmod +x src/run.sh
  cb implementer
  assert_rc "AC2 the exec bit restored to the snapshot state: unchanged again, exit 0" 0
  chmod +x src/plain.js
  cb reviewer
  assert_rc "AC2 a dirty 100644 file gains an exec bit after the snapshot (same bytes): exit 1" 1
  assert_contains "AC2 ... the path is judged and named" "$OUT" "VIOLATION (reviewer): src/plain.js [code]"
  assert_not_contains "AC2 ... and is not listed as unchanged since the baseline" "$OUT" "unchanged since the baseline: src/plain.js"
  blk_check "AC2/AC5 tracked mode flip block" 13 $((T_PASS + T_FAIL - B0))
else rm -f "$PRB"; t_skip 13 "AC2/AC5 tracked mode flip (this file system does not keep executable bits)"; fi

echo "AC2 an untracked file: the OWNER execute bit decides 100755 (a group-only x bit is 100644); a chmod after the snapshot is judged"
R="$(mk_tmp)"; mk_repo "$R"; cd "$R" || exit 3
PRB=probe-x; : > "$PRB"; chmod 755 "$PRB" 2>/dev/null
if fm_true_ok && [ -x "$PRB" ] && chmod 644 "$PRB" 2>/dev/null && [ ! -x "$PRB" ]; then
  rm -f "$PRB"
  B0=$((T_PASS + T_FAIL))
  printf 'a\n' > src/u755.js; chmod 755 src/u755.js
  printf 'b\n' > src/g654.js; chmod 654 src/g654.js
  printf 'c\n' > src/g614.js; chmod 614 src/g614.js
  MF="$(mk_tmp)/m"; gate snapshot --out "$MF"
  assert_mline "AC2 an untracked 0755 file is recorded as 100755" "$MF" "100755 $(hsh src/u755.js)${T}none${T}src/u755.js"
  assert_mline "AC2 an untracked 0654 file (group x, no owner x) is recorded as 100644" "$MF" "100644 $(hsh src/g654.js)${T}none${T}src/g654.js"
  assert_mline "AC2 an untracked 0614 file (group x, no owner x) is recorded as 100644" "$MF" "100644 $(hsh src/g614.js)${T}none${T}src/g614.js"
  chmod 600 src/g614.js
  cb reviewer
  assert_rc "AC2 control: only a group bit changed (still no owner x): unchanged, exit 0" 0
  assert_contains "AC2 ... the 0614 file stays unchanged" "$OUT" "note: unchanged since the baseline: src/g614.js"
  assert_contains "AC2 ... the 0654 file stays unchanged" "$OUT" "note: unchanged since the baseline: src/g654.js"
  assert_contains "AC2 ... the 0755 file stays unchanged" "$OUT" "note: unchanged since the baseline: src/u755.js"
  chmod 644 src/u755.js
  cb reviewer
  assert_rc "AC2 a pre-existing untracked 0755 file chmod 644 after the snapshot (same bytes): exit 1" 1
  assert_contains "AC2 ... the path is judged and named" "$OUT" "VIOLATION (reviewer): src/u755.js [code]"
  assert_not_contains "AC2 ... and is not listed as unchanged since the baseline" "$OUT" "unchanged since the baseline: src/u755.js"
  chmod 744 src/g654.js
  cb reviewer
  assert_rc "AC2 a 0654 file that gains the owner x bit (same bytes): exit 1" 1
  assert_contains "AC2 ... the path is judged and named" "$OUT" "VIOLATION (reviewer): src/g654.js [code]"
  blk_check "AC2 untracked owner exec bit block" 12 $((T_PASS + T_FAIL - B0))
else rm -f "$PRB"; t_skip 12 "AC2 untracked owner exec bit (this file system does not keep executable bits)"; fi

# ================= AC6 size --baseline =================
# size_dirty: a modified tracked production file (120 added lines, 1 deleted), an untracked production file (10 lines), a
# modified tracked test file, then a snapshot (sets MF). Plain size counts 2 files and 131 lines there.
size_dirty() {
  if [ -z "$SD_TPL" ]; then
    base_repo
    i=0; : > src/mod.js; while [ "$i" -lt 120 ]; do i=$((i + 1)); printf 'line %s\n' "$i" >> src/mod.js; done
    i=0; : > src/new.js; while [ "$i" -lt 10 ]; do i=$((i + 1)); printf 'n %s\n' "$i" >> src/new.js; done
    printf 'tt2\n' > tests/t.test.js
    SD_MF="$(mk_tmp)/m"; gate snapshot --out "$SD_MF"; SD_TPL="$R"
  fi
  R="$(mk_tmp)"; cp -a "$SD_TPL/." "$R/"; cd "$R" || exit 3
  MF="$(mk_tmp)/m"; cp "$SD_MF" "$MF"
}
sb() { gate size "$@" --baseline "$MF"; }

echo "AC6 size --baseline leaves out the paths unchanged since the baseline (pre-existing dirty and untracked production files)"
size_dirty
gate size
assert_rc "AC6 control: plain size counts the pre-existing changes and is over the limit: exit 1" 1
assert_contains "AC6 control: plain size reports 2 files and 131 lines (unchanged behaviour)" "$OUT" "files: 2/3 lines: 131/100 (base=HEAD)"
assert_contains "AC6 control: plain size still says escalate to Full" "$OUT" "over the Lite size limit: escalate to Full"
sb
assert_rc "AC6 nothing changed after the snapshot: size --baseline exits 0" 0
assert_contains "AC6 ... the counts exclude the baseline paths, output format kept" "$OUT" "files: 0/3 lines: 0/100 (base=HEAD)"
assert_not_contains "AC6 ... no escalate line" "$OUT" "escalate"
sb --base HEAD --max-files 0 --max-lines 0
assert_rc "AC6 with explicit --base and limits of 0: still exit 0 (nothing counted)" 0
assert_contains "AC6 ... the limits are echoed" "$OUT" "files: 0/0 lines: 0/0 (base=HEAD)"

echo "AC6 a baseline path edited after the snapshot counts again; a new file counts as today"
size_dirty
printf 'more\n' >> src/mod.js
sb --max-lines 1000
assert_rc "AC6 one baseline file edited: exit 0 under a high line limit" 0
assert_contains "AC6 ... it counts again as 1 file and its full numstat lines (121 added + 1 deleted); the other baseline file stays out" "$OUT" "files: 1/3 lines: 122/1000 (base=HEAD)"
sb
assert_rc "AC6 the same edit under the default 100-line limit: exit 1" 1
assert_contains "AC6 ... escalate to Full" "$OUT" "over the Lite size limit: escalate to Full"
size_dirty
printf 'e\n' > src/extra.js
sb
assert_rc "AC6 a new file after the snapshot: exit 0 (1 file, 1 line)" 0
assert_contains "AC6 ... only the new file counts" "$OUT" "files: 1/3 lines: 1/100 (base=HEAD)"
size_dirty
printf 'x\n' > tests/other.test.js
sb
assert_contains "AC6 a new test file after the snapshot is not counted" "$OUT" "files: 0/3 lines: 0/100 (base=HEAD)"

echo "AC6 a staged change (same bytes) is a state change: the baseline path counts again"
size_dirty
git add src/mod.js
sb --max-lines 1000
assert_contains "AC6 a pre-dirty file staged after the snapshot counts (121 lines)" "$OUT" "files: 1/3 lines: 121/1000 (base=HEAD)"

echo "AC6 a baseline path reverted to HEAD or deleted is no longer in the numstat list: it counts as 1 file and 1 line when production, 0 for a test path"
size_dirty
git checkout -q -- src/mod.js
sb
assert_rc "AC6 a pre-dirty production file reverted to HEAD: exit 0" 0
assert_contains "AC6 ... counts as 1 file and 1 line" "$OUT" "files: 1/3 lines: 1/100 (base=HEAD)"
size_dirty
rm -f src/new.js
sb
assert_contains "AC6 a pre-existing untracked production file deleted: 1 file, 1 line" "$OUT" "files: 1/3 lines: 1/100 (base=HEAD)"
size_dirty
git checkout -q -- src/mod.js; rm -f src/new.js
sb
assert_contains "AC6 both production baseline paths reverted or deleted: 2 files, 2 lines" "$OUT" "files: 2/3 lines: 2/100 (base=HEAD)"
size_dirty
git checkout -q -- tests/t.test.js
sb
assert_rc "AC6 a pre-dirty test file reverted to HEAD: exit 0" 0
assert_contains "AC6 ... a test path counts 0 files and 0 lines" "$OUT" "files: 0/3 lines: 0/100 (base=HEAD)"
size_dirty
git checkout -q -- src/mod.js
sb --max-files 0 --max-lines 0
assert_rc "AC6 a reverted production baseline path is judged against the limits too (0/0): exit 1" 1
assert_contains "AC6 ... the over-limit line is printed" "$OUT" "over the Lite size limit: escalate to Full"

echo "AC6 size --baseline: bad manifest, missing value, relative path"
size_dirty
BD="$(mk_tmp)"
printf '# role-gate baseline v2\nabsent\tnone\tsrc/x\n' > "$BD/v2"
gate size --baseline "$BD/v2"
assert_rc "AC6 a manifest with a wrong header: exit 3" 3
assert_not_contains "AC6 ... no files: line before the error" "$OUT" "files:"
gate size --baseline "$BD/does-not-exist"
assert_rc "AC6 a missing manifest: exit 3" 3
printf '%s\ngarbage\n' "# role-gate baseline v1" > "$BD/bad"
gate size --baseline "$BD/bad"
assert_rc "AC6 a malformed manifest line: exit 3" 3
assert_not_contains "AC6 ... never reports counts (no fail-open)" "$OUT" "files:"
gate size --baseline
assert_rc "AC6 size --baseline without a value: exit 2" 2
gate size --base HEAD --baseline
assert_rc "AC6 size --baseline as the last option without a value: exit 2" 2
cd "$R/src" || exit 3
gate snapshot --out ../.git/rel-m
gate size --baseline ../.git/rel-m
assert_rc "AC6 a relative --baseline from a subdirectory resolves against the caller's cwd: exit 0" 0
assert_contains "AC6 ... the baseline paths stay out of the counts" "$OUT" "files: 0/3 lines: 0/100 (base=HEAD)"
cd "$R" || exit 3

# ================= AC1/AC6 a clean tree =================
echo "AC1/AC6 a snapshot of a clean tree records 0 paths and the gates accept it"
base_repo
MF="$(mk_tmp)/m"; gate snapshot --out "$MF"; D="$(dig "$MF")"
assert_rc "AC1 snapshot of a clean tree: exit 0" 0
assert_eq "AC1 the printed line says 0 path(s) with the digest" "baseline: 0 path(s) recorded in $MF (digest $D)" "$OUT"
assert_eq "AC1 the manifest is exactly the header line" "# role-gate baseline v1" "$(cat "$MF" 2>/dev/null)"
assert_eq "AC1 the manifest has one line" "1" "$(wc -l < "$MF" 2>/dev/null | tr -d ' ')"
cb reviewer
assert_rc "AC2 check reviewer --baseline with an empty manifest on a clean tree: exit 0" 0
assert_contains "AC2 ... the OK line" "$OUT" "OK: role gate passed for reviewer (0 file(s) checked, base=HEAD)"
sb
assert_rc "AC6 size --baseline with an empty manifest on a clean tree: exit 0" 0
assert_contains "AC6 ... counts 0 files and 0 lines" "$OUT" "files: 0/3 lines: 0/100 (base=HEAD)"
printf 'later\n' > src/later.js
cb reviewer
assert_rc "AC2 a file created after an empty baseline is judged: exit 1" 1
assert_contains "AC2 ... and named" "$OUT" "VIOLATION (reviewer): src/later.js [code]"
sb
assert_contains "AC6 ... and counted by size --baseline" "$OUT" "files: 1/3 lines: 1/100 (base=HEAD)"

# ================= state definition: raw bytes (git hash-object --no-filters) =================
echo "AC2 a work-tree state is the hash of the raw bytes: a CRLF- or filter-hidden edit is a different state"
# raw_fixture ATTR-LINE: a repo whose .gitattributes holds ATTR-LINE, src/a.js committed as "one"
raw_fixture() {
  R="$(mk_tmp)"; mk_repo "$R"; cd "$R" || exit 3
  printf '%s\n' "$1" > .gitattributes; printf 'one\n' > src/a.js
  git add -A && git commit -q -m attrs || exit 3
}
# raw_snap: src/a.js is dirty ("two") and a baseline is taken (sets MF)
raw_snap() { printf 'two\n' > src/a.js; MF="$(mk_tmp)/m"; gate snapshot --out "$MF"; }
# Case A: eol=lf normalizes CRLF away, so only the raw bytes tell "two\n" from "two\r\n"
raw_fixture "*.js text eol=lf"; raw_snap
assert_rc "RAW A snapshot of the pre-dirty src/a.js: exit 0" 0
cb reviewer
assert_rc "RAW A control: nothing changed after the snapshot, the raw-byte hash is stable: exit 0" 0
assert_contains "RAW A control: src/a.js is unchanged since the baseline" "$OUT" "note: unchanged since the baseline: src/a.js"
assert_not_contains "RAW A control: src/a.js is not a violation" "$OUT" "VIOLATION (reviewer): src/a.js"
printf 'two\r\n' > src/a.js
cb reviewer
assert_rc "RAW A a CRLF rewrite (same normalized content) after the snapshot is judged: exit 1" 1
assert_contains "RAW A ... src/a.js is named" "$OUT" "VIOLATION (reviewer): src/a.js [code]"
assert_not_contains "RAW A ... and not reported as unchanged since the baseline" "$OUT" "unchanged since the baseline: src/a.js"
# Case B: a clean filter upper-cases, so "TWO\n" and "two\n" hash alike through the filter, not raw
raw_fixture "*.js filter=up"
git config filter.up.clean "tr a-z A-Z"
FP="$(printf 'two\n' | git hash-object --stdin --path=src/a.js 2>/dev/null)"; FQ="$(printf 'TWO\n' | git hash-object --stdin 2>/dev/null)"
if [ -n "$FP" ] && [ "$FP" = "$FQ" ]; then
  raw_snap
  cb reviewer
  assert_rc "RAW B control: nothing changed after the snapshot: exit 0" 0
  assert_contains "RAW B control: src/a.js is unchanged since the baseline" "$OUT" "note: unchanged since the baseline: src/a.js"
  printf 'TWO\n' > src/a.js
  cb reviewer
  assert_rc "RAW B a filter-equivalent rewrite (TWO) after the snapshot is judged: exit 1" 1
  assert_contains "RAW B ... src/a.js is named" "$OUT" "VIOLATION (reviewer): src/a.js [code]"
  assert_not_contains "RAW B ... and not reported as unchanged since the baseline" "$OUT" "unchanged since the baseline: src/a.js"
else t_skip 5 "RAW B clean-filter case (a git clean filter is not applied by hash-object on this platform)"; fi

# v0.24.18 (review round 3 MINOR): an unreadable file makes the batch hash fail, so every regular file is hashed one by one;
# that per-file fallback must hash raw bytes too (--no-filters), or a CRLF-only edit next to the unreadable file is skipped.
# Probe: chmod 000 must really block reads (not as root, not on NTFS where Git Bash ignores it); else skip.
raw_fixture "*.js text eol=lf"
printf 'two\n' > src/a.js
printf 'secret\n' > src/secret.txt
chmod 000 src/secret.txt 2>/dev/null
if [ -e src/secret.txt ] && ! cat src/secret.txt >/dev/null 2>&1 &&
   ! printf 'src/secret.txt\n' | git hash-object --no-filters --stdin-paths >/dev/null 2>&1; then
  MF="$(mk_tmp)/m"; gate snapshot --out "$MF"
  assert_rc "FALLBACK snapshot with an unreadable file next to the pre-dirty src/a.js: exit 0" 0
  assert_contains "FALLBACK the unreadable file is recorded as unhashable" "$(cat "$MF" 2>/dev/null)" "unhashable"
  assert_mline "FALLBACK src/a.js is still recorded with its raw-byte hash (per-file fallback)" "$MF" \
    "100644 $(hsh src/a.js)	$(idx src/a.js)	src/a.js"
  printf 'two\r\n' > src/a.js
  cb reviewer
  assert_rc "FALLBACK a CRLF rewrite of src/a.js (same normalized content) is judged: exit 1" 1
  assert_contains "FALLBACK ... src/a.js is named" "$OUT" "VIOLATION (reviewer): src/a.js [code]"
  assert_not_contains "FALLBACK ... and not reported as unchanged since the baseline" "$OUT" "unchanged since the baseline: src/a.js"
else t_skip 6 "FALLBACK per-file hash case (chmod 000 does not block reads here: root, or a file system without POSIX modes)"; fi
chmod 600 src/secret.txt 2>/dev/null

# ================= v0.24.20 N1: a manifest written inside the work tree is warned about =================
echo "v0.24.20 N1 snapshot --out inside the work tree warns that the gate will judge the manifest as a change"
W_IN="the manifest is inside the work tree"
base_repo; printf 'two\n' > src/mod.js
gate snapshot --out "$R/base.txt"
assert_rc "N1 --out inside the work tree: snapshot still exits 0" 0
assert_contains "N1 --out inside the work tree: a note warns" "$OUT" "note: $W_IN"
gate snapshot
assert_rc "N1 default --out (the git dir): exit 0" 0
assert_not_contains "N1 default --out (the git dir): no warning" "$OUT" "$W_IN"
gate snapshot --out "$(mk_tmp)/m"
assert_not_contains "N1 --out outside the repository: no warning" "$OUT" "$W_IN"
mkdir -p .agents/handoff
gate snapshot --out "$R/.agents/handoff/m"
assert_not_contains "N1 --out under .agents/handoff/ (never judged): no warning" "$OUT" "$W_IN"
gate snapshot --out "$R/ignored.log"
assert_not_contains "N1 --out at an ignored path (never judged): no warning" "$OUT" "$W_IN"

# ================= v0.24.20 N2: baseline notes show control characters as ? =================
echo "v0.24.20 N2 a path with a CR is shown with ? in the 'unchanged since the baseline' note"
base_repo
CRN="src/c$(printf '\r').js"
printf 'x\n' > "$CRN" 2>/dev/null
LSF="$(mk_tmp)/ls"; git ls-files --others -z > "$LSF" 2>/dev/null
if printf '%s\0' "$CRN" | cmp -s - "$LSF"; then
  MF="$(mk_tmp)/m"; gate snapshot --out "$MF"
  cb reviewer
  assert_rc "N2 the CR path is unchanged since the baseline: exit 0" 0
  assert_contains "N2 the note shows the CR as ?" "$OUT" "note: unchanged since the baseline: src/c?.js"
  if printf '%s' "$OUT" | grep -q "$(printf '\r')"; then t_bad "N2 the output holds no raw CR" "$(printf '%s' "$OUT" | od -c | head -3)"; else t_ok "N2 the output holds no raw CR"; fi
else t_skip 3 "N2 CR path (this file system cannot store a CR in a name, or git does not list it back unchanged)"; fi

# ================= v0.24.21 T1: snapshot --out refuses a tracked file of the repository =================
echo "v0.24.21 T1 snapshot --out FILE refuses a tracked file of the repository (exit 3) and leaves it untouched"
W_TR="the manifest path is a tracked file of this repository"
# same_as NAME FILE COPY: FILE still has the bytes of COPY
same_as() { if cmp -s "$2" "$3"; then t_ok "$1"; else t_bad "$1" "$(head -2 "$2" 2>/dev/null | tr '\t' '>')"; fi; }
base_repo; printf 'two\n' > src/mod.js
KEEP="$(mk_tmp)"; cp src/gone.js "$KEEP/gone"; cp src/mod.js "$KEEP/mod"
gate snapshot --out src/gone.js
assert_rc "T1 a relative tracked --out: exit 3" 3
assert_contains "T1 ... the refusal names the path as given" "$OUT" "$W_TR: src/gone.js"
assert_not_contains "T1 ... no manifest is reported" "$OUT" "baseline:"
same_as "T1 ... the tracked file is untouched" src/gone.js "$KEEP/gone"
gate snapshot --out "$R/src/gone.js"
assert_rc "T1 an absolute tracked --out: exit 3" 3
assert_contains "T1 ... the refusal names the absolute path" "$OUT" "$W_TR: $R/src/gone.js"
same_as "T1 ... the tracked file is untouched" src/gone.js "$KEEP/gone"
cd src || exit 3
gate snapshot --out mod.js
cd "$R" || exit 3
assert_rc "T1 --out a tracked (modified) file relative to a subdirectory: exit 3" 3
assert_contains "T1 ... named as given" "$OUT" "$W_TR: mod.js"
same_as "T1 ... the modified tracked file keeps its work-tree bytes" src/mod.js "$KEEP/mod"
rm -f src/gone.js
gate snapshot --out src/gone.js
assert_rc "T1 --out a tracked file deleted from the work tree (still in the index): exit 3" 3
if [ -e src/gone.js ]; then t_bad "T1 ... the deleted tracked file is not recreated" "src/gone.js exists"; else t_ok "T1 ... the deleted tracked file is not recreated"; fi
git checkout -q -- src/gone.js
printf 'new\n' > src/added.js; git add src/added.js; cp src/added.js "$KEEP/added"
gate snapshot --out src/added.js
assert_rc "T1 --out a staged new file (tracked in the index): exit 3" 3
same_as "T1 ... the staged file is untouched" src/added.js "$KEEP/added"
gate snapshot --out 'src/[g]one.js'
assert_rc "T1 an untracked --out whose name, read as a glob, would match a tracked file: exit 0 (literal path)" 0
same_as "T1 ... the tracked file the glob would match is untouched" src/gone.js "$KEEP/gone"
gate snapshot --out "$R/src/free.txt"
assert_rc "T1 an untracked --out inside the work tree still works: exit 0" 0
assert_contains "T1 ... the manifest is written" "$(head -1 src/free.txt 2>/dev/null)" "# role-gate baseline v1"
# Git Bash: the same tracked file spelled C:/... (cygpath -m) is refused too; git decides, not a string compare
if command -v cygpath >/dev/null 2>&1 && WIN="$(cygpath -m "$R/src/gone.js" 2>/dev/null)" && [ -n "$WIN" ] && [ "$WIN" != "$R/src/gone.js" ]; then
  gate snapshot --out "$WIN"
  assert_rc "T1 the C:/ spelling of a tracked file: exit 3" 3
  same_as "T1 ... the tracked file is untouched" src/gone.js "$KEEP/gone"
else t_skip 2 "T1 C:/ spelling (no cygpath: not Git Bash)"; fi

# ================= v0.24.22 S1: snapshot --out refuses an untracked symlink into a tracked file =================
echo "v0.24.22 S1 snapshot --out LINK, a symlink into a tracked file of the repository: exit 3, nothing written through the link"
W_SL="the manifest path is a symlink into a tracked file of this repository"
base_repo
SLB="$(mk_tmp)"; : > "$SLB/outside.txt"; mkdir -p "$SLB/dir"
if ln -s src/gone.js lnk-rel 2>/dev/null && [ -L lnk-rel ]; then
  B0=$((T_PASS + T_FAIL))
  KEEP="$(mk_tmp)"; cp src/gone.js "$KEEP/gone"
  ln -s "$R/src/gone.js" lnk-abs; ln -s lnk-rel lnk-chain; mkdir -p sub; ln -s ../src/gone.js sub/lnk-up; ln -s src dirlink
  gate snapshot --out lnk-rel
  assert_rc "S1 a relative link to a tracked file: exit 3" 3
  assert_contains "S1 ... the refusal names the link as given" "$OUT" "$W_SL: lnk-rel"
  assert_not_contains "S1 ... no manifest is reported" "$OUT" "baseline:"
  same_as "S1 ... the tracked file is untouched" src/gone.js "$KEEP/gone"
  if [ -L lnk-rel ] && [ "$(readlink lnk-rel)" = src/gone.js ]; then t_ok "S1 ... the link is untouched"; else t_bad "S1 ... the link is untouched" "$(readlink lnk-rel)"; fi
  gate snapshot --out lnk-abs
  assert_rc "S1 an absolute link to a tracked file: exit 3" 3
  same_as "S1 ... the tracked file is untouched" src/gone.js "$KEEP/gone"
  gate snapshot --out lnk-chain
  assert_rc "S1 a link to a link to a tracked file: exit 3" 3
  same_as "S1 ... the tracked file is untouched" src/gone.js "$KEEP/gone"
  gate snapshot --out sub/lnk-up
  assert_rc "S1 a link in a subdirectory (../src/gone.js): exit 3" 3
  same_as "S1 ... the tracked file is untouched" src/gone.js "$KEEP/gone"
  gate snapshot --out "$R/dirlink/gone.js"
  assert_rc "S1 a path through a symlinked directory into a tracked file: exit 3" 3
  same_as "S1 ... the tracked file is untouched" src/gone.js "$KEEP/gone"
  ln -s "$SLB/outside.txt" lnk-out
  gate snapshot --out lnk-out
  assert_rc "S1 a link to a file outside the repository stays allowed: exit 0" 0
  assert_contains "S1 ... the manifest went through the link" "$(head -1 "$SLB/outside.txt" 2>/dev/null)" "# role-gate baseline v1"
  ln -s src/never-tracked.txt lnk-dead
  gate snapshot --out lnk-dead
  assert_rc "S1 a dangling link whose target is not tracked: exit 0" 0
  blk_check "S1 symlink block" 16 $((T_PASS + T_FAIL - B0))
else rm -f lnk-rel; t_skip 16 "S1 symlink into a tracked file (this file system or git setup cannot create symlinks)"; fi

# ================= v0.24.21 T2: an interrupt in bl_states exits 130 (INT) or 143 (TERM), never 1 or 0 =================
echo "v0.24.21 T2 INT / TERM while bl_states waits on git: exit 130 / 143 and the temp file is removed"
SIGD="$(mk_tmp)"; mkdir -p "$SIGD/fake" "$SIGD/tmp"
REALGIT="$(command -v git)"
# a fake git first on PATH: the batch hash-object of bl_states drops a marker and waits (at most 60 s) for a release file
cat > "$SIGD/fake/git" <<EOF
#!/usr/bin/env bash
case " \$* " in
  *" hash-object "*"--stdin-paths"*)
    : > "$SIGD/marker"
    n=0; while [ ! -f "$SIGD/release" ] && [ "\$n" -lt 60 ]; do sleep 1; n=\$((n + 1)); done ;;
esac
exec "$REALGIT" "\$@"
EOF
chmod +x "$SIGD/fake/git"
# sig_run SIG CMD...: start CMD as a job (set -m: an async list without job control ignores INT), wait until the fake git
# blocks (at most 10 s), send SIG to that process only, release git; SRC is the exit code, SMK 1 when the marker appeared
sig_run() {
  local sig="$1" pid n; shift
  rm -f "$SIGD/marker" "$SIGD/release"
  set -m
  "$@" < /dev/null > /dev/null 2>&1 &
  pid=$!
  set +m
  n=0; while [ ! -f "$SIGD/marker" ] && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
  if [ -f "$SIGD/marker" ]; then SMK=1; else SMK=0; fi
  kill -"$sig" "$pid" 2>/dev/null
  : > "$SIGD/release"
  wait "$pid"; SRC=$?
}
base_repo; printf 'two\n' > src/mod.js
# control: a plain bash with its own INT/TERM trap, signalled the same way, must run its trap (else this shell cannot do it)
CTL=1
for s in INT TERM; do
  sig_run "$s" env PATH="$SIGD/fake:$PATH" bash -c 'trap "exit 7" INT TERM; printf "src/mod.js\n" | git hash-object --stdin-paths > /dev/null; exit 0'
  { [ "$SMK" = 1 ] && [ "$SRC" = 7 ]; } || CTL=0
done
if [ "$CTL" = 1 ]; then
  sig_run INT env PATH="$SIGD/fake:$PATH" TMPDIR="$SIGD/tmp" PLAYBOOK_HOME="$IH" bash "$GATE" snapshot --out "$SIGD/m"
  RC="$SRC"; assert_rc "T2 INT during the snapshot's bl_states: exit 130" 130
  assert_eq "T2 ... the temp file is removed" "" "$(ls "$SIGD/tmp")"
  sig_run TERM env PATH="$SIGD/fake:$PATH" TMPDIR="$SIGD/tmp" PLAYBOOK_HOME="$IH" bash "$GATE" snapshot --out "$SIGD/m"
  RC="$SRC"; assert_rc "T2 TERM during the snapshot's bl_states: exit 143" 143
  assert_eq "T2 ... the temp file is removed" "" "$(ls "$SIGD/tmp")"
else t_skip 4 "T2 signals (a job started here does not get INT/TERM delivered to its trap)"; fi

# ================= AC8 byte-for-byte without --baseline =================
echo "AC8 without --baseline the output and exit code equal the pre-change gate (a manifest on disk is not consulted)"
OLD="$(mk_tmp)"
# the reference is the commit before this feature (30f0444), not HEAD: HEAD holds the new gate, which would compare to itself
PRE=30f0444
if git -C "$PB_ROOT" cat-file -e "$PRE^{commit}" 2>/dev/null &&
   ( cd "$PB_ROOT" && git archive "$PRE" scripts | tar -x -C "$OLD" ) 2>/dev/null && [ -f "$OLD/scripts/role-gate.sh" ] &&
   ! grep -q 'role-gate baseline' "$OLD/scripts/role-gate.sh"; then
  dirty_reviewer
  gate snapshot >/dev/null 2>&1
  printf 'edit\n' >> src/mod.js
  for role in reviewer implementer tester infra; do
    run env PLAYBOOK_HOME="$IH" bash "$OLD/scripts/role-gate.sh" check "$role"; OLDV="$RC|$OUT"
    gate check "$role"; NEWV="$RC|$OUT"
    assert_eq "AC8 check $role: same exit code and bytes as the pre-change gate" "$OLDV" "$NEWV"
  done
  run env PLAYBOOK_HOME="$IH" bash "$OLD/scripts/role-gate.sh" size; OLDV="$RC|$OUT"
  gate size; NEWV="$RC|$OUT"
  assert_eq "AC8 size: same exit code and bytes as the pre-change gate" "$OLDV" "$NEWV"
  run env PLAYBOOK_HOME="$IH" bash "$OLD/scripts/role-gate.sh" check reviewer --base HEAD; OLDV="$RC|$OUT"
  gate check reviewer --base HEAD; NEWV="$RC|$OUT"
  assert_eq "AC8 check with --base: same exit code and bytes" "$OLDV" "$NEWV"
  base_repo
  run env PLAYBOOK_HOME="$IH" bash "$OLD/scripts/role-gate.sh" check reviewer; OLDV="$RC|$OUT"
  gate check reviewer; NEWV="$RC|$OUT"
  assert_eq "AC8 a clean repo: same OK line and exit code" "$OLDV" "$NEWV"
  assert_not_contains "AC8 a clean repo prints no baseline note without --baseline" "$NEWV" "baseline"
else t_skip 8 "AC8 byte comparison (the pre-change commit $PRE is not in this repository, e.g. a shallow clone, or git archive is not available)"; fi
t_summary
