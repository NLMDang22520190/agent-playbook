#!/usr/bin/env bash
# Tests for scripts/conf.sh
. "$(dirname "$0")/lib.sh"
CONF="$PB_ROOT/scripts/conf.sh"

H="$(mk_tmp)"; P="$(mk_tmp)"
export PLAYBOOK_HOME="$H"

echo "conf.sh"
run bash "$CONF" get language
assert_rc "get on missing key exits 1" 1

run bash "$CONF" set language vi --global
assert_rc "set --global ok" 0
assert_file "global file created" "$H/.agents/playbook.conf"
run bash "$CONF" get language
assert_eq "get returns global value" "vi" "$OUT"

run bash "$CONF" set language en --global
run bash "$CONF" get language
assert_eq "set overwrites" "en" "$OUT"
assert_eq "no duplicate lines" "1" "$(grep -c '^language=' "$H/.agents/playbook.conf")"

run_in "$P" bash "$CONF" set language fr --project
assert_rc "set --project ok (in a dir)" 0
assert_file "project file created" "$P/.agents/playbook.conf"
run_in "$P" bash "$CONF" get language
assert_eq "project overrides global" "fr" "$OUT"
run bash "$CONF" get language
assert_eq "global unaffected outside project" "en" "$OUT"

run bash "$CONF" set "Bad Key" x --global
assert_rc "invalid key rejected" 2
run bash "$CONF" set BADKEY x --global
assert_rc "uppercase key rejected (no locale-dependent ranges)" 2
run bash "$CONF" set k "line1
line2" --global
assert_rc "multi-line value rejected" 2

run bash "$CONF" set test_cmd "npm test -- --runInBand" --global
run bash "$CONF" get test_cmd
assert_eq "values with spaces and dashes preserved" "npm test -- --runInBand" "$OUT"

run bash "$CONF" set regex '^(a|b)/=x$' --global
run bash "$CONF" get regex
assert_eq "value containing = and regex chars preserved" '^(a|b)/=x$' "$OUT"

run_in "$P" bash "$CONF" list
assert_contains "list shows origin" "$OUT" "language=fr"
assert_contains "list marks project origin" "$OUT" "project"


echo "#11 list ignores keys that are not lowercase"
printf 'BADKEY=x\n' >> "$H/.agents/playbook.conf"
run bash "$CONF" list
assert_not_contains "#11 list skips an uppercase key line" "$OUT" "BADKEY"

echo "#1 AC1.2 generic model keys warn on set"
for r in tester implementer reviewer; do
  rm -f "$H/.agents/playbook.conf"
  ERR="$(bash "$CONF" set "model_$r" "val-$r" --global 2>&1 >/dev/null)"; RC=$?
  OUT="$ERR"
  assert_rc "AC1.2 set model_$r exits 0" 0
  assert_contains "AC1.2 model_$r warns: applies to every harness" "$ERR" "applies to every harness"
  assert_contains "AC1.2 model_$r warns: names model_<role>_<harness>" "$ERR" "model_<role>_<harness>"
  run bash "$CONF" get "model_$r"
  assert_eq "AC1.2 model_$r is still written" "val-$r" "$OUT"
  OUTONLY="$(bash "$CONF" set "model_$r" "val2-$r" --global 2>/dev/null)"
  assert_not_contains "AC1.2 model_$r warning goes to stderr, not stdout" "$OUTONLY" "applies to every harness"
done
ERR="$(bash "$CONF" set model_tester_codex cx --global 2>&1 >/dev/null)"
assert_eq "AC1.2 model_tester_codex prints nothing on stderr" "" "$ERR"
run bash "$CONF" get model_tester_codex
assert_eq "AC1.2 model_tester_codex is written" "cx" "$OUT"
ERR="$(bash "$CONF" set language vi --global 2>&1 >/dev/null)"
assert_eq "AC1.2 unrelated key prints nothing on stderr" "" "$ERR"
ERR="$(bash "$CONF" set model_testers x --global 2>&1 >/dev/null)"
assert_eq "AC1.2 near-miss key model_testers prints nothing" "" "$ERR"
ERR="$(cd "$P" && bash "$CONF" set model_reviewer pm --project 2>&1 >/dev/null)"
assert_contains "AC1.2 warning also for --project" "$ERR" "applies to every harness"

echo "pb_conf_read lookup"
printf 'dup=first
other=x
dup=second
nonl=tail' > "$H/.agents/playbook.conf"
run bash "$CONF" get dup
assert_eq "duplicate key: the last value wins" "second" "$OUT"
run bash "$CONF" get nonl
assert_eq "final line without trailing newline is read" "tail" "$OUT"
printf '
emptyv=
' >> "$H/.agents/playbook.conf"
run bash "$CONF" get emptyv
assert_rc "empty value: key present exits 0" 0
assert_eq "empty value is returned as empty" "" "$OUT"
run bash "$CONF" get absentkey
assert_rc "absent key still exits 1" 1

echo "v0.10.0 AC1.1 a project conf is kept out of git status"
# no CRLF warnings from git on Windows: they would land in the stderr we compare
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.autocrlf GIT_CONFIG_VALUE_0=false
# excl_of REPO -> absolute path of the repo's local exclude file
excl_of() { ( cd "$1" && p="$(git rev-parse --git-path info/exclude)" && case "$p" in /*) printf '%s' "$p" ;; *) printf '%s/%s' "$1" "$p" ;; esac ); }
# excl_count FILE -> how many lines are exactly the project conf path (0 when the file is missing)
excl_count() { if [ -f "$1" ]; then grep -cx '\.agents/playbook\.conf' "$1" || true; else echo 0; fi; }

R="$(mk_tmp)"; mk_repo "$R"; EX="$(excl_of "$R")"
ERR="$(cd "$R" && bash "$CONF" set language fr --project 2>&1 >/dev/null)"; RC=$?; OUT="$ERR"
assert_rc "AC1.1 set --project in a git repo exits 0" 0
assert_file "AC1.1 the project conf is written" "$R/.agents/playbook.conf"
assert_eq "AC1.1 the exclude file gets the conf path exactly once" "1" "$(excl_count "$EX")"
assert_contains "AC1.1 the notice goes to stderr and names the exclude file" "$ERR" "info/exclude"
assert_contains "AC1.1 the notice names the excluded conf" "$ERR" ".agents/playbook.conf"
assert_eq "AC1.1 git status --porcelain stays clean" "" "$(cd "$R" && git status --porcelain)"
OUTONLY="$(cd "$R" && bash "$CONF" set other x --project 2>/dev/null)"
assert_eq "AC1.1 nothing is printed on stdout" "" "$OUTONLY"
run_in "$R" bash "$CONF" get language
assert_eq "AC1.1 the value is still stored and read" "fr" "$OUT"
( cd "$R" && bash "$CONF" set language de --project ) >/dev/null 2>&1
( cd "$R" && bash "$CONF" set third 3 --project ) >/dev/null 2>&1
assert_eq "AC1.1 repeated sets do not duplicate the exclude line" "1" "$(excl_count "$EX")"
assert_eq "AC1.1 git status stays clean after repeated sets" "" "$(cd "$R" && git status --porcelain)"
ERR="$(cd "$R" && bash "$CONF" set language it --project 2>&1 >/dev/null)"
assert_not_contains "AC1.1 no second notice once the line is there" "$ERR" "info/exclude"

# an existing exclude file without a final newline keeps its own line intact
R="$(mk_tmp)"; mk_repo "$R"; EX="$(excl_of "$R")"
printf 'keepme' > "$EX"
( cd "$R" && bash "$CONF" set language fr --project ) >/dev/null 2>&1
assert_eq "AC1.1 the conf line lands on its own line after an unterminated line" "1" "$(excl_count "$EX")"
assert_eq "AC1.1 the earlier unterminated line is preserved" "1" "$(grep -cx 'keepme' "$EX" || true)"
assert_eq "AC1.1 git status clean with that exclude file" "" "$(cd "$R" && git status --porcelain)"

# the local exclude file (or its directory) may not exist yet
R="$(mk_tmp)"; mk_repo "$R"; EX="$(excl_of "$R")"; rm -rf "$(dirname "$EX")"
( cd "$R" && bash "$CONF" set language fr --project ) >/dev/null 2>&1
assert_eq "AC1.1 a missing exclude file is created with the line" "1" "$(excl_count "$EX")"
assert_eq "AC1.1 git status clean after creating the exclude file" "" "$(cd "$R" && git status --porcelain)"

# from a subdirectory the repo's exclude is used (project root = git top-level)
R="$(mk_tmp)"; mk_repo "$R"; EX="$(excl_of "$R")"
( cd "$R/src" && bash "$CONF" set language fr --project ) >/dev/null 2>&1
assert_eq "AC1.1 set from a subdirectory excludes the top-level conf once" "1" "$(excl_count "$EX")"
assert_eq "AC1.1 git status clean (subdirectory run)" "" "$(cd "$R" && git status --porcelain)"

# a tracked (team-shared) project conf is left alone
R="$(mk_tmp)"; mk_repo "$R"; EX="$(excl_of "$R")"
mkdir -p "$R/.agents"; printf 'language=en\n' > "$R/.agents/playbook.conf"
( cd "$R" && git add -A && git commit -q -m "team conf" )
ERR="$(cd "$R" && bash "$CONF" set language fr --project 2>&1 >/dev/null)"; RC=$?; OUT="$ERR"
assert_rc "AC1.1 set --project on a tracked conf exits 0" 0
assert_eq "AC1.1 a tracked conf gets no exclude line" "0" "$(excl_count "$EX")"
assert_not_contains "AC1.1 a tracked conf gets no exclude notice" "$ERR" "exclude"
assert_contains "AC1.1 the tracked conf is still edited (shows as modified)" "$(cd "$R" && git status --porcelain)" "playbook.conf"

# already ignored (by .gitignore): no redundant line
for pat in '.agents/' '.agents/playbook.conf'; do
  R="$(mk_tmp)"; mk_repo "$R"; EX="$(excl_of "$R")"
  printf '%s\n' "$pat" > "$R/.gitignore"; ( cd "$R" && git add .gitignore && git commit -q -m ignore )
  ERR="$(cd "$R" && bash "$CONF" set language fr --project 2>&1 >/dev/null)"; RC=$?; OUT="$ERR"
  assert_rc "AC1.1 [.gitignore: $pat] set --project exits 0" 0
  assert_eq "AC1.1 [.gitignore: $pat] already ignored: no exclude line added" "0" "$(excl_count "$EX")"
  assert_not_contains "AC1.1 [.gitignore: $pat] already ignored: no exclude notice" "$ERR" "exclude"
done

# outside git: nothing to exclude, no error
N="$(mk_tmp)"
ERR="$(cd "$N" && bash "$CONF" set language fr --project 2>&1 >/dev/null)"; RC=$?; OUT="$ERR"
assert_rc "AC1.1 outside git: set --project exits 0" 0
assert_eq "AC1.1 outside git: no stderr output at all" "" "$ERR"
assert_file "AC1.1 outside git: the conf is still written" "$N/.agents/playbook.conf"
assert_no_path "AC1.1 outside git: no .git is invented" "$N/.git"

# --global never edits excludes, even from inside a repo
R="$(mk_tmp)"; mk_repo "$R"; EX="$(excl_of "$R")"; BEFORE="$(cat "$EX" 2>/dev/null)"
ERR="$(cd "$R" && bash "$CONF" set language vi --global 2>&1 >/dev/null)"
assert_eq "AC1.1 --global prints no notice" "" "$ERR"
assert_eq "AC1.1 --global leaves the exclude file untouched" "$BEFORE" "$(cat "$EX" 2>/dev/null)"
assert_eq "AC1.1 --global adds no exclude line" "0" "$(excl_count "$EX")"

t_summary
