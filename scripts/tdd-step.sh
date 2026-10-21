#!/usr/bin/env bash
# One RED or GREEN step of the TDD workflow: role gate, then the test command as evidence.
#   tdd-step.sh red   --message M [--base REF] [--baseline FILE] [--commit] -- CMD [ARGS...]
#   tdd-step.sh green --base REF --message M [--baseline FILE] [--commit] -- CMD [ARGS...]
# red:   role-gate.sh check tester [--base REF], then proof-run.sh --label red -- CMD. Passes only if the
#        gate passes AND CMD fails (a test that does not fail is not RED). --commit commits all changes
#        as "test(red): M" and prints RED=<sha>. Pass --base <sha recorded before the tester started>
#        so a tester that commits is judged; without it the step prints a note (stderr) and the gate
#        compares with HEAD.
# green: role-gate.sh check implementer --base REF, then proof-run.sh --label green -- CMD. Passes
#        only if the gate passes AND CMD exits 0. --commit commits all changes as "feat(green): M".
# Both paths, with and without --commit (v0.24.22): a changed path with a newline or a \002 byte is refused
#        before CMD runs (commit by hand); the work tree is snapshotted (role-gate.sh snapshot) and HEAD is
#        read before and after CMD, and the gate runs again after it: a changed manifest (CMD wrote, edited
#        or committed a file), a moved HEAD or a failing second gate (its output is printed only then)
#        refuse the step, so a file CMD wrote is never committed unjudged and never printed in a commit
#        command. With --commit the commit is then checked: HEAD must be one commit on the pre-run HEAD
#        and the committed entry (mode, blob, or absence) of every judged path must equal the entry that
#        was judged (the real index after the staging on the default path; a scratch index built like
#        git commit --only builds its own on --baseline), so a git hook cannot change what is committed;
#        otherwise the commit is undone and the index restored.
# The branch (v0.24.23): git symbolic-ref -q HEAD is read before and after CMD (0 attached, 1 detached, else
#        exit 3); a changed branch refuses the step (exit 1, nothing committed). With --commit the branch list
#        (refs/heads) is recorded first; after every commit HEAD must still be on the pre-run branch (or detached
#        as before), that branch must be exactly one new commit on the pre-run HEAD and no other branch may be
#        moved, created or deleted. The undo moves only the pre-run branch back, by compare-and-swap (git
#        update-ref R pre_head <sha read now>; a detached run is detached at pre_head again), re-attaches HEAD
#        only when R is back and restores the index. Only R and HEAD changed and all steps ran: exit 1, nothing
#        committed. Otherwise exit 3, naming the refs and shas left behind and HEAD (a branch is never deleted
#        or created, also when git commit fails after a hook switched the branch). A hook that switched HEAD to
#        another branch took the role files out of the work tree: the undo still runs, then exit 3 names the commit
#        C and its parent and prints the recovery line git checkout C -- . (never "nothing committed"). A failed
#        git commit compares the branch list too (and in a detached run the sha): same undo, exit 3.
#        Another worktree of the same repository that commits while the step runs can move a branch the step
#        compares: that is exit 3 too (the step cannot tell it from a hook).
# Nested repositories (v0.24.24): an untracked nested repository is refused before CMD runs (exit 1, nothing
#        committed), also on --baseline and also one that existed before the snapshot: a git status row ending in
#        a slash outside .agents/handoff/. A staged gitlink (mode 160000) that HEAD lacks is refused too. The message
#        names the path and hints at .git/info/exclude or .gitignore. Not refused: a nested repository under
#        .agents/handoff/, a submodule tracked in HEAD, an empty directory.
# Limits (v0.24.23): a commit the test command makes inside an untracked nested repo (a gitlink the snapshot
#        records as unhashable) is therefore never reached. On --baseline, a path whose exec bit staged in the index git commit
#        --only would not carry is refused (print mode warns); only a mode staged in the index is checked, so a
#        disk-only exec bit under core.filemode=false is not.
# --baseline FILE (red and green): passed to the gate (a manifest from role-gate.sh snapshot, for a repo
#        that was already dirty when the role started). Then --commit commits ONLY the role's paths:
#        git status (-z, all untracked files, both sides of a rename) minus the paths the gate reported
#        as unchanged since the baseline minus .agents/handoff/; a path with a control character other
#        than TAB is refused (commit by hand); an empty list commits nothing; other unchanged-notes after
#        CMD refuse the step. Role paths are committed with literal pathspecs (GIT_LITERAL_PATHSPECS=1)
#        and the baseline paths keep their index and work-tree state. Without --commit the exact
#        commands are printed, every path shell-quoted.
# --commit adds .agents/handoff/ to .git/info/exclude when not ignored (prints a notice).
# Without --commit nothing is committed; the commit command is printed instead (ask-before-commit).
# Runs in the current project (git top-level). Gate and evidence output pass through.
# Exit codes: 0 pass, 1 gate or expectation failed (nothing committed), 2 usage,
#             3 environment (not a git work tree, cannot commit).
set -u
. "$(dirname "$0")/lib.sh"
here="$(cd "$(dirname "$0")" && pwd)"

usage() {
  echo "usage: tdd-step.sh red [--base REF] [--baseline FILE] --message M [--commit] -- CMD..." >&2
  echo "       tdd-step.sh green --base REF [--baseline FILE] --message M [--commit] -- CMD..." >&2
  exit 2
}

step="${1:-}"
case "$step" in red|green) shift ;; *) usage ;; esac

msg=""; base=""; baseline=""; commit=0
while [ $# -gt 0 ]; do
  case "$1" in
    --message)  [ $# -ge 2 ] || usage; msg="$2"; shift 2 ;;
    --base)     [ $# -ge 2 ] || usage; base="$2"; shift 2 ;;
    --baseline) [ $# -ge 2 ] && [ -n "$2" ] || usage; baseline="$2"; shift 2 ;;
    --commit)   commit=1; shift ;;
    --) shift; break ;;
    *) usage ;;
  esac
done
[ -n "$msg" ] || usage
[ $# -ge 1 ] || usage
if [ "$step" = "green" ]; then [ -n "$base" ] || usage; fi
# a relative manifest path is the caller's, not the project root's
if [ -n "$baseline" ]; then
  case "$baseline" in /* | [A-Za-z]:[/\\]*) ;; *) baseline="$PWD/$baseline" ;; esac
fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || pb_die "not inside a git work tree" 3
cd "$(pb_root_dir)" || pb_die "cannot enter the project root" 3

NL=$'\n'
NOTEP="note: unchanged since the baseline: "
gate_args=()
if [ "$step" = "red" ]; then
  role=tester
  if [ -n "$base" ]; then
    gate_args=(--base "$base")
  else
    echo "note: no --base: a tester that commits is not judged; pass the sha from before the role" >&2
  fi
  subject="test(red): $msg"
else
  role=implementer
  gate_args=(--base "$base")
  subject="feat($step): $msg"
fi
if [ -n "$baseline" ]; then gate_args+=(--baseline "$baseline"); fi

run_gate() { bash "$here/role-gate.sh" check "$role" ${gate_args[@]+"${gate_args[@]}"}; }
refuse() { echo "error: $1 - nothing committed" >&2; exit 1; }
# the "unchanged since the baseline" note lines of a gate output
notes_of() { printf '%s\n' "$1" | grep -F "$NOTEP" || true; }

# Before tdd-step stages anything: remember HEAD and the index file (a copy outside the work tree).
save_state() {
  pre_head="$(git rev-parse HEAD)" || pb_die "cannot read HEAD" 3
  R="$branch_before"
  git for-each-ref --format='%(refname) %(objectname)' refs/heads > "$tmpd/refs0" || pb_die "cannot list the branches" 3
  idx="$(git rev-parse --git-path index)" || pb_die "cannot find the index" 3
  idx_had=0
  if [ -f "$idx" ]; then cp -p "$idx" "$tmpd/index.save" || pb_die "cannot save the index" 3; idx_had=1; fi
}

# "mode sha<TAB>path" lines of the entries of git ls-files -s -z / git ls-tree -r -z (stdin), stage and type dropped
index_lines() {
  local r h
  while IFS= read -r -d '' r; do h="${r%%$'\t'*}"; printf '%s\t%s\n' "${h% *}" "${r#*$'\t'}"; done
}
tree_lines() {
  local r h m
  while IFS= read -r -d '' r; do
    h="${r%%$'\t'*}"; m="${h%% *}"; h="${h#* }"; printf '%s %s\t%s\n' "$m" "${h#* }" "${r#*$'\t'}"
  done
}

# Lines (stdin, "mode sha<TAB>path") whose path is listed in the file $1 (one path per line)
filter_judged() { awk 'FILENAME == ARGV[1] { j[$0] = 1; next } { p = substr($0, index($0, "\t") + 1); if (p in j) print }' "$1" -; }
# true when every given pipeline status is 0
pipe_ok() { local s; for s in "$@"; do [ "$s" -eq 0 ] || return 1; done; }
restore_index() {
  if [ "$idx_had" -eq 1 ]; then
    cp -p "$tmpd/index.save" "$idx" || pb_die "cannot restore the index" 3
  else
    rm -f "$idx"
  fi
}
# a refusal after tdd-step staged something: the saved index file comes back first
refuse_staged() { restore_index; refuse "$1"; }

# "mode<TAB>path" lines of the stage-0 regular entries (mode 100644 or 100755) of git ls-files -s -z (stdin)
reg_lines() {
  local r h m
  while IFS= read -r -d '' r; do
    h="${r%%$'\t'*}"; m="${h%% *}"
    case "$h" in *" 0") ;; *) continue ;; esac
    case "$m" in 100644 | 100755) printf '%s\t%s\n' "$m" "${r#*$'\t'}" ;; esac
  done
}
# AC4. Needs $tmpd/scratch.idx (what git commit --only commits) and $tmpd/judged. Sets XB to the judged paths (one per line)
# whose staged exec bit the commit would not carry: a stage-0 regular entry in the real index and in the scratch index with
# different modes, and the real mode differs from HEAD's (or the path is absent in HEAD).
xbit_paths() {
  git ls-files -s -z > "$tmpd/real.z" || return 1
  reg_lines < "$tmpd/real.z" > "$tmpd/real.m" || return 1
  GIT_INDEX_FILE="$tmpd/scratch.idx" git ls-files -s -z > "$tmpd/scr.z" || return 1
  reg_lines < "$tmpd/scr.z" > "$tmpd/scr.m" || return 1
  git ls-tree -r -z HEAD > "$tmpd/head.z" || return 1
  tree_lines < "$tmpd/head.z" > "$tmpd/head.m" || return 1
  awk 'function pth(l) { return substr(l, index(l, "\t") + 1) }
    FILENAME == ARGV[1] { j[$0] = 1; next }
    FILENAME == ARGV[2] { r[pth($0)] = substr($0, 1, index($0, "\t") - 1); next }
    FILENAME == ARGV[3] { s[pth($0)] = substr($0, 1, index($0, "\t") - 1); next }
    { p = pth($0); h[p] = substr($0, 1, index($0, " ") - 1) }
    END { for (p in j) if ((p in r) && (p in s) && r[p] != s[p] && (!(p in h) || r[p] != h[p])) print p }' \
    "$tmpd/judged" "$tmpd/real.m" "$tmpd/scr.m" "$tmpd/head.m" > "$tmpd/xb.raw" || return 1
  XB="$(LC_ALL=C sort "$tmpd/xb.raw")" || return 1
  return 0
}
xbit_text() {
  local fm="" cfg
  cfg="$(git config --bool core.filemode 2>/dev/null)" || cfg=""
  [ "$cfg" != false ] || fm=" (core.filemode=false)"
  printf '%s: the exec bit staged in the index would not be committed by git commit --only%s' "$(printf '%s' "$XB" | paste -s -d, - | sed 's/,/, /g')" "$fm"
}

# HEAD's branch into BR: refs/heads/NAME (attached) or "detached"; returns 1 (BR empty) when git cannot say
BR=""
read_branch() {
  local o rc
  o="$(git symbolic-ref -q HEAD)"; rc=$?
  case "$rc" in 0) BR="$o" ;; 1) BR=detached ;; *) BR=""; return 1 ;; esac
}
# $tmpd/refs1 = the branch list now; $tmpd/chg = "name old new" lines (sorted, "none" = no such branch) of the branches
# that differ from $tmpd/refs0, leaving out the ref named $1 (may be empty)
refs_now() { git for-each-ref --format='%(refname) %(objectname)' refs/heads > "$tmpd/refs1"; }
refs_changed() {
  awk -v skip="$1" 'FILENAME == ARGV[1] { if ($1 != skip) { o[$1] = $2; s[$1] = 1 } next } { if ($1 != skip) { n[$1] = $2; s[$1] = 1 } }
    END { for (k in s) { ho = (k in o); hn = (k in n); if (ho != hn || o[k] != n[k]) print k, (ho ? o[k] : "none"), (hn ? n[k] : "none") } }' "$tmpd/refs0" "$tmpd/refs1" > "$tmpd/chg0" \
    && LC_ALL=C sort "$tmpd/chg0" > "$tmpd/chg"
}
# C, the commit git commit made for the step (a child of pre_head with the step subject), from the HEAD reflog; else the tip of
# the pre-run branch when it moved. Empty when it cannot be told.
LOST_C=""
find_c() {
  local hp h p s first="${subject%%$NL*}" t
  git log -g --format="%H %P%x09%s" HEAD > "$tmpd/reflog" 2>/dev/null || : > "$tmpd/reflog"
  while IFS=$'\t' read -r hp s; do
    h="${hp%% *}"; p="${hp#* }"
    if [ "$p" = "$pre_head" ] && [ "$s" = "$first" ]; then printf '%s' "$h"; return 0; fi
  done < "$tmpd/reflog"
  if [ "$R" != detached ]; then
    t="$(git rev-parse --verify -q "$R")" || t=""
    if [ -n "$t" ] && [ "$t" != "$pre_head" ]; then printf '%s' "$t"; return 0; fi
  fi
  return 0
}
# C from git commit's own report (the file $1, its stdout): the first " <7+ hex>] " is the report line (a branch name holds no
# space, so the label cannot hide it). Accepted only when it is a commit on pre_head with the step subject; else empty.
COMMIT_C=""
report_c() {
  local line c full first="${subject%%$NL*}" re=' ([0-9a-f]{7,})\] '
  COMMIT_C=""
  [ -f "$1" ] || return 0
  while IFS= read -r line; do
    if [[ "$line" =~ $re ]]; then
      c="${BASH_REMATCH[1]}"
      full="$(git rev-parse --verify -q "$c^{commit}" 2>/dev/null)" || full=""
      if [ -n "$full" ] && [ "$(git rev-list --parents -n 1 "$full" 2>/dev/null)" = "$full $pre_head" ] \
        && [ "$(git log -1 --format=%s "$full" 2>/dev/null)" = "$first" ]; then COMMIT_C="$full"; fi
      return 0
    fi
  done < "$1"
  return 0
}
# The lost decision (AC0). Needs $tmpd/judged and $tmpd/expected. Compares the WORK TREE with the judged entries: a temp index
# built from them, then git diff --quiet on the judged paths; a judged deletion is lost when the path is on disk. Any git error
# counts as lost. Sets LOST_C (C, or "unknown") and LOST_RM (the brought-back deletions, one per line). Runs once.
LOST_DONE=0; LOST_RM=""
# true when the work tree equals the entries in the file $1 ("mode sha<TAB>path" lines) for every judged path of $tmpd/judged: a temp
# index built from them, then git diff --quiet (no pathspec: the temp index holds only judged entries, so the argument limit never
# matters). A judged path without an entry must be absent from disk; those present are appended to RM_NOW. Any git error: false.
RM_NOW=""
wt_equals() {
  local line eq=0
  RM_NOW=""
  rm -f "$tmpd/lost.idx"
  if ! { while IFS= read -r line; do printf '%s\0' "$line"; done < "$1" \
      | GIT_INDEX_FILE="$tmpd/lost.idx" git update-index -z --index-info; } >/dev/null 2>&1; then
    eq=1
  elif ! GIT_INDEX_FILE="$tmpd/lost.idx" GIT_OPTIONAL_LOCKS=0 git --literal-pathspecs diff --quiet >/dev/null 2>&1; then
    eq=1
  fi
  if awk 'FILENAME == ARGV[1] { e[substr($0, index($0, "\t") + 1)] = 1; next } !($0 in e)' "$1" "$tmpd/judged" > "$tmpd/deleted"; then
    while IFS= read -r line; do
      if [ -e "$line" ] || [ -L "$line" ]; then eq=1; RM_NOW="$RM_NOW$line$NL"; fi
    done < "$tmpd/deleted"
  else
    eq=1
  fi
  return $eq
}
# The lost decision (AC0). Needs $tmpd/judged and $tmpd/expected. Compares the WORK TREE with the judged entries; when it differs,
# also with the entries of the commit C git made: a work tree equal to C (a pre-commit hook rewrote the files and added them) has
# no role file lost, the commit just differs from what was judged. Sets LOST_C (C, or "unknown") and LOST_RM (the brought-back
# deletions, one per line). Any git error counts as lost. Runs once.
lost_decide() {
  local c
  [ "$LOST_DONE" -eq 0 ] || return 0
  LOST_DONE=1
  [ -s "$tmpd/judged" ] || return 0
  wt_equals "$tmpd/expected" && return 0
  LOST_RM="$RM_NOW"
  if [ -n "$COMMIT_C" ] \
    && git ls-tree -r -z "$COMMIT_C" > "$tmpd/ctree" 2>/dev/null \
    && tree_lines < "$tmpd/ctree" | filter_judged "$tmpd/judged" > "$tmpd/clines" && pipe_ok "${PIPESTATUS[@]}" \
    && wt_equals "$tmpd/clines"; then
    LOST_RM=""
    return 0
  fi
  c="$COMMIT_C"
  [ -n "$c" ] || c="$(find_c)"
  LOST_C="${c:-unknown}"
}
# The undo, then exit. $1 = the reason, $2 = 3 to exit 3 even when everything went well. Steps, each only where safe:
# (a) R (the pre-run branch) back to pre_head by compare-and-swap on the sha read now (a detached run: HEAD detached at
# pre_head); no other ref is moved, created or deleted; (b) HEAD attached to R again, only when R is back;
# (c) the saved index file restored. Exit 1 (nothing committed) only when (a)-(c) ran and no branch differs from before;
# otherwise exit 3 naming HEAD and the branches left behind.
undo_exit() {
  local ok=1 fails="" hsha rsha l hd
  lost_decide
  if [ "$R" = detached ]; then
    hsha="$(git rev-parse --verify -q HEAD)" || hsha=""
    read_branch || BR="?"
    if [ -z "$hsha" ]; then ok=0; fails="$fails HEAD-unreadable"
    elif [ "$BR" != detached ] || [ "$hsha" != "$pre_head" ]; then
      git update-ref --no-deref HEAD "$pre_head" "$hsha" || { ok=0; fails="$fails HEAD-not-detached-at-$pre_head"; }
    fi
  else
    rsha="$(git rev-parse --verify -q "$R")" || rsha=""
    if [ -z "$rsha" ]; then ok=0; fails="$fails $R-is-gone"
    elif [ "$rsha" != "$pre_head" ]; then
      git update-ref "$R" "$pre_head" "$rsha" || { ok=0; fails="$fails $R-not-moved-back"; }
    fi
    rsha="$(git rev-parse --verify -q "$R")" || rsha=""
    if [ "$rsha" = "$pre_head" ]; then
      if ! read_branch || [ "$BR" != "$R" ]; then
        git symbolic-ref HEAD "$R" || { ok=0; fails="$fails HEAD-not-attached-to-$R"; }
      fi
    else
      ok=0
    fi
  fi
  if [ "$idx_had" -eq 1 ]; then
    cp -p "$tmpd/index.save" "$idx" || { ok=0; fails="$fails index-not-restored"; }
  else
    rm -f "$idx" || { ok=0; fails="$fails index-not-restored"; }
  fi
  refs_now && refs_changed "" || { ok=0; fails="$fails branches-unreadable"; : > "$tmpd/chg"; }
  if [ "$ok" -eq 1 ] && [ ! -s "$tmpd/chg" ] && [ "${2:-}" != 3 ] && [ -z "$LOST_C" ]; then
    echo "error: $1; the commit is undone, HEAD and the index are restored, the work tree is kept - nothing committed:" >&2
    for l in ${extra[@]+"${extra[@]}"}; do printf '  %s\n' "$l" >&2; done
    for l in ${differ[@]+"${differ[@]}"}; do printf 'error: the commit differs from what was judged: %s\n' "$l" >&2; done
    exit 1
  fi
  if read_branch; then
    if [ "$BR" = detached ]; then hd="detached at $(git rev-parse HEAD 2>/dev/null)"; else hd="on $BR"; fi
  else hd="unreadable"; fi
  if [ -n "$LOST_C" ]; then
    echo "error: $1; the role files are no longer in the work tree (the undo ran as far as it could):" >&2
    if [ "$LOST_C" = unknown ]; then
      echo "  the commit made for the step could not be found (look in git reflog HEAD; its parent was $pre_head)" >&2
    else
      echo "  the commit made for the step is $LOST_C (its parent is $pre_head)" >&2
      echo "  bring the role files back with: git checkout $LOST_C -- ." >&2
      while IFS= read -r l; do [ -z "$l" ] || printf '  and remove the file the role had deleted: rm -- %q\n' "$l" >&2; done <<EOF
$LOST_RM
EOF
    fi
  else
    echo "error: $1; the undo is incomplete (the work tree is kept), these refs are left behind:" >&2
  fi
  echo "  HEAD is now $hd (it was $R before the step, at $pre_head)" >&2
  while read -r l rsha hsha; do [ -z "$l" ] || printf '  %s: was %s, now %s\n' "$l" "$rsha" "$hsha" >&2; done < "$tmpd/chg"
  [ -z "$fails" ] || echo "  steps that failed:$fails" >&2
  exit 3
}
# git commit failed: a hook may have switched the branch first; then HEAD and the index are restored where possible (exit 3)
commit_failed() {
  local why="" hs
  if ! read_branch; then why="git commit failed after the branch could not be read"
  elif [ "$BR" != "$R" ]; then why="git commit failed after a git hook switched HEAD to $BR (it was on $R)"
  elif [ "$R" = detached ] && { hs="$(git rev-parse --verify -q HEAD)" || hs=""; [ "$hs" != "$pre_head" ]; }; then
    why="git commit failed after a git hook moved HEAD to ${hs:-an unreadable commit} (it was at $pre_head)"
  elif ! { refs_now && refs_changed ""; }; then why="git commit failed and the branches could not be compared"
  elif [ -s "$tmpd/chg" ]; then why="git commit failed after a git hook moved, created or deleted a branch"
  fi
  [ -n "$why" ] || pb_die "git commit failed" 3
  undo_exit "$why" 3
}

# After git commit. $tmpd/judged holds the judged paths (one per line), $tmpd/expected their judged entries
# (index_lines, sorted). The commit must be exactly one commit on the pre-run HEAD, hold exactly the judged paths
# and hold exactly the judged entries of them (a git hook may add or change a path, or commit or merge on top).
# Any git failure while checking counts as a failed check. Otherwise: HEAD back to the pre-run HEAD, the saved
# index file restored byte for byte, the reason and the paths named, exit 1.
check_commit() {
  local -a extra=() differ=(); local g why="" parent_ok=0 line headsha plist
  headsha="$(git rev-parse HEAD)" || headsha=""
  plist="$(git rev-list --parents -n 1 HEAD)" || plist=""
  if [ -n "$headsha" ] && [ "$plist" = "$headsha $pre_head" ]; then parent_ok=1; fi
  : > "$tmpd/extra"
  if [ "$parent_ok" -eq 1 ] || git merge-base --is-ancestor "$pre_head" HEAD 2>/dev/null; then
    if git diff --name-only --no-renames -z "$pre_head" HEAD > "$tmpd/touched" \
      && tr '\0' '\n' < "$tmpd/touched" > "$tmpd/touched.nl" \
      && awk 'FILENAME == ARGV[1] { j[$0] = 1; next } !($0 in j)' "$tmpd/judged" "$tmpd/touched.nl" > "$tmpd/extra"; then
      while IFS= read -r g; do extra+=("$g"); done < "$tmpd/extra"
    else
      why="the paths of the commit could not be listed"
    fi
  fi
  if [ -n "$why" ]; then
    :
  elif [ "$parent_ok" -eq 0 ]; then
    if [ ${#extra[@]} -gt 0 ]; then
      why="HEAD is not a single commit on the pre-run HEAD (a git hook committed or merged on top)"
    else
      why="HEAD was moved to ${headsha:-an unreadable commit} (not one commit on $pre_head)"
    fi
  elif [ ${#extra[@]} -gt 0 ]; then
    why="the commit held paths that were not judged (a git hook added them)"
  elif [ -s "$tmpd/judged" ]; then
    if git ls-tree -r -z HEAD > "$tmpd/headtree" \
      && tree_lines < "$tmpd/headtree" | filter_judged "$tmpd/judged" | LC_ALL=C sort > "$tmpd/got" && pipe_ok "${PIPESTATUS[@]}" \
      && LC_ALL=C sort "$tmpd/expected" "$tmpd/got" | uniq -u > "$tmpd/merged" && pipe_ok "${PIPESTATUS[@]}"; then
      while IFS= read -r line; do printf '%s\n' "${line#*$'\t'}"; done < "$tmpd/merged" | LC_ALL=C sort -u > "$tmpd/diffl"
      while IFS= read -r line; do differ+=("$line"); done < "$tmpd/diffl"
      if [ ${#differ[@]} -gt 0 ]; then why="the commit differs from what was judged (a git hook changed it)"; fi
    else
      why="the committed entries could not be compared with the judged ones"
    fi
  fi
  # the branch: HEAD still where it was, and no other branch moved, created or deleted
  local bwhy="" f3="" skip=""
  [ "$R" = detached ] || skip="$R"
  if ! read_branch; then bwhy="the branch could not be read after the commit"; f3=3
  elif [ "$BR" != "$R" ]; then
    bwhy="a git hook switched HEAD to $BR (it was on $R)"
  elif ! { refs_now && refs_changed "$skip"; }; then bwhy="the branches could not be compared after the commit"; f3=3
  elif [ -s "$tmpd/chg" ]; then bwhy="a git hook moved, created or deleted a branch"
  fi
  # the lost decision (AC0) runs on every failed check, attached or detached
  if [ -n "$bwhy" ] || [ -n "$why" ]; then lost_decide; fi
  if [ -n "$bwhy" ] && { [ -n "$LOST_C" ] || [ -z "$why" ]; }; then why="$bwhy"; fi
  [ -n "$why" ] || return 0
  undo_exit "$why" "$f3"
}

tmpd="$(mktemp -d "${TMPDIR:-/tmp}/tdd-step.XXXXXX")" || pb_die "cannot create a temp dir" 3
trap 'rm -rf "$tmpd"' EXIT
if [ -z "$baseline" ]; then
  run_gate || exit 1
  notes1=""
else
  gout="$(run_gate)"; grc=$?
  [ -z "$gout" ] || printf '%s\n' "$gout"
  [ "$grc" -eq 0 ] || exit 1
  notes1="$(notes_of "$gout")"
fi
# an untracked nested repository (a status row ending in a slash) or a staged gitlink that HEAD lacks: the snapshot
# cannot hash it, so refuse it before the test command runs (a nested repository under .agents/handoff/ is exempt)
# read-only status (no index refresh) for the nested repository check: a refusal leaves the index file untouched
GIT_OPTIONAL_LOCKS=0 git -c core.quotepath=off status --porcelain=v1 -z --untracked-files=all > "$tmpd/statusn" || pb_die "git status failed" 3
nest=""; nxt=0
while IFS= read -r -d '' ent; do
  if [ "$nxt" -eq 1 ]; then p="$ent"; nxt=0; else
    xy="${ent:0:2}"; p="${ent:3}"
    case "$xy" in R? | C? | ?R | ?C) nxt=1 ;; esac
  fi
  case "$p" in .agents/handoff/*) continue ;; */) nest="${nest:-$p}" ;; esac
done < "$tmpd/statusn"
if [ -z "$nest" ]; then
  git ls-files -s -z > "$tmpd/lsf" || pb_die "git ls-files failed" 3
  while IFS= read -r -d '' ent; do
    case "$ent" in 160000" "*) ;; *) continue ;; esac
    p="${ent#*$'\t'}"
    if [ -z "$(GIT_LITERAL_PATHSPECS=1 git ls-tree --name-only HEAD -- "$p" 2>/dev/null)" ]; then nest="$p"; break; fi
  done < "$tmpd/lsf"
fi
if [ -n "$nest" ]; then
  printf 'error: nested repository: %s - the snapshot cannot hash it; add it to .git/info/exclude or .gitignore and run again - nothing committed\n' "$nest" >&2
  exit 1
fi
# a newline or a \002 byte in a path makes the snapshot die (exit 3): refuse it before the test command runs
git -c core.quotepath=off status --porcelain=v1 -z --untracked-files=all > "$tmpd/status0" || pb_die "git status failed" 3
if [ "$(LC_ALL=C tr '\0' 'x' < "$tmpd/status0" | wc -l)" -gt 0 ] || [ "$(LC_ALL=C tr -cd '\002' < "$tmpd/status0" | wc -c)" -gt 0 ]; then
  echo "error: a changed path contains a newline or a \\002 byte: commit the role's paths by hand - nothing committed" >&2
  exit 1
fi
GIT_OPTIONAL_LOCKS=0 bash "$here/role-gate.sh" snapshot --out "$tmpd/before" >/dev/null 2>"$tmpd/snap.err" || { cat "$tmpd/snap.err" >&2; pb_die "cannot snapshot the work tree" 3; }
head_before="$(git rev-parse HEAD)" || pb_die "cannot read HEAD" 3
read_branch || pb_die "cannot read the branch (git symbolic-ref -q HEAD failed) - nothing committed" 3
branch_before="$BR"

bash "$here/proof-run.sh" --label "$step" -- "$@"
rc=$?
if [ "$step" = "red" ]; then
  if [ "$rc" -eq 0 ]; then
    echo "error: the test command did not fail - this is not RED, nothing committed" >&2
    exit 1
  fi
elif [ "$rc" -ne 0 ]; then
  echo "error: the test command failed (exit $rc) - this is not GREEN, nothing committed" >&2
  exit 1
fi

# --baseline: the role's paths, from git status after the test command
GIT_OPTIONAL_LOCKS=0 bash "$here/role-gate.sh" snapshot --out "$tmpd/after" >/dev/null 2>"$tmpd/snap.err" || { cat "$tmpd/snap.err" >&2; refuse "cannot snapshot the work tree after the test command"; }
cmp -s "$tmpd/before" "$tmpd/after" || refuse "the test command changed the work tree (a file was written, edited or committed)"
read_branch || pb_die "cannot read the branch after the test command (git symbolic-ref -q HEAD failed) - nothing committed" 3
[ "$BR" = "$branch_before" ] || refuse "the test command changed the branch (HEAD was on $branch_before, now on $BR)"
[ "$(git rev-parse HEAD)" = "$head_before" ] || refuse "HEAD moved while the test command ran"
gout2="$(GIT_OPTIONAL_LOCKS=0 run_gate 2>"$tmpd/gate2.err")"; grc2=$?
[ "$grc2" -eq 0 ] || { printf '%s\n' "$gout2"; cat "$tmpd/gate2.err" >&2; refuse "the role gate fails after the test command"; }
paths=(); untr=()
if [ -n "$baseline" ]; then
  notes="$(notes_of "$gout2")"
  [ "$notes" = "$notes1" ] || refuse "the paths unchanged since the baseline differ after the test command"
  exempt="$NL"
  while IFS= read -r nl; do
    [ -n "$nl" ] || continue
    exempt+="${nl#"$NOTEP"}$NL"
  done <<EOF
$notes
EOF
  git -c core.quotepath=off status --porcelain=v1 -z --untracked-files=all > "$tmpd/status" || pb_die "git status failed" 3
  nxt=0; ctl=0
  while IFS= read -r -d '' ent; do
    if [ "$nxt" -eq 1 ]; then p="$ent"; nxt=0; xy="  "; else
      xy="${ent:0:2}"; p="${ent:3}"
      case "$xy" in R? | C? | ?R | ?C) nxt=1 ;; esac
    fi
    case "$p" in .agents/handoff/*) continue ;; esac
    case "${p//$'\t'/}" in *[[:cntrl:]]*) ctl=1 ;; esac
    case "$exempt" in *"$NL$p$NL"*) continue ;; esac
    paths+=("$p")
    [ "$xy" != "??" ] || untr+=("$p")
  done < "$tmpd/status"
  if [ "$ctl" -eq 1 ]; then
    echo "error: a changed path contains a control character: commit the role's paths by hand - nothing committed" >&2
    exit 1
  fi
  if [ ${#paths[@]} -eq 0 ]; then
    echo "error: nothing of the role's to commit (every change is a baseline path or under .agents/handoff/)" >&2
    exit 1
  fi
fi

if [ "$commit" -eq 1 ]; then
  # evidence logs live under .agents/handoff/: never commit them, and keep them
  # out of 'git status' via the local exclude file (not the project's .gitignore)
  if ! git check-ignore -q .agents/handoff/x 2>/dev/null; then
    excl="$(git rev-parse --git-path info/exclude 2>/dev/null)" || excl=""
    if [ -n "$excl" ]; then
      mkdir -p "$(dirname "$excl")" && printf '%s\n' '.agents/handoff/' >> "$excl" \
        && echo "notice: added .agents/handoff/ to $excl (local exclude, not .gitignore)"
    fi
  fi
  save_state
  if [ -n "$baseline" ]; then
    if [ ${#untr[@]} -gt 0 ]; then
      GIT_LITERAL_PATHSPECS=1 git add -- "${untr[@]}" || pb_die "git add failed" 3
    fi
    # what git commit --only commits: a scratch index of HEAD plus the judged paths from the work tree
    GIT_INDEX_FILE="$tmpd/scratch.idx" git read-tree HEAD || refuse_staged "cannot build the scratch index"
    GIT_INDEX_FILE="$tmpd/scratch.idx" GIT_LITERAL_PATHSPECS=1 git add -A -- "${paths[@]}" || refuse_staged "git add failed"
    printf '%s\n' "${paths[@]}" > "$tmpd/judged"
    GIT_INDEX_FILE="$tmpd/scratch.idx" git ls-files -s -z > "$tmpd/idxfull" || refuse_staged "cannot read the scratch index"
    index_lines < "$tmpd/idxfull" | filter_judged "$tmpd/judged" | LC_ALL=C sort > "$tmpd/expected"
    pipe_ok "${PIPESTATUS[@]}" || refuse_staged "cannot read the scratch index"
    xbit_paths || refuse_staged "cannot compare the staged modes"
    [ -z "$XB" ] || refuse_staged "$(xbit_text)"
    GIT_LITERAL_PATHSPECS=1 git commit -m "$subject" -- "${paths[@]}" > "$tmpd/creport" || { report_c "$tmpd/creport"; commit_failed; }
    report_c "$tmpd/creport"
    check_commit
  else
    git add -A || pb_die "git add failed" 3
    git reset -q -- .agents/handoff 2>/dev/null || true
    git diff --cached --name-only --no-renames -z > "$tmpd/judged.z" || refuse_staged "cannot list the staged paths"
    tr '\0' '\n' < "$tmpd/judged.z" > "$tmpd/judged" || refuse_staged "cannot list the staged paths"
    git ls-files -s -z > "$tmpd/idxfull" || refuse_staged "cannot read the index"
    index_lines < "$tmpd/idxfull" | filter_judged "$tmpd/judged" | LC_ALL=C sort > "$tmpd/expected"
    pipe_ok "${PIPESTATUS[@]}" || refuse_staged "cannot read the index"
    git commit -m "$subject" > "$tmpd/creport" || { report_c "$tmpd/creport"; commit_failed; }
    report_c "$tmpd/creport"
    check_commit
  fi
  if [ "$step" = "red" ]; then echo "RED=$(git rev-parse HEAD)"; else echo "committed: $(git rev-parse HEAD)"; fi
elif [ -n "$baseline" ]; then
  echo "not committing (no --commit). To commit only the role's paths:"
  if [ ${#untr[@]} -gt 0 ]; then
    printf 'GIT_LITERAL_PATHSPECS=1 git add --'
    for p in "${untr[@]}"; do printf ' %q' "$p"; done
    printf '\n'
  fi
  printf 'GIT_LITERAL_PATHSPECS=1 git commit -m %q --' "$subject"
  for p in "${paths[@]}"; do printf ' %q' "$p"; done
  printf '\n'
  # print mode is advisory and writes nothing: the scratch index is built quietly, its git add writes into a throwaway
  # object dir (the real objects are an alternate). When the scratch index cannot be built (a core.safecrlf refusal) the
  # check is skipped without a word, as in v0.24.22; a failing comparison is a note (exit stays 0)
  pobj="$(git rev-parse --git-path objects 2>/dev/null)" || pobj=""
  case "$pobj" in /* | [A-Za-z]:[/\\]*) ;; *) pobj="$PWD/$pobj" ;; esac
  xb_ok=0
  if [ -n "$pobj" ] && mkdir "$tmpd/obj" 2>/dev/null; then
    {
      GIT_INDEX_FILE="$tmpd/scratch.idx" git read-tree HEAD \
        && GIT_INDEX_FILE="$tmpd/scratch.idx" GIT_OBJECT_DIRECTORY="$tmpd/obj" GIT_ALTERNATE_OBJECT_DIRECTORIES="$pobj" GIT_LITERAL_PATHSPECS=1 git add -A -- "${paths[@]}" \
        && printf '%s\n' "${paths[@]}" > "$tmpd/judged"
    } >/dev/null 2>&1 && xb_ok=1
  fi
  if [ "$xb_ok" -eq 1 ]; then
    if ! xbit_paths >/dev/null 2>&1; then echo "note: cannot compare the staged modes (print mode only, nothing is changed)" >&2
    elif [ -n "$XB" ]; then echo "warning: $(xbit_text)" >&2; fi
  fi
else
  echo "not committing (no --commit). To commit: git add -A && git commit -m \"$subject\""
fi
exit 0
