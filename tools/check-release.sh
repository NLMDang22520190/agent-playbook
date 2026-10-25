#!/usr/bin/env bash
# Check that a release tag matches VERSION and has a CHANGELOG.md entry; optionally print its notes.
#   tools/check-release.sh vX.Y.Z           check only
#   tools/check-release.sh --notes vX.Y.Z   check, then print the CHANGELOG section body to stdout
# Reads VERSION and CHANGELOG.md from the repository root (the parent of this script's directory).
# Word budgets only go down: evals/word-budgets is compared with the previous release (the newest v* tag reachable from HEAD
# that does not point at HEAD), as tests/test-budgets-down.sh does: a path whose budget rose, or a higher sum over
# AGENTS.global.md and skills/*/SKILL.md, fails. A "# moved-in: PATH WORDS from AGENTS.global.md" line new since that tag
# lets PATH rise by at most WORDS, and the AGENTS.global.md budget must fall by at least the total moved in.
# Skipped when there is no such tag or no table at either point.
# Exit codes: 0 ok, 1 VERSION mismatch, README version badge mismatch, a word budget that rose or missing "## X.Y.Z " entry,
#             2 usage (tag not vX.Y.Z), 3 environment (VERSION or CHANGELOG.md unreadable).
set -u
cd "$(dirname "$0")/.." || exit 3

usage() { echo "usage: tools/check-release.sh [--notes] vX.Y.Z" >&2; exit 2; }

notes=0
if [ "${1:-}" = "--notes" ]; then notes=1; shift; fi
[ "$#" -eq 1 ] || usage
tag="$1"
case "$tag" in *$'\n'*) echo "tag contains a newline" >&2; exit 2 ;; esac   # grep matches per line
printf '%s' "$tag" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || { echo "tag '$tag' is not vX.Y.Z" >&2; usage; }
ver="${tag#v}"

[ -r VERSION ] || { echo "VERSION not readable" >&2; exit 3; }
[ -r CHANGELOG.md ] || { echo "CHANGELOG.md not readable" >&2; exit 3; }

file_ver="$(tr -d ' \t\r\n' < VERSION)"
if [ "$file_ver" != "$ver" ]; then
  echo "VERSION is '$file_ver' but the tag is $tag" >&2
  exit 1
fi
if [ -r README.md ]; then
  # every version badge must be exactly VERSION, optionally followed by "-<colour>" (one dash):
  # 1.2.3--rc.1 (a shields.io pre-release) and 1.2.3.1 are mismatches
  for b in $(grep -oE 'badge/version-[0-9A-Za-z._-]*' README.md); do
    v="${b#badge/version-}"
    case "$v" in
      "$file_ver") continue ;;
      "$file_ver"-?*) case "${v#"$file_ver"-}" in -*) ;; *) continue ;; esac ;;
    esac
    echo "README.md version badge is $v but VERSION is $file_ver" >&2
    exit 1
  done
  # the metrics row "| Always-on block | L / 60 lines · B / 5,000 bytes |" must show the real size
  row="$(grep -E '^\| *Always-on block *\|' README.md | head -n 1)"
  if [ -n "$row" ]; then
    rl="$(printf '%s\n' "$row" | grep -oE '[0-9,]+ +/ +60 lines' | head -n 1)"; rl="${rl%% *}"
    rb="$(printf '%s\n' "$row" | grep -oE '[0-9,]+ +/ +5,000 bytes' | head -n 1)"; rb="${rb%% *}"; rbn="${rb//,/}"   # rb as written (for the message), rbn without commas
    if [ -z "$rl" ] || [ -z "$rb" ]; then
      echo "README.md metrics row 'Always-on block' cannot be read (want 'L / 60 lines · B / 5,000 bytes'): $row" >&2; exit 1
    fi
    al="$(awk 'END { print NR }' AGENTS.global.md 2>/dev/null)"
    ab="$(wc -c < AGENTS.global.md 2>/dev/null | tr -d ' ')"
    if [ -n "$rl" ] && [ "$rl" != "$al" ]; then
      echo "README.md metrics row 'Always-on block' says $rl lines but AGENTS.global.md has ${al:-no} lines" >&2; exit 1
    fi
    if [ -n "$rb" ] && [ "$rbn" != "$ab" ]; then
      echo "README.md metrics row 'Always-on block' says $rb bytes but AGENTS.global.md has ${ab:-no} bytes" >&2; exit 1
    fi
  fi
  # the always-on badge "always--on_block-N%2F60_lines" must show the block's real line count
  for b in $(grep -oE 'always--on_block-[0-9]+%2F60_lines' README.md); do
    n="${b#always--on_block-}"; n="${n%%%*}"
    # awk counts a last line without a final newline too (wc -l does not)
    lines="$(awk 'END { print NR }' AGENTS.global.md 2>/dev/null)"
    if [ "$n" != "$lines" ]; then
      echo "README.md always-on badge says $n lines but AGENTS.global.md has ${lines:-no} lines" >&2
      exit 1
    fi
  done
fi
# word budgets only go down (spec A1b): compare with the previous release tag
if [ -f evals/word-budgets ] && git rev-parse --git-dir >/dev/null 2>&1; then
  head_sha="$(git rev-parse HEAD 2>/dev/null)"; prev=""
  for t in $(git tag -l 'v*' --merged HEAD --sort=-v:refname 2>/dev/null); do
    if [ "$(git rev-list -n 1 "$t" 2>/dev/null)" != "$head_sha" ]; then prev="$t"; break; fi
  done
  if [ -n "$prev" ] && old_wb="$(git show "$prev:evals/word-budgets" 2>/dev/null)"; then
    if ! cmp_out="$(printf '%s\n' "$old_wb" | awk '
      { sub(/\r$/, "") }
      FNR == NR && /^# moved-in: / { seen[$0] = 1; next }
      FNR != NR && /^# moved-in: / {
        if (!($0 in seen) && $4 ~ /^[0-9]+$/ && $5 == "from" && $6 == "AGENTS.global.md") { cr[$3] += $4; tot += $4 }
        next }
      /^#/ || NF < 2 || $2 !~ /^[0-9]+$/ { next }
      function loaded(p) { return p == "AGENTS.global.md" || p ~ /^skills\/[^\/]+\/SKILL\.md$/ }
      FNR == NR { old[$1] = $2; if (loaded($1)) so += $2; next }
      { if (loaded($1)) sn += $2; nw[$1] = $2; if (($1 in old) && $2 + 0 > old[$1] + 0) rose[++n] = $1 }
      END {
        for (i = 1; i <= n; i++) {
          p = rose[i]
          if (nw[p] - old[p] > cr[p] + 0) { print "word budget of " p " rose since " tag ": " old[p] " -> " nw[p] " (moved-in credit " cr[p] + 0 ")"; bad = 1 }
        }
        if (tot > 0 && old["AGENTS.global.md"] - nw["AGENTS.global.md"] < tot) {
          print "moved-in total " tot " is more than the AGENTS.global.md budget drop since " tag ": " old["AGENTS.global.md"] + 0 " -> " nw["AGENTS.global.md"] + 0; bad = 1
        }
        if (sn > so) { print "sum of the always-loaded word budgets rose since " tag ": " so + 0 " -> " sn + 0; bad = 1 }
        exit bad }
    ' tag="$prev" - evals/word-budgets)"; then
      printf '%s\n' "$cmp_out" >&2
      echo "evals/word-budgets: budgets only go down (tests/test-budgets-down.sh)" >&2
      exit 1
    fi
  fi
fi
if ! awk -v h="## $ver " 'index($0, h) == 1 { found = 1 } END { exit !found }' CHANGELOG.md; then
  echo "CHANGELOG.md has no '## $ver ' entry for $tag" >&2
  exit 1
fi

if [ "$notes" -eq 1 ]; then
  awk -v h="## $ver " '
    index($0, h) == 1 { on = 1; next }
    on && /^## / { exit }
    on { print }
  ' CHANGELOG.md
else
  echo "release $tag: VERSION and CHANGELOG.md ok"
fi
