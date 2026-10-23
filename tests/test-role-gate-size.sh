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
# PB_SHIM_MODE: count (default) | add-fail | diff-fail | add-rc | diff-rc | diff-drop | diff-dup | race. Every call appends "<label> idx=<0|1>" to PB_SHIM_LOG.
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
printf '%s idx=%s\n' "$label" "$idx" >> "$PB_SHIM_LOG"
case "${PB_SHIM_MODE:-count}:$label" in
  add-fail:add-N) printf 'shim: add -N refused\n' >&2; echo 1 >> "$PB_SHIM_FIRED"; exit 1 ;;
  diff-fail:diff-batch) printf 'shim: diff refused\n' >&2; echo 1 >> "$PB_SHIM_FIRED"; exit 1 ;;
  diff-drop:diff-batch) echo 1 >> "$PB_SHIM_FIRED"; "$REAL_GIT" "$@" | tr '\0' '\n' | sed 1d | tr '\n' '\0'; exit 0 ;;
  diff-dup:diff-batch) echo 1 >> "$PB_SHIM_FIRED"; "$REAL_GIT" "$@" | tr '\0' '\n' | sed 1p | tr '\n' '\0'; exit 0 ;;
  add-rc:add-N | diff-rc:diff-batch) echo 1 >> "$PB_SHIM_FIRED"; "$REAL_GIT" "$@"; exit 1 ;;
  race:add-N | race:diff-noindex)   # a listed file turns into a directory right before the first command that reads it
    if [ -f "$PB_RACE_PATH" ]; then rm -f "$PB_RACE_PATH"; mkdir -p "$PB_RACE_PATH"; printf 'a\nb\nc\n' > "$PB_RACE_PATH/inner"; fi ;;
esac
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
 name-squote name-star name-glob indir"
K_ROUTED="routed-tab routed-dquote routed-backslash routed-newline routed-symlink-dir routed-nested-repo"
mkrepo() { R="$(mk_tmp)"; mk_repo "$R"; cd "$R" || exit 3; }

MF0DIR="$(mk_tmp)"; mk_repo "$MF0DIR"; MF0="$(mk_mf "$MF0DIR")"   # the manifest of a clean repo: nothing is excluded

# ---------------------------------------------------------------- AC1 every kind, one repo each
echo "AC1 each kind of untracked file is counted as v0.24.27 counts it (plain size, wide limits)"
for k in $K_SAME $K_ROUTED; do
  GENV=(X_PB=1)
  mkrepo
  if ! mkkind "$k"; then t_skip 1 "AC1 kind $k (this file system cannot hold it)"; continue; fi
  case "$k" in routed-*) cls="routed to the per-file command" ;; *) cls="batch" ;; esac
  cmp_gate "AC1 kind $k ($cls): stdout, exit code and stderr as v0.24.27" "$R" size $WIDE
done
GENV=(X_PB=1)

# ---------------------------------------------------------------- AC1 corpus: all kinds together, plain, default limits, --baseline
echo "AC1 all kinds in one repo: plain, default limits and --baseline"
mkrepo; CORP="$R"
for k in $K_SAME routed-tab routed-dquote routed-backslash routed-symlink-dir routed-nested-repo; do
  case "$k" in autocrlf | attr-deleted) continue ;; esac
  mkkind "$k" 2>/dev/null || true
done
GENV=(X_PB=1)
cmp_gate "AC1 corpus: plain size, wide limits" "$CORP" size $WIDE
cmp_gate "AC1 corpus: plain size, default limits (over the limit: exit 1)" "$CORP" size
cmp_gate "AC1 corpus: size --baseline of a clean repo (every untracked path counted)" "$CORP" size $WIDE --baseline "$MF0"
CMF="$(mk_mf "$CORP")"
if [ -s "$CMF" ]; then
  printf 'a\nb\nc\nd\n' > zz-new.js; printf 'more\n' >> t.js
  cmp_gate "AC1 corpus: size --baseline taken with every kind present (those paths left out, new and edited ones counted)" "$CORP" size $WIDE --baseline "$CMF"
  cmp_gate "AC1 corpus: size --baseline with default limits" "$CORP" size --baseline "$CMF"
else t_bad "AC1 corpus: the baseline manifest of the corpus could not be written" "snapshot --out gave no file"; fi

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
chk "AC2/N2 characterization: no untracked file, no add -N and no temporary index" "0" "$(grep -c '^add-N\|idx=1' "$SHIMLOG" | tr -d ' ')"
# routed_listed: 0 when git lists the file just made as a quoted (routed) name; NTFS maps a tab to a private-use character, git lists it unquoted and batches it
routed_listed() { git -c core.quotepath=off ls-files --others | head -n 1 | grep -q '^"'; }
if mkrepo && mkkind routed-tab && routed_listed; then
  count_calls "$R" size $WIDE
  chk "AC2/N2 characterization: only a per-file-routed untracked name: no add -N" "0" "$(grep -c '^add-N' "$SHIMLOG" | tr -d ' ')"
else t_skip 1 "AC2/N2 routed-only list (this file system cannot hold a tab in a name, or git does not list it as a quoted name)"; fi

# ---------------------------------------------------------------- AC3 nothing outside the temp dir is written
echo "AC3 the real index, the git dir, index.lock and the object store are untouched"
gsnap() { # DIR -> listing of the git dir and the common dir, the sha256 of the real index, the index.lock state
  local d="$1" gd cd_
  gd="$(cd "$d" && git rev-parse --path-format=absolute --git-dir)"; cd_="$(cd "$d" && git rev-parse --path-format=absolute --git-common-dir)"
  { find "$gd" -print; if [ "$cd_" != "$gd" ]; then find "$cd_" -print; fi; } | LC_ALL=C sort
  printf 'index %s\n' "$(hsum "$gd/index")"
  if [ -e "$gd/index.lock" ]; then printf 'lock %s\n' "$(hsum "$gd/index.lock")"; else printf 'no lock\n'; fi
}
objlist() { local cd_; cd_="$(cd "$1" && git rev-parse --path-format=absolute --git-common-dir)"; find "$cd_/objects" -type f | LC_ALL=C sort; }
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
  cmp_gate "AC3 $name: plain size equals v0.24.27" "$d" size $WIDE
  cmp_gate "AC3 $name: size --baseline equals v0.24.27" "$d" size $WIDE --baseline "$MF0"
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
mk4; D4="$R"
shimrun "AC4 add -N exits non-zero: result equals v0.24.27" add-fail "$D4" size $WIDE
chk "AC4 add -N exits non-zero: the batch was tried (shim refused an add -N)" "1" "$([ -s "$SHIMFIRED" ] && echo 1 || echo 0)"
shimrun "AC4 add -N exits non-zero, --baseline: result equals v0.24.27" add-fail "$D4" size $WIDE --baseline "$MF0"
shimrun "AC4 the batch diff exits non-zero: result equals v0.24.27" diff-fail "$D4" size $WIDE
chk "AC4 the batch diff exits non-zero: the batch was tried (shim refused the numstat -z diff)" "1" "$([ -s "$SHIMFIRED" ] && echo 1 || echo 0)"
shimrun "AC4 the batch diff exits non-zero, --baseline: result equals v0.24.27" diff-fail "$D4" size $WIDE --baseline "$MF0"
perfile_calls() { grep -c '^diff-noindex' "$SHIMLOG" | tr -d ' '; }
shimrun "AC4 add -N does its work but exits 1: result equals v0.24.27" add-rc "$D4" size $WIDE
chk "AC4 add -N exits 1: the batch was tried (shim let add -N run, then exited 1)" "1" "$([ -s "$SHIMFIRED" ] && echo 1 || echo 0)"
chk "AC4 add -N exits 1: its output is not used: each of the 5 files went through the per-file loop" "1" "$([ "$(perfile_calls)" -ge 5 ] && echo 1 || echo 0)"
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
chk "AC4 race on separate copies: the batch was tried (an add -N was made)" "1" "$(grep -q '^add-N' "$SHIMLOG" && echo 1 || echo 0)"
chk "AC4 race on separate copies: the shim really turned race.js into a directory in both copies" "dd" "$([ -d "$D4A/race.js" ] && printf d)$([ -d "$D4B/race.js" ] && printf d)"
chk "AC4 race: the path set of the batch no longer matches, so the whole list went through the per-file loop" "1" "$([ "$(perfile_calls)" -ge 5 ] && echo 1 || echo 0)"

# ---------------------------------------------------------------- AC5 the existing size rows are not edited here
echo "AC5 the existing size rows live in test-role-gate.sh, -batch.sh, -baseline.sh and -b.sh (not copied here; they must stay green and unchanged)"
for f in test-role-gate.sh test-role-gate-batch.sh test-role-gate-baseline.sh test-role-gate-b.sh; do
  assert_file "AC5 $f is still a suite next to this one" "$PB_ROOT/tests/$f"
done
t_summary
