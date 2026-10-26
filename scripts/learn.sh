#!/usr/bin/env bash
# Project-local learnings file (default <project>/.agents/LEARNINGS.md).
#   learn.sh init [--link-agents] [--link-claude]
#   learn.sh add --title T --rule R --why W --evidence E --source user|failure|review [--scope S]
#                [--role tester|implementer|reviewer|all]   (default all; written as "- Role:" after "- Scope:")
#   learn.sh retire L-0001 --reason R
#   learn.sh trust [DIR]|untrust [DIR]|trusted   (the projects whose learnings the SessionStart hook injects: the lines
#                              of <home>/.agents/trusted-projects; DIR defaults to the project root; the USER runs these)
#   learn.sh check
#   learn.sh checklist ROLE   (ROLE = tester|implementer|reviewer: the active entries for ROLE and for all,
#                              as "- [ ] <rule> (L-000N, scope: <scope>)"; read-only)
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

# Trust-file path matching (v0.29.0 slice T). Same helpers in learn.sh and learnings-hook.sh: keep both copies equal.
CYG=""; command -v cygpath >/dev/null 2>&1 && CYG=1
# pb_resolve PATH -> RES: absolute PATH with a Windows form turned into a POSIX one (cygpath -u when present), `.`/`..`
# folded, symlinks resolved when the directory exists; 1 when PATH is not absolute. WIN=1 for a drive-letter form.
pb_resolve() {
  local p="$1" d v seg out="" drv="" IFS
  p="${p%$'\r'}"; WIN=0
  case "$p" in [A-Za-z]:[/\\]* | [A-Za-z]:) WIN=1; p="$(printf '%s' "$p" | tr '\\' '/')" ;; esac
  if [ -n "$CYG" ]; then
    case "$p" in
      /*) d="$(cygpath -u "$p" 2>/dev/null)" && [ -n "$d" ] && p="$d" ;;
      [A-Za-z]:*)   # keep the drive: the POSIX form is used only when it maps back to the same drive letter
        d="$(cygpath -u "$p" 2>/dev/null)" && [ -n "$d" ] && v="$(cygpath -m "$d" 2>/dev/null)" &&
          [ "$(printf '%s' "${v%%:*}" | tr 'A-Z' 'a-z')" = "$(printf '%s' "${p%%:*}" | tr 'A-Z' 'a-z')" ] && p="$d" ;;
    esac
  fi
  case "$p" in /* | [A-Za-z]:*) ;; *) return 1 ;; esac
  if [ -d "$p" ] && d="$(cd "$p" 2>/dev/null && pwd -P)" && [ -n "$d" ]; then RES="$d"; return 0; fi
  case "$p" in [A-Za-z]:*) drv="${p%%:*}:"; p="${p#?:}" ;; esac
  IFS=/; set -f
  for seg in $p; do
    case "$seg" in "" | .) ;; ..) out="${out%/*}" ;; *) out="$out/$seg" ;; esac
  done
  set +f
  RES="$drv${out:-/}"
}
# pb_key PATH -> KEY (stdout): the comparison form of PATH; equal keys are the same project. 1 when not absolute.
pb_key() {
  local k
  pb_resolve "$1" || return 1
  k="$RES"
  [ -n "$CYG" ] && k="$(cygpath -m "$k" 2>/dev/null || printf '%s' "$k")"
  if [ -n "$CYG" ] || [ "$WIN" = 1 ]; then k="$(printf '%s' "$k" | tr 'A-Z' 'a-z')"; fi
  while :; do case "$k" in ?*/) k="${k%/}" ;; *) break ;; esac; done
  printf '%s' "$k"
}

TRUSTF="$(pb_home)/.agents/trusted-projects"
# trust_dir DIR -> DIR absolute (a relative DIR is taken from the cwd)
trust_dir() { case "$1" in /* | [A-Za-z]:*) printf '%s' "$1" ;; *) printf '%s/%s' "$PWD" "$1" ;; esac; }
# trust_lines: the entries of the trust file (comments and blank lines left out), one per line
trust_lines() { [ -f "$TRUSTF" ] || return 0; grep -v '^[[:space:]]*\(#.*\)\{0,1\}$' "$TRUSTF" | tr -d '\r' || true; }

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
    title=""; rule=""; why=""; evidence=""; source=""; scope="project-wide"; role="all"
    while [ $# -gt 0 ]; do
      [ $# -ge 2 ] || pb_die "option $1 needs a value" 2
      case "$1" in
        --title) title="$2" ;;
        --rule) rule="$2" ;;
        --why) why="$2" ;;
        --evidence) evidence="$2" ;;
        --source) source="$2" ;;
        --scope) scope="$2" ;;
        --role) role="$2" ;;
        *) pb_die "unknown option: $1" 2 ;;
      esac
      shift 2
    done
    [ -f "$FILE" ] || pb_die "$REL not found; run: learn.sh init" 2
    for pair in "title:$title" "rule:$rule" "why:$why" "evidence:$evidence" "source:$source"; do
      [ -n "${pair#*:}" ] || pb_die "--${pair%%:*} is required (an entry without evidence is not a learning)" 2
    done
    case "$role" in tester|implementer|reviewer|all) ;; *) pb_die "--role must be tester|implementer|reviewer|all" 2 ;; esac
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
      printf -- '- Role: %s\n' "$role"
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

  trust | untrust)
    [ $# -le 1 ] || pb_die "usage: learn.sh $cmd [DIR]" 2
    dir="$(trust_dir "${1:-$ROOT}")"
    if [ "$cmd" = trust ]; then
      pb_resolve "$dir" && [ -d "$RES" ] || pb_die "no such directory: ${1:-$ROOT}" 2
      store="$RES"
      [ -n "$CYG" ] && store="$(cygpath -m "$RES" 2>/dev/null || printf '%s' "$RES")"
    else
      store="$dir"
    fi
    want="$(pb_key "$dir")" || pb_die "not an absolute path: $dir" 2
    found=0
    while IFS= read -r tl; do
      tk="$(pb_key "$tl")" || continue
      if [ "$tk" = "$want" ]; then found=$((found + 1)); fi
    done <<EOF
$(trust_lines)
EOF
    if [ "$cmd" = trust ]; then
      if [ "$found" -gt 0 ]; then echo "already trusted: $store"; exit 0; fi
      mkdir -p "$(dirname "$TRUSTF")" || pb_die "cannot create $(dirname "$TRUSTF")" 3
      if [ -s "$TRUSTF" ] && [ -n "$(tail -c1 "$TRUSTF")" ]; then printf '\n' >> "$TRUSTF"; fi
      printf '%s\n' "$store" >> "$TRUSTF" || pb_die "cannot write $TRUSTF" 3
      echo "trusted: $store"
    else
      if [ "$found" -eq 0 ]; then echo "not trusted, nothing to remove: $store"; exit 0; fi
      tmp="$(mktemp "${TMPDIR:-/tmp}/pbtrust.XXXXXX")" || pb_die "mktemp failed" 3
      while IFS= read -r tl || [ -n "$tl" ]; do
        t2="${tl%$'\r'}"
        case "$t2" in "" | "#"*) printf '%s\n' "$tl" >> "$tmp"; continue ;; esac
        if tk="$(pb_key "$t2")" && [ "$tk" = "$want" ]; then continue; fi
        printf '%s\n' "$tl" >> "$tmp"
      done < "$TRUSTF"
      cat "$tmp" > "$TRUSTF"
      rm -f "$tmp"
      echo "removed $found trust entr$([ "$found" -eq 1 ] && echo y || echo ies) for $store (untrusted)"
    fi
    ;;

  trusted)
    items="$(trust_lines)"
    if [ -n "$items" ]; then printf '%s\n' "$items"; else echo "no trusted projects"; fi
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
    badrole="$(grep '^- Role: ' "$FILE" | sed 's/^- Role: //' | grep -Ev '^(tester|implementer|reviewer|all)$' || true)"
    if [ -n "$badrole" ]; then
      printf 'problem: unknown Role value(s) (use tester, implementer, reviewer or all):\n%s\n' "$badrole"
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

  checklist)
    crole="${1:-}"
    case "$crole" in tester|implementer|reviewer) ;; *) pb_die "usage: learn.sh checklist tester|implementer|reviewer" 2 ;; esac
    [ -f "$FILE" ] || pb_die "$REL not found" 2
    items="$(ROLE="$crole" awk '
      function flush() {
        if (id != "" && active && rule != "" && (role == "" || role == "all" || role == ENVIRON["ROLE"]))
          printf "- [ ] %s (%s, scope: %s)\n", rule, id, scope
      }
      /^### L-[0-9][0-9][0-9][0-9] / { flush(); id = $2; active = 0; rule = ""; scope = "project-wide"; role = ""; next }
      /^### / { flush(); id = ""; next }
      /^- Status: active/ { active = 1 }
      /^- Rule: / { rule = substr($0, 9) }
      /^- Scope: / { scope = substr($0, 10) }
      /^- Role: / { role = substr($0, 9) }
      END { flush() }
    ' "$FILE")"
    if [ -n "$items" ]; then printf '%s\n' "$items"; else echo "no learnings for $crole"; fi
    ;;
  *)
    pb_die "usage: learn.sh init|add|retire|check|checklist|trust|untrust|trusted" 2
    ;;
esac
