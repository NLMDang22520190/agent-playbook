#!/usr/bin/env bash
. "$(dirname "$0")/evals-variant-fixture.sh"
# ================= AC9 synopsis =================
echo "AC9 --help of run-evals.sh documents --variant"
run bash "$RUNNER" --help
assert_contains "AC9 the usage text mentions --variant" "$OUT" "--variant"

# ================= AC1 AC2 AC3 AC7: the main copy-home run =================
echo "AC1 AC2 AC3 AC7 a variant run on a copy home: snapshot, install, run, restore"
mk_variant; : > "$VD/.m-extra"; VH="$(mk_vhome)"; unset VHOME
B_MAIN="$(tree_sig "$VH")"
vrun --variant "$VD" $VBASE
assert_rc "AC1 the run ends with exit 0" 0
assert_file "AC2 the fake install.sh was called" "$VD/.calls"
CALLS="$(vcalls)"
assert_contains "AC2 install is called as: install --home H --copy --harness claude --yes" "$CALLS" "install --home $VH --copy --harness claude --yes|"
assert_contains "AC2 doctor is called as: doctor --home H --harness claude" "$CALLS" "doctor --home $VH --harness claude|"
assert_eq "AC2 install comes before doctor" "install doctor" "$(printf '%s\n' "$CALLS" | sed 's/ .*//' | tr '\n' ' ' | sed 's/ $//')"
assert_not_contains "AC2 AC17 (D11, was: the caller's registry) install and doctor get a runner temp registry, never the caller's PLAYBOOK_REGISTRY" "$CALLS" "registry=$VREG|"
assert_no_path "AC2 DIR's own registry was never written" "$VD/.install-targets"
assert_contains "AC5' the variant install runs with PB_HOOKS=off (no hooks, no conf change in the harness home)" "$(cat "$VD/.env" 2>/dev/null)" "install|PB_HOOKS=off|"
assert_contains "AC2 stderr: variant: installed <DIR> (<VERSION>, no git)" "$ERR" "variant: installed $VD (1.2.3-variant, no git)"
LOGM="$(vlog)"
assert_contains "AC1 the run sees the variant installed (normalised VERSION)" "$LOGM" "run ver=1.2.3-variant"
assert_contains "AC1 the playbook-* skills of the home were moved away during the run, the other skills stay, the variant's are in" "$LOGM" "cskills=myskill,playbook-vskill,varskill,"
assert_contains "AC1 playbook-* skills of \$H/.agents/skills are moved away too (playbook-old gone, variant's extra in)" "$LOGM" "askills=playbook-vskill,"
assert_contains "AC1 a non-prefixed skill named like DIR/skills/varskill is the variant's during the run" "$LOGM" "varskill=[variant varskill]"
assert_contains "AC1 the block file holds the variant's block" "$LOGM" "block=1"
assert_contains "AC3 stderr: variant: restored the snapshot of <H>" "$ERR" "variant: restored the snapshot of $VH"
expect_restored "AC3 normal end" "$B_MAIN"
assert_no_path "AC3 a target absent before stays absent: \$H/.codex/AGENTS.md" "$VH/.codex/AGENTS.md"
assert_no_path "AC3 a target absent before stays absent: \$H/.config/opencode/AGENTS.md" "$VH/.config/opencode/AGENTS.md"
assert_eq "AC3 the block file is byte-equal (no trailing newline, UTF-8, mode 640)" "$(printf 'my notes\n<!-- BEGIN agent-playbook base -->\nbase block \xc3\xa9 $x\n<!-- END agent-playbook -->\nlast line, no newline' | md5sum)" "$(md5sum < "$VH/.claude/CLAUDE.md")"
if [ "$VMODEKEEP" = 1 ]; then
  assert_eq "AC3 the block file mode is back to 640" "640" "$(fmode "$VH/.claude/CLAUDE.md")"
else t_skip 1 "AC3 the block file mode is back to 640 (chmod modes are not kept here: NTFS)"; fi
assert_eq "AC3 the user's own varskill is back (not the variant's)" "user varskill" "$(cat "$VH/.claude/skills/varskill/SKILL.md")"
if [ "$VMODEKEEP" = 1 ]; then
  assert_eq "AC3 a private mode 600 file in a snapshot dir keeps its mode" "600" "$(fmode "$VH/.claude/skills/playbook-base/sub/x.txt")"
else t_skip 1 "AC3 a private mode 600 file keeps its mode (chmod modes are not kept here: NTFS)"; fi
assert_eq "AC3 a mode 755 script keeps its mode" "755" "$(fmode "$VH/.agents/playbook/scripts/base.sh")"
assert_no_path "AC3 the variant's playbook-vskill is gone" "$VH/.claude/skills/playbook-vskill"
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

# ================= AC7 git DIR, AC2 registry without a caller registry =================
echo "AC7 AC2 a variant DIR that is a git tree: sha in the JSON and the stderr line; registry set although the caller set none"
mk_variant; VH="$(mk_vhome)"; B_GIT="$(tree_sig "$VH")"
git -C "$VD" init -q && git -C "$VD" -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false add -A && git -C "$VD" -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false commit -q -m v
GS="$(git -C "$VD" rev-parse --short HEAD)"; GF="$(git -C "$VD" rev-parse HEAD)"
VNOREG=1 vrun --variant "$VD" $VBASE
unset VNOREG
assert_rc "AC7 git DIR: exit 0" 0
assert_contains "AC2 stderr: variant: installed <DIR> (<VERSION>, <git short sha>)" "$ERR" "variant: installed $VD (1.2.3-variant, $GS)"
JS="${VRES%.md}.json"
JSHA="$(jget "$JS" 'j.variant && j.variant.sha')"
case "$JSHA" in ""|null|undefined) t_bad "AC7 JSON variant.sha is the commit sha" "got [$JSHA]" ;; *) case "$GF" in "$JSHA"*) t_ok "AC7 JSON variant.sha is (a prefix of) the commit sha" ;; *) t_bad "AC7 JSON variant.sha is (a prefix of) the commit sha" "got [$JSHA] want prefix of [$GF]" ;; esac ;; esac
assert_contains "AC7 md Variant line carries the sha" "$(grep '^Variant:' "$VRES")" "$GS"
CALLS="$(vcalls)"
case "$CALLS" in *"registry=UNSET|"*|*"registry=|"*) t_bad "AC2 install and doctor get a PLAYBOOK_REGISTRY even if the caller set none" "$CALLS" ;; *) t_ok "AC2 install and doctor get a PLAYBOOK_REGISTRY even if the caller set none" ;; esac
assert_no_path "AC2 DIR's own .install-targets was not written when the caller set no registry" "$VD/.install-targets"
assert_eq "AC2 install and doctor use the same registry file" "1" "$(printf '%s\n' "$CALLS" | sed -n 's/.*registry=\([^|]*\)|.*/\1/p' | sort -u | grep -c .)"
expect_restored "AC3 git DIR" "$B_GIT"

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
  assert_link_to "AC3 \$H/.agents/skills/playbook-old is the same symlink" "$VH/.agents/skills/playbook-old" "$VSRC/skills/playbook-old"
  assert_eq "AC3 nothing was written through the links into the source tree" "$S_BEFORE" "$(tree_sig "$VSRC")"
else
  t_skip 8 "AC3 link home (no symlink rights here)"
fi

# ================= AC1 AC2: every harness =================
echo "AC1 AC2 AC3 --harness codex and opencode: install --harness h, same restore"
for h in codex opencode; do
  mk_variant; VH="$(mk_vhome)"; B_H="$(tree_sig "$VH")"
  vrun --variant "$VD" --harness "$h" --scenarios E8
  assert_contains "AC2 $h: install is called with --harness $h" "$(vcalls)" "install --home $VH --copy --harness $h --yes|"
  assert_contains "AC2 $h: doctor is called with --harness $h" "$(vcalls)" "doctor --home $VH --harness $h|"
  expect_restored "AC3 $h" "$B_H"
done

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
vrun --variant "$VD" --harness claude --scenarios E8 --arm both --model m-1
LOGM="$(vlog)"
assert_eq "AC1 the first harness call is the leak probe and it sees the variant installed" "probe ver=1.2.3-variant" "$(printf '%s\n' "$LOGM" | head -n 1)"
assert_contains "AC1 the runs saw the variant too" "$LOGM" "run ver=1.2.3-variant"
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
  mk_variant; VD2="$VD"
  vrun --variant "$VD2" $VBASE
  assert_rc "AC4 next run after a failed restore: exit 0" 0
  assert_contains "AC4 the next run restores the stale snapshot first" "$ERR" "variant: restored a stale snapshot left by pid "
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
echo "AC3 AC4 SIGKILL leaves the variant installed and the lock; the next variant run restores the stale snapshot, notes it and goes on"
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
echo "AC6 refusals: exit 2, nothing touched, no install.sh call"
mk_variant; VH="$(mk_vhome)"
refuse "--variant with --cmd" "--cmd" --variant "$VD" --cmd "bash $A/idle.sh" --scenarios E8
refuse "--variant with --real-home" "--real-home" --variant "$VD" $VBASE --real-home
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
vrun --harness claude --scenarios E8 --arm both --model m-1
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

t_summary
