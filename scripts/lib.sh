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
  date -u -d "$1" +%s 2>/dev/null || date -u -j -f '%Y-%m-%d' "$1" +%s 2>/dev/null   # gnu-ok: BSD fallback follows
}

pb_valid_key() { case "$1" in "" | [!abcdefghijklmnopqrstuvwxyz]* | *[!abcdefghijklmnopqrstuvwxyz0123456789_-]*) return 1 ;; esac; return 0; }

pb_sha256() { # stdin -> hex digest
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'
  else shasum -a 256 | awk '{print $1}'; fi
}

# Redact obvious secrets from stdin. Case-insensitive without GNU-only flags (BSD sed safe).
# Key prefixes (sk-, ghp_ ...) count only at a token start (line start or a char outside [A-Za-z0-9_-], kept), so "task-..." is left alone.
pb_redact() {
  sed -E \
    -e 's#(([Aa][Pp][Ii][_-]?[Kk][Ee][Yy]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Tt][Oo][Kk][Ee][Nn]|[Pp][Aa][Ss][Ss][Ww]([Oo][Rr])?[Dd]|[Pp][Ww][Dd]|[Aa][Uu][Tt][Hh][Oo][Rr][Ii][Zz][Aa][Tt][Ii][Oo][Nn])[A-Za-z0-9_-]*[[:space:]]*[=:][[:space:]]*)(Bearer[[:space:]]+)?[^[:space:]"'"'"']+#\1[REDACTED]#g' \
    -e 's#([Bb][Ee][Aa][Rr][Ee][Rr][[:space:]]+)[A-Za-z0-9._~+/=-]{8,}#\1[REDACTED]#g' \
    -e 's#(^|[^A-Za-z0-9_-])(sk-|ghp_|gho_|ghs_|xox[bap]-|AKIA)[A-Za-z0-9_-]{12,}#\1[REDACTED]#g'
}

# pb_raw_lines GIT-DIFF-ARGS... -> one "META<TAB>PATH" line per changed path from `git diff --raw -z` (paths unquoted, so a
# path with a double quote or a tab is printed as it is). META is ":OLDMODE NEWMODE OLDSHA NEWSHA STATUS".
# Status: 0 ok, 1 git failed, 4 a path has an LF inside its -z record (it cannot be split into lines safely; nothing is
# printed). The LF is mapped to \002 while the NULs become line ends, so a \002 in the stream marks that case (a path
# holding a literal \002 byte is refused the same way: the safe side).
pb_raw_lines() {
  local out ctl
  ctl="$(printf '\002')"
  out="$(git -c core.quotepath=off diff --raw -z --no-abbrev --no-renames --no-ext-diff "$@" | tr '\n\000' '\002\n'; exit "${PIPESTATUS[0]}")" || return 1
  case "$out" in *"$ctl"*) return 4 ;; esac
  [ -z "$out" ] || printf '%s\n' "$out" | awk 'NR % 2 == 1 { m = $0; next } { print m "\t" $0 }'
  return 0
}

# pb_hash_bisect LIST [skip] -> one line per path of LIST (newline-terminated paths): its blob sha, or "-" when it cannot
# be hashed. LIST is hashed in one git hash-object --stdin-paths call; when that fails or returns a wrong count the list
# is split in two halves, each handled the same way, and a single path that fails prints "-". With a second argument
# the first call is skipped (the caller already saw it fail).
pb_hash_bisect() {
  local list="$1" out p n=0 h1="" h2="" half i=0 nl
  nl="
"
  [ -n "$list" ] || return 0
  while IFS= read -r p; do [ -n "$p" ] && n=$((n + 1)); done <<EOF
$list
EOF
  if [ $# -lt 2 ]; then
    if out="$(printf '%s' "$list" | git hash-object --stdin-paths 2>/dev/null)" &&
       [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = "$n" ]; then
      printf '%s\n' "$out"; return 0
    fi
  fi
  if [ "$n" -le 1 ]; then printf -- '-\n'; return 0; fi
  half=$((n / 2))
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    i=$((i + 1))
    if [ "$i" -le "$half" ]; then h1="$h1$p$nl"; else h2="$h2$p$nl"; fi
  done <<EOF
$list
EOF
  pb_hash_bisect "$h1"
  pb_hash_bisect "$h2"
}

# pb_lost_exec_paths < RAW-LINES -> one line per finding, sorted, no duplicates: "L<path>" for a path that lost the
# executable bit (100755 -> 100644, or, a rename seen as delete + add, a deleted 100755 path whose blob is added at 100644
# under another path: the NEW path is named; the empty blob never pairs, an empty file is not a rename source) and
# "U<path>" for an added work-tree path that could not be hashed (the check is incomplete for it). An added work-tree
# entry has the sha 0{40} (git diff BASE does not hash the work tree): those paths are hashed in ONE git hash-object
# --stdin-paths call (paths relative to the current directory, so run it at the top of the work tree); when that call
# fails or returns a wrong count, the paths that are not readable regular files are set aside ("cannot hash") and ONE
# batch runs for the rest; only when that fails too is the batch bisected (pb_hash_bisect: halves, recursively, single
# paths at the leaves), so the cost stays bounded for a big change.
# The 10-process bound holds for unreadable files (set aside before the batch). A readable file that cannot be hashed
# (for example a required clean filter fails) is found by bisecting the batch: about 2 * log2(N) processes for one such
# file among N paths, instead of one process per path.
pb_lost_exec_paths() {
  local raw zp hs p h nl hok rd flags hs2 rest
  nl="
"
  raw="$(cat)"
  zp="$(printf '%s\n' "$raw" | awk '
    { t = index($0, "\t"); if (t == 0) next
      split(substr($0, 1, t - 1), m, " ")
      if (m[1] == ":000000" && m[2] == "100644" && m[4] ~ /^0+$/) print substr($0, t + 1) }')"
  hs=""
  if [ -n "$zp" ]; then
    hok=1
    hs="$(printf '%s\n' "$zp" | git hash-object --stdin-paths 2>/dev/null)" || hok=0
    if [ "$hok" = 0 ] || [ "$(printf '%s\n' "$hs" | wc -l | tr -d ' ')" != "$(printf '%s\n' "$zp" | wc -l | tr -d ' ')" ]; then
      rd=""; flags=""
      while IFS= read -r p; do
        [ -n "$p" ] || continue
        if [ -f "$p" ] && [ -r "$p" ]; then rd="$rd$p$nl"; flags="${flags}1"; else flags="${flags}0"; fi
      done <<EOF
$zp
EOF
      hs2=""; hok=1
      if [ -n "$rd" ]; then
        hs2="$(printf '%s' "$rd" | git hash-object --stdin-paths 2>/dev/null)" || hok=0
        [ "$(printf '%s\n' "$hs2" | wc -l | tr -d ' ')" = "$(printf '%s' "$rd" | wc -l | tr -d ' ')" ] || hok=0
        if [ "$hok" = 0 ]; then
          # the batch of the readable paths failed (or, when nothing was set aside, it is the batch that just failed)
          if [ "$rd" = "$zp$nl" ]; then hs2="$(pb_hash_bisect "$rd" skip)"; else hs2="$(pb_hash_bisect "$rd")"; fi
        fi
      fi
      rest="$hs2$nl"; hs=""
      while [ -n "$flags" ]; do
        if [ "${flags%"${flags#?}"}" = 1 ]; then h="${rest%%"$nl"*}"; rest="${rest#*"$nl"}"; else h="-"; fi
        flags="${flags#?}"
        hs="$hs$h$nl"
      done
    fi
  fi
  { printf '%s\n' "$hs" | sed 's/^/@/'; printf '%s\n' "$raw"; } | awk '
    BEGIN { empty = "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391"; nh = 0; k = 0 }
    /^@/ { if (length($0) > 1) hsha[++nh] = substr($0, 2); next }
    { t = index($0, "\t"); if (t == 0) next
      split(substr($0, 1, t - 1), m, " "); p = substr($0, t + 1)
      if (m[1] == ":100755" && m[2] == "100644") print "L" p
      else if (m[1] == ":100755" && m[2] == "000000") { if (m[3] != empty) del[m[3]] = 1 }
      else if (m[1] == ":000000" && m[2] == "100644") {
        sha = m[4]
        if (sha ~ /^0+$/) { k++; sha = (nh > 0 ? hsha[k] : "")
          if (sha == "-") { print "U" p; next } }
        if (sha != "" && sha != empty) { na++; ap[na] = p; as[na] = sha } } }
    END { for (i = 1; i <= na; i++) if (as[i] in del) print "L" ap[i] }
  ' | LC_ALL=C sort -u
}
