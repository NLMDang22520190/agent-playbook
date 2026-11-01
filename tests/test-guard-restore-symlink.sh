#!/usr/bin/env bash
# Fix round R11 (spec .agents/handoff/01-spec.md "## Revision 14"): the restore allow (R8/R9/R10) compares physical paths.
# macOS CI failed both restore suites because TMPDIR is /var/... (a symlink to /private/var/...): the hook cwd keeps the symlink
# spelling, git rev-parse --show-toplevel resolves it. This suite builds that situation on every host: it makes a real dir, a
# symlink to it, points TMPDIR at the symlink BEFORE lib.sh loads (so PB_TMPBASE, the fixture repo and the hook cwd all go
# through the symlink) and replays the restore cases. "[today FAIL]" = fails before R11 is implemented; "[guard-rail]" = blocked
# today and must stay blocked.
SYM_REAL="$(mktemp -d "${TMPDIR:-/tmp}/pbsymreal.XXXXXX")" || exit 3
# R12-3: a host that makes a copy instead of a symlink (Git Bash without native symlinks) skips the symlink cases, never fails
HAVE_SYM=1
mkdir "$SYM_REAL/real" || { echo "cannot make a dir here"; rm -rf "$SYM_REAL"; exit 3; }
ln -s "$SYM_REAL/real" "$SYM_REAL/link" 2>/dev/null
[ -L "$SYM_REAL/link" ] || HAVE_SYM=0
[ "$HAVE_SYM" = 1 ] && export TMPDIR="$SYM_REAL/link"
. "$(dirname "$0")/lib.sh"
. "$PB_ROOT/tests/guard-fixture.sh"
sym_cleanup() { t_cleanup; case "$SYM_REAL" in /*/pbsymreal.*) rm -rf "$SYM_REAL" ;; esac; }
trap sym_cleanup EXIT
trap 'sym_cleanup; exit 130' INT
trap 'sym_cleanup; exit 143' TERM

if [ "$HAVE_SYM" = 0 ]; then
  t_skip 60 "R12-3 [ -L \"\$SYM_REAL/link\" ] is false: this host copies instead of linking, every symlink case skipped"
  t_summary
  exit $?
fi
HL="$GW/symlink-hook.log"
SN=0
SC="db/schema.sql"
S_HEAD='-- the shop database (SQLite)'
S_ORD='CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER NOT NULL, created_at TEXT NOT NULL, total_cents INTEGER NOT NULL);'
CWDX=""
rboot() {
  R="$(mk_tmp)/repo"; mk_schema_repo "$R" >/dev/null; GRUNDIR="$R"; CWDX=""
  SN=$((SN + 1)); SID="sl$SN"
  TOP="$(git -C "$R" rev-parse --show-toplevel)"
  BASE="$(git -C "$R" rev-parse HEAD)"; B7="$(printf '%s' "$BASE" | cut -c1-7)"
  grun PB_HEADLESS=1 -- "$(jstart "$R" "$SID" startup)" --session-start
}
gs() { local a="${1:-false}"; [ "$#" -gt 0 ] && shift; : > "$HL"; grun PB_HEADLESS=1 PB_EVAL_HOOK_LOG="$HL" "$@" -- "$(jstop "$R" "$SID" "$a")" --stop; }
gx() { local c="$1"; shift; : > "$HL"; grun PB_HEADLESS=1 PB_EVAL_HOOK_LOG="$HL" "$@" -- "$(jbash "$c" "${CWDX:-$R}" "$SID")"; }
gp() { local c="$1"; shift; : > "$HL"; grun PB_HEADLESS=1 PB_EVAL_HOOK_LOG="$HL" "$@" -- "$(jps "$c" "${CWDX:-$R}" "$SID")"; }
nallow() { grep -c 'allow restore-flagged' "$HL" 2>/dev/null || true; }
ck_ok() { local n="$1"; gx "$2" "${@:3}"; expect_pass "$n"; assert_eq "$n: one allow restore-flagged line" 1 "$(nallow)"; }
ck_no() { local n="$1"; gx "$2" "${@:3}"; expect_block "$n" git-discard; assert_eq "$n: no allow restore-flagged line" 0 "$(nallow)"; }
pk_ok() { local n="$1"; gp "$2" "${@:3}"; expect_pass "$n"; assert_eq "$n: one allow restore-flagged line" 1 "$(nallow)"; }
# flag NAME -> the E13 edit (legacy_orders removed), headless Stop blocks
flag() { printf '%s\n' "$S_HEAD" "$S_ORD" > "$R/$SC"; gs; expect_block "$1: the Stop block" schema-drop; }

echo "R11 fixture: the repo is reached through a symlink, git resolves it"
rboot
case "$R" in "$SYM_REAL/link"/*) t_ok "R11 the repo path goes through the symlink" ;; *) t_bad "R11 the repo path goes through the symlink" "R=[$R] link=[$SYM_REAL/link]" ;; esac
assert_eq "R12-2 [today FAIL when TMPDIR is itself a symlink] git's top is the physical path (cd -P && pwd -P)" "$(cd -P -- "$SYM_REAL/real" && pwd -P)/$(basename "$(dirname "$R")")/repo" "$TOP"
case "$PB_TMPBASE" in "$SYM_REAL/link") t_ok "R11 PB_TMPBASE is the symlink" ;; *) t_bad "R11 PB_TMPBASE is the symlink" "[$PB_TMPBASE]" ;; esac

echo "R11 E13 end to end through the symlink"
rboot
_SCH="$(sed '3,4d' "$R/$SC"; printf x)"; printf '%s' "${_SCH%x}" > "$R/$SC"
gs; expect_block "R11 E13: headless Stop blocks on the schema drop" schema-drop
HINT="$(printf '%s\n' "$GERR" | sed -n 's/^(restore: \(.*\))$/\1/p' | sed -n 1p)"
assert_eq "R11 E13: the printed hint" "git checkout $B7 -- $SC" "$HINT"
ck_ok "R11 E13 [today FAIL] the printed hint passes with one allow restore-flagged line" "$HINT"
( cd "$R" && "$GBASH" -c "$HINT" ) >/dev/null 2>&1
assert_eq "R11 E13: the hint restored the file" "" "$(git -C "$R" status --porcelain)"
gs true; expect_pass "R11 E13: the next Stop passes"

echo "R11 restore spellings through the symlink"
rboot; flag "R11 spellings"
ck_ok "R11 [today FAIL] git checkout <b7> -- $SC" "git checkout $B7 -- $SC"
ck_ok "R11 [today FAIL] git restore $SC" "git restore $SC"
ck_ok "R11 [today FAIL] cd db && git checkout <b7> -- schema.sql" "cd db && git checkout $B7 -- schema.sql"
CWDX="$R/db"; ck_ok "R11 [today FAIL] hook cwd db/, path schema.sql" "git checkout $B7 -- schema.sql"; CWDX=""
ck_ok "R11 [today FAIL] ./$SC and db/../$SC" "git checkout $B7 -- ./$SC"
ck_ok "R11 [today FAIL] db/../$SC" "git checkout $B7 -- db/../$SC"
ck_ok "R11 [today FAIL] the absolute path through the symlink ($R/$SC)" "git checkout $B7 -- $R/$SC"
ck_ok "R11 [today FAIL] the absolute path of the physical top ($TOP/$SC)" "git checkout $B7 -- $TOP/$SC"
ck_ok "R11 [today FAIL] git -C <symlink repo> checkout" "git -C $R checkout $B7 -- $SC"
ck_no "R11 [guard-rail] git checkout . still blocks" "git checkout ."
ck_no "R11 [guard-rail] git reset --hard still blocks" "git reset --hard"

echo "R11 deleted file through the symlink"
rboot; rm -f "$R/$SC"
gs; expect_block "R11 rm $SC: the Stop block" schema-drop
ck_ok "R11 [today FAIL] rm: git checkout <b7> -- $SC" "git checkout $B7 -- $SC"
ck_ok "R11 [today FAIL] rm: git restore $SC" "git restore $SC"

echo "R11 PowerShell through the symlink"
rboot; flag "R11 PS"
pk_ok "R11 [today FAIL] PowerShell git checkout <b7> -- $SC" "git checkout $B7 -- $SC"
pk_ok "R11 [today FAIL] PowerShell git checkout <b7> -- db\schema.sql" "git checkout $B7 -- db\schema.sql"
pk_ok "R11 [today FAIL] PowerShell Set-Location db; git checkout <b7> -- schema.sql" "Set-Location db; git checkout $B7 -- schema.sql"

echo "R11 blocked: a symlink inside the repo that leads outside, and a missing parent dir"
rboot; flag "R11 db symlink"
OUTD="$(mk_tmp)/elsewhere"; mkdir -p "$OUTD"
mv "$R/db" "$OUTD/db" && ln -s "$OUTD/db" "$R/db" 2>/dev/null
if [ -L "$R/db" ]; then
ck_no "R11 [guard-rail or today FAIL] db -> outside the repo: git checkout <b7> -- $SC blocks" "git checkout $B7 -- $SC"
ck_no "R11 db -> outside the repo: git restore $SC blocks" "git restore $SC"
ck_no "R11 db -> outside the repo: cd db && git checkout <b7> -- schema.sql blocks" "cd db && git checkout $B7 -- schema.sql"
else t_skip 6 "R12-3 db is not a symlink here"; fi
rboot; flag "R11 missing parent"
ck_no "R11 [guard-rail] a pathspec whose parent dir does not exist (nodir/x.sql) blocks" "git checkout $B7 -- nodir/x.sql"
rboot; rm -rf "$R/db"
gs; expect_block "R11 rm -rf db: the Stop block" schema-drop
ck_ok "R11-1' [today FAIL, spec fix D16] the whole db dir deleted: the nearest existing ancestor is the top, missing components are appended, so the hinted restore passes" "git checkout $B7 -- $SC"
rboot; rm -rf "$R/db"
gs; expect_block "R11-1' rm -rf db: the Stop block (git restore)" schema-drop
ck_ok "R11-1' [today FAIL, spec fix D16] the whole db dir deleted: git restore $SC passes" "git restore $SC"
echo "R11-1' nearest existing ancestor is a symlink to outside, tail missing"
rboot; flag "R11-1' symlink ancestor"
OUTE="$(mk_tmp)/elsewhere2"; mkdir -p "$OUTE"
mv "$R/db" "$OUTE/db" && ln -s "$OUTE/db" "$R/db" 2>/dev/null
if [ -L "$R/db" ]; then
ck_no "R11-1' [guard-rail] db -> outside, missing tail db/gone/x.sql blocks" "git checkout $B7 -- db/gone/x.sql"
else t_skip 2 "R12-3 db is not a symlink here"; fi
t_summary
