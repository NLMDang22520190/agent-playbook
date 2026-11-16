#!/usr/bin/env bash
# Shared setup of tests/test-release-ci-skip.sh and tests/test-release-gate-once.sh (v0.37 slice S9, AC11): a throw-away clone of a
# bare origin that ships the REAL tools/release.sh and tools/check-release.sh, plus
#   - a STUB tools/release-gate.sh: logs its arguments to $PB_TEST_GATE_LOG, exit code $PB_TEST_GATE_RC (default 0), on a failure prints
#     one reason line;
#   - a STUB tests/run-all.sh: appends a line to $PB_TEST_SUITE_LOG, prints $PB_TEST_SUITE_OUT (printf %b), exit $PB_TEST_SUITE_RC.
# The fake gh of tests/release-gate-fixture.sh (rgf_gh_install) serves the check-runs REST call; it is put first on PATH, logs every call
# and refuses any command that is not `gh api`. No real network and no real gh are used. Source it after lib.sh and release-gate-fixture.sh.
# It is not a suite: run-all.sh only starts tests/test-*.sh.
REL_SRC="$PB_ROOT/tools/release.sh"
export PLAYBOOK_HOME="$(mk_tmp)"
G() { git -c user.email=t@example.invalid -c user.name=tester -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }
rc_work="$(mk_tmp)"
export PB_TEST_GATE_LOG="$rc_work/gate.log" PB_TEST_SUITE_LOG="$rc_work/suite.log"
export PB_GATE_REPO="acme/widgets"
unset PB_GATE_CACHE_DIR PB_TEST_GATE_RC PB_TEST_SUITE_OUT PB_TEST_SUITE_RC
rgf_gh_install "$rc_work/gh"
ORIG_PATH="$PATH"
export PATH="$RGF_GH/bin:$ORIG_PATH"

# rc_setup -> sets C (clone) and O (bare origin); main pushed, VERSION 1.2.3 with a CHANGELOG entry; logs emptied; gh green
rc_setup() {
  local w; w="$(mk_tmp)"
  O="$w/origin.git"; C="$w/clone"
  git init -q --bare "$O"; git -C "$O" symbolic-ref HEAD refs/heads/main
  mkdir -p "$C/tools" "$C/tests" "$C/scripts"
  cp "$PB_ROOT/tools/check-release.sh" "$C/tools/"
  cp "$PB_ROOT/scripts/lib.sh" "$C/scripts/"
  cp "$REL_SRC" "$C/tools/release.sh"
  cat > "$C/tools/release-gate.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${PB_TEST_GATE_LOG:?}"
if [ "${PB_TEST_GATE_RC:-0}" = 0 ]; then echo "release gate: pass (stub)"; exit 0; fi
echo "stub gate failure"; exit "$PB_TEST_GATE_RC"
STUB
  cat > "$C/tests/run-all.sh" <<'STUB'
#!/usr/bin/env bash
printf 'ran\n' >> "${PB_TEST_SUITE_LOG:?}"
[ -z "${PB_TEST_SUITE_OUT:-}" ] || printf '%b' "$PB_TEST_SUITE_OUT"
exit "${PB_TEST_SUITE_RC:-0}"
STUB
  printf '1.2.3\n' > "$C/VERSION"
  printf '# Changelog\n\n## 1.2.3 - 2026-01-01\n- thing\n' > "$C/CHANGELOG.md"
  ( cd "$C" && git init -q && git checkout -q -b main && G add -A && G commit -qm init &&
    git remote add origin "$O" && git push -q origin main ) || { echo "fixture setup failed"; exit 3; }
  : > "$PB_TEST_GATE_LOG"; : > "$PB_TEST_SUITE_LOG"
  unset PB_GATE_CACHE_DIR PB_TEST_GATE_RC PB_TEST_SUITE_OUT PB_TEST_SUITE_RC
  export PATH="$RGF_GH/bin:$ORIG_PATH" PB_GATE_REPO="acme/widgets"
  rgf_gh_green
  real_green_runs   # CI-green needs the three aggregators (ci_state need list), so the default green carries them
}
# real_green_runs [EXTRA...] -> serve the check runs of a push to main whose tree was reused: the three aggregators success, shards
# skipped (RC_GREEN), plus EXTRA "ID|NAME|STATUS|CONCLUSION" runs
real_green_runs() { rgf_gh_runs "${RC_GREEN[@]}" "$@"; }
RC_GREEN=("124850217910|test (ubuntu-latest)|completed|success" "124853028073|test (macos-latest)|completed|success"
  "124854622507|test (windows-latest)|completed|success" "124850217855|macos shard 1/2|completed|skipped"
  "124850218254|windows shard 1/10|completed|skipped" "124850191813|changes|completed|success")
suite_runs() { grep -c . "$PB_TEST_SUITE_LOG" || true; }
gate_runs() { grep -c . "$PB_TEST_GATE_LOG" || true; }
check_run_calls() { grep -c 'check-runs' "$RGF_GH/gh.log" || true; }
tags_of() { git -C "$1" tag -l | tr '\n' ' '; }
# commit_push MSG -> one more commit on main, pushed (HEAD == origin/main stays true)
commit_push() { ( cd "$C" && printf '%s\n' "$1" > "f-$1.txt" && G add -A && G commit -qm "$1" && git push -q origin main ); }
# set_readme TEXT -> committed + pushed README.md; the run-all stub prints suites that add up to 9 (passed + skipped)
set_readme() {
  printf '%s' "$1" > "$C/README.md"
  ( cd "$C" && G add -A && G commit -qm readme && git push -q origin main ) || echo "fixture setup failed: readme"
  export PB_TEST_SUITE_OUT='test-a.sh: 5 passed, 0 failed\ntest-b.sh: 2 passed, 0 failed, 2 skipped\n'
}
