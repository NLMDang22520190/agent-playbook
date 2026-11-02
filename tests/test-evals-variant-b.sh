#!/usr/bin/env bash
. "$(dirname "$0")/evals-variant-fixture.sh"
# ================= AC10: a symlinked block file is refused =================
echo "AC10 a block file that is a symbolic link is refused (exit 2) before anything is touched, the link target stays as it was"
if [ "$SYMLINKS" = 1 ]; then
  for which in claude codex opencode dangling; do
    mk_variant; VH="$(mk_vhome)"; DOT="$(mk_tmp)"
    case "$which" in
      claude) BF="$VH/.claude/CLAUDE.md"; mv "$BF" "$DOT/real.md"; ln -s "$DOT/real.md" "$BF" ;;
      codex) BF="$VH/.codex/AGENTS.md"; mkdir -p "$VH/.codex"; printf 'dotfile notes\n' > "$DOT/real.md"; ln -s "$DOT/real.md" "$BF" ;;
      opencode) BF="$VH/.config/opencode/AGENTS.md"; mkdir -p "$VH/.config/opencode"; printf 'dotfile notes\n' > "$DOT/real.md"; ln -s "$DOT/real.md" "$BF" ;;
      dangling) BF="$VH/.config/opencode/AGENTS.md"; mkdir -p "$VH/.config/opencode"; ln -s "$DOT/missing.md" "$BF" ;;
    esac
    T_BEFORE="$(md5sum < "$DOT/real.md" 2>/dev/null)"
    refuse "AC10 [$which] symlinked block file" "is a symbolic link" --variant "$VD" $VBASE
    assert_contains "AC10 [$which] the refusal names the file" "$ERR$OUT" "$BF"
    assert_eq "AC10 [$which] the content behind the link is unchanged" "$T_BEFORE" "$(md5sum < "$DOT/real.md" 2>/dev/null)"
    if [ -L "$BF" ]; then t_ok "AC10 [$which] the block file is still a link"; else t_bad "AC10 [$which] the block file is still a link" "not a link any more: $BF"; fi
  done
else
  t_skip 36 "AC10 symlinked block file (no symlink rights here)"
fi

# ================= AC12: a block file edited during the run is kept =================
echo "AC12 a block file edited during the run is kept as <file>.pb-variant-kept.<UTC ts> and the snapshot is restored"
mk_variant; VH="$(mk_vhome)"; B_ED="$(tree_sig "$VH")"
VFAKE_EDIT="$VH/.claude/CLAUDE.md" vrun --variant "$VD" $VBASE
assert_rc "AC12 the run ends with exit 0 (the restore worked)" 0
KEPT="$(vkept "$VH/.claude/CLAUDE.md" | head -n 1)"
assert_eq "AC12 exactly one kept copy next to the block file" "1" "$(vkept "$VH/.claude/CLAUDE.md" | wc -l | tr -d ' ')"
if [ -n "$KEPT" ] && [ -f "$KEPT" ]; then
  assert_contains "AC12 the kept copy holds the edit made during the run" "$(cat "$KEPT")" "USER EDIT"
  assert_contains "AC12 the kept copy is the file as it was at the restore (it still has the variant block)" "$(cat "$KEPT")" "VARIANT-BLOCK"
else t_bad "AC12 the kept copy holds the edit made during the run" "no kept file"; t_bad "AC12 the kept copy is the file as it was at the restore" "no kept file"; fi
case "${KEPT##*.pb-variant-kept.}" in [0-9]*) t_ok "AC12 the kept name ends in a (UTC) timestamp" ;; *) t_bad "AC12 the kept name ends in a (UTC) timestamp" "name [$KEPT]" ;; esac
assert_contains "AC12 stderr: variant: <file> changed during the run; your version is kept at <path>" "$ERR" "variant: $VH/.claude/CLAUDE.md changed during the run; your version is kept at $KEPT"
assert_eq "AC12 the snapshot is restored: the whole home equals the one before (the kept copy aside)" "$B_ED" "$(tree_sig "$VH" | grep -v 'pb-variant-kept')"
assert_eq "AC12 the block file is byte-equal to the original again" "$(printf 'my notes\n<!-- BEGIN agent-playbook base -->\nbase block \xc3\xa9 $x\n<!-- END agent-playbook -->\nlast line, no newline' | md5sum)" "$(md5sum < "$VH/.claude/CLAUDE.md")"
assert_no_path "AC12 the lock is removed" "$VH/.agents/.pb-variant.lock"
echo "AC12 block files nobody edited are restored exactly and no kept copy appears (control: passes before the rework, guards an always-keep implementation)"
mk_variant; : > "$VD/.m-extra"; VH="$(mk_vhome)"; B_NE="$(tree_sig "$VH")"
vrun --variant "$VD" $VBASE
assert_rc "AC12 control: exit 0" 0
assert_eq "AC12 control: no kept copy next to any block file" "" "$(ls "$VH/.claude" "$VH/.codex" "$VH/.config/opencode" 2>/dev/null | grep 'pb-variant-kept')"
expect_restored "AC12 control" "$B_NE"
assert_not_contains "AC12 control: stderr has no 'changed during the run' line" "$ERR" "changed during the run; your version is kept"

# ================= AC13: lock path problems =================
echo "AC13 the lock path is a regular file, or H/.agents is not writable: exit 3 naming the path, no loop, nothing touched"
mk_variant; VH="$(mk_vhome)"; : > "$VH/.agents/.pb-variant.lock"; B_13="$(tree_sig "$VH")"
vrunt --variant "$VD" $VBASE
if [ "$RC" = 124 ]; then t_bad "AC13 lock path is a regular file: the runner ends (no endless loop)" "still running after 20 s (timeout, exit 124)"; else t_ok "AC13 lock path is a regular file: the runner ends (no endless loop)"; fi
assert_rc "AC13 lock path is a regular file -> exit 3" 3
vmsg_names "AC13 the runner's own message (a variant:/error: line) names the lock path" "$VH/.agents/.pb-variant.lock"
assert_eq "AC13 nothing touched (the file is still there, the home is as before)" "$B_13" "$(tree_sig "$VH")"
assert_no_path "AC13 no install.sh call" "$VD/.calls"
assert_eq "AC13 no harness run" "" "$(vlog)"
if [ "$VDIRPERM" = 0 ]; then
  t_skip 7 "AC13 H/.agents not writable (a read-only directory is still writable here: root or NTFS)"
else
  mk_variant; VH="$(mk_vhome)"; B_13W="$(tree_sig "$VH")"; chmod 555 "$VH/.agents"
  vrunt --variant "$VD" $VBASE
  chmod 755 "$VH/.agents"
  if [ "$RC" = 124 ]; then t_bad "AC13 H/.agents not writable: the runner ends (no endless loop)" "still running after 20 s (timeout, exit 124)"; else t_ok "AC13 H/.agents not writable: the runner ends (no endless loop)"; fi
  assert_rc "AC13 H/.agents not writable -> exit 3" 3
  vmsg_names "AC13 the runner's own message (a variant:/error: line) names the path" "$VH/.agents"
  assert_eq "AC13 nothing touched" "$B_13W" "$(tree_sig "$VH")"
  assert_no_path "AC13 no install.sh call" "$VD/.calls"
  assert_no_path "AC13 no lock dir was made" "$VH/.agents/.pb-variant.lock"
  assert_eq "AC13 no harness run" "" "$(vlog)"
fi

# ================= AC14: exit 5 stays after a failed restore =================
echo "AC14 after a failed end-of-run restore a later pb_die and a later TERM still exit 5"
if [ "$VDIRPERM" = 0 ]; then
  t_skip 5 "AC14 (a read-only directory is still writable here: root or NTFS)"
else
  mk_variant; : > "$VD/.m-lock-skills"; VH="$(mk_vhome)"
  VRES_AS_DIR=1 vrun --variant "$VD" $VBASE
  assert_contains "AC14 the restore failed first (RESTORE FAILED)" "$ERR" "variant: RESTORE FAILED, snapshot kept at "
  assert_contains "AC14 a later pb_die really happened (the results file cannot be written)" "$ERR" "cannot write"
  assert_rc "AC14 pb_die after the failed restore -> exit 5 (not the pb_die code)" 5
  unlock
  mk_variant; : > "$VD/.m-lock-skills"; VH="$(mk_vhome)"; vhold_new
  VW_SHIM="$VSHIM" VSHIM_MODE=post VSHIM_HOLD="$VHOLD" vstart --variant "$VD" $VBASE
  P14=$VPID; O14="$VOD"
  if vwait_file "$VHOLD/held"; then
    assert_contains "AC14 [TERM] the restore had failed before the signal came" "$(cat "$O14/stderr")" "variant: RESTORE FAILED, snapshot kept at "
    kill -s TERM "$P14" 2>/dev/null; : > "$VHOLD/go"
    VOD="$O14"; vfinish "$P14"
    assert_rc "AC14 [TERM] a TERM after the failed restore -> exit 5 (not 143)" 5
  else
    t_bad "AC14 [TERM] the runner reached the point after the restore" "no 'held' file after 20 s; stderr: $(cat "$O14/stderr" 2>/dev/null)"
    : > "$VHOLD/go"; kill -KILL "$P14" 2>/dev/null; wait "$P14" 2>/dev/null
  fi
  unlock
fi

# ================= AC17: the registry is always a runner temp file =================
echo "AC17 install and doctor always get a runner-made temp registry; the caller's PLAYBOOK_REGISTRY file is never written"
mk_variant; VH="$(mk_vhome)"; printf 'SENTINEL\n' > "$VREG"
vrun --variant "$VD" $VBASE
assert_rc "AC17 exit 0" 0
CALLS="$(vcalls)"
REGS="$(printf '%s\n' "$CALLS" | sed -n 's/.*registry=\([^|]*\)|.*/\1/p' | sort -u)"
assert_eq "AC17 install and doctor use one registry file" "1" "$(printf '%s\n' "$REGS" | grep -c .)"
if [ -n "$REGS" ] && [ "$REGS" != "$VREG" ]; then t_ok "AC17 that file is not the caller's PLAYBOOK_REGISTRY"; else t_bad "AC17 that file is not the caller's PLAYBOOK_REGISTRY" "registry used: [$REGS] caller: [$VREG]"; fi
assert_eq "AC17 the caller's registry file was never written" "SENTINEL" "$(cat "$VREG")"
assert_no_path "AC17 DIR's own registry was never written" "$VD/.install-targets"
[ -n "$REGS" ] && assert_no_path "AC17 the temp registry is removed at the end" "$REGS"
run bash "$RUNNER" --help
assert_contains "AC17 the usage text speaks of PLAYBOOK_REGISTRY" "$OUT" "PLAYBOOK_REGISTRY"
assert_not_contains "AC17 the usage text no longer says the registry may be the caller's ('yours or a temp')" "$OUT" "yours or a temp"

# ================= AC18: signals are ignored while restoring =================
echo "AC18 INT, TERM and HUP sent while the snapshot is being restored do not interrupt it (end-of-run restore)"
for sig in INT TERM HUP; do
  if [ "$sig" = INT ] && [ "$VPERL" = 0 ]; then t_skip 5 "AC18 [INT] (no perl to start the runner with SIGINT enabled)"; continue; fi
  mk_variant; VH="$(mk_vhome)"; B_SG="$(tree_sig "$VH")"; vhold_new
  VW_INTDFL=1 VW_SHIM="$VSHIM" VSHIM_MODE=restore VSHIM_HOLD="$VHOLD" vstart --variant "$VD" $VBASE
  G_PID=$VPID; G_OD="$VOD"
  if vwait_file "$VHOLD/held"; then
    kill -s "$sig" "$G_PID" 2>/dev/null; : > "$VHOLD/go"
    VOD="$G_OD"; vfinish "$G_PID"
    assert_rc "AC18 [$sig] the signal did not stop the restore or the run: exit 0" 0
    assert_eq "AC18 [$sig] the restore line is printed once" "1" "$(printf '%s\n' "$ERR" | grep -c 'variant: restored the snapshot of ')"
    expect_restored "AC18 [$sig] during the restore" "$B_SG"
    assert_contains "AC18 [$sig] the results say the snapshot was restored" "$(grep '^Variant:' "${G_OD}/results.md" 2>/dev/null)" "snapshot restored"
  else
    t_bad "AC18 [$sig] the runner reached the restore" "no 'held' file after 20 s; stderr: $(cat "$G_OD/stderr" 2>/dev/null)"
    : > "$VHOLD/go"; kill -KILL "$G_PID" 2>/dev/null; wait "$G_PID" 2>/dev/null
  fi
done
echo "AC18 a TERM during the run starts the restore; an INT and a HUP sent while it runs are ignored (exit stays 143)"
mk_variant; VH="$(mk_vhome)"; B_SG2="$(tree_sig "$VH")"; vhold_new
VFAKE_SLEEP=1 VW_INTDFL=1 VW_SHIM="$VSHIM" VSHIM_MODE=restore VSHIM_HOLD="$VHOLD" vstart --variant "$VD" $VBASE
G_PID=$VPID; G_OD="$VOD"; G_FD="$VFD"
if vwait_file "$G_FD/started"; then
  kill -s TERM "$G_PID" 2>/dev/null
  if vwait_file "$VHOLD/held"; then
    [ "$VPERL" = 1 ] && kill -s INT "$G_PID" 2>/dev/null
    kill -s HUP "$G_PID" 2>/dev/null; : > "$VHOLD/go"
    VOD="$G_OD"; vfinish "$G_PID"
    assert_rc "AC18 [TERM, then INT and HUP] the exit code is the first signal's (143)" 143
    assert_eq "AC18 [TERM, then INT and HUP] the restore line is printed once" "1" "$(printf '%s\n' "$ERR" | grep -c 'variant: restored the snapshot of ')"
    expect_restored "AC18 [TERM, then INT and HUP]" "$B_SG2"
  else
    t_bad "AC18 [TERM, then INT and HUP] the runner reached the restore" "no 'held' file after 20 s"
    : > "$VHOLD/go"; kill -KILL "$G_PID" 2>/dev/null; wait "$G_PID" 2>/dev/null
  fi
else
  t_bad "AC18 [TERM, then INT and HUP] the runner reached its adapter" "no 'started' file"
  kill -KILL "$G_PID" 2>/dev/null; wait "$G_PID" 2>/dev/null
fi
[ -f "$G_FD/sleeper.pid" ] && kill "$(cat "$G_FD/sleeper.pid")" 2>/dev/null
unset VFAKE_SLEEP

# ================= AC12 (codex block file) =================
echo "AC12 the same for the codex block file: an edit during the run is kept next to it, the snapshot comes back"
mk_variant; VH="$(mk_vhome)"; mkdir -p "$VH/.codex"; printf 'codex notes\n' > "$VH/.codex/AGENTS.md"; B_CX="$(tree_sig "$VH")"
VFAKE_EDIT="$VH/.codex/AGENTS.md" vrun --variant "$VD" --harness codex --scenarios E8
assert_rc "AC12 codex: exit 0" 0
KEPT="$(vkept "$VH/.codex/AGENTS.md" | head -n 1)"
if [ -n "$KEPT" ] && [ -f "$KEPT" ]; then t_ok "AC12 codex: a kept copy exists next to \$H/.codex/AGENTS.md"; else t_bad "AC12 codex: a kept copy exists next to \$H/.codex/AGENTS.md" "none"; fi
assert_contains "AC12 codex: stderr names the file and the kept path" "$ERR" "variant: $VH/.codex/AGENTS.md changed during the run; your version is kept at $KEPT"
assert_eq "AC12 codex: the home equals the one before (the kept copy aside)" "$B_CX" "$(tree_sig "$VH" | grep -v 'pb-variant-kept')"

# ================= AC11: stale takeover holds the lock =================
echo "AC11 two runners meet one stale lock: the second never snapshots a half-restored home (the first is paused in its restore by a PATH shim)"
mk_variant; VH="$(mk_vhome)"; B_11="$(tree_sig "$VH")"
VFAKE_SLEEP=1 vstart --variant "$VD" $VBASE
S_PID=$VPID; S_FD="$VFD"
if vwait_file "$S_FD/started"; then
  kill -KILL "$S_PID" 2>/dev/null; wait "$S_PID" 2>/dev/null
  kill "$(cat "$S_FD/sleeper.pid")" 2>/dev/null
  unset VFAKE_SLEEP
  vhold_new
  mk_variant; VDA="$VD"
  VW_SHIM="$VSHIM" VSHIM_MODE=restore VSHIM_HOLD="$VHOLD" vstart --variant "$VDA" $VBASE
  A_PID=$VPID; A_OD="$VOD"
  if vwait_file "$VHOLD/held"; then
    mk_variant; VDB="$VD"; VD="$VDB"
    vstart --variant "$VDB" $VBASE
    B_PID=$VPID; B_OD="$VOD"
    # B either refuses at once (a live lock: exit 2) or waits for A; what it must not do is install while A has not finished
    i=0; while [ "$i" -lt 40 ]; do
      [ -s "$VDB/.calls" ] && break
      valive "$B_PID" || break
      sleep 0.1; i=$((i + 1))
    done
    if [ -s "$VDB/.calls" ]; then t_bad "AC11 the second runner did not install while the first was still restoring the stale snapshot" "install.sh was called: $(head -n 1 "$VDB/.calls")"
    else t_ok "AC11 the second runner did not install while the first was still restoring the stale snapshot"; fi
    assert_eq "AC11 the second runner ran no harness while the first was restoring" "" "$(cat "$B_OD/claude.log" 2>/dev/null)"
    if valive "$B_PID"; then
      t_ok "AC11 the second runner is waiting (it did not run through the half-restored home)"
    else
      VOD="$B_OD"; vfinish "$B_PID"
      assert_rc "AC11 the second runner that did not wait was refused on a live lock (exit 2)" 2
      B_DONE=1
    fi
    : > "$VHOLD/go"
    VOD="$A_OD"; vfinish "$A_PID"
    assert_rc "AC11 the first runner finishes its run (exit 0)" 0
    assert_contains "AC11 the first runner restored the stale snapshot" "$ERR" "variant: restored a stale snapshot left by pid $S_PID"
    if [ -z "${B_DONE:-}" ]; then
      vwait_exit "$B_PID" 300 || { kill -KILL "$B_PID" 2>/dev/null; t_bad "AC11 the waiting runner ends once the first one is done" "still running after 30 s"; }
      wait "$B_PID" 2>/dev/null
    fi
    unset B_DONE
    expect_restored "AC11 after both runners ended" "$B_11"
  else
    t_bad "AC11 the first runner reached the stale restore" "no 'held' file after 20 s; stderr: $(cat "$A_OD/stderr" 2>/dev/null)"
    : > "$VHOLD/go"; kill -KILL "$A_PID" 2>/dev/null; wait "$A_PID" 2>/dev/null
  fi
else
  t_bad "AC11 setup: the first runner reached its adapter" "no 'started' file"
  kill -KILL "$S_PID" 2>/dev/null; wait "$S_PID" 2>/dev/null
fi
unset VFAKE_SLEEP

# ================= AC15: a restore never nests into an existing target =================
echo "AC15 a stale snapshot whose target exists again (no install marker): RESTORE FAILED (exit 5), snapshot kept, never a nested move"
mk_variant; VH="$(mk_vhome)"; vmk_stale "$VH"
mkdir -p "$VL/snap/playbook"; printf 'OLD\n' > "$VL/snap/playbook/VERSION"
printf 'REINSTALLED\n' > "$VH/.agents/playbook/VERSION"
vrun --variant "$VD" $VBASE
assert_rc "AC15 [playbook] exit 5" 5
assert_contains "AC15 [playbook] stderr: RESTORE FAILED, snapshot kept at" "$ERR" "variant: RESTORE FAILED, snapshot kept at "
SNAP="$(printf '%s\n' "$ERR" | sed -n 's/.*variant: RESTORE FAILED, snapshot kept at //p' | head -n 1)"
assert_no_path "AC15 [playbook] no nested playbook/playbook" "$VH/.agents/playbook/playbook"
assert_eq "AC15 [playbook] the existing target is as it was" "REINSTALLED" "$(cat "$VH/.agents/playbook/VERSION")"
assert_eq "AC15 [playbook] the kept snapshot still holds the old playbook" "OLD" "$(cat "$SNAP/playbook/VERSION" 2>/dev/null)"
assert_no_path "AC15 [playbook] no install.sh call" "$VD/.calls"
mk_variant; VH="$(mk_vhome)"; vmk_stale "$VH"
mkdir -p "$VL/snap/skills-claude/playbook-base"; printf 'OLD skill\n' > "$VL/snap/skills-claude/playbook-base/SKILL.md"
vrun --variant "$VD" $VBASE
assert_rc "AC15 [skill] exit 5" 5
assert_contains "AC15 [skill] stderr: RESTORE FAILED, snapshot kept at" "$ERR" "variant: RESTORE FAILED, snapshot kept at "
SNAP="$(printf '%s\n' "$ERR" | sed -n 's/.*variant: RESTORE FAILED, snapshot kept at //p' | head -n 1)"
assert_no_path "AC15 [skill] no nested playbook-base/playbook-base" "$VH/.claude/skills/playbook-base/playbook-base"
assert_eq "AC15 [skill] the existing skill is as it was" "base skill" "$(cat "$VH/.claude/skills/playbook-base/SKILL.md")"
assert_eq "AC15 [skill] the kept snapshot still holds the old skill" "OLD skill" "$(cat "$SNAP/skills-claude/playbook-base/SKILL.md" 2>/dev/null)"
assert_no_path "AC15 [skill] no install.sh call" "$VD/.calls"

# ================= AC16: backups of the variant install are removed =================
echo "AC16 backups the variant install made in H/.agents/playbook-backups are removed after the restore; older ones stay"
mk_variant; : > "$VD/.m-backup"; VH="$(mk_vhome)"
mkdir -p "$VH/.agents/playbook-backups"; printf 'old backup\n' > "$VH/.agents/playbook-backups/CLAUDE.md.bak-old"; chmod 600 "$VH/.agents/playbook-backups/CLAUDE.md.bak-old"
B_BK="$(tree_sig "$VH")"
vrun --variant "$VD" $VBASE
assert_rc "AC16 exit 0" 0
assert_contains "AC16 setup: the install made new backups during the run" "$(vlog)" "CLAUDE.md.bak-new"
assert_contains "AC16 setup: the older backup was there during the run" "$(vlog)" "CLAUDE.md.bak-old"
assert_no_path "AC16 the new backup file is gone" "$VH/.agents/playbook-backups/CLAUDE.md.bak-new"
assert_no_path "AC16 the new backup dir is gone" "$VH/.agents/playbook-backups/dir-new"
assert_eq "AC16 the older backup is untouched (content)" "old backup" "$(cat "$VH/.agents/playbook-backups/CLAUDE.md.bak-old")"
expect_restored "AC16 backups" "$B_BK"
echo "AC16 no backup dir before: nothing is left in it after the restore"
mk_variant; : > "$VD/.m-backup"; VH="$(mk_vhome)"; B_BK2="$(tree_sig "$VH")"
vrun --variant "$VD" $VBASE
assert_rc "AC16 [no dir before] exit 0" 0
assert_contains "AC16 [no dir before] setup: the install made backups during the run" "$(vlog)" "CLAUDE.md.bak-new"
assert_eq "AC16 [no dir before] no file is left under playbook-backups" "0" "$(find "$VH/.agents/playbook-backups" -type f 2>/dev/null | wc -l | tr -d ' ')"
expect_restored "AC16 [no dir before]" "$B_BK2"
echo "AC16 the backups are removed also when the run ends early (doctor fails, exit 3)"
mk_variant; : > "$VD/.m-backup"; : > "$VD/.m-fail-doctor"; VH="$(mk_vhome)"; B_BK3="$(tree_sig "$VH")"
vrun --variant "$VD" $VBASE
assert_rc "AC16 [exit 3] exit 3" 3
assert_no_path "AC16 [exit 3] the new backup file is gone" "$VH/.agents/playbook-backups/CLAUDE.md.bak-new"
expect_restored "AC16 [exit 3]" "$B_BK3"

# ================= Rework round 2 (AC19-AC21) =================
# fake claude extras (see its head): VFAKE_BKNEW=<name> makes the entry <name> (a file) and <name>-dir/f in H/.agents/playbook-backups
# while the run is on (someone else's backup); VFAKE_CREATE=<file> writes <file> (any content) while the run is on.
# PATH shim extra: VSHIM_TR_DIR=<dir> VSHIM_TR_NTH=<n> pauses the runner right after its n-th read of H/.agents/.pb-variant.lock/pid
# (the read is done by "tr") until <dir>/go exists, and writes <dir>/held; deterministic, no timing guess.
vls() { ls -A "$1" 2>/dev/null | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//'; }
nobk() { tree_sig "$1" | grep -v 'playbook-backups'; }

# ---- AC19: only the backups of the runner's own install are removed ----
echo "AC19 an entry someone else puts in playbook-backups during the run survives; the install's own backups are removed"
mk_variant; : > "$VD/.m-backup"; VH="$(mk_vhome)"
mkdir -p "$VH/.agents/playbook-backups"; printf 'old backup\n' > "$VH/.agents/playbook-backups/old-backup"
B_19="$(nobk "$VH")"
VFAKE_BKNEW=foreign vrun --variant "$VD" $VBASE
assert_rc "AC19 [dir existed] exit 0" 0
assert_contains "AC19 [dir existed] setup: the install made its backups during the run" "$(vlog)" "CLAUDE.md.bak-new"
assert_eq "AC19 [dir existed] the backups dir holds the old and the foreign entries only" "foreign foreign-dir old-backup" "$(vls "$VH/.agents/playbook-backups")"
assert_eq "AC19 [dir existed] the foreign file keeps its content" "foreign" "$(cat "$VH/.agents/playbook-backups/foreign" 2>/dev/null)"
assert_file "AC19 [dir existed] the foreign dir keeps its file" "$VH/.agents/playbook-backups/foreign-dir/f"
assert_no_path "AC19 [dir existed] the install's own backup file is removed" "$VH/.agents/playbook-backups/CLAUDE.md.bak-new"
assert_no_path "AC19 [dir existed] the install's own backup dir is removed" "$VH/.agents/playbook-backups/dir-new"
assert_eq "AC19 [dir existed] the rest of the home is restored exactly" "$B_19" "$(nobk "$VH")"
assert_no_path "AC19 [dir existed] the lock is removed" "$VH/.agents/.pb-variant.lock"

echo "AC19 the backups dir was absent at the start: a foreign entry made during the run survives, the install's own backups go"
mk_variant; : > "$VD/.m-backup"; VH="$(mk_vhome)"; B_19b="$(nobk "$VH")"
VFAKE_BKNEW=foreign vrun --variant "$VD" $VBASE
assert_rc "AC19 [dir absent] exit 0" 0
assert_contains "AC19 [dir absent] setup: the install made its backups during the run" "$(vlog)" "CLAUDE.md.bak-new"
assert_eq "AC19 [dir absent] only the foreign entries are left" "foreign foreign-dir" "$(vls "$VH/.agents/playbook-backups")"
assert_eq "AC19 [dir absent] the foreign file keeps its content" "foreign" "$(cat "$VH/.agents/playbook-backups/foreign" 2>/dev/null)"
assert_file "AC19 [dir absent] the foreign dir keeps its file" "$VH/.agents/playbook-backups/foreign-dir/f"
assert_eq "AC19 [dir absent] the rest of the home is restored exactly" "$B_19b" "$(nobk "$VH")"

echo "AC19 stale path: a backup the user made after the crash survives, the crashed run's own install backups are removed"
for kind in present absent; do
  mk_variant; : > "$VD/.m-backup"; VH="$(mk_vhome)"
  if [ "$kind" = present ]; then mkdir -p "$VH/.agents/playbook-backups"; printf 'old backup\n' > "$VH/.agents/playbook-backups/old-backup"; fi
  B_19s="$(nobk "$VH")"
  VFAKE_SLEEP=1 vstart --variant "$VD" $VBASE
  K_PID=$VPID; K_FD="$VFD"
  if vwait_file "$K_FD/started"; then
    kill -KILL "$K_PID" 2>/dev/null; wait "$K_PID" 2>/dev/null
    kill "$(cat "$K_FD/sleeper.pid")" 2>/dev/null
    unset VFAKE_SLEEP
    assert_file "AC19 [stale, dir $kind] setup: the crashed run's install backup is there" "$VH/.agents/playbook-backups/CLAUDE.md.bak-new"
    mkdir -p "$VH/.agents/playbook-backups"; printf 'made after the crash\n' > "$VH/.agents/playbook-backups/user-bk"
    mk_variant
    vrun --variant "$VD" $VBASE
    assert_rc "AC19 [stale, dir $kind] the next run goes on (exit 0)" 0
    assert_contains "AC19 [stale, dir $kind] it restored the stale snapshot" "$ERR" "variant: restored a stale snapshot left by pid $K_PID"
    if [ "$kind" = present ]; then WANT="old-backup user-bk"; else WANT="user-bk"; fi
    assert_eq "AC19 [stale, dir $kind] the backups dir holds only what was not the crashed run's" "$WANT" "$(vls "$VH/.agents/playbook-backups")"
    assert_eq "AC19 [stale, dir $kind] the backup made after the crash keeps its content" "made after the crash" "$(cat "$VH/.agents/playbook-backups/user-bk" 2>/dev/null)"
    assert_no_path "AC19 [stale, dir $kind] the crashed run's install backup file is removed" "$VH/.agents/playbook-backups/CLAUDE.md.bak-new"
    assert_no_path "AC19 [stale, dir $kind] the crashed run's install backup dir is removed" "$VH/.agents/playbook-backups/dir-new"
    assert_eq "AC19 [stale, dir $kind] the rest of the home is restored exactly" "$B_19s" "$(nobk "$VH")"
  else
    t_bad "AC19 [stale, dir $kind] setup: the first runner reached its adapter" "no 'started' file"
    kill -KILL "$K_PID" 2>/dev/null; wait "$K_PID" 2>/dev/null
    [ -f "$K_FD/sleeper.pid" ] && kill "$(cat "$K_FD/sleeper.pid")" 2>/dev/null
  fi
  unset VFAKE_SLEEP
done

# ---- AC20: a block file absent at the start is removed only when it is what the install wrote ----
echo "AC20 a block file absent before and created during the run with other content stays in place with that content (codex, opencode, in a claude run)"
for which in codex opencode; do
  case "$which" in codex) BF_REL=".codex/AGENTS.md" ;; *) BF_REL=".config/opencode/AGENTS.md" ;; esac
  mk_variant; VH="$(mk_vhome)"; B_20="$(tree_sig "$VH")"
  VFAKE_CREATE="$VH/$BF_REL" vrun --variant "$VD" $VBASE
  assert_rc "AC20 [$which, user-made] exit 0" 0
  assert_eq "AC20 [$which, user-made] the file is still there with the user's content" "MINE created in the run" "$(cat "$VH/$BF_REL" 2>/dev/null)"
  assert_contains "AC20 [$which, user-made] stderr: variant: <file> was created during the run; left in place" "$ERR" "variant: $VH/$BF_REL was created during the run; left in place"
  assert_eq "AC20 [$which, user-made] the rest of the home is restored exactly" "$B_20" "$(tree_sig "$VH" | grep -vF "$BF_REL")"
  assert_no_path "AC20 [$which, user-made] the lock is removed" "$VH/.agents/.pb-variant.lock"
done
echo "AC20 the install wrote the file, the user then changed it during the run: it stays with the user's content"
mk_variant; : > "$VD/.m-extra"; VH="$(mk_vhome)"; B_20c="$(tree_sig "$VH")"
VFAKE_CREATE="$VH/.codex/AGENTS.md" vrun --variant "$VD" $VBASE
assert_rc "AC20 [install wrote, user changed] exit 0" 0
assert_eq "AC20 [install wrote, user changed] the file keeps the user's content" "MINE created in the run" "$(cat "$VH/.codex/AGENTS.md" 2>/dev/null)"
assert_contains "AC20 [install wrote, user changed] stderr: variant: <file> was created during the run; left in place" "$ERR" "variant: $VH/.codex/AGENTS.md was created during the run; left in place"
assert_no_path "AC20 [install wrote, user changed] the file nobody changed (opencode) is removed" "$VH/.config/opencode/AGENTS.md"
assert_eq "AC20 [install wrote, user changed] the rest of the home is restored exactly" "$B_20c" "$(tree_sig "$VH" | grep -vF '.codex/AGENTS.md')"
echo "AC20 control (passes before the rework; guards an always-keep implementation): block files the install wrote and nobody changed are removed, silently"
mk_variant; : > "$VD/.m-extra"; VH="$(mk_vhome)"; B_20d="$(tree_sig "$VH")"
vrun --variant "$VD" $VBASE
assert_rc "AC20 control: exit 0" 0
assert_no_path "AC20 control: the codex block file the install wrote is removed" "$VH/.codex/AGENTS.md"
assert_no_path "AC20 control: the opencode block file the install wrote is removed" "$VH/.config/opencode/AGENTS.md"
assert_not_contains "AC20 control: no 'was created during the run' line" "$ERR" "was created during the run"
expect_restored "AC20 control" "$B_20d"
echo "AC20 the harness block file itself is absent before, the install writes it, the user edits it during the run: it stays in place (claude, codex)"
for which in claude codex; do
  mk_variant; VH="$(mk_vhome)"
  if [ "$which" = claude ]; then BF_REL=".claude/CLAUDE.md"; rm -f "$VH/.claude/CLAUDE.md"; else BF_REL=".codex/AGENTS.md"; fi
  B_20e="$(tree_sig "$VH")"
  VFAKE_EDIT="$VH/$BF_REL" vrun --variant "$VD" --harness "$which" --scenarios E8
  assert_rc "AC20 [$which block, edited] exit 0" 0
  assert_file "AC20 [$which block, edited] the file is still at its path" "$VH/$BF_REL"
  assert_contains "AC20 [$which block, edited] it holds the user's edit" "$(cat "$VH/$BF_REL" 2>/dev/null)" "USER EDIT"
  assert_contains "AC20 [$which block, edited] stderr: variant: <file> was created during the run; left in place" "$ERR" "variant: $VH/$BF_REL was created during the run; left in place"
  assert_eq "AC20 [$which block, edited] the rest of the home is restored exactly" "$B_20e" "$(tree_sig "$VH" | grep -vF "$BF_REL")"
done
echo "AC20 control (passes before the rework): the harness block file absent before, written by the install, not edited: removed, silently"
mk_variant; VH="$(mk_vhome)"; rm -f "$VH/.claude/CLAUDE.md"; B_20f="$(tree_sig "$VH")"
vrun --variant "$VD" $VBASE
assert_rc "AC20 control [claude block] exit 0" 0
assert_no_path "AC20 control [claude block] the block file is removed" "$VH/.claude/CLAUDE.md"
assert_not_contains "AC20 control [claude block] no 'was created during the run' line" "$ERR" "was created during the run"
expect_restored "AC20 control [claude block]" "$B_20f"

# ---- AC21: the stale takeover guards ----
if [ "$VTRSEE" = 0 ]; then
  t_skip 9 "AC21 two runners read the same dead pid (cannot see which file tr reads: no /proc and /dev/stdin -ef unsupported, macOS)"
else
  echo "AC21 two runners read the same dead pid: only one takes the stale lock over, the other does not install in the meantime"
  mk_variant; VH="$(mk_vhome)"; B_21="$(tree_sig "$VH")"; vmk_stale "$VH"; DEAD21="$(cat "$VL/pid")"
  HA="$(mk_tmp)"; HB="$(mk_tmp)"
  mk_variant; VDA="$VD"
  VW_SHIM="$VSHIM" VSHIM_TR_DIR="$HA" VSHIM_TR_NTH=2 vstart --variant "$VDA" $VBASE   # A: stops after its claim and its second pid read
  A_PID=$VPID; A_OD="$VOD"
  if vwait_file "$HA/held"; then
    mk_variant; VDB="$VD"
    VW_SHIM="$VSHIM" VSHIM_TR_DIR="$HB" VSHIM_TR_NTH=1 vstart --variant "$VDB" $VBASE   # B: stops after its first pid read (the dead pid)
    B_PID=$VPID; B_OD="$VOD"
    if vwait_file "$HB/held"; then
      : > "$HB/go"   # both runners now hold the same dead pid; B goes on while A is between its claim and its pid replacement
      i=0; while [ "$i" -lt 40 ]; do
        [ -s "$VDB/.calls" ] && break
        valive "$B_PID" || break
        sleep 0.1; i=$((i + 1))
      done
      if [ -s "$VDB/.calls" ]; then t_bad "AC21 the second runner did not install while the first held the stale lock" "install.sh of B was called: $(head -n 1 "$VDB/.calls")"
      else t_ok "AC21 the second runner did not install while the first held the stale lock"; fi
      assert_eq "AC21 the second runner ran no harness in the meantime" "" "$(cat "$B_OD/claude.log" 2>/dev/null)"
      assert_not_contains "AC21 the second runner did not report taking the stale lock over" "$(cat "$B_OD/stderr" 2>/dev/null)" "restored a stale snapshot left by pid"
      : > "$HA/go"
      VOD="$A_OD"; vfinish "$A_PID"
      A_RC=$RC; A_ERR="$ERR"
      if [ "$A_RC" = 0 ]; then t_ok "AC21 the first runner finishes (exit 0)"; else t_bad "AC21 the first runner finishes (exit 0)" "rc $A_RC; stderr: $A_ERR"; fi
      assert_contains "AC21 the first runner restored the stale snapshot" "$A_ERR" "variant: restored a stale snapshot left by pid $DEAD21"
      vwait_exit "$B_PID" 300 || { kill -KILL "$B_PID" 2>/dev/null; t_bad "AC21 the second runner ends once the first is done" "still running after 30 s"; }
      VOD="$B_OD"; vfinish "$B_PID"
      case "$RC" in 0|2) t_ok "AC21 the second runner ends with 0 (it went after the first) or 2 (live lock)" ;; *) t_bad "AC21 the second runner ends with 0 or 2" "rc $RC; stderr: $ERR" ;; esac
      assert_eq "AC21 exactly one runner took the stale lock over" "1" "$(printf '%s\n%s\n' "$A_ERR" "$ERR" | grep -c 'variant: restored a stale snapshot left by pid')"
      expect_restored "AC21 after both runners ended" "$B_21"
    else
      t_bad "AC21 setup: the second runner read the lock pid" "no 'held' file after 20 s; stderr: $(cat "$B_OD/stderr" 2>/dev/null)"
      : > "$HB/go"; : > "$HA/go"; kill -KILL "$B_PID" "$A_PID" 2>/dev/null; wait "$B_PID" "$A_PID" 2>/dev/null
    fi
  else
    t_bad "AC21 setup: the first runner reached its second pid read" "no 'held' file after 20 s; stderr: $(cat "$A_OD/stderr" 2>/dev/null)"
    : > "$HA/go"; kill -KILL "$A_PID" 2>/dev/null; wait "$A_PID" 2>/dev/null
  fi
fi

if [ "$VTRSEE" = 0 ]; then
  t_skip 8 "AC21 [replaced lock] a stale lock replaced by a live runner (cannot see which file tr reads: no /proc and /dev/stdin -ef unsupported, macOS)"
else
  echo "AC21 a stale lock replaced by a live runner's lock between the pid read and the claim is not taken over"
  mk_variant; VH="$(mk_vhome)"; B_21b="$(tree_sig "$VH")"; vmk_stale "$VH"; VL21="$VL"
  sleep 120 & LIVE21=$!
  HC="$(mk_tmp)"
  VW_SHIM="$VSHIM" VSHIM_TR_DIR="$HC" VSHIM_TR_NTH=1 vstart --variant "$VD" $VBASE   # stops after reading the dead pid
  C_PID=$VPID; C_OD="$VOD"
  if vwait_file "$HC/held"; then
    rm -rf "$VL21"; mkdir -p "$VL21/snap/playbook"; printf 'LIVE-SNAP\n' > "$VL21/snap/playbook/VERSION"; printf '%s\n' "$LIVE21" > "$VL21/pid"
    : > "$HC/go"
    VOD="$C_OD"; vfinish "$C_PID"
    assert_rc "AC21 [replaced lock] the runner is refused on the live lock (exit 2)" 2
    assert_contains "AC21 [replaced lock] the refusal names the live pid" "$ERR" "$LIVE21"
    assert_no_path "AC21 [replaced lock] no install.sh call" "$VD/.calls"
    assert_eq "AC21 [replaced lock] no harness run" "" "$(vlog)"
    assert_eq "AC21 [replaced lock] the live runner's pid is still in the lock" "$LIVE21" "$(tr -d '[:space:]' < "$VL21/pid" 2>/dev/null)"
    assert_eq "AC21 [replaced lock] its snapshot was not touched" "LIVE-SNAP" "$(cat "$VL21/snap/playbook/VERSION" 2>/dev/null)"
    assert_eq "AC21 [replaced lock] no takeover claim is left in the lock" "" "$(ls -A "$VL21" 2>/dev/null | grep '^takeover\.')"
    assert_eq "AC21 [replaced lock] the rest of the home is as before" "$B_21b" "$(tree_sig "$VH" | grep -v '\.pb-variant\.lock')"
  else
    t_bad "AC21 [replaced lock] setup: the runner read the lock pid" "no 'held' file after 20 s; stderr: $(cat "$C_OD/stderr" 2>/dev/null)"
    : > "$HC/go"; kill -KILL "$C_PID" 2>/dev/null; wait "$C_PID" 2>/dev/null
  fi
  kill "$LIVE21" 2>/dev/null; wait "$LIVE21" 2>/dev/null
  rm -rf "$VL21"
fi

# ---- AC22: a runner that took a stale lock over keeps the lock until its own install ----
# Hold point: the PATH shim pauses the runner right BEFORE its 2nd "mkdir <H>/.agents/.pb-variant.lock" (the 1st finds the stale lock; the 2nd
# is the loop going round after pbh_variant_restore_dir removed the lock) until $HD/go exists. restore_dir ends in shell builtins only, so
# that mkdir is the first command that can be shimmed after the lock is gone: the pause lies in the gap. In the gap the test plays runner B:
# it claims the lock with a live pid. With the gap, the runner that took the stale lock over ends with exit 2 ("another variant run");
# once it keeps the lock it makes no 2nd mkdir of it, ends with exit 0 and the pause is never hit.
echo "AC22 a runner that took a stale lock over and restored it is not refused by a runner that claims the lock right after the restore"
mk_variant; VH="$(mk_vhome)"; B_22="$(tree_sig "$VH")"; vmk_stale "$VH"; VL22="$VL"; DEAD22="$(cat "$VL/pid")"
HD="$(mk_tmp)"
VW_SHIM="$VSHIM" VSHIM_MKLOCK_DIR="$HD" vstart --variant "$VD" $VBASE
D_PID=$VPID; D_OD="$VOD"
i=0; while [ ! -e "$HD/held" ] && valive "$D_PID" && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
GAP22=0
if [ ! -e "$HD/held" ] && valive "$D_PID"; then
  t_bad "AC22 setup: the runner neither paused before re-taking the lock nor ended" "still running after 30 s; stderr: $(cat "$D_OD/stderr" 2>/dev/null)"
  kill -KILL "$D_PID" 2>/dev/null; wait "$D_PID" 2>/dev/null
else
  LIVE22=""
  if [ -e "$HD/held" ]; then   # the runner is in the gap: runner B (a live pid) claims the lock now
    GAP22=1
    sleep 120 & LIVE22=$!
    if mkdir "$VL22" 2>/dev/null; then
      printf '%s\n' "$LIVE22" > "$VL22/pid"; mkdir -p "$VL22/snap/playbook"; printf 'LIVE-SNAP\n' > "$VL22/snap/playbook/VERSION"
    fi
    : > "$HD/go"
  fi
  VOD="$D_OD"; vfinish "$D_PID"
  assert_rc "AC22 the runner that took the stale lock over finishes (exit 0)" 0
  assert_not_contains "AC22 it was not refused as 'another variant run'" "$ERR" "another variant run"
  assert_contains "AC22 it restored the stale snapshot" "$ERR" "variant: restored a stale snapshot left by pid $DEAD22"
  assert_contains "AC22 its eval ran with the variant installed" "$(vlog)" "run ver=1.2.3-variant"
  if [ "$GAP22" = 1 ]; then
    assert_eq "AC22 the lock claimed in the gap was not taken over or installed over (pid and snapshot are still B's)" "$LIVE22 LIVE-SNAP" "$(tr -d '[:space:]' < "$VL22/pid" 2>/dev/null) $(cat "$VL22/snap/playbook/VERSION" 2>/dev/null)"
    kill "$LIVE22" 2>/dev/null; wait "$LIVE22" 2>/dev/null
    rm -rf "$VL22"   # B's claim, made by this test inside its own temp home
  fi
  expect_restored "AC22 at the end" "$B_22"
fi


# ================= AC5': the REAL install.sh as the variant leaves settings.json and playbook.conf byte for byte =================
echo "AC5' a variant run with the real install.sh (hooks on by default) leaves <home>/.claude/settings.json and <home>/.agents/playbook.conf byte-identical"
fsig() { if [ -f "$1" ]; then cksum < "$1"; else echo absent; fi; }
for kind in with-files without-files; do
  VH="$(mk_vhome)"; unset VHOME
  if [ "$kind" = with-files ]; then
    printf '{\n  "model": "opus"\n}\n' > "$VH/.claude/settings.json"
    printf 'autonomy=full\n' >> "$VH/.agents/playbook.conf"
  fi
  SJ0="$(fsig "$VH/.claude/settings.json")"; CF0="$(fsig "$VH/.agents/playbook.conf")"
  vrun --variant "$PB_ROOT" $VBASE
  assert_rc "AC5' [$kind] the real-install variant run ends with exit 0" 0
  assert_eq "AC5' [$kind] settings.json is byte for byte as before (or still absent)" "$SJ0" "$(fsig "$VH/.claude/settings.json")"
  assert_eq "AC5' [$kind] playbook.conf is byte for byte as before (or still absent)" "$CF0" "$(fsig "$VH/.agents/playbook.conf")"
  assert_eq "AC5' [$kind] no settings backup is left in playbook-backups" "0" "$(ls "$VH/.agents/playbook-backups" 2>/dev/null | grep -c '^settings\.json')"
done

t_summary
