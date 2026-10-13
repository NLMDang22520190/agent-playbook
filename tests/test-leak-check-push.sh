#!/usr/bin/env bash
# Tests for scripts/leak-check.sh, part 3 of 3 (split from test-leak-check.sh in v0.24.1): the v0.23.3 sections (pushes to a URL, the mode check
# failing closed, awk multibyte noise, pushInsteadOf and pushurl, remotes with several urls, pushes through the installed pre-push hook).
# Shared setup: leak-check-fixture.sh. This repo is public: every secret below is built at run time from pieces.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/leak-check-fixture.sh"
# the global conf and the environment as the earlier sections of the unsplit suite left them
conf_global "leak_literals=$EML"
unset PB_ALLOW_MODE_CHANGE

# ---- v0.23.3 lane A (tester): AC2 (R2) URL pushes, AC3 (R3) the mode check fails closed, AC11 (R10) no awk multibyte noise ----
# lc_streams ARGS... -> STD (stdout), ERR (stderr) and RC of `leak-check scan ARGS` run in $R
lc_streams() {
  local ef; ef="$(mk_tmp)/err"
  STD="$(cd "$R" && bash "$LC" scan "$@" 2>"$ef")"; RC=$?
  ERR="$(cat "$ef" 2>/dev/null)"
}
# note_for NAME -> the stderr note a scan with a NAME that is not a configured remote must print (R2)
note_for() { printf 'leak-check: %s is not a configured remote; scanning the full range (push through a named remote to limit it)' "$1"; }

echo "v0.23.3 AC2 (R2) a push to a new URL scans the full range"
newrepo
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
U_A="$(mk_tmp)/a.git"; U_B="$(mk_tmp)/b.git"; U_NEW="$(mk_tmp)/new.git"
git -C "$R" remote add origin "$U_A"; git -C "$R" remote add up "$U_B"
git -C "$R" checkout -q -b sec
stage "$R" s.txt "k $GH"; G -C "$R" commit -q --no-verify -m 'secret held only by remote up'
SEC="$(git -C "$R" rev-parse HEAD)"
git -C "$R" update-ref refs/remotes/up/main "$SEC"
assert_eq "AC2 fixture: refs/remotes/up/main holds the secret commit" "$SEC" "$(git -C "$R" rev-parse --verify -q refs/remotes/up/main)"
lc_streams --unpushed "$SEC" --remote "$U_NEW"
assert_eq "AC2 a commit only on refs/remotes/up/main, pushed to a NEW url: scanned, exit 1" "1" "$RC"
assert_contains "AC2 ... the finding is named on stdout" "$STD" "s.txt:1: github-token"
assert_contains "AC2 ... stderr carries the note (NAME is not a configured remote; scanning the full range)" "$ERR" "$(note_for "$U_NEW")"
lc_streams --unpushed "$SEC" --remote nosuchremote
assert_eq "AC2 an unknown NAME: scanned, exit 1" "1" "$RC"
assert_contains "AC2 an unknown NAME: the note names it" "$ERR" "$(note_for nosuchremote)"
lc_streams --unpushed "$SEC"
assert_eq "AC2.2 without --remote any remote counts (unchanged): exit 0" "0" "$RC"
assert_not_contains "AC2.2 without --remote there is no note" "$ERR" "is not a configured remote"
lc_streams --unpushed "$SEC" --remote up
assert_eq "AC2 a configured remote NAME keeps its own refs: up holds the commit: exit 0" "0" "$RC"
assert_not_contains "AC2 a configured remote NAME prints no note" "$ERR" "is not a configured remote"
lc_streams --unpushed "$SEC" --remote origin
assert_eq "AC2 a configured remote NAME: origin does not hold it: exit 1" "1" "$RC"
assert_not_contains "AC2 ... and no note either" "$ERR" "is not a configured remote"

echo "v0.23.3 AC2 (R2) NAME equal to a configured remote's exact url uses that remote's refs"
git -C "$R" update-ref -d refs/remotes/up/main
git -C "$R" update-ref refs/remotes/origin/main "$SEC"
lc_streams --unpushed "$SEC" --remote "$U_A"
assert_eq "AC2 a commit on refs/remotes/origin/* pushed to origin's exact url: skipped, exit 0" "0" "$RC"
assert_contains "AC2 ... says clean" "$STD" "leak-check: clean"
assert_not_contains "AC2 ... no note (the url belongs to a configured remote)" "$ERR" "is not a configured remote"
lc_streams --unpushed "$SEC" --remote "$U_B"
assert_eq "AC2 the url of up (which holds nothing): the commit is scanned, exit 1" "1" "$RC"
assert_not_contains "AC2 ... and the url of a configured remote prints no note" "$ERR" "is not a configured remote"
git -C "$R" config remote.origin.pushurl "$U_A"
lc_streams --unpushed "$SEC" --remote "$U_A"
assert_eq "AC2 a pushurl equal to the url is the same place: still skipped, exit 0" "0" "$RC"
U_P="$(mk_tmp)/push.git"
git -C "$R" config remote.origin.pushurl "$U_P"
lc_streams --unpushed "$SEC" --remote "$U_A"
assert_eq "AC2 the same push when origin's pushurl differs: full scan, exit 1" "1" "$RC"
assert_contains "AC2 ... the finding is named" "$STD" "s.txt:1: github-token"
lc_streams --unpushed "$SEC" --remote "$U_P"
assert_eq "AC2 NAME equal to the differing pushurl: full scan, exit 1" "1" "$RC"
git -C "$R" config --unset remote.origin.pushurl
lc_streams --unpushed "$SEC" --remote "$U_A"
assert_eq "AC2 fixture check: with the pushurl removed origin's exact url is skipped again: exit 0" "0" "$RC"

echo "v0.23.3 AC2 (R2) a second url value, and insteadOf, name the same place"
DIR_A="$(dirname "$U_A")"
git -C "$R" config "url.$DIR_A/.insteadOf" 'short:'
git -C "$R" config --add remote.origin.url 'short:a.git'
assert_eq "AC2 fixture: origin has two url values" "2" "$(git -C "$R" config --get-all remote.origin.url | wc -l | tr -d ' ')"
lc_streams --unpushed "$SEC" --remote 'short:a.git'
assert_eq "AC2 NAME equal to the SECOND url value (both expand to the same place): origin's refs, exit 0" "0" "$RC"
lc_streams --unpushed "$SEC" --remote "$U_A"
assert_eq "AC2 NAME equal to the first url value with a second value present: exit 0" "0" "$RC"
git -C "$R" config --unset-all remote.origin.url
git -C "$R" config remote.origin.url "$U_A"
lc_streams --unpushed "$SEC" --remote 'short:a.git'
assert_eq "AC2 an insteadOf form of origin's url (git ls-remote --get-url): origin's refs, exit 0" "0" "$RC"
assert_not_contains "AC2 ... no note" "$ERR" "is not a configured remote"
git -C "$R" config --unset-all remote.origin.url
git -C "$R" config remote.origin.url 'short:a.git'
lc_streams --unpushed "$SEC" --remote "$U_A"
assert_eq "AC2 origin configured through insteadOf, NAME is the expanded url: exit 0" "0" "$RC"
git -C "$R" config --unset-all remote.origin.url
git -C "$R" config remote.origin.url "$U_A"
git -C "$R" config --add remote.origin.url "$U_B"
lc_streams --unpushed "$SEC" --remote "$U_B"
assert_eq "AC2 a second url value that names ANOTHER place: not every value is the same place: full scan, exit 1" "1" "$RC"
lc_streams --unpushed "$SEC" --remote "$U_A"
assert_eq "AC2 ... also for the first value: full scan, exit 1" "1" "$RC"
git -C "$R" config --unset-all remote.origin.url
git -C "$R" config remote.origin.url "$U_A"
git -C "$R" config --unset "url.$DIR_A/.insteadOf"

echo "v0.23.3 AC2 (R2) a trailing .git or / is not normalized: the safe side is the full scan"
lc_streams --unpushed "$SEC" --remote "${U_A%.git}"
assert_eq "AC2 origin's url without its trailing .git: full scan, exit 1" "1" "$RC"
assert_contains "AC2 ... with the note" "$ERR" "$(note_for "${U_A%.git}")"
lc_streams --unpushed "$SEC" --remote "$U_A/"
assert_eq "AC2 origin's url plus a trailing /: full scan, exit 1" "1" "$RC"
assert_contains "AC2 ... with the note" "$ERR" "$(note_for "$U_A/")"
lc_streams --unpushed "$SEC" --remote "$U_A"
assert_eq "AC2 the exact url is skipped as before: exit 0" "0" "$RC"

echo "v0.23.3 AC2 (R2) several remotes with the same url: the union of their refs counts"
newrepo
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
BASE3="$(git -C "$R" rev-parse HEAD)"
U_S="$(mk_tmp)/shared.git"; U_O="$(mk_tmp)/other.git"
git -C "$R" remote add r1 "$U_S"; git -C "$R" remote add r2 "$U_S"; git -C "$R" remote add r3 "$U_O"
git -C "$R" checkout -q -b s1 "$BASE3"
stage "$R" one.txt "k $GH"; G -C "$R" commit -q --no-verify -m 'secret one (r1)'
S1="$(git -C "$R" rev-parse HEAD)"
git -C "$R" checkout -q -b s2 "$BASE3"
stage "$R" two.txt "k $AWS"; G -C "$R" commit -q --no-verify -m 'secret two (r2)'
S2="$(git -C "$R" rev-parse HEAD)"
git -C "$R" checkout -q -b s3 "$BASE3"
stage "$R" three.txt "k $GHS"; G -C "$R" commit -q --no-verify -m 'secret three (r3)'
S3="$(git -C "$R" rev-parse HEAD)"
git -C "$R" update-ref refs/remotes/r1/main "$S1"
git -C "$R" update-ref refs/remotes/r2/main "$S2"
git -C "$R" update-ref refs/remotes/r3/main "$S3"
git -C "$R" checkout -q -b top "$BASE3"
git -C "$R" merge -q --no-edit -m 'octopus of the three' s1 s2 s3 >/dev/null 2>&1 || echo "fixture: octopus merge failed"
TOP="$(git -C "$R" rev-parse HEAD)"
lc_streams --unpushed "$TOP" --remote "$U_S"
assert_eq "AC2 the url shared by r1 and r2: the commits on r1/* and r2/* are skipped, the one on r3 is scanned: exit 1" "1" "$RC"
assert_contains "AC2 ... r3's secret is named" "$STD" "three.txt:1: github-token"
assert_not_contains "AC2 ... r1's commit (union) is not scanned" "$STD" "one.txt"
assert_not_contains "AC2 ... r2's commit (union) is not scanned" "$STD" "two.txt"
assert_not_contains "AC2 ... no note for a configured url" "$ERR" "is not a configured remote"

echo "v0.23.3 AC2 the usage still describes --remote, and the pre-push hook passes a URL through unchanged"
newrepo
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
HU_A="$(mk_tmp)/a.git"; HU_B="$(mk_tmp)/b.git"; HU_NEW="$(mk_tmp)/n.git"
git init -q --bare "$HU_A"; git init -q --bare "$HU_B"; git init -q --bare "$HU_NEW"
git -C "$R" remote add up "$HU_B"; git -C "$R" push -q up main
run_in "$R" bash "$LC" install-hooks
stage "$R" hk.txt "k $GH"; G -C "$R" commit -q --no-verify -m 'secret'
git -C "$R" push -q --no-verify up "HEAD:refs/heads/held"
run_in "$R" git push "$HU_NEW" "HEAD:refs/heads/viaurl"
if [ "$RC" != 0 ]; then t_ok "AC2 a hook push of a commit that only remote up holds to a NEW bare url is blocked (exit $RC)"; else t_bad "AC2 a hook push of a commit that only remote up holds to a NEW bare url is blocked" "exit 0; output: $OUT"; fi
assert_contains "AC2 ... the hook shows the finding" "$OUT" "hk.txt:1: github-token"
if git -C "$HU_NEW" rev-parse --verify -q refs/heads/viaurl >/dev/null; then t_bad "AC2 ... the blocked push did not reach the new url" "viaurl exists"; else t_ok "AC2 ... the blocked push did not reach the new url"; fi

# ---- AC3 (R3): the mode check never fails open (leak-check side) ----
echo "v0.23.3 AC3.2 (R3) scan --staged: a path with a newline fails closed, with no escape"
modrepo
NLP="$(printf 'bin/new\nline.sh')"
if printf '#!/bin/sh\n' > "$R/$NLP" 2>/dev/null && [ -f "$R/$NLP" ] && git -C "$R" add -- "$NLP" 2>/dev/null && git -C "$R" ls-files --error-unmatch -- "$NLP" >/dev/null 2>&1; then
  NLMSG="VIOLATION (mode): a path contains a newline or a \002 byte; the mode check is incomplete"
  scan_streams
  assert_eq "AC3.2 a staged path with a newline: exit 1" "1" "$RC"
  assert_contains "AC3.2 the refusal says the path contains a newline and the check is incomplete" "$STD$ERR" "$NLMSG"
  scan_streams PB_ALLOW_MODE_CHANGE="$NLP"
  assert_eq "AC3.2 PB_ALLOW_MODE_CHANGE with the whole path is no escape: exit 1" "1" "$RC"
  assert_contains "AC3.2 ... the message is still printed" "$STD$ERR" "$NLMSG"
  scan_streams PB_ALLOW_MODE_CHANGE="bin/new:line.sh:bin/new
line.sh"
  assert_eq "AC3.2 PB_ALLOW_MODE_CHANGE with the pieces is no escape either: exit 1" "1" "$RC"
  git -C "$R" rm -q --cached -f -- "$NLP"; rm -f "$R/$NLP"
  scan_streams
  assert_eq "AC3.2 after the path is gone the scan is clean again: exit 0" "0" "$RC"
else rm -f "$R/$NLP" 2>/dev/null; t_skip 6 "AC3.2 newline path (this file system or git refuses the name)"; fi

echo "v0.23.3 AC3.3 (R3) scan --staged: a failing raw diff makes the mode check fail closed"
modrepo
printf 'changed\n' > "$R/notes.txt"; git -C "$R" add notes.txt
RAWSHIM="$(mk_tmp)/rawshim"; mkdir -p "$RAWSHIM"
REALGIT="$(command -v git)"
cat > "$RAWSHIM/git" <<SHIM
#!/bin/sh
# fails like a broken clean filter on every "diff --raw" call, runs the real git otherwise
for a in "\$@"; do
  case "\$a" in --raw) echo "shim: git diff --raw failed" >&2; exit 128 ;; esac
done
exec "$REALGIT" "\$@"
SHIM
chmod +x "$RAWSHIM/git"
scan_streams
assert_eq "AC3.3 fixture: without the shim the scan is clean: exit 0" "0" "$RC"
scan_streams PATH="$RAWSHIM:$PATH"
assert_eq "AC3.3 pb_raw_lines fails (shim): the mode check fails closed, exit 1" "1" "$RC"
assert_contains "AC3.3 ... the output says VIOLATION (mode)" "$STD$ERR" "VIOLATION (mode)"
assert_contains "AC3.3 ... and that the mode check is incomplete" "$STD$ERR" "the mode check is incomplete"
assert_not_contains "AC3.3 ... and does not say clean" "$STD" "leak-check: clean"
scan_streams PATH="$RAWSHIM:$PATH" PB_ALLOW_MODE_CHANGE=notes.txt
assert_eq "AC3.3 PB_ALLOW_MODE_CHANGE does not turn the failure off: exit 1" "1" "$RC"

# ---- AC11 (R10): gawk under a UTF-8 locale prints nothing for invalid bytes; the masking stays per character ----
echo "v0.23.3 AC11 (R10) gawk + UTF-8 locale: invalid UTF-8 in a diff prints nothing on stderr, the findings are unchanged"
GAWK="$(command -v gawk 2>/dev/null)" || GAWK=""
UCAND=""
if [ -n "$GAWK" ]; then
  # a UTF-8 locale where gawk counts characters (so it also complains about invalid bytes)
  for cand in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
    if [ "$(LC_ALL="$cand" "$GAWK" 'BEGIN { print length("\303\251") }' 2>/dev/null)" = 1 ]; then UCAND="$cand"; break; fi
  done
fi
if [ -z "$GAWK" ] || [ -z "$UCAND" ]; then
  t_skip 6 "AC11 gawk under a UTF-8 locale (gawk: [${GAWK:-missing}], locale: [${UCAND:-none}])"
else
  GAWKD="$(mk_tmp)/gawkbin"; mkdir -p "$GAWKD"
  ln -s "$GAWK" "$GAWKD/awk" 2>/dev/null && [ -x "$GAWKD/awk" ] || { rm -f "$GAWKD/awk"; cp "$GAWK" "$GAWKD/awk" 2>/dev/null; chmod +x "$GAWKD/awk" 2>/dev/null; }
  newrepo
  mkdir -p "$R/bin"
  printf 'bad bytes \377\376 and \300\257 here\n%s\nlast line\n' "k $GH" > "$R/bin/inv.txt"
  git -C "$R" add -- bin/inv.txt
  U8E="$(mk_tmp)/err"
  U8OUT="$(cd "$R" && env LC_ALL="$UCAND" PATH="$GAWKD:$PATH" bash "$LC" scan --staged 2>"$U8E")"; U8RC=$?
  U8ERR="$(grep -v 'LF will be replaced by CRLF' "$U8E" 2>/dev/null)"
  assert_eq "AC11 invalid bytes next to a secret: exit 1 (the finding is unchanged)" "1" "$U8RC"
  assert_contains "AC11 ... the secret is found on its line" "$U8OUT" "bin/inv.txt:2: github-token"
  assert_not_contains "AC11 ... stderr has no 'Invalid multibyte data' warning" "$U8ERR" "multibyte"
  assert_eq "AC11 ... stderr is empty" "" "$U8ERR"
  # the same scan with a clean file: still nothing on stderr
  newrepo
  mkdir -p "$R/bin"; printf 'bad bytes \377\376 only\n' > "$R/bin/inv.txt"; git -C "$R" add -- bin/inv.txt
  U8OUT="$(cd "$R" && env LC_ALL="$UCAND" PATH="$GAWKD:$PATH" bash "$LC" scan --staged 2>"$U8E")"; U8RC=$?
  U8ERR="$(grep -v 'LF will be replaced by CRLF' "$U8E" 2>/dev/null)"
  assert_eq "AC11 invalid bytes and no secret: exit 0" "0" "$U8RC"
  assert_eq "AC11 ... stderr is empty" "" "$U8ERR"
fi

echo "v0.23.3 AC11 (R10) the masking awk keeps the user locale: per-character masking of multibyte text (gawk, UTF-8)"
if [ -z "$GAWK" ] || [ -z "$UCAND" ]; then
  t_skip 6 "AC11 multibyte masking (gawk: [${GAWK:-missing}], locale: [${UCAND:-none}])"
else
  E1="$(printf '\303\251')"   # one letter, two bytes
  E2="$(printf '\303\274')"   # another one
  LIT7="$E1$E1$E1$E1$E1$E1$E1"
  LIT10="$E2$E2$E2$E2$E2$E2$E2$E2$E2$E2"
  conf_global "leak_literals=$LIT7,${LIT10}x"
  newrepo
  stage "$R" mb.txt "one ${LIT7} here" "two ${LIT10}x here"
  U8OUT="$(cd "$R" && env LC_ALL="$UCAND" PATH="$GAWKD:$PATH" bash "$LC" scan --staged 2>/dev/null)"; U8RC=$?
  L1="$(printf '%s\n' "$U8OUT" | grep '^mb.txt:1: ')"
  L2="$(printf '%s\n' "$U8OUT" | grep '^mb.txt:2: ')"
  assert_eq "AC11 multibyte literals present: exit 1" "1" "$U8RC"
  assert_contains "AC11 the 7-letter match (14 bytes) is reported at its line" "$L1" "mb.txt:1: user-literal"
  assert_not_contains "AC11 a 7-LETTER match is 8 characters or fewer: no letter of it is shown" "$L1" "$E1"
  assert_contains "AC11 the 11-letter match is reported at its line" "$L2" "mb.txt:2: user-literal"
  assert_contains "AC11 a longer match shows its first 4 LETTERS then ***" "$L2" "user-literal $E2$E2$E2$E2***"
  assert_not_contains "AC11 ... and not a fifth letter (per character, not per byte)" "$L2" "$E2$E2$E2$E2$E2"
  rm -f "$PH/.agents/playbook.conf"
fi

# ---- v0.23.3 lane A review of 146dd98 ----
echo "v0.23.3 lane A review MAJOR-1 pushInsteadOf: git pushes to the NAME after pushInsteadOf, so a rewritten push scans the full range"
newrepo
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
PU="$(mk_tmp)/u.git"; PZ="$(mk_tmp)/z.git"
git init -q --bare "$PU"; git init -q --bare "$PZ"
git -C "$R" remote add origin "$PU"
git -C "$R" config remote.origin.pushurl "$PU"
git -C "$R" push -q "$PZ" main
stage "$R" p1.txt "k $GH"; G -C "$R" commit -q --no-verify -m 'secret held by origin/main only'
PSEC="$(git -C "$R" rev-parse HEAD)"
git -C "$R" update-ref refs/remotes/origin/main "$PSEC"
lc_streams --unpushed "$PSEC" --remote "$PU"
assert_eq "P1 control: no pushInsteadOf, origin's exact url uses origin's refs: exit 0" "0" "$RC"
assert_not_contains "P1 control: no note" "$ERR" "is not a configured remote"
git -C "$R" config "url.$PZ.pushInsteadOf" "$PU"
lc_streams --unpushed "$PSEC" --remote "$PU"
assert_eq "P1 origin url = pushurl = U, pushInsteadOf U -> Z: the full range is scanned, exit 1" "1" "$RC"
assert_contains "P1 ... the finding is named" "$STD" "p1.txt:1: github-token"
assert_contains "P1 ... stderr carries the usual note" "$ERR" "$(note_for "$PU")"
run_in "$R" bash "$LC" install-hooks
assert_rc "P1 hook setup: install-hooks exit 0" 0
run_in "$R" git push "$PU" "main:refs/heads/newbr"
if [ "$RC" != 0 ]; then t_ok "P1 the installed hook refuses 'git push U main:newbr' (exit $RC)"; else t_bad "P1 the installed hook refuses 'git push U main:newbr'" "exit 0; output: $OUT"; fi
assert_contains "P1 ... the hook shows the finding" "$OUT" "p1.txt:1: github-token"
if git -C "$PZ" rev-parse --verify -q refs/heads/newbr >/dev/null; then t_bad "P1 Z.git did not receive the branch" "newbr is on Z"; else t_ok "P1 Z.git did not receive the branch"; fi
if git -C "$PZ" cat-file -e "$PSEC" 2>/dev/null; then t_bad "P1 Z.git did not receive the secret commit" "object is on Z"; else t_ok "P1 Z.git did not receive the secret commit"; fi
git -C "$R" config --unset-all "url.$PZ.pushInsteadOf"
git -C "$R" config "url.$PZ.pushInsteadOf" "no-such-prefix:"
lc_streams --unpushed "$PSEC" --remote "$PU"
assert_eq "P1 control: a pushInsteadOf whose value is no prefix of NAME changes nothing: exit 0" "0" "$RC"

echo "v0.23.3 lane A review MAJOR-1 P2: insteadOf and pushInsteadOf on one prefix, origin with no pushurl"
newrepo
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
QU="$(mk_tmp)/u.git"; QZ="$(mk_tmp)/z.git"
git init -q --bare "$QU"; git init -q --bare "$QZ"
git -C "$R" remote add origin "$QU"
git -C "$R" config "url.$QU.insteadOf" 'short:'
git -C "$R" config "url.$QZ.pushInsteadOf" 'short:'
git -C "$R" push -q "$QZ" main
stage "$R" p2.txt "k $GH"; G -C "$R" commit -q --no-verify -m 'secret held by origin/main only (P2)'
QSEC="$(git -C "$R" rev-parse HEAD)"
git -C "$R" update-ref refs/remotes/origin/main "$QSEC"
lc_streams --unpushed "$QSEC" --remote 'short:'
assert_eq "P2 NAME short: (insteadOf -> U, pushInsteadOf -> Z): the full range is scanned, exit 1" "1" "$RC"
assert_contains "P2 ... the finding is named" "$STD" "p2.txt:1: github-token"
assert_contains "P2 ... stderr carries the usual note" "$ERR" "$(note_for 'short:')"
run_in "$R" bash "$LC" install-hooks
assert_rc "P2 hook setup: install-hooks exit 0" 0
run_in "$R" git push 'short:' "main:refs/heads/newbr"
if [ "$RC" != 0 ]; then t_ok "P2 the installed hook refuses 'git push short: main:newbr' (exit $RC)"; else t_bad "P2 the installed hook refuses 'git push short: main:newbr'" "exit 0; output: $OUT"; fi
if git -C "$QZ" cat-file -e "$QSEC" 2>/dev/null; then t_bad "P2 Z.git did not receive the secret commit" "object is on Z"; else t_ok "P2 Z.git did not receive the secret commit"; fi

echo "v0.23.3 lane A review MINOR-2 the usage text shows the Exit line"
newrepo
run_in "$R" bash "$LC"
assert_rc "usage: no arguments, exit 2" 2
assert_contains "usage prints the Exit line (0 clean, 1 a hit, 2 usage, 3 not a git repo)" "$OUT" "Exit: 0 clean"
assert_contains "usage prints the whole Exit line (up to exit 3)" "$OUT" "3 not a git repo"

echo "v0.23.3 lane A review MINOR-3 scan --staged: a path with a control byte fails closed with the control-byte message"
modrepo
CTLP="bin/ctl$(printf '\002')x.sh"
if printf '#!/bin/sh\n' > "$R/$CTLP" 2>/dev/null && [ -f "$R/$CTLP" ] && git -C "$R" add -- "$CTLP" 2>/dev/null && git -C "$R" ls-files --error-unmatch -- "$CTLP" >/dev/null 2>&1; then
  CTLMSG="VIOLATION (mode): a path contains a newline or a \002 byte; the mode check is incomplete"
  scan_streams
  assert_eq "a staged path with a \\002 byte: exit 1" "1" "$RC"
  assert_contains "... the message says a path contains a newline or control byte" "$STD$ERR" "$CTLMSG"
  scan_streams PB_ALLOW_MODE_CHANGE="$CTLP"
  assert_eq "... PB_ALLOW_MODE_CHANGE with the path is no escape: exit 1" "1" "$RC"
  assert_contains "... the message is still printed" "$STD$ERR" "$CTLMSG"
  git -C "$R" rm -q --cached -f -- "$CTLP"; rm -f "${R:?}/${CTLP:?}"
else rm -f "${R:?}/${CTLP:?}" 2>/dev/null; t_skip 4 "control-byte path (this file system or git refuses the name)"; fi

# ---- v0.23.3 lane A review round 3 (fix round 3) ----
# pfix WHERE -> sets R (work repo), D-level bare repos PRIV (origin's url), PUB (empty), FORK (empty) and PSEC (the secret commit).
# WHERE=origin: the secret commit is on origin/main (pushed to PRIV, fetched). WHERE=fork: it is on remote fork's refs only
# (origin holds the base commit only). Then a branch feat adds a benign commit on top, and the hooks are installed.
pfix() {
  local d; d="$(mk_tmp)"; PRIV="$d/priv.git"; PUB="$d/pub.git"; FORK="$d/fork.git"
  git init -q --bare "$PRIV"; git init -q --bare "$PUB"; git init -q --bare "$FORK"
  newrepo
  git -C "$R" remote add origin "$PRIV"
  git -C "$R" push -q --no-verify origin HEAD:refs/heads/main
  git -C "$R" fetch -q origin
  if [ "$1" = fork ]; then git -C "$R" remote add fork "$FORK"; fi
  stage "$R" s.txt "k $GH"; G -C "$R" commit -q --no-verify -m 'secret commit'
  PSEC="$(git -C "$R" rev-parse HEAD)"
  if [ "$1" = fork ]; then
    git -C "$R" push -q --no-verify fork HEAD:refs/heads/main; git -C "$R" fetch -q fork
  else
    git -C "$R" push -q --no-verify origin HEAD:refs/heads/main; git -C "$R" fetch -q origin
  fi
  git -C "$R" checkout -q -b feat
  stage "$R" b.txt 'benign'; G -C "$R" commit -q -m 'benign commit'
  run_in "$R" bash "$LC" install-hooks
}
# holds BARE -> 0 when BARE has the secret commit or a feat branch
holds_secret() { git -C "$1" cat-file -e "$PSEC" 2>/dev/null; }
holds_feat() { git -C "$1" rev-parse --verify -q refs/heads/feat >/dev/null 2>&1; }

echo "v0.23.3 lane A review round 3 MAJOR-1: a pushInsteadOf base holding '.pushinsteadof ' is not split at its first occurrence"
pfix origin
XB="$(mk_tmp)/x.pushinsteadof y.git"
if git init -q --bare "$XB" 2>/dev/null && [ -d "$XB" ]; then
  git -C "$R" config "url.$PRIV.insteadOf" 'pv:'
  git -C "$R" config "url.$XB.pushInsteadOf" 'pv:'
  lc_streams --unpushed "$(git -C "$R" rev-parse feat)" --remote 'pv:'
  assert_eq "R3 M1 scan --remote pv: (insteadOf -> priv, pushInsteadOf -> a base with '.pushinsteadof y'): full range, exit 1" "1" "$RC"
  assert_contains "R3 M1 ... the finding is named" "$STD" "s.txt:1: github-token"
  assert_contains "R3 M1 ... stderr carries the usual note" "$ERR" "$(note_for 'pv:')"
  run_in "$R" git push 'pv:' feat
  if [ "$RC" != 0 ]; then t_ok "R3 M1 the installed hook refuses 'git push pv: feat' (exit $RC)"; else t_bad "R3 M1 the installed hook refuses 'git push pv: feat'" "exit 0; output: $OUT"; fi
  assert_contains "R3 M1 ... the hook shows the finding" "$OUT" "s.txt:1: github-token"
  if holds_secret "$XB"; then t_bad "R3 M1 the secret commit did not reach the x.pushinsteadof y.git repo" "object is there"; else t_ok "R3 M1 the secret commit did not reach the x.pushinsteadof y.git repo"; fi
else t_skip 6 "R3 M1 a directory name with a space and '.pushinsteadof' (this file system refuses it)"; fi

echo "v0.23.3 lane A review round 3 MAJOR-2 control: a plain named push, no rewrite, the secret on origin/main"
pfix origin
run_in "$R" git push origin feat
assert_rc "R3 M2 control: git push origin feat with the secret on origin/main: exit 0" 0
if holds_feat "$PRIV"; then t_ok "R3 M2 control: the push reached priv"; else t_bad "R3 M2 control: the push reached priv" "no feat on priv; output: $OUT"; fi

echo "v0.23.3 lane A review round 3 MAJOR-2 F: named remote origin, pushInsteadOf on its url, no pushurl"
pfix origin
git -C "$R" config "url.$PUB.pushInsteadOf" "$PRIV"
run_in "$R" git push origin feat
if [ "$RC" != 0 ]; then t_ok "R3 M2 F: git push origin feat (the push goes to pub) is refused (exit $RC)"; else t_bad "R3 M2 F: git push origin feat (the push goes to pub) is refused" "exit 0; output: $OUT"; fi
assert_contains "R3 M2 F: the hook shows the finding" "$OUT" "s.txt:1: github-token"
if holds_secret "$PUB"; then t_bad "R3 M2 F: pub did not receive the secret commit" "object is on pub"; else t_ok "R3 M2 F: pub did not receive the secret commit"; fi
if holds_feat "$PUB"; then t_bad "R3 M2 F: pub did not receive the branch" "feat is on pub"; else t_ok "R3 M2 F: pub did not receive the branch"; fi

echo "v0.23.3 lane A review round 3 MAJOR-2 F2: named remote origin, pushurl = pub, no pushInsteadOf"
pfix origin
git -C "$R" config remote.origin.pushurl "$PUB"
run_in "$R" git push origin feat
if [ "$RC" != 0 ]; then t_ok "R3 M2 F2: git push origin feat (pushurl is pub) is refused (exit $RC)"; else t_bad "R3 M2 F2: git push origin feat (pushurl is pub) is refused" "exit 0; output: $OUT"; fi
assert_contains "R3 M2 F2: the hook shows the finding" "$OUT" "s.txt:1: github-token"
if holds_secret "$PUB"; then t_bad "R3 M2 F2: pub did not receive the secret commit" "object is on pub"; else t_ok "R3 M2 F2: pub did not receive the secret commit"; fi

echo "v0.23.3 lane A review round 3 MAJOR-2 F3: origin's pushurl is remote fork's url, and fork holds the secret commit"
pfix fork
git -C "$R" config remote.origin.pushurl "$FORK"
run_in "$R" git push origin feat
assert_rc "R3 M2 F3: git push origin feat (the push destination is fork, which holds the secret) is allowed: exit 0" 0
assert_not_contains "R3 M2 F3: no finding is printed" "$OUT" "github-token"
if holds_feat "$FORK"; then t_ok "R3 M2 F3: the push reached fork"; else t_bad "R3 M2 F3: the push reached fork" "no feat on fork; output: $OUT"; fi
if holds_feat "$PRIV"; then t_bad "R3 M2 F3: the push did not go to origin's fetch url" "feat is on priv"; else t_ok "R3 M2 F3: the push did not go to origin's fetch url"; fi

echo "v0.23.3 lane A review round 3 MAJOR-2 G: pushurl = url (same place) with a pushInsteadOf on that url: git ignores the rewrite"
pfix origin
git -C "$R" config remote.origin.pushurl "$PRIV"
git -C "$R" config "url.$PUB.pushInsteadOf" "$PRIV"
run_in "$R" git push origin feat
assert_rc "R3 M2 G: git push origin feat (pushurl = url = priv; the secret is on origin/main): exit 0" 0
if holds_feat "$PRIV"; then t_ok "R3 M2 G: git pushed to the pushurl (priv)"; else t_bad "R3 M2 G: git pushed to the pushurl (priv)" "no feat on priv; output: $OUT"; fi
if holds_feat "$PUB"; then t_bad "R3 M2 G: nothing went to pub" "feat is on pub"; else t_ok "R3 M2 G: nothing went to pub"; fi

# ---- v0.23.3 lane A review round 4 (fix round 4): remotes with several urls ----
# git fetches only from a remote's FIRST url but pushes to all its urls (or to all its pushurls): git-push(1), REMOTES.
# So a secret fetched from the first url is not "owned" by the second url, and the push must scan the full range.
echo "v0.23.3 lane A review round 4 N6: origin has urls priv and pub, no pushurl; the secret is on origin/main (fetched from priv)"
pfix origin
git -C "$R" config --add remote.origin.url "$PUB"
run_in "$R" git push origin feat
if [ "$RC" != 0 ]; then t_ok "R4 N6: git push origin feat (it also pushes to pub) is refused (exit $RC)"; else t_bad "R4 N6: git push origin feat (it also pushes to pub) is refused" "exit 0; output: $OUT"; fi
assert_contains "R4 N6: the hook shows the finding" "$OUT" "s.txt:1: github-token"
if holds_secret "$PUB"; then t_bad "R4 N6: pub did not receive the secret commit" "object is on pub"; else t_ok "R4 N6: pub did not receive the secret commit"; fi
# NIT-C: the push goes to origin's own first url AND elsewhere; the note must not claim that no configured remote owns it
assert_contains "R4 NIT-C N6: the note says origin pushes to a place its fetched refs do not cover" "$OUT" "origin pushes to a place its fetched refs do not cover; scanning the full range"
assert_not_contains "R4 NIT-C N6: the note does not say 'no configured remote owns' (priv is origin's own url)" "$OUT" "no configured remote owns"

echo "v0.23.3 lane A review round 4 N6b: origin has urls priv and pub, pushurl = pub"
pfix origin
git -C "$R" config --add remote.origin.url "$PUB"
git -C "$R" config remote.origin.pushurl "$PUB"
run_in "$R" git push origin feat
if [ "$RC" != 0 ]; then t_ok "R4 N6b: git push origin feat (pushurl is pub) is refused (exit $RC)"; else t_bad "R4 N6b: git push origin feat (pushurl is pub) is refused" "exit 0; output: $OUT"; fi
assert_contains "R4 N6b: the hook shows the finding" "$OUT" "s.txt:1: github-token"
if holds_secret "$PUB"; then t_bad "R4 N6b: pub did not receive the secret commit" "object is on pub"; else t_ok "R4 N6b: pub did not receive the secret commit"; fi

echo "v0.23.3 lane A review round 4 N6c control: origin has urls priv and pub, pushurl = priv (the first url)"
pfix origin
git -C "$R" config --add remote.origin.url "$PUB"
git -C "$R" config remote.origin.pushurl "$PRIV"
run_in "$R" git push origin feat
assert_rc "R4 N6c control: git push origin feat (it only pushes to priv, whose refs origin fetched): exit 0" 0
if holds_feat "$PRIV"; then t_ok "R4 N6c control: the push reached priv"; else t_bad "R4 N6c control: the push reached priv" "no feat on priv; output: $OUT"; fi
if holds_feat "$PUB"; then t_bad "R4 N6c control: nothing went to pub" "feat is on pub"; else t_ok "R4 N6c control: nothing went to pub"; fi

echo "v0.23.3 lane A review round 4 N2: origin has pushurls priv and pub (a check of only the first push destination misses pub)"
pfix origin
git -C "$R" config --add remote.origin.pushurl "$PRIV"
git -C "$R" config --add remote.origin.pushurl "$PUB"
run_in "$R" git push origin feat
if [ "$RC" != 0 ]; then t_ok "R4 N2: git push origin feat (pushurls priv and pub) is refused (exit $RC)"; else t_bad "R4 N2: git push origin feat (pushurls priv and pub) is refused" "exit 0; output: $OUT"; fi
assert_contains "R4 N2: the hook shows the finding" "$OUT" "s.txt:1: github-token"
if holds_secret "$PUB"; then t_bad "R4 N2: pub did not receive the secret commit" "object is on pub"; else t_ok "R4 N2: pub did not receive the secret commit"; fi
assert_contains "R4 NIT-C N2: the note says origin pushes to a place its fetched refs do not cover" "$OUT" "origin pushes to a place its fetched refs do not cover; scanning the full range"
assert_not_contains "R4 NIT-C N2: the note does not say 'no configured remote owns'" "$OUT" "no configured remote owns"

echo "v0.23.3 lane A review round 4 N8: origin has pushurls fork and pub; the secret is on refs/remotes/fork/* only; pub is unowned"
pfix fork
git -C "$R" config --add remote.origin.pushurl "$FORK"
git -C "$R" config --add remote.origin.pushurl "$PUB"
run_in "$R" git push origin feat
if [ "$RC" != 0 ]; then t_ok "R4 N8: git push origin feat (pushurls fork and pub) is refused (exit $RC)"; else t_bad "R4 N8: git push origin feat (pushurls fork and pub) is refused" "exit 0; output: $OUT"; fi
assert_contains "R4 N8: the hook shows the finding" "$OUT" "s.txt:1: github-token"
if holds_secret "$PUB"; then t_bad "R4 N8: pub did not receive the secret commit" "object is on pub"; else t_ok "R4 N8: pub did not receive the secret commit"; fi

echo "v0.24.1 MINOR-B/M2 origin has pushurls pub and fork (pub first); the secret is on refs/remotes/fork/* only; pub is no configured remote"
# dest_owned must fail for a destination that is no configured remote's place (return 1: scan the full range). A skip (|| continue) would
# leave fork's refs as the only owned ones, exclude the secret commit, and let the hook wave the push through to pub. Only the exit code,
# the finding and what the bare repositories hold are asserted here, never the wording of the note.
pfix fork
git -C "$R" config --add remote.origin.pushurl "$PUB"
git -C "$R" config --add remote.origin.pushurl "$FORK"
run_in "$R" git push origin feat
if [ "$RC" != 0 ]; then t_ok "M2: git push origin feat (pushurls pub and fork) is refused (exit $RC)"; else t_bad "M2: git push origin feat (pushurls pub and fork) is refused" "exit 0; output: $OUT"; fi
assert_contains "M2: the hook shows the finding" "$OUT" "s.txt:1: github-token"
if holds_secret "$PUB"; then t_bad "M2: pub did not receive the secret commit" "object is on pub"; else t_ok "M2: pub did not receive the secret commit"; fi
if holds_feat "$PUB"; then t_bad "M2: pub did not receive the feat branch" "feat is on pub"; else t_ok "M2: pub did not receive the feat branch"; fi
if holds_feat "$FORK"; then t_bad "M2: fork did not receive the feat branch either (the hook stopped the whole push)" "feat is on fork"; else t_ok "M2: fork did not receive the feat branch either (the hook stopped the whole push)"; fi

echo "v0.23.3 lane A review round 4 F3 control: origin's pushurl is remote fork's url, fork holds the secret (still allowed)"
pfix fork
git -C "$R" config remote.origin.pushurl "$FORK"
run_in "$R" git push origin feat
assert_rc "R4 F3 control: git push origin feat (the only destination is fork, which holds the secret): exit 0" 0
if holds_feat "$FORK"; then t_ok "R4 F3 control: the push reached fork"; else t_bad "R4 F3 control: the push reached fork" "no feat on fork; output: $OUT"; fi

# ---- v0.24.4 item 7: PB_LEAK_SCAN_BASE bounds the full-range scan of a push to an unknown URL (explicit escape, never automatic) ----
echo "v0.24.4 PB_LEAK_SCAN_BASE=REF scans REF..SHA for a destination no remote owns"
newrepo
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
U_X="$(mk_tmp)/x.git"
stage "$R" old.txt "k $GH"; G -C "$R" commit -q --no-verify -m 'old secret'
OLD="$(git -C "$R" rev-parse HEAD)"
stage "$R" mid.txt "clean line"; G -C "$R" commit -q --no-verify -m 'clean'
MID="$(git -C "$R" rev-parse HEAD)"
lc_streams --unpushed "$MID" --remote "$U_X"
assert_eq "B1 no escape: the old secret is found (full scan unchanged), exit 1" "1" "$RC"
assert_contains "B1 ... named" "$STD" "old.txt:1: github-token"
assert_contains "B1 ... the note mentions the escape" "$ERR" "PB_LEAK_SCAN_BASE"
stage "$R" new.txt "k $AWS"; G -C "$R" commit -q --no-verify -m 'new secret'
NEW="$(git -C "$R" rev-parse HEAD)"
export PB_LEAK_SCAN_BASE="$MID"
lc_streams --unpushed "$NEW" --remote "$U_X"
assert_eq "B2 base=MID: the newer secret is found, exit 1" "1" "$RC"
assert_contains "B2 ... named" "$STD" "new.txt:1: aws-key"
assert_not_contains "B2 ... the older secret is not reported" "$STD" "old.txt"
assert_contains "B2 ... stderr says the scan is bounded" "$ERR" "scanning only $MID..$NEW"
lc_streams --unpushed "$MID" --remote "$U_X"
assert_eq "B3 base=MID with SHA=MID: nothing newer, exit 0" "0" "$RC"
assert_contains "B3 ... clean" "$STD" "leak-check: clean"
export PB_LEAK_SCAN_BASE="$OLD"
lc_streams --unpushed "$NEW" --remote "$U_X"
assert_not_contains "B4 base=OLD: the base commit itself is excluded" "$STD" "old.txt"
assert_contains "B4 ... the newer secret is found" "$STD" "new.txt:1: aws-key"
export PB_LEAK_SCAN_BASE="nosuchref-$$"
lc_streams --unpushed "$NEW" --remote "$U_X"
assert_eq "B5 a bad ref: exit 3, never a silent fallback" "3" "$RC"
assert_contains "B5 ... the message names the variable and the ref" "$ERR" "PB_LEAK_SCAN_BASE"
assert_contains "B5 ... and the ref" "$ERR" "nosuchref-$$"
assert_not_contains "B5 ... nothing is scanned" "$STD" "github-token"
export PB_LEAK_SCAN_BASE=""
lc_streams --unpushed "$NEW" --remote "$U_X"
assert_eq "B6 an empty value is not set: the full scan, exit 1" "1" "$RC"
assert_contains "B6 ... the old secret is found" "$STD" "old.txt:1: github-token"
export PB_LEAK_SCAN_BASE="$MID"
git -C "$R" remote add origin "$(mk_tmp)/o.git"
lc_streams --unpushed "$NEW" --remote origin
assert_eq "B7 a configured remote name does not use the escape: its own refs limit it (nothing owned: all), exit 1" "1" "$RC"
assert_contains "B7 ... the old secret is still found" "$STD" "old.txt:1: github-token"
lc_streams --unpushed "$NEW"
assert_contains "B8 no --remote: the escape is not used either" "$STD" "old.txt:1: github-token"
unset PB_LEAK_SCAN_BASE
t_summary
