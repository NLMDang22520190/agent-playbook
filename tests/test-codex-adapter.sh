#!/usr/bin/env bash
# Tests for evals/codex-adapter.sh and the codex preset (v0.30.0 lane g, queue P0-3, spec AC7-AC8): the Codex adapter of
# Run C1 moves into the repo. The with arm runs codex with the real HOME; the without arm (`--pb-arm without`) gets a fresh
# HOME that holds only .codex/auth.json, so ~/.codex/AGENTS.md and the playbook skills are out of reach. A fake codex first
# on PATH records what it got. Never calls a real harness.
. "$(dirname "$0")/lib.sh"
. "$PB_ROOT/evals/lib-harness.sh"
AD="$PB_ROOT/evals/codex-adapter.sh"

echo "AC7 the adapter exists"
assert_file "AC7 evals/codex-adapter.sh exists" "$AD"

W="$(mk_tmp)"
BIN="$W/bin"; REC="$W/rec"; mkdir -p "$BIN" "$REC"
cat > "$BIN/codex" <<EOF
#!/usr/bin/env bash
REC='$REC'
EOF
cat >> "$BIN/codex" <<'EOF'
printf '%s\n' "$@" > "$REC/args"
printf '%s\n' "$HOME" > "$REC/home"
printf '%s\n' "${CODEX_HOME-UNSET}" > "$REC/codex_home"
printf '%s\n' "${BASH_XTRACEFD-UNSET}" > "$REC/xfd"
pwd -P > "$REC/cwd"
(cd "$HOME" && find . -mindepth 1 | LC_ALL=C sort) > "$REC/homelist"
[ -f "$HOME/.codex/auth.json" ] && cp "$HOME/.codex/auth.json" "$REC/auth"
echo '{"type":"thread.started","thread_id":"t"}'
exit "${FAKE_CODEX_RC:-0}"
EOF
chmod 755 "$BIN/codex"

H="$W/home"; mkdir -p "$H/.codex" "$H/.agents/skills/playbook-tdd"
printf '{"token":"T1"}\n' > "$H/.codex/auth.json"
printf '<!-- BEGIN agent-playbook -->\n' > "$H/.codex/AGENTS.md"
printf 'x\n' > "$H/.agents/skills/playbook-tdd/SKILL.md"
WD="$W/work"; mkdir -p "$WD"
PF="$W/prompt.txt"; printf 'Fix the bug.\nSecond line.\n' > "$PF"
ad() { RC=0; OUT="$(env -u CODEX_HOME HOME="$H" PATH="$BIN:$PATH" "$@" 2>&1)" || RC=$?; }

echo "AC7 with arm: real HOME, the flags, the prompt, the workdir"
ad bash "$AD" "$WD" "$PF" -m m-codex-1
assert_rc "AC7 with arm -> exit 0" 0
assert_eq "AC7 codex argv" "exec
--sandbox
workspace-write
--skip-git-repo-check
--json
--ephemeral
-m
m-codex-1
Fix the bug.
Second line." "$(cat "$REC/args" 2>/dev/null)"
assert_eq "AC7 with arm keeps HOME" "$H" "$(cat "$REC/home" 2>/dev/null)"
assert_eq "AC7 codex runs in the workdir" "$(cd "$WD" && pwd -P)" "$(cat "$REC/cwd" 2>/dev/null)"
assert_contains "AC7 codex stdout passes through" "$OUT" '{"type":"thread.started","thread_id":"t"}'

echo "AC7 without arm: a fresh HOME with only .codex/auth.json"
rm -f "$REC"/*
ad bash "$AD" "$WD" "$PF" -m m-codex-1 --pb-arm without
assert_rc "AC7 without arm -> exit 0" 0
FH="$(cat "$REC/home" 2>/dev/null)"
if [ -n "$FH" ] && [ "$FH" != "$H" ]; then t_ok "AC7 without arm: HOME is another dir"; else t_bad "AC7 without arm: HOME is another dir" "HOME=[$FH]"; fi
assert_eq "AC7 without arm: the fresh HOME holds .codex/auth.json only" "./.codex
./.codex/auth.json" "$(cat "$REC/homelist" 2>/dev/null)"
assert_eq "AC7 without arm: auth.json is the real one" '{"token":"T1"}' "$(cat "$REC/auth" 2>/dev/null)"
assert_eq "AC7 without arm: CODEX_HOME is the fresh HOME's .codex" "$FH/.codex" "$(cat "$REC/codex_home" 2>/dev/null)"
assert_not_contains "AC7 without arm: --pb-arm never reaches codex" "$(cat "$REC/args" 2>/dev/null)" "--pb-arm"
assert_contains "AC7 without arm: -m still reaches codex" "$(tr '\n' ' ' < "$REC/args" 2>/dev/null)" "-m m-codex-1"
assert_no_path "AC7 without arm: the fresh HOME is removed afterwards" "$FH"
assert_file "AC7 without arm: the real auth.json is untouched" "$H/.codex/auth.json"

echo "AC7 --pb-arm with keeps HOME"
rm -f "$REC"/*
ad bash "$AD" "$WD" "$PF" --pb-arm with
assert_eq "AC7 --pb-arm with: HOME unchanged" "$H" "$(cat "$REC/home" 2>/dev/null)"

echo "AC7 CODEX_HOME is the source of auth.json when set"
C2="$W/ch"; mkdir -p "$C2"; printf '{"token":"T2"}\n' > "$C2/auth.json"
rm -f "$REC"/*
RC=0; OUT="$(HOME="$H" CODEX_HOME="$C2" PATH="$BIN:$PATH" bash "$AD" "$WD" "$PF" --pb-arm without 2>&1)" || RC=$?
assert_eq "AC7 auth.json comes from CODEX_HOME" '{"token":"T2"}' "$(cat "$REC/auth" 2>/dev/null)"

echo "AC7 no auth.json: exit 3, codex not called"
H2="$W/home2"; mkdir -p "$H2"
rm -f "$REC"/*
RC=0; OUT="$(env -u CODEX_HOME HOME="$H2" PATH="$BIN:$PATH" bash "$AD" "$WD" "$PF" --pb-arm without 2>&1)" || RC=$?
assert_rc "AC7 no auth.json -> exit 3" 3
assert_contains "AC7 no auth.json: the message" "$OUT" "auth.json"
assert_no_path "AC7 no auth.json: codex never ran" "$REC/args"

echo "AC7 an unknown arm is a usage error"
RC=0; OUT="$(HOME="$H" PATH="$BIN:$PATH" bash "$AD" "$WD" "$PF" --pb-arm both 2>&1)" || RC=$?
assert_rc "AC7 --pb-arm both -> exit 2" 2

echo "AC7 codex's exit code is the adapter's (both arms); BASH_XTRACEFD never reaches codex"
for arm in with without; do
  rm -f "$REC"/*
  RC=0; OUT="$(env -u CODEX_HOME HOME="$H" PATH="$BIN:$PATH" FAKE_CODEX_RC=7 BASH_XTRACEFD=2 bash "$AD" "$WD" "$PF" --pb-arm "$arm" 2>&1)" || RC=$?
  assert_rc "AC7 $arm arm: codex exit 7 -> exit 7" 7
  assert_eq "AC7 $arm arm: no BASH_XTRACEFD in codex's environment" "UNSET" "$(cat "$REC/xfd" 2>/dev/null)"
done

echo "AC8 the preset runs the adapter; the codex without arm is supported; opencode still refuses"
P="$(pbh_preset_cmd codex)"
assert_contains "AC8 the codex preset names evals/codex-adapter.sh" "$P" "codex-adapter.sh"
rm -f "$REC"/*
RC=0; OUT="$(env -u CODEX_HOME HOME="$H" PATH="$BIN:$PATH" bash -c "$P \"\${@:3}\"" adapter "$WD" "$PF" -m m2 --pb-arm without 2>&1)" || RC=$?
assert_rc "AC8 the preset string runs (bash -c, as the runners do)" 0
assert_eq "AC8 through the preset: the fresh HOME holds auth.json only" "./.codex
./.codex/auth.json" "$(cat "$REC/homelist" 2>/dev/null)"
RC=0; pbh_arm_supported codex without >/dev/null || RC=$?
assert_rc "AC8 pbh_arm_supported codex without -> 0" 0
RC=0; pbh_arm_supported opencode without >/dev/null || RC=$?
assert_rc "AC8 pbh_arm_supported opencode without -> 2" 2

t_summary
