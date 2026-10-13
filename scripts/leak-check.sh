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
#                                          insteadOf; only when all their url/pushurl values are one place), else every commit is scanned.
#                                          Escape for that full scan: PB_LEAK_SCAN_BASE=<full commit id> (exactly 40 lowercase hex
#                                          characters, no name or expression) scans only ID..SHA (the destination is taken to hold
#                                          ID; your explicit choice, never applied by itself, not used when a configured remote
#                                          limits the scan). No silent fallback: an id that is not a full commit id of this
#                                          repository, an empty range (ID is SHA or a descendant of it) or an ID that is not an
#                                          ancestor of SHA exits 3
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
  sed -n '2,/^# Exit:/p' "$0" | sed 's/^# \{0,1\}//' >&2
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
    printf 'VIOLATION (mode): a path contains a newline or a \\002 byte; the mode check is incomplete\n'
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

# win_path P -> P in one spelling on Windows shells only. Git Bash hands native git a POSIX path converted (/tmp/x and
# /c/x become C:/...), keeps C:/x in the config and expands insteadOf to either form, so a local path is mapped with
# `cygpath -m` (all of /tmp/x, /c/x, C:/x -> C:/x) and the drive letter lowercased; without cygpath, C:/x -> /c/x.
# Elsewhere P is unchanged (c:/x is a host there).
win_path() {
  case "$(uname -s 2>/dev/null)" in
    MINGW* | MSYS* | CYGWIN*)
      case "$1" in
        /* | [A-Za-z]:/*)
          local w=""
          if command -v cygpath >/dev/null 2>&1; then w="$(cygpath -m -- "$1" 2>/dev/null)" || w=""; fi
          case "$w" in
            [A-Za-z]:/*) printf '%s%s' "$(printf '%s' "${w%"${w#?}"}" | tr 'A-Z' 'a-z')" "${w#?}"; return 0 ;;
          esac
          case "$1" in
            [A-Za-z]:/*) printf '/%s%s' "$(printf '%s' "${1%"${1#?}"}" | tr 'A-Z' 'a-z')" "${1#?:}"; return 0 ;;
          esac ;;
      esac ;;
  esac
  printf '%s' "$1"
}

# same_place A B -> 0 when two destinations are one place: the same string (after win_path). Nothing else is normalized
# (a trailing .git or /, ssh vs https: see url_remotes).
same_place() {
  [ "$(win_path "$1")" = "$(win_path "$2")" ]
}

# url_remotes NAME -> the configured remotes whose destination NAME is, one per line. NAME counts for a remote R when
# every url and pushurl value of R names one place (compared after insteadOf expansion: git remote get-url --all, and
# --push --all) and NAME is one of R's raw values or, expanded (git ls-remote --get-url NAME), is that place. A trailing
# .git or /, or ssh vs https forms, are not normalized: such a NAME matches nothing (the caller then scans everything).
url_remotes() {
  local name="$1" exp r raws exps first hit v mixed
  [ -n "$name" ] || return 0
  exp="$(git ls-remote --get-url "$name" 2>/dev/null)" || exp=""
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    exps="$( { git remote get-url --all "$r" 2>/dev/null; git remote get-url --push --all "$r" 2>/dev/null; } )"
    [ -n "$exps" ] || continue
    first="$(printf '%s\n' "$exps" | sed -n 1p)"
    mixed=0
    while IFS= read -r v; do
      same_place "$v" "$first" || mixed=1   # the values name different places
    done <<EOF
$exps
EOF
    [ "$mixed" = 0 ] || continue
    hit=0
    [ -z "$exp" ] || ! same_place "$exp" "$first" || hit=1
    raws="$( { git config --get-all "remote.$r.url" 2>/dev/null; git config --get-all "remote.$r.pushurl" 2>/dev/null; } )"
    while IFS= read -r v; do
      [ -z "$v" ] || ! same_place "$v" "$name" || hit=1
    done <<EOF
$raws
EOF
    [ "$hit" = 0 ] || printf '%s\n' "$r"
  done <<EOF
$(git remote 2>/dev/null)
EOF
}

# push_rewritten NAME -> 0 when some url.<base>.pushInsteadOf value is a prefix of NAME (the raw NAME, or NAME after
# insteadOf expansion): git then pushes somewhere else than NAME names, so no remote's refs say what that place holds.
# The key names are listed on their own (git config --name-only: <base> may hold dots or spaces, nothing is split on the
# key) and each key's values are read by name. An empty value is skipped.
push_rewritten() {
  local name="$1" exp v key
  exp="$(git ls-remote --get-url "$name" 2>/dev/null)" || exp=""
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    while IFS= read -r v; do
      [ -n "$v" ] || continue
      case "$name" in "$v"*) return 0 ;; esac
      case "$exp" in "$v"*) [ -z "$exp" ] || return 0 ;; esac
    done <<EOF
$(git config --get-all "$key" 2>/dev/null)
EOF
  done <<EOF
$(git config --name-only --get-regexp '^url\..*\.pushinsteadof$' 2>/dev/null | sort -u)
EOF
  return 1
}

# dest_owned DEST... -> appends to $TMP/own the owned refs of the remotes the destinations are, and returns 0; returns 1
# when some DEST is rewritten by pushInsteadOf or is no configured remote's place (the caller scans the full range).
dest_owned() {
  local d rems rn all=""
  for d in "$@"; do
    push_rewritten "$d" && return 1
    rems="$(url_remotes "$d")"
    [ -n "$rems" ] || return 1
    all="$all
$rems"
  done
  while IFS= read -r rn; do
    [ -n "$rn" ] || continue
    owned_refs "$rn" >> "$TMP/own"
  done <<EOF
$all
EOF
  return 0
}

# remote_pushes_home R -> 0 when every push destination of configured remote R (git remote get-url --push --all: pushurl
# and pushInsteadOf already applied, pushInsteadOf ignored when a pushurl is set) is R's FIRST url. Git fetches only from
# the first url, so refs/remotes/R/* reflect that url alone; a second url or a pushurl elsewhere holds none of those commits.
remote_pushes_home() {
  local r="$1" pd fu d
  pd="$(git remote get-url --push --all "$r" 2>/dev/null)" || return 1
  fu="$(git remote get-url "$r" 2>/dev/null)" || return 1
  [ -n "$pd" ] || return 1
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    same_place "$d" "$fu" || return 1
  done <<EOF
$pd
EOF
  return 0
}

in_repo() { git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "leak-check: not a git repository" >&2; exit 3; }; }

do_scan() {
  local mode="" val="" remote="" hasremote=0 fullscan=0 bsha="" fullnote="" nbase=0
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
            if remote_pushes_home "$remote"; then
              owned_refs "$remote" > "$TMP/own"   # owns no ref yet: the list is empty, nothing is excluded
            else
              # the push goes elsewhere (pushurl, pushInsteadOf): treat it as a push to those destinations
              local pd d
              pd="$(git remote get-url --push --all "$remote" 2>/dev/null)" || pd=""
              local fu1 hf=0
              fu1="$(git remote get-url "$remote" 2>/dev/null)" || fu1=""
              set --
              while IFS= read -r d; do
                [ -z "$d" ] && continue
                set -- "$@" "$d"
                [ -z "$fu1" ] || ! same_place "$d" "$fu1" || hf=1
              done <<EOF
$pd
EOF
              if [ $# -eq 0 ] || ! dest_owned "$@"; then
                : > "$TMP/own"; fullscan=1
                if [ "$hf" = 1 ]; then
                  fullnote="$(printf 'leak-check: %s pushes to a place its fetched refs do not cover; scanning the full range (push through a named remote to limit it) or set PB_LEAK_SCAN_BASE=<full commit id> to scan only that id..SHA' "$remote")"
                else
                  fullnote="$(printf 'leak-check: %s pushes to a place no configured remote owns; scanning the full range (push through a named remote to limit it) or set PB_LEAK_SCAN_BASE=<full commit id> to scan only that id..SHA' "$remote")"
                fi
              fi
            fi
          else
            if push_rewritten "$remote" || ! dest_owned "$remote"; then
              : > "$TMP/own"; fullscan=1
              fullnote="$(printf 'leak-check: %s is not a configured remote; scanning the full range (push through a named remote to limit it) or set PB_LEAK_SCAN_BASE=<full commit id> to scan only that id..SHA' "$remote")"
            fi
          fi
          LC_ALL=C sort -u "$TMP/own" | sed 's/^/^/' > "$TMP/not"
          # PB_LEAK_SCAN_BASE=<full commit id>: the user's explicit choice, only for a full-range scan; the destination is taken to hold it.
          # Exactly 40 lowercase hex: a name or an expression can move or be rewritten between this check and the push.
          if [ "$fullscan" = 1 ] && [ -n "${PB_LEAK_SCAN_BASE:-}" ]; then
            case "$PB_LEAK_SCAN_BASE" in
              *[!0-9a-f]*) bsha="" ;;
              *) if [ "${#PB_LEAK_SCAN_BASE}" -eq 40 ]; then bsha="$PB_LEAK_SCAN_BASE"; else bsha=""; fi ;;
            esac
            [ -n "$bsha" ] || { printf 'leak-check: PB_LEAK_SCAN_BASE=%s must be a full commit id (40 lowercase hex characters); refusing to fall back to the full range (unset it to scan everything)\n' "$(printf '%s' "$PB_LEAK_SCAN_BASE" | LC_ALL=C tr -c 'A-Za-z0-9._@{}~^/+=:-' '?' | cut -c1-64)" >&2; exit 3; }
            git rev-parse --verify -q "${bsha}^{commit}" >/dev/null 2>&1 ||
              { printf 'leak-check: PB_LEAK_SCAN_BASE=%s is not a commit in this repository; it must be a full commit id; refusing to fall back to the full range (unset it to scan everything)\n' "$bsha" >&2; exit 3; }
            if git merge-base --is-ancestor "$val" "$bsha" >/dev/null 2>&1; then
              printf 'leak-check: PB_LEAK_SCAN_BASE=%s is the pushed commit or one of its descendants, so the range is empty: nothing to scan; unset PB_LEAK_SCAN_BASE\n' "$bsha" >&2; exit 3
            fi
            git merge-base --is-ancestor "$bsha" "$val" >/dev/null 2>&1 ||
              { printf 'leak-check: PB_LEAK_SCAN_BASE=%s is not an ancestor of the pushed commit; it must be a full commit id of a commit the pushed commit contains; refusing to fall back to the full range (unset it to scan everything)\n' "$bsha" >&2; exit 3; }
            printf '^%s\n' "$bsha" >> "$TMP/not"
            nbase="$(git rev-list --count "$bsha..$val" 2>/dev/null)" || nbase="?"
            case "$nbase" in 1) printf 'leak-check: PB_LEAK_SCAN_BASE is set: scanning 1 commit after %s\n' "$bsha" >&2 ;; *) printf 'leak-check: PB_LEAK_SCAN_BASE is set: scanning %s commits after %s\n' "$nbase" "$bsha" >&2 ;; esac
          elif [ -n "$fullnote" ]; then
            printf '%s\n' "$fullnote" >&2
          fi
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
