#!/usr/bin/env bash
# Tests for tools/eval-guard.sh and evals/scenario-map (v0.22.4 AC2, decision D1).
#   tools/eval-guard.sh --base REF [--max-cost USD] [--harness H]
# The tool is copied into a throw-away repo that has its own evals/scenario-map and a RECORDING fake
# evals/run-evals.sh; fake claude/codex/opencode/node-less harnesses on PATH record every call too.
# The guard must only print: none of them may ever be called.
# Assumption (tester): the map is found in the repo the tool runs in (evals/scenario-map), and the printed
# command is one whole line: bash evals/run-evals.sh --harness H --scenarios E1,E3 --max-cost USD
. "$(dirname "$0")/lib.sh"
GUARD="$PB_ROOT/tools/eval-guard.sh"
MAP="$PB_ROOT/evals/scenario-map"
RUNEV="$PB_ROOT/evals/run-evals.sh"

echo "AC2.1 the real map: every scenario is auto-gradable"
assert_file "AC2.1 evals/scenario-map exists" "$MAP"
AUTO="$(sed -n 's/^AUTO="\(.*\)"$/\1/p' "$RUNEV" | head -n 1)"
if [ -n "$AUTO" ]; then t_ok "AC2.1 run-evals.sh has an AUTO list ($AUTO)"; else t_bad "AC2.1 run-evals.sh has an AUTO list" "no AUTO=\"...\" line"; fi
NMAPPED=0; BAD=""
set -f   # the globs in the map must not expand here
if [ -f "$MAP" ]; then
  while IFS= read -r line; do
    case "$line" in ""|"#"*) continue ;; esac
    set -- $line
    if [ "$#" -lt 2 ]; then BAD="$BAD [no scenario on: $line]"; continue; fi
    shift
    for sc in "$@"; do
      NMAPPED=$((NMAPPED + 1))
      case " $AUTO " in *" $sc "*) ;; *) BAD="$BAD $sc" ;; esac
    done
  done < "$MAP"
fi
set +f
assert_eq "AC2.1 every scenario named in the map is in run-evals.sh's AUTO list (and every line has a scenario)" "" "$BAD"
if [ "$NMAPPED" -gt 0 ]; then t_ok "AC2.1 the map names at least one scenario"; else t_bad "AC2.1 the map names at least one scenario" "empty or missing map"; fi
assert_contains "AC2.1 the map covers AGENTS.global.md" "$(cat "$MAP" 2>/dev/null)" "AGENTS.global.md"
assert_contains "AC2.1 the map covers skill files" "$(cat "$MAP" 2>/dev/null)" "skills/"

echo "AC2.2 the tool exists"
assert_file "AC2.2 tools/eval-guard.sh exists" "$GUARD"

W="$(mk_tmp)"
BIN="$W/bin"; mkdir -p "$BIN"
CALLS="$W/calls.log"; : > "$CALLS"
for h in claude codex opencode; do
  printf '#!/usr/bin/env bash\necho "%s $*" >> "%s"\nexit 0\n' "$h" "$CALLS" > "$BIN/$h"
  chmod +x "$BIN/$h"
done

# fixture repo: base commit with the guard, a map (E1 E3 / E3 E5 / E4 E1), a recording run-evals.sh and some files
R="$W/repo"; mkdir -p "$R/tools" "$R/evals" "$R/skills/a" "$R/skills/b" "$R/docs"
[ -f "$GUARD" ] && cp -p "$GUARD" "$R/tools/eval-guard.sh"
printf 'skills/a/* E1 E3\nskills/b/SKILL.md E3 E5\nAGENTS.global.md E4 E1\n' > "$R/evals/scenario-map"
printf '#!/usr/bin/env bash\necho "run-evals.sh $*" >> "%s"\nexit 0\n' "$CALLS" > "$R/evals/run-evals.sh"
printf 'a1\n' > "$R/skills/a/SKILL.md"; printf 'b1\n' > "$R/skills/b/SKILL.md"; printf 'g1\n' > "$R/AGENTS.global.md"; printf 'd1\n' > "$R/docs/x.md"
( cd "$R" && git init -q && git config user.email t@example.invalid && git config user.name tester &&
  git config commit.gpgsign false && git config core.autocrlf false &&
  git add -A && git commit -q -m base && git tag base ) || exit 3
git_c() { ( cd "$R" && git "$@" ); }
mark() { git_c checkout -q "$1" 2>/dev/null || git_c checkout -q -b "$1"; }
guard() { run_in "$R" env -u PLAYBOOK_HARNESS PATH="$BIN:$PATH" bash tools/eval-guard.sh "$@"; }
guard_env() { local hv="$1"; shift; run_in "$R" env PLAYBOOK_HARNESS="$hv" PATH="$BIN:$PATH" bash tools/eval-guard.sh "$@"; }
has_line() { if printf '%s\n' "$OUT" | grep -qxF -- "$2"; then t_ok "$1"; else t_bad "$1" "no line [$2] in: $OUT"; fi; }

echo "AC2.2 scenarios deduplicated, in map order (not file order, not sorted); the command with the defaults"
mark c1
printf 'b2\n' > "$R/skills/b/SKILL.md"; printf 'g2\n' > "$R/AGENTS.global.md"
git_c add -A; git_c commit -q -m "change b and global"
guard --base base
assert_rc "AC2.2 a mapped change exits 0" 0
has_line "AC2.2 the command: map order E3,E5 (skills/b) then E4,E1 (global), comma separated, harness claude and 3 USD by default" "bash evals/run-evals.sh --harness claude --scenarios E3,E5,E4,E1 --max-cost 3"
assert_contains "AC2.2 the changed mapped file is named (skills/b/SKILL.md)" "$OUT" "skills/b/SKILL.md"
assert_contains "AC2.2 the changed mapped file is named (AGENTS.global.md)" "$OUT" "AGENTS.global.md"
assert_not_contains "AC2.2 an unmapped skill (skills/a) is not named" "$OUT" "skills/a"
assert_not_contains "AC2.2 a changed mapped file prints no 'no skill text changed'" "$OUT" "no skill text changed"

printf 'a2\n' > "$R/skills/a/SKILL.md"
git_c add -A; git_c commit -q -m "change a"
guard --base base
has_line "AC2.2 a, b and global changed: E1,E3 first (map line 1), E5 (E3 is not repeated), E4: E1,E3,E5,E4" "bash evals/run-evals.sh --harness claude --scenarios E1,E3,E5,E4 --max-cost 3"
assert_eq "AC2.2 exactly one command line is printed" "1" "$(printf '%s\n' "$OUT" | grep -c 'run-evals\.sh')"

echo "AC2.2 the harness comes from PLAYBOOK_HARNESS, the flags override the defaults"
guard_env codex --base base
has_line "AC2.2 PLAYBOOK_HARNESS=codex is the default harness" "bash evals/run-evals.sh --harness codex --scenarios E1,E3,E5,E4 --max-cost 3"
guard_env codex --base base --harness opencode
has_line "AC2.2 --harness overrides PLAYBOOK_HARNESS" "bash evals/run-evals.sh --harness opencode --scenarios E1,E3,E5,E4 --max-cost 3"
guard --base base --max-cost 5
has_line "AC2.2 --max-cost 5 overrides the 3 USD default" "bash evals/run-evals.sh --harness claude --scenarios E1,E3,E5,E4 --max-cost 5"
guard --base base --max-cost 1.5 --harness codex
has_line "AC2.2 both flags, a decimal cost" "bash evals/run-evals.sh --harness codex --scenarios E1,E3,E5,E4 --max-cost 1.5"
guard --max-cost 5 --harness codex --base base
has_line "AC2.2 the flags may come in any order" "bash evals/run-evals.sh --harness codex --scenarios E1,E3,E5,E4 --max-cost 5"

echo "AC2.2 only the diff since the base counts (merge base form REF...HEAD)"
guard --base HEAD
assert_rc "AC2.2 no change since HEAD: exit 0" 0
assert_contains "AC2.2 no change since HEAD: 'no skill text changed'" "$OUT" "no skill text changed"
assert_not_contains "AC2.2 no change: no command line" "$OUT" "run-evals.sh"

echo "AC2.2 nothing mapped changed"
git_c checkout -q base 2>/dev/null; git_c checkout -q -b c2
printf 'd2\n' > "$R/docs/x.md"; printf 'new\n' > "$R/docs/y.md"
git_c add -A; git_c commit -q -m "docs only"
guard --base base
assert_rc "AC2.2 only an unmapped file changed: exit 0" 0
assert_contains "AC2.2 only an unmapped file changed: 'no skill text changed'" "$OUT" "no skill text changed"
assert_not_contains "AC2.2 only an unmapped file changed: no command line" "$OUT" "run-evals.sh"
assert_not_contains "AC2.2 only an unmapped file changed: no scenarios" "$OUT" "E1"

echo "AC2.2 a mapped file that changed on the base side only is not reported (three-dot diff)"
git_c checkout -q base 2>/dev/null; git_c checkout -q -b c3
printf 'c3 docs\n' > "$R/docs/z.md"; git_c add -A; git_c commit -q -m "feature docs"
git_c checkout -q base 2>/dev/null; git_c checkout -q -B mainline
printf 'a-main\n' > "$R/skills/a/SKILL.md"; git_c add -A; git_c commit -q -m "main moved a"
git_c checkout -q c3
guard --base mainline
assert_contains "AC2.2 a change made only on the base branch is not the feature's change" "$OUT" "no skill text changed"

echo "AC2.2 usage"
guard
if [ "$RC" -ne 0 ]; then t_ok "AC2.2 no --base: non-zero exit"; else t_bad "AC2.2 no --base: non-zero exit" "exit 0, output: $OUT"; fi

echo "AC2.2 the harness must be opencode, claude or codex (flag and PLAYBOOK_HARNESS)"
for st in c3 c1; do
  git_c checkout -q "$st"
  guard --base base --harness bogus
  assert_rc "AC2.2 [$st] --harness bogus: exit 2" 2
  guard --base base --harness 'claude;touch x'
  assert_rc "AC2.2 [$st] --harness with shell characters: exit 2" 2
  guard --base base --harness Claude
  assert_rc "AC2.2 [$st] --harness Claude (case matters): exit 2" 2
  guard_env bogus --base base
  assert_rc "AC2.2 [$st] PLAYBOOK_HARNESS=bogus: exit 2" 2
  guard_env 'a b' --base base
  assert_rc "AC2.2 [$st] PLAYBOOK_HARNESS with a blank: exit 2" 2
  for okh in opencode claude codex; do
    guard --base base --harness "$okh"
    assert_rc "AC2.2 [$st] --harness $okh: exit 0" 0
  done
done
assert_eq "AC2.2 a rejected harness writes nothing" "" "$(git_c status --porcelain)"

echo "AC2.2 the map: blank lines and a last line without a newline still parse"
git_c checkout -q c1
printf 'skills/a/* E1 E3\n\n\nskills/b/SKILL.md E3 E5\nAGENTS.global.md E4 E1' > "$R/evals/scenario-map"
guard --base base
assert_rc "AC2.2 blank lines in the map: exit 0" 0
has_line "AC2.2 blank lines and no final newline: the last map line is read too (E1,E3,E5,E4)" "bash evals/run-evals.sh --harness claude --scenarios E1,E3,E5,E4 --max-cost 3"
printf 'skills/zzz/* E5\n\nAGENTS.global.md E4 E1' > "$R/evals/scenario-map"
guard --base base
has_line "AC2.2 the last line has no newline and is the only match: E4,E1" "bash evals/run-evals.sh --harness claude --scenarios E4,E1 --max-cost 3"
printf '\nskills/b/SKILL.md E3 E5\n' > "$R/evals/scenario-map"
guard --base base
has_line "AC2.2 a leading blank line is ignored" "bash evals/run-evals.sh --harness claude --scenarios E3,E5 --max-cost 3"
git_c checkout -q -- evals/scenario-map

echo "AC2.2 the guard never runs anything (D1)"
assert_eq "AC2.2 the recording run-evals.sh and the fake harnesses were never called" "" "$(cat "$CALLS")"
t_summary
