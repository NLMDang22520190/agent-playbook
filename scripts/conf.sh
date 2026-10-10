#!/usr/bin/env bash
# Read/write agent-playbook settings. Plain key=value lines, never evaluated.
#   conf.sh get KEY            project value, else global value; exit 1 if unset
#   conf.sh set KEY VALUE [--global|--project]     (default --global)
#   conf.sh list               merged view with origin
#   conf.sh path               print the two file locations
# Files: <project>/.agents/playbook.conf (wins) and ~/.agents/playbook.conf
set -u
. "$(dirname "$0")/lib.sh"

cmd="${1:-}"
[ $# -gt 0 ] && shift

case "$cmd" in
  get)
    [ $# -ge 1 ] || pb_die "usage: conf.sh get KEY" 2
    pb_valid_key "$1" || pb_die "invalid key: $1" 2
    pb_conf_get "$1" || exit 1
    printf '\n'
    ;;
  set)
    [ $# -ge 2 ] || pb_die "usage: conf.sh set KEY VALUE [--global|--project]" 2
    key="$1"; value="$2"; shift 2
    scope="global"
    while [ $# -gt 0 ]; do
      case "$1" in
        --global) scope="global" ;;
        --project) scope="project" ;;
        *) pb_die "unknown option: $1" 2 ;;
      esac
      shift
    done
    pb_valid_key "$key" || pb_die "invalid key '$key' (use lowercase letters, digits, underscore)" 2
    case "$value" in *"
"*) pb_die "value must be a single line" 2 ;; esac
    if [ "$scope" = "project" ]; then file="$(pb_conf_project)"; else file="$(pb_conf_global)"; fi
    mkdir -p "$(dirname "$file")" || pb_die "cannot create $(dirname "$file")" 3
    tmp="$(mktemp "${TMPDIR:-/tmp}/pbconf.XXXXXX")" || pb_die "mktemp failed" 3
    if [ -f "$file" ]; then
      K="$key" V="$value" awk '
        index($0, ENVIRON["K"] "=") == 1 { if (!done) { print ENVIRON["K"] "=" ENVIRON["V"]; done = 1 } ; next }
        { print }
        END { if (!done) print ENVIRON["K"] "=" ENVIRON["V"] }
      ' "$file" > "$tmp"
    else
      printf '%s=%s\n' "$key" "$value" > "$tmp"
    fi
    cat "$tmp" > "$file" && rm -f "$tmp"
    if [ "$scope" = "project" ]; then
      # keep a local, untracked project conf out of `git status` (role gates and release.sh read it as a
      # change): local exclude file, not .gitignore; a tracked (team-shared) conf is left alone
      root="$(pb_root_dir)"
      if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
         ! git -C "$root" ls-files --error-unmatch .agents/playbook.conf >/dev/null 2>&1 &&
         ! git -C "$root" check-ignore -q .agents/playbook.conf 2>/dev/null; then
        excl="$(git -C "$root" rev-parse --git-path info/exclude 2>/dev/null)"
        case "$excl" in /*|?:*) ;; *) excl="$root/$excl" ;; esac
        if mkdir -p "$(dirname "$excl")"; then
          if [ -s "$excl" ] && [ -n "$(tail -c 1 "$excl")" ]; then printf '\n' >> "$excl"; fi
          printf '.agents/playbook.conf\n' >> "$excl" &&
            echo "notice: added .agents/playbook.conf to $excl (local exclude, not .gitignore)" >&2
        fi
      fi
    fi
    case "$key" in
      model_tester | model_implementer | model_reviewer)
        echo "warning: $key applies to every harness; prefer model_<role>_<harness> (e.g. ${key}_claude)" >&2 ;;
    esac
    ;;
  list)
    g="$(pb_conf_global)"; p="$(pb_conf_project)"
    {
      [ -f "$g" ] && sed -n '/^[[:lower:]][[:lower:][:digit:]_]*=/{s/$/  [global]/;p;}' "$g"
      [ -f "$p" ] && [ "$p" != "$g" ] && sed -n '/^[[:lower:]][[:lower:][:digit:]_]*=/{s/$/  [project]/;p;}' "$p"
    } | awk '{
        k = $0; sub(/=.*/, "", k)
        last[k] = $0
        if (!(k in seen)) { seen[k] = 1; order[++n] = k }
      } END { for (i = 1; i <= n; i++) print last[order[i]] }'
    ;;
  path)
    printf 'global:  %s\nproject: %s\n' "$(pb_conf_global)" "$(pb_conf_project)"
    ;;
  *)
    pb_die "usage: conf.sh get|set|list|path" 2
    ;;
esac
