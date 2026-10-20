#!/usr/bin/env bash
# Tests for scripts/leak-check.sh, part 3b (the second half of test-leak-check-push.sh, split in v0.24.19 so that it is not the floor of a CI shard), from
# "v0.23.3 lane A review round 4 N6" to the end (remotes with several urls, the pushurl chain, the note wording, PB_LEAK_SCAN_BASE).
# Shared setup: leak-check-fixture.sh, leak-check-push-fixture.sh. This repo is public: every secret below is built at run time from pieces.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/leak-check-fixture.sh"
. "$(dirname "$0")/leak-check-push-fixture.sh"
# the global conf and the environment as the earlier sections of the unsplit suite left them
conf_global "leak_literals=$EML"
unset PB_ALLOW_MODE_CHANGE

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
# review round 1 MINOR-5: pub is no configured remote at all, so the note keeps the plain wording (no 'fully owns / push places differ')
assert_contains "M2: the note says origin pushes to a place no configured remote owns" "$OUT" "origin pushes to a place no configured remote owns; scanning the full range"
assert_not_contains "M2: the note does not use the chain wording" "$OUT" "fully owns"

echo "v0.24.9 pushurl chain: origin's pushurl is remote fork's url, and fork's own pushurl is pub; the secret is on refs/remotes/fork/* only"
# fork is configured, but it pushes elsewhere (pub), so its refs do not cover what origin's push reaches: the conservative full scan stays,
# and the note must not claim that no configured remote owns the place (fork does; its push places differ).
pfix fork
git -C "$R" config remote.fork.pushurl "$PUB"
git -C "$R" config remote.origin.pushurl "$FORK"
run_in "$R" git push origin feat
if [ "$RC" != 0 ]; then t_ok "CH1: git push origin feat (origin pushurl fork, fork pushurl pub) is refused (exit $RC)"; else t_bad "CH1: git push origin feat (origin pushurl fork, fork pushurl pub) is refused" "exit 0; output: $OUT"; fi
assert_contains "CH1: the hook shows the finding" "$OUT" "s.txt:1: github-token"
if holds_secret "$PUB"; then t_bad "CH1: pub did not receive the secret commit" "object is on pub"; else t_ok "CH1: pub did not receive the secret commit"; fi
assert_contains "CH1: the note says origin pushes to a place that no configured remote fully owns (its push places differ)" "$OUT" "origin pushes to a place that no configured remote fully owns (its push places differ); scanning the full range"
assert_not_contains "CH1: the note does not say 'no configured remote owns' (fork is configured)" "$OUT" "no configured remote owns"

# ---- v0.24.12: the note wording in leak-check.sh (v0.24.9 review round 2 mutants L3-L5): each case asserts the exact wording, the exit code and the finding ----
# the two wordings of the note when origin's push goes to another place
LC_PLAIN="origin pushes to a place no configured remote owns; scanning the full range"
LC_CHAIN="origin pushes to a place that no configured remote fully owns (its push places differ); scanning the full range"

echo "v0.24.12 L3 origin's pushurl is remote fork's url, and url.<pub>.pushInsteadOf rewrites that url: git pushes to pub, the note keeps the plain wording"
# push_rewritten must veto the chain wording: fork is a configured remote with that url, but the push does not go there.
pfix fork
git -C "$R" config remote.origin.pushurl "$FORK"
git -C "$R" config "url.$PUB.pushInsteadOf" "$FORK"
lc_streams --unpushed "$PSEC" --remote origin
assert_eq "L3: the secret is on fork only and the push goes to pub: scanned, exit 1" "1" "$RC"
assert_contains "L3: the finding is named" "$STD" "s.txt:1: github-token"
assert_contains "L3: the note says origin pushes to a place no configured remote owns" "$ERR" "$LC_PLAIN"
assert_not_contains "L3: the note does not use the chain wording" "$ERR" "fully owns"

echo "v0.24.12 L4 origin has urls priv and pub and pushurl pub (its own second url): no other remote owns pub, the note keeps the plain wording"
# place_known must skip the remote being asked about: origin's own url list holds pub, which is no other remote's place.
pfix origin
git -C "$R" config --add remote.origin.url "$PUB"
git -C "$R" config remote.origin.pushurl "$PUB"
lc_streams --unpushed "$PSEC" --remote origin
assert_eq "L4: the secret is on origin/main, the push goes to pub: scanned, exit 1" "1" "$RC"
assert_contains "L4: the finding is named" "$STD" "s.txt:1: github-token"
assert_contains "L4: the note says origin pushes to a place no configured remote owns" "$ERR" "$LC_PLAIN"
assert_not_contains "L4: the note does not use the chain wording (origin is not its own owner)" "$ERR" "fully owns"

echo "v0.24.12 L5 pushurl chain where fork's url is spelled through url.<base>.insteadOf: fork still owns the place, the note uses the chain wording"
# place_known must compare the insteadOf-expanded urls too: fork's raw url is 'short:fork.git', only `git remote get-url` expands it.
pfix fork
git -C "$R" config "url.${FORK%/*}/.insteadOf" "short:"
git -C "$R" config remote.fork.url "short:fork.git"
git -C "$R" config remote.fork.pushurl "$PUB"
git -C "$R" config remote.origin.pushurl "$FORK"
lc_streams --unpushed "$PSEC" --remote origin
assert_eq "L5: the secret is on fork only, origin pushes to fork's expanded url, fork pushes to pub: scanned, exit 1" "1" "$RC"
assert_contains "L5: the finding is named" "$STD" "s.txt:1: github-token"
assert_contains "L5: the note says origin pushes to a place that no configured remote fully owns (its push places differ)" "$ERR" "$LC_CHAIN"
assert_not_contains "L5: the note does not say 'no configured remote owns' (fork is configured)" "$ERR" "no configured remote owns"

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
assert_contains "B2 ... stderr names the resolved base sha" "$ERR" "after $MID"
assert_contains "B2 ... and the number of commits scanned (1: NEW)" "$ERR" "scanning 1 commit"
assert_not_contains "B2 ... the 'scanning the full range' note is not printed when the escape is used (review F4)" "$ERR" "scanning the full range"
lc_streams --unpushed "$MID" --remote "$U_X"
assert_eq "B3 base=MID with SHA=MID (an empty range): exit 3, never a clean pass" "3" "$RC"
assert_contains "B3 ... says there is nothing to scan and to unset the variable" "$ERR" "nothing to scan; unset PB_LEAK_SCAN_BASE"
assert_not_contains "B3 ... is not reported clean" "$STD" "leak-check: clean"
export PB_LEAK_SCAN_BASE="$NEW"
lc_streams --unpushed "$MID" --remote "$U_X"
assert_eq "B3b SHA is an ANCESTOR of base (an empty range too): exit 3" "3" "$RC"
assert_contains "B3b ... nothing to scan; unset PB_LEAK_SCAN_BASE" "$ERR" "nothing to scan; unset PB_LEAK_SCAN_BASE"
assert_not_contains "B3b ... is not reported clean" "$STD" "leak-check: clean"
export PB_LEAK_SCAN_BASE="$OLD"
lc_streams --unpushed "$NEW" --remote "$U_X"
assert_not_contains "B4 base=OLD: the base commit itself is excluded" "$STD" "old.txt"
assert_contains "B4 ... the newer secret is found" "$STD" "new.txt:1: aws-key"
assert_contains "B4 ... stderr names the base sha and the 2 commits scanned (MID, NEW)" "$ERR" "scanning 2 commits after $OLD"
assert_not_contains "B4 ... no 'scanning the full range' note (review F4)" "$ERR" "scanning the full range"
export PB_LEAK_SCAN_BASE="nosuchref-$$"
lc_streams --unpushed "$NEW" --remote "$U_X"
assert_eq "B5 a bad ref: exit 3, never a silent fallback" "3" "$RC"
assert_contains "B5 ... the message names the variable and the ref" "$ERR" "PB_LEAK_SCAN_BASE"
assert_contains "B5 ... and the ref" "$ERR" "nosuchref-$$"
assert_not_contains "B5 ... nothing is scanned" "$STD" "github-token"
# review F1: the base must be a full 40-hex commit id; a name or an expression can move or be rewritten between the check and the push
git -C "$R" branch -q feat2 "$NEW" 2>/dev/null
for bad in main HEAD~1 '@{-1}' 'feat2~0' "${MID:0:7}" "${MID:0:12}" "$(printf '%s' "$MID" | tr 'a-f' 'A-F')x" '--all'; do
  export PB_LEAK_SCAN_BASE="$bad"
  lc_streams --unpushed "$NEW" --remote "$U_X"
  assert_eq "F1 base [$bad] is not a full commit id: exit 3" "3" "$RC"
  assert_contains "F1 ... the message says a full commit id is required" "$ERR" "full commit id"
  assert_not_contains "F1 ... nothing is scanned or reported" "$STD" "github-token"
done
# a 40-hex value that names no commit: still exit 3 and never a fallback
export PB_LEAK_SCAN_BASE="$(printf 'd%.0s' $(seq 40))"
lc_streams --unpushed "$NEW" --remote "$U_X"
assert_eq "F1 a well-formed 40-hex id that is no commit here: exit 3" "3" "$RC"
assert_contains "F1 ... names the variable" "$ERR" "PB_LEAK_SCAN_BASE"
assert_not_contains "F1 ... nothing is scanned" "$STD" "github-token"
# review F4: a value with control characters is never echoed raw
export PB_LEAK_SCAN_BASE="$(printf 'feat2\033[2K\rX')"
lc_streams --unpushed "$NEW" --remote "$U_X"
assert_eq "F4 a base with control characters: exit 3" "3" "$RC"
case "$ERR$STD" in *"$(printf '\033')"*) t_bad "F4 ... no raw ESC byte reaches the output" "an ESC byte was echoed" ;; *) t_ok "F4 ... no raw ESC byte reaches the output" ;; esac
case "$ERR$STD" in *"$(printf '\r')"*) t_bad "F4 ... no raw CR byte reaches the output" "a CR byte was echoed" ;; *) t_ok "F4 ... no raw CR byte reaches the output" ;; esac
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

echo "v0.24.4 review round 2 N3: PB_LEAK_SCAN_BASE must be an ancestor of the pushed commit"
newrepo
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
U_N="$(mk_tmp)/n.git"
stage "$R" a.txt "clean a"; G -C "$R" commit -q --no-verify -m 'A'
N_A="$(git -C "$R" rev-parse HEAD)"
stage "$R" s.txt "k $GH"; G -C "$R" commit -q --no-verify -m 'S secret'
N_S="$(git -C "$R" rev-parse HEAD)"
stage "$R" t.txt "clean t"; G -C "$R" commit -q --no-verify -m 'T'
N_T="$(git -C "$R" rev-parse HEAD)"
git -C "$R" checkout -q -b side "$N_S"
stage "$R" x.txt "clean x"; G -C "$R" commit -q --no-verify -m 'X side'
N_X="$(git -C "$R" rev-parse HEAD)"
git -C "$R" checkout -q main
export PB_LEAK_SCAN_BASE="$N_X"
lc_streams --unpushed "$N_T" --remote "$U_N"
assert_eq "N3 base X is on a side branch (not an ancestor of T): exit 3" "3" "$RC"
assert_contains "N3 ... the message says not an ancestor" "$ERR" "not an ancestor"
assert_not_contains "N3 ... is not reported clean" "$STD$ERR" "leak-check: clean"
export PB_LEAK_SCAN_BASE="$N_A"
lc_streams --unpushed "$N_T" --remote "$U_N"
assert_eq "N3 control: base A is an ancestor of T: the range A..T is scanned, the secret in S is found, exit 1" "1" "$RC"
assert_contains "N3 control: ... named" "$STD" "s.txt:1: github-token"
export PB_LEAK_SCAN_BASE="$N_S"
lc_streams --unpushed "$N_T" --remote "$U_N"
assert_eq "N3 control: base S is an ancestor of T: only T is scanned, exit 0" "0" "$RC"
unset PB_LEAK_SCAN_BASE

echo "v0.24.4 review round 2 N2: the usage says PB_LEAK_SCAN_BASE takes a full commit id, not a REF"
newrepo
run_in "$R" bash "$LC"
assert_rc "N2 usage: no arguments, exit 2" 2
assert_contains "N2 the usage says a full commit id" "$OUT" "full commit id"
assert_not_contains "N2 the usage no longer says PB_LEAK_SCAN_BASE=REF" "$OUT" "PB_LEAK_SCAN_BASE=REF"

echo "v0.24.4 review F1 through the installed pre-push hook: a branch name as the base can never wave a secret through"
newrepo
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
run_in "$R" bash "$LC" install-hooks
assert_rc "P4 hook setup: install-hooks exit 0" 0
HDEST="$(mk_tmp)/hd.git"; git init -q --bare "$HDEST"
git -C "$R" checkout -q -b feat2
stage "$R" h.txt "k $GH"; G -C "$R" commit -q --no-verify -m 'secret on feat2'
HSEC="$(git -C "$R" rev-parse HEAD)"
git -C "$R" checkout -q main
git -C "$R" merge -q --ff-only feat2
# main now points at the secret commit; base=main resolves to the very commit being pushed (an empty range, clean by accident)
run_in "$R" env PB_LEAK_SCAN_BASE=main git push "$HDEST" "main:refs/heads/viabase"
if [ "$RC" != 0 ]; then t_ok "P4 base=main (a branch name), main fast-forwarded onto the secret branch: the push is refused (exit $RC)"; else t_bad "P4 base=main: the push is refused" "exit 0; output: $OUT"; fi
assert_not_contains "P4 ... the push is not reported clean" "$OUT" "leak-check: clean"
assert_contains "P4 ... the refusal says a full commit id is required" "$OUT" "full commit id"
if git -C "$HDEST" cat-file -e "$HSEC" 2>/dev/null; then t_bad "P4 ... the secret commit did not reach the destination" "object is there"; else t_ok "P4 ... the secret commit did not reach the destination"; fi
if git -C "$HDEST" rev-parse --verify -q refs/heads/viabase >/dev/null; then t_bad "P4 ... the branch did not reach the destination" "viabase exists"; else t_ok "P4 ... the branch did not reach the destination"; fi
# P2 through the hook: a full sha equal to the pushed commit is an empty range: refused, not clean
run_in "$R" env PB_LEAK_SCAN_BASE="$HSEC" git push "$HDEST" "main:refs/heads/viaempty"
if [ "$RC" != 0 ]; then t_ok "P2 base = the pushed commit (an empty range): the push is refused (exit $RC)"; else t_bad "P2 base = the pushed commit: the push is refused" "exit 0; output: $OUT"; fi
assert_contains "P2 ... nothing to scan; unset PB_LEAK_SCAN_BASE" "$OUT" "nothing to scan; unset PB_LEAK_SCAN_BASE"
if git -C "$HDEST" cat-file -e "$HSEC" 2>/dev/null; then t_bad "P2 ... the secret commit did not reach the destination" "object is there"; else t_ok "P2 ... the secret commit did not reach the destination"; fi
# a full sha taken BEFORE the secret commit still scans it: refused with the finding
HBASE="$(git -C "$R" rev-parse "${HSEC}~1" 2>/dev/null || git -C "$R" rev-list --max-parents=0 HEAD)"
run_in "$R" env PB_LEAK_SCAN_BASE="$HBASE" git push "$HDEST" "main:refs/heads/viasha"
if [ "$RC" != 0 ]; then t_ok "P4c a full sha base before the secret commit: the push is refused (exit $RC)"; else t_bad "P4c a full sha base before the secret commit: refused" "exit 0; output: $OUT"; fi
assert_contains "P4c ... the finding is shown" "$OUT" "h.txt:1: github-token"
if git -C "$HDEST" cat-file -e "$HSEC" 2>/dev/null; then t_bad "P4c ... the secret commit did not reach the destination" "object is there"; else t_ok "P4c ... the secret commit did not reach the destination"; fi
t_summary
