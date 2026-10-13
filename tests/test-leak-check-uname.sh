#!/usr/bin/env bash
# Tests for scripts/leak-check.sh, v0.24.6 AC1: one leak-check process runs `uname` at most once.
# Today win_path runs `uname -s` in a command substitution on every call (twice per same_place), so a push or unpushed scan that
# compares destinations launches it many times; each launch is a process (slow on Git Bash). The count is measured with a PATH
# shim that wraps the real uname (the output is unchanged, only a counter file grows). Also here: the Windows branch (uname says
# MINGW64_NT-10.0, a fake cygpath converts paths) gives the same decisions and output as before the change.
# Shared setup: leak-check-fixture.sh. This repo is public: every secret below is built at run time from pieces.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/leak-check-fixture.sh"
conf_global "leak_literals=$EML"
unset PB_ALLOW_MODE_CHANGE

REALUNAME="$(command -v uname)"
# CNTBIN: a uname that counts its launches in $UNAME_COUNT_FILE and then answers like the real one
CNTBIN="$(mk_tmp)/cnt"; mkdir -p "$CNTBIN"
cat > "$CNTBIN/uname" <<SHIM
#!/bin/sh
printf 'x\n' >> "\$UNAME_COUNT_FILE"
exec "$REALUNAME" "\$@"
SHIM
chmod +x "$CNTBIN/uname"
# WINBIN: uname says MINGW64_NT-10.0 (and counts), cygpath logs its arguments to $CYG_LOG and converts like Git Bash would:
# /c/x -> C:/x, any other /x -> C:/msys64/x, C:/x stays
WINBIN="$(mk_tmp)/win"; mkdir -p "$WINBIN"
cat > "$WINBIN/uname" <<'SHIM'
#!/bin/sh
printf 'x\n' >> "$UNAME_COUNT_FILE"
echo MINGW64_NT-10.0
SHIM
cat > "$WINBIN/cygpath" <<'SHIM'
#!/bin/sh
printf '%s\n' "$*" >> "$CYG_LOG"
p="$3"
case "$p" in
  /c/*) printf 'C:/%s\n' "${p#/c/}" ;;
  /*) printf 'C:/msys64%s\n' "$p" ;;
  *) printf '%s\n' "$p" ;;
esac
SHIM
chmod +x "$WINBIN/uname" "$WINBIN/cygpath"
# LINBIN: uname says Linux (and counts), so a "non-Windows" control is non-Windows on every host (the real uname says MINGW on Git Bash)
LINBIN="$(mk_tmp)/lin"; mkdir -p "$LINBIN"
cat > "$LINBIN/uname" <<'SHIM'
#!/bin/sh
printf 'x
' >> "$UNAME_COUNT_FILE"
echo Linux
SHIM
chmod +x "$LINBIN/uname"

# lc_count BINDIR ARGS... -> runs `leak-check ARGS` in $R with BINDIR first on PATH. Sets STD, ERR, RC and UCOUNT (uname launches)
# and CYGLOG (the cygpath argument log, "" when it was never called).
lc_count() {
  local bin="$1" d cf ef; shift
  d="$(mk_tmp)"; cf="$d/count"; ef="$d/err"; CYG_LOG="$d/cyg"
  : > "$cf"; : > "$CYG_LOG"
  STD="$(cd "$R" && env PATH="$bin:$PATH" UNAME_COUNT_FILE="$cf" CYG_LOG="$CYG_LOG" bash "$LC" "$@" 2>"$ef")"; RC=$?
  ERR="$(cat "$ef" 2>/dev/null)"
  UCOUNT="$(wc -l < "$cf" | tr -d ' ')"
  CYGLOG="$(cat "$CYG_LOG" 2>/dev/null)"
}
# assert_le NAME N MAX -> pass when N <= MAX
assert_le() { if [ "$2" -le "$3" ] 2>/dev/null; then t_ok "$1"; else t_bad "$1" "expected at most $3 got [$2]"; fi; }

# a repo with a remote origin, a secret commit that only refs/remotes/origin/main holds, and one commit before it
# mkpushrepo -> sets R, SEC, U_A, U_B, U_P
mkpushrepo() {
  newrepo
  git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
  U_A="$(mk_tmp)/a.git"; U_B="$(mk_tmp)/b.git"; U_P="$(mk_tmp)/p.git"
  git -C "$R" remote add origin "$U_A"; git -C "$R" remote add up "$U_B"
  stage "$R" s.txt "k $GH"; G -C "$R" commit -q --no-verify -m 'secret'
  SEC="$(git -C "$R" rev-parse HEAD)"
  git -C "$R" update-ref refs/remotes/origin/main "$SEC"
}

echo "v0.24.6 AC1 a push or unpushed scan that compares destinations runs uname at most once"
mkpushrepo
lc_count "$CNTBIN" scan --unpushed "$SEC" --remote origin
assert_eq "AC1 fixture: scan --unpushed SHA --remote origin (origin holds the commit): exit 0, behaviour unchanged" "0" "$RC"
assert_le "AC1 scan --unpushed SHA --remote origin: uname launches at most 1" "$UCOUNT" 1
git -C "$R" config remote.origin.pushurl "$U_P"
lc_count "$CNTBIN" scan --unpushed "$SEC" --remote origin
assert_eq "AC1 fixture: origin with a different pushurl scans the full range: exit 1, behaviour unchanged" "1" "$RC"
assert_contains "AC1 ... the finding is named" "$STD" "s.txt:1: github-token"
assert_le "AC1 origin with a pushurl that differs (several destinations compared): uname launches at most 1" "$UCOUNT" 1
git -C "$R" config --unset remote.origin.pushurl
lc_count "$CNTBIN" scan --unpushed "$SEC" --remote "$U_A"
assert_eq "AC1 fixture: --remote with origin's exact url uses origin's refs: exit 0, behaviour unchanged" "0" "$RC"
assert_le "AC1 scan --unpushed SHA --remote URL (url_remotes compares every remote): uname launches at most 1" "$UCOUNT" 1
git -C "$R" config --add remote.origin.url "$U_B"
lc_count "$CNTBIN" scan --unpushed "$SEC" --remote "$U_B"
assert_eq "AC1 fixture: a second url value that names another place: full scan, exit 1, behaviour unchanged" "1" "$RC"
assert_le "AC1 a remote with two url values (the values are compared pairwise): uname launches at most 1" "$UCOUNT" 1

echo "v0.24.6 AC1 paths that never compare destinations run uname 0 times (today and after)"
mkpushrepo
stage "$R" st.txt "k $GH"
lc_count "$CNTBIN" scan --staged
assert_eq "AC1 fixture: scan --staged finds the staged secret: exit 1" "1" "$RC"
assert_eq "AC1 scan --staged: uname launches 0" "0" "$UCOUNT"
printf 'clean line\n' > "$R/clean.txt"
lc_count "$CNTBIN" scan "$R/clean.txt"
assert_eq "AC1 fixture: a files scan of a clean file: exit 0" "0" "$RC"
assert_eq "AC1 a files scan: uname launches 0" "0" "$UCOUNT"
lc_count "$CNTBIN" scan --range "$SEC"
assert_eq "AC1 fixture: scan --range without a remote finds the secret commit: exit 1" "1" "$RC"
assert_eq "AC1 a range scan without a remote: uname launches 0" "0" "$UCOUNT"
lc_count "$CNTBIN" install-hooks
assert_eq "AC1 fixture: install-hooks: exit 0" "0" "$RC"
assert_eq "AC1 install-hooks: uname launches 0" "0" "$UCOUNT"

echo "v0.24.6 AC1 control: the counter shim counts a real launch (so a 0 above is a real 0)"
CTL="$(mk_tmp)"; : > "$CTL/count"
env PATH="$CNTBIN:$PATH" UNAME_COUNT_FILE="$CTL/count" sh -c 'uname -s' >/dev/null 2>&1
assert_eq "AC1 control: one uname call through the shim is counted once" "1" "$(wc -l < "$CTL/count" | tr -d ' ')"

# ---- the Windows branch: the same decisions and output before and after the change (characterization, passes today) ----
# MINGW64_NT-10.0 uname plus the fake cygpath. Each case records the exit code, the stdout and the stderr of today's script; the
# temp directory names are replaced by @T so the expectations do not depend on the run.
echo "v0.24.6 AC1 equivalence on the Windows branch (uname MINGW64_NT-10.0, fake cygpath)"
norm() { printf '%s' "$1" | sed "s#$PB_TMPBASE#@T#g"; }
NOTE_PUSHELSE='leak-check: origin pushes to a place no configured remote owns; scanning the full range (push through a named remote to limit it) or set PB_LEAK_SCAN_BASE=<full commit id> to scan only that id..SHA'

mkpushrepo
lc_count "$WINBIN" scan --unpushed "$SEC" --remote origin
assert_eq "AC1 MINGW origin holds the commit, pushes home: exit 0" "0" "$RC"
assert_eq "AC1 MINGW origin pushes home: stdout is the clean line" "leak-check: clean" "$STD"
assert_eq "AC1 MINGW origin pushes home: stderr is empty" "" "$ERR"
assert_contains "AC1 MINGW the fake cygpath was used for the comparison (cygpath -m -- ...)" "$CYGLOG" "-m -- "
git -C "$R" config remote.origin.pushurl "$U_P"
lc_count "$CNTBIN" scan --unpushed "$SEC" --remote origin
LIN_PUSHURL_OUT="$STD"; LIN_PUSHURL_RC="$RC"
lc_count "$WINBIN" scan --unpushed "$SEC" --remote origin
assert_eq "AC1 MINGW origin with a pushurl elsewhere: full scan, exit 1" "1" "$RC"
assert_contains "AC1 MINGW ... the finding is named" "$STD" "s.txt:1: github-token"
assert_eq "AC1 MINGW ... stderr is the 'no configured remote owns' note" "$NOTE_PUSHELSE" "$(norm "$ERR")"
assert_eq "AC1 MINGW ... stdout equals the stdout of the non-Windows run" "$LIN_PUSHURL_OUT" "$STD"
assert_eq "AC1 MINGW ... exit code equals the non-Windows run" "$LIN_PUSHURL_RC" "$RC"
git -C "$R" config --unset remote.origin.pushurl
lc_count "$WINBIN" scan --unpushed "$SEC" --remote "$U_A"
assert_eq "AC1 MINGW --remote origin's exact url: origin's refs, exit 0" "0" "$RC"
assert_eq "AC1 MINGW --remote origin's exact url: stdout is the clean line" "leak-check: clean" "$STD"
assert_eq "AC1 MINGW --remote origin's exact url: stderr is empty" "" "$ERR"
lc_count "$WINBIN" scan --unpushed "$SEC" --remote "$U_B"
assert_eq "AC1 MINGW --remote the url of up (which holds nothing): scanned, exit 1" "1" "$RC"
assert_contains "AC1 MINGW ... the finding is named" "$STD" "s.txt:1: github-token"
assert_not_contains "AC1 MINGW ... no 'not a configured remote' note (the url belongs to up)" "$ERR" "is not a configured remote"
git -C "$R" config --add remote.origin.url "$U_B"
lc_count "$WINBIN" scan --unpushed "$SEC" --remote "$U_A"
assert_eq "AC1 MINGW origin with a second url naming another place: full scan, exit 1" "1" "$RC"
assert_contains "AC1 MINGW ... the finding is named" "$STD" "s.txt:1: github-token"
git -C "$R" config --unset-all remote.origin.url
git -C "$R" config remote.origin.url "$U_A"

# the decision that only the Windows branch makes: C:/x (the configured url) and /c/x (NAME) are one place there, two places elsewhere
newrepo
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
git -C "$R" remote add origin 'C:/pbfake/a.git'
stage "$R" w.txt "k $GH"; G -C "$R" commit -q --no-verify -m 'secret'
WSEC="$(git -C "$R" rev-parse HEAD)"
git -C "$R" update-ref refs/remotes/origin/main "$WSEC"
lc_count "$WINBIN" scan --unpushed "$WSEC" --remote '/c/pbfake/a.git'
assert_eq "AC1 MINGW NAME /c/pbfake/a.git is origin's url C:/pbfake/a.git (same_place through cygpath): origin's refs, exit 0" "0" "$RC"
assert_eq "AC1 MINGW ... stdout is the clean line" "leak-check: clean" "$STD"
assert_eq "AC1 MINGW ... stderr is empty" "" "$ERR"
assert_contains "AC1 MINGW ... cygpath was asked about /c/pbfake/a.git" "$CYGLOG" "/c/pbfake/a.git"
# MSYS_NO_PATHCONV: Git Bash would otherwise rewrite /c/pbfake/a.git to C:/pbfake/a.git for native git, which makes the Linux control a Windows run
MSYS_NO_PATHCONV=1 lc_count "$LINBIN" scan --unpushed "$WSEC" --remote '/c/pbfake/a.git'
assert_eq "AC1 non-Windows uname: /c/pbfake/a.git is NOT origin's url (strings differ): full scan, exit 1" "1" "$RC"
assert_contains "AC1 non-Windows ... the note says it is not a configured remote" "$ERR" "/c/pbfake/a.git is not a configured remote"

t_summary
