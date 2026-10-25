#!/usr/bin/env bash
# Shared harness helpers of evals/run-evals.sh (v0.26.0). Source it; do not execute it.
# It is also the interface lane O's evals/run-outcome.sh sources: renaming a pbh_* function breaks run-outcome.sh.
# No top-level side effects, set -u safe, no shell option changed, bash 3.2 compatible; every function starts with pbh_.
#   pbh_preset_cmd HARNESS            the adapter string of a preset (claude, codex, opencode), run as
#                                     bash -c "$s" adapter <workdir> <prompt-file>; returns 1 for any other name
#   pbh_model_args HARNESS MODEL      the model flag, one word per line: claude --model M, codex -m M, opencode --model M
#                                     (DECISION[D7], flag not verified); nothing when MODEL is empty
#   pbh_arm_supported HARNESS ARM     0 when ARM (with, without, both) can run on HARNESS; else prints the reason, returns 2
#   pbh_arm_settings FILE ARM HOME REPO
#                                     writes the Claude Code --settings JSON of ARM to FILE and prints the number of
#                                     non-playbook lines of HOME/.claude/CLAUDE.md that the without arm also drops (0 for with)
#   pbh_check_key NAME                NAME without a trailing " (...)" group that carries a run-specific value (DECISION[D8])
#   pbh_phys PATH                     PATH with its symbolic links resolved (PATH itself when its directory does not exist)
#   pbh_json_str TEXT                 TEXT as a JSON string literal (control characters dropped)

# stream-json (needs --verbose with -p) puts tool calls such as the Skill call into the transcript;
# flags as listed by `claude --help` in Claude Code 2.1.295. DECISION[D3]: the claude and codex presets are best guesses.
pbh_preset_cmd() {
  case "$1" in
    claude)   printf '%s' 'cd "$1" && claude -p --output-format stream-json --verbose "$(cat "$2")"' ;;
    codex)    printf '%s' 'cd "$1" && codex exec "$(cat "$2")"' ;;
    opencode) printf '%s' 'cd "$1" && opencode run --auto "$(cat "$2")"' ;;
    *) return 1 ;;
  esac
}

pbh_model_args() {
  [ -n "${2:-}" ] || return 0
  case "$1" in
    codex) printf '%s\n' -m "$2" ;;                  # skills/playbook-tdd/references/harnesses.md: codex exec -m <model>
    claude | opencode) printf '%s\n' --model "$2" ;;
  esac
  return 0
}

# DECISION[D6]: only Claude Code (settings file) and --cmd (adapter-defined) can run the without arm in v0.26.0
pbh_arm_supported() {
  [ "$2" = with ] && return 0
  case "$1" in
    codex)
      printf '%s\n' 'no documented per-run switch removes ~/.codex/AGENTS.md or the playbook skills without editing ~/.codex/config.toml'
      return 2 ;;
    opencode)
      printf '%s\n' 'no documented per-run switch removes ~/.config/opencode/AGENTS.md'
      return 2 ;;
  esac
  return 0
}

pbh_json_str() {
  printf '"%s"' "$(printf '%s' "$1" | LC_ALL=C tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g')"
}

pbh_phys() {
  local p="$1" t d n=0
  while [ -L "$p" ] && [ "$n" -lt 40 ]; do
    t="$(readlink "$p")" || break
    case "$t" in /*) p="$t" ;; *) p="$(dirname "$p")/$t" ;; esac
    n=$((n + 1))
  done
  d="$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)" || { printf '%s\n' "$1"; return 0; }
  printf '%s/%s\n' "${d%/}" "$(basename "$p")"
}

# the lines of FILE outside the <!-- BEGIN agent-playbook ... <!-- END agent-playbook block (blank lines not counted)
pbh_dropped_lines() {
  [ -f "$1" ] || { printf '0\n'; return 0; }
  awk 'index($0, "<!-- BEGIN agent-playbook") == 1 { b = 1; next }
    b && index($0, "<!-- END agent-playbook") == 1 { b = 0; next }
    !b && NF { n++ }
    END { print n + 0 }' "$1"
}

# without: claudeMdExcludes (the user CLAUDE.md, also by its physical path), skillOverrides "off" and Skill deny rules for
# every skill of the runner's repo (skills/*/SKILL.md) and every playbook-* entry of HOME/.claude/skills, Read deny rules for
# ~/.agents and the playbook skills (a linked skill also by its physical path), autoMemoryEnabled false.
# with: autoMemoryEnabled false only (DECISION[D11]). DECISION[D2]: the whole user CLAUDE.md is excluded.
pbh_arm_settings() {
  local file="$1" arm="$2" home="$3" repo="$4" cm phys ex names="" n f p ov="" dn="" sep=""
  if [ "$arm" = with ]; then
    printf '{"autoMemoryEnabled": false}\n' > "$file" || return 1
    printf '0\n'
    return 0
  fi
  cm="$home/.claude/CLAUDE.md"
  ex="$(pbh_json_str "$cm")"
  phys="$(pbh_phys "$cm")"
  [ "$phys" = "$cm" ] || ex="$ex, $(pbh_json_str "$phys")"
  for f in "$repo"/skills/*/SKILL.md; do
    [ -f "$f" ] || continue
    n="${f%/SKILL.md}"
    names="$names${n##*/}
"
  done
  for p in "$home"/.claude/skills/playbook-*; do
    { [ -e "$p" ] || [ -L "$p" ]; } || continue
    names="$names${p##*/}
"
    if [ -L "$p" ]; then dn="$dn, $(pbh_json_str "Read(/$(pbh_phys "$p")/**)")"; fi
  done
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    ov="$ov$sep$(pbh_json_str "$n"): \"off\""
    dn="$dn, $(pbh_json_str "Skill($n)"), $(pbh_json_str "Skill($n *)"), $(pbh_json_str "Skill(skill:$n)")"
    sep=", "
  done <<EOF
$(printf '%s' "$names" | LC_ALL=C sort -u)
EOF
  {
    printf '{\n  "claudeMdExcludes": [%s],\n' "$ex"
    printf '  "skillOverrides": {%s},\n' "$ov"
    printf '  "permissions": {"deny": ["Read(~/.agents/**)", "Read(~/.claude/skills/playbook-*/**)"%s]},\n' "$dn"
    printf '  "autoMemoryEnabled": false\n}\n'
  } > "$file" || return 1
  pbh_dropped_lines "$cm"
}

pbh_check_key() {
  local n="$1" g
  case "$n" in
    *" ("*")")
      g="${n##* (}"
      g="${g%)}"
      case "$g" in *")"*) ;; *=* | *": "* | *"bucket "* | *"first one after"*) printf '%s\n' "${n% (*}"; return 0 ;; esac ;;
  esac
  printf '%s\n' "$n"
}
