#!/usr/bin/env bash
# Tests for tools/ship.sh v0.37 AC10: every step line carries a timestamp and the elapsed seconds, the whole output (stdout and stderr)
# is also written to a log file (default .agents/handoff/ship-<tag>-<YYYYMMDD-HHMMSS>.log in the repo, PB_SHIP_LOG=<file> overrides),
# and a successful ship prints "total time: Ns". Step lines still START with "== ". Spec: docs/v0.37-spec.md AC10.
# Shared setup (fake gh, stubs, fx, sh_run, steps): ship-fixture.sh.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/ship-fixture.sh"

TS_RE='^== \[[0-9][0-9]:[0-9][0-9]:[0-9][0-9] \+[0-9]+s\] .'
# step_lines TEXT -> the lines starting with '== '
step_lines() { printf '%s\n' "$1" | grep '^== ' || true; }
# bad_step_lines TEXT -> the '== ' lines that lack the timestamp
bad_step_lines() { step_lines "$1" | grep -Ev "$TS_RE" || true; }

echo "AC10 every step line is '== [HH:MM:SS +Ns] <title>'"
fx
unset PB_SHIP_LOG
sh_run 12 v1.2.3 --yes
assert_rc "AC10 --yes flow exits 0" 0
NSTEP="$(step_lines "$OUT" | grep -c . || true)"
if [ "$NSTEP" -ge 6 ]; then t_ok "AC10 still at least 6 lines start with '== ' ($NSTEP)"; else t_bad "AC10 still at least 6 lines start with '== '" "$NSTEP in: $OUT"; fi
assert_eq "AC10 no '== ' step line lacks the timestamp" "" "$(bad_step_lines "$OUT")"
assert_contains "AC10 the step title is kept after the timestamp" "$(step_lines "$OUT")" "] check PR #12"
assert_contains "AC10 the release step title keeps the tag" "$(step_lines "$OUT")" "] release v1.2.3"
assert_eq "AC10 the flow order is unchanged" "$FULL_YES" "$(steps)"
SECS="$(step_lines "$OUT" | sed -n 's/^== \[[0-9:]* +\([0-9][0-9]*\)s\].*/\1/p' | tr '\n' ' ')"
SORTED="$(printf '%s\n' $SECS | sort -n | tr '\n' ' ')"
assert_eq "AC10 elapsed seconds never go backwards" "$SORTED" "$SECS"
FIRSTSEC="${SECS%% *}"
if [ -n "$FIRSTSEC" ] && [ "$FIRSTSEC" -le 5 ]; then t_ok "AC10 the first step is at most +5s after ship started ($FIRSTSEC)"; else t_bad "AC10 the first step is at most +5s after ship started" "first elapsed = [$FIRSTSEC] in: $OUT"; fi

echo "AC10 the stub steps' own output and the step lines of the dry-run path carry the timestamp too"
fx
unset PB_SHIP_LOG
run_in "$F/repo" bash -c 'printf "y\ny\ny\n" | bash tools/ship.sh 12 v1.2.3' 
# no terminal: ask() refuses, but the steps before it were printed with timestamps
assert_eq "AC10 without --yes: every printed '== ' line has the timestamp" "" "$(bad_step_lines "$OUT")"
if [ "$(step_lines "$OUT" | grep -c . || true)" -ge 1 ]; then t_ok "AC10 without --yes: at least one step line printed"; else t_bad "AC10 without --yes: at least one step line printed" "$OUT"; fi
NTS="$(step_lines "$OUT" | grep -Ec "$TS_RE" || true)"
if [ "$NTS" -ge 2 ]; then t_ok "AC10 without --yes: at least 2 timestamped step lines printed ($NTS)"; else t_bad "AC10 without --yes: at least 2 timestamped step lines printed" "$NTS in: $OUT"; fi

echo "AC10 default log file: .agents/handoff/ship-<tag>-<YYYYMMDD-HHMMSS>.log in the repo"
fx
unset PB_SHIP_LOG
rm -rf "$F/repo/.agents/handoff"
sh_run 12 v1.2.3 --yes
assert_rc "AC10 default log: exit 0" 0
LOGS="$(ls "$F/repo/.agents/handoff"/ship-v1.2.3-*.log 2>/dev/null || true)"
assert_eq "AC10 default log: exactly one ship-v1.2.3-*.log file" "1" "$(printf '%s\n' "$LOGS" | grep -c . || true)"
LOGBASE="$(basename "$LOGS")"
if printf '%s' "$LOGBASE" | grep -Eq '^ship-v1\.2\.3-[0-9]{8}-[0-9]{6}\.log$'; then t_ok "AC10 default log name is ship-v1.2.3-YYYYMMDD-HHMMSS.log"; else t_bad "AC10 default log name is ship-v1.2.3-YYYYMMDD-HHMMSS.log" "got [$LOGBASE]"; fi
LOGTXT="$(cat "$LOGS" 2>/dev/null || true)"
assert_eq "AC10 the log has the same step lines as the screen output" "$(step_lines "$OUT")" "$(step_lines "$LOGTXT")"
assert_contains "AC10 the log has the final shipped line" "$LOGTXT" "shipped v1.2.3"
assert_contains "AC10 the log has the stubbed release.sh output (stdout of a child step)" "$LOGTXT" "$(printf '%s\n' "$OUT" | grep -v '^==' | head -n 1)"

echo "AC10 another tag names the default log after that tag"
fx
export FAKE_PR=345 FAKE_TAG=v10.20.30
unset PB_SHIP_LOG
sh_run 345 v10.20.30 --yes
assert_rc "AC10 v10.20.30: exit 0" 0
assert_eq "AC10 the log is named after v10.20.30" "1" "$(ls "$F/repo/.agents/handoff"/ship-v10.20.30-*.log 2>/dev/null | grep -c . || true)"

echo "AC10 PB_SHIP_LOG=<file> overrides the path"
fx
rm -rf "$F/repo/.agents/handoff"
CUSTOM="$F/custom dir/my ship.log"
mkdir -p "$F/custom dir"
export PB_SHIP_LOG="$CUSTOM"
sh_run 12 v1.2.3 --yes
unset PB_SHIP_LOG
assert_rc "AC10 PB_SHIP_LOG: exit 0" 0
assert_file "AC10 PB_SHIP_LOG: the log is written to the given file (path with a space)" "$CUSTOM"
assert_eq "AC10 PB_SHIP_LOG: the log has the same step lines as the screen output" "$(step_lines "$OUT")" "$(step_lines "$(cat "$CUSTOM" 2>/dev/null || true)")"
assert_eq "AC10 PB_SHIP_LOG: no default ship-*.log is written as well" "0" "$(ls "$F/repo/.agents/handoff"/ship-*.log 2>/dev/null | grep -c . || true)"

echo "AC10 a successful ship ends with 'total time: Ns'"
fx
export PB_SHIP_LOG="$F/ok.log"
sh_run 12 v1.2.3 --yes
unset PB_SHIP_LOG
assert_rc "AC10 total time: exit 0" 0
TT="$(printf '%s\n' "$OUT" | grep -E '^total time: [0-9]+s$' || true)"
assert_eq "AC10 exactly one 'total time: Ns' line on screen" "1" "$(printf '%s\n' "$TT" | grep -c . || true)"
assert_contains "AC10 'total time: Ns' is in the log" "$(cat "$F/ok.log" 2>/dev/null || true)" "total time: "
assert_contains "AC10 shipped line is still printed" "$OUT" "shipped v1.2.3"
LAST2="$(printf '%s\n' "$OUT" | tail -n 2 | tr '\n' '|')"
case "$LAST2" in
  "shipped v1.2.3|total time: "*s"|"|"total time: "*s"|shipped v1.2.3|") t_ok "AC10 the last two lines are 'shipped vX.Y.Z' and 'total time: Ns' (either order)" ;;
  *) t_bad "AC10 the last two lines are 'shipped vX.Y.Z' and 'total time: Ns' (either order)" "got: $LAST2" ;;
esac

echo "AC10 a refusal (fail()) is logged to the file, with the timestamped steps before it"
fx
export FAKE_GATE_RC=1 FAKE_GATE_MSG="no gate result for this commit (fake reason)"
export PB_SHIP_LOG="$F/refused.log"
sh_run 12 v1.2.3 --yes
unset PB_SHIP_LOG
assert_rc "AC10 refusal: ship exits 1" 1
REFLOG="$(cat "$F/refused.log" 2>/dev/null || true)"
assert_contains "AC10 refusal: the refusal line is in the log" "$REFLOG" "ship refused: release gate: no gate result for this commit (fake reason)"
assert_contains "AC10 refusal: the step lines before it are in the log, timestamped" "$(step_lines "$REFLOG")" "] check PR #12"
assert_eq "AC10 refusal: no untimestamped step line" "" "$(bad_step_lines "$REFLOG")"
assert_not_contains "AC10 refusal: no 'total time' claim in the log" "$REFLOG" "total time:"
assert_not_contains "AC10 refusal: no 'total time' claim on screen" "$OUT" "total time:"

echo "AC10 the elapsed +Ns is real: a 2 s slow step shows up in later step lines and in the total"
fx
mkdir -p "$W/slowbin"
cat > "$W/slowbin/gh" <<'EOS'
#!/usr/bin/env bash
# slow fake gh: 'run watch' takes 2 s, everything else is the plain fake gh
[ "$1 $2" = "run watch" ] && sleep 2
exec "$FAKE_GH_REAL" "$@"
EOS
chmod +x "$W/slowbin/gh"
export FAKE_GH_REAL="$BIN/gh"
export PATH="$W/slowbin:$PATH"
export PB_SHIP_LOG="$F/slow.log"
sh_run 12 v1.2.3 --yes
unset PB_SHIP_LOG
export PATH="$BIN:$ORIG_PATH"
assert_rc "AC10 slow step: exit 0" 0
SLOWSECS="$(step_lines "$OUT" | sed -n 's/^== \[[0-9:]* +\([0-9][0-9]*\)s\].*/\1/p' | tr '\n' ' ')"
LASTSEC="$(printf '%s\n' $SLOWSECS | tail -n 1)"
if [ -n "$LASTSEC" ] && [ "$LASTSEC" -ge 2 ]; then t_ok "AC10 slow step: the last step line shows +N with N>=2 ($LASTSEC)"; else t_bad "AC10 slow step: the last step line shows +N with N>=2" "elapsed list = [$SLOWSECS] in: $OUT"; fi
TOTSEC="$(printf '%s\n' "$OUT" | sed -n 's/^total time: \([0-9][0-9]*\)s$/\1/p')"
if [ -n "$TOTSEC" ] && [ "$TOTSEC" -ge 2 ]; then t_ok "AC10 slow step: total time >= 2s ($TOTSEC)"; else t_bad "AC10 slow step: total time >= 2s" "total = [$TOTSEC] in: $OUT"; fi

echo "AC10 the dirty-tree check exempts the ship log by exact path, not by substring"
# dirty_case LOGNAME EXTRA_FILE_NAME -> relative PB_SHIP_LOG, an extra untracked file whose name contains it
dirty_case() {
  fx
  printf 'dirt\n' > "$F/repo/$2"
  export PB_SHIP_LOG="$1"
  sh_run 12 v1.2.3 --yes
  unset PB_SHIP_LOG
}
dirty_case x xyz
assert_rc "AC10 log 'x' + untracked 'xyz': ship refuses (exit 1)" 1
assert_contains "AC10 log 'x' + untracked 'xyz': says the work tree is not clean" "$OUT" "work tree is not clean"
assert_eq "AC10 log 'x' + untracked 'xyz': nothing merged" "0" "$(origin_merges)"
assert_eq "AC10 log 'x' + untracked 'xyz': no merge call (PUT or gh pr merge)" "0" "$(merges_logged)"
dirty_case log "my log"
assert_rc "AC10 log 'log' + untracked 'my log': ship refuses (exit 1)" 1
assert_contains "AC10 log 'log' + untracked 'my log': says the work tree is not clean" "$OUT" "work tree is not clean"
assert_eq "AC10 log 'log' + untracked 'my log': nothing merged" "0" "$(origin_merges)"
fx
printf 'one\n' > "$F/repo/x-tracked.txt"
( cd "$F/repo" && git add x-tracked.txt && GITID commit -qm "tracked x" ) || echo "fixture setup failed"
printf 'two\n' >> "$F/repo/x-tracked.txt"
export PB_SHIP_LOG="x"
sh_run 12 v1.2.3 --yes
unset PB_SHIP_LOG
assert_rc "AC10 log 'x' + modified tracked 'x-tracked.txt': ship refuses (exit 1)" 1
assert_contains "AC10 log 'x' + modified tracked file: says the work tree is not clean" "$OUT" "work tree is not clean"
assert_eq "AC10 log 'x' + modified tracked file: nothing merged" "0" "$(origin_merges)"
fx
export PB_SHIP_LOG="x"
sh_run 12 v1.2.3 --yes
unset PB_SHIP_LOG
assert_rc "AC10 log 'x' alone (the log file is the only new file): ship does not refuse" 0
assert_not_contains "AC10 log 'x' alone: no 'work tree is not clean'" "$OUT" "work tree is not clean"
fx
unset PB_SHIP_LOG
printf 'dirt\n' > "$F/repo/stray.txt"
sh_run 12 v1.2.3 --yes
assert_rc "AC10 default log path + untracked 'stray.txt': ship refuses (exit 1)" 1
assert_contains "AC10 default log path + untracked file: says the work tree is not clean" "$OUT" "work tree is not clean"
assert_eq "AC10 default log path + untracked file: nothing merged" "0" "$(origin_merges)"

echo "AC10 the log exemption does not depend on how git spells the repo root (Git Bash: pwd -P gives /d/a/x, git gives D:/a/x)"
# skew_git: a git that is the fixture git except 'rev-parse --show-toplevel', which prints the SAME directory spelled differently
# (a trailing '/.'): a prefix strip of the pwd -P path against it fails, as it does on Windows between /d/a/x and D:/a/x.
SKEWBIN="$W/skewbin"; mkdir -p "$SKEWBIN"
cat > "$SKEWBIN/git" <<EOS
#!/usr/bin/env bash
if [ "\$*" = "rev-parse --show-toplevel" ]; then
  t="\$("$BIN/git" rev-parse --show-toplevel)" || exit \$?
  printf '%s/.\n' "\$t"
  exit 0
fi
exec "$BIN/git" "\$@"
EOS
chmod +x "$SKEWBIN/git"
# probe (L-0004): the skew git really prints a different spelling of the same directory
fx
export PATH="$SKEWBIN:$BIN:$ORIG_PATH"
SK_TOP="$(cd "$F/repo" && git rev-parse --show-toplevel)"
SK_REAL="$(cd "$F/repo" && "$BIN/git" rev-parse --show-toplevel)"
export PATH="$BIN:$ORIG_PATH"
if [ "$SK_TOP" != "$SK_REAL" ] && [ "$SK_TOP" -ef "$SK_REAL" ]; then
  t_ok "AC10 skew control: the fake git spells the repo root differently ($SK_TOP vs $SK_REAL) and it is the same directory"
else
  t_bad "AC10 skew control: the fake git spells the repo root differently and it is the same directory" "skew=[$SK_TOP] real=[$SK_REAL]"
fi
# skew_run LOG|"" EXTRA_FILE|"" -> a --yes ship with the skewed toplevel
skew_run() {
  fx
  mkdir -p "$F/repo/.agents/handoff" "$F/repo/logs"
  [ -z "$2" ] || printf 'dirt\n' > "$F/repo/$2"
  if [ -n "$1" ]; then export PB_SHIP_LOG="${1//@REPO@/$F/repo}"; else unset PB_SHIP_LOG; fi
  export PATH="$SKEWBIN:$BIN:$ORIG_PATH"
  sh_run 12 v1.2.3 --yes
  export PATH="$BIN:$ORIG_PATH"
  unset PB_SHIP_LOG
}
skew_run "" ""
assert_rc "AC10 skewed toplevel + default log path: ship exits 0 (the log is not dirt)" 0
assert_not_contains "AC10 skewed toplevel + default log path: no 'work tree is not clean'" "$OUT" "work tree is not clean"
skew_run "@REPO@/logs/my ship.log" ""
assert_rc "AC10 skewed toplevel + absolute PB_SHIP_LOG inside the repo (subdir, space): ship exits 0" 0
assert_not_contains "AC10 skewed toplevel + absolute PB_SHIP_LOG in a subdir: no 'work tree is not clean'" "$OUT" "work tree is not clean"
skew_run "@REPO@/root.log" ""
assert_rc "AC10 skewed toplevel + absolute PB_SHIP_LOG at the repo root: ship exits 0" 0
assert_not_contains "AC10 skewed toplevel + absolute PB_SHIP_LOG at the repo root: no 'work tree is not clean'" "$OUT" "work tree is not clean"
skew_run "" "stray.txt"
assert_rc "AC10 skewed toplevel + default log + untracked 'stray.txt': ship still refuses (exit 1)" 1
assert_contains "AC10 skewed toplevel + untracked file: says the work tree is not clean" "$OUT" "work tree is not clean"
assert_eq "AC10 skewed toplevel + untracked file: nothing merged" "0" "$(origin_merges)"
skew_run "@REPO@/logs/x.log" "logs/other.log"
assert_rc "AC10 skewed toplevel + log 'logs/x.log' + untracked 'logs/other.log' beside it: ship refuses (exit 1)" 1
assert_eq "AC10 skewed toplevel + sibling of the log: nothing merged" "0" "$(origin_merges)"

echo "AC10 a usage error writes no log and no timestamped step"
fx
rm -rf "$F/repo/.agents/handoff"
unset PB_SHIP_LOG
sh_run 12
assert_rc "AC10 usage error exits 2" 2
assert_eq "AC10 usage error: no ship log file" "0" "$(ls "$F/repo/.agents/handoff"/ship-*.log 2>/dev/null | grep -c . || true)"

t_summary
