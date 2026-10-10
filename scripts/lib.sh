#!/usr/bin/env bash
# Shared helpers for agent-playbook scripts. Source it; do not execute it.
# Bash 3.2 compatible (macOS default shell).

pb_die() { # message [exit-code]
  printf 'error: %s\n' "$1" >&2
  exit "${2:-1}"
}

# Directory that holds ~/.agents/playbook.conf. PLAYBOOK_HOME overrides $HOME (tests, sandboxes).
pb_home() { printf '%s' "${PLAYBOOK_HOME:-$HOME}"; }

# Project root: git top-level when inside a repo, otherwise the current directory.
pb_root_dir() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

pb_conf_global()  { printf '%s/.agents/playbook.conf' "$(pb_home)"; }
pb_conf_project() { printf '%s/.agents/playbook.conf' "$(pb_root_dir)"; }

# pb_conf_read FILE KEY -> last value of KEY in FILE (key=value lines, no quoting, no eval)
# Pure bash (no sed/grep/tail): every conf lookup used to start three processes, which is slow on Git Bash.
pb_conf_read() {
  [ -f "$1" ] || return 1
  local line v="" found=1
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in "$2="*) v="${line#"$2="}"; found=0 ;; esac
  done < "$1"
  # distinguish "key absent" from "key present with empty value"
  [ "$found" = 0 ] || return 1
  printf '%s' "$v"
}

# pb_conf_get KEY [DEFAULT] -> project value, else global value, else DEFAULT (exit 1 if none)
pb_conf_get() {
  local v
  if v="$(pb_conf_read "$(pb_conf_project)" "$1")"; then printf '%s' "$v"; return 0; fi
  if v="$(pb_conf_read "$(pb_conf_global)" "$1")"; then printf '%s' "$v"; return 0; fi
  if [ $# -ge 2 ]; then printf '%s' "$2"; return 0; fi
  return 1
}

# YYYY-MM-DD -> epoch seconds (GNU date, then BSD date)
pb_epoch_day() {
  date -u -d "$1" +%s 2>/dev/null || date -u -j -f '%Y-%m-%d' "$1" +%s 2>/dev/null
}

pb_valid_key() { case "$1" in "" | [!abcdefghijklmnopqrstuvwxyz]* | *[!abcdefghijklmnopqrstuvwxyz0123456789_]*) return 1 ;; esac; return 0; }

pb_sha256() { # stdin -> hex digest
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'
  else shasum -a 256 | awk '{print $1}'; fi
}

# Redact obvious secrets from stdin. Case-insensitive without GNU-only flags (BSD sed safe).
pb_redact() {
  sed -E \
    -e 's#(([Aa][Pp][Ii][_-]?[Kk][Ee][Yy]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Tt][Oo][Kk][Ee][Nn]|[Pp][Aa][Ss][Ss][Ww]([Oo][Rr])?[Dd]|[Pp][Ww][Dd]|[Aa][Uu][Tt][Hh][Oo][Rr][Ii][Zz][Aa][Tt][Ii][Oo][Nn])[A-Za-z0-9_-]*[[:space:]]*[=:][[:space:]]*)(Bearer[[:space:]]+)?[^[:space:]"'"'"']+#\1[REDACTED]#g' \
    -e 's#([Bb][Ee][Aa][Rr][Ee][Rr][[:space:]]+)[A-Za-z0-9._~+/=-]{8,}#\1[REDACTED]#g' \
    -e 's#(sk-|ghp_|gho_|ghs_|xox[bap]-|AKIA)[A-Za-z0-9_-]{12,}#[REDACTED]#g'
}
