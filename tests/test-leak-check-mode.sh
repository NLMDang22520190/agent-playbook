#!/usr/bin/env bash
# Tests for scripts/leak-check.sh, part 2 of 3 (split from test-leak-check.sh in v0.24.1): the v0.23.2 sections (the mode check of scan --staged,
# the ownership of remote refs, bounded argv, odd path names) and their review rounds. Shared setup: leak-check-fixture.sh.
# This repo is public: every secret below is built at run time from pieces, so no scanner finds a literal in this file.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/leak-check-fixture.sh"
# the global conf and the environment as the earlier sections of the unsplit suite left them
conf_global "leak_literals=$EML"
unset PB_ALLOW_MODE_CHANGE

# ---- v0.23.2 AC1.2: scan --staged refuses a lost executable bit and warns about a new #! file at 100644 ----
echo "v0.23.2 AC1.2 scan --staged: a staged 100755 -> 100644 is refused"
unset PB_ALLOW_MODE_CHANGE
MODEMSG="VIOLATION (mode): bin/run.sh lost its executable bit (100755 -> 100644)"
modrepo
assert_eq "AC1.2 fixture: bin/run.sh is committed 100755" "100755" "$(git -C "$R" ls-files -s -- bin/run.sh | cut -d' ' -f1)"
git -C "$R" update-index --chmod=-x -- bin/run.sh
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.2 a staged mode drop is refused: exit 1" 1
assert_contains "AC1.2 the refusal names the path and both modes" "$OUT" "$MODEMSG"
run_in "$R" env PB_ALLOW_MODE_CHANGE=bin/run.sh bash "$LC" scan --staged
assert_rc "AC1.2 PB_ALLOW_MODE_CHANGE=bin/run.sh lets it pass: exit 0" 0
assert_contains "AC1.2 ... and says clean" "$OUT" "leak-check: clean"
run_in "$R" env PB_ALLOW_MODE_CHANGE=docs/a.sh:bin/run.sh:x bash "$LC" scan --staged
assert_rc "AC1.2 a colon list containing the path passes" 0
for bad in bin "bin/*" run.sh "bin/run.sh.bak" "bin/run" "/bin/run.sh" ""; do
  run_in "$R" env PB_ALLOW_MODE_CHANGE="$bad" bash "$LC" scan --staged
  assert_rc "AC1.2 allow entry [$bad] is not an exact match: exit 1" 1
  assert_contains "AC1.2 allow entry [$bad]: the path is still reported" "$OUT" "$MODEMSG"
done
# two drops, one allowed
git -C "$R" update-index --chmod=-x -- bin/other.sh
run_in "$R" env PB_ALLOW_MODE_CHANGE=bin/run.sh bash "$LC" scan --staged
assert_rc "AC1.2 one of two drops allowed: exit 1" 1
assert_contains "AC1.2 the unlisted drop is reported" "$OUT" "VIOLATION (mode): bin/other.sh lost its executable bit (100755 -> 100644)"
assert_not_contains "AC1.2 the listed drop is not reported" "$OUT" "VIOLATION (mode): bin/run.sh"
run_in "$R" env PB_ALLOW_MODE_CHANGE=bin/run.sh:bin/other.sh bash "$LC" scan --staged
assert_rc "AC1.2 both drops allowed: exit 0" 0
# the secret check still runs next to the mode check
stage "$R" cfg.txt "k $GH"
run_in "$R" env PB_ALLOW_MODE_CHANGE=bin/run.sh:bin/other.sh bash "$LC" scan --staged
assert_rc "AC1.2 the allowed mode drop does not hide a secret: exit 1" 1
assert_contains "AC1.2 ... the secret is named" "$OUT" "cfg.txt:1: github-token"
run_in "$R" bash "$LC" scan --staged

echo "v0.23.2 AC1.2 scan --staged: changes that are not a lost executable bit"
modrepo
printf 'changed\n' > "$R/notes.txt"; git -C "$R" add notes.txt
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.2 a never-executable file edited: exit 0" 0
assert_not_contains "AC1.2 ... no mode violation" "$OUT" "(mode)"
git -C "$R" update-index --chmod=+x -- notes.txt
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.2 gaining the executable bit (100644 -> 100755): exit 0" 0
assert_not_contains "AC1.2 ... gaining is no mode violation" "$OUT" "(mode)"
modrepo
git -C "$R" rm -q bin/run.sh
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.2 deleting an executable file: exit 0" 0
assert_not_contains "AC1.2 ... deleting is no mode violation" "$OUT" "(mode)"
modrepo
printf '#!/bin/sh\necho ok\n' > "$R/bin/run.sh"; git -C "$R" add bin/run.sh
run_in "$R" bash "$LC" scan --staged
assert_rc "AC1.2 an executable file edited and still 100755: exit 0" 0
assert_not_contains "AC1.2 ... no mode violation" "$OUT" "(mode)"

echo "v0.23.2 AC1.2 scan --staged: a new staged #! file at 100644 is a warning, not a refusal"
modrepo
stage "$R" bin/new.sh '#!/bin/sh' 'echo new'
git -C "$R" update-index --chmod=-x -- bin/new.sh
scan_streams
assert_eq "AC1.2 the exit code is unchanged (0)" "0" "$RC"
assert_contains "AC1.2 stdout still says clean" "$STD" "leak-check: clean"
assert_contains "AC1.2 the warning is on stderr and names the path" "$ERR" "bin/new.sh"
assert_contains "AC1.2 the warning says warning" "$(printf '%s' "$ERR" | tr 'A-Z' 'a-z')" "warning"
assert_not_contains "AC1.2 the warning is not on stdout" "$STD" "bin/new.sh"
modrepo
stage "$R" bin/new.sh '#!/bin/sh' 'echo new'
git -C "$R" update-index --chmod=+x -- bin/new.sh
scan_streams
assert_eq "AC1.2 a new #! file at 100755: exit 0" "0" "$RC"
assert_not_contains "AC1.2 a new #! file at 100755: no warning" "$ERR" "bin/new.sh"
modrepo
stage "$R" docs/new.txt 'just text' '#!/bin/sh'
scan_streams
assert_not_contains "AC1.2 a new 100644 file without #! on line 1: no warning" "$ERR" "docs/new.txt"
modrepo
stage "$R" docs/plain.txt 'just text'
scan_streams
assert_not_contains "AC1.2 a new plain file: no warning" "$ERR" "docs/plain.txt"
modrepo
printf '#!/bin/sh\necho changed\n' > "$R/notes.txt"; git -C "$R" add notes.txt
scan_streams
assert_not_contains "AC1.2 an existing file that gains a #! line (not newly added): no warning" "$ERR" "notes.txt"
modrepo
stage "$R" bin/new.sh '#!/bin/sh' "token = $GH"
git -C "$R" update-index --chmod=-x -- bin/new.sh
scan_streams
assert_eq "AC1.2 a warning does not hide a secret: exit 1" "1" "$RC"
assert_contains "AC1.2 ... the finding is named" "$STD" "bin/new.sh:2: github-token"

echo "v0.23.2 AC1.2 the installed pre-commit hook is unchanged and still enforces the mode check"
modrepo
HOOKS="$R/.git/hooks"
run_in "$R" bash "$LC" install-hooks
assert_rc "AC1.2 install-hooks: exit 0" 0
assert_contains "AC1.2 the hook body still ends with 'exec bash \"\$LC\" scan --staged'" "$(tail -n 1 "$HOOKS/pre-commit" 2>/dev/null)" 'exec bash "$LC" scan --staged'
assert_not_contains "AC1.2 the hook body carries no mode logic of its own (100755)" "$(cat "$HOOKS/pre-commit" 2>/dev/null)" "100755"
assert_not_contains "AC1.2 the hook body carries no mode logic of its own (ls-files)" "$(cat "$HOOKS/pre-commit" 2>/dev/null)" "ls-files"
assert_not_contains "AC1.2 the hook body does not mention PB_ALLOW_MODE_CHANGE" "$(cat "$HOOKS/pre-commit" 2>/dev/null)" "PB_ALLOW_MODE_CHANGE"
head1="$(git -C "$R" rev-parse HEAD)"
git -C "$R" update-index --chmod=-x -- bin/run.sh
run_in "$R" git -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false commit -q -m 'drop the bit'
if [ "$RC" != 0 ]; then t_ok "AC1.2 the installed hook refuses a commit that drops the exec bit (exit $RC)"; else t_bad "AC1.2 the installed hook refuses a commit that drops the exec bit" "exit 0; output: $OUT"; fi
assert_contains "AC1.2 the hook output names the lost bit" "$OUT" "$MODEMSG"
assert_eq "AC1.2 the refused commit was not created" "$head1" "$(git -C "$R" rev-parse HEAD)"
run_in "$R" env PB_ALLOW_MODE_CHANGE=bin/run.sh git -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false commit -q -m 'deliberate'
assert_rc "AC1.2 the environment escape reaches the hook: the commit goes through" 0
assert_eq "AC1.2 the deliberate commit exists" "deliberate" "$(git -C "$R" log -1 --format=%s)"
assert_eq "AC1.2 the committed mode is now 100644" "100644" "$(git -C "$R" ls-files -s -- bin/run.sh | cut -d' ' -f1)"

# ---- v0.23.2 AC7.1: --remote NAME owns the refs of its fetch refspec (longest destination wins) ----
echo "v0.23.2 AC7.1 without a configured remote origin/foo, refs/remotes/origin/foo/x belongs to origin"
newrepo
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
RO="$(mk_tmp)/o.git"; RF="$(mk_tmp)/f.git"
git init -q --bare "$RO"; git init -q --bare "$RF"
git -C "$R" remote add origin "$RO"
git -C "$R" checkout -q -b sec
stage "$R" s.txt "k $GH"; G -C "$R" commit -q --no-verify -m 'secret on origin/foo/x'
SEC="$(git -C "$R" rev-parse HEAD)"
git -C "$R" update-ref refs/remotes/origin/foo/x "$SEC"
run_in "$R" bash "$LC" scan --unpushed "$SEC" --remote origin
assert_rc "AC7.1 origin/foo/x is origin's own branch foo/x: not scanned when pushing to origin: exit 0" 0
assert_contains "AC7.1 ... says clean" "$OUT" "leak-check: clean"
run_in "$R" bash "$LC" scan --unpushed "$SEC"
assert_rc "AC7.1 without --remote any remote counts: exit 0" 0

echo "v0.23.2 AC7.1 with a configured remote origin/foo, its commits are scanned when pushing to origin"
git -C "$R" update-ref -d refs/remotes/origin/foo/x
git -C "$R" push -q "$RF" sec:main
# newer git refuses `remote add origin/foo` when origin exists ("subset of existing remote"); such remotes still
# exist through config (older git, hand edits), so the fixture writes the config directly
git -C "$R" config remote.origin/foo.url "$RF"
git -C "$R" config remote.origin/foo.fetch '+refs/heads/*:refs/remotes/origin/foo/*'
git -C "$R" update-ref refs/remotes/origin/foo/main "$SEC"
assert_eq "AC7.1 fixture: refs/remotes/origin/foo/main holds the secret commit" "$SEC" "$(git -C "$R" rev-parse --verify -q refs/remotes/origin/foo/main 2>/dev/null)"
run_in "$R" bash "$LC" scan --unpushed "$SEC" --remote origin
assert_rc "AC7.1 a commit only on remote origin/foo IS scanned when pushing to origin: exit 1" 1
assert_contains "AC7.1 ... the finding is named" "$OUT" "s.txt:1: github-token"
run_in "$R" bash "$LC" scan --unpushed "$SEC" --remote origin/foo
assert_rc "AC7.1 the same commit is skipped when pushing to origin/foo itself: exit 0" 0
assert_contains "AC7.1 ... says clean" "$OUT" "leak-check: clean"
run_in "$R" bash "$LC" scan --unpushed "$SEC"
assert_rc "AC7.1 without --remote any remote still counts: exit 0" 0

echo "v0.23.2 AC7.1 the longest matching destination wins (origin's own foo/x counts as origin/foo's)"
git -C "$R" checkout -q -b sec2 main
stage "$R" s2.txt "k $AWS"; G -C "$R" commit -q --no-verify -m 'secret 2'
SEC2="$(git -C "$R" rev-parse HEAD)"
git -C "$R" update-ref refs/remotes/origin/foo/x "$SEC2"
run_in "$R" bash "$LC" scan --unpushed "$SEC2" --remote origin
assert_rc "AC7.1 refs/remotes/origin/foo/x belongs to origin/foo now: scanned for origin: exit 1" 1
assert_contains "AC7.1 ... the finding is named" "$OUT" "s2.txt:1: aws-key"
run_in "$R" bash "$LC" scan --unpushed "$SEC2" --remote origin/foo
assert_rc "AC7.1 ... and skipped for origin/foo: exit 0" 0
git -C "$R" checkout -q -b sec3 main
stage "$R" s3.txt "k $GHS"; G -C "$R" commit -q --no-verify -m 'secret 3'
SEC3="$(git -C "$R" rev-parse HEAD)"
git -C "$R" update-ref refs/remotes/origin/main "$SEC3"
run_in "$R" bash "$LC" scan --unpushed "$SEC3" --remote origin
assert_rc "AC7.1 an ordinary origin ref (origin/main) is still skipped for origin: exit 0" 0
run_in "$R" bash "$LC" scan --unpushed "$SEC3" --remote origin/foo
assert_rc "AC7.1 ... and scanned for origin/foo: exit 1" 1
assert_contains "AC7.1 ... the finding is named" "$OUT" "s3.txt:1: github-token"

echo "v0.23.2 AC7.1 the help states the consequence"
run_in "$R" bash "$LC" scan
assert_rc "AC7.1 no scan arguments: usage, exit 2" 2
assert_contains "AC7.1 the usage text names the origin/foo case" "$OUT" "origin/foo"
assert_contains "AC7.1 the usage text says the nested ref is scanned too" "$(printf '%s' "$OUT" | tr 'A-Z' 'a-z')" "scanned"


# ---- v0.23.2 fix round (lane A): bounded argv, implicit remote ownership, renamed and odd-named mode drops ----
# gitshim DIR -> DIR/git, a wrapper that logs every call. GIT_SHIM_LOG gets one line per call: "<argc> <subcommand-ish first word>".
# GIT_SHIM_MAXARGS (when set) makes a call with more arguments fail like a too-long command line (exit 126).
gitshim() {
  local real; real="$(command -v git)"
  mkdir -p "$1"
  cat > "$1/git" <<SHIM
#!/bin/sh
echo "\$# \$1" >> "\${GIT_SHIM_LOG:-/dev/null}"
if [ -n "\${GIT_SHIM_MAXARGS:-}" ] && [ "\$#" -gt "\$GIT_SHIM_MAXARGS" ]; then
  echo "shim: Argument list too long" >&2
  exit 126
fi
exec "$real" "\$@"
SHIM
  chmod +x "$1/git"
}
# shim_max LOG -> the largest argc in the log
shim_max() { awk 'BEGIN { m = 0 } $1 + 0 > m { m = $1 + 0 } END { print m }' "$1"; }
SHIMD="$(mk_tmp)/shim"; gitshim "$SHIMD"

echo "v0.23.2 fix MAJOR-1 scan --unpushed SHA --remote NAME with ~1200 remote refs keeps the command line bounded"
newrepo
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
RO="$(mk_tmp)/o.git"; git init -q --bare "$RO"
git -C "$R" remote add origin "$RO"
BASE_SHA="$(git -C "$R" rev-parse HEAD)"
git -C "$R" checkout -q -b sec
stage "$R" s.txt "k $GH"; G -C "$R" commit -q --no-verify -m 'local only secret'
SEC="$(git -C "$R" rev-parse HEAD)"
UR="$(mk_tmp)/refs.txt"
awk -v s="$BASE_SHA" 'BEGIN { for (i = 1; i <= 1200; i++) printf "create refs/remotes/origin/feature/some-long-branch-name-%d %s\n", i, s }' > "$UR"
git -C "$R" update-ref --stdin < "$UR"
assert_eq "MAJOR-1 fixture: 1200 long remote refs exist" "1200" "$(git -C "$R" for-each-ref refs/remotes/origin/feature | wc -l | tr -d ' ')"
# v0.23.3 AC1b: 1200 refs are enough: as one command line they are longer than the 32768 characters of a Windows command line
REFCHARS="$(git -C "$R" for-each-ref --format='%(refname)' refs/remotes/origin/feature | awk '{ n += length($0) + 1 } END { print n + 0 }')"
assert_eq "MAJOR-1 fixture: the 1200 ref names alone are over 32768 characters on a command line (computed: ${REFCHARS})" "ok" "$([ "$REFCHARS" -gt 32768 ] && echo ok || echo "only $REFCHARS")"
SLOG="$(mk_tmp)/shim.log"; : > "$SLOG"
run_in "$R" env PATH="$SHIMD:$PATH" GIT_SHIM_LOG="$SLOG" bash "$LC" scan --unpushed "$SEC" --remote origin
assert_rc "MAJOR-1 a local-only secret is found with 1200 remote refs: exit 1 (not 3)" 1
assert_contains "MAJOR-1 ... the finding is named" "$OUT" "s.txt:1: github-token"
assert_not_contains "MAJOR-1 ... no 'git log failed'" "$OUT" "git log failed"
assert_eq "MAJOR-1 no git call gets more than 50 arguments (Windows has a 32K command line)" "ok" "$([ "$(shim_max "$SLOG")" -le 50 ] && echo ok || echo "max argc $(shim_max "$SLOG")")"
: > "$SLOG"
run_in "$R" env PATH="$SHIMD:$PATH" GIT_SHIM_LOG="$SLOG" GIT_SHIM_MAXARGS=1000 bash "$LC" scan --unpushed "$SEC" --remote origin
assert_rc "MAJOR-1 with a 1000-argument limit on git calls the secret is still found: exit 1" 1
assert_not_contains "MAJOR-1 ... no 'git log failed' under the limit" "$OUT" "git log failed"
# a commit that IS on a ref of origin is still skipped
run_in "$R" bash "$LC" scan --unpushed "$BASE_SHA" --remote origin
assert_rc "MAJOR-1 a commit on one of the 1200 refs is skipped: exit 0" 0

echo "v0.23.2 fix MAJOR-2a a remote without a fetch line still owns refs/remotes/NAME/*"
newrepo
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
RO="$(mk_tmp)/o.git"; RF="$(mk_tmp)/f.git"; git init -q --bare "$RO"; git init -q --bare "$RF"
git -C "$R" remote add origin "$RO"
# newer git refuses `remote add origin/foo` when origin exists ("subset of existing remote"); such remotes still
# exist through config (older git, hand edits), so the fixture writes the config directly
git -C "$R" config remote.origin/foo.url "$RF"
git -C "$R" config remote.origin/foo.fetch '+refs/heads/*:refs/remotes/origin/foo/*'
git -C "$R" config --unset remote.origin/foo.fetch
assert_eq "MAJOR-2a fixture: origin/foo has no fetch line" "" "$(git -C "$R" config --get-all remote.origin/foo.fetch)"
assert_contains "MAJOR-2a fixture: origin keeps its standard fetch line" "$(git -C "$R" config --get-all remote.origin.fetch)" "refs/remotes/origin/*"
git -C "$R" checkout -q -b sec
stage "$R" s.txt "k $GH"; G -C "$R" commit -q --no-verify -m 'secret only on origin/foo/main'
SEC="$(git -C "$R" rev-parse HEAD)"
git -C "$R" update-ref refs/remotes/origin/foo/main "$SEC"
run_in "$R" bash "$LC" scan --unpushed "$SEC" --remote origin
assert_rc "MAJOR-2a a commit only on fetch-less remote origin/foo IS scanned when pushing to origin: exit 1" 1
assert_contains "MAJOR-2a ... the finding is named" "$OUT" "s.txt:1: github-token"
run_in "$R" bash "$LC" scan --unpushed "$SEC" --remote origin/foo
assert_rc "MAJOR-2a ... and skipped when pushing to origin/foo itself (MAJOR-2c): exit 0" 0
run_in "$R" bash "$LC" scan --unpushed "$SEC"
assert_rc "MAJOR-2a without --remote any remote counts: exit 0" 0

echo "v0.23.2 fix MAJOR-2a variant: remote o owns refs/remotes/o*, remote o2 has no fetch line"
newrepo
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
RO="$(mk_tmp)/o.git"; R2="$(mk_tmp)/o2.git"; git init -q --bare "$RO"; git init -q --bare "$R2"
git -C "$R" remote add o "$RO"
git -C "$R" config --replace-all remote.o.fetch '+refs/heads/*:refs/remotes/o*'
git -C "$R" remote add o2 "$R2"
git -C "$R" config --unset remote.o2.fetch
git -C "$R" checkout -q -b sec
stage "$R" s.txt "k $GHS"; G -C "$R" commit -q --no-verify -m 'secret only on o2/main'
SEC="$(git -C "$R" rev-parse HEAD)"
git -C "$R" update-ref refs/remotes/o2/main "$SEC"
run_in "$R" bash "$LC" scan --unpushed "$SEC" --remote o
assert_rc "MAJOR-2a variant: a commit only on fetch-less remote o2 IS scanned when pushing to o: exit 1" 1
assert_contains "MAJOR-2a variant: ... the finding is named" "$OUT" "s.txt:1: github-token"
run_in "$R" bash "$LC" scan --unpushed "$SEC" --remote o2
assert_rc "MAJOR-2a variant: ... and skipped when pushing to o2: exit 0" 0

echo "v0.23.2 fix MAJOR-2b a tie between two remotes: the ref is scanned when pushing to either, in either config order"
for order in "ta tb" "tb ta"; do
  newrepo
  git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
  for rn in $order; do
    RT="$(mk_tmp)/$rn.git"; git init -q --bare "$RT"
    git -C "$R" remote add "$rn" "$RT"
    git -C "$R" config --replace-all "remote.$rn.fetch" '+refs/heads/*:refs/remotes/shared/*'
  done
  git -C "$R" checkout -q -b sec
  stage "$R" s.txt "k $AWS"; G -C "$R" commit -q --no-verify -m 'secret on the tied ref'
  SEC="$(git -C "$R" rev-parse HEAD)"
  git -C "$R" update-ref refs/remotes/shared/main "$SEC"
  run_in "$R" bash "$LC" scan --unpushed "$SEC" --remote ta
  assert_rc "MAJOR-2b order [$order]: scanned when pushing to ta: exit 1" 1
  assert_contains "MAJOR-2b order [$order]: ta: the finding is named" "$OUT" "s.txt:1: aws-key"
  run_in "$R" bash "$LC" scan --unpushed "$SEC" --remote tb
  assert_rc "MAJOR-2b order [$order]: scanned when pushing to tb: exit 1" 1
  assert_contains "MAJOR-2b order [$order]: tb: the finding is named" "$OUT" "s.txt:1: aws-key"
done

echo "v0.23.2 fix MAJOR-2c a fetch-less remote owns refs/remotes/NAME/*: its commits are not re-scanned when pushing to it"
newrepo
git -C "$R" checkout -q -b main 2>/dev/null || git -C "$R" branch -q -M main
RO="$(mk_tmp)/o.git"; RN="$(mk_tmp)/n.git"; git init -q --bare "$RO"; git init -q --bare "$RN"
git -C "$R" remote add origin "$RO"
git -C "$R" remote add nofetch "$RN"
git -C "$R" config --unset remote.nofetch.fetch
git -C "$R" checkout -q -b sec
stage "$R" s.txt "k $ANT"; G -C "$R" commit -q --no-verify -m 'secret on nofetch/x'
SEC="$(git -C "$R" rev-parse HEAD)"
git -C "$R" update-ref refs/remotes/nofetch/x "$SEC"
run_in "$R" bash "$LC" scan --unpushed "$SEC" --remote nofetch
assert_rc "MAJOR-2c a commit already on refs/remotes/nofetch/x is skipped when pushing to nofetch: exit 0" 0
assert_contains "MAJOR-2c ... says clean" "$OUT" "leak-check: clean"
run_in "$R" bash "$LC" scan --unpushed "$SEC" --remote origin
assert_rc "MAJOR-2c ... but scanned when pushing to origin (not its ref): exit 1" 1

echo "v0.23.2 fix MINOR-5 a rename plus a mode drop is a lost executable bit (scan --staged)"
modrepo
git -C "$R" mv bin/run.sh bin/renamed.sh
chmod -x "$R/bin/renamed.sh" 2>/dev/null; git -C "$R" update-index --chmod=-x -- bin/renamed.sh
assert_eq "MINOR-5 fixture: bin/renamed.sh is staged 100644" "100644" "$(git -C "$R" ls-files -s -- bin/renamed.sh | cut -d' ' -f1)"
RENMSG="VIOLATION (mode): bin/renamed.sh lost its executable bit (100755 -> 100644)"
run_in "$R" bash "$LC" scan --staged
assert_rc "MINOR-5 rename + drop is refused: exit 1" 1
assert_contains "MINOR-5 the NEW path is named with both modes" "$OUT" "$RENMSG"
run_in "$R" env PB_ALLOW_MODE_CHANGE=bin/renamed.sh bash "$LC" scan --staged
assert_rc "MINOR-5 PB_ALLOW_MODE_CHANGE with the new path lets it pass: exit 0" 0
run_in "$R" env PB_ALLOW_MODE_CHANGE=bin/run.sh bash "$LC" scan --staged
assert_rc "MINOR-5 listing the OLD path does not let it pass: exit 1" 1
assert_contains "MINOR-5 ... the new path is still named" "$OUT" "$RENMSG"
modrepo
git -C "$R" rm -q bin/run.sh
stage "$R" bin/unrelated.sh '#!/bin/sh' 'echo different'
git -C "$R" update-index --chmod=-x -- bin/unrelated.sh
run_in "$R" bash "$LC" scan --staged
assert_not_contains "MINOR-5 a deleted 100755 path plus a 100644 path with a DIFFERENT blob is no mode violation" "$OUT" "(mode)"

echo "v0.23.2 fix LOW-6 paths with a double quote or a tab are reported with their real name and can be allowed"
modrepo
QP='bin/we"ird.sh'
TP="$(printf 'bin/ta\tb.sh')"
for P in "$QP" "$TP"; do
  if ( cd "$R" && cp bin/run.sh "$P" && git add -- "$P" ) 2>/dev/null && [ -f "$R/$P" ] && [ -n "$(git -C "$R" ls-files -- "$P")" ]; then
    ( cd "$R" && git update-index --chmod=+x -- "$P" && G commit -q -m "add odd name" )
    git -C "$R" update-index --chmod=-x -- "$P"
    run_in "$R" bash "$LC" scan --staged
    assert_rc "LOW-6 [$P] mode drop is refused: exit 1" 1
    assert_contains "LOW-6 [$P] the real path is printed unquoted" "$OUT" "VIOLATION (mode): $P lost its executable bit (100755 -> 100644)"
    run_in "$R" env PB_ALLOW_MODE_CHANGE="$P" bash "$LC" scan --staged
    assert_rc "LOW-6 [$P] PB_ALLOW_MODE_CHANGE with the real path lets it pass: exit 0" 0
    git -C "$R" update-index --chmod=+x -- "$P"
  else rm -f -- "$R/$P" 2>/dev/null; t_skip 3 "LOW-6 path [$P] (this file system or git refuses the name)"; fi
done
run_in "$R" bash "$LC" scan
assert_rc "LOW-6 usage: exit 2" 2
assert_contains "LOW-6 the usage says a path with a colon cannot be listed in PB_ALLOW_MODE_CHANGE" "$(printf '%s' "$OUT" | tr 'A-Z' 'a-z')" "cannot be listed"

echo "v0.23.2 fix LOW-7 a secret and a mode violation together: the summary counts both"
modrepo
git -C "$R" update-index --chmod=-x -- bin/run.sh
stage "$R" cfg.txt "k $GH"
run_in "$R" bash "$LC" scan --staged
assert_rc "LOW-7 secret + mode drop: exit 1" 1
assert_contains "LOW-7 the summary has the finding count" "$OUT" "1 finding(s)"
assert_contains "LOW-7 the summary has the mode violation count" "$OUT" "1 mode violation(s)"
assert_contains "LOW-7 the mode violation line is printed" "$OUT" "$MODEMSG"
assert_contains "LOW-7 the finding line is printed" "$OUT" "cfg.txt:1: github-token"
modrepo
git -C "$R" update-index --chmod=-x -- bin/run.sh
run_in "$R" bash "$LC" scan --staged
assert_contains "LOW-7 mode only: the summary still says 'no secret found'" "$OUT" "1 mode violation(s); no secret found"

echo "v0.23.2 fix MINOR-4 scan --staged does not run one git process per new staged file"
NF=1000
# mkmany DIR MODEFLAG -> DIR gets NF new files (#! first line) staged; MODEFLAG x makes them 100755
mkmany() {
  local d="$1" x="$2"
  mkdir -p "$d/gen"
  awk -v d="$d/gen" 'BEGIN { for (i = 1; i <= '"$NF"'; i++) { f = d "/f" i ".sh"; printf "#!/bin/sh\necho %d\n", i > f; close(f) } }'
  [ "$x" != x ] || chmod +x "$d"/gen/*.sh 2>/dev/null
  git -C "$d" add -A
}
# nsecs REPO LOG -> seconds the scan takes (stdout) ; LOG gets the git shim log
newrepo; RX="$R"; mkmany "$RX" x
newrepo; RN="$R"; mkmany "$RN" n
XMODES="$(git -C "$RX" ls-files -s -- gen | cut -c1-6 | sort -u | tr '\n' ' ')"
NMODES="$(git -C "$RN" ls-files -s -- gen | cut -c1-6 | sort -u | tr '\n' ' ')"
if [ "$XMODES" != "100755 " ] || [ "$NMODES" != "100644 " ]; then
  t_skip 7 "MINOR-4 (cannot stage 100755 / 100644 files here: [$XMODES] [$NMODES])"
else
  T0="$(date +%s)"; run_in "$RX" bash "$LC" scan --staged; XRC="$RC"; T1="$(date +%s)"
  run_in "$RN" bash "$LC" scan --staged; NRC="$RC"; T2="$(date +%s)"
  XT=$((T1 - T0)); NT=$((T2 - T1))
  assert_eq "MINOR-4 baseline (1000 new 100755 files) is clean: exit 0" "0" "$XRC"
  assert_eq "MINOR-4 1000 new 100644 #! files are clean (a warning only): exit 0" "0" "$NRC"
  assert_eq "MINOR-4 the 100644 scan takes under baseline + 10 s (baseline ${XT}s, took ${NT}s)" "ok" "$([ "$NT" -lt $((XT + 10)) ] && echo ok || echo "slow: ${NT}s vs baseline ${XT}s")"
  SLOGX="$(mk_tmp)/x.log"; SLOGN="$(mk_tmp)/n.log"; : > "$SLOGX"; : > "$SLOGN"
  run_in "$RX" env PATH="$SHIMD:$PATH" GIT_SHIM_LOG="$SLOGX" bash "$LC" scan --staged
  run_in "$RN" env PATH="$SHIMD:$PATH" GIT_SHIM_LOG="$SLOGN" bash "$LC" scan --staged
  assert_eq "MINOR-4 baseline: at most 10 git processes for 1000 new files" "ok" "$([ "$(wc -l < "$SLOGX" | tr -d ' ')" -le 10 ] && echo ok || echo "$(wc -l < "$SLOGX" | tr -d ' ') git calls")"
  assert_eq "MINOR-4 at most 10 git processes for 1000 new 100644 files (not one per file)" "ok" "$([ "$(wc -l < "$SLOGN" | tr -d ' ')" -le 10 ] && echo ok || echo "$(wc -l < "$SLOGN" | tr -d ' ') git calls")"
  assert_contains "MINOR-4 the #! warning is still printed for the 100644 files" "$OUT" "gen/f1.sh"
  assert_eq "MINOR-A all $NF new 100644 #! files are warned about, one line each" "$NF" "$(printf '%s\n' "$OUT" | grep -c 'warning: new file .* starts with #! ')"
fi

echo "v0.23.2 round 2 MINOR-A the one-pass #! warning keeps its byte count across a mixed batch"
# every blob's size decides where the next header starts: plain files with and without a trailing newline, an empty one,
# a CRLF #! file, a #! file right after an empty one, a #! file with no trailing newline, and a #! file last in the batch
newrepo
mkdir -p "$R/mix"
printf 'plain text\nsecond line\n' > "$R/mix/a01_plain.txt"
printf 'no trailing newline' > "$R/mix/a02_nonl.txt"
: > "$R/mix/a03_empty.txt"
printf '#!/bin/sh\r\necho crlf\r\n' > "$R/mix/a04_crlf.sh"
: > "$R/mix/a05_empty.txt"
printf '#!/bin/sh\necho after-empty\n' > "$R/mix/a06_after_empty.sh"
printf '#!/bin/sh' > "$R/mix/a07_shebang_nonl.sh"
printf 'x\n\n\n' > "$R/mix/a08_blank_lines.txt"
printf 'x\n#!/bin/sh\n' > "$R/mix/a09_shebang_on_line2.txt"
printf '#!/bin/sh\necho last\n' > "$R/mix/a10_last.sh"
git -C "$R" add -A
MIXMODES="$(git -C "$R" ls-files -s -- mix | cut -c1-6 | sort -u | tr '\n' ' ')"
scan_streams
assert_eq "MINOR-A fixture: all ten files are staged 100644" "100644 " "$MIXMODES"
assert_eq "MINOR-A the exit code is 0 (warnings only)" "0" "$RC"
WARNED="$(printf '%s\n' "$ERR" | grep 'warning: new file ' | sed 's/^.*warning: new file \(.*\) starts with #! .*$/\1/' | LC_ALL=C sort)"
WANT="$(printf '%s\n' mix/a04_crlf.sh mix/a06_after_empty.sh mix/a07_shebang_nonl.sh mix/a10_last.sh)"
assert_eq "MINOR-A exactly the four #! files are warned about (no other file, none missed)" "$WANT" "$WARNED"
assert_eq "MINOR-A four warning lines" "4" "$(printf '%s\n' "$ERR" | grep -c 'warning: new file ')"

echo "v0.23.2 round 2 LOW-a an empty executable deleted and an empty 644 file added is not a rename"
newrepo
: > "$R/keep.sh"; chmod +x "$R/keep.sh" 2>/dev/null
git -C "$R" add keep.sh; git -C "$R" update-index --chmod=+x -- keep.sh; G -C "$R" commit -q -m "empty exec"
assert_eq "LOW-a fixture: keep.sh is committed 100755" "100755" "$(git -C "$R" ls-files -s -- keep.sh | cut -d' ' -f1)"
git -C "$R" rm -q keep.sh
mkdir -p "$R/pkg"; : > "$R/pkg/__init__.py"; git -C "$R" add pkg/__init__.py
assert_eq "LOW-a fixture: pkg/__init__.py is staged 100644" "100644" "$(git -C "$R" ls-files -s -- pkg/__init__.py | cut -d' ' -f1)"
run_in "$R" bash "$LC" scan --staged
assert_rc "LOW-a deleting an empty 100755 file and adding an empty 100644 file: exit 0" 0
assert_not_contains "LOW-a ... no mode violation" "$OUT" "(mode)"

echo "v0.23.2 round 2 LOW-b the usage describes rename detection as a rename with unchanged content"
run_in "$R" bash "$LC" scan
USAGE_FLAT="$(printf '%s' "$OUT" | tr 'A-Z' 'a-z' | tr -s ' \n\t' '   ')"
assert_contains "LOW-b the usage says 'a rename with unchanged content'" "$USAGE_FLAT" "a rename with unchanged content"

t_summary
