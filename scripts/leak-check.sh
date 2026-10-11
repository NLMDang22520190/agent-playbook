#!/usr/bin/env bash
# Refuses secrets and private literals in ADDED lines (a guard against leaking into a public repository).
#   leak-check.sh scan --staged            the staged change (index vs HEAD)
#   leak-check.sh scan --range A..B        the lines added by the commits of that range
#   leak-check.sh scan --unpushed SHA      the commits of SHA that are on no remote (the pre-push hook uses it for a new branch)
#   leak-check.sh scan FILE...             every line of the given files
#   leak-check.sh install-hooks [--repo DIR]     write .git/hooks/pre-commit and pre-push (marker: "# agent-playbook leak-check")
#   leak-check.sh uninstall-hooks [--repo DIR]   remove the hooks that carry the marker, and only those
# Patterns: github-token, anthropic-key, aws-key, private-key (built in), plus the conf keys
#   leak_patterns  (ERE, alternatives separated by |)         reported as user-pattern
#   leak_literals  (comma-separated FIXED strings)             reported as user-literal
# read from the global conf (PLAYBOOK_HOME or HOME) and the project conf.
# A hit prints "file:line: <pattern name> <first 4 chars>***" (never the full match) and exits 1.
# Exit: 0 clean ("leak-check: clean"), 1 a hit (or, for install-hooks, a hook left alone), 2 usage, 3 not a git repo or git failed.
# Bash 3.2 and BSD tool compatible.
set -u
SELF_DIR="$(cd "$(dirname "$0")" && pwd -P)"
. "$SELF_DIR/lib.sh"

MARKER='# agent-playbook leak-check'

usage() {
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

TMP=""
cleanup() { [ -z "$TMP" ] || rm -rf "${TMP:?}"; }
trap cleanup EXIT

# scan_text NAME FLAG EXPR -> findings for one pattern over $TMP/txt, as "file:line: name masked"
scan_text() {
  grep -a -n -o "$2" -e "$3" "$TMP/txt" 2>/dev/null |
    awk -v name="$1" 'NR == FNR { loc[FNR] = $0; next }
      { n = $0; sub(/:.*/, "", n); m = $0; sub(/^[0-9]+:/, "", m); print loc[n] ": " name " " substr(m, 1, 4) "***" }' "$TMP/idx" - >> "$TMP/found"
}

# conf_values KEY -> the global then the project value of KEY, one per line (empty ones left out)
conf_values() {
  local v
  v="$(pb_conf_read "$(pb_conf_global)" "$1")" && [ -n "$v" ] && printf '%s\n' "$v"
  v="$(pb_conf_read "$(pb_conf_project)" "$1")" && [ -n "$v" ] && printf '%s\n' "$v"
  return 0
}

# check_added: $TMP/idx (file:line) and $TMP/txt (the line) hold the lines to check, one pair per line
check_added() {
  : > "$TMP/found"
  if [ -s "$TMP/txt" ]; then
    scan_text github-token -E 'gh[pousr]_[A-Za-z0-9]{36}'
    scan_text github-token -E 'github_pat_[A-Za-z0-9_]{22,}'
    scan_text anthropic-key -E 'sk-ant-[A-Za-z0-9_-]{20,}'
    scan_text aws-key -E 'AKIA[0-9A-Z]{16}'
    scan_text private-key -E '-----BEGIN [A-Z ]*PRIVATE KEY-----'
    local pat lit
    while IFS= read -r pat; do
      [ -n "$pat" ] || continue
      printf '' | grep -E -e "$pat" >/dev/null 2>&1
      [ $? -ne 2 ] || { printf 'error: leak_patterns is not a valid extended regex: %s\n' "$pat" >&2; exit 2; }
      scan_text user-pattern -E "$pat"
    done <<EOF
$(conf_values leak_patterns)
EOF
    while IFS= read -r pat; do
      [ -n "$pat" ] || continue
      while IFS= read -r lit; do
        [ -n "$lit" ] || continue
        scan_text user-literal -F "$lit"
      done <<EOF2
$(printf '%s\n' "$pat" | tr ',' '\n')
EOF2
    done <<EOF3
$(conf_values leak_literals)
EOF3
  fi
  if [ -s "$TMP/found" ]; then
    LC_ALL=C sort -u "$TMP/found"
    printf 'leak-check: %s finding(s); the matches are masked above\n' "$(wc -l < "$TMP/found" | tr -d ' ')"
    return 1
  fi
  echo "leak-check: clean"
  return 0
}

# diff_to_added FILE -> idx and txt from a unified diff (-U0) of FILE: the added lines only
diff_to_added() {
  awk -v idx="$TMP/idx" -v txt="$TMP/txt" '
    /^diff --git / { hdr = 1; file = ""; next }
    hdr && /^\+\+\+ / { f = $0; sub(/^\+\+\+ /, "", f); sub(/\t.*$/, "", f)
      if (f == "/dev/null") file = ""; else { sub(/^b\//, "", f); file = f }; next }
    /^@@ / { hdr = 0; s = $0; sub(/^@@ -[0-9,]+ \+/, "", s); sub(/[ ,].*$/, "", s); ln = s + 0; next }
    !hdr && /^\+/ { if (file != "") { print file ":" ln >> idx; print substr($0, 2) >> txt }; ln++; next }
  ' "$1"
  : >> "$TMP/idx"; : >> "$TMP/txt"
}

in_repo() { git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "leak-check: not a git repository" >&2; exit 3; }; }

do_scan() {
  local mode="" val=""
  [ $# -gt 0 ] || usage
  case "$1" in
    --staged) [ $# -eq 1 ] || usage; mode=staged ;;
    --range|--unpushed) [ $# -eq 2 ] || usage; mode="${1#--}"; val="$2" ;;
    --) shift; [ $# -gt 0 ] || usage; mode=files ;;
    -*) usage ;;
    *) mode=files ;;
  esac
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/pbleak.XXXXXX")" || pb_die "mktemp failed" 3
  : > "$TMP/idx"; : > "$TMP/txt"
  case "$mode" in
    staged)
      in_repo
      git -c core.quotePath=false diff --cached -U0 --no-color --no-ext-diff --no-renames --src-prefix=a/ --dst-prefix=b/ > "$TMP/diff" 2>/dev/null ||
        { echo "leak-check: git diff failed" >&2; exit 3; }
      diff_to_added "$TMP/diff" ;;
    range|unpushed)
      in_repo
      if [ "$mode" = range ]; then
        git -c core.quotePath=false log -p -U0 --no-color --no-ext-diff --no-renames --src-prefix=a/ --dst-prefix=b/ --format= "$val" -- > "$TMP/diff" 2>/dev/null ||
          { echo "leak-check: git log failed for range $val" >&2; exit 3; }
      else
        git -c core.quotePath=false log -p -U0 --no-color --no-ext-diff --no-renames --src-prefix=a/ --dst-prefix=b/ --format= "$val" --not --remotes -- > "$TMP/diff" 2>/dev/null ||
          { echo "leak-check: git log failed for $val" >&2; exit 3; }
      fi
      diff_to_added "$TMP/diff" ;;
    files)
      local f
      for f in "$@"; do
        [ -f "$f" ] && [ -r "$f" ] || { printf 'leak-check: cannot read %s\n' "$f" >&2; exit 2; }
        awk -v f="$f" -v idx="$TMP/idx" '{ print f ":" FNR >> idx }' "$f"
        cat "$f" >> "$TMP/txt"
        # a file without a final newline must not glue its last line to the next file
        [ -z "$(tail -c 1 "$f" | tr -d '\n')" ] || printf '\n' >> "$TMP/txt"
        : >> "$TMP/idx"
      done ;;
  esac
  check_added
}

# hooks_dir REPO -> the absolute hooks directory of the repository at REPO
hooks_dir() {
  local p
  p="$(git -C "$1" rev-parse --git-path hooks 2>/dev/null)" || { printf 'leak-check: %s is not a git repository\n' "$1" >&2; exit 3; }
  case "$p" in /*|[A-Za-z]:*) ;; *) p="$1/$p" ;; esac
  printf '%s' "$p"
}

parse_repo() { # args after the command -> REPO
  REPO="."
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) [ $# -ge 2 ] || usage; REPO="$2"; shift ;;
      *) usage ;;
    esac
    shift
  done
}

hook_head() { # the first lines of a hook
  local lc="$SELF_DIR/leak-check.sh"
  lc="$(printf '%s' "$lc" | sed "s/'/'\\\\''/g")"
  printf '#!/bin/sh\n%s\n# Installed by leak-check.sh install-hooks; leak-check.sh uninstall-hooks removes it.\nLC='"'"'%s'"'"'\n[ -f "$LC" ] || exit 0\n' "$MARKER" "$lc"
}

install_hooks() {
  parse_repo "$@"
  local dir rc=0 h
  dir="$(hooks_dir "$REPO")" || exit 3
  mkdir -p "$dir" || pb_die "cannot create $dir" 3
  for h in pre-commit pre-push; do
    if [ -e "$dir/$h" ] && ! grep -qF "$MARKER" "$dir/$h" 2>/dev/null; then
      printf 'leak-check: %s already exists and is not a leak-check hook; left alone\n' "$h" >&2
      rc=1; continue
    fi
    {
      hook_head
      if [ "$h" = pre-commit ]; then
        printf 'exec bash "$LC" scan --staged\n'
      else
        cat <<'HOOK'
# stdin: <local ref> <local sha> <remote ref> <remote sha>, one line per pushed ref
rc=0
while read -r lref lsha rref rsha; do
  case "$lsha" in *[!0]*) ;; *) continue ;; esac   # a deletion pushes no commits
  case "$rsha" in
    *[!0]*) if git cat-file -e "$rsha^{commit}" 2>/dev/null; then
              bash "$LC" scan --range "$rsha..$lsha" </dev/null || rc=1
              continue
            fi ;;
  esac
  bash "$LC" scan --unpushed "$lsha" </dev/null || rc=1   # a new branch: its commits that are on no remote
done
exit $rc
HOOK
      fi
    } > "$dir/$h" || pb_die "cannot write $dir/$h" 3
    chmod +x "$dir/$h"
    printf 'leak-check: installed %s\n' "$dir/$h"
  done
  return $rc
}

uninstall_hooks() {
  parse_repo "$@"
  local dir h
  dir="$(hooks_dir "$REPO")" || exit 3
  for h in pre-commit pre-push; do
    if [ -f "$dir/$h" ] && grep -qF "$MARKER" "$dir/$h" 2>/dev/null; then
      rm -f "${dir:?}/${h:?}" && printf 'leak-check: removed %s\n' "$dir/$h"
    fi
  done
  return 0
}

cmd="${1:-}"
[ $# -eq 0 ] || shift
case "$cmd" in
  scan) do_scan "$@" ;;
  install-hooks) install_hooks "$@" ;;
  uninstall-hooks) uninstall_hooks "$@" ;;
  *) usage ;;
esac
