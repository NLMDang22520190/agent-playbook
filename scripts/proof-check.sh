#!/usr/bin/env bash
# Check that the evidence blocks in a report (final answer, PR body) still match the working tree.
#   proof-check.sh FILE    one line per "### Evidence:" block: fresh | stale | missing (no tree: line, or tree: none)
#   proof-check.sh --tree  print the current fingerprint (proof-run.sh writes it as "- tree: ...")
# Fingerprint: git write-tree of a temporary index (a copy of the real one, then git add -A), so it covers tracked and
# untracked-not-ignored content, staged or not; .agents/handoff (reports, evidence logs) is left out. The real index is
# never written, and no object is added to the repository: blobs and the tree go to a temporary object directory that
# reads the repository's objects as an alternate, removed on exit. Outside a git repo: none.
# Lines inside ``` fences (command output) are not parsed. As in CommonMark, a fence opens with a line of three or more
# backticks and closes only with a line of at least as many backticks and nothing else but blanks, so a log line such as
# ```diff does not close it.
# Exit: 0 every block fresh | 1 a block stale or missing, or no block | 2 usage | 3 environment
set -u
. "$(dirname "$0")/lib.sh"

usage="usage: proof-check.sh FILE | proof-check.sh --tree"

tree_fp() (
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || { printf 'none\n'; exit 0; }
  cd "$top" || exit 3
  real="$(git rev-parse --git-path index)" || exit 3
  gd="$(git rev-parse --git-dir)" || exit 3
  # Inside the git dir: git prints it in its own path syntax, so the temp index needs no conversion on Git Bash.
  tmp="$(mktemp "$gd/pbtree.XXXXXX" 2>/dev/null)" || tmp="$(mktemp "${TMPDIR:-/tmp}/pbtree.XXXXXX")" || exit 3
  tobj=""
  trap 'rm -f "$tmp" "$tmp.lock" "$tmp.ent"; [ -z "$tobj" ] || rm -rf "$tobj"' EXIT
  # Entries are rebuilt from the real index without their cached stat data (git ls-files -s | update-index --index-info),
  # so git add -A re-hashes every file: a plain copy would let a same-size edit with an unchanged mtime keep its old blob.
  if [ -f "$real" ]; then git ls-files -s -z > "$tmp.ent" || { rm -f "$tmp.ent"; exit 3; }; fi
  rm -f "$tmp"
  GIT_INDEX_FILE="$tmp"; export GIT_INDEX_FILE
  if [ -f "$tmp.ent" ]; then git update-index -z --index-info < "$tmp.ent" || exit 3; fi
  # A temporary object directory inside the repository's own one, so its alternates entry ".." (relative to it) is that
  # directory, in git's path syntax on every platform; git add -A and write-tree store their new objects there only.
  objs="$(git rev-parse --git-path objects)" || exit 3
  tobj="$(mktemp -d "$objs/pbtree.XXXXXX")" || { tobj=""; exit 3; }
  { mkdir "$tobj/info" && printf '..\n' > "$tobj/info/alternates"; } || exit 3
  GIT_OBJECT_DIRECTORY="$tobj"; export GIT_OBJECT_DIRECTORY
  git add -A -- . >/dev/null 2>&1 || exit 3
  git rm -r -q --cached --ignore-unmatch -- .agents/handoff >/dev/null 2>&1 || exit 3
  git write-tree
)

[ $# -eq 1 ] || pb_die "$usage" 2
case "$1" in
  --tree) tree_fp; exit $? ;;
  -*) pb_die "$usage" 2 ;;
esac
f="$1"
{ [ -f "$f" ] && [ -r "$f" ]; } || pb_die "cannot read $f" 2
now="$(tree_fp)" || pb_die "cannot fingerprint the working tree" 3

n=0; bad=0; inblk=0; label=""; rec=""; fence=0; bt='`'; ws=" $(printf '\t')"
emit() { # label recorded-tree
  n=$((n + 1))
  if [ -z "$2" ] || [ "$2" = none ]; then printf 'missing: %s\n' "$1"; bad=1
  elif [ "$2" = "$now" ]; then printf 'fresh: %s\n' "$1"
  else printf 'stale: %s (tree %s, now %s)\n' "$1" "$2" "$now"; bad=1; fi
}
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  case "$line" in
    '```'*) # fence = the opening fence's backtick count while inside one
      ticks="${line%%[!$bt]*}"; rest="${line#"$ticks"}"
      if [ "$fence" = 0 ]; then fence=${#ticks}
      else case "$rest" in *[!"$ws"]*) ;; *) [ "${#ticks}" -lt "$fence" ] || fence=0 ;; esac; fi
      continue ;;
  esac
  [ "$fence" = 0 ] || continue
  case "$line" in
    '### Evidence: '*)
      [ "$inblk" = 0 ] || emit "$label" "$rec"
      inblk=1; label="${line#'### Evidence: '}"; rec="" ;;
    '- tree: '* | 'tree: '*)
      t="${line#*tree: }"; t="${t%% *}"
      if [ "$inblk" = 1 ] && [ -z "$rec" ]; then rec="$t"
      else [ "$inblk" = 0 ] || emit "$label" "$rec"; inblk=1; label="(no heading)"; rec="$t"; fi ;;
  esac
done < "$f"
[ "$inblk" = 0 ] || emit "$label" "$rec"
[ "$n" -gt 0 ] || { printf 'missing: no evidence block in %s\n' "$f"; exit 1; }
exit "$bad"
