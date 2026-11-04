#!/usr/bin/env bash
# Shared setup of tests/test-evals-jobs.sh and tests/test-outcome-jobs.sh (slice C1: --jobs N and the held variant
# --variant-held DIR of evals/run-evals.sh and evals/run-outcome.sh). Source it after lib.sh, evals-fixture.sh and
# evals-arms-fixture.sh; set JOBS_RUNNER (the runner under test) and JOBS_TASKS (outcome tasks dir, "" for run-evals) first.
# It is not a suite: run-all.sh only starts tests/test-*.sh.
# Never calls a real harness and never touches a real home: HOME and PB_VARIANT_HOME are temp dirs, the "claude" on PATH is a
# fake, and DIR/install.sh is a fake that logs every call to DIR/.calls.

VFK="$(mk_tmp)"   # the fake harness binary and the runner wrapper
# The fake claude: records the home as it is when a run starts (one "run ver=..." line per run, plus a "probe" line for the leak
# probe), solves the outcome task named by the label (JOBS_TASKS) when there is one, and sleeps when VFAKE_SLEEP is set.
cat > "$VFK/claude" <<'EOS'
#!/usr/bin/env bash
H="${VFAKE_H:-$HOME}"
probe=0
for a in "$@"; do case "$a" in *"$VFAKE_PBH"*) probe=1 ;; esac; done
ver="$(tr -d ' \r\n' < "$H/.agents/playbook/VERSION" 2>/dev/null)"; [ -n "$ver" ] || ver=none
if [ "$probe" = 1 ]; then
  printf 'probe ver=%s\n' "$ver" >> "$VFAKE_LOG"
  echo '{"type":"system","subtype":"init","session_id":"p1","skills":[],"slash_commands":[]}'
  echo '{"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.001,"result":"NO"}'
  exit 0
fi
l="$(basename "$PWD")"
printf 'run %s ver=%s\n' "$l" "$ver" >> "$VFAKE_LOG"
if [ -n "${VFAKE_SLEEP:-}" ]; then
  echo $$ > "$VFAKE_DIR/sleeper.pid"; echo $$ >> "$VFAKE_DIR/sleepers"; : > "$VFAKE_DIR/started"
  exec sleep 120
fi
if [ -n "${VFAKE_TASKS:-}" ] && [ -f "$VFAKE_TASKS/${l%%.*}/solution.patch" ]; then git apply "$VFAKE_TASKS/${l%%.*}/solution.patch" 2>/dev/null; fi
echo '{"type":"system","subtype":"init","session_id":"s1","skills":[],"slash_commands":[]}'
echo '{"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.01,"result":"Done."}'
exit 0
EOS
chmod 755 "$VFK/claude"
# the runner wrapper: environment from VW_* variables, then exec (so $! of a background start is the runner's pid)
cat > "$VFK/runner.sh" <<'EOS'
#!/usr/bin/env bash
unset PLAYBOOK_HOME PB_EVAL_ARM PB_EVAL_MODEL PB_EVAL_SETTINGS PLAYBOOK_REGISTRY
export HOME="$VW_HOME" PATH="$VW_FK:$PATH" PB_VARIANT_HOME="$VW_VHOME"
exec bash "$VW_RUNNER" --workroot "$VW_WR" --out "$VW_RES" "$@"
EOS
chmod 755 "$VFK/runner.sh"
export VW_FK="$VFK" VW_RUNNER="$JOBS_RUNNER" VFAKE_PBH="$PBH" VFAKE_TASKS="$JOBS_TASKS"

# mk_variant [VERSION] -> VD: a variant tree (default VERSION 1.2.3-variant) with a fake install.sh that logs "install ..." and
# "doctor ..." calls to $VD/.calls and installs VERSION, a script and the skill playbook-vskill into the home it is given
mk_variant() {
  VD="$(mk_tmp)"
  mkdir -p "$VD/skills/playbook-vskill" "$VD/scripts"
  printf '%s\n' "${1:-1.2.3-variant}" > "$VD/VERSION"
  printf 'variant skill\n' > "$VD/skills/playbook-vskill/SKILL.md"
  printf '#!/bin/sh\necho variant\n' > "$VD/scripts/vmark"
  cat > "$VD/install.sh" <<'EOS'
#!/usr/bin/env bash
D="$(cd "$(dirname "$0")" && pwd)"
ALL="$*"; cmd="$1"; shift
H=""
while [ $# -gt 0 ]; do case "$1" in --home) H="$2"; shift ;; esac; shift; done
printf '%s|\n' "$cmd $ALL" >> "$D/.calls"
case "$cmd" in
  install)
    rm -rf "$H/.agents/playbook"; mkdir -p "$H/.agents/playbook/scripts"
    printf '%s \n' "$(cat "$D/VERSION")" > "$H/.agents/playbook/VERSION"
    cp "$D/scripts/vmark" "$H/.agents/playbook/scripts/vmark"
    mkdir -p "$H/.claude/skills"
    rm -rf "$H/.claude/skills/playbook-vskill"; cp -R "$D/skills/playbook-vskill" "$H/.claude/skills/playbook-vskill"
    printf 'VARIANT-BLOCK\n' >> "$H/.claude/CLAUDE.md"
    exit 0 ;;
esac
exit 0
EOS
}
# mk_vhome -> VH: a harness home with a playbook install, a skill of the playbook, one of the user, a block file and a conf
mk_vhome() {
  local h; h="$(mk_tmp)"
  mkdir -p "$h/.agents/playbook/scripts" "$h/.claude/skills/playbook-base" "$h/.claude/skills/myskill"
  printf '0.0.1-base\n' > "$h/.agents/playbook/VERSION"
  printf '#!/bin/sh\necho base\n' > "$h/.agents/playbook/scripts/base.sh"; chmod 755 "$h/.agents/playbook/scripts/base.sh"
  printf 'base skill\n' > "$h/.claude/skills/playbook-base/SKILL.md"
  printf 'mine\n' > "$h/.claude/skills/myskill/SKILL.md"
  printf 'my notes\n<!-- BEGIN agent-playbook base -->\nbase block\n<!-- END agent-playbook -->\n' > "$h/.claude/CLAUDE.md"
  printf 'SECRET-TOKEN\n' > "$h/.claude/.credentials.json"
  printf 'test_cmd=make check\nmodel_tester_claude=opus-x1\n' > "$h/.agents/playbook.conf"
  printf '%s\n' "$h"
}
# tree_sig DIR -> every regular file (md5) and symlink (target) under DIR, sorted
tree_sig() {
  (cd "$1" && find . -mindepth 1 \( -type f -o -type l \) | LC_ALL=C sort | while IFS= read -r p; do
    if [ -L "$p" ]; then printf 'L %s -> %s\n' "$p" "$(readlink "$p")"
    else printf 'F %s %s\n' "$p" "$(md5sum < "$p")"; fi
  done)
}
# vsetup/vrun/vstart ARGS... -> the runner with HOME=PB_VARIANT_HOME=$VH; sets OUT ERR RC VWR VOD VRES VFD
vsetup() {
  VWR="$(mk_tmp)"; : > "$VWR/.pb-eval-workroot"; VOD="$(mk_tmp)"; VRES="$VOD/results.md"; VFD="$(mk_tmp)"
  export VW_HOME="$VH" VW_VHOME="$VH" VW_WR="$VWR" VW_RES="$VRES" VFAKE_LOG="$VOD/claude.log" VFAKE_DIR="$VFD" VFAKE_H="$VH"
  : > "$VFAKE_LOG"
}
vrun() { vsetup; bash "$VFK/runner.sh" "$@" > "$VOD/stdout" 2> "$VOD/stderr"; RC=$?; OUT="$(cat "$VOD/stdout")"; ERR="$(cat "$VOD/stderr")"; }
vstart() { vsetup; bash "$VFK/runner.sh" "$@" > "$VOD/stdout" 2> "$VOD/stderr" & VPID=$!; }
vwait_file() { local i=0; while [ ! -e "$1" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i + 1)); done; [ -e "$1" ]; }
vfinish() { RC=0; wait "$1" 2>/dev/null || RC=$?; OUT="$(cat "$VOD/stdout")"; ERR="$(cat "$VOD/stderr")"; }
vlog() { cat "$VFAKE_LOG" 2>/dev/null; }
# ncalls WORD -> how many install.sh calls of $VD were "WORD ..." (install or doctor)
ncalls() { if [ -f "$VD/.calls" ]; then grep -c "^$1 " "$VD/.calls" || true; else echo 0; fi; }
# nlines TEXT FILE-CONTENT -> number of lines containing TEXT
nlines() { printf '%s\n' "$2" | grep -cF -- "$1" || true; }

# jobs_variant_suite BASE... -> the J2 / D6 cases, for the runner in JOBS_RUNNER; BASE = the options that select the work
# (harness, scenarios or tasks); JOBS_OUTER_BASE = the same for the outer runner that sleeps in its one run (so ONE scenario or task). The refusal exit code of --variant-held is pinned here: 2 (a refusal before anything starts,
# like a live lock for --variant; no install, no restore, no run, the home and the lock untouched).
jobs_variant_suite() {
  local base="$*" ref refh sigA pidA held other dead callsA
  echo "J2 --variant with --jobs 2: one install, one doctor, the runs fan out, one restore"
  mk_variant; VH="$(mk_vhome)"; B_J2="$(tree_sig "$VH")"
  vrun --variant "$VD" $base --jobs 2
  case "$RC" in 0|1) t_ok "J2 the run ends normally (exit $RC)" ;; *) t_bad "J2 the run ends normally (exit 0 or 1)" "exit $RC; $ERR $OUT" ;; esac
  assert_eq "J2 the variant install ran exactly once" "1" "$(ncalls install)"
  assert_eq "J2 doctor ran exactly once" "1" "$(ncalls doctor)"
  assert_contains "J2 the one install is the normal variant install" "$(cat "$VD/.calls" 2>/dev/null)" "install install --home $VH --copy --harness claude --yes|"
  assert_eq "J2 the snapshot was restored exactly once (one 'restored the snapshot' line)" "1" "$(nlines "variant: restored the snapshot of $VH" "$ERR")"
  assert_eq "J2 the home is back exactly as before" "$B_J2" "$(tree_sig "$VH")"
  assert_no_path "J2 the lock is removed" "$VH/.agents/.pb-variant.lock"
  assert_eq "J2 no run saw anything but the variant installed" "0" "$(vlog | grep '^run ' | grep -vc 'ver=1.2.3-variant')"
  if [ "$(vlog | grep -c '^run ')" -ge 2 ]; then t_ok "J2 at least two runs saw the variant"; else t_bad "J2 at least two runs saw the variant" "$(vlog)"; fi
  assert_contains "J2 the JSON records the variant version" "$(jget "${VRES%.md}.json" 'JSON.stringify(j.variant)')" '"version":"1.2.3-variant"'

  echo "D6 --variant-held DIR refuses (exit 2, nothing touched, no install, no run): no lock, a dead pid"
  mk_variant; VH="$(mk_vhome)"; sigA="$(tree_sig "$VH")"
  vrun --variant-held "$VD" $base
  assert_rc "D6 no lock at all: refused with exit 2" 2
  assert_contains "D6 the refusal names --variant-held" "$ERR$OUT" "variant-held"
  assert_eq "D6 no lock: the home is untouched" "$sigA" "$(tree_sig "$VH")"
  assert_not_contains "D6 no lock: the refusal is not an unknown-option error" "$ERR$OUT" "unknown option"
  assert_eq "D6 no lock: install.sh was never called" "00" "$(ncalls install)$(ncalls doctor)"
  assert_eq "D6 no lock: no harness run" "0" "$(vlog | grep -c '^run ')"
  assert_no_path "D6 no lock: none was made" "$VH/.agents/.pb-variant.lock"
  mk_variant; VH="$(mk_vhome)"   # a lock whose pid is dead, with the variant's VERSION installed
  mkdir -p "$VH/.agents/.pb-variant.lock"; printf '1.2.3-variant\n' > "$VH/.agents/playbook/VERSION"
  ( : ) & dead=$!; wait "$dead"
  printf '%s\n' "$dead" > "$VH/.agents/.pb-variant.lock/pid"
  sigA="$(tree_sig "$VH")"
  vrun --variant-held "$VD" $base
  assert_rc "D6 a lock whose pid is not alive: refused with exit 2" 2
  assert_not_contains "D6 dead pid: the refusal is not an unknown-option error" "$ERR$OUT" "unknown option"
  assert_eq "D6 dead pid: the home and the lock are untouched (no restore, no take-over)" "$sigA" "$(tree_sig "$VH")"
  assert_eq "D6 dead pid: install.sh was never called" "00" "$(ncalls install)$(ncalls doctor)"
  assert_eq "D6 dead pid: no harness run" "0" "$(vlog | grep -c '^run ')"

  echo "D6 --variant-held DIR with a live lock: never installs, never restores, records the same variant object"
  mk_variant; held="$VD"; VH="$(mk_vhome)"; unset VFAKE_SLEEP
  vrun --variant "$held" $base
  ref="$(jget "${VRES%.md}.json" 'JSON.stringify(j.variant)')"   # the variant object of a normal run (the lock is gone again)
  rm -f "$held/.calls"
  VFAKE_SLEEP=1 vstart --variant "$held" $JOBS_OUTER_BASE   # the outer process: holds the lock and the install while its run sleeps
  pidA="$VPID"; A_OD="$VOD"; A_FD="$VFD"
  if vwait_file "$A_FD/started"; then
    unset VFAKE_SLEEP
    sigA="$(tree_sig "$VH")"; callsA="$(cat "$held/.calls" 2>/dev/null)"
    mk_variant 2.0.0-other; other="$VD"
    vrun --variant-held "$other" $base
    assert_rc "D6 the installed VERSION is not DIR's: refused with exit 2" 2
    assert_not_contains "D6 other VERSION: the refusal is not an unknown-option error" "$ERR$OUT" "unknown option"
    assert_eq "D6 other VERSION: nothing touched (lock, install and snapshot stay)" "$sigA" "$(tree_sig "$VH")"
    assert_eq "D6 other VERSION: the other tree's install.sh was never called" "" "$(cat "$other/.calls" 2>/dev/null)"
    assert_eq "D6 other VERSION: no harness run" "0" "$(vlog | grep -c '^run ')"
    VD="$held"
    vrun --variant-held "$held" $base --jobs 2
    case "$RC" in 0|1) t_ok "D6 held lock, same VERSION: the runs happen (exit $RC)" ;; *) t_bad "D6 held lock, same VERSION: the runs happen (exit 0 or 1)" "exit $RC; $ERR $OUT" ;; esac
    refh="$(jget "${VRES%.md}.json" 'JSON.stringify(j.variant)')"
    assert_eq "D6 the held run records the same variant object as a normal --variant run" "$ref" "$refh"
    assert_eq "D6 the held run never installed and never ran doctor (the outer runner's calls only)" "$callsA" "$(cat "$held/.calls" 2>/dev/null)"
    assert_not_contains "D6 the held run is not an unknown-option error" "$ERR$OUT" "unknown option"
    assert_eq "D6 the held run never restored (no restore line)" "0" "$(nlines "restored the snapshot" "$ERR")"
    assert_eq "D6 the held run left the home, the lock and the snapshot as they were" "$sigA" "$(tree_sig "$VH")"
    assert_dir "D6 the lock is still there" "$VH/.agents/.pb-variant.lock"
    assert_eq "D6 the lock still names the outer runner" "$pidA" "$(tr -d ' \r\n' < "$VH/.agents/.pb-variant.lock/pid" 2>/dev/null)"
    assert_eq "D6 every run of the held run saw the variant installed" "0" "$(vlog | grep '^run ' | grep -vc 'ver=1.2.3-variant')"
    if [ "$(vlog | grep -c '^run ')" -ge 1 ]; then t_ok "D6 the held run ran the harness"; else t_bad "D6 the held run ran the harness" "$(vlog)"; fi
  else
    t_bad "D6 the outer runner reached its adapter" "no 'started' file; stderr: $(cat "$A_OD/stderr" 2>/dev/null)"
  fi
  kill "$(cat "$A_FD/sleeper.pid" 2>/dev/null)" 2>/dev/null
  VOD="$A_OD"; vfinish "$pidA"
  unset VFAKE_SLEEP
}

# jobs_signal_suite BASE... -> C3 (review 05, minor): TERM and HUP to a --variant --jobs 2 runner whose runs sleep (the fake claude of this file):
# exactly one restore line, the home as before, the lock gone, no sleeper left. BASE selects two runs.
jobs_signal_suite() {
  local base="$*" sig pid i n alive p sigB
  for sig in TERM HUP; do
    echo "C3 --variant --jobs 2: $sig after the runs started: one restore, home restored, lock gone, no stub left"
    mk_variant; VH="$(mk_vhome)"; sigB="$(tree_sig "$VH")"
    VFAKE_SLEEP=1 vstart --variant "$VD" $base --jobs 2
    pid="$VPID"; i=0
    while [ "$(wc -l < "$VFD/sleepers" 2>/dev/null || echo 0)" -lt 2 ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
    unset VFAKE_SLEEP
    n="$(wc -l < "$VFD/sleepers" 2>/dev/null || echo 0)"
    if [ "$n" -ge 2 ] && kill -"$sig" "$pid" 2>/dev/null; then
      t_ok "C3 $sig: two runs were running (sleepers: $n) and the signal was delivered"
      i=0; while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 150 ]; do sleep 0.1; i=$((i + 1)); done
      vfinish "$pid"
      assert_eq "C3 $sig: exactly one 'restored the snapshot' line" "1" "$(nlines "variant: restored the snapshot of $VH" "$ERR")"
      assert_eq "C3 $sig: the home is back exactly as before" "$sigB" "$(tree_sig "$VH")"
      assert_no_path "C3 $sig: the lock is gone" "$VH/.agents/.pb-variant.lock"
      i=0; alive=""
      while [ "$i" -lt 50 ]; do
        alive=""; for p in $(cat "$VFD/sleepers"); do kill -0 "$p" 2>/dev/null && alive="$alive $p"; done
        [ -z "$alive" ] && break; sleep 0.1; i=$((i + 1))
      done
      assert_eq "C3 $sig: no stub process is left" "" "$alive"
      for p in $alive; do kill "$p" 2>/dev/null; done
    else
      kill "$pid" 2>/dev/null; vfinish "$pid"
      t_skip 5 "C3 $sig: the runs did not both start or the signal could not be delivered"
    fi
  done
  unset VFAKE_SLEEP
}
