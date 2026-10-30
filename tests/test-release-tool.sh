#!/usr/bin/env bash
# Tests for tools/release.sh (AC4) against a throw-away clone with its own bare origin.
# v0.32.0 (S3, AC7): every fixture clone ships tools/release-gate.sh and holds a committed passing synthetic gate (see
# tests/release-gate-fixture.sh), so the success cases keep their meaning now that release.sh checks the gate (AC4); a change to
# the fixture after setup is re-sealed with `reseal`. The gate cases are at the end of this file.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/release-gate-fixture.sh"
command -v node >/dev/null 2>&1 || { t_skip 1 "node missing (the synthetic release gate needs it)"; t_summary; exit $?; }
REL_SRC="$PB_ROOT/tools/release.sh"
export PLAYBOOK_HOME="$(mk_tmp)"
G() { git -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }

# setup -> sets C (clone) and O (bare origin). main is pushed; VERSION 1.2.3 with a CHANGELOG entry.
# tests/run-all.sh is a stub (exit 0) so release.sh's own suite run is cheap.
setup() {
  local w; w="$(mk_tmp)"
  O="$w/origin.git"; C="$w/clone"
  git init -q --bare "$O"; git -C "$O" symbolic-ref HEAD refs/heads/main   # independent of init.defaultBranch
  mkdir -p "$C/tools" "$C/tests" "$C/scripts"
  cp "$PB_ROOT/tools/check-release.sh" "$C/tools/"
  cp "$PB_ROOT/scripts/lib.sh" "$C/scripts/"
  [ -f "$REL_SRC" ] && cp "$REL_SRC" "$C/tools/release.sh"
  rgf_prepare "$C"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$C/tests/run-all.sh"
  printf '1.2.3\n' > "$C/VERSION"
  printf '# Changelog\n\n## 1.2.3 - 2026-01-01\n- thing\n' > "$C/CHANGELOG.md"
  ( cd "$C" && git init -q && git checkout -q -b main && G add -A && G commit -qm init &&
    git remote add origin "$O" && git push -q origin main ) || { echo "fixture setup failed"; exit 3; }
  [ "${NOGATE:-0}" = 1 ] || reseal || { echo "fixture gate failed"; exit 3; }
}
# reseal: a committed passing gate for the current HEAD of $C, pushed (a later commit outside evals/results needs a new one)
reseal() { rgf_seal "$C" && ( cd "$C" && git push -q origin main ); }
tags_of() { git -C "$1" tag -l | tr '\n' ' '; }
origin_tags() { git -C "$O" tag -l | tr '\n' ' '; }

echo "refusals"
setup
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC4 control: valid setup passes the checks (dry run) -> exit 0" 0

setup
run_in "$C" bash tools/release.sh v1.2.4
assert_rc "AC4 refuses on VERSION mismatch -> exit 1" 1
assert_eq "AC4 VERSION mismatch creates no tag" "" "$(tags_of "$C")$(origin_tags)"

setup
printf '1.2.4\n' > "$C/VERSION"; ( cd "$C" && G commit -qam bump && git push -q origin main ) && reseal
run_in "$C" bash tools/release.sh v1.2.4
assert_rc "AC4 refuses on missing CHANGELOG entry -> exit 1" 1
assert_eq "AC4 CHANGELOG refusal creates no tag" "" "$(tags_of "$C")$(origin_tags)"

setup
printf 'wip\n' >> "$C/CHANGELOG.md"
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC4 refuses on a dirty tree -> exit 1" 1
assert_eq "AC4 dirty refusal creates no tag" "" "$(tags_of "$C")$(origin_tags)"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC4 refuses on a dirty tree even with --dry-run -> exit 1" 1

setup
printf 'new\n' > "$C/untracked.txt"
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC4 refuses when an untracked file is present -> exit 1" 1

setup
( cd "$C" && git checkout -q -b feature )
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC4 refuses when not on main -> exit 1" 1
assert_eq "AC4 not-on-main creates no tag" "" "$(tags_of "$C")$(origin_tags)"

setup
( cd "$C" && printf 'x\n' > extra.txt && G add -A && G commit -qm local-only ) && rgf_seal "$C"
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC4 refuses when main is ahead of origin/main -> exit 1" 1
assert_eq "AC4 ahead-of-origin creates no tag" "" "$(tags_of "$C")$(origin_tags)"

setup
W2="$(mk_tmp)"; git clone -q -b main "$O" "$W2/other" || echo "fixture clone failed"
( cd "$W2/other" && git config user.email t@example.invalid && git config user.name tester && git config commit.gpgsign false &&
  printf 'y\n' > other.txt && git add -A && git commit -qm upstream && git push -q origin main )
( cd "$C" && git fetch -q origin )
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC4 refuses when main is behind origin/main -> exit 1" 1
assert_eq "AC4 behind-origin creates no tag" "" "$(tags_of "$C")$(origin_tags)"

setup
printf '#!/usr/bin/env bash\nexit 1\n' > "$C/tests/run-all.sh"
( cd "$C" && G commit -qam red-suite && git push -q origin main ) && reseal
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC4 refuses when tests/run-all.sh fails -> exit 1" 1
assert_eq "AC4 red suite creates no tag" "" "$(tags_of "$C")$(origin_tags)"

echo "dry run"
setup
HEAD0="$(git -C "$C" rev-parse HEAD)"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC4 --dry-run on a valid setup -> exit 0" 0
assert_contains "AC4 --dry-run prints 'would tag'" "$OUT" "would tag"
assert_contains "AC4 --dry-run prints 'would push'" "$OUT" "would push"
assert_contains "AC4 --dry-run names the tag" "$OUT" "v1.2.3"
assert_eq "AC4 --dry-run creates no local tag" "" "$(tags_of "$C")"
assert_eq "AC4 --dry-run pushes nothing to origin" "" "$(origin_tags)"
assert_eq "AC4 --dry-run leaves HEAD alone" "$HEAD0" "$(git -C "$C" rev-parse HEAD)"
run_in "$C" bash tools/release.sh --dry-run v1.2.3
assert_rc "AC4 flag order is free (--dry-run before the tag) -> exit 0" 0
assert_eq "AC4 still no tag after the second dry run" "" "$(tags_of "$C")$(origin_tags)"

echo "release"
setup
HEAD0="$(git -C "$C" rev-parse HEAD)"
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC4 release on a valid setup -> exit 0" 0
assert_contains "AC4 tag exists locally" "$(tags_of "$C")" "v1.2.3"
assert_contains "AC4 tag exists in the origin" "$(origin_tags)" "v1.2.3"
assert_eq "AC4 tag points at HEAD (origin)" "$HEAD0" "$(git -C "$O" rev-parse 'v1.2.3^{commit}')"
assert_eq "AC4 release leaves HEAD alone" "$HEAD0" "$(git -C "$C" rev-parse HEAD)"
assert_eq "AC4 release leaves the tree clean" "" "$(git -C "$C" status --porcelain)"

echo "usage"
setup
run_in "$C" bash tools/release.sh
assert_rc "AC4 no tag -> exit 2" 2
run_in "$C" bash tools/release.sh 1.2.3
assert_rc "AC4 tag without the leading v -> exit 2" 2
run_in "$C" bash tools/release.sh v1.2
assert_rc "AC4 tag not vX.Y.Z -> exit 2" 2
run_in "$C" bash tools/release.sh v1.2.3 --bogus
assert_rc "AC4 unknown flag -> exit 2" 2
run_in "$C" bash tools/release.sh v1.2.3 v1.2.4
assert_rc "AC4 two tags -> exit 2" 2
assert_eq "AC4 usage errors create no tag" "" "$(tags_of "$C")$(origin_tags)"


echo "#12a release.sh: newline tag, and no ref updates while checking origin"
setup
run_in "$C" bash tools/release.sh "$(printf 'v1.2.3\nx')" --dry-run
assert_rc "AC12a.1 release.sh: tag with a newline exits 2" 2
setup
W3="$(mk_tmp)"; git clone -q -b main "$O" "$W3/other" || echo "fixture clone failed"
( cd "$W3/other" && git config user.email t@example.invalid && git config user.name tester && git config commit.gpgsign false &&
  printf 'z\n' > z.txt && git add -A && git commit -qm upstream2 && git push -q origin main )
BEFORE="$(git -C "$C" rev-parse refs/remotes/origin/main)"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC12a.2 behind origin without a prior fetch is refused (dry run) -> exit 1" 1
assert_eq "AC12a.2 dry run leaves refs/remotes/origin/main unchanged" "$BEFORE" "$(git -C "$C" rev-parse refs/remotes/origin/main)"


echo "README test counts (v0.9.0 AC7.2)"
# set_readme TEXT -> committed + pushed README.md in $C, and a run-all stub that prints suite summaries
# (a.sh 5 passed; b.sh 3 passed + 2 skipped; c.sh 1 passed => passed+skipped total 11, passed only 9)
set_readme() {
  printf '%s' "$1" > "$C/README.md"
  cat > "$C/tests/run-all.sh" <<'STUB'
#!/usr/bin/env bash
echo "== tests/test-a.sh"
echo "test-a.sh: 5 passed, 0 failed"
echo "== tests/test-b.sh"
echo "test-b.sh: 3 passed, 0 failed, 2 skipped"
echo "== tests/test-c.sh"
echo "test-c.sh: 1 passed, 0 failed"
echo "== evals/run-checks.sh (static skill checks)"
echo "run-checks: all ok"
echo "ALL GREEN"
exit 0
STUB
  ( cd "$C" && G add -A && G commit -qm readme && git push -q origin main ) && reseal
}
README_OK='# demo
![tests](https://img.shields.io/badge/tests-11-1F9D63)
| Script tests | **11 passing** (see run-all) |
Every one of the 11 tests, run in sandboxes.
'
setup; set_readme "$README_OK"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC7.2 all three README numbers equal passed+skipped (11): dry run exit 0" 0
assert_contains "AC7.2 dry run still reaches 'would tag'" "$OUT" "would tag"
setup; set_readme "$README_OK"
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC7.2 matching README numbers: real release exit 0" 0
assert_contains "AC7.2 the tag is created" "$(tags_of "$C")" "v1.2.3"

setup; set_readme '![tests](https://img.shields.io/badge/tests-9-1F9D63)
'
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC7.2 badge 9 (passed only, skipped not added) vs 11 -> refused, exit 1" 1
assert_contains "AC7.2 refusal names README" "$OUT" "README"
assert_contains "AC7.2 refusal names the README number" "$OUT" "9"
assert_contains "AC7.2 refusal names the real total" "$OUT" "11"
assert_eq "AC7.2 refusal creates no tag" "" "$(tags_of "$C")$(origin_tags)"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC7.2 --dry-run refuses on the same mismatch: exit 1" 1
assert_not_contains "AC7.2 --dry-run mismatch does not print 'would tag'" "$OUT" "would tag"

setup; set_readme '![tests](https://img.shields.io/badge/tests-12-1F9D63)
'
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC7.2 badge 12 (too high) vs 11 -> exit 1" 1

setup; set_readme '![tests](https://img.shields.io/badge/tests-11-1F9D63)
| Script tests | **10 passing** |
'
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC7.2 only the '**N passing**' number is stale -> exit 1" 1
assert_contains "AC7.2 names the stale number 10" "$OUT" "10"

setup; set_readme '![tests](https://img.shields.io/badge/tests-11-1F9D63)
Every one of the 8 tests, run in sandboxes.
'
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC7.2 only the 'N tests, run in sandboxes' number is stale -> exit 1" 1
assert_contains "AC7.2 names the stale number 8" "$OUT" "8"

setup; set_readme '![tests](https://img.shields.io/badge/tests-11-1F9D63)
| Script tests | **11 passing** |
Every one of the 11 tests, run in sandboxes.
**3 passing** in some unrelated old table
'
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC7.2 every occurrence is checked, a second stale '**3 passing**' -> exit 1" 1

setup; set_readme '# demo
Version 0.9.0 has 40 files. We run 3 jobs. Issue #120 is closed.
'
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC7.2 README without the three count patterns: no check, exit 0" 0

setup
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC7.2 no README.md at all: no check, exit 0" 0

setup; printf '#!/usr/bin/env bash\necho "test-a.sh: 4 passed, 0 failed"\necho "test-b.sh: 6 passed, 0 failed, 1 skipped"\nexit 1\n' > "$C/tests/run-all.sh"
printf '![tests](https://img.shields.io/badge/tests-11-1F9D63)\n' > "$C/README.md"
( cd "$C" && G add -A && G commit -qm red && git push -q origin main ) && reseal
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC7.2 a failing suite is refused before (and regardless of) the README check" 1

setup
printf '#!/usr/bin/env bash\necho "test-a.sh: 4 passed, 0 failed"\necho "test-b.sh: 6 passed, 0 failed, 1 skipped"\nexit 0\n' > "$C/tests/run-all.sh"
printf '![tests](https://img.shields.io/badge/tests-11-1F9D63)\n' > "$C/README.md"
( cd "$C" && G add -A && G commit -qm other-totals && git push -q origin main ) && reseal
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC7.2 totals are summed over suite lines (4+6+1 = 11): exit 0" 0


echo "v0.10.0 AC8.1 the suite output is streamed, the exit status is run-all's"
# a stub that prints, then reports its own status; messages are distinctive
setup
printf '#!/usr/bin/env bash\necho "STUB-LINE-ONE"\necho "STUB-LINE-TWO"\necho "STUB-STDERR-LINE" >&2\nexit 0\n' > "$C/tests/run-all.sh"
( cd "$C" && G commit -qam stub-out && git push -q origin main ) && reseal
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC8.1 a printing stub that passes: dry run exit 0" 0
assert_contains "AC8.1 stub stdout appears in the release output" "$OUT" "STUB-LINE-ONE"
assert_contains "AC8.1 the later stub line appears too" "$OUT" "STUB-LINE-TWO"
assert_contains "AC8.1 stub stderr appears in the release output" "$OUT" "STUB-STDERR-LINE"
assert_eq "AC8.1 each stub line is shown once (not tee'd and cat'ed again)" "1" "$(printf '%s\n' "$OUT" | grep -c 'STUB-LINE-ONE')"
assert_contains "AC8.1 the dry run still ends with 'would tag'" "$OUT" "would tag"

setup
printf '#!/usr/bin/env bash\necho "STUB-FAIL-OUT"\nexit 1\n' > "$C/tests/run-all.sh"
( cd "$C" && G commit -qam stub-red && git push -q origin main ) && reseal
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC8.1 a failing stub that prints is refused (status from run-all, not tee): exit 1" 1
assert_contains "AC8.1 the failing stub's output is still shown" "$OUT" "STUB-FAIL-OUT"
assert_contains "AC8.1 the refusal is reported" "$OUT" "refused"
assert_eq "AC8.1 a failing printing stub creates no tag" "" "$(tags_of "$C")$(origin_tags)"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC8.1 failing printing stub is refused in a dry run too: exit 1" 1
assert_not_contains "AC8.1 refused dry run does not print 'would tag'" "$OUT" "would tag"

setup
printf '#!/usr/bin/env bash\necho "test-a.sh: 4 passed, 0 failed"\necho "STUB-SEVEN"\nexit 7\n' > "$C/tests/run-all.sh"
( cd "$C" && G commit -qam stub-seven && git push -q origin main ) && reseal
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC8.1 a stub exiting 7 is refused with 1 (the release.sh refusal code)" 1
assert_eq "AC8.1 a stub exiting 7 creates no tag" "" "$(tags_of "$C")$(origin_tags)"

# the README count check reads the streamed log, including a final line without a newline
setup
printf '#!/usr/bin/env bash\necho "test-a.sh: 5 passed, 0 failed"\necho "test-b.sh: 3 passed, 0 failed, 2 skipped"\nprintf "test-c.sh: 1 passed, 0 failed"\nexit 0\n' > "$C/tests/run-all.sh"
printf '![tests](https://img.shields.io/badge/tests-11-1F9D63)\n' > "$C/README.md"
( cd "$C" && G add -A && G commit -qm count-ok && git push -q origin main ) && reseal
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC8.1 count check works on streamed output (5+3+2+1 = 11, last line unterminated): exit 0" 0
printf '![tests](https://img.shields.io/badge/tests-10-1F9D63)\n' > "$C/README.md"
( cd "$C" && G commit -qam count-bad && git push -q origin main ) && reseal
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC8.1 count check still refuses a wrong README number on streamed output: exit 1" 1
assert_contains "AC8.1 the refusal names the README number" "$OUT" "10"
assert_contains "AC8.1 the refusal names the real total" "$OUT" "11"

# liveness: the first stub line must be visible while the stub is still running.
# The stub waits for a go-file (no timing guess); it gives up after ~60s so a buffering implementation cannot hang.
setup
GO="$(mk_tmp)/go"
cat > "$C/tests/run-all.sh" <<STUB
#!/usr/bin/env bash
echo "LIVE-FIRST"
i=0
while [ ! -e "$GO" ] && [ \$i -lt 600 ]; do sleep 0.1; i=\$((i + 1)); done
echo "LIVE-SECOND"
exit 0
STUB
( cd "$C" && G commit -qam live-stub && git push -q origin main ) && reseal
LOUT="$(mk_tmp)/out"; : > "$LOUT"
( cd "$C" && bash tools/release.sh v1.2.3 --dry-run > "$LOUT" 2>&1; echo $? > "$LOUT.rc" ) &
LPID=$!
SEEN=0; n=0
while [ $n -lt 300 ]; do   # up to ~30s for a slow Windows box
  if grep -q 'LIVE-FIRST' "$LOUT" 2>/dev/null; then SEEN=1; break; fi
  sleep 0.1; n=$((n + 1))
done
: > "$GO"   # release the stub whatever happened
wait "$LPID"
if [ "$SEEN" = 1 ]; then t_ok "AC8.1 the first stub line is visible while the suite is still running"; else t_bad "AC8.1 the first stub line is visible while the suite is still running" "no LIVE-FIRST in the output before the stub finished (output is buffered until the end)"; fi
assert_contains "AC8.1 the whole stub output arrives" "$(cat "$LOUT")" "LIVE-SECOND"
assert_eq "AC8.1 the live run still exits 0" "0" "$(cat "$LOUT.rc" 2>/dev/null)"
assert_contains "AC8.1 the live run still ends with 'would tag'" "$(cat "$LOUT")" "would tag"


echo "README counts read only suite summary lines (an assertion line with N passed, M failed in its name is ignored)"
set_readme_assert() {   # README_TEXT -> committed run-all stub: one summary line (10 passed) plus an assertion line naming 4 passed, 1 failed
  printf '%s' "$1" > "$C/README.md"
  cat > "$C/tests/run-all.sh" <<'STUB'
#!/usr/bin/env bash
echo "== tests/test-a.sh"
echo "  ok   AC6.2 'Tests: 4 passed, 1 failed: subtract.': PASS"
echo "test-a.sh: 10 passed, 0 failed"
echo "ALL GREEN"
exit 0
STUB
  ( cd "$C" && G add -A && G commit -qm readme && git push -q origin main ) && reseal
}
setup; set_readme_assert '# demo
![tests](https://img.shields.io/badge/tests-10-1F9D63)
| Script tests | **10 passing** |
Every one of the 10 tests, run in sandboxes.
'
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "RV release: README 10 equals the one summary line (assertion line ignored): dry run exit 0" 0
assert_contains "RV release: that dry run reaches 'would tag'" "$OUT" "would tag"
setup; set_readme_assert '![tests](https://img.shields.io/badge/tests-15-1F9D63)
'
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "RV release: README 15 (summary 10 + the assertion line's 4 + 1) is wrong: refused, exit 1" 1
assert_contains "RV release: the refusal names the real total 10" "$OUT" "suite ran 10"


echo "v0.23.2 AC14 a README count that differs from the run is refused naming the expected and the found count"
# Spec note (tester): no tool in this repo writes VERSION/CHANGELOG/README and commits; the README count is re-counted by
# tools/release.sh after the suite run, on a clean tree equal to origin/main (i.e. after the last commit). These cases pin that
# place. The only change asked of it: the refusal says "expected N" (the suite's passed + skipped) and "found M" (README).
setup; set_readme '![tests](https://img.shields.io/badge/tests-9-1F9D63)
'
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC14.1 README 9 vs the run's 11: refused, exit 1" 1
if printf '%s\n' "$OUT" | grep -iE 'expected[^0-9]{0,20}11' | grep -iqE 'found[^0-9]{0,20}9([^0-9]|$)'; then t_ok "AC14.1 the refusal reads 'expected 11 ... found 9'"; else
  if printf '%s\n' "$OUT" | grep -iE 'found[^0-9]{0,20}9([^0-9]|$)' | grep -iqE 'expected[^0-9]{0,20}11'; then t_ok "AC14.1 the refusal reads 'found 9 ... expected 11'"; else t_bad "AC14.1 the refusal names the expected (11) and the found (9) counts with those words" "$OUT"; fi
fi
assert_eq "AC14.1 the refusal creates no tag and pushes nothing" "" "$(tags_of "$C")$(origin_tags)"
setup; set_readme "$README_OK"
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC14.1 README equals the run's count (11): it proceeds, exit 0" 0
assert_not_contains "AC14.1 a matching count prints no 'expected ... found' refusal" "$OUT" "found 11"

echo "v0.29 slice S: release tag signing (AC-S1..AC-S7, spec 01-spec.md)"
# Isolation: no real global/system git config, temp HOME and GNUPGHOME; the throw-away key lives in mk_tmp only.
SW="$(cd "$(mk_tmp)" && pwd -P)"
export GIT_CONFIG_GLOBAL="$SW/gitconfig" GIT_CONFIG_NOSYSTEM=1
GNUPGHOME="$(mk_tmp)"; export GNUPGHOME
HOME="$(mk_tmp)"; export HOME
GC="$GIT_CONFIG_GLOBAL"
cfg_reset() {   # fresh global config: identity only (git tag -s needs a tagger)
  : > "$GC"
  git config --file "$GC" user.name tester && git config --file "$GC" user.email t@example.invalid
}
cfg_ssh() {     # cfg_ssh KEYFILE: user.signingkey + gpg.format=ssh in the global config
  cfg_reset
  git config --file "$GC" gpg.format ssh && git config --file "$GC" user.signingkey "$1"
}
setup_full() {  # setup + install.sh and scripts/ committed, so a clone of origin is a working playbook checkout
  setup
  mkdir -p "$C/skills/stub" && echo "# stub" > "$C/skills/stub/SKILL.md" &&
    cp "$PB_ROOT/install.sh" "$C/install.sh" && cp -R "$PB_ROOT/scripts/." "$C/scripts/" &&
    ( cd "$C" && G add -A && G commit -qm installer && git push -q origin main ) && reseal || { echo "setup_full failed"; exit 3; }
}
probe_ssh_sign() {   # can this git + ssh-keygen sign a tag and verify it against an allowed signers file? (L-0004)
  local p
  p="$(cd "$(mk_tmp)" && pwd -P)" || return 1
  command -v ssh-keygen >/dev/null 2>&1 || return 1
  ssh-keygen -q -t ed25519 -N '' -C probe -f "$p/k" < /dev/null > /dev/null 2>&1 || return 1
  printf 'probe@example.invalid namespaces="git" %s\n' "$(cat "$p/k.pub")" > "$p/allowed" || return 1
  ( cd "$p" && git init -q r && cd r && printf 'x\n' > f && G add f && G commit -qm p &&
    G -c gpg.format=ssh -c user.signingkey="$p/k" tag -s probe -m probe ) > /dev/null 2>&1 || return 1
  git -C "$p/r" -c gpg.ssh.allowedSignersFile="$p/allowed" verify-tag probe > /dev/null 2>&1 || return 1
  return 0
}
SSH_SIGN=0
if probe_ssh_sign; then SSH_SIGN=1; fi
KEY="$SW/missing-key"   # nonexistent unless ssh-keygen works
if [ "$SSH_SIGN" = 1 ]; then
  ssh-keygen -q -t ed25519 -N '' -C relkey -f "$SW/relkey" < /dev/null > /dev/null 2>&1 &&
    printf 'release@example.invalid namespaces="git" %s\n' "$(cat "$SW/relkey.pub")" > "$SW/allowed" &&
    KEY="$SW/relkey" || { echo "key setup failed"; exit 3; }
fi
RELSRC="$PB_ROOT/tools/release.sh"

echo "AC-S3: release.sh never generates keys and never writes git config"
assert_eq "AC-S3 release.sh does not mention ssh-keygen" "0" "$(grep -c 'ssh-keygen' "$RELSRC")"
assert_eq "AC-S3 release.sh has no gpg key generation" "0" "$(grep -Ec 'gen-key|generate-key|quick-gen' "$RELSRC")"
assert_eq "AC-S3 release.sh has no git config write (only --get reads)" "" \
  "$(grep -E 'git[^|;&]* config' "$RELSRC" | grep -vE -e '--get|--list' || true)"

echo "AC-S2: no signing key -> lightweight tag as today, one line naming it unsigned"
setup; cfg_reset
CFG0="$(cksum < "$GC")"
HEAD0="$(git -C "$C" rev-parse HEAD)"
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC-S2 release without a signing key -> exit 0" 0
assert_eq "AC-S2 the tag is lightweight (points straight at the commit)" "commit" "$(git -C "$C" cat-file -t refs/tags/v1.2.3 2>/dev/null)"
assert_contains "AC-S2 the tag is in the origin" "$(origin_tags)" "v1.2.3"
assert_eq "AC-S2 the tag peels to HEAD" "$HEAD0" "$(git -C "$O" rev-parse 'v1.2.3^{commit}')"
assert_eq "AC-S2 exactly one output line says the tag is unsigned" "1" "$(printf '%s\n' "$OUT" | grep -ic 'unsigned')"
assert_contains "AC-S2 that line names docs/development.md" "$(printf '%s\n' "$OUT" | grep -i 'unsigned')" "docs/development.md"
assert_contains "AC-S2 that line names the tag" "$(printf '%s\n' "$OUT" | grep -i 'unsigned')" "v1.2.3"
assert_contains "AC-S2 the release line is still printed" "$OUT" "released v1.2.3"
assert_eq "AC-S3 the global git config is byte-identical after an unsigned release" "$CFG0" "$(cksum < "$GC")"
cfg_reset; git config --file "$GC" user.signingkey ""
setup
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC-S2 an empty user.signingkey counts as no key -> exit 0" 0
assert_eq "AC-S2 an empty user.signingkey gives a lightweight tag" "commit" "$(git -C "$C" cat-file -t refs/tags/v1.2.3 2>/dev/null)"
assert_eq "AC-S2 an empty user.signingkey still prints one unsigned line" "1" "$(printf '%s\n' "$OUT" | grep -ic 'unsigned')"

echo "AC-S4: --dry-run changes nothing, with a signing key configured"
cfg_ssh "$KEY"; CFG0="$(cksum < "$GC")"
setup
HEAD0="$(git -C "$C" rev-parse HEAD)"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC-S4 dry run with a signing key configured -> exit 0" 0
assert_contains "AC-S4 dry run still says 'would tag'" "$OUT" "would tag"
assert_eq "AC-S4 dry run creates no local tag" "" "$(tags_of "$C")"
assert_eq "AC-S4 dry run pushes no tag" "" "$(origin_tags)"
assert_eq "AC-S4 dry run leaves HEAD alone" "$HEAD0" "$(git -C "$C" rev-parse HEAD)"
assert_eq "AC-S4 dry run leaves the global git config byte-identical" "$CFG0" "$(cksum < "$GC")"

echo "AC-S7: signing key configured but signing fails -> exit 3, no tag, nothing pushed, no unsigned fallback"
cfg_ssh "$SW/no-such-key-file"; CFG0="$(cksum < "$GC")"
setup
HEAD0="$(git -C "$C" rev-parse HEAD)"
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC-S7 user.signingkey names a missing file -> exit 3" 3
assert_eq "AC-S7 no local tag is left behind (not even an unsigned one)" "" "$(tags_of "$C")"
assert_eq "AC-S7 nothing is pushed to the origin" "" "$(origin_tags)"
assert_contains "AC-S7 the output says signing failed" "$(printf '%s' "$OUT" | tr 'A-Z' 'a-z')" "signing failed"
assert_not_contains "AC-S7 it does not claim a release" "$OUT" "released v1.2.3"
assert_eq "AC-S7 HEAD is untouched" "$HEAD0" "$(git -C "$C" rev-parse HEAD)"
assert_eq "AC-S7 the global git config is byte-identical" "$CFG0" "$(cksum < "$GC")"

# git 2.43 exits 0 and leaves an annotated UNSIGNED tag when the ssh key file is missing, so the case above also pins that
# release.sh checks the result. Second injection: git itself fails (gpg program fails).
cfg_reset; git config --file "$GC" user.signingkey ABCD1234; git config --file "$GC" gpg.program false
setup
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC-S7 git tag -s fails (gpg program fails) -> exit 3" 3
assert_eq "AC-S7 gpg failure: no local tag left behind" "" "$(tags_of "$C")"
assert_eq "AC-S7 gpg failure: nothing pushed" "" "$(origin_tags)"
assert_contains "AC-S7 gpg failure: the output says signing failed" "$(printf '%s' "$OUT" | tr 'A-Z' 'a-z')" "signing failed"

echo "AC-S1/AC-S5: signing key configured -> signed annotated tag that verifies, locally, at the origin and through install.sh update"
if [ "$SSH_SIGN" = 1 ]; then
  cfg_ssh "$KEY"; CFG0="$(cksum < "$GC")"
  setup_full
  HEAD0="$(git -C "$C" rev-parse HEAD)"
  REPO_CFG0="$(cksum < "$C/.git/config")"
  run_in "$C" bash tools/release.sh v1.2.3
  assert_rc "AC-S1 release with an ssh signing key -> exit 0" 0
  assert_eq "AC-S1 the tag is an annotated tag object" "tag" "$(git -C "$C" cat-file -t refs/tags/v1.2.3 2>/dev/null)"
  assert_eq "AC-S1 the signed tag message is 'release v1.2.3'" "release v1.2.3" "$(git -C "$C" tag -l --format='%(contents:subject)' v1.2.3 2>/dev/null)"
  assert_contains "AC-S1 the tag object carries an SSH signature (the marker install.sh classifies on)" \
    "$(git -C "$C" cat-file tag refs/tags/v1.2.3 2>/dev/null | LC_ALL=C grep -e '^-----BEGIN SSH SIGNATURE-----')" "BEGIN SSH SIGNATURE"
  if git -C "$C" -c gpg.ssh.allowedSignersFile="$SW/allowed" verify-tag v1.2.3 > /dev/null 2>&1; then t_ok "AC-S1 git verify-tag accepts the local tag against the allowed signers file"; else t_bad "AC-S1 git verify-tag accepts the local tag against the allowed signers file"; fi
  assert_eq "AC-S1 the origin holds the same (signed) tag object" "$(git -C "$C" rev-parse refs/tags/v1.2.3 2>/dev/null)" "$(git -C "$O" rev-parse refs/tags/v1.2.3 2>/dev/null)"
  if git -C "$O" -c gpg.ssh.allowedSignersFile="$SW/allowed" verify-tag v1.2.3 > /dev/null 2>&1; then t_ok "AC-S1 git verify-tag accepts the tag at the origin"; else t_bad "AC-S1 git verify-tag accepts the tag at the origin"; fi
  assert_eq "AC-S1 the tag peels to HEAD" "$HEAD0" "$(git -C "$O" rev-parse 'v1.2.3^{commit}')"
  assert_not_contains "AC-S1 a signed release prints no 'unsigned' line" "$(printf '%s' "$OUT" | tr 'A-Z' 'a-z')" "unsigned"
  assert_contains "AC-S1 the release line is still printed" "$OUT" "released v1.2.3"
  assert_eq "AC-S3 the global git config is byte-identical after a signed release" "$CFG0" "$(cksum < "$GC")"
  assert_eq "AC-S3 the clone's repo config is byte-identical after a signed release" "$REPO_CFG0" "$(cksum < "$C/.git/config")"
  # AC-S5: a fresh client of the origin runs install.sh's own verify path on the tag release.sh signed
  D="$SW/client"; git clone -q "$O" "$D" 2>/dev/null || { echo "client clone failed"; exit 3; }
  : > "$SW/registry"
  git config --file "$GC" gpg.ssh.allowedSignersFile "$SW/allowed"
  UOUT="$(cd "$D" && PLAYBOOK_REGISTRY="$SW/registry" bash install.sh update --yes < /dev/null 2>&1)"; URC=$?
  assert_eq "AC-S5 install.sh update on the signed release -> exit 0" "0" "$URC"
  assert_contains "AC-S5 install.sh update reports the signature verified" "$UOUT" "release tag v1.2.3: signature verified"
  git config --file "$GC" --unset gpg.ssh.allowedSignersFile
  UOUT="$(cd "$D" && PLAYBOOK_REGISTRY="$SW/registry" bash install.sh update --yes < /dev/null 2>&1)"
  assert_not_contains "AC-S5 control: without an allowed signers file install.sh does not say verified" "$UOUT" "signature verified"
  # a signing key set only in the repo config (not global) is honoured too (effective config)
  cfg_reset; git config --file "$GC" gpg.format ssh
  setup
  git -C "$C" config user.signingkey "$KEY"
  run_in "$C" bash tools/release.sh v1.2.3
  assert_rc "AC-S1 a repo-level user.signingkey is used (effective config) -> exit 0" 0
  assert_eq "AC-S1 a repo-level signing key gives an annotated tag" "tag" "$(git -C "$C" cat-file -t refs/tags/v1.2.3 2>/dev/null)"
  assert_eq "AC-S1 a repo-level signing key: the tag message is 'release v1.2.3'" "release v1.2.3" "$(git -C "$C" tag -l --format='%(contents:subject)' v1.2.3 2>/dev/null)"
else
  t_skip 18 "AC-S1/AC-S5 signed release tag (ssh-keygen or ssh tag signing unsupported here)"
fi

echo "AC-S6: docs/development.md 'Signing release tags' section"
DEVMD="$(cat "$PB_ROOT/docs/development.md" 2>/dev/null)"
assert_contains "AC-S6 docs/development.md has a 'Signing release tags' section" "$DEVMD" "Signing release tags"
assert_contains "AC-S6 it names gpg.format=ssh" "$DEVMD" "gpg.format"
assert_contains "AC-S6 it names user.signingkey" "$DEVMD" "user.signingkey"
assert_contains "AC-S6 it names gpg.ssh.allowedSignersFile" "$DEVMD" "gpg.ssh.allowedSignersFile"
assert_contains "AC-S6 it says release.sh signs when a key is configured" "$(printf '%s\n' "$DEVMD" | grep -i 'release\.sh' | grep -i 'sign')" "release.sh"
assert_contains "AC-S6 it says to watch the main-ci job of the first signed release" "$DEVMD" "main-ci"
assert_contains "AC-S6 it names the recovery (gh release create by hand)" "$DEVMD" "gh release create"
assert_contains "AC-S6 it names the GITHUB_SHA tag-object risk" "$DEVMD" "GITHUB_SHA"

echo "AC4: release.sh checks the release gate (tools/release-gate.sh --check HEAD) before the suite and before any tag (v0.32.0 S3)"
# suite_mark: tests/run-all.sh becomes a stub that records that it ran (in $MARK); committed and pushed, NOT re-sealed
suite_mark() {
  MARK="$(mk_tmp)/suite-ran"
  printf '#!/usr/bin/env bash\necho ran >> "%s"\nexit 0\n' "$MARK" > "$C/tests/run-all.sh"
  ( cd "$C" && G commit -qam mark-suite && git push -q origin main )
}
suite_runs() { if [ -f "$MARK" ]; then wc -l < "$MARK" | tr -d ' '; else echo 0; fi; }
# gate_stub RC: tools/release-gate.sh becomes a stub that logs its arguments to $GLOG, prints two reason lines and exits RC
gate_stub() {
  GLOG="$(mk_tmp)/gate-args"
  printf '#!/usr/bin/env bash\nprintf "%%s\n" "$*" >> "%s"\nprintf "stub reason one\nstub reason two\n"\nexit %s\n' "$GLOG" "$1" > "$C/tools/release-gate.sh"
  ( cd "$C" && G commit -qam "gate-stub-$1" && git push -q origin main )
}

NOGATE=1 setup; suite_mark
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC4 no gate result committed: refused, exit 1" 1
assert_contains "AC4 the refusal carries the gate's first reason line" "$OUT" "release refused: release gate: no gate result under evals/results/gate-*/ at REV"
assert_eq "AC4 no gate: no tag, nothing pushed" "" "$(tags_of "$C")$(origin_tags)"
assert_eq "AC4 no gate: refused before the test suite runs" "0" "$(suite_runs)"
assert_not_contains "AC4 no gate: it does not claim a release" "$OUT" "released v1.2.3"

NOGATE=1 setup; suite_mark
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC4 --dry-run without a gate -> exit 1" 1
assert_contains "AC4 --dry-run prints the gate outcome" "$OUT" "release gate: no gate result under evals/results/gate-*/ at REV"
assert_not_contains "AC4 --dry-run without a gate does not print 'would tag'" "$OUT" "would tag"
assert_eq "AC4 --dry-run without a gate: no tag" "" "$(tags_of "$C")$(origin_tags)"
assert_eq "AC4 --dry-run without a gate: the suite did not run" "0" "$(suite_runs)"

# a gate sealed for an older commit is stale once a file outside evals/results changed after it (the suite_mark commit)
setup; suite_mark
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC4 a gate for an older commit (a change outside evals/results since) -> exit 1" 1
assert_contains "AC4 the refusal names the gate" "$OUT" "release refused: release gate:"
assert_contains "AC4 the reason says what changed" "$OUT" "changes outside evals/results since"
assert_eq "AC4 stale gate: no tag, nothing pushed" "" "$(tags_of "$C")$(origin_tags)"
assert_eq "AC4 stale gate: the suite did not run" "0" "$(suite_runs)"

# a committed gate whose recomputed verdict is fail (item E2 has a negative delta)
NOGATE=1 setup; suite_mark
rgf_seal "$C" E2 && ( cd "$C" && git push -q origin main )
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC4 a committed gate with verdict fail -> exit 1" 1
assert_contains "AC4 the refusal names the gate" "$OUT" "release refused: release gate:"
assert_contains "AC4 the refusal names the failing item" "$(printf '%s\n' "$OUT" | grep 'release refused: release gate:')" "E2"
assert_eq "AC4 failing gate: no tag, nothing pushed" "" "$(tags_of "$C")$(origin_tags)"
assert_eq "AC4 failing gate: the suite did not run" "0" "$(suite_runs)"

# a committed passing gate: the old behaviour
NOGATE=1 setup; suite_mark; reseal
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC4 passing committed gate, --dry-run -> exit 0" 0
assert_contains "AC4 --dry-run prints the gate outcome (pass)" "$OUT" "release gate: pass"
assert_contains "AC4 --dry-run still reaches 'would tag'" "$OUT" "would tag"
assert_eq "AC4 --dry-run with a passing gate still runs the suite once" "1" "$(suite_runs)"
NOGATE=1 setup; suite_mark; reseal
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC4 passing committed gate: release exit 0" 0
assert_contains "AC4 passing gate: the tag is in the origin" "$(origin_tags)" "v1.2.3"
assert_eq "AC4 passing gate: the suite ran once" "1" "$(suite_runs)"

echo "AC4': release.sh maps the exit codes of --check (0 goes on, 1 refuses, anything else is an environment error)"
NOGATE=1 setup; gate_stub 0; suite_mark
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC4' --check exit 0 goes on: release exit 0" 0
assert_contains "AC4' the tag exists in the origin" "$(origin_tags)" "v1.2.3"
assert_eq "AC4' the suite ran once" "1" "$(suite_runs)"
assert_contains "AC4' the tool was called as 'release-gate.sh --check HEAD'" "$(cat "$GLOG")" "--check HEAD"
NOGATE=1 setup; gate_stub 1; suite_mark
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC4' --check exit 1 refuses: release exit 1" 1
assert_contains "AC4' the refusal carries the first reason line only" "$(printf '%s\n' "$OUT" | grep 'release refused: release gate:')" "release refused: release gate: stub reason one"
assert_not_contains "AC4' the refusal line does not carry the second reason line" "$(printf '%s\n' "$OUT" | grep 'release refused: release gate:')" "stub reason two"
assert_eq "AC4' exit 1: no tag, nothing pushed" "" "$(tags_of "$C")$(origin_tags)"
assert_eq "AC4' exit 1: the suite did not run" "0" "$(suite_runs)"
for GRC in 2 3 4; do
  NOGATE=1 setup; gate_stub "$GRC"; suite_mark
  run_in "$C" bash tools/release.sh v1.2.3
  assert_rc "AC4' --check exit $GRC is an environment error: release exit 3" 3
  assert_eq "AC4' exit $GRC: no tag, nothing pushed" "" "$(tags_of "$C")$(origin_tags)"
  assert_eq "AC4' exit $GRC: the suite did not run" "0" "$(suite_runs)"
  assert_not_contains "AC4' exit $GRC: it does not claim a release" "$OUT" "released v1.2.3"
done
NOGATE=1 setup; gate_stub 3; suite_mark
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC4' --dry-run with --check exit 3 -> exit 3" 3


t_summary
