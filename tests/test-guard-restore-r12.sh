#!/usr/bin/env bash
# Fix round R12 (spec .agents/handoff/01-spec.md "## Revision 15"):
#   R12-1 a relative pathspec is joined to the PHYSICAL directory git runs in: from an in-repo symlinked cwd (lnk -> a/b), "../db/schema.sql"
#         is a/db/schema.sql, a tracked file that was dirty at session start. The four spellings must block, and when the guard says allow
#         the command is run FOR REAL and the check is that a/db/schema.sql's start-of-session edit survives.
#   R12-4 a SessionStart where git status fails writes "unknown" into <sid>.dirty, so a restore then blocks.
# "[today FAIL]" = fails before R12 is implemented; "[guard-rail]" = passes today and must stay.
. "$(dirname "$0")/lib.sh"
. "$PB_ROOT/tests/guard-fixture.sh"
trap t_cleanup EXIT
trap 't_cleanup; exit 130' INT
trap 't_cleanup; exit 143' TERM

HL="$GW/r12-hook.log"
SN=0
SC="db/schema.sql"
S_HEAD='-- the shop database (SQLite)'
S_ORD='CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER NOT NULL, created_at TEXT NOT NULL, total_cents INTEGER NOT NULL);'
MARK='-- USER WORK at start'
CWDX=""
gs() { local a="${1:-false}"; [ "$#" -gt 0 ] && shift; : > "$HL"; grun PB_HEADLESS=1 PB_EVAL_HOOK_LOG="$HL" "$@" -- "$(jstop "$R" "$SID" "$a")" --stop; }
gx() { local c="$1"; shift; : > "$HL"; grun PB_HEADLESS=1 PB_EVAL_HOOK_LOG="$HL" "$@" -- "$(jbash "$c" "${CWDX:-$R}" "$SID")"; }
nallow() { grep -c 'allow restore-flagged' "$HL" 2>/dev/null || true; }
flagit() { printf '%s\n' "$S_HEAD" "$S_ORD" > "$R/$SC"; }

# rboot: repo + a/b, a/db/schema.sql (tracked, second schema file), lnk -> a/b; a/db/schema.sql gets a user edit BEFORE SessionStart
rboot() {
  R="$(mk_tmp)/repo"; mk_schema_repo "$R" >/dev/null; GRUNDIR="$R"; CWDX=""
  SN=$((SN + 1)); SID="r12$SN"
  mkdir -p "$R/a/b" "$R/a/db"
  printf 'CREATE TABLE other_t (id INTEGER);\n' > "$R/a/db/schema.sql"; printf 'k\n' > "$R/a/b/keep"
  ln -s a/b "$R/lnk" 2>/dev/null
  fxg "$R" add -A; fxg "$R" commit -qm more
  BASE="$(git -C "$R" rev-parse HEAD)"; B7="$(printf '%s' "$BASE" | cut -c1-7)"
  printf '%s\n' "$MARK" >> "$R/a/db/schema.sql"
  grun PB_HEADLESS=1 -- "$(jstart "$R" "$SID" startup)" --session-start
  flagit
  gs; expect_block "$1: the Stop block" schema-drop
}
# survives NAME -> a/db/schema.sql still has the start-of-session edit
survives() { assert_eq "$1: a/db/schema.sql's edit survives" 1 "$(grep -c -- "$MARK" "$R/a/db/schema.sql" 2>/dev/null || true)"; }
# ck_blk NAME CMD -> the guard must block; if it says allow, the command is run for real (in the hook cwd) so the data loss shows up
ck_blk() {
  local n="$1" c="$2" real
  gx "$c"; real="$RC"
  if [ "$real" = 0 ]; then
    ( cd "${CWDX:-$R}" && "$GBASH" -c "$c" ) >/dev/null 2>&1
    survives "$n (ran for real because the guard allowed it)"
    git -C "$R" checkout -q "$BASE" -- a/db/schema.sql 2>/dev/null; printf '%s\n' "$MARK" >> "$R/a/db/schema.sql"; flagit
    gx "$c"
  fi
  expect_block "$n" git-discard
  assert_eq "$n: no allow restore-flagged line" 0 "$(nallow)"
}

PROBE="$(mk_tmp)"; mkdir "$PROBE/d"; ln -s d "$PROBE/l" 2>/dev/null
if [ -L "$PROBE/l" ]; then
  echo "R12-1 .. from an in-repo symlinked dir (lnk -> a/b): ../db/schema.sql is a/db/schema.sql, dirty at session start"
  rboot "R12-1"
  [ -L "$R/lnk" ] || t_bad "R12-1 the fixture lnk is a symlink" "not a symlink"
  ck_blk "R12-1 [today FAIL] cd lnk && git checkout <b7> -- ../db/schema.sql" "cd lnk && git checkout $B7 -- ../db/schema.sql"
  ck_blk "R12-1 [today FAIL] git -C lnk checkout <b7> -- ../db/schema.sql" "git -C lnk checkout $B7 -- ../db/schema.sql"
  ck_blk "R12-1 [today FAIL] cd lnk; git restore ../db/schema.sql" "cd lnk; git restore ../db/schema.sql"
  CWDX="$R/lnk"
  ck_blk "R12-1 [today FAIL] hook cwd lnk: git checkout <b7> -- ../db/schema.sql" "git checkout $B7 -- ../db/schema.sql"
  CWDX=""
  ck_blk "R12-1 [guard-rail] git checkout . still blocks" "git checkout ."
  gx "git checkout $B7 -- lnk/../db/schema.sql"; expect_pass "R12-1 [guard-rail] lnk/../db/schema.sql from the top passes (git folds it lexically)"
  assert_eq "R12-1 lnk/../db/schema.sql: one allow restore-flagged line" 1 "$(nallow)"
  ( cd "$R" && "$GBASH" -c "git checkout $B7 -- lnk/../db/schema.sql" ) >/dev/null 2>&1
  assert_eq "R12-1 lnk/../db/schema.sql restored db/schema.sql (legacy_orders is back)" 1 "$(grep -c legacy_orders "$R/$SC" 2>/dev/null || true)"
  survives "R12-1 lnk/../db/schema.sql"
else
  t_skip 20 "R12-3 symlinks are copies on this host: the lnk cases are skipped"
fi

echo "R12-4 SessionStart where git status fails: the record says unknown, the restore blocks"
R="$(mk_tmp)/repo"; mk_schema_repo "$R" >/dev/null; GRUNDIR="$R"; CWDX=""
SN=$((SN + 1)); SID="r12$SN"
BASE="$(git -C "$R" rev-parse HEAD)"; B7="$(printf '%s' "$BASE" | cut -c1-7)"
JUNK="$(mk_tmp)/junk-index"; printf 'this is not a git index\n' > "$JUNK"
grun PB_HEADLESS=1 GIT_INDEX_FILE="$JUNK" -- "$(jstart "$R" "$SID" startup)" --session-start
ST="$(gcd "$R")/pb-guard"
assert_file "R12-4 .dirty exists" "$ST/$SID.dirty"
if grep -Fxq unknown "$ST/$SID.dirty" 2>/dev/null; then t_ok "R12-4 [today FAIL] a failing git status gives the line unknown in .dirty"; else t_bad "R12-4 [today FAIL] a failing git status gives the line unknown in .dirty" "$(head -3 "$ST/$SID.dirty" 2>/dev/null)"; fi
flagit
gs; expect_block "R12-4: the Stop block" schema-drop
gx "git checkout $B7 -- $SC"
expect_block "R12-4 [today FAIL] with 'unknown' the hinted restore blocks: git checkout <b7> -- $SC" git-discard
assert_eq "R12-4 no allow restore-flagged line" 0 "$(nallow)"
t_summary
