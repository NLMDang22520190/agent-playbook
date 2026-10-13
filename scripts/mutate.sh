#!/usr/bin/env bash
# Mutation testing on the changed lines of a diff: does the test command notice a flipped operator?
#   mutate.sh --base REF --test "CMD" [--max N] [--timeout S] [--exclude GLOB]... [--include-docs] [--fail-under PCT]
#
# Changed lines = the added lines of `git diff -U0 -M --diff-filter=AMR REF...HEAD` (merge base; deleted and
# binary files ignored; a rename counts only its changed lines). Only regular files count: symlinks and submodules
# are skipped. tests/*, markdown (*.md: prose gives false survivors; --include-docs brings it back) and every
# --exclude glob (repeatable, e.g. '*_test.go') are left out, and so are comment lines (first non-blank text is
# #, //, * or /*).
# One mutant per (line, operator), on the first whole-token occurrence on the line, in this order:
#   == != | === !== | -eq -ne | -lt -ge | -gt -le | && || | true false | return 0 return 1
#   and, only in non-shell files (shell uses < and > for redirection and * for globs): < >= | > <=
#   and, only in files with a code extension (js ts jsx tsx mjs cjs py go rs c h cc cpp hpp java kt rb php cs
#   swift scala; so not shell, YAML, Makefile, Dockerfile or extension-less scripts): + - | * /
#   (+ - * / only as a binary operator with a blank (space or tab) and an operand on both sides, so ++ += -> a-b
#   /* and a YAML "- item" are left alone; not inside a trailing " //" comment or a /* ... */ comment; and not a
#   * after import or export, as in import * as x, import d, * as x, export * from). === and !== are swapped
#   as whole tokens; == and != never match inside them.
# At most --max mutants (default 20).
#
# Safety: your work tree is never written. Only HEAD is mutated, in a throwaway `git worktree` under
# ${TMPDIR:-/tmp}; CMD runs there (untracked or ignored files such as node_modules are not there). The worktree
# is removed on exit. Each run writes its pid and its start time (ps lstart) to <its temp dir>/owner. At the start a run removes only the worktrees
# of dead owners or reused pids (a stale one left by a kill -9); a live run's worktree is never touched. A temp dir without an
# owner file is removed only when it is older than 24 hours.
# Before the first mutant CMD runs once unmutated; when it does not pass, exit 4.
# Every CMD run is limited by --timeout S (default 120): a portable background watchdog, no GNU timeout.
# A mutant where CMD exits 0 survived; a failing or timed-out run killed it.
# Output: "survived: file:line: <original line> -> <mutant line>", "killed (timeout): file:line", then
# "mutants: N, killed: K, survived: S". --fail-under PCT: exit 1 when K*100/N (integer division) < PCT.
# A mutant that cannot be written into the worktree prints "error: file:line: ..." and counts as neither killed nor
# survived; the exit is then 5 (when --fail-under is not also missed).
# Exit: 0 ok | 1 below --fail-under | 2 usage | 3 not a git repository or no worktree | 4 baseline fails
#       5 a mutant could not be applied
set -u

usage() {
  echo "usage: mutate.sh --base REF --test \"CMD\" [--max N] [--timeout S] [--exclude GLOB]... [--include-docs] [--fail-under PCT]" >&2
  exit 2
}
die() { printf 'error: %s\n' "$1" >&2; exit "${2:-1}"; }
is_uint() { case "$1" in "" | *[!0-9]*) return 1 ;; esac; return 0; }

base=""; cmd=""; max=20; tmo=120; failunder=""; excludes=""; docs=0
while [ $# -gt 0 ]; do
  if [ "$1" = "--include-docs" ]; then docs=1; shift; continue; fi
  case "$1" in
    --base | --test | --max | --timeout | --exclude | --fail-under) [ $# -ge 2 ] || usage ;;
    *) usage ;;
  esac
  case "$1" in
    --base) base="$2" ;;
    --test) cmd="$2" ;;
    --max) is_uint "$2" || usage; max="$2" ;;
    --timeout) is_uint "$2" || usage; [ "$2" -ge 1 ] || usage; tmo="$2" ;;
    --fail-under) is_uint "$2" || usage; failunder="$2" ;;
    --exclude) excludes="$excludes$2
" ;;
  esac
  shift 2
done
[ -n "$base" ] && [ -n "$cmd" ] || usage

root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not a git repository" 3
[ -n "$root" ] || die "not a git repository" 3
git -C "$root" rev-parse --verify -q "$base^{commit}" >/dev/null 2>&1 || die "unknown base: $base" 2

tmpbase="${TMPDIR:-/tmp}"
tmpbase="${tmpbase%/}"
[ -n "$tmpbase" ] || tmpbase="/tmp"
realbase="$(cd "$tmpbase" 2>/dev/null && pwd -P)" || die "cannot use the temp dir $tmpbase" 3
altbase=""
if command -v cygpath >/dev/null 2>&1; then altbase="$(cygpath -m "$realbase" 2>/dev/null || true)"; fi

run="$(mktemp -d "$tmpbase/pbmutate.XXXXXX")" || die "cannot create a temp dir in $tmpbase" 3
# owner file: line 1 = pid, line 2 = its start string (a v0.22.4 file has line 1 only). The start string is, where
# /proc/PID/stat exists (Linux), the start ticks (field 22: immune to wall-clock steps from NTP or a WSL2 resume), else
# the trimmed ps lstart. Only values of the same kind are compared: all digits = ticks.
pticks() { sed 's/^.*) //' "/proc/$1/stat" 2>/dev/null | awk '{ print $20 }' | sed 1q; }
plstart() { LC_ALL=C TZ=UTC0 ps -o lstart= -p "$1" 2>/dev/null | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sed 1q; }
pstart() { # PID [KIND]: KIND "ticks" or "lstart" forces that kind; the default is ticks when /proc has the pid
  case "${2:-}" in
    ticks) pticks "$1" ;;
    lstart) plstart "$1" ;;
    *) if [ -r "/proc/$1/stat" ]; then pticks "$1"; else plstart "$1"; fi ;;
  esac
}
printf '%s\n%s\n' "$$" "$(pstart "$$")" > "$run/owner"
cr="$(printf '\r')"
wt="$run/wt"

# a stale worktree under our prefix: its owner is dead (a previous run was killed with kill -9). A live run's
# worktree is never touched; a dir without an owner file is only removed when it is older than 24 hours.
stale="$(git -C "$root" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')"
printf '%s\n' "$stale" | while IFS= read -r wp; do
  case "$wp" in
    "$realbase"/pbmutate.*/wt | "${altbase:-$realbase}"/pbmutate.*/wt)
      d="$(dirname "$wp")"
      opid=""
      if [ -f "$d/owner" ]; then
        ostart=""
        { read -r opid && read -r ostart; } < "$d/owner" 2>/dev/null || true
        opid="${opid%"$cr"}"; ostart="${ostart%"$cr"}"
        case "$opid" in "" | *[!0-9]*) opid="" ;; esac
        if [ -n "$opid" ] && kill -0 "$opid" 2>/dev/null; then
          # alive, unless the pid was reused: both start strings known and different (an empty or failed ps = alive)
          nstart=""
          if [ -n "$ostart" ]; then
            case "$ostart" in *[!0-9]*) nstart="$(pstart "$opid" lstart)" ;; *) nstart="$(pstart "$opid" ticks)" ;; esac
          fi
          if [ -z "$ostart" ] || [ -z "$nstart" ] || [ "$ostart" = "$nstart" ]; then continue; fi
        fi
      elif [ -d "$d" ] && [ -z "$(find "$d" -maxdepth 0 -mmin +1440 2>/dev/null)" ]; then
        continue
      fi
      git -C "$root" worktree remove --force "$wp" >/dev/null 2>&1 || true
      rm -rf "$d"
      ;;
  esac
done
git -C "$root" worktree prune >/dev/null 2>&1 || true
curpid=""
cleanup() {
  if [ -n "$curpid" ]; then kill -9 -- "-$curpid" 2>/dev/null; kill -9 "$curpid" 2>/dev/null; fi
  git -C "$root" worktree remove --force "$wt" >/dev/null 2>&1 || true
  rm -rf "$run"
  git -C "$root" worktree prune >/dev/null 2>&1 || true
}
trap cleanup EXIT
trap 'exit 1' INT TERM HUP

# ---- the changed lines ----
git -C "$root" -c core.quotepath=off diff --no-ext-diff --no-color -M --diff-filter=AMR --raw "$base...HEAD" > "$run/names" \
  || die "git diff failed for $base...HEAD" 2
: > "$run/files"
tab="$(printf '\t')"
set -f
while IFS= read -r rec; do
  [ -n "$rec" ] || continue
  meta="${rec%%"$tab"*}"
  f="${rec##*"$tab"}"
  # shellcheck disable=SC2086  # split ":oldmode newmode oldsha newsha status" on blanks
  set -- $meta
  # only regular files: a symlink (120000) or a submodule (160000) is never mutated
  case "${2:-}" in 100644 | 100755) ;; *) continue ;; esac
  [ -n "$f" ] || continue
  skip=0
  case "$f" in tests/*) skip=1 ;; esac
  if [ "$docs" = 0 ]; then case "$f" in *.md) skip=1 ;; esac; fi
  if [ "$skip" = 0 ] && [ -n "$excludes" ]; then
    while IFS= read -r g; do
      [ -n "$g" ] || continue
      # shellcheck disable=SC2254  # the exclude is a glob on purpose
      case "$f" in $g) skip=1; break ;; esac
    done <<EOF
$excludes
EOF
  fi
  [ "$skip" = 1 ] || printf '%s\n' "$f" >> "$run/files"
done < "$run/names"
set +f

git -C "$root" -c core.quotepath=off diff --no-ext-diff --no-color -U0 -M --diff-filter=AMR --src-prefix=a/ --dst-prefix=b/ "$base...HEAD" > "$run/diff" \
  || die "git diff failed for $base...HEAD" 2

: > "$run/mutants"
if [ "$max" -gt 0 ] && [ -s "$run/files" ]; then
  awk '
    function inset(c, set) { return c != "" && index(set, c) > 0 }
    function isblank(c) { return c == " " || c == "\t" }
    function isword(c) { return c != "" && c ~ /[A-Za-z0-9_]/ }
    function iswordh(c) { return c != "" && c ~ /[A-Za-z0-9_-]/ }
    function ok(kind, pre, post, pp, pn) {
      if (kind == "eq") return !inset(pre, "=!<>") && post != "="
      if (kind == "ne") return post != "="
      if (kind == "seq") return !inset(pre, "=!<>") && post != "="
      if (kind == "sne") return post != "="
      if (kind == "arith") return isblank(pre) && isblank(post) && pp != "" && pp != " " && pp != "\t" && pn != "" && pn != " " && pn != "\t"
      if (kind == "word") return !iswordh(pre) && !iswordh(post)
      if (kind == "and") return pre != "&" && post != "&"
      if (kind == "or") return pre != "|" && post != "|"
      if (kind == "bool") return !isword(pre) && !isword(post)
      if (kind == "ret") return !isword(pre) && !isword(post) && post != "."
      if (kind == "lt") return !inset(pre, "<") && !inset(post, "=<>-")
      if (kind == "ge") return !inset(pre, "><=") && post != "="
      if (kind == "gt") return !inset(pre, "-=><|%") && !inset(post, "=>&")
      if (kind == "le") return !inset(pre, "<") && !inset(post, "=>")
      return 0
    }
    function isimport(pfx) {
      return pfx ~ /(^|[^A-Za-z0-9_$])(import|export)[ \t]*$/ || pfx ~ /(^|[^A-Za-z0-9_$])import[ \t]+[A-Za-z0-9_$]+[ \t]*,[ \t]*$/
    }
    function nocomment(s,   i, n, c, j, e, out) {
      n = length(s); out = ""; i = 1
      while (i <= n) {
        c = substr(s, i, 2)
        if (c == "/*") {
          j = index(substr(s, i + 2), "*/")
          e = (j > 0) ? i + j + 2 : n
          while (i <= e) { out = out "_"; i++ }
        } else if (c == "//" && (i == 1 || substr(s, i - 1, 1) ~ /[ \t]/)) {
          while (i <= n) { out = out "_"; i++ }
        } else { out = out substr(s, i, 1); i++ }
      }
      return out
    }
    function find(s, tok, kind,   off, p, pre, post, pp, pn) {
      off = 0
      while ((p = index(substr(s, off + 1), tok)) > 0) {
        p += off
        pre = (p > 1) ? substr(s, p - 1, 1) : ""
        post = substr(s, p + length(tok), 1)
        pp = (p > 2) ? substr(s, p - 2, 1) : ""
        pn = substr(s, p + length(tok) + 1, 1)
        if (ok(kind, pre, post, pp, pn) && !(kind == "arith" && tok == "*" && isimport(substr(s, 1, p - 1)))) return p
        off = p
      }
      return 0
    }
    function add(tok, repl, kind, nonshell) {
      nops++; otok[nops] = tok; orepl[nops] = repl; okind[nops] = kind; onon[nops] = nonshell
    }
    function process(n, line,   t, i, p, isshell, iscode, code) {
      t = line
      sub(/^[ \t]+/, "", t)
      if (t == "" || substr(t, 1, 1) == "#" || substr(t, 1, 2) == "//" || substr(t, 1, 1) == "*" || substr(t, 1, 2) == "/*") return
      isshell = (file ~ /\.(sh|bash|zsh|ksh)$/)
      iscode = (file ~ /\.(js|ts|jsx|tsx|mjs|cjs|py|go|rs|c|h|cc|cpp|hpp|java|kt|rb|php|cs|swift|scala)$/)
      code = nocomment(line)
      for (i = 1; i <= nops; i++) {
        if (onon[i] && isshell) continue
        if (onon[i] == 2 && !iscode) continue
        p = find((onon[i] == 2) ? code : line, otok[i], okind[i])
        if (p > 0) print file SEP n SEP line SEP (substr(line, 1, p - 1) orepl[i] substr(line, p + length(otok[i])))
      }
    }
    BEGIN {
      SEP = "\034"
      add("==", "!=", "eq", 0);      add("!=", "==", "ne", 0)
      add("===", "!==", "seq", 0);   add("!==", "===", "sne", 0)
      add("-eq", "-ne", "word", 0);  add("-ne", "-eq", "word", 0)
      add("-lt", "-ge", "word", 0);  add("-ge", "-lt", "word", 0)
      add("-gt", "-le", "word", 0);  add("-le", "-gt", "word", 0)
      add("&&", "||", "and", 0);     add("||", "&&", "or", 0)
      add("true", "false", "bool", 0); add("false", "true", "bool", 0)
      add("return 0", "return 1", "ret", 0); add("return 1", "return 0", "ret", 0)
      add("<", ">=", "lt", 1);       add(">=", "<", "ge", 1)
      add(">", "<=", "gt", 1);       add("<=", ">", "le", 1)
      add("+", "-", "arith", 2);     add("-", "+", "arith", 2)
      add("*", "/", "arith", 2);     add("/", "*", "arith", 2)
    }
    FNR == NR { allowed[$0] = 1; next }
    /^diff --git / { inhunk = 0; file = ""; next }
    inhunk == 0 && /^\+\+\+ / {
      f = substr($0, 5); sub(/\t.*$/, "", f)
      if (f == "/dev/null") file = ""
      else { sub(/^b\//, "", f); file = (f in allowed) ? f : "" }
      next
    }
    /^@@ / {
      inhunk = 1
      s = $0; sub(/^@@ [^+]*\+/, "", s); sub(/[, ].*$/, "", s)
      newln = s + 0
      next
    }
    inhunk == 1 && substr($0, 1, 1) == "+" {
      if (file != "") process(newln, substr($0, 2))
      newln++
    }
  ' "$run/files" "$run/diff" | sed "${max}q" > "$run/mutants"
fi

# ---- running a command with a watchdog ----
# run_cmd -> 0 passed, 1 failed, 2 timed out. The command runs in its own process group (set -m) so that
# a timeout also stops what it started.
set -m
run_cmd() {
  rm -f "$run/timeout"
  ( cd "$wt" && exec bash -c "$cmd" ) >/dev/null 2>&1 </dev/null &
  curpid=$!
  (
    # A subshell can still hold the parent's EXIT/TERM traps for a moment after the fork: a signal in that window ran
    # cleanup() here and removed the live worktree. So the watchdog drops the traps first and is never signalled:
    # it ends by itself within a second of the command ending.
    trap - EXIT INT TERM HUP
    n=0
    while [ "$n" -lt "$tmo" ]; do
      sleep 1
      if ! kill -0 "$curpid" 2>/dev/null; then exit 0; fi
      if ! kill -0 "$$" 2>/dev/null; then kill -9 -- "-$curpid" 2>/dev/null; kill -9 "$curpid" 2>/dev/null; exit 0; fi
      n=$((n + 1))
    done
    : > "$run/timeout"
    kill -9 -- "-$curpid" 2>/dev/null
    kill -9 "$curpid" 2>/dev/null
  ) >/dev/null 2>&1 &
  { wait "$curpid"; } 2>/dev/null
  rc=$?
  curpid=""
  if [ -f "$run/timeout" ]; then return 2; fi
  [ "$rc" -eq 0 ] && return 0
  return 1
}

total=0; killed=0; survived=0; errors=0
if [ -s "$run/mutants" ]; then
  git -C "$root" worktree add -q --detach "$wt" HEAD >/dev/null 2>&1 || die "cannot create a throwaway worktree" 3
  run_cmd; brc=$?
  if [ "$brc" -ne 0 ]; then
    msg="tests fail without mutation in the throwaway worktree (untracked or ignored files such as node_modules are not there)"
    [ "$brc" -eq 2 ] && msg="tests time out without mutation in the throwaway worktree (--timeout $tmo s)"
    die "$msg" 4
  fi
  soh="$(printf '\034')"   # ASCII field separator: bash 3.2 (macOS) uses \001 internally (CTLESC), so IFS cannot split on it
  while IFS="$soh" read -r f n orig mut; do
    [ -n "$f" ] || continue
    if [ ! -f "$wt/$f" ] || [ -L "$wt/$f" ] ||
       ! cp "$wt/$f" "$run/orig" 2>/dev/null ||
       ! M="$mut" awk -v n="$n" 'NR == n { print ENVIRON["M"]; next } { print }' "$run/orig" > "$run/mutf" 2>/dev/null ||
       ! { cat "$run/mutf" > "$wt/$f"; } 2>/dev/null; then
      printf 'error: %s:%s: cannot apply the mutant (not a writable regular file in the worktree)\n' "$f" "$n"
      errors=$((errors + 1))
      continue
    fi
    total=$((total + 1))
    run_cmd; rc=$?
    cat "$run/orig" > "$wt/$f"
    case "$rc" in
      0) survived=$((survived + 1)); printf 'survived: %s:%s: %s -> %s\n' "$f" "$n" "$orig" "$mut" ;;
      2) killed=$((killed + 1)); printf 'killed (timeout): %s:%s\n' "$f" "$n" ;;
      *) killed=$((killed + 1)) ;;
    esac
  done < "$run/mutants"
fi

printf 'mutants: %d, killed: %d, survived: %d\n' "$total" "$killed" "$survived"
if [ -n "$failunder" ] && [ "$total" -gt 0 ] && [ $((killed * 100 / total)) -lt "$failunder" ]; then
  exit 1
fi
[ "$errors" -eq 0 ] || exit 5
exit 0
