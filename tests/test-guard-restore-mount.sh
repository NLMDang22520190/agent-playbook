#!/usr/bin/env bash
# D4 (spec .agents/handoff/01-spec.md, slice S1): the restore exemption (restore_ok) and the D1 hint (d1_cmd) of scripts/guard-irreversible.sh
# must give the same verdict whatever form of the same directory the hook cwd uses. On Git for Windows the user's Temp dir is mounted as
# /tmp: git reports the toplevel as C:/Users/<u>/AppData/Local/Temp/X, `cd -P` + `pwd -P` of the mount form gives /tmp/X but of the drive
# form /c/Users/<u>/AppData/Local/Temp/X (pwd -P does not fold mounts), and the hook cwd may be given as /tmp/X, /c/Users/.../X or C:\...\X.
# The hinted restore `git checkout <base7> -- db/schema.sql`, run alone, must be allowed in all of them; everything blocked today stays
# blocked. Runs real Git Bash and the real guard, no stub of git, cd or pwd.
# "[today FAIL]" = fails before the fix; "[guard-rail]" = passes today and must stay (the allow-list must not widen).
# Skips with a printed reason only where there is no cygpath (Linux, macOS: AC6) or where no unfolded mount can be had (below).
# Where the mount comes from (AC7: it must RUN, not skip, in a Windows CI shard with real Git Bash):
#  1. /tmp when it already is a Git Bash mount that pwd -P leaves unfolded (a laptop with the "usertemp" mount): the repos live in /tmp.
#  2. otherwise (GitHub windows-latest: /tmp has the same physical path in both forms) a RUNTIME user mount: a mktemp dir under the drive
#     form of the temp base is mounted at /pbmnt.<pid> with `mount DIR /pbmnt.<pid>`, and the repos are built under that mount point.
#     The trap umounts it and removes the dir. No stub of git, cd or pwd.
# PB_MT_FORCE_RUNTIME=1 skips step 1 (used only to prove step 2 on a host where step 1 applies; it changes no assertion).
MT_MNT=""; MT_MNTDIR=""; MT_SRC=""; MT_PRESKIP=""
MT_OWNER="${BASHPID:-}"   # the process that made the mount/junction; a forked child running the trap must not undo them (as lib.sh t_cleanup; no BASHPID on bash 3.2: no guard)
mt_owner() { [ -z "${BASHPID:-}" ] || [ "$BASHPID" = "$MT_OWNER" ]; }
mt_mount_rm() {
  # umount only after t_cleanup removed the repos, then rmdir (never rm -rf) the now empty base dir, by a checked literal name
  mt_owner || return 0
  if [ -n "$MT_MNT" ]; then umount "$MT_MNT" >/dev/null 2>&1; MT_MNT=""; fi
  case "$MT_MNTDIR" in */pbmntbase.??????) rmdir "$MT_MNTDIR" 2>/dev/null ;; esac
  MT_MNTDIR=""
}
mt_physdiff() { # DIR_IN_MOUNT_FORM -> 0 when pwd -P of the mount form and of its drive form differ; sets MT_PM MT_PD MT_DRV
  local m
  m="$(cygpath -m "$1")"; MT_DRV="/$(printf '%s' "${m%%:*}" | tr 'A-Z' 'a-z')${m#?:}"
  MT_PM="$(cd -P -- "$1" 2>/dev/null && pwd -P)"; MT_PD="$(cd -P -- "$MT_DRV" 2>/dev/null && pwd -P)"
  [ -n "$MT_PM" ] && [ -n "$MT_PD" ] && [ "$MT_PM" != "$MT_PD" ]
}
if command -v cygpath >/dev/null 2>&1; then
  if [ -z "${PB_MT_FORCE_RUNTIME:-}" ] && [ -d /tmp ]; then
    _p="$(mktemp -d /tmp/pbmprobe.XXXXXX 2>/dev/null)"
    if [ -n "$_p" ] && mt_physdiff "$_p"; then MT_SRC="/tmp is already a mount that pwd -P leaves unfolded"; export TMPDIR=/tmp; fi
    case "$_p" in /tmp/pbmprobe.??????) rmdir "$_p" 2>/dev/null ;; esac
  fi
  if [ -z "$MT_SRC" ]; then
    _b="${TMPDIR:-/tmp}"; _bd="$(cygpath -m "$_b")"; _bd="/$(printf '%s' "${_bd%%:*}" | tr 'A-Z' 'a-z')${_bd#?:}"
    MT_MNTDIR="$(mktemp -d "$_bd/pbmntbase.XXXXXX" 2>/dev/null)"
    if [ -z "$MT_MNTDIR" ]; then MT_PRESKIP="cannot make a directory under the temp base [$_bd] to mount"
    else
      _mp="/pbmnt.$$"
      mount "$(cygpath -m "$MT_MNTDIR")" "$_mp" >/dev/null 2>&1   # the source must be a Windows (mixed) path: a POSIX one gives EINVAL
      if mount 2>/dev/null | grep -q " on $_mp type "; then
        MT_MNT="$_mp"
        trap mt_mount_rm EXIT; trap 'mt_mount_rm; exit 130' INT; trap 'mt_mount_rm; exit 143' TERM   # early trap: lib.sh (mktemp || exit 3) or a signal before the full trap below must not leak the mount; replaced by mt_cleanup after lib.sh
        if mt_physdiff "$MT_MNT"; then MT_SRC="runtime mount $MT_MNT -> $MT_MNTDIR"; export TMPDIR="$MT_MNT"
        else MT_PRESKIP="the runtime mount [$MT_MNT] was made but pwd -P gives [$MT_PM] / [$MT_PD] for its mount and drive forms: no unfolded mount here"; fi
      else MT_PRESKIP="the runtime mount of [$MT_MNTDIR] at [$_mp] could not be made"; fi
    fi
  fi
fi
. "$(dirname "$0")/lib.sh"
. "$PB_ROOT/tests/guard-fixture.sh"
MT_JUNC=""
mt_junc_rm() {
  # a directory junction is removed with rmdir so that no recursive delete ever walks through it
  mt_owner || return 0
  if [ -n "$MT_JUNC" ]; then cmd //c "rmdir $(cygpath -w "$MT_JUNC")" >/dev/null 2>&1; MT_JUNC=""; fi
}
mt_cleanup() { mt_junc_rm; t_cleanup; mt_mount_rm; }
trap mt_cleanup EXIT
trap 'mt_cleanup; exit 130' INT
trap 'mt_cleanup; exit 143' TERM

# ---- probe: is there a mount that pwd -P does not fold? (AC6) ----
MT_SKIP=""
if ! command -v cygpath >/dev/null 2>&1; then
  MT_SKIP="no cygpath: this is not MSYS/Cygwin (Git Bash), there is no Windows drive/mount mix of one directory"
elif [ -n "$MT_PRESKIP" ]; then MT_SKIP="$MT_PRESKIP"
else
  PD="$(mk_tmp)"
  if ! mt_physdiff "$PD"; then MT_SKIP="the temp dir [$PD] has no unfolded mount form here (mount form [$MT_PM], drive form [$MT_PD])"; fi
  _pm="$MT_PM"; _pd="$MT_PD"
fi
if [ -n "$MT_SKIP" ]; then
  t_skip 100 "AC6 mount cases not run: $MT_SKIP"
  t_summary
  exit $?
fi
echo "mount probe: source: $MT_SRC; mount form [$_pm] vs drive form [$_pd] (pwd -P differs: the defect class exists on this host)"

HL="$GW/mount-hook.log"
SN=0
SC="db/schema.sql"
S_HEAD='-- the shop database (SQLite)'
S_ORD='CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER NOT NULL, created_at TEXT NOT NULL, total_cents INTEGER NOT NULL);'
MARK2='-- USER WORK after the Stop block (not on the restore list)'
CWDX=""    # the hook cwd for gx
SCW=""     # the hook cwd for the session start and the Stop hook (default: the mount form)

# fm FORM PATH -> PATH (given in the mount form) spelled as FORM: mount | drive | win | case (drive form, lower-cased)
fm() {
  local m d
  case "$1" in
    mount) printf '%s' "$2" ;;
    win) cygpath -w "$2" ;;
    drive | case)
      m="$(cygpath -m "$2")"; d="/$(printf '%s' "${m%%:*}" | tr 'A-Z' 'a-z')${m#?:}"
      if [ "$1" = case ]; then printf '%s' "$d" | tr 'A-Z' 'a-z'; else printf '%s' "$d"; fi ;;
  esac
}
# tg FORM -> the label of a positive case: the mount form already works at baseline, the others do not
# (layout-dependent: the mount form works at baseline where /tmp is the usertemp mount, because the old guard folds a C:/ toplevel back to /tmp/..;
#  under a runtime mount /pbmnt.N it is folded back only if the base dir is inside Temp (this laptop); on a CI-like layout (base outside Temp)
#  the old guard also passes the mount-form cases, so their [today FAIL] label is right only on the laptop layout. No assertion depends on the label)
tg() { if [ "$1" = mount ] && [ -z "$MT_MNT" ]; then printf '[guard-rail]'; else printf '[today FAIL]'; fi; }

gs() { local a="${1:-false}"; [ "$#" -gt 0 ] && shift; : > "$HL"; grun PB_HEADLESS=1 PB_EVAL_HOOK_LOG="$HL" "$@" -- "$(jstop "${SCW:-$R}" "$SID" "$a")" --stop; }
gx() { local c="$1"; shift; : > "$HL"; grun PB_HEADLESS=1 PB_EVAL_HOOK_LOG="$HL" "$@" -- "$(jbash "$c" "${CWDX:-$R}" "$SID")"; }
nallow() { grep -c 'allow restore-flagged' "$HL" 2>/dev/null || true; }
ck_ok() { local n="$1"; gx "$2" "${@:3}"; expect_pass "$n"; assert_eq "$n: one allow restore-flagged line" 1 "$(nallow)"; }
# slurp FILE -> its bytes in SLURP (trailing newlines kept)
slurp() { SLURP="$(cat "$1" 2>/dev/null; printf x)"; SLURP="${SLURP%x}"; }
# ck_blk NAME CMD GUARDED_FILE -> the guard must block (git-discard). If it says allow, CMD is run for real in the repo (mount form) and
# the check is that GUARDED_FILE is unchanged, so the data loss is caught; then the file is put back and the block is asserted again.
ck_blk() {
  local n="$1" c="$2" f="$3" real
  gx "$c"; real="$RC"
  if [ "$real" = 0 ]; then
    slurp "$f"; local before="$SLURP"
    ( cd "$R" && "$GBASH" -c "$c" ) >/dev/null 2>&1
    slurp "$f"; assert_eq "$n: GUARDED FILE UNCHANGED (the guard allowed it, ran for real)" "$before" "$SLURP"
    printf '%s' "$before" > "$f"
    gx "$c"
  fi
  expect_block "$n" git-discard
  assert_eq "$n: no allow restore-flagged line" 0 "$(nallow)"
}

# rboot NAME [del] -> repo under the mount, tracked notes.txt and a/keep, session start, the E13 edit (or db/ deleted), Stop block.
# Sets R (mount form), TOP (as git prints it), BASE, B7, SID. After the Stop block notes.txt gets an edit that is NOT on the restore list.
rboot() {
  R="$(mk_tmp)/repo"; mk_schema_repo "$R" >/dev/null; GRUNDIR="$R"; CWDX=""
  SN=$((SN + 1)); SID="mt$SN"
  mkdir -p "$R/a"; printf 'k\n' > "$R/a/keep"; printf 'notes\n' > "$R/notes.txt"
  fxg "$R" add -A 2>/dev/null; fxg "$R" commit -qm more 2>/dev/null
  TOP="$(git -C "$R" rev-parse --show-toplevel)"
  BASE="$(git -C "$R" rev-parse HEAD)"; B7="$(printf '%s' "$BASE" | cut -c1-7)"
  grun PB_HEADLESS=1 -- "$(jstart "${SCW:-$R}" "$SID" startup)" --session-start
  if [ "${2:-}" = del ]; then rm -rf "$R/db"; else printf '%s\n' "$S_HEAD" "$S_ORD" > "$R/$SC"; fi
  gs; expect_block "$1: the Stop block" schema-drop
  printf '%s\n' "$MARK2" >> "$R/notes.txt"
}

echo "setup sanity: git's toplevel is the C:/ form for every cwd form, the three forms are one directory"
rboot "setup"
case "$TOP" in [A-Za-z]:/*) t_ok "setup: git prints the toplevel as a drive path [$TOP]" ;; *) t_bad "setup: git prints the toplevel as a drive path" "TOP=[$TOP]" ;; esac
for F in mount drive win; do
  assert_eq "setup: git -C <$F form> gives the same toplevel" "$TOP" "$(git -C "$(fm $F "$R")" rev-parse --show-toplevel 2>/dev/null)"
done
assert_eq "setup: pwd -P of the mount form and of the drive form differ (the defect class)" 1 "$([ "$(cd -P -- "$R" && pwd -P)" != "$(cd -P -- "$(fm drive "$R")" && pwd -P)" ] && echo 1 || echo 0)"

echo "AC1 the hinted restore alone is allowed in the mount, drive and Windows forms"
rboot "AC1"
for F in mount drive win; do
  CWDX="$(fm $F "$R")"
  ck_ok "AC1 $(tg $F) $F cwd [$CWDX]: git checkout <b7> -- $SC" "git checkout $B7 -- $SC"
  ck_ok "AC1 $(tg $F) $F cwd: git restore $SC" "git restore $SC"
done

echo "AC1b the hinted restore with a case-variant drive-form cwd (only where the disk is case-insensitive)"
CWDX="$(fm case "$R")"
if [ -d "$CWDX" ] && [ "$(cd -P -- "$CWDX" && git rev-parse --show-toplevel 2>/dev/null)" = "$TOP" ]; then
  ck_ok "AC1b [today FAIL] case-variant cwd [$CWDX]: git checkout <b7> -- $SC" "git checkout $B7 -- $SC"
  ck_blk "AC1b [guard-rail] case-variant cwd: a path not on the list (notes.txt) still blocks" "git checkout $B7 -- notes.txt" "$R/notes.txt"
else
  t_skip 5 "AC1b the disk is case-sensitive here (or [$CWDX] is not the repo): the case-variant cwd cannot be built"
fi

echo "AC2 a tracked path NOT on the restore list is blocked in every cwd form"
for F in mount drive win; do
  CWDX="$(fm $F "$R")"
  ck_blk "AC2 [guard-rail] $F cwd: git checkout <b7> -- notes.txt" "git checkout $B7 -- notes.txt" "$R/notes.txt"
  ck_blk "AC2 [guard-rail] $F cwd: git restore notes.txt" "git restore notes.txt" "$R/notes.txt"
  ck_blk "AC2 [guard-rail] $F cwd: git checkout . still blocks" "git checkout ." "$R/notes.txt"
  ck_blk "AC2 [guard-rail] $F cwd: git checkout <b7> -- a/keep (clean tracked, not on the list)" "git checkout $B7 -- a/keep" "$R/notes.txt"
done

echo "AC2b the guard's own D1 form: cd '<TOP as git prints it>' && restore, from a subdirectory, in every cwd form"
for F in mount drive win; do
  CWDX="$(fm $F "$R/a")"
  ck_ok "AC2b [today FAIL] $F cwd (subdir a): cd '$TOP' && git checkout <b7> -- $SC" "cd '$TOP' && git checkout $B7 -- $SC"
  ck_blk "AC2b [guard-rail] $F cwd (subdir a): the same cd form with notes.txt blocks" "cd '$TOP' && git checkout $B7 -- notes.txt" "$R/notes.txt"
done

echo "AC3b a '..' pathspec that leaves TOP, in every cwd form"
mkdir -p "$(dirname "$R")/out/db"; printf 'OUTSIDE-FILE\n' > "$(dirname "$R")/out/db/schema.sql"
for F in mount drive win; do
  CWDX="$(fm $F "$R/a")"
  ck_blk "AC3b [guard-rail] $F cwd (subdir a): git checkout <b7> -- ../../out/db/schema.sql" "git checkout $B7 -- ../../out/db/schema.sql" "$(dirname "$R")/out/db/schema.sql"
  ck_blk "AC3b [guard-rail] $F cwd (subdir a): git checkout <b7> -- ../../repo/../out/db/schema.sql" "git checkout $B7 -- ../../repo/../out/db/schema.sql" "$(dirname "$R")/out/db/schema.sql"
done

echo "AC3b a directory deleted this session: the listed path is allowed, a path not on the list blocks, in every cwd form"
rboot "AC3b del" del
for F in mount drive win; do
  CWDX="$(fm $F "$R")"
  ck_ok "AC3b $(tg $F) $F cwd, db/ deleted: git checkout <b7> -- $SC (listed, parent missing)" "git checkout $B7 -- $SC"
  ck_blk "AC3b [guard-rail] $F cwd, db/ deleted: db/nosuch.sql (not on the list) blocks" "git checkout $B7 -- db/nosuch.sql" "$R/notes.txt"
  ck_blk "AC3b [guard-rail] $F cwd, db/ deleted: db/gone/x.sql (missing tail, not on the list) blocks" "git checkout $B7 -- db/gone/x.sql" "$R/notes.txt"
done

echo "AC3 / AC3w a link inside the repo that leads outside TOP still blocks in every cwd form"
rboot "AC3"
PD2="$(mk_tmp)"; mkdir "$PD2/d"; ln -s d "$PD2/l" 2>/dev/null
OUTD="$(dirname "$R")/outd"; mkdir -p "$OUTD"
LINKKIND=""
mv "$R/db" "$OUTD/db"
if [ -L "$PD2/l" ]; then
  ln -s "$OUTD/db" "$R/db" 2>/dev/null; [ -L "$R/db" ] && LINKKIND=symlink
else
  # AC3w: Git Bash without symlink rights; a directory junction is used if cd -P resolves it
  if cmd //c "mklink /J $(cygpath -w "$R/db") $(cygpath -w "$OUTD/db")" >/dev/null 2>&1 && [ -d "$R/db" ]; then
    MT_JUNC="$R/db"
    _jp="$(cd -P -- "$R/db" 2>/dev/null && pwd -P)"
    _op="$(cd -P -- "$OUTD/db" 2>/dev/null && pwd -P)"
    if [ -n "$_jp" ] && { [ "$_jp" = "$_op" ] || [ "$(cygpath -m "$_jp")" = "$(cygpath -m "$_op")" ]; }; then LINKKIND=junction   # one directory, whatever mount spells it
    else printf '  note: junction made but cd -P does not resolve it (cd -P gives [%s], target [%s]) [D3]\n' "$_jp" "$_op"; fi
  else printf '  note: mklink /J failed [D3]\n'; fi
fi
if [ -n "$LINKKIND" ]; then
  echo "  ($LINKKIND: $R/db -> $OUTD/db)"
  for F in mount drive win; do
    CWDX="$(fm $F "$R")"
    ck_blk "AC3 [guard-rail] $F cwd, db -> outside TOP ($LINKKIND): git checkout <b7> -- $SC" "git checkout $B7 -- $SC" "$OUTD/db/schema.sql"
    ck_blk "AC3 [guard-rail] $F cwd, db -> outside TOP ($LINKKIND): git restore $SC" "git restore $SC" "$OUTD/db/schema.sql"
    ck_blk "AC3 [guard-rail] $F cwd, db -> outside TOP ($LINKKIND): cd db && git checkout <b7> -- schema.sql" "cd db && git checkout $B7 -- schema.sql" "$OUTD/db/schema.sql"
  done
else
  t_skip 9 "AC3w no symlink and no junction that cd -P resolves on this host: AC3 stays covered by the Linux/macOS symlink suites (D3)"
fi
mt_junc_rm

echo "AC4 the headless E13 path end to end with a drive-form cwd (/c/...) for session start, Stop and the restore"
SCW=""
R="$(mk_tmp)/repo"; mk_schema_repo "$R" >/dev/null; GRUNDIR="$R"
SN=$((SN + 1)); SID="mt$SN"
RD="$(fm drive "$R")"; SCW="$RD"; CWDX="$RD"
BASE="$(git -C "$R" rev-parse HEAD)"; B7="$(printf '%s' "$BASE" | cut -c1-7)"
grun PB_HEADLESS=1 -- "$(jstart "$RD" "$SID" startup)" --session-start
_SCH="$(sed '3,4d' "$R/$SC"; printf x)"; printf '%s' "${_SCH%x}" > "$R/$SC"
gs; expect_block "AC4: headless Stop blocks on the schema drop (drive-form cwd)" schema-drop
HINT="$(printf '%s\n' "$GERR" | sed -n 's/^(restore: \(.*\))$/\1/p' | sed -n 1p)"
assert_eq "AC4: the printed hint" "git checkout $B7 -- $SC" "$HINT"
ck_ok "AC4 [today FAIL] the printed hint passes alone with a drive-form cwd" "$HINT"
( cd "$RD" && "$GBASH" -c "$HINT" ) >/dev/null 2>&1
assert_eq "AC4: the hint restored the file (git status clean)" "" "$(git -C "$R" status --porcelain)"
gs true; expect_pass "AC4: the next Stop passes (no Stop block)"
SCW=""

echo "AC5 D1 message: a blocked compound command holding the hinted restore, hook cwd = TOP itself in each form"
rboot "AC5"
for F in mount drive win; do
  CWDX="$(fm $F "$R")"
  gx "git diff $SC > p.patch && git checkout $B7 -- $SC"
  expect_block "AC5 $F cwd: the compound stays blocked [characterization]" git-discard
  q="$(printf '%s\n' "$GERR" | sed -n 's/.*run exactly `\([^`]*\)`.*/\1/p' | sed -n 1p)"
  assert_eq "AC5 $(tg $F) $F cwd = TOP: the hinted restore has no 'cd <TOP> &&' prefix" "git checkout $B7 -- $SC" "$q"
done
# AC5 from a subdir: the pathspec is written relative to the cwd (../db/schema.sql names TOP/db/schema.sql, which is on the list;
# a bare db/schema.sql from a/ names a/db/schema.sql, which is not, so no hint is correct there). TOP is quoted the way the guard's
# shq quotes it: only when it holds a character outside [A-Za-z0-9._/@%+=:,-].
case "$TOP" in *[!A-Za-z0-9._/@%+=:,-]*) QTOP="'$TOP'" ;; *) QTOP="$TOP" ;; esac
for F in mount drive; do
  CWDX="$(fm $F "$R/a")"
  gx "git diff ../$SC > p.patch && git checkout $B7 -- ../$SC"
  expect_block "AC5 $F cwd in subdir a: the compound stays blocked [characterization]" git-discard
  q="$(printf '%s\n' "$GERR" | sed -n 's/.*run exactly `\([^`]*\)`.*/\1/p' | sed -n 1p)"
  assert_eq "AC5 [today FAIL] $F cwd in a SUBDIR of TOP: the hint names the top with cd first" "cd $QTOP && git checkout $B7 -- $SC" "$q"
done
t_summary
