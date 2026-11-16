#!/usr/bin/env bash
# Tests for v0.37 slice S9, AC11 (Q8c): `release-gate.sh --check` runs once per sha within one ship. tools/ship.sh exports
# PB_GATE_CACHE_DIR (a temporary directory it removes on exit); tools/release.sh, when PB_GATE_CACHE_DIR is set, records a PASSING gate
# check as a file named by the HEAD sha and reuses it, printing "release gate: pass (cached for <sha> in this ship)", instead of calling
# the gate again. A failing gate is never cached. Without PB_GATE_CACHE_DIR (a standalone release.sh) nothing changes: every run calls the gate.
# Spec: docs/v0.37-spec.md AC11. Part 1: release.sh alone (release-ci-fixture.sh: real release.sh, stub gate that logs its calls).
# Part 2: ship.sh end to end (ship-fixture.sh: fake gh, the REAL release.sh with a stub gate) through a pseudo-terminal, so that ship
# runs `release.sh --dry-run` and then `release.sh` on the same HEAD.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/release-gate-fixture.sh"
command -v node >/dev/null 2>&1 || { t_skip 1 "node missing (the fake gh needs it)"; t_summary; exit $?; }
. "$(dirname "$0")/release-ci-fixture.sh"

# every case here keeps CI "not green" for the CI read of the same slice, so the suite stub runs and only the gate calls are under test
rgf_gh_fail all
cached_sha() { printf '%s\n' "$1" | sed -n 's/^release gate: pass (cached for \([0-9a-f]*\) in this ship)$/\1/p' | head -n 1; }

echo "AC11 standalone release.sh (no PB_GATE_CACHE_DIR): every run calls the gate"
rc_setup; rgf_gh_fail all
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC11 standalone run 1 -> exit 0" 0
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC11 standalone run 2 -> exit 0" 0
assert_eq "AC11 standalone twice: the gate was called twice" "2" "$(gate_runs)"
assert_not_contains "AC11 standalone: nothing says 'cached'" "$OUT" "cached"
assert_eq "AC11 standalone: both calls are '--check HEAD'" "--check HEAD
--check HEAD" "$(cat "$PB_TEST_GATE_LOG")"
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC11 standalone real release after two dry runs -> exit 0" 0
assert_eq "AC11 standalone: three runs, three gate calls" "3" "$(gate_runs)"

echo "AC11 with PB_GATE_CACHE_DIR a passing check is recorded per sha and reused"
rc_setup; rgf_gh_fail all
CD="$(mk_tmp)/cache"; mkdir -p "$CD"; export PB_GATE_CACHE_DIR="$CD"
HEAD1="$(git -C "$C" rev-parse HEAD)"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC11 cache dir, first run -> exit 0" 0
assert_eq "AC11 cache dir, first run: the gate is called" "1" "$(gate_runs)"
assert_contains "AC11 cache dir, first run: the gate's own output is printed" "$OUT" "release gate: pass (stub)"
assert_not_contains "AC11 cache dir, first run: nothing is cached yet" "$OUT" "cached for"
assert_file "AC11 the pass is recorded as a file named by the full HEAD sha" "$CD/$HEAD1"
run_in "$C" bash tools/release.sh v1.2.3
assert_rc "AC11 cache dir, second run (the real release) -> exit 0" 0
assert_eq "AC11 cache dir, second run: the gate is NOT called again (one call for the sha)" "1" "$(gate_runs)"
CS="$(cached_sha "$OUT")"
if [ -n "$CS" ] && [ "${#CS}" -ge 7 ] && [ "${HEAD1#"$CS"}" != "$HEAD1" ]; then t_ok "AC11 second run prints 'release gate: pass (cached for <sha> in this ship)' with HEAD's sha ($CS)"
else t_bad "AC11 second run prints 'release gate: pass (cached for <sha> in this ship)' with HEAD's sha" "sha=[$CS] HEAD=$HEAD1 in: $OUT"; fi
assert_not_contains "AC11 cached run does not print the stub's own output again" "$OUT" "release gate: pass (stub)"
assert_contains "AC11 the second run still tags" "$(tags_of "$O")" "v1.2.3"
assert_eq "AC11 the cache dir holds only the one file for the sha" "$HEAD1" "$(ls "$CD")"

echo "AC11 the cache is per sha: another HEAD is checked again"
rc_setup; rgf_gh_fail all
CD="$(mk_tmp)/cache"; mkdir -p "$CD"; export PB_GATE_CACHE_DIR="$CD"
HEAD1="$(git -C "$C" rev-parse HEAD)"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_eq "AC11 sha A: gate called" "1" "$(gate_runs)"
commit_push second
HEAD2="$(git -C "$C" rev-parse HEAD)"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC11 sha B -> exit 0" 0
assert_eq "AC11 sha B differs from sha A: the gate is called again (2 calls)" "2" "$(gate_runs)"
assert_not_contains "AC11 sha B: not served from the cache of sha A" "$OUT" "cached for"
assert_file "AC11 sha A recorded" "$CD/$HEAD1"
assert_file "AC11 sha B recorded" "$CD/$HEAD2"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_eq "AC11 sha B again: served from the cache (still 2 calls)" "2" "$(gate_runs)"
assert_contains "AC11 sha B again: says cached" "$OUT" "release gate: pass (cached for "

echo "AC11 a failing gate is never cached"
for grc in 1 3; do
  rc_setup; rgf_gh_fail all
  CD="$(mk_tmp)/cache"; mkdir -p "$CD"; export PB_GATE_CACHE_DIR="$CD"
  export PB_TEST_GATE_RC="$grc"
  run_in "$C" bash tools/release.sh v1.2.3 --dry-run
  assert_eq "AC11 gate exit $grc: exit code passed on (1 refused, 3 environment)" "$grc" "$RC"
  assert_eq "AC11 gate exit $grc: nothing was recorded in the cache dir" "" "$(ls -A "$CD")"
  run_in "$C" bash tools/release.sh v1.2.3 --dry-run
  assert_eq "AC11 gate exit $grc: the second run calls the gate again (2 calls)" "2" "$(gate_runs)"
  assert_not_contains "AC11 gate exit $grc: the failure is not reported as cached" "$OUT" "cached for"
  unset PB_TEST_GATE_RC
  run_in "$C" bash tools/release.sh v1.2.3 --dry-run
  assert_rc "AC11 gate exit $grc: once the gate passes, the run goes on -> exit 0" 0
  assert_eq "AC11 gate exit $grc: the passing third run called the gate (3 calls)" "3" "$(gate_runs)"
  assert_file "AC11 gate exit $grc: the pass is now recorded" "$CD/$(git -C "$C" rev-parse HEAD)"
done
rc_setup; rgf_gh_fail all
CD="$(mk_tmp)/cache"; mkdir -p "$CD"; export PB_GATE_CACHE_DIR="$CD"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
export PB_TEST_GATE_RC=1
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC11 a pass cached for this sha is reused even if the gate would fail now -> exit 0" 0
assert_eq "AC11 cached pass: still one gate call" "1" "$(gate_runs)"
unset PB_TEST_GATE_RC

echo "AC11 an unusable cache dir does not break the release"
rc_setup; rgf_gh_fail all
export PB_GATE_CACHE_DIR="$(mk_tmp)/does/not/exist"
run_in "$C" bash tools/release.sh v1.2.3 --dry-run
assert_rc "AC11 PB_GATE_CACHE_DIR pointing at a missing directory: the gate is called and the run goes on -> exit 0" 0
assert_eq "AC11 missing cache dir: the gate was called" "1" "$(gate_runs)"
unset PB_GATE_CACHE_DIR

# ---- part 2: ship.sh end to end ----
. "$(dirname "$0")/ship-fixture.sh"
PTY_OK=0
if [ -z "${PB_NO_PTY:-}" ] && command -v python3 >/dev/null 2>&1; then
  OUT="$(python3 "$W/ptyrun.py" -- bash -c '[ -t 0 ] && echo isatty' 2>/dev/null)"
  case "$OUT" in *isatty*) PTY_OK=1 ;; esac
fi
# fx_real_release -> the fixture repo of ship-fixture.sh with the REAL tools/release.sh (stub gate, stub run-all) committed on main
# and in the PR head, so ship's dry run and real run both reach the gate; the ship log goes outside the repository
fx_real_release() {
  fx
  unset PB_GATE_CACHE_DIR
  ( cd "$F/repo" && git switch -q main &&
    mkdir -p scripts && cp "$PB_ROOT/tools/release.sh" tools/release.sh && cp "$PB_ROOT/tools/check-release.sh" tools/check-release.sh &&
    cp "$PB_ROOT/scripts/lib.sh" scripts/lib.sh &&
    printf '#!/usr/bin/env bash\nexit 0\n' > tests/run-all.sh &&
    printf '# Changelog\n\n## 1.2.3 - 2026-01-01\n- thing\n' > CHANGELOG.md &&
    git add -A && GITID commit -qm "real release.sh" && git push -q origin main &&
    git branch -f feat/x main && git push -q -f origin feat/x:refs/heads/feat/x main:refs/pull/12/head && git switch -q feat/x ) ||
    { echo "fixture setup failed: real release.sh"; exit 3; }
  export PB_SHIP_LOG="$F/ship.log" PB_GATE_REPO=acme/widgets
}
# release_gate_calls -> the logged gate calls made by release.sh ('--check HEAD'; ship's own pre-merge call names the PR head sha)
release_gate_calls() { grep -c '^release-gate.sh --check HEAD$' "$FAKE_LOG" || true; }
# dup_shas -> shas the gate was asked about more than once ('HEAD' resolved to the HEAD sha of the repo after the ship)
dup_shas() {
  local hsha; hsha="$(git -C "$F/repo" rev-parse main)"
  sed -n 's/^release-gate.sh --check //p' "$FAKE_LOG" | sed "s/^HEAD\$/$hsha/" | sort | uniq -d
}

if [ "$PTY_OK" = 1 ]; then
  echo "AC11 ship with its questions (dry run, then the real release on the same HEAD): the gate check runs once per sha"
  fx_real_release
  TD="$(mk_tmp)/tmp"; mkdir -p "$TD"
  OUT="$(cd "$F/repo" && TMPDIR="$TD" python3 "$W/ptyrun.py" y y -- bash tools/ship.sh 12 v1.2.3 2>&1)"; RC=$?
  assert_rc "AC11 ship with the questions -> exit 0" 0
  assert_eq "AC11 ship ran the dry run (release.sh printed 'would tag') and then the real release.sh (tag created)" "1" "$(printf '%s\n' "$OUT" | grep -c '^dry run: would tag')"
  assert_contains "AC11 the dry run step ran" "$OUT" "] release v1.2.3 (dry run)"
  assert_contains "AC11 shipped" "$OUT" "shipped v1.2.3"
  assert_eq "AC11 the gate was asked 'release-gate.sh --check HEAD' once by release.sh across the dry run and the real run" "1" "$(release_gate_calls)"
  assert_eq "AC11 no sha was gate-checked more than once in the whole ship" "" "$(dup_shas)"
  assert_contains "AC11 the second release.sh run says its gate pass was cached" "$OUT" "release gate: pass (cached for "
  assert_contains "AC11 the real release created the tag" "$(git -C "$F/origin.git" tag -l)" "v1.2.3"
  assert_eq "AC11 ship removed its cache directory (nothing left in TMPDIR)" "" "$(ls -A "$TD")"

  echo "AC11 a failing gate in ship's dry run is not cached for the real run"
  fx_real_release
  # the pre-merge check passes; flip the stub to fail only for release.sh's own call (it passes the literal HEAD)
  cat > "$F/repo/tools/release-gate.sh.new" <<'STUB'
#!/usr/bin/env bash
echo "release-gate.sh $*" >> "$FAKE_LOG"
if [ "$2" = HEAD ]; then
  n="$(grep -c '^release-gate.sh --check HEAD$' "$FAKE_LOG")"
  if [ "$n" -le 1 ]; then echo "stub gate failure"; exit 1; fi
fi
echo "release gate: pass (stub)"; exit 0
STUB
  ( cd "$F/repo" && git switch -q main && mv tools/release-gate.sh.new tools/release-gate.sh && chmod 755 tools/release-gate.sh &&
    git add -A && GITID commit -qm "flaky gate stub" && git push -q origin main &&
    git branch -f feat/x main && git push -q -f origin feat/x:refs/heads/feat/x main:refs/pull/12/head && git switch -q feat/x )
  TD2="$(mk_tmp)/tmp"; mkdir -p "$TD2"
  OUT="$(cd "$F/repo" && TMPDIR="$TD2" python3 "$W/ptyrun.py" y y -- bash tools/ship.sh 12 v1.2.3 2>&1)"; RC=$?
  assert_rc "AC11 the dry run's gate failure stops ship with release.sh's exit code (1)" 1
  assert_eq "AC11 the failing dry run reached the gate once" "1" "$(release_gate_calls)"
  assert_eq "AC11 ship removed its cache directory also when it stops on a failing gate (nothing left in TMPDIR)" "" "$(ls -A "$TD2")"
else
  t_skip 12 "no pseudo-terminal (python3 pty) for the ship questions"
fi

echo "AC11 ship --yes: one release.sh run, so one gate check on HEAD"
fx_real_release
sh_run 12 v1.2.3 --yes
assert_rc "AC11 ship --yes -> exit 0" 0
assert_eq "AC11 ship --yes: release.sh asked the gate once" "1" "$(release_gate_calls)"
assert_eq "AC11 ship --yes: no sha checked twice" "" "$(dup_shas)"
assert_not_contains "AC11 ship --yes: nothing was cached (a single run)" "$OUT" "cached for"

t_summary
