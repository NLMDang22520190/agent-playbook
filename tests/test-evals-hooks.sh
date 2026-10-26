#!/usr/bin/env bash
# Tests for evals/run-evals.sh --hooks and the hook environment (v0.28.0 lane k1c, spec .agents/handoff/01-spec.md AC-C1 and AC-C2; decisions
# D7 (confirmed), D30): option checks, the hooks block of the with arm's settings file (pbh_hook_settings), PB_EVAL_HOOKS, PB_EVAL_HOOK_LOG and
# PB_HEADLESS for every run, the md and JSON fields. Never calls a real harness and never runs a guard script: --cmd fake adapters
# (evals-fixture.sh) and fake claude/codex/opencode binaries first on PATH (evals-arms-fixture.sh); HOME is a stand-in.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/evals-fixture.sh"
. "$(dirname "$0")/evals-arms-fixture.sh"

# R: the runner repo in the form the handler commands use (cygpath -m when cygpath exists, D30)
R="$(cd "$PB_ROOT" && pwd -P)"
if command -v cygpath >/dev/null 2>&1; then R="$(cygpath -m "$R")"; fi
H_GUARD="bash \"$R/scripts/guard-irreversible.sh\" --eval # agent-playbook:guard"
H_START="bash \"$R/scripts/guard-irreversible.sh\" --eval --session-start # agent-playbook:guard-start"
H_LEARN="bash \"$R/scripts/learnings-hook.sh\" --eval # agent-playbook:learnings"
H_STOP="bash \"$R/scripts/guard-irreversible.sh\" --eval --stop # agent-playbook:guard-stop"
# hk FILE EVENT -> "matcher|command|timeout" per handler of EVENT, one per line (matcher "-" when absent), sorted
hk() { jget "$1" '((j.hooks||{})["'"$2"'"]||[]).flatMap(g=>(g.hooks||[]).map(h=>(g.matcher===undefined?"-":g.matcher)+"|"+h.type+"|"+h.command+"|"+h.timeout)).sort().join("\n")'; }
no_e8() { assert_no_path "$1: no workdir is made" "$WR/E8"; assert_no_path "$1: no labelled workdir is made" "$WR/E8.with.1"; }

# ================= AC-C1 option checks =================
echo "AC-C1 --hooks needs --arm or --repeat"
go --cmd "bash $A/idle.sh" --scenarios E8 --hooks
assert_rc "AC-C1 --hooks without --arm/--repeat -> exit 2" 2
assert_not_contains "AC-C1 --hooks is a known option" "$OUT" "unknown option"
assert_contains "AC-C1 the message names --hooks" "$OUT" "--hooks"
no_e8 "AC-C1 --hooks without --arm/--repeat"

echo "AC-C1 --hooks needs --harness claude or --cmd (codex, opencode refused before any run)"
for h in codex opencode; do
  go --harness "$h" --model m-x-1 --arm with --hooks --scenarios E8
  assert_rc "AC-C1 --harness $h --hooks -> exit 2" 2
  assert_contains "AC-C1 --harness $h --hooks: the message names --hooks" "$OUT" "--hooks"
  assert_not_contains "AC-C1 --harness $h --hooks: refused as unsupported, not as an unknown option" "$OUT" "unknown option"
  assert_no_path "AC-C1 --harness $h --hooks: the fake $h never ran" "$FR/$h.E8.args"
  no_e8 "AC-C1 --harness $h --hooks"
done

echo "AC-C1 --hooks --repeat 1 with --cmd runs"
go --cmd "bash $A/idle.sh" --scenarios E8 --hooks --repeat 1
assert_rc "AC-C1 --cmd --hooks --repeat 1 -> exit 0" 0
assert_eq "AC-C1 --cmd --hooks --repeat 1: E8 was graded" "PASS" "$(e_state E8 'tests/calc.test.js still exists')"

# ================= AC-C1 settings files =================
echo "AC-C1 --harness claude --arm both --hooks: the with settings file gets the four handlers, the without file none"
go --harness claude --model m-claude-1 --arm both --hooks --scenarios E8
assert_rc "AC-C1 --harness claude --arm both --hooks -> exit 0" 0
SWI="$FR/claude.E8.with.1.settings"; SWO="$FR/claude.E8.without.1.settings"
assert_file "AC-C1 the with run got a settings file" "$SWI"
assert_eq "AC-C1 with: the settings file holds autoMemoryEnabled and hooks only" "autoMemoryEnabled,hooks" "$(jget "$SWI" 'Object.keys(j).sort().join(",")')"
assert_eq "AC-C1 with: autoMemoryEnabled stays false" "false" "$(jget "$SWI" 'j.autoMemoryEnabled')"
assert_eq "AC-C1 with: hooks has the events PreToolUse, SessionStart, Stop" "PreToolUse,SessionStart,Stop" "$(jget "$SWI" 'Object.keys(j.hooks||{}).sort().join(",")')"
assert_eq "AC-C1 with: PreToolUse = the guard, matcher Bash|Write|Edit, timeout 10" "Bash|Write|Edit|command|$H_GUARD|10" "$(hk "$SWI" PreToolUse)"
assert_eq "AC-C1 with: SessionStart = guard --session-start and the learnings hook, no matcher, timeout 10" \
  "$(printf '%s\n' "-|command|$H_START|10" "-|command|$H_LEARN|10" | LC_ALL=C sort)" "$(hk "$SWI" SessionStart | LC_ALL=C sort)"
assert_eq "AC-C1 with: Stop = guard --stop, no matcher, timeout 30" "-|command|$H_STOP|30" "$(hk "$SWI" Stop)"
assert_eq "AC-C1 without: no hooks key" "false" "$(jget "$SWO" '"hooks" in j')"
assert_eq "AC-C1 without: still the isolation file (claudeMdExcludes)" "true" "$(jget "$SWO" 'Array.isArray(j.claudeMdExcludes)')"
assert_file "AC-C1 the leak probe ran with the without settings" "$FR/claude.probe.1.settings"
assert_eq "AC-C1 the leak probe settings have no hooks" "false" "$(jget "$FR/claude.probe.1.settings" '"hooks" in j')"

echo "AC-C1 --arm both without --hooks: both files are today's, byte for byte (characterization: passes before and after)"
go --harness claude --model m-claude-1 --arm both --scenarios E8
WANT="$(mk_tmp)/with.json"; printf '{"autoMemoryEnabled": false}\n' > "$WANT"
if [ -f "$FR/claude.E8.with.1.settings" ] && cmp -s "$WANT" "$FR/claude.E8.with.1.settings"; then t_ok "AC-C1 no --hooks: the with file is {\"autoMemoryEnabled\": false} byte for byte"
else t_bad "AC-C1 no --hooks: the with file is {\"autoMemoryEnabled\": false} byte for byte" "$(cat "$FR/claude.E8.with.1.settings" 2>/dev/null)"; fi
assert_eq "AC-C1 no --hooks: the without file has no hooks key" "false" "$(jget "$FR/claude.E8.without.1.settings" '"hooks" in j')"

echo "AC-C1 --cmd --arm both --hooks: PB_EVAL_SETTINGS of the with arm has the hooks, the without arm none"
mk_adapter setrec 'cp "${PB_EVAL_SETTINGS:-/nonexistent}" "$REC/$e.settings" 2>/dev/null; true'
go --cmd "bash $A/setrec.sh" --arm both --hooks --scenarios E8
assert_rc "AC-C1 --cmd --arm both --hooks -> exit 0" 0
assert_eq "AC-C1 --cmd with: Stop = guard --stop" "-|command|$H_STOP|30" "$(hk "$REC/E8.with.1.settings" Stop)"
assert_eq "AC-C1 --cmd with: PreToolUse = the guard" "Bash|Write|Edit|command|$H_GUARD|10" "$(hk "$REC/E8.with.1.settings" PreToolUse)"
assert_eq "AC-C1 --cmd without: no hooks key" "false" "$(jget "$REC/E8.without.1.settings" '"hooks" in j')"

# ================= AC-C2 environment =================
mk_adapter envh 'env | grep -E "^(PB_EVAL_|PB_HEADLESS=)" | LC_ALL=C sort > "$REC/$e.henv"
printf "%s\n" "${PB_EVAL_HOOK_LOG-UNSET}" > "$REC/$e.hlog"
[ -n "${PB_EVAL_HOOK_LOG:-}" ] && printf "learnings inject 12\n" >> "$PB_EVAL_HOOK_LOG"
true'
# envof LABEL NAME -> the value of NAME in the env record of LABEL (UNSET when absent)
envof() { local v; v="$(sed -n "s/^$2=//p" "$REC/$1.henv" 2>/dev/null)"; if grep -q "^$2=" "$REC/$1.henv" 2>/dev/null; then printf '%s' "$v"; else printf 'UNSET'; fi; }

echo "AC-C2 a --cmd run without --hooks still gets PB_EVAL_HOOKS=1, PB_EVAL_HOOK_LOG=<run log>.hooks and PB_HEADLESS=1 (the caller's values replaced)"
WR="$(mk_tmp)"; : > "$WR/.pb-eval-workroot"; OD="$(mk_tmp)"; RES="$OD/results.md"; rm -f "$REC"/* "$FR"/*
run env -u PLAYBOOK_HOME PB_HEADLESS=0 PB_EVAL_HOOKS= PB_EVAL_HOOK_LOG=/leaked HOME="$GH" bash "$RUNNER" --cmd "bash $A/envh.sh" --scenarios E8 --workroot "$WR" --out "$RES"
assert_rc "AC-C2 --cmd run -> exit 0" 0
WRP="$(physdir "$WR")"
assert_eq "AC-C2 PB_EVAL_HOOKS=1" "1" "$(envof E8 PB_EVAL_HOOKS)"
assert_eq "AC-C2 PB_EVAL_HOOK_LOG=<workroot>/E8.log.hooks" "$WRP/E8.log.hooks" "$(envof E8 PB_EVAL_HOOK_LOG)"
assert_eq "AC-C2 PB_HEADLESS=1 (headless run, the caller's 0 replaced)" "1" "$(envof E8 PB_HEADLESS)"
assert_eq "AC-C2 a hook log written by the run is not a stray write" "PASS" "$(e_state E8 'nothing written outside the workdir')"
assert_eq "AC-C2 no --hooks: the md says Hooks: off" "1" "$(grep -cx 'Hooks: off' "$RES" 2>/dev/null || true)"
assert_eq "AC-C2 no --hooks: the JSON has hooks false" "false" "$(jget "$OD/results.json" 'j.hooks')"

echo "AC-C2 --interactive gives PB_HEADLESS=0"
go --cmd "bash $A/envh.sh" --scenarios E8 --interactive
assert_eq "AC-C2 --interactive: PB_HEADLESS=0" "0" "$(envof E8 PB_HEADLESS)"
assert_eq "AC-C2 --interactive: PB_EVAL_HOOKS=1 still" "1" "$(envof E8 PB_EVAL_HOOKS)"

echo "AC-C2 --hooks --arm both: each label gets its own hook log; md and JSON say hooks on"
go --cmd "bash $A/envh.sh" --arm both --hooks --scenarios E8
WRP="$(physdir "$WR")"
assert_eq "AC-C2 E8.with.1: PB_EVAL_HOOK_LOG=<workroot>/E8.with.1.log.hooks" "$WRP/E8.with.1.log.hooks" "$(envof E8.with.1 PB_EVAL_HOOK_LOG)"
assert_eq "AC-C2 E8.without.1: PB_EVAL_HOOK_LOG=<workroot>/E8.without.1.log.hooks" "$WRP/E8.without.1.log.hooks" "$(envof E8.without.1 PB_EVAL_HOOK_LOG)"
assert_eq "AC-C2 E8.without.1: PB_EVAL_HOOKS=1 (user-installed hooks stand aside in both arms)" "1" "$(envof E8.without.1 PB_EVAL_HOOKS)"
assert_eq "AC-C2 E8.with.1: the hook log is not a stray write" "PASS" "$(e_state E8.with.1 'nothing written outside the workdir')"
assert_eq "AC-C2 E8.without.1: the hook log is not a stray write" "PASS" "$(e_state E8.without.1 'nothing written outside the workdir')"
assert_eq "AC-C2 --hooks: the md says Hooks: on (with arm)" "1" "$(grep -cx 'Hooks: on (with arm)' "$RES" 2>/dev/null || true)"
assert_eq "AC-C2 --hooks: the md has no Hooks: off line" "0" "$(grep -cx 'Hooks: off' "$RES" 2>/dev/null || true)"
assert_eq "AC-C2 --hooks: the JSON has hooks true" "true" "$(jget "$OD/results.json" 'j.hooks')"
assert_eq "AC-C2 --hooks: the JSON hooks is a boolean" "boolean" "$(jget "$OD/results.json" 'typeof j.hooks')"
if grep -q 'PB_HEADLESS=1' "$RES" 2>/dev/null && grep -i 'PB_HEADLESS=1' "$RES" | grep -qi 'warn'; then
  t_ok "AC-C2 --hooks: the md notes that evals set PB_HEADLESS=1 and a local claude -p without it is only warned"
else t_bad "AC-C2 --hooks: the md notes that evals set PB_HEADLESS=1 and a local claude -p without it is only warned" "$(grep -i 'headless' "$RES" 2>/dev/null | head -n 3)"; fi

echo "AC-C2 the claude preset and the leak probe get PB_EVAL_HOOKS=1; the preset also PB_EVAL_HOOK_LOG and PB_HEADLESS=1"
WR="$(mk_tmp)"; : > "$WR/.pb-eval-workroot"; OD="$(mk_tmp)"; rm -f "$REC"/* "$FR"/*
run env -u PLAYBOOK_HOME PB_EVAL_HOOKS= PB_HEADLESS=0 HOME="$GH" PATH="$FK:$PATH" \
  bash "$RUNNER" --harness claude --model m-claude-1 --arm both --hooks --scenarios E8 --workroot "$WR" --out "$OD/r.md"
assert_rc "AC-C2 claude --arm both --hooks -> exit 0" 0
for L in E8.with.1 E8.without.1; do
  assert_contains "AC-C2 $L: the claude process gets PB_EVAL_HOOKS=1" "$(rec_of "$FR/claude.$L.env")" "PB_EVAL_HOOKS=1"
  assert_contains "AC-C2 $L: the claude process gets PB_EVAL_HOOK_LOG=.../$L.log.hooks" "$(rec_of "$FR/claude.$L.env")" "/$L.log.hooks"
  assert_eq "AC-C2 $L: the claude process gets PB_HEADLESS=1" "1" "$(rec_of "$FR/claude.$L.headless")"
done
assert_contains "AC-C2 the leak probe gets PB_EVAL_HOOKS=1" "$(rec_of "$FR/claude.probe.1.env")" "PB_EVAL_HOOKS=1"

t_summary
