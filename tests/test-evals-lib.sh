#!/usr/bin/env bash
# Tests for evals/lib-harness.sh (v0.26.0 lane E, spec .agents/handoff/01-spec.md slices S0 and the direct part of S3a): the
# shared helper of evals/run-evals.sh and lane O's run-outcome.sh. Each pbh_* function is called directly in a fresh bash
# that sources the library under set -u (AC8.2 "Each function has a direct test"). Never runs a harness.
. "$(dirname "$0")/lib.sh"
LIBH="$PB_ROOT/evals/lib-harness.sh"

# pbh CODE [BASH] -> OUT/RC of CODE run after sourcing the library under set -u (exit 99 when it cannot be sourced)
pbh() { run "${2:-bash}" -c 'set -u; . "$0" || exit 99; eval "$1"' "$LIBH" "$1"; }
words() { printf '%s' "$1" | tr '\n' ' ' | sed 's/^ *//; s/ *$//'; }   # OUT as one line of space-separated words
B32="$HOME/.local/bin/bash3.2"; [ -x "$B32" ] || B32="$(command -v bash3.2 2>/dev/null)"

echo "S0 AC8.1 the library is a sourced library: silent, no side effects, set -u safe, only pbh_ functions"
pbh 'true'
assert_rc "AC8.1 sourcing evals/lib-harness.sh under set -u succeeds" 0
assert_eq "AC8.1 sourcing prints nothing" "" "$OUT"
D="$(mk_tmp)"
run_in "$D" bash -c '. "$0"' "$LIBH"
assert_eq "AC8.1 sourcing writes nothing in the current directory" "" "$(ls -A "$D")"
pbh 'declare -F | sed "s/^declare -f[a-z]* //"'
FNS="$OUT"
assert_contains "AC8.1 the library defines pbh_preset_cmd" " $(words "$FNS") " " pbh_preset_cmd "
# pbh_results_json and pbh_stats (slice S5) have their direct tests in tests/test-evals-json.sh
for f in pbh_model_args pbh_arm_supported pbh_arm_settings pbh_check_key pbh_results_json pbh_stats pbh_clean_env; do
  assert_contains "AC8.1 the library defines $f" " $(words "$FNS") " " $f "
done
assert_eq "AC8.1 every function the library defines starts with pbh_" "" "$(printf '%s\n' "$FNS" | grep -v '^pbh_' | grep -v '^$' | tr '\n' ' ')"
pbh 'printf "%s" "$-"'
LIB_OPTS="$OUT"
run bash -c 'set -u; printf "%s" "$-"'
assert_eq "AC8.1 sourcing changes no shell option (no set -e, no set -x)" "$OUT" "$LIB_OPTS"
assert_contains "AC8.1 the library header names lane O's run-outcome.sh as a user of the interface" "$(sed -n '1,40p' "$LIBH" 2>/dev/null | grep '^#')" "run-outcome.sh"

echo "v0.28.2 lane o pbh_clean_env unsets CLAUDE* and ANTHROPIC_BASE_URL in the calling shell, keeps the rest"
run env CLAUDECODE=1 CLAUDE_X_Y=2 ANTHROPIC_BASE_URL=http://leak.invalid ANTHROPIC_API_KEY=k1 MY_CLAUDE_X=keep2 \
  bash -c 'set -u; . "$0"; pbh_clean_env; env | LC_ALL=C sort' "$LIBH"
assert_rc "pbh_clean_env returns 0 under set -u" 0
assert_eq "pbh_clean_env: no CLAUDE* variable is left" "0" "$(printf '%s\n' "$OUT" | grep -c '^CLAUDE')"
assert_eq "pbh_clean_env: ANTHROPIC_BASE_URL is gone" "0" "$(printf '%s\n' "$OUT" | grep -c '^ANTHROPIC_BASE_URL=')"
assert_contains "pbh_clean_env: ANTHROPIC_API_KEY stays" "$OUT" "ANTHROPIC_API_KEY=k1"
assert_contains "pbh_clean_env: MY_CLAUDE_X stays" "$OUT" "MY_CLAUDE_X=keep2"
assert_contains "pbh_clean_env is listed in the library header" "$(sed -n '1,60p' "$LIBH" 2>/dev/null | grep '^#')" "pbh_clean_env"

echo "S0 AC8.1 pbh_preset_cmd keeps today's preset strings (evals/run-evals.sh:135-139 at 4ebfd71)"
pbh 'pbh_preset_cmd claude'
assert_eq "AC8.1 pbh_preset_cmd claude" 'cd "$1" && claude -p --output-format stream-json --verbose "$(cat "$2")"' "$OUT"
pbh 'pbh_preset_cmd codex'
assert_eq "AC8.1 pbh_preset_cmd codex" 'cd "$1" && codex exec "$(cat "$2")"' "$OUT"
pbh 'pbh_preset_cmd opencode'
assert_eq "AC8.1 pbh_preset_cmd opencode" 'cd "$1" && opencode run --auto "$(cat "$2")"' "$OUT"

echo "S0 AC8.2 run-evals.sh sources the library and keeps no second copy of the presets"
if grep -qE '^[^#]*(\.|source)[[:space:]].*lib-harness\.sh' "$PB_ROOT/evals/run-evals.sh"; then t_ok "AC8.2 run-evals.sh sources evals/lib-harness.sh"
else t_bad "AC8.2 run-evals.sh sources evals/lib-harness.sh" "no '. .../lib-harness.sh' line in evals/run-evals.sh"; fi
for p in 'claude -p --output-format stream-json --verbose' 'codex exec "$(cat' 'opencode run --auto'; do
  hits="$(cd "$PB_ROOT" && grep -lF -- "$p" evals/*.sh tools/*.sh 2>/dev/null | tr '\n' ' ')"
  assert_eq "AC8.2 the preset string [$p] appears in one file only, the library" "evals/lib-harness.sh " "$hits"
  assert_eq "AC8.2 the preset string [$p] appears once in the library" "1" "$(grep -cF -- "$p" "$LIBH" 2>/dev/null || true)"
done

echo "S0 AC1.4/AC8.1 pbh_model_args maps the model flag per harness"
pbh 'pbh_model_args claude claude-opus-x'
assert_eq "AC1.4 pbh_model_args claude M -> --model M" "--model claude-opus-x" "$(words "$OUT")"
pbh 'pbh_model_args codex gpt-x-1'
assert_eq "AC1.4 pbh_model_args codex M -> -m M (references/harnesses.md:10)" "-m gpt-x-1" "$(words "$OUT")"
pbh 'pbh_model_args opencode prov/model-1'
assert_eq "AC1.4 D7 [UNVERIFIED flag] pbh_model_args opencode M -> --model M" "--model prov/model-1" "$(words "$OUT")"
pbh 'pbh_model_args claude "a.b_c:d/e@f-1"'
assert_eq "AC1.4 pbh_model_args keeps a model with . _ : / @ - as one value" "--model a.b_c:d/e@f-1" "$(words "$OUT")"
pbh 'pbh_model_args claude ""'
assert_eq "AC1.4 pbh_model_args with no model adds nothing" "" "$(words "$OUT")"
assert_rc "AC1.4 pbh_model_args with no model returns 0" 0

echo "S0 AC3.5/AC8.1 pbh_arm_supported"
for h in claude codex opencode; do
  pbh "pbh_arm_supported $h with"
  assert_rc "AC8.1 pbh_arm_supported $h with -> 0" 0
done
pbh 'pbh_arm_supported claude without'
assert_rc "AC8.1 pbh_arm_supported claude without -> 0 (claude-settings mechanism)" 0
for h in codex opencode; do
  pbh "pbh_arm_supported $h without"
  assert_rc "AC3.5 pbh_arm_supported $h without -> 2" 2
  if [ "$RC" = 2 ] && [ -n "$(words "$OUT")" ]; then t_ok "AC3.5 pbh_arm_supported $h without prints a reason"; else t_bad "AC3.5 pbh_arm_supported $h without prints a reason" "empty output"; fi
done

echo "S0 AC5.3/AC8.1 pbh_check_key drops a trailing (...) group that carries a run-specific value (D8)"
ck() { # NAME INPUT EXPECTED
  pbh "pbh_check_key $(printf '%q' "$2")"
  assert_eq "AC5.3 $1" "$3" "$OUT"
}
ck "a plain name is its own key" "subtract(5,3) === 2" "subtract(5,3) === 2"
ck "a (...) group with = is dropped" "at least one question to the user mentions humanizer (asked=1)" "at least one question to the user mentions humanizer"
ck "a (...) group with ': ' is dropped" "nothing written outside the workdir (new in the workroot: x y)" "nothing written outside the workdir"
ck "a (models: ...) group is dropped" "the roles use the conf models (models: sonnet,opus)" "the roles use the conf models"
ck "a (...) group with 'bucket ' is dropped" "the cost lands in one row (bucket tester)" "the cost lands in one row"
ck "a (...) group with 'first one after' is dropped" "the description reads naturally (the commit is the first one after abc1234)" "the description reads naturally"
ck "a (...) group without a marker stays" "transcript shows sub-agent use (Agent or Task tool)" "transcript shows sub-agent use (Agent or Task tool)"
ck "a group with a marker that is not trailing stays" "x (a=1) then more" "x (a=1) then more"
ck "only the trailing group goes" "keep (Agent tool) drop (asked=2)" "keep (Agent tool) drop"

echo "S0 AC8.1 bash 3.2: the library sources and works under bash 3.2 (macOS)"
if [ -n "$B32" ] && [ -x "$B32" ]; then
  pbh 'pbh_check_key "a (asked=1)"' "$B32"
  assert_eq "AC8.1 bash 3.2: pbh_check_key" "a" "$OUT"
  pbh 'pbh_model_args codex m1' "$B32"
  assert_eq "AC8.1 bash 3.2: pbh_model_args" "-m m1" "$(words "$OUT")"
else
  t_skip 2 "no bash 3.2 binary on this machine"
fi

# ---- S3a (direct part): pbh_arm_settings FILE ARM HOME REPO writes the settings JSON of an arm (AC3.2) and prints the dropped-line count (AC3.4) ----
echo "S3a AC3.2 pbh_arm_settings without: the settings JSON"
# stand-in home: block + 2 personal lines, two playbook skills and one other skill, a credentials file
H="$(mk_tmp)"; mkdir -p "$H/.claude/skills/playbook-tdd" "$H/.claude/skills/playbook-extra" "$H/.claude/skills/other-skill" "$H/.agents/playbook"
printf '%s\n' '# my notes' '<!-- BEGIN agent-playbook v0.25.1 (managed block) -->' '## Agent Playbook' 'rule one' '<!-- END agent-playbook -->' 'my personal rule' > "$H/.claude/CLAUDE.md"
printf 'SECRET-TOKEN-XYZ\n' > "$H/.claude/.credentials.json"
for s in playbook-tdd playbook-extra other-skill; do printf -- '---\nname: %s\n---\n' "$s" > "$H/.claude/skills/$s/SKILL.md"; done
# stand-in runner repo: skills/<name>/SKILL.md for playbook-alpha, playbook-beta and helper-x; zz-nofile has no SKILL.md
R="$(mk_tmp)"; mkdir -p "$R/skills/playbook-alpha" "$R/skills/playbook-beta" "$R/skills/helper-x" "$R/skills/zz-nofile"
for s in playbook-alpha playbook-beta helper-x; do printf -- '---\nname: %s\n---\n' "$s" > "$R/skills/$s/SKILL.md"; done
H_BEFORE="$(cd "$H" && find . | LC_ALL=C sort)"
SD="$(mk_tmp)"; F="$SD/without.json"
pbh "pbh_arm_settings '$F' without '$H' '$R'"
assert_rc "AC3.2 pbh_arm_settings without -> 0" 0
assert_eq "AC3.4 pbh_arm_settings prints the count of non-playbook lines of ~/.claude/CLAUDE.md (2)" "2" "$(words "$OUT")"
jget() {
  node -e 'const fs=require("fs");let j;try{j=JSON.parse(fs.readFileSync(process.argv[1],"utf8"))}catch(e){process.stdout.write("NOJSON");process.exit(0)}
let r;try{r=(new Function("j","return ("+process.argv[2]+")"))(j)}catch(e){r="ERR:"+e.message}
process.stdout.write(typeof r==="string"?r:String(JSON.stringify(r)))' "$1" "$2"
}
assert_eq "AC3.2 the without file is a JSON object" "object" "$(jget "$F" 'typeof j')"
assert_eq "AC3.2 claudeMdExcludes holds the absolute HOME/.claude/CLAUDE.md" "true" "$(jget "$F" 'Array.isArray(j.claudeMdExcludes) && j.claudeMdExcludes.includes("'"$H"'/.claude/CLAUDE.md")')"
# Windows (Git Bash): claude.exe matches claudeMdExcludes against a native path, so the MSYS form /c/Users/... is not enough;
# with cygpath on PATH the entry also holds the `cygpath -m` form (C:/Users/...), the form a real run showed to work (Run 25 smoke)
CYGB="$(mk_tmp)"
printf '#!/bin/sh\n[ "$1" = -m ] || exit 2\nprintf "C:/fake%%s\\n" "$2"\n' > "$CYGB/cygpath"; chmod +x "$CYGB/cygpath"
F2="$SD/without-cyg.json"
OUT="$(PATH="$CYGB:$PATH" bash -c '. "$1"; pbh_arm_settings "$2" without "$3" "$4"' _ "$PB_ROOT/evals/lib-harness.sh" "$F2" "$H" "$R" 2>&1)"; RC=$?
assert_rc "cygpath: pbh_arm_settings without -> 0" 0
assert_eq "cygpath: claudeMdExcludes also holds the cygpath -m form of HOME/.claude/CLAUDE.md" "true" "$(jget "$F2" '(j.claudeMdExcludes||[]).includes("C:/fake'"$H"'/.claude/CLAUDE.md")')"
assert_eq "cygpath: claudeMdExcludes still holds the plain form" "true" "$(jget "$F2" '(j.claudeMdExcludes||[]).includes("'"$H"'/.claude/CLAUDE.md")')"
assert_eq "no cygpath: claudeMdExcludes has no C:/fake entry" "false" "$(jget "$F" 'JSON.stringify(j.claudeMdExcludes||[]).includes("C:/fake")')"
for s in playbook-alpha playbook-beta helper-x; do
  assert_eq "AC3.2 skillOverrides turns off the repo skill $s" "off" "$(jget "$F" '(j.skillOverrides||{})["'"$s"'"]')"
done
for s in playbook-tdd playbook-extra; do
  assert_eq "AC3.2 skillOverrides turns off the home playbook skill $s" "off" "$(jget "$F" '(j.skillOverrides||{})["'"$s"'"]')"
done
assert_eq "AC3.2 skillOverrides leaves the non-playbook home skill other-skill alone" "absent" "$(jget "$F" '(j.skillOverrides||{})["other-skill"] === undefined ? "absent" : "present"')"
assert_eq "AC3.2 skillOverrides skips a repo skills dir without SKILL.md" "absent" "$(jget "$F" '(j.skillOverrides||{})["zz-nofile"] === undefined ? "absent" : "present"')"
DENY='((j.permissions||{}).deny||[])'
for s in playbook-alpha playbook-extra; do
  for p in "Skill($s)" "Skill($s *)"; do
    assert_eq "AC3.2 permissions.deny holds $p" "true" "$(jget "$F" "$DENY"'.includes("'"$p"'")')"
  done
done
for p in 'Read(~/.agents/**)' 'Read(~/.claude/skills/playbook-*/**)'; do
  assert_eq "AC3.2 permissions.deny holds $p" "true" "$(jget "$F" "$DENY"'.includes("'"$p"'")')"
done
assert_eq "fix7 permissions.deny has a Skill(skill:NAME) rule (documented form, matches any name)" "true" "$(jget "$F" "$DENY"'.some(x => /^Skill[(]skill:/.test(x))')"
assert_eq "AC3.2 permissions.deny has no Skill rule for other-skill" "false" "$(jget "$F" "$DENY"'.some(x => /other-skill/.test(x))')"
assert_eq "AC3.2 autoMemoryEnabled is false in the without file" "false" "$(jget "$F" 'j.autoMemoryEnabled')"
assert_eq "AC3.1 no credential content in the settings file" "0" "$(grep -c SECRET-TOKEN-XYZ "$F" 2>/dev/null || true)"
assert_eq "AC3.1 pbh_arm_settings leaves the home unchanged (listing)" "$H_BEFORE" "$(cd "$H" && find . | LC_ALL=C sort)"

echo "S3a AC3.2 pbh_arm_settings with: only autoMemoryEnabled false (D11)"
F2="$SD/with.json"
pbh "pbh_arm_settings '$F2' with '$H' '$R'"
assert_rc "AC3.2 pbh_arm_settings with -> 0" 0
assert_eq "AC3.2 the with file holds one key" "autoMemoryEnabled" "$(jget "$F2" 'Object.keys(j).join(",")')"
assert_eq "AC3.2 the with file sets autoMemoryEnabled false" "false" "$(jget "$F2" 'j.autoMemoryEnabled')"

echo "S3a AC3.4 pbh_arm_settings without: a home whose CLAUDE.md is the block alone drops 0 lines; no CLAUDE.md drops 0"
H0="$(mk_tmp)"; mkdir -p "$H0/.claude"
printf '%s\n' '<!-- BEGIN agent-playbook v0.25.1 (managed block) -->' 'rule one' '<!-- END agent-playbook -->' > "$H0/.claude/CLAUDE.md"
pbh "pbh_arm_settings '$SD/b.json' without '$H0' '$R'"
assert_eq "AC3.4 block-only CLAUDE.md: 0 dropped lines" "0" "$(words "$OUT")"
HN="$(mk_tmp)"
pbh "pbh_arm_settings '$SD/n.json' without '$HN' '$R'"
assert_rc "AC3.4 a home without ~/.claude: pbh_arm_settings without -> 0" 0
assert_eq "AC3.4 a home without ~/.claude/CLAUDE.md: 0 dropped lines" "0" "$(words "$OUT")"
assert_eq "AC3.2 a home without ~/.claude: the repo skills are still turned off" "off" "$(jget "$SD/n.json" '(j.skillOverrides||{})["playbook-alpha"]')"

echo "S3a AC3.2 pbh_arm_settings without: a linked CLAUDE.md is excluded by its path and its physical path; a linked playbook skill is turned off"
if [ "$SYMLINKS" = 1 ]; then
  X="$(mk_tmp)"; XP="$(cd "$X" && pwd -P)"
  printf '%s\n' '<!-- BEGIN agent-playbook v0.25.1 (managed block) -->' 'rule' '<!-- END agent-playbook -->' > "$X/real-claude.md"
  mkdir -p "$X/pl-dir"; printf -- '---\nname: playbook-linked\n---\n' > "$X/pl-dir/SKILL.md"
  HL="$(mk_tmp)"; mkdir -p "$HL/.claude/skills"
  ln -s "$X/real-claude.md" "$HL/.claude/CLAUDE.md"; ln -s "$X/pl-dir" "$HL/.claude/skills/playbook-linked"
  pbh "pbh_arm_settings '$SD/l.json' without '$HL' '$R'"
  assert_eq "AC3.2 linked CLAUDE.md: claudeMdExcludes holds HOME/.claude/CLAUDE.md" "true" "$(jget "$SD/l.json" '(j.claudeMdExcludes||[]).includes("'"$HL"'/.claude/CLAUDE.md")')"
  assert_eq "AC3.2 linked CLAUDE.md: claudeMdExcludes also holds its physical path" "true" "$(jget "$SD/l.json" '(j.claudeMdExcludes||[]).includes("'"$XP"'/real-claude.md")')"
  assert_eq "AC3.2 a playbook-* link in the home skills dir is turned off" "off" "$(jget "$SD/l.json" '(j.skillOverrides||{})["playbook-linked"]')"
  DENYL='((j.permissions||{}).deny||[])'
  assert_eq "AC3.2 a linked playbook skill: deny Read(/<physical path>/**)" "true" "$(jget "$SD/l.json" "$DENYL"'.includes("Read(/'"$XP"'/pl-dir/**)")')"
  OUT="$(PATH="$CYGB:$PATH" bash -c '. "$1"; pbh_arm_settings "$2" without "$3" "$4"' _ "$PB_ROOT/evals/lib-harness.sh" "$SD/lc.json" "$HL" "$R" 2>&1)"
  assert_eq "fix7 cygpath: deny also holds a Read(...) rule with the cygpath -m form of the linked skill's physical path" "true" \
    "$(jget "$SD/lc.json" "$DENYL"'.some(x => x.indexOf("Read(") === 0 && x.indexOf("C:/fake'"$XP"'/pl-dir") >= 0 && x.slice(-4) === "/**)")')"
  assert_eq "fix7 cygpath: the plain physical-path rule stays" "true" "$(jget "$SD/lc.json" "$DENYL"'.includes("Read(/'"$XP"'/pl-dir/**)")')"
else
  t_skip 6 "ln -s makes a copy here (L-0004)"
fi

t_summary
