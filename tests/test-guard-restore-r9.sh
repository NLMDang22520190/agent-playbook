#!/usr/bin/env bash
# Fix round R9 (spec .agents/handoff/01-spec.md "## Revision 12"; decision D15): an allow-list around the restore.
# The guard lets the hinted restore pass (it already did, R8) but only when the command text around it is on a short allow-list:
#   R9-1 before the restore: only `cd <literal dir>` / `git status|diff|log|show` with literal plain words (PowerShell: cd / Set-Location / sl)
#   R9-2 the restore segment: no assignment prefix, no wrapper (env, sudo, nice, ...), redirections only 2>&1 / >&M / >/dev/null forms
#   R9-3 segments after the restore do not matter (| tail -5 passes)
#   R9-4 a headless Stop block with no restore hint (scan-capped only, migration only) removes <sid>.restore
# Each case runs in its own throwaway repo. The guard only reads the commands it is shown. The one thing this suite really runs is a
# command the guard ALLOWED (rrun refuses repos this suite did not make): a second worktree holds an uncommitted edit, and the edit
# must survive; so a guard regression that lets a wrapper/pushd/env bypass through shows as lost work, not only as a wrong verdict.
# "[R9]" marks a case of the new rules; "[guard-rail]" marks one that behaved the same before R9 and stays pinned.
# Which of the R9 cases fail against the pre-R9 guard is in .agents/handoff/02-tests-R9.md.
. "$(dirname "$0")/lib.sh"
. "$PB_ROOT/tests/guard-fixture.sh"

S_HEAD='-- the shop database (SQLite)'
S_ORD='CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER NOT NULL, created_at TEXT NOT NULL, total_cents INTEGER NOT NULL);'
HL="$GW/restore-r9-hook.log"
SN=0
CWDX=""
SC="db/schema.sql"
NL=$'\n'

rnew() {
  R="$(mk_tmp)/repo"; mk_schema_repo "$R" >/dev/null; GRUNDIR="$R"; CWDX=""; WT=""
  mkdir -p "$R/src"
  printf '%s\n' 'module.exports = { ordersOf: (db, id) => db.all("SELECT 1", [id]) };' > "$R/src/orders.js"
  fxg "$R" add -A; fxg "$R" commit -qm code
  SN=$((SN + 1)); SID="r9s$SN"
  ST="$(gcd "$R")/pb-guard"
  TOP="$(git -C "$R" rev-parse --show-toplevel)"
}
rstart() {
  BASE="$(git -C "$R" rev-parse HEAD)"; B7="$(printf '%s' "$BASE" | cut -c1-7)"
  grun PB_HEADLESS=1 -- "$(jstart "$R" "$SID" "${1:-startup}")" --session-start
}
rboot() { rnew; rstart; }
drop() { printf '%s\n' "$S_HEAD" "$S_ORD" > "$R/db/schema.sql"; }
gs() { local a="${1:-false}"; [ "$#" -gt 0 ] && shift; : > "$HL"; grun PB_HEADLESS=1 PB_EVAL_HOOK_LOG="$HL" "$@" -- "$(jstop "$R" "$SID" "$a")" --stop; }
gx() { local c="$1"; shift; : > "$HL"; grun PB_HEADLESS=1 PB_EVAL_HOOK_LOG="$HL" "$@" -- "$(jbash "$c" "${CWDX:-$R}" "$SID")"; }
gp() { local c="$1"; shift; : > "$HL"; grun PB_HEADLESS=1 PB_EVAL_HOOK_LOG="$HL" "$@" -- "$(jps "$c" "${CWDX:-$R}" "$SID")"; }
nallow() { grep -c 'allow restore-flagged' "$HL" 2>/dev/null || true; }
ck_ok() { local n="$1"; gx "$2" "${@:3}"; expect_pass "$n"; assert_eq "$n: one allow restore-flagged line" 1 "$(nallow)"; }
ck_no() { local n="$1"; gx "$2" "${@:3}"; expect_block "$n" git-discard; assert_eq "$n: no allow restore-flagged line" 0 "$(nallow)"; }
pk_ok() { local n="$1"; gp "$2" "${@:3}"; expect_pass "$n"; assert_eq "$n: one allow restore-flagged line" 1 "$(nallow)"; }
pk_no() { local n="$1"; gp "$2" "${@:3}"; expect_block "$n" git-discard; assert_eq "$n: no allow restore-flagged line" 0 "$(nallow)"; }
flag() { drop; gs; expect_block "$1: the Stop block" schema-drop; }
assert_line() { if [ -f "$2" ] && grep -Fxq -- "$3" "$2" 2>/dev/null; then t_ok "$1"; else t_bad "$1" "no line [$3] in $2: [$(cat "$2" 2>/dev/null | tr '\n' '|')]"; fi; }

# --- the data-survival harness ---------------------------------------------------------------------------------------------
# wtnew -> a second worktree $WT of R (same commit) with an uncommitted edit: the user's work that no restore may touch
wtnew() {
  WT="$R.wt"
  fxg "$R" worktree add -q -b "side-r9-$SN" "$WT" 2>/dev/null || { WT=""; return 1; }
  printf -- '-- USER WORK in the other worktree\n' >> "$WT/$SC"
}
wtedit() { [ -n "$WT" ] && grep -c 'USER WORK in the other worktree' "$WT/$SC" 2>/dev/null; }
# rrun CMD -> really runs CMD in R through bash (aliases on, stdin closed), only in a repo this suite made
rrun() {
  case "$R" in "$PB_TMPBASE"/pbtest.*/repo) ;; *) t_bad "rrun refuses a repo this suite did not make" "R=[$R]"; return 1 ;; esac
  [ -d "$R/.git" ] || { t_bad "rrun refuses a directory that is not a repo root" "R=[$R]"; return 1; }
  ( cd "$R" && "$GBASH" -O expand_aliases -c "$1" ) >/dev/null 2>&1 </dev/null
}
# ck_safe NAME CMD : the guard BLOCKS git-discard; and, in case it did not, the command is run for real and the other worktree's
# uncommitted edit must still be there (it is lost today if the guard lets the bypass through)
ck_safe() {
  local n="$1" c="$2"
  ck_no "$n" "$c"
  if [ -z "$WT" ]; then t_skip 1 "$n: no second worktree on this host"; return; fi
  [ "$RC" = 0 ] && rrun "$c"
  assert_eq "$n: the uncommitted edit in the other worktree survives" 1 "$(wtedit)"
  # put the edit back if a regression removed it, so later cases still start from the same state
  [ "$(wtedit)" = 1 ] || { git -C "$WT" checkout -q -- "$SC" 2>/dev/null; printf -- '-- USER WORK in the other worktree\n' >> "$WT/$SC"; }
}
# PS cases cannot be run for real here (no PowerShell): verdict only
ck_psno() { pk_no "$1" "$2"; }

echo "R9-1 blocked: a wrapper, pushd, a definition or an env write before / around the restore (review findings 1-4)"
rboot; flag "R9 setup"
wtnew
RS="git checkout $B7 -- $SC"
ck_safe "R9-1 [R9] env -C <wt> git checkout ..." "env -C $WT $RS"
ck_safe "R9-1 [R9] env --chdir=<wt> git checkout ..." "env --chdir=$WT $RS"
ck_safe "R9-1 [R9] sudo -D <wt> git checkout ..." "sudo -n -D $WT $RS"
ck_safe "R9-1 [R9] sudo -D <wt> (spec spelling, no -n)" "sudo -D $WT $RS"
ck_safe "R9-1 [R9] pushd <wt> && git checkout ..." "pushd $WT && $RS"
ck_safe "R9-1 [R9] pushd <wt>; git checkout ..." "pushd $WT; $RS"
ck_safe "R9-1 [R9] pushd <wt> >/dev/null; git checkout ..." "pushd $WT >/dev/null; $RS"
ck_safe "R9-1 [R9] shell function git() {...}; git checkout ..." "git() { command git -C $WT \"\$@\"; }; $RS"
ck_safe "R9-1 [R9] function git {...}; git checkout ..." "function git { command git -C $WT \"\$@\"; }; $RS"
ck_safe "R9-1 [R9] alias git='git -C <wt>' on its own line, then git checkout ..." "alias git='git -C $WT'${NL}$RS"
ck_safe "R9-1 [R9] export GIT_WORK_TREE=<wt>; git checkout ..." "export GIT_WORK_TREE=$WT; $RS"
ck_safe "R9-1 [R9] GIT_WORK_TREE=<wt>; git checkout ... (bare assignment)" "GIT_WORK_TREE=$WT; $RS"
ck_safe "R9-1 [R9] declare -x GIT_WORK_TREE=<wt>; git checkout ..." "declare -x GIT_WORK_TREE=$WT; $RS"
ck_safe "R9-1 [R9] echo hi && git checkout ... (an unknown command before)" "echo hi && $RS"
ck_safe "R9-1 [R9] true || git checkout ..." "true || $RS"
ck_safe "R9-1 [R9] echo hi | git checkout ..." "echo hi | $RS"
ck_safe "R9-1 [R9] a newline-separated unknown command before" "echo hi${NL}$RS"
ck_safe "R9-1 [R9] (cd <wt> && git checkout ...) a subshell" "(cd $WT && $RS)"
ck_safe "R9-1 [R9] { cd <wt>; git checkout ...; } a group" "{ cd $WT; $RS; }"
ck_safe "R9-1 [R9] cd <wt> && git checkout ... (the other worktree, dirty there; ambiguity A1 in the report)" "cd $WT && $RS"
ck_no "R9-1 [R9] cd \$UNSET_R9 && git checkout ... (not a literal dir)" "cd \$UNSET_R9 && $RS"
ck_no "R9-1 [R9] cd db extra && git checkout ... (two words are not one literal dir)" "cd db extra && $RS"
ck_no "R9-1 [R9] a read-only git with -c before: git -c core.worktree=x status; git checkout ..." "git -c core.worktree=x status; $RS"
ck_no "R9-1 [R9] git --git-dir=<x> status; git checkout ..." "git --git-dir=$R/.git status; $RS"
ck_no "R9-1 [R9] git --work-tree=<wt> diff; git checkout ..." "git --work-tree=$WT diff; $RS"
ck_no "R9-1 [R9] git --exec-path=/x log; git checkout ..." "git --exec-path=/x log; $RS"
ck_no "R9-1 [R9] git --namespace=x show; git checkout ..." "git --namespace=x show; $RS"
ck_no "R9-1 [R9] git --config-env=a.b=C status; git checkout ..." "git --config-env=a.b=C status; $RS"
ck_no "R9-1 [R9] an assignment before a read-only git: GIT_DIR=x git status; git checkout ..." "GIT_DIR=$R/.git git status; $RS"
ck_no "R9-1 [R9] git status \$(echo x); git checkout ... (a non-literal word)" "git status \$(echo x); $RS"
ck_no "R9-1 [R9] git stash; git checkout ... (git, but not one of the four read-only commands)" "git stash; $RS"
ck_no "R9-1 [R9] git config core.worktree <wt>; git checkout ..." "git config core.worktree $WT; $RS"
ck_no "R9-1 [R9] git status; echo hi; git checkout ... (the unknown one is in the middle)" "git status; echo hi; $RS"
[ -n "$WT" ] && fxg "$R" worktree remove --force "$WT" 2>/dev/null

echo "R9-1 blocked (PowerShell): env writes, function and alias definitions before the restore"
rboot; flag "R9 PS setup"
RP="git checkout $B7 -- db\\schema.sql"
ck_psno "R9-1 [R9] PS \$env:GIT_WORK_TREE='<wt>'; git checkout ..." "\$env:GIT_WORK_TREE='$R.wt'; $RP"
ck_psno "R9-1 [R9] PS Set-Item env:GIT_WORK_TREE '<wt>'; git checkout ..." "Set-Item env:GIT_WORK_TREE '$R.wt'; $RP"
ck_psno "R9-1 [R9] PS [Environment]::SetEnvironmentVariable('GIT_WORK_TREE','<wt>'); git checkout ..." "[Environment]::SetEnvironmentVariable('GIT_WORK_TREE','$R.wt'); $RP"
ck_psno "R9-1 [R9] PS \$env:GIT_DIR = 'x'; git checkout ..." "\$env:GIT_DIR = 'x'; $RP"
ck_psno "R9-1 [R9] PS function git {...}; git checkout ..." "function git { & git.exe -C $R.wt @args }; $RP"
ck_psno "R9-1 [R9] PS Set-Alias git foo; git checkout ..." "Set-Alias git foo; $RP"
ck_psno "R9-1 [R9] PS \$x = 1; git checkout ... (any assignment)" "\$x = 1; $RP"
ck_psno "R9-1 [R9] PS pushd <wt>; git checkout ..." "pushd $R.wt; $RP"
ck_psno "R9-1 [R9] PS Push-Location <wt>; git checkout ..." "Push-Location $R.wt; $RP"
ck_psno "R9-1 [R9] PS Write-Host hi; git checkout ... (unknown command before)" "Write-Host hi; $RP"
ck_psno "R9-1 [R9] PS git -c core.worktree=x status; git checkout ..." "git -c core.worktree=x status; $RP"

echo "R9-2 blocked: the restore segment itself (assignment prefix, wrapper, redirection) (findings 5, 8)"
rboot; flag "R9-2 setup"; wtnew
RS="git checkout $B7 -- $SC"
ck_safe "R9-2 [R9] HOME=/x git checkout ... (any assignment, not only GIT_*)" "HOME=/x $RS"
ck_safe "R9-2 [R9] XDG_CONFIG_HOME=/x git checkout ..." "XDG_CONFIG_HOME=/x $RS"
ck_safe "R9-2 [R9] FOO=1 git checkout ..." "FOO=1 $RS"
ck_safe "R9-2 [R9] nice git checkout ..." "nice $RS"
ck_safe "R9-2 [R9] nohup git checkout ..." "nohup $RS"
ck_safe "R9-2 [R9] time git checkout ..." "time $RS"
ck_safe "R9-2 [R9] exec git checkout ..." "exec $RS"
ck_safe "R9-2 [R9] eval \"git checkout ...\"" "eval \"$RS\""
ck_safe "R9-2 [R9] builtin command git checkout ..." "builtin command $RS"
ck_safe "R9-2 [R9] xargs git checkout ..." "echo $SC | xargs git checkout $B7 --"
ck_safe "R9-2 [R9] env git checkout ... (env alone is a wrapper)" "env $RS"
ck_safe "R9-2 [R9] a redirect to a file: git checkout ... > db/other.sql" "$RS > db/other.sql"
ck_safe "R9-2 [R9] a redirect to a file: ... >> db/other.sql" "$RS >> db/other.sql"
ck_safe "R9-2 [R9] a stderr redirect to a file: ... 2> db/other.sql" "$RS 2> db/other.sql"
ck_safe "R9-2 [R9] &> to a file: ... &> db/other.sql" "$RS &> db/other.sql"
ck_safe "R9-2 [R9] a redirect to /dev/null-like name: ... >/dev/nullx" "$RS >/dev/nullx"
ck_safe "R9-2 [R9] a leading redirect to a file: > db/other.sql git checkout ..." "> db/other.sql $RS"
ck_no "R9-2 [R9] an input redirect: git checkout ... < db/other.sql" "$RS < db/other.sql"
if [ -f "$R/db/other.sql" ]; then t_bad "R9-2 no db/other.sql was written by a blocked case" "exists"; else t_ok "R9-2 no db/other.sql was written by a blocked case"; fi
[ -n "$WT" ] && fxg "$R" worktree remove --force "$WT" 2>/dev/null

echo "R9-2 blocked (PowerShell): assignment, wrapper and redirection around the restore"
rboot; flag "R9-2 PS setup"
RP="git checkout $B7 -- db\\schema.sql"
ck_psno "R9-2 [R9] PS a redirect to a file: ... > db\\other.sql" "$RP > db\\other.sql"
ck_psno "R9-2 [R9] PS ... 2> err.txt" "$RP 2> err.txt"
ck_psno "R9-2 [R9] PS & { git checkout ... } (a script block)" "& { $RP }"
ck_psno "R9-2 [R9] PS Start-Process git (a wrapper)" "Start-Process git -ArgumentList 'checkout',$B7,'--','db\\schema.sql'"
ck_psno "R9-2 [R9] PS Invoke-Expression (eval)" "Invoke-Expression \"$RP\""

echo "R9-1/2/3 still passing: the hinted restore alone, after cd / read-only git, with the allowed redirections, before a later segment"
rboot; flag "R9 pass setup"
RS="git checkout $B7 -- $SC"
ck_ok "R9-2 [guard-rail] the bare hinted restore" "$RS"
ck_ok "R9-2 [R9] ... 2>&1" "$RS 2>&1"
ck_ok "R9-2 [R9] ... >/dev/null" "$RS >/dev/null"
ck_ok "R9-2 [R9] ... 2>/dev/null" "$RS 2>/dev/null"
ck_ok "R9-2 [R9] ... &>/dev/null" "$RS &>/dev/null"
ck_ok "R9-2 [R9] ... >/dev/null 2>&1" "$RS >/dev/null 2>&1"
ck_ok "R9-2 [R9] ... >&2" "$RS >&2"
ck_ok "R9-2 [R9] ... 2>&1 | tail -5 (R9-3: | tail is a later segment)" "$RS 2>&1 | tail -5"
ck_ok "R9-3 [R9] ... && echo done (a later segment is judged on its own)" "$RS && echo done"
ck_ok "R9-3 [R9] ... ; echo done" "$RS; echo done"
ck_ok "R9-1 [R9] cd db && git checkout <b7> -- schema.sql 2>&1 | tail" "cd db && git checkout $B7 -- schema.sql 2>&1 | tail"
ck_ok "R9-1 [R9] git status && git checkout ..." "git status && $RS"
ck_ok "R9-1 [R9] git diff --stat; git checkout ..." "git diff --stat; $RS"
ck_ok "R9-1 [R9] git log --oneline -3; git checkout ..." "git log --oneline -3; $RS"
ck_ok "R9-1 [R9] git show HEAD --stat; git checkout ..." "git show HEAD --stat; $RS"
ck_ok "R9-1 [R9] cd db; git status; git checkout <b7> -- schema.sql (cd then read-only git)" "cd db; git status; git checkout $B7 -- schema.sql"
ck_ok "R9-2 [guard-rail] command git checkout ... (already resolves to git)" "command $RS"
ck_ok "R9-2 [guard-rail] /usr/bin/git checkout ... (a path ending in /git)" "/usr/bin/git checkout $B7 -- $SC"
ck_ok "R9-2 [R9] git restore --source=<b7> --worktree ... 2>&1" "git restore --source=$B7 --worktree $SC 2>&1"
CWDX="$R/db"; ck_ok "R9-1 [R9] hook cwd db/: git checkout <b7> -- schema.sql 2>&1" "git checkout $B7 -- schema.sql 2>&1"; CWDX=""

echo "R9-1/2/3 still passing (PowerShell)"
pk_ok "R9-2 [R9] PS git checkout <b7> -- db\\schema.sql 2>&1" "git checkout $B7 -- db\\schema.sql 2>&1"
pk_ok "R9-2 [R9] PS ... *>&1" "git checkout $B7 -- db\\schema.sql *>&1"
pk_ok "R9-2 [R9] PS ... 2>\$null" "git checkout $B7 -- db\\schema.sql 2>\$null"
pk_ok "R9-2 [R9] PS ... >\$null" "git checkout $B7 -- db\\schema.sql >\$null"
pk_ok "R9-2 [R9] PS ... | Out-Null" "git checkout $B7 -- db\\schema.sql | Out-Null"
pk_ok "R9-1 [R9] PS Set-Location db; git checkout <b7> -- schema.sql" "Set-Location db; git checkout $B7 -- schema.sql"
pk_ok "R9-1 [R9] PS cd db; git checkout <b7> -- schema.sql" "cd db; git checkout $B7 -- schema.sql"
pk_ok "R9-1 [R9] PS sl db; git checkout <b7> -- schema.sql" "sl db; git checkout $B7 -- schema.sql"
pk_ok "R9-1 [R9] PS git status; git checkout ..." "git status; git checkout $B7 -- db\\schema.sql"
pk_ok "R9-2 [guard-rail] PS git.exe checkout ..." "git.exe checkout $B7 -- db\\schema.sql"

echo "R9-4 a headless Stop block with no restore hint removes <sid>.restore (finding 6)"
mkmany() { mkdir -p "$R/src/many"; local i=1; while [ "$i" -le "$1" ]; do printf 'module.exports = %d;\n' "$i" > "$R/src/many/$(printf 'f%04d' "$i").js"; i=$((i + 1)); done; }
# scan-capped only: first a schema-drop block (writes .restore), then the user restores, then 2100 clean untracked files push the scan over its cap
rboot; flag "R9-4 scan-capped"
assert_line "R9-4 [guard-rail] the first block wrote the restore list (names $SC)" "$ST/$SID.restore" "$SC"
git -C "$R" checkout -q "$BASE" -- "$SC"
mkmany 2100
gs; expect_block "R9-4 the next headless Stop blocks with scan-capped only" scan-capped
assert_not_contains "R9-4 the block has no restore hint" "$GERR" "(restore:"
assert_no_path "R9-4 [R9] a scan-capped-only block removes the stale <sid>.restore" "$ST/$SID.restore"
drop   # the tracked tree was cleaned by the user restore above: dirty the flagged path again, else no git-discard rule has anything to fire on
ck_no "R9-4 [R9] ...so the old restore command blocks again after the scan-capped Stop" "git checkout $B7 -- $SC"
# migration only
rboot; flag "R9-4 migration"
git -C "$R" checkout -q "$BASE" -- "$SC"
mkdir -p "$R/db/migrations"; printf 'DROP TABLE legacy_orders;\n' > "$R/db/migrations/001_drop.sql"
gs; expect_block "R9-4 the next headless Stop blocks with a migration finding only" migration-contract
assert_not_contains "R9-4 the migration block has no restore hint" "$GERR" "(restore:"
assert_no_path "R9-4 [R9] a migration-only block removes the stale <sid>.restore" "$ST/$SID.restore"
# an interactive Stop is not a headless block: it leaves .restore alone (R8-2, unchanged)
rboot; flag "R9-4 interactive"
mkmany 2100
grun PB_HEADLESS=0 -- "$(jstop "$R" "$SID")" --stop
assert_line "R9-4 [guard-rail] an interactive Stop leaves the existing restore list alone" "$ST/$SID.restore" "$SC"
# a block that does carry a hint still writes it (the removal must not hit it)
rboot; flag "R9-4 hint kept"; mkmany 2100
gs; expect_block "R9-4 a Stop with a schema-drop hint and scan-capped" schema-drop
assert_line "R9-4 [guard-rail] a block that has a restore hint keeps the list" "$ST/$SID.restore" "$SC"

echo "R10 (Revision 13): file redirections on the restore segment, and no restore list armed"
# R10-1: `>&FILE` / `>& FILE` is a file write (not an fd duplication), so the restore segment carries a forbidden redirection
rboot; flag "R10 setup"
ck_no "R10-1 [guard-rail] git checkout <b7> -- schema.sql >&f.txt blocks" "git checkout $B7 -- $SC >&f.txt"
ck_no "R10-1 [guard-rail] git checkout <b7> -- schema.sql >& f.txt blocks" "git checkout $B7 -- $SC >& f.txt"
ck_ok "R10-1 [guard-rail] git checkout <b7> -- schema.sql >&2 still passes (fd dup)" "git checkout $B7 -- $SC >&2"
# review MINOR 4: no <sid>.restore at all (the user was never flagged). Wrappers get the verdict the guard gave at cf7ccc2: rc=0, no hit
rboot; drop
assert_no_path "R10-4 setup: no <sid>.restore exists" "$ST/$SID.restore"
ck_nolist() { local n="$1"; gx "$2"; expect_pass "$n"; assert_eq "$n: no allow restore-flagged line" 0 "$(nallow)"; }
ck_nolist "R10-4 [guard-rail] no list, dirty tree: bash -c 'git checkout -- db/schema.sql'" "bash -c 'git checkout -- $SC'"
ck_nolist "R10-4 [guard-rail] no list, dirty tree: eval 'git checkout -- db/schema.sql'" "eval 'git checkout -- $SC'"
ck_nolist "R10-4 [guard-rail] no list, dirty tree: bash -c 'git checkout <b7> -- db/schema.sql'" "bash -c 'git checkout $B7 -- $SC'"
gx "git checkout -- $SC"; expect_block "R10-4 [guard-rail] no list: the plain discard blocks" git-discard
assert_eq "R10-4 no allow restore-flagged line for the plain discard" 0 "$(nallow)"
gx "git checkout $B7 -- $SC"; expect_block "R10-4 [guard-rail] no list: the plain restore blocks (nothing was flagged)" git-discard
assert_eq "R10-4 no allow restore-flagged line for the plain restore" 0 "$(nallow)"
pk_psno() { gp "$2"; expect_pass "$1"; assert_eq "$1: no allow restore-flagged line" 0 "$(nallow)"; }
pk_psno "R10-4 [guard-rail] no list, PS iex 'git checkout -- db/schema.sql'" "iex 'git checkout -- db\schema.sql'"
gp "git checkout -- db\schema.sql"; expect_block "R10-4 [guard-rail] no list, PS: the plain discard blocks" git-discard

echo "R2-D1a/b the git-discard block of a compound command that holds the hinted restore says the restore is allowed alone (messages only; D1 of revision 2)"
# Pins the AC text: "The restore itself is allowed: run exactly `git checkout <b7> -- db/schema.sql` as its own command, with nothing before or after it
# (cd is fine)." and no "Do not try another way". The allow/block verdicts are characterization: they are the same as before this slice.
rboot; drop; gs; expect_block "R2-D1b the headless Stop block" schema-drop
assert_contains "R2-D1b the Stop block hint says to run the restore as its own command" "$GERR" "as its own command"
D1CMD="git checkout $B7 -- $SC"
# d1chk NAME CMD [ps]: CMD is blocked (git-discard) and the message names the restore alone; the quoted command passes when run alone
d1chk() {
  local n="$1" c="$2" q
  if [ "${3:-}" = ps ]; then gp "$c"; else gx "$c"; fi
  expect_block "R2-D1c $n [characterization: still blocked]" git-discard
  assert_contains "R2-D1a $n: says the restore itself is allowed" "$GERR" "The restore itself is allowed"
  assert_contains "R2-D1a $n: gives the exact command in backticks" "$GERR" "\`$D1CMD\`"
  assert_contains "R2-D1a $n: as its own command" "$GERR" "as its own command"
  assert_contains "R2-D1a $n: nothing before or after it" "$GERR" "nothing before or after it"
  assert_not_contains "R2-D1a $n: no 'Do not try another way'" "$GERR" "Do not try another way"
  q="$(printf '%s\n' "$GERR" | sed -n 's/.*run exactly `\([^`]*\)`.*/\1/p' | sed -n 1p)"
  assert_eq "R2-D1c $n: the command quoted in the message is the hinted restore" "$D1CMD" "$q"
  if [ -n "$q" ]; then ck_ok "R2-D1c $n: the quoted command run alone passes" "$q"; else t_bad "R2-D1c $n: a command was quoted in the message" "$GERR"; fi
}
d1chk "the exact gate-run compound" "cd \"$R\" && git diff $SC > .agents/handoff/PENDING-schema-drop.patch && $D1CMD && git reset -q $SC && git status --short && npm test 2>&1 | grep x"
d1chk "only '> file' before" "git diff $SC > p.patch && $D1CMD"
# [characterization, R9-3] a restore with only segments AFTER it is allowed today (nothing to message); the allow-list is unchanged
ck_ok "R2-D1c [characterization, R9-3] only '&& npm test' after: passes (no message needed)" "$D1CMD && npm test"
ck_ok "R2-D1c [characterization, R9-3] only '; git status' after: passes" "$D1CMD; git status --short"
pk_ok "R2-D1c [characterization, R9-3] PowerShell '<restore>; git status' passes" "$D1CMD; git status --short"
d1chk "';' chain before" "git diff $SC > p.patch; $D1CMD"
d1chk "';' chain both sides" "git diff $SC > p.patch; $D1CMD; npm test"
d1chk "PowerShell: '> x; <restore>'" "git diff $SC > x; $D1CMD" ps
d1chk "PowerShell: '> x; <restore>; git status'" "git diff $SC > x; $D1CMD; git status --short" ps
ck_ok "R2-D1c [characterization] the hinted command alone passes" "$D1CMD"
ck_ok "R2-D1c [characterization] cd <dir> && <hinted command> passes (cd is fine)" "cd \"$R\" && $D1CMD"

echo "R2-D1a a compound command whose checkout path is NOT on the restore list keeps today's text"
rnew; printf '%s\n' 'module.exports = 1;' > "$R/src/app.js"; fxg "$R" add -A; fxg "$R" commit -qm app; rstart
drop; gs; expect_block "R2-D1a setup: the Stop block (restore list holds only $SC)" schema-drop
printf '%s\n' 'module.exports = 2;' > "$R/src/app.js"
for c in "cd \"$R\" && git checkout HEAD -- src/app.js && npm test" "git diff src/app.js > p.patch && git checkout HEAD -- src/app.js" "git checkout HEAD -- src/app.js; git status --short" "git checkout HEAD -- src/app.js"; do
  gx "$c"; expect_block "R2-D1a [characterization] not on the restore list, still blocked: $c" git-discard
  assert_contains "R2-D1a not on the restore list keeps 'Do not try another way': $c" "$GERR" "Do not try another way"
  assert_not_contains "R2-D1a not on the restore list does not claim a restore is allowed: $c" "$GERR" "The restore itself is allowed"
done
gp "git diff src/app.js > x; git checkout HEAD -- src/app.js"
expect_block "R2-D1a [characterization] PowerShell, not on the restore list, still blocked" git-discard
assert_contains "R2-D1a PowerShell, not on the restore list keeps 'Do not try another way'" "$GERR" "Do not try another way"

echo "R2-D1 a git-discard block with no restore list (nothing armed) keeps today's text"
rboot; printf '%s\n' '-- edit' >> "$R/$SC"
gx "git checkout HEAD -- $SC && npm test"; expect_block "R2-D1 [characterization] no restore list: blocked" git-discard
assert_contains "R2-D1 no restore list keeps 'Do not try another way'" "$GERR" "Do not try another way"
assert_not_contains "R2-D1 no restore list does not claim a restore is allowed" "$GERR" "The restore itself is allowed"


t_summary
