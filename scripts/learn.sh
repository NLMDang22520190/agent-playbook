#!/usr/bin/env bash
# Project-local learnings file (default <project>/.agents/LEARNINGS.md).
#   learn.sh init [--link-agents] [--link-claude]
#   learn.sh add --title T --rule R --why W --evidence E --source user|failure|review [--scope S]
#                [--role tester|implementer|reviewer|all]   (default all; written as "- Role:" after "- Scope:")
#   learn.sh retire L-0001 --reason R
#   learn.sh trust [DIR]|untrust [DIR]|trusted   (the projects whose learnings the SessionStart hook injects: the lines
#                              of <home>/.agents/trusted-projects; DIR defaults to the project root; the USER runs these)
#   learn.sh check   (problems, then a summary line ending "; entry lines: A active, R retired", then a warning line
#                              when the hook injects only some of the active entries; the exit code ignores the warning)
#   learn.sh checklist ROLE [--dates]   (ROLE = tester|implementer|reviewer: the active entries for ROLE and for all,
#                              as "- [ ] <rule> (L-000N, scope: <scope>)"; --dates appends ", verified D" or ", added D"
#                              inside the parentheses; read-only)
#   learn.sh verify L-0001   (the USER confirmed the active entry still holds: write "- Verified: <today>" after its
#                              "- Role:" line, or replace that line; `stale` then ages the entry from that date)
#   learn.sh stale [--days N] [--fail]   (active entries older than N days (default 180) and/or whose path-like scope
#                              matches no tracked file, one line each, then a summary; read-only; --fail: exit 1 when any listed)
#   learn.sh candidate add --title T --rule R --why W --evidence E --source user|failure|review [--scope S] [--role ROLE]
#                              (queue an unapproved proposal in .agents/handoff/learn-candidates.md; never touches LEARNINGS.md)
#   learn.sh candidate list [--all]   (pending candidates, two lines each, then "candidates: P pending, T total"; read-only)
#   learn.sh candidate promote C-NNNN   (the USER approved it: write it as an entry through the same checks as add, mark it promoted)
#   learn.sh candidate drop C-NNNN --reason R   (mark a candidate dropped; the reason is never copied from candidate text)
# Exit: 0 ok | 1 check failed | 2 usage/validation | 3 environment | 4 duplicate | 5 at capacity
# Env: LEARN_MAX_ENTRIES (default 40 active), LEARN_MAX_LINES (default 250), PLAYBOOK_DATE (tests), LEARN_MAX_CANDIDATES (default 30 pending),
#      LEARN_LOCK_TRIES (default 100), learn_stale_days (conf, default 180)
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

# S4-BEGIN (shared entry functions: used by add and by candidate)
# entry_parse_opts "$@": the flag pairs of add/candidate add -> title rule why evidence source scope role
entry_parse_opts() {
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
}
# entry_validate: required fields, role, source, one line, length, secrets (uses the globals above; dies with 2)
entry_validate() {
  local pair name rest val max
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
}
# rule_in_file FILE RULE: 0 when a "- Rule: " line of FILE equals RULE (case-insensitive, any status); 1 otherwise
rule_in_file() {
  local norm
  norm="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
  grep '^- Rule: ' "$1" 2>/dev/null | sed 's/^- Rule: //' | tr -d '\r' | tr '[:upper:]' '[:lower:]' | grep -qxF -- "$norm"
}
# next_id PREFIX FILE: sets NEXT_ID to PREFIX-NNNN (largest heading number + 1); 1 when that would pass 9999
next_id() {
  local last n
  last="$(grep -E "^### $1-[0-9]{4} " "$2" 2>/dev/null | sed -E "s/^### $1-([0-9]{4}) .*/\1/" | sort -n | tail -n 1)"
  n=$((10#${last:-0} + 1))
  [ "$n" -le 9999 ] || return 1
  NEXT_ID="$(printf '%s-%04d' "$1" "$n")"
}
# emit_entry ID STATUS: one entry block on stdout (the single place that defines the entry format)
emit_entry() {
  printf '\n### %s · %s · %s\n' "$1" "$TODAY" "$title"
  printf -- '- Status: %s\n' "$2"
  printf -- '- Rule: %s\n' "$rule"
  printf -- '- Why: %s\n' "$why"
  printf -- '- Evidence: %s\n' "$evidence"
  printf -- '- Source: %s\n' "$source"
  printf -- '- Scope: %s\n' "$scope"
  printf -- '- Role: %s\n' "$role"
}
# S4-END

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
    entry_parse_opts "$@"
    [ -f "$FILE" ] || pb_die "$REL not found; run: learn.sh init" 2
    entry_validate
    if rule_in_file "$FILE" "$rule"; then
      echo "duplicate: an entry with the same rule already exists" >&2
      exit 4
    fi
    if [ "$(active_count)" -ge "$MAX_ENTRIES" ]; then
      echo "at capacity ($MAX_ENTRIES active entries): merge or retire entries first (learn.sh retire L-NNNN --reason ...)" >&2
      exit 5
    fi
    next_id L "$FILE" || pb_die "entry ids exhausted: retire or merge entries by hand" 5
    emit_entry "$NEXT_ID" active >> "$FILE"
    echo "added $NEXT_ID to $REL"
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

  stale)
    # Read-only. Differences from other commands, on purpose: an entry is active when its FIRST "- Status:" line starts
    # with "- Status: active" (so A can differ from the per-line "N active" of `check`); the scope is taken from the FIRST
    # "- Scope:" line of the entry (`checklist` takes the last one).
    sdays=""; sfail=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --fail) sfail=1 ;;
        --days)
          [ $# -ge 2 ] || pb_die "--days needs a value (a positive integer)" 2
          sdays="$2"
          case "$sdays" in "" | *[!0-9]* | 0*) pb_die "--days must be a positive integer without sign or leading zero: $sdays" 2 ;; esac
          [ "${#sdays}" -le 6 ] || pb_die "--days is too large: $sdays" 2
          shift ;;
        *) pb_die "unknown option: $1 (usage: learn.sh stale [--days N] [--fail])" 2 ;;
      esac
      shift
    done
    [ -f "$FILE" ] || pb_die "$REL not found" 2
    if [ -z "$sdays" ]; then
      sdays="$(pb_conf_get learn_stale_days 180)"
      case "$sdays" in "" | *[!0-9]* | 0*) pb_die "invalid learn_stale_days: $sdays (a positive integer)" 2 ;; esac
      [ "${#sdays}" -le 6 ] || pb_die "invalid learn_stale_days: $sdays (too large)" 2
    fi
    # one record per active entry: AGE<TAB>VDATE<TAB>SCOPE<TAB>HEADING (AGE is "-" when no usable date; VDATE is the date of
    # the FIRST "- Verified:" line when valid, else "-"; a valid Verified date, not the heading date, then sets AGE)
    srecs="$(TODAY_S="$TODAY" awk '
      function dnum(s,   y, m, d, dim, leap, era, yoe, doy) {
        if (s !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return -1
        y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
        if (m < 1 || m > 12 || d < 1) return -1
        leap = ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0)
        dim = (m == 2) ? (leap ? 29 : 28) : ((m == 4 || m == 6 || m == 9 || m == 11) ? 30 : 31)
        if (d > dim) return -1
        if (m <= 2) y--
        y += 400
        era = int(y / 400); yoe = y - era * 400
        doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
        return era * 146097 + yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
      }
      function flush() {
        if (inent && active) printf "%s\t%s\t%s\t%s\n", age, vdate, scope, rest
        inent = 0
      }
      BEGIN {
        sep = " · "; sl = length(sep)
        tdays = dnum(ENVIRON["TODAY_S"])
        if (tdays < 0) { bad = 1; exit 3 }
      }
      { sub(/\r$/, "") }
      /^### L-[0-9][0-9][0-9][0-9] / {
        flush(); inent = 1; active = 0; seen = 0; hasscope = 0; vseen = 0; vdate = "-"; scope = "project-wide"; age = "-"
        rest = substr($0, 5)
        if (substr(rest, 7, sl) == sep && substr(rest, 17 + sl, sl) == sep && length(rest) > 16 + 2 * sl) {
          n = dnum(substr(rest, 7 + sl, 10))
          if (n >= 0) age = tdays - n
        }
        next
      }
      /^### / { flush(); next }
      inent && !seen && /^- Status:/ { seen = 1; if ($0 ~ /^- Status: active/) active = 1; next }
      inent && !vseen && index($0, "- Verified:") == 1 {
        vseen = 1
        if ($0 ~ /^- Verified: [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) {
          n = dnum(substr($0, 13))
          if (n >= 0) { vdate = substr($0, 13); age = tdays - n }
        }
        next
      }
      inent && !hasscope && /^- Scope:/ {
        hasscope = 1
        if (substr($0, 1, 9) == "- Scope: " && length($0) > 9) { scope = substr($0, 10); gsub(/\t/, " ", scope) }
        next
      }
      END { if (bad) exit 3; flush() }
    ' "$FILE")" || pb_die "invalid PLAYBOOK_DATE: $TODAY (expected a real date, YYYY-MM-DD)" 2
    srepo=0
    if [ "$( (unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE; git -C "$ROOT" rev-parse --is-inside-work-tree 2>/dev/null) )" = true ]; then srepo=1; fi
    sout=""; sk=0; sa=0
    if [ -n "$srecs" ]; then
      while IFS="$(printf '\t')" read -r sage svdate sscope shead; do
        sa=$((sa + 1))
        sreason=""
        if [ "$sage" != "-" ] && [ "$sage" -gt "$sdays" ]; then
          if [ "$svdate" != "-" ]; then sreason="$sage days since verified $svdate"; else sreason="$sage days old"; fi
        fi
        if [ "$srepo" -eq 1 ]; then
          slike=1
          case "$sscope" in
            *[[:space:]]* | *\\* | :* | /* | [A-Za-z]:*) slike=0 ;;
            .. | ../* | */.. | */../*) slike=0 ;;
            */* | *\** | *.*) ;;
            *) slike=0 ;;
          esac
          if [ "$slike" -eq 1 ]; then
            sls="$( (unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE; git -C "$ROOT" ls-files -- "$sscope" 2>/dev/null) )" && src=0 || src=1
            if [ "$src" -eq 0 ] && [ -z "$sls" ]; then
              sreason="${sreason:+$sreason; }scope matches no tracked file"
            fi
          fi
        fi
        if [ -n "$sreason" ]; then
          sk=$((sk + 1))
          sout="$sout$shead: $sreason
"
        fi
      done <<EOF
$srecs
EOF
    fi
    [ -z "$sout" ] || printf '%s' "$sout"
    [ "$srepo" -eq 1 ] || echo "scope check skipped: not a git repository"
    echo "stale: $sk of $sa active entries listed (older than $sdays days)"
    if [ "$sfail" -eq 1 ] && [ "$sk" -gt 0 ]; then exit 1; fi
    ;;

  candidate)
    # S4-BEGIN (candidate queue; candidate text is data: never expanded, never run)
    CAND_REL=".agents/handoff/learn-candidates.md"
    CFILE="$ROOT/$CAND_REL"
    CLOCK="$CFILE.lock"
    csub="${1:-}"
    [ $# -gt 0 ] && shift
    LOCKED=0; CTMP=""
    cand_cleanup() {
      if [ -n "$CTMP" ]; then rm -f "$CTMP"; fi
      if [ "$LOCKED" = 1 ]; then rmdir "$CLOCK" 2>/dev/null || true; LOCKED=0; fi
    }
    trap cand_cleanup EXIT
    trap 'exit 143' TERM
    trap 'exit 130' INT
    # cand_tries / cand_max: validate the environment knobs (dies with 2)
    cand_tries() {
      CTRIES="${LEARN_LOCK_TRIES:-100}"
      case "$CTRIES" in
        "" | *[!0-9]*) pb_die "invalid LEARN_LOCK_TRIES: $CTRIES (0..9999)" 2 ;;
      esac
      [ "${#CTRIES}" -le 4 ] || pb_die "invalid LEARN_LOCK_TRIES: $CTRIES (0..9999)" 2
    }
    cand_max() {
      CMAX="${LEARN_MAX_CANDIDATES:-30}"
      case "$CMAX" in
        "" | 0* | *[!0-9]*) pb_die "invalid LEARN_MAX_CANDIDATES: $CMAX (a positive integer)" 2 ;;
      esac
      [ "${#CMAX}" -le 6 ] || pb_die "invalid LEARN_MAX_CANDIDATES: $CMAX (a positive integer)" 2
    }
    cand_lock() {
      local i=0
      while :; do
        if mkdir "$CLOCK" 2>/dev/null; then LOCKED=1; return 0; fi
        # mkdir failed: a missing or read-only parent can never succeed (exit 3 at once); anything else is
        # contention, retried. The lock dir itself is not tested: its holder may have just released it.
        { [ -d "${CFILE%/*}" ] && [ -w "${CFILE%/*}" ]; } || pb_die "cannot create lock: $CAND_REL.lock" 3
        # a lock path that exists but is not a directory can never be taken either
        { [ ! -e "$CLOCK" ] || [ -d "$CLOCK" ]; } || pb_die "cannot create lock: $CAND_REL.lock" 3
        [ "$i" -lt "$CTRIES" ] || pb_die "candidate file is locked: $CAND_REL.lock (remove it if no learn.sh is running)" 3
        i=$((i + 1))
        sleep 0.1 2>/dev/null || sleep 1
      done
    }
    # cand_ctrl_check: the five text fields must not hold control characters (dies with 2)
    cand_ctrl_check() {
      local pair name val
      for pair in "title:$title" "rule:$rule" "why:$why" "evidence:$evidence" "scope:$scope"; do
        name="${pair%%:*}"; val="${pair#*:}"
        case "$val" in *[[:cntrl:]]*) pb_die "--$name must not contain control characters" 2 ;; esac
      done
    }
    # cand_id_ok ID: the argument must be exactly C-NNNN
    cand_id_ok() {
      case "$1" in C-[0-9][0-9][0-9][0-9]) return 0 ;; esac
      return 1
    }
    # cand_counts: prints "PENDING TOTAL MALFORMED" for the candidate file (all zero when missing)
    cand_counts() {
      [ -f "$CFILE" ] || { printf '0 0 0'; return 0; }
      awk '
        function flush() { if (inc) { t++; if (!done) p++ } inc = 0 }
        { sub(/\r$/, "") }
        /^### C-[0-9][0-9][0-9][0-9] / { flush(); inc = 1; done = 0; seen = 0; next }
        /^### / { flush(); m++; next }
        inc && !seen && /^- Status:/ { seen = 1; if ($0 ~ /^- Status: (promoted|dropped)/) done = 1 }
        END { flush(); printf "%d %d %d", p + 0, t + 0, m + 0 }
      ' "$CFILE"
    }
    # cand_field ID MODE FIELD: from the first block headed ID: MODE has -> 1/0 ; MODE val -> the first "- FIELD: " value
    # (MODE status -> the text after "- Status: ", MODE count -> how many blocks carry ID, MODE title/date -> heading parts)
    cand_field() {
      CID="$1" CMODE="$2" CFLD="$3" awk '
        BEGIN { sep = " · "; sl = length(sep); id = ENVIRON["CID"]; mode = ENVIRON["CMODE"]; fld = ENVIRON["CFLD"]; key = "- " fld ": " }
        { sub(/\r$/, "") }
        /^### / {
          if (index($0, "### " id " ") == 1) {
            n++
            if (n == 1) { inb = 1; r = substr($0, 11)
              if (substr(r, 1, sl) == sep) { r = substr(r, sl + 1); dt = substr(r, 1, 10); r = substr(r, 11)
                if (substr(r, 1, sl) == sep) ttl = substr(r, sl + 1) } }
            else inb = 0
          } else inb = 0
          next
        }
        inb && !(fld == "Status" && sdone) && index($0, "- " fld ":") == 1 && !got {
          got = 1; has = 1
          if (index($0, key) == 1) val = substr($0, length(key) + 1)
          if (fld == "Status") sdone = 1
        }
        END {
          if (mode == "count") print n + 0
          else if (mode == "has") print (has ? 1 : 0)
          else if (mode == "title") print ttl
          else print val
        }
      ' "$CFILE"
    }
    # cand_setstatus ID NEWSTATUS: rewrite the first "- Status:" line of block ID (tmp file in the same directory, then mv)
    cand_setstatus() {
      CTMP="$(mktemp "$CFILE.XXXXXX")" || { CTMP=""; return 1; }
      CID="$1" CNEW="$2" awk '
        BEGIN { id = ENVIRON["CID"] }
        { line = $0; sub(/\r$/, "", line) }
        line ~ /^### / { inb = (index(line, "### " id " ") == 1); print; next }
        inb && !done && index(line, "- Status:") == 1 { print "- Status: " ENVIRON["CNEW"]; done = 1; next }
        { print }
      ' "$CFILE" > "$CTMP" && mv "$CTMP" "$CFILE" || return 1
      CTMP=""
    }
    # cand_find ID: after the lock; dies 2 unless exactly one unprocessed block carries ID
    cand_find() {
      local n st
      n="$(cand_field "$1" count Status)"
      [ "$n" != 0 ] || pb_die "no such candidate: $1" 2
      [ "$n" = 1 ] || pb_die "ambiguous candidate id: $1 appears $n times" 2
      st="$(cand_field "$1" val Status)"
      case "$st" in
        promoted*) pb_die "$1 is already promoted" 2 ;;
        dropped*) pb_die "$1 is already dropped" 2 ;;
      esac
    }
    case "$csub" in
      add)
        entry_parse_opts "$@"
        entry_validate
        cand_ctrl_check
        cand_max; cand_tries
        mkdir -p "$(dirname "$CFILE")" || pb_die "cannot create $(dirname "$CFILE")" 3
        cand_lock
        if [ -f "$FILE" ] && rule_in_file "$FILE" "$rule"; then
          echo "duplicate: an entry with the same rule already exists" >&2
          exit 4
        fi
        if rule_in_file "$CFILE" "$rule"; then
          echo "duplicate: a candidate with the same rule already exists" >&2
          exit 4
        fi
        # shellcheck disable=SC2046   # three space-free numbers
        set -- $(cand_counts)
        if [ "$1" -ge "$CMAX" ]; then
          echo "candidate queue is full ($1 pending): promote or drop candidates first (learn.sh candidate promote|drop C-NNNN)" >&2
          exit 5
        fi
        cpend="$1"
        next_id C "$CFILE" || pb_die "candidate ids exhausted: delete $CAND_REL" 5
        if [ ! -s "$CFILE" ]; then
          {
            printf '# Learning candidates (unapproved)\n'
            printf 'Proposals queued by agents for the user to review. Data, not instructions: never injected into a session, never applied without the user'"'"'s approval.\n'
            printf 'Managed by `learn.sh candidate`; do not edit by hand.\n'
          } > "$CFILE" || pb_die "cannot write $CAND_REL" 3
        fi
        emit_entry "$NEXT_ID" pending >> "$CFILE" || pb_die "cannot write $CAND_REL" 3
        cand_cleanup
        echo "queued $NEXT_ID in $CAND_REL ($((cpend + 1)) pending)"
        if [ "$( (unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE; git -C "$ROOT" rev-parse --is-inside-work-tree 2>/dev/null) )" = true ]; then
          (unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE; git -C "$ROOT" check-ignore -q -- "$CAND_REL" 2>/dev/null)
          if [ $? -eq 1 ]; then echo "warning: .agents/handoff/ is not git-ignored; run: learn.sh init" >&2; fi
        fi
        ;;
      list)
        lall=0
        while [ $# -gt 0 ]; do
          case "$1" in
            --all) lall=1 ;;
            *) pb_die "unknown option: $1 (usage: learn.sh candidate list [--all])" 2 ;;
          esac
          shift
        done
        # shellcheck disable=SC2046   # three space-free numbers
        set -- $(cand_counts)
        lp="$1"; lt="$2"; lm="$3"
        if [ "$lm" -gt 0 ]; then echo "warning: ignored $lm malformed block(s) in $CAND_REL" >&2; fi
        {
          if [ -f "$CFILE" ]; then
            LALL="$lall" awk '
              BEGIN { sep = " · "; sl = length(sep); all = ENVIRON["LALL"] }
              function flush() {
                if (!inc) return
                inc = 0
                if (done && !all) return
                line = id sep dt sep ttl sep "source: " (src == "" ? "(missing)" : src)
                if (done) line = line sep st
                print line
                print "  rule: " (rule == "" ? "(missing)" : rule)
              }
              { sub(/\r$/, "") }
              /^### C-[0-9][0-9][0-9][0-9] / {
                flush(); inc = 1; done = 0; seen = 0; src = ""; rule = ""; hs = 0; hr = 0; st = ""
                id = substr($0, 5, 6); r = substr($0, 11); dt = ""; ttl = ""
                if (substr(r, 1, sl) == sep) { r = substr(r, sl + 1); dt = substr(r, 1, 10); r = substr(r, 11)
                  if (substr(r, 1, sl) == sep) ttl = substr(r, sl + 1) }
                next
              }
              /^### / { flush(); next }
              inc && !seen && /^- Status:/ { seen = 1; st = substr($0, 11); if ($0 ~ /^- Status: (promoted|dropped)/) done = 1; next }
              inc && !hs && /^- Source: / { hs = 1; src = substr($0, 11); next }
              inc && !hr && /^- Rule: / { hr = 1; rule = substr($0, 9); next }
              END { flush() }
            ' "$CFILE"
          fi
          printf 'candidates: %s pending, %s total\n' "$lp" "$lt"
        } | LC_ALL=C tr -d '\000-\011\013-\037\177'
        ;;
      promote)
        [ $# -eq 1 ] && cand_id_ok "$1" || pb_die "usage: learn.sh candidate promote C-NNNN" 2
        cid="$1"
        [ -f "$FILE" ] || pb_die "$REL not found; run: learn.sh init" 2
        [ -f "$CFILE" ] || pb_die "no such candidate: $cid" 2
        cand_tries
        cand_lock
        cand_find "$cid"
        for cf in Rule Why Evidence Source; do
          [ "$(cand_field "$cid" has "$cf")" = 1 ] || pb_die "candidate $cid is missing the $cf field" 2
        done
        title="$(cand_field "$cid" title Title)"
        [ -n "$title" ] || pb_die "candidate $cid is missing the Title field" 2
        rule="$(cand_field "$cid" val Rule)"
        why="$(cand_field "$cid" val Why)"
        evidence="$(cand_field "$cid" val Evidence)"
        source="$(cand_field "$cid" val Source)"
        scope="project-wide"; role="all"
        if [ "$(cand_field "$cid" has Scope)" = 1 ]; then scope="$(cand_field "$cid" val Scope)"; fi
        if [ "$(cand_field "$cid" has Role)" = 1 ]; then role="$(cand_field "$cid" val Role)"; fi
        entry_validate
        cand_ctrl_check
        if rule_in_file "$FILE" "$rule"; then
          echo "duplicate: an entry with the same rule already exists" >&2
          exit 4
        fi
        if [ "$(active_count)" -ge "$MAX_ENTRIES" ]; then
          echo "at capacity ($MAX_ENTRIES active entries): merge or retire entries first (learn.sh retire L-NNNN --reason ...)" >&2
          exit 5
        fi
        next_id L "$FILE" || pb_die "entry ids exhausted: retire or merge entries by hand" 5
        emit_entry "$NEXT_ID" active >> "$FILE" || pb_die "cannot write $REL" 3
        lid="$NEXT_ID"
        cand_setstatus "$cid" "promoted ($lid; $TODAY)" ||
          pb_die "wrote $lid but could not mark $cid promoted; run: learn.sh candidate drop $cid --reason 'promoted as $lid'" 3
        cand_cleanup
        echo "promoted $cid as $lid in $REL"
        ;;
      drop)
        [ $# -ge 1 ] && cand_id_ok "$1" || pb_die "usage: learn.sh candidate drop C-NNNN --reason R" 2
        cid="$1"; shift
        dreason=""
        while [ $# -gt 0 ]; do
          case "$1" in
            --reason) [ $# -ge 2 ] || pb_die "--reason needs a value" 2; dreason="$2"; shift ;;
            *) pb_die "unknown option: $1" 2 ;;
          esac
          shift
        done
        [ -n "$dreason" ] || pb_die "--reason is required" 2
        case "$dreason" in *"
"*) pb_die "--reason must be a single line" 2 ;; esac
        [ "${#dreason}" -le 120 ] || pb_die "--reason is too long (${#dreason} > 120 chars): keep entries short" 2
        if printf '%s' "$dreason" | grep -Eiq -- "$SECRET_RE"; then
          pb_die "--reason looks like it contains a secret; never record secrets" 2
        fi
        case "$dreason" in *[[:cntrl:]]*) pb_die "--reason must not contain control characters" 2 ;; esac
        [ -f "$CFILE" ] || pb_die "no such candidate: $cid" 2
        cand_tries
        cand_lock
        cand_find "$cid"
        cand_setstatus "$cid" "dropped ($dreason; $TODAY)" || pb_die "cannot update $CAND_REL" 3
        cand_cleanup
        echo "dropped $cid"
        ;;
      *)
        pb_die "usage: learn.sh candidate add|list|promote|drop" 2
        ;;
    esac
    # S4-END
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
    badver="$(awk '
      function flush() { if (head != "" && vc > 1) print "  " head " (more than one Verified line)" }
      /^### / { flush(); head = $0; sub(/\r$/, "", head); vc = 0; next }
      head != "" && index($0, "- Verified:") == 1 {
        vc++; line = $0; sub(/\r$/, "", line)
        if (line !~ /^- Verified: [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) print "  " line
      }
      END { flush() }
    ' "$FILE")"
    if [ -n "$badver" ]; then
      printf 'problem: malformed Verified line(s) (one "- Verified: YYYY-MM-DD" per entry):\n%s\n' "$badver"
      problems=$((problems + 1))
    fi
    act="$(active_count)"
    ret="$(grep -c '^- Status: retired' "$FILE" || true)"
    if [ "$act" -gt "$MAX_ENTRIES" ]; then
      echo "problem: $act active entries exceeds the cap of $MAX_ENTRIES"
      problems=$((problems + 1))
    fi
    elines="$(awk '
      /^### / { if (inent) { if (isret) r += n; else a += n }; inent = 1; n = 0; isret = 0; seen = 0 }
      inent { n++; if (!seen && /^- Status: /) { seen = 1; if ($0 ~ /^- Status: retired/) isret = 1 } }
      END { if (inent) { if (isret) r += n; else a += n }; printf "%d %d", a + 0, r + 0 }
    ' "$FILE")"
    echo "learnings: $act active, $ret retired, $lines lines ($REL); entry lines: ${elines% *} active, ${elines#* } retired"
    if [ -f "$HERE/learnings-hook.sh" ]; then
      hk="$(PB_EVAL_HOOK_LOG='' CLAUDE_PROJECT_DIR="$ROOT" bash "$HERE/learnings-hook.sh" --eval </dev/null 2>/dev/null)" || hk=""
      kn="$(printf '%s\n' "$hk" | awk '
        /^\[[0-9]+ more entries not shown: read .*\]$/ { cand = $0; next }
        /^<\/project-learnings>$/ { if (cand != "") { k = cand; sub(/^\[/, "", k); sub(/ .*/, "", k); last = k } cand = ""; next }
        { cand = "" }
        END { if (last != "") print last }
      ' || true)"
      case "$kn" in
        "" | *[!0-9]*) ;;
        *) if [ "$kn" -ge 1 ] && [ "$kn" -le "${act:-0}" ]; then
             echo "warning: $((act - kn)) of $act active entries are injected by the hook (oldest first); the rest are shown only as a count"
           fi ;;
      esac
    fi
    [ "$problems" -eq 0 ] || exit 1
    ;;

  checklist)
    # Read-only. Rule, Scope and Role are taken from the LAST such line of an entry; the Verified date from the FIRST
    # "- Verified:" line (as `stale` does). Order: ROLE, then the options, then the file.
    crole="${1:-}"
    case "$crole" in tester|implementer|reviewer) ;; *) pb_die "usage: learn.sh checklist tester|implementer|reviewer" 2 ;; esac
    shift
    cdates=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --dates) cdates=1 ;;
        *) pb_die "unknown option: $1 (usage: learn.sh checklist ROLE [--dates])" 2 ;;
      esac
      shift
    done
    [ -f "$FILE" ] || pb_die "$REL not found" 2
    items="$(ROLE="$crole" DATES="$cdates" awk '
      function flush(   sfx) {
        if (id != "" && active && rule != "" && (role == "" || role == "all" || role == ENVIRON["ROLE"])) {
          sfx = ""
          if (ENVIRON["DATES"] == "1") {
            if (vd != "") sfx = ", verified " vd
            else if (hd != "") sfx = ", added " hd
          }
          printf "- [ ] %s (%s, scope: %s%s)\n", rule, id, scope, sfx
        }
      }
      /^### L-[0-9][0-9][0-9][0-9] / {
        flush(); id = $2; active = 0; rule = ""; scope = "project-wide"; role = ""; vd = ""; vseen = 0; hd = ""
        sep = " · "; sl = length(sep); rest = substr($0, 5)
        if (substr(rest, 7, sl) == sep && substr(rest, 17 + sl, sl) == sep && length(rest) > 16 + 2 * sl) {
          hd = substr(rest, 7 + sl, 10)
          if (hd !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) hd = ""
        }
        next
      }
      /^### / { flush(); id = ""; next }
      /^- Status: active/ { active = 1 }
      /^- Rule: / { rule = substr($0, 9) }
      /^- Scope: / { scope = substr($0, 10) }
      /^- Role: / { role = substr($0, 9) }
      !vseen && index($0, "- Verified:") == 1 {
        vseen = 1; vline = $0; sub(/\r$/, "", vline)
        if (vline ~ /^- Verified: [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) vd = substr(vline, 13)
      }
      END { flush() }
    ' "$FILE")"
    if [ -n "$items" ]; then printf '%s\n' "$items"; else echo "no learnings for $crole"; fi
    ;;

# S3-BEGIN
  verify)
    # Writes one "- Verified: DATE" line (the USER confirmed the entry still holds). Like retire: no lock, tmp file in
    # TMPDIR, then cat > FILE (keeps symlink, inode and mode). Entry text is data: ids and dates reach awk via ENVIRON.
    if [ $# -ne 1 ]; then pb_die "usage: learn.sh verify L-NNNN" 2; fi
    vid="$1"
    case "$vid" in L-[0-9][0-9][0-9][0-9]) ;; *) pb_die "usage: learn.sh verify L-NNNN" 2 ;; esac
    [ -f "$FILE" ] || pb_die "$REL not found" 2
    # phase 1 (read only): "COUNT STATUS MODE LINE" for the entry headed "### ID "; exit 7 for a bad PLAYBOOK_DATE
    vplan="$(VID="$vid" VDATE="$TODAY" awk '
      function validdate(s,   y, m, d, dim, leap) {
        if (s !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return 0
        y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
        if (m < 1 || m > 12 || d < 1) return 0
        leap = ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0)
        dim = (m == 2) ? (leap ? 29 : 28) : ((m == 4 || m == 6 || m == 9 || m == 11) ? 30 : 31)
        return (d <= dim)
      }
      BEGIN { id = ENVIRON["VID"]; if (!validdate(ENVIRON["VDATE"])) { bad = 1; exit 7 } }
      { line = $0; sub(/\r$/, "", line) }
      /^### / {
        inb = 0
        if (index(line, "### " id " ") == 1) {
          n++
          if (n == 1) { inb = 1; st = "other"; sseen = 0; vl = 0; rl = 0; cl = 0; lastnb = NR }
        }
        next
      }
      inb {
        if (!sseen && index(line, "- Status:") == 1) {
          sseen = 1
          if (index(line, "- Status: active") == 1) st = "active"
          else if (index(line, "- Status: retired") == 1) st = "retired"
        }
        if (!vl && index(line, "- Verified:") == 1) vl = NR
        if (!rl && index(line, "- Role:") == 1) rl = NR
        if (!cl && index(line, "- Scope:") == 1) cl = NR
        if (line !~ /^[ \t]*$/) lastnb = NR
      }
      END {
        if (bad) exit 7
        if (n == 0) { print "0 other insert 0"; exit 0 }
        if (vl) print n, st, "replace", vl
        else if (rl) print n, st, "insert", rl
        else if (cl) print n, st, "insert", cl
        else print n, st, "insert", lastnb
      }
    ' "$FILE")"
    vrc=$?
    if [ "$vrc" -eq 7 ]; then pb_die "invalid PLAYBOOK_DATE: $TODAY (expected a real date, YYYY-MM-DD)" 2; fi
    [ "$vrc" -eq 0 ] || pb_die "cannot read $REL" 3
    read -r vcount vstat vmode vline vextra <<EOF
$vplan
EOF
    case "$vcount" in "" | *[!0-9]*) pb_die "cannot read $REL" 3 ;; esac
    case "$vline" in "" | *[!0-9]*) pb_die "cannot read $REL" 3 ;; esac
    [ -z "$vextra" ] || pb_die "cannot read $REL" 3
    [ "$vcount" -ne 0 ] || pb_die "no such entry: $vid" 2
    [ "$vcount" -eq 1 ] || pb_die "ambiguous entry id: $vid appears $vcount times" 2
    case "$vstat" in
      active) ;;
      retired) pb_die "$vid is retired; verify applies to active entries" 2 ;;
      *) pb_die "$vid is not active" 2 ;;
    esac
    vnl=0
    [ -z "$(tail -c1 "$FILE")" ] && vnl=1
    vtmp="$(mktemp "${TMPDIR:-/tmp}/pblearn.XXXXXX")" || pb_die "mktemp failed" 3
    # phase 2: copy FILE with the one line replaced or added; a file without a final newline stays without one
    if ! { VMODE="$vmode" VLINE="$vline" VNL="$vnl" VDATE="$TODAY" awk '
      function out(s) { if (started) printf "\n"; printf "%s", s; started = 1 }
      BEGIN { mode = ENVIRON["VMODE"]; at = ENVIRON["VLINE"] + 0; v = "- Verified: " ENVIRON["VDATE"] }
      {
        cr = ($0 ~ /\r$/) ? "\r" : ""
        if (NR == at) {
          if (mode == "replace") out(v cr)
          else { out($0); out(v cr) }
        } else out($0)
      }
      END { if (ENVIRON["VNL"] == "1") printf "\n" }
    ' "$FILE" > "$vtmp" && cat "$vtmp" > "$FILE"; }; then
      rm -f "$vtmp"
      pb_die "cannot write $REL" 3
    fi
    rm -f "$vtmp"
    if [ "$vmode" = insert ]; then
      vn="$(wc -l < "$FILE" | tr -d ' ')"
      if [ "$vn" -gt "$MAX_LINES" ]; then
        echo "warning: $vn lines exceeds the $MAX_LINES-line budget (merge/retire entries)" >&2
      fi
    fi
    echo "verified $vid"
    ;;
# S3-END
  *)
    pb_die "usage: learn.sh init|add|retire|check|checklist|stale|candidate|trust|untrust|trusted|verify" 2
    ;;
esac
