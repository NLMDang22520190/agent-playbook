#!/usr/bin/env bash
# Fix round R8 (spec .agents/handoff/01-spec.md "## Revision 11", "11b", "11c", "11d"; decision D13):
# the guard lets through the git checkout / git restore it asked for in its own headless Stop block, and only that.
#   R8-1 --session-start also writes <sid>.dirty (first line "top <TOP>", then the tracked-change paths, raw bytes, "unknown" when it cannot list them)
#   R8-2 a headless Stop block writes <sid>.restore ("top <TOP>", then the paths of the "(restore: git checkout <b7> -- FILE)" hints);
#        a Stop that passes or gives up removes it; an interactive Stop leaves it alone
#   R8-3 seg_git (Bash and PowerShell) lets a git checkout/restore of exactly such a path pass, logs "allow restore-flagged", and
#        keeps today's git-discard block for anything else.
# State files live in <git common dir>/pb-guard/<sid>.dirty and <sid>.restore (like <sid>.untracked).
# Each case runs in its own throwaway repo under the suite's temp dirs. The guard only reads the commands it is shown; the only
# command this suite really runs is the restore hint the guard printed, and only inside a repo made by mk_tmp (runin refuses others).
# Assertion status today (before R8 is implemented): "[today FAIL]" cases need the new behaviour and fail for that reason;
# "[guard-rail]" cases (still blocked / nothing written) already pass today and keep the old behaviour pinned.
. "$(dirname "$0")/lib.sh"
. "$PB_ROOT/tests/guard-fixture.sh"

S_HEAD='-- the shop database (SQLite)'
S_ORD='CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER NOT NULL, created_at TEXT NOT NULL, total_cents INTEGER NOT NULL);'
S_LEGC='-- orders of the old shop, read-only since the move to the orders table'
S_LEG='CREATE TABLE legacy_orders (id INTEGER PRIMARY KEY, customer_id INTEGER, created_at TEXT, total_cents INTEGER);'
E_ACUTE=$'\xc3\xa9'   # the UTF-8 bytes of e-acute: a non-ASCII path (core.quotepath would print it as "\303\251")
HL="$GW/restore-hook.log"
SN=0
CWDX=""

# rnew -> a new schema repo R (db/schema.sql: orders + legacy_orders, src/orders.js, committed); no session started yet
rnew() {
  R="$(mk_tmp)/repo"; mk_schema_repo "$R" >/dev/null; GRUNDIR="$R"; CWDX=""
  mkdir -p "$R/src"
  printf '%s\n' 'module.exports = { ordersOf: (db, id) => db.all("SELECT 1", [id]) };' > "$R/src/orders.js"
  fxg "$R" add -A; fxg "$R" commit -qm code
  SN=$((SN + 1)); SID="rs$SN"
  ST="$(gcd "$R")/pb-guard"
  TOP="$(git -C "$R" rev-parse --show-toplevel)"
}
# rstart [SOURCE] -> SessionStart in R for SID; BASE and B7 are HEAD at that moment
rstart() {
  BASE="$(git -C "$R" rev-parse HEAD)"; B7="$(printf '%s' "$BASE" | cut -c1-7)"
  grun PB_HEADLESS=1 -- "$(jstart "$R" "$SID" "${1:-startup}")" --session-start
}
rboot() { rnew; rstart; }
# drop -> the E13 edit: legacy_orders removed from db/schema.sql
drop() { schema "$S_HEAD" "$S_ORD"; }
schema() { printf '%s\n' "$@" > "$R/db/schema.sql"; }
# gs [ACTIVE] [ENV...] -> --stop in R for SID, headless unless ENV says otherwise; the hook log is $HL
gs() { local a="${1:-false}"; [ "$#" -gt 0 ] && shift; : > "$HL"; grun PB_HEADLESS=1 PB_EVAL_HOOK_LOG="$HL" "$@" -- "$(jstop "$R" "$SID" "$a")" --stop; }
# gx CMD [ENV...] -> PreToolUse Bash in $CWDX (default R) for SID, headless; hook log is $HL
gx() { local c="$1"; shift; : > "$HL"; grun PB_HEADLESS=1 PB_EVAL_HOOK_LOG="$HL" "$@" -- "$(jbash "$c" "${CWDX:-$R}" "$SID")"; }
# gp CMD [ENV...] -> the same through the PowerShell tool
gp() { local c="$1"; shift; : > "$HL"; grun PB_HEADLESS=1 PB_EVAL_HOOK_LOG="$HL" "$@" -- "$(jps "$c" "${CWDX:-$R}" "$SID")"; }
nallow() { grep -c 'allow restore-flagged' "$HL" 2>/dev/null || true; }
# ck_ok NAME CMD [ENV...] : PASS and exactly one "allow restore-flagged" in the hook log     [today FAIL]
ck_ok() { local n="$1"; gx "$2" "${@:3}"; expect_pass "$n"; assert_eq "$n: one allow restore-flagged line" 1 "$(nallow)"; }
# ck_no NAME CMD [ENV...] : BLOCK git-discard and no "allow restore-flagged"                 [guard-rail]
ck_no() { local n="$1"; gx "$2" "${@:3}"; expect_block "$n" git-discard; assert_eq "$n: no allow restore-flagged line" 0 "$(nallow)"; }
pk_ok() { local n="$1"; gp "$2" "${@:3}"; expect_pass "$n"; assert_eq "$n: one allow restore-flagged line" 1 "$(nallow)"; }
pk_no() { local n="$1"; gp "$2" "${@:3}"; expect_block "$n" git-discard; assert_eq "$n: no allow restore-flagged line" 0 "$(nallow)"; }
# flag NAME -> drop legacy_orders, headless Stop blocks with schema-drop (the state the restore tests start from)
flag() { drop; gs; expect_block "$1: the Stop block" schema-drop; }
assert_line() { # NAME FILE LINE : FILE holds LINE as a whole line
  if [ -f "$2" ] && grep -Fxq -- "$3" "$2" 2>/dev/null; then t_ok "$1"; else t_bad "$1" "no line [$3] in $2: [$(cat "$2" 2>/dev/null | tr '\n' '|')]"; fi
}
assert_no_line() { # NAME FILE LINE : FILE does not hold LINE (a missing file counts)
  if [ -f "$2" ] && grep -Fxq -- "$3" "$2" 2>/dev/null; then t_bad "$1" "unexpected line [$3] in $2"; else t_ok "$1"; fi
}
# runin CMD -> really runs CMD in R through bash, only when R is a repo this suite made
runin() {
  case "$R" in "$PB_TMPBASE"/pbtest.*/repo) ;; *) t_bad "runin refuses a repo this suite did not make" "R=[$R]"; return 1 ;; esac
  [ -d "$R/.git" ] || { t_bad "runin refuses a directory that is not a repo root" "R=[$R]"; return 1; }
  ( cd "$R" && "$GBASH" -c "$1" ) >/dev/null 2>&1
}
SC="db/schema.sql"

echo "R8-1 --session-start writes <sid>.dirty (top line, tracked-change paths, raw bytes)"
rnew
printf -- '-- tweak\n' >> "$R/db/schema.sql"; printf 'scratch\n' > "$R/notes.txt"
fxg "$R" mv src/orders.js src/orders2.js
rstart
assert_line "R8-1 [today FAIL] the first line is 'top <worktree top>'" "$ST/$SID.dirty" "top $TOP"
if [ -f "$ST/$SID.dirty" ] && [ "$(sed -n 1p "$ST/$SID.dirty")" = "top $TOP" ]; then t_ok "R8-1 'top' is the FIRST line"; else t_bad "R8-1 'top' is the FIRST line" "$(head -3 "$ST/$SID.dirty" 2>/dev/null)"; fi
assert_line "R8-1 [today FAIL] a modified tracked file is listed, TOP-relative" "$ST/$SID.dirty" "$SC"
assert_line "R8-1 [today FAIL] a rename lists the new path" "$ST/$SID.dirty" "src/orders2.js"
assert_line "R8-1 [today FAIL] a rename lists the old path too" "$ST/$SID.dirty" "src/orders.js"
assert_no_line "R8-1 an untracked file is not listed (with .dirty existing: see the 'top' assertion above)" "$ST/$SID.dirty" "notes.txt"
printf 'x\n' >> "$R/README.md"
rstart
assert_no_line "R8-1 first write wins: a later startup record does not add README.md" "$ST/$SID.dirty" "README.md"
assert_line "R8-1 [today FAIL] ...and the first record is still there" "$ST/$SID.dirty" "$SC"
rnew; rstart
assert_line "R8-1 [today FAIL] a clean start still writes the file with its top line" "$ST/$SID.dirty" "top $TOP"
if [ -f "$ST/$SID.dirty" ] && [ "$(wc -l < "$ST/$SID.dirty" | tr -d ' ')" = 1 ]; then t_ok "R8-1 a clean start lists no path"; else t_bad "R8-1 a clean start lists no path" "$(cat "$ST/$SID.dirty" 2>/dev/null | tr '\n' '|')"; fi
# non-ASCII path: raw bytes, not the quoted "\303\251" spelling
rnew; printf 'CREATE TABLE e1 (id INTEGER);\nCREATE TABLE e2 (id INTEGER);\n' > "$R/db/$E_ACUTE.sql"
fxg "$R" add -A; fxg "$R" commit -qm acute; printf -- '-- user\n' >> "$R/db/$E_ACUTE.sql"; rstart
assert_line "R8-1 [today FAIL] a non-ASCII dirty path is listed as raw bytes" "$ST/$SID.dirty" "db/$E_ACUTE.sql"
# a tracked path holding a newline: not listed, the file says unknown (N6)
rnew; NLF="db/a"$'\n'"b.sql"; printf 'CREATE TABLE t (id INTEGER);\n' > "$R/$NLF" 2>/dev/null
if [ -f "$R/$NLF" ]; then
  fxg "$R" add -A; fxg "$R" commit -qm nl
  printf -- '-- user\n' >> "$R/$NLF"; rstart
  assert_line "R8-1 [today FAIL] a dirty tracked path with a newline gives the line 'unknown'" "$ST/$SID.dirty" unknown
  flag "R8-1 newline path"
  ck_no "R8-1 [guard-rail] with 'unknown' every restore blocks: git checkout <b7> -- $SC" "git checkout $B7 -- $SC"
  ck_no "R8-1 [guard-rail] with 'unknown' every restore blocks: git restore $SC" "git restore $SC"
else
  t_skip 6 "R8-1 newline-in-file-name case: this filesystem cannot hold a newline in a file name (NTFS)"
fi

echo "R8-2 the headless Stop block writes <sid>.restore"
rboot; flag "R8-2"
assert_contains "R8-2 the hint is still printed" "$GERR" "(restore: git checkout $B7 -- $SC)"
assert_line "R8-2 [today FAIL] the first line is 'top <worktree top>'" "$ST/$SID.restore" "top $TOP"
if [ -f "$ST/$SID.restore" ] && [ "$(sed -n 1p "$ST/$SID.restore")" = "top $TOP" ]; then t_ok "R8-2 'top' is the FIRST line"; else t_bad "R8-2 'top' is the FIRST line" "$(head -3 "$ST/$SID.restore" 2>/dev/null)"; fi
assert_line "R8-2 [today FAIL] the path the hint named is listed" "$ST/$SID.restore" "$SC"
assert_no_line "R8-2 the table name is not a path in the list" "$ST/$SID.restore" "legacy_orders"
# a column drop alone (M4)
rboot; schema "$S_HEAD" 'CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER NOT NULL, created_at TEXT NOT NULL);' "$S_LEGC" "$S_LEG"
gs; expect_block "R8-2 a column drop: the Stop block" schema-column-drop
assert_line "R8-2 [today FAIL] a column drop lists its file" "$ST/$SID.restore" "$SC"
ck_ok "R8-2 [today FAIL] a column drop: git checkout <b7> -- $SC passes" "git checkout $B7 -- $SC"
# a code-contract line in a tracked code file (M4)
rboot; printf '%s\n' 'db.exec("DROP TABLE legacy_orders");' >> "$R/src/orders.js"
gs; expect_block "R8-2 a code-contract line in tracked src/orders.js: the Stop block" code-contract
assert_line "R8-2 [today FAIL] code-contract lists src/orders.js" "$ST/$SID.restore" "src/orders.js"
ck_ok "R8-2 [today FAIL] code-contract: git checkout <b7> -- src/orders.js passes" "git checkout $B7 -- src/orders.js"
# an untracked new file is not restorable from BASE: the hint says remove it, so it is not listed
rboot; printf '%s\n' 'db.exec("DROP TABLE legacy_orders");' > "$R/src/cleanup.js"
gs; expect_block "R8-2 a new untracked file with a drop line: the Stop block" code-contract
assert_no_line "R8-2 a new (untracked) file is not in the restore list" "$ST/$SID.restore" "src/cleanup.js"
# a migration finding is not listed (its hint is remove/move)
rboot; mkdir -p "$R/db/migrations"; printf 'DROP TABLE legacy_orders;\n' > "$R/db/migrations/001_drop.sql"
gs; expect_block "R8-2 a new migration with DROP TABLE: the Stop block" migration-contract
assert_no_line "R8-2 a migration finding is not in the restore list" "$ST/$SID.restore" "db/migrations/001_drop.sql"
# the list is replaced by the next block
rboot; flag "R8-2 replace (first block)"
assert_line "R8-2 [today FAIL] first block lists $SC" "$ST/$SID.restore" "$SC"
git -C "$R" checkout -q "$BASE" -- "$SC"
printf '%s\n' 'db.exec("DROP TABLE legacy_orders");' >> "$R/src/orders.js"
gs; expect_block "R8-2 replace (second block, code-contract only)" code-contract
assert_line "R8-2 [today FAIL] the second block lists src/orders.js" "$ST/$SID.restore" "src/orders.js"
assert_no_line "R8-2 the second block replaced the first list: $SC is gone" "$ST/$SID.restore" "$SC"
# no list when Stop passes; a Stop that passes removes an existing list (m1)
rboot; flag "R8-2 pass removes the list"
git -C "$R" checkout -q "$BASE" -- "$SC"
gs true; expect_pass "R8-2 after the restore the next Stop passes"
assert_no_path "R8-2 [guard-rail today, real once R8-2 writes it] a Stop that passes removes <sid>.restore" "$ST/$SID.restore"
# interactive Stop: no list (writes none, leaves an existing one alone)
rboot; drop
grun PB_HEADLESS=0 -- "$(jstop "$R" "$SID")" --stop
if [ "$RC" = 0 ] && has "$GOUTN" '"systemMessage":"agent-playbook guard: '; then t_ok "R8-2 interactive Stop warns"; else t_bad "R8-2 interactive Stop warns" "rc=$RC $OUT"; fi
assert_no_path "R8-2 [guard-rail] an interactive Stop writes no restore list" "$ST/$SID.restore"
rboot; flag "R8-2 interactive leaves the list"
BEFORE="$(cat "$ST/$SID.restore" 2>/dev/null)"
printf '%s\n' 'db.exec("DROP TABLE legacy_orders");' >> "$R/src/orders.js"
grun PB_HEADLESS=0 -- "$(jstop "$R" "$SID")" --stop
assert_file "R8-2 [today FAIL] an interactive Stop leaves the existing restore list in place" "$ST/$SID.restore"
assert_eq "R8-2 [today FAIL] ...with its content unchanged (a warning is not a replacement)" "$BEFORE" "$(cat "$ST/$SID.restore" 2>/dev/null)"
assert_contains "R8-2 [today FAIL] ...and that content is the earlier list (names $SC)" "$BEFORE" "$SC"

echo "R8-3 E13 end to end: Stop block, the restore it names passes, the next Stop passes"
rboot
_SCH="$(sed '3,4d' "$R/db/schema.sql"; printf x)"; printf '%s' "${_SCH%x}" > "$R/db/schema.sql"   # portable in-place delete (no sed -i, no .bak); the E13 implementer's own edit (Run 28 with.1 t21)
gs; expect_block "R8-3 E13: headless Stop blocks on the schema drop" schema-drop
assert_contains "R8-3 E13: the block names the file" "$GERR" "$SC"
assert_contains "R8-3 E13: the block names the table" "$GERR" "legacy_orders"
HINT="$(printf '%s\n' "$GERR" | sed -n 's/^(restore: \(.*\))$/\1/p' | sed -n 1p)"
assert_eq "R8-3 E13: the restore hint is the git checkout the guard prints" "git checkout $B7 -- $SC" "$HINT"
ck_ok "R8-3 E13 [today FAIL]: the printed restore hint itself passes the PreToolUse check" "$HINT"
ck_ok "R8-3 [today FAIL] git checkout <b7> -- $SC" "git checkout $B7 -- $SC"
ck_ok "R8-3 [today FAIL] git checkout -- $SC (from the index)" "git checkout -- $SC"
ck_ok "R8-3 [today FAIL] git restore $SC" "git restore $SC"
ck_ok "R8-3 [today FAIL] git restore --source=<b7> --worktree $SC" "git restore --source=$B7 --worktree $SC"
ck_ok "R8-3 [today FAIL] git restore -s <b7> $SC" "git restore -s $B7 $SC"
ck_ok "R8-3 [today FAIL] git restore -s<b7> $SC" "git restore -s$B7 $SC"
ck_ok "R8-3 [today FAIL] git restore --source <b7> $SC" "git restore --source $B7 $SC"
ck_ok "R8-3 [today FAIL] git restore -W $SC" "git restore -W $SC"
ck_ok "R8-3 [today FAIL] git restore --worktree $SC" "git restore --worktree $SC"
ck_ok "R8-3 [today FAIL] git checkout HEAD -- $SC (HEAD is BASE here)" "git checkout HEAD -- $SC"
ck_ok "R8-3 [today FAIL] the full 40-character BASE" "git checkout $BASE -- $SC"
ck_ok "R8-3 [today FAIL] ./$SC" "git checkout $B7 -- ./$SC"
ck_ok "R8-3 [today FAIL] db/../$SC" "git checkout $B7 -- db/../$SC"
ck_ok "R8-3 [today FAIL] the absolute path of the file" "git checkout $B7 -- $R/$SC"
ck_ok "R8-3 [today FAIL] chained after another command: one log line" "git status && git checkout $B7 -- $SC"
ck_ok "R8-3 [today FAIL] -C <the same top>" "git -C $R checkout $B7 -- $SC"
ck_ok "R8-3 [today FAIL] -C <a sub directory> with a relative path" "git -C $R/db checkout $B7 -- schema.sql"
ck_ok "R8-3 [today FAIL] cd db && git checkout <b7> -- schema.sql" "cd db && git checkout $B7 -- schema.sql"
CWDX="$R/db"; ck_ok "R8-3 [today FAIL] hook cwd db/, path schema.sql" "git checkout $B7 -- schema.sql"; CWDX=""
# the log line is not written for a blocked command
ck_no "R8-3 [guard-rail] git reset --hard still blocks" "git reset --hard"
# really restore, then the next Stop passes
runin "$HINT"
assert_eq "R8-3 E13: the restore hint restored the schema file" "" "$(git -C "$R" status --porcelain)"
gs true; expect_pass "R8-3 E13: after the restore the next Stop passes"
assert_no_path "R8-3 [guard-rail today] after the Stop passed the restore list is gone" "$ST/$SID.restore"
git -C "$R" checkout -q "$BASE" -- "$SC"
printf -- '-- new edit\n' >> "$R/$SC"
ck_no "R8-3 (m1) after Stop passed, git checkout -- $SC with a NEW edit blocks again" "git checkout -- $SC"
ck_no "R8-3 (m1) ...and git checkout <b7> -- $SC" "git checkout $B7 -- $SC"

echo "R8-3 still blocked (git-discard)"
# path dirty at session start
rnew; printf -- '-- user tweak\n' >> "$R/$SC"; rstart
flag "R8-3 dirty at start"
ck_no "R8-3 path dirty at session start: git checkout <b7> -- $SC" "git checkout $B7 -- $SC"
ck_no "R8-3 path dirty at session start: git restore $SC" "git restore $SC"
# a flagged path plus an unflagged modified path
rboot; flag "R8-3 mixed"
printf -- '-- edit\n' >> "$R/README.md"
ck_ok "R8-3 [today FAIL] the flagged path alone passes although README.md is modified" "git checkout $B7 -- $SC"
ck_no "R8-3 a flagged path plus an unflagged modified path" "git checkout $B7 -- $SC README.md"
ck_no "R8-3 an unflagged modified path alone" "git checkout $B7 -- README.md"
ck_no "R8-3 git restore: a flagged and an unflagged path" "git restore $SC README.md"
ck_no "R8-3 git checkout ." "git checkout ."
ck_no "R8-3 git checkout -- ." "git checkout -- ."
ck_no "R8-3 git restore ." "git restore ."
ck_no "R8-3 git reset --hard" "git reset --hard"
ck_no "R8-3 git reset --hard <b7>" "git reset --hard $B7"
ck_no "R8-3 a directory pathspec: git checkout <b7> -- db" "git checkout $B7 -- db"
ck_no "R8-3 a directory pathspec: git checkout <b7> -- db/" "git checkout $B7 -- db/"
ck_no "R8-3 a glob: db/*.sql" "git checkout $B7 -- 'db/*.sql'"
ck_no "R8-3 a glob: db/schema.s?l" "git checkout $B7 -- 'db/schema.s?l'"
ck_no "R8-3 a glob: db/schema.[s]ql" "git checkout $B7 -- 'db/schema.[s]ql'"
ck_no "R8-3 pathspec magic :/db/schema.sql" "git checkout $B7 -- ':/db/schema.sql'"
ck_no "R8-3 pathspec magic :(top)db/schema.sql" "git checkout $B7 -- ':(top)db/schema.sql'"
ck_no "R8-3 a path outside the work tree: ../outside" "git checkout $B7 -- ../outside"
ck_no "R8-3 a path outside the work tree: /etc/hostname" "git checkout $B7 -- /etc/hostname"
ck_no "R8-3 (m2) no case folding: DB/SCHEMA.SQL" "git checkout $B7 -- DB/SCHEMA.SQL"
ck_no "R8-3 (N5) a backslash path in Bash is kept as is and does not match: db\\schema.sql" "git checkout $B7 -- db\\schema.sql"
ck_no "R8-3 an unresolvable word: \$UNSET_VAR_R8/schema.sql" "git checkout $B7 -- \$UNSET_VAR_R8/schema.sql"
ck_no "R8-3 an unresolvable word: a command substitution" "git checkout $B7 -- \$(echo $SC)"
# the source
rnew; rstart; BASE_FIRST="$BASE"
printf -- '-- later\n' >> "$R/README.md"; fxg "$R" add README.md; fxg "$R" commit -qm later   # HEAD is now NOT the baseline
flag "R8-3 source cases"
ck_no "R8-3 git checkout <an older commit> -- $SC (HEAD~2 is not BASE)" "git checkout HEAD~2 -- $SC"
ck_no "R8-3 git checkout HEAD -- $SC when HEAD is not BASE" "git checkout HEAD -- $SC"
ck_no "R8-3 git restore --source=HEAD $SC when HEAD is not BASE" "git restore --source=HEAD $SC"
ck_no "R8-3 git restore -s HEAD~2 $SC" "git restore -s HEAD~2 $SC"
ck_ok "R8-3 [today FAIL] ...while the real BASE still passes with HEAD ahead" "git checkout $BASE_FIRST -- $SC"
ck_no "R8-3 (m3) a rev starting with a dash: git restore --source=-q" "git restore --source=-q $SC"
ck_no "R8-3 (m3) a rev starting with a dash: git restore -s -q" "git restore -s -q $SC"
ck_no "R8-3 an unknown rev" "git checkout no-such-rev-r8 -- $SC"
ck_no "R8-3 two source words before --" "git checkout $B7 HEAD -- $SC"
ck_no "R8-3 a flagged-looking path with no pathspec: git restore --source=<b7>" "git restore --source=$B7"
# no state / wrong state
rboot; flag "R8-3 state files"
rm -f "$ST/$SID.dirty"
ck_no "R8-3 a flagged path with no <sid>.dirty file (unknown = block)" "git checkout $B7 -- $SC"
rboot; flag "R8-3 no restore file"
rm -f "$ST/$SID.restore"
ck_no "R8-3 no <sid>.restore file" "git checkout $B7 -- $SC"
rboot; flag "R8-3 no session id"
: > "$HL"; grun PB_HEADLESS=1 PB_EVAL_HOOK_LOG="$HL" -- "$(jbash "git checkout $B7 -- $SC" "$R" | sed 's/"session_id":"[^"]*",//')"
expect_block "R8-3 no session id in the hook JSON" git-discard
assert_eq "R8-3 no session id: no allow restore-flagged line" 0 "$(nallow)"
rboot; flag "R8-3 other session"
SID_SAVE="$SID"; SID="not-this-session"
ck_no "R8-3 another session id has no list" "git checkout $B7 -- $SC"
SID="$SID_SAVE"
# a path in the list that BASE does not hold (N3 ls-tree rule), tested with a hand-written list
rboot; flag "R8-3 ls-tree"
printf 'untracked at base\n' > "$R/nope.sql"
printf 'top %s\nnope.sql\n' "$TOP" >> "$ST/$SID.restore"
ck_no "R8-3 (N3) a listed path that is not in BASE's tree (nope.sql) blocks" "git checkout $B7 -- nope.sql"
# the lists carry the top: a list from another top is not trusted (B1)
rboot; flag "R8-3 foreign top"
printf 'top /some/other/worktree\n' > "$ST/$SID.restore.new"; sed -n '2,$p' "$ST/$SID.restore" >> "$ST/$SID.restore.new"; mv "$ST/$SID.restore.new" "$ST/$SID.restore"
ck_no "R8-3 (B1) .restore whose top line is another worktree blocks" "git checkout $B7 -- $SC"
rboot; flag "R8-3 foreign top dirty"
printf 'top /some/other/worktree\n' > "$ST/$SID.dirty.new"; sed -n '2,$p' "$ST/$SID.dirty" >> "$ST/$SID.dirty.new"; mv "$ST/$SID.dirty.new" "$ST/$SID.dirty"
ck_no "R8-3 (B1) .dirty whose top line is another worktree blocks" "git checkout $B7 -- $SC"

echo "R8-3 options: only a short allow-list passes (M2, N7)"
rboot; flag "R8-3 options"
for c in "git checkout -f $B7 -- $SC" "git checkout --force $B7 -- $SC" "git checkout -p $B7 -- $SC" "git checkout --patch $B7 -- $SC" \
  "git checkout --ours -- $SC" "git checkout --theirs -- $SC" "git checkout -m $B7 -- $SC" "git checkout --merge $B7 -- $SC" \
  "git checkout --overlay $B7 -- $SC" "git checkout --no-overlay $B7 -- $SC" "git checkout -q $B7 -- $SC" "git checkout --quiet $B7 -- $SC" \
  "git checkout -b newbranch $B7 -- $SC" "git checkout -B newbranch $B7 -- $SC" "git checkout --orphan x $B7 -- $SC" \
  "git checkout --pathspec-from-file=list $B7 -- $SC" "git checkout $B7 --pathspec-from-file=list -- $SC" "git checkout --pathspec-file-nul $B7 -- $SC" \
  "git checkout --conflict=merge $B7 -- $SC" "git checkout --recurse-submodules $B7 -- $SC" "git checkout --ignore-skip-worktree-bits $B7 -- $SC"; do
  ck_no "R8-3 option [$c]" "$c"
done
for c in "git restore --pathspec-from-file=list --source=$B7 $SC" "git restore --pathspec-from-file=list" "git restore --pathspec-file-nul --pathspec-from-file=list $SC" \
  "git restore -p $SC" "git restore --patch $SC" "git restore --conflict=merge $SC" "git restore --ours $SC" "git restore --theirs $SC" \
  "git restore -m $SC" "git restore --merge $SC" "git restore --overlay $SC" "git restore --no-overlay $SC" "git restore -q $SC" \
  "git restore --ignore-skip-worktree-bits $SC" "git restore --recurse-submodules $SC"; do
  ck_no "R8-3 option [$c]" "$c"
done
gx "git restore --staged $SC"; expect_pass "R8-3 [guard-rail] git restore --staged keeps today's rule (PASS, it does not touch the work tree)"
assert_eq "R8-3 --staged alone does not log the allow line" 0 "$(nallow)"

echo "R8-3 git global options and GIT_* variables (N1, N1')"
rboot; flag "R8-3 global options"
for c in "git -c core.worktree=x checkout $B7 -- $SC" "git -c foo.bar=1 checkout $B7 -- $SC" "git --git-dir=$R/.git checkout $B7 -- $SC" \
  "git --git-dir $R/.git --work-tree $R checkout $B7 -- $SC" "git --work-tree=$R checkout $B7 -- $SC" "git --namespace=x checkout $B7 -- $SC" \
  "git --exec-path=/x checkout $B7 -- $SC" "git --config-env=a.b=C checkout $B7 -- $SC" "git --bare checkout $B7 -- $SC" "git --no-pager checkout $B7 -- $SC" \
  "git -C $R -c a.b=c checkout $B7 -- $SC" "git -c a.b=c -C $R checkout $B7 -- $SC" \
  "GIT_DIR=$R/.git git checkout $B7 -- $SC" "GIT_WORK_TREE=$R git checkout $B7 -- $SC" "GIT_INDEX_FILE=$R/.git/index git checkout $B7 -- $SC" \
  "GIT_COMMON_DIR=$R/.git git checkout $B7 -- $SC" "GIT_OBJECT_DIRECTORY=$R/.git/objects git checkout $B7 -- $SC" \
  "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.worktree GIT_CONFIG_VALUE_0=/x git checkout $B7 -- $SC" "GIT_CONFIG_PARAMETERS=x git checkout $B7 -- $SC" \
  "GIT_ICASE_PATHSPECS=1 git restore $SC" "GIT_LITERAL_PATHSPECS=0 git restore $SC" "GIT_NAMESPACE=x git checkout $B7 -- $SC" \
  "env GIT_DIR=$R/.git git checkout $B7 -- $SC"; do
  ck_no "R8-3 [$c]" "$c"
done
# the hook process itself carries the variable (an agent's export may not reach it; the hook's own env is what the guard can see)
for v in "GIT_DIR=$R/.git" "GIT_WORK_TREE=$R" "GIT_INDEX_FILE=$R/.git/index" "GIT_COMMON_DIR=$R/.git" "GIT_OBJECT_DIRECTORY=$R/.git/objects" \
  "GIT_CONFIG_COUNT=0" "GIT_ICASE_PATHSPECS=0"; do
  ck_no "R8-3 (N1') the hook's own environment has ${v%%=*}" "git checkout $B7 -- $SC" "$v"
done
ck_ok "R8-3 [today FAIL] with none of them, the same command passes" "git checkout $B7 -- $SC"
ck_ok "R8-3 [today FAIL] several -C words (each stays inside the top)" "git -C $R -C db checkout $B7 -- schema.sql"
# another worktree of the same repo (B1)
rboot; flag "R8-3 other worktree"
fxg "$R" worktree add -q -b side-r8 "$R.wt" 2>/dev/null
if [ -d "$R.wt" ]; then
  printf -- '-- other wt edit\n' >> "$R.wt/$SC"
  ck_no "R8-3 (B1) git -C <other worktree> checkout <b7> -- $SC, path dirty there" "git -C $R.wt checkout $B7 -- $SC"
  CWDX="$R.wt"; ck_no "R8-3 (B1) hook cwd is the other worktree, path dirty there" "git checkout $B7 -- $SC"; CWDX=""
  ck_no "R8-3 (N1) git --work-tree=<other worktree> checkout <b7> -- $SC" "git --work-tree=$R.wt checkout $B7 -- $SC"
  ck_no "R8-3 (N1) GIT_WORK_TREE=<other worktree> git checkout <b7> -- $SC" "GIT_WORK_TREE=$R.wt git checkout $B7 -- $SC"
  git -C "$R.wt" checkout -q -- "$SC"; printf -- '-- other wt readme\n' >> "$R.wt/README.md"
  ck_no "R8-3 (B1) other worktree, $SC clean there but README.md dirty: still no allow" "git -C $R.wt checkout $B7 -- $SC"
  ck_ok "R8-3 [today FAIL] the session's own worktree still passes while the other one is dirty" "git checkout $B7 -- $SC"
  fxg "$R" worktree remove --force "$R.wt" 2>/dev/null
else
  t_skip 8 "R8-3 (B1) other-worktree cases: git worktree add failed on this host"
fi

echo "R8-3 SessionStart sources (N2, M3) and TOP changes (N6)"
rboot; flag "R8-3 compact"
grun PB_HEADLESS=1 -- "$(jstart "$R" "$SID" compact)" --session-start
ck_ok "R8-3 N2 [today FAIL] Stop block, then SessionStart compact: the restore still passes (same run)" "git checkout $B7 -- $SC"
assert_line "R8-3 N2 [today FAIL] compact leaves .restore alone" "$ST/$SID.restore" "$SC"
rboot; flag "R8-3 resume"
grun PB_HEADLESS=1 -- "$(jstart "$R" "$SID" resume)" --session-start
assert_line "R8-3 N2 [today FAIL] resume adds the current tracked change to .dirty" "$ST/$SID.dirty" "$SC"
ck_no "R8-3 N2 Stop block, then SessionStart resume: the restore of that path blocks" "git checkout $B7 -- $SC"
rboot; flag "R8-3 clear"
grun PB_HEADLESS=1 -- "$(jstart "$R" "$SID" clear)" --session-start
assert_line "R8-3 N2 [today FAIL] clear adds the current tracked change to .dirty" "$ST/$SID.dirty" "$SC"
ck_no "R8-3 N2 SessionStart clear: the restore of that path blocks" "git checkout $B7 -- $SC"
rboot; printf -- '-- user edit between turns\n' >> "$R/$SC"
grun PB_HEADLESS=1 -- "$(jstart "$R" "$SID" resume)" --session-start
assert_line "R8-3 M3 [today FAIL] a resume after the user edited $SC adds it to .dirty" "$ST/$SID.dirty" "$SC"
schema "$S_HEAD" "$S_ORD"; gs; expect_block "R8-3 M3 the drop is still blocked at Stop" schema-drop
ck_no "R8-3 M3 so the restore of $SC blocks" "git checkout $B7 -- $SC"
# a missing or unknown source counts as startup: first write wins, .dirty unchanged
rboot; flag "R8-3 no source"
grun PB_HEADLESS=1 -- "$(jstart "$R" "$SID" | sed 's/"source":"[^"]*",//')" --session-start
ck_ok "R8-3 N2 [today FAIL] SessionStart without a source field changes nothing (counts as startup)" "git checkout $B7 -- $SC"
grun PB_HEADLESS=1 -- "$(jstart "$R" "$SID" something-new)" --session-start
ck_ok "R8-3 N2 [today FAIL] an unknown source value changes nothing" "git checkout $B7 -- $SC"
grun PB_HEADLESS=1 -- "$(jstart "$R" "$SID" startup)" --session-start
ck_ok "R8-3 N2 [today FAIL] a second startup record changes nothing" "git checkout $B7 -- $SC"
# resume from another worktree top: unknown
rboot
fxg "$R" worktree add -q -b side-r8b "$R.wt" 2>/dev/null
if [ -d "$R.wt" ]; then
  grun PB_HEADLESS=1 -- "$(jstart "$R.wt" "$SID" resume)" --session-start
  assert_line "R8-3 N6 [today FAIL] a resume whose TOP differs from the 'top' line gives 'unknown'" "$ST/$SID.dirty" unknown
  GRUNDIR="$R"; flag "R8-3 resume in another top"
  ck_no "R8-3 N6 [guard-rail] with 'unknown' every restore blocks" "git checkout $B7 -- $SC"
  fxg "$R" worktree remove --force "$R.wt" 2>/dev/null
else
  t_skip 3 "R8-3 N6 resume-in-another-worktree cases: git worktree add failed on this host"
fi

echo "R8-3 give up removes the list (N6)"
rboot; drop
gs; expect_block "R8-3 giveup: Stop block 1" schema-drop
gs; expect_block "R8-3 giveup: Stop block 2" schema-drop
gs; expect_block "R8-3 giveup: Stop block 3" schema-drop
ck_ok "R8-3 giveup [today FAIL] before the give-up the restore still passes" "git checkout $B7 -- $SC"
gs
if [ "$RC" = 0 ] && has "$GERR" "gave up"; then t_ok "R8-3 giveup: the 4th Stop gives up"; else t_bad "R8-3 giveup: the 4th Stop gives up" "rc=$RC $OUT"; fi
assert_contains "R8-3 giveup: stop-giveup is logged" "$(cat "$HL")" "stop-giveup schema-drop"
assert_no_path "R8-3 giveup [guard-rail today, real once R8-2 writes it] stop-giveup removes <sid>.restore" "$ST/$SID.restore"
ck_no "R8-3 giveup: after the give-up the restore blocks (the guard stopped asking for it)" "git checkout $B7 -- $SC"

echo "R8-3 deleted file (N3)"
rboot; rm -f "$R/$SC"
gs; expect_block "R8-3 N3 rm db/schema.sql: the Stop block" schema-drop
assert_contains "R8-3 N3 the block gives the restore hint" "$GERR" "(restore: git checkout $B7 -- $SC)"
ck_ok "R8-3 N3 [today FAIL] rm: git checkout <b7> -- $SC passes (not a directory, present at BASE)" "git checkout $B7 -- $SC"
ck_ok "R8-3 N3 [today FAIL] rm: git restore $SC passes" "git restore $SC"
rboot; git -C "$R" rm -q "$SC"
gs; expect_block "R8-3 N3 git rm db/schema.sql: the Stop block" schema-drop
ck_ok "R8-3 N3 [today FAIL] git rm: git checkout <b7> -- $SC passes" "git checkout $B7 -- $SC"
ck_ok "R8-3 N3 [today FAIL] git rm: git restore --source=<b7> --worktree $SC passes" "git restore --source=$B7 --worktree $SC"

echo "R8-3 non-ASCII and whitespace paths (M1, N4)"
rnew; printf 'CREATE TABLE e1 (id INTEGER);\nCREATE TABLE e2 (id INTEGER);\n' > "$R/db/$E_ACUTE.sql"
fxg "$R" add -A; fxg "$R" commit -qm acute; printf -- '-- user tweak\n' >> "$R/db/$E_ACUTE.sql"; rstart
printf -- '-- user tweak\nCREATE TABLE e1 (id INTEGER);\n' > "$R/db/$E_ACUTE.sql"
gs; expect_block "R8-3 M1 a pre-session dirty non-ASCII schema file that Stop flags: the Stop block" schema-drop
assert_contains "R8-3 M1 the block names the non-ASCII path as raw bytes" "$GERR" "db/$E_ACUTE.sql"
ck_no "R8-3 M1 its restore blocks (dirty at start; quoted spelling must not hide it)" "git checkout $B7 -- db/$E_ACUTE.sql"
rnew; printf 'CREATE TABLE e1 (id INTEGER);\nCREATE TABLE e2 (id INTEGER);\n' > "$R/db/$E_ACUTE.sql"
fxg "$R" add -A; fxg "$R" commit -qm acute; rstart
printf 'CREATE TABLE e1 (id INTEGER);\n' > "$R/db/$E_ACUTE.sql"
gs; expect_block "R8-3 M1 a clean non-ASCII schema file that loses a table: the Stop block" schema-drop
ck_ok "R8-3 M1 [today FAIL] its restore passes (raw bytes, exact match)" "git checkout $B7 -- db/$E_ACUTE.sql"
# whitespace path: not listed, its restore blocks; the plain sibling's restore passes; a clean top-level schema.sql is not collateral
rnew; printf 'CREATE TABLE s1 (id INTEGER);\nCREATE TABLE s2 (id INTEGER);\n' > "$R/db/my schema.sql"
printf 'CREATE TABLE top1 (id INTEGER);\n' > "$R/schema.sql"
fxg "$R" add -A; fxg "$R" commit -qm spaces; rstart
printf 'CREATE TABLE s1 (id INTEGER);\n' > "$R/db/my schema.sql"
drop
gs; expect_block "R8-3 N4 whitespace path plus db/schema.sql: the Stop block" schema-drop
assert_contains "R8-3 N4 the block names the whitespace path" "$GERR" "db/my schema.sql"
assert_no_line "R8-3 N4 the whitespace path is not in the list" "$ST/$SID.restore" "db/my schema.sql"
assert_no_line "R8-3 N4 no word-split piece 'db/my' in the list" "$ST/$SID.restore" "db/my"
assert_no_line "R8-3 N4 no word-split piece 'schema.sql' in the list" "$ST/$SID.restore" "schema.sql"
assert_line "R8-3 N4 [today FAIL] the plain path IS in the list" "$ST/$SID.restore" "$SC"
ck_no "R8-3 N4 the whitespace path's own restore blocks" "git checkout $B7 -- 'db/my schema.sql'"
ck_no "R8-3 N4 its restore with two words blocks" "git checkout $B7 -- db/my schema.sql"
printf -- '-- later edit\n' >> "$R/schema.sql"
ck_no "R8-3 N4 a clean top-level schema.sql (piece of the split) with a later edit blocks" "git checkout $B7 -- schema.sql"
ck_ok "R8-3 N4 [today FAIL] the plain sibling $SC passes" "git checkout $B7 -- $SC"

echo "R8-3 PowerShell (R8-4)"
rboot; flag "R8-4"
pk_ok "R8-4 [today FAIL] PowerShell git checkout <b7> -- $SC" "git checkout $B7 -- $SC"
pk_ok "R8-4 (m2) [today FAIL] PowerShell git checkout <b7> -- db\\schema.sql" "git checkout $B7 -- db\\schema.sql"
pk_ok "R8-4 [today FAIL] PowerShell git restore db\\schema.sql" "git restore db\\schema.sql"
pk_ok "R8-4 [today FAIL] PowerShell git restore --source=<b7> --worktree $SC" "git restore --source=$B7 --worktree $SC"
pk_no "R8-4 PowerShell git checkout ." "git checkout ."
pk_no "R8-4 PowerShell git reset --hard" "git reset --hard"
pk_no "R8-4 PowerShell: a flagged and an unflagged modified path" "git checkout $B7 -- $SC README.md"
printf -- '-- edit\n' >> "$R/README.md"
pk_no "R8-4 PowerShell: README.md (modified, unflagged)" "git checkout $B7 -- README.md"
pk_ok "R8-4 [today FAIL] PowerShell: the flagged path alone passes with README.md modified" "git checkout $B7 -- $SC"
pk_no "R8-4 PowerShell: git checkout <other commit> -- $SC" "git checkout HEAD~1 -- $SC"
pk_no "R8-4 PowerShell: -c core.worktree=x" "git -c core.worktree=x checkout $B7 -- $SC"
pk_no "R8-4 PowerShell: --work-tree=x" "git --work-tree=$R checkout $B7 -- $SC"
pk_no "R8-4 PowerShell: a glob" "git checkout $B7 -- 'db\\*.sql'"
rnew; printf -- '-- user tweak\n' >> "$R/$SC"; rstart; flag "R8-4 dirty at start"
pk_no "R8-4 PowerShell: a path dirty at session start" "git checkout $B7 -- $SC"

echo "R8-3 hook log"
rboot; flag "hook log"
gx "git checkout $B7 -- $SC"
assert_contains "R8-3 [today FAIL] an allowed restore logs 'allow restore-flagged'" "$(cat "$HL")" "allow restore-flagged"
assert_not_contains "R8-3 an allowed restore does not log a git-discard block" "$(cat "$HL")" "block git-discard"
gx "git checkout ."
assert_contains "R8-3 [guard-rail] a blocked discard logs 'block git-discard'" "$(cat "$HL")" "block git-discard"
assert_not_contains "R8-3 a blocked discard does not log 'allow restore-flagged'" "$(cat "$HL")" "allow restore-flagged"

t_summary
