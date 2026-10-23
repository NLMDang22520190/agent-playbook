#!/usr/bin/env bash
# Tests for the batched untracked-file count of `role-gate.sh size` (v0.24.28 lane S, .agents/handoff/01-spec.md):
# size (plain and with --baseline) counts the untracked files in one batch (an EMPTY temporary index, `add -N`, one
# `diff --numstat -z`) instead of one `git diff --no-index` per file, and every output byte stays as it was in v0.24.27.
#   AC1  stdout and exit code equal v0.24.27 for every "same" kind and every per-file-routed kind (plain, --baseline, default
#        limits); stderr of the new gate has no line the old one did not print (the batch is silent)
#   AC2  the number of git calls does not depend on the number of untracked files (counting git shim): 200 regular files,
#        200 files with a tab-named one, 100 files + 100 symlinks to files; an empty list and a routed-only list make no `add -N`
#   AC3  real index (sha256), listing of the git dir and the common dir, index.lock and the loose objects are unchanged
#        by a run: normal repo, linked worktree, core.splitIndex=true repo, a pre-held index.lock; no temp dir is left
#   AC4  a shim that makes `add -N` or the batch `diff` exit non-zero (with no output, or with the right output), drops a record,
#        duplicates a record, or turns a listed file into a directory (race) still gives the v0.24.27 result: the whole batch
#        falls back to the per-file loop (a `diff --no-index` per file in the log), so it is never fewer
#   AC5  the size rows of test-role-gate.sh, -batch.sh, -baseline.sh and -b.sh are not part of this suite: they stay as they are
# v0.24.29 lane S1 (quoted names): an untracked name that git C-quotes (tab, `"`, `\`, newline) is read raw (one `ls-files -z`), counted,
# classified (test / .agents/handoff skip) and baseline-matched by its raw name:
#   S1-AC1  routed-tab/-dquote/-backslash/-newline: v0.24.27 file count and 2 more lines (cmp_q; plain and --baseline); corpus rows re-pinned
#   S1-AC2  tests/ and .agents/handoff/ names with a tab, quote or backslash are not production; a --baseline manifest matches the raw name;
#           a raw name with a newline is production even under tests/ (D13/D23); an unreadable tests/ name is not an error (D2)
#   S1-AC3  a 101-line production file with a quoted name: over the limit, exit 1
# v0.24.29 lane S2 (fail closed): an untracked production regular file or symlink to a file that size cannot count (unreadable, gone after the
# listing, git exits above 1, no numstat line for a non-empty file) prints one `error: cannot count the lines of untracked file PATH ...` line
# per file (ls-files -z order, control chars but TAB as ?), no `files:` line, exit 3; test and .agents/handoff paths are not affected (D2, D23):
#   S2-AC4 unreadable (chmod 000)   S2-AC5 vanished / per-file git failure; size-0 file still 0 lines   S2-AC6 stderr pinned byte for byte
#   S2-AC7 test / handoff unaffected, newline names are production   S2-AC8 symlink to a dir, nested repos, dangling symlink, fifo keep their count
#   S2-AC16 header exit line and SKILL.md Lite step name the exit 3
# v0.24.29 lane S3 (linear batch): the batch is ONE `update-index --add -z --stdin` into an empty temporary index and a temporary object dir, then
# ONE `diff --cached --numstat -z` against the empty tree (id from `hash-object -t tree`); the shim labels and fault modes follow it (D10):
#   S3-AC10 one ls-files / hash-object / update-index / diff-batch whatever the number of files, no `add -N`; the calls run with the temp index and
#           the temp object dir (idx=1 obj=1)   S3-AC9/AC11 the corpus (+ clean filter, core.safecrlf=true, splitIndex repo, sha256 repo) equals v0.24.27
#   S3-AC12 sha256 repo: real index, git dir, index.lock, object store untouched   S3-AC13 update-index refused / partial / rc 1: whole list per-file
#   S3-AC15 TERM to the gate during the batch: the process group finishes, no pbgate.* dir (and no BL_TMPW file with --baseline) is left
#   S3-AC14 (timing) and S3-AC17 (shard weight) are evidence rows in the report, not suite rows
# The expected values are v0.24.27's own scripts (git archive 0b6af9c), run beside the current gate on the same repo.
# Kinds that this file system cannot hold (tab or quote in a name, symlinks) are skipped, not failed.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/role-gate-fixture.sh"

DT="$(mk_tmp)"
REAL_GIT="$(command -v git)"; export REAL_GIT
OLD="$(mk_tmp)"; PRE=0b6af9c; REF_OK=0
if git -C "$PB_ROOT" cat-file -e "$PRE^{commit}" 2>/dev/null &&
   ( cd "$PB_ROOT" && git archive "$PRE" scripts | tar -x -C "$OLD" ) 2>/dev/null && [ -f "$OLD/scripts/role-gate.sh" ] &&
   ! grep -q 'add -N' "$OLD/scripts/role-gate.sh"; then REF_OK=1; fi
OLDG="$OLD/scripts/role-gate.sh"; NEWG="$GATE"
WIDE="--max-files 1000 --max-lines 100000"

# ---------------------------------------------------------------- the git shim (counts, records, and injects failures)
SHIM="$(mk_tmp)"; SHIMLOG="$DT/shim.log"; SHIMFIRED="$DT/shim.fired"
cat > "$SHIM/git" <<'SHIMEOF'
#!/usr/bin/env bash
# PB_SHIM_MODE: count (default) | upd-fail | diff-fail | upd-rc | upd-partial | diff-rc | diff-drop | diff-dup | race | vanish | uncount-none | uncount-128 | rc2 | hang.
# Every call appends "<label> idx=<0|1> obj=<0|1>" to PB_SHIM_LOG (idx: GIT_INDEX_FILE set, obj: GIT_OBJECT_DIRECTORY set); update-index, diff-batch and
# hash-object calls also append "<label>: <args>" to PB_SHIM_LOG.args. hang: the first call labelled $PB_HANG_LABEL (default update-index) marks
# PB_HANG_REACHED, then waits (up to 25 s) for PB_HANG_RELEASE before it runs.
sub=""; skip=0; hasN=0; hasz=0; hasnum=0; hasnoindex=0
for a in "$@"; do
  if [ -z "$sub" ]; then
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    case "$a" in -c | -C | --git-dir | --work-tree) skip=1; continue ;; -*) continue ;; esac
    sub="$a"; continue
  fi
  case "$a" in -N | --intent-to-add) hasN=1 ;; -z) hasz=1 ;; --numstat) hasnum=1 ;; --no-index) hasnoindex=1 ;; esac
done
label="$sub"
if [ "$sub" = add ] && [ "$hasN" = 1 ]; then label=add-N; fi
if [ "$sub" = diff ] && [ "$hasnum" = 1 ] && [ "$hasz" = 1 ]; then label=diff-batch; fi
if [ "$sub" = diff ] && [ "$hasnoindex" = 1 ]; then label=diff-noindex; fi
idx=0; if [ -n "${GIT_INDEX_FILE:-}" ]; then idx=1; fi
obj=0; if [ -n "${GIT_OBJECT_DIRECTORY:-}" ]; then obj=1; fi
printf '%s idx=%s obj=%s\n' "$label" "$idx" "$obj" >> "$PB_SHIM_LOG"
case "$label" in update-index | diff-batch | hash-object) printf '%s: %s\n' "$label" "$*" >> "$PB_SHIM_LOG.args" ;; esac
case "${PB_SHIM_MODE:-count}:$label" in
  upd-fail:update-index) printf 'shim: update-index refused\n' >&2; echo 1 >> "$PB_SHIM_FIRED"; exit 1 ;;
  diff-fail:diff-batch) printf 'shim: diff refused\n' >&2; echo 1 >> "$PB_SHIM_FIRED"; exit 1 ;;
  diff-drop:diff-batch) echo 1 >> "$PB_SHIM_FIRED"; "$REAL_GIT" "$@" | tr '\0' '\n' | sed 1d | tr '\n' '\0'; exit 0 ;;
  diff-dup:diff-batch) echo 1 >> "$PB_SHIM_FIRED"; "$REAL_GIT" "$@" | tr '\0' '\n' | sed 1p | tr '\n' '\0'; exit 0 ;;
  upd-rc:update-index | diff-rc:diff-batch) echo 1 >> "$PB_SHIM_FIRED"; "$REAL_GIT" "$@"; exit 1 ;;
  vanish:ls-files) : > "$PB_SHIM_FIRED.listed" ;;   # v0.24.29 S2: after the listing, the first count call finds PB_VANISH_PATH gone
  vanish:update-index | vanish:diff-batch | vanish:diff-noindex)
    if [ -e "$PB_SHIM_FIRED.listed" ] && [ -e "$PB_VANISH_PATH" ]; then rm -f "$PB_VANISH_PATH"; echo 1 >> "$PB_SHIM_FIRED"; fi ;;
  uncount-none:update-index | uncount-none:diff-batch | uncount-none:diff-noindex) echo 1 >> "$PB_SHIM_FIRED"; exit 1 ;;   # no output at all
  uncount-128:update-index | uncount-128:diff-batch) exit 1 ;;   # the batch is refused; the per-file command fails with 128
  rc2:update-index | rc2:diff-batch) exit 1 ;;   # the batch is refused; the per-file command exits 2 but still prints its numstat line
  rc2:diff-noindex) echo 1 >> "$PB_SHIM_FIRED"; "$REAL_GIT" "$@"; exit 2 ;;
  uncount-128:diff-noindex) printf 'fatal: shim\n' >&2; echo 1 >> "$PB_SHIM_FIRED"; exit 128 ;;
  upd-partial:update-index)   # most of the list is indexed, then git fails: a partial failure
    echo 1 >> "$PB_SHIM_FIRED"; tr '\0' '\n' | sed '$d' | tr '\n' '\0' | "$REAL_GIT" "$@" >/dev/null 2>&1; printf 'fatal: shim partial update\n' >&2; exit 128 ;;
  race:update-index | race:diff-noindex)   # a listed file turns into a directory right before the first command that reads it
    if [ -f "$PB_RACE_PATH" ]; then rm -f "$PB_RACE_PATH"; mkdir -p "$PB_RACE_PATH"; printf 'a\nb\nc\n' > "$PB_RACE_PATH/inner"; fi ;;
esac
if [ "${PB_SHIM_MODE:-}" = hang ] && [ "$label" = "${PB_HANG_LABEL:-update-index}" ]; then
  : > "$PB_HANG_REACHED"; w=0
  while [ ! -e "$PB_HANG_RELEASE" ] && [ "$w" -lt 250 ]; do sleep 0.1 2>/dev/null || sleep 1; w=$((w + 1)); done
fi
exec "$REAL_GIT" "$@"
SHIMEOF
chmod +x "$SHIM/git"

# ---------------------------------------------------------------- helpers
GENV=(X_PB=1)
# oneside TAG SCRIPT DIR ARGS... -> $DT/TAG.out .err .rc ; the gate runs in DIR with GENV in its environment, PATH = GPATH when set
oneside() {
  local tag="$1" s="$2" d="$3"; shift 3
  ( cd "$d" && env "${GENV[@]}" PLAYBOOK_HOME="$PLAYBOOK_HOME" LC_ALL=C PATH="${GPATH:-$PATH}" bash "$s" "$@" ) >"$DT/$tag.out" 2>"$DT/$tag.err" </dev/null
  echo $? > "$DT/$tag.rc"
}
# cmp_gate NAME DIR ARGS... -> the current gate equals v0.24.27 on DIR (D2: the new side runs in DIR2 when set; SHIMLOG then holds the new run only)
cmp_gate() {
  local name="$1" d="$2" nd why="" extra; shift 2; nd="${D2:-$d}"
  if [ "$REF_OK" != 1 ]; then t_skip 1 "$name (the reference commit $PRE is not in this clone, or git archive is not available)"; return; fi
  : > "$SHIMLOG"; : > "$SHIMFIRED"
  oneside o "$OLDG" "$d" "$@"
  : > "$SHIMLOG"; : > "$SHIMFIRED"
  oneside n "$NEWG" "$nd" "$@"
  if ! grep -q '^files: [0-9]' "$DT/o.out"; then
    why="the v0.24.27 run printed no size line: [$(head -c 120 "$DT/o.out" | tr '\n' '|')] [$(head -c 120 "$DT/o.err" | tr '\n' '|')]"
  elif [ -z "${ALLOW_ZERO:-}" ] && grep -q '^files: 0/' "$DT/o.out"; then
    why="fixture error: v0.24.27 counted no file"
  else
    cmp -s "$DT/o.out" "$DT/n.out" || why="stdout differs: v0.24.27 [$(head -c 160 "$DT/o.out" | tr '\n' '|')] now [$(head -c 160 "$DT/n.out" | tr '\n' '|')]"
    [ "$(cat "$DT/o.rc")" = "$(cat "$DT/n.rc")" ] || why="$why exit code: v0.24.27 $(cat "$DT/o.rc") now $(cat "$DT/n.rc")"
    # stderr may differ only by silence: no line of the new run is missing from the v0.24.27 run (a multiset, order aside)
    LC_ALL=C sort "$DT/o.err" > "$DT/o.es"; LC_ALL=C sort "$DT/n.err" > "$DT/n.es"
    extra="$(LC_ALL=C comm -13 "$DT/o.es" "$DT/n.es")"
    if [ -n "$extra" ]; then why="$why stderr has a line v0.24.27 did not print: [$(printf '%s' "$extra" | head -c 200 | tr '\n' '|')]"; fi
  fi
  if [ -z "$why" ]; then t_ok "$name"; else t_bad "$name" "$why"; fi
}
chk() { # name expected actual
  if [ "$2" = "$3" ]; then t_ok "$1"; return; fi
  printf '%s\n' "$2" > "$DT/exp"; printf '%s\n' "$3" > "$DT/act"
  t_bad "$1" "$(diff -a "$DT/exp" "$DT/act" | head -6 | tr '\n' '|')"
}
# routed_listed: 0 when git lists the file just made as a quoted (routed) name; NTFS maps a tab to a private-use character, git lists it unquoted and batches it
routed_listed() { git -c core.quotepath=off ls-files --others | head -n 1 | grep -q '^"'; }
# quoted_count -> (current dir) how many untracked names git lists C-quoted: 0 on NTFS, where the tab name stays plain (D15)
quoted_count() { git -c core.quotepath=off ls-files --others --exclude-standard | grep -c '^"' || true; }
# cmp_q NAME DF_PER DL_PER DIR ARGS... -> the current gate prints what v0.24.27 prints with the files count moved by
# quoted_count x DF_PER and the lines count by quoted_count x DL_PER (the `over the Lite size limit` line follows the new totals);
# exit code 1 when over, else 0; stderr gets no line v0.24.27 did not print
cmp_q() {
  local name="$1" dfp="$2" dlp="$3" d="$4" qc F N L M B why="" extra exp erc re; shift 4
  if [ "$REF_OK" != 1 ]; then t_skip 1 "$name (the reference commit $PRE is not in this clone, or git archive is not available)"; return; fi
  qc="$(cd "$d" && quoted_count)"
  : > "$SHIMLOG"; oneside o "$OLDG" "$d" "$@"
  oneside n "$NEWG" "$d" "$@"
  re='^files: ([0-9]+)/([0-9]+) lines: ([0-9]+)/([0-9]+) \(base=(.*)\)$'
  if ! [[ "$(head -n 1 "$DT/o.out")" =~ $re ]]; then
    why="the v0.24.27 run printed no size line: [$(head -c 120 "$DT/o.out" | tr '\n' '|')] [$(head -c 120 "$DT/o.err" | tr '\n' '|')]"
  else
    F=$((BASH_REMATCH[1] + qc * dfp)); N="${BASH_REMATCH[2]}"; L=$((BASH_REMATCH[3] + qc * dlp)); M="${BASH_REMATCH[4]}"; B="${BASH_REMATCH[5]}"
    exp="files: $F/$N lines: $L/$M (base=$B)"; erc=0
    if [ "$F" -gt "$N" ] || [ "$L" -gt "$M" ]; then exp="$exp"$'\n'"over the Lite size limit: escalate to Full"; erc=1; fi
    printf '%s\n' "$exp" > "$DT/q.exp"
    cmp -s "$DT/q.exp" "$DT/n.out" || why="stdout: expected [$(head -c 160 "$DT/q.exp" | tr '\n' '|')] (v0.24.27 [$(head -c 100 "$DT/o.out" | tr '\n' '|')], $qc quoted) now [$(head -c 160 "$DT/n.out" | tr '\n' '|')]"
    [ "$(cat "$DT/n.rc")" = "$erc" ] || why="$why exit code: expected $erc now $(cat "$DT/n.rc")"
    LC_ALL=C sort "$DT/o.err" > "$DT/o.es"; LC_ALL=C sort "$DT/n.err" > "$DT/n.es"
    extra="$(LC_ALL=C comm -13 "$DT/o.es" "$DT/n.es")"
    if [ -n "$extra" ]; then why="$why stderr has a line v0.24.27 did not print: [$(printf '%s' "$extra" | head -c 200 | tr '\n' '|')]"; fi
  fi
  if [ -z "$why" ]; then t_ok "$name"; else t_bad "$name" "$why"; fi
}
# nrow NAME DIR EXPECTED_STDOUT EXPECTED_RC ARGS... -> the current gate's stdout (absolute) and exit code; $DT/n.err keeps its stderr
nrow() {
  local name="$1" d="$2" exp="$3" erc="$4"; shift 4
  oneside n "$NEWG" "$d" "$@"
  chk "$name" "$exp"$'\n'"rc=$erc" "$(cat "$DT/n.out")"$'\n'"rc=$(cat "$DT/n.rc")"
}
# mk_mf DIR -> a baseline manifest of DIR's current state (on stdout)
mk_mf() {
  local mf; mf="$(mk_tmp)/m"
  ( cd "$1" && env PLAYBOOK_HOME="$PLAYBOOK_HOME" LC_ALL=C bash "$GATE" snapshot --out "$mf" >/dev/null 2>&1 )
  printf '%s\n' "$mf"
}
hsum() { # FILE -> its sha256 (cksum where neither tool exists)
  if command -v sha256sum >/dev/null 2>&1; then sha256sum < "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 < "$1" | cut -d' ' -f1
  else cksum < "$1"; fi
}
attr() { printf '%s\n' "$1" >> .gitattributes && git add .gitattributes && git commit -q -m attr; }
# mkkind KIND -> creates the files of KIND in the current repo (committing .gitattributes first when the kind needs it);
# returns 1 when this file system cannot hold the kind (the caller skips it)
mkkind() {
  local i
  case "$1" in
    text) printf 'a\nb\nc\n' > t.js ;;
    binary) printf 'B\000\003bin\n' > b.bin ;;
    empty) : > e.js ;;
    nofinalnl) printf 'a\nb' > nf.js ;;
    attr-binary) attr '*.dat binary'; printf 'x\ny\n' > a.dat ;;
    attr-nodiff) attr '*.nd -diff'; printf 'x\ny\nz\n' > a.nd ;;
    attr-eol) attr '*.crlf text eol=crlf'; printf 'a\nb\n' > lf.crlf; printf 'a\r\nb\r\n' > crlf.crlf ;;
    attr-textauto) attr '*.ta text=auto'; printf 'a\r\nb\r\nc\r\n' > m.ta ;;
    attr-driver-binary) git config diff.dbin.binary true; attr '*.db diff=dbin'; printf 'x\ny\n' > a.db ;;
    attr-driver-textconv) git config diff.dtc.textconv 'sed 1d'; attr '*.tc diff=dtc'; printf 'a\nb\nc\n' > a.tc ;;
    attr-driver-ext) git config diff.dex.command false; attr '*.ex diff=dex'; printf 'a\nb\n' > a.ex ;;
    autocrlf) GENV=(X_PB=1 GIT_CONFIG_VALUE_0=true); printf 'a\r\nb\r\n' > c1.js; printf 'a\nb\n' > c2.js; printf 'a\r\nb\n' > c3.js
      GIT_CONFIG_VALUE_0=true git status --porcelain >/dev/null 2>&1 ;;   # settle the index: the first run would otherwise print the tracked files' warnings, later runs not
    attr-clean) git config filter.up.clean 'tr a-z A-Z'; attr '*.up filter=up'; printf 'x\ny\nz\n' > a.up ;;
    safecrlf) git config core.safecrlf true; GENV=(X_PB=1 GIT_CONFIG_VALUE_0=true)
      printf 'a\nb\n' > lf.js; printf 'a\r\nb\n' > mix.js; printf 'a\r\nb\r\n' > crlf.js ;;
    attr-untracked) mkdir -p sub; printf '*.x binary\n' > sub/.gitattributes; printf 'a\nb\n' > sub/f.x ;;
    attr-deleted) printf '*.dat binary\n' > .gitattributes; git add .gitattributes; git commit -q -m attr; rm .gitattributes; printf 'x\ny\n' > ad.dat ;;
    symlink-file) [ "$SYMLINKS" = 1 ] || return 1; printf 'l1\nl2\n' > target.js; ln -s target.js lnk.js ;;
    symlink-dangling) [ "$SYMLINKS" = 1 ] || return 1; ln -s nowhere.js dang.js ;;
    bigfile) git config core.bigFileThreshold 1k; i=0; while [ "$i" -lt 400 ]; do printf 'line %s\n' "$i"; i=$((i + 1)); done > big.js ;;
    exec) printf '#!/bin/sh\necho a\n' > run.sh; chmod +x run.sh ;;
    name-space) printf 'a\nb\n' > 'my file.js' ;;
    name-dash) printf 'a\nb\n' > ./-lead.js ;;
    name-unicode) printf 'a\nb\n' > $'caf\303\251.js' ;;
    name-squote) printf 'a\nb\n' > "it's.js" ;;
    name-star) printf 'a\nb\n' > '*.js' || return 1; printf 'c\n' > plain1.js; printf 'd\ne\n' > 'q?.js' || return 1; printf 'f\n' > 'br[1].js' || return 1 ;;
    name-glob) printf 'a\nb\n' > ':(glob)x.js' || return 1; printf 'c\n' > ':(top)y.js' || return 1 ;;
    indir) mkdir -p newdir/deep; printf 'a\n' > newdir/deep/x.js; printf 'b\nc\n' > newdir/y.js ;;
    routed-tab) printf 'a\nb\n' > $'ta\tb.js' || return 1 ;;
    routed-dquote) printf 'a\nb\n' > 'q"x.js' || return 1 ;;
    routed-backslash) printf 'a\nb\n' > 'bs\x.js' || return 1 ;;
    routed-newline) printf 'a\nb\n' > $'nl\nx.js' || return 1 ;;
    routed-symlink-dir) [ "$SYMLINKS" = 1 ] || return 1; ln -s src sd ;;
    routed-nested-repo) git init -q nested && ( cd nested && git config user.email t@example.invalid && git config user.name t &&
                          printf 'a\n' > f && git add f && git commit -q -m n ) ;;
    *) return 1 ;;
  esac
}
K_SAME="text binary empty nofinalnl attr-binary attr-nodiff attr-eol attr-textauto attr-driver-binary attr-driver-textconv
 attr-driver-ext autocrlf attr-untracked attr-deleted symlink-file symlink-dangling bigfile exec name-space name-dash name-unicode
 name-squote name-star name-glob indir attr-clean safecrlf"
K_ROUTED="routed-tab routed-dquote routed-backslash routed-newline routed-symlink-dir routed-nested-repo"
mkrepo() { R="$(mk_tmp)"; mk_repo "$R"; cd "$R" || exit 3; }

MF0DIR="$(mk_tmp)"; mk_repo "$MF0DIR"; MF0="$(mk_mf "$MF0DIR")"   # the manifest of a clean repo: nothing is excluded

# ---------------------------------------------------------------- AC1 every kind, one repo each
echo "AC1 each kind of untracked file is counted as v0.24.27 counts it (plain size, wide limits)"
for k in $K_SAME $K_ROUTED; do
  GENV=(X_PB=1)
  mkrepo
  if ! mkkind "$k"; then t_skip 1 "AC1 kind $k (this file system cannot hold it)"; continue; fi
  case "$k" in
    routed-tab | routed-dquote | routed-backslash | routed-newline)
      cmp_q "AC1 kind $k (git-quoted name, 2 lines): v0.24.27 files, 2 more lines (NTFS tab: as v0.24.27)" 0 2 "$R" size $WIDE
      cmp_q "AC1 kind $k (git-quoted name, 2 lines), --baseline of a clean repo: v0.24.27 files, 2 more lines" 0 2 "$R" size $WIDE --baseline "$MF0" ;;
    routed-*) cmp_gate "AC1 kind $k (routed to the per-file command): stdout, exit code and stderr as v0.24.27" "$R" size $WIDE ;;
    *) cmp_gate "AC1 kind $k (batch): stdout, exit code and stderr as v0.24.27" "$R" size $WIDE ;;
  esac
done
GENV=(X_PB=1)

# ---------------------------------------------------------------- AC1 corpus: all kinds together, plain, default limits, --baseline
echo "AC1 all kinds in one repo: plain, default limits and --baseline"
mkrepo; CORP="$R"
for k in $K_SAME routed-tab routed-dquote routed-backslash routed-symlink-dir routed-nested-repo; do
  case "$k" in autocrlf | attr-deleted | safecrlf) continue ;; esac
  mkkind "$k" 2>/dev/null || true
done
GENV=(X_PB=1)
cmp_q "AC1 corpus: plain size, wide limits: v0.24.27 + 2 lines per git-quoted file (3 files: +6; NTFS +4)" 0 2 "$CORP" size $WIDE
cmp_q "AC1 corpus: plain size, default limits (over the limit: exit 1): + 2 lines per git-quoted file" 0 2 "$CORP" size
cmp_q "AC1 corpus: size --baseline of a clean repo (every untracked path counted): + 2 lines per git-quoted file" 0 2 "$CORP" size $WIDE --baseline "$MF0"
CMF="$(mk_mf "$CORP")"
if [ -s "$CMF" ]; then
  printf 'a\nb\nc\nd\n' > zz-new.js; printf 'more\n' >> t.js
  cmp_q "AC1 corpus: size --baseline taken with every kind present: the git-quoted files match the manifest by raw name and are left out (1 file less each, same lines)" -1 0 "$CORP" size $WIDE --baseline "$CMF"
  cmp_q "AC1 corpus: size --baseline with default limits: the git-quoted files are left out (1 file less each, same lines)" -1 0 "$CORP" size --baseline "$CMF"
else t_bad "AC1 corpus: the baseline manifest of the corpus could not be written" "snapshot --out gave no file"; fi

# ---------------------------------------------------------------- S1 quoted names: raw-name classification and counting, default limits
echo "S1 git-quoted untracked names are classified, skipped, baseline-matched and counted by the raw name (default limits: 3 files, 100 lines)"
S1_OVER="over the Lite size limit: escalate to Full"
# s1_name KIND EXT -> the file name of KIND (tab, dquote, backslash) with extension EXT
s1_name() { case "$1" in tab) printf 'a\tb.%s' "$2" ;; dquote) printf 'q"x.%s' "$2" ;; backslash) printf 'bs\\x.%s' "$2" ;; esac; }
# s1_put PATH LINES -> PATH with that many lines (parent dirs made); 1 when this file system cannot hold the name
s1_put() { local i=0; mkdir -p "$(dirname "$1")" && : > "$1" 2>/dev/null || return 1; while [ "$i" -lt "$2" ]; do printf 'line %s\n' "$i" >> "$1"; i=$((i + 1)); done; }
for kind in tab dquote backslash; do
  for place in tests handoff; do
    case "$place" in tests) rel="tests/$(s1_name "$kind" js)" ;; handoff) rel=".agents/handoff/$(s1_name "$kind" md)" ;; esac
    mkrepo
    if ! s1_put "$rel" 2 || ! s1_put src/p.js 1; then t_skip 2 "S1 $place $kind name (this file system cannot hold it)"; continue; fi
    nrow "S1 AC2 untracked $rel + 1-line src/p.js: the $kind-named $place file is not production: 1 file, 1 line" "$R" "files: 1/3 lines: 1/100 (base=HEAD)" 0 size
    nrow "S1 AC2 untracked $rel + 1-line src/p.js, --baseline of a clean repo: 1 file, 1 line" "$R" "files: 1/3 lines: 1/100 (base=HEAD)" 0 size --baseline "$MF0"
  done
done

# a baseline manifest that holds production files with the three names; the raw names match it, so only the new src/p.js counts
mkrepo; made=0
for kind in tab dquote backslash; do if s1_put "src/$(s1_name "$kind" js)" 1; then made=$((made + 1)); fi; done
if [ "$made" -gt 0 ]; then
  S1MF="$(mk_mf "$R")"
  if [ -s "$S1MF" ]; then
    s1_put src/p.js 1
    nrow "S1 AC2 --baseline manifest holds src files named with a tab, a quote, a backslash ($made made): they match by raw name; new src/p.js: 1 file, 1 line" "$R" "files: 1/3 lines: 1/100 (base=HEAD)" 0 size --baseline "$S1MF"
  else t_bad "S1 AC2 --baseline manifest with quoted production names could not be written" "snapshot --out gave no file"; fi
else t_skip 1 "S1 AC2 --baseline manifest with quoted production names (this file system cannot hold them)"; fi

# a 101-line production file with a quoted name pushes the total over the limit
for kind in tab dquote backslash; do
  mkrepo
  if ! s1_put "src/$(s1_name "$kind" js)" 101; then t_skip 1 "S1 AC3 $kind-named production file (this file system cannot hold it)"; continue; fi
  nrow "S1 AC3 a 101-line production file with a $kind in its name: lines 101/100, escalate to Full, exit 1" "$R" "files: 1/3 lines: 101/100 (base=HEAD)"$'\n'"$S1_OVER" 1 size
done

# an unreadable test path is a test (D2): no error, no count; skipped where chmod 000 does not block reads (root, NTFS)
UP="$(mk_tmp)/probe"; printf 'x\n' > "$UP"; chmod 000 "$UP" 2>/dev/null
if cat "$UP" >/dev/null 2>&1; then t_skip 4 "S1 AC2 unreadable tests/ name (chmod 000 does not block reads here: root or NTFS)"
else
  mkrepo
  if s1_put "tests/$(s1_name tab js)" 3 && s1_put src/p.js 1; then
    chmod 000 "tests/$(s1_name tab js)"
    nrow "S1 AC2 unreadable (chmod 000) tests/x<TAB>y.js + 1-line src/p.js: a test path, no error: 1 file, 1 line" "$R" "files: 1/3 lines: 1/100 (base=HEAD)" 0 size
    assert_not_contains "S1 AC2 unreadable tests/ name: no 'cannot count' line on stderr" "$(cat "$DT/n.err")" "cannot count"
    nrow "S1 AC2 unreadable tests/ name, --baseline of a clean repo: 1 file, 1 line" "$R" "files: 1/3 lines: 1/100 (base=HEAD)" 0 size --baseline "$MF0"
    assert_not_contains "S1 AC2 unreadable tests/ name, --baseline: no 'cannot count' line on stderr" "$(cat "$DT/n.err")" "cannot count"
  else t_skip 4 "S1 AC2 unreadable tests/ name (this file system cannot hold a tab in a name)"; fi
fi

# D13/D23: a raw name with a newline is production even under tests/ (the newline-separated classify could otherwise under-count)
mkrepo
if s1_put $'tests/a\nb.js' 2 && git -c core.quotepath=off ls-files --others | grep -q '\\n'; then
  nrow "S1 AC2 untracked tests/a<LF>b.js (2 lines): counted as production (D23): 1 file, 2 lines" "$R" "files: 1/3 lines: 2/100 (base=HEAD)" 0 size
  nrow "S1 AC2 untracked tests/a<LF>b.js (2 lines), --baseline of a clean repo: 1 file, 2 lines" "$R" "files: 1/3 lines: 2/100 (base=HEAD)" 0 size --baseline "$MF0"
else t_skip 2 "S1 AC2 tests/a<LF>b.js (this file system cannot hold a newline in a name, or git does not list it as a quoted name: NTFS maps it to a private-use character)"; fi

# ---------------------------------------------------------------- S2 fail closed: an uncountable untracked production file is exit 3
echo "S2 an untracked production file that size cannot count fails closed: stderr line, no files: line, exit 3 (D1, D21)"
S2_MSG_TAIL="(unreadable, or gone since the listing); fix it and run size again"
s2_err() { printf 'error: cannot count the lines of untracked file %s %s' "$1" "$S2_MSG_TAIL"; }   # one expected stderr line (no trailing newline)
# chmod 000 does not block reads as root or on NTFS: the unreadable rows skip there (as tests/test-role-gate-baseline.sh:636-640)
S2_UP="$(mk_tmp)/probe"; printf 'x\n' > "$S2_UP"; chmod 000 "$S2_UP" 2>/dev/null
if cat "$S2_UP" >/dev/null 2>&1; then S2_CHMOD=0; else S2_CHMOD=1; fi
# s2row NAME DIR EXPECTED_STDERR ARGS... -> the current gate prints no stdout (no `files:` line), exit 3, and stderr is EXACTLY EXPECTED_STDERR
s2row() {
  local name="$1" d="$2" experr="$3"; shift 3
  oneside n "$NEWG" "$d" "$@"
  chk "$name: stdout empty (no files: line), exit 3" $'\nrc=3' "$(cat "$DT/n.out")"$'\nrc='"$(cat "$DT/n.rc")"
  chk "$name: stderr is exactly the cannot-count line(s)" "$experr" "$(cat "$DT/n.err")"
}
# an s2 gate run under the counting shim in MODE (the shim env is set only for this call); PATH = shim first
s2shim() { # MODE NAME DIR EXPECTED_STDERR ARGS...
  local mode="$1"; shift
  GENV=(X_PB=1 PB_SHIM_MODE="$mode" PB_SHIM_LOG="$SHIMLOG" PB_SHIM_FIRED="$SHIMFIRED" PB_VANISH_PATH="${S2_VANISH:-}"); GPATH="$SHIM:$PATH"
  : > "$SHIMLOG"; : > "$SHIMFIRED"; rm -f "$SHIMFIRED.listed"
  s2row "$@"
  unset GPATH; GENV=(X_PB=1)
}

if [ "$S2_CHMOD" = 1 ]; then
  # AC4: unreadable production file (plain name, plain and --baseline)
  mkrepo; printf 'a\nb\nc\n' > src/unr.js; chmod 000 src/unr.js; R_UNR="$R"
  s2row "S2 AC4 unreadable (chmod 000) untracked src/unr.js" "$R_UNR" "$(s2_err src/unr.js)" size
  s2row "S2 AC4 unreadable untracked src/unr.js, --baseline of a clean repo" "$R_UNR" "$(s2_err src/unr.js)" size --baseline "$MF0"
  # an unreadable file next to a readable one: the readable one does not make a total (no files: line at all)
  mkrepo; printf 'a\nb\nc\n' > src/unr.js; chmod 000 src/unr.js; printf 'ok\n' > src/ok.js
  s2row "S2 AC4 unreadable src/unr.js next to a readable src/ok.js: still no total" "$R" "$(s2_err src/unr.js)" size
  # AC4: the same on a file with a git-quoted name (tab): the raw name is in the line
  mkrepo
  if s1_put "src/$(s1_name tab js)" 2; then
    chmod 000 "src/$(s1_name tab js)"
    s2row "S2 AC4 unreadable src/a<TAB>b.js (git-quoted name): the raw name (a real TAB) is in the line" "$R" "$(s2_err "src/$(s1_name tab js)")" size
  else t_skip 2 "S2 AC4 unreadable tab-named file (this file system cannot hold a tab in a name)"; fi

  # AC6: several uncountable files: one line each, in ls-files -z order (byte order, not creation order); control chars but TAB shown as ?
  mkrepo; printf 'ok\n' > src/m.js
  mk_ok=1
  for nm in src/z.js $'src/t\tb.js' $'src/n\nx.js' $'src/c\003d.js' src/a.js; do
    if ! { : > "$nm" 2>/dev/null && printf 'l1\nl2\n' > "$nm" && chmod 000 "$nm"; }; then mk_ok=0; fi
  done
  if [ "$mk_ok" = 1 ]; then
    exp6="$(s2_err src/a.js)"$'\n'"$(s2_err 'src/c?d.js')"$'\n'"$(s2_err 'src/n?x.js')"$'\n'"$(s2_err $'src/t\tb.js')"$'\n'"$(s2_err src/z.js)"
    s2row "S2 AC6 five uncountable files (created z, t<TAB>, n<LF>, c<ETX>, a): five lines in ls-files -z order, control chars but TAB as ?" "$R" "$exp6" size
    s2row "S2 AC6 the same five files, --baseline of a clean repo" "$R" "$exp6" size --baseline "$MF0"
  else t_skip 4 "S2 AC6 five uncountable files (this file system cannot hold the names)"; fi
  mkrepo; for nm in src/z.js src/a.js; do printf 'l1\n' > "$nm"; chmod 000 "$nm"; done
  s2row "S2 AC6 two unreadable files (created z, a): two lines, a first" "$R" "$(s2_err src/a.js)"$'\n'"$(s2_err src/z.js)" size

  # AC7 / D2: a test path or .agents/handoff/ file is not counted and causes no error, also when unreadable
  mkrepo; printf 'ok\n' > src/p.js; mkdir -p .agents/handoff tests
  printf 'a\n' > tests/u.js; printf 'a\n' > .agents/handoff/h.md; chmod 000 tests/u.js .agents/handoff/h.md
  s1_put ".agents/handoff/$(s1_name tab md)" 2 && chmod 000 ".agents/handoff/$(s1_name tab md)"
  nrow "S2 AC7 unreadable tests/u.js, .agents/handoff/h.md and .agents/handoff/a<TAB>b.md + 1-line src/p.js: all skipped, no error: 1 file, 1 line" "$R" "files: 1/3 lines: 1/100 (base=HEAD)" 0 size
  assert_not_contains "S2 AC7 unreadable test and handoff files: no 'cannot count' line on stderr" "$(cat "$DT/n.err")" "cannot count"
  nrow "S2 AC7 the same, --baseline of a clean repo" "$R" "files: 1/3 lines: 1/100 (base=HEAD)" 0 size --baseline "$MF0"
  assert_not_contains "S2 AC7 the same, --baseline: no 'cannot count' line on stderr" "$(cat "$DT/n.err")" "cannot count"
  # an unreadable test file next to an unreadable production file: only the production file is named
  mkrepo; printf 'a\n' > tests/u.js; chmod 000 tests/u.js; printf 'a\nb\n' > src/unr.js; chmod 000 src/unr.js
  s2row "S2 AC7 unreadable tests/u.js + unreadable src/unr.js: exit 3 names only src/unr.js" "$R" "$(s2_err src/unr.js)" size
  # D13/D23: a raw name with a newline is production even under tests/ or .agents/handoff/: unreadable -> exit 3
  mkrepo
  if s1_put $'tests/a\nb.js' 2; then
    chmod 000 $'tests/a\nb.js'
    s2row "S2 AC7 unreadable tests/a<LF>b.js (production by D23): exit 3, the newline shown as ?" "$R" "$(s2_err 'tests/a?b.js')" size
  else t_skip 2 "S2 AC7 unreadable tests/a<LF>b.js (this file system cannot hold a newline in a name)"; fi
  mkrepo
  if s1_put $'.agents/handoff/a\nb.md' 2; then
    chmod 000 $'.agents/handoff/a\nb.md'
    s2row "S2 AC7 unreadable .agents/handoff/a<LF>b.md (production by D23): exit 3, the newline shown as ?" "$R" "$(s2_err '.agents/handoff/a?b.md')" size
  else t_skip 2 "S2 AC7 unreadable .agents/handoff/a<LF>b.md (this file system cannot hold a newline in a name)"; fi
else
  t_skip 22 "S2 AC4/AC6/AC7 unreadable rows (chmod 000 does not block reads here: root or NTFS)"
fi

# AC5: a file that vanishes after the listing (the shim deletes it right before the first count call; the tracked numstat runs before the
# listing, and hash-object is not a trigger because --baseline hashes the work tree first): same exit 3, same line
mkrepo; printf 'a\nb\n' > src/v.js; printf 'ok\n' > src/ok.js; R_V="$R"
S2_VANISH=src/v.js
s2shim vanish "S2 AC5 src/v.js vanishes after the listing" "$R_V" "$(s2_err src/v.js)" size
chk "S2 AC5 control: the shim really deleted src/v.js after the listing (it fired, and the file is gone)" "1" "$([ -s "$SHIMFIRED" ] && [ ! -e "$R_V/src/v.js" ] && echo 1 || echo 0)"
mkrepo; printf 'a\nb\n' > src/v.js; printf 'ok\n' > src/ok.js; R_V="$R"
s2shim vanish "S2 AC5 src/v.js vanishes after the listing, --baseline of a clean repo" "$R_V" "$(s2_err src/v.js)" size --baseline "$MF0"
chk "S2 AC5 control: --baseline: the shim really deleted src/v.js after the listing" "1" "$([ -s "$SHIMFIRED" ] && [ ! -e "$R_V/src/v.js" ] && echo 1 || echo 0)"
# a tab-named file (routed per-file) vanishes the same way
mkrepo
if s1_put "src/$(s1_name tab js)" 2 && routed_listed; then
  S2_VANISH="src/$(s1_name tab js)"
  s2shim vanish "S2 AC5 src/a<TAB>b.js vanishes after the listing" "$R" "$(s2_err "src/$(s1_name tab js)")" size
else t_skip 2 "S2 AC5 tab-named file that vanishes (this file system cannot hold a tab in a name, or git does not list it as a quoted name: NTFS maps a tab to a private-use character)"; fi
# D2: a test file that vanishes is not an error
mkrepo; printf 'a\nb\n' > tests/gone.js; printf 'ok\n' > src/p.js; S2_VANISH=tests/gone.js
GENV=(X_PB=1 PB_SHIM_MODE=vanish PB_SHIM_LOG="$SHIMLOG" PB_SHIM_FIRED="$SHIMFIRED" PB_VANISH_PATH="$S2_VANISH"); GPATH="$SHIM:$PATH"; : > "$SHIMFIRED"; rm -f "$SHIMFIRED.listed"
nrow "S2 AC7 tests/gone.js vanishes after the listing: not an error: 1 file, 1 line" "$R" "files: 1/3 lines: 1/100 (base=HEAD)" 0 size
assert_not_contains "S2 AC7 vanished test file: no 'cannot count' line on stderr" "$(cat "$DT/n.err")" "cannot count"
chk "S2 AC7 control: the shim really deleted tests/gone.js" "1" "$([ -s "$SHIMFIRED" ] && [ ! -e "$R/tests/gone.js" ] && echo 1 || echo 0)"
unset GPATH; GENV=(X_PB=1); S2_VANISH=

# AC5: the per-file count itself fails (batch refused too, so the file reaches the per-file command): git exits above 1, or prints no
# numstat line for a non-empty file -> exit 3; a regular file of size 0 still counts 1 file, 0 lines
mkrepo; printf 'a\nb\n' > src/p.js; R_P="$R"
s2shim uncount-128 "S2 AC5 per-file git exits 128 for src/p.js (2 lines)" "$R_P" "$(s2_err src/p.js)" size
s2shim uncount-128 "S2 AC5 per-file git exits 128 for src/p.js, --baseline of a clean repo" "$R_P" "$(s2_err src/p.js)" size --baseline "$MF0"
chk "S2 AC5 control: the per-file command was reached (a diff --no-index in the shim log)" "1" "$(grep -q '^diff-noindex' "$SHIMLOG" && echo 1 || echo 0)"
s2shim uncount-none "S2 AC5 per-file git prints no numstat line for the non-empty src/p.js (exit 1)" "$R_P" "$(s2_err src/p.js)" size
chk "S2 AC5 control: the per-file command was reached (a diff --no-index in the shim log)" "1" "$(grep -q '^diff-noindex' "$SHIMLOG" && echo 1 || echo 0)"
mkrepo; : > src/empty.js
GENV=(X_PB=1 PB_SHIM_MODE=uncount-none PB_SHIM_LOG="$SHIMLOG" PB_SHIM_FIRED="$SHIMFIRED"); GPATH="$SHIM:$PATH"; : > "$SHIMLOG"
nrow "S2 AC5 a size-0 src/empty.js with no numstat line from git: still 1 file, 0 lines, exit 0" "$R" "files: 1/3 lines: 0/100 (base=HEAD)" 0 size
chk "S2 AC5 size-0 file: no cannot-count line on stderr" "" "$(cat "$DT/n.err")"
unset GPATH; GENV=(X_PB=1)
mkrepo; : > src/empty.js; printf 'a\nb\n' > src/two.js
nrow "S2 AC5 control (no shim): a size-0 file and a 2-line file: 2 files, 2 lines" "$R" "files: 2/3 lines: 2/100 (base=HEAD)" 0 size

# AC8: a path that is not a regular file or a symlink to a file keeps its v0.24.27 count and never causes exit 3
echo "S2 AC8 non-regular kinds keep their count and never exit 3"
if [ "$SYMLINKS" = 1 ]; then
  mkrepo; ln -s src sd
  nrow "S2 AC8 untracked symlink to a directory: 1 file, 0 lines, exit 0" "$R" "files: 1/3 lines: 0/100 (base=HEAD)" 0 size
  chk "S2 AC8 symlink to a directory: stderr has no cannot-count line" "0" "$(grep -c 'cannot count' "$DT/n.err" | tr -d ' ')"
  mkrepo; ln -s nowhere.js dang.js
  nrow "S2 AC8 untracked dangling symlink alone: 1 file, 1 line (the link text), exit 0" "$R" "files: 1/3 lines: 1/100 (base=HEAD)" 0 size
  chk "S2 AC8 dangling symlink: stderr has no cannot-count line" "0" "$(grep -c 'cannot count' "$DT/n.err" | tr -d ' ')"
  nrow "S2 AC8 untracked dangling symlink alone, --baseline of a clean repo: 1 file, 1 line" "$R" "files: 1/3 lines: 1/100 (base=HEAD)" 0 size --baseline "$MF0"
else t_skip 5 "S2 AC8 symlink kinds (this file system has none)"; fi
mkrepo; git init -q nested && ( cd nested && git config user.email t@example.invalid && git config user.name t && printf 'a\n' > f && git add f && git commit -q -m n )
nrow "S2 AC8 nested repo with a commit: 1 file, 0 lines, exit 0" "$R" "files: 1/3 lines: 0/100 (base=HEAD)" 0 size
chk "S2 AC8 nested repo with a commit: stderr has no cannot-count line" "0" "$(grep -c 'cannot count' "$DT/n.err" | tr -d ' ')"
mkrepo; git init -q emptynest
nrow "S2 AC8 nested repo without commits: 1 file, 0 lines, exit 0" "$R" "files: 1/3 lines: 0/100 (base=HEAD)" 0 size
chk "S2 AC8 nested repo without commits: stderr has no cannot-count line" "0" "$(grep -c 'cannot count' "$DT/n.err" | tr -d ' ')"
# the fifo row needs a git that sees a fifo as a non-regular file: Git Bash on Windows makes a pipe.fifo.lnk shortcut that git lists, so it skips there
if mkrepo && mkfifo pipe.fifo 2>/dev/null && [ -p pipe.fifo ] && ! git -c core.quotepath=off ls-files --others | grep -q '^pipe[.]fifo'; then
  printf 'ok\n' > src/p.js
  nrow "S2 AC8 a fifo next to a 1-line src/p.js: the fifo is not listed and not counted: 1 file, 1 line, exit 0" "$R" "files: 1/3 lines: 1/100 (base=HEAD)" 0 size
else t_skip 1 "S2 AC8 fifo (mkfifo is not available here, or makes no real fifo: Git Bash on Windows)"; fi
# the non-regular kinds do not hide a regular uncountable file next to them, and are not named in the error
if [ "$S2_CHMOD" = 1 ] && [ "$SYMLINKS" = 1 ]; then
  mkrepo; ln -s src sd; ln -s nowhere.js dang.js; git init -q nested; printf 'a\nb\n' > src/unr.js; chmod 000 src/unr.js
  s2row "S2 AC8 symlink to a directory, dangling symlink, nested repo + unreadable src/unr.js: exit 3 names only src/unr.js" "$R" "$(s2_err src/unr.js)" size
else t_skip 2 "S2 AC8 non-regular kinds next to an unreadable file (chmod 000 does not block reads, or no symlinks)"; fi

# S-fix F3: the AC5 clause "git exits above 1" on its own: the per-file command exits 2 yet prints a numstat line -> exit 3 (kills rc -gt 128)
mkrepo; printf 'a\nb\n' > src/p.js
s2shim rc2 "S-fix F3 per-file git exits 2 but prints a numstat line for src/p.js" "$R" "$(s2_err src/p.js)" size
chk "S-fix F3 control: the per-file command ran and exited 2 (the shim fired)" "1" "$([ -s "$SHIMFIRED" ] && grep -q '^diff-noindex' "$SHIMLOG" && echo 1 || echo 0)"

# S-fix F1: git counts a symlink's link text, so a symlink to an unreadable target is 1 file, 1 line, whatever the route
echo "S-fix F1 a symlink is counted by its link text (never by its target), also on the per-file route"
if [ "$S2_CHMOD" = 1 ] && [ "$SYMLINKS" = 1 ]; then
  F1T="$(mk_tmp)/tgt"; printf 'a\nb\nc\n' > "$F1T"; chmod 000 "$F1T"
  mkrepo; ln -s "$F1T" src/pl.js
  nrow "S-fix F1 control: plain-name symlink to an unreadable target (batch route): 1 file, 1 line, exit 0" "$R" "files: 1/3 lines: 1/100 (base=HEAD)" 0 size
  mkrepo; ln -s "$F1T" "src/$(s1_name dquote js)"
  nrow "S-fix F1 quoted-name (q\"x.js) symlink to an unreadable target (per-file route): 1 file, 1 line, exit 0" "$R" "files: 1/3 lines: 1/100 (base=HEAD)" 0 size
  chk "S-fix F1 quoted-name symlink: no cannot-count line on stderr" "0" "$(grep -c 'cannot count' "$DT/n.err" | tr -d ' ')"
  mkrepo; ln -s "$F1T" src/pl.js
  GENV=(X_PB=1 PB_SHIM_MODE=upd-fail PB_SHIM_LOG="$SHIMLOG" PB_SHIM_FIRED="$SHIMFIRED"); GPATH="$SHIM:$PATH"; : > "$SHIMLOG"; : > "$SHIMFIRED"
  nrow "S-fix F1 plain-name symlink to an unreadable target, batch refused (whole list per-file): 1 file, 1 line, exit 0" "$R" "files: 1/3 lines: 1/100 (base=HEAD)" 0 size
  chk "S-fix F1 control: the batch was refused and the per-file command ran" "1" "$([ -s "$SHIMFIRED" ] && grep -q '^diff-noindex' "$SHIMLOG" && echo 1 || echo 0)"
  unset GPATH; GENV=(X_PB=1)
else t_skip 5 "S-fix F1 symlink to an unreadable target (chmod 000 does not block reads, or no symlinks)"; fi

# S-fix F4: a path the manifest records as unchanged that vanishes after the listing is skipped, not an error (spec: baseline-unchanged paths
# are left out of the error list); only the BL_UNCH skip in pf_emit does this
mkrepo; printf 'a\nb\n' > src/v.js; MF_V="$(mk_mf "$R")"; printf 'ok\n' > src/ok.js
S2_VANISH=src/v.js
GENV=(X_PB=1 PB_SHIM_MODE=vanish PB_SHIM_LOG="$SHIMLOG" PB_SHIM_FIRED="$SHIMFIRED" PB_VANISH_PATH="$S2_VANISH"); GPATH="$SHIM:$PATH"; : > "$SHIMFIRED"; rm -f "$SHIMFIRED.listed"
nrow "S-fix F4 manifest-unchanged src/v.js vanishes after the listing, --baseline: skipped, not exit 3: 1 file, 1 line" "$R" "files: 1/3 lines: 1/100 (base=HEAD)" 0 size --baseline "$MF_V"
chk "S-fix F4 control: the shim really deleted src/v.js after the listing" "1" "$([ -s "$SHIMFIRED" ] && [ ! -e "$R/src/v.js" ] && echo 1 || echo 0)"
unset GPATH; GENV=(X_PB=1); S2_VANISH=

# AC16 (the docs the spec puts in S2: the header, the exit line, SKILL.md; the method comment and CHANGELOG are S3 / the release)
echo "S2 AC16 the docs name the size exit 3"
HDR="$(sed -n '1,/^set -u$/p' "$PB_ROOT/scripts/role-gate.sh")"
EXITL="$(printf '%s\n' "$HDR" | sed -n '/^# Exit:/,/(INT \/ TERM)/p' | tr '\n' ' ')"
case "$EXITL" in *"untracked"*) t_ok "S2 AC16 the header exit line names an untracked file that size cannot count as an exit-3 cause" ;; *) t_bad "S2 AC16 the header exit line names an untracked file that size cannot count as an exit-3 cause" "exit line: [$EXITL]" ;; esac
case "$HDR" in *"cannot count the lines of untracked file"*) t_ok "S2 AC16 the header says size prints the cannot-count line" ;; *) t_bad "S2 AC16 the header says size prints the cannot-count line" "no 'cannot count the lines of untracked file' in the header (before set -u)" ;; esac
SKL="$(sed -n '/^### Lite workflow/,/^### Exempt/p' "$PB_ROOT/skills/playbook-tdd/SKILL.md" | tr '\n' ' ')"
case "$SKL" in *"size --base"*"exit 3"* | *"size --base"*"exits 3"*) t_ok "S2 AC16 SKILL.md Lite step 3 says what exit 3 from size means" ;; *) t_bad "S2 AC16 SKILL.md Lite step 3 says what exit 3 from size means" "no 'exit 3' / 'exits 3' after 'size --base' in the Lite workflow" ;; esac
case "$SKL" in *"exit 3"*"fix"*"again"* | *"exits 3"*"fix"*"again"*) t_ok "S2 AC16 SKILL.md says to fix the named file and run size again" ;; *) t_bad "S2 AC16 SKILL.md says to fix the named file and run size again" "no 'fix ... again' next to exit 3 in the Lite workflow" ;; esac

# ---------------------------------------------------------------- AC2 git calls do not grow with the number of files
echo "AC2 the number of git calls does not depend on the number of untracked files (counting git shim)"
# count_calls DIR ARGS... -> CNT (git calls of one run of the current gate), SIZEOUT
count_calls() {
  local d="$1"; shift
  GENV=(X_PB=1 PB_SHIM_MODE=count PB_SHIM_LOG="$SHIMLOG" PB_SHIM_FIRED="$SHIMFIRED"); GPATH="$SHIM:$PATH"
  : > "$SHIMLOG"; oneside c "$NEWG" "$d" "$@"
  unset GPATH; GENV=(X_PB=1)
  CNT="$(wc -l < "$SHIMLOG" | tr -d ' ')"; SIZEOUT="$(cat "$DT/c.out")"
}
mkfiles() { # PREFIX N -> N regular files with 1 line each
  local i=0; while [ "$i" -lt "$2" ]; do i=$((i + 1)); printf 'line %s\n' "$i" > "$1$i.js"; done
}
mkrepo; mkfiles f 2; D_2="$R"
mkrepo; mkfiles f 200; D_200="$R"
count_calls "$D_2" size $WIDE; C2="$CNT"
count_calls "$D_200" size $WIDE; C200="$CNT"
assert_contains "AC2 control: the run with 200 untracked files counted all of them" "$SIZEOUT" "files: 200/1000 lines: 200/100000"
chk "AC2 plain size: 200 untracked files make as many git calls as 2 (2 files: $C2 calls)" "$C2" "$C200"

mkrepo; mkfiles f 2; mkfiles g 2; D_2="$R"
mkrepo; mkfiles f 2; mkfiles g 200; D_200="$R"
count_calls "$D_2" size $WIDE --baseline "$MF0"; C2="$CNT"
count_calls "$D_200" size $WIDE --baseline "$MF0"; C200="$CNT"
assert_contains "AC2 control: size --baseline counted all 202 untracked files" "$SIZEOUT" "files: 202/1000"
chk "AC2 size --baseline: 202 untracked files make as many git calls as 4 (4 files: $C2 calls)" "$C2" "$C200"

if mkrepo && mkkind routed-tab && mkfiles f 2 && D_2="$R" && mkrepo && mkkind routed-tab && mkfiles f 200 && D_200="$R"; then
  count_calls "$D_2" size $WIDE; C2="$CNT"
  count_calls "$D_200" size $WIDE; C200="$CNT"
  chk "AC2 a tab-named file next to 200 regular ones: as many git calls as next to 2 (the routed file costs the same)" "$C2" "$C200"
else t_skip 1 "AC2 a tab-named file (this file system cannot hold it)"; fi

if mkrepo && mkkind name-star && mkkind name-glob && mkfiles f 2 && D_2="$R" && mkrepo && mkkind name-star && mkkind name-glob && mkfiles f 200 && D_200="$R"; then
  count_calls "$D_2" size $WIDE; C2="$CNT"
  count_calls "$D_200" size $WIDE; C200="$CNT"
  chk "AC2 names that look like a glob or pathspec magic (*.js, q?.js, br[1].js, :(glob)x.js, :(top)y.js) stay literal: 200 regular files make as many git calls as 2" "$C2" "$C200"
else t_skip 1 "AC2 glob-looking names (this file system cannot hold them)"; fi

if [ "$SYMLINKS" = 1 ]; then
  mklinks() { local i=0; printf 'x\n' > tgt.js; while [ "$i" -lt "$1" ]; do i=$((i + 1)); printf 'line %s\n' "$i" > "r$i.js"; ln -s tgt.js "s$i.js"; done; }
  mkrepo; mklinks 1; D_2="$R"
  mkrepo; mklinks 100; D_200="$R"
  count_calls "$D_2" size $WIDE; C2="$CNT"
  count_calls "$D_200" size $WIDE; C200="$CNT"
  assert_contains "AC2 control: 100 regular files and 100 symlinks to files were all counted" "$SIZEOUT" "files: 201/1000"
  chk "AC2 100 regular files + 100 symlinks to files make as many git calls as 1 + 1" "$C2" "$C200"
else t_skip 2 "AC2 symlinks (this file system has none)"; fi

mkrepo; count_calls "$R" size $WIDE
chk "AC2/N2 characterization: no untracked file, no batch call (update-index, diff-batch, add -N) and no temporary index" "0" "$(grep -c '^add-N\|^update-index\|^diff-batch\|idx=1' "$SHIMLOG" | tr -d ' ')"
if mkrepo && mkkind routed-tab && routed_listed; then
  count_calls "$R" size $WIDE
  chk "AC2/N2 characterization: only a per-file-routed untracked name: no update-index and no diff-batch" "0" "$(grep -c '^update-index\|^diff-batch' "$SHIMLOG" | tr -d ' ')"
else t_skip 1 "AC2/N2 routed-only list (this file system cannot hold a tab in a name, or git does not list it as a quoted name)"; fi

# ---------------------------------------------------------------- S3 AC10: one linear call, whatever the number of files
echo "S3 AC10 the untracked batch is one ls-files, one hash-object, one update-index --add -z --stdin and one diff --cached --numstat -z (no add -N)"
lbl() { grep -c "^$1 " "$SHIMLOG" | tr -d ' '; }
argsof() { grep "^$1: " "$SHIMLOG.args" | head -n 1; }
s3_calls() { # NAME DIR ARGS... -> one run under the counting shim; rows on the labelled calls of that run
  local name="$1" d="$2"; shift 2
  count_calls "$d" "$@"
  S3_LS="$(lbl ls-files)"; S3_HO="$(lbl hash-object)"; S3_UI="$(lbl update-index)"; S3_DB="$(lbl diff-batch)"; S3_AN="$(lbl add-N)"; S3_PF="$(lbl diff-noindex)"
}
mkrepo; mkfiles f 2; D_2="$R"
mkrepo; mkfiles f 200; D_200="$R"
for pair in "2:$D_2" "200:$D_200"; do
  n="${pair%%:*}"; d="${pair#*:}"
  : > "$SHIMLOG.args"
  s3_calls x "$d" size $WIDE
  assert_contains "S3 AC10 control: the run with $n untracked files counted all of them" "$SIZEOUT" "files: $n/1000 lines: $n/100000"
  chk "S3 AC10 $n files: exactly one update-index call" "1" "$S3_UI"
  chk "S3 AC10 $n files: exactly one diff --cached --numstat -z call (the batch diff)" "1" "$S3_DB"
  chk "S3 AC10 $n files: exactly one hash-object call (the empty tree id)" "1" "$S3_HO"
  chk "S3 AC10 $n files: exactly one ls-files call" "1" "$S3_LS"
  chk "S3 AC10 $n files: no add -N call" "0" "$S3_AN"
  chk "S3 AC10 $n files: no per-file diff --no-index call" "0" "$S3_PF"
  chk "S3 AC10 $n files: the update-index call runs with the temporary index and the temporary object dir" "update-index idx=1 obj=1" "$(grep '^update-index ' "$SHIMLOG" | head -n 1)"
  chk "S3 AC10 $n files: the batch diff runs with the temporary index and the temporary object dir" "diff-batch idx=1 obj=1" "$(grep '^diff-batch ' "$SHIMLOG" | head -n 1)"
  UA="$(argsof update-index)"
  for fl in "--add" "-z" "--stdin" "core.splitIndex=false"; do
    case " $UA " in *" $fl "* | *"$fl "*) t_ok "S3 AC10 $n files: update-index is called with $fl" ;; *) t_bad "S3 AC10 $n files: update-index is called with $fl" "args: [$UA]" ;; esac
  done
  DA="$(argsof diff-batch)"
  for fl in "--cached" "--numstat" "-z"; do
    case " $DA " in *" $fl "*) t_ok "S3 AC10 $n files: the batch diff is called with $fl" ;; *) t_bad "S3 AC10 $n files: the batch diff is called with $fl" "args: [$DA]" ;; esac
  done
  case "$(argsof hash-object)" in *"-t tree"*) t_ok "S3 AC10 $n files: hash-object asks for the empty tree (-t tree)" ;; *) t_bad "S3 AC10 $n files: hash-object asks for the empty tree (-t tree)" "args: [$(argsof hash-object)]" ;; esac
done
# --baseline: the batch is still one update-index and one diff-batch with 4 vs 202 files
mkrepo; mkfiles f 2; mkfiles g 2; D_2="$R"
mkrepo; mkfiles f 2; mkfiles g 200; D_200="$R"
for pair in "4:$D_2" "202:$D_200"; do
  n="${pair%%:*}"; d="${pair#*:}"
  s3_calls x "$d" size $WIDE --baseline "$MF0"
  chk "S3 AC10 --baseline, $n files: one update-index and one diff-batch, no add -N" "1 1 0" "$S3_UI $S3_DB $S3_AN"
done
# every kind of the corpus together: still one batch call pair, no per-file command for the batchable kinds
s3_calls x "$CORP" size $WIDE
chk "S3 AC10 corpus (all kinds in one repo): one update-index, one diff-batch, no add -N" "1 1 0" "$S3_UI $S3_DB $S3_AN"
chk "S3 AC10 corpus: the real git calls are 2 + the per-file ones of the routed kinds only (the batch never doubles): update-index runs with idx=1 obj=1" "update-index idx=1 obj=1" "$(grep '^update-index ' "$SHIMLOG" | head -n 1)"

# ---------------------------------------------------------------- S3 AC9/AC11/AC13 more corpus: core.splitIndex, sha256, core.safecrlf=true
echo "S3 AC9/AC11 the batch equals v0.24.27 on a split-index repo, a sha256 repo and under core.safecrlf=true (whole-batch fallback)"
mkrepo; git config core.splitIndex true; git update-index --split-index; mkkind text; mkkind binary; mkkind empty; mkkind attr-eol; mkkind exec; mkkind name-space; mkkind indir
cmp_gate "S3 AC11 core.splitIndex=true repo: stdout, exit code and stderr as v0.24.27" "$R" size $WIDE
cmp_gate "S3 AC11 core.splitIndex=true repo, --baseline of a clean repo: as v0.24.27" "$R" size $WIDE --baseline "$MF0"
gsnap() { # DIR -> listing of the git dir and the common dir, the sha256 of the real index, the index.lock state
  local d="$1" gd cd_
  gd="$(cd "$d" && git rev-parse --path-format=absolute --git-dir)"; cd_="$(cd "$d" && git rev-parse --path-format=absolute --git-common-dir)"
  { find "$gd" -print; if [ "$cd_" != "$gd" ]; then find "$cd_" -print; fi; } | LC_ALL=C sort
  printf 'index %s\n' "$(hsum "$gd/index")"
  if [ -e "$gd/index.lock" ]; then printf 'lock %s\n' "$(hsum "$gd/index.lock")"; else printf 'no lock\n'; fi
}
objlist() { local cd_; cd_="$(cd "$1" && git rev-parse --path-format=absolute --git-common-dir)"; find "$cd_/objects" -type f | LC_ALL=C sort; }
S3_SHA="$(mk_tmp)"
if git init -q --object-format=sha256 "$S3_SHA" 2>/dev/null; then
  ( cd "$S3_SHA" && git config user.email t@example.invalid && git config user.name t && mkdir -p src tests && printf 'a\n' > src/app.js &&
    printf 'b\n' > tests/app.test.js && git add -A && git commit -q -m init ) || t_bad "S3 AC11 sha256 fixture" "could not commit"
  cd "$S3_SHA" || exit 3; R="$S3_SHA"
  mkkind text; mkkind binary; mkkind empty; mkkind attr-eol; mkkind name-space; mkkind routed-tab 2>/dev/null || true
  cmp_q "S3 AC11 sha256 repo: v0.24.27 + 2 lines per git-quoted name (the empty tree id is the sha256 one)" 0 2 "$S3_SHA" size $WIDE
  count_calls "$S3_SHA" size $WIDE
  chk "S3 AC11 sha256 repo: the batch was used (one update-index, one diff-batch, no add -N, no per-file call for a plain file)" "1 1 0" "$(lbl update-index) $(lbl diff-batch) $(lbl add-N)"
  s0="$(gsnap "$S3_SHA")"; o0="$(objlist "$S3_SHA")"
  oneside n "$NEWG" "$S3_SHA" size $WIDE
  chk "S3 AC12 sha256 repo: real index sha256, git dir listing and index.lock unchanged" "$s0" "$(gsnap "$S3_SHA")"
  chk "S3 AC12 sha256 repo: no new loose object in the real object store" "$o0" "$(objlist "$S3_SHA")"
else t_skip 6 "S3 AC11/AC12 sha256 repo (this git has no --object-format=sha256)"; fi
# core.safecrlf=true: update-index --add refuses an LF file under autocrlf (rc 128); the whole list falls back to the per-file command (D18)
GENV=(X_PB=1); mkrepo; mkkind safecrlf
cmp_gate "S3 AC11 core.autocrlf=true + core.safecrlf=true, LF / mixed / CRLF files: stdout, exit code and stderr as v0.24.27 (files: 3, lines: 6)" "$R" size $WIDE
GENV=(X_PB=1 GIT_CONFIG_VALUE_0=true PB_SHIM_MODE=count PB_SHIM_LOG="$SHIMLOG" PB_SHIM_FIRED="$SHIMFIRED"); GPATH="$SHIM:$PATH"; : > "$SHIMLOG"
oneside n "$NEWG" "$R" size $WIDE
unset GPATH; GENV=(X_PB=1)
chk "S3 AC11 core.safecrlf=true: the answer is right through the fallback (3 files, 6 lines), exit 0" "files: 3/1000 lines: 6/100000 (base=HEAD)"$'\n'"rc=0" "$(cat "$DT/n.out")"$'\n'"rc=$(cat "$DT/n.rc")"
chk "S3 AC11 core.safecrlf=true: the batch index step was tried (one update-index call)" "1" "$(lbl update-index)"
chk "S3 AC11 core.safecrlf=true: the whole list went per-file (a diff --no-index for each of the 3 files)" "3" "$(lbl diff-noindex)"

# ---------------------------------------------------------------- AC3 nothing outside the temp dir is written
echo "AC3 the real index, the git dir, index.lock and the object store are untouched"
settle() { # make the index quiet: old mtimes (no racy entry), refreshed, written
  find . -name .git -prune -o -type f -exec touch -t 202001010000 {} + 2>/dev/null
  git update-index -q --refresh; git status --porcelain >/dev/null 2>&1; git status --porcelain >/dev/null 2>&1
}
ac3_files() { # unique contents, so a stray write would be a new object
  printf 'u-%s one\nu two\n' "$1" > u1.js; printf 'B\000\003%s\n' "$1" > u2.bin; : > u3.js; printf 'changed %s\n' "$1" >> src/app.js
  mkdir -p fresh; printf 'f-%s\n' "$1" > fresh/in.js
  mkkind routed-tab 2>/dev/null || true
  if [ "$SYMLINKS" = 1 ]; then ln -s u1.js u4.js; fi
}
ac3_run() { # NAME DIR [lock]
  local name="$1" d="$2" lock="${3:-}" gd s0 s1 o0 o1 lk
  gd="$(cd "$d" && git rev-parse --path-format=absolute --git-dir)"
  lk="$(mk_tmp)"; GENV=(X_PB=1 TMPDIR="$lk")
  if [ -n "$lock" ]; then printf 'held\n' > "$gd/index.lock"; fi
  s0="$(gsnap "$d")"; o0="$(objlist "$d")"
  # ac3_files holds a git-quoted name (routed-tab, 2 lines): AC1 counts its lines, v0.24.27 counted 0 (quoted_count is 0 on NTFS)
  cmp_q "AC3 $name: plain size equals v0.24.27 (+2 lines per git-quoted name)" 0 2 "$d" size $WIDE
  cmp_q "AC3 $name: size --baseline equals v0.24.27 (+2 lines per git-quoted name)" 0 2 "$d" size $WIDE --baseline "$MF0"
  s1="$(gsnap "$d")"; o1="$(objlist "$d")"
  chk "AC3 $name: real index sha256, git dir and common dir listing, index.lock unchanged" "$s0" "$s1"
  chk "AC3 $name: no new loose object in the real object store" "$o0" "$o1"
  chk "AC3 $name: no temporary directory left in TMPDIR" "" "$(ls -A "$lk")"
  if [ -n "$lock" ]; then rm -f "$gd/index.lock"; fi
  GENV=(X_PB=1)
}
mkrepo; ac3_files n; settle; ac3_run "normal repo" "$R"
mkrepo; ac3_files l; settle; ac3_run "normal repo with a pre-held index.lock" "$R" lock
mkrepo; git config core.splitIndex true; git update-index --split-index; ac3_files s; settle
if ls "$(git rev-parse --git-dir)" | grep -q '^sharedindex\.'; then ac3_run "core.splitIndex=true repo" "$R"
else t_bad "AC3 core.splitIndex=true fixture" "no sharedindex file: the repo is not split"; fi
mkrepo; MAINR="$R"; WT="$(mk_tmp)/wt"
if git worktree add -q "$WT" -b wtb 2>/dev/null; then
  cd "$WT" || exit 3; ac3_files w; settle; ac3_run "linked worktree" "$WT"
else t_bad "AC3 linked worktree fixture" "git worktree add failed"; fi

# ---------------------------------------------------------------- AC4 any doubt about the batch: the whole list goes through the per-file loop
echo "AC4 a failing or inconsistent batch gives the v0.24.27 result (counting shim injects the fault)"
mk4() { mkrepo; printf 'a\nb\n' > f1.js; printf 'a\nb\nc\n' > f2.js; printf 'a\nb\nc\nd\n' > f3.js; printf '1\n2\n3\n4\n5\n' > race.js; printf 'B\000\003\n' > f4.bin; }
shimrun() { # NAME MODE DIR ARGS... -> cmp_gate under the shim in MODE; then the batch must have been tried
  local name="$1" mode="$2" d="$3"; shift 3
  GENV=(X_PB=1 PB_SHIM_MODE="$mode" PB_SHIM_LOG="$SHIMLOG" PB_SHIM_FIRED="$SHIMFIRED" PB_RACE_PATH=race.js); GPATH="$SHIM:$PATH"
  cmp_gate "$name" "$d" "$@"
  unset GPATH; GENV=(X_PB=1)
}
perfile_calls() { grep -c '^diff-noindex' "$SHIMLOG" | tr -d ' '; }
mk4; D4="$R"
shimrun "AC4 update-index exits non-zero: result equals v0.24.27" upd-fail "$D4" size $WIDE
chk "AC4 update-index exits non-zero: the batch was tried (shim refused an update-index)" "1" "$([ -s "$SHIMFIRED" ] && echo 1 || echo 0)"
shimrun "AC4 update-index exits non-zero, --baseline: result equals v0.24.27" upd-fail "$D4" size $WIDE --baseline "$MF0"
shimrun "S3 AC13 a partial update-index failure (all but one record indexed, then rc 128): result equals v0.24.27" upd-partial "$D4" size $WIDE
chk "S3 AC13 partial update-index failure: the batch was tried (shim indexed most of the list, then failed)" "1" "$([ -s "$SHIMFIRED" ] && echo 1 || echo 0)"
chk "S3 AC13 partial update-index failure: the whole list went per-file (each of the 5 files had a diff --no-index)" "1" "$([ "$(perfile_calls)" -ge 5 ] && echo 1 || echo 0)"
chk "S3 AC13 partial update-index failure: the batch diff is not run on a half-built index (no diff-batch call)" "0" "$(lbl diff-batch)"
shimrun "S3 AC13 partial update-index failure, --baseline: result equals v0.24.27" upd-partial "$D4" size $WIDE --baseline "$MF0"
shimrun "AC4 the batch diff exits non-zero: result equals v0.24.27" diff-fail "$D4" size $WIDE
chk "AC4 the batch diff exits non-zero: the batch was tried (shim refused the numstat -z diff)" "1" "$([ -s "$SHIMFIRED" ] && echo 1 || echo 0)"
shimrun "AC4 the batch diff exits non-zero, --baseline: result equals v0.24.27" diff-fail "$D4" size $WIDE --baseline "$MF0"
shimrun "AC4 update-index does its work but exits 1: result equals v0.24.27" upd-rc "$D4" size $WIDE
chk "AC4 update-index exits 1: the batch was tried (shim let update-index run, then exited 1)" "1" "$([ -s "$SHIMFIRED" ] && echo 1 || echo 0)"
chk "AC4 update-index exits 1: its output is not used: each of the 5 files went through the per-file loop" "1" "$([ "$(perfile_calls)" -ge 5 ] && echo 1 || echo 0)"
shimrun "AC4 the batch diff prints the right numbers but exits 1: result equals v0.24.27" diff-rc "$D4" size $WIDE
chk "AC4 diff exits 1: the batch was tried (shim let the diff run, then exited 1)" "1" "$([ -s "$SHIMFIRED" ] && echo 1 || echo 0)"
chk "AC4 diff exits 1: its output is not used: each of the 5 files went through the per-file loop" "1" "$([ "$(perfile_calls)" -ge 5 ] && echo 1 || echo 0)"
shimrun "AC4 the batch diff exits 0 but omits a path: result equals v0.24.27 (never fewer)" diff-drop "$D4" size $WIDE
chk "AC4 omitted path: the batch was tried (shim changed the numstat -z output)" "1" "$([ -s "$SHIMFIRED" ] && echo 1 || echo 0)"
shimrun "AC4 the batch diff exits 0 but lists a path twice: result equals v0.24.27" diff-dup "$D4" size $WIDE
chk "AC4 duplicated path: the batch was tried (shim changed the numstat -z output)" "1" "$([ -s "$SHIMFIRED" ] && echo 1 || echo 0)"
# the race mutates the work tree: the v0.24.27 side and the current side each get their own copy of the same state
mk4; D4A="$R"; mk4; D4B="$R"
D2="$D4B"; shimrun "AC4 race on separate copies of the repo: result equals v0.24.27" race "$D4A" size $WIDE; unset D2
chk "AC4 race on separate copies: the batch was tried (an update-index was made)" "1" "$(grep -q '^update-index' "$SHIMLOG" && echo 1 || echo 0)"
chk "AC4 race on separate copies: the shim really turned race.js into a directory in both copies" "dd" "$([ -d "$D4A/race.js" ] && printf d)$([ -d "$D4B/race.js" ] && printf d)"
chk "AC4 race: the path set of the batch no longer matches, so the whole list went through the per-file loop" "1" "$([ "$(perfile_calls)" -ge 5 ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- S3 AC15 TERM during the batch leaves no temporary file
echo "S3 AC15 a TERM sent to the gate's PID while it is inside the batch: its process group finishes and no pbgate.* dir (or BL_TMPW file) is left"
# ac15_run NAME DIR ARGS... -> the gate runs in its own process group (setsid), the shim holds the update-index call until the TERM is sent,
# then the row polls (up to 30 s, the first check at once) until nobody is left in that group; TMPDIR must then be empty
ac15_run() {
  local name="$1" d="$2" lk ad pid pgid i=0 left=1; shift 2
  if ! command -v setsid >/dev/null 2>&1; then t_skip 3 "$name (no setsid here)"; return; fi
  lk="$(mk_tmp)"; ad="$(mk_tmp)"; : > "$SHIMLOG"
  ( cd "$d" && exec setsid env X_PB=1 PLAYBOOK_HOME="$PLAYBOOK_HOME" LC_ALL=C TMPDIR="$lk" PATH="$SHIM:$PATH" PB_SHIM_MODE=hang PB_SHIM_LOG="$SHIMLOG" \
      PB_SHIM_FIRED="$SHIMFIRED" PB_HANG_REACHED="$ad/reached" PB_HANG_RELEASE="$ad/release" bash "$NEWG" "$@" ) >"$DT/a15.out" 2>"$DT/a15.err" </dev/null &
  pid=$!
  while [ ! -e "$ad/reached" ] && kill -0 "$pid" 2>/dev/null && [ "$i" -lt 300 ]; do sleep 0.1 2>/dev/null || sleep 1; i=$((i + 1)); done
  if [ ! -e "$ad/reached" ]; then
    : > "$ad/release"; wait "$pid" 2>/dev/null
    t_bad "$name: the gate reached the update-index call (the shim's hang marker)" "the gate ended (or 30 s passed) without an update-index call; stderr [$(head -c 160 "$DT/a15.err" | tr '\n' '|')]"
    return
  fi
  pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')"
  if [ "$pgid" != "$pid" ]; then
    : > "$ad/release"; wait "$pid" 2>/dev/null
    t_skip 3 "$name (the gate is not the leader of its own process group here: pgid [$pgid] pid [$pid])"; return
  fi
  chk "$name: control: a temporary entry exists in TMPDIR while the gate is inside the batch (so the empty-TMPDIR row below can fail)" "1" "$([ -n "$(ls -A "$lk")" ] && echo 1 || echo 0)"
  chk "$name: S4 AC20 every temporary entry is named pbgate.XXXXXX (the mktemp -d has the template, as BL_TMPW)" "" "$(ls -A "$lk" | grep -v '^pbgate\.[A-Za-z0-9]\{6\}$' || true)"
  kill -TERM "$pid" 2>/dev/null; : > "$ad/release"
  i=0
  while [ "$i" -lt 300 ]; do
    if ! kill -0 -- "-$pgid" 2>/dev/null; then left=0; break; fi
    sleep 0.1 2>/dev/null || sleep 1; i=$((i + 1))
  done
  if [ "$left" = 1 ]; then kill -KILL -- "-$pgid" 2>/dev/null; fi
  wait "$pid" 2>/dev/null
  chk "$name: the process group finished within 30 s of the TERM" "0" "$left"
  chk "$name: nothing is left in TMPDIR (no pbgate.* dir, no BL_TMPW file)" "" "$(ls -A "$lk")"
}
mkrepo; mkfiles f 3; ac15_run "S3 AC15 TERM to the gate during the batch (plain size)" "$R" size $WIDE
mkrepo; mkfiles f 3; ac15_run "S3 AC15 TERM to the gate during the batch (size --baseline)" "$R" size $WIDE --baseline "$MF0"

# ---------------------------------------------------------------- S4 route-only mutants and nits (AC18, AC19, AC20)
echo "S4 AC18 the batch sorts under LC_ALL=C: a caller in en_US.UTF-8 still gets the batch and the same totals"
# s4_run DIR LOCALE ARGS... -> one run under the counting shim with LC_ALL=LOCALE; stdout in S4_OUT, call counts in S4_UI / S4_PF
s4_run() {
  local d="$1" loc="$2"; shift 2
  : > "$SHIMLOG"; : > "$SHIMFIRED"
  S4_OUT="$( cd "$d" && env X_PB=1 PLAYBOOK_HOME="$PLAYBOOK_HOME" LC_ALL="$loc" PB_SHIM_MODE=count PB_SHIM_LOG="$SHIMLOG" PB_SHIM_FIRED="$SHIMFIRED" PATH="$SHIM:$PATH" bash "$NEWG" "$@" 2>/dev/null </dev/null )"
  S4_UI="$(lbl update-index)"; S4_PF="$(lbl diff-noindex)"
}
S4_EN="$(locale -a 2>/dev/null | grep -i '^en_US\.utf-\{0,1\}8$' | head -n 1 || true)"
S4_ORD_C="$(printf 'a.js\nB.js\n_c.js\nZ.js\n' | LC_ALL=C sort | tr '\n' ' ')"
S4_ORD_EN="$(printf 'a.js\nB.js\n_c.js\nZ.js\n' | LC_ALL="${S4_EN:-C}" sort 2>/dev/null | tr '\n' ' ')"
if [ -z "$S4_EN" ] || [ "$S4_ORD_C" = "$S4_ORD_EN" ]; then
  t_skip 4 "S4 AC18 (no en_US.UTF-8 locale here, or it sorts a.js B.js _c.js Z.js like C)"
else
  chk "S4 AC18 control: C and $S4_EN order the four names differently" "1" "$([ "$S4_ORD_C" != "$S4_ORD_EN" ] && echo 1 || echo 0)"
  mkrepo; for n in a B _c Z; do printf 'l1\nl2\n' > "$n.js"; done
  s4_run "$R" "$S4_EN" size $WIDE
  chk "S4 AC18 en_US run: totals equal the C-locale run (4 files, 8 lines)" "files: 4/1000 lines: 8/100000 (base=HEAD)" "$S4_OUT"
  chk "S4 AC18 en_US run: the batch is used (one update-index call)" "1" "$S4_UI"
  chk "S4 AC18 en_US run: no per-file diff --no-index call (the two sorted lists matched)" "0" "$S4_PF"
fi

echo "S4 AC19 untracked paths that are not regular files go per file, never into the batch input"
if [ "$SYMLINKS" != 1 ]; then t_skip 6 "S4 AC19 (no symlinks on this file system)"
else
  mkrepo; printf 'x\n' > f1.js; ln -s nowhere.js dang.js
  s4_run "$R" C size $WIDE
  chk "S4 AC19 dangling symlink + 1 file: counted, 2 files 2 lines" "files: 2/1000 lines: 2/100000 (base=HEAD)" "$S4_OUT"
  chk "S4 AC19 dangling symlink: exactly one per-file diff --no-index call (it is not in the batch)" "1" "$S4_PF"
  chk "S4 AC19 dangling symlink: the regular file still rides the batch (one update-index call)" "1" "$S4_UI"
  mkrepo; printf 'x\n' > f1.js; ln -s src sd
  s4_run "$R" C size $WIDE
  chk "S4 AC19 symlink to a directory + 1 file: 2 files, 1 line (a directory link has no numstat line, as v0.24.27)" "files: 2/1000 lines: 1/100000 (base=HEAD)" "$S4_OUT"
  chk "S4 AC19 symlink to a directory: exactly one per-file diff --no-index call (it is not in the batch)" "1" "$S4_PF"
  chk "S4 AC19 symlink to a directory: the regular file still rides the batch (one update-index call)" "1" "$S4_UI"
fi

echo "S4 AC20 the batch directory has the pbgate template (row in S3 AC15) and the redundant [ ! -d ] is gone"
chk "S4 AC20 role-gate.sh holds no [ -f \"\$u\" ] && [ ! -d \"\$u\" ] (a regular file is never a directory)" "0" "$(grep -c '\[ -f "\$u" \] && \[ ! -d "\$u" \]' "$NEWG" | tr -d ' ' || true)"
chk "S4 AC20 every mktemp -d in role-gate.sh carries the pbgate.XXXXXX template" "0" "$(grep 'mktemp -d' "$NEWG" | grep -vc 'pbgate\.XXXXXX' | tr -d ' ' || true)"

# ---------------------------------------------------------------- AC5 the existing size rows are not edited here
echo "AC5 the existing size rows live in test-role-gate.sh, -batch.sh, -baseline.sh and -b.sh (not copied here; they must stay green and unchanged)"
for f in test-role-gate.sh test-role-gate-batch.sh test-role-gate-baseline.sh test-role-gate-b.sh; do
  assert_file "AC5 $f is still a suite next to this one" "$PB_ROOT/tests/$f"
done
t_summary
