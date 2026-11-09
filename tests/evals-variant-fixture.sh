#!/usr/bin/env bash
# shellcheck shell=bash
# Sourced by tests/test-evals-variant.sh and tests/test-evals-variant-b.sh: the shared setup, helpers and fakes of the --variant suites.
# Tests for evals/run-evals.sh --variant DIR (v0.31 slice S1, spec .agents/handoff/01-spec.md AC1-AC8, AC9 synopsis only):
# the runner snapshots the install targets of the harness home H, installs DIR into H, runs, and puts the snapshot back.
# Never calls a real harness and never touches a real home: HOME, PB_VARIANT_HOME and PLAYBOOK_REGISTRY are temp dirs/files,
# the "claude" on PATH is a fake that records what the home looked like when it ran, and DIR/install.sh is a fake
# whose behaviour is switched by marker files in DIR (.m-fail-install, .m-fail-doctor, .m-wrong-version, .m-extra, .m-lock-skills).
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-arms-fixture.sh"   # jget, row_of, alive, PBH, and idle adapters; its own fakes/home are not used here

VFK="$(mk_tmp)"   # the fake harness binaries and the runner wrapper
VBASE="--harness claude --scenarios E8"

# ---- the fake claude (also copied as codex and opencode): records the home as it is when a run starts ----
cat > "$VFK/claude" <<'EOF'
#!/usr/bin/env bash
H="${VFAKE_H:-$HOME}"
probe=0
for a in "$@"; do case "$a" in *"$VFAKE_PBH"*) probe=1 ;; esac; done
ver="$(tr -d ' \r\n' < "$H/.agents/playbook/VERSION" 2>/dev/null)"; [ -n "$ver" ] || ver=none
cs="$(ls "$H/.claude/skills" 2>/dev/null | tr '\n' ,)"; as="$(ls "$H/.agents/skills" 2>/dev/null | tr '\n' ,)"
vs="$(head -n 1 "$H/.claude/skills/varskill/SKILL.md" 2>/dev/null)"
blk="$(grep -c VARIANT-BLOCK "$H/.claude/CLAUDE.md" 2>/dev/null)"
bk="$(ls "$H/.agents/playbook-backups" 2>/dev/null | tr '\n' ,)"
if [ "$probe" = 1 ]; then
  printf 'probe ver=%s\n' "$ver" >> "$VFAKE_LOG"
  sj=0; for a in "$@"; do [ "$a" = stream-json ] && sj=1; done
  if [ "$sj" = 1 ]; then
    echo '{"type":"system","subtype":"init","session_id":"p1","skills":[],"slash_commands":[]}'
    echo '{"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.001,"result":"NO"}'
  else echo NO; fi
  exit 0
fi
printf 'run ver=%s cskills=%s askills=%s varskill=[%s] block=%s bk=%s\n' "$ver" "$cs" "$as" "$vs" "$blk" "$bk" >> "$VFAKE_LOG"
if [ -n "${VFAKE_TAMPER:-}" ]; then printf '0.0.0-tampered\n' > "$H/.agents/playbook/VERSION"; fi
if [ -n "${VFAKE_EDIT:-}" ]; then printf 'USER EDIT\n' >> "$VFAKE_EDIT"; fi   # the user edits a block file while the run is on
if [ -n "${VFAKE_BKNEW:-}" ]; then   # someone else makes a backup in the home's backup dir while the run is on
  mkdir -p "$H/.agents/playbook-backups/$VFAKE_BKNEW-dir"; printf 'foreign\n' > "$H/.agents/playbook-backups/$VFAKE_BKNEW"; printf 'foreign\n' > "$H/.agents/playbook-backups/$VFAKE_BKNEW-dir/f"
fi
if [ -n "${VFAKE_CREATE:-}" ]; then mkdir -p "$(dirname "$VFAKE_CREATE")"; printf 'MINE created in the run\n' > "$VFAKE_CREATE"; fi   # the user creates or overwrites a file while the run is on
if [ -n "${VFAKE_SLEEP:-}" ]; then
  echo $$ > "$VFAKE_DIR/sleeper.pid"; : > "$VFAKE_DIR/started"
  exec sleep 120
fi
echo '{"type":"system","subtype":"init","session_id":"s1","skills":[],"slash_commands":[]}'
echo '{"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.01,"result":"Done."}'
exit 0
EOF
cp "$VFK/claude" "$VFK/codex"; cp "$VFK/claude" "$VFK/opencode"; chmod 755 "$VFK/claude" "$VFK/codex" "$VFK/opencode"

# ---- the runner wrapper: environment from VW_* variables, then exec (so $! of a background start is the runner's pid) ----
cat > "$VFK/runner.sh" <<'EOF'
#!/usr/bin/env bash
unset PLAYBOOK_HOME PB_EVAL_ARM PB_EVAL_MODEL PB_EVAL_SETTINGS
export HOME="$VW_HOME" PATH="${VW_SHIM:+$VW_SHIM:}$VW_FK:$PATH"
if [ -n "${VW_VHOME:-}" ]; then export PB_VARIANT_HOME="$VW_VHOME"; else unset PB_VARIANT_HOME; fi
if [ -n "${VW_REG:-}" ]; then export PLAYBOOK_REGISTRY="$VW_REG"; else unset PLAYBOOK_REGISTRY; fi
if [ -n "${VW_INTDFL:-}" ]; then exec perl -e '$SIG{INT} = "DEFAULT"; exec @ARGV' bash "$VW_RUNNER" --workroot "$VW_WR" --out "$VW_RES" "$@"; fi
exec bash "$VW_RUNNER" --workroot "$VW_WR" --out "$VW_RES" "$@"
EOF
chmod 755 "$VFK/runner.sh"
export VW_FK="$VFK" VW_RUNNER="$RUNNER" VFAKE_PBH="$PBH"
VREG="$(mk_tmp)/registry"; printf 'SENTINEL\n' > "$VREG"

# ---- fixtures ----
# mk_variant -> VD: a variant tree with VERSION 1.2.3-variant, skills playbook-vskill and varskill (a non-prefixed skill dir
# holding SKILL.md), and an install.sh that logs every call to $VD/.calls and obeys the marker files .m-*
mk_variant() {
  VD="$(mk_tmp)"
  mkdir -p "$VD/skills/playbook-vskill" "$VD/skills/varskill" "$VD/scripts"
  printf '1.2.3-variant\n' > "$VD/VERSION"
  printf 'variant skill\n' > "$VD/skills/playbook-vskill/SKILL.md"
  printf 'variant varskill\n' > "$VD/skills/varskill/SKILL.md"
  printf '#!/bin/sh\necho variant\n' > "$VD/scripts/vmark"
  cat > "$VD/install.sh" <<'EOF'
#!/usr/bin/env bash
D="$(cd "$(dirname "$0")" && pwd)"
ALL="$*"; cmd="$1"; shift
H=""; HAR=""
while [ $# -gt 0 ]; do case "$1" in --home) H="$2"; shift ;; --harness) HAR="$2"; shift ;; esac; shift; done
printf '%s|registry=%s|\n' "$cmd $ALL" "${PLAYBOOK_REGISTRY-UNSET}" >> "$D/.calls"
printf '%s|PB_HOOKS=%s|\n' "$cmd" "${PB_HOOKS-UNSET}" >> "$D/.env"   # v0.33 AC5': what the runner exports to the install
if [ -n "${PLAYBOOK_REGISTRY:-}" ]; then printf 'variant-write\n' >> "$PLAYBOOK_REGISTRY"; else printf 'x\n' >> "$D/.install-targets"; fi
case "$cmd" in
  install)
    [ -e "$D/.m-fail-install" ] && exit 1
    rm -rf "$H/.agents/playbook"; mkdir -p "$H/.agents/playbook/scripts"
    printf '%s \n' "$(cat "$D/VERSION")" > "$H/.agents/playbook/VERSION"
    if [ -e "$D/.m-backup" ]; then   # like install.sh backup_copy: new entries in the home's backup dir
      mkdir -p "$H/.agents/playbook-backups/dir-new"
      printf 'bak\n' > "$H/.agents/playbook-backups/CLAUDE.md.bak-new"
      printf 'bak\n' > "$H/.agents/playbook-backups/dir-new/f"
    fi
    [ -e "$D/.m-wrong-version" ] && printf '9.9.9\n' > "$H/.agents/playbook/VERSION"
    cp "$D/scripts/vmark" "$H/.agents/playbook/scripts/vmark"
    if [ "$HAR" = claude ]; then SK="$H/.claude/skills"; BL="$H/.claude/CLAUDE.md"
    elif [ "$HAR" = codex ]; then SK="$H/.agents/skills"; BL="$H/.codex/AGENTS.md"
    else SK="$H/.agents/skills"; BL="$H/.config/opencode/AGENTS.md"; fi
    mkdir -p "$SK" "$(dirname "$BL")"
    for s in "$D"/skills/*/; do s="${s%/}"; rm -rf "$SK/$(basename "$s")"; cp -R "$s" "$SK/$(basename "$s")"; done
    printf 'VARIANT-BLOCK %s\n' "$(cat "$D/VERSION")" >> "$BL"
    if [ -e "$D/.m-extra" ]; then   # also places targets of the other harnesses (they were absent before)
      mkdir -p "$H/.agents/skills/playbook-vskill" "$H/.codex" "$H/.config/opencode"
      printf 'extra\n' > "$H/.agents/skills/playbook-vskill/SKILL.md"
      printf 'VARIANT-BLOCK extra\n' > "$H/.codex/AGENTS.md"
      printf 'VARIANT-BLOCK extra\n' > "$H/.config/opencode/AGENTS.md"
    fi
    [ -e "$D/.m-lock-skills" ] && chmod 555 "$SK"
    exit 0 ;;
  doctor)
    [ -e "$D/.m-fail-doctor" ] && exit 1
    exit 0 ;;
esac
exit 0
EOF
}
# mk_vhome [link] -> VH: a harness home with every kind of target. link: the targets are symlinks into another temp tree.
mk_vhome() {
  local h s mode="${1:-copy}"
  h="$(mk_tmp)"; s="$h"
  [ "$mode" = link ] && s="$(mk_tmp)"
  mkdir -p "$s/playbook/scripts" "$s/skills/playbook-base/sub" "$s/skills/playbook-two" "$s/skills/varskill" "$s/skills/playbook-old"
  mkdir -p "$h/.agents" "$h/.claude/skills/myskill" "$h/.agents/skills"
  printf '0.0.1-base\n' > "$s/playbook/VERSION"
  printf '#!/bin/sh\necho base\n' > "$s/playbook/scripts/base.sh"; chmod 755 "$s/playbook/scripts/base.sh"
  printf 'base skill\n' > "$s/skills/playbook-base/SKILL.md"
  printf 'private\n' > "$s/skills/playbook-base/sub/x.txt"; chmod 600 "$s/skills/playbook-base/sub/x.txt"
  printf 'two\n' > "$s/skills/playbook-two/SKILL.md"
  printf 'user varskill\n' > "$s/skills/varskill/SKILL.md"
  printf 'old\n' > "$s/skills/playbook-old/SKILL.md"
  printf 'mine\n' > "$h/.claude/skills/myskill/SKILL.md"
  if [ "$mode" = link ]; then
    ln -s "$s/playbook" "$h/.agents/playbook"
    ln -s "$s/skills/playbook-base" "$h/.claude/skills/playbook-base"
    ln -s "$s/skills/playbook-two" "$h/.claude/skills/playbook-two"
    ln -s "$s/skills/varskill" "$h/.claude/skills/varskill"
    ln -s "$s/skills/playbook-old" "$h/.agents/skills/playbook-old"
  else
    mv "$s/playbook" "$h/.agents/playbook"
    mv "$s/skills/playbook-base" "$s/skills/playbook-two" "$s/skills/varskill" "$h/.claude/skills/"
    mv "$s/skills/playbook-old" "$h/.agents/skills/"
  fi
  printf 'my notes\n<!-- BEGIN agent-playbook base -->\nbase block \xc3\xa9 $x\n<!-- END agent-playbook -->\nlast line, no newline' > "$h/.claude/CLAUDE.md"
  chmod 640 "$h/.claude/CLAUDE.md"
  printf 'SECRET-TOKEN\n' > "$h/.claude/.credentials.json"; chmod 600 "$h/.claude/.credentials.json"
  printf 'test_cmd=make check\nfeedback_repo=acme/fb\nmodel_tester_claude=opus-x1\nmodel_reviewer_claude=sonnet\n' > "$h/.agents/playbook.conf"
  printf '%s\n' "$h"
}
# fmode FILE -> octal permission bits (rwx triples, e.g. 640), read from ls -l so it works on GNU and BSD/macOS alike
fmode() { ls -ld "$1" | awk '{ s = substr($1, 2, 9); m = ""; for (i = 0; i < 3; i++) { r = substr(s, i * 3 + 1, 3); v = 0; if (substr(r, 1, 1) == "r") v += 4; if (substr(r, 2, 1) == "w") v += 2; if (substr(r, 3, 1) ~ /[xst]/) v += 1; m = m v }; print m }'; }
# Capability probes (what this file system and user can do), so the assertions that need a capability are skipped, not failed, where it is missing:
#   VDIRPERM=0: a directory made read-only (chmod 555) can still be written (root, or NTFS under Git Bash)
#   VMODEKEEP=0: chmod modes 640 / 600 are not read back as set (NTFS under Git Bash)
VDIRPERM=1; VMODEKEEP=1
VPROBE="$(mk_tmp)"; mkdir "$VPROBE/d"; chmod 555 "$VPROBE/d"
if ( : > "$VPROBE/d/x" ) 2>/dev/null; then VDIRPERM=0; fi
chmod 755 "$VPROBE/d"
if [ "$(id -u)" = 0 ]; then VDIRPERM=0; fi
printf 'x\n' > "$VPROBE/m"; chmod 640 "$VPROBE/m"; [ "$(fmode "$VPROBE/m")" = 640 ] || VMODEKEEP=0
chmod 600 "$VPROBE/m"; [ "$(fmode "$VPROBE/m")" = 600 ] || VMODEKEEP=0
#   VTRSEE=0: a "tr" cannot tell which file it reads from stdin (no /proc/<pid>/fd/0 link, and [ /dev/stdin -ef FILE ] is false: macOS),
#   so the tr shim of the AC21 blocks cannot see the lock's pid read
VTRSEE=0
printf 'x
' > "$VPROBE/t"
if [ /dev/stdin -ef "$VPROBE/t" ] 2>/dev/null < "$VPROBE/t"; then VTRSEE=1; fi
case "$(bash -c 'readlink "/proc/$$/fd/0"' < "$VPROBE/t" 2>/dev/null)" in */t) VTRSEE=1 ;; esac
# tree_sig DIR -> every regular file (mode, md5) and symlink (target) under DIR, sorted; directories are not listed
tree_sig() {
  (cd "$1" && find . -mindepth 1 \( -type f -o -type l \) | LC_ALL=C sort | while IFS= read -r p; do
    if [ -L "$p" ]; then printf 'L %s -> %s\n' "$p" "$(readlink "$p")"
    else printf 'F %s %s %s\n' "$p" "$(fmode "$p")" "$(md5sum < "$p")"; fi
  done)
}
# vrun ARGS... -> runs the runner (HOME=$VH, PB_VARIANT_HOME=$VHOME or $VH, registry $VREG unless VNOREG=1), sets OUT ERR RC VWR VOD VRES VFD
vsetup() {
  VWR="$(mk_tmp)"; : > "$VWR/.pb-eval-workroot"; VOD="$(mk_tmp)"; VRES="$VOD/results.md"; VFD="$(mk_tmp)"
  export VW_HOME="$VH" VW_VHOME="${VHOME:-$VH}" VW_WR="$VWR" VW_RES="$VRES" VFAKE_LOG="$VOD/claude.log" VFAKE_DIR="$VFD" VFAKE_H="${VHOME:-$VH}"
  if [ -n "${VNOREG:-}" ]; then export VW_REG=""; else export VW_REG="$VREG"; fi
  : > "$VFAKE_LOG"
  if [ -n "${VRES_AS_DIR:-}" ]; then mkdir -p "$VRES"; fi   # the md results cannot be written: a pb_die after the restore
}
vrun() { vsetup; bash "$VFK/runner.sh" "$@" > "$VOD/stdout" 2> "$VOD/stderr"; RC=$?; OUT="$(cat "$VOD/stdout")"; ERR="$(cat "$VOD/stderr")"; }
vstart() { vsetup; bash "$VFK/runner.sh" "$@" > "$VOD/stdout" 2> "$VOD/stderr" & VPID=$!; }
vwait_file() { local i=0; while [ ! -e "$1" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i + 1)); done; [ -e "$1" ]; }
vfinish() { RC=0; wait "$1" 2>/dev/null || RC=$?; OUT="$(cat "$VOD/stdout")"; ERR="$(cat "$VOD/stderr")"; }
vlog() { cat "$VFAKE_LOG" 2>/dev/null; }
vcalls() { cat "$VD/.calls" 2>/dev/null; }
# expect_restored NAME BEFORE -> the home VH has exactly the files, modes, contents and links of BEFORE and no lock
expect_restored() {
  assert_eq "$1: the home is restored exactly (files, modes, content, symlinks)" "$2" "$(tree_sig "$VH")"
  assert_no_path "$1: the lock is removed" "$VH/.agents/.pb-variant.lock"
}
unlock() { chmod u+rwx "$VH/.claude/skills" "$VH/.agents/skills" 2>/dev/null; }   # only the dirs the fake adapter made read-only (non-recursive: the kept snapshot in the lock dir keeps its modes)

refuse() { # NAME NEEDLE ARGS... (VD, VH set by the caller)
  local n="$1" needle="$2" before; shift 2
  before="$(tree_sig "$VH")"
  vrun "$@"
  assert_rc "AC6 $n -> exit 2" 2
  assert_not_contains "AC6 $n is a refusal, not an unknown option" "$ERR$OUT" "unknown option"
  assert_contains "AC6 $n: the message names $needle" "$ERR$OUT" "$needle"
  assert_eq "AC6 $n: nothing touched" "$before" "$(tree_sig "$VH")"
  assert_no_path "AC6 $n: no install.sh call" "$VD/.calls"
  assert_no_path "AC6 $n: no lock" "$VH/.agents/.pb-variant.lock"
  assert_eq "AC6 $n: no harness run" "" "$(vlog)"
}

# ================= Rework round 1 (AC10-AC18): helpers =================
# A PATH shim (mv, cp, rm in $VSHIM, put first on the runner's PATH only when VW_SHIM is set) that pauses ONE chosen command of the
# runner until $VHOLD/go exists, so a test can act while the runner is in the middle of a restore, deterministically (no timing guess).
#   VSHIM_MODE=restore: the first mv/cp of a snapshot's playbook back to */.agents/playbook (a stale restore, or the end-of-run restore)
#   VSHIM_MODE=post:    the first rm of the runner's results scratch file (pb-evnd.*), which happens after the end-of-run restore
# It writes $VHOLD/held when it paused, passes every other call straight through, and gives up waiting after 30 s.
VSHIM="$(mk_tmp)"
cat > "$VSHIM/shim" <<'EOF'
#!/usr/bin/env bash
n="${0##*/}"; hold=0; prev=""; last=""
if [ "$n" = tr ] && [ -n "${VSHIM_TR_DIR:-}" ]; then   # pause right after the n-th read of the lock's pid file (stdin is that file)
  isl=0   # is stdin the lock's pid file? by inode (macOS has no /proc), or by /proc where there is one
  if [ /dev/stdin -ef "$VW_VHOME/.agents/.pb-variant.lock/pid" ] 2>/dev/null; then isl=1; fi
  case "$(readlink "/proc/$$/fd/0" 2>/dev/null)" in */.pb-variant.lock/pid) isl=1 ;; esac
  case "$isl" in
    1)
      PATH="${PATH#"$VW_SHIM":}"
      out="$(tr "$@")"
      c=$(( $(cat "$VSHIM_TR_DIR/count" 2>/dev/null || echo 0) + 1 )); echo "$c" > "$VSHIM_TR_DIR/count"
      if [ "$c" = "${VSHIM_TR_NTH:-1}" ] && mkdir "$VSHIM_TR_DIR/claimed" 2>/dev/null; then
        : > "$VSHIM_TR_DIR/held"
        i=0; while [ ! -e "$VSHIM_TR_DIR/go" ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
      fi
      printf '%s' "$out"; exit 0 ;;
  esac
fi
if [ "$n" = mkdir ] && [ -n "${VSHIM_MKLOCK_DIR:-}" ]; then   # pause BEFORE the runner's 2nd mkdir of the lock dir (the 1st finds the stale lock; the 2nd comes after its restore)
  for a in "$@"; do last="$a"; done
  case "$last" in
    */.agents/.pb-variant.lock)
      c=$(( $(cat "$VSHIM_MKLOCK_DIR/count" 2>/dev/null || echo 0) + 1 )); echo "$c" > "$VSHIM_MKLOCK_DIR/count"
      if [ "$c" = 2 ] && mkdir "$VSHIM_MKLOCK_DIR/claimed" 2>/dev/null; then
        : > "$VSHIM_MKLOCK_DIR/held"
        i=0; while [ ! -e "$VSHIM_MKLOCK_DIR/go" ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
      fi ;;
  esac
  last=""
fi
for a in "$@"; do prev="$last"; last="$a"; done
if [ -n "${VSHIM_HOLD:-}" ]; then
  case "${VSHIM_MODE:-}:$n" in
    restore:mv | restore:cp) case "$prev" in */snap/playbook) case "$last" in */.agents/playbook) hold=1 ;; esac ;; esac ;;
    post:rm) for a in "$@"; do case "$a" in *pb-evnd.*) hold=1 ;; esac; done ;;
  esac
fi
if [ "$hold" = 1 ] && mkdir "$VSHIM_HOLD/claimed" 2>/dev/null; then
  : > "$VSHIM_HOLD/held"
  i=0; while [ ! -e "$VSHIM_HOLD/go" ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
fi
PATH="${PATH#"$VW_SHIM":}"
exec "$n" "$@"
EOF
chmod 755 "$VSHIM/shim"; cp "$VSHIM/shim" "$VSHIM/mv"; cp "$VSHIM/shim" "$VSHIM/cp"; cp "$VSHIM/shim" "$VSHIM/rm"; cp "$VSHIM/shim" "$VSHIM/mkdir"; cp "$VSHIM/shim" "$VSHIM/tr"
vhold_new() { VHOLD="$(mk_tmp)"; }
# valive PID: true when the process is running (not gone, not a zombie); /proc where there is one, else kill -0 and ps (macOS)
valive() {
  if [ -r /proc/self/status ]; then [ -d "/proc/$1" ] && ! grep -q '^State:[[:space:]]*[ZX]' "/proc/$1/status" 2>/dev/null; return; fi
  kill -0 "$1" 2>/dev/null || return 1
  case "$(ps -o stat= -p "$1" 2>/dev/null)" in Z* | X*) return 1 ;; esac
  return 0
}
# vwait_exit PID [TENTHS]: true when the process is gone (not a zombie) within the time
vwait_exit() { local i=0; while valive "$1" && [ "$i" -lt "${2:-300}" ]; do sleep 0.1; i=$((i + 1)); done; ! valive "$1"; }
# vtimeout20 CMD...: CMD with a 20 s limit, exit 124 when it did not finish (timeout or gtimeout when there is one, else a background kill timer: macOS has none)
vtimeout20() {
  local p w rc
  if command -v timeout >/dev/null 2>&1; then timeout 20 "$@"; return; fi
  if command -v gtimeout >/dev/null 2>&1; then gtimeout 20 "$@"; return; fi
  "$@" & p=$!
  ( sleep 20; : > "$VOD/timedout"; kill -TERM "$p" 2>/dev/null; sleep 1; kill -KILL "$p" 2>/dev/null ) >/dev/null 2>&1 & w=$!
  wait "$p" 2>/dev/null; rc=$?
  if [ -e "$VOD/timedout" ]; then rc=124; fi
  kill "$w" 2>/dev/null; wait "$w" 2>/dev/null
  return "$rc"
}
# vrunt ARGS...: like vrun with a 20 s limit (exit 124 = the runner did not finish: a loop)
vrunt() { vsetup; vtimeout20 bash "$VFK/runner.sh" "$@" > "$VOD/stdout" 2> "$VOD/stderr"; RC=$?; OUT="$(cat "$VOD/stdout")"; ERR="$(cat "$VOD/stderr")"; }
# vdead_pid -> the pid of a process that has finished
vdead_pid() { local p; ( : ) & p=$!; wait "$p" 2>/dev/null; printf '%s' "$p"; }
# vmk_stale H -> VL: a stale lock dir (dead pid) with an empty snapshot skeleton and no "installing" marker
vmk_stale() {
  VL="$1/.agents/.pb-variant.lock"; mkdir -p "$VL/snap/skills-claude" "$VL/snap/skills-agents" "$VL/snap/blocks"
  : > "$VL/names"; printf '%s\n' "$(vdead_pid)" > "$VL/pid"
}
# the kept copies of an edited block file
vkept() { ls "$1".pb-variant-kept.* 2>/dev/null; }
# vmsg_names NAME PATH: some line of ERR/OUT that starts with "variant:" or "error:" names PATH (a shell error line that only quotes the path does not count)
vmsg_names() { if printf '%s
' "$ERR$OUT" | grep -E '^(variant|error):' | grep -qF -- "$2"; then t_ok "$1"; else t_bad "$1" "no variant:/error: line naming $2; got: $(printf '%s' "$ERR$OUT" | head -c 300)"; fi; }
VPERL=0; command -v perl >/dev/null 2>&1 && VPERL=1

