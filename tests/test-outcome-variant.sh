#!/usr/bin/env bash
# Tests for evals/run-outcome.sh --variant DIR (v0.31 slice S2, spec .agents/handoff/01-spec.md AC1-AC8, AC9 synopsis only):
# the same contract as evals/run-evals.sh (tests/test-evals-variant.sh covers the shared lib code in depth; this suite keeps the
# cases that prove run-outcome.sh is wired to it): the runner snapshots the install targets of the harness home H, installs DIR
# into H BEFORE the first harness run (also before the leak probe), runs the outcome task, and puts the snapshot back.
# Never calls a real harness and never touches a real home: HOME, PB_VARIANT_HOME and PLAYBOOK_REGISTRY are temp dirs/files,
# the "claude" on PATH is a fake that records what the home looked like when it ran (and solves the fixture task t-add), and
# DIR/install.sh is a fake switched by marker files in DIR (.m-fail-install, .m-fail-doctor, .m-wrong-version, .m-extra, .m-lock-skills).
# run-outcome.sh has no --real-home flag, so the AC6 refusal of --variant with --real-home does not apply here.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-arms-fixture.sh"   # jget, alive, PBH; its own fakes/home are not used here
. "$(dirname "$0")/outcome-fixture.sh"      # OUTCOME, T (fixture tasks), SA (stub adapters)

VFK="$(mk_tmp)"   # the fake harness binary and the runner wrapper
VBASE="--harness claude --tasks-dir $T --tasks t-add"

# ---- the fake claude: records the home as it is when a run starts, then solves t-add like a good agent ----
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
if [ -n "${VFAKE_SLEEP:-}" ]; then
  echo $$ > "$VFAKE_DIR/sleeper.pid"; : > "$VFAKE_DIR/started"
  exec sleep 120
fi
if [ -f "$VFAKE_TASKS/t-add/solution.patch" ]; then git apply "$VFAKE_TASKS/t-add/solution.patch" 2>/dev/null; fi
echo '{"type":"system","subtype":"init","session_id":"s1","skills":[],"slash_commands":[]}'
echo '{"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.01,"result":"Done."}'
exit 0
EOF
chmod 755 "$VFK/claude"

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
export VW_FK="$VFK" VW_RUNNER="$OUTCOME" VFAKE_PBH="$PBH" VFAKE_TASKS="$T"
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
    SK="$H/.claude/skills"; BL="$H/.claude/CLAUDE.md"
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
# tree_sig DIR -> every regular file (mode, md5) and symlink (target) under DIR, sorted; directories are not listed
tree_sig() {
  (cd "$1" && find . -mindepth 1 \( -type f -o -type l \) | LC_ALL=C sort | while IFS= read -r p; do
    if [ -L "$p" ]; then printf 'L %s -> %s\n' "$p" "$(readlink "$p")"
    else printf 'F %s %s %s\n' "$p" "$(fmode "$p")" "$(md5sum < "$p")"; fi
  done)
}
# vsetup/vrun/vstart: run the runner (HOME=$VH, PB_VARIANT_HOME=$VHOME or $VH, registry $VREG unless VNOREG=1);
# sets OUT ERR RC VWR VOD VRES VFD
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
expect_restored() {
  assert_eq "$1: the home is restored exactly (files, modes, content, symlinks)" "$2" "$(tree_sig "$VH")"
  assert_no_path "$1: the lock is removed" "$VH/.agents/.pb-variant.lock"
}
unlock() { chmod u+rwx "$VH/.claude/skills" "$VH/.agents/skills" 2>/dev/null; }   # only the dirs the fake install made read-only (non-recursive: the kept snapshot keeps its modes)

# ================= AC9 synopsis =================
echo "AC9 --help of run-outcome.sh documents --variant"
run bash "$OUTCOME" --help
assert_contains "AC9 the usage text mentions --variant" "$OUT" "--variant"

# ================= AC1 AC2 AC3 AC7: the main copy-home run =================
echo "AC1 AC2 AC3 AC7 a variant run on a copy home: snapshot, install, run, restore"
mk_variant; : > "$VD/.m-extra"; VH="$(mk_vhome)"; unset VHOME
B_MAIN="$(tree_sig "$VH")"
vrun --variant "$VD" $VBASE
assert_rc "AC1 the run ends with exit 0 (the fake agent solved t-add)" 0
assert_file "AC2 the fake install.sh was called" "$VD/.calls"
CALLS="$(vcalls)"
assert_contains "AC2 install is called as: install --home H --copy --harness claude --yes" "$CALLS" "install --home $VH --copy --harness claude --yes|"
assert_contains "AC2 doctor is called as: doctor --home H --harness claude" "$CALLS" "doctor --home $VH --harness claude|"
assert_eq "AC2 install comes before doctor" "install doctor" "$(printf '%s\n' "$CALLS" | sed 's/ .*//' | tr '\n' ' ' | sed 's/ $//')"
assert_not_contains "AC2 AC17 (D11, was: the caller's registry) install and doctor get a runner temp registry, never the caller's PLAYBOOK_REGISTRY" "$CALLS" "registry=$VREG|"
assert_no_path "AC2 DIR's own registry was never written" "$VD/.install-targets"
assert_contains "AC2 stderr: variant: installed <DIR> (<VERSION>, no git)" "$ERR" "variant: installed $VD (1.2.3-variant, no git)"
LOGM="$(vlog)"
assert_contains "AC1 the run sees the variant installed (normalised VERSION)" "$LOGM" "run ver=1.2.3-variant"
assert_contains "AC1 playbook-* skills of the home moved away, other skills stay, the variant's are in" "$LOGM" "cskills=myskill,playbook-vskill,varskill,"
assert_contains "AC1 playbook-* skills of \$H/.agents/skills are moved away too (playbook-old gone, variant's extra in)" "$LOGM" "askills=playbook-vskill,"
assert_contains "AC1 a non-prefixed skill named like DIR/skills/varskill is the variant's during the run" "$LOGM" "varskill=[variant varskill]"
assert_contains "AC1 the block file holds the variant's block" "$LOGM" "block=1"
assert_contains "AC3 stderr: variant: restored the snapshot of <H>" "$ERR" "variant: restored the snapshot of $VH"
expect_restored "AC3 normal end" "$B_MAIN"
assert_no_path "AC3 a target absent before stays absent: \$H/.codex/AGENTS.md" "$VH/.codex/AGENTS.md"
assert_no_path "AC3 a target absent before stays absent: \$H/.config/opencode/AGENTS.md" "$VH/.config/opencode/AGENTS.md"
assert_eq "AC3 the block file is byte-equal (no trailing newline, UTF-8)" "$(printf 'my notes\n<!-- BEGIN agent-playbook base -->\nbase block \xc3\xa9 $x\n<!-- END agent-playbook -->\nlast line, no newline' | md5sum)" "$(md5sum < "$VH/.claude/CLAUDE.md")"
if [ "$VMODEKEEP" = 1 ]; then
  assert_eq "AC3 the block file mode is back to 640" "640" "$(fmode "$VH/.claude/CLAUDE.md")"
else t_skip 1 "AC3 the block file mode is back to 640 (chmod modes are not kept here: NTFS)"; fi
assert_eq "AC3 the user's own varskill is back (not the variant's)" "user varskill" "$(cat "$VH/.claude/skills/varskill/SKILL.md")"
assert_eq "AC1 the other skill (myskill) and the credentials were never touched" "mine SECRET-TOKEN" "$(cat "$VH/.claude/skills/myskill/SKILL.md") $(cat "$VH/.claude/.credentials.json")"
# AC7 md and JSON
MDL="$(grep '^Variant:' "$VRES")"
assert_contains "AC7 md: Variant: <DIR> (<VERSION>," "$MDL" "Variant: $VD (1.2.3-variant,"
assert_contains "AC7 md: the Variant line ends with 'snapshot restored'" "$MDL" "snapshot restored"
JS="${VRES%.md}.json"
assert_eq "AC7 JSON variant.tree" "$VD" "$(jget "$JS" 'j.variant && j.variant.tree')"
assert_eq "AC7 JSON variant.version" "1.2.3-variant" "$(jget "$JS" 'j.variant && j.variant.version')"
assert_eq "AC7 JSON variant.sha is null for a DIR that is not a git tree" "null" "$(jget "$JS" 'j.variant && j.variant.sha')"
END_OK="$(jget "$JS" 'j.variant && j.variant.end_check')"
case "$END_OK" in ""|null|undefined|NOJSON|ERR:*) t_bad "AC7 JSON variant.end_check is set when the end check passed" "got [$END_OK]" ;; *) t_ok "AC7 JSON variant.end_check is set when the end check passed" ;; esac
CMODELS="$(grep '^Conf models:' "$VRES")"
assert_contains "AC7 md: Conf models: names model_tester_claude=opus-x1" "$CMODELS" "model_tester_claude=opus-x1"
assert_contains "AC7 md: Conf models: names model_reviewer_claude=sonnet" "$CMODELS" "model_reviewer_claude=sonnet"
assert_not_contains "AC7 md: Conf models: lists model_* keys only (no test_cmd)" "$CMODELS" "test_cmd"
assert_not_contains "AC7 md: Conf models: no feedback_repo" "$CMODELS" "feedback_repo"
assert_eq "AC7 JSON conf_models keys" '["model_reviewer_claude","model_tester_claude"]' "$(jget "$JS" 'JSON.stringify(Object.keys(j.conf_models).sort())')"
assert_eq "AC7 JSON conf_models value (differs from its key)" "opus-x1" "$(jget "$JS" 'j.conf_models.model_tester_claude')"

# ================= AC3 link home =================
echo "AC3 a link home: symlinks into another tree come back as the same symlinks"
if [ "$SYMLINKS" = 1 ]; then
  mk_variant; VH="$(mk_vhome link)"; VSRC="$(dirname "$(readlink "$VH/.agents/playbook")")"; B_LINK="$(tree_sig "$VH")"; S_BEFORE="$(tree_sig "$VSRC")"
  assert_link_to "AC3 setup: \$H/.agents/playbook is a link" "$VH/.agents/playbook" "$VSRC/playbook"
  vrun --variant "$VD" $VBASE
  assert_rc "AC3 link home: exit 0" 0
  assert_contains "AC1 link home: the run saw the variant" "$(vlog)" "run ver=1.2.3-variant"
  expect_restored "AC3 link home" "$B_LINK"
  assert_link_to "AC3 \$H/.agents/playbook is the same symlink (readlink equal)" "$VH/.agents/playbook" "$VSRC/playbook"
  assert_link_to "AC3 playbook-base skill is the same symlink" "$VH/.claude/skills/playbook-base" "$VSRC/skills/playbook-base"
  assert_link_to "AC3 the non-prefixed varskill is the same symlink" "$VH/.claude/skills/varskill" "$VSRC/skills/varskill"
  assert_eq "AC3 nothing was written through the links into the source tree" "$S_BEFORE" "$(tree_sig "$VSRC")"
else
  t_skip 7 "AC3 link home (no symlink rights here)"
fi

# ================= AC2 AC3: exit 3 =================
echo "AC2 AC3 install fails, doctor fails or the installed VERSION differs: exit 3 before any run, home restored"
for m in fail-install fail-doctor wrong-version; do
  mk_variant; : > "$VD/.m-$m"; VH="$(mk_vhome)"; B_3="$(tree_sig "$VH")"
  vrun --variant "$VD" $VBASE
  assert_rc "AC2 $m -> exit 3" 3
  assert_eq "AC2 $m: no run started" "" "$(vlog)"
  assert_contains "AC3 $m: stderr says the snapshot was restored" "$ERR" "variant: restored the snapshot of $VH"
  expect_restored "AC3 $m" "$B_3"
done

# ================= AC1: snapshot and install come before the leak probe =================
echo "AC1 the leak probe runs with the variant installed (snapshot and install first); --arm both is allowed"
mk_variant; VH="$(mk_vhome)"; B_P="$(tree_sig "$VH")"
vrun --variant "$VD" $VBASE --arm both --model m-1
LOGM="$(vlog)"
assert_eq "AC1 the first harness call is the leak probe and it sees the variant installed" "probe ver=1.2.3-variant" "$(printf '%s\n' "$LOGM" | head -n 1)"
assert_contains "AC1 the runs saw the variant too" "$LOGM" "run ver=1.2.3-variant"
assert_not_contains "AC1 no run saw the base playbook" "$LOGM" "ver=0.0.1-base"
expect_restored "AC3 --arm both" "$B_P"

# ================= AC5 end check =================
echo "AC5 the VERSION changed during the run: results marked, exit 3, home restored"
mk_variant; VH="$(mk_vhome)"; B_E="$(tree_sig "$VH")"
VFAKE_TAMPER=1 vrun --variant "$VD" $VBASE
assert_rc "AC5 changed VERSION -> exit 3" 3
assert_contains "AC5 md: variant changed during the run" "$(cat "$VRES" 2>/dev/null)" "variant changed during the run"
assert_contains "AC5 md Variant line: end check FAILED" "$(grep '^Variant:' "$VRES" 2>/dev/null)" "end check FAILED"
JS="${VRES%.md}.json"
if [ "$(jget "$JS" 'j.variant && j.variant.end_check')" != "$END_OK" ]; then t_ok "AC5 JSON variant.end_check differs from a passing run's"; else t_bad "AC5 JSON variant.end_check differs from a passing run's" "same as the passing run: [$END_OK]"; fi
expect_restored "AC5" "$B_E"
unset VFAKE_TAMPER

# ================= AC3 restore failure =================
echo "AC3 AC4 the restore fails: exit 5 (wins over exit 3), RESTORE FAILED, the snapshot is kept; the next run restores it as stale"
if [ "$VDIRPERM" = 0 ]; then
  t_skip 10 "AC3 restore failure (a read-only directory is still writable here: root or NTFS)"
else
  mk_variant; : > "$VD/.m-lock-skills"; VH="$(mk_vhome)"; B_5="$(tree_sig "$VH")"
  vrun --variant "$VD" $VBASE
  assert_rc "AC3 restore failure -> exit 5" 5
  assert_contains "AC3 stderr: variant: RESTORE FAILED, snapshot kept at" "$ERR" "variant: RESTORE FAILED, snapshot kept at "
  SNAP="$(printf '%s\n' "$ERR" | sed -n 's/.*variant: RESTORE FAILED, snapshot kept at //p' | head -n 1)"
  if [ -n "$SNAP" ] && [ -e "$SNAP" ]; then t_ok "AC3 the kept snapshot path exists"; else t_bad "AC3 the kept snapshot path exists" "path [$SNAP]"; fi
  case "$SNAP" in "$VH/.agents/.pb-variant.lock"/*) t_ok "AC3 the snapshot is inside the lock dir" ;; *) t_bad "AC3 the snapshot is inside the lock dir" "path [$SNAP]" ;; esac
  assert_dir "AC3 the lock stays after a failed restore" "$VH/.agents/.pb-variant.lock"
  unlock
  mk_variant
  vrun --variant "$VD" $VBASE
  assert_rc "AC4 next run after a failed restore: exit 0" 0
  assert_contains "AC4 the next run restores the stale snapshot first" "$ERR" "variant: restored a stale snapshot left by pid "
  # the kept snapshot keeps its modes (unlock above was not recursive), so the restored home equals the original
  expect_restored "AC4 stale snapshot of a failed restore" "$B_5"
  # exit 5 wins over exit 3
  mk_variant; : > "$VD/.m-lock-skills"; : > "$VD/.m-wrong-version"; VH="$(mk_vhome)"
  vrun --variant "$VD" $VBASE
  assert_rc "AC3 exit 5 wins over exit 3 (wrong VERSION and a failed restore)" 5
  unlock
fi

# ================= AC4 lock (live pid), warning, TERM and HUP restore =================
echo "AC4 AC3 a live lock refuses a second variant run (exit 2, nothing touched); a run without --variant warns; TERM and HUP restore"
for sig in TERM HUP; do
  mk_variant; VH="$(mk_vhome)"; B_L="$(tree_sig "$VH")"
  VFAKE_SLEEP=1 vstart --variant "$VD" $VBASE
  A_PID=$VPID; A_OD="$VOD"; A_FD="$VFD"
  if vwait_file "$A_FD/started"; then
    SIG_A="$(tree_sig "$VH")"; CALLS_A="$(vcalls)"
    assert_dir "AC4 [$sig] the lock dir exists while the run is live" "$VH/.agents/.pb-variant.lock"
    if [ "$SIG_A" != "$B_L" ]; then t_ok "AC1 [$sig] the home holds the variant while it runs"; else t_bad "AC1 [$sig] the home holds the variant while it runs" "no change seen"; fi
    unset VFAKE_SLEEP
    vrun --variant "$VD" $VBASE
    assert_rc "AC4 [$sig] second variant run on a live lock -> exit 2" 2
    assert_contains "AC4 [$sig] the refusal names the live pid" "$ERR$OUT" "$A_PID"
    assert_not_contains "AC4 [$sig] the refusal is not an unknown-option error" "$ERR$OUT" "unknown option"
    assert_eq "AC4 [$sig] the refused run touched nothing" "$SIG_A" "$(tree_sig "$VH")"
    assert_eq "AC4 [$sig] the refused run called no install.sh" "$CALLS_A" "$(vcalls)"
    vrun $VBASE
    assert_rc "AC4 [$sig] a run without --variant on a locked home still runs (exit 0)" 0
    assert_contains "AC4 [$sig] it warns: a variant run (pid N) has another tree installed in <H>" "$ERR" "WARNING a variant run (pid $A_PID) has another tree installed in $VH"
    assert_eq "AC4 [$sig] the warning run touched nothing" "$SIG_A" "$(tree_sig "$VH")"
    kill -s "$sig" "$A_PID" 2>/dev/null
    VOD="$A_OD"; vfinish "$A_PID"
    if [ "$RC" != 0 ]; then t_ok "AC3 [$sig] the interrupted runner exits non-zero"; else t_bad "AC3 [$sig] the interrupted runner exits non-zero" "rc 0"; fi
    assert_contains "AC3 [$sig] the interrupted runner printed the restore line" "$ERR" "variant: restored the snapshot of $VH"
    expect_restored "AC3 [$sig]" "$B_L"
  else
    t_bad "AC4 [$sig] the first runner reached its adapter" "no 'started' file after 20 s; stderr: $(cat "$A_OD/stderr" 2>/dev/null)"
    kill -KILL "$A_PID" 2>/dev/null; wait "$A_PID" 2>/dev/null
  fi
  [ -f "$A_FD/sleeper.pid" ] && kill "$(cat "$A_FD/sleeper.pid")" 2>/dev/null
  unset VFAKE_SLEEP
done

# ================= AC4 stale lock after SIGKILL =================
echo "AC4 AC3 SIGKILL cannot be handled: the variant and the lock stay; the next run restores the stale snapshot and goes on"
mk_variant; VH="$(mk_vhome)"; B_K="$(tree_sig "$VH")"
VFAKE_SLEEP=1 vstart --variant "$VD" $VBASE
K_PID=$VPID; K_FD="$VFD"
if vwait_file "$K_FD/started"; then
  kill -KILL "$K_PID" 2>/dev/null; wait "$K_PID" 2>/dev/null
  kill "$(cat "$K_FD/sleeper.pid")" 2>/dev/null
  unset VFAKE_SLEEP
  assert_dir "AC3 after SIGKILL the lock stays" "$VH/.agents/.pb-variant.lock"
  assert_eq "AC3 after SIGKILL the variant stays installed" "1.2.3-variant" "$(tr -d ' \r\n' < "$VH/.agents/playbook/VERSION")"
  vrun --variant "$VD" $VBASE
  assert_rc "AC4 stale lock: the new run goes on (exit 0)" 0
  assert_contains "AC4 stale lock: variant: restored a stale snapshot left by pid N" "$ERR" "variant: restored a stale snapshot left by pid $K_PID"
  assert_contains "AC4 stale lock: the new run saw the variant installed" "$(vlog)" "run ver=1.2.3-variant"
  expect_restored "AC4 stale lock" "$B_K"
else
  t_bad "AC4 stale lock: the first runner reached its adapter" "no 'started' file"
  kill -KILL "$K_PID" 2>/dev/null; wait "$K_PID" 2>/dev/null
  [ -f "$K_FD/sleeper.pid" ] && kill "$(cat "$K_FD/sleeper.pid")" 2>/dev/null
fi
unset VFAKE_SLEEP

# ================= AC6 refusals =================
echo "AC6 refusals: exit 2, nothing touched, no install.sh call (no --real-home flag in run-outcome.sh)"
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
mk_variant; VH="$(mk_vhome)"
refuse "--variant with --cmd" "--cmd" --variant "$VD" --cmd "bash $SA/idle.sh" --tasks-dir "$T" --tasks t-add
refuse "--variant with --arm without (alone)" "--arm" --variant "$VD" $VBASE --arm without --model m-1
refuse "--variant without a value" "--variant" --variant
mk_variant; rm -f "$VD/install.sh"; refuse "--variant DIR without install.sh" "install.sh" --variant "$VD" $VBASE
mk_variant; rm -f "$VD/VERSION"; refuse "--variant DIR without VERSION" "VERSION" --variant "$VD" $VBASE
VD="$VH/no-such-dir"; refuse "--variant DIR that does not exist" "no-such-dir" --variant "$VD" $VBASE

# ================= PB_VARIANT_HOME =================
echo "AC1 H is PB_VARIANT_HOME when set: the install goes there, HOME is not touched"
mk_variant; VH="$(mk_vhome)"; DECOY="$(mk_vhome)"
B_V="$(tree_sig "$VH")"; B_D="$(tree_sig "$DECOY")"
HOME_SAVE="$VH"; VH="$DECOY"; VHOME="$HOME_SAVE"
vrun --variant "$VD" $VBASE
assert_contains "AC1 install --home is PB_VARIANT_HOME" "$(vcalls)" "install --home $HOME_SAVE --copy --harness claude --yes|"
assert_contains "AC1 stderr names PB_VARIANT_HOME as the restored home" "$ERR" "variant: restored the snapshot of $HOME_SAVE"
assert_eq "AC3 PB_VARIANT_HOME restored" "$B_V" "$(tree_sig "$HOME_SAVE")"
assert_eq "AC1 the HOME stand-in was not touched at all" "$B_D" "$(tree_sig "$DECOY")"
assert_no_path "AC4 no lock in HOME" "$DECOY/.agents/.pb-variant.lock"
unset VHOME

# ================= AC8 without --variant =================
echo "AC8 without --variant: no install call, no Variant line, JSON variant null, conf models still recorded"
mk_variant; VH="$(mk_vhome)"; B_8="$(tree_sig "$VH")"
vrun $VBASE --arm both --model m-1
assert_rc "AC8 control: --arm both without --variant -> exit 0" 0
assert_no_path "AC8 install.sh of an unrelated DIR is never called" "$VD/.calls"
assert_eq "AC8 the home is untouched" "$B_8" "$(tree_sig "$VH")"
assert_no_path "AC8 no lock" "$VH/.agents/.pb-variant.lock"
assert_eq "AC8 md has no Variant line" "0" "$(grep -c '^Variant:' "$VRES")"
JS="${VRES%.md}.json"
assert_eq "AC8 JSON has the key variant" "true" "$(jget "$JS" '"variant" in j')"
assert_eq "AC8 JSON variant is null" "null" "$(jget "$JS" 'j.variant')"
assert_contains "AC7 the Conf models line is written without --variant too" "$(grep '^Conf models:' "$VRES")" "model_tester_claude=opus-x1"
assert_eq "AC7 JSON conf_models without --variant" "opus-x1" "$(jget "$JS" 'j.conf_models.model_tester_claude')"
assert_contains "AC8 the runs saw the installed (base) playbook" "$(vlog)" "run ver=0.0.1-base"
assert_not_contains "AC8 no run saw a variant" "$(vlog)" "1.2.3-variant"
echo "AC7 a conf without model_* keys: 'Conf models: none' and an empty conf_models"
printf 'test_cmd=make check\nfeedback_repo=acme/fb\n' > "$VH/.agents/playbook.conf"
vrun $VBASE
assert_eq "AC7 md: Conf models: none" "Conf models: none" "$(grep '^Conf models:' "$VRES")"
assert_eq "AC7 JSON conf_models is {}" "{}" "$(jget "${VRES%.md}.json" 'j.conf_models')"

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
chmod 755 "$VSHIM/shim"; cp "$VSHIM/shim" "$VSHIM/mv"; cp "$VSHIM/shim" "$VSHIM/cp"; cp "$VSHIM/shim" "$VSHIM/rm"
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
run bash "$OUTCOME" --help
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

t_summary
