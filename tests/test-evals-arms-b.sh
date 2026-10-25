#!/usr/bin/env bash
# Tests for the without arm of evals/run-evals.sh (v0.26.0 lane E, spec .agents/handoff/01-spec.md slices S3a and S3b): the empty
# PLAYBOOK_HOME, the untouched HOME, the --settings file given to the claude preset (content, location, removal, evidence copy),
# PB_EVAL_* for --cmd adapters only, the dropped-lines NOTE, and the refusals (codex, opencode, --real-home, a playbook block in
# an ancestor instruction file or a user rules file). Never calls a real harness: a fake claude/codex/opencode first on PATH
# records its argv, environment and the settings file, and prints a canned stream-json transcript (evals-arms-fixture.sh).
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-arms-fixture.sh"

no_label_dirs() { local l="" p; for p in "$WR"/E[0-9]*; do if [ -e "$p" ]; then l="$l${p##*/} "; fi; done; assert_eq "$1" "" "$l"; }
under() { case "$1" in "$2"/*) return 0 ;; esac; return 1; }   # PATH DIR -> 0 when PATH is inside DIR
NOTE34='NOTE the without arm also drops 2 non-playbook lines of ~/.claude/CLAUDE.md'

# ================= S3a the claude preset =================
echo "S3a AC3.1-AC3.4 --harness claude --arm both: settings files, empty PLAYBOOK_HOME, untouched HOME, no PB_EVAL_* in the preset"
GH="$(mk_home)"; GH_BEFORE="$(home_listing "$GH")"
WR="$(mk_tmp)"; : > "$WR/.pb-eval-workroot"; OD="$(mk_tmp)"; RES="$OD/results.md"; rm -f "$REC"/* "$FR"/*
# the caller's environment carries PB_EVAL_* values: the preset must still see none
run env -u PLAYBOOK_HOME PB_EVAL_ARM=leaked PB_EVAL_SETTINGS=/leaked PB_EVAL_MODEL=leaked HOME="$GH" PATH="$FK:$PATH" \
  bash "$RUNNER" --harness claude --model m-claude-1 --arm both --scenarios E8 --workroot "$WR" --out "$RES"
assert_rc "AC3.2 --harness claude --model M --arm both -> exit 0" 0
WRP="$(physdir "$WR")"
for arm in with without; do
  L="E8.$arm.1"
  assert_file "AC3.2 $L: the claude preset ran" "$FR/claude.$L.args"
  if argpair "$FR/claude.$L.args" --model m-claude-1; then t_ok "AC1.4 $L: claude gets --model M"; else t_bad "AC1.4 $L: claude gets --model M" "$(tr '\n' ' ' < "$FR/claude.$L.args" 2>/dev/null)"; fi
  SP="$(cat "$FR/claude.$L.setpath" 2>/dev/null)"
  if [ -n "$SP" ]; then t_ok "AC3.2 $L: claude gets --settings <file>"; else t_bad "AC3.2 $L: claude gets --settings <file>" "argv: $(tr '\n' ' ' < "$FR/claude.$L.args" 2>/dev/null)"; fi
  PH="$(cat "$FR/claude.$L.ph" 2>/dev/null)"
  if [ -n "$SP" ] && ! under "$SP" "$WRP" && ! under "$SP" "$WR" && ! under "$SP" "$PH"; then t_ok "AC3.2 $L: the settings file is outside the workroot and outside PLAYBOOK_HOME"
  else t_bad "AC3.2 $L: the settings file is outside the workroot and outside PLAYBOOK_HOME" "settings [$SP] workroot [$WRP] PLAYBOOK_HOME [$PH]"; fi
  case "$(basename "$(dirname "$SP")")" in pb-evset.*) t_ok "AC3.2 $L: the settings file sits in a runner temp dir pb-evset.*" ;; *) t_bad "AC3.2 $L: the settings file sits in a runner temp dir pb-evset.*" "[$SP]" ;; esac
  if [ -n "$SP" ]; then assert_no_path "AC3.2 $L: the settings file is removed after the run" "$SP"; else t_bad "AC3.2 $L: the settings file is removed after the run" "no settings path recorded"; fi
  assert_eq "AC3.2 $L: the settings file sets autoMemoryEnabled false (both arms, D11)" "false" "$(jget "$FR/claude.$L.settings" 'j.autoMemoryEnabled')"
  assert_file "AC3.2 $L: an evidence copy $arm-settings.json is kept" "$OD/results.$L.evidence/$arm-settings.json"
  if [ -f "$FR/claude.$L.settings" ] && cmp -s "$FR/claude.$L.settings" "$OD/results.$L.evidence/$arm-settings.json"; then t_ok "AC3.2 $L: the evidence copy equals the file claude got"
  else t_bad "AC3.2 $L: the evidence copy equals the file claude got" "differs or missing"; fi
  assert_file "AC3.3 $L: the env record exists" "$FR/claude.$L.env"
  assert_eq "AC3.3 $L: the claude process has no PB_EVAL_* variable (not even the caller's)" "" "$(rec_of "$FR/claude.$L.env")"
  assert_eq "AC3.1 $L: HOME is the real one" "$GH" "$(cat "$FR/claude.$L.hm" 2>/dev/null)"
done
SW="$FR/claude.E8.without.1.settings"
assert_eq "AC3.2 with: the settings file holds only autoMemoryEnabled" "autoMemoryEnabled" "$(jget "$FR/claude.E8.with.1.settings" 'Object.keys(j).join(",")')"
assert_eq "AC3.2 without: claudeMdExcludes holds HOME/.claude/CLAUDE.md" "true" "$(jget "$SW" '(j.claudeMdExcludes||[]).includes("'"$GH"'/.claude/CLAUDE.md")')"
for s in playbook-tdd playbook-proof playbook-feedback playbook-learn playbook-setup playbook-extra; do
  assert_eq "AC3.2 without: skillOverrides turns off $s" "off" "$(jget "$SW" '(j.skillOverrides||{})["'"$s"'"]')"
done
assert_eq "AC3.2 without: other-skill is not overridden" "absent" "$(jget "$SW" '(j.skillOverrides||{})["other-skill"] === undefined ? "absent" : "present"')"
for p in 'Skill(playbook-proof)' 'Skill(playbook-proof *)' 'Skill(playbook-extra *)' 'Read(~/.agents/**)' 'Read(~/.claude/skills/playbook-*/**)'; do
  assert_eq "AC3.2 without: permissions.deny holds $p" "true" "$(jget "$SW" '((j.permissions||{}).deny||[]).includes("'"$p"'")')"
done
assert_eq "fix7 without: permissions.deny has no Skill(skill:NAME) rule (not a documented form)" "false" "$(jget "$SW" '((j.permissions||{}).deny||[]).some(x => /^Skill\(skill:/.test(x))')"
assert_eq "AC3.1 without: PLAYBOOK_HOME holds no file (no conf copy, no settings file)" "" "$(rec_of "$FR/claude.E8.without.1.phfiles")"
assert_contains "AC3.1 with: PLAYBOOK_HOME keeps today's conf copy" "$(cat "$FR/claude.E8.with.1.phfiles" 2>/dev/null)" ".agents/playbook.conf"
assert_eq "AC3.1 HOME is unchanged (listing before = after)" "$GH_BEFORE" "$(home_listing "$GH")"
assert_eq "AC3.1 no credential content under the workroot or the results dir" "" "$(grep -rl SECRET-TOKEN-XYZ "$WR" "$OD" 2>/dev/null | tr '\n' ' ')"
assert_eq "AC3.1 no credential content in the settings files" "" "$(grep -l SECRET-TOKEN-XYZ "$FR"/*.settings 2>/dev/null | tr '\n' ' ')"
echo "S3a AC3.4 the without run notes the dropped non-playbook lines of ~/.claude/CLAUDE.md"
assert_eq "AC3.4 output line '<label> $NOTE34'" "1" "$(printf '%s\n' "$OUT" | grep -cxF "E8.without.1 $NOTE34")"
assert_eq "AC3.4 the with run gets no such NOTE" "0" "$(printf '%s\n' "$OUT" | grep -c '^E8\.with\.1 NOTE the without arm')"
assert_contains "AC3.4 the md carries the NOTE" "$(cat "$RES" 2>/dev/null)" "the without arm also drops 2 non-playbook lines of ~/.claude/CLAUDE.md"
assert_eq "AC3.4 the NOTE is never a FAIL" "0" "$(printf '%s\n' "$OUT" | grep -c ' FAIL ')"
assert_contains "AC3.3 the md records isolation: claude-settings" "$(cat "$RES" 2>/dev/null)" "isolation: claude-settings"

echo "S3a AC3.2 default mode (no --arm, no --repeat): the claude argv gets no --settings"
GH="$(mk_home)"
go --harness claude --model m-claude-1 --scenarios E8
assert_file "AC3.2 default mode: the claude preset ran" "$FR/claude.E8.args"
if has_line "$FR/claude.E8.args" --settings; then t_bad "AC3.2 default mode: no --settings (D11)" "$(tr '\n' ' ' < "$FR/claude.E8.args")"; else t_ok "AC3.2 default mode: no --settings (D11)"; fi

echo "S3a AC3.2 --repeat alone: the with run passes --settings with only autoMemoryEnabled"
go --harness claude --model m-claude-1 --repeat 1 --scenarios E8
SPF="$(ls "$FR"/claude.*.settings 2>/dev/null | head -n 1)"
assert_eq "AC3.2 --repeat 1: the with settings file holds only autoMemoryEnabled false" "autoMemoryEnabled=false" "$(jget "${SPF:-/nonexistent}" 'Object.keys(j).join(",") + "=" + j.autoMemoryEnabled')"

echo "S3a AC3.4 a CLAUDE.md that holds only the block: no NOTE, never a refusal"
GH="$(mk_home blockonly)"
go --harness claude --model m-claude-1 --arm without --scenarios E8
assert_rc "AC3.4 block-only CLAUDE.md, --arm without -> exit 0" 0
assert_file "AC3.4 block-only: the without run ran" "$FR/claude.E8.without.1.args"
assert_eq "AC3.4 block-only: no dropped-lines NOTE" "0" "$(printf '%s\n' "$OUT" | grep -c 'NOTE the without arm also drops')"
assert_eq "AC2.2 --arm without alone: only the without run" "" "$(ls "$FR"/claude.E8.with.1.args 2>/dev/null)"

# ================= S3a the --cmd adapter =================
echo "S3a AC3.1/AC3.3 --cmd with --arm both: PB_EVAL_ARM and PB_EVAL_SETTINGS, empty PLAYBOOK_HOME in the without arm"
mk_adapter armrec 'printf "%s\n" "${PB_EVAL_ARM-UNSET}" > "$REC/$e.arm"
printf "%s\n" "${PB_EVAL_SETTINGS-UNSET}" > "$REC/$e.setpath"
cp "${PB_EVAL_SETTINGS:-/nonexistent}" "$REC/$e.settings" 2>/dev/null
printf "%s\n" "$HOME" > "$REC/$e.hm"
printf "%s\n" "${PLAYBOOK_HOME-UNSET}" > "$REC/$e.ph"
if [ -d "${PLAYBOOK_HOME:-/nonexistent}" ]; then (cd "$PLAYBOOK_HOME" && find . -type f) > "$REC/$e.phfiles"; fi
cat "${PLAYBOOK_HOME:-/nonexistent}/.agents/playbook.conf" > "$REC/$e.conf" 2>/dev/null
true'
GH="$(mk_home)"; GH_BEFORE="$(home_listing "$GH")"
go --cmd "bash $A/armrec.sh" --arm both --scenarios E8
assert_rc "AC3.3 --cmd --arm both -> exit 0" 0
assert_eq "AC3.3 E8.with.1: PB_EVAL_ARM=with" "with" "$(cat "$REC/E8.with.1.arm" 2>/dev/null)"
assert_eq "AC3.3 E8.without.1: PB_EVAL_ARM=without" "without" "$(cat "$REC/E8.without.1.arm" 2>/dev/null)"
for arm in with without; do
  L="E8.$arm.1"; SP="$(cat "$REC/$L.setpath" 2>/dev/null)"
  assert_file "AC3.3 $L: PB_EVAL_SETTINGS names a file that exists while the adapter runs" "$REC/$L.settings"
  case "$SP" in "" | UNSET) t_bad "AC3.3 $L: the settings file is removed after the run" "no path [$SP]" ;; *) assert_no_path "AC3.3 $L: the settings file is removed after the run" "$SP" ;; esac
  assert_eq "AC3.3 $L: the settings file sets autoMemoryEnabled false" "false" "$(jget "$REC/$L.settings" 'j.autoMemoryEnabled')"
  assert_eq "AC3.1 $L: HOME is the real one" "$GH" "$(cat "$REC/$L.hm" 2>/dev/null)"
done
assert_eq "AC3.3 without: the adapter's settings file excludes HOME/.claude/CLAUDE.md" "true" "$(jget "$REC/E8.without.1.settings" '(j.claudeMdExcludes||[]).includes("'"$GH"'/.claude/CLAUDE.md")')"
assert_eq "AC3.3 with: the adapter's settings file holds only autoMemoryEnabled" "autoMemoryEnabled" "$(jget "$REC/E8.with.1.settings" 'Object.keys(j).join(",")')"
PHW="$(cat "$REC/E8.without.1.ph" 2>/dev/null)"
case "$PHW" in "" | UNSET | "$GH") t_bad "AC3.1 without: PLAYBOOK_HOME is a temp dir, not the real home" "[$PHW]" ;; *) t_ok "AC3.1 without: PLAYBOOK_HOME is a temp dir, not the real home" ;; esac
assert_file "AC3.1 without: the PLAYBOOK_HOME listing was recorded" "$REC/E8.without.1.phfiles"
assert_eq "AC3.1 without: PLAYBOOK_HOME holds no file" "" "$(rec_of "$REC/E8.without.1.phfiles")"
assert_contains "AC3.1 with: PLAYBOOK_HOME keeps the conf copy (test_cmd)" "$(cat "$REC/E8.with.1.conf" 2>/dev/null)" "test_cmd=make check"
assert_not_contains "AC3.1 with: the conf copy still drops feedback_repo" "$(cat "$REC/E8.with.1.conf" 2>/dev/null)" "feedback_repo"
assert_eq "AC3.1 HOME is unchanged (listing before = after)" "$GH_BEFORE" "$(home_listing "$GH")"
assert_eq "AC3.1 no credential content under the workroot or the results dir" "" "$(grep -rl SECRET-TOKEN-XYZ "$WR" "$OD" 2>/dev/null | tr '\n' ' ')"
assert_contains "AC3.3 the md records isolation: adapter" "$(cat "$RES" 2>/dev/null)" "isolation: adapter"

echo "S3a AC3.2 the settings file is removed when the runner gets SIGTERM"
OD="$(mk_tmp)"; WR="$(mk_tmp)"; rm -f "$REC/term.sp" "$REC/term.mark" "$REC/term.mark.tmp"
mk_adapter term 'printf "%s\n" "${PB_EVAL_SETTINGS-UNSET}" > "'"$REC"'/term.sp"; printf "%s\n" "$$" > "'"$REC"'/term.mark.tmp"; mv "'"$REC"'/term.mark.tmp" "'"$REC"'/term.mark"; exec sleep 30'
env -u PLAYBOOK_HOME HOME="$GH" bash "$RUNNER" --cmd "bash $A/term.sh" --arm without --scenarios E8 --workroot "$WR" --out "$OD/results.md" >/dev/null 2>&1 &
RP=$!
for _ in $(seq 1 100); do [ -f "$REC/term.mark" ] && break; alive "$RP" || break; sleep 0.1; done
if [ -f "$REC/term.mark" ]; then
  t_ok "AC3.2 SIGTERM: the adapter started"
  kill -TERM "$RP" 2>/dev/null
  for _ in $(seq 1 50); do alive "$RP" || break; sleep 0.1; done
  kill "$(sed -n 1p "$REC/term.mark")" 2>/dev/null
  for _ in $(seq 1 30); do alive "$RP" || break; sleep 0.1; done
  kill -KILL "$RP" 2>/dev/null; wait "$RP" 2>/dev/null
  SP="$(cat "$REC/term.sp" 2>/dev/null)"
  case "$SP" in "" | UNSET) t_bad "AC3.2 SIGTERM: the settings file is gone" "no settings path [$SP]" ;; *) assert_no_path "AC3.2 SIGTERM: the settings file is gone" "$SP" ;; esac
else
  t_bad "AC3.2 SIGTERM: the adapter started" "no marker (the runner exited early or the adapter did not start)"
  t_bad "AC3.2 SIGTERM: the settings file is gone" "not reached"
  kill -KILL "$RP" 2>/dev/null; wait "$RP" 2>/dev/null
fi

# ================= fix3 the leak probe (--harness claude, without arm) =================
# The fake claude is the probe when its argv names the heading of AGENTS.global.md; it answers $FK/probe.answer (evals-arms-fixture.sh).
echo "fix3 --harness claude --arm both: one leak probe with the without settings before the first without run; no leak -> 'leak probe: none'"
PBH_T="$(sed -n 's/^## //p' "$PB_ROOT/AGENTS.global.md" | head -n 1)"
assert_eq "fix3 setup: the heading read from AGENTS.global.md" "Agent Playbook (always on)" "$PBH_T"
probes() { cat "$FR/claude.probe.count" 2>/dev/null || echo 0; }
GH="$(mk_home)"; printf 'NO\n' > "$FK/probe.answer"
go --harness claude --model m-claude-1 --arm both --repeat 2 --scenarios E8
assert_rc "fix3 the probe says no: exit 0" 0
assert_eq "fix3 the probe says no: exactly one probe for the whole invocation (both arms, repeat 2)" "1" "$(probes)"
ORD="$(tr '\n' ' ' < "$FR/claude.order" 2>/dev/null)"
case " $ORD" in *" probe "*"E8.without.1 "*) t_ok "fix3 the probe runs before the first without run" ;; *) t_bad "fix3 the probe runs before the first without run" "order: [$ORD]" ;; esac
assert_eq "fix3 the probe says no: every scenario run still ran (4)" "4" "$(grep -c '^E8\.' "$FR/claude.order" 2>/dev/null)"
assert_file "fix3 the probe got a --settings file" "$FR/claude.probe.1.settings"
if [ -f "$FR/claude.probe.1.settings" ] && cmp -s "$FR/claude.probe.1.settings" "$FR/claude.E8.without.1.settings"; then t_ok "fix3 the probe ran with the without settings (byte-equal to E8.without.1's file)"
else t_bad "fix3 the probe ran with the without settings (byte-equal to E8.without.1's file)" "$(cat "$FR/claude.probe.1.settings" 2>/dev/null | tr '\n' ' ')"; fi
assert_contains "fix3 the probe says no: the md records 'leak probe: none'" "$(cat "$RES" 2>/dev/null)" "leak probe: none"

echo "fix3 the probe says yes: exit 3, a message naming the leak, no scenario runs"
printf 'YES\n' > "$FK/probe.answer"
go --harness claude --model m-claude-1 --arm both --scenarios E8
assert_rc "fix3 the probe says yes: exit 3" 3
assert_eq "fix3 the probe says yes: one probe" "1" "$(probes)"
assert_contains "fix3 the probe says yes: the message names the heading that leaked" "$OUT" "$PBH_T"
if printf '%s\n' "$OUT" | grep -qi 'leak'; then t_ok "fix3 the probe says yes: the message says leak"; else t_bad "fix3 the probe says yes: the message says leak" "$OUT"; fi
assert_eq "fix3 the probe says yes: no scenario run reached claude" "" "$(ls "$FR" 2>/dev/null | grep '^claude\.E8' | tr '\n' ' ')"
assert_no_path "fix3 the probe says yes: no workdir E8.with.1" "$WR/E8.with.1"
assert_no_path "fix3 the probe says yes: no workdir E8.without.1" "$WR/E8.without.1"
rm -f "$FK/probe.answer"

echo "fix3 no probe for --cmd adapters ('leak probe: n/a'), for --arm with, or in the default mode"
go --cmd "bash $A/idle.sh" --arm both --scenarios E8
assert_rc "fix3 --cmd --arm both: exit 0" 0
assert_eq "fix3 --cmd: the adapter ran once per run and never for a probe" "E8.with.1 E8.without.1" "$(cd "$REC" && ls *.args 2>/dev/null | sed 's/\.args$//' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
assert_contains "fix3 --cmd: the md records 'leak probe: n/a'" "$(cat "$RES" 2>/dev/null)" "leak probe: n/a"
go --harness claude --model m-claude-1 --arm with --scenarios E8
assert_eq "fix3 --harness claude --arm with: no probe" "0" "$(probes)"
assert_file "fix3 --harness claude --arm with: the with run ran (label E8, as today)" "$FR/claude.E8.args"
go --harness claude --model m-claude-1 --scenarios E8
assert_eq "fix3 default mode: no probe" "0" "$(probes)"
assert_file "fix3 default mode: the run ran" "$FR/claude.E8.args"

# ================= S3b refusals =================
echo "S3b AC3.5 codex and opencode refuse the without arm before any workdir; --arm with still works"
GH="$(mk_home)"
for h in codex opencode; do
  for arm in without both; do
    go --harness "$h" --model m1 --arm "$arm" --scenarios E8
    assert_rc "AC3.5 --harness $h --arm $arm -> exit 2" 2
    assert_contains "AC3.5 --harness $h --arm $arm: the message names the harness" "$OUT" "the without arm is not supported for $h: "
    assert_contains "AC3.5 --harness $h --arm $arm: the message offers the way out" "$OUT" "; use --arm with, or --cmd with your own isolation"
    assert_eq "AC3.5 --harness $h --arm $arm: the harness never ran" "" "$(ls "$FR" 2>/dev/null | tr '\n' ' ')"
    no_label_dirs "AC3.5 --harness $h --arm $arm: no workdir is made"
  done
done
go --harness codex --model m1 --arm with --scenarios E8
assert_rc "AC3.5 --harness codex --model M --arm with -> exit 0" 0
assert_file "AC3.5 --harness codex --arm with: codex ran" "$FR/codex.E8.args"
go --cmd "bash $A/idle.sh" --real-home --arm without --scenarios E8
assert_rc "AC3.5 --real-home --arm without -> exit 2" 2
assert_contains "AC3.5 --real-home --arm without: the message" "$OUT" "--real-home keeps the playbook home; it cannot run the without arm"
no_label_dirs "AC3.5 --real-home --arm without: no workdir is made"
go --cmd "bash $A/idle.sh" --arm both --real-home --scenarios E8
assert_rc "AC3.5 --arm both --real-home -> exit 2" 2
assert_contains "AC3.5 --arm both --real-home: the message" "$OUT" "--real-home keeps the playbook home; it cannot run the without arm"

echo "S3b AC3.6 a playbook block in an instruction file of the workroot's ancestors refuses the without arm"
MARK="$PB_BLOCK_BEGIN"
anc() { # REL-FILE [CONTENT-LINE] -> run --cmd --arm without with a workroot two levels under a dir P that holds REL-FILE
  P="$(mk_tmp)"; mkdir -p "$(dirname "$P/$1")"; printf '%s\n' '# project notes' "${2:-$MARK}" 'rule' > "$P/$1"
  WR="$P/a/wr"; OD="$(mk_tmp)"; RES="$OD/results.md"; rm -f "$REC"/*
  run env -u PLAYBOOK_HOME HOME="$GH" PATH="$FK:$PATH" bash "$RUNNER" --cmd "bash $A/idle.sh" --arm "${ARM:-without}" --scenarios E8 --workroot "$WR" --out "$RES"
}
for f in CLAUDE.md CLAUDE.local.md AGENTS.md .claude/CLAUDE.md .claude/AGENTS.md .claude/rules/sub/style.md; do
  anc "$f"
  assert_rc "AC3.6 marker in an ancestor's $f -> exit 2" 2
  assert_contains "AC3.6 marker in an ancestor's $f: the message names the file" "$OUT" "${P##*/}/$f"
  assert_contains "AC3.6 marker in an ancestor's $f: the message says to move the workroot" "$OUT" "move the workroot"
  assert_no_path "AC3.6 marker in an ancestor's $f: no without run" "$WR/E8.without.1"
  assert_no_path "AC3.6 marker in an ancestor's $f: no results file" "$RES"
done
anc a/AGENTS.md
assert_rc "AC3.6 marker in the workroot's parent (a/AGENTS.md) -> exit 2" 2
assert_contains "AC3.6 marker in the workroot's parent: the message names it" "$OUT" "${P##*/}/a/AGENTS.md"
anc CLAUDE.md '# a project file without the playbook block'
assert_rc "AC3.6 an ancestor CLAUDE.md without the marker does not refuse (exit 0)" 0
assert_dir "AC3.6 no marker: the without run ran" "$WR/E8.without.1"
ARM=with anc CLAUDE.md
assert_rc "AC3.6 --arm with: an ancestor block does not refuse (exit 0)" 0

echo "S3b AC3.6 a playbook block in a user rules file (~/.claude/rules/**/*.md) refuses the without arm"
GH="$(mk_home)"; mkdir -p "$GH/.claude/rules/team"; printf '%s\n' "$MARK" 'rule' '<!-- END agent-playbook -->' > "$GH/.claude/rules/team/pb.md"
GH_BEFORE="$(home_listing "$GH")"
go --cmd "bash $A/idle.sh" --arm without --scenarios E8
assert_rc "AC3.6 marker in ~/.claude/rules/team/pb.md -> exit 2" 2
assert_contains "AC3.6 the message names the rules file" "$OUT" "/.claude/rules/team/pb.md"
assert_contains "AC3.6 the message says to remove the block from the rules file" "$OUT" "remove the block from the rules file"
assert_no_path "AC3.6 rules file: no without run" "$WR/E8.without.1"
assert_eq "AC3.6 rules file: HOME is unchanged" "$GH_BEFORE" "$(home_listing "$GH")"

t_summary
