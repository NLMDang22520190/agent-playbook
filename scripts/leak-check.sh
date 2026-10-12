#!/usr/bin/env bash
# Refuses secrets and private literals in ADDED lines (a guard against leaking into a public repository).
#   leak-check.sh scan --staged            the staged change (index vs HEAD); also refuses a staged 100755 -> 100644 change
#                                          ("VIOLATION (mode)", escape: PB_ALLOW_MODE_CHANGE=path1:path2, exact paths; a path
#                                          with a colon cannot be listed) also when a rename with unchanged content drops the bit (the new path is named),
#                                          and warns on stderr about a new staged file that starts with #! at mode 100644
#   leak-check.sh scan --range A..B        the lines added by the commits of that range
#   leak-check.sh scan --unpushed SHA [--remote NAME]   the commits of SHA that are on no remote (the pre-push hook uses it
#                                          for a new branch); with NAME (a configured remote) only the refs it owns count:
#                                          a ref belongs to the remote whose fetch refspec destination matches it longest, so
#                                          with a remote "origin/foo", origin's own branch foo/x is origin/foo's and is scanned
#                                          too when pushing to origin (scanning more is the safe side). A NAME that is no
#                                          configured remote (a URL push) uses the refs of the remotes that url names (raw or after
#                                          insteadOf; only when all their url/pushurl values are one place), else every commit is scanned
#   leak-check.sh scan FILE...             every line of the given files
#   leak-check.sh install-hooks [--repo DIR]     write .git/hooks/pre-commit and pre-push (marker: "# agent-playbook leak-check")
#   leak-check.sh uninstall-hooks [--repo DIR]   remove the hooks that carry the marker, and only those
# Patterns: github-token, anthropic-key, aws-key, private-key (built in), plus the conf keys
#   leak_patterns  (ERE, alternatives separated by |)         reported as user-pattern
#   leak_literals  (comma-separated FIXED strings, case-insensitive)   reported as user-literal
#                  (a UTF-8 locale is probed so non-ASCII letters fold case too; none found: ASCII-only, noted on stderr)
# read from the global conf (PLAYBOOK_HOME or HOME) and the project conf.
# A hit prints "file:line: <pattern name> <first 4 chars>***" (a match of 8 characters or fewer: just ***) and exits 1.
# Exit: 0 clean ("leak-check: clean"), 1 a hit (or, for install-hooks, a hook left alone), 2 usage, 3 not a git repo or git failed.
# Bash 3.2 and BSD tool compatible.
set -u
SELF_DIR="$(cd "$(dirname "$0")" && pwd -P)"
. "$SELF_DIR/lib.sh"

MARKER='# agent-playbook leak-check'

usage() {
  sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

TMP=""
cleanup() { [ -z "$TMP" ] || rm -rf "${TMP:?}"; }
trap cleanup EXIT

# scan_text NAME FLAG EXPR -> findings for one pattern over $TMP/txt, as "file:line: name masked"
# (LITLOC, when set, is the locale for grep: the case folding of non-ASCII literals)
scan_text() {
  if [ -n "${LITLOC:-}" ]; then
    LC_ALL="$LITLOC" grep -a -n -o "$2" -e "$3" "$TMP/txt" 2>/dev/null
  else
    grep -a -n -o "$2" -e "$3" "$TMP/txt" 2>/dev/null
  fi |
    awk -v name="$1" 'NR == FNR { loc[FNR] = $0; next }
      { n = $0; sub(/:.*/, "", n); m = $0; sub(/^[0-9]+:/, "", m); print loc[n] ": " name " " (length(m) <= 8 ? "" : substr(m, 1, 4)) "***" }' "$TMP/idx" - >> "$TMP/found"
}

# conf_values KEY -> the global then the project value of KEY, one per line (empty ones left out)
conf_values() {
  local v
  v="$(pb_conf_read "$(pb_conf_global)" "$1")" && [ -n "$v" ] && printf '%s\n' "$v"
  v="$(pb_conf_read "$(pb_conf_project)" "$1")" && [ -n "$v" ] && printf '%s\n' "$v"
  return 0
}

# utf8_locale -> the first of C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8 where grep -i folds a non-ASCII letter (D-stroke vs
# d-stroke, written as bytes), or nothing
utf8_locale() {
  local c
  for c in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
    if printf '\304\220' | LC_ALL="$c" grep -qiF "$(printf '\304\221')" 2>/dev/null; then printf '%s' "$c"; return 0; fi
  done
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
    local pat lit lits
    while IFS= read -r pat; do
      [ -n "$pat" ] || continue
      printf '' | grep -E -e "$pat" >/dev/null 2>&1
      [ $? -ne 2 ] || { printf 'error: leak_patterns is not a valid extended regex: %s\n' "$pat" >&2; exit 2; }
      scan_text user-pattern -E "$pat"
    done <<EOF
$(conf_values leak_patterns)
EOF
    lits="$(conf_values leak_literals)"
    LITLOC=""
    if [ -n "$lits" ]; then
      LITLOC="$(utf8_locale)"
      [ -n "$LITLOC" ] || echo "leak-check: no UTF-8 locale; literal case folding is ASCII-only" >&2
    fi
    while IFS= read -r pat; do
      [ -n "$pat" ] || continue
      while IFS= read -r lit; do
        [ -n "$lit" ] || continue
        scan_text user-literal -Fi "$lit"
      done <<EOF2
$(printf '%s\n' "$pat" | tr ',' '\n')
EOF2
    done <<EOF3
$lits
EOF3
  fi
  if [ -s "$TMP/found" ]; then
    LC_ALL=C sort -u "$TMP/found" > "$TMP/shown"
    cat "$TMP/shown"
    if [ "${MODEBAD:-0}" -gt 0 ]; then
      printf 'leak-check: %s finding(s), %d mode violation(s); the matches are masked above\n' "$(wc -l < "$TMP/shown" | tr -d ' ')" "$MODEBAD"
    else
      printf 'leak-check: %s finding(s); the matches are masked above\n' "$(wc -l < "$TMP/shown" | tr -d ' ')"
    fi
    return 1
  fi
  if [ "${MODEBAD:-0}" -gt 0 ]; then
    printf 'leak-check: %d mode violation(s); no secret found\n' "$MODEBAD"
    return 1
  fi
  echo "leak-check: clean"
  return 0
}

# mode_check: scan --staged only. Refuses a staged 100755 -> 100644 change (sets MODEBAD) unless the path is listed in
# PB_ALLOW_MODE_CHANGE (colon-separated exact paths; a case pattern, so no glob and no splitting); warns on stderr
# about a newly added staged file that starts with #! at mode 100644. Raw lines: ":OLDMODE NEWMODE SHA SHA STATUS<TAB>PATH".
mode_check() {
  MODEBAD=0
  local raw lost mpath mkind rrc
  # one git call for the raw list (paths unquoted, see pb_raw_lines in lib.sh); a rename that drops the bit is found by blob.
  # The check never fails open: a failing raw list, or a path with a newline (no escape: rename it), is a violation.
  raw="$(pb_raw_lines --cached 2>/dev/null)"; rrc=$?
  if [ "$rrc" = 4 ]; then
    printf 'VIOLATION (mode): a path contains a newline; the mode check is incomplete\n'
    MODEBAD=$((MODEBAD + 1)); return 0
  elif [ "$rrc" != 0 ]; then
    printf 'VIOLATION (mode): git diff --raw failed; the mode check is incomplete\n'
    MODEBAD=$((MODEBAD + 1)); return 0
  fi
  lost="$(printf '%s\n' "$raw" | pb_lost_exec_paths)"
  while IFS= read -r mpath; do
    [ -n "$mpath" ] || continue
    mkind="${mpath%"${mpath#?}"}"; mpath="${mpath#?}"
    case ":${PB_ALLOW_MODE_CHANGE:-}:" in *":$mpath:"*) continue ;; esac
    if [ "$mkind" = U ]; then
      printf 'VIOLATION (mode): cannot hash %s; the mode check is incomplete\n' "$mpath"
    else
      printf 'VIOLATION (mode): %s lost its executable bit (100755 -> 100644)\n' "$mpath"
    fi
    MODEBAD=$((MODEBAD + 1))
  done <<EOF
$lost
EOF
  # the #! warning: the first line of every new 100644 blob, read in ONE git cat-file --batch pass (not one git call per file)
  printf '%s\n' "$raw" | grep '^:000000 100644 ' > "$TMP/addl"
  [ -s "$TMP/addl" ] || return 0
  awk '{ t = index($0, "\t"); split(substr($0, 1, t - 1), m, " "); print m[4] }' "$TMP/addl" > "$TMP/addsha"
  # batch output: "SHA blob SIZE", then SIZE bytes of content and one LF; so SIZE + 1 bytes follow the header line
  git cat-file --batch < "$TMP/addsha" 2>/dev/null | tr '\000' ' ' | LC_ALL=C awk -v list="$TMP/addl" '
    BEGIN { while ((getline l < list) > 0) { t = index(l, "\t"); if (t) paths[++np] = substr(l, t + 1) } st = 0; k = 0 }
    st == 0 { k++; if ($2 == "missing" || NF < 3) next; rem = $3 + 1; st = 1; first = 1; next }
    st == 1 { if (first) { first = 0; if (substr($0, 1, 2) == "#!") print paths[k] }
              rem -= length($0) + 1; if (rem <= 0) st = 0; next }
  ' > "$TMP/shebang"
  while IFS= read -r mpath; do
    [ -n "$mpath" ] || continue
    printf 'leak-check: warning: new file %s starts with #! but is mode 100644 (not executable); fix: git update-index --chmod=+x -- %s\n' "$mpath" "$mpath" >&2
  done < "$TMP/shebang"
  return 0
}

# diff_to_added FILE -> idx and txt from a unified diff (-U0) of FILE: the added lines only
diff_to_added() {
  # NUL bytes (binary files) end a line early in BSD awk and grep (macOS): turn them into spaces first
  # LC_ALL=C: bytes, not characters (gawk in a UTF-8 locale warns about invalid bytes); only the masking awk keeps the locale
  tr '\000' ' ' < "$1" | LC_ALL=C awk -v idx="$TMP/idx" -v txt="$TMP/txt" '
    /^diff --(git|cc|combined) / { hdr = 1; file = ""; next }
    hdr && /^\+\+\+ / { f = $0; sub(/^\+\+\+ /, "", f); sub(/\t.*$/, "", f)
      if (f == "/dev/null") file = ""; else { sub(/^b\//, "", f); file = f }; next }
    /^@@+ / { hdr = 0; np = 0; while (substr($0, np + 1, 1) == "@") np++; np--   # columns: one per parent
      s = $0; sub(/ @@+.*$/, "", s); sub(/^.* \+/, "", s); sub(/,.*$/, "", s); ln = s + 0; next }
    !hdr && !/^\\/ { p = substr($0, 1, np)
      if (index(p, "-")) next                                       # not in the result
      if (p ~ /^\++$/ && file != "") { print file ":" ln >> idx; print substr($0, np + 1) >> txt }
      ln++; next }
  '
  : >> "$TMP/idx"; : >> "$TMP/txt"
}

# owned_refs NAME -> the refs/remotes refs that belong to remote NAME, one per line. A ref belongs to the remote whose
# fetch refspec destination (remote.<r>.fetch) matches it with the longest prefix; on a tie it is not NAME's (scan more).
# A remote with no fetch refspec owns refs/remotes/NAME/*.
owned_refs() {
  {
    git config --get-regexp '^remote\..*\.fetch$' 2>/dev/null | sed 's/^/C /'
    git for-each-ref --format='%(refname)' refs/remotes 2>/dev/null | sed 's/^/R /'
    git remote 2>/dev/null | sed 's/^/N /'
  } | awk -v want="$1" '
    $1 == "N" { nm[++nn] = $2; next }
    $1 == "C" { key = $2; sub(/^remote\./, "", key); sub(/\.fetch$/, "", key)
      v = $0; sub(/^C [^ ]+ /, "", v); sub(/^\+/, "", v)
      i = index(v, ":"); if (i == 0) next
      dst = substr(v, i + 1); if (dst == "") next
      star = index(dst, "*")
      n++; rn[n] = key; if (star) { rp[n] = substr(dst, 1, star - 1); re[n] = 0 } else { rp[n] = dst; re[n] = 1 }
      hasf[key] = 1
      next }
    $1 == "R" { refs[++m] = $2 }
    END {
      # every configured remote without a fetch line owns refs/remotes/NAME/* (so the longest match sees all of them)
      for (j = 1; j <= nn; j++) if (!(nm[j] in hasf)) { hasf[nm[j]] = 1; n++; rn[n] = nm[j]; rp[n] = "refs/remotes/" nm[j] "/"; re[n] = 0 }
      if (!(want in hasf)) { n++; rn[n] = want; rp[n] = "refs/remotes/" want "/"; re[n] = 0 }
      for (k = 1; k <= m; k++) {
        bl = -1; bw = 0
        for (i = 1; i <= n; i++) {
          if (re[i] ? (refs[k] != rp[i]) : (index(refs[k], rp[i]) != 1)) continue
          l = length(rp[i])
          if (l > bl) { bl = l; bw = (rn[i] == want) }
          else if (l == bl && rn[i] != want) bw = 0
        }
        if (bw) print refs[k]
      }
    }'
}

# url_remotes NAME -> the configured remotes whose destination NAME is, one per line. NAME counts for a remote R when
# every url and pushurl value of R names one place (compared after insteadOf expansion: git remote get-url --all, and
# --push --all) and NAME is one of R's raw values or, expanded (git ls-remote --get-url NAME), is that place. A trailing
# .git or /, or ssh vs https forms, are not normalized: such a NAME matches nothing (the caller then scans everything).
url_remotes() {
  local name="$1" exp r raws exps hit v
  [ -n "$name" ] || return 0
  exp="$(git ls-remote --get-url "$name" 2>/dev/null)" || exp=""
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    exps="$( { git remote get-url --all "$r" 2>/dev/null; git remote get-url --push --all "$r" 2>/dev/null; } | LC_ALL=C sort -u)"
    [ -n "$exps" ] || continue
    [ "$(printf '%s\n' "$exps" | wc -l | tr -d ' ')" = 1 ] || continue   # the values name different places
    hit=0
    [ -z "$exp" ] || [ "$exp" != "$exps" ] || hit=1
    raws="$( { git config --get-all "remote.$r.url" 2>/dev/null; git config --get-all "remote.$r.pushurl" 2>/dev/null; } )"
    while IFS= read -r v; do
      [ "$v" != "$name" ] || hit=1
    done <<EOF
$raws
EOF
    [ "$hit" = 0 ] || printf '%s\n' "$r"
  done <<EOF
$(git remote 2>/dev/null)
EOF
}

in_repo() { git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "leak-check: not a git repository" >&2; exit 3; }; }

do_scan() {
  local mode="" val="" remote="" hasremote=0
  [ $# -gt 0 ] || usage
  case "$1" in
    --staged) [ $# -eq 1 ] || usage; mode=staged ;;
    --range) [ $# -eq 2 ] || usage; mode=range; val="$2" ;;
    --unpushed)
      [ $# -eq 2 ] || { [ $# -eq 4 ] && [ "$3" = --remote ]; } || usage
      mode=unpushed; val="$2"
      if [ $# -eq 4 ]; then hasremote=1; remote="$4"; fi ;;
    --) shift; [ $# -gt 0 ] || usage; mode=files ;;
    -*) usage ;;
    *) mode=files ;;
  esac
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/pbleak.XXXXXX")" || pb_die "mktemp failed" 3
  : > "$TMP/idx"; : > "$TMP/txt"
  case "$mode" in
    staged)
      in_repo
      git -c core.quotePath=false diff --cached --text -U0 --no-color --no-ext-diff --no-renames --src-prefix=a/ --dst-prefix=b/ > "$TMP/diff" 2>/dev/null ||
        { echo "leak-check: git diff failed" >&2; exit 3; }
      diff_to_added "$TMP/diff"
      mode_check ;;
    range|unpushed)
      in_repo
      if [ "$mode" = range ]; then
        git -c core.quotePath=false log -p --cc --text -U0 --no-color --no-ext-diff --no-renames --src-prefix=a/ --dst-prefix=b/ --format= "$val" -- > "$TMP/diff" 2>/dev/null ||
          { echo "leak-check: git log failed for range $val" >&2; exit 3; }
      else
        # --remote NAME with NAME exactly a configured remote: only the refs NAME owns count. NAME that is a url of a
        # configured remote (url_remotes): the union of those remotes' owned refs. Any other NAME (a new destination holds
        # none of the commits): nothing is excluded, the full range is scanned, with a note. No --remote: any remote counts.
        # The owned refs go through stdin ("^REF" per line, git log --stdin), never as one argument each: thousands of
        # remote refs would overflow the command line (Windows: 32K).
        if [ "$hasremote" = 1 ]; then
          : > "$TMP/own"
          if [ -n "$remote" ] && git remote 2>/dev/null | grep -qxF -e "$remote"; then
            owned_refs "$remote" > "$TMP/own"   # owns no ref yet: the list is empty, nothing is excluded
          else
            local rems rn
            rems="$(url_remotes "$remote")"
            if [ -n "$rems" ]; then
              while IFS= read -r rn; do
                [ -n "$rn" ] || continue
                owned_refs "$rn" >> "$TMP/own"
              done <<EOF
$rems
EOF
            else
              printf 'leak-check: %s is not a configured remote; scanning the full range (push through a named remote to limit it)\n' "$remote" >&2
            fi
          fi
          LC_ALL=C sort -u "$TMP/own" | sed 's/^/^/' > "$TMP/not"
          git -c core.quotePath=false log -p --cc --text -U0 --no-color --no-ext-diff --no-renames --src-prefix=a/ --dst-prefix=b/ --format= --stdin "$val" -- < "$TMP/not" > "$TMP/diff" 2>/dev/null ||
            { echo "leak-check: git log failed for $val" >&2; exit 3; }
        else
          git -c core.quotePath=false log -p --cc --text -U0 --no-color --no-ext-diff --no-renames --src-prefix=a/ --dst-prefix=b/ --format= "$val" --not --remotes -- > "$TMP/diff" 2>/dev/null ||
            { echo "leak-check: git log failed for $val" >&2; exit 3; }
        fi
      fi
      diff_to_added "$TMP/diff" ;;
    files)
      local f
      for f in "$@"; do
        [ -f "$f" ] && [ -r "$f" ] || { printf 'leak-check: cannot read %s\n' "$f" >&2; exit 2; }
        awk -v f="$f" -v idx="$TMP/idx" '{ print f ":" FNR >> idx }' "$f"
        tr '\000' ' ' < "$f" >> "$TMP/txt"   # NUL bytes: see diff_to_added
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
  printf '#!/bin/sh\n%s\n# Installed by leak-check.sh install-hooks; leak-check.sh uninstall-hooks removes it.\nLC='"'"'%s'"'"'\n[ -f "$LC" ] || { echo "leak-check: $LC is missing; the hook refuses. Run leak-check.sh uninstall-hooks, or install-hooks again from a current checkout." >&2; exit 1; }\n' "$MARKER" "$lc"
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
  bash "$LC" scan --unpushed "$lsha" --remote "$1" </dev/null || rc=1   # a new branch: its commits that are on no remote
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
