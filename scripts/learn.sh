#!/usr/bin/env bash
# Project-local learnings file (default <project>/.agents/LEARNINGS.md).
#   learn.sh init [--link-agents] [--link-claude]
#   learn.sh add --title T --rule R --why W --evidence E --source user|failure|review [--scope S]
#   learn.sh retire L-0001 --reason R
#   learn.sh check
# Exit: 0 ok | 1 check failed | 2 usage/validation | 3 environment | 4 duplicate | 5 at capacity
# Env: LEARN_MAX_ENTRIES (default 40 active), LEARN_MAX_LINES (default 250), PLAYBOOK_DATE (tests)
set -u
. "$(dirname "$0")/lib.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(pb_root_dir)"
REL="$(pb_conf_get learnings_path ".agents/LEARNINGS.md")"
FILE="$ROOT/$REL"
MAX_ENTRIES="${LEARN_MAX_ENTRIES:-$(pb_conf_get learn_max_entries 40)}"
MAX_LINES="${LEARN_MAX_LINES:-$(pb_conf_get learn_max_lines 250)}"
TODAY="${PLAYBOOK_DATE:-$(date -u +%F)}"
SECRET_RE='sk-[A-Za-z0-9]{16,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{12,}|(password|passwd|secret|token|api[_-]?key)[[:space:]]*[=:]'

active_count() { grep -c '^- Status: active' "$FILE" 2>/dev/null || true; }

cmd="${1:-}"
[ $# -gt 0 ] && shift

case "$cmd" in
  init)
    link_agents=0; link_claude=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --link-agents) link_agents=1 ;;
        --link-claude) link_claude=1 ;;
        *) pb_die "unknown option: $1" 2 ;;
      esac
      shift
    done
    mkdir -p "$(dirname "$FILE")" || pb_die "cannot create $(dirname "$FILE")" 3
    if [ ! -f "$FILE" ]; then
      tpl="$HERE/../templates/LEARNINGS.md"
      [ -f "$tpl" ] || pb_die "template not found: $tpl" 3
      cp "$tpl" "$FILE"
      echo "created $REL"
    else
      echo "exists  $REL"
    fi
    gi="$ROOT/.gitignore"
    if ! grep -qxF '.agents/handoff/' "$gi" 2>/dev/null; then
      if [ -s "$gi" ] && [ -n "$(tail -c1 "$gi")" ]; then printf '\n' >> "$gi"; fi
      printf '.agents/handoff/\n' >> "$gi"
      echo "added   .agents/handoff/ to .gitignore"
    fi
    if [ "$link_agents" -eq 1 ]; then
      ag="$ROOT/AGENTS.md"
      if grep -q 'agent-playbook:learnings' "$ag" 2>/dev/null; then
        echo "exists  learnings pointer in AGENTS.md"
      else
        if [ -s "$ag" ]; then printf '\n' >> "$ag"; fi
        {
          printf '<!-- agent-playbook:learnings -->\n'
          printf '## Agent learnings\n'
          printf 'At the start of a task, read `%s` (project-specific lessons).\n' "$REL"
          printf 'Do not edit it by hand: propose entries through the `playbook-learn` skill.\n'
          printf '<!-- /agent-playbook-learnings -->\n'
        } >> "$ag"
        echo "added   learnings pointer to AGENTS.md"
      fi
    fi
    if [ "$link_claude" -eq 1 ] && [ ! -e "$ROOT/CLAUDE.md" ]; then
      printf '@AGENTS.md\n' > "$ROOT/CLAUDE.md"
      echo "created CLAUDE.md (imports AGENTS.md)"
    fi
    ;;

  add)
    title=""; rule=""; why=""; evidence=""; source=""; scope="project-wide"
    while [ $# -gt 0 ]; do
      [ $# -ge 2 ] || pb_die "option $1 needs a value" 2
      case "$1" in
        --title) title="$2" ;;
        --rule) rule="$2" ;;
        --why) why="$2" ;;
        --evidence) evidence="$2" ;;
        --source) source="$2" ;;
        --scope) scope="$2" ;;
        *) pb_die "unknown option: $1" 2 ;;
      esac
      shift 2
    done
    [ -f "$FILE" ] || pb_die "$REL not found; run: learn.sh init" 2
    for pair in "title:$title" "rule:$rule" "why:$why" "evidence:$evidence" "source:$source"; do
      [ -n "${pair#*:}" ] || pb_die "--${pair%%:*} is required (an entry without evidence is not a learning)" 2
    done
    case "$source" in user|failure|review) ;; *) pb_die "--source must be user|failure|review (web or tool output is not a valid source)" 2 ;; esac
    for pair in "title:$title:80" "rule:$rule:300" "why:$why:300" "evidence:$evidence:400" "scope:$scope:120"; do
      name="${pair%%:*}"; rest="${pair#*:}"; val="${rest%:*}"; max="${rest##*:}"
      case "$val" in *"
"*) pb_die "--$name must be a single line" 2 ;; esac
      [ "${#val}" -le "$max" ] || pb_die "--$name is too long (${#val} > $max chars): keep entries short" 2
      if printf '%s' "$val" | grep -Eiq -- "$SECRET_RE"; then
        pb_die "--$name looks like it contains a secret; never record secrets" 2
      fi
    done
    norm="$(printf '%s' "$rule" | tr '[:upper:]' '[:lower:]')"
    if grep '^- Rule: ' "$FILE" | sed 's/^- Rule: //' | tr '[:upper:]' '[:lower:]' | grep -qxF -- "$norm"; then
      echo "duplicate: an entry with the same rule already exists" >&2
      exit 4
    fi
    if [ "$(active_count)" -ge "$MAX_ENTRIES" ]; then
      echo "at capacity ($MAX_ENTRIES active entries): merge or retire entries first (learn.sh retire L-NNNN --reason ...)" >&2
      exit 5
    fi
    last="$(grep -E '^### L-[0-9]{4} ' "$FILE" | sed -E 's/^### L-([0-9]{4}) .*/\1/' | sort -n | tail -n 1)"
    id="$(printf 'L-%04d' $((10#${last:-0} + 1)))"
    {
      printf '\n### %s · %s · %s\n' "$id" "$TODAY" "$title"
      printf -- '- Status: active\n'
      printf -- '- Rule: %s\n' "$rule"
      printf -- '- Why: %s\n' "$why"
      printf -- '- Evidence: %s\n' "$evidence"
      printf -- '- Source: %s\n' "$source"
      printf -- '- Scope: %s\n' "$scope"
    } >> "$FILE"
    echo "added $id to $REL"
    ;;

  retire)
    id="${1:-}"; [ $# -gt 0 ] && shift
    reason=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --reason) [ $# -ge 2 ] || pb_die "--reason needs a value" 2; reason="$2"; shift ;;
        *) pb_die "unknown option: $1" 2 ;;
      esac
      shift
    done
    [ -f "$FILE" ] || pb_die "$REL not found" 2
    [ -n "$reason" ] || pb_die "--reason is required" 2
    grep -q "^### $id · " "$FILE" || pb_die "no such entry: $id" 2
    tmp="$(mktemp "${TMPDIR:-/tmp}/pblearn.XXXXXX")" || pb_die "mktemp failed" 3
    ID="$id" R="$reason" D="$TODAY" awk '
      index($0, "### " ENVIRON["ID"] " · ") == 1 { inside = 1; print; next }
      /^### / { inside = 0 }
      inside && /^- Status: / { print "- Status: retired (" ENVIRON["R"] "; " ENVIRON["D"] ")"; inside = 0; next }
      { print }
    ' "$FILE" > "$tmp" && cat "$tmp" > "$FILE"
    rm -f "$tmp"
    echo "retired $id"
    ;;

  check)
    [ -f "$FILE" ] || pb_die "$REL not found" 2
    problems=0
    lines="$(wc -l < "$FILE" | tr -d ' ')"
    if [ "$lines" -gt "$MAX_LINES" ]; then
      echo "problem: $lines lines exceeds the $MAX_LINES-line budget (merge/retire entries)"
      problems=$((problems + 1))
    fi
    bad_headings="$(grep '^### ' "$FILE" | grep -Ev '^### L-[0-9]{4} · [0-9]{4}-[0-9]{2}-[0-9]{2} · .+' || true)"
    if [ -n "$bad_headings" ]; then
      printf 'problem: malformed entry heading(s):\n%s\n' "$bad_headings"
      problems=$((problems + 1))
    fi
    missing="$(awk '
      function flush() { if (head != "" && (!st || !ru || !wh || !ev || !so || !sc)) print "  " head }
      /^### / { flush(); head = $0; st = ru = wh = ev = so = sc = 0; next }
      /^- Status: / { st = 1 } /^- Rule: / { ru = 1 } /^- Why: / { wh = 1 }
      /^- Evidence: / { ev = 1 } /^- Source: / { so = 1 } /^- Scope: / { sc = 1 }
      END { flush() }
    ' "$FILE")"
    if [ -n "$missing" ]; then
      printf 'problem: entries missing a required field (Status/Rule/Why/Evidence/Source/Scope):\n%s\n' "$missing"
      problems=$((problems + 1))
    fi
    act="$(active_count)"
    ret="$(grep -c '^- Status: retired' "$FILE" || true)"
    if [ "$act" -gt "$MAX_ENTRIES" ]; then
      echo "problem: $act active entries exceeds the cap of $MAX_ENTRIES"
      problems=$((problems + 1))
    fi
    echo "learnings: $act active, $ret retired, $lines lines ($REL)"
    [ "$problems" -eq 0 ] || exit 1
    ;;

  *)
    pb_die "usage: learn.sh init|add|retire|check" 2
    ;;
esac
